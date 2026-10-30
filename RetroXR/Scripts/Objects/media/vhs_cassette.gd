## VhsCassette — the drawn VHS cassette inside a VCRTape: RetroXR-models' generic/vhs-tape at three levels, the
## tape wound onto its reels by how far through the cassette it is, its flap, and label art on its face and spine.
##
## Ported from that item's godot_demo/vhs_tape.gd, which its validation checks against the model's own
## tape_contract.json. Meters; the top face (windows, label) looks along +Z, the flap is the +Y edge, the supply reel
## is at -X. Origin: the cassette's center (188 x 104 x 25 mm). The tape winds at the drawn T-n's length:
##     wound radius  r = sqrt(hub^2 + length_on_reel * thickness / PI)
##     reel angle    2 PI (r - hub) / thickness
class_name VhsCassette
extends Node3D

const LEVELS := [
	"res://imported-assets/appliances/vhs_tape/vhs_mobile_clean.glb",
	"res://imported-assets/appliances/vhs_tape/vhs_mobile_clean_lod1.glb",
	"res://imported-assets/appliances/vhs_tape/vhs_mobile_clean_lod2.glb",
]
const SWITCH_DISTANCE := 1.0
const FAR_DISTANCE := 2.2
const HYSTERESIS := 0.12

# The cassette's tape geometry in millimeters (tape_contract.json).
const REEL_SUPPLY := Vector2(-46.0, -4.0)
const REEL_TAKEUP := Vector2(46.0, -4.0)
const HUB_RADIUS := 13.0
const PACK_MAX_RADIUS := 43.8
const TAPE_WIDTH := 12.65
const TAPE_CENTER_Z := -0.5
const GUIDE_SUPPLY := Vector2(-86.0, 47.0)
const GUIDE_TAKEUP := Vector2(57.0, 47.0)
const GUIDE_RADIUS := 3.0
const POST_SUPPLY := Vector2(-81.5, 32.0)
const POST_SUPPLY_RADIUS := 1.25
const POST_TAKEUP := Vector2(61.8, 42.5)
const POST_TAKEUP_RADIUS := 1.3
const SPAN_UNIT := 10.0
const GAUGES := [0.0190, 0.0156, 0.0125]
const DOOR_OPEN_DEGREES := 90.0
## NTSC SP, mm/s: a T-n holds n minutes at it.
const TAPE_SPEED := 33.35

## The cassette's running time in minutes (its T-n); the drawn packs are this long a tape.
var tape_minutes: float = 120.0:
	set(v):
		tape_minutes = maxf(v, 1.0)
		_dirty()
## 0 rewound (all on the supply reel) .. 1 at the cassette's end.
var progress: float = 0.0:
	set(v):
		progress = clampf(v, 0.0, 1.0)
		_dirty()
## 0 closed .. 1 open: the flap swings up 90 degrees about its hinge.
var door_open: float = 0.0:
	set(v):
		door_open = clampf(v, 0.0, 1.0)
		for door in _parts("Door"):
			door.rotation = Vector3(deg_to_rad(DOOR_OPEN_DEGREES) * door_open, 0.0, 0.0)

var levels: Array[Node3D] = []
var _wound := false


func _ready() -> void:
	for i in LEVELS.size():
		var level := (load(LEVELS[i]) as PackedScene).instantiate() as Node3D
		level.name = "LOD%d" % i
		add_child(level)
		levels.append(level)
		for n in ["PackSupply", "PackTakeup"]:
			var pack := level.find_child(n, true, false) as MeshInstance3D
			# The mesh's own bounds are the exported pose's: give culling the largest pack.
			var r := PACK_MAX_RADIUS * 0.001
			pack.custom_aabb = AABB(Vector3(-r, -r, (TAPE_CENTER_Z - TAPE_WIDTH * 0.5) * 0.001),
				Vector3(2.0 * r, 2.0 * r, TAPE_WIDTH * 0.001))
		var starts := [0.0, SWITCH_DISTANCE, FAR_DISTANCE]
		for n in level.find_children("*", "GeometryInstance3D", true, false):
			var g := n as GeometryInstance3D
			g.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			g.visibility_range_begin = starts[i]
			g.visibility_range_begin_margin = HYSTERESIS if i > 0 else 0.0
			g.visibility_range_end = starts[i + 1] if i + 1 < LEVELS.size() else 0.0
			g.visibility_range_end_margin = HYSTERESIS if i + 1 < LEVELS.size() else 0.0
	door_open = door_open
	_wind()


func _dirty() -> void:
	if not _wound:
		_wound = true
		_wind.call_deferred()


func _parts(part_name: String) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for level in levels:
		var p := level.find_child(part_name, true, false) as Node3D
		if p != null:
			out.append(p)
	return out


# --- the tape ---------------------------------------------------------------------------------------------------------

func _tape_length() -> float:
	return tape_minutes * 60.0 * TAPE_SPEED


## The thickest standard gauge whose full pack fits the reel, as the makers did.
func _thickness() -> float:
	var length := _tape_length()
	for g: float in GAUGES:
		if _pack_radius(g, length) <= PACK_MAX_RADIUS + 1e-9:
			return g
	return PI * (PACK_MAX_RADIUS * PACK_MAX_RADIUS - HUB_RADIUS * HUB_RADIUS) / maxf(length, 1.0)


static func _pack_radius(thickness: float, length: float) -> float:
	return sqrt(HUB_RADIUS * HUB_RADIUS + maxf(length, 0.0) * thickness / PI)


static func _pack_turns(thickness: float, length: float) -> float:
	return (_pack_radius(thickness, length) - HUB_RADIUS) / thickness


## The straight run between circle 1 and circle 2: [point on 1, point on 2].
static func _tangent(c1: Vector2, r1: float, c2: Vector2, r2: float, side: float, crossed := false) -> Array[Vector2]:
	var d := c2 - c1
	var e := d / d.length()
	var left := Vector2(-e.y, e.x)
	var k := (r1 + r2) / d.length() if crossed else (r1 - r2) / d.length()
	var s := sqrt(maxf(1.0 - k * k, 0.0)) * signf(side)
	var n := e * k + left * s
	return [c1 + n * r1, c2 - n * r2 if crossed else c2 + n * r2]


## The tape between one front guide and its pack: one run, or two where it bears on the thin post.
static func _tape_run(supply: bool, pack_r: float) -> Array:
	var c := REEL_SUPPLY if supply else REEL_TAKEUP
	var g := GUIDE_SUPPLY if supply else GUIDE_TAKEUP
	var p := POST_SUPPLY if supply else POST_TAKEUP
	var pr := POST_SUPPLY_RADIUS if supply else POST_TAKEUP_RADIUS
	var sgn := -1.0 if supply else 1.0
	var direct := _tangent(g, GUIDE_RADIUS, c, pack_r, sgn)
	var n := (direct[0] - g) / GUIDE_RADIUS
	var inside := -(p - direct[0]).dot(n)
	var along_dir := direct[1] - direct[0]
	var along := (p - direct[0]).dot(along_dir) / along_dir.length()
	if along <= 0.0 or along >= along_dir.length():
		return [direct]
	if supply:
		if inside >= pr:
			return [direct]
		return [_tangent(g, GUIDE_RADIUS, p, pr, sgn), _tangent(p, pr, c, pack_r, sgn)]
	if inside <= -pr:
		return [direct]
	return [_tangent(g, GUIDE_RADIUS, p, pr, sgn, true), _tangent(p, pr, c, pack_r, -sgn, true)]


func _wind() -> void:
	_wound = false
	if levels.is_empty():
		return
	var length := _tape_length()
	var t := _thickness()
	var on_takeup := length * progress
	var on_supply := length - on_takeup
	for level in levels:
		for supply: bool in [true, false]:
			var side := "Supply" if supply else "Takeup"
			var r := _pack_radius(t, on_supply if supply else on_takeup)
			var turns := (_pack_turns(t, length) - _pack_turns(t, on_supply)) if supply else _pack_turns(t, on_takeup)
			var reel := level.find_child("Reel" + side, true, false) as Node3D
			if reel:
				reel.rotation = Vector3(0, 0, -fposmod(turns, 1.0) * TAU)      # clockwise seen from +Z
			var pack := level.find_child("Pack" + side, true, false) as MeshInstance3D
			if pack:
				_set_pack_radius(pack, r)
			var runs := _tape_run(supply, r)
			for k in 2:
				var span := level.find_child("TapeSpan%s%s" % [side, "AB"[k]], true, false) as Node3D
				if span == null:
					continue
				span.visible = k < runs.size()
				if not span.visible:
					continue
				var a: Vector2 = runs[k][0]
				var b: Vector2 = runs[k][1]
				span.position = Vector3(a.x, a.y, 0.0) * 0.001
				span.rotation = Vector3(0, 0, (b - a).angle())
				span.scale = Vector3((b - a).length() / SPAN_UNIT, 1, 1)


static func _set_pack_radius(pack: MeshInstance3D, r: float) -> void:
	var extras: Dictionary = pack.get_meta("extras", {})
	var supply := String(pack.name).ends_with("Supply")
	var basis: float = extras.get("basis_radius_mm", 40.7 if supply else HUB_RADIUS + 0.3)
	var target: float = extras.get("target_radius_mm", HUB_RADIUS if supply else PACK_MAX_RADIUS)
	pack.set_blend_shape_value(0, (r - basis) / (target - basis))
	pack.visible = r > HUB_RADIUS + 0.05


# --- labels -----------------------------------------------------------------------------------------------------------

## Paint art on one label ("LabelFace" or "LabelSpine") of every level, or put the plain white back (null).
func set_label(label: String, texture: Texture2D) -> void:
	for p in _parts(label):
		var mi := p as MeshInstance3D
		if mi == null:
			continue
		if texture == null:
			mi.set_surface_override_material(0, null)
			continue
		var material := mi.mesh.surface_get_material(0).duplicate() as StandardMaterial3D
		material.albedo_color = Color.WHITE
		material.albedo_texture = texture
		material.texture_repeat = false
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		mi.set_surface_override_material(0, material)


## Every mesh of every level.
func meshes() -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	for level in levels:
		for n in level.find_children("*", "MeshInstance3D", true, false):
			out.append(n as MeshInstance3D)
	return out
