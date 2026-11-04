## Renders the DMG-07 4 Player Adapter on a desk with four Game Boys: player 1's
## captive lead in the first, DMG-04 leads from the other three into its sockets.
## Prints where each socket and plug landed, so the seat is checked by numbers as
## well as by eye.
##
##     "$godot" --path RetroXR --resolution 320x240 --position 20,20 \
##         res://Tools/models/dmg07_render_probe.tscn -- --out=<dir>
##
## Windowed: the headless renderer returns a blank image at the right size.
extends Node

var out_dir := ""


func _ready() -> void:
	out_dir = OS.get_user_data_dir()
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--out="):
			out_dir = str(arg).trim_prefix("--out=").replace("\\", "/")
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("[dmg07render] TIMEOUT")
		get_tree().quit(1))
	get_tree().current_scene = self
	_run()


func _run() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.30, 0.31, 0.34)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.52, 0.52, 0.55)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 25, 0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	add_child(sun)
	_add_desk()

	var adapter := (load("res://Scenes/Objects/peripherals/dmg07_adapter.tscn") as PackedScene).instantiate() as Dmg07Adapter
	adapter.auto_power = false
	add_child(adapter)
	adapter.global_position = Vector3(0, 0.0, 0)
	adapter.freeze = true
	# Four Game Boys round it, standing up as on a desk: player 1 behind (its lead
	# leaves the back), 2 left, 3 in front, 4 right.
	var spots := [Vector3(-0.05, 0.0, -0.32), Vector3(-0.34, 0.0, 0.06), Vector3(0.06, 0.0, 0.36), Vector3(0.34, 0.0, -0.06)]
	var gbs: Array = []
	for i in 4:
		var sys := (load("res://Scenes/Objects/system.tscn") as PackedScene).instantiate() as RetroSystem
		sys.systemid = "gb"
		sys.name = "GameBoy%d" % (i + 1)
		add_child(sys)
		sys.global_position = spots[i]
		sys.freeze = true
		gbs.append(sys)
	for i in range(10):
		await get_tree().physics_frame
	var leads: Array = []
	for i in 3:
		var l := (load("res://Scenes/Objects/cables/dmg_link_cable.tscn") as PackedScene).instantiate() as LinkCable
		add_child(l)
		leads.append(l)
	for i in range(6):
		await get_tree().physics_frame
	var ports: Array = gbs.map(func(g: Node) -> LinkPort: return _link_port(g))
	print("[dmg07render] Game Boy link sockets: %s" % str(ports.map(func(p: Variant) -> String: return str((p as Node).get_path()) if p != null else "none")))
	(ports[0] as LinkPort).pick_up_object(adapter.lead().get_node("PlugB0"))
	for i in 3:
		(ports[i + 1] as LinkPort).pick_up_object(leads[i].get_node("PlugA0"))
		adapter.sockets()[i].pick_up_object(leads[i].get_node("PlugB0"))
	for i in range(240):
		await get_tree().physics_frame
	for i in 3:
		var s := adapter.sockets()[i]
		var plug := leads[i].get_node("PlugB0") as Node3D
		print("[dmg07render] %s at %s faces %s; plug at %s, seated %s" % [s.name, s.global_position, s.global_basis.z,
			plug.global_position, s.picked_up_object == plug])
	print("[dmg07render] player 1's plug in Game Boy 1: %s; adapter wants power: %s" % [
		(ports[0] as LinkPort).picked_up_object == adapter.lead().get_node("PlugB0"), adapter.wants_power()])

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
	var t := adapter.global_position
	await _shot(sv, cam, t + Vector3(0.0, 0.85, 0.75), t + Vector3(0.0, 0.0, 0.0), "dmg07_overview.png")
	await _shot(sv, cam, t + Vector3(-0.13, 0.12, 0.17), t + Vector3(0.0, 0.012, 0.0), "dmg07_close.png")
	await _shot(sv, cam, t + Vector3(0.11, 0.10, -0.17), t + Vector3(0.0, 0.012, 0.0), "dmg07_back.png")
	get_tree().quit(0)


## A machine's link socket, whatever its model calls it.
func _link_port(n: Node) -> LinkPort:
	if n is LinkPort:
		return n as LinkPort
	for c in n.get_children():
		var found := _link_port(c)
		if found != null:
			return found
	return null


func _add_desk() -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 0.06, 1.6)
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
	print("[dmg07render] wrote %s" % path)
