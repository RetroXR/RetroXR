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
## A clear disc tray's look (_clear_plastic): the haze on its flats, and its walls seen edge-on.
const CLEAR_TRAY_NODES := ["Tray", "LidTray"]
const CLEAR_TRAY_TINT := Color(0.78, 0.83, 0.9, 0.15)
const CLEAR_TRAY_RIM := 0.9
const CLEAR_TRAY_RIM_COLOR := Color(0.3, 0.33, 0.4)
const CLEAR_TRAY_RIM_POWER := 1.4
## A tinted see-through plastic's walls edge-on: this much more opaque than its flats, this much darker.
const TINTED_RIM_OVER := 0.3
const TINTED_FLAT_GAIN := 1.3
const TINTED_RIM_DARKER := 0.45

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
## the long box's back | spine | front (440 | 51 | 440) stretched across it. Sonic CD (USA): back 0..484 px (the
## "Welcome to the next level" mark and the screenshots' frames are the back's), spine 484..540 (the turned logos),
## front from 540 with its blue SEGA CD band. Not 430 and 621: that took the front's band for spine and put the back's
## right edge on the spine flaps (a player's report, 2026-11-21) [E: one scan].
const NORMALIZED_LAYOUT := Vector2(440.0 / 931.0, 51.0 / 931.0)
## Reading a scan's own panel edges (fit_jewel_scan): two columns differ by this much of full scale; a panel's edge
## runs this share of the height, and there is none under this share; the widest spine strip looked for, per height
## (12.5 mm of a 118 mm inlay: a case's thickness and a little).
const SCAN_EDGE_JUMP := 24.0 / 255.0
const SCAN_EDGE_TALL := 0.75
const SCAN_EDGE_NONE := 0.5
const SCAN_SPINE_MAX := 72.0 / 680.0
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
const DEFAULT_COLORS := {"gc_jp": "clear", "gc_jp_double": "clear", "bluray": "bd_blue", "bluray_game": "bd_blue", "x360": "x360_green",
	"umd": "clear", "wiiu": "wiiu_blue"}
## Flippers turn like pages: each stays this far behind the one above once that one has moved (KeepCase).
const LEAF_SPREAD := 15.0
## A flipper under another never stands past this: the one above lies over on the cover by then.
const LEAF_STAND := 85.0
const SPINE_OPEN_MAX := 90.0
## A jewel lid laid open on a table turns a little past flat (RetroGameCase.open_max_deg).
const OPEN_LIMIT := 190.0

var family := "jewel"
var variant := "single"
var levels: Array[Node3D] = []
var _lid_chain: Array[Node3D] = []               # the lid's node and its parents up to this model (lid_transform_at)
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
	var paths := model_paths(family, variant)
	for i in paths.size():
		var path := paths[i]
		# Held already when the spawn menu made this case (ModelWarmer.acquire, off the main thread); a case a save
		# puts back loads them here, and they are kept for the next.
		var packed := load(path) as PackedScene
		if packed == null:
			push_warning("[GameCaseModel] missing %s" % path)
			return false
		ModelWarmer.hold(path, packed)
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


## Every inner panel's own two faces, baked: "<family>/<variant>" -> {node: [lo, hi, from_x]} (m). Its mesh read
## back off the graphics card (surface_get_arrays) stalls the renderer once per buffer: 17 ms of a 20 ms case build
## on a desktop, far more on a headset, each time a multi-disc case spawned (the owner, 2026-11-23: "the game
## freezes for a while"). Written by DevTools/cases/bake_panel_slabs; game_case_tests holds it to the models.
const PANEL_SLABS := "res://imported-assets/media/case_panel_slabs.json"
static var _slabs: Dictionary = {}
static var _slabs_read := false


## The baked faces of one panel for the half from `from_x` out: (lo, hi), or (INF, -INF) when the table has no
## row for it or its row was baked for another `from_x`.
static func baked_slab(case_family: String, case_variant: String, node_name: String, from_x: float) -> Vector2:
	if not _slabs_read:
		_slabs_read = true
		var text := FileAccess.get_file_as_string(PANEL_SLABS) if FileAccess.file_exists(PANEL_SLABS) else ""
		var parsed: Variant = JSON.parse_string(text) if not text.is_empty() else null
		if parsed is Dictionary:
			_slabs = parsed
	var row: Variant = (_slabs.get("%s/%s" % [case_family, case_variant], {}) as Dictionary).get(node_name)
	if row is Array and (row as Array).size() >= 3 and absf(float((row as Array)[2]) - from_x) < 0.00005:
		return Vector2(float((row as Array)[0]), float((row as Array)[1]))
	return Vector2(INF, -INF)


## A variant's model files, near to far. A plain load() of them froze a headset while a case spawned (the owner,
## 2026-11-23): whatever spawns a case in play awaits ModelWarmer.acquire() on each first.
static func model_paths(case_family: String, case_variant: String) -> PackedStringArray:
	var out := PackedStringArray()
	if MODELS.has(case_family):
		for suffix: String in SUFFIXES:
			out.append(str(MODELS[case_family]) % [case_variant, suffix])
	return out


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
			# CaseHingeSim's page rule (_cap): the case's sim holds its angles to it already, so this only
			# clamps angles set here by hand.
			var above: float = out[i + 1]
			var limit := minf(above - LEAF_SPREAD if above >= 2.0 * LEAF_SPREAD else above * 0.5, LEAF_STAND)
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


## The jewel booklet's back page (seen inside the open lid): a seated manual's own material for its last page, or
## null for the plain paper the model ships.
func set_booklet_back(mat: Material) -> void:
	_each_surface("Jewel_BookletBack", func(mi: MeshInstance3D, s: int, _base: Material) -> void:
		mi.set_surface_override_material(s, mat))


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


## The lid (a keep case's cover) in this model's own frame with the case open `open` degrees: what _pose gives
## it, worked out without posing anything, so a caller can ask where the lid WOULD be (a keep case's cover turns
## on its spine's two creases, the spine first).
func lid_transform_at(open: float) -> Transform3D:
	if levels.is_empty():
		return Transform3D.IDENTITY
	if _lid_chain.is_empty():
		var n := levels[0].find_child("Lid" if family == "jewel" else "Cover", true, false) as Node3D
		while n != null and n != self:
			_lid_chain.append(n)
			n = n.get_parent() as Node3D
	var deg := clampf(open, 0.0, OPEN_LIMIT)
	var t := Transform3D.IDENTITY
	for n: Node3D in _lid_chain:
		var own := n.transform
		var turn := NAN
		match String(n.name):
			"Lid":
				turn = -deg_to_rad(deg)
			"Spine":
				turn = -deg_to_rad(minf(deg, SPINE_OPEN_MAX))
			"Cover":
				turn = -deg_to_rad(maxf(0.0, deg - SPINE_OPEN_MAX))
		if not is_nan(turn):
			own.basis = Basis.from_euler(Vector3(n.rotation.x, turn, n.rotation.z)) * Basis.from_scale(n.scale)
		t = own * t
	return t


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


## See-through plastic molded into a shape (a clear or tinted disc tray, a keep case's shell with its hub): a haze
## of its own color on its flats and its walls seen edge-on, so a hub, a ring and a rim read as lines. Drawn as a
## flat sheet at one opacity, a clear part was not there at all (a disc lay on bare paper) and a tinted one was a
## flat wash (the owner, 2026-11-22). `c`: the plastic's color, its alpha how much the flats hide.
static func molded_plastic(c: Color, roughness := 0.06) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = CLEAR_SHADER
	var colorless := c.s < 0.15 and c.v > 0.6
	if colorless:                                        # clear: a cool haze, gray lines
		m.set_shader_parameter("tint", Color(CLEAR_TRAY_TINT, maxf(c.a, CLEAR_TRAY_TINT.a)))
		m.set_shader_parameter("rim", CLEAR_TRAY_RIM)
		m.set_shader_parameter("rim_color", CLEAR_TRAY_RIM_COLOR)
	else:                                                # tinted or smoked: its own color, deeper edge-on
		# (Denser on its flats than the preset says: the plain material it replaces cast a whole shadow on what lay
		# under it, which was half of how deep its color looked; this one casts none.)
		var flat := clampf(c.a * TINTED_FLAT_GAIN, 0.0, 0.88)
		m.set_shader_parameter("tint", Color(c.r, c.g, c.b, flat))
		m.set_shader_parameter("rim", clampf(flat + TINTED_RIM_OVER, 0.0, 0.97))
		m.set_shader_parameter("rim_color", Color(c.r, c.g, c.b).darkened(TINTED_RIM_DARKER))
	m.set_shader_parameter("rim_power", CLEAR_TRAY_RIM_POWER)
	# Clear polystyrene is glossy; a tinted or smoked shell keeps the finish it had (glossier, its color washed out
	# under a bright sky).
	m.set_shader_parameter("roughness", minf(roughness, 0.12) if colorless else roughness)
	return m


## Clear polystyrene (the jewel lid and base) and the keep case's sleeve: premultiplied alpha keeps reflections whole
## where plain alpha blending dims them with the opacity.
func _clear_plastic(level: Node3D) -> void:
	# The jewel lid's booklet tabs are the same plastic, drawn more opaque (Jewel_Tab: they read as a lip over the paper).
	var clear_names := ["Jewel_Clear", "Jewel_Tab"] if family == "jewel" else ["Keep_Sleeve"]
	for mi in meshes(level):
		for s in mi.mesh.get_surface_count():
			var base := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if base == null or not String(base.resource_name) in clear_names:
				continue
			var clear_name := String(base.resource_name)
			var m := ShaderMaterial.new()
			m.shader = CLEAR_SHADER
			m.resource_name = clear_name
			m.set_shader_parameter("tint", Color(base.albedo_color, base.albedo_color.a))
			m.set_shader_parameter("roughness", base.roughness)
			# A clear disc tray (the North American fat case's two) is a molded part, not a flat sheet: drawn as the
			# lid is, at 5 percent, it was not there at all, and a disc lay on bare paper (the owner, 2026-11-22).
			# A light haze on its flats, and its walls seen edge-on: the hub, the ring, the rim.
			if String(mi.name) in CLEAR_TRAY_NODES:
				m = molded_plastic(Color(base.albedo_color, base.albedo_color.a), base.roughness)
				m.resource_name = clear_name
			mi.set_surface_override_material(s, m)


## The tray (jewel) or the whole shell (keep): a preset name or a Color (sRGB); alpha below 1 is clear or smoked.
func set_color(color: Variant) -> void:
	var presets: Dictionary = TRAY_PRESETS if family == "jewel" else SHELL_PRESETS
	if color is String and not presets.has(color):
		return
	var c: Color = presets[color] if color is String else color
	_each_surface("Jewel_Tray" if family == "jewel" else "Keep_Shell",
		func(mi: MeshInstance3D, s: int, base: Material) -> void:
			# A see-through tray or shell (clear, smoke, the PS3 blue, the Xbox 360 green) is molded plastic.
			if c.a < 1.0:
				mi.set_surface_override_material(s, molded_plastic(c, (base as StandardMaterial3D).roughness))
				return
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
	# A slim case has no ribbed band to print a US scan's strip over: its base is one flat deck.
	if strip * w >= 2.0 and variant != "slim":
		_art("Jewel_Strip", texture, Vector3(strip, 1, 1), Vector3(1.0 - book - strip, 0, 0))
	else:
		_hide_strip()
	return OK if n >= levels.size() else ERR_DOES_NOT_EXIST


## A jewel case's three panels (ScreenScraper's box-2D-back, box-2D-side and box-2D, each its own picture) joined
## into the one image apply_box_texture takes: the back at the layout's width, the side at its spine's, the front
## after them. Each panel fills its own part whatever shape its scan had, which is the point: one wrap split by the
## layout is right only for a wrap that keeps it (fit_jewel_scan), and they do not all (PlayStation: back and
## spine 792 and 36 px of 680, or 765 and 65; a long box's 476 and 67 of 1024, where the layout says 484 and 56).
## A front wider than the booklet is a US scan's whole lid, the tray band's strip at its left: kept at its own
## shape. A layout with no strip (the long box) takes the whole front on its booklet. A keep case's sheet is its
## own contract's (the back, its spine, the front: a five-disc case's spine is 22 mm of 281, a GameCube's 17 of
## 220, where one wrap stretched over the sheet gives every case the scan's). Null when a panel is missing. Any
## thread.
static func join_panels(back: Image, side: Image, front: Image, case_variant := "", case_family := "jewel") -> Image:
	for part: Image in [back, side, front]:
		if part == null or part.is_empty():
			return null
	var h := back.get_height()
	var widths := panel_widths(h, front.get_size(), case_variant, case_family)
	var back_w := widths.x
	var spine_w := widths.y
	var front_w := widths.z
	var out := Image.create_empty(back_w + spine_w + front_w, h, false, Image.FORMAT_RGBA8)
	var x := 0
	for row: Array in [[back, back_w], [side, spine_w], [front, front_w]]:
		var part := (row[0] as Image).duplicate() as Image
		if part.is_compressed() and part.decompress() != OK:
			return null
		if part.has_mipmaps():
			part.clear_mipmaps()
		part.convert(Image.FORMAT_RGBA8)
		var w := int(row[1])
		if part.get_width() != w or part.get_height() != h:
			part.resize(w, h, Image.INTERPOLATE_LANCZOS)
		out.blit_rect(part, Rect2i(0, 0, w, h), Vector2i(x, 0))
		x += w
	return out


## How wide join_panels makes the back, the spine and the front (px) of a sheet `h` tall, for a front picture of
## `front_px`. Any thread.
static func panel_widths(h: int, front_px: Vector2i, case_variant := "", case_family := "jewel") -> Vector3i:
	var lay := jewel_layout(case_variant)
	var back_w := int(round(h * float(lay["back"])))
	var spine_w := maxi(1, int(round(h * float(lay["spine"]))))
	var front_w := maxi(1, int(round(float(front_px.x) * h / float(maxi(front_px.y, 1)))))
	if float(lay["strip_mm"]) <= 0.0:
		front_w = int(round(h * float(lay["booklet_per_h"])))
	if case_family == "keep":
		var art: Dictionary = variant_contract("keep", case_variant).get("art", {})
		var sheet: Array = art.get("sheet_mm", [273.0, 183.0])
		var total := maxi(3, int(round(h * float(sheet[0]) / float(sheet[1]))))
		back_w = int(round(total * float(art.get("back_mm", 129.5)) / float(sheet[0])))
		spine_w = maxi(1, int(round(total * float(art.get("spine_mm", 14.0)) / float(sheet[0]))))
		front_w = maxi(1, total - back_w - spine_w)
	return Vector3i(back_w, spine_w, front_w)


## A jewel box-texture whose spine strip is not where the layout has it, put right in place. Most scans keep the
## layout (Crash Bandicoot 2 and 3, Spyro x Sparx, Japan: the back to 792, the spine to 829 of 1509 x 680); some
## carry a wider strip, the back squeezed to make room (Spyro the Dragon (Japan): back 0..764, strip 764..830), and
## laid out by the numbers the strip's left 28 px landed on the back panel, its title off the spine (a player's
## report, 2026-11-22). The back is drawn out to the layout's width and the strip in to the spine's. Returns whether
## the image changed. Before its mipmaps; any thread.
static func fit_jewel_scan(img: Image) -> bool:
	var at := jewel_spine_start(img)
	if at < 0:
		return false
	var h := img.get_height()
	var back := int(round(h * float(JEWEL_LAYOUT["back"])))
	var edge := int(round(h * (float(JEWEL_LAYOUT["back"]) + float(JEWEL_LAYOUT["spine"]))))
	var right := _scan_edge_near(img, edge)
	if img.has_mipmaps():
		img.clear_mipmaps()
	var panel := img.get_region(Rect2i(0, 0, at, h))
	panel.resize(back, h, Image.INTERPOLATE_CUBIC)
	var strip := img.get_region(Rect2i(at, 0, right - at, h))
	strip.resize(edge - back, h, Image.INTERPOLATE_LANCZOS)
	img.blit_rect(panel, Rect2i(0, 0, back, h), Vector2i.ZERO)
	img.blit_rect(strip, Rect2i(0, 0, edge - back, h), Vector2i(back, 0))
	return true


## Where a jewel box-texture's spine strip begins (px from the left) when that is NOT where the layout has it; -1
## for a scan that keeps the layout, one with no edge to go by, and anything that is not a jewel case's scan (a
## keep case's sheet, a long box, a front alone). The strip is known by its own edge: a jump most of the image's
## height tall within a case's thickness of the front, and none where the layout expects the back to end.
static func jewel_spine_start(img: Image) -> int:
	if img == null or img.is_empty() or img.is_compressed():
		return -1
	var w := img.get_width()
	var h := img.get_height()
	var back := int(round(h * float(JEWEL_LAYOUT["back"])))
	var edge := int(round(h * (float(JEWEL_LAYOUT["back"]) + float(JEWEL_LAYOUT["spine"]))))
	if GameCase.is_normalized_scan(Vector2i(w, h)) or w < edge + int(h * 0.9):
		return -1
	var slack := maxi(2, int(round(h * 3.0 / 680.0)))
	for x in range(back - slack, back + slack + 1):
		if _scan_edge(img, x) >= SCAN_EDGE_NONE:
			return -1                                    # the back ends where the layout says
	var found := -1
	var strongest := SCAN_EDGE_TALL
	for x in range(_scan_edge_near(img, edge) - int(round(h * SCAN_SPINE_MAX)), back - slack):
		var share := _scan_edge(img, x)
		if share >= strongest:
			strongest = share
			found = x
	return found


## The panel edge within a few px of `x` (the scans' fronts start a pixel or two off the layout's), or `x`.
static func _scan_edge_near(img: Image, x: int) -> int:
	var slack := maxi(2, int(round(img.get_height() * 4.0 / 680.0)))
	var out := x
	var strongest := SCAN_EDGE_TALL
	for c in range(x - slack, x + slack + 1):
		var share := _scan_edge(img, c)
		if share >= strongest:
			strongest = share
			out = c
	return out


## The share of the image's height (every few rows) over which column x differs from the one left of it.
static func _scan_edge(img: Image, x: int) -> float:
	if x < 1 or x >= img.get_width():
		return 0.0
	var h := img.get_height()
	var rows := 0
	var jumps := 0
	for y in range(0, h, maxi(1, h / 170)):
		var a := img.get_pixel(x - 1, y)
		var b := img.get_pixel(x, y)
		rows += 1
		if maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) > SCAN_EDGE_JUMP:
			jumps += 1
	return float(jumps) / float(maxi(rows, 1))


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
	var kind := "%s/%s" % [family, mat_name]
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
		mi.visible = true
		if not _kept_paper.has(kind):
			var blank := m.duplicate() as StandardMaterial3D
			blank.albedo_texture = _blank_sheet()
			blank.get_rid()                              # its shader made (and counted as used) now
			_kept_paper[kind] = blank)


## One blank sheet of each kind of printed paper, kept for the session. A StandardMaterial3D's shader is made for
## its settings and dropped with the last material that has them: the only case in a room took its paper's with
## it, and the next case made it again in its spawn frame (24 ms on a desktop, every spawn).
static var _kept_paper: Dictionary = {}
static var _blank: ImageTexture = null


static func _blank_sheet() -> ImageTexture:
	if _blank == null:
		_blank = ImageTexture.create_from_image(Image.create_empty(2, 2, false, Image.FORMAT_RGBA8))
	return _blank
