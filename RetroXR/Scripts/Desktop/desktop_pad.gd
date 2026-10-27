## DesktopPad -- the first gamepad as the PLAYER's input, off a headset.
##
## Off a headset controller 1 is treated as the keyboard and mouse are: it walks, looks, works the
## hand and plays what is held, and the two are interchangeable on the fly. The help prompts follow
## the last device used (`last_is_pad`, `device_changed`). A pad that has been given a PadReceiver
## in the room is an EXTERNAL controller instead, and stops being the player's until that item is
## put away (`main_device` is -1 meanwhile, so the keyboard is the only way in).
##
## How it is done. The pad is made into the input the game already understands rather than given
## code paths of its own:
##   * movement, crouch, walk, the menu, the TV's full screen and taking cover in a gun game (RB) are
##     InputMap actions, so the pad's events are ADDED to those actions while a pad is the main one
##     (`_sync_map`) and taken off again when it is not; the engine's own ui_* pad buttons
##     (B = ui_cancel lets go of the mouse) come off meanwhile, A stays the jump (ui_accept);
##   * the hand (grab, drop on release, push, pull, catch, turn) and looking round read the MOUSE,
##     so the pad sends the mouse events: RT is the left button, LT the middle one, D-pad up and
##     down the wheel, the right stick mouse motion (with LB as Shift). Those events carry
##     `SYNTH_DEVICE` so this script does not take them for the keyboard and mouse coming back.
##     While a held device has the keys (F3) all of that stops, the InputMap events included: the
##     pad is the GAME's then;
##   * R3 sends F3, the keyboard's own "this device has my keys" (ScrollLockCapture), and a held
##     handheld or pad merges the main pad while it has them (handheld_input.gd, retro_controller.gd).
##
## The mapping is the plan's ASSUMED default (docs/dev/gamepad-desktop.md): Xbox names.
class_name DesktopPadService
extends Node

## The last device used changed: true = the pad, false = keyboard and mouse.
signal device_changed(pad: bool)
## The pad that is the player's changed (-1 = none: no pad, a headset, or one made external).
signal main_changed(device: int)

## Marks the events this script makes, so it does not read them as the keyboard and mouse.
const SYNTH_DEVICE := 4242
## Right stick at full tilt, in mouse pixels a second. About 0.2 deg a pixel in the look-around
## (movement_desktop_turn.gd), so ~150 deg/s.
const LOOK_SPEED := 750.0
## The same stick turning an object (LT held) is slower: the hand turns 0.46 deg a pixel.
const TURN_SCALE := 0.4
const STICK_DEADZONE := 0.2
## A trigger counts as pressed past ON and as released under OFF.
const TRIGGER_ON := 0.5
const TRIGGER_OFF := 0.35
## An axis past this is the player using the pad (to pick the prompts).
const AXIS_PICK := 0.5
## Holding the D-pad up or down repeats the wheel.
const WHEEL_DELAY := 0.35
const WHEEL_EVERY := 0.12

## The row prompts as a pad shows them: [glyphs, caption], by row id (held_hint.gd). Only the Xbox
## set is whole in Textures/InputPrompts (PlayStation lacks the face buttons and the Switch lacks
## the triggers and sticks), so one set serves every pad.
const PAD_ROWS := {
	&"rotate_yaw": [["xbox_lt_outline"], "Hold {g} and move the right stick to pitch and yaw"],
	&"rotate_roll": [["xbox_lt_outline", "xbox_lb_outline"],
		"Hold {g} and move the right stick to pitch and roll"],
	&"hand_hold_desktop": [["xbox_dpad_down_outline"],
		"Keep pressing {g} to hold it in your hand; again to square it up"],
	&"capture": [["xbox_stick_r_press"], "press to send buttons here"],
	&"drop_desktop": [["xbox_lb_outline", "xbox_rt_outline"], "Drop"],
	&"pedal_cover_desktop": [["xbox_rb_outline"], "Hold {g} to take cover"],
	&"fret_pc": [["xbox_button_x_outline", "xbox_button_y_outline", "xbox_rb_outline"], "{g}: red, green, blue"],
	&"wail_pc": [["xbox_lt_outline"], "Hold {g}: wail"],
}
## Any other keyboard / mouse glyph, one for one.
const PAD_GLYPHS := {
	"keyboard_scroll_lock_outline": "xbox_stick_r_press",
	"keyboard_tab_outline": "xbox_button_menu_outline",
	"keyboard_shift_outline": "xbox_lb_outline",
	"mouse_left_outline": "xbox_rt_outline",
	"mouse_scroll_outline": "xbox_dpad_down_outline",
}

## The joypad index that is the player's, or -1.
var main_device: int = -1
## True after a pad press, false after a key or the mouse. Always false while there is no main pad.
var last_is_pad: bool = false

## Tests: the pads there are (an Array of device indexes) and whether a headset is on, in place of
## the real ones. null = ask the engine.
var pads_override: Variant = null
var xr_override: Variant = null
## Tests: which joypad index a pad (guid, ordinal) is. Empty = GamepadBindings.resolve_device.
var resolver: Callable = Callable()
## Tests: no frame loop of its own, so a case drives `tick` and sees what it did.
var manual: bool = false

var _axes: Dictionary = {}
## XENU_PAD_DEBUG=1: once a second, the sticks and what the walk actions read, in the log.
var _debug := OS.get_environment("XENU_PAD_DEBUG") == "1"
var _logged := 0
var _debug_clock := 0.0
var _debug_walk := 0.0
var _left_sources: Dictionary = {}
var _left_down: bool = false
var _middle_down: bool = false
var _shift: bool = false
var _wheel_dir: int = 0
var _wheel_wait: float = 0.0
## [action, event] pairs this script put on the InputMap, to take off again.
var _added: Array = []
## [action, event] pairs it took OFF the engine's own ui_* actions, to put back.
var _stripped: Array = []
## Whether a held device had the keys when the map was last made: its events are off the map then.
var _map_captured: bool = false


func _ready() -> void:
	set_process_input(true)
	set_process(not manual)


func _process(delta: float) -> void:
	tick(delta)


func _exit_tree() -> void:
	main_device = -1
	_sync_map()


## One step: who the main pad is, the wheel repeating, the right stick looking round.
func tick(delta: float) -> void:
	refresh_main()
	_keep_map()
	if _debug:
		_debug_report(delta)
	if main_device < 0:
		return
	if _captured() != _map_captured:
		_sync_map()
	if _captured():
		return
	if _wheel_dir != 0:
		_wheel_wait -= delta
		if _wheel_wait <= 0.0:
			_wheel_wait = WHEEL_EVERY
			_send_wheel(_wheel_dir)
	var look := stick_vector(float(_axes.get(JOY_AXIS_RIGHT_X, 0.0)),
		float(_axes.get(JOY_AXIS_RIGHT_Y, 0.0)))
	if look != Vector2.ZERO:
		_send_motion(look * LOOK_SPEED * (TURN_SCALE if _middle_down else 1.0) * delta)


func _input(event: InputEvent) -> void:
	handle_event(event)


func _debug_report(delta: float) -> void:
	_debug_walk = maxf(_debug_walk, Input.get_vector("desktop_move_left", "desktop_move_right",
		"desktop_move_backward", "desktop_move_forward").length())
	_debug_clock += delta
	if _debug_clock < 1.0:
		return
	_debug_clock = 0.0
	var any := _debug_walk > 0.0
	for axis in _axes:
		any = any or absf(float(_axes[axis])) > 0.1
	if any:
		print("[DesktopPad] main %d, left (%.2f, %.2f), right (%.2f, %.2f), walk action up to %.2f, captured %s, last %s" % [
			main_device, float(_axes.get(JOY_AXIS_LEFT_X, 0.0)), float(_axes.get(JOY_AXIS_LEFT_Y, 0.0)),
			float(_axes.get(JOY_AXIS_RIGHT_X, 0.0)), float(_axes.get(JOY_AXIS_RIGHT_Y, 0.0)),
			_debug_walk, _captured(), "pad" if last_is_pad else "keyboard"])
	_debug_walk = 0.0


# ── Who the main pad is ──────────────────────────────────────────────────────

## The pad that should be the player's now: the first one, unless a headset is on or a PadReceiver
## in the room is for it.
func resolve_main() -> int:
	if _xr():
		return -1
	var pads := _pads()
	if pads.is_empty():
		return -1
	var first: int = pads[0]
	return -1 if _has_receiver(first) else first


func refresh_main() -> void:
	var want := resolve_main()
	if want == main_device:
		return
	_release_all()
	main_device = want
	print("[DesktopPad] the player's pad is now %s" % (
		"none" if want < 0 else "%d '%s'" % [want, Input.get_joy_name(want)]))
	_sync_map()
	if want < 0:
		_set_last(false)
	main_changed.emit(want)


## Would a PadReceiver for this pad (guid + ordinal, as the menu names it) take the player's own pad
## away? The spawn menu asks, to warn before it does.
func would_go_external(guid: String, ordinal: int) -> bool:
	return main_device >= 0 and _device_of(guid, ordinal) == main_device


func _device_of(guid: String, ordinal: int) -> int:
	if resolver.is_valid():
		return int(resolver.call(guid, ordinal))
	return GamepadBindings.resolve_device(guid, ordinal)


func _pads() -> Array:
	if pads_override != null:
		return pads_override as Array
	return GamepadBindings.usable_pads()


## A headset build is never one: an Android build is a Quest, and the room turns `use_xr` on only
## after boot, so a paired pad would be the player's (and fake the mouse) through the loading screen.
func _xr() -> bool:
	if xr_override != null:
		return bool(xr_override)
	return OS.has_feature("android") or MenuStyle.is_vr_mode() \
		or (is_inside_tree() and get_viewport().use_xr)


func _has_receiver(device: int) -> bool:
	if not is_inside_tree():
		return false
	for node in get_tree().get_nodes_in_group(ControllerBindings.CONSUMER_GROUP):
		var rx := node as PadReceiver
		if rx == null or rx.is_queued_for_deletion():
			continue
		if _device_of(rx.pad_guid, rx.pad_ordinal) == device:
			return true
	return false


# ── The pad's events ─────────────────────────────────────────────────────────

func handle_event(event: InputEvent) -> void:
	if event.device == SYNTH_DEVICE:
		return
	_log_first(event)
	if event is InputEventKey:
		if (event as InputEventKey).pressed:
			_set_last(false)
	elif event is InputEventMouseButton:
		if (event as InputEventMouseButton).pressed:
			_set_last(false)
	elif event is InputEventMouseMotion:
		if (event as InputEventMouseMotion).relative.length() > 2.0:
			_set_last(false)
	elif event is InputEventJoypadButton:
		var jb := event as InputEventJoypadButton
		if main_device < 0 or jb.device != main_device:
			return
		if jb.pressed:
			_set_last(true)
		_button(jb.button_index, jb.pressed)
	elif event is InputEventJoypadMotion:
		var jm := event as InputEventJoypadMotion
		if main_device < 0 or jm.device != main_device:
			return
		_axes[jm.axis] = jm.axis_value
		if absf(jm.axis_value) > AXIS_PICK:
			_set_last(true)
		_axis(jm.axis, jm.axis_value)


## A held device has the keyboard (F3): the pad is its, not the hand's.
func _captured() -> bool:
	return ScrollLockCapture.any_active()


## The first few pad events of a session go in the log, so a pad that does nothing can be told from
## one whose events never arrive.
func _log_first(event: InputEvent) -> void:
	if _logged >= 24:
		return
	if event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		_logged += 1
		print("[DesktopPad] pad %d button %d (main %d)" % [event.device, (event as InputEventJoypadButton).button_index, main_device])
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > AXIS_PICK:
		_logged += 1
		print("[DesktopPad] pad %d axis %d = %.2f (main %d)" % [event.device, (event as InputEventJoypadMotion).axis,
			(event as InputEventJoypadMotion).axis_value, main_device])


func _set_last(pad: bool) -> void:
	if pad and main_device < 0:
		return
	if pad == last_is_pad:
		return
	last_is_pad = pad
	device_changed.emit(pad)


func _button(index: int, pressed: bool) -> void:
	match index:
		JOY_BUTTON_LEFT_SHOULDER:
			_shift = pressed
		JOY_BUTTON_RIGHT_STICK:
			if pressed:
				_tap_key(KEY_F3)
		JOY_BUTTON_DPAD_UP:
			_set_wheel(1, pressed)
		JOY_BUTTON_DPAD_DOWN:
			_set_wheel(-1, pressed)


func _axis(axis: int, value: float) -> void:
	match axis:
		JOY_AXIS_TRIGGER_RIGHT:
			_hold_left("rt", not _captured() and _trigger(_left_sources.get("rt", false), value))
		JOY_AXIS_TRIGGER_LEFT:
			var down := not _captured() and _trigger(_middle_down, value)
			if down != _middle_down:
				_middle_down = down
				_send_button(MOUSE_BUTTON_MIDDLE, down)


static func _trigger(was_down: bool, value: float) -> bool:
	return value > (TRIGGER_OFF if was_down else TRIGGER_ON)


## The D-pad's notches: +1 is up (the wheel's UP pushes the held object away), -1 down (pulls it
## in). Held, it repeats; letting go of the other direction does not stop this one.
func _set_wheel(dir: int, pressed: bool) -> void:
	if not pressed:
		if _wheel_dir == dir:
			_wheel_dir = 0
		return
	if _captured():
		return
	_wheel_dir = dir
	_wheel_wait = WHEEL_DELAY
	_send_wheel(dir)


# ── The events it makes ──────────────────────────────────────────────────────

func _centre() -> Vector2:
	return get_viewport().get_visible_rect().size * 0.5 if is_inside_tree() else Vector2.ZERO


func _hold_left(source: String, down: bool) -> void:
	_left_sources[source] = down
	var any := false
	for key in _left_sources:
		any = any or bool(_left_sources[key])
	if any != _left_down:
		_left_down = any
		_send_button(MOUSE_BUTTON_LEFT, any)


func _send_button(button: int, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.device = SYNTH_DEVICE
	e.button_index = button as MouseButton
	e.pressed = pressed
	e.shift_pressed = _shift
	e.position = _centre()
	e.global_position = e.position
	Input.parse_input_event(e)


## A notch is a press and its release, as a real wheel sends it: a press alone leaves the wheel's bit
## in Input's button mask, and any action on the wheel, held.
func _send_wheel(dir: int) -> void:
	var button := MOUSE_BUTTON_WHEEL_UP if dir > 0 else MOUSE_BUTTON_WHEEL_DOWN
	_send_button(button, true)
	_send_button(button, false)


func _send_motion(relative: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.device = SYNTH_DEVICE
	e.relative = relative
	e.shift_pressed = _shift
	e.position = _centre()
	e.global_position = e.position
	var mask := 0
	if _left_down:
		mask |= MOUSE_BUTTON_MASK_LEFT
	if _middle_down:
		mask |= MOUSE_BUTTON_MASK_MIDDLE
	e.button_mask = mask as MouseButtonMask
	Input.parse_input_event(e)


func _tap_key(key: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.device = SYNTH_DEVICE
		e.keycode = key
		e.physical_keycode = key
		e.pressed = pressed
		Input.parse_input_event(e)


## Let go of everything the pad is holding: the buttons it pressed, the wheel it repeats.
func _release_all() -> void:
	if _left_down:
		_send_button(MOUSE_BUTTON_LEFT, false)
	if _middle_down:
		_send_button(MOUSE_BUTTON_MIDDLE, false)
	_left_down = false
	_middle_down = false
	_left_sources.clear()
	_shift = false
	_wheel_dir = 0
	_axes.clear()


# ── The InputMap ─────────────────────────────────────────────────────────────

func _sync_map() -> void:
	for pair: Array in _added:
		if InputMap.has_action(pair[0]):
			InputMap.action_erase_event(pair[0], pair[1])
	_added.clear()
	for pair: Array in _stripped:
		if InputMap.has_action(pair[0]):
			InputMap.action_add_event(pair[0], pair[1])
	_stripped.clear()
	# While a held device has the keys the pad is the GAME's: Start must not open the menu as well,
	# nor B crouch, nor A jump. The ui_* defaults go back too, as a captured keyboard leaves them.
	_map_captured = _captured()
	if main_device < 0 or _map_captured:
		return
	_strip_engine_defaults()
	_add_axis("desktop_move_left", JOY_AXIS_LEFT_X, -1.0)
	_add_axis("desktop_move_right", JOY_AXIS_LEFT_X, 1.0)
	_add_axis("desktop_move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_add_axis("desktop_move_backward", JOY_AXIS_LEFT_Y, 1.0)
	_add_button("desktop_spawn_menu", JOY_BUTTON_START)
	_add_button("desktop_tv_fullscreen", JOY_BUTTON_BACK)
	_add_button("action_crouch", JOY_BUTTON_B)
	_add_button("action_walk", JOY_BUTTON_LEFT_STICK)
	_add_button("ui_accept", JOY_BUTTON_A)
	# Taking cover in a gun game, which lifts its foot pedal (ArcadeInput.PEDAL_ACTION): RB, free under the right
	# index finger while RT fires. LB is Shift (LB + RT drops what is held), LT the middle button (it holds the
	# look still).
	_add_button("arcade_pedal", JOY_BUTTON_RIGHT_SHOULDER)
	# A guitar held in the hand (ArcadeGuitar): X, Y and RB the red, green and blue frets under the right hand's fingers, RT the pick (the left button) and LT the wail (the middle one).
	_add_button("arcade_fret_r", JOY_BUTTON_X)
	_add_button("arcade_fret_g", JOY_BUTTON_Y)
	_add_button("arcade_fret_b", JOY_BUTTON_RIGHT_SHOULDER)


## The map can be rewritten under this script: DesktopBindings.apply_for_system reloads the whole
## InputMap from the project settings at boot (xr_init) and each time a controller is picked up or put
## down, which wipes everything added here. So its own events are checked every frame and the whole
## sync is made again when they are gone.
func _keep_map() -> void:
	if main_device < 0 or _added.is_empty():
		return
	var first: Array = _added[0]
	if InputMap.has_action(first[0]) and InputMap.action_has_event(first[0], first[1]):
		return
	_added.clear()
	_stripped.clear()
	_sync_map()


## The engine gives its own ui_* actions pad buttons (Y is ui_select, and a future engine may add B as
## ui_cancel, which the mouse capture reads as "let go of the mouse"), so a pad press could do things
## nobody mapped. They are taken off while a pad is the player's. ui_accept is the jump, and A is put
## on it by `_sync_map`.
func _strip_engine_defaults() -> void:
	for action in InputMap.get_actions():
		var action_name := String(action)
		if not action_name.begins_with("ui_"):
			continue
		for e in InputMap.action_get_events(action_name):
			if e is InputEventJoypadButton or e is InputEventJoypadMotion:
				_stripped.append([action_name, e])
				InputMap.action_erase_event(action_name, e)


func _add_axis(action: String, axis: JoyAxis, dir_sign: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = main_device
	e.axis = axis
	e.axis_value = dir_sign
	_add(action, e)


func _add_button(action: String, button: JoyButton) -> void:
	var e := InputEventJoypadButton.new()
	e.device = main_device
	e.button_index = button
	_add(action, e)


func _add(action: String, event: InputEvent) -> void:
	if not InputMap.has_action(action):
		return
	InputMap.action_add_event(action, event)
	_added.append([action, event])


# ── Pure helpers ─────────────────────────────────────────────────────────────

## A stick, with the dead zone taken off its radius and the rest stretched to 0..1, and eased (a
## small tilt is a small turn).
static func stick_vector(x: float, y: float) -> Vector2:
	var v := Vector2(x, y)
	var length := v.length()
	if length <= STICK_DEADZONE:
		return Vector2.ZERO
	var scaled := clampf((length - STICK_DEADZONE) / (1.0 - STICK_DEADZONE), 0.0, 1.0)
	return v / length * scaled * scaled


## True when the prompts should show the pad: it is the player's and it was used last.
func prompts_use_pad() -> bool:
	return main_device >= 0 and last_is_pad


## A hint row as a pad shows it, [glyphs, caption]: the row's own pad version, else its glyphs one
## for one, else the keyboard's untouched.
static func pad_row(id: StringName, glyphs: Array, caption: String) -> Array:
	if PAD_ROWS.has(id):
		var own: Array = PAD_ROWS[id]
		return [own[0], own[1]]
	var mapped: Array = []
	for g in glyphs:
		mapped.append(PAD_GLYPHS.get(String(g), String(g)))
	return [mapped, caption]


## Two pad states as one: buttons OR together, each stick takes the larger of the two.
static func merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := {"btn": int(a["btn"]) | int(b["btn"])}
	for pair: Array in [["alx", "aly"], ["arx", "ary"]]:
		var ax: int = a[pair[0]]
		var ay: int = a[pair[1]]
		var bx: int = b[pair[0]]
		var by: int = b[pair[1]]
		var use_b := bx * bx + by * by > ax * ax + ay * ay
		out[pair[0]] = bx if use_b else ax
		out[pair[1]] = by if use_b else ay
	return out


## What a held handheld or pad merges while it has the keyboard: the main pad's buttons and sticks
## through the same map a PadReceiver uses. Zero when there is no main pad.
func held_state(button_map: Dictionary, stick_map: Dictionary) -> Dictionary:
	return GamepadBindings.poll(button_map, stick_map, main_device)
