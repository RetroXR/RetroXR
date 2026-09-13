## Windowed probe: a real core on a real television, then the desktop fullscreen
## lerp over it. Wants a core and a ROM, so it is a probe and not a suite.
##
##   godot --path RetroXR --resolution 960x600 --position 20,20 \
##     res://Tools/av/tv_fullscreen_live_probe.tscn -- \
##     --core=fceumm "--rom=C:/Users/me/retroxr/roms/nes/game.nes"
##
## Never --headless: the dummy renderer hands back a correctly sized blank frame,
## so the size oracle passes while the recording shows nothing at all.
extends Node

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const TV_SCENE := preload("res://Scenes/Objects/tv.tscn")
const CABLE_SCENE := preload("res://Scenes/Objects/cables/composite_cable.tscn")

var _core := "fceumm"
var _rom := ""
var _systemid := "nes"
var _fs: TvFullscreen
var _camera: Camera3D
var _frame := 0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--core="):
			_core = arg.trim_prefix("--core=")
		elif arg.begins_with("--rom="):
			_rom = arg.trim_prefix("--rom=")
		elif arg.begins_with("--systemid="):
			_systemid = arg.trim_prefix("--systemid=")
	if _rom.is_empty() or not FileAccess.file_exists(_rom):
		print("[probe] SKIP: need --rom=<path to a real ROM>")
		get_tree().quit(1)
		return
	get_tree().create_timer(180.0).timeout.connect(func() -> void:
		print("[probe] TIMED OUT")
		get_tree().quit(1))
	LoadingOverlay.suspend()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://probe_out"))
	_build_room()
	await _run()


func _build_room() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.16, 0.17, 0.2)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.7
	add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 25, 0)
	add_child(light)
	_camera = Camera3D.new()
	_camera.position = Vector3(0, 1.32, 0.78)
	add_child(_camera)
	_camera.current = true
	var loco := LocomotionManager.new()
	add_child(loco)
	_fs = TvFullscreen.new()
	add_child(_fs)
	_fs.configure(_camera, null, null, null, loco)


func _run() -> void:
	var tv := TV_SCENE.instantiate() as RetroTV
	tv.position = Vector3(0, 1.3, 0)
	tv.freeze = true
	add_child(tv)
	var sys := SYSTEM_SCENE.instantiate() as RetroSystem
	sys.systemid = _systemid
	sys.position = Vector3(1.6, 1.0, 0)
	sys.freeze = true
	add_child(sys)
	await _wait(60)

	# The lead a player would plug in: video out of the machine, into the set's
	# first composite socket. The picture arrives because the cable says so.
	var cable := CABLE_SCENE.instantiate() as Node3D
	cable.position = Vector3(0.8, 1.0, 0.4)
	add_child(cable)
	await _wait(20)
	var from := sys.get_node_or_null("VideoOut") as RcaPort
	var to := tv.get_node_or_null("CompositePort") as RcaPort
	if from == null or to == null:
		print("[probe] FAIL: no VideoOut (%s) or CompositePort (%s)" % [from, to])
		get_tree().quit(1)
		return
	from.pick_up_object(cable.get_node("PlugA0") as RcaPlug)
	to.pick_up_object(cable.get_node("PlugB0") as RcaPlug)
	await _wait(30)

	if not tv.is_on():
		tv.remote_power_toggle()
	tv.set_source(RetroTV.Source.COMPOSITE_1)
	sys.rom_path = _rom
	sys.power_on()
	print("[probe] core=%s rom=%s" % [_core, _rom.get_file()])

	# A core comes up asynchronously — fceumm took 34 frames in an earlier probe
	# here — so wait for a picture rather than for a fixed count, and title
	# screens want seconds beyond that before there is motion worth filming.
	var waited := 0
	while tv.display().screen_texture() == null and waited < 600:
		await get_tree().process_frame
		waited += 1
	await _wait(240)
	print("[probe] picture after %d frames, %s" % [waited, tv.display().screen_texture()])

	await _shoot(24)
	_fs.open(tv)
	await _shoot(60)
	_fs.close()
	await _shoot(40)
	print("[probe] frames=%d" % _frame)
	sys.power_off() if sys.has_method("power_off") else null
	await _wait(30)
	get_tree().quit(0)


func _wait(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shoot(n: int) -> void:
	for i in n:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://probe_out/live_%04d.png" % _frame)
		_frame += 1
		await get_tree().process_frame
