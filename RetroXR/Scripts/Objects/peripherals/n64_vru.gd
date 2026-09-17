## N64Vru — the Voice Recognition Unit (NUS-020): a dongle on a cord with an
## ordinary N64 controller plug at the far end, and the NUS-021 microphone plugged
## into a 3.5 mm jack on its front.
##
## THE PLUG is what a console socket takes, not this box. ControllerPlug copies
## `device_type` and `systemid` off whatever owns it, joins the "controller_plug"
## group itself and forwards seating both ways; RetroSystem unwraps a seated plug
## with get_controller() before filing it as the port's controller. So the console
## still hears a VRU and this unit still answers where it hears from, without ever
## being in the socket itself — and the cord it hangs off is the same moulding
## every other N64 controller wears.
##
## It attaches when the core builds its joybus channels, which happens as content
## loads — so a unit pushed in while a game is running is heard at the next
## power-on, and the core says as much. Both games that listen want socket 4.
class_name N64Vru
extends XRToolsPickable

const MIC_CABLE_SCENE := preload("res://Scenes/Objects/controllers/n64/n64_vru_cable.tscn")
const CONSOLE_CABLE_SCENE := preload("res://Scenes/Objects/cables/controller_cable.tscn")

## The cord between the unit and the microphone.
const LEAD_LENGTH := 1.1
## And the one between the unit and the console.
const CONSOLE_LEAD_LENGTH := 1.3

## What a Voice Recognition Unit is, as libretro counts devices. Matches
## RETRO_DEVICE_N64_VRU in the core fork: RETRO_DEVICE_SUBCLASS(JOYPAD, 0).
const DEVICE_VRU := (1 << 8) | 1

## Read off this unit by its own plug, and announced to the core from there.
var device_type: int = DEVICE_VRU

## Which console's ports will take it.
var systemid: String = "nintendo_64"

## Set through the plug, which is what the socket actually holds.
var seated_system: Node3D = null
var seated_port_index: int = -1

var _mic_cable: Node3D = null
var _console_cable: Node3D = null
var _mic: N64VruMic = null
var _mic_plug: N64VruMicPlug = null
var _plug: ControllerPlug = null
var _mic_rope: VerletRope = null
var _console_rope: VerletRope = null
var _max_mic_rope := 0.0
var _max_console_rope := 0.0
var _pending_seat: Dictionary = {}
## The microphone comes plugged in, the way it comes in the box. A load says
## otherwise before the cords exist, so the answer is kept until they do.
var _pending_mic_plugged := true

@onready var _cable_attach_point: Node3D = $CableAttachPoint
@onready var _mic_jack: XRToolsSnapZone = $MicJack


func _ready() -> void:
	super._ready()
	add_to_group("spawned")
	add_to_group("n64_vru")
	# The jack takes the microphone's plug and nothing else. Filtering on the
	# group every cable plug is in would let a console controller into it.
	_mic_jack.snap_require = String(N64VruMicPlug.GROUP)
	_mic_jack.has_picked_up.connect(_on_mic_seated)
	_mic_jack.has_dropped.connect(_on_mic_pulled)
	_mic_cable = MIC_CABLE_SCENE.instantiate()
	_console_cable = CONSOLE_CABLE_SCENE.instantiate()
	_add_cables_to_scene.call_deferred()


func get_mic() -> N64VruMic:
	return _mic


## The 3.5 mm plug on the microphone's cord.
func get_mic_plug() -> N64VruMicPlug:
	return _mic_plug


## The controller plug on the console cord — what a socket takes.
func get_plug() -> ControllerPlug:
	return _plug


## The cord between the microphone and its plug.
func get_mic_rope() -> VerletRope:
	return _mic_rope


## The cord between this unit and the console.
func get_console_rope() -> VerletRope:
	return _console_rope


## Is the microphone in this unit's jack?
func mic_plugged() -> bool:
	return is_instance_valid(_mic_plug) and _mic_plug.seated_unit == self


## Where this machine hears from: the microphone, while it is plugged in. Out of
## the jack it is just an object lying somewhere, so the unit answers with itself
## rather than letting a microphone across the room set the gain.
func microphone_position() -> Vector3:
	if mic_plugged() and is_instance_valid(_mic):
		return _mic.global_position
	return global_position


## Called by the plug when it snaps into one of a console's ports.
func on_plugged_in(system: RetroSystem, port_index: int) -> void:
	seated_system = system
	seated_port_index = port_index


func on_unplugged() -> void:
	seated_system = null
	seated_port_index = -1


## Seat this unit's plug in `port` of `system`, once the cord exists.
func restore_seat(system: RetroSystem, port: int) -> void:
	if _plug != null:
		system.restore_controller_plug(port, _plug)
	else:
		_pending_seat = {"system": system, "port": port}


## Put the microphone back in the jack after a load, or leave it out of it.
func restore_mic_plugged(plugged: bool) -> void:
	if _mic_plug == null:
		_pending_mic_plugged = plugged
		return
	_apply_mic_plugged(plugged)


func _apply_mic_plugged(plugged: bool) -> void:
	if plugged and not mic_plugged():
		_mic_jack.pick_up_object(_mic_plug)
	elif not plugged and mic_plugged():
		_mic_jack.drop_object()


func _add_cables_to_scene() -> void:
	var scene := get_tree().current_scene
	scene.add_child(_mic_cable)
	_mic_cable.add_to_group("spawned")
	scene.add_child(_console_cable)
	_console_cable.add_to_group("spawned")

	_mic = _mic_cable.get_node("Nus021Mic") as N64VruMic
	_mic_plug = _mic_cable.get_node("MicPlug") as N64VruMicPlug
	_mic_rope = _mic_cable.get_node("VerletRope") as VerletRope
	_mic.set_unit(self)
	_mic.set_plug(_mic_plug)
	_mic_plug.set_microphone(_mic)
	_mic.add_collision_exception_with(self)
	_mic_plug.add_collision_exception_with(self)
	_mic_plug.global_transform = _mic_jack.global_transform
	_mic.global_position = _mic_jack.global_transform * Vector3(0, 0, 0.18)
	_mic_rope.set_rope_length(LEAD_LENGTH)
	_mic_rope.start_node = _mic
	_mic_rope.end_node = _mic_plug
	# Both ends say which way the cord leaves rather than taking the default, and
	# they disagree: a rope exits a directional endpoint along its local -Z, the
	# microphone's boss is at +Z, and the plug's cord trails -Z behind a connector
	# that points +Z. Left alone, the mic's cord came out of its own grille.
	_mic_rope.start_endpoint_role = VerletRope.ENDPOINT_HOST
	_mic_rope.end_endpoint_role = VerletRope.ENDPOINT_HOST
	_mic_rope.start_exit_axis = Vector3(0, 0, 1)
	_mic_rope.end_exit_axis = Vector3(0, 0, -1)
	_mic_rope.start_anchor_offset = N64VruMic.CORD_EXIT
	_mic_rope.end_anchor_offset = N64VruMicPlug.CORD_EXIT
	_mic_rope._init_points()
	_max_mic_rope = _mic_rope.segment_count * _mic_rope.segment_length

	_plug = _console_cable.get_node("ControllerPlug") as ControllerPlug
	_console_rope = _console_cable.get_node("VerletRope") as VerletRope
	# This is the whole of the wiring: the plug takes device_type and systemid off
	# this unit and hands seating back to it.
	_plug.set_controller(self)
	_plug.add_collision_exception_with(self)
	_plug.global_position = _cable_attach_point.global_transform * Vector3(0, 0, 0.12)
	_console_rope.set_rope_length(CONSOLE_LEAD_LENGTH)
	_console_rope.start_node = _cable_attach_point
	_console_rope.end_node = _plug
	_console_rope.start_endpoint_role = VerletRope.ENDPOINT_HOST
	_console_rope.start_exit_axis = Vector3(0, 0, 1)
	_console_rope.end_anchor_offset = _plug.cable_anchor
	_console_rope._init_points()
	_max_console_rope = _console_rope.segment_count * _console_rope.segment_length

	_apply_mic_plugged(_pending_mic_plugged)

	if not _pending_seat.is_empty():
		var system: RetroSystem = _pending_seat.get("system")
		var port := int(_pending_seat.get("port", -1))
		_pending_seat = {}
		if is_instance_valid(system) and port >= 0:
			system.restore_controller_plug(port, _plug)


func _on_mic_seated(obj: Node3D) -> void:
	var plug := obj as N64VruMicPlug
	if plug == null:
		return
	plug.on_seated(self)
	add_collision_exception_with(plug)


## has_dropped carries no argument, which is enough: the jack holds one thing.
func _on_mic_pulled() -> void:
	if is_instance_valid(_mic_plug):
		_mic_plug.on_pulled()


## Validity is tested HERE rather than inside the call: a freed body fails the
## typed argument check before the function is entered, which is a script error
## every tick between a unit being binned and its cords catching up.
func _physics_process(_delta: float) -> void:
	if is_instance_valid(_mic) and is_instance_valid(_mic_plug):
		_hold_within(_mic, _mic_plug, _max_mic_rope)
	if is_instance_valid(_plug) and is_instance_valid(_cable_attach_point):
		_hold_within(_plug, _cable_attach_point, _max_console_rope)


## Keep `body` inside the cord that ties it to `anchor`. A held body is the
## player's business, and so is a rope that has not been built yet.
func _hold_within(body: XRToolsPickable, anchor: Node3D, limit: float) -> void:
	if limit <= 0.0:
		return
	if body.is_picked_up():
		return
	var anchor_pos := anchor.global_position
	var diff := body.global_position - anchor_pos
	var dist := diff.length()
	if dist <= limit:
		return
	var dir := diff / dist
	body.global_position = anchor_pos + dir * limit
	var outward := dir.dot(body.linear_velocity)
	if outward > 0.0:
		body.linear_velocity -= dir * outward


## Both cords go with the unit.
func drop_and_free() -> void:
	if is_instance_valid(_mic):
		_mic.drop()
	if is_instance_valid(_mic_plug):
		_mic_plug.drop()
	if is_instance_valid(_plug):
		_plug.drop()
	if is_instance_valid(_mic_cable):
		_mic_cable.queue_free()
	if is_instance_valid(_console_cable):
		_console_cable.queue_free()
	Vanish.free_node(self)
