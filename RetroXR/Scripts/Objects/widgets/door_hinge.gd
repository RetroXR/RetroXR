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

## A door closer: an unlatched leaf nobody is moving eases shut by itself and the
## bolt drops in, as an exit door's overhead closer does.
@export var self_closing: bool = false
## The closer's speed, degrees a second; it slows over the last 10 degrees. A real
## overhead closer is SLOW: several seconds from wide open, so a door shuts behind you.
@export var closer_speed_deg: float = 12.0

## False for a push door with no latch: it never latches, however it comes home.
var has_latch: bool = true
## The door's opener (DoorKnob or DoorPushBar): a fingertip in its reach takes the
## OPENER, not the leaf, so a trigger at the knob or a hand on the bar never swings
## the door without working the latch first.
var opener: Node3D = null
## The leaf's width, how far from the hinge a pushing hand can be and still be on it.
var leaf_width: float = 0.9
## Held off by the door's own code: a desktop swing or a remote update moving it.
var closer_hold: bool = false
# Opened past close_latch_deg since the last unlatch: a door swinging home latches.
var _armed := false
# push_with: the hand walking the leaf open, and how fast it was going.
var _pusher: XRController3D = null
var _push_velocity_deg := 0.0
var _closer_wait := 0.0


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
	if not has_latch:
		_apply(min_deg, true)   # shut, and nothing holds it
		return
	super.latch_closed(rebound_from_overtravel, preserve_poke)


func set_state_remote(degrees: float, latched: bool, emit: bool = true) -> void:
	latched = latched and has_latch
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


## A hand that just pushed the crash bar through walks the leaf open: it follows the
## hand FORWARD only (a door is pushed, not pulled, from the bar side), with no button
## held, and lets go when the hand falls behind it or leaves it. What speed it had
## carries on as release momentum, so a push sends it swinging.
func push_with(ctrl: XRController3D) -> void:
	if ctrl == null or target == null:
		return
	_pusher = ctrl
	_push_velocity_deg = 0.0
	_release_angular_velocity_deg = 0.0
	_begin_track(PokeTip.tip_of(ctrl))


func is_pushing() -> bool:
	return _pusher != null


## Keep the closer off for `seconds` (a desktop swing opens it for a moment first).
func hold_closer(seconds: float) -> void:
	_closer_wait = maxf(_closer_wait, seconds)


## Whether a hand, a pointer or a fingertip is driving the leaf right now.
func is_held() -> bool:
	return _trigger_ctrl != null or _pointer_held or _poke_ctrl != null or _pusher != null


func _can_engage() -> bool:
	return _pusher == null and super._can_engage()


func _process(delta: float) -> void:
	super._process(delta)
	_step_push(delta)
	if _closer_wait > 0.0:
		_closer_wait = maxf(0.0, _closer_wait - delta)
	if _latched_closed or target == null:
		return
	var cur := rad_to_deg(target.rotation.x)
	if cur > min_deg + close_latch_deg:
		_armed = true
	elif has_latch and _armed and not is_held() and cur <= min_deg + 0.5:
		# Swung home on its own: the bolt rides the strike and drops in.
		latch_closed()


## A push door has nothing to catch it near shut: let go there, it simply stays.
func _on_released() -> void:
	if has_latch:
		super._on_released()


func _step_push(delta: float) -> void:
	if _pusher == null:
		return
	var why := ""
	var raw := NAN
	if not is_instance_valid(_pusher) or not _pusher.get_is_active() \
			or not PokeTip.is_poking(_pusher):
		why = "hand gone"
	else:
		var tip := PokeTip.tip_of(_pusher)
		var parent := target.get_parent() as Node3D
		var rel: Vector3 = parent.to_local(tip) - target.position
		var r := Vector2(rel.y, rel.z).length()
		if r > leaf_width + 0.1 or r < 0.05:
			why = "off the leaf"
		else:
			raw = _angle_at(tip, _grab_raw_prev)
			if is_nan(raw):
				why = "at the hinge"
	if why.is_empty():
		_grab_raw_prev = raw
		var cur := rad_to_deg(target.rotation.x)
		var wanted := raw + _grab_offset_deg
		if wanted < cur - 3.0:
			why = "drew back"
		elif wanted > cur:
			var next := minf(wanted, max_deg)
			_apply(next, true)
			if delta > 0.0:
				_push_velocity_deg = lerpf(_push_velocity_deg, (next - cur) / delta, 0.5)
			return
		else:
			_push_velocity_deg = lerpf(_push_velocity_deg, 0.0, 0.2)
			return
	print("[Door] push let go at %.1f deg (%s), carrying %.0f deg/s" % [
		rad_to_deg(target.rotation.x), why, _push_velocity_deg])
	_pusher = null
	_release_angular_velocity_deg = clampf(_push_velocity_deg, 0.0, poke_momentum_max_deg_per_sec)
	_push_velocity_deg = 0.0


## No spring: an unlatched door stays where it was left, unless it has a closer.
func _step_spring_open(delta: float) -> void:
	if not self_closing or closer_hold or _closer_wait > 0.0 or is_held() or target == null:
		return
	if absf(_release_angular_velocity_deg) > 1.0:
		return   # still swinging from a push: the closer takes it once it has stopped
	var cur := rad_to_deg(target.rotation.x)
	if cur <= min_deg:
		return
	var slow := 0.4 + 0.6 * clampf((cur - min_deg) / 10.0, 0.0, 1.0)
	_apply(move_toward(cur, min_deg, closer_speed_deg * slow * delta), true)


func _tip_in_activation_region(tip: Vector3) -> bool:
	if opener != null and is_instance_valid(opener) and opener.has_method("in_reach") \
			and opener.call("in_reach", tip):
		return false
	return super._tip_in_activation_region(tip)
