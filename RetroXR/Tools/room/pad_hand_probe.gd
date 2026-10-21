## The first gamepad working the desktop hand, through the real room (DesktopPad).
##
## No pad is attached, so one is declared (`pads_override`) and its events are handed to the
## DesktopPad autoload; what is checked is what the REAL DesktopPickup does with the mouse events
## the pad makes: D-pad down pulls an object in and catches it, LT + the right stick turns it, D-pad
## up lets it back out, RT clicks it away. WINDOWED, scratch XDG_DATA_HOME:
##
##     XDG_DATA_HOME=/tmp/scratch "$godot" --path RetroXR --resolution 1280x720 \
##         res://Tools/room/pad_hand_probe.tscn
extends Node

const SCENE := preload("res://Scenes/BedroomScene.tscn")
const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const PAD := 7

var _pad: DesktopPadService


func _ready() -> void:
	get_tree().create_timer(150.0).timeout.connect(func() -> void: get_tree().quit(1))
	add_child(SCENE.instantiate())
	await get_tree().create_timer(10.0).timeout
	_pad = DesktopPad
	_pad.pads_override = [PAD]
	_pad.xr_override = false
	await get_tree().process_frame
	await get_tree().process_frame
	print("[padhand] main pad %d" % _pad.main_device)
	var cam := get_viewport().get_camera_3d()
	# The left stick walks: pushed forward as the engine would deliver it (the event goes through
	# Input, so the InputMap actions answer), the player must move; the control is no push at all.
	# The boot (xr_init) and picking a controller up both reload the InputMap from the project
	# settings; the pad's events must survive that.
	DesktopBindings.load_and_apply()
	var start := cam.global_position
	await get_tree().create_timer(1.0).timeout
	var still := cam.global_position.distance_to(start)
	start = cam.global_position
	_engine_axis(JOY_AXIS_LEFT_Y, -1.0)
	await get_tree().create_timer(1.5).timeout
	_engine_axis(JOY_AXIS_LEFT_Y, 0.0)
	await get_tree().create_timer(0.3).timeout
	print("[padhand] walking: no push moved the player %.3f m, the left stick forward for 1.5 s %.3f m (action %s)" % [
		still, cam.global_position.distance_to(start), Input.get_action_strength("desktop_move_forward")])
	var sys := SYSTEM_SCENE.instantiate() as RetroSystem
	sys.systemid = "gba"
	sys.ignore_gravity = true
	get_tree().current_scene.add_child(sys)
	sys.add_to_group("spawned")
	await get_tree().create_timer(3.0).timeout
	sys.global_position = cam.global_position - cam.global_transform.basis.z * 0.45
	cam.call("grab_spawned", sys)
	await get_tree().create_timer(1.0).timeout
	print("[padhand] held %s at %.3f m" % [cam.call("held_object") != null, float(cam.get("_grab_dist"))])

	# D-pad down, tapped: pulls it in, then the catch.
	var taps := 0
	while not bool(cam.get("_hand_hold")) and taps < 60:
		_tap(JOY_BUTTON_DPAD_DOWN)
		taps += 1
		await get_tree().create_timer(0.08).timeout
	await get_tree().create_timer(0.6).timeout
	print("[padhand] D-pad down %d taps: caught %s, held %s" % [taps, cam.get("_hand_hold"), cam.call("held_object") != null])

	# LT held and the right stick pushed: turns it in the hand.
	var before: Basis = cam.get("_hand_cam_basis")
	var cam_before := cam.global_basis
	_axis(JOY_AXIS_TRIGGER_LEFT, 1.0)
	_axis(JOY_AXIS_RIGHT_X, 1.0)
	await get_tree().create_timer(1.0).timeout
	_axis(JOY_AXIS_RIGHT_X, 0.0)
	_axis(JOY_AXIS_TRIGGER_LEFT, 0.0)
	await get_tree().create_timer(0.3).timeout
	var turned := rad_to_deg(before.get_rotation_quaternion().angle_to((cam.get("_hand_cam_basis") as Basis).get_rotation_quaternion()))
	var looked := rad_to_deg(cam_before.get_rotation_quaternion().angle_to(cam.global_basis.get_rotation_quaternion()))
	print("[padhand] LT + right stick for a second: the object turned %.1f deg, the camera %.1f deg (want ~0), held %s" % [
		turned, looked, cam.call("held_object") != null])

	# The right stick alone looks round.
	_axis(JOY_AXIS_RIGHT_X, 1.0)
	await get_tree().create_timer(1.0).timeout
	_axis(JOY_AXIS_RIGHT_X, 0.0)
	await get_tree().create_timer(0.3).timeout
	print("[padhand] the right stick alone for a second: the camera turned %.1f deg" % rad_to_deg(
		cam_before.get_rotation_quaternion().angle_to(cam.global_basis.get_rotation_quaternion())))

	# D-pad up: out of the hand.
	_tap(JOY_BUTTON_DPAD_UP)
	await get_tree().create_timer(0.5).timeout
	print("[padhand] D-pad up: in the hand %s, held %s" % [cam.get("_hand_hold"), cam.call("held_object") != null])

	# RT: a click with the crosshair on nothing lets go on release.
	cam.rotation = Vector3(deg_to_rad(60.0), cam.rotation.y, 0.0)
	await get_tree().create_timer(0.5).timeout
	_axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)
	await get_tree().create_timer(0.2).timeout
	var held_down: bool = cam.call("held_object") != null
	_axis(JOY_AXIS_TRIGGER_RIGHT, 0.0)
	await get_tree().create_timer(0.5).timeout
	print("[padhand] RT: held while down %s, after release %s" % [held_down, cam.call("held_object") != null])

	# The keyboard takes over at once, and the prompts with it.
	print("[padhand] last device: pad %s" % _pad.last_is_pad)
	var key := InputEventKey.new()
	key.keycode = KEY_W
	key.pressed = true
	Input.parse_input_event(key)
	await get_tree().process_frame
	await get_tree().process_frame
	print("[padhand] after a key: pad %s" % _pad.last_is_pad)
	_pad.pads_override = null
	_pad.xr_override = null
	get_tree().quit(0)


func _tap(button: int) -> void:
	for pressed in [true, false]:
		var e := InputEventJoypadButton.new()
		e.device = PAD
		e.button_index = button
		e.pressed = pressed
		_pad.handle_event(e)
		await get_tree().process_frame


func _axis(axis: int, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = PAD
	e.axis = axis
	e.axis_value = value
	_pad.handle_event(e)


## As the engine delivers a real pad's stick: through Input, so actions and everything else hear it.
func _engine_axis(axis: int, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = PAD
	e.axis = axis
	e.axis_value = value
	Input.parse_input_event(e)
	_pad.handle_event(e)
