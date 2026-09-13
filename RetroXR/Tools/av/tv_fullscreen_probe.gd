## Windowed probe: records the fullscreen lerp on a TV, a DS and a Game Boy to
## PNG frames under res://probe_out/. Not headless — the dummy renderer draws nothing.
extends Node

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const TV_SCENE := preload("res://Scenes/Objects/tv.tscn")

var _fs: TvFullscreen
var _camera: Camera3D
var _frame := 0


func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(func() -> void: get_tree().quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://probe_out"))
	LoadingOverlay.suspend()
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.18, 0.2, 0.24)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.8
	add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 30, 0)
	add_child(light)
	_camera = Camera3D.new()
	_camera.position = Vector3(0, 1.4, 1.6)
	add_child(_camera)
	_camera.current = true
	var loco := LocomotionManager.new()
	add_child(loco)
	_fs = TvFullscreen.new()
	add_child(_fs)
	_fs.configure(_camera, null, null, null, loco)

	var tv := TV_SCENE.instantiate() as RetroTV
	tv.position = Vector3(-0.3, 1.3, 0)
	tv.freeze = true
	add_child(tv)
	var ds := SYSTEM_SCENE.instantiate() as RetroSystem
	ds.systemid = "nds"
	ds.position = Vector3(0.35, 1.25, 0.4)
	ds.rotation_degrees = Vector3(-35, -15, 0)
	ds.freeze = true
	add_child(ds)
	for i in 40:
		await get_tree().process_frame
	if not tv.is_on():
		tv.remote_power_toggle()
	for i in 10:
		await get_tree().process_frame
	await _record(tv, "tv")
	# No core runs here, so the DS's panels are fed a stand-in composite: top
	# half orange, bottom half teal, which is what proves the crop and the stack.
	await _record(ds, "ds", _composite())
	print("[probe] frames=%d" % _frame)
	get_tree().quit(0)


func _composite() -> Texture2D:
	var img := Image.create(256, 384, false, Image.FORMAT_RGB8)
	for y in 384:
		for x in 256:
			var top := y < 192
			var checker := ((x / 16) + (y / 16)) % 2 == 0
			var c := Color(0.95, 0.55, 0.15) if top else Color(0.15, 0.7, 0.65)
			img.set_pixel(x, y, c.darkened(0.25) if checker else c)
	return ImageTexture.create_from_image(img)


func _record(device: Node3D, tag: String, stand_in: Texture2D = null) -> void:
	await _shoot(6)
	_fs.open(device)
	if stand_in != null:
		for panel: Dictionary in _fs._panels:
			panel["texture_fn"] = func() -> Texture2D: return stand_in
	await _shoot(30)
	_fs.close()
	await _shoot(30)
	print("[probe] %s done" % tag)


func _shoot(n: int) -> void:
	for i in n:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png("res://probe_out/fs_%04d.png" % _frame)
		_frame += 1
		await get_tree().process_frame
