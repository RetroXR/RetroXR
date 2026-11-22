## Does a Wii U game boot on RetroXR's Cemu, and does the core hand the TV and the
## GamePad over as two video views (RETRO_ENVIRONMENT_SET_VIDEO_VIEWS)?
##
## Needs the real core and a game, so it is a probe. Windowed (the core renders on
## the GPU). One leg per process:
##
##   "$godot" --path RetroXR --resolution 320x240 --position 20,20 \
##     res://DevTools/cores/wiiu_boot_probe.tscn -- \
##     --rom="$HOME/retroxr/roms/wiiu/Nintendo Land [0005000010102000]/title.tmd"
##
## --leg=views    (default) two views, screen 0 the TV and 1 the GamePad, inside
##                the frame, and pictures in both rects
## --leg=noviews  the control: run with XENU_NO_VIDEO_VIEWS=1 so the frontend says it
##                presents none, and the core must send none
## --seconds=N    how long to let it run (default 90); --shot=<png> saves the last frame
## --press=<id>@<s>[,...]  presses RetroPad id <id> on port 0 (the GamePad) for a
##                quarter second at <s> seconds; 16 is HOME (RetroXR's own id), 8 A
## --shots=<s>[,...]  also saves the frame at each time, as <shot>_<s>s.png
## --touch=<u>:<v>@<s>[,...]  touches the packed frame at (u, v), 0..1, for a
##                quarter second at <s> seconds (the GamePad's view is on the right)
##
## The Wii U Menu: --rom=<mlc01>/sys/title/00050010/10040100/code/men.rpx (the US
## menu, from a system dump laid into the core's mlc01).
extends Node

var _lib: Node = null
var _rom := ""
var _root := ""
var _leg := "views"
var _seconds := 90.0
## --gyro=<rad/s>: the GamePad (port 0) lying flat, still until 25 s and then
## turning at this rate about the vertical (out of its screen, Android's z). Run
## with CEMU_MOTION_TRACE=1: the core says what it got and what it reports.
var _gyro := 0.0
var _shot := ""
## --core=<name>: the libretro core to run (default parallel_gx2; cemu is RetroXR's old fork).
var _core := "parallel_gx2"
## --opt=<key>=<value> (repeatable): written into the core's .opt before start, as
## RetroSystem pins its forced options (CoreOptionsStore.merge_values).
var _opts := {}
## [[id, seconds], ...] from --press; seconds still to shoot from --shots.
var _presses: Array = []
var _shots: Array[float] = []
## [[Vector2 uv, seconds], ...] from --touch.
var _touches: Array = []
var _touching := false
var _failed := ""
var _last_mask := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rom="):
			_rom = a.substr(6)
		elif a.begins_with("--root="):
			_root = a.substr(7)
		elif a.begins_with("--leg="):
			_leg = a.substr(6)
		elif a.begins_with("--gyro="):
			_gyro = float(a.substr(7))
		elif a.begins_with("--seconds="):
			_seconds = float(a.substr(10))
		elif a.begins_with("--shot="):
			_shot = a.substr(7)
		elif a.begins_with("--core="):
			_core = a.substr(7)
		elif a.begins_with("--opt="):
			var kv := a.substr(6).split("=", true, 1)
			if kv.size() == 2:
				_opts[kv[0]] = kv[1]
		elif a.begins_with("--press="):
			for item: String in a.substr(8).split(",", false):
				var parts := item.split("@")
				if parts.size() == 2:
					_presses.append([int(parts[0]), float(parts[1])])
		elif a.begins_with("--touch="):
			for item: String in a.substr(8).split(",", false):
				var at := item.split("@")
				var uv := at[0].split(":") if at.size() == 2 else PackedStringArray()
				if uv.size() == 2:
					_touches.append([Vector2(float(uv[0]), float(uv[1])), float(at[1])])
		elif a.begins_with("--shots="):
			for t: String in a.substr(8).split(",", false):
				_shots.append(float(t))
	get_tree().create_timer(_seconds + 60.0).timeout.connect(func() -> void:
		print("[wiiu] FAIL: timed out")
		get_tree().quit(1))
	if _root.is_empty():
		_root = CoreDownloadManager.default_core_root()
	if _rom.is_empty() or not FileAccess.file_exists(_rom):
		print("[wiiu] FAIL: --rom must name a file that exists (got '%s')" % _rom)
		get_tree().quit(1)
		return
	var env_off := OS.get_environment("XENU_NO_VIDEO_VIEWS")
	if _leg == "noviews" and (env_off.is_empty() or env_off == "0"):
		print("[wiiu] FAIL: the noviews leg needs XENU_NO_VIDEO_VIEWS=1 in the environment")
		get_tree().quit(1)
		return

	_lib = ClassDB.instantiate("Libretro") as Node
	if _lib == null:
		print("[wiiu] FAIL: could not instantiate Libretro")
		get_tree().quit(1)
		return
	add_child(_lib)
	_lib.connect("content_load_failed", func(reason: String) -> void: _failed = reason)
	print("[wiiu] leg=%s core=%s rom=%s" % [_leg, _core, _rom])
	if not _opts.is_empty():
		CoreOptionsStore.merge_values(_root, _core, _opts)
		print("[wiiu] options pinned: %s" % str(_opts))
	_lib.StartContent(_root, _core, _rom)

	var t0 := Time.get_ticks_msec()
	var views: Array = []
	var first_views_ms := -1
	var frames_seen := 0
	var last_tex: Texture2D = null
	# The CORE's frames a second, against what it declares (Wind Waker HD says 30).
	var fps_at := t0
	var fps_frames := 0
	var fps_samples: Array[float] = []
	while Time.get_ticks_msec() - t0 < int(_seconds * 1000.0):
		await get_tree().process_frame
		if not _failed.is_empty():
			break
		if _gyro != 0.0:
			var turning := Time.get_ticks_msec() - t0 >= 25000
			_lib.call("SetSensorAccel", 0, 0.0, 0.0, 1.0)
			_lib.call("SetSensorGyro", 0, 0.0, 0.0, _gyro if turning else 0.0)
		var now_s := (Time.get_ticks_msec() - t0) / 1000.0
		if not _presses.is_empty():
			var mask := 0
			for pr: Array in _presses:
				if now_s >= float(pr[1]) and now_s < float(pr[1]) + 0.25:
					mask |= 1 << int(pr[0])
			_lib.call("SetJoypadState", 0, mask, 0, 0, 0, 0)
			if mask != _last_mask:
				_last_mask = mask
				print("[wiiu] t=%.2fs port 0 buttons 0x%x" % [now_s, mask])
		if not _touches.is_empty():
			var touch: Variant = null
			for tc: Array in _touches:
				if now_s >= float(tc[1]) and now_s < float(tc[1]) + 0.25:
					touch = tc[0]
			var down := touch != null
			var uv: Vector2 = touch if down else Vector2.ZERO
			_lib.call("SetPointerState", 0, int(uv.x * 65534.0) - 32767, int(uv.y * 65534.0) - 32767, down)
			if down != _touching:
				_touching = down
				print("[wiiu] t=%.2fs touch %s %s" % [now_s, "on" if down else "off", str(uv)])
		if not _shots.is_empty() and now_s >= _shots[0] and not _shot.is_empty():
			var at := _shots.pop_front() as float
			var cur: Texture2D = _lib.call("GetVideoTexture")
			var img := cur.get_image() if cur != null else null
			if img != null:
				var path := "%s_%ds.png" % [_shot.get_basename(), int(at)]
				img.save_png(path)
				print("[wiiu] saved %s" % path)
		if Time.get_ticks_msec() - fps_at >= 1000:
			var n := int(_lib.call("GetFrameCount"))
			var fps := (n - fps_frames) * 1000.0 / float(Time.get_ticks_msec() - fps_at)
			fps_frames = n
			fps_at = Time.get_ticks_msec()
			fps_samples.append(fps)
			print("[wiiu] t=%ds core_fps=%.1f declared=%.2f dropped=%d godot_fps=%d" % [
				(fps_at - t0) / 1000, fps, float(_lib.call("GetDeclaredFps")),
				int(_lib.call("GetDroppedFrameCount")), Engine.get_frames_per_second()])
		var tex: Texture2D = _lib.call("GetVideoTexture")
		if tex != null:
			if tex != last_tex:
				last_tex = tex
			frames_seen += 1
		var v: Array = _lib.call("GetVideoViews")
		if not v.is_empty() and first_views_ms < 0:
			first_views_ms = Time.get_ticks_msec() - t0
			print("[wiiu] first views after %d ms: %s" % [first_views_ms, str(v)])
		if not v.is_empty():
			views = v
	_report(views, last_tex, frames_seen)


func _report(views: Array, tex: Texture2D, frames: int) -> void:
	if not _failed.is_empty():
		print("[wiiu] FAIL: content load failed: %s" % _failed)
		get_tree().quit(1)
		return
	var geo: Dictionary = _lib.call("GetVideoGeometry")
	print("[wiiu] frames=%d geometry=%s views=%s" % [frames, str(geo), str(views)])
	var img: Image = tex.get_image() if tex != null else null
	if img != null and not _shot.is_empty():
		img.save_png(_shot)
		print("[wiiu] saved %s (%dx%d)" % [_shot, img.get_width(), img.get_height()])
	var ok := true
	if img == null:
		print("[wiiu] FAIL: no frame")
		ok = false
	elif _leg == "noviews":
		if not views.is_empty():
			print("[wiiu] FAIL: views arrived with the frontend saying it presents none")
			ok = false
		var lit := _lit_fraction(img, Rect2(0, 0, 1, 1))
		print("[wiiu] whole frame lit=%.3f" % lit)
		ok = ok and lit > 0.02
	else:
		var tv: Variant = _view(views, 0)
		var pad: Variant = _view(views, 1)
		if tv == null or pad == null:
			print("[wiiu] FAIL: want screen 0 and screen 1, got %s" % str(views))
			ok = false
		else:
			var tv_lit := _lit_fraction(img, tv)
			var pad_lit := _lit_fraction(img, pad)
			print("[wiiu] TV %s lit=%.3f, GamePad %s lit=%.3f" % [tv, tv_lit, pad, pad_lit])
			ok = tv_lit > 0.02 and pad_lit > 0.02
			if not ok:
				print("[wiiu] FAIL: a view is black")
	print("[wiiu] RESULT=%s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)


func _view(views: Array, screen: int) -> Variant:
	for v: Dictionary in views:
		if int(v.get("screen", -1)) == screen:
			return v.get("rect")
	return null


## The share of a grid of samples inside `r` (0..1 of the frame) that is not black.
func _lit_fraction(img: Image, r: Rect2) -> float:
	var lit := 0
	var n := 0
	for gy in 24:
		for gx in 32:
			var x := int((r.position.x + r.size.x * (gx + 0.5) / 32.0) * img.get_width())
			var y := int((r.position.y + r.size.y * (gy + 0.5) / 24.0) * img.get_height())
			x = clampi(x, 0, img.get_width() - 1)
			y = clampi(y, 0, img.get_height() - 1)
			var c := img.get_pixel(x, y)
			n += 1
			if c.r + c.g + c.b > 0.06:
				lit += 1
	return float(lit) / float(maxi(n, 1))
