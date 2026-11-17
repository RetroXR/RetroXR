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
## While set, every frame adds how far each coin in the tray is drawn from its place in it (_process).
var _watch_drawn := false
var _drawn_sum := 0.0
var _drawn_count := 0


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
		local_before.append(_in_tray(token))
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
		shift = maxf(shift, _in_tray(cabinet._cash_tokens[i]).distance_to(local_before[i]))
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
	return tray.mesh.get_aabb().grow(0.008).has_point(_in_tray(token))


## Where a coin's body is in the tray: the tray as its collider has it (CashPhysics.tray_frame), which trails the drawn tray
## while the box is carried.
func _in_tray(token: RigidBody3D) -> Vector3:
	var state := box.get_node_or_null("CashPhysics")
	var frame: Transform3D = state.tray_frame() if state != null else tray.global_transform
	return frame.affine_inverse() * token.global_position


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
			await _capture()


func _capture() -> void:
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
		var hold := box.get("_grab_driver") as Node3D
		var off_hold := 0.0
		var peak := 0.0
		var last := box.global_position
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
			off_hold = maxf(off_hold, box.global_position.distance_to(hold.global_position))
			# (its axes against the hold's, about a radian each: a quaternion's angle is good to a milliradian only)
			off_hold = maxf(off_hold, maxf((box.global_basis.x - hold.global_basis.x).length(), (box.global_basis.z - hold.global_basis.z).length()))
			peak = maxf(peak, box.global_position.distance_to(last) * Engine.physics_ticks_per_second)
			last = box.global_position
			for token in previous_tokens:
				var id := token.get_instance_id()
				var at := _in_tray(token)
				if at.y >= bounds.end.y - 0.004:
					escaped_top[id] = true
				if not escaped_top.has(id) and not bounds.grow(0.025).has_point(at):
					leaked[id] = true
		_ok(leaked.is_empty(), "%s cannot pass through a solid wall" % leg, "%d leaks, %d through open top" % [leaked.size(), escaped_top.size()])
		# The box itself is never slowed for its coins' sake (it was eased and held to 3 m/s until 2026-11-17).
		_ok(off_hold < 0.0001 and (leg == "spin" or peak > 4.0), "%s: the box is where its hold puts it, at the speed asked" % leg,
			"%.4f off at most, %.1f m/s at its fastest" % [off_hold, peak])
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


## A box seated in its slot stands on its seat, whatever handed it there and wherever the slot then goes (the owner, 2026-11-17:
## set in the cabinet and moved a bit, it "appears to be jumping up in to the cabinet in an odd area and then back down every
## other frame"). The other legs seat the box where it already stands, which is the one case that never showed it.
func _run_seated() -> void:
	suite_tag = "cash-seated"
	record = OS.get_cmdline_user_args().has("--record")
	get_tree().create_timer(120).timeout.connect(func() -> void: get_tree().quit(1))
	_setup()
	await _frames(5)
	var zone := cabinet._cash_zone
	# (a recording watches the seat from a fixed place, so the box is SEEN to stand or to move; following the box, as the
	# other legs' does, a box that jumped looked still)
	camera_focus = Node3D.new()
	add_child(camera_focus)
	camera_focus.global_position = box.global_position + Vector3(0.1, 0.12, 0.05)
	camera.fov = 60
	# Empty, carried off and handed back to its slot from there (as a restore or a throw at the slot does).
	hand.global_transform = box.global_transform
	hand._pick_up_object(box)
	await _move(Vector3(0, 0.3, 0), 60)
	await _frames(30)
	hand.drop_object()
	zone.pick_up_object(box)
	await _frames(90)
	var rest := await _rest(zone)
	_ok(rest.x < 0.0001, "handed to its slot, the box stays still", "%.4f m of travel" % rest.x)
	_ok(rest.y < 0.0001, "handed to its slot, the box and its coin collider are on the seat", "%.4f m off" % rest.y)
	# Full, in a slot that moves (its cabinet carried) and stops.
	box.get_node("CashPhysics").free()
	box.set_meta(cabinet.CASH_COINS_META, 60)
	cabinet._cash_solid(box)
	await _frames(240)
	_eq(_contained(), 60, "the seated box holds sixty coins")
	var mount := zone.get_parent() as Node3D
	var from := mount.position
	var trail := 0.0
	var drawn := 0.0
	for i in 30:
		await get_tree().physics_frame
		mount.position = from + Vector3(0.2, 0.0, 0.1) * smoothstep(0.0, 1.0, float(i + 1) / 30.0)
		await _shown()
		# (from the second tick: a grab driver at rest in a zone is woken by the zone's move a tick late, as for every seated thing)
		if i > 0:
			trail = maxf(trail, box.global_position.distance_to(zone.snap_pose_for(box).origin))
		drawn = maxf(drawn, _drawn_error())
	_ok(trail < 0.0001, "the box moves with its slot, never behind it", "%.4f m behind at most" % trail)
	_ok(drawn < 0.0001, "in a moving slot the coins are drawn where they stand in the tray", "%.4f m off at most" % drawn)
	await _frames(5)
	rest = await _rest(zone)
	_ok(rest.x < 0.0001, "its slot stopped, the box stays still", "%.4f m of travel" % rest.x)
	_ok(rest.y < 0.0001, "its slot stopped, the box and its coin collider are on the seat", "%.4f m off" % rest.y)
	_eq(_contained(), 60, "a moving slot keeps all sixty coins")
	# The slot drops in one tick (a carried cabinet let go onto the floor).
	mount.position.y -= 0.05
	await _frames(5)
	rest = await _rest(zone)
	_ok(rest.x < 0.0001, "its slot dropped, the box stays still", "%.4f m of travel" % rest.x)
	_ok(rest.y < 0.0001, "its slot dropped, the box and its coin collider are on the seat", "%.4f m off" % rest.y)
	await _frames(60)
	_ok(_contained() >= 55, "a dropped slot keeps the pile", "%d remain" % _contained())
	# Carried at speed: the box is where the hand has it, the coin collider trails it, and the coins are drawn in the tray.
	# (the recording follows the box from here)
	camera_focus.queue_free()
	camera_focus = null
	camera.fov = 40
	box.get_node("CashPhysics").free()
	for token in get_tree().get_nodes_in_group(ArcadeToken.GROUP):
		token.free()
	box.set_meta(cabinet.CASH_COINS_META, 60)
	cabinet._cash_solid(box)
	await _frames(240)
	hand.global_transform = box.global_transform
	hand._pick_up_object(box)
	await _move(Vector3(0, 0.3, 0), 45)
	await _frames(30)
	_eq(_contained(), 60, "lifted out of its slot with sixty coins")
	# (a table just under the swing, to be let go over)
	var worn := CoverSlots.worn_part(box)
	var low := INF
	for i in 8:
		low = minf(low, (worn.global_transform * worn.get_aabb().get_endpoint(i)).y)
	var table := StaticBody3D.new()
	var top := CollisionShape3D.new()
	var slab := BoxShape3D.new()
	slab.size = Vector3(4, 0.1, 4)
	top.shape = slab
	table.add_child(top)
	add_child(table)
	table.global_position = Vector3(box.global_position.x, low - 0.02 - 0.05, box.global_position.z)
	var hold := box.get("_grab_driver") as Node3D
	var shell := box.get_node("CashCoinCollider") as Node3D
	# The box JUMPS to the hand: a seated one stays in its seat until the hand is some 10 cm out, then catches it up at 2 to
	# 6 m/s. Its coin collider goes after it no harder than MAX_CARRY_ACCEL, and no coin is thrown (0 to 7 of 30 were, by an
	# ordinary pull, while the collider went after the box at 2 to 6 g).
	var tps := float(Engine.physics_ticks_per_second)
	var limit: float = box.get_node("CashPhysics").MAX_CARRY_ACCEL
	var shell_last := shell.global_position
	var shell_speed := 0.0
	var hardest := 0.0
	var fastest := 0.0
	for i in 70:
		await get_tree().physics_frame
		if i < 3:
			# 0.3 m in three ticks
			hand.position.x += 0.1
		var speed := shell.global_position.distance_to(shell_last) * tps
		hardest = maxf(hardest, absf(speed - shell_speed) * tps)
		fastest = maxf(fastest, speed)
		shell_speed = speed
		shell_last = shell.global_position
	_ok(fastest > 0.5 and hardest < limit * 1.1, "the box jumps to the hand: its coin collider goes after it gently",
		"%.1f m/s2 at its hardest, %.1f m/s at its fastest" % [hardest, fastest])
	_ok(shell.global_position.distance_to(box.global_position) < 0.0001, "and reaches it", "%.4f m off" % shell.global_position.distance_to(box.global_position))
	_eq(_contained(), 60, "and no coin is thrown")
	var off_hold := 0.0
	var behind := 0.0
	drawn = 0.0
	_watch_drawn = true
	for i in 40:
		await get_tree().physics_frame
		# 1.1 m/s
		hand.position.x += 1.1 / Engine.physics_ticks_per_second
		await _shown()
		off_hold = maxf(off_hold, box.global_position.distance_to(hold.global_position))
		drawn = maxf(drawn, _drawn_error())
		behind = maxf(behind, shell.global_position.distance_to(box.global_position))
	_watch_drawn = false
	_ok(off_hold < 0.0001, "carried, the box is where its hold puts it", "%.4f m off at most" % off_hold)
	_ok(behind > 0.01, "carried at speed, the coin collider trails the box", "%.4f m behind" % behind)
	_ok(drawn < 0.0001, "carried, the coins are drawn where they stand in the tray", "%.4f m off at most" % drawn)
	# Between ticks too: the poses a frame is DRAWN from are interpolated (the project's physics interpolation), the tray's and
	# each coin mesh's. Drawn on their bodies the coins trail the tray by 66 mm here; a few slide as the swing starts.
	var drawn_mean := _drawn_sum / maxf(_drawn_count, 1)
	_ok(_drawn_count > 0 and drawn_mean < 0.001, "carried, every frame draws the coins in the tray", "%.4f m off on average" % drawn_mean)
	# Let go mid-swing: the coins end in the box, not where their collider trailed it.
	hand.drop_object()
	await _frames(2)
	_eq(_contained(), 60, "let go mid-swing, the coins are in the box")
	await _frames(150)
	_ok(_contained() >= 55, "and stay in it as it lands", "%d remain" % _contained())
	_finish()


## Over `ticks`: how far the box travelled (x) and the farthest it or its coin collider stood from the slot's seat (y).
func _rest(zone: XRToolsSnapZone, ticks: int = 60) -> Vector2:
	var lo := Vector3.ONE * INF
	var hi := Vector3.ONE * -INF
	var off := 0.0
	var shell := box.get_node_or_null("CashCoinCollider") as Node3D
	for i in ticks:
		await _frames(1)
		var at := box.global_position
		lo = lo.min(at)
		hi = hi.max(at)
		var seat := zone.snap_pose_for(box).origin
		off = maxf(off, at.distance_to(seat))
		if shell != null:
			off = maxf(off, shell.global_position.distance_to(box.global_position))
	return Vector2((hi - lo).length(), off)


## From the start of a physics tick (where a test moves what it moves) to the frame that draws it: the box is then where its
## hold put it this tick, and the coins' bodies, their collider and their meshes are all of one step.
func _shown() -> void:
	await get_tree().process_frame
	if record:
		await _capture()


## What a frame draws while _watch_drawn: the interpolated tray and coin meshes, each coin's place in that tray against its
## body's in the tray as its collider has it.
func _process(_delta: float) -> void:
	if not _watch_drawn:
		return
	var state := box.get_node_or_null("CashPhysics")
	if state == null:
		return
	var drawn_tray := tray.get_global_transform_interpolated().affine_inverse()
	for token in cabinet._cash_tokens:
		if token.freeze or not _inside(token):
			continue
		var at := drawn_tray * (token.get_node("Mesh") as Node3D).get_global_transform_interpolated().origin
		_drawn_sum += at.distance_to(_in_tray(token))
		_drawn_count += 1


## The farthest a coin in the tray is DRAWN from where its body stands in it: its mesh in the drawn tray, against its body in
## the tray as its collider has it. Read after _shown.
func _drawn_error() -> float:
	var worst := 0.0
	for token in cabinet._cash_tokens:
		if token.freeze or not _inside(token):
			continue
		var at := tray.to_local((token.get_node("Mesh") as Node3D).global_position)
		worst = maxf(worst, at.distance_to(_in_tray(token)))
	return worst
