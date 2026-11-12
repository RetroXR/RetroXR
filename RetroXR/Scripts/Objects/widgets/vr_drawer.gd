## VRDrawer — a drawer (or a flat pull-out tray) taken by its HANDLE, pulled straight out to a length and pushed back in.
##
## A VRSlider whose knob is a whole drawer. That is the point of extending it: the scene save already records every
## VRSlider's `value` (ScenePersistence, kind "slider") and netplay already sends its `value_changed` (ObjectSync), so a
## drawer's open amount is saved and synced with no code of its own. `value` is 0 shut and 1 pulled out `travel` metres
## along `axis_local` (+Z by default: out of the front).
##
## Rigging (see Scenes/Objects/furniture/nightstand.tscn):
##   • This Area3D stays FIXED on the furniture, its origin where the handle is with the drawer SHUT. Its child
##     CollisionShape3D (a BoxShape3D) is the handle's grab box and rides out with the drawer.
##   • `target` is the drawer. Make it an AnimatableBody3D (sync_to_physics on) with a floor box and wall boxes and
##     whatever rests in it is carried out and in by friction; a flat tray is the same with the floor alone.
##   • `handle_mesh` is the handle as drawn (outlined while armed, and what the desktop crosshair is held to).
##
## Interaction:
##   • A fingertip in the handle box ARMS it (green); the TRIGGER or the GRIP latches (amber) and the drawer follows the
##     hand along its runners, relative to where it was taken (taking hold never jumps it), until that button is let go,
##     wherever the hand roams. While a hand holding nothing is in the box its pickup is MUTED (VRHinge's arrangement),
##     so squeezing the handle never lifts the furniture.
##   • Let go moving, it COASTS on (`release_momentum`) against `friction`, and knocks back a little off the stops.
##   • The last `soft_close_zone` metres it eases itself shut, as a soft-close runner does.
##   • A bare fingertip pressing the drawer's FRONT (`push_face_size`, 0 = off) pushes it in; only a tip that came from
##     in front of the face pushes, so a hand reaching INTO the open drawer for something never shuts it.
##   • Desktop: the crosshair on the handle drags it with the mouse (VRSlider.mouse_drag); a VR laser press-drags.
class_name VRDrawer
extends VRSlider

signal opened
signal closed

const GRIP_ACTION := "grip"
const GRIP_ON := 0.6
const GRIP_OFF := 0.4
## A drawer that is a body follows its value over this time constant (s), on the physics tick: see _physics_process.
const FOLLOW_TAU := 0.02
## Slower than this (m/s) when let go, it just stops.
const COAST_MIN := 0.05
## The fastest a flick may send it (m/s).
const COAST_MAX := 2.0
## A push only counts from a tip that was at least this far in front of the face (m) ...
const PUSH_SLACK := 0.004
## ... and stops counting once the tip is this far behind it (the hand went past, into the drawer).
const PUSH_DEPTH := 0.04

## The drawer (or tray) the handle pulls. Moved along axis_local, in its own parent's frame.
@export var target: Node3D
## What DRAWS the drawer, when the target is a physics body: a plain Node3D (the model's drawer and pull hang from it)
## moved with the same smoothed position as the body. A synced body gets its pose written back by the physics sync a
## tick late, so with physics interpolation on, a drawer drawn from the body trailed its case by up to 13.7 mm while
## the furniture was carried (vr_drawer_tests haul/); a plain child of the case interpolates WITH it.
@export var visual: Node3D
## The handle as drawn. Optional: without it the drawer still works, with no outline and no crosshair test.
@export var handle_mesh: MeshInstance3D
## The GRIP latches too, not only the trigger (and mutes the hand's pickup in the handle box).
@export var grip_engages: bool = true
## Let go moving, it slides on.
@export var release_momentum: bool = true
## Runner friction while coasting, m/s per second.
@export var friction: float = 1.6
## Share of its speed it keeps knocking off a stop (0 = dead stop).
@export_range(0.0, 1.0) var restitution: float = 0.15
## The last metres it pulls itself shut, and how fast (m/s). 0 = off.
@export var soft_close_zone: float = 0.015
@export var soft_close_speed: float = 0.08
## The drawer front a fingertip can push in, in this node's local X (width) and Y (height), centred on
## push_face_centre. Zero = no push. The push assumes axis_local runs along local Z (a drawer's).
@export var push_face_size: Vector2 = Vector2.ZERO
@export var push_face_centre: Vector2 = Vector2.ZERO
## Where the front face is along the axis with the drawer shut, from this node's origin (the handle stands proud of
## the front, so this is usually a little negative).
@export var push_face_offset: float = -0.02

var _rearmed_grip: Dictionary = {}
## Which action the latched hand took hold with, so letting go watches that one.
var _grab_action := TRIGGER_ACTION
var _muted_pickups: Array[Node] = []
var _target_rest := Vector3.ZERO
var _target_axis := Vector3.FORWARD
var _target_rest_value := 0.0
var _rigged := false
## m/s along the axis: measured while held, spent while coasting.
var _speed := 0.0
var _coasting := false
var _easing := false
var _held_prev := false
var _prev_value := 0.0
var _last_hand: XRController3D = null
var _at_end := -1                   # 0 shut, 1 out, -1 between: the stop it rests against, for the bump
var _was_shut := true
## Per controller: true while its tip is in front of the face (a push may start), and where it was along the axis
## last frame (a push is the TIP moving in, never the face sliding out onto a still hand).
var _push_ready: Dictionary = {}
var _push_prev: Dictionary = {}
var _push_ctrl: XRController3D = null
## The frame the latch last looked at the triggers. After a gap (the widget asleep, no hand near) a button already
## down is not a press: a hand that squeezed elsewhere and carried the squeeze here must let go first.
var _trigger_frame := -10
## The target is a physics body (the drawer carrying what is in it): its pose is re-asserted every physics tick.
var _target_body := false
var _snap := false
## Where a body target is being led to, in its parent's frame (see _physics_process).
var _follow := Vector3.ZERO
var _follow_v := Vector3.ZERO
## Per controller: a press in the handle box already logged as refused (one line a press, not a frame).
var _refusal_logged: Dictionary = {}
var _armed_logged := false


func _init() -> void:
	super._init()
	# A drawer is always latched (trigger or grip), never grabbed by brushing past it, and continuous.
	require_trigger = true
	mouse_drag = true
	steps = 0
	axis_local = Vector3(0, 0, 1)
	travel = 0.3


func _ready() -> void:
	steps = 0
	if handle_mesh != null:
		_knob = handle_mesh
	if target != null:
		var parent := target.get_parent() as Node3D
		var world_axis := (global_basis * axis_local.normalized()).normalized()
		_target_axis = (parent.global_basis.inverse() * world_axis).normalized() if parent else world_axis
		_target_rest = target.position
		_target_rest_value = value
		_target_body = target is PhysicsBody3D
		_follow = _target_rest
	else:
		push_warning("[VRDrawer] %s: no target; the handle moves nothing" % name)
	if push_face_size != Vector2.ZERO and absf(axis_local.normalized().z) < 0.99:
		push_warning("[VRDrawer] %s: the front push needs axis_local along Z; it is off" % name)
		push_face_size = Vector2.ZERO
	_rigged = true
	set_physics_process(_target_body)
	_prev_value = value
	_was_shut = value <= 0.0
	value_changed.connect(_on_value_changed)
	await super._ready()
	print("[VRDrawer] %s: %.0f mm of travel at %.2f, target %s, grip %s, push %s" % [name, travel * 1000.0, value,
		target.name if target else "none", grip_engages, push_face_size != Vector2.ZERO])


## The handle as drawn, given after _ready by an owner whose model builds it later (a child is ready before its
## parent, so a model's part is not there yet when this node readies).
func set_handle_mesh(mesh: MeshInstance3D) -> void:
	handle_mesh = mesh
	_knob = mesh
	if _outline != null:
		_outline.set_source(mesh)


## How far out it is, in metres.
func open_distance() -> float:
	return value * travel


func is_held() -> bool:
	return _engaged_ctrl != null or _pointer_engaged or _mouse_held or _push_ctrl != null


## Coasting or easing shut by itself.
func is_moving() -> bool:
	return _coasting or _easing


func set_value(v: float) -> void:
	_stop_moving()
	super.set_value(v)


func set_value_no_signal(v: float) -> void:
	_stop_moving()
	_snap = true
	super.set_value_no_signal(v)
	_snap = false
	_was_shut = value <= 0.0


func _process(delta: float) -> void:
	super._process(delta)
	if not _controllers.is_empty() and (not _muted_pickups.is_empty()
			or PokeTip.any_tip_within(_controllers, _reach_point(), PokeTip.WIDGET_NEAR)):
		_sync_pickup_mutes()
		if push_face_size != Vector2.ZERO:
			_process_push()
	var held := is_held()
	if held:
		if delta > 0.0:
			var measured := (value - _prev_value) * travel / delta
			_speed = lerpf(_speed, measured, 0.5)
		_coasting = false
		_easing = false
	elif _held_prev:
		_let_go()
	elif _coasting:
		_coast(delta)
	elif _easing or (soft_close_zone > 0.0 and value > 0.0 and open_distance() <= soft_close_zone):
		_ease_shut(delta)
	_bump_at_stops(held)
	_held_prev = held
	_prev_value = value


## A drawer that is a BODY is moved here, on the physics tick, and nowhere else (but a snap):
##   • A body moved with sync_to_physics keeps its OWN physics pose, so when the furniture under it moves (settles, is
##     carried) it is left where it was and slips off its runners (measured: 1.75 mm from the nightstand settling).
##     Re-asserting the pose it should have every tick keeps it on them.
##   • The hand moves `value` once a RENDER frame (60-90 Hz) and physics ticks at 90: set straight from _process the
##     drawer stood still one tick and jumped the next, and what rests in it slipped (a box rode 162 mm of a 200 mm pull).
##     Following the value over FOLLOW_TAU spreads each step over the ticks between.
func _physics_process(delta: float) -> void:
	if not _target_body or not is_instance_valid(target):
		return
	var want := _target_want()
	if _follow.distance_to(want) < 0.0001 and _follow_v.length() < 0.001:
		_follow = want
		_follow_v = Vector3.ZERO
	else:
		# Critically damped: the drawer's SPEED changes smoothly too. A first-order follow still changed speed in a
		# step at every render frame, which slipped what was in it on 60 fps against 90 Hz physics (223 mm of 250).
		var w := 1.0 / FOLLOW_TAU
		_follow_v += ((want - _follow) * w * w - _follow_v * 2.0 * w) * delta
		_follow += _follow_v * delta
	# Every tick, moving or not: the furniture under it may have moved. And never read back target.position as where
	# the drawer is: a synced body hands the node its PREVIOUS physics pose until the tick has run.
	target.position = _follow
	if is_instance_valid(visual):
		visual.position = _follow


func _target_want() -> Vector3:
	return _target_rest + _target_axis * (value - _target_rest_value) * travel


func _reach_point() -> Vector3:
	return _handle_box_world().origin if is_instance_valid(_knob_collision) else global_position


func _keep_awake() -> bool:
	return _coasting or _easing or _push_ctrl != null or not _muted_pickups.is_empty()


## Value 0 at this node's origin (the handle with the drawer shut), not VRSlider's mid-travel.
func _raw_value_at(world_pos: Vector3) -> float:
	if travel <= 0.0:
		return value
	return to_local(world_pos).dot(axis_local.normalized()) / travel


## The handle box, not the knob mesh's bounds: the box is what the scene sized for a hand.
func _tip_in_box(tip: Vector3) -> bool:
	if not is_instance_valid(_knob_collision):
		return super._tip_in_box(tip)
	var box := _knob_collision.shape as BoxShape3D
	if box == null:
		return super._tip_in_box(tip)
	var local := _handle_box_world().affine_inverse() * tip
	var half := box.size * 0.5 + Vector3.ONE * interact_margin
	return absf(local.x) <= half.x and absf(local.y) <= half.y and absf(local.z) <= half.z


func _handle_box_world() -> Transform3D:
	return _knob_collision.global_transform


## VRSlider's trigger latch, with the grip as a second way to take hold, and taking hold RELATIVE to where the hand is
## (the plain slider's trigger mode tracks absolutely, which would jump a drawer to the hand).
func _process_trigger_mode() -> void:
	var frame := Engine.get_process_frames()
	var fresh := frame - _trigger_frame > 1
	_trigger_frame = frame
	for ctrl in _controllers:
		if ctrl == null:
			continue
		var id := ctrl.get_instance_id()
		if ctrl.get_float(TRIGGER_ACTION) < TRIGGER_OFF:
			_rearmed[id] = true
		elif fresh:
			_rearmed[id] = false
		if ctrl.get_float(GRIP_ACTION) < GRIP_OFF:
			_rearmed_grip[id] = true
		elif fresh:
			_rearmed_grip[id] = false
	if _engaged_ctrl != null:
		var off := TRIGGER_OFF if _grab_action == TRIGGER_ACTION else GRIP_OFF
		if not is_instance_valid(_engaged_ctrl) or not _engaged_ctrl.get_is_active() \
				or _engaged_ctrl.get_float(_grab_action) < off:
			_engaged_ctrl = null
		else:
			_track_world_point(PokeTip.tip_of(_engaged_ctrl))
			_armed = true
			return
	var ctrl := _hovering_ctrl()
	_armed = ctrl != null
	if _armed != _armed_logged:
		_armed_logged = _armed
		print("[VRDrawer] %s: a fingertip %s the handle at %.2f" % [name, "is on" if _armed else "left", value])
	if ctrl == null:
		return
	var id := ctrl.get_instance_id()
	var trigger := ctrl.get_float(TRIGGER_ACTION) > TRIGGER_ON
	var grip := grip_engages and ctrl.get_float(GRIP_ACTION) > GRIP_ON
	if trigger and _rearmed.get(id, false):
		_rearmed[id] = false
		_latch(ctrl, TRIGGER_ACTION)
	elif grip and _rearmed_grip.get(id, false):
		_rearmed_grip[id] = false
		_latch(ctrl, GRIP_ACTION)
	elif trigger or grip:
		# Pressed in the box and not taken: say why, once a press (a squeeze carried in, never let go here).
		if not _refusal_logged.get(id, false):
			_refusal_logged[id] = true
			print("[VRDrawer] %s: %s pressed on the handle but not taken: it was already down when the hand came (let go and press again)" % [
				name, "trigger" if trigger else "grip"])
		return
	_refusal_logged[id] = false


## A laser or the desktop crosshair on the handle: logged on press and release (VRSlider does the work).
func pointer_event(event: XRToolsPointerEvent) -> void:
	if event.event_type == XRToolsPointerEvent.Type.PRESSED:
		print("[VRDrawer] %s: pointer pressed at %s (%.2f, box %s)" % [name, event.position, value,
			"hit" if _tip_in_box(event.position) else "MISSED by %.0f mm" % (_box_gap(event.position) * 1000.0)])
	elif event.event_type == XRToolsPointerEvent.Type.RELEASED:
		print("[VRDrawer] %s: pointer released at %.2f" % [name, value])
	super.pointer_event(event)


## Where the physics engine has this handle and its drawer, against the nodes: mm of difference for the area, the handle
## box and the drawer body. Asked after the furniture is put down; all three must be ~0.
func collision_report() -> Dictionary:
	var out := {"area": 0.0, "box": 0.0, "body": 0.0, "node": 0.0}
	var a_srv := PhysicsServer3D.area_get_transform(get_rid())
	out["area"] = a_srv.origin.distance_to(global_position) * 1000.0
	if is_instance_valid(_knob_collision) and PhysicsServer3D.area_get_shape_count(get_rid()) > 0:
		var s_srv := a_srv * PhysicsServer3D.area_get_shape_transform(get_rid(), 0)
		out["box"] = s_srv.origin.distance_to(_knob_collision.global_position) * 1000.0
	if _target_body and is_instance_valid(target):
		var b_srv := PhysicsServer3D.body_get_state((target as PhysicsBody3D).get_rid(),
			PhysicsServer3D.BODY_STATE_TRANSFORM) as Transform3D
		# Against where it SHOULD be (its parent, at the open amount it is drawn at), never the body's own node: a synced
		# body's node reads back the physics pose, so the two can be wrong together.
		var parent := target.get_parent() as Node3D
		var want := parent.global_transform * _follow if parent != null else _follow
		out["body"] = b_srv.origin.distance_to(want) * 1000.0
		out["node"] = target.global_position.distance_to(want) * 1000.0
	return out


func _box_gap(world: Vector3) -> float:
	if not is_instance_valid(_knob_collision) or not _knob_collision.shape is BoxShape3D:
		return 0.0
	var local := _handle_box_world().affine_inverse() * world
	var half := (_knob_collision.shape as BoxShape3D).size * 0.5
	return (local - local.clamp(-half, half)).length()


func _latch(ctrl: XRController3D, action: String) -> void:
	_stop_moving()
	_engaged_ctrl = ctrl
	_grab_action = action
	_last_hand = ctrl
	_speed = 0.0
	_begin_track(PokeTip.tip_of(ctrl))
	Haptics.click(ctrl, true, &"vr_drawer")
	print("[VRDrawer] %s: taken by the %s at %.2f" % [name, action, value])


func _let_go() -> void:
	var speed := clampf(_speed, -COAST_MAX, COAST_MAX)
	var why := last_input
	if release_momentum and absf(speed) >= COAST_MIN and not has_meta(&"net_restore_in_progress"):
		_speed = speed
		_coasting = true
		print("[VRDrawer] %s: let go at %.2f (%s), sliding %.2f m/s" % [name, value, why, speed])
	else:
		_speed = 0.0
		print("[VRDrawer] %s: let go at %.2f (%s)" % [name, value, why])


func _coast(delta: float) -> void:
	var before := _speed
	_speed -= signf(_speed) * friction * delta
	if signf(_speed) != signf(before) or absf(_speed) < 0.001:
		_coasting = false
		_speed = 0.0
		print("[VRDrawer] %s: came to rest at %.2f" % [name, value])
		return
	var raw := value + _speed * delta / maxf(travel, 0.0001)
	if raw <= 0.0 or raw >= 1.0:
		_speed = -_speed * restitution
		if absf(_speed) < COAST_MIN:
			_coasting = false
			_speed = 0.0
			print("[VRDrawer] %s: ran to the %s stop" % [name, "shut" if raw <= 0.0 else "open"])
	last_input = "coast"
	_set_from_raw(raw)


func _ease_shut(delta: float) -> void:
	if not _easing:
		_easing = true
		print("[VRDrawer] %s: easing shut from %.1f mm" % [name, open_distance() * 1000.0])
	last_input = "soft_close"
	_set_from_raw(value - soft_close_speed * delta / maxf(travel, 0.0001))
	if value <= 0.0:
		_easing = false


func _stop_moving() -> void:
	_coasting = false
	_easing = false
	_speed = 0.0


## A tick in the hand that is on it as the drawer meets a stop.
func _bump_at_stops(held: bool) -> void:
	var end := 0 if value <= 0.0 else (1 if value >= 1.0 else -1)
	if end != _at_end and end != -1 and held:
		Haptics.click(_engaged_ctrl if _engaged_ctrl != null else _push_ctrl, true, &"vr_drawer")
	_at_end = end


## The front push: the face stands at push_face_offset + value * travel along the axis.
func _process_push() -> void:
	var axis := axis_local.normalized()
	var half := push_face_size * 0.5
	var pushing: XRController3D = null
	for ctrl in _controllers:
		if ctrl == _engaged_ctrl or not _qualified(ctrl):
			_push_ready.erase(ctrl.get_instance_id() if ctrl else 0)
			continue
		var id := ctrl.get_instance_id()
		var local := to_local(PokeTip.tip_of(ctrl))
		var face := push_face_offset + value * travel
		var a := local.dot(axis)
		var on_face := absf(local.x - push_face_centre.x) <= half.x and absf(local.y - push_face_centre.y) <= half.y
		var prev: float = _push_prev.get(id, a)
		_push_prev[id] = a
		if not on_face or a < face - PUSH_DEPTH:
			_push_ready[id] = false
			continue
		if a > face + PUSH_SLACK:
			_push_ready[id] = true
			continue
		if _push_ready.get(id, false) and a < face and a < prev - 0.0001:
			pushing = ctrl
			_stop_moving()
			last_input = "hand"
			_set_from_raw((a - push_face_offset) / maxf(travel, 0.0001))
	if pushing != _push_ctrl:
		if pushing != null:
			print("[VRDrawer] %s: pushed in by a fingertip from %.2f" % [name, value])
		_push_ctrl = pushing


## VRHinge._sync_pickup_mutes: a hand holding nothing with its tip in the handle box (or latched on it) has its pickup
## switched off, so the grip works the drawer INSTEAD of picking up the furniture; it is handed back as the tip leaves.
func _sync_pickup_mutes() -> void:
	var want: Array[Node] = []
	if grip_engages:
		for ctrl in _controllers:
			if not is_instance_valid(ctrl) or not ctrl.get_is_active():
				continue
			if ctrl != _engaged_ctrl and not (PokeTip.is_poking(ctrl) and _tip_in_box(PokeTip.tip_of(ctrl))):
				continue
			var pickup := ctrl.get_node_or_null("FunctionPickup")
			if pickup != null:
				want.append(pickup)
	for pickup in _muted_pickups:
		if is_instance_valid(pickup) and not want.has(pickup):
			pickup.set("enabled", true)
	for pickup in want:
		pickup.set("enabled", false)
	_muted_pickups = want


func _exit_tree() -> void:
	for pickup in _muted_pickups:
		if is_instance_valid(pickup):
			pickup.set("enabled", true)
	_muted_pickups.clear()


## The drawer moves, not a knob: the target along its parent's axis, the handle box along ours.
func _update_knob() -> void:
	if not _rigged:
		return
	if is_instance_valid(_knob_collision):
		_knob_collision.transform = Transform3D(_knob_collision_rest.basis,
			_knob_collision_rest.origin + axis_local.normalized() * (value - _knob_collision_value) * travel)
	# A body follows on the physics tick (_physics_process); it is put straight there only when it must not slide:
	# before it is rigged in the tree, on a restore or a set_value_no_signal (what was saved in it is laid back where
	# the drawer WILL be, so a drawer sliding out under it would tip it over).
	if is_instance_valid(target) and (not _target_body or _snap or has_meta(&"net_restore_in_progress")
			or not target.is_inside_tree()):
		# The follow is led straight there too, so _physics_process does not ease it back from where it was. (A synced
		# body reads its PREVIOUS pose until the tick has run; it is there after one.)
		_follow = _target_want()
		_follow_v = Vector3.ZERO
		target.position = _follow
		if _target_body and is_instance_valid(visual):
			visual.position = _follow
			visual.reset_physics_interpolation()


func _on_value_changed(v: float) -> void:
	var shut := v <= 0.0
	if shut == _was_shut:
		return
	_was_shut = shut
	if shut:
		closed.emit()
	else:
		opened.emit()
