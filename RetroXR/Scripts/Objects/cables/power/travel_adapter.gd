class_name TravelAdapter
extends Node3D

## A universal travel adapter: a block with the room's wall prongs on its front
## and a universal socket on its back, so any wall plug the game ships -- an
## import's Schuko, a UK lead in a US room -- goes into this room's wall through
## it. The prongs are the mains region's, as the power strip's plug is: change
## the region and they change with it (MainsRegions' "strip" plug).
##
## The whole adapter is its plug, WallPlug; the root never moves. It speaks the
## power strip's persistence API (plug_at / seating / restore_*), one end and no
## cord, and the plug in its socket is recorded by THAT plug's lead, naming this
## adapter and "Socket".

const END_WALL := PowerCord.End.WALL

## Every adapter in the tree, so a change of mains region reaches them.
const GROUP := "travel_adapter"

## Its block and prongs for each wall plug (gen_power_connectors.gd).
const MESH_DIR := "res://Scenes/Objects/appliances/travel_adapter_%s.res"

@onready var wall_plug: PowerPlug = $WallPlug
@onready var socket: PowerPort = $WallPlug/Socket

## The region the adapter was last made as; "" before _ready.
var region := ""

## Put in by a region change (MainsSplice) rather than by the player, so taken
## out again by the one that makes it unneeded.
var spliced := false


func _ready() -> void:
	add_to_group(GROUP)
	wall_plug.cable = self
	# Its own socket is in its own body's way, and takes any wall plug: all but
	# this one.
	var own := "travel_adapter_%d" % get_instance_id()
	wall_plug.add_to_group(own)
	socket.snap_exclude = own
	socket.set_connector("universal_socket")
	set_region(AppPrefs.mains_region)


## Make the prongs `id`'s, the block and its socket with them. Out of a wall
## that no longer takes it, as the strip's plug falls out.
func set_region(id: String) -> void:
	var want := MainsRegions.resolve(id)
	if want == region:
		return
	region = want
	var spec: Dictionary = MainsRegions.of(want).get("strip", {})
	var plug := str(spec.get("plug", "nema_5_15_plug"))
	if not ResourceLoader.exists(MESH_DIR % plug):
		plug = "nema_5_15_plug"
	wall_plug.set_connector(plug)
	var tip := wall_plug.get_node("PlugTip") as MeshInstance3D
	tip.mesh = load(MESH_DIR % plug) as Mesh
	# The block's back is where the socket's face is, and the box the hand and the
	# pointer meet is the block's.
	var box := tip.mesh.get_aabb()
	socket.position = Vector3(0, 0, box.position.z)
	for path: String in ["CollisionShape3D", "PointerArea/CollisionShape3D"]:
		var shape := wall_plug.get_node(path) as CollisionShape3D
		var b := BoxShape3D.new()
		b.size = box.size + (Vector3(0.01, 0.01, 0.01) if path.begins_with("Pointer")
			else Vector3.ZERO)
		shape.shape = b
		shape.position = box.get_center()
	var holder := PowerCord.socket_holding(wall_plug)
	if holder != null and not wall_plug.is_in_group(holder.snap_require):
		holder.drop_object()


## Remake every adapter in `tree` as `id`'s, with PowerStrip.apply_region.
static func apply_region(tree: SceneTree, id: String) -> void:
	for node in tree.get_nodes_in_group(GROUP):
		(node as TravelAdapter).set_region(id)


func on_plug_seating_changed() -> void:
	pass


## Let go of the wall and of the plug in it, then free it.
func drop_and_free() -> void:
	var port := PowerCord.socket_holding(wall_plug)
	if port != null:
		port.drop_object()
	if socket.picked_up_object != null:
		socket.drop_object()
	queue_free()


# ── Persistence: the power strip's API, one end ──────────────────────────────────

func cord_count() -> int:
	return 1


func plug_at(end: int) -> PowerPlug:
	return wall_plug if end == END_WALL else null


func seating() -> Array[Dictionary]:
	var holder := PowerCord.socket_holding(wall_plug)
	return [{
		"plug": wall_plug,
		"end": int(END_WALL),
		"cord": 0,
		"device": holder.get_device() if holder != null else null,
		"port": String(holder.name) if holder != null else "",
	}]


func restore_plug_poses(seats: Array) -> void:
	for seat: Dictionary in seats:
		if int(seat.get("end", 0)) != END_WALL:
			continue
		var pos: Array = seat.get("position", [])
		var rot: Array = seat.get("rotation", [])
		if pos.size() == 3:
			wall_plug.global_position = Vector3(pos[0], pos[1], pos[2])
		if rot.size() == 3:
			wall_plug.global_rotation_degrees = Vector3(rot[0], rot[1], rot[2])


func restore_seating(seats: Array) -> void:
	call_deferred("_apply_seating", seats)


func _apply_seating(seats: Array) -> void:
	restore_plug_poses(seats)
	for seat: Dictionary in seats:
		var device: Node3D = seat.get("device")
		var port_name := str(seat.get("port", ""))
		if int(seat.get("end", 0)) != END_WALL or device == null \
				or not is_instance_valid(device) or port_name.is_empty():
			continue
		var port := CompositeCable.port_named(device, port_name)
		if port != null and wall_plug.is_in_group(port.snap_require):
			port.pick_up_object(wall_plug)
