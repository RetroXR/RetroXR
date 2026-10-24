class_name WallOutlet
extends Node3D

## A wall plate of the player's region: its mesh, and a PowerPort per receptacle.
##
## Built in code from MainsRegions rather than authored in each room, so a room
## places one node and the plate is whatever AppPrefs.mains_region says -- a US
## duplex, a Schuko pair, a UK twin. Changing the region rebuilds every plate in
## the room (group GROUP); a plug already in the wall stays in the receptacle of
## the same name if it fits the new one, and drops out if it does not, as it
## would if the outlet had been changed under it.
##
## The plate's frame is the outlet generators': +X across the wall, +Y up, +Z out
## of the wall, origin on the wall surface.

const GROUP := "wall_outlet"
const PORT_SCENE := preload("res://Scenes/Objects/cables/power_port.tscn")

## A region this plate always is, whatever the setting -- a room set somewhere
## in particular. Empty follows AppPrefs.mains_region.
@export var region_override := ""

## The region the plate was last built as; "" before the first build.
var region := ""

var _plate: MeshInstance3D


func _ready() -> void:
	add_to_group(GROUP)
	_plate = MeshInstance3D.new()
	_plate.name = "Plate"
	add_child(_plate)
	set_region(AppPrefs.mains_region)


## Rebuild as `id`'s plate, unless region_override pins it. Seated plugs that fit
## the new receptacle of the same name are put back in it; the rest are let go.
func set_region(id: String) -> void:
	var want := MainsRegions.resolve(region_override if not region_override.is_empty() else id)
	if want == region:
		return
	region = want
	var spec := MainsRegions.of(want)
	_plate.mesh = load(str(spec.get("mesh", ""))) as Mesh

	var held := {}
	# Every old receptacle shut first. One let go of inside the other's reach (a
	# plug in the top one, the bottom one empty and watching) was caught by it on
	# the way out, and then freed with it: the plug went on saying it was held by
	# a receptacle that no longer existed, and the pointer threw on it.
	for port in ports():
		port.enabled = false
	for port in ports():
		if port.picked_up_object != null:
			held[String(port.name)] = port.picked_up_object
			port.drop_object()
		# Out of the tree now, not at the end of the frame: the new socket takes
		# the same name.
		remove_child(port)
		port.queue_free()

	for socket: Dictionary in spec.get("sockets", []):
		var port := PORT_SCENE.instantiate() as PowerPort
		port.name = str(socket.get("name", "Port"))
		port.connector = str(socket.get("connector", ""))
		port.position = socket.get("position", Vector3.ZERO)
		port.rotation_degrees = socket.get("rotation", Vector3.ZERO)
		add_child(port)

	for port_name: String in held:
		var plug: Node3D = held[port_name]
		var port := get_node_or_null(port_name) as PowerPort
		if port != null and is_instance_valid(plug) and plug.is_in_group(port.snap_require):
			port.pick_up_object(plug)


## This plate's receptacles, top first.
func ports() -> Array[PowerPort]:
	var out: Array[PowerPort] = []
	for n in get_children():
		if n is PowerPort:
			out.append(n as PowerPort)
	return out


## Rebuild every plate in `tree` as `id` -- the OPTIONS dropdown's live half.
static func apply_region(tree: SceneTree, id: String) -> void:
	for node in tree.get_nodes_in_group(GROUP):
		(node as WallOutlet).set_region(id)
