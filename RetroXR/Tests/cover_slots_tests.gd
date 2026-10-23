## CoverSlots self-tests -- removable covers on any object, headless.
##
##     "$godot" --headless --path RetroXR res://Tests/cover_slots_tests.tscn
##     "$godot" --headless --path RetroXR res://Tests/cover_slots_tests.tscn -- --only=restore
##
## Exits 0 when everything passes, 1 otherwise.
##
## A mod gives an object that is not a console (here the game's Rumble Pak, whose
## battery door xenu.n64paks makes one) a slot for a PortCover. Covered: a fresh
## object gets its cover, once; the cover's pointer target is its own box while
## it is seated and the loose cover's margin once it is off; a save records each
## slot's cover or null; and a load gives back the cover that was on, leaves off
## the one that was off, and gives a cover to a slot a save from before covers
## never named -- whether the slot is built as the object enters the room (a mod's
## hook) or after the restore's second pass (a shell that loads late).
extends Node

const PAK_SCENE := preload("res://Scenes/Objects/controllers/n64/rumble_pak.tscn")
const SOCKET := "test_battery"
const SIZE := Vector3(0.056, 0.0015, 0.035)
const SEAT := Transform3D(Basis.IDENTITY, Vector3(0.0, -0.012, 0.01))

var _pass := 0
var _fail := 0
var _only := ""
## Set while a test wants every Rumble Pak that enters the tree to get its slot
## at once, as a mod's hook would build it.
var _build_on_enter := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7)
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("[covers] TIMEOUT")
		get_tree().quit(1))
	get_tree().node_added.connect(_on_node_added)
	if _want("fresh"):
		await _test_fresh()
	if _want("pointer"):
		await _test_pointer()
	if _want("save"):
		await _test_save()
	if _want("restore"):
		await _test_restore(true)
		await _test_restore(false)
	if _want("shell"):
		await _test_shell_cover()
	print("[covers] ---- %d passed, %d failed ----" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _want(group: String) -> bool:
	return _only.is_empty() or _only == group


func _ok(cond: bool, msg: String, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("[covers] PASS  ", msg)
	else:
		_fail += 1
		print("[covers] FAIL  ", msg, ("  (" + detail + ")") if not detail.is_empty() else "")


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _on_node_added(node: Node) -> void:
	if _build_on_enter and node.scene_file_path == PAK_SCENE.resource_path:
		_build(node as Node3D)


func _build(pak: Node3D) -> XRToolsSnapZone:
	return CoverSlots.on(pak).build(SOCKET, pak, SEAT, SIZE)


func _pak() -> Node3D:
	var pak := PAK_SCENE.instantiate() as Node3D
	add_child(pak)
	pak.add_to_group("spawned")
	return pak


func _covers() -> Array[Node]:
	return get_tree().get_nodes_in_group(PortCover.GROUP)


func _clear() -> void:
	for n in get_tree().get_nodes_in_group("spawned"):
		n.queue_free()
	for n in _covers():
		n.queue_free()
	await _wait(3)


func _test_fresh() -> void:
	var pak := _pak()
	var zone := _build(pak)
	await _wait(3)
	var cover := zone.picked_up_object as PortCover
	_ok(cover != null, "fresh/ a fresh object's slot gets its cover")
	if cover != null:
		_ok(cover.socket_id == SOCKET and cover.size.is_equal_approx(SIZE), "fresh/ for its socket, at its size")
		_ok(cover.is_in_group(PortCover.group_for(SOCKET)), "fresh/ in the group its slot takes")
		_ok(cover.is_in_group("spawned"), "fresh/ and saved as a thing of its own")
		_ok(cover.global_transform.origin.is_equal_approx(zone.global_transform.origin), "fresh/ where the slot is")
	_ok(_build(pak) == zone, "fresh/ building the slot again gives the same slot")
	await _wait(3)
	_ok(_covers().size() == 1, "fresh/ and no second cover", str(_covers().size()))
	_ok(CoverSlots.of(pak).is_on(SOCKET) and CoverSlots.of(pak).sockets() == [SOCKET], "fresh/ the slot says its cover is on")
	await _clear()


func _test_pointer() -> void:
	var pak := _pak()
	var zone := _build(pak)
	await _wait(3)
	var cover := zone.picked_up_object as PortCover
	if cover == null:
		_ok(false, "pointer/ a cover to test")
		return
	var target := cover.get_node("PointerArea/CollisionShape3D") as CollisionShape3D
	_ok(((target.shape as BoxShape3D).size - SIZE).is_equal_approx(CoverSlots.SEATED_POINTER_MARGIN),
		"pointer/ seated, a cover is pointed at by its own box", str((target.shape as BoxShape3D).size))
	zone.drop_object()
	await _wait(3)
	_ok(((target.shape as BoxShape3D).size - SIZE).is_equal_approx(PortCover.POINTER_MARGIN),
		"pointer/ off, by the loose cover's margin", str((target.shape as BoxShape3D).size))
	_ok(not CoverSlots.of(pak).is_on(SOCKET), "pointer/ and its slot says it is off")
	zone.pick_up_object(cover)
	await _wait(3)
	_ok(((target.shape as BoxShape3D).size - SIZE).is_equal_approx(CoverSlots.SEATED_POINTER_MARGIN),
		"pointer/ put back, its own box again")
	await _clear()


func _test_save() -> void:
	var pak := _pak()
	var zone := _build(pak)
	await _wait(3)
	var cover := zone.picked_up_object as PortCover
	var sp := ScenePersistence.new()
	var rec: Dictionary = sp._serialize_node(pak, 1, {cover: 7})
	_ok(rec.get("cover_slots") == {SOCKET: 7}, "save/ the object's record names the cover on it", str(rec.get("cover_slots")))
	zone.drop_object()
	await _wait(2)
	rec = sp._serialize_node(pak, 1, {cover: 7})
	_ok(rec.get("cover_slots") == {SOCKET: null}, "save/ and null for one that is off", str(rec.get("cover_slots")))
	var plain := _pak()
	_ok(not sp._serialize_node(plain, 2, {}).has("cover_slots"), "save/ an object with no slot saves as it did")
	var ids := {1: true, 7: true}
	var base := {"id": 1, "type": "rumble_pak", "position": [0, 0, 0], "rotation": [0, 0, 0]}
	_ok(ScenePersistence._entry_validation_error(base.merged({"cover_slots": {SOCKET: 7}}), ids).is_empty(),
		"save/ a record naming its cover is valid")
	_ok(not ScenePersistence._entry_validation_error(base.merged({"cover_slots": [7]}), ids).is_empty(),
		"save/ covers that are not by socket are refused")
	_ok(not ScenePersistence._entry_validation_error(base.merged({"cover_slots": {SOCKET: 9}}), ids).is_empty(),
		"save/ and a cover that is not in the save")
	await _clear()


## `early`: the slot is built as the object enters the room (a mod's hook), before
## the save's second pass; otherwise after it (a shell that loads late).
func _test_restore(early: bool) -> void:
	var tag := "restore/%s " % ("hook" if early else "late")
	var sp := ScenePersistence.new()
	var pak_rec := {"id": 1, "type": "rumble_pak", "position": [0.3, 0.5, 0.0], "rotation": [0, 0, 0]}
	var cover_rec := {"id": 7, "type": "port_cover", "position": [0.6, 0.5, 0.0], "rotation": [0, 0, 0],
		"cover_socket": SOCKET, "cover_size": [SIZE.x, SIZE.y, SIZE.z], "model_variant": ""}
	for case: Array in [["on", {SOCKET: 7}, true], ["off", {SOCKET: null}, false], ["old", null, true]]:
		var rec := pak_rec.duplicate(true)
		if case[1] != null:
			rec["cover_slots"] = case[1]
		var objects: Array = [rec]
		if case[0] != "old":
			objects.append(cover_rec.duplicate(true))
		_build_on_enter = early
		# Through JSON, as a save is: ids come back as floats.
		var spawned := sp.instantiate_objects(self, JSON.parse_string(JSON.stringify(objects)))
		_build_on_enter = false
		var pak := spawned.get(1) as Node3D
		if pak == null:
			_ok(false, tag + case[0] + ": the pak comes back")
			continue
		if not early:
			await _wait(2)
			_build(pak)
		await _wait(4)
		var zone := CoverSlots.of(pak).slot(SOCKET) if CoverSlots.of(pak) != null else null
		var on := zone != null and zone.has_snapped_object()
		_ok(on == case[2], tag + "%s: the cover is %s" % [case[0], "on" if case[2] else "off"])
		_ok(_covers().size() == 1, tag + "%s: one cover in the room, no second" % case[0], str(_covers().size()))
		if case[0] == "on" and on:
			_ok(zone.picked_up_object == spawned.get(7), tag + "on: and it is the saved cover")
		await _clear()


## A shell's own cover, as a mod makes one: a mesh of the model, on the back
## (-Z) of a shell nested in the object. Its slot goes round the part's bounds,
## turned so the cover's +Y is out of the shell; the part is hidden; and a cover
## dressed in a copy of the part (wear) draws it exactly where the shell had it.
func _test_shell_cover() -> void:
	var pak := _pak()
	var shell := Node3D.new()
	shell.position = Vector3(0.01, 0.02, 0.0)
	pak.add_child(shell)
	var make_part := func() -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.05, 0.03, 0.002)
		mi.mesh = bm
		mi.position = Vector3(0.0, -0.01, -0.012)
		return mi
	var part: MeshInstance3D = make_part.call()
	shell.add_child(part)
	var zone := CoverSlots.shell_cover(part, SOCKET, Vector3(0, 0, -1))
	_ok(zone != null and zone.get_parent() == shell, "shell/ the slot is built beside the part")
	_ok(not part.visible, "shell/ and the shell's own part is hidden")
	if zone == null:
		return
	_ok(zone.transform.origin.is_equal_approx(part.position), "shell/ at the part's middle")
	_ok(zone.transform.basis.y.is_equal_approx(Vector3(0, 0, -1)), "shell/ its +Y out of the shell")
	await _wait(3)
	var cover := zone.picked_up_object as PortCover
	_ok(cover != null and cover.size.is_equal_approx(Vector3(0.05, 0.002, 0.03)),
		"shell/ its cover is the part's box, thin along +Y", str(cover.size if cover != null else null))
	if cover == null:
		await _clear()
		return
	# the dress hook's copy: the same part, in a copy of the shell
	var copy := Node3D.new()
	var twin: MeshInstance3D = make_part.call()
	copy.add_child(twin)
	CoverSlots.wear(cover, twin, Vector3(0, 0, -1))
	copy.free()
	await _wait(3)
	var drawn := cover.get_node_or_null("Shell") as Node3D
	var worn := drawn.get_child(0) as MeshInstance3D if drawn != null and drawn.get_child_count() > 0 else null
	_ok(worn != null and worn.visible and not (cover.get_node("Mesh") as Node3D).visible,
		"shell/ the cover wears the part, not its plain block")
	if worn != null:
		_ok(worn.global_transform.origin.is_equal_approx(part.global_transform.origin)
			and worn.global_basis.is_equal_approx(part.global_basis),
			"shell/ drawn exactly where the shell's part was", str(worn.global_transform.origin))
	await _clear()
