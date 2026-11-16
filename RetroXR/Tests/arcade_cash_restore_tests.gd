## Box-owned coins: a loose save restores now, and seating/swapping never refills.
extends "res://Tests/arcade_cash_tests.gd"


func _ready() -> void:
	suite_tag = "cash-restore"
	get_tree().create_timer(90).timeout.connect(func() -> void: get_tree().quit(1))
	_setup()
	var source := Node3D.new()
	add_child(source)
	var part := _tray_part()
	source.add_child(part)
	var socket := "cabinet_cash_box_lift_off"
	cabinet._loose_lift_offs[socket] = [part, Vector3.UP]
	var persistence := ScenePersistence.new()
	var loose := persistence._load_port_cover({"cover_socket": socket, "cover_size": [0.22, 0.08, 0.18], "coins": 24}) as PortCover
	loose.position = Vector3(2, 0.3, 0)
	loose.freeze = true
	add_child(loose)
	cabinet._dress_loose(loose)
	var state := loose.get_node_or_null("CashPhysics")
	_ok(state != null, "loose restored box gets physics before insertion")
	if state == null:
		_finish()
		return
	_eq(state.tokens.size(), 24, "loose box immediately restores its saved coins")
	await _frames(180)
	_eq(state.tokens.size(), 24, "loose saved pile remains visible and contained")
	var ids: Array[int] = []
	for token: RigidBody3D in state.tokens:
		ids.append(token.get_instance_id())
	cabinet._dress_loose(loose)
	cabinet._dress_lift_off(loose, part, Vector3.UP)
	var another := ArcadeCabinetFromModel.new()
	add_child(another)
	another._dress_lift_off(loose, part, Vector3.UP)
	var after: Array[int] = []
	for token: RigidBody3D in state.tokens:
		after.append(token.get_instance_id())
	_eq(after, ids, "redressing and changing cabinets keep the same physical coins")
	var seat := CoverSlots.make_zone("OtherCashSeat", "", 0.12, source)
	seat.global_transform = loose.global_transform
	seat.pick_up_object(loose)
	another._cash_zone = seat
	another._bank_coin(1)
	_eq(state.tokens.size(), 25, "accepted coin reaches the box in the current cabinet")
	_eq(int(loose.get_meta(cabinet.CASH_COINS_META)), 25, "accepted coin updates that box's saved count")
	another._unbank_coin(1)
	await _frames(2)
	_eq(state.tokens.size(), 24, "refund removes one coin from the current box")
	# Empty the box between timer ticks; saving must flush the count immediately.
	for token: RigidBody3D in state.tokens:
		token.global_position += Vector3(0, 0, 2)
	var saved := persistence._port_cover_fields(loose, {})
	_ok(not saved.has("coins"), "saving an emptied box cannot retain an old coin count")
	another._dress_lift_off(loose, part, Vector3.UP)
	_eq(state.tokens.size(), 0, "reseating an emptied box never spawns replacements")
	# Existing saves can have more banked coins than the sixty physical bodies.
	var overflow := persistence._load_port_cover({"cover_socket": socket, "cover_size": [0.22, 0.08, 0.18], "coins": 80}) as PortCover
	overflow.position = Vector3(-2, 0.3, 0)
	overflow.freeze = true
	add_child(overflow)
	cabinet._dress_loose(overflow)
	var extra := overflow.get_node("CashPhysics")
	_eq(extra.tokens.size(), 60, "old overflow saves respect the physical coin limit")
	extra.unbank()
	_eq(extra.tokens.size(), 60, "refunding overflow does not delete a visible coin")
	_eq(int(overflow.get_meta(cabinet.CASH_COINS_META)), 79, "overflow refund decrements the saved count")
	_finish()
