## N64VruMic — the NUS-021 microphone on the Voice Recognition Unit's cord.
##
## The unit has no button of its own: the game watches the VRU port's Z line to
## know someone is talking, and times the utterance by how long it is held. So
## the trigger of the hand holding the microphone raises Z on the unit's port,
## through SetJoypadExtraButtons — the controller's own writes do not clear it.
##
## Hey You, Pikachu! also wants Z held on the socket-1 pad, which is the player's
## own controller and nothing to do with this.
class_name N64VruMic
extends XRToolsPickable

## Where the cord leaves the body, in this microphone's frame.
const CORD_EXIT := Vector3(0, 0, 0.048)

## The N64's Z, as libretro counts buttons.
const TALK_BITS := 1 << ControllerBindings.JOYPAD_L2

var _unit: N64Vru = null
## The Libretro node Z is currently held on, or null.
var _pressed_on: Libretro = null


func _ready() -> void:
	super._ready()
	add_to_group("spawned")


func set_unit(unit: N64Vru) -> void:
	_unit = unit


func _process(_delta: float) -> void:
	var lib := _seated_libretro()
	var talking := lib != null and _trigger_held()
	var target: Libretro = lib if talking else null
	if target == _pressed_on:
		return
	release_button()
	if target != null and is_instance_valid(_unit):
		target.SetJoypadExtraButtons(_unit.seated_port_index, TALK_BITS)
	_pressed_on = target


func _exit_tree() -> void:
	release_button()


func release_button() -> void:
	if is_instance_valid(_pressed_on) and is_instance_valid(_unit) \
			and _unit.seated_port_index >= 0:
		_pressed_on.SetJoypadExtraButtons(_unit.seated_port_index, 0)
	_pressed_on = null


func _seated_libretro() -> Libretro:
	if not is_instance_valid(_unit) or _unit.seated_port_index < 0:
		return null
	var system := _unit.seated_system as RetroSystem
	if system == null or not system.is_powered_on:
		return null
	return system.get_libretro_node()


func _trigger_held() -> bool:
	if not is_picked_up():
		return false
	var controller := get_picked_up_by_controller()
	if controller != null:
		return controller.is_button_pressed("trigger_click")
	return Input.is_action_pressed("trigger_left")
