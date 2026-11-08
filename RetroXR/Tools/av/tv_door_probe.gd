## Films the RETRO XR set's key door (TvKeyDoor) worked by a tracked fingertip, then by the desktop mouse: poked in,
## it unlatches and falls open; pushed up part-way and let go, it falls open again; pushed home, it latches; on the
## desktop a press unlatches it and a drag shuts it. Windowed (the dummy renderer films nothing):
##
##   godot --path RetroXR --resolution 960x540 --position 20,20 res://Tools/av/tv_door_probe.tscn -- --out=<dir>
##
## Writes <dir>/frame_00000.png ...; Tools/art or imageio makes the mp4.
extends Node3D

const FINGER := &"tv_door_probe_finger"

var _out := ""
var _frame := 0
var _finger: XRPositionalTracker
var _caption: Label
var _door: TvKeyDoor
var _tv: Node3D


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.split("=")[1]
	if _out.is_empty():
		_out = OS.get_user_data_dir() + "/tv_door_probe"
	DirAccess.make_dir_recursive_absolute(_out)
	get_tree().create_timer(240.0).timeout.connect(func() -> void:
		print("[doorprobe] TIMEOUT")
		get_tree().quit(1))
	_finger = XRPositionalTracker.new()
	_finger.name = FINGER
	_finger.type = XRServer.TRACKER_CONTROLLER
	XRServer.add_tracker(_finger)
	var origin := XROrigin3D.new()
	add_child(origin)
	var ctrl := XRController3D.new()
	ctrl.tracker = FINGER
	origin.add_child(ctrl)
	var tip := Node3D.new()
	tip.name = "PokeTip"
	ctrl.add_child(tip)
	var ball := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.006
	sphere.height = 0.012
	ball.mesh = sphere
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.95, 0.72, 0.6)
	ball.material_override = skin
	tip.add_child(ball)
	# A finger behind the tip, so it reads as one.
	var shaft := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.0075
	cyl.bottom_radius = 0.0075
	cyl.height = 0.07
	shaft.mesh = cyl
	shaft.material_override = skin
	tip.add_child(shaft)
	shaft.position = Vector3(0, -0.035, 0.0)
	_place(Vector3(0, 4, 0))

	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.16, 0.17, 0.19)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.55, 0.58)
	add_child(env)
	var sun := DirectionalLight3D.new()
	add_child(sun)
	sun.look_at_from_position(Vector3(0.6, 2.0, 1.5), Vector3(0, 1, 0))
	var fill := OmniLight3D.new()
	fill.omni_range = 2.0
	fill.light_energy = 0.8
	add_child(fill)

	# The boot's loading screen draws over every frame otherwise.
	LoadingOverlay.suspend()
	_tv = (load("res://Scenes/Objects/tv.tscn") as PackedScene).instantiate() as Node3D
	_tv.set("tv_model", "retroxr_crt")
	if _tv is RigidBody3D:
		(_tv as RigidBody3D).freeze = true
	add_child(_tv)
	_tv.global_position = Vector3(0, 1, 0)
	var cam := Camera3D.new()
	cam.fov = 40.0
	add_child(cam)
	for i in 6:
		await get_tree().process_frame
	_door = _tv.find_child("KeyDoorHinge", true, false) as TvKeyDoor
	if _door == null:
		print("[doorprobe] FAIL no key door")
		get_tree().quit(1)
		return
	var at := _door.global_position
	cam.look_at_from_position(at + Vector3(0.16, 0.12, 0.36), at + Vector3(-0.01, -0.005, 0))
	cam.current = true
	fill.global_position = at + Vector3(0.1, 0.2, 0.4)
	var layer := CanvasLayer.new()
	add_child(layer)
	_caption = Label.new()
	_caption.position = Vector2(16, 12)
	_caption.add_theme_font_size_override("font_size", 22)
	_caption.add_theme_color_override("font_outline_color", Color.BLACK)
	_caption.add_theme_constant_override("outline_size", 6)
	layer.add_child(_caption)
	await _film()
	print("[doorprobe] wrote %d frames to %s" % [_frame, _out])
	print("[doorprobe] DONE latched=%s deg=%.1f" % [_door.is_latched_closed(), _door.get_rotation_deg()])
	XRServer.remove_tracker(_finger)
	get_tree().quit(0)


func _place(at: Vector3) -> void:
	_finger.set_pose(&"default", Transform3D(Basis(), at), Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)


func _shot(n: int = 1) -> void:
	for i in n:
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/frame_%05d.png" % [_out, _frame])
		_frame += 1


func _on_face(deg: float, out: float, up: float = 0.0) -> Vector3:
	var pivot := _door.target
	var box := ((_door.get_node("CollisionShape3D") as CollisionShape3D).shape as BoxShape3D).size
	var local := _door.position + Vector3(0.02, box.y * 0.5 * up, box.z * 0.5 + out)
	var turned := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(deg)), pivot.position)
	return (pivot.get_parent() as Node3D).global_transform * turned * local


## The finger from where it is to `to` over `frames` frames, a shot each.
func _move(from: Vector3, to: Vector3, frames: int) -> void:
	for i in frames:
		_place(from.lerp(to, float(i + 1) / frames))
		await _shot()


func _arc(from_deg: float, to_deg: float, out: float, frames: int) -> void:
	for i in frames:
		_place(_on_face(lerpf(from_deg, to_deg, float(i + 1) / frames), out, 0.6))
		await _shot()


func _say(text: String) -> void:
	_caption.text = text
	print("[doorprobe] %s (door %.1f deg, latched %s)" % [text, _door.get_rotation_deg(), _door.is_latched_closed()])


func _film() -> void:
	_say("The key door, latched shut")
	await _shot(30)
	_say("A fingertip pushes the shut door in...")
	var start := _on_face(0.0, 0.08)
	_place(start)
	await _move(start, _on_face(0.0, 0.004), 24)
	await _move(_on_face(0.0, 0.004), _on_face(0.0, -0.004), 12)
	_say("...the catch lets go and it falls open")
	await _move(_on_face(0.0, -0.004), _on_face(0.0, 0.10), 20)
	_place(Vector3(0, 4, 0))
	await _shot(30)
	_say("Pushed up part-way and let go: it falls open again")
	_place(_on_face(TvKeyDoor.OPEN_DEG, 0.05, 0.6))
	await _move(_on_face(TvKeyDoor.OPEN_DEG, 0.05, 0.6), _on_face(TvKeyDoor.OPEN_DEG, 0.002, 0.6), 12)
	await _arc(TvKeyDoor.OPEN_DEG, 45.0, 0.001, 24)
	var part := _door.get_rotation_deg()
	await _move(_on_face(part, 0.001, 0.6), _on_face(part, 0.08, 0.6), 8)
	_place(Vector3(0, 4, 0))
	await _shot(36)
	_say("Pushed all the way home: it latches")
	_place(_on_face(TvKeyDoor.OPEN_DEG, 0.05, 0.6))
	await _move(_on_face(TvKeyDoor.OPEN_DEG, 0.05, 0.6), _on_face(TvKeyDoor.OPEN_DEG, 0.002, 0.6), 12)
	await _arc(TvKeyDoor.OPEN_DEG, -6.0, 0.001, 40)
	await _move(_on_face(0.0, 0.001, 0.6), _on_face(0.0, 0.08, 0.6), 12)
	_place(Vector3(0, 4, 0))
	await _shot(30)
	_say("Desktop: a press on the shut door unlatches it")
	var box := _door.get_node("CollisionShape3D") as CollisionShape3D
	var cam := get_viewport().get_camera_3d()
	_door.pointer_event(XRToolsPointerEvent.new(XRToolsPointerEvent.Type.PRESSED, cam, _door, box.global_position,
		box.global_position))
	_door.pointer_event(XRToolsPointerEvent.new(XRToolsPointerEvent.Type.RELEASED, cam, _door, box.global_position,
		box.global_position))
	await _shot(45)
	_say("Desktop: pressed and dragged with the mouse, it shuts and latches")
	_door.pointer_event(XRToolsPointerEvent.new(XRToolsPointerEvent.Type.PRESSED, cam, _door, box.global_position,
		box.global_position))
	for i in 60:
		if _door.is_latched_closed():
			break
		var path: Dictionary = _door.call("_edge_on_screen")
		var ev := InputEventMouseMotion.new()
		ev.relative = -(path["dir"] as Vector2) * 8.0
		get_viewport().push_input(ev)
		await _shot()
	_door.pointer_event(XRToolsPointerEvent.new(XRToolsPointerEvent.Type.RELEASED, cam, _door, box.global_position,
		box.global_position))
	await _shot(40)
