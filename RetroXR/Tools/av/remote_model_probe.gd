extends Node3D
## The RETRO XR remote in the game: held in a right hand and aimed at the RETRO XR television, its grid up over
## it, then one of its keys pressed (a desktop click held down) close up. Checks the grid targeted the set and the
## pressed key did its cell. Windowed only (headless draws nothing):
##
##     godot --path RetroXR res://Tools/av/remote_model_probe.tscn --resolution 1280x720 --position 20,20 -- --out=<dir>
##
## Renders through its own SubViewport + camera (the desktop loading screen is a CanvasLayer over the main view); a
## second camera in the main view follows it, because the grid turns to face the main view's camera.

const TV := preload("res://Scenes/Objects/tv.tscn")
const REMOTE := preload("res://Scenes/Objects/appliances/tv_remote.tscn")

var _vp: SubViewport
var _cam: Camera3D
var _main_cam: Camera3D
var _out := "user://remote_model_probe"
var _fails := 0


func _ready() -> void:
	get_tree().create_timer(90.0).timeout.connect(func(): print("[remoteprobe] timeout"); get_tree().quit(1))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.2, 0.2, 0.21)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.55, 0.57)
	env.environment.ambient_light_energy = 0.9
	env.environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 25, 0)
	sun.light_energy = 2.0
	sun.shadow_enabled = true
	add_child(sun)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(6, 6)
	floor.mesh = pm
	floor.position.y = -0.165
	add_child(floor)

	var tv := TV.instantiate() as RetroTV
	tv.tv_model = "retroxr_crt"
	add_child(tv)
	tv.freeze = true
	_vp = SubViewport.new()
	_vp.size = Vector2i(1280, 720)
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_cam = Camera3D.new()
	_cam.fov = 45
	_cam.near = 0.01
	_vp.add_child(_cam)
	_main_cam = Camera3D.new()
	add_child(_main_cam)
	_main_cam.current = true
	await _frames(8)
	tv.set_power(true)

	# Held in a right hand at chest height, a metre from the set, aimed at it and tipped up a little.
	var remote := REMOTE.instantiate() as TVRemote
	remote.freeze = true
	add_child(remote)
	remote.global_transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(12), deg_to_rad(4), deg_to_rad(-10))),
		Vector3(0.12, -0.02, 0.85))
	(remote.get_node("HandRight") as Node3D).visible = true
	var hand := XRController3D.new()
	hand.tracker = &"right_hand"
	add_child(hand)
	await _frames(4)
	remote._holding_ctrl = hand
	_aim(Vector3(0.42, 0.22, 1.45), Vector3(0.02, 0.02, 0.35))
	await _frames(12)
	_check(remote._target == tv, "the held remote targets the set it points at")
	_check(remote._menu.visible, "the grid is up")
	await _shot("remote_held_aimed_at_tv")

	# A key held down, close up: MUTE, which mutes the set it points at.
	var key := remote.key_button("KeyMute")
	var muted := tv.is_muted()
	var at := key.global_position
	key.pointer_event(XRToolsPointerEvent.new(XRToolsPointerEvent.Type.PRESSED, null, key, at, at))
	await _frames(2)
	_check(tv.is_muted() != muted, "the pressed MUTE key muted the set")
	var face := remote.global_transform
	_aim(face * Vector3(0.07, 0.07, 0.03), face * Vector3(0.0, 0.01, -0.06))
	await _frames(6)
	await _shot("remote_key_pressed")
	print("[remoteprobe] ---- %d failed ----" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


func _aim(from: Vector3, to: Vector3) -> void:
	_cam.look_at_from_position(from, to)
	_main_cam.global_transform = _cam.global_transform


func _check(ok: bool, what: String, detail := "") -> void:
	if not ok:
		_fails += 1
	print("[remoteprobe] %s %s %s" % ["PASS" if ok else "FAIL", what, detail])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	var path := _out.path_join(shot_name + ".png")
	img.save_png(path)
	print("[remoteprobe] wrote ", path)
