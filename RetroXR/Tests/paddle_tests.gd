## The Atari 2600's CX30 paddles (Atari2600CX30): a pair on one plug, on a real
## console with Stella's device lists. Headless, no core: what the core would be
## sent is read off each paddle's last frame.
##
##     "$godot" --headless --path RetroXR res://Tests/paddle_tests.tscn
##
## Groups:
##   pair/   the lead builds its partner, whose cord ends in the lead's plug
##   ports/  the left jack is libretro ports 0 and 1, the right 2 and 3; the jack is
##           announced as Stella's Paddles
##   knob/   a stick turns the knob, which stops at its ends; what is sent is where
##           it is; any face button fires; the D-pad turns it too
##   save/   the partner's place and both knobs come back from the lead's entry; the
##           partner goes when the lead does
##   core/   Stella is pinned to an absolute axis with no deadzone
extends "res://Tests/test_suite.gd"

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const PADDLES_SCENE := preload("res://Scenes/Objects/controllers/atari/atari_2600_cx30.tscn")

## Stella's two jacks as it declares them (libretro.cxx controllers[]).
const STELLA_PADDLES := 1281
const STELLA_PORTS: Array = [
	{"port": 0, "controllers": [{"name": "Automatic", "id": 1}, {"name": "Joystick", "id": 257},
		{"name": "Paddles", "id": 1281}]},
	{"port": 1, "controllers": [{"name": "Automatic", "id": 1}, {"name": "Joystick", "id": 257},
		{"name": "Paddles", "id": 1281}]},
]

var _spawned: Array[Node] = []


func _ready() -> void:
	suite_tag = "paddle"
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		print("[paddle] TIMED OUT")
		get_tree().quit(1))
	get_tree().current_scene = self
	await _group_pair_and_ports()
	await _group_save()
	_group_core()
	await _clear()
	_finish()


func _group_pair_and_ports() -> void:
	var sys := await _console(Vector3(0, 1, 0))
	var lead := _make(Vector3(0, 1, 0.5)) as Atari2600CX30
	await _wait(6)
	var partner := lead.get_partner()
	_ok(partner != null and partner.is_partner, "pair/the lead builds its partner")
	if partner == null:
		return
	_ok(not partner.is_in_group("spawned") and lead.is_in_group("spawned"),
		"pair/the partner is the lead's, not an object a save sweeps up")
	var plug := lead.get_plug()
	_ok(plug != null, "pair/the lead has the plug")
	var rope := partner.get("_cable_rope") as VerletRope
	_ok(rope != null and rope.end_node == plug, "pair/the partner's cord ends in the lead's plug")
	_eq(partner.get_plug(), null, "pair/the partner has no plug of its own")

	# Unplugged: nowhere to send.
	_eq(lead._lib_port(), -1, "ports/unplugged, the lead reaches no port")
	_eq(partner._lib_port(), -1, "ports/nor does the partner")

	sys.restore_controller_plug(0, plug)
	await _wait(4)
	_eq([lead._lib_port(), partner._lib_port()], [0, 1], "ports/in the left jack, paddles A and B are ports 0 and 1")
	_eq(_id(sys, 0), STELLA_PADDLES, "ports/and the jack is announced as Stella's Paddles")
	await _wait(2)
	_eq(int(lead.last_sent.get("port", -1)), 0, "ports/the lead's frames go to port 0")
	_eq(int(partner.last_sent.get("port", -1)), 1, "ports/the partner's to port 1")

	# Knob: a full stick to the right for half a second turns it clockwise.
	lead.knob_angle = 0.0
	for i in 30:
		lead._send_joypad(0, 0x7fff, 0, 0, 0)
		await get_tree().process_frame
	_ok(lead.knob_angle > 0.3, "knob/a stick to the right turns it clockwise", "%.3f rad" % lead.knob_angle)
	var pad: Dictionary = lead.last_sent.get("pad", {})
	_eq(int(pad.get("alx", 0)), lead._knob_axis(), "knob/what is sent is where it is")
	_ok(int(pad.get("alx", 0)) > 0, "knob/clockwise is a positive axis")
	for i in 200:
		lead._send_joypad(0, 0x7fff, 0, 0, 0)
		await get_tree().process_frame
	_ok(is_equal_approx(lead.knob_angle, Atari2600CX30.KNOB_HALF_TURN), "knob/it stops at its end")
	_eq(int((lead.last_sent["pad"] as Dictionary)["alx"]), 0x7fff, "knob/and at its end the axis is full")
	var before := lead.knob_angle
	lead._send_joypad(0, 0, 0, 0, 0)
	_eq(lead.knob_angle, before, "knob/let go, it stays where it was")
	lead._send_joypad(1 << ControllerBindings.JOYPAD_A, 0, 0, 0, 0)
	_eq(int((lead.last_sent["pad"] as Dictionary)["btn"]), 1 << ControllerBindings.JOYPAD_B,
		"knob/any face button fires, sent as B")
	for i in 10:
		lead._send_joypad(1 << ControllerBindings.JOYPAD_LEFT, 0, 0, 0, 0)
		await get_tree().process_frame
	_ok(lead.knob_angle < before, "knob/the D-pad's left turns it back")
	_eq(int((lead.last_sent["pad"] as Dictionary)["btn"]), 0, "knob/and the D-pad does not fire")

	# The right jack: ports 2 and 3.
	(sys.controller_ports().zones[0] as XRToolsSnapZone).drop_object()
	await _wait(3)
	sys.restore_controller_plug(1, plug)
	await _wait(4)
	_eq([lead._lib_port(), partner._lib_port()], [2, 3], "ports/in the right jack, they are ports 2 and 3")
	_eq(_id(sys, 1), STELLA_PADDLES, "ports/and the right jack is announced as Paddles")


func _group_save() -> void:
	await _clear()
	var lead := _make(Vector3(0, 1, 0.5)) as Atari2600CX30
	await _wait(4)
	var partner := lead.get_partner()
	if partner == null:
		_ok(false, "save/a partner to save")
		return
	partner.global_position = Vector3(0.4, 1.2, 0.3)
	partner.knob_angle = -0.5
	lead.knob_angle = 0.25
	var pose := lead.partner_pose()
	lead.queue_free()
	await _wait(3)
	_ok(not is_instance_valid(partner), "save/the partner goes when the lead does")

	var again := _make(Vector3(0, 1, 0.5)) as Atari2600CX30
	# As a load does: the entry is handed over before the partner exists.
	again.restore_partner(pose)
	await _wait(4)
	var back := again.get_partner()
	# Across the floor: it is not frozen, so it has begun to fall.
	_ok(back != null and Vector2(back.global_position.x - 0.4, back.global_position.z - 0.3).length() < 0.001,
		"save/the partner comes back where it was", str(back.global_position if back else null))
	_ok(back != null and is_equal_approx(back.knob_angle, -0.5), "save/with its knob where it was")
	_ok(is_equal_approx(again.knob_angle, 0.25), "save/and the lead's knob")
	var entry_has := ScenePersistence.CONTROLLER_SCENES.has(PADDLES_SCENE.resource_path)
	_ok(entry_has, "save/the scene is one a load restores")


func _group_core() -> void:
	var opts := ForcedCoreOptions.all("stella", "atari2600", "", [], "", [] as Array[bool], "")
	_eq(opts.get("stella_paddle_analog_absolute"), "enabled", "core/Stella reads the axis as a position")
	_eq(opts.get("stella_paddle_analog_deadzone"), "0", "core/with no deadzone")
	_ok(not ForcedCoreOptions.all("stella2014", "atari2600", "", [], "", [] as Array[bool], "")
		.has("stella_paddle_analog_absolute"), "core/and only on the core that has the option")


# ── helpers ─────────────────────────────────────────────────────────────────

func _console(at: Vector3) -> RetroSystem:
	var sys := SYSTEM_SCENE.instantiate() as RetroSystem
	sys.systemid = "atari2600"
	sys.position = at
	sys.freeze = true
	add_child(sys)
	_spawned.append(sys)
	await _wait(20)
	sys.controller_ports().controller_info = STELLA_PORTS.duplicate(true)
	return sys


func _make(at: Vector3) -> Node3D:
	var obj := PADDLES_SCENE.instantiate() as Node3D
	obj.position = at
	(obj as RigidBody3D).freeze = true
	add_child(obj)
	_spawned.append(obj)
	return obj


func _id(sys: RetroSystem, port: int) -> int:
	for e: Dictionary in sys.controller_ports().controller_info:
		if int(e.get("port", -1)) == port:
			return int(e.get("current_id", -1))
	return -1


func _wait(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _clear() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			n.queue_free()
	_spawned.clear()
	await _wait(3)
