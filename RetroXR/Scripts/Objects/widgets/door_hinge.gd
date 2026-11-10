## DoorHinge — the leaf of a VRDoor, on VRSpringLatchedHinge's latch with no spring.
##
## A door is a latched hinge that STAYS where it is left: shut, its latch bolt holds
## it (`_can_engage` refuses a hand, the grab box is off) and only the door's knob
## lets it go (VRDoor calls open()); unlatched, a hand on the leaf (trigger, or the
## grip on the edge) or a fingertip pushing either face swings it, and it carries on
## a little after a push (poke momentum) and then stops. Nothing pulls it open.
##
## The bolt springs back in by itself: a door released within close_latch_deg of
## shut latches (the parent's _on_released), and so does one that swings home on
## its own momentum, once it has been opened past that since it was unlatched — so
## a door just let go of by its knob, still at 0°, does not snap shut again before
## it could be pulled (VRDoor decides that case when the knob comes back).
##
## The axis is the PARENT's local X (VRHinge drives `target.rotation.x`, the middle
## of a Y-X-Z Euler, so a pivot can never be rolled into a vertical axis itself):
## VRDoor builds a HingeFrame whose X is the door's vertical, and the pivot under it
## turns at identity otherwise.
class_name DoorHinge
extends VRSpringLatchedHinge

## A hand whose fingertip is in the knob's reach takes the KNOB, not the leaf, so a
## trigger at the knob never swings the door without turning the knob first.
var knob: VRKnob = null
# Opened past close_latch_deg since the last unlatch: a door swinging home latches.
var _armed := false


func _init() -> void:
	super._init()
	push_push = false
	spring_speed_deg = 0.0
	close_latch_deg = 3.0
	box_engages = true
	grip_engages = true
	# Both faces: a push moves it whichever way the fingertip travels.
	poke_torque_faces = FACE_Y_NEG | FACE_Y_POS
	poke_release_momentum = true
	poke_momentum_max_deg_per_sec = 180.0
	poke_momentum_damping_deg_per_sec2 = 240.0


func open() -> void:
	super.open()
	_armed = false


func latch_closed(rebound_from_overtravel: bool = false,
		preserve_poke: bool = false) -> void:
	_armed = false
	_release_angular_velocity_deg = 0.0
	super.latch_closed(rebound_from_overtravel, preserve_poke)


func set_state_remote(degrees: float, latched: bool, emit: bool = true) -> void:
	_armed = not latched and degrees > min_deg + close_latch_deg
	super.set_state_remote(degrees, latched, emit)


## Move the leaf as the door's own code does (a desktop swing, a remote catching
## up), telling listeners: a door inside a spawned object is synced by its hinge's
## signal, as every other articulated control is.
##
## A latched leaf is shut and is not driven: a desktop swing still easing home when
## the bolt drops in would otherwise write its last few hundredths of a degree back.
func drive_to(degrees: float) -> void:
	if _latched_closed:
		return
	_release_angular_velocity_deg = 0.0
	_apply(degrees, true)


func is_armed() -> bool:
	return _armed


## Take hold with a hand that is ALREADY holding the door's knob, without waiting
## for its trigger to be let go first (VRHinge's re-arm guard): the knob turned far
## enough hands its hand straight on, so one pull both turns and swings the door.
## That hand still has to let go before it can take the leaf again by itself.
func grab_with(ctrl: XRController3D, action: String = TRIGGER_ACTION) -> void:
	if ctrl == null or target == null or _trigger_ctrl == ctrl:
		return
	if action == GRIP_ACTION:
		_rearmed_grip[ctrl.get_instance_id()] = false
	else:
		_rearmed[ctrl.get_instance_id()] = false
	_latch(ctrl, action, PokeTip.tip_of(ctrl))


## Whether a hand, a pointer or a fingertip is driving the leaf right now.
func is_held() -> bool:
	return _trigger_ctrl != null or _pointer_held or _poke_ctrl != null


func _process(delta: float) -> void:
	super._process(delta)
	if _latched_closed or target == null:
		return
	var cur := rad_to_deg(target.rotation.x)
	if cur > min_deg + close_latch_deg:
		_armed = true
	elif _armed and not is_held() and cur <= min_deg + 0.5:
		# Swung home on its own: the bolt rides the strike and drops in.
		latch_closed()


## No spring: an unlatched door stays where it was left.
func _step_spring_open(_delta: float) -> void:
	pass


func _tip_in_activation_region(tip: Vector3) -> bool:
	if knob != null and is_instance_valid(knob) and knob.has_method("in_reach") \
			and knob.call("in_reach", tip):
		return false
	return super._tip_in_activation_region(tip)
