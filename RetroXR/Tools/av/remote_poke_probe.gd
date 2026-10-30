extends Node3D
## A fingertip poking the RETRO XR remote's keys in turn, the way a tracked hand does in the room: a real
## XRController3D on a registered tracker (so VRButton's own touch path presses, nothing is called directly), its
## index tip a small sphere. Writes one PNG per frame for an mp4 and checks each key sank and fired once.
## Windowed only (headless draws nothing):
##
##     godot --path RetroXR res://Tools/av/remote_poke_probe.tscn --resolution 640x360 --position 20,20 -- --out=<dir>
##
## Renders through its own SubViewport + camera (the desktop loading screen is a CanvasLayer over the main view).

const REMOTE := preload("res://Scenes/Objects/appliances/tv_remote.tscn")
const KEYS: Array[String] = ["KeyPower", "KeyMute", "KeyPlayPause", "KeyOk", "KeyRight", "KeyMenu"]
const TRACKER := &"remote_poke_probe_finger"

var _vp: SubViewport
var _cam: Camera3D
var _out := "user://remote_poke_probe"
var _fails := 0
var _frame := 0
var _tracker: XRPositionalTracker
var _fired: Dictionary = {}


func _ready() -> void:
	get_tree().create_timer(120.0).timeout.connect(func(): print("[pokeprobe] timeout"); get_tree().quit(1))
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
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.light_energy = 2.0
	sun.shadow_enabled = true
	add_child(sun)
	var table := MeshInstance3D.new()
	var tm := BoxMesh.new()
	tm.size = Vector3(0.6, 0.02, 0.5)
	table.mesh = tm
	table.position = Vector3(0, -0.0215, 0)
	add_child(table)

	# The finger first, so every key finds it as its controllers are gathered.
	_tracker = XRPositionalTracker.new()
	_tracker.name = TRACKER
	_tracker.type = XRServer.TRACKER_CONTROLLER
	XRServer.add_tracker(_tracker)
	var origin := XROrigin3D.new()
	add_child(origin)
	var ctrl := XRController3D.new()
	ctrl.tracker = TRACKER
	origin.add_child(ctrl)
	var tip := Node3D.new()
	tip.name = "PokeTip"
	ctrl.add_child(tip)
	var ball := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.0045
	sm.height = 0.009
	ball.mesh = sm
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.93, 0.74, 0.62)
	ball.material_override = skin
	ball.position = Vector3(0, 0.0045, 0)       # the pad of the finger, its lowest point on the tip
	tip.add_child(ball)
	var finger := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0045
	cm.bottom_radius = 0.0045
	cm.height = 0.06
	finger.mesh = cm
	finger.material_override = skin
	finger.position = Vector3(0, 0.0345, 0)
	tip.add_child(finger)
	_move_tip(Vector3(0, 0.06, 0))

	var remote := REMOTE.instantiate() as TVRemote
	remote.freeze = true
	add_child(remote)
	_vp = SubViewport.new()
	_vp.size = Vector2i(1280, 720)
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_cam = Camera3D.new()
	_cam.fov = 28
	_cam.near = 0.005
	_vp.add_child(_cam)
	_cam.look_at_from_position(Vector3(0.1, 0.15, 0.09), Vector3(0.0, 0.0, -0.03))
	await _frames(10)
	for k in KEYS:
		var b := remote.key_button(k)
		_fired[k] = 0
		b.button_pressed.connect(func() -> void: _fired[k] += 1)

	for k in KEYS:
		var b := remote.key_button(k)
		var cap := b.get_node("ButtonMesh") as MeshInstance3D
		var face := cap.global_position
		var rest := face
		await _glide(_tip_pos(), face + Vector3(0, 0.02, 0), 10)
		await _glide(face + Vector3(0, 0.02, 0), face - Vector3(0, TVRemote.KEY_TRAVEL, 0), 6)
		await _hold(8)
		var sank := rest.y - cap.global_position.y
		await _glide(face - Vector3(0, TVRemote.KEY_TRAVEL, 0), face + Vector3(0, 0.025, 0), 6)
		await _hold(3)
		var back := cap.global_position.distance_to(rest)
		_check(absf(sank - TVRemote.KEY_TRAVEL) < 0.0001 and back < 0.00001 and _fired[k] == 1,
			"%s sank %.2f mm, came back, fired %d time(s)" % [k, sank * 1000.0, _fired[k]])
	var others := 0
	for k in _fired:
		others += int(_fired[k])
	_check(others == KEYS.size(), "every poke fired its own key and no other", str(_fired))
	XRServer.remove_tracker(_tracker)
	print("[pokeprobe] frames %d" % _frame)
	print("[pokeprobe] ---- %d failed ----" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


func _tip_pos() -> Vector3:
	return _tracker.get_pose(&"default").transform.origin if _tracker.has_pose(&"default") else Vector3.ZERO


func _move_tip(at: Vector3) -> void:
	_tracker.set_pose(&"default", Transform3D(Basis(), at), Vector3.ZERO, Vector3.ZERO,
		XRPose.XR_TRACKING_CONFIDENCE_HIGH)


func _glide(from: Vector3, to: Vector3, n: int) -> void:
	for i in n:
		var t := float(i + 1) / n
		_move_tip(from.lerp(to, t * t * (3.0 - 2.0 * t)))
		await _shot()


func _hold(n: int) -> void:
	for i in n:
		await _shot()


func _check(ok: bool, what: String, detail := "") -> void:
	if not ok:
		_fails += 1
	print("[pokeprobe] %s %s %s" % ["PASS" if ok else "FAIL", what, detail])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot() -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	img.save_png(_out.path_join("f%04d.png" % _frame))
	_frame += 1
