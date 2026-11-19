extends Node3D
## Windowed regression picture for a TV power cycle. All four coloured edges
## and the full MUTE banner must remain visible through the cabinet.
## Run with -- --no-mods --out=<directory>.

const TV := preload("res://Scenes/Objects/tv.tscn")
var _vp: SubViewport
var _cam: Camera3D
var _out := "user://tv_picture_fit_probe"


func _ready() -> void:
	get_tree().create_timer(120.0).timeout.connect(func(): print("[tvprobe] timeout"); get_tree().quit(1))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.2, 0.2, 0.21)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.55, 0.57)
	env.environment.ambient_light_energy = 0.9
	env.environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 2.0
	sun.shadow_enabled = true
	add_child(sun)
	var back := DirectionalLight3D.new()
	back.rotation_degrees = Vector3(-35, 160, 0)
	back.light_energy = 1.2
	add_child(back)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(6, 6)
	floor.mesh = pm
	floor.position.y = -0.165
	add_child(floor)

	var tv := TV.instantiate() as RetroTV
	tv.tv_model = "retroxr_crt"
	add_child(tv)
	tv.freeze = true
	_vp = SubViewport.new()
	_vp.size = Vector2i(1280, 720)
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_cam = Camera3D.new()
	_cam.fov = 40
	_vp.add_child(_cam)
	await _frames(8)

	var shell := tv.get_node("RetroXRCrt") as RetroXRCrtShell
	print("[tvprobe] tube ", tv.screen_mesh().transform, " bounds ", tv.screen_mesh().mesh.get_aabb())
	tv.set_power(false)
	await get_tree().create_timer(0.1).timeout
	tv.set_power(true)
	await get_tree().create_timer(1.0).timeout
	tv.set_process(false)
	var image := Image.create(640, 480, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.18, 0.18, 0.18))
	for x in range(0, 640, 40):
		image.fill_rect(Rect2i(x, 0, 2, 480), Color.WHITE)
	for y in range(0, 480, 40):
		image.fill_rect(Rect2i(0, y, 640, 2), Color.WHITE)
	image.fill_rect(Rect2i(0, 0, 12, 480), Color.RED)
	image.fill_rect(Rect2i(628, 0, 12, 480), Color.GREEN)
	image.fill_rect(Rect2i(0, 0, 640, 12), Color.BLUE)
	image.fill_rect(Rect2i(0, 468, 640, 12), Color.YELLOW)
	var mat := tv.display()._crt_screen_material()
	tv.display()._show_sampled(mat, ImageTexture.create_from_image(image))
	tv.crt_enabled = false
	mat.set_shader_parameter("crt_enabled", false)
	tv.show_osd("MUTE")
	_cam.look_at_from_position(Vector3(0.0, 0.023, 0.85), Vector3(0.0, 0.023, 0.0))
	await _shot("picture_cabinet")
	shell.hide()
	await _shot("picture_without_cabinet")
	get_tree().quit()


func _frames(k: int) -> void:
	for i in k:
		await get_tree().process_frame


func _shot(shot_name: String) -> void:
	await _frames(10)
	var path := _out.path_join(shot_name + ".png")
	_vp.get_texture().get_image().save_png(path)
	print("[tvprobe] wrote ", path)
