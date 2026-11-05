## seventh_gen_render_probe — how the PlayStation 3 and the Xbox 360 stand in the
## room with no model of their own: the placeholder box, a SLOT in the PS3's face
## and a front tray on the 360, and a disc of each lying in front (a Blu-ray and
## a DVD, so the finishes can be told apart). Then the 360's tray is opened, so
## the two loaders are seen to differ rather than only said to.
##
## Windowed, never --headless (the dummy renderer returns a blank image):
##
##   "$godot" --path RetroXR --resolution 960x540 --position 20,20 \
##     res://Tools/models/seventh_gen_render_probe.tscn -- --out=C:/tmp/seventh_gen
##
## Writes <out>_closed.png and <out>_open.png and prints [seventh] lines.
extends Node3D

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const DISC_SCENE := preload("res://Scenes/Objects/media/disc.tscn")

var _out := "user://seventh_gen"


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("[seventh] TIMEOUT")
		get_tree().quit(1))
	_build_stage()
	var ps3 := _spawn_system("ps3", "PlayStation 3", Vector3(-0.22, 0.0, 0.0))
	var x360 := _spawn_system("xbox360", "Xbox 360", Vector3(0.22, 0.0, 0.0))
	_spawn_disc("ps3", Vector3(-0.22, 0.004, 0.30))
	_spawn_disc("xbox360", Vector3(0.22, 0.004, 0.30))
	for i in 45:
		await get_tree().process_frame
	# The boot's loading overlay is a CanvasLayer over everything: end it, or both
	# shots are the loading card.
	for o in LoadingOverlay.owners():
		LoadingOverlay.end(o)
	LoadingOverlay.suspend()
	for i in 10:
		await get_tree().process_frame
	for sys: RetroSystem in [ps3, x360]:
		print("[seventh] %s loader=%d front_tray=%s slot=%s tray=%s" % [sys.systemid,
			MediaDimensions.disc_loader(sys.systemid), MediaDimensions.has_front_tray(sys.systemid),
			sys.get("_slot") != null, sys.get("_tray") != null])
	await _shot("closed")
	var drive: Variant = x360.get("_disc_tray")
	if drive != null and bool(drive.get("front_tray")):
		drive.call("set_open", true)
		for i in 90:
			await get_tree().process_frame
		await _shot("open")
	else:
		print("[seventh] the 360 built no front tray, so there is no tray to open: skipped _open.png")
	print("[seventh] done")
	get_tree().quit(0)


func _build_stage() -> void:
	var cam := Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	cam.look_at_from_position(Vector3(0.0, 0.42, 0.85), Vector3(0.0, 0.05, 0.08))
	cam.current = true
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.16, 0.17, 0.19)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.55, 0.6)
	add_child(env)
	var floor := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 0.02, 4.0)
	shape.shape = box
	shape.position.y = -0.01
	floor.add_child(shape)
	var mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(4.0, 4.0)
	mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.27, 0.22)
	mesh.material_override = mat
	floor.add_child(mesh)
	add_child(floor)


func _spawn_system(systemid: String, label: String, at: Vector3) -> RetroSystem:
	var sys := SYSTEM_SCENE.instantiate() as RetroSystem
	sys.name = "Sys_" + systemid
	sys.systemid = systemid
	sys.model_id = SystemModelRegistry.PLACEHOLDER_ID
	sys.system_label = label
	add_child(sys)
	sys.freeze = true
	sys.ignore_gravity = true
	sys.position = at + Vector3(0.0, 0.05, 0.0)
	return sys


func _spawn_disc(systemid: String, at: Vector3) -> void:
	var disc := DISC_SCENE.instantiate()
	disc.set("systemid", systemid)
	disc.set("rom_path", "")
	add_child(disc)
	if disc is RigidBody3D:
		(disc as RigidBody3D).freeze = true
	# Label side up, lying on the floor: lifted by half a disc's thickness plus air.
	(disc as Node3D).position = at + Vector3(0.0, 0.004, 0.0)
	var finish := MediaDimensions.disc_finish(systemid)
	print("[seventh] %s disc: diameter=%.3f pitch=%.2f" % [systemid,
		MediaDimensions.disc_diameter(systemid), float(finish["pitch"])])


func _shot(tag: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s_%s.png" % [_out, tag]
	var err := img.save_png(path)
	print("[seventh] shot %s -> %s (%dx%d, err=%d)" % [tag, path, img.get_width(), img.get_height(), err])
