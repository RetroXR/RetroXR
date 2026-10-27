## CellSlots self-tests -- battery cells in an object's bays, headless.
##
##     "$godot" --headless --path RetroXR res://Tests/cell_slots_tests.tscn
##     "$godot" --headless --path RetroXR res://Tests/cell_slots_tests.tscn -- --only=roll
##
## Exits 0 when everything passes, 1 otherwise.
##
## A model's BatteryAAA<n> nodes (here added by hand to the game's Rumble Pak, in
## a scaled shell as an imported GLB is) become slots that take an AAA cell and
## no other. Covered: the seats are found and the slots sit on them at the cell's
## own size; a cell goes in at the roll it was held at, the right way round even
## offered end for end, and the ghost (roll_basis) shows the same pose; while a
## cover is on, a slot takes nothing and its cell cannot be taken out; a save
## records each seated cell and its roll on the object, not on the cell; and a
## load seats each cell back at its roll, whether the slots are built as the
## object enters the room or after the restore's second pass.
extends "res://Tests/test_suite.gd"

const PAK_SCENE := preload("res://Scenes/Objects/controllers/n64/rumble_pak.tscn")
const CELL_TYPE := "battery_aaa"
const CELL_SCENE := "res://Scenes/Objects/batteries/battery_aaa.tscn"
## The two seats, in the shell's frame (millimetres, as a GLB would have them
## before its 0.001 scale): side by side, + ends opposite ways.
const SEATS := {
	"BatteryAAA1": Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(-6.0, -4.0, 2.0)),
	"BatteryAAA2": Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(6.0, -4.0, 2.0)),
}
const COVER := "test_battery"

var _only := ""
## Set while a test wants every Rumble Pak that enters the tree to get its slots
## at once, as a mod's hook would build them.
var _build_on_enter := false


func _ready() -> void:
	suite_tag = "cells"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7)
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("[cells] TIMEOUT")
		get_tree().quit(1))
	get_tree().node_added.connect(_on_node_added)
	if _want("names"):
		_test_names()
	if _want("seats"):
		await _test_seats()
	if _want("roll"):
		await _test_roll()
	if _want("cover"):
		await _test_cover(true)
		await _test_cover(false)
	if _want("save"):
		await _test_save()
	if _want("restore"):
		await _test_restore(true)
		await _test_restore(false)
	if _want("labels"):
		await _test_labels()
	_finish()


func _want(group: String) -> bool:
	return _only.is_empty() or _only == group


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _on_node_added(node: Node) -> void:
	if _build_on_enter and node.scene_file_path == PAK_SCENE.resource_path:
		_shell(node as Node3D)


## A shell in `pak` as a mod hangs a GLB: scaled to metres, turned, and holding
## the seats, plus a node whose name only starts like one.
func _shell(pak: Node3D) -> Node3D:
	var shell := Node3D.new()
	shell.name = "Shell"
	shell.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5).scaled(Vector3.ONE * 0.001), Vector3(0, 0.01, 0))
	pak.add_child(shell)
	for seat_name: String in SEATS:
		var marker := Node3D.new()
		marker.name = seat_name
		marker.transform = SEATS[seat_name]
		shell.add_child(marker)
	var cover := Node3D.new()
	cover.name = "BatteryCover"
	shell.add_child(cover)
	CellSlots.build_seats(shell)
	return shell


func _pak() -> Node3D:
	var pak := PAK_SCENE.instantiate() as Node3D
	add_child(pak)
	pak.add_to_group("spawned")
	return pak


func _cell() -> XRToolsPickable:
	var cell := (load(CELL_SCENE) as PackedScene).instantiate() as XRToolsPickable
	add_child(cell)
	cell.add_to_group("spawned")
	return cell


func _clear() -> void:
	for n in get_tree().get_nodes_in_group("spawned"):
		n.queue_free()
	for n in get_tree().get_nodes_in_group(PortCover.GROUP):
		n.queue_free()
	await _wait(3)


## The labels a cell comes in: given before it enters the room (as the spawn menu
## and a save give it), a cell wears that label on the model's own label surface;
## a cell given none wears the model's; the label is saved and comes back; and
## the Power tab offers both sizes in every label, held to choose.
func _test_labels() -> void:
	var plain := ScenePersistence.instantiate("battery_aa") as BatteryCell
	add_child(plain)
	var gold := ScenePersistence.instantiate("battery_aaa") as BatteryCell
	SystemModelRegistry.set_variant_of(gold, "black_gold")
	add_child(gold)
	await _wait(2)
	var worn := _label_texture(gold)
	_ok(worn != null and worn == BatteryCell.LABELS["AAA"]["black_gold"],
		"labels/an AAA asked for in Black & Gold wears it", str(worn))
	_ok(_label_override(plain) == null, "labels/a cell asked for nothing wears the model's own label")
	var rec: Dictionary = ScenePersistence.new().serialize_node(gold, 3, {gold: 3})
	_ok(rec.get("model_variant") == "black_gold", "labels/its label is saved", str(rec.get("model_variant")))
	rec["id"] = 3
	var back := ScenePersistence.new().instantiate_objects(self, JSON.parse_string(JSON.stringify([rec])))
	await _wait(2)
	var again := back.get(3) as BatteryCell
	_ok(again != null and _label_texture(again) == BatteryCell.LABELS["AAA"]["black_gold"],
		"labels/and comes back on load")
	var view: Variant = load("res://Scripts/UI/spawn_menu/views/spawn_view.gd").new()
	var power: Array = view.call("_power_items")
	if view is Node:
		(view as Node).free()
	for token: String in ["battery_aa", "battery_aaa"]:
		var row: Array = []
		for item: Array in power:
			if item[1] == token:
				row = item
		_ok(row.size() > 2 and (row[2] as Array).size() == BatteryCell.VARIANTS.size(),
			"labels/the Power tab's %s row comes in every label" % token)
	for n in [plain, gold, again]:
		if is_instance_valid(n):
			n.queue_free()
	await _wait(2)


## The texture a cell's label surface draws with, override first.
func _label_texture(cell: BatteryCell) -> Texture2D:
	for node in cell.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var m := mi.get_active_material(s) as BaseMaterial3D
			if m != null and m.resource_name == BatteryCell.LABEL_MATERIAL:
				return m.albedo_texture
	return null


func _label_override(cell: BatteryCell) -> Material:
	for node in cell.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for s in mi.mesh.get_surface_count():
			var own := mi.mesh.surface_get_material(s)
			if own != null and own.resource_name == BatteryCell.LABEL_MATERIAL:
				return mi.get_surface_override_material(s)
	return null


func _test_names() -> void:
	_ok(CellSlots.size_of_seat("BatteryAA1") == "AA", "names/ BatteryAA1 is an AA seat")
	_ok(CellSlots.size_of_seat("BatteryAAA12") == "AAA", "names/ BatteryAAA12 an AAA one")
	var not_seats := ["BatteryCover", "BatteryAA", "BatteryAAx", "Battery1", "BatteryAAA"]
	var none := not_seats.all(func(n: String) -> bool: return CellSlots.size_of_seat(n).is_empty())
	_ok(none, "names/ BatteryCover, BatteryAA, BatteryAAx, Battery1 are not seats")
	_ok(CellSlots.group_for("AAA") == "battery_cell:aaa", "names/ an AAA cell's group")
	var aa := ScenePersistence.instantiate("battery_aa") as BatteryCell
	var aaa := ScenePersistence.instantiate("battery_aaa") as BatteryCell
	_ok(aa != null and aa.is_in_group(CellSlots.group_for("AA")) and aa.save_type() == "battery_aa"
		and aaa != null and aaa.is_in_group(CellSlots.group_for("AAA")) and aaa.save_type() == "battery_aaa",
		"names/ the game's AA and AAA cells, each in its size's group")
	for c: Node in [aa, aaa]:
		if c != null:
			c.free()


func _test_seats() -> void:
	var pak := _pak()
	var shell := _shell(pak)
	var slots := CellSlots.of(pak)
	_ok(slots != null and slots.seats() == ["BatteryAAA1", "BatteryAAA2"], "seats/ a slot at each seat, and only there",
		str(slots.seats() if slots != null else null))
	if slots == null:
		await _clear()
		return
	var zone := slots.slot("BatteryAAA1")
	var marker := shell.get_node("BatteryAAA1") as Node3D
	_ok(zone.snap_require == "battery_cell:aaa", "seats/ it takes an AAA cell")
	_ok(zone.global_position.is_equal_approx(marker.global_position), "seats/ at the seat")
	_ok(zone.global_basis.is_equal_approx(marker.global_basis.orthonormalized()),
		"seats/ turned as the seat, at the cell's own size", str(zone.global_basis.get_scale()))
	_ok(CellSlots.build_seats(shell).size() == 2 and slots.seats().size() == 2 and slots.slot("BatteryAAA1") == zone,
		"seats/ building again gives the same slots")
	var cell := _cell()
	_ok(zone.can_preview(cell), "seats/ an AAA cell may go in")
	cell.remove_from_group("battery_cell:aaa")
	cell.add_to_group("battery_cell:aa")
	_ok(not zone.can_preview(cell), "seats/ an AA one may not")
	await _wait(2)
	_ok(not slots.slot("BatteryAAA2").has_snapped_object(), "seats/ bays come empty")
	await _clear()


## Put `cell` into `zone` held at `held` (world basis), as a hand lets go of it.
func _drop_into(zone: CellSlot, cell: XRToolsPickable, held: Basis) -> void:
	cell.global_transform = Transform3D(held, zone.global_position + Vector3(0.0, 0.005, 0.0))
	zone.pick_up_object(cell)
	await _wait(3)


## Take the cell out of `zone` and away from it, as a hand does: let go where it
## was, a slot in dropped mode (its own, or the next seat 12 mm over) would take
## it straight back, so every slot is shut while it goes.
func _take_out(zone: CellSlot) -> XRToolsPickable:
	var cell := zone.picked_up_object as XRToolsPickable
	var slots := CellSlots.of(CoverSlots.host_of(zone))
	for seat_name: String in slots.seats():
		slots.slot(seat_name).enabled = false
	zone.drop_object()
	if cell != null:
		cell.global_position = zone.global_position + Vector3(0.0, 0.4, 0.0)
		cell.freeze = true
	for i in 3:
		await get_tree().physics_frame
	slots.refresh()
	await _wait(2)
	return cell


func _test_roll() -> void:
	var pak := _pak()
	_shell(pak)
	var zone := CellSlots.of(pak).slot("BatteryAAA1")
	var seat := zone.global_basis
	var cell := _cell()
	var turned := seat * Basis(Vector3.BACK, deg_to_rad(40.0))
	await _drop_into(zone, cell, turned)
	_ok(zone.picked_up_object == cell, "roll/ the cell goes in")
	_ok(absf(rad_to_deg(zone.roll) - 40.0) < 0.01, "roll/ at the roll it was held at", str(rad_to_deg(zone.roll)))
	_ok(cell.global_basis.is_equal_approx(turned), "roll/ and drawn so", str(cell.global_basis))
	_ok(cell.global_position.is_equal_approx(zone.global_position), "roll/ its middle on the seat")
	var ghost := CellSlot.roll_basis(seat, turned)
	_ok(ghost.is_equal_approx(turned), "roll/ the ghost shows the same pose")
	await _take_out(zone)
	_ok(not zone.has_snapped_object(), "roll/ taken out, the slot is empty")
	# End for end and tilted: still + end first, keeping only the roll.
	var wrong := seat * Basis(Vector3.RIGHT, PI) * Basis(Vector3.BACK, deg_to_rad(-70.0)) \
		* Basis(Vector3.UP, deg_to_rad(12.0))
	await _drop_into(zone, cell, wrong)
	_ok(cell.global_basis.z.is_equal_approx(seat.z), "roll/ offered end for end, it still goes in + end first")
	_ok(absf(cell.global_basis.z.dot(seat.z) - 1.0) < 1e-4 and (cell.global_basis.y - seat.y).length() > 0.1,
		"roll/ keeping a roll, not the seat's own", str(rad_to_deg(zone.roll)))
	var preview := CellSlot.roll_basis(seat, wrong)
	_ok(preview.is_equal_approx(cell.global_basis), "roll/ and the ghost agrees", "%s vs %s" % [preview, cell.global_basis])
	await _clear()


## `cover_first`: the cover's slot is built before the bays, else after.
func _test_cover(cover_first: bool) -> void:
	var tag := "cover/%s " % ("first" if cover_first else "after")
	var pak := _pak()
	if cover_first:
		CoverSlots.on(pak).build(COVER, pak, Transform3D(), Vector3(0.05, 0.002, 0.03))
		_shell(pak)
	else:
		_shell(pak)
		var early := CellSlots.of(pak).slot("BatteryAAA1")
		var cell0 := _cell()
		await _drop_into(early, cell0, early.global_basis)
		_ok(early.picked_up_object == cell0, tag + "with the cover off, a cell goes in")
		CoverSlots.on(pak).build(COVER, pak, Transform3D(), Vector3(0.05, 0.002, 0.03))
	await _wait(4)
	var covers := CoverSlots.of(pak)
	var slots := CellSlots.of(pak)
	var zone := slots.slot("BatteryAAA2")
	_ok(covers.is_on(COVER) and slots.is_blocked(), tag + "the cover is on and the bays are shut")
	_ok(not zone.enabled, tag + "a slot takes nothing")
	if not cover_first:
		var held := slots.slot("BatteryAAA1").picked_up_object as XRToolsPickable
		_ok(held != null and not held.enabled, tag + "and its cell cannot be taken out")
	var cover := covers.slot(COVER).picked_up_object as PortCover
	covers.slot(COVER).drop_object()
	await _wait(3)
	_ok(not slots.is_blocked() and zone.enabled, tag + "cover off: the slots open")
	if not cover_first:
		var held := slots.slot("BatteryAAA1").picked_up_object as XRToolsPickable
		_ok(held != null and held.enabled, tag + "and the cell can be taken out")
	covers.slot(COVER).pick_up_object(cover)
	await _wait(3)
	_ok(not zone.enabled, tag + "cover back: shut again")
	await _clear()


func _test_save() -> void:
	var pak := _pak()
	_shell(pak)
	var zone := CellSlots.of(pak).slot("BatteryAAA2")
	var cell := _cell()
	await _drop_into(zone, cell, zone.global_basis * Basis(Vector3.BACK, deg_to_rad(-25.0)))
	var sp := ScenePersistence.new()
	var rec: Dictionary = sp.serialize_node(pak, 1, {cell: 5})
	_ok(rec.get("cell_slots") == {"BatteryAAA2": {"cell": 5, "roll": -25.0}},
		"save/ the object names its cell and roll", str(rec.get("cell_slots")))
	var cell_rec: Dictionary = sp.serialize_node(cell, 5, {pak: 1, cell: 5})
	_ok(cell_rec.get("type") == CELL_TYPE and not cell_rec.has("attached"),
		"save/ the cell saves as an AAA cell, and does not say what holds it", str(cell_rec))
	await _take_out(zone)
	_ok(not sp.serialize_node(pak, 1, {cell: 5}).has("cell_slots"), "save/ empty bays write nothing")
	var ids := {1: true, 5: true}
	var base := {"id": 1, "type": "rumble_pak", "position": [0, 0, 0], "rotation": [0, 0, 0]}
	_ok(ScenePersistence._entry_validation_error(base.merged({"cell_slots": {"BatteryAAA2": {"cell": 5, "roll": 10}}}), ids).is_empty(),
		"save/ a record naming its cells is valid")
	_ok(not ScenePersistence._entry_validation_error(base.merged({"cell_slots": {"BatteryAAA2": 5}}), ids).is_empty(),
		"save/ a seat that is not a record is refused")
	_ok(not ScenePersistence._entry_validation_error(base.merged({"cell_slots": {"BatteryAAA2": {"cell": 9}}}), ids).is_empty(),
		"save/ and a cell that is not in the save")
	var pruned := ScenePersistence._prune_unknown_types([
		base.merged({"cell_slots": {"BatteryAAA2": {"cell": 5, "roll": 0}}}),
		{"id": 5, "type": "gone.mod:aaa", "position": [0, 0, 0], "rotation": [0, 0, 0]}], "test")
	_ok(pruned.size() == 1 and ((pruned[0] as Dictionary).get("cell_slots", {}) as Dictionary).is_empty(),
		"save/ a cell whose mod is gone leaves its seat empty", str(pruned))
	await _clear()


## `early`: the slots are built as the object enters the room (a mod's hook),
## before the save's second pass; otherwise after it (a shell that loads late).
func _test_restore(early: bool) -> void:
	var tag := "restore/%s " % ("hook" if early else "late")
	var sp := ScenePersistence.new()
	var objects: Array = [
		{"id": 1, "type": "rumble_pak", "position": [0.3, 0.5, 0.0], "rotation": [0, 0, 0],
			"cell_slots": {"BatteryAAA1": {"cell": 5, "roll": 33.0}}},
		{"id": 5, "type": CELL_TYPE, "position": [0.6, 0.5, 0.0], "rotation": [0, 0, 0]},
		{"id": 6, "type": CELL_TYPE, "position": [0.7, 0.5, 0.0], "rotation": [0, 0, 0]},
	]
	_build_on_enter = early
	# Through JSON, as a save is: ids come back as floats.
	var spawned := sp.instantiate_objects(self, JSON.parse_string(JSON.stringify(objects)))
	_build_on_enter = false
	var pak := spawned.get(1) as Node3D
	if pak == null or spawned.get(5) == null:
		_ok(false, tag + "the pak and its cell come back", str(spawned.keys()))
		await _clear()
		return
	if not early:
		await _wait(2)
		_shell(pak)
	await _wait(4)
	var zone := CellSlots.of(pak).slot("BatteryAAA1") if CellSlots.of(pak) != null else null
	_ok(zone != null and zone.picked_up_object == spawned.get(5), tag + "the saved cell is back in its seat")
	if zone != null:
		_ok(absf(rad_to_deg(zone.roll) - 33.0) < 0.01, tag + "at its roll", str(rad_to_deg(zone.roll)))
	_ok(not CellSlots.of(pak).slot("BatteryAAA2").has_snapped_object(), tag + "the empty seat stays empty")
	_ok((spawned.get(6) as XRToolsPickable).get_picked_up_by() == null, tag + "and the loose cell stays loose")
	await _clear()
