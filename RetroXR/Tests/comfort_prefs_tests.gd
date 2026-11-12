extends "res://Tests/test_suite.gd"

## The comfort rows at the top of OPTIONS > General (Turn Style, Snap Angle, Field
## of View, Height Offset, World Scale) are saved and read back. They reset every
## launch until 2026-11-11.

func _ready() -> void:
	suite_tag = "comfort_prefs"
	get_tree().create_timer(30.0).timeout.connect(func() -> void:
		push_error("[comfort_prefs] TIMEOUT")
		get_tree().quit(1))

	_test_defaults()
	_test_round_trip()
	_test_clamped()
	_finish()


## A fresh install starts where the menu always said it did.
func _test_defaults() -> void:
	_eq(_app_prefs_default("turn_smooth"), false, "default/snap turning")
	_eq(_app_prefs_default("snap_turn_angle"), 45.0, "default/45 degree snap, as the menu shows")
	_eq(_app_prefs_default("desktop_fov"), 75.0, "default/75 degree field of view")
	_eq(_app_prefs_default("height_offset"), 0.0, "default/no height offset")
	_eq(_app_prefs_default("world_scale"), 0.85, "default/0.85 world scale")


## Values that differ from the defaults survive a save and a load.
func _test_round_trip() -> void:
	var want := {
		"turn_smooth": true,
		"snap_turn_angle": 30.0,
		"desktop_fov": 98.0,
		"height_offset": -0.25,
		"world_scale": 1.2,
	}
	var back := _app_prefs_round_trip(want)
	for key: String in want:
		_eq(back.get(key), want[key], "save/%s survives a save and a load" % key)


## A hand-edited file cannot put a control outside its own range.
func _test_clamped() -> void:
	var prefs := get_node("/root/AppPrefs")
	var path: String = prefs.PREFS_PATH
	var saved: Variant = _snapshot_file(path)
	JsonStore.write_dict(path, {
		"snap_turn_angle": 20.0,
		"desktop_fov": 400.0,
		"height_offset": -9.0,
		"world_scale": 0.0,
	}, "comfort_prefs")
	var fresh := (prefs.get_script() as GDScript).new() as Node
	fresh.load_prefs()
	_eq(fresh.get("snap_turn_angle"), 45.0, "clamp/a snap angle not on the list reads 45")
	_eq(fresh.get("desktop_fov"), prefs.DESKTOP_FOV_MAX, "clamp/field of view to the slider's top")
	_eq(fresh.get("height_offset"), prefs.HEIGHT_OFFSET_MIN, "clamp/height offset to the slider's bottom")
	_eq(fresh.get("world_scale"), prefs.WORLD_SCALE_MIN, "clamp/world scale to the slider's bottom")
	fresh.free()
	_restore_file(path, saved)
