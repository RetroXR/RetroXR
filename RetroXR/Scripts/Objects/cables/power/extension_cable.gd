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

## North America's strip keeps the old GLB body, so its head is written here
## (mm; a grounded single-outlet cord end, EST).
const NA_HEAD := {"size": Vector3(52, 44, 32), "turn": -90.0}

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


## The region's head: its size (mm) and its one socket, in the plate frame
## MainsRegions.strip_sockets uses (on its back, +X toward the cord end, +Z up).
## The socket is the strip's own kind, with its turn, offset and well.
static func head_of(id: String) -> Dictionary:
	var key := MainsRegions.resolve(id)
	var strip: Dictionary = MainsRegions.of(key).get("strip", {})
	var connector := str(strip.get("socket", "nema_5_15_plug"))
	var size: Vector3 = NA_HEAD["size"]
	var entry := {"turn": NA_HEAD["turn"]}
	if strip.has("size"):
		var layout: Array = strip.get("layout", [{}])
		entry = layout[0]
		for e: Dictionary in layout:
			if not e.has("socket"):
				entry = e
				break
		connector = str(entry.get("socket", connector))
		var body: Vector3 = strip["size"]
		size = Vector3(maxf(float(entry.get("pitch", 40.0)), 40.0) + 16.0, body.y, body.z)
	var offset: Vector2 = entry.get("offset", Vector2.ZERO)
	return {
		"size": size,
		"mesh": "res://Scenes/Objects/appliances/extension_head_%s.res" % key,
		"socket": {
			"name": "Socket1",
			"connector": connector,
			"position": Vector3(offset.x, offset.y,
				size.z - float(entry.get("well", 0.0))) * 0.001,
			"rotation": Vector3(0, 0, float(entry.get("turn", 0.0))),
		},
	}


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
	var size: Vector3 = head["size"] * 0.001
	var mesh := _body.get_node("Head") as MeshInstance3D
	mesh.transform = PLATE_AT
	var path := str(head["mesh"])
	if ResourceLoader.exists(path):
		mesh.mesh = load(path) as Mesh
	else:
		# A mod's region, with no head baked: a plain block.
		var box := BoxMesh.new()
		box.size = Vector3(size.x, size.y, size.z)
		mesh.mesh = box
	_set_shape("CollisionShape3D", Vector3(size.x, size.z, size.y), size.z * 0.5)
	_set_shape("PointerArea/CollisionShape3D",
		Vector3(size.x + 0.02, size.z + 0.012, size.y + 0.018), size.z * 0.5)
	# The cord out of the +X end, its -Z along +X.
	_set_anchor(Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(size.x * 0.5, size.z * 0.5, 0)))
	var at: Dictionary = head["socket"]
	var s := sockets()[0]
	s.transform = PLATE_AT * Transform3D(
		Basis.from_euler((at["rotation"] as Vector3) * (PI / 180.0)), at["position"])
	_open(s, str(at["connector"]), true)
	_fit_plug(spec)


func mains_noun() -> String:
	return "extension cable"
