## The RETRO XR computer desks (DrawerFurniture, RetroXR-models generic/living-room) in the Mobile renderer, each with the
## game's own computer on it: the PC tower set in its cubby, the keyboard on the keyboard tray PULLED OUT, the Plain
## Monitor on the top facing the tray, and a still from behind of the cubby's open back (the tower's back panel shows
## through). Writes two stills a desk.
##
##     "$godot" --path RetroXR --resolution 1280x720 --position 20,20 res://DevTools/room/computer_desk_probe.tscn -- --out=DIR
##
## Windowed, never --headless: the dummy renderer draws nothing.
extends Node3D

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const TV_SCENE := preload("res://Scenes/Objects/tv.tscn")
const KEYBOARD_SCENE := preload("res://Scenes/Objects/peripherals/retro_keyboard.tscn")
const DESKS := ["computer_desk_laminate", "computer_desk_corner", "computer_desk_mission"]

var out_dir := ""
var cam: Camera3D


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--out="):
			out_dir = String(a).trim_prefix("--out=")
	if out_dir.is_empty():
		out_dir = OS.get_user_data_dir().path_join("computer_desk_probe")
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_tree().create_timer(240.0).timeout.connect(func() -> void:
		print("[probe] TIMED OUT")
		get_tree().quit(2))
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.32, 0.33, 0.36)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.62, 0.66)
	env.ambient_light_energy = 0.8
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
	cam = Camera3D.new()
	add_child(cam)
	cam.fov = 50
	cam.current = true
	for id: String in DESKS:
		await _desk(id)
	get_tree().quit(0)


func _desk(id: String) -> void:
	var desk := ScenePersistence.instantiate(id) as DrawerFurniture
	add_child(desk)
	for i in 10:
		await get_tree().physics_frame
	desk.freeze = true
	var c: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(desk.contract_path))
	var comp: Dictionary = c["computer"]
	var cub: Dictionary = comp["tower_cubby"]
	var lo := DrawerFurniture._v3(cub["min"])
	var hi := DrawerFurniture._v3(cub["max"])
	# The tower in its cubby, its front 15 mm in.
	var sys := SYSTEM_SCENE.instantiate() as RigidBody3D
	sys.set("model_id", "pc_tower")
	sys.set("systemid", "dos")
	sys.freeze = true
	sys.position = Vector3(5.0, 1.0, 5.0)
	add_child(sys)
	for i in 90:
		await get_tree().physics_frame
	await _set_down(sys, desk, Basis.IDENTITY, Vector3((lo.x + hi.x) * 0.5, lo.y, 0.0), hi.z - 0.015)
	# The keyboard on the tray, the tray then pulled out.
	var k := -1
	var rows: Array = c["drawers"]
	for i in rows.size():
		if str(rows[i]["node"]) == str(comp["keyboard_tray"]["node"]):
			k = i
	var row: Dictionary = rows[k]
	var axis := DrawerFurniture._v3(row["axis"]).normalized()
	var inner: Dictionary = row["inner"]
	var inner_len := float((inner.get("size_local", inner["size"]) as Array)[2])
	var seat := desk.drawer_seat_local(k)
	var kb := KEYBOARD_SCENE.instantiate() as RigidBody3D
	kb.position = desk.global_transform * (Vector3(seat.x, 0.05, seat.z) + axis * 0.7)   # its cord's plug lands here
	add_child(kb)
	for i in 5:
		await get_tree().physics_frame
	var at := seat + axis * (inner_len * 0.5 - 0.095)
	await _set_down(kb, desk, FurnitureDrawers.axis_basis(axis), Vector3(at.x, seat.y, at.z))
	# The monitor on the top, facing the tray, its front 30 mm behind the edge the tray comes out of.
	var face := float(row.get("case_face_m", c.get("case_front_z", 0.0)))
	var top_y := float((comp["monitor_places"] as Array)[0]["min"][1])
	var centre := seat + axis * ((face - 0.24) - seat.dot(axis))
	var tv := TV_SCENE.instantiate() as RigidBody3D
	tv.set("tv_model", "crt_plain")
	tv.freeze = true
	tv.position = Vector3(-5.0, 1.0, 5.0)
	add_child(tv)
	for i in 60:
		await get_tree().physics_frame
	await _set_down(tv, desk, FurnitureDrawers.axis_basis(axis), Vector3(centre.x, top_y, centre.z))
	for i in 60:      # pulled out as a hand pulls it
		desk.drawers()[k].set_value((i + 1) / 60.0)
		await get_tree().physics_frame
	for i in 60:
		await get_tree().physics_frame
	# Plugged into the tower's first port (the PS/2 keyboard jack on its back): the cord runs out of the open cubby.
	if kb.has_method("restore_port_connection"):
		kb.call("restore_port_connection", sys, 0)
	for i in 120:
		await get_tree().physics_frame
	var kp := desk.global_transform.affine_inverse() * kb.global_position
	print("[probe] %s: tray out %.0f mm, keyboard at %s (seat %s), tower at %s, monitor at %s" % [id,
		desk.drawers()[k].open_distance() * 1000.0, kp, seat, desk.to_local(sys.global_position),
		desk.to_local(tv.global_position)])
	cam.current = true
	var size := DrawerFurniture._v3(c["size"])
	var s := maxf(size.x, size.z)
	var mid := Vector3(0.0, 0.55, 0.0)
	cam.look_at_from_position(Vector3(0.55 * s, 1.35, 1.25 * s + 0.6), mid)
	for i in 3:
		await RenderingServer.frame_post_draw
	await _shot("%s_front" % id)
	# From behind, low, at the cubby: its back is open and the tower's back panel shows.
	var cc := Vector3((lo.x + hi.x) * 0.5, 0.3, lo.z)
	cam.look_at_from_position(cc + Vector3(-0.55, 0.45, -1.3), cc + Vector3(0.0, 0.05, 0.25))
	for i in 3:
		await RenderingServer.frame_post_draw
	await _shot("%s_back" % id)
	for n in [sys, kb, tv, desk]:
		n.queue_free()
	for i in 5:
		await get_tree().physics_frame


func _visual_box(node: Node3D, frame: Node3D) -> AABB:
	var inv := frame.global_transform.affine_inverse()
	var out := AABB()
	var first := true
	for c in node.get_children():
		var cs := c as CollisionShape3D
		if cs == null or cs.disabled or cs.shape == null:
			continue
		var b := (inv * cs.global_transform) * cs.shape.get_debug_mesh().get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out


func _set_down(body: RigidBody3D, frame: Node3D, basis: Basis, at: Vector3, front_z := INF) -> void:
	# Worked out from the body's own box BEFORE it is moved: put down overlapping the desk, even frozen for a tick, it
	# shoves the desk away (the desk was pushed two metres).
	var own := Transform3D(basis, Vector3.ZERO) * _visual_box(body, body)
	var origin := Vector3(at.x - own.get_center().x, at.y + 0.008 - own.position.y, at.z - own.get_center().z)
	if front_z != INF:
		origin.z = front_z - own.end.z
	# Unfrozen FIRST, then moved: a frozen (kinematic) body moved by its transform gets the jump as a velocity, which it
	# keeps when let go (500 m/s: the monitor left the room).
	body.freeze = false
	body.global_transform = frame.global_transform * Transform3D(basis, origin)
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	for i in 90:
		await get_tree().physics_frame


func _shot(stem: String) -> void:
	for layer in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var path := out_dir.path_join(stem + ".png")
	get_viewport().get_texture().get_image().save_png(path)
	print("[probe] wrote %s" % path)
