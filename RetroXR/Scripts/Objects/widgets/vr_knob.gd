## VRKnob — a physical, trigger-latched rotary control: a cap the player grabs and
## twists about its own axle, reporting a normalised 0..1 value.
##
## The two halves of this already existed separately. VRHinge is grab-and-twist and
## owns the angle maths — the rest-frame measurement and the unwrap, both of which
## are load-bearing and are lifted here verbatim in spirit. VRSlider owns the 0..1
## `value_changed` contract that every volume control in the project speaks, so a
## knob emitting anything else would need a translator at each end. This is the two
## joined: a hinge's grip, a slider's signal.
##
## Interaction (VR + desktop), the same model as VRHinge and VRSlider:
##   • HOVER — a controller tip within engage_radius, or the desktop reticle over
##     the grab box, shows a floating OPEN-HAND icon ("grab here").
##   • HELD  — pull the TRIGGER (VR) / press the reticle (desktop) to LATCH; the
##     icon becomes a FIST and the cap turns with the hand. Once latched the hand
##     need NOT stay in the grab box. On desktop the mouse WHEEL then steps the
##     value, which is finer than dragging a ray around a 20 mm cap.
##
## TRIGGER ONLY, and there is deliberately no `grip_engages` here. Grip is how
## XRToolsFunctionPickup takes hold, and a speaker cabinet IS a pickable — so a
## grip-latched knob would mean one squeeze both turned the volume up and lifted the
## whole box off the desk. VRHinge offers the grip as an opt-in for hardware nobody
## ever picks up; nothing this knob goes on qualifies.
##
## The axle is the target's local **Z**, and that is forced rather than chosen.
## Node3D Euler order is YXZ, so the rotation composes as Ry * Rx * Rz: only the Z
## term is INNERMOST, i.e. only Z turns the node about its own axis. Driving
## rotation.y on a cap that had been laid over to face out of a panel would have
## spun it about the panel's up axis instead — the cap would have swung like a door
## rather than turned like a knob.
##
## So the target is a pivot whose local Z already points out of the panel, and the
## cap mesh is its CHILD, carrying whatever rotation a CylinderMesh needs (Y-aligned,
## so a 90° turn about X) to lie along that axle. The pivot itself stays at identity
## on a front-facing panel.
##
## Three ways a hand turns it, chosen per knob:
##   • ROUND THE AXLE (the default) — the fingertip walks round the cap and the cap
##     follows its angle. Right for a dial on a panel, whose whole face is in reach.
##   • follow_roll — the controller's roll about the axle. A wand twisted in the fist.
##   • rim_drag — a straight drag along the rim. A THUMBWHEEL: only a sliver of rim
##     shows through a shell's edge and the axle is buried inside it, so a hand can
##     neither circle it nor roll round it. Measured as an angle, a straight swipe
##     from the rim can never pass 90° (atan of distance over an 8 mm radius) and
##     turns 7° per millimetre near the rim but next to nothing a few cm out. Rim
##     drag turns the cap by the distance moved along the rim's tangent instead,
##     geared by rim_travel, so a thumb-length swipe covers the sweep evenly.
##
## Haptics (opt-in, `haptics`): a click as the trigger latches and lets go, a light
## tick per detent crossed, a firm bump on reaching either end, and an optional
## stronger detent at the middle (a contrast wheel's "normal"). Each tick is ONE
## short event: the rumble manager holds the motor ~0.1 s for every frame an event
## lives, so anything longer smears a fast swipe into a buzz (haptics.gd).
##
## Attach to an Area3D with a child CollisionShape3D covering the cap (the desktop
## reticle ray hits this; VR engages on tip proximity to the Area origin).
class_name VRKnob
extends Area3D

signal value_changed(value: float)
## A hand-driven turn was felt: `magnitude` is the pulse sent (detent, centre or end
## stop). Emitted only while a controller holds the knob, as the pulse is.
signal detent_felt(magnitude: float)

const POINTABLE_LAYER := 1 << 20
## Analog trigger action, read as a float — same contract as VRButton/VRSlider/VRHinge.
const TRIGGER_ACTION := "trigger"
const TRIGGER_ON := 0.6   # trigger float that latches the knob
const TRIGGER_OFF := 0.4  # trigger float that releases it (hysteresis)
const ICON_HOVER := 0xF256   # Nerd Font: open palm — "grab here"
const ICON_HELD := 0xF255    # Nerd Font: closed fist — "holding"
const SYMBOL_FONT_PATH := "res://fonts/SymbolsNerdFont-Regular.ttf"
## Child adopted as the pivot when `target` is unset — see the note there.
const PIVOT_NAME := "KnobPivot"
## Haptics: one rumble key for every knob (one hand turns one knob at a time).
const HAPTIC_KEY := &"vr_knob"
const HAPTIC_MS := 10
## Detent ticks closer together than this are dropped, so a fast swipe stays a
## run of ticks rather than a buzz. End stops and the centre are never dropped.
const DETENT_MIN_GAP_MS := 30

## The pivot this knob turns, about its own local Z. Give it the cap mesh as a child
## rather than pointing this at the mesh itself — see the axle note above.
##
## Leave it unset and a child named `PIVOT_NAME` is used. That is the normal case,
## because an exported node reference pointing DOWN at a child does not survive
## scene instantiation: it arrives null, silently, and the knob then reads correct
## values while the cap never moves. Every other exported target in this project
## points at "..", which already exists by the time it is resolved.
@export var target: Node3D
## The cap angle about its local Z at value 0 and at value 1, in degrees. The pair
## are named by their VALUE rather than as min/max because which way round they go is
## the whole point: a positive rotation about +Z is counter-clockwise seen from the
## front, so a knob authored low-to-high would turn the wrong way — you would wind a
## volume pot anti-clockwise to make it louder. The defaults are the 270° sweep of a
## real pot, running clockwise.
@export var deg_at_zero: float = 135.0
@export var deg_at_one: float = -135.0
## Controller tip distance (m) that engages the cap. Smaller than a hinge's: a knob
## is a 20 mm part and a generous sphere would swallow the whole front panel.
@export var engage_radius: float = 0.03
## Desktop: fraction of full travel the mouse wheel steps per notch while held.
@export var wheel_step: float = 0.05
## Icon glyph height, roughly, in metres.
@export var icon_size: float = 0.024
## Starting position, 0..1. Applied without emitting in _ready — assigning this at
## runtime moves nothing and tells nobody; use set_value / set_value_no_signal.
@export var value: float = 0.75
## VR: follow the latched controller's ROLL about the axle, 1:1, instead of where its
## tip sits around it. For a part you twist in your fist, like a blind's tilt wand: a
## rod a centimeter thick is turned by rolling the wrist, and the hand hardly moves
## round it, so the tip's angle about the axle tells nothing. A dial on a panel keeps
## the default, where the fingertip walks round the cap.
@export var follow_roll: bool = false
## VR: where along the knob's local Y a hand can take hold, from .x to .y (metres), as
## a capsule of engage_radius round that line. Zero keeps the ball round the origin a
## panel knob uses; a wand sets it to its length, so it can be taken anywhere on it.
@export var engage_span: Vector2 = Vector2.ZERO
## VR (hand and laser): turn by dragging ALONG THE RIM rather than round the axle —
## for a thumbwheel showing through a shell's edge (see the note at the top). The
## rim is where the knob's CollisionShape3D sits off the axle, so the box must be
## put over the rim showing (the handheld model scripts do); a box on the axle
## falls back to where the hand first takes hold.
@export var rim_drag: bool = false
## rim_drag: metres of drag along the rim for the whole sweep, deg_at_zero to
## deg_at_one. Independent of the sweep's degrees, so a 270° wheel and a 153° one
## take the same swipe.
@export var rim_travel: float = 0.04

@export_group("Haptics")
## Rumble the holding controller: latch/release clicks, detents, end stops.
@export var haptics: bool = false
## Detents across the sweep: a tick each time the value passes k / detents. 0: none.
@export var detents: int = 0
@export_range(0.0, 1.0) var detent_magnitude: float = 0.2
## The bump on arriving at either end. 0: none.
@export_range(0.0, 1.0) var end_magnitude: float = 0.5
## The detent at value 0.5 (needs an even `detents`), felt harder. 0: as any other.
@export_range(0.0, 1.0) var center_magnitude: float = 0.0
@export_group("")

var _trigger_ctrl: XRController3D = null   # latched controller (trigger held)
var _pointer_ctrl: XRController3D = null   # the controller behind a held laser
# rim_drag: the direction the rim moves as the angle grows (unit, rest-frame XY),
# and the hand's last rest-frame position.
var _rim_tangent := Vector2.UP
var _rim_prev := Vector3.ZERO
var _last_tick_ms := -DETENT_MIN_GAP_MS
# follow_roll: which controller axis (0 = X, 2 = Z) is measured, chosen at grab time as
# the one lying flattest across the axle and kept for the whole twist, so the reading
# never swaps reference halfway through.
var _roll_axis := 0
# Drag bookkeeping: how far the cap sat from the angle the hand implied when it took
# hold, and the last raw hand angle (the unwrap reference).
var _grab_offset_deg: float = 0.0
var _grab_raw_prev: float = 0.0
# Controller instance ids whose trigger has dropped since they last latched.
var _rearmed: Dictionary = {}
var _pointer_held := false               # desktop pointer latched
## The pointers on this (a laser per hand, or the desktop reticle). Hover is
## any of them, so one leaving does not unlight what the other is still on.
var _hover_pointers: Dictionary = {}
var _pointer_hover: bool:              # a pointer over the grab box
	get: return not _hover_pointers.is_empty()
var _controllers: Array[XRController3D] = []
var _icon: Label3D = null
# Frames idle so far (PokeWake.tick).
var _poke_idle := 0


# The scene save finds every control it records through this group (one
# list, not a walk of each object's subtree: ScenePersistence.CONTROL_GROUP).
func _init() -> void:
	add_to_group(ScenePersistence.CONTROL_GROUP)


func _ready() -> void:
	collision_layer |= POINTABLE_LAYER
	PokeWake.ensure(self)
	if target == null:
		target = get_node_or_null(PIVOT_NAME) as Node3D
	if target == null:
		push_warning("[VRKnob] %s has no pivot: the value will move but the cap will not"
			% get_path())
	_build_icon()
	set_value_no_signal(value)
	await get_tree().process_frame
	# Removed during that frame (a preview thrown away, a room change): get_tree() is null now.
	if not is_inside_tree():
		return
	for node in get_tree().root.find_children("*", "XRController3D", true, false):
		_controllers.append(node as XRController3D)


## Turn the cap and tell everyone — for an owner driving the knob from something
## other than a hand on it.
func set_value(v: float) -> void:
	_apply_value(v, true)


## Turn the cap and stay quiet — restore and populate use this.
func set_value_no_signal(v: float) -> void:
	_apply_value(v, false)


func get_value() -> float:
	return value


func _process(_delta: float) -> void:
	# A hand nowhere near the cap is asked nothing; a latched hand keeps driving
	# the knob wherever it roams.
	if _trigger_ctrl == null \
			and not PokeTip.any_tip_within(_controllers, global_position, PokeTip.WIDGET_NEAR):
		_update_icon()
		# Idle long enough, the knob sleeps until PokeWake finds a tip in reach.
		_poke_idle = PokeWake.tick(self, _pointer_held or _pointer_hover, _poke_idle)
		return
	_poke_idle = 0
	# A trigger already down cannot grab control after control as the hand sweeps
	# across a panel — it has to fall below TRIGGER_OFF first. Same re-arm guard
	# VRSlider and VRHinge use.
	for ctrl in _controllers:
		if ctrl == null:
			continue
		if ctrl.get_float(TRIGGER_ACTION) < TRIGGER_OFF:
			_rearmed[ctrl.get_instance_id()] = true
	# VR: a latched controller drives the knob until it lets the trigger go, however
	# far the hand roams from the cap.
	if _trigger_ctrl != null:
		if not is_instance_valid(_trigger_ctrl) or not _trigger_ctrl.get_is_active() \
				or _trigger_ctrl.get_float(TRIGGER_ACTION) < TRIGGER_OFF:
			if haptics and is_instance_valid(_trigger_ctrl):
				Haptics.click(_trigger_ctrl, false, HAPTIC_KEY)
			_trigger_ctrl = null
		elif follow_roll:
			_track_angle(_roll_at(_trigger_ctrl, _grab_raw_prev))
		elif rim_drag:
			_track_rim(PokeTip.tip_of(_trigger_ctrl))
		else:
			_track_world_point(PokeTip.tip_of(_trigger_ctrl))
	elif not _pointer_held:
		# Latch a hovering hand that pulls the trigger. A hand already holding
		# something is skipped, so firing a held object's action never turns a knob
		# as a side effect.
		for ctrl in _controllers:
			if ctrl == null or not ctrl.get_is_active() or not PokeTip.is_poking(ctrl):
				continue
			var id := ctrl.get_instance_id()
			var tip: Vector3 = PokeTip.tip_of(ctrl)
			if _rearmed.get(id, false) \
					and _engage_distance(tip) <= engage_radius \
					and ctrl.get_float(TRIGGER_ACTION) > TRIGGER_ON:
				_rearmed[id] = false
				_trigger_ctrl = ctrl
				if follow_roll:
					_begin_roll(ctrl)
				elif rim_drag:
					_begin_rim(tip)
				else:
					_begin_track(tip)
				if haptics:
					Haptics.click(ctrl, true, HAPTIC_KEY)
				break
	_update_icon()


## Desktop reticle / VR laser support (same contract as VRButton/VRSlider/VRHinge).
## Press latches; the latch holds through MOVED even if the ray leaves the cap, and
## only RELEASED lets go — EXITED just clears the hover highlight, never the drag.
func pointer_event(event: XRToolsPointerEvent) -> void:
	# A laser on it needs the hover hint kept every frame.
	PokeWake.wake(self)
	var vr := get_viewport().use_xr
	match event.event_type:
		XRToolsPointerEvent.Type.ENTERED:
			_hover_pointers[event.pointer] = true
		XRToolsPointerEvent.Type.PRESSED:
			_pointer_held = true
			# Null for the desktop reticle, which must not rumble.
			_pointer_ctrl = Haptics.controller_of(event.pointer)
			if vr:
				if rim_drag:
					_begin_rim(event.position)
				else:
					_begin_track(event.position)
			if haptics:
				Haptics.click(_pointer_ctrl, true, HAPTIC_KEY)
		XRToolsPointerEvent.Type.MOVED:
			if _pointer_held and vr:
				if rim_drag:
					_track_rim(event.position)
				else:
					_track_world_point(event.position)
		XRToolsPointerEvent.Type.RELEASED:
			if _pointer_held and haptics:
				Haptics.click(_pointer_ctrl, false, HAPTIC_KEY)
			_pointer_held = false
			_pointer_ctrl = null
		XRToolsPointerEvent.Type.EXITED:
			_hover_pointers.erase(event.pointer)
			# NB: keep _pointer_held — a drag is allowed to leave the cap.
	_update_icon()


## Desktop: while the cap is held, the mouse wheel steps the value. Gated on
## _pointer_held so other wheel consumers only see the event when no knob is grabbed.
func _unhandled_input(event: InputEvent) -> void:
	if not _pointer_held or target == null:
		return
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		set_value(value + wheel_step)
	elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		set_value(value - wheel_step)
	else:
		return
	get_viewport().set_input_as_handled()


## Angle about the axle implied by a world point, or NAN where it is undefined.
##
## Measured in the CAP'S OWN rest frame rather than the parent's, for the reason
## VRHinge records: a cap authored with a yaw of its own would otherwise report an
## angle of the opposite sign to its rotation and track the hand backwards. Rest
## frame = the pivot's basis with the knob rotation taken out; Node3D Euler order is
## YXZ, so dropping the Z term leaves Ry * Rx.
##
## Rotation about +Z carries +X toward +Y, hence atan2(y, x).
##
## atan2 wraps at ±180°, so near a limit a tiny cross-axis jitter can flip the sign
## and snap the knob to the opposite end. `near_deg` unwraps onto the branch nearest
## a reference angle, keeping the twist continuous end to end.
func _angle_at(world_pos: Vector3, near_deg: float) -> float:
	var rel := _rest_local(world_pos)
	if not rel.is_finite() or Vector2(rel.x, rel.y).length() < 0.001:
		return NAN   # hand on the axle — angle undefined
	var deg := rad_to_deg(atan2(rel.y, rel.x))
	while deg - near_deg > 180.0:
		deg -= 360.0
	while deg - near_deg < -180.0:
		deg += 360.0
	return deg


## Take hold WITHOUT moving the cap. The grab box sits on the knob, so the angle a
## hand implies at the moment it grabs is wherever it happens to be around the axle
## and has nothing to do with where the cap is. Driving the cap straight to it would
## jump the volume on contact — a trigger tap near the knob would slam it to one end.
## Remember the difference instead and carry it through the twist.
func _begin_track(world_pos: Vector3) -> void:
	if target == null:
		return
	var cur := rad_to_deg(target.rotation.z)
	var raw := _angle_at(world_pos, cur)
	_grab_offset_deg = 0.0 if is_nan(raw) else cur - raw
	_grab_raw_prev = cur if is_nan(raw) else raw


## A world point in the cap's rest frame (see _angle_at): Z the axle, X and Y across
## it, the origin on the axle. Vector3.INF when there is no pivot to measure from.
func _rest_local(world_pos: Vector3) -> Vector3:
	if target == null:
		return Vector3.INF
	var parent := target.get_parent() as Node3D
	if parent == null:
		return Vector3.INF
	var rest := Basis.from_euler(Vector3(target.rotation.x, target.rotation.y, 0.0))
	return rest.inverse() * (parent.to_local(world_pos) - target.position)


## rim_drag: take hold without moving the cap. The rim is where the grab box sits
## off the axle -- the sliver a shell shows -- and the drag that turns the cap is
## along that rim's tangent: Z x radial, the way a rim point goes as the angle grows
## (rotation about +Z carries +X toward +Y). Fixed for the whole drag, so a hand
## wandering off the rim keeps turning the wheel the same way.
func _begin_rim(world_pos: Vector3) -> void:
	var at := _rest_local(world_pos)
	if not at.is_finite():
		return
	var radial := Vector2.ZERO
	# The first box, whatever its name: one built in code has a generated one.
	for child in get_children():
		if child is CollisionShape3D:
			var b := _rest_local((child as Node3D).global_position)
			radial = Vector2(b.x, b.y)
			break
	if radial.length() < 0.001:
		radial = Vector2(at.x, at.y)   # a box on the axle: the rim is where the hand is
	if radial.length() < 0.001:
		radial = Vector2.RIGHT
	radial = radial.normalized()
	_rim_tangent = Vector2(-radial.y, radial.x)
	_rim_prev = at


## rim_drag: turn by how far the hand moved along the rim since the last frame,
## geared so rim_travel is the whole sweep. Incremental against the CAP, which is
## clamped, so pushing past an end and coming back turns at once with no dead travel.
func _track_rim(world_pos: Vector3) -> void:
	var at := _rest_local(world_pos)
	if not at.is_finite() or target == null or rim_travel <= 0.0:
		return
	var along := Vector2(at.x - _rim_prev.x, at.y - _rim_prev.y).dot(_rim_tangent)
	_rim_prev = at
	if is_zero_approx(along):
		return
	var span := absf(deg_at_one - deg_at_zero)
	_apply_deg(rad_to_deg(target.rotation.z) + along * span / rim_travel, true)


## How far a hand is from where it can take hold: the origin, or with engage_span the
## nearest point of that stretch of the knob's local Y.
func _engage_distance(world_pos: Vector3) -> float:
	if engage_span == Vector2.ZERO:
		return global_position.distance_to(world_pos)
	var y := clampf(to_local(world_pos).y, minf(engage_span.x, engage_span.y), maxf(engage_span.x, engage_span.y))
	return to_global(Vector3(0.0, y, 0.0)).distance_to(world_pos)


## follow_roll: the controller's turn about the axle, in degrees in the cap's rest frame
## (the same frame and sign as _angle_at), from one of its own axes projected across the
## axle: a fist rolling round a rod turns every axis of the controller that lies across
## it by the same angle. NAN when that axis has swung into line with the axle.
func _roll_at(ctrl: XRController3D, near_deg: float) -> float:
	if target == null or ctrl == null:
		return NAN
	var parent := target.get_parent() as Node3D
	if parent == null:
		return NAN
	var rest := Basis.from_euler(Vector3(target.rotation.x, target.rotation.y, 0.0))
	var to_rest := (parent.global_basis.orthonormalized() * rest).inverse()
	var r: Vector3 = to_rest * ctrl.global_basis.orthonormalized()[_roll_axis]
	if Vector2(r.x, r.y).length() < 0.25:
		return NAN
	var deg := rad_to_deg(atan2(r.y, r.x))
	while deg - near_deg > 180.0:
		deg -= 360.0
	while deg - near_deg < -180.0:
		deg += 360.0
	return deg


## follow_roll: take hold without moving the cap, as _begin_track does, measuring the
## controller axis that lies flattest across the axle.
func _begin_roll(ctrl: XRController3D) -> void:
	if target == null:
		return
	var parent := target.get_parent() as Node3D
	if parent == null:
		return
	var rest := Basis.from_euler(Vector3(target.rotation.x, target.rotation.y, 0.0))
	var to_rest := (parent.global_basis.orthonormalized() * rest).inverse()
	var b := ctrl.global_basis.orthonormalized()
	var across_x := Vector2((to_rest * b.x).x, (to_rest * b.x).y).length()
	var across_z := Vector2((to_rest * b.z).x, (to_rest * b.z).y).length()
	_roll_axis = 0 if across_x >= across_z else 2
	var cur := rad_to_deg(target.rotation.z)
	var raw := _roll_at(ctrl, cur)
	_grab_offset_deg = 0.0 if is_nan(raw) else cur - raw
	_grab_raw_prev = cur if is_nan(raw) else raw


func _track_world_point(world_pos: Vector3) -> void:
	_track_angle(_angle_at(world_pos, _grab_raw_prev))


func _track_angle(raw: float) -> void:
	# Unwrap against the PREVIOUS raw angle, not the cap's: once an offset is in play
	# the two are no longer near each other, and unwrapping against the cap would fold
	# a large offset into a 360° jump.
	if is_nan(raw):
		return
	_grab_raw_prev = raw
	_apply_deg(raw + _grab_offset_deg, true)


func _apply_value(v: float, emit: bool) -> void:
	_apply_deg(lerpf(deg_at_zero, deg_at_one, clampf(v, 0.0, 1.0)), emit)


func _apply_deg(deg: float, emit: bool) -> void:
	# Clamped against the ORDERED pair, since deg_at_zero is the larger of the two on
	# a clockwise knob and clampf with its arguments the wrong way round returns the
	# high bound for everything.
	deg = clampf(deg, minf(deg_at_zero, deg_at_one), maxf(deg_at_zero, deg_at_one))
	var span: float = deg_at_one - deg_at_zero
	var before := value
	value = 0.0 if is_zero_approx(span) else clampf((deg - deg_at_zero) / span, 0.0, 1.0)
	if target != null:
		target.rotation.z = deg_to_rad(deg)
	if emit:
		value_changed.emit(value)
		_feel(before)


## The controller holding the knob, whose hand feels it turn: a latched trigger or
## a held laser. Null for the desktop reticle and for an owner's set_value, neither
## of which is a hand on the cap.
func _holding_ctrl() -> XRController3D:
	if is_instance_valid(_trigger_ctrl):
		return _trigger_ctrl
	if _pointer_held and is_instance_valid(_pointer_ctrl):
		return _pointer_ctrl
	return null


## Haptics for a hand-driven move from `before` to `value`: the end stop on ARRIVING
## at either end (not every frame pushed against it), else the detent crossed --
## boundary k sits at value k / detents, and the two ends are the end stops' own, so
## coming off an end does not tick. Several crossed in one frame are one tick.
func _feel(before: float) -> void:
	if not haptics:
		return
	var ctrl := _holding_ctrl()
	if ctrl == null:
		return
	var magnitude := 0.0
	var arrived := (value <= 0.0 and before > 0.0) or (value >= 1.0 and before < 1.0)
	if arrived:
		magnitude = end_magnitude
	elif detents > 0:
		var a := int(floor(before * detents))
		var b := int(floor(value * detents))
		if a != b:
			var lo := mini(a, b) + 1
			var hi := maxi(a, b)
			var centre := int(detents / 2.0)
			if center_magnitude > 0.0 and detents % 2 == 0 and lo <= centre and centre <= hi:
				magnitude = center_magnitude
			elif not (lo == hi and (hi <= 0 or hi >= detents)):
				var now := Time.get_ticks_msec()
				if now - _last_tick_ms >= DETENT_MIN_GAP_MS:
					_last_tick_ms = now
					magnitude = detent_magnitude
	if magnitude <= 0.0:
		return
	Haptics.pulse(ctrl, magnitude, HAPTIC_MS, HAPTIC_KEY)
	detent_felt.emit(magnitude)


# --- floating hint icon --------------------------------------------------------

## Build the open-hand / fist hint, the same recipe VRHinge uses — the Symbols Nerd
## Font chained as a fallback so the PUA glyphs resolve. WHERE it sits is the
## scene's business: an authored "KnobHint" child keeps the position it was given.
func _build_icon() -> void:
	var existing := get_node_or_null("KnobHint") as Label3D
	if existing != null:
		_icon = existing
	else:
		_icon = Label3D.new()
		_icon.name = "KnobHint"
		add_child(_icon)
	var fv := FontVariation.new()
	fv.base_font = ThemeDB.fallback_font
	var symbols: Font = load(SYMBOL_FONT_PATH)
	if symbols:
		fv.fallbacks = [symbols]
	_icon.font = fv
	_icon.font_size = 96
	_icon.pixel_size = icon_size / 96.0
	_icon.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_icon.no_depth_test = true
	_icon.render_priority = 2
	_icon.outline_size = 18
	_icon.outline_modulate = Color(0.0, 0.0, 0.0, 0.7)
	_icon.visible = false


func _update_icon() -> void:
	if _icon == null:
		return
	if _trigger_ctrl != null or _pointer_held:
		_icon.text = String.chr(ICON_HELD)
		_icon.modulate = Color(1.0, 0.82, 0.28)   # fist — amber "holding"
		_icon.visible = true
		return
	if _pointer_hover or _vr_hovering():
		_icon.text = String.chr(ICON_HOVER)
		_icon.modulate = Color(0.92, 0.96, 1.0)    # open hand — cool white
		_icon.visible = true
		return
	_icon.visible = false


## Position the hint, for rigs assembled in code rather than authored in a scene.
func place_hint(local_pos: Vector3) -> void:
	if _icon != null:
		_icon.position = local_pos


func _vr_hovering() -> bool:
	for ctrl in _controllers:
		if ctrl and ctrl.get_is_active() \
				and _engage_distance(PokeTip.tip_of(ctrl)) <= engage_radius:
			return true
	return false
