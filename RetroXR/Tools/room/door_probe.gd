## A VRDoor on its own in a wall, rendered, for judging how a door looks: the plain
## knob or crash-bar leaf a room or mod gets from properties alone.
##   "$godot" --path RetroXR --resolution 960x720 --position 20,20 \
##       res://Tools/room/door_probe.tscn -- --opener=bar --deg=35 [--out=res://probe_out/door.png]
## Windowed, never --headless (the dummy renderer saves a blank image). The camera is
## on the PUSH side for a bar (the door swings away from it), on the pull side for a knob.
extends Node3D

var _out := "res://probe_out/door.png"


func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("[probe] TIMEOUT"); get_tree().quit(1))
	var opener := "bar"
	var deg := 0.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--opener="):
			opener = arg.get_slice("=", 1)
		elif arg.begins_with("--deg="):
			deg = float(arg.get_slice("=", 1))
		elif arg.begins_with("--out="):
			_out = arg.get_slice("=", 1)
	_build_room()
	var d := VRDoor.new()
	d.log_name = "probe"
	d.opener = VRDoor.Opener.PUSH_BAR if opener == "bar" else VRDoor.Opener.KNOB
	# Toward -Z: away from the camera, which stands at +Z.
	d.swing = VRDoor.Swing.TOWARD_NEGATIVE_Z if opener == "bar" else VRDoor.Swing.TOWARD_POSITIVE_Z
	d.hinge_side = VRDoor.HingeSide.NEGATIVE_X
	d.width = 0.92
	d.height = 2.08
	d.thickness = 0.045
	add_child(d)
	await get_tree().process_frame
	d.apply_state(deg, deg <= 0.0)
	print("[probe] door %s at %.1f deg, latched %s, bar at %s" % [opener, d.get_angle_deg(),
		d.is_latched(), str(d.to_local(d.bar.global_position)) if d.bar != null else "-"])
	# The boot's loading panel covers the main viewport until something says the room is ready.
	LoadingOverlay.suspend()
	for i in 8:
		await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(_out.get_base_dir())
	get_viewport().get_texture().get_image().save_png(_out)
	print("[probe] saved %s" % _out)
	get_tree().quit(0)


func _build_room() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.02, 0.02, 0.025)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.5, 0.55)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 30, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var lamp := OmniLight3D.new()
	lamp.position = Vector3(0.6, 2.3, 1.6)
	lamp.omni_range = 6.0
	lamp.light_energy = 1.5
	add_child(lamp)
	var wall := StandardMaterial3D.new()
	wall.albedo_color = Color(0.55, 0.52, 0.6)
	# Wall at z 0, 15 cm thick behind the door's plane, a 0.96 x 2.10 opening.
	for b: Array in [[Vector3(-1.48, 1.3, -0.075), Vector3(2.0, 2.6, 0.15)],
			[Vector3(1.48, 1.3, -0.075), Vector3(2.0, 2.6, 0.15)],
			[Vector3(0, 2.35, -0.075), Vector3(0.96, 0.5, 0.15)]]:
		var mi := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = b[1]
		box.material = wall
		mi.mesh = box
		mi.position = b[0]
		add_child(mi)
	var floor_mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(6, 6)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.3, 0.28, 0.27)
	plane.material = fm
	floor_mi.mesh = plane
	add_child(floor_mi)
	var cam := Camera3D.new()
	cam.position = Vector3(1.1, 1.55, 2.1)
	cam.fov = 55.0
	add_child(cam)
	cam.look_at(Vector3(0.0, 1.0, -0.2), Vector3.UP)
	cam.current = true
