## The Mission pair in the Mobile renderer, every drawer out a different amount, the case collision drawn as the
## game would meet it. Writes stills.
##
##     "$godot" --path RetroXR --resolution 1200x800 --position 20,20 res://Tools/room/mission_probe.tscn -- --out=DIR
##
## Windowed, never --headless: the dummy renderer draws nothing.
extends Node3D

var out_dir := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--out="):
			out_dir = String(a).trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_tree().create_timer(60.0).timeout.connect(func() -> void: get_tree().quit(2))
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
	key.rotation_degrees = Vector3(-48, -32, 0)
	key.light_energy = 1.6
	key.shadow_enabled = true
	add_child(key)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(6, 6)
	floor_mesh.mesh = plane
	add_child(floor_mesh)
	# A floor to stand on: the pieces are rigid bodies.
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6, 0.2, 6)
	cs.shape = box
	cs.position = Vector3(0, -0.1, 0)
	floor_body.add_child(cs)
	add_child(floor_body)
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 45
	var scale := 1.0
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--scale="):
			scale = float(String(a).trim_prefix("--scale="))
	var target := Vector3(-0.1, 0.6, 0.0)
	cam.look_at_from_position(target + (Vector3(1.2, 1.7, 2.8) - target) * scale, target)
	cam.current = true
	var n := (ScenePersistence.PLAIN_SCENES["mission_nightstand"] as PackedScene).instantiate() as DrawerFurniture
	n.position = Vector3(0.6, 0, 0)
	add_child(n)
	var c := (ScenePersistence.PLAIN_SCENES["mission_chest"] as PackedScene).instantiate() as DrawerFurniture
	c.position = Vector3(-0.55, 0, 0)
	add_child(c)
	for i in 10:
		await get_tree().physics_frame
	for layer in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	await _shot("mission_shut")
	var amounts := [0.7, 0.0, 0.4, 0.0, 0.9, 0.2]
	for i in c.drawers().size():
		c.drawers()[i].set_value(amounts[i])
	n.drawers()[0].set_value(0.8)
	for i in 60:
		await get_tree().physics_frame
	await _shot("mission_open_%.1f" % scale)
	for piece: DrawerFurniture in [n, c]:
		var model := piece.get_node("Model") as ApplianceModel
		for i in model.levels.size():
			var cm := model.part("Case", i) as GeometryInstance3D
			if cm == null:
				print("[probe] %s level %d: no Case" % [piece.type_id, i])
				continue
			print("[probe] %s level %d Case: visible %s range %.2f-%.2f, camera %.2f m from its origin" % [piece.type_id, i,
				cm.is_visible_in_tree(), cm.visibility_range_begin, cm.visibility_range_end,
				get_viewport().get_camera_3d().global_position.distance_to(cm.global_transform * (cm as MeshInstance3D).get_aabb().get_center())])
	print("[probe] chest drawers at %s, nightstand drawer at %.2f" % [
		c.drawers().map(func(d: VRDrawer) -> String: return "%.2f" % d.value), n.drawers()[0].value])
	get_tree().quit(0)


func _shot(stem: String) -> void:
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join(stem + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("[probe] wrote %s" % path)
