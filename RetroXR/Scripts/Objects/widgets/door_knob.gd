## DoorKnob — a VRDoor's knob: a VRKnob that turns EITHER way from rest, follows the
## wrist (a doorknob is twisted in the fist, not walked round with a fingertip), and
## springs back to rest when let go, as the latch spring inside a real one does.
##
## value 0.5 is rest, 0 and 1 the two ends of its turn; `turn()` is how far from rest,
## 0..1, whichever way. One cap serves both faces of the door: the knob's reach is a
## capsule along its axle (`reach`, either side of the leaf), so a hand at the knob
## on either side takes the same spindle, the way the two knobs of a real door are.
##
## On a pointer (the desktop reticle, a VR laser) a press does not latch a turn the
## wheel would then step: it asks the door to open or shut (`pointer_pressed`), which
## is what a click on a doorknob means at a desk.
class_name DoorKnob
extends VRKnob

## A press from a pointer (desktop reticle / VR laser) on the knob.
signal pointer_pressed

## Metres either side of the axle's origin (the leaf's middle) a hand can take hold.
@export var reach: float = 0.1
## Degrees a second the knob springs back to rest.
@export var return_speed_deg: float = 360.0


func _init() -> void:
	super._init()
	deg_at_zero = -60.0
	deg_at_one = 60.0
	value = 0.5
	engage_radius = 0.04
	follow_roll = true
	haptics = true
	detents = 0
	end_magnitude = 0.35


## How far the knob is turned from rest, 0..1, whichever way.
func turn() -> float:
	return absf(value - 0.5) * 2.0


## The controller turning it, or null.
func holding_ctrl() -> XRController3D:
	return _trigger_ctrl if is_instance_valid(_trigger_ctrl) else null


func is_held() -> bool:
	return holding_ctrl() != null or _pointer_held


## A fingertip in the knob's reach (either side of the door).
func in_reach(world_pos: Vector3) -> bool:
	return _engage_distance(world_pos) <= engage_radius


func _engage_distance(world_pos: Vector3) -> float:
	var z := clampf(to_local(world_pos).z, -reach, reach)
	return to_global(Vector3(0.0, 0.0, z)).distance_to(world_pos)


func _process(delta: float) -> void:
	super._process(delta)
	if is_held() or is_equal_approx(value, 0.5):
		return
	var span := absf(deg_at_one - deg_at_zero)
	var step := 1.0 if is_zero_approx(span) else return_speed_deg * delta / span
	set_value_no_signal(move_toward(value, 0.5, step))
	# Asleep it would stop half turned: stay awake until it is home.
	PokeWake.wake(self)
	_poke_idle = 0


func pointer_event(event: XRToolsPointerEvent) -> void:
	match event.event_type:
		XRToolsPointerEvent.Type.PRESSED:
			PokeWake.wake(self)
			pointer_pressed.emit()
		XRToolsPointerEvent.Type.MOVED, XRToolsPointerEvent.Type.RELEASED:
			pass
		_:
			super.pointer_event(event)
