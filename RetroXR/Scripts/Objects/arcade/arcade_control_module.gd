## ArcadeControlModule — one player's panel: a stick, six buttons and START, as ONE controller.
##
## The kind is `stick_buttons`. The parts are pictures that follow the input: the stick leans
## and the caps sink while their bits are held. Aiming at the panel lights all of it and a press
## attaches you to it (`PanelGrip`, see ArcadePanelGrip), as you would pick up a controller, except
## that you hold on to it instead of carrying it: while attached, your own controller plays this
## player (ArcadeInput). A headset's hands can also work the controls themselves, no attaching
## first: a fingertip presses a cap, the trigger takes hold of a stick, a wheel, a dial
## (ArcadePanelHands). A part in a hand goes where the hand takes it; the rest follow the input.
##
## Parts are found by name inside this module's subtree: `Btn1`..`Btn6`, `Start` (meshes),
## `StickPivot` (a Node3D the shaft and ball hang from), `DialPivot` (a Node3D a paddle knob
## hangs from, turned by LEFT and RIGHT) and `PanelGrip` (the pointable box). A panel built for
## its game (ArcadeCabinetBuilder) may also carry `StickPivot2` (a second stick, leaning with the
## right analog stick or the four face buttons), `BallPivot` (a trackball, rolling with the left
## stick), `WheelPivot` (a steering wheel, turning about its own Y with the left stick or LEFT and
## RIGHT), `GasPivot` and `BrakePivot` (pedals, tipping with R2 and L2), `ShifterPivot` (a gear
## lever, thrown with the game's own shift button: ArcadeGameProfile.shifter), `LeanPivot` (a motorbike leaning with the steering) and
## `PadUp`/`PadDown`/`PadLeft`/`PadRight` (a dance stage's arrows, sinking with the directions; DDR Solo's `PadUpLeft` and `PadUpRight` sink with buttons 3 and 4), `BarsPivot` (a bicycle's
## handlebars, turned with the left stick's X and tipped with its Y), `CrankPivot` (its crank, turned by the right stick's
## Y, faster the further it is pushed), `SlidePivot` (a lever in a slot, sliding with the left stick's X) and `ThrottlePivot` (a flight
## cockpit's throttle lever, the right stick's Y: forward is up, and it stays where it is left). A cockpit on a moving base has `MotionPivot`
## among this panel's ancestors, and tilts with the stick and the wheel (`tick`, when the player's choice and the form allow it).
## Every one is optional: a Neo Geo panel has four buttons, a gun cabinet's has only START.
class_name ArcadeControlModule
extends ArcadeModule

signal attach_changed(player: int, attached: bool)

## How far the stick leans at full deflection.
const STICK_TILT_DEG := 16.0
## Per-frame blend toward the target lean.
const STICK_BLEND := 0.35
## How far a pressed cap sinks into the deck.
const CAP_PRESS := 0.006
## A cap's label: font size in pixels, metres a pixel, how far above the deck it is printed, and the
## cap's radius when its mesh cannot say.
const LABEL_FONT := 20
const LABEL_PIXEL := 0.00045
const LABEL_LIFT := 0.0015
const CAP_RADIUS := 0.0155
## How fast a held LEFT or RIGHT turns a dial, radians a second (about one turn a second).
const DIAL_SPEED := TAU
## How far a steering wheel turns at full lock either way, and a bike leans.
const WHEEL_LOCK_DEG := 120.0
const LEAN_DEG := 14.0
## How far a pedal tips down when pressed, and a gear lever is thrown.
const PEDAL_DEG := 16.0
const SHIFT_DEG := 22.0
## How fast a trackball rolls at full deflection, radians a second.
const BALL_SPEED := 9.0
## A bicycle's bars at full lock either way and full push or pull, and its crank at full deflection (a brisk 90 rpm), a turn
## a second and a half.
const BARS_YAW_DEG := 28.0
const BARS_PITCH_DEG := 12.0
const CRANK_SPEED := TAU * 1.5
## A stick's full deflection, as the analog axes are sent.
const AXIS_FULL := 32767.0
## How far over the panel's parts the hint it says its controls with floats, and how far over a control a hand has taken (metres).
const PROMPT_MARGIN := 0.12
const PROMPT_LIFT := 0.22
## A flight throttle at full travel either way from the middle, the angle its lever is thrown through.
const THROTTLE_DEG := 32.0
## A moving base banks this far at full stick or wheel, noses this far up or down at full pull or push or at full gas or brake, and follows what
## the player does at this rate (per second): a few degrees, because a head carried on a tilting seat is a head being rocked.
const MOTION_ROLL_DEG := 4.0
const MOTION_PITCH_DEG := 3.0
const MOTION_RATE := 4.0
## The R-360's rings turn far more than a base tips: the outer one about the pod's lateral axis (a full pull is 96 degrees over the top), the rear one about the view's own.
const RING_PITCH_DEG := 120.0
const RING_ROLL_DEG := 120.0

var _caps: Array[Node3D] = []
## Each cap's flange (`<cap>Rim`, fixed, of the cap's colour), or null where a scene has none.
var _cap_rims: Array[Node3D] = []
var _cap_rest: Array[Vector3] = []
## How far each cap moves when its bit is held, in its parent's frame: into the deck (CAP_PRESS) unless the part says otherwise (`press_offset`: a bass drum's pedal goes down, not into a slope).
var _cap_press: Array[Vector3] = []
var _cap_bits: Array[int] = []
## Which of the six buttons each cap is (0-based), or -1 for START, which every game has.
var _cap_button: Array[int] = []
## The label on a cap, made the first time a core names one (Label3D, a child of the cap so it sinks with it).
var _cap_labels: Dictionary = {}
var _stick: Node3D = null
var _stick2: Node3D = null
var _ball: Node3D = null
var _wheel: Node3D = null
var _gas: Node3D = null
var _brake: Node3D = null
var _shifter: Node3D = null
var _lean: Node3D = null
var _bars: Node3D = null
var _crank: Node3D = null
var _slide: Node3D = null
var _throttle: Node3D = null
## Where a slot's lever rests: the carriage slides along X from here.
var _slide_rest := Vector3.ZERO
## The moving base this panel stands on (an ancestor named `MotionPivot`, its `motion_centre` meta the point it tilts about, in its parent's
## frame), where it is tilted to now and where it is going: x banks (-1..1, right positive), y noses up (-1..1). Never moved when the player's
## choice is off (`motion_on`).
var _motion: Node3D = null
## The R-360 pod's two rings (on the base, `RingOuter` and `RingInner`), or null.
var _ring_outer: Node3D = null
var _ring_inner: Node3D = null
var _motion_centre := Vector3.ZERO
var _motion_now := Vector2.ZERO
var _motion_target := Vector2.ZERO
var _motion_written := false
## The player's choice, asked once a frame the base has something to do (the tests set it).
var motion_override := -1
## How fast the crank is being pedalled now (-1..1, forward positive) and how far round it has come.
var _crank_rate := 0.0
var _crank_angle := 0.0
## Each pivot's pose at rest, so a lean or a tip is laid over it rather than replacing it.
var _rest_basis: Dictionary = {}
## What the analog parts are moving toward (-1..1 steering, 0..1 pedals and lever) and are at now.
var _analog_target := {}
var _analog_now := {}
var _ball_roll := Vector2.ZERO
var _analog_written := false
## Whether this panel has any of the parts the analog state moves (a wheel, pedals, a lever, a bike).
var _has_analog := false
var _stick2_target := Vector2.ZERO
var _stick2_current := Vector2.ZERO
var _dial: Node3D = null
var _dial_dir := 0.0
## How far the dial has turned, clockwise seen by the player.
var _dial_angle := 0.0
var _grip: ArcadePanelGrip = null
## The hands on this panel's controls (null until the parts are found).
var _hands: ArcadePanelHands = null
var _stick_target := Vector2.ZERO
var _stick_current := Vector2.ZERO
## The mask last drawn, so an unchanged one costs nothing: show_state runs every frame, and a
## `position =` dirties the transform and goes to the renderer even when it writes the value it holds.
var _shown_mask := -1
var _shown_axes := Vector4i.ZERO
## The game's gear lever (ArcadeGameProfile.shifter(): {} none, {button, toggle}, {up, down}) and where the lever stands. A toggle shifter is
## where the game's gear is as far as the cabinet can tell: it flips at every press of the shift button, counted on the button's rising edge,
## whoever pressed it (a pad, a finger, the lever itself); a held one is high while the button is down; a sequential box goes high on `up`
## and low on `down`.
var _shift_cfg: Dictionary = {}
var _shift_high := false
## Whether the stick's basis has been written at all (the first tick always writes it once).
var _stick_written := false
## What the last prompt said of this game's buttons and pedals (ArcadePrompts.signature), so the same game is not described again at every take.
var _prompted_game := ""


func _init() -> void:
	kind = ArcadeProfiles.KIND_STICK_BUTTONS


func attach(p_cabinet: RetroSystemModel) -> void:
	super.attach(p_cabinet)
	_caps.clear()
	_cap_rims.clear()
	_cap_rest.clear()
	_cap_press.clear()
	_cap_bits.clear()
	_cap_button.clear()
	for i in ArcadeProfiles.BUTTON_COUNT:
		_add_cap("Btn%d" % (i + 1), ArcadeProfiles.BUTTON_BITS[i], i)
	_add_cap("Start", ArcadeProfiles.START_BIT, -1)
	# A dance stage's arrows are the directions (index -2: not one of the six buttons, never hidden).
	_add_cap("PadUp", ControllerBindings.JOYPAD_UP, -2)
	_add_cap("PadDown", ControllerBindings.JOYPAD_DOWN, -2)
	_add_cap("PadLeft", ControllerBindings.JOYPAD_LEFT, -2)
	_add_cap("PadRight", ControllerBindings.JOYPAD_RIGHT, -2)
	# DDR Solo's two panels at the screen's corners are MAME's buttons 3 and 4 ("P1 Up-Left", "P1 Up-Right": ksys573.cpp's ddrsolo).
	_add_cap("PadUpLeft", ArcadeProfiles.button_bit(3), -2)
	_add_cap("PadUpRight", ArcadeProfiles.button_bit(4), -2)
	_stick = find_child("StickPivot", true, false) as Node3D
	_stick2 = find_child("StickPivot2", true, false) as Node3D
	_ball = find_child("BallPivot", true, false) as Node3D
	_wheel = find_child("WheelPivot", true, false) as Node3D
	_gas = find_child("GasPivot", true, false) as Node3D
	_brake = find_child("BrakePivot", true, false) as Node3D
	_shifter = find_child("ShifterPivot", true, false) as Node3D
	_lean = find_child("LeanPivot", true, false) as Node3D
	_bars = find_child("BarsPivot", true, false) as Node3D
	_crank = find_child("CrankPivot", true, false) as Node3D
	_slide = find_child("SlidePivot", true, false) as Node3D
	_slide_rest = _slide.position if _slide != null else Vector3.ZERO
	_throttle = find_child("ThrottlePivot", true, false) as Node3D
	_motion = _ancestor_named(&"MotionPivot")
	_ring_outer = _motion.find_child("RingOuter", true, false) as Node3D if _motion != null else null
	_ring_inner = _motion.find_child("RingInner", true, false) as Node3D if _motion != null else null
	_motion_centre = Vector3(_motion.get_meta(&"motion_centre", Vector3.ZERO)) if _motion != null else Vector3.ZERO
	_motion_now = Vector2.ZERO
	_motion_target = Vector2.ZERO
	_motion_written = false
	_rest_basis.clear()
	for pivot: Node3D in [_wheel, _gas, _brake, _shifter, _lean, _stick2, _ball, _bars, _crank, _throttle]:
		if pivot != null:
			_rest_basis[pivot] = pivot.basis
	_has_analog = _wheel != null or _lean != null or _gas != null or _brake != null or _shifter != null \
		or _bars != null or _slide != null or _throttle != null
	_dial = find_child("DialPivot", true, false) as Node3D
	_grip = find_child("PanelGrip", true, false) as ArcadePanelGrip
	if _grip != null:
		_grip.toggled.connect(func(on: bool) -> void: attach_changed.emit(player, on))
	_hands = ArcadePanelHands.new(self)


## Whatever a hand held or pressed here is let go before the panel is: a laser switched off for it comes back.
func _exit_tree() -> void:
	if _hands != null:
		_hands.release_all()


## The nearest ancestor with this name, or null.
func _ancestor_named(node_name: StringName) -> Node3D:
	var n := get_parent()
	while n != null:
		if n.name == node_name and n is Node3D:
			return n as Node3D
		n = n.get_parent()
	return null


func _add_cap(node_name: String, bit: int, button: int) -> void:
	var cap := find_child(node_name, true, false) as Node3D
	if cap == null:
		return
	_caps.append(cap)
	_cap_rims.append(find_child(node_name + "Rim", true, false) as Node3D)
	_cap_rest.append(cap.position)
	_cap_press.append(cap.get_meta(&"press_offset", Vector3(0.0, 0.0, -CAP_PRESS)) as Vector3)
	_cap_bits.append(bit)
	_cap_button.append(button)


## Show only what the game in the bay has: the panel at all (a one-player game has no second),
## the stick, the caps it reads, and the words the core gave them. `profile` null, or a game the
## table does not know, puts the whole panel back.
func apply_profile(profile: ArcadeGameProfile) -> void:
	var cfg: Dictionary = profile.shifter() if profile != null else {}
	if cfg != _shift_cfg:
		_shift_cfg = cfg
		_shift_high = false
	var on_panel := profile == null or profile.panel_visible(player)
	visible = on_panel
	ArcadeModule.set_pointable(_grip, on_panel)
	if not on_panel:
		set_attached(false)
	if _stick != null:
		_stick.visible = profile == null or profile.stick_visible()
	# A throttle lever the game does not read is not drawn (a cockpit is built for its game, so this is a seam for a cockpit that stays).
	if _throttle != null:
		_throttle.visible = profile == null or profile.has_throttle()
	for i in _caps.size():
		var button := _cap_button[i]
		if button < 0:
			continue
		_caps[i].visible = profile == null or profile.button_visible(player, button)
		# A button the game does not have leaves no empty flange behind.
		if _cap_rims[i] != null:
			_cap_rims[i].visible = _caps[i].visible
		_label_cap(i, "" if profile == null else profile.button_label(player, button))


## Put words on a cap, or take them off. The words are printed on the deck just under the cap (a cap is
## 31 mm across and tilts away from a player, so words on its top cannot be read); they do not sink with it.
func _label_cap(index: int, text: String) -> void:
	var label := _cap_labels.get(index) as Label3D
	if text.is_empty():
		if label != null:
			label.visible = false
		return
	if label == null:
		var cap := _caps[index]
		var holder := cap.get_parent() as Node3D
		if holder == null:
			return
		label = Label3D.new()
		label.name = "CapLabel"
		label.font_size = LABEL_FONT
		label.pixel_size = LABEL_PIXEL
		label.outline_size = 8
		label.modulate = Color.WHITE
		label.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
		label.shaded = false
		label.double_sided = false
		# The monitor-side row of caps is labelled above its caps, the rest below theirs: two rows of
		# caps are only ~50 mm apart, and words under the top row land on the bottom row.
		var above := _cap_rest[index].y > _mean_cap_y() + 0.005
		label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM if above else VERTICAL_ALIGNMENT_TOP
		label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var radius := CAP_RADIUS
		# Measured on the flange where the button has one: it is the widest part, and a word printed
		# inside it would be under it.
		var shape := _cap_rims[index] if _cap_rims[index] != null else cap
		if shape is MeshInstance3D and (shape as MeshInstance3D).mesh != null:
			var box := (shape as MeshInstance3D).get_aabb()
			radius = maxf(box.size.x, box.size.y) * 0.5
		label.position = _cap_rest[index] + Vector3(0.0, (radius + 0.002) * (1.0 if above else -1.0), LABEL_LIFT)
		holder.add_child(label)
		_cap_labels[index] = label
	label.text = text
	label.visible = true


## The mean height of the six buttons' caps on the panel (0 with none).
func _mean_cap_y() -> float:
	var sum := 0.0
	var n := 0
	for i in _caps.size():
		if _cap_button[i] >= 0:
			sum += _cap_rest[i].y
			n += 1
	return sum / float(n) if n > 0 else 0.0


## The label text on a cap (0-based, the six buttons), or "" when it has none, for the tests.
func cap_label(button: int) -> String:
	for i in _caps.size():
		if _cap_button[i] == button:
			var label := _cap_labels.get(i) as Label3D
			return label.text if label != null and label.visible else ""
	return ""


## Is the cap for button `button` (0-based) drawn, for the tests.
func cap_shown(button: int) -> bool:
	for i in _caps.size():
		if _cap_button[i] == button:
			return _caps[i].visible
	return false


func stick_shown() -> bool:
	return _stick != null and _stick.visible


# ── prompts (ArcadePrompts) ─────────────────────────────────────────────────

## The buttons this panel shows, `{n: MAME's button 1 to 10, label: the core's word for it or ""}`: what a prompt names.
func shown_buttons() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in ArcadeProfiles.BUTTON_COUNT:
		if cap_shown(i):
			out.append({"n": i + 1, "label": cap_label(i)})
	return out


## A hand took hold of a control of kind `kind` (ArcadePanelHands): the panel says what it is for and, the first time for this game, which buttons the game has under the fingers and that there are pedals.
## The buttons a game has are not said again at every take of its stick: a player who has been told them has them, and a game that changes (a morph, another board) says them afresh.
func prompt_control(kind: StringName, ctrl: XRController3D, handle: Vector3) -> void:
	var rows := ArcadePrompts.control_rows(&"lean" if kind == &"bars" and _bars == null else kind)
	var game := ArcadePrompts.button_rows(shown_buttons())
	if kind == &"wheel" and _gas != null and _gas.is_visible_in_tree():
		game.append_array(ArcadePrompts.pedal_rows())
	var told := ArcadePrompts.signature(game)
	if told != _prompted_game:
		_prompted_game = told
		rows.append_array(game)
	_say(rows, ctrl, false, handle + Vector3.UP * PROMPT_LIFT)


## The player attached to this panel, with a headset's controller or the keyboard: how to play it. `button_map` and `stick_map` are the controller's for this machine, `systemid` the scope of the keys.
func prompt_attached(vr: bool, button_map: Dictionary, stick_map: Dictionary, systemid: String) -> void:
	var buttons := shown_buttons()
	_say(ArcadePrompts.attach_rows_vr(player, stick_shown(), buttons, button_map, stick_map) if vr
		else ArcadePrompts.attach_rows_desktop(player, stick_shown(), buttons, systemid), null, not vr, Vector3.INF)


## The panel's hint, with exactly these rows, over the control that was taken (`over`, a point in the world: where the hand is, so where the eyes are) or, for a player who attached, floating clear of what is on
## the panel (`over` infinite); a verb row counts a use as it is said (HeldHint.LEARNED_AFTER), a row about the game does not.
func _say(rows: Array, ctrl: XRController3D, desktop: bool, over: Vector3) -> void:
	var hint := HeldHint.for_node(self, false, 0.30)
	hint.clear_rows()
	for row: Array in rows:
		hint.add_row(row[0], row[1], row[2], row[3], HeldHint.WHEN_HELD)
	if over.is_finite():
		hint.pin_to_host(to_local(over))
	else:
		hint.unpin()
		hint.fit_above(PROMPT_MARGIN)
	if desktop:
		hint.on_taken_desktop()
	else:
		hint.on_taken(ctrl)
	for row: Array in rows:
		if not ArcadePrompts.is_game_row(row[0]):
			hint.note_used(row[0])


## The hint the panel carries (null until it has said something), for the tests.
func prompt_hint() -> HeldHint:
	return get_node_or_null("HeldHint") as HeldHint


## Attach to (or let go of) this panel, as a press on it does.
func set_attached(on: bool) -> void:
	# A panel the game does not use (apply_profile) is not there to attach to.
	if _grip != null and (visible or not on):
		_grip.set_attached(on)


func is_attached() -> bool:
	return _grip != null and _grip.attached


## Whether this is a momentary panel (a gun cabinet's START) and it is being pressed now.
func start_held() -> bool:
	return _grip != null and _grip.momentary and _grip.held


func grip() -> ArcadePanelGrip:
	return _grip


## Show the state that reached the core: sink the caps it presses, lean the stick, and move what
## a game's own panel has (a wheel, the pedals, a second stick...). `mask` is the joypad mask, `axes`
## the analog sticks as sent (left x, left y, right x, right y).
func show_state(mask: int, axes: Vector4i = Vector4i.ZERO) -> void:
	if mask == _shown_mask and axes == _shown_axes:
		return
	var before := _shown_mask
	_shown_mask = mask
	_shown_axes = axes
	for i in _caps.size():
		var pressed := (mask & (1 << _cap_bits[i])) != 0
		_caps[i].position = _cap_rest[i] + (_cap_press[i] if pressed else Vector3.ZERO)
	var x := float((mask >> ControllerBindings.JOYPAD_RIGHT) & 1) \
		- float((mask >> ControllerBindings.JOYPAD_LEFT) & 1)
	var y := float((mask >> ControllerBindings.JOYPAD_DOWN) & 1) \
		- float((mask >> ControllerBindings.JOYPAD_UP) & 1)
	var left := Vector2(float(axes.x), float(axes.y)) / AXIS_FULL
	var right := Vector2(float(axes.z), float(axes.w)) / AXIS_FULL
	# A digital direction wins; an analog stick (Prop Cycle's, a driving game's wheel) moves it otherwise.
	var dirs := Vector2(x, y)
	var steer := dirs if dirs != Vector2.ZERO else left.limit_length(1.0)
	_stick_target = steer
	_dial_dir = steer.x
	_ball_roll = steer
	if _has_analog:
		_analog_target["steer"] = clampf(steer.x, -1.0, 1.0)
		_analog_target["pitch"] = clampf(steer.y, -1.0, 1.0)
		_analog_target["gas"] = 1.0 if (mask >> ControllerBindings.JOYPAD_R2) & 1 else 0.0
		_analog_target["brake"] = 1.0 if (mask >> ControllerBindings.JOYPAD_L2) & 1 else 0.0
		_step_shift(before, mask)
		_analog_target["shift"] = 1.0 if _shift_high else 0.0
		# The throttle is the right stick's Y: pushed up (negative as sent) is forward, the lever away from the player.
		_analog_target["throttle"] = clampf(-right.y, -1.0, 1.0)
	# The second stick: the right analog stick, or the four face buttons as its directions (Robotron's
	# fire stick is the diamond on a pad: X up, B down, Y left, A right).
	var face := Vector2(float((mask >> ControllerBindings.JOYPAD_A) & 1) - float((mask >> ControllerBindings.JOYPAD_Y) & 1),
		float((mask >> ControllerBindings.JOYPAD_B) & 1) - float((mask >> ControllerBindings.JOYPAD_X) & 1))
	_stick2_target = face if face != Vector2.ZERO else right.limit_length(1.0)
	# The crank: the right stick's Y, up (negative as sent) being forward.
	_crank_rate = clampf(-right.y, -1.0, 1.0)
	# The moving base: banks into the turn, noses up with a pull on the stick and with the gas, down with the brake.
	if _motion != null:
		var pedals := float((mask >> ControllerBindings.JOYPAD_R2) & 1) - float((mask >> ControllerBindings.JOYPAD_L2) & 1)
		_motion_target = Vector2(clampf(steer.x, -1.0, 1.0), clampf(steer.y * 0.8 + pedals * 0.5, -1.0, 1.0))


## The gear lever follows the game's own shift button (or the two of a sequential box), seen in what the player is sending. A press the
## cabinet cannot see (the game shifted down by itself) is not known: the lever is where the presses left it.
func _step_shift(before: int, mask: int) -> void:
	if _shift_cfg.is_empty():
		_shift_high = false
		return
	if _shift_cfg.has("up"):
		var up := ArcadeProfiles.button_bit(int(_shift_cfg["up"]))
		var down := ArcadeProfiles.button_bit(int(_shift_cfg["down"]))
		if up >= 0 and _rose(before, mask, up):
			_shift_high = true
		if down >= 0 and _rose(before, mask, down):
			_shift_high = false
		return
	var bit := ArcadeProfiles.button_bit(int(_shift_cfg.get("button", 0)))
	if bit < 0:
		return
	if bool(_shift_cfg.get("toggle", false)):
		if _rose(before, mask, bit):
			_shift_high = not _shift_high
	else:
		_shift_high = (mask >> bit) & 1 == 1


## Did `bit` go from up to down between two masks? (`before` is -1 until the first state is shown: nothing was down then.)
static func _rose(before: int, mask: int, bit: int) -> bool:
	return (mask >> bit) & 1 == 1 and (maxi(before, 0) >> bit) & 1 == 0


## The game's gear lever (ArcadeGameProfile.shifter), and whether it is high now, for the hands and the tests.
func shift_config() -> Dictionary:
	return _shift_cfg


func shift_high() -> bool:
	return _shift_high


## A new run starts with the game in its first gear.
func reset_shift() -> void:
	_shift_high = false
	_shown_mask = -1


## The run is over: a moving base settles, a latched throttle lever is back in the middle. (The next run starts from rest.)
func rest() -> void:
	_motion_target = Vector2.ZERO
	if _throttle != null:
		_analog_target["throttle"] = 0.0
	if _hands != null:
		_hands.reset_latched()


func tick(delta: float) -> void:
	_tick_analog(delta)
	_tick_motion(delta)
	if _dial != null:
		if _in_hand(&"dial"):
			_dial_angle = _hands.dial_angle()
			_dial.basis = Basis(Vector3.BACK, -_dial_angle)
		elif _dial_dir != 0.0:
			# Right is clockwise seen by the player, and a turn about +Z (toward the player) is counter-clockwise.
			_dial_angle = wrapf(_dial_angle + _dial_dir * DIAL_SPEED * delta, -PI, PI)
			_dial.basis = Basis(Vector3.BACK, -_dial_angle)
	if _stick == null:
		return
	if _in_hand(&"stick", 0):
		# A stick in a hand goes where the hand takes it, with no easing between. Its target is left alone: when the
		# hand lets go the stick eases back to whatever the input says then.
		_stick_current = _hands.stick_lean(0)
		_stick_written = true
		_pose_stick()
		return
	# Settled: the lerp never reaches its target, so it used to rewrite the same basis every frame for ever.
	if _stick_written and _stick_current == _stick_target:
		return
	_stick_written = true
	_stick_current = _stick_current.lerp(_stick_target, STICK_BLEND)
	if _stick_current.distance_squared_to(_stick_target) < 1.0e-6:
		_stick_current = _stick_target
	_pose_stick()


## Deck-local: +X right, +Y toward the monitor, the shaft along +Z. A turn about X
## leans it toward -Y (the player) for a positive angle, which is "down" on the
## pad; a turn about Y leans it toward +X, which is "right".
func _pose_stick() -> void:
	_stick.basis = Basis.from_euler(Vector3(
		deg_to_rad(_stick_current.y * STICK_TILT_DEG),
		deg_to_rad(_stick_current.x * STICK_TILT_DEG), 0.0))


func _in_hand(kind: StringName, index: int = 0) -> bool:
	return _hands != null and _hands.holds(kind, index)


## Whether the player's choice lets a base move (AppPrefs.arcade_motion; automatic is on at a desk, off in a headset).
func motion_on() -> bool:
	if motion_override >= 0:
		return motion_override == 1
	return AppPrefs.arcade_motion_enabled(MenuStyle.is_vr_mode())


## The moving base eases toward where the play puts it and is tilted about its centre (a few degrees; the seat and cabin on it go with it).
func _tick_motion(delta: float) -> void:
	if _motion == null:
		return
	var want := _motion_target if motion_on() else Vector2.ZERO
	if _motion_now != want:
		_motion_now = _motion_now.lerp(want, minf(1.0, delta * MOTION_RATE))
		if _motion_now.distance_squared_to(want) < 1.0e-6:
			_motion_now = want
	elif _motion_written:
		return
	_motion_written = true
	# Banked into the turn (the right side down for a push to the right), nosed up for a pull (the front rises).
	var b := Basis.from_euler(Vector3(deg_to_rad(MOTION_PITCH_DEG) * _motion_now.y, 0.0, -deg_to_rad(MOTION_ROLL_DEG) * _motion_now.x))
	_motion.transform = Transform3D(b, _motion_centre - b * _motion_centre)
	# The R-360's rings turn with it (the seat does not): the outer one over the top for a pull, the rear one round the view's axis for a push to the side.
	if _ring_outer != null:
		_ring_outer.basis = Basis(Vector3.RIGHT, deg_to_rad(RING_PITCH_DEG) * _motion_now.y)
	if _ring_inner != null:
		_ring_inner.basis = Basis(Vector3.BACK, -deg_to_rad(RING_ROLL_DEG) * _motion_now.x)


## How far the base is tilted now (x banked right, y nose up, -1..1), for the tests and the probe.
func motion_state() -> Vector2:
	return _motion_now


## The stick's lean as last shown, for the tests and the probe.
func stick_lean() -> Vector2:
	return _stick_current


## The parts a game's own panel adds, each eased toward what was last shown (a wheel does not snap to lock).
func _tick_analog(delta: float) -> void:
	if not _analog_target.is_empty():
		var moving := false
		# What a hand holds is where the hand has it, with no easing: the wheel, the bars, the gear lever.
		var held := _held_analog()
		for key: String in _analog_target:
			var now := float(_analog_now.get(key, 0.0))
			var want := float(_analog_target[key])
			if held.has(key):
				if now != float(held[key]):
					_analog_now[key] = float(held[key])
					moving = true
				continue
			if now != want:
				now = lerpf(now, want, minf(1.0, delta * 14.0))
				if absf(now - want) < 0.002:
					now = want
				_analog_now[key] = now
				moving = true
		# Settled parts are not written again (a `basis =` goes to the renderer even when it writes the same).
		if moving or not _analog_written:
			_analog_written = true
			_pose_analog()
	if _crank != null:
		var before := _crank_angle
		if _in_hand(&"crank"):
			_crank_angle = _hands.crank_angle()
		elif _crank_rate != 0.0:
			_crank_angle = wrapf(_crank_angle + _crank_rate * CRANK_SPEED * delta, -PI, PI)
		if _crank_angle != before or not _analog_written:
			# Forward is the top of the crank going away from the rider: a turn about -X.
			_crank.basis = _rest_basis[_crank] * Basis(Vector3.RIGHT, -_crank_angle)
	if _ball != null:
		var roll := _hands.ball_roll() if _in_hand(&"ball") else _ball_roll
		if roll != Vector2.ZERO:
			# Rolled toward where it is pushed: about X for up and down, about Y for left and right (deck frame).
			_ball.basis = (Basis(Vector3.RIGHT, roll.y * BALL_SPEED * delta)
				* Basis(Vector3.UP, roll.x * BALL_SPEED * delta) * _ball.basis).orthonormalized()
	if _stick2 != null:
		if _in_hand(&"stick", 1):
			_stick2_current = _hands.stick_lean(1)
		elif _stick2_current != _stick2_target:
			_stick2_current = _stick2_current.lerp(_stick2_target, STICK_BLEND)
			if _stick2_current.distance_squared_to(_stick2_target) < 1.0e-6:
				_stick2_current = _stick2_target
		else:
			return
		_stick2.basis = Basis.from_euler(Vector3(
			deg_to_rad(_stick2_current.y * STICK_TILT_DEG), deg_to_rad(_stick2_current.x * STICK_TILT_DEG), 0.0))


## The analog parts a hand is holding, and where it has them: {key: value} for `_analog_now`.
func _held_analog() -> Dictionary:
	var out := {}
	if _hands == null:
		return out
	if _hands.holds(&"wheel"):
		out["steer"] = _hands.steer(&"wheel")
	elif _hands.holds(&"bars"):
		out["steer"] = _hands.steer(&"bars")
		out["pitch"] = _hands.bars_pitch()
	elif _hands.holds(&"slide"):
		out["steer"] = _hands.steer(&"slide")
	if _hands.holds(&"lever"):
		out["shift"] = _hands.lever_throw()
	if _hands.holds(&"throttle"):
		out["throttle"] = _hands.throttle_value()
	return out


func _pose_analog() -> void:
	var steer := float(_analog_now.get("steer", 0.0))
	if _wheel != null:
		# About the wheel's own axis (its local Y): a turn to the right is clockwise seen by the driver.
		_wheel.basis = _rest_basis[_wheel] * Basis(Vector3.UP, -deg_to_rad(wheel_lock_deg()) * steer)
	if _lean != null:
		_lean.basis = _rest_basis[_lean] * Basis(Vector3.BACK, -deg_to_rad(LEAN_DEG) * steer)
	if _gas != null:
		_gas.basis = _rest_basis[_gas] * Basis(Vector3.RIGHT, -deg_to_rad(PEDAL_DEG) * float(_analog_now.get("gas", 0.0)))
	if _brake != null:
		_brake.basis = _rest_basis[_brake] * Basis(Vector3.RIGHT, -deg_to_rad(PEDAL_DEG) * float(_analog_now.get("brake", 0.0)))
	if _shifter != null:
		_shifter.basis = _rest_basis[_shifter] * Basis(Vector3.RIGHT, -deg_to_rad(SHIFT_DEG) * float(_analog_now.get("shift", 0.0)))
	if _bars != null:
		# Right is clockwise seen from above (about the stem's own Y); a pull toward the player tips the grips down.
		_bars.basis = _rest_basis[_bars] * Basis(Vector3.UP, -deg_to_rad(BARS_YAW_DEG) * steer) \
			* Basis(Vector3.RIGHT, deg_to_rad(BARS_PITCH_DEG) * float(_analog_now.get("pitch", 0.0)))
	if _slide != null:
		_slide.position = _slide_rest + Vector3(steer * ArcadeCabinetSpecs.SLOT_TRAVEL, 0.0, 0.0)
	if _throttle != null:
		# Forward (the lever's top away from the player, toward -Z) is a turn about -X for a lever standing up.
		_throttle.basis = _rest_basis[_throttle] * Basis(Vector3.RIGHT, -deg_to_rad(THROTTLE_DEG) * float(_analog_now.get("throttle", 0.0)))


## How far the steering wheel turns each way, in degrees: a yoke's own (`lock_deg` on its pivot: Road Blasters' turns 135, about 270 lock to lock), else a wheel's.
func wheel_lock_deg() -> float:
	return float(_wheel.get_meta(&"lock_deg", WHEEL_LOCK_DEG)) if _wheel != null else WHEEL_LOCK_DEG


## The steering wheel's turn as last shown (-1 full left .. 1 full right), and how far a pedal is down, for the
## tests and the probe.
func steering() -> float:
	return float(_analog_now.get("steer", 0.0))


func pedal_down(which: String) -> float:
	return float(_analog_now.get(which, 0.0))


# ── the hands (ArcadePanelHands) ─────────────────────────────────────────────

## Step the hands on this panel: `ctrls` are the player's two hands, `live` false while the machine is off.
func update_hands(delta: float, ctrls: Array, live: bool) -> void:
	if _hands != null:
		_hands.update(delta, ctrls, live)


## Let go of everything a hand holds or presses here.
func release_hands() -> void:
	if _hands != null:
		_hands.release_all()


## The pad bits the hands hold on this panel, and the thumbstick they stand in for (0 left, 1 right; x right, y up).
func hand_buttons() -> int:
	return _hands.buttons() if _hands != null else 0


func hand_thumbstick(side: int) -> Vector2:
	return _hands.thumbstick(side) if _hands != null else Vector2.ZERO


## Is a hand pressing a cap or holding a control here, or a foot on an arrow?
func hands_active() -> bool:
	return _hands != null and _hands.active()


## Does this panel have arrows to stand on?
func has_feet() -> bool:
	return _hands != null and _hands.has_feet()


## The player's body at `point` (the floor under them; Vector3.INF for nobody): the arrows under it are pressed.
func update_body(point: Vector3) -> void:
	if _hands != null:
		_hands.update_body(point)


## Is `ctrl` holding, or reaching for, a control of this panel? (ArcadePanelGrip does not take its press.)
func hand_reaching(ctrl: XRController3D) -> bool:
	return _hands != null and _hands.reaching(ctrl)


func hands() -> ArcadePanelHands:
	return _hands


## What the hands need to know of the parts (ArcadePanelHands): the caps by index, a pivot's pose at rest, and where
## the stick, the dial and the lever are now.
func cap_count() -> int:
	return _caps.size()


func cap_node(index: int) -> Node3D:
	return _caps[index]


func cap_rest_position(index: int) -> Vector3:
	return _cap_rest[index]


func cap_bit(index: int) -> int:
	return _cap_bits[index]


func rest_basis_of(node: Node3D) -> Basis:
	return _rest_basis.get(node, Basis.IDENTITY) as Basis


## A stick's lean now (0 the first, 1 the second): x right, y down, -1..1.
func stick_lean_of(index: int) -> Vector2:
	return _stick2_current if index == 1 else _stick_current


func dial_angle() -> float:
	return _dial_angle


## The crank's turn as drawn (radians, forward positive), and how far the bars are pushed (-1 pulled .. 1 pushed) now.
func crank_angle() -> float:
	return _crank_angle


func bars_pitch() -> float:
	return float(_analog_now.get("pitch", 0.0))


func shift_amount() -> float:
	return float(_analog_now.get("shift", 0.0))


## Where the throttle lever is (-1 back .. 1 forward), as drawn.
func throttle_amount() -> float:
	return float(_analog_now.get("throttle", 0.0))
