## Console stands (StandCatalog): the Wii in its RVL-017 cradle and a PS2 in its
## SCPH-10040 vertical stand, each mounted the way a restore mounts it, beside an
## empty stand and the console lying loose for contrast.
##
## Prints how far each console's resting face lies from its stand's seat and
## which way its up points, and writes stills.
##
##     "$godot" --path RetroXR --resolution 960x720 --position 20,20 \
##         res://Tools/room/console_stand_probe.tscn -- --out=C:/path/to/stills
##
## Windowed, never --headless: the dummy renderer draws nothing.
extends Node3D

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const STAND_SCENE := preload("res://Scenes/Objects/stands/console_stand.tscn")

var out_dir := ""
var _cam: Camera3D
## Every VisualInstance3D outside these is hidden: the panels a console floats
## beside itself would stand in front of the cameras.
var _keep: Array[Node] = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if String(a).begins_with("--out="):
			out_dir = String(a).trim_prefix("--out=")
	if not out_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(out_dir)
	get_tree().create_timer(90.0).timeout.connect(func() -> void: get_tree().quit(2))
	_light()
	await _run()
	get_tree().quit(0)


func _light() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.57, 0.62)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.62, 0.68)
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42, -38, 0)
	key.light_energy = 1.6
	key.shadow_enabled = true
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18, 130, 0)
	fill.light_energy = 0.6
	add_child(fill)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(3, 3)
	floor_mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.36, 0.30)
	floor_mesh.material_override = mat
	floor_mesh.position = Vector3(0, 1.0, 0)
	add_child(floor_mesh)
	_keep.append(floor_mesh)
	_cam = Camera3D.new()
	_cam.fov = 40.0
	add_child(_cam)


func _wait(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _shot(name: String, from: Vector3, at: Vector3) -> void:
	_hide_panels()
	_cam.position = from
	_cam.look_at(at, Vector3.UP)
	await _wait(3)
	await RenderingServer.frame_post_draw
	if out_dir.is_empty():
		return
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])
	print("[probe] wrote %s" % name)


func _hide_panels() -> void:
	# Off a headset the loading screen is a flat CanvasLayer over everything.
	for layer in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	for n in get_tree().root.find_children("*", "VisualInstance3D", true, false):
		if n is Light3D:
			continue
		var wanted := _keep.any(func(k: Node) -> bool:
			return is_instance_valid(k) and (k == n or k.is_ancestor_of(n)))
		(n as VisualInstance3D).visible = wanted


func _console(systemid: String, at: Vector3) -> RetroSystem:
	var sys := SYSTEM_SCENE.instantiate() as RetroSystem
	sys.systemid = systemid
	sys.freeze = true
	add_child(sys)
	sys.global_position = at
	await _wait(25)
	_keep.append(sys.get("_model"))
	var box := sys.get("_system_body") as Node
	if box != null and (box as Node3D).visible:
		_keep.append(box)
	return sys


func _stand(stand_id: String, at: Vector3) -> ConsoleStand:
	var stand := STAND_SCENE.instantiate() as ConsoleStand
	stand.stand_id = stand_id
	stand.freeze = true
	add_child(stand)
	stand.global_position = at
	await _wait(2)
	for c in stand.get_children():
		if c is MeshInstance3D or c.name == "Model":
			_keep.append(c)
	return stand


func _report(stand: ConsoleStand, sys: RetroSystem) -> void:
	var face := StandCatalog.face_of(stand.stand_id)
	var foot := StandFoot.find(sys, face)
	if foot == null or stand.seated_console() != sys:
		print("[probe] %s: NOT mounted" % stand.stand_id)
		return
	print("[probe] %s: %s mounted on its %s face, %.2f mm from the seat; console +Y %s, +X %s, box %s" % [
		stand.stand_id, sys.systemid, face,
		foot.global_position.distance_to(stand.mount().global_position) * 1000.0,
		sys.global_basis.y.snapped(Vector3.ONE * 0.001), sys.global_basis.x.snapped(Vector3.ONE * 0.001),
		sys.body_aabb().size])


func _run() -> void:
	const Y := 1.0
	var wii_stand := await _stand("wii_stand", Vector3(-0.25, Y, 0))
	var wii := await _console("wii", Vector3(-0.25, Y + 0.3, 0.4))
	var ps2_stand := await _stand("ps2_vertical_stand", Vector3(0.20, Y, 0))
	var ps2 := await _console("ps2", Vector3(0.20, Y + 0.3, 0.6))
	# Empty, for what the stands look like on their own.
	await _shot("stands_empty", Vector3(0.0, Y + 0.45, 0.85), Vector3(0.0, Y + 0.03, 0))
	wii_stand.restore_console(wii)
	ps2_stand.restore_console(ps2)
	await _wait(10)
	_report(wii_stand, wii)
	_report(ps2_stand, ps2)
	await _shot("mounted_front", Vector3(0.05, Y + 0.30, 0.95), Vector3(0.0, Y + 0.10, 0))
	await _shot("mounted_side", Vector3(0.85, Y + 0.25, 0.55), Vector3(0.0, Y + 0.10, 0))
	await _shot("wii_close", Vector3(-0.10, Y + 0.18, 0.40), Vector3(-0.25, Y + 0.06, 0))
