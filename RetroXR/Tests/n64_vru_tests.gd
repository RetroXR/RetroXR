## Voice Recognition Unit self-tests — the NUS-020 in a socket, headless.
##
##     "$godot" --headless --path RetroXR res://Tests/n64_vru_tests.tscn
##     "$godot" --headless --path RetroXR res://Tests/n64_vru_tests.tscn -- --only=seat
##
## Exits 0 when everything passes, 1 otherwise.
##
## What a core does with the device it is told about needs mupen64plus-next, a
## speech model and a ROM, and lives in Tools/input/vru_probe.
extends Node

const VRU_SCENE := preload("res://Scenes/Objects/controllers/n64/n64_vru.tscn")

var _pass := 0
var _fail := 0
var _only := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.substr(7)
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("[vru] TIMEOUT")
		get_tree().quit(1))

	if _wants("device"):
		await _test_device()
	if _wants("seat"):
		await _test_seat()
	if _wants("mic"):
		await _test_mic()
	if _wants("catalog"):
		_test_catalog()
	if _wants("persist"):
		await _test_persist()

	print("[vru] ---- %d passed, %d failed ----" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _wants(group: String) -> bool:
	return _only.is_empty() or _only == group


func _ok(cond: bool, test_name: String, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("[vru] PASS  %s" % test_name)
	else:
		_fail += 1
		print("[vru] FAIL  %s%s" % [test_name, "  — " + detail if not detail.is_empty() else ""])


## A unit with its cord and microphone grown, as it is one frame after spawning.
func _spawn_unit() -> N64Vru:
	var unit := VRU_SCENE.instantiate() as N64Vru
	add_child(unit)
	for i in range(3):
		await get_tree().process_frame
	return unit


func _spawn_n64() -> RetroSystem:
	var sys := preload("res://Scenes/Objects/system.tscn").instantiate() as RetroSystem
	sys.systemid = "nintendo_64"
	add_child(sys)
	await get_tree().process_frame
	return sys


## Which way the cord leaves the body, which is not something a look settles:
## a rope exits a directional endpoint along its local -Z BY DEFAULT, and both
## microphones are built nose-at-minus-Z with the cord boss at plus-Z. Left at
## the default the cord came out of the grille and doubled back through the
## body, and the only honest oracle is the sign of this dot.
func _check_cord(what: String, rope: VerletRope, host: Node3D,
		nose_local: Vector3, boss_local: Vector3) -> void:
	var basis := host.global_transform.basis.orthonormalized()
	var exit: Vector3 = (basis * Vector3(rope.start_exit_axis)).normalized()
	var body_dir: Vector3 = (basis * (boss_local - nose_local)).normalized()
	var d := exit.dot(body_dir)
	_ok(d > 0.5, "%s the cord leaves away from the nose, not back through it" % what,
		"dot %+.2f" % d)
	var end_exit: Vector3 = Vector3(rope.end_exit_axis).normalized()
	_ok(end_exit.dot(Vector3(0, 0, 1)) > 0.5,
		"%s and so does the end a hand is holding" % what, str(end_exit))


func _test_device() -> void:
	var unit := await _spawn_unit()

	# RETRO_DEVICE_SUBCLASS(RETRO_DEVICE_JOYPAD, 0): the subclass in the high
	# byte, the base device in the low one. The core fork reads the same number.
	_ok(N64Vru.DEVICE_VRU == (1 << 8) | 1, "device/the id is a joypad subclass",
		str(N64Vru.DEVICE_VRU))
	_ok(unit.device_type == N64Vru.DEVICE_VRU, "device/the unit announces it")
	_ok(unit.systemid == "nintendo_64", "device/it only fits an N64")
	_ok(unit.is_in_group("controller_plug"), "device/it is what a socket filters on")
	_ok(unit.is_in_group("n64_vru"), "device/and has its own group")
	_ok(unit.get_mic() != null, "device/the cord and microphone grew")

	unit.drop_and_free()
	await get_tree().process_frame


func _test_seat() -> void:
	var sys := await _spawn_n64()
	var unit := await _spawn_unit()

	sys.restore_controller_plug(3, unit)
	await get_tree().process_frame

	_ok(unit.seated_system == sys and unit.seated_port_index == 3,
		"seat/socket 4 takes it and it knows where it is",
		"%s %d" % [unit.seated_system, unit.seated_port_index])
	_ok(sys.get_port_controllers()[3] == unit, "seat/the console holds it on that port")

	unit.on_unplugged()
	_ok(unit.seated_system == null and unit.seated_port_index == -1,
		"seat/pulled out, it knows that too")

	sys.queue_free()
	unit.drop_and_free()
	await get_tree().process_frame


func _test_mic() -> void:
	var sys := await _spawn_n64()
	var unit := await _spawn_unit()
	sys.restore_controller_plug(3, unit)
	await get_tree().process_frame

	var mic := unit.get_mic()
	mic.global_position = sys.global_position + Vector3(0, 1.2, 0.8)
	await get_tree().process_frame

	_ok(unit.microphone_position().is_equal_approx(mic.global_position),
		"mic/the unit hears from the microphone, not the box")
	_ok(sys.microphone_position().is_equal_approx(mic.global_position),
		"mic/and so does the machine it is seated in",
		"%s vs %s" % [sys.microphone_position(), mic.global_position])

	# The box: its connector tongue is at -Z and its cord boss at +Z.
	var rope: VerletRope = null
	for n: Node in get_tree().current_scene.find_children("*", "VerletRope", true, false):
		if n.get_parent() != null and String(n.get_parent().name).contains("Vru"):
			rope = n as VerletRope
	if rope != null:
		_check_cord("mic/", rope, unit.get_node("CableAttachPoint"),
			Vector3(0, 0, -0.023), Vector3(0, 0, 0.041))
	else:
		_ok(false, "mic/the unit built its cord")

	sys.queue_free()
	unit.drop_and_free()
	await get_tree().process_frame


func _test_catalog() -> void:
	var rows: Array = SpawnCatalog.items_for("nintendo_64")
	var found := false
	for row: Variant in rows:
		if SpawnCatalog.spawn_token("nintendo_64", row as Dictionary) == "n64_vru":
			found = true
	_ok(found, "catalog/the N64 card offers a Voice Recognition Unit")
	_ok(ScenePersistence.PLAIN_SCENES.has("n64_vru"),
		"catalog/and a saved room knows how to build one")


func _test_persist() -> void:
	const SLOT := "__vru_selftest"
	var slot_file := "user://scenes/arcade/%s.json" % SLOT
	get_tree().current_scene = self

	var sys := await _spawn_n64()
	sys.add_to_group("spawned")
	var unit := await _spawn_unit()
	sys.restore_controller_plug(3, unit)
	await get_tree().process_frame

	var sp := ScenePersistence.new("arcade")
	_ok(sp.save_slot(self, SLOT), "persist/the room saves")

	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(slot_file))
	var entry: Dictionary = {}
	if raw is Dictionary:
		for o: Variant in (raw as Dictionary).get("objects", []):
			if str((o as Dictionary).get("type", "")) == "n64_vru":
				entry = o as Dictionary
	_ok(int(entry.get("port", -1)) == 3 and entry.get("system") != null,
		"persist/the unit records socket 4 of its console", str(entry.get("port", -1)))

	sp.clear_scene(self)
	for i in range(20):
		await get_tree().physics_frame
	await sp.load_slot_async(self, SLOT)
	for i in range(40):
		await get_tree().physics_frame

	var back_unit: N64Vru = null
	var back_sys: RetroSystem = null
	for n in get_tree().get_nodes_in_group("spawned"):
		if n is N64Vru:
			back_unit = n as N64Vru
		elif n is RetroSystem:
			back_sys = n as RetroSystem
	_ok(back_unit != null and back_sys != null and back_unit.seated_system == back_sys
			and back_unit.seated_port_index == 3,
		"persist/and comes back in that socket")

	sp.clear_scene(self)
	for i in range(10):
		await get_tree().physics_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(slot_file))
