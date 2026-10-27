## ArcadeGuitar — a GuitarFreaks guitar, wired to the cabinet (ArcadeHeldGear): it hangs in a holster on the cabinet's front beside the screen, is taken down by the body, held as a guitar is
## (the body in one hand, the neck in the other: ArcadeGuitarGrab) and played with what the hands and the keyboard have.
##
## It is MAME's guitar controller (konami/ksys573.cpp `gtrfrks`): three fret buttons R, G and B = BUTTON1 to BUTTON3, the pick = BUTTON6, the wailing = BUTTON7, an effect knob (a dial). The frets
## and the wail are HELD, ORed into the player's state (held_pad_bits, ArcadeInput._with_hands); the pick is a flick, a tap of its button (ArcadeInput.tap_pad_bit) as a drum's hit is.
##
## HOW IT IS PLAYED, by whatever the player has:
##   VR, two hands   the NECK hand's trigger, A / X and B / Y are the red, green and blue frets; the BODY hand's trigger strums (the pick); its thumbstick up is the wail and sideways the effect knob;
##                   the neck RAISED (25 degrees above the horizontal) is the wail too, as the real guitar's tilt switch.
##   VR, one hand    the hand that holds it works the frets, and the other hand's trigger strums.
##   desktop         Z, X and C the frets (`arcade_fret_r/g/b`), a click the pick, V (`arcade_wail`) or the right or middle button the wail, the wheel the effect knob; the guitar rides in the lower right.
##                   A gamepad (DesktopPad): X, Y and RB the frets, RT the pick, LT the wail, the D-pad up and down the knob.
## Every key, speed and angle is an estimate: nothing has been played in a headset.
class_name ArcadeGuitar
extends ArcadeHeldGear

const FRETS := 3
## MAME's buttons.
const PICK_BUTTON := 6
const WAIL_BUTTON := 7
## The analog trigger and the thumbstick, latched with a gap.
const TRIGGER_ON := 0.6
const TRIGGER_OFF := 0.4
const STICK_ON := 0.6
const STICK_OFF := 0.4
## Dead zone of the knob's stick.
const KNOB_DEAD := 0.15
## The neck is RAISED for the wail from this far above the horizontal (the sine of the angle: 25 degrees) and lowered at the second.
const TILT_ON := 0.42
const TILT_OFF := 0.34
## How long a strum holds the pick's button (seconds): a few frames, so every core sees it.
const PICK_SECONDS := 0.07
## What the buttons do to the picture: a pressed fret sinks this far (m), the pick flicks this far (radians) over this long, a wheel notch turns the knob this much.
const FRET_SINK := 0.006
const PICK_FLICK := 0.16
const PICK_FLICK_SECONDS := 0.12
const WHEEL_KNOB := 1.0
## The effect knob turns this far (radians) for a full push, and a wheel notch's push dies away in this many seconds.
const KNOB_TURN := 3.0
const WHEEL_DECAY := 0.25

## A hand reaches the guitar this far from its waist to take it out of its holster: the body is a hand's width across, the 10 cm of a stick's cradle is too little.
const WELL_REACH := 0.20
## How far above its waist the hint floats (m).
const GUITAR_HINT_HEIGHT := 0.32

## The fret buttons now held, the wail from the pedal-less sources, and the knob (-1 .. 1).
var _fret_down: Array[bool] = [false, false, false]
var _wail_stick := false
var _wail_tilt := false
var _wail_key := false
var _knob := 0.0
var _wheel_push := 0.0
## Latches of the analog inputs, by name.
var _latches: Dictionary = {}

var _frets: Array[Node3D] = []
var _rest: Dictionary = {}
var _pick_bar: Node3D = null
var _wail_cap: Node3D = null
var _knob_node: Node3D = null
var _pick_t := 1.0
var _knob_angle := 0.0
var _colored := false


func _ready() -> void:
	super._ready()
	# Both hands hold it, one on the body and one on the neck (ArcadeGuitarGrab says which place a hand may take).
	second_hand_grab = SecondHandGrab.SECOND
	for k in FRETS:
		var fret := get_node_or_null("Fret%d" % (k + 1)) as Node3D
		_frets.append(fret)
		if fret != null:
			_rest[fret] = fret.position
	_pick_bar = get_node_or_null("Pick") as Node3D
	_wail_cap = get_node_or_null("Wail") as Node3D
	if _wail_cap != null:
		_rest[_wail_cap] = _wail_cap.position
	_knob_node = get_node_or_null("Knob") as Node3D
	set_rows(_rows())
	_paint()


## The body is its player's colour (the cabinet's player colours: 1 red, 2 blue).
func _paint() -> void:
	if _colored:
		return
	_colored = true
	var paint := ArcadeParts.mat(ArcadeCabinetBuilder._player_color(player).lerp(Color(0.25, 0.05, 0.05), 0.20), 0.0, 0.35)
	for part in ["BodyLower", "BodyUpper", "BodyWaist"]:
		var mesh := get_node_or_null(part) as MeshInstance3D
		if mesh != null:
			mesh.material_override = paint


func well_reach() -> float:
	return WELL_REACH


## The hint floats over the body, clear of the neck.
func hint_height() -> float:
	return GUITAR_HINT_HEIGHT


func _prepare_hint(_by: Node3D) -> void:
	replace_rows(_rows())


## Which hand holds the neck, LEFT or RIGHT (ArcadeGuitarGrab): the first hand's place says which way about the guitar is held, and a right-handed player (the body in the right hand) has the neck in the left.
func neck_side() -> int:
	var holding := holders()
	if holding.is_empty():
		return ArcadeGuitarGrab.LEFT
	var first: Dictionary = holding[0]
	var hand := int(first["hand"])
	return hand if int(first["role"]) == ArcadeGuitarGrab.NECK else 1 - hand


## What the hint over a held guitar says (HeldHint rows: [id, platform, glyphs, caption]), the VR rows with the hands the guitar is held in (`neck_hand`: LEFT or RIGHT; -1 for the one that holds it now).
## Rows in the desktop's own keys name them as the player has set them.
func _rows(neck_hand: int = -1) -> Array:
	var neck := neck_side() if neck_hand < 0 else neck_hand
	var body := 1 - neck
	return [
		[&"fret_vr", HeldHint.PLATFORM_VR, [_trigger_glyph(neck), _face_glyph(neck, 0), _face_glyph(neck, 1)], "Neck hand: red, green, blue"],
		[&"pick_vr", HeldHint.PLATFORM_VR, [_trigger_glyph(body)], "Body hand: strum"],
		[&"wail_vr", HeldHint.PLATFORM_VR, [_stick_glyph(body)], "Push up, or raise the neck: wail"],
		[&"fret_pc", HeldHint.PLATFORM_DESKTOP, [], "%s %s %s: red, green, blue" % [_key(&"arcade_fret_r"), _key(&"arcade_fret_g"), _key(&"arcade_fret_b")]],
		[&"pick_pc", HeldHint.PLATFORM_DESKTOP, ["mouse_left_outline"], "Strum"],
		[&"wail_pc", HeldHint.PLATFORM_DESKTOP, [], "%s or right click: wail" % _key(&"arcade_wail")],
	]


static func _trigger_glyph(hand: int) -> String:
	return "quest_trigger_%s_outline" % ("left" if hand == ArcadeGuitarGrab.LEFT else "right")


## The controller's lower (0: X, A) or upper (1: Y, B) face button.
static func _face_glyph(hand: int, upper: int) -> String:
	var names := ["x", "y"] if hand == ArcadeGuitarGrab.LEFT else ["a", "b"]
	return "quest_button_%s_outline" % names[upper]


static func _stick_glyph(hand: int) -> String:
	return "quest_stick_%s_press" % ("l" if hand == ArcadeGuitarGrab.LEFT else "r")


static func _key(action: StringName) -> String:
	return DesktopBindings.event_display_name(String(action)) if InputMap.has_action(action) else String(action)


# ── what the hands do ───────────────────────────────────────────────────────

func _on_let_go() -> void:
	_release_all()


func _on_taken_by_controller(_ctrl: XRController3D) -> void:
	_latches.clear()


func _tick(delta: float) -> void:
	_animate(delta)
	if not is_picked_up() or not ArcadeInput.held_by_hand(self):
		_release_all()
		return
	if held_by_desktop():
		_read_desktop(delta)
	elif holding_controller() != null:
		_read_vr()
	else:
		_release_all()


## Nothing is held down: let go, put away.
func _release_all() -> void:
	for k in FRETS:
		_fret_down[k] = false
	_wail_stick = false
	_wail_tilt = false
	_wail_key = false
	_knob = 0.0
	_wheel_push = 0.0
	_latches.clear()


## A latch with a gap for an analog value: on from `on` up, off from `off` down, remembered by `key`.
func _latched(key: String, value: float, on: float, off: float) -> bool:
	var was := bool(_latches.get(key, false))
	var now := value >= on or (was and value > off)
	_latches[key] = now
	return now


## The controllers that hold the guitar and the end each holds: [{ctrl, role}], the primary's first.
func holders() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var driver: Variant = _grab_driver
	if driver == null:
		return out
	for grab: Variant in [driver.primary, driver.secondary]:
		if grab == null or not is_instance_valid(grab):
			continue
		var ctrl: XRController3D = grab.controller
		var point := grab.point as ArcadeGuitarGrab
		if ctrl != null and point != null:
			out.append({"ctrl": ctrl, "role": point.role, "hand": point.hand_side})
	return out


## A controller that is tracked and holds nothing: the free hand, which strums when one hand holds the guitar. Null when there is none.
func _free_hand(holding: Array[Dictionary]) -> XRController3D:
	var rig := PadInputShared.find_rig(get_tree())
	for key in ["left", "right"]:
		var ctrl := rig.get(key) as XRController3D
		if ctrl == null or not is_instance_valid(ctrl) or not ctrl.get_is_active():
			continue
		var busy := false
		for h: Dictionary in holding:
			busy = busy or h["ctrl"] == ctrl
		if busy:
			continue
		var pickup := XRToolsFunctionPickup.find_instance(ctrl)
		if pickup != null and is_instance_valid(pickup.picked_up_object):
			continue
		return ctrl
	return null


func _read_vr() -> void:
	var holding := holders()
	var neck: XRController3D = null
	var body: XRController3D = null
	for h: Dictionary in holding:
		if int(h["role"]) == ArcadeGuitarGrab.NECK:
			neck = h["ctrl"]
		else:
			body = h["ctrl"]
	# The hand that fingers the frets: the neck hand, or the only hand there is. The hand that strums: the body hand when both hold it, else the free one.
	var fret_hand := neck if neck != null else body
	var strum_hand := body if (body != null and neck != null) else _free_hand(holding)
	var stick_hand := body if body != null else neck
	if fret_hand != null:
		_fret_down[0] = _latched("fret0", fret_hand.get_float("trigger"), TRIGGER_ON, TRIGGER_OFF)
		_fret_down[1] = fret_hand.is_button_pressed("ax_button")
		_fret_down[2] = fret_hand.is_button_pressed("by_button")
	if strum_hand != null:
		var was := bool(_latches.get("pick", false))
		if _latched("pick", strum_hand.get_float("trigger"), TRIGGER_ON, TRIGGER_OFF) and not was:
			strum(strum_hand)
	var stick := stick_hand.get_vector2("primary") if stick_hand != null else Vector2.ZERO
	_wail_stick = _latched("wail", stick.y, STICK_ON, STICK_OFF)
	_knob = stick.x if absf(stick.x) > KNOB_DEAD else 0.0
	_wail_tilt = _neck_raised()


## Is the neck raised above the horizontal enough for the wail (the real guitar's tilt switch)? Latched, so a neck at the edge does not flutter.
func _neck_raised() -> bool:
	var raised := global_basis.y.normalized().y
	var was := _wail_tilt
	return raised >= TILT_ON or (was and raised > TILT_OFF)


## The desktop's keys: the frets and the wail are held, the wheel turns the knob (a notch's push dies away), a click strums (_unhandled_input).
func _read_desktop(delta: float) -> void:
	for k in FRETS:
		var action := StringName(["arcade_fret_r", "arcade_fret_g", "arcade_fret_b"][k])
		_fret_down[k] = InputMap.has_action(action) and Input.is_action_pressed(action)
	_wail_key = (InputMap.has_action(&"arcade_wail") and Input.is_action_pressed(&"arcade_wail")) \
			or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE)
	_wheel_push = move_toward(_wheel_push, 0.0, delta / WHEEL_DECAY)
	_knob = clampf(_wheel_push, -1.0, 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if not held_by_desktop() or not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_LEFT and not mb.shift_pressed:
		strum()
	elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		_wheel_push = clampf(_wheel_push + WHEEL_KNOB, -1.0, 1.0)
	elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_wheel_push = clampf(_wheel_push - WHEEL_KNOB, -1.0, 1.0)


## A strum: the pick's button, tapped. `hand` is the controller that did it (it feels it), null on the desktop.
func strum(hand: XRController3D = null) -> bool:
	var input: ArcadeInput = cabinet.call("arcade_input") if cabinet != null and is_instance_valid(cabinet) and cabinet.has_method("arcade_input") else null
	if input == null:
		return false
	input.tap_pad_bit(player, ArcadeProfiles.button_bit(PICK_BUTTON), PICK_SECONDS)
	_pick_t = 0.0
	if hand != null:
		Haptics.pulse(hand, 0.5, 25, &"arcade_guitar")
	return true


# ── what the cabinet reads ──────────────────────────────────────────────────

func held_pad_bits() -> int:
	if not ArcadeInput.held_by_hand(self):
		return 0
	var bits := 0
	for k in FRETS:
		if _fret_down[k]:
			bits |= 1 << ArcadeProfiles.button_bit(k + 1)
	if wailing():
		bits |= 1 << ArcadeProfiles.button_bit(WAIL_BUTTON)
	return bits


## The effect knob is a dial, which a panel's is the left stick's X (ArcadePanelHands DialGrab).
func held_sticks() -> Array[Vector2]:
	if not ArcadeInput.held_by_hand(self):
		return [Vector2.ZERO, Vector2.ZERO]
	return [Vector2(_knob, 0.0), Vector2.ZERO]


func wailing() -> bool:
	return _wail_stick or _wail_tilt or _wail_key


## The fret buttons held down now, [R, G, B] (the tests and the picture).
func frets_down() -> Array[bool]:
	return _fret_down.duplicate()


# ── the picture ─────────────────────────────────────────────────────────────

func _animate(delta: float) -> void:
	for k in FRETS:
		var fret := _frets[k] if k < _frets.size() else null
		if fret != null:
			var home: Vector3 = _rest[fret]
			fret.position = home + Vector3(0.0, 0.0, -FRET_SINK if _fret_down[k] else 0.0)
	if _wail_cap != null:
		var home: Vector3 = _rest[_wail_cap]
		_wail_cap.position = home + Vector3(0.0, 0.0, -FRET_SINK if wailing() else 0.0)
	if _pick_bar != null and _pick_t < 1.0:
		_pick_t = minf(_pick_t + delta / PICK_FLICK_SECONDS, 1.0)
		_pick_bar.rotation.x = PICK_FLICK * sin(PI * _pick_t)
		if _pick_t >= 1.0:
			_pick_bar.rotation.x = 0.0
	if _knob_node != null:
		_knob_angle += _knob * KNOB_TURN * delta
		_knob_node.rotation.z = _knob_angle
