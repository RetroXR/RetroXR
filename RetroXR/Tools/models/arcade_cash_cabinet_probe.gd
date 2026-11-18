## A MODEL cabinet's cash box (the installed NAOMI Universal's, or -- --model=xenu.aerocity:cabinet, xenu.blastcity:cabinet):
## its collision is the mod's own convex pieces, which no suite can load (a suite boots with no mods). The cabinet stands on a
## floor, thirty coins are banked, and the box is pulled 0.5 m out the way it lifts off, in 0.6 s. Printed: whether the
## cabinet's collision covers the inside of the box, how many seated coins are in contact with the cabinet's body, and how
## far the pull moved the cabinet and how many coins came out in the box. Read the numbers: it asserts nothing.
##
## 2026-11-17, all three: 0.0 mm and 30 of 30. On their own layers the coins moved the cabinet 19 to 78 mm (18 to 28 of them
## in contact with it at rest); one-way and with no exemption near the slot, a Blast City scraped 4 of 30 out.
extends Node3D

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


func _wait(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _find(n: Node) -> ArcadeCabinetFromModel:
	if n is ArcadeCabinetFromModel and not n is ArcadeCashBox:
		return n as ArcadeCabinetFromModel
	for c in n.get_children():
		var got := _find(c)
		if got != null:
			return got
	return null


func _ready() -> void:
	get_tree().create_timer(170).timeout.connect(func() -> void: get_tree().quit(1))
	var model_id := "xenu.naomiuniversal:cabinet"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--model="):
			model_id = a.substr(8)
	var floor_body := StaticBody3D.new()
	var floor_col := CollisionShape3D.new()
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(10, 0.1, 10)
	floor_col.shape = floor_shape
	floor_col.position.y = -0.05
	floor_body.add_child(floor_col)
	add_child(floor_body)
	await _wait(30)
	var sys := SYSTEM_SCENE.instantiate() as Node3D
	sys.set("model_id", model_id)
	sys.set("systemid", "naomi")
	add_child(sys)
	sys.add_to_group("spawned")
	await _wait(240)
	var body := sys as RigidBody3D
	var cab := _find(sys)
	if cab == null:
		print("[probe] %s: no cabinet built from a model (is the mod installed?)" % model_id)
		get_tree().quit(0)
		return
	var zone := cab.get("_cash_zone") as XRToolsSnapZone
	var source := cab.get("_cash_source") as MeshInstance3D
	if zone == null or source == null:
		print("[probe] %s: this cabinet has no cash box" % model_id)
		get_tree().quit(0)
		return
	var box := zone.picked_up_object as PortCover
	var shapes := 0
	for c in sys.get_children():
		if c is CollisionShape3D:
			shapes += 1
	print("[probe] %s: mass %.1f, frozen %s, %d collision pieces, cash box seated: %s" % [model_id, body.mass, str(body.freeze), shapes, str(box != null)])
	# Is the inside of the box inside the cabinet's own collision?
	var inner: AABB = ArcadeCabinetFromModel._cash_inner(source.mesh.get_aabb())
	var space := get_world_3d().direct_space_state
	var covered := 0
	var samples := 0
	for ix in 3:
		for iz in 3:
			for iy in 2:
				var p := inner.position + Vector3(inner.size.x * (0.15 + 0.35 * ix), 0.004 + 0.03 * iy, inner.size.z * (0.15 + 0.35 * iz))
				var q := PhysicsPointQueryParameters3D.new()
				q.position = source.global_transform * p
				q.collision_mask = 4
				q.collide_with_areas = false
				samples += 1
				for hit in space.intersect_point(q, 8):
					if hit["collider"] == sys:
						covered += 1
						break
	print("[probe] the cabinet's own collision covers %d of %d points inside its cash box" % [covered, samples])
	# (doors out of the way: this is about the cabinet's body)
	for d in sys.find_children("DoorBody", "", true, false):
		(d as CollisionObject3D).collision_layer = 0
	for i in 30:
		cab.call("_bank_coin", 0)
		await _wait(3)
	var start := body.global_transform
	await _wait(240)
	var state := box.get_node_or_null("CashPhysics") if box != null else null
	if state == null:
		print("[probe] no CashPhysics on the box")
		get_tree().quit(0)
		return
	var tray := state.get("_tray") as MeshInstance3D
	var coins: Array = (state.get("tokens") as Array).duplicate()
	for t: RigidBody3D in coins:
		t.contact_monitor = true
		t.max_contacts_reported = 8
	await _wait(60)
	var touching := 0
	var others := {}
	for t: RigidBody3D in coins:
		for o in t.get_colliding_bodies():
			if o == sys:
				touching += 1
			elif not o is ArcadeToken:
				others[str(o.name)] = true
	print("[probe] seated, at rest: %d coins in the box, %d of them touching the cabinet's body; other things touched: %s; the cabinet drifted %.1f mm" % [
		_kept(state, tray, coins), touching, str(others.keys()), body.global_position.distance_to(start.origin) * 1000.0])
	# Pulled out along the way the box comes out.
	var hand := Hand.new()
	add_child(hand)
	hand.global_transform = box.global_transform
	hand._pick_up_object(box)
	await _wait(5)
	var out := zone.global_basis.y.normalized()
	var from := hand.global_position
	start = body.global_transform
	var moved := 0.0
	var met := {}
	for i in 54 + 60:
		await get_tree().physics_frame
		hand.global_position = from + out * 0.5 * smoothstep(0.0, 1.0, minf(1.0, float(i + 1) / 54.0))
		moved = maxf(moved, body.global_position.distance_to(start.origin))
		for t: RigidBody3D in coins:
			for o in t.get_colliding_bodies():
				if o == sys:
					met[t] = true
	var low := 0
	for t: RigidBody3D in coins:
		if t.global_position.y < -0.05:
			low += 1
	print("[probe] pulled 0.5 m out in 0.6 s: the cabinet moved %.1f mm; %d of 30 coins still in the box (%d fell through the floor)" % [
		moved * 1000.0, _kept(state, tray, coins), low])
	get_tree().quit(0)


func _kept(state: Node, tray: MeshInstance3D, coins: Array) -> int:
	var inv := (state.call("tray_frame") as Transform3D).affine_inverse()
	var n := 0
	for t: RigidBody3D in coins:
		if is_instance_valid(t) and tray.mesh.get_aabb().grow(0.008).has_point(inv * t.global_position):
			n += 1
	return n
