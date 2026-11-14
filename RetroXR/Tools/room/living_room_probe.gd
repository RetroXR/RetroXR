## The RETRO XR living-room set (DrawerFurniture, RetroXR-models generic/living-room) in the Mobile renderer: all fifteen
## laid out shut, then every drawer, sliding door and hinged door OPEN through its own control (VRDrawer.set_value,
## VRDoor.open_to), a close shot of the wall unit's clear glass doors with a box behind them, and a TV and a VCR dropped
## onto the Mission TV stand (its top and a cubby). Writes stills.
##
##     "$godot" --path RetroXR --resolution 1280x720 --position 20,20 res://Tools/room/living_room_probe.tscn -- --out=DIR
##
## Windowed, never --headless: the dummy renderer draws nothing.
extends Node3D

const TV := preload("res://Scenes/Objects/tv.tscn")

var out_dir := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--out="):
			out_dir = String(a).trim_prefix("--out=")
	if out_dir.is_empty():
		out_dir = OS.get_user_data_dir().path_join("living_room_probe")
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
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
	plane.size = Vector2(18, 14)
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.55, 0.52, 0.48)
	plane.material = floor_mat
	floor_mesh.mesh = plane
	add_child(floor_mesh)
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(18, 0.2, 14)
	cs.shape = box
	cs.position = Vector3(0, -0.1, 0)
	floor_body.add_child(cs)
	add_child(floor_body)
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 50
	cam.current = true
	# Bookcases at the back, TV stands in the middle, coffee tables at the front, every one facing the camera (+Z).
	var pieces := {}
	var rows := [
		[["bookshelf_oak", -4.0], ["bookshelf_mission", -2.6], ["bookshelf_midcentury", -1.2], ["bookshelf_cube", 0.3],
			["bookshelf_pine", 1.9], ["tv_stand_wall_unit", 4.0], -2.6],
		[["tv_stand_mission", -4.6], ["tv_stand_credenza", -2.6], ["tv_stand_bench", -0.7], ["tv_stand_corner", 0.8],
			["tv_stand_cubby", 2.5], 0.0],
		[["coffee_table_mission", -3.0], ["coffee_table_midcentury", -1.2], ["coffee_table_glass", 0.6],
			["coffee_table_pine", 2.4], 2.2]]
	for row: Array in rows:
		var z := float(row[row.size() - 1])
		for i in row.size() - 1:
			pieces[row[i][0]] = _spawn(row[i][0], Vector3(float(row[i][1]), 0.0, z))
	for i in 20:
		await get_tree().physics_frame
	await get_tree().create_timer(3.0).timeout
	cam.look_at_from_position(Vector3(0.0, 3.4, 9.6), Vector3(0.0, 0.6, -0.2))
	await _shot("living_all")
	# Everything open through its own control.
	var opened := 0
	for id: String in pieces:
		var p := pieces[id] as DrawerFurniture
		var ds := p.drawers()
		for k in ds.size():
			# The mid-century bookcase's two sliders cover each other's half: both slid, they only swap places.
			if id == "bookshelf_midcentury" and k > 0:
				break
			ds[k].set_value(1.0)
			opened += 1
		for door: VRDoor in p.doors():
			door.open_to(door.open_deg, true)
			opened += 1
	for i in 90:
		await get_tree().physics_frame
	print("[probe] opened %d drawers, sliders and doors" % opened)
	await _shot("living_all_open")
	cam.look_at_from_position(Vector3(-1.4, 1.8, 4.2), Vector3(-1.4, 0.7, -1.2))
	await _shot("living_bookcases_open")
	cam.look_at_from_position(Vector3(-2.6, 1.5, 3.4), Vector3(-2.6, 0.35, 0.0))
	await _shot("living_stands_open")
	cam.look_at_from_position(Vector3(-0.3, 1.6, 5.0), Vector3(-0.3, 0.3, 2.2))
	await _shot("living_tables_open")
	# The wall unit shut again, a box on a shelf behind each glass door: the glass shows it.
	var wall := pieces["tv_stand_wall_unit"] as DrawerFurniture
	for door: VRDoor in wall.doors():
		door.close(false)
	for x in [-0.72, 0.72]:
		var marker := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.22, 0.2, 0.15)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.85, 0.2, 0.15)
		bm.material = mat
		marker.mesh = bm
		wall.add_child(marker)
		marker.position = Vector3(x, 0.95, 0.0)
	await get_tree().physics_frame
	var glass := 0
	for mi in wall.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for s in m.mesh.get_surface_count():
			var sm := m.get_active_material(s) as BaseMaterial3D
			if sm != null and sm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				glass += 1
				print("[probe] transparent surface on %s: %s, alpha %.2f" % [m.name, sm.resource_name, sm.albedo_color.a])
	print("[probe] the wall unit has %d transparent surfaces (all levels)" % glass)
	cam.look_at_from_position(wall.global_position + Vector3(-0.2, 1.1, 1.9), wall.global_position + Vector3(0.0, 0.8, 0.0))
	await _shot("living_wall_unit_glass")
	# A TV on the Mission stand's top and a VCR in its cubby, dropped and left to settle.
	var stand := pieces["tv_stand_mission"] as DrawerFurniture
	for d: VRDrawer in stand.drawers():
		d.set_value(0.0)
	var tv := TV.instantiate() as Node3D
	add_child(tv)
	tv.global_position = stand.global_position + Vector3(0.0, 0.62, 0.0)
	var vcr := ScenePersistence.instantiate("vcr_player") as Node3D
	if vcr != null:
		add_child(vcr)
		vcr.global_position = stand.global_position + Vector3(-0.26, 0.35, 0.06)
	for i in 150:
		await get_tree().physics_frame
	print("[probe] stand at %s" % stand.global_position)
	print("[probe] TV at %s (stand top %.3f), VCR at %s" % [tv.global_position, stand.global_position.y + 0.56,
		vcr.global_position if vcr != null else Vector3.ZERO])
	# The set brings cameras of its own (focus mode): ours is made current again for the still.
	cam.current = true
	cam.look_at_from_position(stand.global_position + Vector3(1.2, 1.3, 2.2), stand.global_position + Vector3(0.0, 0.6, 0.0))
	for i in 3:
		await RenderingServer.frame_post_draw
	await _shot("living_tv_on_stand")
	get_tree().quit(0)


func _spawn(id: String, at: Vector3) -> DrawerFurniture:
	var s := (ScenePersistence.PLAIN_SCENES[id] as PackedScene).instantiate() as DrawerFurniture
	s.position = at
	add_child(s)
	return s


func _shot(stem: String) -> void:
	for layer in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join(stem + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("[probe] wrote %s" % path)
