## GameCaseModel — the look of one game case: a CD jewel case or a DVD-style keep case from RetroXR-models
## (generic/jewel-case, generic/dvd-case; the clean files only), in imported-assets/media/{jewel,keep}_case.
##
## Ported from those packages' godot_demo scripts (JewelCase, KeepCase), which validate.gd checks against the build:
## the three mobile levels (switched by visibility range), the hinges, the tray or shell colour, the box art, and a
## seat node for every disc, the manual and a holder, which stay put across level switches.
##
## Frame (the case's own, metres): x right across the front with the spine at -x, y up, z out of the front. Every
## hinge turns about a line along y at the spine edge: `open_deg` is the jewel lid, or the keep case's spine-then-
## cover (0 shut, 90 the spine flat, 180 the cover flat too); `inner_deg` the flip trays (jewel) or the flippers
## (keep), numbered from the back. A seat's local +Y runs along its hub, out of its tray (a disc's label side).
class_name GameCaseModel
extends Node3D

const FAMILIES := ["jewel", "keep"]
const MODELS := {
	"jewel": "res://imported-assets/media/jewel_case/jewel_%s_%s.glb",
	"keep": "res://imported-assets/media/keep_case/dvd_%s_%s.glb",
}
const CONTRACTS := {
	"jewel": "res://imported-assets/media/jewel_case/jewel_contract.json",
	"keep": "res://imported-assets/media/keep_case/keep_contract.json",
}
const SUFFIXES := ["mobile", "mobile_lod1", "mobile_lod2"]
## Where LOD0 gives way to LOD1 and LOD1 to LOD2 (m), as the demo scripts' switch and far distances.
const LOD_RANGES := {"jewel": [0.7, 1.6], "keep": [0.8, 1.8]}
const LOD_MARGIN := 0.05
const CLEAR_SHADER := preload("res://Shaders/case_clear_plastic.gdshader")

# ---- jewel (jewel_params.py; JewelCase) ----
## Box-texture layout: the back panel is 792/680 of the image's height wide, the spine 36/680; the booklet is the
## image's rightmost min(front, height x 120/118) (a US scan's front is the whole case front, a JP or EU one the
## booklet alone). The long box is laid out like a Saturn scan.
const JEWEL_LAYOUT := {"back": 792.0 / 680.0, "spine": 36.0 / 680.0, "booklet_per_h": 120.0 / 118.0,
	"strip_mm": 13.3, "booklet_mm": 120.0}
const JEWEL_LAYOUTS := {
	"longbox": {"back": 440.0 / 680.0, "spine": 51.0 / 680.0, "booklet_per_h": 127.0 / 203.2, "strip_mm": 0.0,
		"booklet_mm": 127.0},
}
## A box-texture ScreenScraper stretched to 1024 x 680 (its Sega CD scans): back and spine as shares of the width,
## read off the seams of Sonic CD (USA)'s long box (430 and 621 px) [E: one scan].
const NORMALIZED_LAYOUT := Vector2(430.0 / 1024.0, 191.0 / 1024.0)
const TRAY_PRESETS := {
	"black": Color(0.035, 0.035, 0.037, 1.0), "clear": Color(0.92, 0.94, 0.95, 0.10),
	"smoke": Color(0.22, 0.23, 0.25, 0.45), "white": Color(0.86, 0.86, 0.84, 1.0),
	"red": Color(0.62, 0.05, 0.05, 1.0), "blue": Color(0.06, 0.18, 0.55, 1.0),
	"green": Color(0.08, 0.42, 0.16, 1.0), "yellow": Color(0.92, 0.72, 0.06, 1.0),
	"purple": Color(0.32, 0.12, 0.48, 1.0), "dc_blue": Color(0.12, 0.32, 0.70, 1.0),
}
const DEFAULT_TRAYS := {"dc_pal": "dc_blue"}

# ---- keep (keep_params.py; KeepCase) ----
const SHELL_PRESETS := {
	"black": Color(0.035, 0.035, 0.038, 1.0), "navy": Color(0.06, 0.09, 0.20, 1.0),
	"white": Color(0.88, 0.88, 0.86, 1.0), "blue": Color(0.05, 0.42, 0.78, 1.0),
	"green": Color(0.20, 0.55, 0.12, 1.0), "red": Color(0.70, 0.06, 0.06, 1.0),
	"silver": Color(0.62, 0.63, 0.65, 1.0), "clear": Color(0.90, 0.92, 0.93, 0.18),
	"smoke": Color(0.18, 0.19, 0.21, 0.55), "blue_black": Color(0.035, 0.040, 0.062, 1.0),
	"yellow": Color(0.93, 0.76, 0.08, 1.0), "lime": Color(0.47, 0.78, 0.16, 1.0),
	"x360_green": Color(0.36, 0.72, 0.22, 0.55), "bd_blue": Color(0.10, 0.36, 0.78, 0.55),
	"ps5_blue": Color(0.06, 0.24, 0.62, 0.6), "xbox_one_green": Color(0.10, 0.55, 0.16, 0.55),
	"wiiu_blue": Color(0.0, 0.60, 0.80, 1.0),
}
const DEFAULT_COLORS := {"gc_jp": "clear", "bluray": "bd_blue", "bluray_game": "bd_blue", "x360": "x360_green",
	"umd": "clear", "wiiu": "wiiu_blue"}
## Flippers turn like pages: each stays this far behind the one above once that one has moved (KeepCase).
const LEAF_SPREAD := 15.0
const SPINE_OPEN_MAX := 90.0
## A jewel lid laid open on a table turns a little past flat (RetroGameCase.open_max_deg).
const OPEN_LIMIT := 190.0

var family := "jewel"
var variant := "single"
var levels: Array[Node3D] = []
var open_deg := 0.0
var inner_deg: Array[float] = []
var _seats: Dictionary = {}          # name -> Node3D of ours, kept on level 0's node of that name
var _contract: Dictionary = {}

static var _contracts: Dictionary = {}


## Build the levels for `family` ("jewel" or "keep") and `variant` (a key of its contract). Call before or after
## adding to the tree; returns false when the variant has no files.
func build(case_family: String, case_variant: String) -> bool:
	family = case_family
	variant = case_variant
	_contract = variant_contract(family, variant)
	if _contract.is_empty():
		push_warning("[GameCaseModel] no %s case '%s'" % [family, variant])
		return false
	var ranges: Array = LOD_RANGES[family]
	for i in SUFFIXES.size():
		var path := str(MODELS[family]) % [variant, SUFFIXES[i]]
		var packed := load(path) as PackedScene
		if packed == null:
			push_warning("[GameCaseModel] missing %s" % path)
			return false
		var level := packed.instantiate() as Node3D
		level.name = "LOD%d" % i
		add_child(level)
		levels.append(level)
		_clear_plastic(level)
		var begin: float = 0.0 if i == 0 else float(ranges[i - 1])
		var end: float = float(ranges[i]) if i < ranges.size() else 0.0
		for mi in meshes(level):
			# The pickable's outline is drawn once, at the pose it is built in: only the body's own LOD0 meshes,
			# not the far levels or anything a hinge turns.
			if i > 0 or _under_hinge(mi, level):
				mi.add_to_group("outline_exclude")
			mi.visibility_range_begin = begin
			mi.visibility_range_begin_margin = LOD_MARGIN if i > 0 else 0.0
			mi.visibility_range_end = end
			mi.visibility_range_end_margin = LOD_MARGIN if end > 0.0 else 0.0
	if family == "jewel":
		_hide_strip()
	for n in levels[0].find_children("*Seat*", "Node3D", true, false):
		var seat := Node3D.new()
		seat.name = n.name
		add_child(seat)
		_seats[String(n.name)] = seat
	inner_deg.resize(inner_count())
	inner_deg.fill(0.0)
	if family == "jewel" and DEFAULT_TRAYS.has(variant):
		set_color(DEFAULT_TRAYS[variant])
	elif family == "keep" and DEFAULT_COLORS.has(variant):
		set_color(DEFAULT_COLORS[variant])
	_pose()
	return true


static func _under_hinge(node: Node, level: Node) -> bool:
	var n := node
	while n != null and n != level:
		var s := String(n.name)
		if s == "Lid" or s == "Spine" or s == "Cover" or s.begins_with("FlipTray") or s.begins_with("Leaf"):
			return true
		n = n.get_parent()
	return false


## The contract row of one variant (sizes, seats, pivots), or {} for none.
static func variant_contract(case_family: String, case_variant: String) -> Dictionary:
	if not _contracts.has(case_family):
		var text := FileAccess.get_file_as_string(str(CONTRACTS.get(case_family, "")))
		var parsed: Variant = JSON.parse_string(text) if not text.is_empty() else null
		_contracts[case_family] = (parsed as Dictionary).get("variants", {}) if parsed is Dictionary else {}
	return (_contracts[case_family] as Dictionary).get(case_variant, {})


## Every variant of a family.
static func variants_of(case_family: String) -> Array:
	variant_contract(case_family, "")
	return (_contracts.get(case_family, {}) as Dictionary).keys()


func contract() -> Dictionary:
	return _contract


## The closed case's size (m): across, up, through.
func size_m() -> Vector3:
	var s: Array = _contract.get("size_mm", [142.0, 125.0, 10.4])
	return Vector3(float(s[0]), float(s[1]), float(s[2])) * 0.001


## How many flip trays (jewel) or flippers (keep).
func inner_count() -> int:
	if levels.is_empty():
		return 0
	var pattern := "FlipTray*" if family == "jewel" else "Leaf*"
	return levels[0].find_children(pattern, "Node3D", true, false).size()


## A hinge's pivot in the case frame (m): "open" the lid (keep: the spine's middle, between its two creases), or
## "inner<i>" a flip tray or flipper (i from 1).
func pivot_m(which: String) -> Vector3:
	var node := "Lid" if family == "jewel" else "Spine"
	if which.begins_with("inner"):
		node = ("FlipTray%s" if family == "jewel" else "Leaf%s") % which.trim_prefix("inner")
	for p: Dictionary in _contract.get("pivots", []):
		if str(p.get("node", "")) == node:
			var mm: Array = p["pivot_mm"]
			var at := Vector3(float(mm[0]), float(mm[1]), float(mm[2])) * 0.001
			if family == "keep" and node == "Spine":
				at.z = 0.0
			return at
	return Vector3(-size_m().x * 0.5, 0.0, 0.0)


func set_angles(open: float, inner: Array) -> void:
	open_deg = clampf(open, 0.0, OPEN_LIMIT)
	for i in mini(inner.size(), inner_deg.size()):
		inner_deg[i] = clampf(float(inner[i]), 0.0, OPEN_LIMIT)
	_pose()


## The flippers as posed: the set angles, each held LEAF_SPREAD behind the one above once that one is off the back
## half, so two never pass through each other (KeepCase.effective_leaf_angles). Flip trays pose as set.
func effective_inner() -> Array[float]:
	var out: Array[float] = []
	out.resize(inner_deg.size())
	for i in range(inner_deg.size() - 1, -1, -1):
		var a := inner_deg[i]
		if family == "keep" and i < inner_deg.size() - 1:
			var above: float = out[i + 1]
			var limit := 85.0 if above > 100.0 else above - LEAF_SPREAD
			a = clampf(a, 0.0, maxf(0.0, limit))
		out[i] = a
	return out


## The node a disc goes on, index from 1, numbered from the back.
func disc_seat(index: int) -> Node3D:
	return _seats.get("DiscSeat%d" % index)


func disc_seat_count() -> int:
	return _seats.keys().filter(func(k): return String(k).begins_with("DiscSeat")).size()


## Where the manual goes: origin its centre, local +Y toward its top, +Z out of its front.
func manual_seat() -> Node3D:
	return _seats.get("ManualSeat")


## A PS2 or GameCube memory card's holder, or the UMD's (keep only; null otherwise).
func card_seat() -> Node3D:
	return _seats.get("CardSeat")


func umd_seat() -> Node3D:
	return _seats.get("UmdSeat")


## The paper manual's size in the case (m), across and up.
func manual_size_m() -> Vector2:
	var m: Array = (_contract.get("manual", {}) as Dictionary).get("size_mm", [120.0, 120.0])
	return Vector2(float(m[0]), float(m[1])) * 0.001


## The booklet the case shows (the jewel case's printed front; the keep case has none of its own).
func show_booklet(on: bool) -> void:
	for level in levels:
		var b := level.find_child("Booklet", true, false) as Node3D
		if b != null:
			b.visible = on


func _pose() -> void:
	if levels.is_empty():
		return
	var eff := effective_inner()
	for level in levels:
		if family == "jewel":
			(level.find_child("Lid", true, false) as Node3D).rotation.y = -deg_to_rad(open_deg)
			for i in eff.size():
				var f := level.find_child("FlipTray%d" % (i + 1), true, false) as Node3D
				if f != null:
					f.rotation.y = -deg_to_rad(eff[i])
		else:
			(level.find_child("Spine", true, false) as Node3D).rotation.y = -deg_to_rad(minf(open_deg, SPINE_OPEN_MAX))
			(level.find_child("Cover", true, false) as Node3D).rotation.y = -deg_to_rad(maxf(0.0, open_deg - SPINE_OPEN_MAX))
			for i in eff.size():
				var f := level.find_child("Leaf%d" % (i + 1), true, false) as Node3D
				if f != null:
					f.rotation.y = -deg_to_rad(eff[i])
	for key: String in _seats:
		var src := levels[0].find_child(key, true, false) as Node3D
		(_seats[key] as Node3D).transform = levels[0].transform * _local_to(levels[0], src)


## A node's transform relative to an ancestor (valid outside the tree too).
static func _local_to(ancestor: Node3D, node: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n := node
	while n != ancestor and n != null:
		t = n.transform * t
		n = n.get_parent() as Node3D
	return t


static func meshes(root: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	for n in root.find_children("*", "MeshInstance3D", true, false):
		found.append(n as MeshInstance3D)
	return found


# ------------------------------------------------------------------ materials
func _each_surface(mat_name: String, fn: Callable) -> int:
	var n := 0
	for level in levels:
		for mi in meshes(level):
			for s in mi.mesh.get_surface_count():
				var base := mi.mesh.surface_get_material(s)
				if base != null and String(base.resource_name) == mat_name:
					fn.call(mi, s, base)
					n += 1
	return n


## Clear polystyrene (the jewel lid and base) and the keep case's sleeve: premultiplied alpha keeps reflections whole
## where plain alpha blending dims them with the opacity.
func _clear_plastic(level: Node3D) -> void:
	var clear_name := "Jewel_Clear" if family == "jewel" else "Keep_Sleeve"
	for mi in meshes(level):
		for s in mi.mesh.get_surface_count():
			var base := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if base == null or String(base.resource_name) != clear_name:
				continue
			var m := ShaderMaterial.new()
			m.shader = CLEAR_SHADER
			m.resource_name = clear_name
			m.set_shader_parameter("tint", Color(base.albedo_color, base.albedo_color.a))
			m.set_shader_parameter("roughness", base.roughness)
			mi.set_surface_override_material(s, m)


## The tray (jewel) or the whole shell (keep): a preset name or a Color (sRGB); alpha below 1 is clear or smoked.
func set_color(color: Variant) -> void:
	var presets: Dictionary = TRAY_PRESETS if family == "jewel" else SHELL_PRESETS
	if color is String and not presets.has(color):
		return
	var c: Color = presets[color] if color is String else color
	_each_surface("Jewel_Tray" if family == "jewel" else "Keep_Shell",
		func(mi: MeshInstance3D, s: int, base: Material) -> void:
			var m := (base as StandardMaterial3D).duplicate() as StandardMaterial3D
			m.resource_local_to_scene = true
			m.albedo_color = c
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if c.a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
			mi.set_surface_override_material(s, m))


## A ScreenScraper "box-texture" (back | spine | front, full height) on the case's paper. Jewel: the back inlay
## with its spines, the booklet, and on a US scan the strip over the tray's band. Keep: the cover sheet under the
## sleeve, the whole image across back, spine and front.
func apply_box_texture(texture: Texture2D) -> Error:
	if texture == null:
		return ERR_INVALID_PARAMETER
	if family == "keep":
		var n := _art("Keep_Art", texture, Vector3.ONE, Vector3.ZERO)
		return OK if n == 3 * levels.size() else ERR_DOES_NOT_EXIST
	var w := float(texture.get_width())
	var h := float(texture.get_height())
	var lay := jewel_layout(variant)
	var b := h * float(lay["back"]) / w
	var s := h * float(lay["spine"]) / w
	var book := booklet_fraction(variant, w, h)
	if GameCase.is_normalized_scan(Vector2i(int(w), int(h))):
		# Stretched to 1024 x 680: its panels are shares of the width, not of the height (NORMALIZED_LAYOUT).
		b = NORMALIZED_LAYOUT.x
		s = NORMALIZED_LAYOUT.y
		book = 1.0 - b - s
	if b + s >= 1.0:
		return ERR_INVALID_DATA          # not a box texture: too narrow for back and spine
	var n := _art("Jewel_Inlay", texture, Vector3(b, 1, 1), Vector3.ZERO)
	n += _art("Jewel_Booklet", texture, Vector3(book, 1, 1), Vector3(1.0 - book, 0, 0))
	# A US scan's front is the whole case front: what lies left of the booklet goes on the strip over the band.
	var band := w - h * (float(lay["back"]) + float(lay["spine"])) - book * w
	var strip := minf(band, float(lay["strip_mm"]) * book * w / float(lay["booklet_mm"])) / w
	if strip * w >= 2.0:
		_art("Jewel_Strip", texture, Vector3(strip, 1, 1), Vector3(1.0 - book - strip, 0, 0))
	else:
		_hide_strip()
	return OK if n >= levels.size() else ERR_DOES_NOT_EXIST


## A front cover alone (ScreenScraper "box-2D") on the jewel booklet or the keep case's front panel.
func apply_front_texture(texture: Texture2D) -> Error:
	if texture == null:
		return ERR_INVALID_PARAMETER
	if family == "jewel":
		_hide_strip()
		return OK if _art("Jewel_Booklet", texture, Vector3.ONE, Vector3.ZERO) > 0 else ERR_DOES_NOT_EXIST
	return ERR_UNAVAILABLE


static func jewel_layout(case_variant: String) -> Dictionary:
	return JEWEL_LAYOUTS.get(case_variant, JEWEL_LAYOUT)


## The share of a box texture's width the jewel booklet takes, from its right edge.
static func booklet_fraction(case_variant: String, w: float, h: float) -> float:
	var lay := jewel_layout(case_variant)
	var front := w - h * (float(lay["back"]) + float(lay["spine"]))
	return minf(front, h * float(lay["booklet_per_h"])) / w


func _hide_strip() -> void:
	_each_surface("Jewel_Strip", func(mi: MeshInstance3D, s: int, _base: Material) -> void:
		mi.set_surface_override_material(s, null)
		mi.visible = false)


func _art(mat_name: String, texture: Texture2D, scale: Vector3, offset: Vector3) -> int:
	return _each_surface(mat_name, func(mi: MeshInstance3D, s: int, base: Material) -> void:
		var m := (base as StandardMaterial3D).duplicate() as StandardMaterial3D
		m.resource_local_to_scene = true
		m.albedo_color = Color.WHITE
		m.albedo_texture = texture
		m.uv1_scale = scale
		m.uv1_offset = offset
		m.texture_repeat = false
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		m.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		mi.set_surface_override_material(s, m)
		mi.visible = true)
