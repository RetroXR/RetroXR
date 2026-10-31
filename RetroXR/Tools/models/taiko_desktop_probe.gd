## A Taiko drummer's sticks through the REAL desktop hand (DesktopPickup on the player's camera) in a bare room with the player rig, the way a player takes them with the mouse: the crosshair on the first player's
## left stick in its cradle, a click to take it (its mate arrives in the lower left), the mouse hitting the drum (left a don, right a ka, the two taking turns), a Shift click to let go, and
## the sticks going home. WINDOWED, never --headless (the dummy renderer returns a correctly sized BLANK image), a scratch data root:
##
##   XDG_DATA_HOME=/tmp/scratch "$godot" --path RetroXR --resolution 1280x720 res://Tools/models/taiko_desktop_probe.tscn -- --out=/some/dir
##
## Prints `[taiko] ...` lines and writes taiko_aim.png (the crosshair on the stick), taiko_held.png (both in the hands), taiko_swing.png (a click, a few frames in) and taiko_home.png.
extends Node

const RIG := preload("res://Scenes/player_rig.tscn")
const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")

var _out := "/tmp"
var _cam: Camera3D
var _sys: RetroSystem
var _input: ArcadeInput
var _failed := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	get_tree().create_timer(170.0).timeout.connect(func() -> void:
		print("[taiko] TIMED OUT")
		get_tree().quit(1))
	_build_room()
	await get_tree().create_timer(4.0).timeout
	_cam = get_viewport().get_camera_3d()
	await _run()
	print("[taiko] RESULT=%s" % ("PASS" if _failed == 0 else "FAIL"))
	get_tree().quit(1 if _failed > 0 else 0)


## A floor, a light and the player rig (with its desktop hand) -- what a room is to this probe.
func _build_room() -> void:
	var init := Node3D.new()
	init.name = "XrInit"
	init.set_script(load("res://Scripts/XR/xr_init.gd"))
	add_child(init)
	var env := WorldEnvironment.new()
	var look := Environment.new()
	look.background_mode = Environment.BG_COLOR
	look.background_color = Color(0.05, 0.05, 0.07)
	look.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	look.ambient_light_color = Color(0.75, 0.77, 0.85)
	look.ambient_light_energy = 0.7
	env.environment = look
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	add_child(sun)
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 0.2, 20.0)
	shape.shape = box
	floor_body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var slab := BoxMesh.new()
	slab.size = box.size
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.32, 0.30, 0.28)
	slab.material = paint
	mesh.mesh = slab
	floor_body.add_child(mesh)
	floor_body.position = Vector3(0.0, -0.1, 0.0)
	add_child(floor_body)
	var rig := RIG.instantiate() as Node3D
	rig.position = Vector3(0.0, 0.0, 0.8)
	add_child(rig)


func _ok(ok: bool, what: String) -> void:
	if not ok:
		_failed += 1
	print("[taiko] %s  %s" % ["PASS" if ok else "FAIL", what])


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## Physics steps, not seconds: a software renderer draws a few frames a second, and what a timer counts is wall clock.
func _phys(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join(name + ".png"))


func _mouse(button: int, pressed: bool, shift: bool = false) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.shift_pressed = shift
	e.position = get_viewport().get_visible_rect().size * 0.5
	e.global_position = e.position
	Input.parse_input_event(e)


func _click(button: int, shift: bool = false) -> void:
	_mouse(button, true, shift)
	await _frames(1)
	_mouse(button, false, shift)


func _tapped() -> Array:
	var held: Array = []
	for port: Variant in _input._taps.keys():
		for bit: Variant in (_input._taps[port] as Dictionary).keys():
			held.append("%d:%d" % [int(port), int(bit)])
	held.sort()
	return held


func _stick(player: int, side: int) -> ArcadeDrumstick:
	for piece: Variant in _sys.captive_gear():
		var stick := piece as ArcadeDrumstick
		if stick != null and stick.player == player and stick.side == side:
			return stick
	return null


func _run() -> void:
	# A Taiko cabinet on the floor, wearing its form (a board in the bay would do the same), switched on.
	_sys = SYSTEM_SCENE.instantiate() as RetroSystem
	_sys.model_id = ArcadeProfiles.CABINET_MODEL_ID
	_sys.systemid = "arcade"
	_sys.freeze = true
	get_tree().current_scene.add_child(_sys)
	_sys.add_to_group("spawned")
	await get_tree().create_timer(3.0).timeout
	var model := _sys.get_model() as RetroSystemModelArcadeCabinet
	var base := ArcadeCabinetSpecs.variant("generic")
	base["variant"] = "generic"
	var profile := ArcadeGameProfile.for_romset("taiko6")
	model.morph_to(ArcadeCabinetSpecs.for_game(base, profile))
	model.apply_game_profile(profile)
	await get_tree().create_timer(1.5).timeout
	_sys.is_powered_on = true
	_input = model.arcade_input()
	var left := _stick(0, 0)
	var right := _stick(0, 1)
	_ok(left != null and right != null, "the form brought the first player's pair")
	if left == null or right == null:
		return
	# Stand the cabinet so the first player's left stick lies under the crosshair, 55 cm ahead of the feet and looking down at it, front toward the camera.
	var seat_local := _sys.global_transform.affine_inverse() * left.global_position
	var ahead := -_cam.global_basis.z
	ahead.y = 0.0
	ahead = ahead.normalized()
	var reach := 0.55
	var down := atan2(_cam.global_position.y - seat_local.y, reach)
	var basis := Basis.looking_at(ahead, Vector3.UP)
	var seat_world := _cam.global_position + ahead * reach + Vector3(0.0, seat_local.y - _cam.global_position.y, 0.0)
	_sys.global_transform = Transform3D(basis, seat_world - basis * seat_local)
	_cam.global_basis = Basis.looking_at(ahead * cos(down) + Vector3.DOWN * sin(down), Vector3.UP)
	# The gear was built where the cabinet stood: build it again where it stands.
	_sys._free_captive_gear()
	_sys._spawn_captive_gear()
	await get_tree().create_timer(1.0).timeout
	left = _stick(0, 0)
	right = _stick(0, 1)
	var ray_dir := -_cam.global_basis.z
	print("[taiko] camera %s looks %s; the left stick lies at %s (%.3f m off the crosshair's ray)" % [str(_cam.global_position), str(ray_dir), str(left.global_position),
		Geometry3D.get_closest_point_to_segment_uncapped(left.global_position, _cam.global_position, _cam.global_position + ray_dir).distance_to(left.global_position)])
	await _shot("taiko_aim")
	# Take it with a click: the crosshair is on it.
	await _click(MOUSE_BUTTON_LEFT)
	await _phys(40)
	_ok(_cam.call("held_object") == left, "a click on the left stick in its cradle takes it into the desktop hand (held: %s)" % str(_cam.call("held_object")))
	_ok(right.is_picked_up() and right.held_by_desktop(), "and its mate comes to the other hand")
	_ok(ArcadeDrumstick._leader == left, "the first is the one that reads the mouse")
	_ok(_input.engaged(), "the cabinet has somebody at it")
	var offset_l := _cam.global_transform.affine_inverse() * left.global_position
	var offset_r := _cam.global_transform.affine_inverse() * right.global_position
	print("[taiko] in the camera's frame: left stick %s, right stick %s" % [str(offset_l), str(offset_r)])
	_ok(offset_l.x > 0.05 and offset_r.x < -0.05 and offset_l.z < 0.0 and offset_r.z < 0.0, "one rides in the lower right of the view and one in the lower left, ahead of the eye")
	await _shot("taiko_held")
	# The mouse: left a don, right a ka, the two sticks taking turns.
	_input._taps.clear()
	await _click(MOUSE_BUTTON_LEFT)
	var first := _tapped()
	_input._taps.clear()
	await _frames(1)
	await _click(MOUSE_BUTTON_LEFT)
	var second := _tapped()
	_ok(first == ["0:%d" % ArcadeProfiles.button_bit(3)] and second == ["0:%d" % ArcadeProfiles.button_bit(2)], "left click: a don on the left half of the face (BUTTON3), then on the right (BUTTON2) (%s then %s)" % [str(first), str(second)])
	_input._taps.clear()
	await _click(MOUSE_BUTTON_RIGHT)
	var ka_first := _tapped()
	_input._taps.clear()
	await _frames(1)
	await _click(MOUSE_BUTTON_RIGHT)
	var ka_second := _tapped()
	_ok(ka_first == ["0:%d" % ArcadeProfiles.button_bit(4)] and ka_second == ["0:%d" % ArcadeProfiles.button_bit(1)], "right click: a ka on the left half of the rim (BUTTON4), then on the right (BUTTON1) (%s then %s)" % [str(ka_first), str(ka_second)])
	await _phys(40)
	await _click(MOUSE_BUTTON_LEFT)
	await _frames(1)
	await _shot("taiko_swing")
	_ok(_cam.call("held_object") == left and left.is_picked_up(), "clicking does not let go of the sticks")
	# Shift + click lets go: the sticks fall and hang on their cords.
	await _click(MOUSE_BUTTON_LEFT, true)
	await _phys(150)
	_ok(_cam.call("held_object") == null and not left.held_by_desktop() and not right.held_by_desktop(), "Shift + click lets go of both")
	_ok(left.global_position.y < 0.2 and right.global_position.y < 0.2, "and both fall: neither hangs in the air (left y %.3f, right y %.3f)" % [left.global_position.y, right.global_position.y])
	await _shot("taiko_home")
