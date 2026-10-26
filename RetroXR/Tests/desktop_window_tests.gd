extends "res://Tests/test_suite.gd"

## The desktop window's arithmetic: how a size becomes a key and back, how a
## window too big for its screen is brought inside it, and which sizes the
## Resolution row offers.
##
##   godot --headless --path RetroXR res://Tests/desktop_window_tests.tscn
##
## Pure: no window is moved and nothing is saved (QualityManager's prefs file is
## the player's real one). Whether a drag really lands in the saved size, and how
## the room looks at an odd shape, is `Tools/room/window_resize_probe`, which needs
## a display.


func _ready() -> void:
	suite_tag = "window"
	_keys()
	_fit()
	_options()
	_menu()
	_fills()
	_usable()
	_target()
	_ratios()
	_zoom()
	_mode()
	_finish()


func _keys() -> void:
	_eq(DesktopWindow.parse_key("1920x1080"), Vector2i(1920, 1080), "keys/parses WxH")
	_eq(DesktopWindow.key_of(Vector2i(1280, 720)), "1280x720", "keys/formats WxH")
	_eq(DesktopWindow.parse_key(DesktopWindow.key_of(Vector2i(1733, 977))), Vector2i(1733, 977),
		"keys/an odd dragged size round-trips")
	for bad in ["", "1920", "axb", "1920x", "x1080", "0x0", "-5x10", "1x2x3", "1920×1080"]:
		_eq(DesktopWindow.parse_key(bad), Vector2i.ZERO, "keys/refuses '%s'" % bad)


func _fit() -> void:
	var room := Vector2i(1920, 1040)
	_eq(DesktopWindow.fit(Vector2i(1280, 720), room), Vector2i(1280, 720),
		"fit/a window that fits is left alone")
	var big := DesktopWindow.fit(Vector2i(2560, 1440), room)
	_ok(big.x <= room.x and big.y <= room.y, "fit/the 2560x1440 default is brought inside a 1080p screen", str(big))
	_ok(absf(float(big.x) / big.y - 2560.0 / 1440.0) < 0.01,
		"fit/and keeps its shape rather than being squeezed on one axis", str(big))
	var tall := DesktopWindow.fit(Vector2i(1000, 3000), Vector2i(1920, 1040))
	_ok(tall.y <= 1040 and tall.x <= 1920, "fit/a tall window is limited by the height", str(tall))
	_eq(DesktopWindow.fit(Vector2i(100, 100), room), DesktopWindow.MIN_SIZE,
		"fit/a tiny window is raised to the minimum")
	_eq(DesktopWindow.fit(Vector2i(2560, 1440), Vector2i.ZERO), Vector2i(2560, 1440),
		"fit/no screen information changes nothing (a headless run)")
	var cramped := DesktopWindow.fit(Vector2i(2560, 1440), Vector2i(700, 400))
	_ok(cramped.x <= 700 and cramped.y <= 400, "fit/a screen smaller than the minimum wins over it", str(cramped))


func _options() -> void:
	var opts := DesktopWindow.resolution_options(Vector2i(1920, 1080), Vector2i(1920, 1080))
	var keys: Array = opts.map(func(o: Array) -> String: return o[1])
	_ok(keys.has("1280x720") and keys.has("1920x1080") and keys.has("1024x768") and keys.has("1280x800"),
		"options/offers the standard steps that fit, 4:3 and 16:10 among them")
	_ok(not keys.has("2560x1440") and not keys.has("3840x2160"),
		"options/leaves out what the screen cannot hold")
	_eq(keys[-1], "1920x1080", "options/the native size ends the list")
	_ok((opts[-1] as Array)[0].contains("native"), "options/and is labelled")
	var odd := DesktopWindow.resolution_options(Vector2i(1920, 1080), Vector2i(1733, 977))
	var odd_keys: Array = odd.map(func(o: Array) -> String: return o[1])
	_ok(odd_keys.has("1733x977"), "options/a dragged size appears, so the row never opens blank")
	_ok(str(odd[odd_keys.find("1733x977")][0]).contains("current"), "options/and is labelled current")
	var areas := odd_keys.map(func(k: String) -> int:
		var v := DesktopWindow.parse_key(k)
		return v.x * v.y)
	var sorted := areas.duplicate()
	sorted.sort()
	_eq(areas, sorted, "options/smallest first")
	var dup := DesktopWindow.resolution_options(Vector2i(1920, 1080), Vector2i(1280, 720))
	var dup_keys: Array = dup.map(func(o: Array) -> String: return o[1])
	_eq(dup_keys.count("1280x720"), 1, "options/a current size that is a step is listed once")
	var nothing := DesktopWindow.resolution_options(Vector2i.ZERO, Vector2i.ZERO)
	_eq(nothing, [], "options/a headless display offers nothing rather than a zero size")


func _menu() -> void:
	_eq(DesktopWindow.menu_distance_factor(1.0), 1.0, "menu/at 1x the menu stands where it always did")
	_eq(DesktopWindow.menu_distance_factor(2.0), 1.5, "menu/at 2x it is 1.5 times as far (1.35 m)")
	_eq(DesktopWindow.menu_distance_factor(4.0), 2.5, "menu/at 4x, 2.5 times (2.25 m)")
	_eq(DesktopWindow.menu_distance_factor(0.5), 1.0, "menu/never nearer than usual")
	var last := 0.0
	for z: float in [1.0, 1.25, 1.5, 2.0, 3.0, 4.0]:
		var f := DesktopWindow.menu_distance_factor(z)
		_ok(f >= last, "menu/%.2fx is no nearer than the zoom below it" % z)
		_ok(f <= z, "menu/%.2fx is never further than the zoom itself (the menu never shrinks)" % z)
		last = f


func _fills() -> void:
	var usable := Vector2i(1969, 1108)
	_ok(DesktopWindow.fills_screen(Vector2i(1817, 1108), usable),
		"fills/a window as tall as the screen may be held maximised on that axis")
	_ok(DesktopWindow.fills_screen(Vector2i(1969, 700), usable), "fills/and one as wide as it")
	_ok(DesktopWindow.fills_screen(Vector2i(640, 1060), usable), "fills/a title bar short of the height still counts")
	_ok(not DesktopWindow.fills_screen(Vector2i(1280, 720), usable), "fills/an ordinary window does not, so it is not flickered")
	_ok(not DesktopWindow.fills_screen(Vector2i(1280, 720), Vector2i.ZERO), "fills/no screen information, no unstick")


func _usable() -> void:
	# A 1920x1200 monitor whose panel leaves 1108 rows: nothing taller than that is offered
	# as a standard size, or it would come out as a different size than the label says.
	var opts := DesktopWindow.resolution_options(Vector2i(1920, 1200), Vector2i(1280, 720),
		Vector2i(1920, 1108))
	var keys: Array = opts.map(func(o: Array) -> String: return o[1])
	# 1920x1200 is there as the monitor's own (native) size, for a borderless window; the
	# standard steps stop at the usable height.
	_ok(not keys.has("1600x1200") and not keys.has("2560x1600"),
		"usable/no standard size taller than the usable area is offered", str(keys))
	_ok(keys.has("1920x1080") and keys.has("1280x1024") and keys.has("1280x800"),
		"usable/what fits still is", str(keys))
	_eq(DesktopWindow.parse_key("1024x768"), Vector2i(1024, 768), "usable/1024x768 is 1024 wide and 768 tall")


func _target() -> void:
	var usable := Vector2i(1969, 1108)
	var title := Vector2i(0, 37)
	# A window the player made as tall as the screen must come back the size it was, not
	# a little smaller every launch (it saved 1633x1108 and restored 1592x1080, then less).
	_eq(DesktopWindow.target_size(Vector2i(1633, 1108), usable, title, false), Vector2i(1633, 1108),
		"target/a size the player chose is restored exactly, title bar or not")
	var again := Vector2i(1633, 1108)
	for i in 5:
		again = DesktopWindow.target_size(again, usable, title, false)
	_eq(again, Vector2i(1633, 1108), "target/and stays put over repeated restarts")
	var strict := DesktopWindow.target_size(Vector2i(2560, 1440), usable, title, true)
	_ok(strict.y <= usable.y - title.y, "target/the never-chosen default leaves room for the title bar", str(strict))
	_eq(DesktopWindow.target_size(Vector2i(7680, 4320), usable, title, false).y, 1108,
		"target/a size beyond the screen is still brought inside it")
	_eq(QualityManager.ZOOM_DEFAULT, 1.0, "zoom/the desktop starts at 1x, the Field of View as set")


func _ratios() -> void:
	for case: Array in [[1024, 768, "4:3"], [1280, 1024, "5:4"], [1280, 800, "16:10"],
			[1680, 1050, "16:10"], [1920, 1080, "16:9"], [1366, 768, "16:9"], [640, 480, "4:3"],
			[2560, 1080, "21:9"], [3440, 1440, "21:9"], [1500, 1000, "3:2"], [1000, 1000, "1:1"],
			[1400, 1050, "4:3"], [3840, 2160, "16:9"]]:
		_eq(DesktopWindow.ratio_label(Vector2i(case[0], case[1])), case[2],
			"ratio/%dx%d is %s" % [case[0], case[1], case[2]])
	_eq(DesktopWindow.ratio_label(Vector2i(1400, 1000)), "7:5", "ratio/an unusual shape is its fraction")
	_ok(DesktopWindow.ratio_label(Vector2i(1733, 977)) != "", "ratio/a dragged size is never blank")
	_eq(DesktopWindow.ratio_label(Vector2i.ZERO), "", "ratio/no size, no shape")
	# Every standard step is named by the shape its comment in the table says.
	var shapes := {}
	for step in DesktopWindow.SIZE_STEPS:
		shapes[DesktopWindow.ratio_label(step)] = true
	for want in ["4:3", "5:4", "16:10", "16:9", "21:9"]:
		_ok(shapes.has(want), "ratio/the sizes on offer include %s" % want)
	var opts := DesktopWindow.resolution_options(Vector2i(2560, 1600), Vector2i(1920, 1080))
	var labels: Array = opts.map(func(o: Array) -> String: return o[0])
	_ok(labels.has("1024×768  4:3"), "ratio/the row shows 1024x768 as 4:3", str(labels))
	_ok(labels.has("1280×800  16:10"), "ratio/and 1280x800 as 16:10")
	_ok(labels.has("2560×1600  16:10  (native)"), "ratio/and still marks the native size")


func _zoom() -> void:
	_ok(absf(DesktopWindow.zoomed_fov(75.0, 1.0) - 75.0) < 0.0001, "zoom/1x is the field of view as set")
	var two := DesktopWindow.zoomed_fov(75.0, 2.0)
	_ok(absf(tan(deg_to_rad(two) * 0.5) * 2.0 - tan(deg_to_rad(75.0) * 0.5)) < 0.0001,
		"zoom/2x halves the visible height, not the angle", str(two))
	_ok(two < 75.0 and two > 37.5, "zoom/so 75 degrees at 2x is between 37.5 and 75", str(two))
	_ok(DesktopWindow.zoomed_fov(75.0, 4.0) < DesktopWindow.zoomed_fov(75.0, 2.0), "zoom/more zoom, narrower view")
	_ok(DesktopWindow.zoomed_fov(110.0, 3.0) > 0.0 and DesktopWindow.zoomed_fov(110.0, 3.0) < 110.0,
		"zoom/a wide field of view still narrows")
	_ok(is_finite(DesktopWindow.zoomed_fov(75.0, 0.0)), "zoom/a zero zoom does not divide by zero")


func _mode() -> void:
	_ok(DesktopWindow.current_mode() in ["windowed", "borderless", "maximized", "fullscreen", ""],
		"mode/reads one of the known modes", DesktopWindow.current_mode())
