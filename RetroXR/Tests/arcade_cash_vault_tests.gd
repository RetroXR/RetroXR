## A generated cabinet's cash vault with a loaded tray pulled out of it: a real cabinet standing on a floor (the room's own
## system scene, no mod), its coin panel opened, thirty coins banked, the tray taken by a hand and pulled out as an arm does.
## A held tray passes through the cabinet; its coins do not, so whatever of the cabinet stands in their way is pushed by them
## (the owner, 2026-11-17: "as i pull the coin box out, it can collide with the cabinet and it moves a bit there").
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

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const COINS := 30
## The pull: this far out of the front, in this long, eased in and out (its fastest 1.2 m/s).
const PULL := 0.4
const PULL_SECONDS := 0.5


func _ready() -> void:
	suite_tag = "cash-vault"
	show_pass_detail = true
	get_tree().create_timer(120).timeout.connect(func() -> void: get_tree().quit(1))
	var floor_body := StaticBody3D.new()
	var floor_col := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(10, 0.1, 10)
	floor_col.shape = floor_shape
	floor_col.position.y = -0.05
	floor_body.add_child(floor_col)
	add_child(floor_body)
	var sys := SYSTEM_SCENE.instantiate() as Node3D
	sys.set("model_id", "arcade_cabinet_generic")
	sys.set("systemid", "arcade")
	add_child(sys)
	sys.add_to_group("spawned")
	await _wait(120)
	var body := sys as RigidBody3D
	var cash := _find_cash(sys)
	var box := cash.get("_seated") as PortCover if cash != null else null
	_ok(cash != null and box != null and not body.freeze, "the cabinet stands by itself, its tray seated in its vault")
	if box == null:
		_finish()
		return
	var cabinet := cash.get_parent() as Node3D
	var room: AABB = cabinet.get_meta(RetroSystemModelArcadeCabinet.CASH_VAULT_META)
	var panel := cash.get("_panel_turn") as Node3D
	var wall := sys.get_node_or_null(ArcadeCashBox.PANEL_WALL) as CollisionShape3D
	# The mouth: from the vault's room forward, where a tray and its coins leave by.
	var mouth := AABB(Vector3(room.position.x, room.position.y, room.end.z - 0.03), Vector3(room.size.x, room.size.y, 0.13)).grow(-0.002)
	var across := 0
	for s in sys.get_children():
		var cs := s as CollisionShape3D
		if cs == null or cs == wall or not cs.shape is BoxShape3D:
			continue
		var bs := (cs.shape as BoxShape3D).size
		var cut := AABB(cs.position - bs * 0.5, bs).intersection(mouth)
		if cut.size.x > 0.001 and cut.size.y > 0.001 and cut.size.z > 0.001:
			across += 1
	_eq(across, 0, "none of the cabinet's fixed boxes stands across the vault's mouth")
	_ok(wall != null and not wall.disabled and (wall.shape as BoxShape3D).size.x > room.size.x - 0.001,
		"shut, the mouth is closed to coins by a wall of the cabinet's own")
	panel.rotation.x = deg_to_rad(ArcadeCashBox.OPEN_DEG)
	await _wait(5)
	_ok(wall != null and wall.disabled, "open, that wall is gone")
	for i in COINS:
		cash.call("_bank_coin", 0)
		await _wait(3)
	await _wait(200)
	var state := box.get_node("CashPhysics")
	var tray := state.get("_tray") as MeshInstance3D
	_eq(_in_box(state, tray), COINS, "thirty coins lie in the seated tray")
	var start := body.global_transform
	var hand := Hand.new()
	add_child(hand)
	hand.global_transform = box.global_transform
	hand._pick_up_object(box)
	await _wait(5)
	var out := sys.global_basis.z.normalized()
	var side := sys.global_basis.x.normalized()
	var from := hand.global_position
	# On its rail (the slot's preview_rail): the tray comes out with the hand from the first centimetre, on the line out of
	# its seat though the hand strays, and goes back in with it. Without the rail it stood in its seat until the hand was
	# some 10 cm out, then caught it up at 2 to 6 m/s.
	var seat := box.global_position
	var behind := 0.0
	var off_line := 0.0
	var hand_out := 0.0
	for i in 30:
		await get_tree().physics_frame
		# (the box as the tick before left it, against the hand of that tick)
		var travel := box.global_position - seat
		behind = maxf(behind, absf(hand_out - travel.dot(out)))
		off_line = maxf(off_line, (travel - out * travel.dot(out)).length())
		hand_out = 0.06 * float(i + 1) / 30.0
		hand.global_position = from + out * hand_out + side * (0.015 * float(i + 1) / 30.0)
	_ok(behind < 0.005 and off_line < 0.002, "the tray comes out with the hand from the first centimetre, on its rail",
		"%.1f mm behind and %.1f mm off the line at most, over 60 mm" % [behind * 1000.0, off_line * 1000.0])
	for i in 30:
		await get_tree().physics_frame
		hand.global_position = from + (out * 0.06 + side * 0.015) * (1.0 - float(i + 1) / 30.0)
	await _wait(3)
	_ok(box.global_position.distance_to(seat) < 0.001, "and goes back in with it", "%.1f mm from its seat" % (box.global_position.distance_to(seat) * 1000.0))
	var ticks := int(PULL_SECONDS * Engine.physics_ticks_per_second)
	var moved := 0.0
	var turned := 0.0
	for i in ticks + 90:
		await get_tree().physics_frame
		hand.global_position = from + out * PULL * smoothstep(0.0, 1.0, minf(1.0, float(i + 1) / ticks))
		moved = maxf(moved, body.global_position.distance_to(start.origin))
		turned = maxf(turned, maxf((body.global_basis.x - start.basis.x).length(), (body.global_basis.y - start.basis.y).length()))
	_ok(box.global_position.distance_to(from + out * PULL) < 0.001, "the tray is out, in the hand")
	_ok(moved < 0.001 and turned < 0.002, "pulling the loaded tray out does not move the cabinet",
		"%.1f mm and %.2f degrees at most" % [moved * 1000.0, rad_to_deg(turned)])
	_eq(_in_box(state, tray), COINS, "and every coin comes out in the tray")
	# Then moved THROUGH the cabinet. A held tray passes through it; its coins are solid, but push nothing (CashPhysics
	# HELD_COIN_LAYER), and near its own slot they do not meet its cabinet at all. On their own layers they shoved the cabinet
	# 60 to 115 mm on each of these legs (an empty tray: nothing).
	start = body.global_transform
	moved = 0.0
	for leg: Vector3 in [Vector3.UP * 0.35 - out * 0.3, Vector3.DOWN * 0.35 + out * 0.3, side * 0.35 - out * 0.45, side * 0.5,
			out * 0.45 - side * 0.85]:
		from = hand.global_position
		for i in 60:
			await get_tree().physics_frame
			hand.global_position = from + leg * smoothstep(0.0, 1.0, float(i + 1) / 60.0)
			moved = maxf(moved, body.global_position.distance_to(start.origin))
		await _wait(20)
		moved = maxf(moved, body.global_position.distance_to(start.origin))
	_ok(moved < 0.001, "moved through the cabinet's deck, front and side, the loaded tray does not move it", "%.1f mm at most" % (moved * 1000.0))
	# What the cabinet scraped out of the tray is a coin of the room's, lying in or by the cabinet, not under the floor.
	var kept := _in_box(state, tray)
	var lost_ok := 0
	var coins := get_tree().get_nodes_in_group(ArcadeToken.GROUP)
	for node in coins:
		var t := node as RigidBody3D
		if (t.collision_layer & 4) != 0 and t.global_position.y > -0.02:
			lost_ok += 1
	_ok(kept + lost_ok == coins.size() and coins.size() == COINS, "every coin is in the tray or a coin of the room's above the floor",
		"%d in the tray, %d of the room's, of %d" % [kept, lost_ok, coins.size()])
	hand.drop_object()
	await _wait(3)
	var own := 0
	for node in coins:
		if ((node as RigidBody3D).collision_layer & 4) != 0:
			own += 1
	_eq(own, COINS, "let go, every coin is the room's again")
	panel.rotation.x = 0.0
	await _wait(5)
	_ok(wall != null and not wall.disabled, "shut again, the wall stands again")
	_finish()


func _wait(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _find_cash(n: Node) -> ArcadeCashBox:
	if n is ArcadeCashBox:
		return n as ArcadeCashBox
	for c in n.get_children():
		var got := _find_cash(c)
		if got != null:
			return got
	return null


## How many of the box's coins stand in its tray (the tray as their collider has it).
func _in_box(state: Node, tray: MeshInstance3D) -> int:
	var frame: Transform3D = state.call("tray_frame")
	var inv := frame.affine_inverse()
	var count := 0
	for t: Variant in state.get("tokens"):
		if is_instance_valid(t) and tray.mesh.get_aabb().grow(0.008).has_point(inv * (t as Node3D).global_position):
			count += 1
	return count
