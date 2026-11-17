## Real Jolt, real pick_up/let_go; synthetic tray needs no mod, ROM or headset.
extends "res://Tests/test_suite.gd"

class Hand extends Node3D:
	var picked_up_ranged := false
	var held: XRToolsPickable
	func drop_object(v := Vector3.ZERO, w := Vector3.ZERO) -> void:
		if is_instance_valid(held):
			held.let_go(self, v, w)
			held = null
	func _pick_up_object(obj: XRToolsPickable) -> void:
		if obj.is_picked_up():
			obj.drop()
		held = obj
		obj.pick_up(self)

var cabinet: ArcadeCabinetFromModel
var box: PortCover
var hand: Hand
var tray: MeshInstance3D
var record := false
var frame := 0
var record_dir := "res://../build_out/coin_frames"
var camera_focus: Node3D
var camera: Camera3D


func _ready() -> void:
	suite_tag = "cash"
	show_pass_detail = true
	record = OS.get_cmdline_user_args().has("--record")
	get_tree().create_timer(90).timeout.connect(func() -> void: get_tree().quit(1))
	_setup()
	await _frames(5)
	# Production acceptance path, one token falling into a seated tray.
	cabinet._bank_coin(0)
	var first := cabinet._cash_tokens[0]
	var start_y := first.global_position.y
	await _frames(180)
	_ok(first.global_position.y < start_y - 0.03, "accepted coin falls under gravity")
	_ok(_inside(first), "accepted coin settles inside the tray")
	_ok(not first.freeze and first.linear_velocity.length() < 0.03, "settled coin remains a free rigid body")
	cabinet._unbank_coin(0)
	await _frames(2)
	_eq(int(box.get_meta(cabinet.CASH_COINS_META)), 0, "refund removes the banked count")
	_eq(cabinet._cash_tokens.size(), 0, "refund removes its physical coin")
	# A full restored box, including stacks; no eight-rider query cap.
	# Recreate the transient owner as on scene load; seating a live empty box
	# must never use an old saved count to refill it.
	box.get_node("CashPhysics").free()
	box.set_meta(cabinet.CASH_COINS_META, 60)
	cabinet._cash_solid(box)
	await _frames(240)
	_eq(cabinet._cash_tokens.size(), 60, "restore creates all sixty coins")
	_eq(_contained(), 60, "full box settles without losing coins")
	var coin := cabinet._cash_tokens[0]
	var before := coin.global_position
	cabinet._cash_seat_tokens(box)
	_ok(coin.global_position.is_equal_approx(before), "reseating does not rewrite a live coin pose")
	var floor_shape := (box.get_node("CollisionShape3D") as CollisionShape3D).shape
	hand.global_transform = box.global_transform
	hand._pick_up_object(box)
	await _frames(10)
	_ok((box.get_node("CollisionShape3D") as CollisionShape3D).shape == floor_shape,
		"unseating and pointer refresh preserve the tray floor")
	_ok(_all_loose(), "picking up the tray never freezes its coins")
	await _move(Vector3(0.3, 0.5, 0), 150)
	_eq(_contained(), 60, "lifting and carrying retains all sixty coins")
	# Another hand can take a coin without inheriting a frozen carry state.
	var other := Hand.new()
	add_child(other)
	other.global_transform = coin.global_transform
	other._pick_up_object(coin as XRToolsPickable)
	await _frames(3)
	other.drop_object()
	await _frames(90)
	_ok(not coin.freeze and _inside(coin), "coin taken from held tray returns to normal physics")
	other.queue_free()
	# Put the loaded tray down a few centimetres above a solid table.
	var table := StaticBody3D.new()
	var top := CollisionShape3D.new()
	var slab := BoxShape3D.new()
	slab.size = Vector3(1, 0.1, 1)
	top.shape = slab
	table.add_child(top)
	table.position = Vector3(0.3, 0.65, 0)
	add_child(table)
	hand.drop_object()
	await _frames(180)
	_ok(not box.freeze and _all_loose(), "loaded tray and coins remain dynamic on release")
	_ok(_contained() >= 55, "setting down retains the loose pile", "%d remain" % _contained())
	# It stands on its drawn bottom, not on a collision floor hung under it, and stays still there (the owner, 2026-11-17: "the
	# coin box will rather jump up and down when I set it down").
	var worn := CoverSlots.worn_part(box)
	var drawn := worn.get_aabb()
	var low := INF
	for i in 8:
		low = minf(low, (worn.global_transform * drawn.get_endpoint(i)).y)
	_ok(absf(low - 0.70) < 0.003, "set down, the box stands on its drawn bottom", "%.4f m above the table" % (low - 0.70))
	var ys: Array[float] = []
	for i in 60:
		await _frames(1)
		ys.append(box.global_position.y)
	_ok(ys.max() - ys.min() < 0.001, "set down, the box stays still", "%.4f m of travel" % (ys.max() - ys.min()))
	hand.global_transform = box.global_transform
	hand._pick_up_object(box)
	await _move(Vector3(0, 0.2, 0), 90)
	table.queue_free()
	var local_before: Array[Vector3] = []
	for token in cabinet._cash_tokens:
		local_before.append(tray.to_local(token.global_position))
	await _move(Vector3(-0.25, 0, 0), 45)
	await _frames(30)
	_ok(_contained() > 30, "shaking does not lose the pile through the floor", "%d remain" % _contained())
	_ok(_all_loose(), "shaking leaves coins unfrozen")
	# Tilt progressively: contents must slide before the old 40-degree trigger.
	var upright := hand.global_basis
	for i in 90:
		hand.global_basis = Basis(Vector3.BACK, deg_to_rad(35.0) * float(i + 1) / 90.0) * upright
		await _frames(1)
	await _frames(90)
	# A gentle shake can legitimately stick through static friction. At 35 degrees
	# gravity exceeds the coin's friction, so relative motion is required even
	# below the old scripted 40-degree release threshold.
	var shift := 0.0
	for i in cabinet._cash_tokens.size():
		shift = maxf(shift, tray.to_local(cabinet._cash_tokens[i].global_position).distance_to(local_before[i]))
	_ok(shift > 0.003, "shake and tilt move coins relative to the tray", "shift %.4f m" % shift)
	_ok(_all_loose(), "coins remain dynamic below the old spill threshold")
	for i in 120:
		hand.global_basis = Basis(Vector3.BACK, deg_to_rad(35.0 + 95.0 * float(i + 1) / 120.0)) * upright
		await _frames(1)
	await _frames(120)
	_ok(_contained() < 10, "tipping spills coins through the open top", "%d remain" % _contained())
	cabinet._cash_watch_tick()
	_ok(int(box.get_meta(cabinet.CASH_COINS_META)) < 10, "spilled coins leave the saved count")
	hand.drop_object()
	await _frames(120)
	_ok(not box.freeze, "released tray returns to rigid-body physics")
	# Ray pickup uses a separate path, with no body picked_up signal.
	var ray := XRToolsFunctionPickup.new()
	add_child(ray)
	ray.set_physics_process(false)
	ray.set_process(false)
	ray._start_ray_grab_at(box, 1.0)
	await _frames(3)
	_ok(box.get_node("CashPhysics").coin_layer_active(), "ray grab keeps the coin collider active")
	ray._release_ray_for_transfer()
	await _frames(3)
	_ok(not box.get_node("CashPhysics").coin_layer_active() and not box.freeze, "ray release restores ordinary box collision")
	ray.queue_free()
	_finish()


func _setup() -> void:
	var floor_body := StaticBody3D.new()
	var floor_col := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(5, 0.1, 5)
	floor_col.shape = floor_shape
	floor_col.position.y = -0.05
	floor_body.add_child(floor_col)
	add_child(floor_body)
	cabinet = ArcadeCabinetFromModel.new()
	add_child(cabinet)
	box = preload("res://Scenes/Objects/port_cover.tscn").instantiate()
	box.position = Vector3(0, 0.3, 0)
	box.freeze = true
	box.release_mode = XRToolsPickable.ReleaseMode.UNFROZEN
	add_child(box)
	var source := Node3D.new()
	add_child(source)
	tray = _tray_part()
	source.add_child(tray)
	var out := _tray_out()
	box.size = CoverSlots.part_size(tray, out)
	box.global_basis = CoverSlots.part_seat(tray, out).basis
	CoverSlots.wear(box, tray, out)
	tray.visible = not _draw_collision_tray()
	# The hidden original stays in the cabinet; only its copy wears the cover.
	var deposit := tray.duplicate() as MeshInstance3D
	source.add_child(deposit)
	deposit.global_transform = tray.global_transform
	deposit.visible = false
	cabinet._cash_source = deposit
	cabinet._cash_box = box
	var slots := CoverSlots.new()
	add_child(slots)
	var seat_parent := Node3D.new()
	add_child(seat_parent)
	var zone := CoverSlots.make_zone("CashBoxSeat", "", 0.12, seat_parent)
	zone.add_to_group(CoverSlots.SLOT_GROUP)
	zone.global_transform = box.global_transform
	zone.has_picked_up.connect(slots._on_seated)
	zone.pick_up_object(box)
	cabinet._cash_zone = zone
	cabinet._cash_solid(box)
	hand = Hand.new()
	add_child(hand)
	# Render the exact collision geometry, so the recording also reveals tunnelling.
	if _draw_collision_tray():
		for child in box.get_children():
			if child is CollisionShape3D:
				var mesh := MeshInstance3D.new()
				var shape := BoxMesh.new()
				shape.size = (child.shape as BoxShape3D).size
				mesh.mesh = shape
				mesh.transform = child.transform
				box.add_child(mesh)
	camera = Camera3D.new()
	add_child(camera)
	camera.fov = 40
	camera.position = box.global_position + Vector3(0.35, 0.55, 0.4)
	camera.look_at(box.global_position)
	camera.current = true
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -30, 0)
	add_child(light)
	if record:
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--record-dir="):
				record_dir = arg.substr(13)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(record_dir))


func _tray_part() -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = "CashBoxLiftOff"
	var bounds := BoxMesh.new()
	bounds.size = Vector3(0.22, 0.08, 0.18)
	part.mesh = bounds
	return part


func _tray_out() -> Vector3:
	return Vector3.UP


func _draw_collision_tray() -> bool:
	return true


func _inside(token: RigidBody3D) -> bool:
	return tray.mesh.get_aabb().grow(0.008).has_point(tray.to_local(token.global_position))


func _contained() -> int:
	var count := 0
	for token in cabinet._cash_tokens:
		if _inside(token):
			count += 1
	return count


func _all_loose() -> bool:
	for token in cabinet._cash_tokens:
		if token.freeze:
			return false
	return true


func _move(offset: Vector3, frames: int) -> void:
	var from := hand.position
	for i in frames:
		hand.position = from + offset * smoothstep(0.0, 1.0, float(i + 1) / frames)
		await _frames(1)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
		if record:
			var focus := camera_focus.global_position if camera_focus != null else box.global_position
			camera.global_position = focus + Vector3(0.35, 0.55, 0.4)
			camera.look_at(focus)
			await RenderingServer.frame_post_draw
			if frame % 3 == 0:
				get_viewport().get_texture().get_image().save_png(record_dir.path_join("%05d.png" % frame))
			frame += 1


func _run_fast() -> void:
	suite_tag = "cash-fast"
	record = OS.get_cmdline_user_args().has("--record")
	get_tree().create_timer(120).timeout.connect(func() -> void: get_tree().quit(1))
	_setup()
	var start := box.global_transform
	var previous_tokens: Array[RigidBody3D] = []
	for leg in ["side", "lift", "spin"]:
		hand.drop_object()
		for token in previous_tokens:
			if is_instance_valid(token):
				token.free()
		box.freeze = true
		box.global_transform = start
		box.linear_velocity = Vector3.ZERO
		box.angular_velocity = Vector3.ZERO
		box.get_node("CashPhysics").free()
		box.set_meta(cabinet.CASH_COINS_META, 60)
		cabinet._cash_solid(box)
		await _frames(180)
		previous_tokens.assign(cabinet._cash_tokens)
		_eq(previous_tokens.size(), 60, "%s starts with sixty coins" % leg)
		hand.global_transform = box.global_transform
		hand._pick_up_object(box)
		await _frames(10)
		var from := hand.global_transform
		var escaped_top := {}
		var leaked := {}
		var bounds := tray.mesh.get_aabb()
		for tick in 100:
			# 4.5 m/s peak translation; 675 degrees/s peak yaw.
			var t := minf(float(tick + 1) / (36.0 if leg == "spin" else 18.0), 1.0)
			if leg == "spin":
				hand.global_basis = Basis(Vector3.UP, PI * smoothstep(0, 1, t)) * from.basis
			else:
				hand.global_position = from.origin + (Vector3.RIGHT if leg == "side" else Vector3.UP) * 0.6 * smoothstep(0, 1, t)
			await _frames(1)
			for token in previous_tokens:
				var id := token.get_instance_id()
				var at := tray.to_local(token.global_position)
				if at.y >= bounds.end.y - 0.004:
					escaped_top[id] = true
				if not escaped_top.has(id) and not bounds.grow(0.025).has_point(at):
					leaked[id] = true
		_ok(leaked.is_empty(), "%s cannot pass through a solid wall" % leg, "%d leaks, %d through open top" % [leaked.size(), escaped_top.size()])
	_finish()


func _run_no_box() -> void:
	suite_tag = "cash-no-box"
	record = OS.get_cmdline_user_args().has("--record")
	get_tree().create_timer(90).timeout.connect(func() -> void: get_tree().quit(1))
	_setup()
	camera_focus = Node3D.new()
	add_child(camera_focus)
	camera_focus.global_position = box.global_position
	hand.global_transform = box.global_transform
	hand._pick_up_object(box)
	await _move(Vector3(0.45, 0, 0), 60)
	_ok(cabinet._cash_zone.picked_up_object == null, "box is removed from its slot")
	var before := get_tree().get_nodes_in_group(ArcadeToken.GROUP)
	cabinet._bank_coin(0)
	var after := get_tree().get_nodes_in_group(ArcadeToken.GROUP)
	_eq(after.size(), before.size() + 1, "acceptance without a box creates one physical coin")
	if after.size() != before.size() + 1:
		_finish()
		return
	var token := after.back() as ArcadeToken
	var inner := cabinet._cash_inner(cabinet._cash_source.mesh.get_aabb())
	var at := cabinet._cash_source.to_local(token.global_position)
	_ok(is_equal_approx(at.y, inner.position.y + 0.06) and at.x >= inner.position.x and at.x <= inner.end.x and at.z >= inner.position.z and at.z <= inner.end.z,
		"coin starts in the cabinet's deposit volume, not the removed box")
	_eq(int(box.get_meta(cabinet.CASH_COINS_META, 0)), 0, "missing-box deposit does not increase the removed box's count")
	var start_y := token.global_position.y
	await _frames(180)
	_ok(not token.freeze and token.global_position.y < start_y - 0.1 and absf(token.global_position.y) < 0.03,
		"coin falls freely and lands on the room floor")
	# Moving the cabinet moves its deposit point; it must not be a cached world pose.
	cabinet._cash_source.get_parent().position += Vector3(0, 0.4, 0.2)
	cabinet._bank_coin(1)
	var next := get_tree().get_nodes_in_group(ArcadeToken.GROUP).back() as ArcadeToken
	at = cabinet._cash_source.to_local(next.global_position)
	_ok(next != token and is_equal_approx(at.y, inner.position.y + 0.06), "deposit follows the cabinet after it moves")
	await _frames(120)
	_finish()
