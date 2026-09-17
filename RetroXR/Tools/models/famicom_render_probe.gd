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

	# A surface to stand on, and it is not staging: both cords are hardwired, and
	# where their spare lies is decided by whatever the console is standing on.
	# Rendered in a void they hang in it, which is not a state any room produces.
	_add_desk()

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
	# Long enough for both coils to lie down. Full sleep takes about 800 ticks
	# from a fresh lay, so the number to read below is the residual speed, not
	# the sleep flag: a settled cord is well under the 2.5 mm/s a rope sleeps at,
	# and a cord whose turns are self-colliding sits an order above it for ever.
	for i in range(480):
		await get_tree().physics_frame
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
	# Each cord leaves its pad over the OUTER wall of the well it lies in, so the
	# lead runs back along that side to the grommet at its own rear corner rather
	# than inboard across the cartridge deck. A sign, not a look.
	for i in pads.size():
		var pad: Node3D = pads[i]
		var boss: Node3D = pad.get_node("CableAttachPoint")
		var outward: float = signf(boss.global_position.x - pad.global_position.x)
		var side: float = signf(pad.global_position.x - sys.global_position.x)
		print("[fcrender] pad %d cord leaves outboard: %s" % [i + 1, outward == side])
	for i in pads.size():
		var rope: VerletRope = pads[i].cable_instance().get_node("VerletRope")
		var n: int = rope.point_count()
		var metrics: Dictionary = rope.get_sleep_metrics()
		print("[fcrender] cord %d: %d points, ends at %s, %.4f m/s (sleeps under 0.0025)"
			% [i + 1, n, rope.point_position(n - 1), float(metrics.get("max_velocity", 0.0))])
	# The wells the pads came out of, which are also what puts one back.
	for i in pads.size():
		var well := sys.get_node_or_null("ControllerWell%d" % (i + 1)) as XRToolsSnapZone
		var held: Variant = well.picked_up_object if well != null else null
		print("[fcrender] well %d holds its own pad: %s, offers it the other: %s"
			% [i + 1, is_instance_valid(held) and held == pads[i],
				well != null and well.can_preview(pads[1 - i])])

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
	# High over the back quarter: the one framing that carries both leads whole,
	# from the wells they lie in to the grommets they end at.
	var cords := sys.global_position - b.z * 0.09
	await _shot(sv, cam, cords - b.z * 0.34 + up * 0.40 + b.x * 0.26, cords, up,
		"famicom_cords.png")
	get_tree().quit(0)


## A matte desk under the machine, big enough for both cords' spare to lie on.
func _add_desk() -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, 0.06, 0.8)
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
