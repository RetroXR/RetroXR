## Renders the NES Four Score and the Famicom's 4 Players Adaptor plugged in, pads
## in their sockets, and prints where the parts landed so the seat is checked by
## numbers as well as by eye.
##
##     "$godot" --path RetroXR --resolution 320x240 --position 20,20 \
##         res://Tools/models/four_player_render_probe.tscn -- --out=<dir>
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
		print("[fourrender] TIMEOUT")
		get_tree().quit(1))
	get_tree().current_scene = self
	_run()


func _spawn(scene: String, at: Vector3, yaw := 0.0) -> Node3D:
	var obj := (load(scene) as PackedScene).instantiate() as Node3D
	add_child(obj)
	obj.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), at)
	return obj


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

	var nes := preload("res://Scenes/Objects/system.tscn").instantiate() as RetroSystem
	nes.systemid = "nes"
	add_child(nes)
	nes.global_position = Vector3(-0.32, 0.0, -0.05)
	nes.freeze = true
	var fc := preload("res://Scenes/Objects/system.tscn").instantiate() as RetroSystem
	fc.systemid = "famicom"
	add_child(fc)
	fc.global_position = Vector3(0.36, 0.0, -0.05)
	fc.freeze = true
	for i in range(10):
		await get_tree().process_frame

	var fs := _spawn("res://Scenes/Objects/controllers/nes/nes_four_score.tscn", Vector3(-0.34, 0.03, 0.24)) as NesFourScore
	var hori := _spawn("res://Scenes/Objects/controllers/famicom/famicom_four_players_adaptor.tscn",
		Vector3(0.36, 0.03, 0.24)) as FamicomFourPlayersAdaptor
	var pads: Array = []
	for i in 4:
		pads.append(_spawn("res://Scenes/Objects/controllers/nes/nes_controller.tscn",
			Vector3(-0.58 + 0.16 * i, 0.03, 0.46)))
	var gpads: Array = []
	for i in 2:
		gpads.append(_spawn("res://Scenes/Objects/controllers/retro_controller.tscn",
			Vector3(0.24 + 0.24 * i, 0.04, 0.48)))
	for i in range(6):
		await get_tree().physics_frame

	nes.restore_controller_plug(0, fs.get_plug())
	fc.restore_controller_plug(RetroSystem.ACCESSORY_SLOT, hori.get_plug())
	for i in 4:
		fs.restore_socket(i, pads[i])
	for i in 2:
		hori.restore_socket(i, gpads[i])
	for i in range(240):
		await get_tree().physics_frame

	var zones: Array = nes.controller_ports().zones
	var plug := fs.get_plug()
	print("[fourrender] Four Score block in NES sockets %s" % str(nes.cabinet_ports_of_plug(plug)))
	for k in 2:
		var pm := plug.get_node_or_null("PlugModel" if k == 0 else "PlugModel2") as Node3D
		if pm != null:
			print("[fourrender] block plug %d at %s, NES port %d zone at %s" % [k + 1,
				pm.global_position, k + 1, (zones[k] as Node3D).global_position])
	print("[fourrender] NES pads on ports %s" % str(pads.map(func(p: Node) -> int: return int(p.call("get_port_index")))))
	print("[fourrender] Famicom connector holds the adaptor: %s; its pads on ports %s" % [
		fc.controller_ports().accessory_plug == hori.get_plug(),
		str(gpads.map(func(p: Node) -> int: return int(p.call("get_port_index"))))])
	var top := fs.get_node("Top") as Node3D
	print("[fourrender] Four Score top normal %s (tilts toward +Z, the front)" % top.global_basis.y)

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

	await _shot(sv, cam, Vector3(0.0, 0.62, 0.95), Vector3(0.0, 0.02, 0.12), "four_overview.png")
	var fsp := fs.global_position
	await _shot(sv, cam, fsp + Vector3(-0.06, 0.24, 0.20), fsp + Vector3(0, 0.02, 0), "four_score_top.png")
	var nes_ports := (zones[0] as Node3D).global_position.lerp((zones[1] as Node3D).global_position, 0.5)
	await _shot(sv, cam, nes_ports + Vector3(0.10, 0.07, 0.17), nes_ports, "four_score_block.png")
	var hp := hori.global_position
	await _shot(sv, cam, hp + Vector3(0.05, 0.22, 0.20), hp + Vector3(0, 0.015, 0.0), "hori_top.png")
	var fcz := fc.controller_ports().accessory_zone.global_position
	await _shot(sv, cam, fcz + Vector3(-0.12, 0.08, 0.16), fcz, "hori_plug.png")
	# The switches thrown: the Four Score to 2 with TURBO A on, the Hori to 2. Each
	# knob's place along its slot (the Four Score's +Z is the front; the Hori's +X
	# its right), before and after, so a knob that does not move is a number.
	var knobs := {"2/4": fs.get_node("Top/ModeSwitchKnob"), "TURBO A cap": fs.get_node("Top/TurboA/ButtonMesh"),
		"Hori 2/4": hori.get_node("ModeSwitchKnob")}
	var before := {}
	for k: String in knobs:
		before[k] = (knobs[k] as Node3D).position
	fs.set_mode(FourPlayerAdapter.MODE_2P)
	fs.set_turbo("a", true)
	hori.set_mode(FourPlayerAdapter.MODE_2P)
	for k: String in knobs:
		print("[fourrender] %s knob %s -> %s" % [k, before[k], (knobs[k] as Node3D).position])
	print("[fourrender] at 2: NES pads on ports %s" % str(pads.map(func(p: Node) -> int: return int(p.call("get_port_index")))))
	await _shot(sv, cam, fsp + Vector3(-0.06, 0.24, 0.20), fsp + Vector3(0, 0.02, 0), "four_score_top_2p.png")
	get_tree().quit(0)


func _add_desk() -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.6, 0.06, 1.1)
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
	body.global_position = Vector3(0, -0.03, 0.15)


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
	print("[fourrender] wrote %s" % path)
