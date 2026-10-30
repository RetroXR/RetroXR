## CompactCassette — the audio cassette's own Compact Cassette (RetroXR-models generic/audio-cassette), worn by the
## game's AudioCassette in place of its stand-in box unless a mod dresses the cassette (AudioCassette._dress_shell).
##
## Three levels shown by distance. The tape is live: the packs are blend shapes, and how much tape is on each hub
## follows the cassette's own place (AudioCassette.tape_progress, written by the deck it is in and saved with it),
## so the packs cross the window and the hubs turn as a deck plays it, and both stay where it was stopped. The deck
## reads the hubs back (CassettePlayer turns its spindles to HubSupply / HubTakeup), so they are what it shows.
##
## Ported from the model's own Godot script (godot_demo/audio_cassette.gd): meters; side A looks along +Z, the head
## edge (the openings) is -Y, the supply hub at -X seen from side A. The stand-in box is the same way round, so it
## goes on with no turn. The tape is taken to be a C60's whatever the album: the deck says how far through, not how
## long, and a C60's gauge winds the packs at a believable rate.
class_name CompactCassette
extends Node3D

const MODELS := ["res://imported-assets/appliances/audio_cassette/cassette_mobile.glb",
	"res://imported-assets/appliances/audio_cassette/cassette_mobile_lod1.glb",
	"res://imported-assets/appliances/audio_cassette/cassette_mobile_lod2.glb"]
const CLEAR_SHADER := preload("res://Shaders/cassette_clear_plastic.gdshader")

## Camera distances where LOD0 hands over to LOD1, and LOD1 to LOD2, and the hysteresis either side.
const SWITCH_DISTANCE := 0.7
const FAR_DISTANCE := 1.6
const HYSTERESIS := 0.1

# The tape's geometry in millimeters (tape_contract.json beside the models has the same numbers).
const HUB_SUPPLY := Vector2(-21.25, 2.9)
const HUB_TAKEUP := Vector2(21.25, 2.9)
const HUB_RADIUS := 10.85
const PACK_MAX_RADIUS := 26.2
const TAPE_WIDTH := 3.81
const TAPE_SPEED := 47.6          # mm/s
const LENGTH_FACTOR := 1.035      # the tape runs a little past its nominal time
const ROLLER_SUPPLY := Vector2(-39.8, -25.7)
const ROLLER_TAKEUP := Vector2(39.8, -25.7)
const ROLLER_RADIUS := 3.4
const SPAN_UNIT := 10.0
## Standard tape gauges in mm, thickest first.
const GAUGES := [0.018, 0.0125, 0.009]
const TAPE_MINUTES := 60.0

## How long the reels take to catch up with the tape's place (s): a deck writes it in steps, and a hub that jumped
## with each would tick round like a clock.
const EASE := 0.25
## The slowest the reels close on the tape's place (fraction of the tape a second): a play-speed album moves far slower.
const MIN_RATE := 0.02

## Where the album's name is written: the middle of side A's label strip above the hubs, a seventh of a millimeter
## off the paper, letters 4.5 mm tall and wrapped inside the 78 mm between the label's cut corners.
const TITLE_AT := Vector3(0.0, 0.018875, 0.0044)
const TITLE_WIDTH := 0.078
const TITLE_FONT_SIZE := 30
const TITLE_PIXEL := 0.00015

var levels: Array[Node3D] = []
## Where the reels are drawn, 0 (all the tape on the supply hub) .. 1; eases toward the tape's own place.
var progress := 0.0
var _tape: AudioCassette = null


func _ready() -> void:
	for i in MODELS.size():
		var level := (load(MODELS[i]) as PackedScene).instantiate() as Node3D
		level.name = "LOD%d" % i
		add_child(level)
		levels.append(level)
		for n in ["PackSupply", "PackTakeup"]:
			var pack := level.find_child(n, true, false) as MeshInstance3D
			# The mesh's own bounds are the exported pose's: give culling the largest pack.
			var r := PACK_MAX_RADIUS * 0.001
			pack.custom_aabb = AABB(Vector3(-r, -r, -TAPE_WIDTH * 0.0005), Vector3(2.0 * r, 2.0 * r, TAPE_WIDTH * 0.001))
		_clear_plastic(level)
	_ranges()
	_tape = get_parent() as AudioCassette
	if _tape != null:
		progress = _tape.tape_progress
	_apply_tape()


func _process(delta: float) -> void:
	if _tape == null:
		return
	var target := clampf(_tape.tape_progress, 0.0, 1.0)
	if is_equal_approx(progress, target):
		return
	# Eased, with a floor on the speed so it arrives and the hubs stop, rather than creeping for seconds.
	var step := maxf(absf(target - progress) * minf(1.0, delta / EASE), delta * MIN_RATE)
	progress = move_toward(progress, target, step)
	_apply_tape()


# ── the tape ─────────────────────────────────────────────────────────────────

func tape_length() -> float:
	return TAPE_MINUTES * 0.5 * 60.0 * TAPE_SPEED * LENGTH_FACTOR


## The thickest standard gauge whose full pack fits the shell.
func tape_thickness() -> float:
	var length := tape_length()
	for g: float in GAUGES:
		if pack_radius(g, length) <= PACK_MAX_RADIUS + 1e-9:
			return g
	return PI * (PACK_MAX_RADIUS * PACK_MAX_RADIUS - HUB_RADIUS * HUB_RADIUS) / maxf(length, 1.0)


static func pack_radius(thickness: float, length: float) -> float:
	return sqrt(HUB_RADIUS * HUB_RADIUS + maxf(length, 0.0) * thickness / PI)


static func pack_turns(thickness: float, length: float) -> float:
	return (pack_radius(thickness, length) - HUB_RADIUS) / thickness


## Both hubs now: supply_r, takeup_r (mm), supply_turns, takeup_turns.
func tape_state() -> Dictionary:
	var length := tape_length()
	var t := tape_thickness()
	var on_takeup := length * progress
	var on_supply := length - on_takeup
	return {
		"supply_r": pack_radius(t, on_supply), "takeup_r": pack_radius(t, on_takeup),
		"supply_turns": pack_turns(t, length) - pack_turns(t, on_supply), "takeup_turns": pack_turns(t, on_takeup),
	}


## The straight run between two circles on the same side of both: [point on 1, point on 2].
static func tangent(c1: Vector2, r1: float, c2: Vector2, r2: float, side: float) -> Array[Vector2]:
	var d := c2 - c1
	var e := d / d.length()
	var left := Vector2(-e.y, e.x)
	var k := (r1 - r2) / d.length()
	var s := sqrt(maxf(1.0 - k * k, 0.0)) * signf(side)
	var n := e * k + left * s
	return [c1 + n * r1, c2 + n * r2]


static func tape_run(supply: bool, pack_r: float) -> Array[Vector2]:
	if supply:
		return tangent(ROLLER_SUPPLY, ROLLER_RADIUS, HUB_SUPPLY, pack_r, 1.0)
	return tangent(ROLLER_TAKEUP, ROLLER_RADIUS, HUB_TAKEUP, pack_r, -1.0)


func _apply_tape() -> void:
	var st := tape_state()
	for level in levels:
		for supply: bool in [true, false]:
			var side := "Supply" if supply else "Takeup"
			var r: float = st["supply_r"] if supply else st["takeup_r"]
			var turns: float = st["supply_turns"] if supply else st["takeup_turns"]
			var hub := level.find_child("Hub" + side, true, false) as Node3D
			if hub:
				hub.rotation = Vector3(0, 0, fposmod(turns, 1.0) * TAU)       # counter-clockwise seen from +Z
			var pack := level.find_child("Pack" + side, true, false) as MeshInstance3D
			if pack:
				set_pack_radius(pack, r)
			var span := level.find_child("TapeSpan" + side, true, false) as Node3D
			if span:
				var run := tape_run(supply, r)
				span.position = Vector3(run[0].x, run[0].y, 0.0) * 0.001
				span.rotation = Vector3(0, 0, (run[1] - run[0]).angle())
				span.scale = Vector3((run[1] - run[0]).length() / SPAN_UNIT, 1, 1)


static func set_pack_radius(pack: MeshInstance3D, r: float) -> void:
	var extras: Dictionary = pack.get_meta("extras", {})
	var supply := String(pack.name).ends_with("Supply")
	var basis: float = extras.get("basis_radius_mm", 25.02 if supply else HUB_RADIUS + 0.3)
	var target: float = extras.get("target_radius_mm", HUB_RADIUS if supply else PACK_MAX_RADIUS)
	pack.set_blend_shape_value(0, (r - basis) / (target - basis))
	pack.visible = r > HUB_RADIUS + 0.05


# ── levels, plastic, labels ──────────────────────────────────────────────────

func _meshes(root: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	for n in root.find_children("*", "MeshInstance3D", true, false):
		found.append(n as MeshInstance3D)
	return found


func _ranges() -> void:
	var starts := [0.0, SWITCH_DISTANCE, FAR_DISTANCE]
	for i in levels.size():
		var begin: float = starts[i]
		var end: float = starts[i + 1] if i + 1 < levels.size() else 0.0
		for mi in _meshes(levels[i]):
			mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			mi.visibility_range_begin = begin
			mi.visibility_range_begin_margin = HYSTERESIS if begin > 0.0 else 0.0
			mi.visibility_range_end = end
			mi.visibility_range_end_margin = HYSTERESIS if end > 0.0 else 0.0
			if i > 0:
				mi.add_to_group("outline_exclude")       # one outline: LOD0's


## The windows are clear plastic: premultiplied alpha keeps their reflections at full strength.
func _clear_plastic(level: Node3D) -> void:
	for mi in _meshes(level):
		for s in mi.mesh.get_surface_count():
			var base := mi.mesh.surface_get_material(s) as StandardMaterial3D
			if base == null or String(base.resource_name) != "Cassette_Window":
				continue
			var m := ShaderMaterial.new()
			m.shader = CLEAR_SHADER
			m.resource_name = "Cassette_Window"
			m.set_shader_parameter("tint", Color(base.albedo_color, base.albedo_color.a))
			m.set_shader_parameter("roughness", base.roughness)
			mi.set_surface_override_material(s, m)


## One label ("LabelA" or "LabelB") on every level: the picture when there is one, fitted inside the label and not
## stretched (on paper of `paper`'s colour, as the stand-in's quads fitted it), else plain paper of that colour.
func set_label(label: String, texture: Texture2D, paper: Color) -> void:
	var fitted: Texture2D = null
	for level in levels:
		var mi := level.find_child(label, true, false) as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var base := mi.mesh.surface_get_material(0) as StandardMaterial3D
		if base == null:
			continue
		if texture != null and fitted == null:
			fitted = fit_on_paper(texture, Vector2(mi.mesh.get_aabb().size.x, mi.mesh.get_aabb().size.y), paper)
		var m := base.duplicate() as StandardMaterial3D
		m.albedo_color = Color.WHITE if fitted != null else paper
		m.albedo_texture = fitted if fitted != null else base.albedo_texture
		m.texture_repeat = false
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		mi.set_surface_override_material(0, m)


## `texture` letterboxed onto paper of the label's proportions (`size`, its width and height), at the middle.
static func fit_on_paper(texture: Texture2D, size: Vector2, paper: Color) -> Texture2D:
	var src := texture.get_image()
	if src == null or size.x <= 0.0 or size.y <= 0.0:
		return texture
	if src.is_compressed():
		src.decompress()
	src.convert(Image.FORMAT_RGBA8)
	const WIDTH := 512
	var h := maxi(1, roundi(WIDTH * size.y / size.x))
	var canvas := Image.create(WIDTH, h, false, Image.FORMAT_RGBA8)
	canvas.fill(paper)
	var scale := minf(float(WIDTH) / src.get_width(), float(h) / src.get_height())
	var w2 := maxi(1, roundi(src.get_width() * scale))
	var h2 := maxi(1, roundi(src.get_height() * scale))
	src.resize(w2, h2, Image.INTERPOLATE_LANCZOS)
	canvas.blend_rect(src, Rect2i(0, 0, w2, h2), Vector2i((WIDTH - w2) / 2, (h - h2) / 2))
	canvas.generate_mipmaps()
	return ImageTexture.create_from_image(canvas)


## Put the cassette's name label on side A's paper. Its text stays the game's (the album's name, or a download's
## progress); only where and how large it is drawn changes, and a long name wraps inside the paper.
static func write_on_label(title: Label3D) -> void:
	title.position = TITLE_AT
	title.rotation = Vector3.ZERO
	title.scale = Vector3.ONE
	var per_point := float(title.outline_size) / float(maxi(title.font_size, 1))
	title.font_size = TITLE_FONT_SIZE
	title.outline_size = roundi(per_point * TITLE_FONT_SIZE)
	title.pixel_size = TITLE_PIXEL
	title.width = TITLE_WIDTH / TITLE_PIXEL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
