class_name ExtensionCable
extends PowerStrip

## A mains extension cable: a wall plug, a cord of the length asked for at spawn,
## and a one-outlet head the player carries. The room's region, like the strip:
## its plug, its socket, its head (head_of).
##
## A PowerStrip with one socket, so it is saved, re-plugged on a region change
## (MainsSplice) and powered (MainsPower) as one. Only the body and the cord's
## length are its own.

## The lengths the spawn menu offers, as the speaker lead's.
const SPAWN_LENGTHS := CompositeCable.SPAWN_LENGTHS
const SHIPPED_LENGTH := CompositeCable.SHIPPED_LENGTH

## The strain relief behind the head, mm: the cord goes in at its narrow end.
const RELIEF := 16.0

## A head with no baked mesh (a mod's region): face and length, mm.
const FALLBACK_FACE := Vector2(40, 34)
const FALLBACK_LENGTH := 40.0

## Metres, read once in _ready before the rope is laid. The scene authors the
## longest; a shorter one drops segments (never adds: CompositeCable's reason).
@export var cord_length: float = SHIPPED_LENGTH


func _anchor_path() -> NodePath:
	return ^"Body/CordAnchor"


func _ready() -> void:
	_apply_cord_length()
	super()


func _apply_cord_length() -> void:
	var seg := rope.segment_length
	var authored := rope.segment_count
	if seg <= 0.0 or cord_length <= 0.0:
		return
	cord_length = clampf(cord_length, 0.3, float(authored) * seg)
	var count := clampi(int(round(cord_length / seg)), 2, authored)
	rope.segment_count = count
	rope.segment_length = cord_length / float(count)
	# Arrays at the new count now, not at _build_rope's: a save's layout is
	# checked against them before that runs.
	rope._init_points()
	# Laid out part of the way, not as a heap at the head.
	wall_plug.position.x = clampf(cord_length * 0.4, 0.4, 1.2)


## The region's head: its socket (the strip's own kind) and its baked mesh. The
## mesh is a plate (MainsRegions.strip_sockets' frame, the socket at its origin
## facing +Z) whose metadata gives its face and length and the socket's well, mm.
static func head_of(id: String) -> Dictionary:
	var key := MainsRegions.resolve(id)
	var strip: Dictionary = MainsRegions.of(key).get("strip", {})
	var connector := str(strip.get("socket", "nema_5_15_plug"))
	var layout: Array = strip.get("layout", [])
	if not layout.is_empty():
		var entry: Dictionary = layout[0]
		for e: Dictionary in layout:
			if not e.has("socket"):
				entry = e
				break
		connector = str(entry.get("socket", connector))
	return {"connector": connector,
		"mesh": "res://Scenes/Objects/appliances/extension_head_%s.res" % key}


## The plate into the body's frame: an inline connector lying on its side, its
## face out along -X (away from the cord), upright, on the floor.
static func head_at(length: float, height: float) -> Transform3D:
	return Transform3D(Basis(Vector3(0, 0, 1), Vector3.UP, Vector3(-1, 0, 0)),
		Vector3(length * 0.5, height * 0.5, 0))


## "Type B": the outlet on the head, by the plug it takes; the region's own
## types for a plug MainsRegions does not letter.
static func outlet_type(id: String) -> String:
	var strip: Dictionary = MainsRegions.of(id).get("strip", {})
	var kind := MainsRegions.plug_type(str(strip.get("plug", "")))
	return kind if not kind.is_empty() else str(MainsRegions.of(id).get("types", ""))


## "3 m", "1.5 m".
static func length_label(metres: float) -> String:
	for row: Array in SPAWN_LENGTHS:
		if is_equal_approx(float(row[0]), metres):
			return str(row[1])
	return "%s m" % str(snappedf(metres, 0.1))


func set_region(id: String) -> void:
	var want := MainsRegions.resolve(id)
	if want == region:
		return
	region = want
	var spec: Dictionary = MainsRegions.of(want).get("strip", {})
	if spec.is_empty():
		spec = MainsRegions.of(MainsRegions.DEFAULT).get("strip", {})
	var head := head_of(want)
	var face := FALLBACK_FACE * 0.001
	var length := FALLBACK_LENGTH * 0.001
	var well := 0.0
	var mesh := _body.get_node("Head") as MeshInstance3D
	var path := str(head["mesh"])
	var baked: Mesh = load(path) as Mesh if ResourceLoader.exists(path) else null
	if baked != null and baked.has_meta("head_length"):
		face = (baked.get_meta("head_face") as Vector2) * 0.001
		length = float(baked.get_meta("head_length")) * 0.001
		well = float(baked.get_meta("head_well")) * 0.001
		mesh.mesh = baked
		mesh.transform = head_at(length, face.y)
	else:
		var box := BoxMesh.new()
		box.size = Vector3(face.x, face.y, length)
		mesh.mesh = box
		mesh.transform = head_at(length, face.y) * Transform3D(Basis.IDENTITY,
			Vector3(0, 0, length * 0.5))
	var relief := RELIEF * 0.001
	_set_shape("CollisionShape3D", Vector3(length, face.y, face.x), face.y * 0.5)
	_set_shape("PointerArea/CollisionShape3D",
		Vector3(length + relief * 2.0, face.y + 0.012, face.x + 0.012), face.y * 0.5)
	# The cord out of the relief's end, its -Z along +X.
	_set_anchor(Transform3D(Basis(Vector3.UP, -PI * 0.5),
		Vector3(length * 0.5 + relief, face.y * 0.5, 0)))
	var s := sockets()[0]
	s.transform = head_at(length, face.y) * Transform3D(Basis.IDENTITY,
		Vector3(0, 0, length - well))
	_open(s, str(head["connector"]), true)
	_fit_plug(spec)


func mains_noun() -> String:
	return "extension cable"
