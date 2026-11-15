## The seat facing arrow (SeatFacingArrow, shown by the seat itself as a hand takes it) on two green overstuffed sofas
## and two captain's beds (a bed's runs pillow to foot), then frames of it fading out, in and pulsing for a clip.
## Writes stills and frames/NNN.png.
##
##     "$godot" --path RetroXR --resolution 1280x720 --position 20,20 res://Tools/room/seat_arrow_probe.tscn -- --out=DIR
##
## Windowed, never --headless: the dummy renderer draws nothing.
extends Node3D

var out_dir := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--out="):
			out_dir = String(a).trim_prefix("--out=")
	if out_dir.is_empty():
		out_dir = OS.get_user_data_dir().path_join("seat_arrow_probe")
	DirAccess.make_dir_recursive_absolute(out_dir.path_join("frames"))
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
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 50
	cam.current = true
	# Old on the left, new on the right; sofas in front, beds behind. All face the camera (+Z).
	var old_sofa := _spawn("sofa_overstuffed", Vector3(-1.3, 0.0, 1.2))
	var new_sofa := _spawn("sofa_overstuffed", Vector3(1.3, 0.0, 1.2))
	var old_bed := _spawn("bed_captain", Vector3(-1.4, 0.0, -1.6))
	var new_bed := _spawn("bed_captain", Vector3(1.4, 0.0, -1.6))
	for s: ContractSeat in [old_sofa, new_sofa, old_bed, new_bed]:
		s.freeze = true
	await get_tree().create_timer(3.0).timeout
	var arrows: Array[SeatFacingArrow] = []
	for s: ContractSeat in [old_sofa, old_bed, new_sofa, new_bed]:
		arrows.append(_new_arrow(s))
	arrows = [arrows[2], arrows[3]]
	await get_tree().create_timer(0.5).timeout
	cam.look_at_from_position(Vector3(0.0, 2.6, 4.6), Vector3(0.0, 0.45, 0.0))
	await _shot("arrow_compare")
	cam.look_at_from_position(new_sofa.global_position + Vector3(0.9, 1.3, 1.6), new_sofa.global_position + Vector3(0, 0.45, 0))
	await _shot("arrow_sofa_close")
	cam.look_at_from_position(new_sofa.global_position + Vector3(0.0, 2.2, 0.5), new_sofa.global_position + Vector3(0, 0.45, 0.05))
	await _shot("arrow_sofa_top")
	cam.look_at_from_position(new_bed.global_position + Vector3(1.4, 1.6, 2.4), new_bed.global_position + Vector3(0, 0.5, 0))
	await _shot("arrow_bed_close")
	# The place highlight a laser lights (SeatTrigger's hover), on every place of a sofa and a bed, the arrows hidden.
	for s: ContractSeat in [new_sofa, new_bed]:
		s.call("_hide_facing_arrow")
		for p: Dictionary in s.places():
			var t := p["trigger"] as SeatTrigger
			t.pointer_event(XRToolsPointerEvent.new(XRToolsPointerEvent.Type.ENTERED, null, t, Vector3.ZERO, Vector3.ZERO))
	await get_tree().create_timer(0.4).timeout
	cam.look_at_from_position(new_bed.global_position + Vector3(1.4, 1.6, 2.4), new_bed.global_position + Vector3(0, 0.5, 0))
	await _shot("hover_bed")
	cam.look_at_from_position(new_bed.global_position + Vector3(0.4, 1.0, 1.6), new_bed.global_position + Vector3(0, 0.62, 0.3))
	await _shot("hover_bed_low")
	cam.look_at_from_position(new_sofa.global_position + Vector3(0.9, 1.3, 1.6), new_sofa.global_position + Vector3(0, 0.45, 0))
	await _shot("hover_sofa")
	for s: ContractSeat in [new_sofa, new_bed]:
		for p: Dictionary in s.places():
			var t := p["trigger"] as SeatTrigger
			t.pointer_event(XRToolsPointerEvent.new(XRToolsPointerEvent.Type.EXITED, null, t, Vector3.ZERO, Vector3.ZERO))
	arrows = [_new_arrow(new_sofa), _new_arrow(new_bed)]
	# A clip: dismissed and made again (fade out, fade in), then the pulse and scanlines running.
	cam.look_at_from_position(new_sofa.global_position + Vector3(0.9, 1.3, 1.6), new_sofa.global_position + Vector3(0, 0.45, 0))
	var n := 0
	for i in 150:
		if i == 10:
			new_sofa.call("_hide_facing_arrow")
		if i == 40:
			new_sofa.call("_hide_facing_arrow")
			arrows[0] = _new_arrow(new_sofa)
		await _frame(n)
		n += 1
	print("[probe] %d frames" % n)
	get_tree().quit(0)


func _new_arrow(s: ContractSeat) -> SeatFacingArrow:
	s.call("_show_facing_arrow")
	var arrow := s.facing_arrow()
	print("[probe] arrow on %s at %s pointing %s" % [s.name, arrow.global_position, -arrow.global_basis.z])
	return arrow


func _spawn(id: String, at: Vector3) -> ContractSeat:
	var s := (ScenePersistence.PLAIN_SCENES[id] as PackedScene).instantiate() as ContractSeat
	s.position = at
	add_child(s)
	return s


func _hide_overlays() -> void:
	for layer in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false


func _shot(stem: String) -> void:
	_hide_overlays()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join(stem + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("[probe] wrote %s" % path)


func _frame(n: int) -> void:
	_hide_overlays()
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join("frames/%03d.png" % n))
