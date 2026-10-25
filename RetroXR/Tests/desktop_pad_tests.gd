## desktop_pad_tests -- the first gamepad as the player's input (DesktopPadService).
##
## No pad is attached to the machine that runs this, and Input.get_joy_* reads the OS, so the pads
## here are indexes handed in (`pads_override`) and the events are made by hand. What is checked is
## what the service DOES with them: who the main pad is, which device was last, what it adds to the
## InputMap, which mouse and key events it sends, what a held device gets, which prompts it asks.
##
##   "$godot" --headless --path RetroXR res://Tests/desktop_pad_tests.tscn
extends "res://Tests/test_suite.gd"

const PAD := 7

var _seen: Array = []


func _ready() -> void:
	suite_tag = "pad"
	# The autoload sees no pad, and is kept from seeing one: a joypad event parsed below makes the
	# engine list a device, and the autoload would then make it the player's and add its own events.
	var auto: DesktopPadService = DesktopPad
	auto.pads_override = []
	auto.xr_override = false
	await _main_pad()
	await _last_device()
	await _input_map()
	await _synthetic()
	_helpers()
	await _prompts()
	auto.pads_override = null
	auto.xr_override = null
	_finish()


## Our own service, so the one that is the autoload (which sees no pad here) is left alone.
func _service(pads: Array = [PAD]) -> DesktopPadService:
	var svc := DesktopPadService.new()
	svc.manual = true
	svc.pads_override = pads
	svc.xr_override = false
	add_child(svc)
	svc.refresh_main()
	return svc


func _input(event: InputEvent) -> void:
	if event.device == DesktopPadService.SYNTH_DEVICE:
		_seen.append(event)


func _axis(device: int, axis: int, value: float) -> InputEventJoypadMotion:
	var e := InputEventJoypadMotion.new()
	e.device = device
	e.axis = axis
	e.axis_value = value
	return e


func _button(device: int, index: int, pressed: bool) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.device = device
	e.button_index = index
	e.pressed = pressed
	return e


func _key() -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = KEY_W
	e.pressed = true
	return e


func _mouse_buttons(button: int) -> Array:
	return _seen.filter(func(e: InputEvent) -> bool:
		return e is InputEventMouseButton and (e as InputEventMouseButton).button_index == button)


## Wheel notches: the presses (each comes with its release).
func _notches(button: int) -> int:
	return _mouse_buttons(button).filter(func(e: InputEvent) -> bool:
		return (e as InputEventMouseButton).pressed).size()


func _main_pad() -> void:
	var svc := _service()
	_ok(svc.main_device == PAD, "main/the first pad is the player's")
	svc.pads_override = [3, 5]
	svc.refresh_main()
	_ok(svc.main_device == 3, "main/of two, the first")
	svc.xr_override = true
	svc.refresh_main()
	_ok(svc.main_device == -1, "main/a headset is on: no pad is the player's")
	svc.xr_override = false
	svc.pads_override = []
	svc.refresh_main()
	_ok(svc.main_device == -1, "main/no pad, none")
	svc.pads_override = [PAD]
	svc.refresh_main()
	# A receiver for the pad makes it external, and putting the receiver away gives it back.
	svc.resolver = func(guid: String, _ordinal: int) -> int: return PAD if guid == "g1" else -1
	_ok(svc.would_go_external("g1", 0), "main/a receiver for the main pad would make it external")
	_ok(not svc.would_go_external("g2", 0), "main/and one for another pad would not")
	var rx := load("res://Scenes/Objects/controllers/pad_receiver.tscn").instantiate() as PadReceiver
	rx.pad_guid = "g1"
	add_child(rx)
	svc.refresh_main()
	_ok(svc.main_device == -1, "main/a PadReceiver for it is in the room: external, not the player's")
	rx.free()
	svc.refresh_main()
	_ok(svc.main_device == PAD, "main/the receiver put away: the player's again")
	svc.free()


func _last_device() -> void:
	var svc := _service()
	var changes: Array = []
	svc.device_changed.connect(func(pad: bool) -> void: changes.append(pad))
	_ok(not svc.last_is_pad, "last/starts on the keyboard")
	svc.handle_event(_button(PAD, JOY_BUTTON_X, true))
	_ok(svc.last_is_pad and changes == [true], "last/a pad button: the pad, once")
	svc.handle_event(_button(PAD, JOY_BUTTON_Y, true))
	_ok(changes == [true], "last/and another does not announce it again")
	svc.handle_event(_key())
	_ok(not svc.last_is_pad and changes == [true, false], "last/a key: the keyboard, instantly")
	svc.handle_event(_button(PAD + 1, JOY_BUTTON_X, true))
	_ok(not svc.last_is_pad, "last/a button on some OTHER pad is not the player")
	svc.handle_event(_axis(PAD, JOY_AXIS_LEFT_X, 0.3))
	_ok(not svc.last_is_pad, "last/a stick barely off centre is not it either")
	svc.handle_event(_axis(PAD, JOY_AXIS_LEFT_X, 0.8))
	_ok(svc.last_is_pad, "last/a stick pushed is")
	var move := InputEventMouseMotion.new()
	move.relative = Vector2(1, 0)
	svc.handle_event(move)
	_ok(svc.last_is_pad, "last/a nudge of the mouse is not a change")
	move.relative = Vector2(9, 0)
	svc.handle_event(move)
	_ok(not svc.last_is_pad, "last/a real mouse move is")
	var synth := InputEventMouseButton.new()
	synth.device = DesktopPadService.SYNTH_DEVICE
	synth.pressed = true
	svc.handle_event(_button(PAD, JOY_BUTTON_X, true))
	svc.handle_event(synth)
	_ok(svc.last_is_pad, "last/the mouse events the pad sends itself are not the mouse")
	svc.pads_override = []
	svc.refresh_main()
	_ok(not svc.last_is_pad, "last/the pad gone: back on the keyboard")
	svc.free()


func _input_map() -> void:
	var before := InputMap.action_get_events("action_crouch").size()
	var select_before := InputMap.action_get_events("ui_select").size()
	var accept_before := InputMap.action_get_events("ui_accept").size()
	_ok(not InputMap.action_get_events("ui_select").filter(func(e: InputEvent) -> bool:
		return e is InputEventJoypadButton).is_empty(), "map/(the engine's own ui_select has a pad button to begin with: Y)")
	var svc := _service()
	var crouch := InputMap.action_get_events("action_crouch")
	_ok(crouch.size() == before + 1, "map/the pad's B is added to crouch beside the key")
	var found := false
	for e in crouch:
		if e is InputEventJoypadButton and e.button_index == JOY_BUTTON_B and e.device == PAD:
			found = true
	_ok(found, "map/and it is on the main pad")
	_ok(InputMap.action_get_events("ui_select").filter(func(e: InputEvent) -> bool:
		return e is InputEventJoypadButton).is_empty(), "map/the engine's own pad buttons are off its ui_* actions meanwhile")
	var accept_pad := InputMap.action_get_events("ui_accept").filter(func(e: InputEvent) -> bool:
		return e is InputEventJoypadButton and e.button_index == JOY_BUTTON_A and e.device == PAD)
	_ok(accept_pad.size() == 1, "map/A is the jump (ui_accept)")
	var pedal_pad := InputMap.action_get_events(ArcadeInput.PEDAL_ACTION).filter(func(e: InputEvent) -> bool:
		return e is InputEventJoypadButton and e.button_index == JOY_BUTTON_RIGHT_SHOULDER and e.device == PAD)
	_ok(pedal_pad.size() == 1, "map/RB is a gun cabinet's foot pedal (LB is Shift, LT holds the look still)")
	for action: String in ["desktop_move_forward", "desktop_move_backward", "desktop_move_left",
			"desktop_move_right", "desktop_spawn_menu", "desktop_tv_fullscreen", "action_walk"]:
		var has := false
		for e in InputMap.action_get_events(action):
			has = has or (e is InputEventJoypadButton or e is InputEventJoypadMotion)
		_ok(has, "map/%s answers the pad" % action)
	# The left stick walks: a real analog action reading.
	Input.parse_input_event(_axis(PAD, JOY_AXIS_LEFT_Y, -1.0))
	await get_tree().process_frame
	_ok(Input.get_action_strength("desktop_move_forward") > 0.9, "map/the left stick forward is walking forward")
	Input.parse_input_event(_axis(PAD, JOY_AXIS_LEFT_Y, 0.0))
	await get_tree().process_frame
	# DesktopBindings reloads the whole map at boot and whenever a controller is held: the pad's
	# events are put back within a tick.
	InputMap.load_from_project_settings()
	_ok(InputMap.action_get_events("action_crouch").size() == before, "map/(the project reload wipes the pad's events)")
	svc.tick(0.016)
	var back := false
	for e in InputMap.action_get_events("action_crouch"):
		back = back or e is InputEventJoypadButton
	_ok(back, "map/and they are back after one tick")
	Input.parse_input_event(_axis(PAD, JOY_AXIS_LEFT_Y, -1.0))
	await get_tree().process_frame
	_ok(Input.get_action_strength("desktop_move_forward") > 0.9, "map/and the left stick walks again")
	Input.parse_input_event(_axis(PAD, JOY_AXIS_LEFT_Y, 0.0))
	await get_tree().process_frame
	_ok(InputMap.action_get_events("ui_select").filter(func(e: InputEvent) -> bool:
		return e is InputEventJoypadButton).is_empty(), "map/and the engine's own pad buttons are off again")
	svc.pads_override = []
	svc.refresh_main()
	_ok(InputMap.action_get_events("ui_select").size() == select_before, "map/no pad: the engine's own events are put back")
	_ok(InputMap.action_get_events("ui_accept").size() == accept_before, "map/and the jump's A is gone again")
	_ok(InputMap.action_get_events("action_crouch").size() == before, "map/no pad: the events are taken off again",
		"%d now, %d before: %s" % [InputMap.action_get_events("action_crouch").size(), before, InputMap.action_get_events("action_crouch")])
	_ok(InputMap.action_get_events(ArcadeInput.PEDAL_ACTION).filter(func(e: InputEvent) -> bool:
		return e is InputEventJoypadButton).is_empty(), "map/and the pedal's RB with them")
	for e in InputMap.action_get_events("desktop_move_forward"):
		_ok(e is InputEventKey, "map/and what is left on walk forward is the keyboard's")
	svc.free()


func _synthetic() -> void:
	var svc := _service()
	_seen.clear()
	svc.handle_event(_axis(PAD, JOY_AXIS_TRIGGER_RIGHT, 1.0))
	await get_tree().process_frame
	var left := _mouse_buttons(MOUSE_BUTTON_LEFT)
	_ok(left.size() == 1 and (left[0] as InputEventMouseButton).pressed, "send/RT pressed is the left button down")
	_ok(Input.is_action_pressed("trigger_left"), "send/and the pointer's own action (trigger_left) reads it as pressed")
	svc.handle_event(_axis(PAD, JOY_AXIS_TRIGGER_RIGHT, 0.8))
	_ok(_mouse_buttons(MOUSE_BUTTON_LEFT).size() == 1, "send/and a trigger staying down is not another press")
	svc.handle_event(_axis(PAD, JOY_AXIS_TRIGGER_RIGHT, 0.0))
	await get_tree().process_frame
	left = _mouse_buttons(MOUSE_BUTTON_LEFT)
	_ok(not Input.is_action_pressed("trigger_left"), "send/and let go")
	_ok(left.size() == 2 and not (left[1] as InputEventMouseButton).pressed, "send/RT let go is the button up")

	_seen.clear()
	svc.handle_event(_axis(PAD, JOY_AXIS_TRIGGER_LEFT, 1.0))
	await get_tree().process_frame
	_ok(_mouse_buttons(MOUSE_BUTTON_MIDDLE).size() == 1, "send/LT is the middle button (turn it)")
	svc.handle_event(_axis(PAD, JOY_AXIS_TRIGGER_LEFT, 0.0))

	_seen.clear()
	svc.handle_event(_button(PAD, JOY_BUTTON_DPAD_UP, true))
	svc.handle_event(_button(PAD, JOY_BUTTON_DPAD_UP, false))
	svc.handle_event(_button(PAD, JOY_BUTTON_DPAD_DOWN, true))
	await get_tree().process_frame
	_ok(_notches(MOUSE_BUTTON_WHEEL_UP) == 1, "send/D-pad up is a wheel notch up (push it away)")
	_ok(_notches(MOUSE_BUTTON_WHEEL_DOWN) == 1, "send/D-pad down is one down (pull it in)")
	_ok(_mouse_buttons(MOUSE_BUTTON_WHEEL_UP).size() == 2 and not Input.is_mouse_button_pressed(MOUSE_BUTTON_WHEEL_UP),
		"send/a notch is released, as a real wheel's is: the wheel is never left held")
	svc.tick(DesktopPadService.WHEEL_DELAY + 0.01)
	await get_tree().process_frame
	_ok(_notches(MOUSE_BUTTON_WHEEL_DOWN) == 2, "send/held, it repeats")
	svc.handle_event(_button(PAD, JOY_BUTTON_DPAD_DOWN, false))
	svc.tick(1.0)
	await get_tree().process_frame
	_ok(_notches(MOUSE_BUTTON_WHEEL_DOWN) == 2, "send/let go, it stops")

	# The right stick looks round: mouse motion, more for more tilt, none inside the dead zone.
	_seen.clear()
	svc.handle_event(_axis(PAD, JOY_AXIS_RIGHT_X, 0.1))
	svc.tick(0.016)
	await get_tree().process_frame
	_ok(_seen.filter(func(e: InputEvent) -> bool: return e is InputEventMouseMotion).is_empty(),
		"look/inside the dead zone nothing is sent")
	svc.handle_event(_axis(PAD, JOY_AXIS_RIGHT_X, 0.6))
	svc.tick(0.016)
	svc.handle_event(_axis(PAD, JOY_AXIS_RIGHT_X, 1.0))
	svc.tick(0.016)
	await get_tree().process_frame
	var motions := _seen.filter(func(e: InputEvent) -> bool: return e is InputEventMouseMotion)
	_ok(motions.size() >= 1, "look/pushed, it sends mouse motion")
	if motions.size() >= 1:
		var total := Vector2.ZERO
		for m in motions:
			total += (m as InputEventMouseMotion).relative
		_ok(total.x > 0.0 and absf(total.y) < 0.001, "look/to the right, the way the mouse goes")
		# 1.0 for 16 ms is LOOK_SPEED * 0.016 px; with the 0.6 step before it, a bit more.
		_ok(total.x > DesktopPadService.LOOK_SPEED * 0.016 - 0.01, "look/full tilt is LOOK_SPEED a second")
	svc.handle_event(_axis(PAD, JOY_AXIS_RIGHT_X, 0.0))

	# LB is Shift on what is sent (roll, drop a gun); LT slows the stick to turn an object.
	_seen.clear()
	svc.handle_event(_button(PAD, JOY_BUTTON_LEFT_SHOULDER, true))
	svc.handle_event(_axis(PAD, JOY_AXIS_RIGHT_X, 1.0))
	svc.tick(0.016)
	await get_tree().process_frame
	var shifted := _seen.filter(func(e: InputEvent) -> bool:
		return e is InputEventMouseMotion and (e as InputEventMouseMotion).shift_pressed)
	_ok(not shifted.is_empty(), "look/LB held: the motion carries Shift")
	svc.handle_event(_button(PAD, JOY_BUTTON_LEFT_SHOULDER, false))
	svc.handle_event(_axis(PAD, JOY_AXIS_RIGHT_X, 0.0))

	var keys_before := _seen.size()
	svc.handle_event(_button(PAD, JOY_BUTTON_RIGHT_STICK, true))
	await get_tree().process_frame
	var f3 := _seen.filter(func(e: InputEvent) -> bool:
		return e is InputEventKey and (e as InputEventKey).keycode == KEY_F3)
	_ok(_seen.size() > keys_before and f3.size() == 2, "send/R3 is F3, pressed and released (the keys of what is held)")

	# While a held device has the keys, the pad is ITS: nothing is sent for the hand.
	var host := Node3D.new()
	add_child(host)
	var cap := ScrollLockCapture.attach(host, func() -> bool: return true, 0xF11C)
	cap.set_active(true)
	_seen.clear()
	svc.handle_event(_axis(PAD, JOY_AXIS_TRIGGER_RIGHT, 1.0))
	svc.handle_event(_button(PAD, JOY_BUTTON_DPAD_UP, true))
	svc.handle_event(_axis(PAD, JOY_AXIS_RIGHT_X, 1.0))
	svc.tick(0.5)
	await get_tree().process_frame
	_ok(_seen.is_empty(), "captured/RT, the D-pad and the right stick send nothing: they are the game's",
		"%d sent" % _seen.size())
	_ok(not InputMap.event_is_action(_button(PAD, JOY_BUTTON_START, true), "desktop_spawn_menu")
		and not InputMap.event_is_action(_button(PAD, JOY_BUTTON_B, true), "action_crouch"),
		"captured/Start and B are off the map: the game's Start does not open the menu as well")
	cap.release()
	svc.tick(0.0)
	_ok(InputMap.event_is_action(_button(PAD, JOY_BUTTON_START, true), "desktop_spawn_menu"),
		"captured/let go of the keys, Start is the menu again")
	host.free()
	svc.free()


func _helpers() -> void:
	_ok(DesktopPadService.stick_vector(0.1, 0.1) == Vector2.ZERO, "stick/inside the dead zone is nothing")
	_ok(is_equal_approx(DesktopPadService.stick_vector(1.0, 0.0).length(), 1.0), "stick/full is 1")
	var half := DesktopPadService.stick_vector(0.6, 0.0).length()
	var more := DesktopPadService.stick_vector(0.8, 0.0).length()
	_ok(half > 0.0 and half < more and more < 1.0, "stick/between, rising")
	_ok(half < 0.5, "stick/eased: a small tilt is a smaller turn")

	var a := {"btn": 0b0101, "alx": 100, "aly": 0, "arx": 0, "ary": 0}
	var b := {"btn": 0b0011, "alx": 0, "aly": 300, "arx": 5, "ary": 0}
	var m := DesktopPadService.merge(a, b)
	_ok(m["btn"] == 0b0111, "merge/buttons are ORed")
	_ok(m["alx"] == 0 and m["aly"] == 300, "merge/each stick takes the bigger of the two")
	_ok(m["arx"] == 5, "merge/and the other stick is its own")

	var yaw := DesktopPadService.pad_row(&"rotate_yaw", ["mouse_scroll_outline"], "Use {g}")
	_ok(String(yaw[1]).contains("right stick") and yaw[0] == ["xbox_lt_outline"], "rows/rotate has a pad version")
	var other := DesktopPadService.pad_row(&"menu", ["keyboard_tab_outline"], "Menu")
	_ok(other[0] == ["xbox_button_menu_outline"] and other[1] == "Menu", "rows/any other: its glyphs one for one")
	var odd := DesktopPadService.pad_row(&"menu", ["quest_trigger_left_outline"], "x")
	_ok(odd[0] == ["quest_trigger_left_outline"], "rows/a glyph with no pad one stays")
	for g: String in DesktopPadService.PAD_GLYPHS.values():
		_ok(ResourceLoader.exists("res://Textures/InputPrompts/%s%s" % [g, ConsolePadDiagram.GLYPH_EXT]),
			"rows/the glyph %s exists" % g)
	for id: StringName in DesktopPadService.PAD_ROWS:
		for g: String in (DesktopPadService.PAD_ROWS[id] as Array)[0]:
			_ok(ResourceLoader.exists("res://Textures/InputPrompts/%s%s" % [g, ConsolePadDiagram.GLYPH_EXT]),
				"rows/%s: the glyph %s exists" % [id, g])


## The prompts follow the last device: the same rows, drawn in the other's glyphs.
func _prompts() -> void:
	var pad: DesktopPadService = DesktopPad
	pad.pads_override = [PAD]
	pad.xr_override = false
	pad.refresh_main()
	var host := Node3D.new()
	add_child(host)
	var hint := HeldHint.attach(host, false)
	hint._desktop_rows = true
	var rows: Array = [[&"rotate_yaw", HeldHint.PLATFORM_DESKTOP, ["mouse_scroll_outline"],
		"Use {g} to pitch and yaw", HeldHint.WHEN_HELD, false]]
	pad.handle_event(_key())
	hint._build(rows, true)
	var keyboard_sig := hint._built_sig
	_ok(keyboard_sig.contains("mouse_scroll_outline"), "prompts/the keyboard last: the keyboard's glyphs")
	pad.handle_event(_button(PAD, JOY_BUTTON_X, true))
	hint._build(rows, true)
	_ok(hint._built_sig.contains("xbox_lt_outline") and hint._built_sig != keyboard_sig,
		"prompts/a pad press: the pad's, drawn again")
	hint.visible = true
	pad.handle_event(_key())
	_ok(hint._built_sig == keyboard_sig, "prompts/a key: back at once, with the hint on screen")
	hint._desktop_rows = false
	pad.handle_event(_button(PAD, JOY_BUTTON_X, true))
	hint._build(rows, true)
	_ok(hint._built_sig.contains("mouse_scroll_outline"), "prompts/a hold that is not the desktop's is left alone")
	host.free()
	pad.pads_override = []
	pad.refresh_main()
