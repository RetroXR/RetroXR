## The Wii U in the room: a console, a set on the Wii's AV lead, a GamePad paired
## over SYNC, a disc in the slot, POWER. The set shows the TV's view of the frame
## Cemu packs and the GamePad its own (video views); a touch on the GamePad's glass
## goes to the game. Windowed: stills of the set and the GamePad.
##
##   "$godot" --path RetroXR --resolution 960x540 --position 20,20 \
##     res://DevTools/models/wiiu_room_probe.tscn -- \
##     --rom="C:/Users/<you>/retroxr/roms/wiiu/Nintendo Land [0005000010102000]/title.tmd" \
##     [--out=<dir>] [--touch=none] [--perf=<seconds>] [--nopair]
##
## --perf=N times the ROOM's frames for N seconds from POWER (each second: frames,
## the worst frame in ms, the core's frames) and quits; --nopair leaves the GamePad
## and the Pro Controller unpaired, its control.
##
## --touch=none is the control leg: nothing touches the glass, and Nintendo Land's
## "Touch the Wii U GamePad to start" title must still be up at the end.
extends Node3D

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const TV_SCENE := preload("res://Scenes/Objects/tv.tscn")
const DISC_SCENE := preload("res://Scenes/Objects/media/disc.tscn")
const GAMEPAD_SCENE := preload("res://Scenes/Objects/controllers/wiiu/wiiu_gamepad.tscn")
const PRO_SCENE := preload("res://Scenes/Objects/controllers/wiiu/wiiu_pro_controller.tscn")
const AV_SCENE := preload("res://Scenes/Objects/system_models/wii/wii_av_cable.tscn")

var _rom := ""
var _out := ""
var _touch := "tap"
var _fail := false
var _sys: RetroSystem = null
var _tv: RetroTV = null
var _pad: WiiUGamePad = null
var _cam: Camera3D = null
## Unless --keep-save: Nintendo Land's save is moved aside for the run and put back
## after, so every leg starts from the game's first run (where the box is).
var _fresh := true
var _save_dir := ""
var _perf := 0.0
var _pair := true
var _perf_t0 := -1
var _perf_sec := 0
var _perf_frames := 0
var _perf_worst := 0.0
var _perf_core := 0
var _perf_hitches := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rom="):
			_rom = a.substr(6)
		elif a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--touch="):
			_touch = a.substr(8)
		elif a == "--keep-save":
			_fresh = false
		elif a.begins_with("--perf="):
			_perf = float(a.substr(7))
		elif a == "--nopair":
			_pair = false
	if _out.is_empty():
		_out = OS.get_user_data_dir()
	get_tree().create_timer(600.0).timeout.connect(func() -> void:
		print("[wiiu-room] FAIL: timed out")
		get_tree().quit(1))
	if _rom.is_empty() or not FileAccess.file_exists(_rom):
		print("[wiiu-room] FAIL: --rom must name a file that exists (got '%s')" % _rom)
		get_tree().quit(1)
		return
	# The GamePad's speaker is a Meta XR Audio voice of its own; the desktop
	# option can leave the SDK off for the whole process (controller-audio.md).
	var mx: Object = Engine.get_singleton("MetaXRAudio") if Engine.has_singleton("MetaXRAudio") else null
	if "--sdk=off" in OS.get_cmdline_user_args():
		mx = null
	# Only when it is off: set_enabled(true) on an SDK already on left Nintendo
	# Land on its loading screen for good (2026-11-20, four runs in a row).
	if mx != null and not bool(mx.call("is_available")):
		print("[wiiu-room] Meta XR Audio was off; enabling it for this run")
		mx.call("set_enabled", true)
	if _fresh:
		_set_save_aside()
	await _stage()
	if _perf > 0.0:
		await _perf_run()
		return
	await _boot()
	await _shoot("boot")
	# With no save, Nintendo Land waits at its title -- a red stage curtain, "Touch
	# the Wii U GamePad to start" -- for as long as nobody touches it (measured: 5
	# minutes). With a save it does not wait, which is why the save is set aside.
	var t0 := Time.get_ticks_msec()
	var red := 0.0
	while Time.get_ticks_msec() - t0 < 200000:
		await _wait_seconds(2.0)
		red = _red_share(_tv_image())
		if red > 0.5:
			break
	print("[wiiu-room] title curtain after %d s (red share %.2f)" % [(Time.get_ticks_msec() - t0) / 1000, red])
	_check(red > 0.5, "Nintendo Land reached its title")
	await _wait_seconds(5.0)   # the curtain settles before it takes a touch
	await _shoot("title")
	if _touch != "none":
		await _tap_gamepad()
	else:
		await _wait_seconds(15.0)   # the touches' length, so both legs keep one clock
	await _wait_seconds(10.0)
	await _shoot("after")
	var after := _red_share(_tv_image())
	print("[wiiu-room] red share after %s: %.2f" % ["touching the GamePad" if _touch != "none" else "no touch", after])
	if _touch != "none":
		_check(after < 0.25, "a touch on the GamePad's glass started the game")
		var lib := _sys.get_libretro_node()
		var voice := int(lib.call("GetControllerAudioVoiceId", 0, 0))
		print("[wiiu-room] the GamePad's speaker voice after the touch: %d" % voice)
		_check(voice >= 0, "the GamePad's sound has a voice of its own, played from the GamePad")
	else:
		_check(after > 0.5, "with no touch the title is still waiting (the control)")
	if _touch != "none":
		# What comes after the box: report whether the loading screen ever ends.
		var t2 := Time.get_ticks_msec()
		var lit := 0.0
		while Time.get_ticks_msec() - t2 < 90000:
			await _wait_seconds(3.0)
			lit = _lit_share(_tv_image())
			if lit > 0.5:
				break
		print("[wiiu-room] after the box: the TV is %s (lit %.2f, %d s)" % [
			"showing the game" if lit > 0.5 else "still on the loading screen", lit, (Time.get_ticks_msec() - t2) / 1000])
		await _shoot("later")
	if _fresh:
		_lib_stop_then_restore()
		await _wait_seconds(8.0)
		_put_save_back()
	print("[wiiu-room] RESULT=%s" % ("FAIL" if _fail else "PASS"))
	get_tree().quit(1 if _fail else 0)


## --perf: POWER, then the room's frame times for _perf seconds.
func _perf_run() -> void:
	var disc := DISC_SCENE.instantiate() as Node3D
	disc.set("systemid", "wiiu")
	disc.set("rom_path", _rom)
	add_child(disc)
	disc.global_position = _sys.global_position + Vector3(0, 0.3, 0.3)
	await _frames(10)
	(_sys.get_node("CartridgeSlot") as XRToolsSnapZone).pick_up_object(disc)
	await _frames(120)
	print("[wiiu-room] perf: POWER (paired=%s)" % _pair)
	_perf_t0 = Time.get_ticks_msec()
	_perf_sec = _perf_t0
	(_sys.get_node("PowerButton") as VRButton).button_pressed.emit()
	for o in LoadingOverlay.owners():
		LoadingOverlay.end(o)
	await _wait_seconds(_perf)
	print("[wiiu-room] perf: frames over 50 ms in %d s: %d" % [int(_perf), _perf_hitches])
	_lib_stop_then_restore()
	await _wait_seconds(8.0)
	if _fresh:
		_put_save_back()
	print("[wiiu-room] RESULT=PASS")
	get_tree().quit(0)


func _process(delta: float) -> void:
	if _perf_t0 < 0:
		return
	_perf_frames += 1
	_perf_worst = maxf(_perf_worst, delta * 1000.0)
	if delta > 0.05:
		_perf_hitches += 1
	var now := Time.get_ticks_msec()
	if now - _perf_sec >= 1000:
		var lib := _sys.get_libretro_node() if _sys != null else null
		var core := int(lib.call("GetFrameCount")) if lib != null and lib.has_method("GetFrameCount") else 0
		if (now - _perf_t0) / 1000 % 10 == 5 and lib != null and lib.has_method("GetPacingStats"):
			print("[wiiu-room] pacing %s" % str(lib.call("GetPacingStats")))
		print("[wiiu-room] perf t=%ds room_fps=%d worst=%.0fms core_fps=%d" % [
			(now - _perf_t0) / 1000, _perf_frames, _perf_worst, core - _perf_core])
		_perf_core = core
		_perf_frames = 0
		_perf_worst = 0.0
		_perf_sec = now


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _check(cond: bool, what: String) -> void:
	print("[wiiu-room] %s  %s" % ["PASS" if cond else "FAIL", what])
	if not cond:
		_fail = true


func _stage() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.18, 0.19, 0.22)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.85, 0.85, 0.9)
	add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 25, 0)
	add_child(light)
	var floor_body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6, 0.1, 6)
	col.shape = box
	floor_body.add_child(col)
	floor_body.position = Vector3(0, -0.05, 0)
	add_child(floor_body)

	_tv = TV_SCENE.instantiate() as RetroTV
	_tv.tv_model = "retroxr_crt"
	_tv.freeze = true
	add_child(_tv)
	_tv.global_position = Vector3(0.0, 0.0, -0.6)
	_tv.add_to_group("spawned")

	_sys = SYSTEM_SCENE.instantiate() as RetroSystem
	_sys.systemid = "wiiu"
	_sys.core_name = "cemu"
	_sys.freeze = true
	add_child(_sys)
	_sys.global_position = Vector3(-0.45, 0.0, -0.2)
	_sys.add_to_group("spawned")

	_pad = GAMEPAD_SCENE.instantiate() as WiiUGamePad
	_pad.freeze = true
	add_child(_pad)
	_pad.global_position = Vector3(0.32, 0.36, 0.3)
	# Tipped up toward the camera, as it is held.
	_pad.rotation_degrees = Vector3(55, -15, 0)
	_pad.add_to_group("spawned")

	var pro := PRO_SCENE.instantiate() as Node3D
	pro.set("freeze", true)
	add_child(pro)
	pro.global_position = Vector3(-0.45, 0.06, 0.15)

	var lead := AV_SCENE.instantiate() as Node3D
	add_child(lead)
	lead.global_position = Vector3(-0.2, 0.1, -0.4)
	await _frames(30)
	var multi := _sys.find_child("AvMultiOut", true, false) as XRToolsSnapZone
	_check(multi != null, "the Wii U has an AV MULTI OUT")
	if multi != null:
		multi.pick_up_object(lead.get_node("PlugA0"))
	(_tv.find_child("CompositePort", true, false) as XRToolsSnapZone).pick_up_object(lead.get_node("PlugB0"))
	(_tv.find_child("AudioLIn", true, false) as XRToolsSnapZone).pick_up_object(lead.get_node("PlugB1"))
	(_tv.find_child("AudioRIn", true, false) as XRToolsSnapZone).pick_up_object(lead.get_node("PlugB2"))
	await _frames(30)

	# SYNC on the console, then on the GamePad and the Pro Controller.
	var link := _sys.get_wii_link()
	if _pair:
		link.open_pairing()
		_pad._on_sync_pressed()
		link.open_pairing()
		pro.call("_on_sync_pressed")
		_check(_pad.get_port_index() == 0, "the GamePad paired on port 0")
		_check(int(pro.call("get_port_index")) == 1, "the Pro Controller paired on port 1")
	else:
		print("[wiiu-room] --nopair: GamePad and Pro Controller left unpaired")

	_cam = Camera3D.new()
	_cam.fov = 50.0
	_cam.near = 0.01
	add_child(_cam)
	_cam.global_position = Vector3(0.05, 0.6, 1.05)
	_cam.look_at(Vector3(0.0, 0.28, -0.3))


func _boot() -> void:
	var disc := DISC_SCENE.instantiate() as Node3D
	disc.set("systemid", "wiiu")
	disc.set("rom_path", _rom)
	disc.set("game_label", _rom.get_base_dir().get_file())
	add_child(disc)
	disc.global_position = _sys.global_position + Vector3(0, 0.3, 0.3)
	await _frames(10)
	(_sys.get_node("CartridgeSlot") as XRToolsSnapZone).pick_up_object(disc)
	await _frames(60)
	(_sys.get_node("PowerButton") as VRButton).button_pressed.emit()
	for o in LoadingOverlay.owners():
		LoadingOverlay.end(o)
	# Until the GamePad has its own window of the frame (Cemu's views).
	var t0 := Time.get_ticks_msec()
	var rect: Variant = null
	while Time.get_ticks_msec() - t0 < 90000:
		await _frames(10)
		var model := _sys.get_model() as RetroSystemModelWiiU
		rect = model.gamepad_rect() if model != null else null
		if rect is Rect2:
			break
	_check(rect is Rect2, "the GamePad has its view of the frame (%s)" % str(rect))
	for o in LoadingOverlay.owners():
		LoadingOverlay.end(o)
	await _frames(240)
	var mat := _pad.get_node("Model/Screen").get("surface_material_override/0") as ShaderMaterial
	_check(mat != null and mat.get_shader_parameter("source_tex") != null,
		"the GamePad's glass shows the console's picture")
	if mat != null:
		var r: Vector4 = mat.get_shader_parameter("source_rect")
		_check(r.x > 0.5, "and the GamePad's window of it, not the TV's (%s)" % str(r))


## A finger on the middle of the glass for a moment: Nintendo Land's title says
## "Touch the Wii U GamePad to start".
func _tap_gamepad() -> void:
	var touch: TVTouchSurface = _pad._touch
	_check(touch != null, "the GamePad's glass is a touch screen")
	if touch == null:
		return
	# Five touches two seconds apart, a second each: the curtain is still rising
	# when it is first seen, before the prompt takes a touch.
	for n in 5:
		print("[wiiu-room] touching the GamePad at its middle (%d)" % (n + 1))
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 1000:
			touch._send_touch_local(Vector2.ZERO, true)
			await _frames(1)
		touch._send_touch_local(Vector2.ZERO, false)
		await _wait_seconds(2.0)


func _wait_seconds(sec: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(sec * 1000.0):
		await _frames(10)


## The TV's view of the core's frame, small, for comparing.
func _tv_image() -> Image:
	var frame: Texture2D = _sys.get_video_texture()
	if frame == null:
		return null
	var img := frame.get_image()
	var r: Variant = _sys.video_window(0)
	if r is Rect2:
		var rr: Rect2 = r
		img = img.get_region(Rect2i(int(rr.position.x * img.get_width()), int(rr.position.y * img.get_height()),
			int(rr.size.x * img.get_width()), int(rr.size.y * img.get_height())))
	img.resize(64, 36, Image.INTERPOLATE_BILINEAR)
	return img


## The GamePad's view of the core's frame, small.
func _pad_image() -> Image:
	var frame: Texture2D = _sys.get_video_texture()
	var model := _sys.get_model() as RetroSystemModelWiiU
	var r: Variant = model.gamepad_rect() if model != null else null
	if frame == null or not (r is Rect2):
		return null
	var img := frame.get_image()
	var rr: Rect2 = r
	img = img.get_region(Rect2i(int(rr.position.x * img.get_width()), int(rr.position.y * img.get_height()),
		int(rr.size.x * img.get_width()), int(rr.size.y * img.get_height())))
	img.resize(64, 36, Image.INTERPOLATE_BILINEAR)
	return img


## The share of the middle of an image (the box's place) that is the box's gold.
func _gold_share(img: Image) -> float:
	if img == null:
		return 0.0
	var n := 0
	var total := 0
	for y in range(int(img.get_height() * 0.25), int(img.get_height() * 0.75)):
		for x in range(int(img.get_width() * 0.35), int(img.get_width() * 0.65)):
			var c := img.get_pixel(x, y)
			total += 1
			if c.r > 0.55 and c.g > 0.45 and c.b < 0.35 and c.r > c.b * 2.0:
				n += 1
	return float(n) / float(maxi(total, 1))


## The share of the band a prompt panel fills along the bottom of the TV that is
## the panel's pale grey.
func _prompt_share(img: Image) -> float:
	if img == null:
		return 0.0
	var n := 0
	var total := 0
	for y in range(int(img.get_height() * 0.78), int(img.get_height() * 0.92)):
		for x in range(int(img.get_width() * 0.12), int(img.get_width() * 0.88)):
			var c := img.get_pixel(x, y)
			total += 1
			var lo := minf(c.r, minf(c.g, c.b))
			var hi := maxf(c.r, maxf(c.g, c.b))
			if lo > 0.6 and hi - lo < 0.25:
				n += 1
	return float(n) / float(maxi(total, 1))


## The share of an image brighter than near-black.
func _lit_share(img: Image) -> float:
	if img == null:
		return 0.0
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.r + c.g + c.b > 0.45:
				n += 1
	return float(n) / float(img.get_width() * img.get_height())


func _set_save_aside() -> void:
	_save_dir = CoreDownloadManager.default_core_root().path_join("save/cemu/Cemu/mlc01/usr/save/00050000/10102000")
	var aside := _save_dir + ".probe_aside"
	if DirAccess.dir_exists_absolute(aside):
		print("[wiiu-room] FAIL: %s is already there from a run that did not finish; put it back by hand" % aside)
		get_tree().quit(1)
		return
	if DirAccess.dir_exists_absolute(_save_dir):
		var err := DirAccess.rename_absolute(_save_dir, aside)
		print("[wiiu-room] save set aside (%s): %s" % [error_string(err), aside])


## Power off first, so the core writes nothing back after the save returns.
func _lib_stop_then_restore() -> void:
	if is_instance_valid(_sys) and _sys.is_powered_on:
		_sys.power_off()


func _put_save_back() -> void:
	var aside := _save_dir + ".probe_aside"
	if not DirAccess.dir_exists_absolute(aside):
		return
	if DirAccess.dir_exists_absolute(_save_dir):
		OS.move_to_trash(ProjectSettings.globalize_path(_save_dir))
	var err := DirAccess.rename_absolute(aside, _save_dir)
	print("[wiiu-room] save put back (%s)" % error_string(err))


## The share of the picture that is the curtain's red.
func _red_share(img: Image) -> float:
	if img == null:
		return 0.0
	var n := 0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.r > 0.4 and c.r > c.g * 1.5 and c.r > c.b * 1.2:
				n += 1
	return float(n) / float(img.get_width() * img.get_height())


## Mean absolute difference of two small images, 0..1.
func _difference(a: Image, b: Image) -> float:
	if a == null or b == null:
		return 0.0
	var sum := 0.0
	for y in a.get_height():
		for x in a.get_width():
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			sum += (absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)) / 3.0
	return sum / float(a.get_width() * a.get_height())


func _shoot(tag: String) -> void:
	_cam.make_current()
	await _frames(4)
	await RenderingServer.frame_post_draw
	var path := _out.path_join("wiiu_room_%s.png" % tag)
	get_viewport().get_texture().get_image().save_png(path)
	print("[wiiu-room] wrote %s" % path)
	var frame: Texture2D = _sys.get_video_texture()
	if frame != null:
		var fp := _out.path_join("wiiu_frame_%s.png" % tag)
		frame.get_image().save_png(fp)
		print("[wiiu-room] wrote %s" % fp)
