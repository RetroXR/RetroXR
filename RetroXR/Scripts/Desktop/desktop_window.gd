## DesktopWindow -- the desktop window: where it opens, what it remembers, and
## how it behaves when the player drags its edge.
##
## Three things used to be true of the window and none should have been:
##  * it opened at the project's 2560x1440 whatever the screen, so on a 1080p
##    monitor the bottom of the picture hung off the desktop;
##  * the saved mode and size were applied only when the spawn menu was BUILT, so
##    they came back late, and again (re-centring the window) on every room change;
##  * a size chosen by dragging was never saved, and the menu's Resolution row went
##    on showing the old one.
##
## The pure part is static and takes plain values, so Tests/desktop_window_tests
## can check the arithmetic without a display. The instance is the tracker: it
## listens for the window changing, waits for it to settle (a drag is hundreds of
## events), and writes the settled mode and size through QualityManager.
class_name DesktopWindow
extends Node

## The window has settled on a new size or mode; the key is "WxH".
signal settled(key: String)

## Below this the room's own overlays no longer fit, and nothing is gained. Low enough
## for 640x480, the smallest of the usual 4:3 sizes.
const MIN_SIZE := Vector2i(640, 360)
## How long the window must hold still before it counts as settled.
const SETTLE_SECONDS := 0.5
## How far short of the usable area a window may fall and still count as filling it (a title
## bar, a border), and how long a maximise or restore is given to reach the window manager.
const FILL_MARGIN := 60
## What a window gets when nothing was ever saved: the size the project was authored at, brought
## inside the screen. (The window itself OPENS at a small override, see project.godot.)
const DEFAULT_KEY := "2560x1440"
const UNSTICK_SECONDS := 0.25
## What the Resolution row offers, before it is cut down to what the screen holds:
## the usual sizes of every common shape, not only the wide ones.
const SIZE_STEPS: Array[Vector2i] = [
	# 4:3
	Vector2i(640, 480), Vector2i(800, 600), Vector2i(1024, 768), Vector2i(1280, 960),
	Vector2i(1400, 1050), Vector2i(1600, 1200),
	# 5:4
	Vector2i(1280, 1024),
	# 16:10
	Vector2i(1280, 800), Vector2i(1440, 900), Vector2i(1680, 1050), Vector2i(1920, 1200),
	Vector2i(2560, 1600),
	# 16:9
	Vector2i(1024, 576), Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900),
	Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160),
	# 21:9
	Vector2i(2560, 1080), Vector2i(3440, 1440),
]

## The shapes a size is named by, [width / height, name]. A size within RATIO_TOLERANCE
## of one is that shape: 1366x768 is not exactly 16:9, and nobody calls it anything else.
const RATIOS: Array = [
	[1.0, "1:1"], [5.0 / 4.0, "5:4"], [4.0 / 3.0, "4:3"], [3.0 / 2.0, "3:2"],
	[16.0 / 10.0, "16:10"], [5.0 / 3.0, "5:3"], [16.0 / 9.0, "16:9"], [2.0, "2:1"],
	[64.0 / 27.0, "21:9"], [43.0 / 18.0, "21:9"], [32.0 / 9.0, "32:9"],
]
const RATIO_TOLERANCE := 0.012

## The tracker in the tree, for a view that wants its `settled`.
static var instance: DesktopWindow = null
static var _restored := false

var _token := 0


# ── Pure ──────────────────────────────────────────────────────────────────────

## "1920x1080" -> (1920, 1080); (0, 0) for anything else.
static func parse_key(key: String) -> Vector2i:
	var parts := key.split("x")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i.ZERO
	var v := Vector2i(parts[0].to_int(), parts[1].to_int())
	return v if v.x > 0 and v.y > 0 else Vector2i.ZERO


static func key_of(size: Vector2i) -> String:
	return "%dx%d" % [size.x, size.y]


## `size` brought inside `room`, keeping its shape: a window wider than the screen
## is scaled down, never squeezed on one axis. Never smaller than MIN_SIZE unless
## `room` itself is. An empty `room` (a headless run reports none) changes nothing.
static func fit(size: Vector2i, room: Vector2i) -> Vector2i:
	if room.x <= 0 or room.y <= 0:
		return size
	var out := size
	if out.x > room.x or out.y > room.y:
		var k := minf(float(room.x) / out.x, float(room.y) / out.y)
		out = Vector2i(roundi(out.x * k), roundi(out.y * k))
	out = Vector2i(maxi(out.x, MIN_SIZE.x), maxi(out.y, MIN_SIZE.y))
	return Vector2i(mini(out.x, room.x), mini(out.y, room.y))


## The shape of a size as people say it: "16:9", "4:3", "16:10". A shape that is none of
## the usual ones is its reduced fraction ("7:5"), or "2.35:1" when that is not small.
static func ratio_label(size: Vector2i) -> String:
	if size.x <= 0 or size.y <= 0:
		return ""
	var r := float(size.x) / size.y
	for entry: Array in RATIOS:
		if absf(r - float(entry[0])) / float(entry[0]) <= RATIO_TOLERANCE:
			return str(entry[1])
	var g := _gcd(size.x, size.y)
	@warning_ignore("integer_division")
	var w := size.x / g
	@warning_ignore("integer_division")
	var h := size.y / g
	return "%d:%d" % [w, h] if w <= 32 and h <= 32 else "%.2f:1" % r


static func _gcd(a: int, b: int) -> int:
	while b != 0:
		var t := b
		b = a % b
		a = t
	return maxi(a, 1)


## The vertical field of view that shows `zoom` times as close as `fov_degrees` does.
## Zoom 1 is exactly the field of view; 2 shows half the width and half the height of
## it. The tangent is what scales, not the angle: halving 75 degrees is not twice as
## close.
static func zoomed_fov(fov_degrees: float, zoom: float) -> float:
	var z := maxf(zoom, 0.01)
	return rad_to_deg(2.0 * atan(tan(deg_to_rad(fov_degrees) * 0.5) / z))


## How many times further than usual the spawn menu stands at this zoom. 1x leaves it where
## it always was; each extra 1x of zoom adds MENU_PUSH_PER_ZOOM of the usual distance, so 2x
## is 1.5 times as far (1.35 m) and 4x two and a half (2.25 m). Pushing it out by the full
## zoom (2x = 1.8 m) keeps it exactly as large as at 1x but was found too far away, and three
## times as far at 2x worse; the cost of this middle is a menu that looks a little larger
## than at 1x in a zoomed view.
const MENU_PUSH_PER_ZOOM := 0.5


static func menu_distance_factor(zoom: float) -> float:
	return 1.0 + maxf(zoom - 1.0, 0.0) * MENU_PUSH_PER_ZOOM


## The sizes to offer: the standard steps the usable screen can hold, the screen's own
## size, and the window as it is now (so the row never opens on a blank value after
## a drag), smallest first. Each is [label, key].
static func resolution_options(native: Vector2i, current: Vector2i,
		usable := Vector2i.ZERO) -> Array:
	var sizes: Array[Vector2i] = []
	# A window cannot be taller than the desktop's usable area (the panel and dock take
	# some of the screen), so the standard sizes are held to THAT, not to the monitor:
	# 1600x1200 on a 1920x1200 screen with a panel would otherwise be offered and come
	# out as 1525x1108.
	var room := usable if usable.x > 0 and usable.y > 0 else native
	for step in SIZE_STEPS:
		if step.x <= room.x and step.y <= room.y:
			sizes.append(step)
	for extra in [current, native]:
		if extra.x > 0 and extra.y > 0 and not sizes.has(extra):
			sizes.append(extra)
	sizes.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var area_a := a.x * a.y
		var area_b := b.x * b.y
		return area_a < area_b or (area_a == area_b and a.x < b.x))
	var options: Array = []
	for s in sizes:
		var label := "%d×%d  %s" % [s.x, s.y, ratio_label(s)]
		if s == native:
			label += "  (native)"
		elif s == current and not SIZE_STEPS.has(s):
			label += "  (current)"
		options.append([label, key_of(s)])
	return options


# ── The display ───────────────────────────────────────────────────────────────

## "fullscreen", "maximized", "borderless" or "windowed"; "" while minimised, when
## the size means nothing.
static func current_mode() -> String:
	match DisplayServer.window_get_mode():
		DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
			return "fullscreen"
		DisplayServer.WINDOW_MODE_MAXIMIZED:
			return "maximized"
		DisplayServer.WINDOW_MODE_MINIMIZED:
			return ""
	return "borderless" if DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_BORDERLESS) \
		else "windowed"


static func current_key() -> String:
	return key_of(DisplayServer.window_get_size())


## The main window, through the engine's own Window rather than DisplayServer. They are
## NOT interchangeable on X11: DisplayServer.window_set_size resizes the real window
## and records the new size, so when the X server's ConfigureNotify arrives there is
## "no change" to report and the Window node (and so the viewport) never hears of it --
## a bigger window drawing the old picture, cropped, with the crosshair off to one side.
## Window.size does both. (Measured on X11 under GNOME: the window 1500x700, the viewport
## 960x600, no size_changed.)
static func _window() -> Window:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root if tree != null else null


static func apply_mode(mode: String) -> void:
	var win := _window()
	if win == null:
		return
	match mode:
		"fullscreen":
			win.mode = Window.MODE_FULLSCREEN
		"maximized":
			win.borderless = false
			win.mode = Window.MODE_MAXIMIZED
		"borderless":
			win.mode = Window.MODE_WINDOWED
			win.borderless = true
		_:
			win.mode = Window.MODE_WINDOWED
			win.borderless = false


## What size a window asked to be `want` gets on a screen whose usable area is `usable`
## and whose windows wear `decoration` (the title bar), counted only when `strict`.
static func target_size(want: Vector2i, usable: Vector2i, decoration: Vector2i,
		strict: bool) -> Vector2i:
	return fit(want, usable - (decoration if strict else Vector2i.ZERO))


## Size the window to `key` and centre it on the screen it is on. A fullscreen
## window is left alone (the choice is saved by the caller and applies when the
## player leaves it); a maximised one is brought out of that first, since a size
## cannot be asked of it.
##
## The size is brought inside the screen's usable area, but the window's own title bar
## is only counted when `strict`: a size the player made themselves (a drag, a pick from
## the list) was reachable, and taking the title bar off it on every launch shrank a
## window that was as tall as the screen by a little more at each restart. `strict` is for
## a size nobody chose, the project's 2560x1440 default.
##
## `unstick` is for a size the player asks for while the game is running (the Resolution row).
## A window that fills the screen along one axis may be MAXIMISED along just that one, which
## GNOME does when an edge is dragged to the top of the screen, and the engine neither
## reports nor clears it: it only undoes a full maximise. The size request then lands on the
## other axis alone -- 640x480 asked, 640x1108 got. So such a window is first maximised and
## restored, which the engine does clear, and only then sized. A coroutine, for that reason:
## `await` it where the order matters.
static func apply_size(key: String, strict := false, unstick := false) -> void:
	var want := parse_key(key)
	var win := _window()
	if want == Vector2i.ZERO or win == null or current_mode() == "fullscreen":
		return
	var screen := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	if current_mode() == "maximized":
		win.mode = Window.MODE_WINDOWED
	elif unstick and fills_screen(win.size, usable.size):
		var tree := Engine.get_main_loop() as SceneTree
		win.mode = Window.MODE_MAXIMIZED
		await tree.create_timer(UNSTICK_SECONDS).timeout
		win.mode = Window.MODE_WINDOWED
		await tree.create_timer(UNSTICK_SECONDS).timeout
	var decoration := DisplayServer.window_get_size_with_decorations() \
		- DisplayServer.window_get_size()
	var size := target_size(want, usable.size, decoration, strict)
	win.size = size
	if usable.size.x > 0:
		@warning_ignore("integer_division")
		var centred := usable.position + (usable.size - size - decoration) / 2
		win.position = Vector2i(maxi(centred.x, usable.position.x), maxi(centred.y, usable.position.y))


## Whether a window of `size` reaches (nearly) both edges of the usable area along either
## axis, which is when a window manager may hold it maximised or tiled on that axis.
static func fills_screen(size: Vector2i, usable: Vector2i) -> bool:
	if usable.x <= 0 or usable.y <= 0:
		return false
	return size.x >= usable.x - FILL_MARGIN or size.y >= usable.y - FILL_MARGIN


## The saved mode and size, applied once per process. The size goes first so that
## leaving fullscreen or maximised returns to it. With nothing saved the window is
## still fitted to the screen, which the project's 2560x1440 default never was.
static func restore() -> void:
	if _restored:
		return
	_restored = true
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.root.min_size = MIN_SIZE
	var key := QualityManager.resolution
	var chosen := parse_key(key) != Vector2i.ZERO
	if not chosen:
		key = DEFAULT_KEY
	# unstick: a window that came up held along one axis by the window manager is freed first,
	# or only the other axis would take the saved size and the wrong one be saved back.
	# Awaited: the unstick ends by setting the window WINDOWED, which would undo a saved
	# fullscreen or maximised mode applied before it. Each step is inside the tracker's
	# SETTLE_SECONDS, so only the mode applied last is saved.
	await apply_size(key, not chosen, true)
	var mode := QualityManager.window_mode
	if not mode.is_empty() and mode != "windowed":
		apply_mode(mode)


# ── The tracker ───────────────────────────────────────────────────────────────

func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	if instance == self:
		instance = null


func _ready() -> void:
	get_window().min_size = MIN_SIZE
	get_window().size_changed.connect(_on_size_changed)


func _on_size_changed() -> void:
	_token += 1
	var mine := _token
	get_tree().create_timer(SETTLE_SECONDS).timeout.connect(func() -> void:
		if mine == _token:
			_settle())


func _settle() -> void:
	var mode := current_mode()
	if mode.is_empty():
		return
	if mode != QualityManager.window_mode:
		QualityManager.set_window_state(mode, "")
	# Only a window the player sized: a maximised or fullscreen one reports the
	# screen's size, which is not a choice and would be wrong to bring back.
	if mode in ["windowed", "borderless"] and current_key() != QualityManager.resolution:
		QualityManager.set_window_state("", current_key())
	settled.emit(current_key())
