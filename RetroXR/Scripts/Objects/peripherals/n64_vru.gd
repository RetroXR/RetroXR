## N64Vru — the Voice Recognition Unit (NUS-020): a box that goes in a
## controller socket with the NUS-021 microphone on a cord.
##
## Saying so in `device_type` is the whole of how the console finds out, the way
## the GameCube link lead does it: RetroSystem announces a seated plug's device
## type to the core, and mupen64plus-next turns that into a VRU controller.
##
## It attaches when the core builds its joybus channels, which happens as content
## loads — so a unit pushed in while a game is running is heard at the next
## power-on, and the core says as much. Both games that listen want socket 4.
class_name N64Vru
extends XRToolsPickable

const CABLE_SCENE := preload("res://Scenes/Objects/controllers/n64/n64_vru_cable.tscn")

## The cord between the unit and the microphone.
const LEAD_LENGTH := 1.5

## What a Voice Recognition Unit is, as libretro counts devices. Matches
## RETRO_DEVICE_N64_VRU in the core fork: RETRO_DEVICE_SUBCLASS(JOYPAD, 0).
const DEVICE_VRU := (1 << 8) | 1

## Read by RetroSystem when this seats, and announced to the core.
var device_type: int = DEVICE_VRU

## Which console's ports will take it.
var systemid: String = "nintendo_64"

## Set by the console, which is the only thing that knows: a controller socket is
## a plain snap zone, so there is no port object to walk out of.
var seated_system: Node3D = null
var seated_port_index: int = -1

var _cable_instance: Node3D = null
var _mic: N64VruMic = null
var _rope: VerletRope = null
var _max_rope_length := 0.0
var _pending_seat: Dictionary = {}

@onready var _cable_attach_point: Node3D = $CableAttachPoint


func _ready() -> void:
	super._ready()
	add_to_group("spawned")
	# The string a console's ports filter on. A connector that fits a socket has
	# to answer to the name the socket asks for.
	add_to_group("controller_plug")
	add_to_group("n64_vru")
	_cable_instance = CABLE_SCENE.instantiate()
	_add_cable_to_scene.call_deferred()


func get_mic() -> N64VruMic:
	return _mic


## Where this machine hears from: the microphone in the player's hand, not the
## box in the socket.
func microphone_position() -> Vector3:
	if is_instance_valid(_mic):
		return _mic.global_position
	return global_position


## Called by RetroSystem when this snaps into one of its ports.
func on_plugged_in(system: RetroSystem, port_index: int) -> void:
	seated_system = system
	seated_port_index = port_index
	if is_instance_valid(_mic):
		_mic.set_unit(self)


func on_unplugged() -> void:
	seated_system = null
	seated_port_index = -1


## Seat this unit in `port` of `system`, once the cord exists.
func restore_seat(system: RetroSystem, port: int) -> void:
	if _cable_instance != null and _mic != null:
		system.restore_controller_plug(port, self)
	else:
		_pending_seat = {"system": system, "port": port}


func _add_cable_to_scene() -> void:
	get_tree().current_scene.add_child(_cable_instance)
	_cable_instance.add_to_group("spawned")
	_mic = _cable_instance.get_node("Nus021Mic") as N64VruMic
	_rope = _cable_instance.get_node("VerletRope") as VerletRope
	_mic.set_unit(self)
	_mic.add_collision_exception_with(self)
	_mic.global_position = _cable_attach_point.global_transform * Vector3(0, 0, 0.1)
	_rope.set_rope_length(LEAD_LENGTH)
	_rope.start_node = _cable_attach_point
	_rope.end_node = _mic
	# Both ends leave along +Z, which has to be said rather than assumed: a rope
	# exits a directional endpoint along its local -Z by default, and BOTH bodies
	# here are built the other way round -- the grille and the connector are at
	# -Z and the cord boss at +Z. Left at the default the cord came out of the
	# nose and doubled back through the body.
	_rope.start_endpoint_role = VerletRope.ENDPOINT_HOST
	# Not AUTO: the rope turns a free-plug end to face its cord every tick, and on
	# a floor that walks the microphone forward without end.
	_rope.end_endpoint_role = VerletRope.ENDPOINT_HOST
	_rope.start_exit_axis = Vector3(0, 0, 1)
	_rope.end_exit_axis = Vector3(0, 0, 1)
	_rope.end_anchor_offset = N64VruMic.CORD_EXIT
	_rope._init_points()
	_max_rope_length = _rope.segment_count * _rope.segment_length

	if not _pending_seat.is_empty():
		var system: RetroSystem = _pending_seat.get("system")
		var port := int(_pending_seat.get("port", -1))
		_pending_seat = {}
		if is_instance_valid(system) and port >= 0:
			system.restore_controller_plug(port, self)


func _physics_process(_delta: float) -> void:
	if _mic == null or _cable_attach_point == null or _max_rope_length <= 0.0 \
			or _mic.is_picked_up():
		return
	var attach_pos := _cable_attach_point.global_position
	var diff := _mic.global_position - attach_pos
	var dist := diff.length()
	if dist > _max_rope_length:
		var dir := diff / dist
		_mic.global_position = attach_pos + dir * _max_rope_length
		var outward := dir.dot(_mic.linear_velocity)
		if outward > 0.0:
			_mic.linear_velocity -= dir * outward


## The microphone and its cord go with the unit.
func drop_and_free() -> void:
	if is_instance_valid(_mic):
		_mic.drop()
	if is_instance_valid(_cable_instance):
		_cable_instance.queue_free()
	Vanish.free_node(self)
