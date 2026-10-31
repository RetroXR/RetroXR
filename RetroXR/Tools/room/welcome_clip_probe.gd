## Records the welcome page's menu clip (Welcome2D.MENU_CLIP): the real spawn menu,
## at its real size in a viewport of its own, driven by a pointer that moves the
## way a hand would and clicks with the real input events, so every hover and
## press is the menu's own.
##
## Writes one PNG a frame at FPS into --out; Tools/art/encode_welcome_clip.py
## makes the .ogv from them. WINDOWED (headless draws nothing):
##
##     "$godot" --path RetroXR --resolution 1280x720 --position 20,20 \
##         res://Tools/room/welcome_clip_probe.tscn -- --out=/tmp/welcome/clip
##     python Tools/art/encode_welcome_clip.py /tmp/welcome/clip
##
## --map lists what can be pressed at each stage (text and place) and saves a
## still of each, to choose targets by; nothing is recorded.
##
## It presses nothing that changes anything: CORES and SPAWN are views, a
## system's card is a view, and "Download All Recommended" is only pointed at.
extends Node

const MENU := preload("res://Scenes/UI/spawn_menu.tscn")
const SIZE := Vector2i(2200, 1800)
## The clip's frame: the menu at 0.4, which is what the page shows it at.
const OUT_SIZE := Vector2i(880, 720)
const FPS := 30
## What the clip types into the Systems filter.
const FILTER := "super nin"

var _out := ""
var _map := false
var _sub: SubViewport = null
var _menu: Control = null
var _pointer: Pointer = null
var _frame := 0
var _recording := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
		elif a == "--map":
			_map = true
	DirAccess.make_dir_recursive_absolute(_out)
	get_tree().create_timer(240.0).timeout.connect(func() -> void:
		print("[clipprobe] TIMEOUT")
		get_tree().quit(1))

	_sub = SubViewport.new()
	_sub.size = SIZE
	_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sub.transparent_bg = false
	add_child(_sub)
	_menu = MENU.instantiate() as Control
	_sub.add_child(_menu)
	_pointer = Pointer.new()
	_sub.add_child(_pointer)
	_pointer.at = Vector2(SIZE) * Vector2(0.62, 0.92)
	await _settle(90)

	if _map:
		await _map_stage("start")
		await _press(_nav("CORES"))
		await _wait_for_core_list()
		_scrub()
		await _settle(10)
		await _map_stage("cores")
		await _press(_nav("SPAWN"))
		await _settle(30)
		await _press(_filter_box())
		await _type(FILTER)
		await _settle(30)
		await _map_stage("filtered")
		await _press(_system_tile())
		await _settle(30)
		await _map_stage("card")
		get_tree().quit(0)
		return

	await _record()
	print("[clipprobe] wrote %d frames to %s" % [_frame, _out])
	get_tree().quit(0)


# ── the clip ──────────────────────────────────────────────────────────────────

func _record() -> void:
	# Fetched before the clip starts, so it never shows a wait.
	await _press(_nav("CORES"))
	await _wait_for_core_list()
	await _press(_nav("SPAWN"))
	await _settle(20)
	_scrub()

	_recording = true
	await _hold(0.8)
	var cores := _nav("CORES")
	await _move_to(cores, 1.0)
	await _press(cores)
	_scrub()
	await _hold(0.8)
	var all := _button_with("Download All Recommended")
	if all == null:
		all = _button_with("Every Recommended Core")
	await _move_to(all, 1.0)
	await _pulse(1.6)

	var spawn := _nav("SPAWN")
	await _move_to(spawn, 1.1)
	await _press(spawn)
	await _hold(0.6)
	var box := _filter_box()
	await _move_to(box, 0.8)
	await _press(box)
	await _type(FILTER)
	await _hold(0.6)
	var tile := _system_tile()
	await _move_to(tile, 0.8)
	await _press(tile)
	await _hold(0.8)
	var row := _button_with_part("Super NES")
	await _move_to(row, 0.9)
	await _pulse(1.4)

	var tvs := _button_with("TVs", true)
	await _move_to(tvs, 1.0)
	await _press(tvs)
	await _hold(0.8)
	var set_row := _button_with_part("+")
	await _move_to(set_row, 0.9)
	await _pulse(1.4)
	await _move_to(null, 0.9)
	await _hold(0.4)
	_recording = false


## The first visible button whose text has `part` in it.
func _button_with_part(part: String) -> Control:
	for node: Node in _menu.find_children("*", "BaseButton", true, false):
		var b := node as BaseButton
		if b.is_visible_in_tree() and "text" in b and part in str(b.get("text")):
			return b
	print("[clipprobe] no button with '%s'" % part)
	return null


# ── finding things ────────────────────────────────────────────────────────────

## The CORES download list is fetched from the buildbot; until it lands the
## button the clip points at says "waiting". Up to 30 s.
func _wait_for_core_list() -> void:
	for i in 30 * 60:
		var b := _button_with("Download All Recommended", false, true)
		var e := _button_with("Every Recommended Core", false, true)
		if (b != null and not (b as BaseButton).disabled) or e != null:
			print("[clipprobe] core list in after %.1f s" % (i / 60.0))
			return
		await get_tree().process_frame
	print("[clipprobe] core list never came; the button stays disabled in the clip")


## Nothing of this machine's in a clip that ships: the folder labels name the
## user's home, so they read as a fresh install's would.
func _scrub() -> void:
	var home := OS.get_environment("USERPROFILE").replace("\\", "/")
	if home.is_empty():
		home = OS.get_environment("HOME")
	for node: Node in _menu.find_children("*", "Label", true, false):
		var l := node as Label
		if not home.is_empty() and home in l.text:
			l.text = l.text.replace(home, "~")


## The Systems page's filter box.
func _filter_box() -> Control:
	for node: Node in _menu.find_children("*", "LineEdit", true, false):
		var e := node as LineEdit
		if e.is_visible_in_tree() and "ilter" in e.placeholder_text:
			return e
	print("[clipprobe] no filter box")
	return null


## Type `text` into whatever has focus, a key at a time, as a keyboard would.
func _type(text: String) -> void:
	for ch in text:
		var ev := InputEventKey.new()
		ev.pressed = true
		ev.unicode = ch.unicode_at(0)
		ev.keycode = OS.find_keycode_from_string(ch.to_upper())
		_sub.push_input(ev)
		var up := ev.duplicate() as InputEventKey
		up.pressed = false
		_sub.push_input(up)
		for i in 5:
			await _tick()

func _nav(label: String) -> Control:
	return _button_with(label, true)


## The first visible button whose text is `label` (or begins with it).
func _button_with(label: String, exact := false, quiet := false) -> Control:
	for node: Node in _menu.find_children("*", "BaseButton", true, false):
		var b := node as BaseButton
		if not b.is_visible_in_tree():
			continue
		var t := str(b.get("text")) if "text" in b else ""
		if (t == label) if exact else t.strip_edges().begins_with(label):
			return b
	if not quiet:
		print("[clipprobe] no button '%s'" % label)
	return null


## A system's tile on the Systems grid: the first visible tile-sized button
## below the nav bar, preferring a familiar console.
func _system_tile() -> Control:
	var best: Control = null
	for node: Node in _menu.find_children("*", "BaseButton", true, false):
		var b := node as BaseButton
		if not b.is_visible_in_tree():
			continue
		var r := b.get_global_rect()
		if r.size.x < 150 or r.size.y < 150:
			continue
		var t := (str(b.get("tooltip_text")) + " " + str(b.get("text"))).to_lower()
		if "super nintendo" in t or "snes" in t:
			return b
		if best == null:
			best = b
	return best


func _map_stage(stage: String) -> void:
	await RenderingServer.frame_post_draw
	_sub.get_texture().get_image().save_png(_out.path_join("map_%s.png" % stage))
	for node: Node in _menu.find_children("*", "BaseButton", true, false):
		var b := node as BaseButton
		if not b.is_visible_in_tree():
			continue
		var r := b.get_global_rect()
		var t := str(b.get("text")) if "text" in b else ""
		print("[clipprobe] %s  %-28s %s  tip=%s  (%s)" % [stage, t.substr(0, 28).replace("\n", " "),
			r, str(b.get("tooltip_text")).substr(0, 40).replace("\n", " "), b.name])


# ── the pointer, and the frames ───────────────────────────────────────────────

## Glide to `target`'s centre (or off to the lower right, for null) over `seconds`,
## eased, sending the menu a mouse motion every frame so it lights what it is over.
func _move_to(target: Control, seconds: float) -> void:
	var from := _pointer.at
	var to := _aim(target) if target != null else Vector2(SIZE) * Vector2(0.62, 0.92)
	var n := maxi(1, int(seconds * FPS))
	for i in n:
		var k := smoothstep(0.0, 1.0, float(i + 1) / n)
		_pointer.at = from.lerp(to, k)
		_motion(_pointer.at)
		await _tick()


func _press(target: Control) -> void:
	if target == null:
		return
	var at := _aim(target)
	_pointer.click()
	_button(at, true)
	await _tick()
	await _tick()
	_button(at, false)
	await _tick()


## Where on `target` the dot goes: beside its words, not on them, or the clip
## hides the very label it is pointing at. Right of the middle of a wide button
## (row text is left-aligned, a centred label is short), under the label of a
## narrow one.
func _aim(target: Control) -> Vector2:
	var r := target.get_global_rect()
	if r.size.x > 500.0:
		return r.get_center() + Vector2(r.size.x * 0.3, 0.0)
	return r.get_center() + Vector2(0.0, r.size.y * 0.3)


## Point at something without pressing it: the pointer pulses where it is.
func _pulse(seconds: float) -> void:
	var n := int(seconds * FPS)
	for i in n:
		_pointer.ring = 0.5 + 0.5 * sin(float(i) / FPS * TAU * 1.5)
		_motion(_pointer.at)
		await _tick()
	_pointer.ring = 0.0


func _hold(seconds: float) -> void:
	for i in int(seconds * FPS):
		await _tick()


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _motion(at: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = at
	ev.global_position = at
	_sub.push_input(ev)


func _button(at: Vector2, down: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = down
	ev.position = at
	ev.global_position = at
	_sub.push_input(ev)


## One frame of the clip: drawn, then saved at the clip's size.
func _tick() -> void:
	_pointer.queue_redraw()
	await RenderingServer.frame_post_draw
	if _recording:
		var img := _sub.get_texture().get_image()
		img.resize(OUT_SIZE.x, OUT_SIZE.y, Image.INTERPOLATE_LANCZOS)
		img.save_png(_out.path_join("f_%05d.png" % _frame))
		_frame += 1


## The pointer drawn over the menu: a laser's dot, so it reads as the headset's
## pointer and as the desktop's crosshair alike, a ripple when it clicks and a ring
## when it only points.
class Pointer extends Control:
	const COLOR := Color(0.35, 0.95, 1.0)
	const RADIUS := 22.0
	const RIPPLE_SECONDS := 0.45

	var at := Vector2.ZERO
	## 0..1: how strongly the "pointing at this" ring shows.
	var ring := 0.0
	var _ripple := -1.0

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		z_index = 100

	func click() -> void:
		_ripple = 0.0

	func _process(delta: float) -> void:
		if _ripple >= 0.0:
			_ripple += delta
			if _ripple > RIPPLE_SECONDS:
				_ripple = -1.0
		queue_redraw()

	func _draw() -> void:
		if _ripple >= 0.0:
			var k := _ripple / RIPPLE_SECONDS
			draw_arc(at, RADIUS + 70.0 * k, 0.0, TAU, 48, Color(COLOR, 1.0 - k), 8.0)
		if ring > 0.01:
			draw_arc(at, RADIUS + 16.0 + 10.0 * ring, 0.0, TAU, 48, Color(COLOR, 0.35 + 0.5 * ring), 6.0)
		draw_circle(at, RADIUS + 5.0, Color(0, 0, 0, 0.55))
		draw_circle(at, RADIUS, COLOR)
		draw_circle(at, RADIUS * 0.4, Color.WHITE)
