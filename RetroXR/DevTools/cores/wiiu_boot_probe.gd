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
extends Node

var _lib: Node = null
var _rom := ""
var _root := ""
var _leg := "views"
var _seconds := 90.0
var _shot := ""
var _failed := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rom="):
			_rom = a.substr(6)
		elif a.begins_with("--root="):
			_root = a.substr(7)
		elif a.begins_with("--leg="):
			_leg = a.substr(6)
		elif a.begins_with("--seconds="):
			_seconds = float(a.substr(10))
		elif a.begins_with("--shot="):
			_shot = a.substr(7)
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
	print("[wiiu] leg=%s rom=%s" % [_leg, _rom])
	_lib.StartContent(_root, "cemu", _rom)

	var t0 := Time.get_ticks_msec()
	var views: Array = []
	var first_views_ms := -1
	var frames_seen := 0
	var last_tex: Texture2D = null
	while Time.get_ticks_msec() - t0 < int(_seconds * 1000.0):
		await get_tree().process_frame
		if not _failed.is_empty():
			break
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
