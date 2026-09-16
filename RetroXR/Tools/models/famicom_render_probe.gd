## Renders the HVC-001 with Controller I and II, and prints the facings so they
## are checked by numbers rather than by eye.
##
##     "$godot" --path RetroXR --resolution 320x240 --position 20,20 \
##         res://Tools/models/famicom_render_probe.tscn -- --out=<dir>
##
## Windowed: the headless renderer returns a blank image at the right size, which
## is the one failure a size check cannot see.
##
## It spawns NO pads of its own. Both arrive with the console -- they are moulded
## onto cords out of the back -- so a probe that made its own would be proving the
## wrong thing and would put four pads in the room.
extends Node

var out_dir := ""


func _ready() -> void:
	out_dir = OS.get_user_data_dir()
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--out="):
			out_dir = str(arg).trim_prefix("--out=").replace("\\", "/")
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		print("[fcrender] TIMEOUT")
		get_tree().quit(1))
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
	sun.rotation_degrees = Vector3(-52, 28, 0)
	sun.light_energy = 1.5
	add_child(sun)

	var sys := preload("res://Scenes/Objects/system.tscn").instantiate() as RetroSystem
	sys.systemid = "famicom"
	add_child(sys)
	sys.freeze = true
	for i in range(8):
		await get_tree().process_frame

	# The pads the CONSOLE built. Give the cords a moment: each is created one
	# deferred call after its pad, and the seat is pending until then.
	for i in range(30):
		await get_tree().physics_frame
	var pads: Array = sys.captive_controllers()
	if pads.size() < 2:
		print("[fcrender] FAIL the console built %d captive pad(s), wanted 2" % pads.size())
		get_tree().quit(1)
		return
	var one: Node3D = pads[0]
	var two: Node3D = pads[1]
	one.freeze = true
	two.freeze = true
	var b := sys.global_transform.basis.orthonormalized()

	print("[fcrender] console at %s" % sys.global_position)
	print("[fcrender] Controller I  at %s, port %d" % [one.global_position, one.get_port_index()])
	print("[fcrender] Controller II at %s, port %d" % [two.global_position, two.get_port_index()])
	print("[fcrender] II hears from the grille: %s (pad origin %s)"
		% [two.microphone_position(), two.global_position])
	# Numbers rather than a look: the pads must be the two the console owns, in
	# the hardware's order, and their ports must be shut.
	print("[fcrender] II is the microphone pad: %s" % (two is FamicomControllerII))
	print("[fcrender] I is not: %s" % (not (one is FamicomControllerII)))
	print("[fcrender] neither is saved as a spawned object: %s"
		% (not one.is_in_group("spawned") and not two.is_in_group("spawned")))

	var sv := SubViewport.new()
	sv.size = Vector2i(1400, 900)
	sv.own_world_3d = false
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sv)
	var cam := Camera3D.new()
	cam.fov = 38.0
	sv.add_child(cam)

	for o in LoadingOverlay.owners():
		LoadingOverlay.end(o)
	for i in range(30):
		await get_tree().process_frame

	var up := b.y
	var mid := sys.global_position + b.y * 0.03
	await _shot(sv, cam, mid + b.z * 0.44 + up * 0.30 - b.x * 0.16, mid, up, "famicom_front.png")
	await _shot(sv, cam, mid + b.y * 0.52 + b.z * 0.10, mid, -b.z, "famicom_top.png")
	# The rear, which is the whole of this machine's panel: AC ADAPTER, TV/GAME,
	# CH1/CH2, RF SWITCH, and a cord grommet at each corner.
	var rear := sys.global_position + b.y * 0.022
	await _shot(sv, cam, rear - b.z * 0.30 + up * 0.13, rear, up, "famicom_rear.png")
	var pad_mid := two.global_position + b.y * 0.01
	await _shot(sv, cam, pad_mid + b.y * 0.17 + b.z * 0.09 + b.x * 0.05, pad_mid, -b.z,
		"famicom_controller_ii.png")
	get_tree().quit(0)


func _shot(sv: SubViewport, cam: Camera3D, eye: Vector3, target: Vector3, up: Vector3,
		file: String) -> void:
	cam.look_at_from_position(eye, target, up)
	cam.current = true
	for i in range(8):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	var path := out_dir.path_join(file)
	# FORMAT_RGB8 first: the frame carries an alpha channel nothing fills, and a
	# straight save writes a picture every viewer paints as a blank rectangle.
	var img := sv.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png(path)
	print("[fcrender] wrote %s" % path)
