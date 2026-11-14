## The RETRO XR seats and beds (ContractSeat) in the Mobile renderer: all nineteen laid out (the floor seats in a row of
## their own), the beds' drawers open, then the view from the player's own camera sitting on the overstuffed sofa's left
## cushion, lying on the captain's bed and sitting on the square floor cushion, each sat on through its own trigger's
## press. Writes stills.
##
##     "$godot" --path RetroXR --resolution 1280x720 --position 20,20 res://Tools/room/furniture_probe.tscn -- --out=DIR
##
## Windowed, never --headless: the dummy renderer draws nothing.
extends Node3D

var out_dir := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--out="):
			out_dir = String(a).trim_prefix("--out=")
	if out_dir.is_empty():
		out_dir = OS.get_user_data_dir().path_join("furniture_probe")
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		print("[probe] TIMED OUT")
		get_tree().quit(2))
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.32, 0.33, 0.36)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.62, 0.66)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50, -28, 0)
	key.light_energy = 1.5
	key.shadow_enabled = true
	add_child(key)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(16, 14)
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.55, 0.52, 0.48)
	plane.material = floor_mat
	floor_mesh.mesh = plane
	add_child(floor_mesh)
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(16, 0.2, 14)
	cs.shape = box
	cs.position = Vector3(0, -0.1, 0)
	floor_body.add_child(cs)
	add_child(floor_body)
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 50
	cam.current = true
	# Seats along the front, beds behind, every one facing the camera (+Z).
	var pieces := {}
	var seats := [["sofa_midcentury", -5.4], ["sofa_overstuffed", -3.0], ["sofa_futon", -0.6], ["stool_mission", 1.0],
		["stool_midcentury", 1.7], ["chair_desk", 2.6], ["chair_papasan", 3.8], ["pouf", 5.1]]
	for s: Array in seats:
		pieces[s[0]] = _spawn(s[0], Vector3(float(s[1]), 0.0, 1.6))
	var beds := [["bed_captain", -4.4], ["bed_brass", -2.2], ["bed_waterbed", 0.0], ["bed_wooden", 2.0], ["bed_racecar", 3.9]]
	for b: Array in beds:
		pieces[b[0]] = _spawn(b[0], Vector3(float(b[1]), 0.0, -1.6))
	# The floor seats in a row in front of the rest.
	var floor_seats := [["floor_cushion_square", -3.1], ["floor_cushion_round", -2.0], ["zabuton", -1.0],
		["flip_chair", 0.1], ["floor_pillow", 1.5], ["floor_rocker", 2.9]]
	for f: Array in floor_seats:
		pieces[f[0]] = _spawn(f[0], Vector3(float(f[1]), 0.0, 3.4))
	for i in 20:
		await get_tree().physics_frame
	# The boot's loading overlay (not a CanvasLayer) is still up for the first couple of seconds: wait it out.
	await get_tree().create_timer(3.0).timeout
	cam.look_at_from_position(Vector3(0.0, 3.6, 9.4), Vector3(0.0, 0.4, 0.4))
	for id: String in pieces:
		var p := pieces[id] as ContractSeat
		print("[probe] %s at %s (%.1f m from the camera), sleeping %s" % [id, p.global_position,
			p.global_position.distance_to(cam.global_position), p.sleeping])
	await _shot("furniture_all")
	# Closer, the beds' drawers out.
	for id in ["bed_captain", "bed_waterbed"]:
		for d: VRDrawer in (pieces[id] as ContractSeat).drawers():
			d.set_value(0.8)
	for i in 60:
		await get_tree().physics_frame
	cam.look_at_from_position(Vector3(1.6, 2.4, 3.2), Vector3(-1.6, 0.4, -1.6))
	await _shot("furniture_beds")
	cam.look_at_from_position(Vector3(-2.2, 1.5, 4.2), Vector3(-2.2, 0.55, 1.6))
	await _shot("furniture_sofas")
	cam.look_at_from_position(Vector3(0.0, 1.7, 6.4), Vector3(0.0, 0.2, 3.4))
	await _shot("furniture_floor")
	var rocker := pieces["floor_rocker"] as Node3D
	print("[probe] floor_rocker at %s, up %s, facing %s" % [rocker.global_position, rocker.global_basis.y, rocker.global_basis.z])
	cam.look_at_from_position(rocker.global_position + Vector3(1.6, 0.9, 0.9), rocker.global_position + Vector3(0, 0.3, 0))
	await _shot("furniture_rocker")
	# The player's own camera, seated: a minimal rig, as seat_tests builds one.
	var rig := Node3D.new()
	var origin := XROrigin3D.new()
	origin.position = Vector3(0.0, 0.0, 5.0)
	rig.add_child(origin)
	origin.owner = rig
	var xcam := XRCamera3D.new()
	xcam.position = Vector3(0.0, 1.6, 0.0)
	xcam.fov = 75
	origin.add_child(xcam)
	xcam.owner = rig
	var loco := LocomotionManager.new()
	loco.name = "LocomotionManager"
	rig.add_child(loco)
	add_child(rig)
	xcam.current = true
	var sofa := pieces["sofa_overstuffed"] as ContractSeat
	# Turned round to face the room, so the view from its cushion shows what a sitter sees.
	sofa.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, 0.0, 4.6))
	await get_tree().physics_frame
	var left: Dictionary = {}
	for p: Dictionary in sofa.places():
		if (p["eye"] as Node3D).position.x < -0.1:
			left = p
	(left["trigger"] as SeatTrigger).pointer_event(XRToolsPointerEvent.new(XRToolsPointerEvent.Type.PRESSED, null,
		left["trigger"], Vector3.ZERO, Vector3.ZERO))
	await get_tree().physics_frame
	print("[probe] seated on %s at %s: camera %s, looking %s" % [sofa.name, (left["eye"] as Node3D).name,
		xcam.global_position, -xcam.global_basis.z])
	await _shot("furniture_seated_sofa")
	var bed := pieces["bed_captain"] as ContractSeat
	sofa.stand()
	for p: Dictionary in bed.places():
		if p["lie"]:
			(p["trigger"] as SeatTrigger).pointer_event(XRToolsPointerEvent.new(XRToolsPointerEvent.Type.PRESSED, null,
				p["trigger"], Vector3.ZERO, Vector3.ZERO))
	await get_tree().physics_frame
	print("[probe] lying on %s: camera %s, looking %s" % [bed.name, xcam.global_position, -xcam.global_basis.z])
	await _shot("furniture_lying_bed")
	bed.stand()
	# A floor cushion, turned to face the room: the eyes a floor-sitter's, under a metre.
	var cushion := pieces["floor_cushion_square"] as ContractSeat
	cushion.transform = Transform3D(Basis(Vector3.UP, PI), Vector3(-4.6, 0.0, 6.0))
	await get_tree().physics_frame
	var place: Dictionary = cushion.places()[0]
	(place["trigger"] as SeatTrigger).pointer_event(XRToolsPointerEvent.new(XRToolsPointerEvent.Type.PRESSED, null,
		place["trigger"], Vector3.ZERO, Vector3.ZERO))
	await get_tree().physics_frame
	print("[probe] seated on the floor cushion (floor seat %s): camera %s, %.2f m over the floor, looking %s" % [
		cushion.is_floor_seat(), xcam.global_position, xcam.global_position.y, -xcam.global_basis.z])
	await _shot("furniture_seated_floor")
	cushion.stand()
	for id: String in pieces:
		var model := (pieces[id] as Node).get_node("Model") as ApplianceModel
		print("[probe] %s: %d levels, %d meshes at level 0" % [id, model.levels.size(),
			model.levels[0].find_children("*", "MeshInstance3D", true, false).size() if not model.levels.is_empty() else 0])
	get_tree().quit(0)


func _spawn(id: String, at: Vector3) -> ContractSeat:
	var s := (ScenePersistence.PLAIN_SCENES[id] as PackedScene).instantiate() as ContractSeat
	s.position = at
	add_child(s)
	return s


func _shot(stem: String) -> void:
	# The boot's loading overlay comes up after the first frames: hidden before every still.
	for layer in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join(stem + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("[probe] wrote %s" % path)
