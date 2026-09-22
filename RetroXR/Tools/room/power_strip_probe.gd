extends Node3D

## Windowed: the power strip with its own plug in Socket3, the cord settled.
## Writes user://power_strip_<view>.png. Run with --resolution 960x540.

var _vp: SubViewport


## Everything goes in a SubViewport with its own world: the app's autoloads put their
## own camera and panels in the main one.
func add_child3(n: Node) -> void:
	_vp.add_child(n)


func _ready() -> void:
	get_tree().create_timer(20.0).timeout.connect(func() -> void: get_tree().quit(1))
	_vp = SubViewport.new()
	_vp.size = Vector2i(960, 540)
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.msaa_3d = Viewport.MSAA_4X
	add_child(_vp)
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 0.1, 4)
	cs.shape = box
	cs.position.y = -0.05
	floor_body.add_child(cs)
	var fm := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(4, 4)
	fm.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.33, 0.24)
	fm.material_override = mat
	floor_body.add_child(fm)
	add_child3(floor_body)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.shadow_enabled = true
	add_child3(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.2, 0.2, 0.22)
	add_child3(env)

	var strip := preload("res://Scenes/Objects/appliances/power_strip.tscn").instantiate() as PowerStrip
	add_child3(strip)
	strip.add_to_group("spawned")
	await get_tree().physics_frame
	await get_tree().physics_frame
	strip.sockets()[2].pick_up_object(strip.wall_plug)
	for i in 120:
		await get_tree().physics_frame
	var cam := Camera3D.new()
	add_child3(cam)
	cam.current = true
	for view: Array in [["overview", Vector3(0.05, 0.55, 0.55), Vector3(0.05, 0.02, 0)],
			["close", Vector3(-0.06, 0.16, 0.16), Vector3(-0.03, 0.03, 0)]]:
		cam.look_at_from_position(view[1], view[2])
		for i in 3:
			await RenderingServer.frame_post_draw
		_vp.get_texture().get_image().save_png("user://power_strip_%s.png" % view[0])
		print("[probe] saved ", view[0])
	var b := strip.get_node("Body") as Node3D
	print("[probe] body y=%.3f plug seated=%s" % [b.global_position.y,
		PowerCord.socket_holding(strip.wall_plug) != null])
	get_tree().quit(0)
