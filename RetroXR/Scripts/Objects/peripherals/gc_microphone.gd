## GcMicrophone — the GameCube Microphone (DOL-022): a held stick on a 2 m cord
## whose plug seats in a memory card slot.
##
## The aqua button is the trigger of the hand holding the stick, or the left mouse
## button on desktop. Dolphin reads the microphone's button from the joypad bit its
## hotkey option names, on any port, and ForcedCoreOptions pins that bit to R3; a
## press holds R3 on port 0 through Libretro.SetJoypadExtraButtons, which the
## controller's own writes do not clear.
class_name GcMicrophone
extends XRToolsPickable

const CABLE_SCENE := preload("res://Scenes/Objects/controllers/gamecube/gc_microphone_cable.tscn")

const LEAD_LENGTH := 2.0
const BUTTON_BITS := 1 << ControllerBindings.JOYPAD_R3
const BUTTON_TRAVEL := 0.0015

## Desktop: plain left-click is the aqua button while held, so dropping requires
## Shift+click (same rule as the mouse and the light gun's trigger).
var desktop_shift_drop := true

var _cable_instance: Node3D = null
var _plug: GcMicrophonePlug = null
var _rope: VerletRope = null
var _max_rope_length := 0.0
var _pending_seat: Dictionary = {}
## The Libretro node the button is currently held on, or null.
var _pressed_on: Libretro = null

@onready var _cable_attach_point: Node3D = $CableAttachPoint
@onready var _button: Node3D = $Button
@onready var _button_rest: Vector3 = _button.position


func _ready() -> void:
	super._ready()
	add_to_group("spawned")
	_cable_instance = CABLE_SCENE.instantiate()
	_add_cable_to_scene.call_deferred()


func get_plug() -> GcMicrophonePlug:
	return _plug


func seated_system() -> RetroSystem:
	return _plug.seated_system() if _plug != null else null


func seated_slot() -> int:
	return _plug.seated_slot() if _plug != null else -1


## Seat the plug in `slot` of `system`, once the cord exists.
func restore_seat(system: RetroSystem, slot: int) -> void:
	if _plug != null:
		system.restore_memory_card(_plug, slot)
	else:
		_pending_seat = {"system": system, "slot": slot}


func _add_cable_to_scene() -> void:
	get_tree().current_scene.add_child(_cable_instance)
	_cable_instance.add_to_group("spawned")
	_plug = _cable_instance.get_node("MicPlug") as GcMicrophonePlug
	_rope = _cable_instance.get_node("VerletRope") as VerletRope
	_plug.set_microphone(self)
	_plug.add_collision_exception_with(self)
	_plug.global_position = _cable_attach_point.global_transform * Vector3(0, 0, 0.12)
	_rope.set_rope_length(LEAD_LENGTH)
	_rope.start_node = _cable_attach_point
	_rope.end_node = _plug
	# Both ends leave along +Z, which has to be said rather than assumed: a rope
	# exits a directional endpoint along its local -Z by default, and BOTH bodies
	# here are built the other way round -- the grille and the connector are at
	# -Z and the cord boss at +Z. Left at the default the cord came out of the
	# nose and doubled back through the body.
	_rope.start_endpoint_role = VerletRope.ENDPOINT_HOST
	_rope.end_endpoint_role = VerletRope.ENDPOINT_AUTO
	_rope.start_exit_axis = Vector3(0, 0, 1)
	_rope.end_exit_axis = Vector3(0, 0, 1)
	_rope.end_anchor_offset = GcMicrophonePlug.CORD_EXIT
	_rope._init_points()
	_max_rope_length = _rope.segment_count * _rope.segment_length

	if not _pending_seat.is_empty():
		var system: RetroSystem = _pending_seat.get("system")
		var slot := int(_pending_seat.get("slot", -1))
		_pending_seat = {}
		if is_instance_valid(system) and slot >= 0:
			system.restore_memory_card(_plug, slot)


func _process(_delta: float) -> void:
	var lib := _seated_libretro()
	var pressed := lib != null and _trigger_held()
	var target: Libretro = lib if pressed else null
	if target != _pressed_on:
		_release_button()
		if target != null:
			target.SetJoypadExtraButtons(0, BUTTON_BITS)
		_pressed_on = target
	_button.position = _button_rest - Vector3(0, BUTTON_TRAVEL, 0) if pressed else _button_rest


func _physics_process(_delta: float) -> void:
	if _plug == null or _cable_attach_point == null or _max_rope_length <= 0.0 \
			or _plug.is_picked_up():
		return
	var attach_pos := _cable_attach_point.global_position
	var diff := _plug.global_position - attach_pos
	var dist := diff.length()
	if dist > _max_rope_length:
		var dir := diff / dist
		_plug.global_position = attach_pos + dir * _max_rope_length
		var outward := dir.dot(_plug.linear_velocity)
		if outward > 0.0:
			_plug.linear_velocity -= dir * outward


func _exit_tree() -> void:
	_release_button()


func _seated_libretro() -> Libretro:
	var system := seated_system()
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


func _release_button() -> void:
	if is_instance_valid(_pressed_on):
		_pressed_on.SetJoypadExtraButtons(0, 0)
	_pressed_on = null


## The plug and its cord go with the stick.
func drop_and_free() -> void:
	_release_button()
	if is_instance_valid(_plug):
		_plug.drop()
	if is_instance_valid(_cable_instance):
		_cable_instance.queue_free()
	Vanish.free_node(self)
