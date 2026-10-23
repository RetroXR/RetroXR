## VRLever — a throw lever with a continuous 0..1 value, on a wall or a panel.
##
## VRHinge is already the whole interaction: trigger-latched grab with 0.6/0.4
## hysteresis, gated on PokeTip.is_poking() so a hand holding something cannot grab
## it, offset bookkeeping so taking hold never teleports the arm, clamped between two
## angles, and the open-palm / fist hint icon. This adds exactly two things to it.
##
## 1. DESKTOP PRESS-DRAG. VRHinge deliberately gates its pointer tracking on
##    use_xr: on desktop a press only LATCHES and the mouse WHEEL rolls the angle,
##    which is right for a lid you nudge to a position. A lever is swept, so the
##    press has to drag. The wheel still works while held, as the fine adjustment.
##
## 2. A VALUE. The angle is what the hinge knows; a lever's consumer wants 0..1.
##    value_at_min / value_at_max let the scene pick which end is zero, so a lever
##    reading right-to-left needs no sign juggling at the far end.
##
## Overriding here rather than in VRHinge on purpose: every clamshell lid, disc door,
## cartridge flap and battery cover in the project is a VRHinge, and they all want
## the wheel-only desktop behaviour they have now.
class_name VRLever
extends VRHinge

## Emitted on every change, including while dragging. A consumer that does real work
## should throttle — see TimeOfDay.min_apply_interval.
signal value_changed(value: float)

## Emitted once, on the frame the hand or the pointer lets go. For the work that
## should happen at the END of a sweep rather than throughout it — writing a
## preference to disk, say.
signal released(value: float)

## Value reported at each end of the throw. Reversed by default (min_deg = 1) so a
## lever that reads left-to-right on a wall maps left = 0 without negating anything.
@export var value_at_min: float = 1.0
@export var value_at_max: float = 0.0

var _suppress: bool = false


func _ready() -> void:
	# Connected BEFORE the base's _ready, which awaits a frame before it finishes
	# caching controllers. Nothing can emit in between, but the ordering costs
	# nothing and removes the question.
	rotation_changed.connect(_on_rotation_changed)
	super()


## Current value, derived from the target's angle rather than stored — the angle is
## the single source of truth, and the base class may move it without asking.
func get_value() -> float:
	if target == null:
		return value_at_min
	return _value_of(rad_to_deg(target.rotation.x))


## Set the value AND report it.
func set_value(v: float) -> void:
	set_rotation_deg_no_signal(_deg_of(v))
	value_changed.emit(get_value())


## Set the value without emitting — for a restore, which must position the arm
## without looking like the player just moved it.
func set_value_no_signal(v: float) -> void:
	_suppress = true
	set_rotation_deg_no_signal(_deg_of(v))
	_suppress = false


func _on_rotation_changed(deg: float) -> void:
	if not _suppress:
		value_changed.emit(_value_of(deg))


func _value_of(deg: float) -> float:
	var span: float = max_deg - min_deg
	if is_zero_approx(span):
		return value_at_min
	return lerpf(value_at_min, value_at_max, clampf((deg - min_deg) / span, 0.0, 1.0))


func _deg_of(v: float) -> float:
	var span: float = value_at_max - value_at_min
	if is_zero_approx(span):
		return min_deg
	return lerpf(min_deg, max_deg, clampf((v - value_at_min) / span, 0.0, 1.0))


## The base calls this the frame a grab ends, however it ended.
func _on_released() -> void:
	super()
	released.emit(get_value())


## Press-drag on desktop as well as in VR.
##
## Identical to VRHinge.pointer_event except that _begin_track / _track_world_point
## are not gated on use_xr. The latch still survives EXITED — a sweep is allowed to
## leave the grab box, and on a lever it usually does, because the box rides the arm
## and the hand is chasing it.
func pointer_event(event: XRToolsPointerEvent) -> void:
	match event.event_type:
		XRToolsPointerEvent.Type.ENTERED:
			_hover_pointers[event.pointer] = true
		XRToolsPointerEvent.Type.PRESSED:
			if _can_engage():
				_pointer_held = true
				_begin_track(event.position)
		XRToolsPointerEvent.Type.MOVED:
			if _pointer_held:
				_track_world_point(event.position)
		XRToolsPointerEvent.Type.RELEASED:
			_pointer_held = false
		XRToolsPointerEvent.Type.EXITED:
			_hover_pointers.erase(event.pointer)
	_update_icon()
