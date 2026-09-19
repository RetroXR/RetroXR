## Renders the GameCube Microphone (DOL-022) seated in a GameCube's slot B, and
## prints the plug's axes so its facing is checked by numbers, not by eye.
##
##     "$godot" --path RetroXR --resolution 320x240 --position 20,20 \
##         res://Tools/models/gc_microphone_render_probe.tscn -- --out=<dir>
##
## Windowed: the headless renderer returns a blank image. The SubViewport shares
## the probe's world, because the cord is parented to the current scene.
extends Node

var out_dir := ""


func _ready() -> void:
	out_dir = OS.get_user_data_dir()
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--out="):
			out_dir = str(arg).trim_prefix("--out=").replace("\\", "/")
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("[gcmicrender] TIMEOUT")
		get_tree().quit(1))
	_run()


func _run() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.32, 0.33, 0.36)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.55, 0.58)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.4
	add_child(sun)

	var sys := preload("res://Scenes/Objects/system.tscn").instantiate() as RetroSystem
	sys.systemid = "gc"
	add_child(sys)
	sys.freeze = true
	var mic := preload("res://Scenes/Objects/controllers/gamecube/gc_microphone.tscn").instantiate() as GcMicrophone
	add_child(mic)
	mic.freeze = true
	for i in range(5):
		await get_tree().process_frame

	var slot := sys.memcard_slots()[1]
	var plug := mic.get_plug()
	sys.restore_memory_card(plug, 1)
	var sys_basis := sys.global_transform.basis.orthonormalized()
	mic.global_transform = Transform3D(sys_basis, slot.global_position
		+ slot.global_transform.basis.z * 0.22 + sys_basis.x * 0.10 + sys_basis.y * 0.02)
	for i in range(90):
		await get_tree().physics_frame

	var outward := (plug.global_position - sys.global_position).normalized()
	print("[gcmicrender] slot B basis z = %s" % slot.global_transform.basis.z)
	print("[gcmicrender] plug basis x = %s  y = %s  z = %s" % [plug.global_transform.basis.x,
		plug.global_transform.basis.y, plug.global_transform.basis.z])
	print("[gcmicrender] cord end (+Z) points out of the console: %s (dot %.2f)"
		% [plug.global_transform.basis.z.dot(outward) > 0.0, plug.global_transform.basis.z.dot(outward)])
	print("[gcmicrender] microphone_position follows the stick: %s"
		% sys.microphone_position().is_equal_approx(mic.global_position))

	var sv := SubViewport.new()
	sv.size = Vector2i(1200, 900)
	sv.own_world_3d = false
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sv)
	var cam := Camera3D.new()
	cam.fov = 40.0
	sv.add_child(cam)

	# The loading overlay parks a panel in front of the first camera it sees.
	for o in LoadingOverlay.owners():
		LoadingOverlay.end(o)
	for i in range(30):
		await get_tree().process_frame

	var up := sys_basis.y
	var target := plug.global_position
	var out_z := plug.global_transform.basis.z
	print("[gcmicrender] plug at %s, stick at %s, console at %s"
		% [plug.global_position, mic.global_position, sys.global_position])
	var eye := target + out_z * 0.14 + up * 0.06 + sys_basis.x * 0.05
	await _shot(sv, cam, eye, target, up, "gc_mic_seated.png")
	var wide_target := (target + mic.global_position) * 0.5
	var span := maxf(target.distance_to(mic.global_position), 0.2)
	await _shot(sv, cam, wide_target + out_z * span * 1.6 + up * span * 0.9, wide_target, up,
		"gc_mic_wide.png")
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
	print("[gcmicrender] wrote %s" % path)
