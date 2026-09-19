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

	if _wants("faces"):
		_test_faces()
	if _wants("device"):
		await _test_device()
	if _wants("seat"):
		await _test_seat()
	if _wants("jack"):
		await _test_jack()
	if _wants("mic"):
		await _test_mic()
	if _wants("drop"):
		await _test_drop()
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
	sys.systemid = "n64"
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


## Where a mesh's FLAT faces are, in `root`'s own frame: a box's six, a cylinder's
## two caps. A sphere or a capsule has none, which is the whole reason a microphone
## head is built out of one.
##
## Read off the packed scene rather than a live object, and composed from local
## transforms rather than global ones: an object in the tree has grown a
## PickableHighlight overlay per mesh by now, and those carry copies of the very
## geometry this is comparing.
func _flat_faces(root: Node3D) -> Array:
	var out: Array = []
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var planes: Array = []
		if mi.mesh is BoxMesh:
			var half: Vector3 = (mi.mesh as BoxMesh).size * 0.5
			planes = [[Vector3.RIGHT, half.x], [Vector3.LEFT, half.x],
				[Vector3.UP, half.y], [Vector3.DOWN, half.y],
				[Vector3.BACK, half.z], [Vector3.FORWARD, half.z]]
		elif mi.mesh is CylinderMesh:
			var cyl := mi.mesh as CylinderMesh
			if not cyl.cap_top and not cyl.cap_bottom:
				continue
			planes = [[Vector3.UP, cyl.height * 0.5], [Vector3.DOWN, cyl.height * 0.5]]
		else:
			continue
		var t := _to_root(root, mi)
		var box: AABB = t * mi.mesh.get_aabb()
		for plane: Array in planes:
			var axis: Vector3 = plane[0]
			var normal: Vector3 = (t.basis * axis).normalized()
			var point: Vector3 = t * (axis * float(plane[1]))
			out.append({"node": String(mi.name), "normal": normal,
				"d": normal.dot(point), "box": box})
	return out


## A node's transform in `root`'s frame, walked up by hand so this works on a scene
## that was never added to the tree.
func _to_root(root: Node3D, node: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var n: Node3D = node
	while n != null and n != root:
		t = n.transform * t
		n = n.get_parent() as Node3D
	return t


## Two faces in one plane FACING THE SAME WAY fight for the same depth values, and
## the loser flickers through the winner — on the microphone's nose that is a black
## grille disc and a white body disc trading pixels, which draws as a pinwheel
## because a cylinder cap is a triangle fan.
##
## Two faces in a plane facing OPPOSITE ways are a butt joint and are left alone:
## back-face culling draws one of them and the other never competes.
func _coplanar_pairs(root: Node3D) -> Array:
	var faces := _flat_faces(root)
	var hits: Array = []
	for i in range(faces.size()):
		for j in range(i + 1, faces.size()):
			var a: Dictionary = faces[i]
			var b: Dictionary = faces[j]
			if str(a["node"]) == str(b["node"]):
				continue
			if (a["normal"] as Vector3).dot(b["normal"] as Vector3) < 0.999:
				continue
			if absf(float(a["d"]) - float(b["d"])) > 0.00005:
				continue
			if not (a["box"] as AABB).grow(0.0005).intersects(b["box"] as AABB):
				continue
			hits.append("%s|%s at %.4f" % [a["node"], b["node"], float(a["d"])])
	return hits


func _test_faces() -> void:
	var unit := VRU_SCENE.instantiate() as N64Vru
	var unit_hits := _coplanar_pairs(unit)
	_ok(unit_hits.is_empty(), "faces/no two faces of the unit share a plane",
		", ".join(PackedStringArray(unit_hits)))
	unit.free()

	var lead := preload(
		"res://Scenes/Objects/controllers/n64/n64_vru_cable.tscn").instantiate()
	var mic := lead.get_node("Nus021Mic") as Node3D
	var mic_hits := _coplanar_pairs(mic)
	_ok(mic_hits.is_empty(), "faces/nor two of the microphone's",
		", ".join(PackedStringArray(mic_hits)))
	lead.free()


func _test_device() -> void:
	var unit := await _spawn_unit()

	# RETRO_DEVICE_SUBCLASS(RETRO_DEVICE_JOYPAD, 0): the subclass in the high
	# byte, the base device in the low one. The core fork reads the same number.
	_ok(N64Vru.DEVICE_VRU == (1 << 8) | 1, "device/the id is a joypad subclass",
		str(N64Vru.DEVICE_VRU))
	_ok(unit.device_type == N64Vru.DEVICE_VRU, "device/the unit announces it")
	_ok(unit.systemid == "n64", "device/it only fits an N64")
	# The box is NOT what a socket takes any more; the plug on its cord is, and it
	# reads the device off the unit the way every controller's plug does.
	_ok(not unit.is_in_group("controller_plug"), "device/the box is not itself a plug")
	var plug := unit.get_plug()
	_ok(plug != null and plug.is_in_group("controller_plug"),
		"device/its plug is what a socket filters on")
	_ok(plug != null and plug.device_type == N64Vru.DEVICE_VRU,
		"device/and the plug carries the unit's device", str(plug.device_type))
	_ok(plug != null and plug.systemid == "n64",
		"device/and its console", plug.systemid)
	_ok(plug != null and plug.get_controller() == unit,
		"device/the console unwraps the plug back to the unit")
	_ok(unit.is_in_group("n64_vru"), "device/and has its own group")
	_ok(unit.get_mic() != null, "device/the cord and microphone grew")

	unit.drop_and_free()
	await get_tree().process_frame


func _test_seat() -> void:
	var sys := await _spawn_n64()
	var unit := await _spawn_unit()

	unit.restore_seat(sys, 3)
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


## The microphone plugs into the unit, and comes out of it again. Out of the jack
## it is an object lying somewhere, which is exactly why the unit stops reporting
## its position — a microphone on a table across the room must not go on setting
## the gain as though the player were speaking into it.
func _test_jack() -> void:
	var sys := await _spawn_n64()
	var unit := await _spawn_unit()
	unit.restore_seat(sys, 3)
	await get_tree().process_frame

	var mic := unit.get_mic()
	var mic_plug := unit.get_mic_plug()
	_ok(mic_plug != null and mic_plug.is_in_group(String(N64VruMicPlug.GROUP)),
		"jack/the microphone's plug has a group of its own")
	_ok(mic_plug != null and not mic_plug.is_in_group("controller_plug"),
		"jack/and is not one a console socket would take")
	_ok(unit.mic_plugged(), "jack/it comes out of the box plugged in")
	_ok(mic_plug != null and mic_plug.seated_unit == unit,
		"jack/and the plug knows which unit holds it")
	_ok(unit.microphone_position().is_equal_approx(mic.global_position),
		"jack/plugged in, the unit hears from the microphone")

	unit.restore_mic_plugged(false)
	await get_tree().process_frame
	_ok(not unit.mic_plugged(), "jack/it can be pulled out")
	_ok(mic_plug != null and mic_plug.seated_unit == null,
		"jack/and the plug knows it is out")
	mic.global_position = sys.global_position + Vector3(2.5, 0, 0)
	await get_tree().process_frame
	_ok(unit.microphone_position().is_equal_approx(unit.global_position),
		"jack/out of the jack, the unit hears from itself",
		"%s vs %s" % [unit.microphone_position(), unit.global_position])
	_ok(sys.microphone_position().is_equal_approx(unit.global_position),
		"jack/and so does the machine it is seated in")

	unit.restore_mic_plugged(true)
	await get_tree().process_frame
	_ok(unit.mic_plugged(), "jack/and it goes back in")

	sys.queue_free()
	unit.drop_and_free()
	await get_tree().process_frame


func _test_mic() -> void:
	var sys := await _spawn_n64()
	var unit := await _spawn_unit()
	unit.restore_seat(sys, 3)
	await get_tree().process_frame

	var mic := unit.get_mic()
	mic.global_position = sys.global_position + Vector3(0, 1.2, 0.8)
	await get_tree().process_frame

	_ok(unit.microphone_position().is_equal_approx(mic.global_position),
		"mic/the unit hears from the microphone, not the box")
	_ok(sys.microphone_position().is_equal_approx(mic.global_position),
		"mic/and so does the machine it is seated in",
		"%s vs %s" % [sys.microphone_position(), mic.global_position])

	# Which way each cord leaves the body it is tied to, by the sign of a dot rather
	# than by a look. Two cords now: the microphone's grille is at -Z and its boss at
	# +Z, and the unit's jack is at -Z with its own boss at +Z.
	var mic_rope := unit.get_mic_rope()
	if mic_rope != null:
		_check_cord("mic/", mic_rope, mic, Vector3(0, 0, -0.0585), Vector3(0, 0, 0.06))
		# The far end is a plug, and a plug's cord trails BEHIND its connector.
		var mic_end: Vector3 = Vector3(mic_rope.end_exit_axis).normalized()
		_ok(mic_end.dot(Vector3(0, 0, -1)) > 0.5,
			"mic/and leaves the 3.5 mm plug behind its connector", str(mic_end))
	else:
		_ok(false, "mic/the microphone has a cord")

	var console_rope := unit.get_console_rope()
	if console_rope != null:
		_check_cord("mic/console ", console_rope, unit.get_node("CableAttachPoint"),
			Vector3(0, 0, -0.029), Vector3(0, 0, 0.039))
	else:
		_ok(false, "mic/the unit has a cord to the console")

	sys.queue_free()
	unit.drop_and_free()
	await get_tree().process_frame


func _physics_seconds(seconds: float) -> void:
	for i in range(int(seconds * Engine.physics_ticks_per_second)):
		await get_tree().physics_frame


## A rope turns a free-plug end to face its cord every tick; on a floor that
## walks the microphone grille-first for as long as the cord reaches.
func _test_drop() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 0.1, 4)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0, -0.05, 0)
	add_child(floor_body)

	var unit := await _spawn_unit()
	unit.freeze = true
	unit.global_position = Vector3(0, 0.03, 0)
	var mic := unit.get_mic()
	mic.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(10.0)),
		Vector3(0.05, 0.25, -0.45))
	unit.get_mic_rope()._init_points()

	await _physics_seconds(2.5)
	var landed := mic.global_position
	await _physics_seconds(1.5)
	var d := mic.global_position - landed
	var moved := Vector2(d.x, d.z).length()
	_ok(landed.y > 0.005 and landed.y < 0.02, "drop/the microphone lands on the floor",
		"y %.1f mm" % (landed.y * 1000.0))
	_ok(moved < 0.005, "drop/and stays where it landed",
		"%.1f mm in 1.5 s" % (moved * 1000.0))

	unit.drop_and_free()
	floor_body.queue_free()
	await get_tree().process_frame


func _test_catalog() -> void:
	var rows: Array = SpawnCatalog.items_for("n64")
	var found := false
	for row: Variant in rows:
		if SpawnCatalog.spawn_token("n64", row as Dictionary) == "n64_vru":
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
