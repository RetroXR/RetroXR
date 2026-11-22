## touch_feel_tests — a machine's touch screen feel (TouchFeel, TouchMenuRows): the
## touch and lift-off distances, the touch haptic, the System tab section that sets
## them, and the room's save.
##
##   "$godot" --headless --path RetroXR res://Tests/touch_feel_tests.tscn [-- --only=<group>]
##
## Groups: order, defaults, panel, save. The fingertip itself needs live controllers;
## what a screen reads is TouchFeel.distances_m(its machine, its own defaults), which
## is what these hold to.
extends "res://Tests/test_suite.gd"

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const GAMEPAD_SCENE := preload("res://Scenes/Objects/controllers/wiiu/wiiu_gamepad.tscn")

var _only := ""
var _spawned: Array[Node] = []


func _ready() -> void:
	suite_tag = "touch"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.substr(7)
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("[touch] TIMEOUT")
		get_tree().quit(1))

	if _wants("order"):
		_test_lift_off_is_never_inside_touch()
	if _wants("defaults"):
		await _test_each_screen_keeps_its_own_distances()
	if _wants("panel"):
		await _test_the_system_tab_sets_the_feel()
		await _test_the_gamepads_menu_sets_its_consoles_feel()
	if _wants("save"):
		await _test_the_room_keeps_the_feel()

	for n in _spawned:
		if is_instance_valid(n):
			n.queue_free()
	await _wait(2)
	_finish()


func _wants(group: String) -> bool:
	return _only.is_empty() or _only == group


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _console(systemid: String) -> RetroSystem:
	var sys := SYSTEM_SCENE.instantiate() as RetroSystem
	sys.systemid = systemid
	sys.position = Vector3(_spawned.size() * 2.0, 0, 0)
	sys.freeze = true
	add_child(sys)
	_spawned.append(sys)
	await _wait(6)
	return sys


# ── order/ ───────────────────────────────────────────────────────────────────

func _test_lift_off_is_never_inside_touch() -> void:
	_eq(TouchFeel.ordered(20.0, 12.0, true), Vector2(20.0, 20.0),
		"order/raising touch past lift-off carries lift-off up")
	_eq(TouchFeel.ordered(10.0, 6.0, false), Vector2(6.0, 6.0),
		"order/lowering lift-off under touch carries touch down")
	_eq(TouchFeel.ordered(8.0, 14.0, true), Vector2(8.0, 14.0),
		"order/a gap is kept as it is")
	_eq(TouchFeel.ordered(0.0, 900.0, true), Vector2(TouchFeel.TOUCH_MIN_MM, TouchFeel.LIFT_MAX_MM),
		"order/both are held to their ranges")
	var host := Node.new()
	host.set_script(null)
	_ok(is_equal_approx(TouchFeel.haptic(null), TouchFeel.HAPTIC_DEFAULT),
		"order/with no machine the haptic is the light default")
	host.free()


# ── defaults/ ────────────────────────────────────────────────────────────────

func _test_each_screen_keeps_its_own_distances() -> void:
	var wiiu := await _console("wiiu")
	var ds := await _console("nds")
	var snes := await _console("snes")
	_ok(TouchFeel.defaults_mm(wiiu).is_equal_approx(Vector2(8.0, 12.8)),
		"defaults/the GamePad's glass: touch 8 mm, lift-off 12.8 mm, as it always was",
		str(TouchFeel.defaults_mm(wiiu)))
	_ok(TouchFeel.defaults_mm(ds).is_equal_approx(Vector2(10.0, 16.0)),
		"defaults/a DS's bottom screen: touch 10 mm, lift-off 16 mm, as it always was",
		str(TouchFeel.defaults_mm(ds)))
	_ok(not TouchFeel.has_touch_screen(snes), "defaults/a Super NES has no touch screen")
	# Unset, a screen reads its own; set, the machine's, on any screen of that machine.
	_ok(TouchFeel.distances_m(ds, Vector2(10.0, 16.0)).is_equal_approx(Vector2(0.010, 0.016)),
		"defaults/unset, the screen's own distances", str(TouchFeel.distances_m(ds, Vector2(10.0, 16.0))))
	ds.touch_mm = 4.0
	ds.lift_mm = 25.0
	_ok(TouchFeel.distances_m(ds, Vector2(10.0, 16.0)).is_equal_approx(Vector2(0.004, 0.025)),
		"defaults/set, the machine's on its own screen", str(TouchFeel.distances_m(ds, Vector2(10.0, 16.0))))
	_ok(TouchFeel.distances_m(ds, TVTouchSurface.defaults_mm()).is_equal_approx(Vector2(0.004, 0.025)),
		"defaults/and on its picture on a TV", str(TouchFeel.distances_m(ds, TVTouchSurface.defaults_mm())))
	ds.lift_mm = -1.0
	ds.touch_mm = 20.0
	_ok(TouchFeel.distances_m(ds, Vector2(10.0, 16.0)).is_equal_approx(Vector2(0.020, 0.020)),
		"defaults/a touch set past the screen's own lift-off lifts no closer than it",
		str(TouchFeel.distances_m(ds, Vector2(10.0, 16.0))))


# ── panel/ ───────────────────────────────────────────────────────────────────

func _test_the_system_tab_sets_the_feel() -> void:
	var wiiu := await _console("wiiu")
	var snes := await _console("snes")
	var ui := VBoxContainer.new()
	add_child(ui)
	_spawned.append(ui)
	_ok(TouchMenuRows.ensure_in(ui, snes) == null and ui.find_child("TouchRows", true, false) == null,
		"panel/no section on a machine with no touch screen")
	var rows := TouchMenuRows.ensure_in(ui, wiiu)
	_ok(rows != null, "panel/a Wii U's System tab has a Touch Screen section")
	if rows == null:
		return
	await _wait(1)
	_ok(is_equal_approx(rows._touch.value, 8.0) and is_equal_approx(rows._lift.value, 12.8),
		"panel/it opens on the screen's own distances",
		"%s / %s" % [rows._touch.value, rows._lift.value])
	_ok(is_equal_approx(rows._haptic.value, TouchFeel.HAPTIC_DEFAULT * 100.0),
		"panel/and the light default haptic", str(rows._haptic.value))
	rows._touch.value = 20.0
	_ok(is_equal_approx(wiiu.touch_mm, 20.0) and is_equal_approx(wiiu.lift_mm, 20.0)
		and is_equal_approx(rows._lift.value, 20.0),
		"panel/touch raised past lift-off: the machine has both at 20 mm, and so does the lift-off slider",
		"%s / %s / %s" % [wiiu.touch_mm, wiiu.lift_mm, rows._lift.value])
	rows._lift.value = 6.0
	_ok(is_equal_approx(wiiu.touch_mm, 6.0) and is_equal_approx(wiiu.lift_mm, 6.0)
		and is_equal_approx(rows._touch.value, 6.0),
		"panel/lift-off lowered under touch: touch comes down with it",
		"%s / %s / %s" % [wiiu.touch_mm, wiiu.lift_mm, rows._touch.value])
	rows._haptic.value = 0.0
	_ok(is_zero_approx(wiiu.touch_haptic) and rows._haptic_val.text == "Off",
		"panel/the haptic slider at 0 turns it off", "%s %s" % [wiiu.touch_haptic, rows._haptic_val.text])
	rows._haptic.value = 60.0
	_ok(is_equal_approx(wiiu.touch_haptic, 0.6), "panel/and sets its strength", str(wiiu.touch_haptic))
	rows._on_reset()
	_ok(wiiu.touch_mm < 0.0 and wiiu.lift_mm < 0.0
		and is_equal_approx(wiiu.touch_haptic, TouchFeel.HAPTIC_DEFAULT)
		and is_equal_approx(rows._touch.value, 8.0),
		"panel/Screen's own feel puts it all back", "%s / %s / %s" % [wiiu.touch_mm, wiiu.lift_mm, wiiu.touch_haptic])


## The GamePad opens the generic object menu, not its console's: the section
## must be there too, setting the CONSOLE's feel, and only while it is paired.
func _test_the_gamepads_menu_sets_its_consoles_feel() -> void:
	var wiiu := await _console("wiiu")
	var pad := GAMEPAD_SCENE.instantiate() as WiiUGamePad
	pad.position = Vector3(-2, 0, 0)
	pad.freeze = true
	add_child(pad)
	_spawned.append(pad)
	await _wait(2)
	var cam := Camera3D.new()
	add_child(cam)
	_spawned.append(cam)
	# The menu the menu button opens on it (SpawnMenuController._open_options_for).
	_ok(not pad.has_method("toggle_options_ui"), "panel/the GamePad opens the generic object menu")
	ObjectOptionsPanel.toggle_for(pad, cam)
	await _wait(4)
	_ok(pad.find_child("TouchRows", true, false) == null,
		"panel/an unpaired GamePad's menu has no Touch Screen section")
	var panel := pad.get_node_or_null(ObjectOptionsPanel.NODE_NAME) as ObjectOptionsPanel
	panel.hide_panel()
	pad._connected_system = wiiu
	ObjectOptionsPanel.toggle_for(pad, cam)
	await _wait(4)
	var rows := pad.find_child("TouchRows", true, false) as TouchMenuRows
	_ok(rows != null, "panel/a paired GamePad's menu has its console's Touch Screen section")
	if rows == null:
		pad._connected_system = null
		return
	rows._touch.value = 5.0
	_ok(is_equal_approx(wiiu.touch_mm, 5.0), "panel/and it sets the console's touch distance",
		str(wiiu.touch_mm))
	pad._connected_system = null


# ── save/ ────────────────────────────────────────────────────────────────────

func _test_the_room_keeps_the_feel() -> void:
	var ds := await _console("nds")
	var sp := ScenePersistence.new()
	var plain: Dictionary = sp.serialize_node(ds, 1, {})
	_ok(not plain.has("touch_mm") and not plain.has("lift_mm") and not plain.has("touch_haptic"),
		"save/a machine left on its screen's own feel writes nothing new")
	TouchFeel.apply(ds, 5.0, 22.0, 0.45, true)
	var rec: Dictionary = sp.serialize_node(ds, 1, {})
	_ok(is_equal_approx(float(rec.get("touch_mm", -1)), 5.0)
		and is_equal_approx(float(rec.get("lift_mm", -1)), 22.0)
		and is_equal_approx(float(rec.get("touch_haptic", -1)), 0.45),
		"save/a set feel is recorded", str(rec))
	var back := sp.deserialize_object(rec) as RetroSystem
	_ok(back != null, "save/the machine is rebuilt")
	if back != null:
		_ok(is_equal_approx(back.touch_mm, 5.0) and is_equal_approx(back.lift_mm, 22.0)
			and is_equal_approx(back.touch_haptic, 0.45),
			"save/with its feel", "%s / %s / %s" % [back.touch_mm, back.lift_mm, back.touch_haptic])
		back.free()
	# A hand-edited save with lift-off inside touch comes back ordered.
	rec["touch_mm"] = 18.0
	rec["lift_mm"] = 9.0
	var bent := sp.deserialize_object(rec) as RetroSystem
	if bent != null:
		_ok(bent.lift_mm >= bent.touch_mm, "save/a save with lift-off inside touch is put in order",
			"%s / %s" % [bent.touch_mm, bent.lift_mm])
		bent.free()
