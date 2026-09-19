## Renders the Voice Recognition Unit — the NUS-020 dongle, its 3.5 mm jack and
## the NUS-021 microphone — and prints the facings so they are settled by numbers
## rather than by a look at a render.
##
##     "$godot" --path RetroXR --resolution 900x700 --position 20,20 \
##         res://Tools/models/n64_vru_render_probe.tscn -- --out=<dir>
##
## Windowed: the headless renderer hands back a correctly sized blank. That matters
## more here than usual, because what this probe exists to show is a FLICKER, and a
## blank frame and a clean one look equally innocent.
extends Node

var out_dir := ""


func _ready() -> void:
	out_dir = OS.get_user_data_dir()
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--out="):
			out_dir = str(arg).trim_prefix("--out=").replace("\\", "/")
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		print("[vrurender] TIMEOUT")
		get_tree().quit(1))
	_run()


func _run() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.30, 0.31, 0.34)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.52, 0.52, 0.56)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 32, 0)
	sun.light_energy = 1.5
	add_child(sun)

	# A floor, or the microphone hangs a metre under the jack on its own cord and
	# every wide shot is a picture of cable.
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(4, 0.1, 4)
	floor_shape.shape = floor_box
	floor_body.add_child(floor_shape)
	var floor_mesh := MeshInstance3D.new()
	var floor_plane := BoxMesh.new()
	floor_plane.size = Vector3(4, 0.1, 4)
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.26, 0.26, 0.28)
	floor_mat.roughness = 0.9
	floor_mesh.mesh = floor_plane
	floor_mesh.material_override = floor_mat
	floor_body.add_child(floor_mesh)
	floor_body.position = Vector3(0, -0.05, 0)
	add_child(floor_body)

	var sys := preload("res://Scenes/Objects/system.tscn").instantiate() as RetroSystem
	sys.systemid = "n64"
	add_child(sys)
	sys.freeze = true
	var unit := preload(
		"res://Scenes/Objects/controllers/n64/n64_vru.tscn").instantiate() as N64Vru
	add_child(unit)
	unit.freeze = true
	for i in range(6):
		await get_tree().process_frame

	unit.restore_seat(sys, 3)
	# Clear of the console so the shell, its jack and both cords are all visible.
	unit.global_transform = Transform3D(Basis.IDENTITY,
		sys.global_position + Vector3(0.34, 0.001, 0.30))
	for i in range(120):
		await get_tree().physics_frame

	var mic := unit.get_mic()
	var plug := unit.get_plug()
	print("[vrurender] seated in socket %d, device 0x%X"
		% [unit.seated_port_index, unit.device_type])
	print("[vrurender] the microphone is in the jack: %s" % unit.mic_plugged())
	print("[vrurender] the machine hears from the microphone: %s"
		% sys.microphone_position().is_equal_approx(mic.global_position))
	print("[vrurender] unit basis x = %s  y = %s  z = %s" % [unit.global_transform.basis.x,
		unit.global_transform.basis.y, unit.global_transform.basis.z])
	print("[vrurender] mic basis x = %s  y = %s  z = %s" % [mic.global_transform.basis.x,
		mic.global_transform.basis.y, mic.global_transform.basis.z])
	print("[vrurender] plug at %s, unit at %s, mic at %s"
		% [plug.global_position, unit.global_position, mic.global_position])

	var sv := SubViewport.new()
	sv.size = Vector2i(1200, 900)
	sv.own_world_3d = false
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sv)
	var cam := Camera3D.new()
	cam.fov = 38.0
	sv.add_child(cam)

	# The loading overlay parks a panel in front of the first camera it sees.
	for o in LoadingOverlay.owners():
		LoadingOverlay.end(o)
	for i in range(30):
		await get_tree().process_frame

	var up := Vector3.UP
	# The microphone, nose on, which is the face that used to flicker.
	var head := mic.global_position + mic.global_transform.basis.z * -0.055
	await _shot(sv, cam, head + Vector3(0.0, 0.055, -0.16), mic.global_position, up,
		"vru_mic_nose.png")
	# And along it, so the head, collar and taper read as a microphone.
	await _shot(sv, cam, mic.global_position + Vector3(0.20, 0.09, 0.02),
		mic.global_position, up, "vru_mic_side.png")
	# The dongle's front, where the jack and the microphone's plug are.
	await _shot(sv, cam, unit.global_position + Vector3(0.02, 0.10, -0.24),
		unit.global_position, up, "vru_unit_front.png")
	# The whole set: console, plug in socket 4, dongle, both cords, microphone.
	var mid := (unit.global_position + mic.global_position) * 0.5
	var span := maxf(unit.global_position.distance_to(mic.global_position), 0.3)
	await _shot(sv, cam, mid + Vector3(0.1, 0.55, -1.0) * span, mid, up, "vru_set.png")
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
	sv.get_texture().get_image().save_png(path)
	print("[vrurender] wrote %s" % path)
