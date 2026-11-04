## Renders Nintendo's Super Scope, its sight on each clip, and its receiver on top
## of a television with its plug in a Super NES's port 2, and prints whether the
## scope, held in front of the set and aimed at it, pairs and links -- so the
## build is checked by numbers as well as by eye.
##
##     "$godot" --path RetroXR --resolution 320x240 --position 20,20 \
##         res://Tools/models/super_scope_render_probe.tscn -- --out=<dir>
##
## Windowed: the headless renderer returns a blank image at the right size.
extends Node

const TV_SCENE := preload("res://Scenes/Objects/tv.tscn")

var out_dir := ""


func _ready() -> void:
	out_dir = OS.get_user_data_dir()
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--out="):
			out_dir = str(arg).trim_prefix("--out=").replace("\\", "/")
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("[scoperender] TIMEOUT")
		get_tree().quit(1))
	get_tree().current_scene = self
	_run()


func _spawn(scene: String, at: Vector3, basis := Basis.IDENTITY) -> Node3D:
	var obj := (load(scene) as PackedScene).instantiate() as Node3D
	add_child(obj)
	obj.global_transform = Transform3D(basis, at)
	if obj is RigidBody3D:
		(obj as RigidBody3D).freeze = true
	return obj


## The world box round every mesh under `n`.
func _bounds(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi: Node in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or not m.is_visible_in_tree():
			continue
		var box := m.global_transform * m.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out


func _run() -> void:
	AppPrefs.power_simulation = false
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.30, 0.31, 0.34)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.52, 0.52, 0.55)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	add_child(sun)
	_add_floor()

	var snes := preload("res://Scenes/Objects/system.tscn").instantiate() as RetroSystem
	snes.systemid = "snes"
	add_child(snes)
	snes.global_position = Vector3(0.0, 0.0, 0.3)
	snes.freeze = true
	var tv := TV_SCENE.instantiate() as RetroTV
	add_child(tv)
	# Its origin is its middle: stood on the floor.
	tv.global_position = Vector3(0.0, 0.2, -0.3)
	if tv is RigidBody3D:
		(tv as RigidBody3D).freeze = true
	for i in range(20):
		await get_tree().process_frame
	var tvbox := _bounds(tv)
	print("[scoperender] TV box %s" % tvbox)
	# The receiver on top of the set, its window (-Z) toward the player (+Z).
	var rx := _spawn("res://Scenes/Objects/peripherals/super_scope_receiver.tscn",
		Vector3(0.0, tvbox.end.y, tvbox.end.z - 0.05), Basis(Vector3.UP, PI)) as SuperScopeReceiver
	# The scope held 1.8 m in front of the set at eye height, aimed at the screen.
	var aim_at := tvbox.get_center()
	var scope_at := Vector3(0.15, 1.15, tvbox.end.z + 1.8)
	var scope := _spawn("res://Scenes/Objects/peripherals/super_scope.tscn", scope_at) as SuperScope
	scope.add_to_group("spawned")
	scope.look_at(aim_at, Vector3.UP)
	scope.set_power_switch(SuperScope.SWITCH_ON)
	for i in range(8):
		await get_tree().physics_frame
	snes.restore_controller_plug(1, rx.get_plug())
	for i in range(120):
		await get_tree().physics_frame
	print("[scoperender] receiver seated: %s, libretro port %d" % [rx.is_plugged_in(), rx.get_port_index()])
	print("[scoperender] scope paired: %s, link up: %s (window %s -> receiver %s)" % [
		scope.receiver() == rx, scope.link_up(), scope.window_point(), rx.lens_point()])
	print("[scoperender] sight on the %s" % scope.sight_side())

	var sv := SubViewport.new()
	sv.size = Vector2i(1400, 900)
	sv.own_world_3d = false
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sv)
	var cam := Camera3D.new()
	cam.fov = 40.0
	sv.add_child(cam)
	for o in LoadingOverlay.owners():
		LoadingOverlay.end(o)
	for i in range(20):
		await get_tree().process_frame

	await _shot(sv, cam, Vector3(1.6, 1.5, tvbox.end.z + 1.4), Vector3(0.0, 0.7, tvbox.end.z + 0.6), "scope_overview.png")
	var b := scope.global_basis
	var mid := scope.global_transform * Vector3(0, 0.07, 0.2)
	await _shot(sv, cam, mid + b * Vector3(-0.75, 0.10, 0.0), mid, "scope_left.png")
	await _shot(sv, cam, mid + b * Vector3(0.75, 0.10, 0.0), mid, "scope_right.png")
	var top := scope.global_transform * Vector3(0, 0.11, 0.25)
	await _shot(sv, cam, top + b * Vector3(-0.12, 0.22, 0.10), top, "scope_controls.png")
	var rxp := rx.global_position
	await _shot(sv, cam, rxp + Vector3(0.15, 0.12, 0.35), rxp, "scope_receiver.png")
	# The sight moved to the right clip.
	var sight := scope.get_sight()
	if sight != null:
		(scope.get_node("SightClipL") as XRToolsSnapZone).drop_object()
		await get_tree().physics_frame
		(scope.get_node("SightClipR") as XRToolsSnapZone).pick_up_object(sight)
		for i in range(4):
			await get_tree().physics_frame
		print("[scoperender] sight moved to the %s" % scope.sight_side())
		await _shot(sv, cam, mid + b * Vector3(0.75, 0.10, 0.0), mid, "scope_right_sight.png")
	# The muzzle end, its orange ring and the infrared window over it.
	var muzzle := scope.global_transform * Vector3(0, 0.09, -0.09)
	await _shot(sv, cam, muzzle + b * Vector3(0.12, 0.06, -0.22), muzzle, "scope_muzzle.png")
	get_tree().quit(0)


func _add_floor() -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8, 0.06, 8)
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = box.size
	mesh.mesh = cube
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.34, 0.26)
	mat.roughness = 0.9
	mesh.material_override = mat
	body.add_child(mesh)
	add_child(body)
	body.global_position = Vector3(0, -0.03, 0)


func _shot(sv: SubViewport, cam: Camera3D, eye: Vector3, target: Vector3, file: String) -> void:
	cam.look_at_from_position(eye, target, Vector3.UP)
	cam.current = true
	for i in range(8):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	var path := out_dir.path_join(file)
	var img := sv.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png(path)
	print("[scoperender] wrote %s" % path)
