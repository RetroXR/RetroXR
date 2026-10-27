## ArcadePanelHands — a player's hands on the panel: a fingertip presses a cap, and the trigger takes hold of a stick,
## a wheel, a dial, a trackball, a gear lever or a motorbike's bars.
##
## A panel used to be ONE controller you attached to (ArcadePanelGrip): aim at it, press, and your own controller played
## that player. That stays, and it is how a keyboard or a pad plays. This is the other way, the one a headset has hands
## for: reach out and use the control, no attaching first. The two add up (a pressed cap and a pressed button on the
## pad are both pressed), and everything out of here goes the way the attached controller's does: ArcadeInput adds
## `buttons()` and `thumbstick()` to the player's state before it is sent, so netplay routes it unchanged.
##
## FINGERS. A fingertip (PokeTip.tip_of) inside a cap's own box, a few millimetres proud of it, presses it, and the
## press HOLDS for as long as the finger stays: the same contract as a Wii Remote's 1 and 2 (VRButton's touch mode, whose
## is_held() exists for exactly a button wired to a game), with the same release slack (RELEASE_SCALE, CONTACT_GRACE).
## A hand presses ONE cap at a time, the one the tip is nearest, and slides from a cap to the next without lifting. A
## hand that holds something (a gun, a pad: PokeTip.is_poking) or a control presses none. The caps, the dance stage's
## arrows and a racer's two pedals are all this.
##
## TAKING HOLD. The TRIGGER, on the rising edge, with the tip within reach of a control's handle (the stick's ball,
## the wheel's rim, the dial's knob, the trackball, the lever's knob, a bar's grip); let go with the trigger, or by
## taking the hand far away. There is deliberately no grip for most of them (the project's rule for VRKnob): a squeeze is how
## the hand picks a thing up, and a cabinet IS a pickable, so a squeeze on a stick would also begin the carry, and on this
## panel it is already the ATTACH. The BARS are the exception (`takes_grip`): a hand reaching for them has no laser and the panel
## takes no press from it, and handlebars are taken by squeezing. While a hand reaches for or holds a control its laser is off (VrPointerBlock), so the
## trigger clicks nothing behind it; ArcadePanelGrip also ignores a press from a hand that reaches.
##
## What each control does with the hand:
##   stick      leans where the hand takes it, from where it was taken (STICK_THROW is a full lean). Its ball follows.
##   wheel      turns with the hand about the axle, to the lock and no further (a hand that goes on winds nothing up);
##              let go, it comes back to centre by itself.
##   dial       turns freely with the hand; the SPEED it is turned at is the deflection, as holding LEFT or RIGHT is.
##   trackball  rolls where the hand pushes it, at the surface speed the picture rolls at (BALL_SPEED).
##   lever      thrown or not: past 60% of its throw it is in high gear and STAYS there when let go (a gear lever does);
##              it is pulled back below 40% the same way. What that SAYS is the game's (ArcadeGameProfile.shifter): a shifter MAME
##              makes a toggle gets ONE tap of its button at every change of gear (the button the table names, queued: two
##              changes in a hurry are two taps, never one long press), one it does not holds the button while the lever is
##              high, and a sequential box taps `up` going high and `down` going low.
##   bars       a motorbike's: the hand pushes the bar sideways and the bike leans (a bar 15 cm over is a full lean). A BICYCLE's
##              are turned as real bars are: a hand on a grip goes round the stem (the grip stays under it, up to the lock), two hands turn
##              them by the line between them, one grip forward and the other back; a lift of the hands, and a push or pull of both, tips the craft
##              (10 cm is the whole of it). Taken with the squeeze as well as the trigger, a hand on each grip.
##   crank      a bicycle's: turned with the hand like a dial, the SPEED it is turned at the right stick's Y, forward up.
##   slide      a lever in a slot (Panic Park's): pushed along it, 14 cm either way from where it rests.
##   throttle   a flight cockpit's lever: pushed forward or pulled back (10 cm is all of it) and LEFT WHERE IT IS, as a throttle is;
##              it is the right stick's Y, forward up. A pad's right stick over it wins while it is further over (the larger wins,
##              as with any control a hand and a pad both work).
## Clockwise seen by the player is RIGHT, for the wheel, the dial and the bars alike.
##
## EVERY NUMBER HERE IS AN ESTIMATE. A headset has not touched it; the suite (arcade_hand_tests) pins the mechanics, not
## the feel. They are consts so the feel can be tuned on a device.
class_name ArcadePanelHands
extends RefCounted

## The analog trigger, read as a float like VRKnob, VRButton and the rest; latch and release with a gap between.
const TRIGGER_ACTION := "trigger"
const TRIGGER_ON := 0.6
const TRIGGER_OFF := 0.4
## The squeeze, for the controls taken by it (a bicycle's bars).
const GRIP_ACTION := "grip"
const GRIP_ON := 0.6
const GRIP_OFF := 0.4
const HAPTIC_KEY := &"arcade_panel"

## A cap is pressed by a tip within this of its side, this far above its face, or this far through it (metres).
## The caps stand 52 mm apart centre to centre and are 31 mm across, so a cap and its neighbour's zones never meet.
const POKE_SIDE := 0.005
const POKE_OUT := 0.010
const POKE_IN := 0.025
## A press lets go when the tip is outside the zone grown by this, for CONTACT_GRACE seconds.
const RELEASE_SCALE := 1.8
const CONTACT_GRACE := 0.05
## The contact disc of the fingertip lands on a cap once the tip is this close (in zone widths).
const CONTACT_READING := 2.0

## The tip within this of a handle takes hold of it on a trigger pull; a hand reaching is within REACH_SCALE times
## that (its laser is off, and the panel ignores its press).
const STICK_REACH := 0.05
const DIAL_REACH := 0.045
const BALL_REACH := 0.06
const LEVER_REACH := 0.055
const BARS_REACH := 0.07
const REACH_SCALE := 1.5
## A hand this far from what it holds lets go (a tracking loss, a trigger that stuck).
const LET_GO_DISTANCE := 0.35
## A stick leans fully over this far from where it was taken (the ball itself travels about 23 mm), and sends nothing
## inside the dead zone (the fraction of a full lean).
const STICK_THROW := 0.030
const STICK_DEAD := 0.06
## The wheel is taken on its rim: between these fractions of its radius, and within this of its plane.
const WHEEL_INNER := 0.45
const WHEEL_OUTER := 1.40
const WHEEL_AXIAL := 0.07
## A motorbike's bars push this far sideways for a full lean (14 degrees at the 62 cm they stand over the stand); a
## bicycle's bars also push forward and pull back this far for a full tip.
const BARS_THROW := 0.15
const BARS_PITCH_THROW := 0.10
## A bicycle's bars are turned by the line between two hands when they are this far apart at least (a pair of hands on one grip say nothing), and by one hand's angle about the stem
## when it is this far from the stem at least (on the axis an angle is noise).
const BARS_PAIR_MIN := 0.15
const BARS_AXIS_MIN := 0.08
const CRANK_REACH := 0.06
const SLIDE_REACH := 0.055
## A throttle lever is taken at its knob, and moves through its whole travel for this much of the hand's way forward or back.
const THROTTLE_REACH := 0.06
const THROTTLE_THROW := 0.10
## The lever goes high past this much of its throw and low again under this much (hysteresis: a toggle shifter must not shift at every
## wobble of a hand about the middle), and a tap on a toggle or sequential shifter's button lasts and rests this long.
const LEVER_HIGH_ON := 0.6
const LEVER_HIGH_OFF := 0.4
const LEVER_TAP_GAP := 0.10
## A hand on the bars is this far from where they pivot at most (the grips stand 30 cm out).
const BARS_LET_GO := 0.55
## A hand within this of a panel is asked about its controls at all.
const NEAR := 2.0
## A hand takes a yoke by a grip: within this of the bar's line, the grips being at +-90 degrees from the pivot's -Z, atan2(x, z) of the hand in the axle frame.
const HELM_GRIP_ARC := 0.9


## Is a point `p` (in the yoke's axle frame: Y along the axle, the bar along X) near one of its two handgrips, by angle about the axle? Pure, for the tests.
static func near_helm_grip(p: Vector3) -> bool:
	var a := atan2(p.x, p.z)
	return absf(absf(a) - PI * 0.5) <= HELM_GRIP_ARC


## FEET. A dancer's arrows are pressed by whoever stands on them, and nothing tracks feet: the player's body is the head's place on the floor
## (`update_body`, a point at the height of the floor under the player). A panel is pressed while that point is over its square, grown by FOOT_MARGIN
## (a foot is wider than a point), and the floor under the player is no more than FOOT_BELOW under the panel's top (walking up from the room's floor onto
## a platform) and FOOT_ABOVE over it.
const FOOT_MARGIN := 0.02
const FOOT_BELOW := 0.18
const FOOT_ABOVE := 0.06

## The pad bits a racer's pedals press, as the keyboard's R2 and L2 do (ArcadeControlModule._show_analog).
const GAS_BIT := ControllerBindings.JOYPAD_R2
const BRAKE_BIT := ControllerBindings.JOYPAD_L2

var _panel: ArcadeControlModule
var _grabs: Array[ControlGrab] = []
var _pokes: Array[Poke] = []
## Controller instance id -> what the hand holds (a ControlGrab), what it presses (a Poke), its trigger last frame, and
## the seconds its finger has been outside the release zone.
var _holding: Dictionary = {}
var _pressing: Dictionary = {}
var _trigger: Dictionary = {}
var _grip: Dictionary = {}
## Controller id -> what took the control it holds, &"trigger" or &"grip": it is let go when THAT is.
var _taken_with: Dictionary = {}
var _lost: Dictionary = {}
var _block := VrPointerBlock.new()
var _hands: Array[XRController3D] = []
## The lasers this has switched off, by controller id, so one that went away is given back.
var _blocked: Dictionary = {}
var _idle := true


func _init(panel: ArcadeControlModule) -> void:
	_panel = panel
	rebuild()


# ── what there is to touch ───────────────────────────────────────────────────

## Find the panel's controls again. Called once the panel's parts are in place (ArcadeControlModule.attach), by name,
## as the module itself finds them.
func rebuild() -> void:
	release_all()
	_grabs.clear()
	_pokes.clear()
	for i in _panel.cap_count():
		var cap := _panel.cap_node(i) as MeshInstance3D
		if cap == null or cap.mesh == null:
			continue
		var poke := Poke.new()
		poke.node = cap
		poke.mesh = cap
		poke.local = Transform3D(cap.basis, _panel.cap_rest_position(i))
		poke.bit = _panel.cap_bit(i)
		poke.is_round = cap.mesh is CylinderMesh
		poke.sector = cap.get_meta(&"sector", {}) as Dictionary
		poke.foot = bool(cap.get_meta(&"stage_panel", false))
		_pokes.append(poke)
	for entry: Array in [["GasPivot", GAS_BIT, "GasDeck"], ["BrakePivot", BRAKE_BIT, "BrakeDeck"]]:
		var pivot := _panel.find_child(str(entry[0]), true, false) as Node3D
		var tread := _panel.find_child(str(entry[2]), true, false) as MeshInstance3D
		if pivot == null or tread == null or tread.mesh == null:
			continue
		var pedal := Poke.new()
		pedal.node = pivot
		pedal.mesh = tread
		# The tread where it rests, not where it is tipped to: a pedal under a finger goes down, and a zone that went
		# with it would let go of the finger that was pushing it.
		pedal.local = Transform3D(_panel.rest_basis_of(pivot), pivot.position) * tread.transform
		pedal.bit = int(entry[1])
		_pokes.append(pedal)
	for k in 2:
		var stick := _panel.find_child("StickPivot" if k == 0 else "StickPivot2", true, false) as Node3D
		if stick != null:
			_grabs.append(StickGrab.new(_panel, stick, k))
	var wheel := _panel.find_child("WheelPivot", true, false) as Node3D
	if wheel != null:
		_grabs.append(WheelGrab.new(_panel, wheel))
	var dial := _panel.find_child("DialPivot", true, false) as Node3D
	if dial != null:
		_grabs.append(DialGrab.new(_panel, dial))
	var ball := _panel.find_child("BallPivot", true, false) as Node3D
	if ball != null:
		_grabs.append(BallGrab.new(_panel, ball))
	var lever := _panel.find_child("ShifterPivot", true, false) as Node3D
	if lever != null:
		_grabs.append(LeverGrab.new(_panel, lever))
	var lean := _panel.find_child("LeanPivot", true, false) as Node3D
	if lean != null:
		_grabs.append(BarsGrab.new(_panel, lean, false))
	var bars := _panel.find_child("BarsPivot", true, false) as Node3D
	if bars != null:
		_grabs.append(BarsGrab.new(_panel, bars, true))
	var crank := _panel.find_child("CrankPivot", true, false) as Node3D
	if crank != null:
		_grabs.append(CrankGrab.new(_panel, crank))
	var slide := _panel.find_child("SlidePivot", true, false) as Node3D
	if slide != null:
		_grabs.append(SlideGrab.new(_panel, slide))
	var throttle := _panel.find_child("ThrottlePivot", true, false) as Node3D
	if throttle != null:
		_grabs.append(ThrottleGrab.new(_panel, throttle))


# ── every frame ──────────────────────────────────────────────────────────────

## Step the hands on this panel. `ctrls` are the player's two hands; `live` is false while the machine is off (the
## controls are dead then, and whatever was held is let go).
func update(delta: float, ctrls: Array, live: bool) -> void:
	if not live or _panel == null or not is_instance_valid(_panel) or not _panel.is_inside_tree() \
			or not _panel.is_visible_in_tree():
		release_all()
		# A machine that is off has its throttle back in the middle.
		if not live:
			reset_latched()
		return
	# Whatever a control is in the middle of (a tap on a shift button) goes on with no hand on it.
	for g in _grabs:
		g.tick(delta)
	_hands.clear()
	for c: Variant in ctrls:
		if c != null and is_instance_valid(c) and (c as XRController3D).get_is_active():
			_hands.append(c as XRController3D)
	_forget_gone()
	if _hands.is_empty() or (_holding.is_empty() and _pressing.is_empty() \
			and not PokeTip.any_tip_within(_hands, _panel.global_position, NEAR)):
		if not _idle:
			release_all()
		return
	_idle = false
	for ctrl in _hands:
		_step_hand(ctrl, delta)
	_sync_outlines()


func _step_hand(ctrl: XRController3D, delta: float) -> void:
	var id := ctrl.get_instance_id()
	var tip := PokeTip.tip_of(ctrl)
	var poking := PokeTip.is_poking(ctrl)
	var trigger := ctrl.get_float(TRIGGER_ACTION)
	var squeeze := ctrl.get_float(GRIP_ACTION)
	var before := float(_trigger.get(id, 0.0))
	var squeeze_before := float(_grip.get(id, 0.0))
	_trigger[id] = trigger
	_grip[id] = squeeze
	var grab := _holding.get(id) as ControlGrab
	if grab != null:
		# Let go when what took it lets go: the trigger for a control taken by it, the squeeze for one taken by that.
		var held_on := squeeze >= GRIP_OFF if _taken_with.get(id, &"trigger") == &"grip" else trigger >= TRIGGER_OFF
		if not poking or not held_on or tip.distance_to(grab.handle()) > grab.let_go_distance():
			_let_go(ctrl, id)
			grab = null
		else:
			var was := grab.detent()
			grab.drag_hand(id, tip, delta)
			if grab.detent() != was:
				Haptics.pulse(ctrl, 0.25, 8, HAPTIC_KEY)
	elif poking:
		var pulled := trigger >= TRIGGER_ON and before < TRIGGER_ON
		var squeezed := squeeze >= GRIP_ON and squeeze_before < GRIP_ON
		if pulled or squeezed:
			# A trigger takes any control within reach; a squeeze only those that are taken by squeezing.
			var found := _nearest_grab(tip, 1.0, squeezed and not pulled)
			if found != null:
				_take(ctrl, id, found, tip, &"grip" if squeezed and not pulled else &"trigger")
				grab = found
	# A hand reaching for a control has no laser: the trigger it pulls is for the control.
	_set_laser(ctrl, poking and (grab != null or _nearest_grab(tip, REACH_SCALE) != null))
	if grab == null and poking:
		_fingers(ctrl, id, tip, delta)
	else:
		_lift(ctrl, id)


func _nearest_grab(tip: Vector3, scale: float, by_squeeze: bool = false) -> ControlGrab:
	var best: ControlGrab = null
	var best_d := INF
	for g in _grabs:
		# A control a hand holds is taken by no other, but a pair of bars by a second hand, on the other grip.
		if (g.holder != null and not g.takes_second_hand()) or not g.usable() or not g.can_grab(tip, scale):
			continue
		if by_squeeze and not g.takes_grip():
			continue
		var d := g.handle().distance_to(tip)
		if d < best_d:
			best = g
			best_d = d
	return best


func _take(ctrl: XRController3D, id: int, grab: ControlGrab, tip: Vector3, with: StringName = &"trigger") -> void:
	_holding[id] = grab
	_taken_with[id] = with
	grab.attach_hand(ctrl, id, tip)
	_lift(ctrl, id)
	Haptics.click(ctrl, true, HAPTIC_KEY)
	# What the player is told about this control and the game's buttons: by the first hand on it, not again by a second hand on a pair of bars.
	if grab.hands_on() == 1:
		_panel.prompt_control(grab.kind, ctrl, grab.handle())


func _let_go(ctrl: XRController3D, id: int) -> void:
	var grab := _holding.get(id) as ControlGrab
	_holding.erase(id)
	_taken_with.erase(id)
	if grab == null:
		return
	grab.detach_hand(id)
	if is_instance_valid(ctrl):
		Haptics.click(ctrl, false, HAPTIC_KEY)


## A hand's finger on the caps: keep the cap it presses while the tip stays near, else press the nearest.
func _fingers(ctrl: XRController3D, id: int, tip: Vector3, delta: float) -> void:
	var held := _pressing.get(id) as Poke
	# A cap the game stopped using (or the machine rebuilt) is not pressed any more, finger or no finger.
	if held != null and not held.usable():
		_lift(ctrl, id)
		held = null
	if held != null:
		if held.reading(tip, 1.0) <= 1.0:
			_lost[id] = 0.0
			PokeTip.claim_box_face(ctrl, held.mesh, tip, held.out(), PokeTip.CONTACT_ENGAGED)
			return
		# Off its zone: another cap the tip is in takes over at once (a finger rolled across a row); else a grace.
		var next := _nearest_poke(tip)
		if next == null:
			if held.reading(tip, RELEASE_SCALE) <= 1.0:
				_lost[id] = 0.0
				return
			_lost[id] = float(_lost.get(id, 0.0)) + delta
			if float(_lost[id]) < CONTACT_GRACE:
				return
		_lift(ctrl, id)
	var poke := _nearest_poke(tip)
	if poke != null:
		poke.held += 1
		_pressing[id] = poke
		_lost[id] = 0.0
		Haptics.click(ctrl, true, HAPTIC_KEY)
		PokeTip.claim_box_face(ctrl, poke.mesh, tip, poke.out(), PokeTip.CONTACT_ENGAGED)
		return
	# Nothing pressed: the disc of the fingertip still lands on the cap it is about to press.
	var near := _closest_poke(tip, CONTACT_READING)
	if near != null:
		PokeTip.claim_box_face(ctrl, near.mesh, tip, near.out(), PokeTip.CONTACT_HOVER)


## The cap the tip is inside the zone of and nearest the middle of.
func _nearest_poke(tip: Vector3) -> Poke:
	return _closest_poke(tip, 1.0)


func _closest_poke(tip: Vector3, within: float) -> Poke:
	var best: Poke = null
	var best_r := within
	for p in _pokes:
		if not p.usable():
			continue
		var r := p.reading(tip, 1.0)
		if r <= best_r:
			best = p
			best_r = r
	return best


func _lift(ctrl: XRController3D, id: int) -> void:
	var poke := _pressing.get(id) as Poke
	_pressing.erase(id)
	_lost.erase(id)
	if poke == null:
		return
	poke.held = maxi(0, poke.held - 1)
	if is_instance_valid(ctrl):
		Haptics.click(ctrl, false, HAPTIC_KEY)


## A hand that is no longer there (freed, inactive) holds and presses nothing.
func _forget_gone() -> void:
	var ids: Dictionary = {}
	for h in _hands:
		ids[h.get_instance_id()] = true
	for id: int in _holding.keys():
		if not ids.has(id):
			_let_go(null, id)
	for id: int in _pressing.keys():
		if not ids.has(id):
			_lift(null, id)
	for id: int in _blocked.keys():
		if not ids.has(id):
			var gone: Variant = _blocked[id]
			_block.set_block(gone if is_instance_valid(gone) else null, false)
			_blocked.erase(id)
	for id: int in _trigger.keys():
		if not ids.has(id):
			_trigger.erase(id)
	for id: int in _grip.keys():
		if not ids.has(id):
			_grip.erase(id)


## Everything let go, every laser back, the outlines away: the machine went off, the panel left the tree or a hand
## went. Cheap to call again.
func release_all() -> void:
	if _idle and _holding.is_empty() and _pressing.is_empty() and _blocked.is_empty():
		return
	for id: int in _holding.keys():
		var grab := _holding[id] as ControlGrab
		if grab != null:
			grab.release()
	_holding.clear()
	_taken_with.clear()
	for p in _pokes:
		p.held = 0
	_pressing.clear()
	_lost.clear()
	_trigger.clear()
	_grip.clear()
	for id: int in _blocked.keys():
		var ctrl: Variant = _blocked[id]
		_block.set_block(ctrl if is_instance_valid(ctrl) else null, false)
	_blocked.clear()
	for g in _grabs:
		g.show_outline(false)
	_idle = true


## The laser of `ctrl` off while it reaches for a control, back when it does not.
func _set_laser(ctrl: XRController3D, off: bool) -> void:
	if ctrl == null or not is_instance_valid(ctrl):
		return
	var id := ctrl.get_instance_id()
	if off == _blocked.has(id):
		return
	_block.set_block(ctrl, off)
	if off:
		_blocked[id] = ctrl
	else:
		_blocked.erase(id)


## Each control a hand could take is outlined yellow (WidgetOutline.SELECT_COLOR, the colour a laser-held pad wears); the one a
## hand HOLDS has no outline at all: the hand is on it, and the ring would only sit between the player and the control.
func _sync_outlines() -> void:
	for g in _grabs:
		var held := g.holder != null
		var near := false
		if not held and g.usable():
			for ctrl in _hands:
				if PokeTip.is_poking(ctrl) and not _holding.has(ctrl.get_instance_id()) \
						and g.can_grab(PokeTip.tip_of(ctrl), REACH_SCALE):
					near = true
					break
		g.show_outline(near and not held)


# ── what the hands say ───────────────────────────────────────────────────────

## The pad bits the hands hold: the caps and the pedals under a finger, the arrows under the player's feet, and the gear lever in high gear.
func buttons() -> int:
	var mask := 0
	for p in _pokes:
		if (p.held > 0 or p.body) and p.usable():
			mask |= 1 << p.bit
	for g in _grabs:
		mask |= g.bits()
	return mask


## The thumbsticks the hands stand in for: 0 the left (the first stick, a wheel, a dial, a trackball, a bike's bars),
## 1 the right (the second stick). x right, y UP, as a thumbstick reads, each inside the unit circle's square.
func thumbstick(side: int) -> Vector2:
	var best := Vector2.ZERO
	for g in _grabs:
		var v := g.stick(side)
		if v.length_squared() > best.length_squared():
			best = v
	return best


## Is a hand on the panel? A finger on a cap or a hold on a control, or a foot on an arrow, now.
func active() -> bool:
	if not _holding.is_empty() or not _pressing.is_empty():
		return true
	for p in _pokes:
		if p.body:
			return true
	return false


## Does this panel have arrows to stand on (a dance stage's)?
func has_feet() -> bool:
	for p in _pokes:
		if p.foot:
			return true
	return false


## The player's body: `point` is where they stand, at the height of the floor under them (Vector3.INF: nobody, or the machine is off). Presses each arrow
## whose square it is over (`foot_on`); every other arrow comes up.
func update_body(point: Vector3) -> void:
	var here := point.is_finite()
	for p in _pokes:
		if not p.foot:
			continue
		p.body = here and p.usable() and ArcadePanelHands.foot_on(p.frame().affine_inverse() * point, p.mesh.mesh.get_aabb())


## Is a body at `p` (in the panel's own frame: Y out of its face) on a panel whose mesh box is `box`? Over its square, and the floor it stands on within
## reach of the panel's top. Pure, for the tests.
static func foot_on(p: Vector3, box: AABB) -> bool:
	var q := p - box.get_center()
	var half := box.size * 0.5
	if absf(q.x) > half.x + FOOT_MARGIN or absf(q.z) > half.z + FOOT_MARGIN:
		return false
	var above_top := q.y - half.y
	return above_top >= -FOOT_BELOW and above_top <= FOOT_ABOVE


## Is a hand HOLDING a control (a stick, a wheel, a lever...) now? A finger on a cap is not a hold.
func is_holding() -> bool:
	return not _holding.is_empty()


## The hands that hold a control now.
func holding_hands() -> Array[XRController3D]:
	var out: Array[XRController3D] = []
	for grab: Variant in _holding.values():
		var holder := (grab as ControlGrab).holder
		if holder != null and is_instance_valid(holder):
			out.append(holder)
	return out


## Is `ctrl` holding, or about to take hold of, a control of this panel? Asked afresh, from where the hand is, so it
## does not depend on whether the panel's own step has run yet this frame (ArcadePanelGrip asks before it takes a press).
func reaching(ctrl: XRController3D) -> bool:
	if ctrl == null or not is_instance_valid(ctrl):
		return false
	if _holding.has(ctrl.get_instance_id()):
		return true
	if not PokeTip.is_poking(ctrl):
		return false
	var tip := PokeTip.tip_of(ctrl)
	for g in _grabs:
		if g.usable() and g.can_grab(tip, REACH_SCALE):
			return true
	return false


func holds(kind: StringName, index: int = 0) -> bool:
	var g := _grab_of(kind, index)
	return g != null and g.holder != null


## What a held control shows, for the module to draw: the stick's lean (x right, y DOWN, -1..1), the wheel's or
## the bars' steering (-1 left .. 1 right), the dial's angle (clockwise, radians), the trackball's roll, the lever's
## throw (0..1).
func stick_lean(index: int) -> Vector2:
	var g := _grab_of(&"stick", index) as StickGrab
	return g.lean if g != null else Vector2.ZERO


func steer(kind: StringName) -> float:
	var g := _grab_of(kind, 0)
	if g is WheelGrab:
		return (g as WheelGrab).steer
	if g is BarsGrab:
		return (g as BarsGrab).steer
	if g is SlideGrab:
		return (g as SlideGrab).steer
	return 0.0


## How far a bicycle's bars are pulled toward the player (-1 pushed away .. 1 pulled), the module's convention.
func bars_pitch() -> float:
	var g := _grab_of(&"bars", 0) as BarsGrab
	return g.pull if g != null else 0.0


## How far the crank has been turned by the hand (radians, forward positive).
func crank_angle() -> float:
	var g := _grab_of(&"crank", 0) as CrankGrab
	return g.angle if g != null else 0.0


func dial_angle() -> float:
	var g := _grab_of(&"dial", 0) as DialGrab
	return g.angle if g != null else 0.0


func ball_roll() -> Vector2:
	var g := _grab_of(&"ball", 0) as BallGrab
	return g.roll if g != null else Vector2.ZERO


func lever_throw() -> float:
	var g := _grab_of(&"lever", 0) as LeverGrab
	return g.shift if g != null else 0.0


## Where the throttle lever stands (-1 back .. 1 forward): where the hand has it, and where it was left.
func throttle_value() -> float:
	var g := _grab_of(&"throttle", 0) as ThrottleGrab
	return g.value if g != null else 0.0


## A control that keeps its place when let go (a throttle) goes back to the middle: the machine went off, or the run ended.
func reset_latched() -> void:
	for g in _grabs:
		g.reset()


func _grab_of(kind: StringName, index: int) -> ControlGrab:
	for g in _grabs:
		if g.kind == kind and g.index == index:
			return g
	return null


## The grabs and pokes, for the suite and the probe.
func grabs() -> Array[ControlGrab]:
	return _grabs


func pokes() -> Array[Poke]:
	return _pokes


# ── a cap, a pedal: pressed by a finger ──────────────────────────────────────

class Poke extends RefCounted:
	## The node the part belongs to (a cap, a pedal's pivot) and the mesh whose box is the zone.
	var node: Node3D = null
	var mesh: MeshInstance3D = null
	## The mesh's frame in its node's PARENT frame, at rest.
	var local := Transform3D.IDENTITY
	var bit := 0
	var is_round := true
	## A drum's zone is a sector of a ring (Taiko's rim, a Mambo a Go-Go pad): `{r0, r1, a0, a1}` (metres and radians, the angle counter-clockwise from the mesh's +X about its origin, seen from the face),
	## and the box of its mesh would cover its neighbours' zones.
	var sector: Dictionary = {}
	## How many hands press it.
	var held := 0
	## A panel stood on (a dance stage's arrow), and whether the player's body is on it now.
	var foot := false
	var body := false

	func frame() -> Transform3D:
		return (node.get_parent() as Node3D).global_transform * local

	## A cap that is drawn: the game does not use one that is not.
	func usable() -> bool:
		return is_instance_valid(node) and is_instance_valid(mesh) and node.is_visible_in_tree()

	## Which way the face is, in the world: the mesh's +Y (a cylinder's top, a box's top).
	func out() -> Vector3:
		return frame().basis.y.normalized()

	func reading(tip: Vector3, scale: float) -> float:
		var p := frame().affine_inverse() * tip
		if not sector.is_empty():
			return ArcadePanelHands.sector_reading(p, mesh.mesh.get_aabb(), sector, scale)
		return ArcadePanelHands.poke_reading(p, mesh.mesh.get_aabb(), is_round, scale)


## How near a fingertip at `p` (in the mesh's own frame) is to pressing a part whose mesh box is `box`: 1.0 or less is
## inside the zone (the box grown by POKE_SIDE round it, POKE_OUT above and POKE_IN through, each times `scale`), less
## is nearer its middle. A round part (a cap) is a cylinder, a flat one (an arrow) a box.
static func poke_reading(p: Vector3, box: AABB, is_round: bool, scale: float = 1.0) -> float:
	var q := p - box.get_center()
	var half := box.size * 0.5
	var lateral := 0.0
	if is_round:
		lateral = Vector2(q.x, q.z).length() / (maxf(half.x, half.z) + POKE_SIDE * scale)
	else:
		lateral = maxf(absf(q.x) / (half.x + POKE_SIDE * scale), absf(q.z) / (half.z + POKE_SIDE * scale))
	var axial := 0.0
	if q.y > half.y:
		axial = (q.y - half.y) / (POKE_OUT * scale)
	elif q.y < -half.y:
		axial = (-half.y - q.y) / (POKE_IN * scale)
	return maxf(lateral, axial)


## How near a fingertip at `p` (in the mesh's own frame: Y the face's normal, the panel's y is -Z there) is to pressing a SECTOR of a ring (`sector`: r0, r1, a0, a1): 1.0 or less is inside, the
## ring's thickness and the arc's width grown by POKE_SIDE, and less is nearer the sector's middle (its mid radius, its mid angle). The box of such a mesh covers the zones beside it (a
## Taiko drum's two face halves and its two rim halves share one square), so two neighbours would both read as pressed at the edge of either.
static func sector_reading(p: Vector3, box: AABB, sector: Dictionary, scale: float = 1.0) -> float:
	var x := p.x
	var y := -p.z
	var r := Vector2(x, y).length()
	var r0 := float(sector["r0"])
	var r1 := float(sector["r1"])
	var side := POKE_SIDE * scale
	var radial := absf(r - (r0 + r1) * 0.5) / ((r1 - r0) * 0.5 + side)
	var a0 := float(sector["a0"])
	var a1 := float(sector["a1"])
	var off := absf(wrapf(atan2(y, x) - (a0 + a1) * 0.5, -PI, PI))
	var angular := off / ((a1 - a0) * 0.5 + side / maxf(r, 0.02))
	var q := p - box.get_center()
	var half := box.size.y * 0.5
	var axial := 0.0
	if q.y > half:
		axial = (q.y - half) / (POKE_OUT * scale)
	elif q.y < -half:
		axial = (-half - q.y) / (POKE_IN * scale)
	return maxf(maxf(radial, angular), axial)


# ── a control: held by a hand ────────────────────────────────────────────────

class ControlGrab extends RefCounted:
	var kind: StringName = &""
	var index := 0
	var panel: ArcadeControlModule = null
	var node: Node3D = null
	## The hand holding it, or null.
	var holder: XRController3D = null
	## What the outline traces, and the outline (made the first time it is wanted).
	var trace: MeshInstance3D = null
	var _outline: WidgetOutline = null

	## Where a hand takes hold of it, in the world.
	func handle() -> Vector3:
		return node.global_position

	func reach() -> float:
		return ArcadePanelHands.STICK_REACH

	## How far the hand may wander from the handle before it is taken to have lost the control.
	func let_go_distance() -> float:
		return ArcadePanelHands.LET_GO_DISTANCE

	## Is the control there to be held: drawn, and not a part the game does not use.
	func usable() -> bool:
		return is_instance_valid(node) and node.is_visible_in_tree()

	func can_grab(tip: Vector3, scale: float) -> bool:
		return handle().distance_to(tip) <= reach() * scale

	## A hand (controller id `id`) takes hold, drags and lets go: the three a panel calls. A control one hand holds is the default (`holder`, `begin`, `drag`, `end`); a pair of bars is held by two.
	func attach_hand(ctrl: XRController3D, _id: int, tip: Vector3) -> void:
		holder = ctrl
		begin(tip)

	func drag_hand(_id: int, tip: Vector3, delta: float) -> void:
		drag(tip, delta)

	func detach_hand(_id: int) -> void:
		end()
		holder = null

	## Every hand let go at once (the machine went off, the panel left).
	func release() -> void:
		end()
		holder = null

	## How many hands are on it.
	func hands_on() -> int:
		return 1 if holder != null else 0

	## Is it taken by a squeeze as well as a trigger, and can a second hand take it while one holds it?
	func takes_grip() -> bool:
		return false

	func takes_second_hand() -> bool:
		return false

	## The hand takes hold with its tip at `tip`; every frame it holds, `drag`; let go, `end`.
	func begin(_tip: Vector3) -> void:
		pass

	func drag(_tip: Vector3, _delta: float) -> void:
		pass

	func end() -> void:
		pass

	## Every frame the panel is live, held or not.
	func tick(_delta: float) -> void:
		pass

	## Back to where it starts a run (a control that is left where it is when let go: a throttle).
	func reset() -> void:
		pass

	## The pad bits this holds, and the thumbstick it stands in for (0 left, 1 right).
	func bits() -> int:
		return 0

	func stick(_side: int) -> Vector2:
		return Vector2.ZERO

	## A state that changes as it is moved, for a click in the hand (a stick crossing the point its switch closes).
	func detent() -> int:
		return 0

	## The frame the panel's parts are measured in: where the control's parent stands.
	func frame() -> Transform3D:
		return (node.get_parent() as Node3D).global_transform

	func show_outline(on: bool) -> void:
		if _outline == null:
			if not on or not is_instance_valid(trace) or not is_instance_valid(panel):
				return
			_outline = WidgetOutline.attach(panel)
			_outline.set_source(trace)
			_outline.set_color(WidgetOutline.SELECT_COLOR)
		_outline.sync(on)


## The stick: leans where the hand takes it, from where it was taken.
class StickGrab extends ControlGrab:
	var lean := Vector2.ZERO
	var _origin := Vector3.ZERO
	var _base := Vector2.ZERO
	## Where the ball is on the shaft, in the pivot's frame, and how far the hand goes for a full lean: the ball's own travel at full tilt, which
	## a longer shaft makes longer (a flight stick is 30 cm: the deck stick's 3 cm would leave the ball running off ahead of the hand).
	var _ball := Vector3(0.0, 0.0, 0.085)
	var _throw := ArcadePanelHands.STICK_THROW

	func _init(p_panel: ArcadeControlModule, p_node: Node3D, p_index: int) -> void:
		kind = &"stick"
		index = p_index
		panel = p_panel
		node = p_node
		var ball := p_node.find_child("StickBall", false, false) as MeshInstance3D
		if ball != null:
			trace = ball
			_ball = ball.position
		_throw = ArcadePanelHands.STICK_THROW * maxf(1.0, _ball.length() / 0.085)

	func handle() -> Vector3:
		return node.global_transform * _ball

	func reach() -> float:
		return ArcadePanelHands.STICK_REACH

	func begin(tip: Vector3) -> void:
		_origin = frame().affine_inverse() * tip
		# From the lean it has, so taking hold of a stick that is over (a key holds it) does not snap it.
		_base = panel.stick_lean_of(index)
		lean = _base

	func drag(tip: Vector3, _delta: float) -> void:
		var d := frame().affine_inverse() * tip - _origin
		var v := _base + Vector2(d.x, -d.y) / _throw
		lean = Vector2(clampf(v.x, -1.0, 1.0), clampf(v.y, -1.0, 1.0))

	func end() -> void:
		lean = Vector2.ZERO

	func stick(side: int) -> Vector2:
		if holder == null or side != index:
			return Vector2.ZERO
		var v := Vector2(lean.x, -lean.y)
		if v.length() < ArcadePanelHands.STICK_DEAD:
			return Vector2.ZERO
		return v

	## Which of the four directions are past the point the switches close.
	func detent() -> int:
		var s := stick(index)
		var n := 0
		n |= 1 if s.x > ArcadeInput.DPAD_THRESHOLD else 0
		n |= 2 if s.x < -ArcadeInput.DPAD_THRESHOLD else 0
		n |= 4 if s.y > ArcadeInput.DPAD_THRESHOLD else 0
		n |= 8 if s.y < -ArcadeInput.DPAD_THRESHOLD else 0
		return n


## The steering wheel: turns with the hand about its axle, to the lock.
class WheelGrab extends ControlGrab:
	var radius := 0.13
	## A YOKE that only turns (Road Blasters'): two handgrips HELM span from the axle on the bar's line, no rim. It is taken by a grip (within HELM_GRIP_ARC of one), and the
	## A / X and B / Y of the hand that holds it are the game's buttons 2 and 3 (its Lasers and Special Weapon), which are on the grips.
	var helm := false
	## The turn of the wheel about its axle (radians, counter-clockwise seen by the driver positive), and what it is as
	## the steering (-1 full left .. 1 full right).
	var _phi := 0.0
	var steer := 0.0
	var _alpha := 0.0

	func _init(p_panel: ArcadeControlModule, p_node: Node3D) -> void:
		kind = &"wheel"
		panel = p_panel
		node = p_node
		var rim := p_node.find_child("WheelRim", false, false) as MeshInstance3D
		if rim != null:
			trace = rim
			if rim.mesh is TorusMesh:
				radius = (rim.mesh as TorusMesh).outer_radius - 0.014
		helm = bool(p_node.get_meta(&"helm", false))
		if helm:
			radius = float(p_node.get_meta(&"helm_span", radius))
			trace = p_node.find_child("HelmBar", false, false) as MeshInstance3D

	## The wheel's rest frame: its +Y is the axle, towards the driver.
	func _axle() -> Transform3D:
		return frame() * Transform3D(panel.rest_basis_of(node), node.position)

	func handle() -> Vector3:
		return _axle().origin

	func reach() -> float:
		return radius

	func can_grab(tip: Vector3, scale: float) -> bool:
		var p := _axle().affine_inverse() * tip
		var r := Vector2(p.x, p.z).length()
		# The reach scale (a hand "reaching") widens the tolerance off the wheel's plane only: along the rim it would
		# take in the whole panel.
		var near_grip := not helm or ArcadePanelHands.near_helm_grip(p)
		return near_grip and absf(p.y) <= ArcadePanelHands.WHEEL_AXIAL * scale \
			and r >= radius * ArcadePanelHands.WHEEL_INNER and r <= radius * ArcadePanelHands.WHEEL_OUTER

	func begin(tip: Vector3) -> void:
		var p := _axle().affine_inverse() * tip
		_alpha = atan2(p.x, p.z)
		steer = panel.steering()
		_phi = -deg_to_rad(panel.wheel_lock_deg()) * steer

	func drag(tip: Vector3, _delta: float) -> void:
		var p := _axle().affine_inverse() * tip
		# Too near the axle the angle is only noise.
		if Vector2(p.x, p.z).length() < radius * 0.2:
			return
		var a := atan2(p.x, p.z)
		var lock := deg_to_rad(panel.wheel_lock_deg())
		# Accumulated and clamped a step at a time: the hand that goes past the lock winds nothing up, so turning back
		# turns the wheel back at once.
		_phi = clampf(_phi + wrapf(a - _alpha, -PI, PI), -lock, lock)
		_alpha = a
		steer = -_phi / lock

	func stick(side: int) -> Vector2:
		return Vector2(steer, 0.0) if holder != null and side == 0 else Vector2.ZERO

	## A yoke's buttons are on its grips: the holding hand's A / X is the game's button 2 and its B / Y button 3 (Road Blasters' Lasers and Special Weapon).
	func bits() -> int:
		if not helm or holder == null:
			return 0
		var mask := 0
		if holder.get_float("ax_button") >= 0.5:
			mask |= 1 << ArcadeProfiles.button_bit(2)
		if holder.get_float("by_button") >= 0.5:
			mask |= 1 << ArcadeProfiles.button_bit(3)
		return mask


## The paddle dial: turns freely; how fast it is turned is the deflection.
class DialGrab extends ControlGrab:
	## Clockwise seen by the player, radians.
	var angle := 0.0
	var rate := 0.0
	var _alpha := 0.0

	func _init(p_panel: ArcadeControlModule, p_node: Node3D) -> void:
		kind = &"dial"
		panel = p_panel
		node = p_node
		trace = p_node.find_child("DialKnob", false, false) as MeshInstance3D

	func handle() -> Vector3:
		return node.global_transform * Vector3(0.0, 0.0, 0.012)

	## A turntable is taken anywhere on its platter (its pivot's `reach` meta, the platter's radius), a knob where it stands.
	func reach() -> float:
		return maxf(ArcadePanelHands.DIAL_REACH, float(node.get_meta(&"reach", 0.0)))

	func _clockwise(tip: Vector3) -> float:
		var p := frame().affine_inverse() * tip - node.position
		return -atan2(p.y, p.x)

	func begin(tip: Vector3) -> void:
		angle = panel.dial_angle()
		rate = 0.0
		_alpha = _clockwise(tip)

	func drag(tip: Vector3, delta: float) -> void:
		var p := frame().affine_inverse() * tip - node.position
		# On its axis the angle is only noise.
		if Vector2(p.x, p.y).length() < 0.008:
			return
		var a := _clockwise(tip)
		var d := wrapf(a - _alpha, -PI, PI)
		_alpha = a
		angle = wrapf(angle + d, -PI, PI)
		if delta > 0.0:
			rate = lerpf(rate, clampf(d / delta / ArcadeControlModule.DIAL_SPEED, -1.0, 1.0), 0.5)

	func end() -> void:
		rate = 0.0

	func stick(side: int) -> Vector2:
		return Vector2(rate, 0.0) if holder != null and side == 0 else Vector2.ZERO


## The trackball: rolls where the hand pushes it.
class BallGrab extends ControlGrab:
	var roll := Vector2.ZERO
	var radius := 0.038
	var _last := Vector3.ZERO

	func _init(p_panel: ArcadeControlModule, p_node: Node3D) -> void:
		kind = &"ball"
		panel = p_panel
		node = p_node
		trace = p_node.find_child("Ball", false, false) as MeshInstance3D
		if trace != null and trace.mesh is SphereMesh:
			radius = (trace.mesh as SphereMesh).radius

	func reach() -> float:
		return ArcadePanelHands.BALL_REACH

	func begin(tip: Vector3) -> void:
		_last = frame().affine_inverse() * tip
		roll = Vector2.ZERO

	func drag(tip: Vector3, delta: float) -> void:
		var p := frame().affine_inverse() * tip
		if delta > 0.0:
			# The surface speed under the hand against the speed the picture rolls at full deflection.
			var v := Vector2(p.x - _last.x, -(p.y - _last.y)) / delta
			roll = roll.lerp((v / (ArcadeControlModule.BALL_SPEED * radius)).limit_length(1.0), 0.5)
		_last = p

	func end() -> void:
		roll = Vector2.ZERO

	func stick(side: int) -> Vector2:
		return Vector2(roll.x, -roll.y) if holder != null and side == 0 else Vector2.ZERO


## The gear lever: thrown, it stays in high gear. What that sends is the game's (ArcadeGameProfile.shifter, read live from the panel).
class LeverGrab extends ControlGrab:
	var shift := 0.0
	## A held shifter's lever is in high gear when let go.
	var latched := false
	## What the hand last asked the gear to be, so a change is asked once.
	var _want := false
	## The taps still to be made (the pad bit of each), the one being held, and how long it has left and the rest after it.
	var _queue: Array[int] = []
	var _tap_bit := -1
	var _tap_left := 0.0
	var _gap_left := 0.0

	func _init(p_panel: ArcadeControlModule, p_node: Node3D) -> void:
		kind = &"lever"
		panel = p_panel
		node = p_node
		trace = p_node.find_child("ShifterKnob", false, false) as MeshInstance3D

	func handle() -> Vector3:
		return node.global_transform * Vector3(0.0, 0.0, 0.125)

	func reach() -> float:
		return ArcadePanelHands.LEVER_REACH

	func _throw(tip: Vector3) -> float:
		var p := panel.rest_basis_of(node).inverse() * (frame().affine_inverse() * tip - node.position)
		return clampf(atan2(p.y, p.z) / deg_to_rad(ArcadeControlModule.SHIFT_DEG), 0.0, 1.0)

	## A shifter that is not held down: it says its changes in taps, and the lever is drawn where the game's gear is.
	func _taps() -> bool:
		var cfg := panel.shift_config()
		return cfg.has("up") or (cfg.has("button") and bool(cfg["toggle"]))

	func begin(tip: Vector3) -> void:
		shift = _throw(tip)
		_want = panel.shift_high()
		latched = shift >= 0.5

	func drag(tip: Vector3, _delta: float) -> void:
		shift = _throw(tip)
		if not _taps():
			return
		var high := _want
		if shift >= ArcadePanelHands.LEVER_HIGH_ON:
			high = true
		elif shift <= ArcadePanelHands.LEVER_HIGH_OFF:
			high = false
		if high != _want:
			_want = high
			_ask(high)

	## One tap for a change of gear: the toggle's button, or a sequential box's `up` going high and `down` going low.
	func _ask(high: bool) -> void:
		var cfg := panel.shift_config()
		var bit := -1
		if cfg.has("up"):
			bit = ArcadeProfiles.button_bit(int(cfg["up"] if high else cfg["down"]))
		elif cfg.has("button"):
			bit = ArcadeProfiles.button_bit(int(cfg["button"]))
		if bit >= 0:
			_queue.append(bit)

	func end() -> void:
		if _taps():
			# The lever settles where the game's gear is, once the taps are through (the module draws it).
			shift = 1.0 if _want else 0.0
			return
		latched = shift >= 0.5
		shift = 1.0 if latched else 0.0

	func tick(delta: float) -> void:
		if _tap_left > 0.0:
			_tap_left -= delta
			if _tap_left <= 0.0:
				_tap_bit = -1
				_gap_left = ArcadePanelHands.LEVER_TAP_GAP
		elif _gap_left > 0.0:
			_gap_left -= delta
		elif not _queue.is_empty():
			_tap_bit = _queue.pop_front()
			_tap_left = ArcadeInput.TAP_SECONDS

	func bits() -> int:
		var cfg := panel.shift_config()
		if cfg.is_empty():
			return 0
		if _taps():
			return (1 << _tap_bit) if _tap_bit >= 0 else 0
		var bit := ArcadeProfiles.button_bit(int(cfg.get("button", 0)))
		var thrown := latched if holder == null else shift >= 0.5
		return (1 << bit) if bit >= 0 and thrown else 0

	## The gear a click in the hand is for: a change either way.
	func detent() -> int:
		if _taps():
			return 1 if _want else 0
		return 1 if shift >= 0.5 else 0

	## Pending taps, for the tests.
	func pending() -> int:
		return _queue.size() + (1 if _tap_bit >= 0 else 0)


## Bars: pushed sideways, the bike leans; a bicycle's bars also push forward and pull back to tip the craft.
class BarsGrab extends ControlGrab:
	var steer := 0.0
	## Pulled toward the player, -1..1 (the module's way round: down); a motorbike's bars have none.
	var pull := 0.0
	## The second hand, when two hold the bars.
	var holder2: XRController3D = null
	var _two_axes := false
	var _base := 0.0
	var _base_pull := 0.0
	var _grips: Array[Node3D] = []
	var _bars: Node3D = null
	## The hands on the bars, by controller id, in the order they took hold; where each is now and where it was when the deflection last became the base (in the bike's frame).
	var _ids: Array[int] = []
	var _ctrls: Dictionary = {}
	var _now: Dictionary = {}
	var _ref: Dictionary = {}
	## The outlines of the two grips (made the first time they are wanted).
	var _outlines: Array[WidgetOutline] = []

	func _init(p_panel: ArcadeControlModule, p_node: Node3D, two_axes: bool) -> void:
		kind = &"bars"
		panel = p_panel
		node = p_node
		_two_axes = two_axes
		_bars = p_node.find_child("Handlebars", true, false) as Node3D
		for n in ["BarGripL", "BarGripR"]:
			var grip := p_node.find_child(n, true, false) as Node3D
			if grip != null:
				_grips.append(grip)
		if not _grips.is_empty():
			trace = _grips[0] as MeshInstance3D

	func reach() -> float:
		return ArcadePanelHands.BARS_REACH

	func let_go_distance() -> float:
		return ArcadePanelHands.BARS_LET_GO

	## Bars are taken by a squeeze too, and by a second hand.
	func takes_grip() -> bool:
		return true

	func takes_second_hand() -> bool:
		return holder != null and holder2 == null

	func hands_on() -> int:
		return _ids.size()

	## The middle of the bars, not the pivot the bike leans about (at the stand, 60 cm below the hands).
	func handle() -> Vector3:
		return _bars.global_position if _bars != null else node.global_position

	## A grip within reach of the tip that no hand is on: the second hand takes the OTHER one.
	func can_grab(tip: Vector3, scale: float) -> bool:
		for g in _grips:
			if g.global_position.distance_to(tip) <= reach() * scale and not _occupied(g):
				return true
		return false

	func _occupied(grip: Node3D) -> bool:
		for id in _ids:
			var ctrl := _ctrls.get(id) as XRController3D
			if ctrl != null and is_instance_valid(ctrl) and PokeTip.tip_of(ctrl).distance_to(grip.global_position) <= reach() * 2.0:
				return true
		return false

	func usable() -> bool:
		return is_instance_valid(node) and node.is_visible_in_tree() and not _grips.is_empty()

	## BOTH grips are outlined, each by its own state: yellow while it can be taken, none with a hand on it (one outline for a pair of hands would say that one grip is the way in).
	func show_outline(on: bool) -> void:
		if _outlines.is_empty():
			if not on or not is_instance_valid(panel):
				return
			for g in _grips:
				var outline := WidgetOutline.attach(panel)
				outline.set_source(g as MeshInstance3D)
				outline.set_color(WidgetOutline.SELECT_COLOR)
				_outlines.append(outline)
		for i in _outlines.size():
			_outlines[i].sync(on and not _occupied(_grips[i]))

	func attach_hand(ctrl: XRController3D, id: int, tip: Vector3) -> void:
		var p := frame().affine_inverse() * tip
		if _ids.is_empty():
			# The first hand has the bars as they stand.
			_base = panel.steering()
			_base_pull = panel.bars_pitch()
			steer = _base
			pull = _base_pull
		else:
			_fold()
		_ids.append(id)
		_ctrls[id] = ctrl
		_now[id] = p
		_ref[id] = p
		if holder == null:
			holder = ctrl
		else:
			holder2 = ctrl

	func drag_hand(id: int, tip: Vector3, _delta: float) -> void:
		if not _ids.has(id):
			return
		_now[id] = frame().affine_inverse() * tip
		_solve()

	func detach_hand(id: int) -> void:
		if not _ids.has(id):
			return
		# What is left of the deflection stays, and the hand that is still on the bars goes on from there.
		_fold()
		_ids.erase(id)
		_ctrls.erase(id)
		_now.erase(id)
		_ref.erase(id)
		holder = _ctrls.get(_ids[0]) as XRController3D if not _ids.is_empty() else null
		holder2 = _ctrls.get(_ids[1]) as XRController3D if _ids.size() > 1 else null

	func release() -> void:
		_ids.clear()
		_ctrls.clear()
		_now.clear()
		_ref.clear()
		holder = null
		holder2 = null

	## What the deflection is now becomes the base, and every hand's reference is where it is: a hand that joins or leaves moves nothing.
	func _fold() -> void:
		_base = steer
		_base_pull = pull
		for id in _ids:
			_ref[id] = _now[id]

	func _solve() -> void:
		var count := _ids.size()
		if count == 0:
			return
		if not _two_axes:
			# A motorbike's bars lean it as the hands push them sideways, the hands' mean when there are two.
			var dx := 0.0
			for id in _ids:
				dx += (_now[id] as Vector3).x - (_ref[id] as Vector3).x
			steer = clampf(_base + dx / float(count) / ArcadePanelHands.BARS_THROW, -1.0, 1.0)
			return
		# A bicycle's bars turn about the stem as the hands take them round: right is clockwise seen from above, a turn about -Y.
		steer = clampf(_base - _yaw() / deg_to_rad(ArcadeControlModule.BARS_YAW_DEG), -1.0, 1.0)
		# They tip with the hands' lift and, with both on them, their push or pull: toward the player is +Z, up is +Y, a pull is positive.
		var dy := 0.0
		var dz := 0.0
		for id in _ids:
			dy += (_now[id] as Vector3).y - (_ref[id] as Vector3).y
			dz += (_now[id] as Vector3).z - (_ref[id] as Vector3).z
		var push := (dy + (dz if count > 1 else 0.0)) / float(count)
		pull = clampf(_base_pull + push / ArcadePanelHands.BARS_PITCH_THROW, -1.0, 1.0)

	## How far the bars have been turned since the base, radians about +Y (counter-clockwise from above is positive): by the line between two hands, or one hand's angle about the stem.
	func _yaw() -> float:
		if _ids.size() > 1:
			var a := _ids[0]
			var b := _ids[1]
			var v0 := Vector2((_ref[b] as Vector3).x - (_ref[a] as Vector3).x, (_ref[b] as Vector3).z - (_ref[a] as Vector3).z)
			var v := Vector2((_now[b] as Vector3).x - (_now[a] as Vector3).x, (_now[b] as Vector3).z - (_now[a] as Vector3).z)
			if v0.length() >= ArcadePanelHands.BARS_PAIR_MIN and v.length() > 0.02:
				return wrapf(_angle(v) - _angle(v0), -PI, PI)
		var first := _ids[0]
		var axis := Vector2(node.position.x, node.position.z)
		var r0 := Vector2((_ref[first] as Vector3).x, (_ref[first] as Vector3).z) - axis
		var r := Vector2((_now[first] as Vector3).x, (_now[first] as Vector3).z) - axis
		if r0.length() < ArcadePanelHands.BARS_AXIS_MIN or r.length() < ArcadePanelHands.BARS_AXIS_MIN:
			return 0.0
		return wrapf(_angle(r) - _angle(r0), -PI, PI)

	## The angle of a horizontal vector (x, z) about +Y: from +X toward -Z.
	static func _angle(v: Vector2) -> float:
		return atan2(-v.y, v.x)

	func stick(side: int) -> Vector2:
		if holder == null or side != 0:
			return Vector2.ZERO
		return Vector2(steer, -pull)


## A bicycle's crank: turned with the hand like a dial; the speed it is turned at is the deflection, forward up.
class CrankGrab extends ControlGrab:
	## Forward positive, radians.
	var angle := 0.0
	var rate := 0.0
	var _alpha := 0.0
	var _pedals: Array[Node3D] = []

	func _init(p_panel: ArcadeControlModule, p_node: Node3D) -> void:
		kind = &"crank"
		panel = p_panel
		node = p_node
		for n in ["CrankPedalL", "CrankPedalR"]:
			var pedal := p_node.find_child(n, true, false) as Node3D
			if pedal != null:
				_pedals.append(pedal)
		if not _pedals.is_empty():
			trace = _pedals[0] as MeshInstance3D

	func reach() -> float:
		return ArcadePanelHands.CRANK_REACH

	func can_grab(tip: Vector3, scale: float) -> bool:
		for g in _pedals:
			if g.global_position.distance_to(tip) <= reach() * scale:
				return true
		return false

	func usable() -> bool:
		return is_instance_valid(node) and node.is_visible_in_tree() and not _pedals.is_empty()

	## Round the axle (the crank turns about its own X), the angle of a point as the module draws a forward turn: the top
	## of the crank going away from the rider is positive.
	func _forward(tip: Vector3) -> float:
		var p := frame().affine_inverse() * tip - node.position
		return atan2(-p.z, p.y)

	func begin(tip: Vector3) -> void:
		angle = panel.crank_angle()
		rate = 0.0
		_alpha = _forward(tip)

	func drag(tip: Vector3, delta: float) -> void:
		var p := frame().affine_inverse() * tip - node.position
		# On its axle the angle is only noise.
		if Vector2(p.y, p.z).length() < 0.04:
			return
		var a := _forward(tip)
		var d := wrapf(a - _alpha, -PI, PI)
		_alpha = a
		angle = wrapf(angle + d, -PI, PI)
		if delta > 0.0:
			rate = lerpf(rate, clampf(d / delta / ArcadeControlModule.CRANK_SPEED, -1.0, 1.0), 0.5)

	func end() -> void:
		rate = 0.0

	func stick(side: int) -> Vector2:
		return Vector2(0.0, rate) if holder != null and side == 1 else Vector2.ZERO


## A lever in a slot (Panic Park): pushed along it.
class SlideGrab extends ControlGrab:
	var steer := 0.0
	var _x0 := 0.0
	var _base := 0.0

	func _init(p_panel: ArcadeControlModule, p_node: Node3D) -> void:
		kind = &"slide"
		panel = p_panel
		node = p_node
		trace = p_node.find_child("LeverBall", true, false) as MeshInstance3D

	func handle() -> Vector3:
		return node.global_transform * Vector3(0.0, 0.0, ArcadeCabinetBuilder.SLOT_HANDLE_Z)

	func reach() -> float:
		return ArcadePanelHands.SLIDE_REACH

	func begin(tip: Vector3) -> void:
		_x0 = (frame().affine_inverse() * tip).x
		_base = panel.steering()
		steer = _base

	func drag(tip: Vector3, _delta: float) -> void:
		steer = clampf(_base + ((frame().affine_inverse() * tip).x - _x0) / ArcadeCabinetSpecs.SLOT_TRAVEL, -1.0, 1.0)

	func stick(side: int) -> Vector2:
		return Vector2(steer, 0.0) if holder != null and side == 0 else Vector2.ZERO


## A flight cockpit's throttle lever: pushed forward or pulled back and left where it is. The value is the right stick's Y (forward up); a lever
## in the middle sends nothing, as a stick at rest does.
class ThrottleGrab extends ControlGrab:
	## -1 pulled all the way back .. 1 pushed all the way forward.
	var value := 0.0
	var _z0 := 0.0
	var _base := 0.0

	func _init(p_panel: ArcadeControlModule, p_node: Node3D) -> void:
		kind = &"throttle"
		panel = p_panel
		node = p_node
		trace = p_node.find_child("ThrottleKnob", true, false) as MeshInstance3D

	## The knob, where the lever's top is now.
	func handle() -> Vector3:
		return trace.global_position if trace != null else node.global_transform * Vector3(0.0, 0.2, 0.0)

	func reach() -> float:
		return ArcadePanelHands.THROTTLE_REACH

	func begin(tip: Vector3) -> void:
		_z0 = (frame().affine_inverse() * tip).z
		# From where the lever is, whatever put it there (the pad's stick, a hand that left it).
		_base = panel.throttle_amount()
		value = _base

	func drag(tip: Vector3, _delta: float) -> void:
		# Forward is -Z in the cockpit's frame.
		value = clampf(_base - ((frame().affine_inverse() * tip).z - _z0) / ArcadePanelHands.THROTTLE_THROW, -1.0, 1.0)

	## Let go, the lever stays (value is kept); only a machine that goes off, or a run that ends, puts it back (reset).
	func reset() -> void:
		value = 0.0

	## Held or left alone, the lever sends where it stands: not at rest in the middle.
	func stick(side: int) -> Vector2:
		if side != 1 or absf(value) < 0.02:
			return Vector2.ZERO
		return Vector2(0.0, value)
