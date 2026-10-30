## A video of the TV remote driven by its own keys, windowed, one PNG a frame at a fixed 30 fps step:
##   godot --path RetroXR res://Tools/av/remote_stick_video_probe.tscn --resolution 320x240 --position 20,20 --fixed-fps 30 -- --out=<dir>
## A tracked hand (a tracker of the probe's own, as tv_remote_tests' stick/ does) holds the remote aimed at the
## RETRO XR set: its stick walks the lit key to VOL-, its click turns the set down twice (the key sinks, the
## volume bar shows), over to VOL+ and up once; turned away from the set, the light goes down onto the ring and
## OK is clicked. Then a still of the remote's own menu with its "Floating button menu" row (menu.png).
extends Node

const REMOTE := preload("res://Scenes/Objects/appliances/tv_remote.tscn")
const TV := preload("res://Scenes/Objects/tv.tscn")
const HAND := &"remote_stick_probe_hand"

var _out := ""
var _view: SubViewport
var _cam: Camera3D
var _n := 0
var _remote: TVRemote
var _tracker: XRPositionalTracker
var _cam_local := Transform3D.IDENTITY


func _ready() -> void:
	get_tree().create_timer(300.0).timeout.connect(func() -> void:
		print("[probe] TIMEOUT")
		get_tree().quit(1))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(_out.path_join("frames"))
	AppPrefs.remote_button_menu = false
	_stage()
	await _run()
	XRServer.remove_tracker(_tracker)
	print("[probe] %d frames" % _n)
	get_tree().quit(0)


func _stage() -> void:
	_view = SubViewport.new()
	_view.size = Vector2i(1280, 720)
	_view.own_world_3d = true
	_view.msaa_3d = Viewport.MSAA_4X
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_view)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.16, 0.17, 0.20)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.57, 0.62)
	env.environment.ambient_light_energy = 1.0
	env.environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	_view.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 25, 0)
	sun.light_energy = 1.8
	sun.shadow_enabled = true
	_view.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8, 8)
	floor_mesh.mesh = plane
	floor_mesh.position = Vector3(0, 0.835, 0)
	_view.add_child(floor_mesh)
	_cam = Camera3D.new()
	_cam.fov = 50
	_view.add_child(_cam)
	_cam.current = true


func _frame() -> void:
	await get_tree().process_frame
	_cam.global_transform = _remote.global_transform * _cam_local
	_view.get_texture().get_image().save_png(_out.path_join("frames/f_%04d.png" % _n))
	_n += 1


func _frames(count: int) -> void:
	for i in count:
		await _frame()


## One push of the stick and back, then a beat to see where the light went.
func _push(dir: Vector2) -> void:
	_tracker.set_input("primary", dir)
	await _frames(3)
	_tracker.set_input("primary", Vector2.ZERO)
	await _frames(12)
	print("[probe] stick %s -> %s" % [dir, _remote.selected_key()])


func _click(hold := 10) -> void:
	_tracker.set_input("primary_click", 1.0)
	await _frames(hold)
	_tracker.set_input("primary_click", 0.0)
	await _frames(14)


func _walk_to(key: String, dir: Vector2, tries := 8) -> void:
	for i in tries:
		if _remote.selected_key() == key:
			return
		await _push(dir)


func _run() -> void:
	_tracker = XRPositionalTracker.new()
	_tracker.name = HAND
	_tracker.type = XRServer.TRACKER_CONTROLLER
	XRServer.add_tracker(_tracker)
	var origin := XROrigin3D.new()
	_view.add_child(origin)
	var ctrl := XRController3D.new()
	ctrl.tracker = HAND
	origin.add_child(ctrl)
	_tracker.set_pose(&"default", Transform3D(Basis(), Vector3(0, -5, 0)), Vector3.ZERO, Vector3.ZERO,
		XRPose.XR_TRACKING_CONFIDENCE_HIGH)

	var tv := TV.instantiate() as RetroTV
	tv.tv_model = "retroxr_crt"
	tv.freeze = true
	tv.position = Vector3(0, 1.0, -1.1)
	_view.add_child(tv)
	_remote = REMOTE.instantiate() as TVRemote
	_remote.freeze = true
	_remote.position = Vector3(0.04, 1.02, 0)
	_view.add_child(_remote)
	for i in 10:
		await get_tree().process_frame
	if not tv.is_on():
		tv.remote_power_toggle()
	_remote._holding_ctrl = ctrl
	# Over the shoulder of the hand: looking down the keypad at the set.
	_cam_local = Transform3D(Basis.looking_at(Vector3(0.0, -0.14, -0.27)), Vector3(0.0, 0.125, 0.15))
	await _frames(30)
	print("[probe] aimed at %s, lit %s" % [_remote._target, _remote.selected_key()])

	await _walk_to("KeyVolDown", Vector2(0, 1))
	await _click()
	await _click()
	await _push(Vector2(1, 0))
	await _walk_to("KeyVolUp", Vector2(1, 0))
	await _click(12)
	print("[probe] volume now %.2f" % tv.volume())
	await _frames(20)

	# Turned away from the set: aimed at nothing, every key is live, and the light goes down onto the ring.
	for i in 30:
		_remote.rotation.y = deg_to_rad(lerpf(0.0, 75.0, float(i) / 29.0))
		await _frame()
	await _frames(10)
	print("[probe] turned away, aimed at %s" % _remote._target)
	for i in 10:
		if _remote.selected_key() == "KeyOk" or TVRemote.RING_DIRS.has(_remote.selected_key()):
			break
		await _push(Vector2(0, -1))
	# Round the ring: in to OK, up, left (round it, not off it), back to OK, and click.
	await _walk_to("KeyOk", Vector2(-1, 0), 2)
	await _push(Vector2(0, 1))
	await _push(Vector2(-1, 0))
	await _push(Vector2(1, 0))
	await _click()
	await _frames(20)

	# The remote's own menu, with the row that brings the floating grid back.
	_remote.rotation.y = 0.0
	ObjectOptionsPanel.toggle_for(_remote, _cam)
	await _frames(10)
	_cam.global_transform = Transform3D(Basis.looking_at(Vector3(0, 0.08, -0.6)), _remote.global_position + Vector3(0, 0.2, 0.55))
	for i in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_view.get_texture().get_image().save_png(_out.path_join("menu.png"))
	print("[probe] menu still written")
