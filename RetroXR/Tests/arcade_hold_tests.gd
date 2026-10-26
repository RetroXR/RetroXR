## Arcade cabinet self-tests — a cabinet in a hand is not solid and is never thrown. Headless, no core, no ROM, no headset.
##
##     "$godot" --headless --path RetroXR res://Tests/arcade_hold_tests.tscn
##     "$godot" --headless --path RetroXR res://Tests/arcade_hold_tests.tscn -- --only=throw
##
## A hand is faked (a Node3D with `drop_object` and `_pick_up_object`, the two methods XRToolsPickable calls back into: Tools/vr/pad_drop_probe), so the REAL
## pick_up and let_go run on a REAL cabinet with the real HeldObjectPhysics autoload, on a floor of its own. What a headset feels like holding one is OWED.
##
## Groups:
##   held/    carried through loose things at floor level, nothing moves: the cabinet, its bay and its guns are on the held layer with no mask; set down on a
##            cartridge or another cabinet, nothing is thrown
##   throw/   let go of with the arm swinging, a cabinet is set down where the hand was (no speed, no turn); a loose pad still takes the hand's velocity
extends Node3D

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const PAD_SCENE := preload("res://Scenes/Objects/controllers/retro_controller.tscn")
const CART_SCENE := preload("res://Scenes/Objects/media/cartridge.tscn")

var _checks := 0
var _failed := 0
var _only := ""


## The two methods XRToolsPickable calls back into on whatever is holding it.
class FakeHand extends Node3D:
	var picked_up_ranged := false
	var held: Node3D = null

	func drop_object(linear: Vector3 = Vector3.ZERO, angular: Vector3 = Vector3.ZERO) -> void:
		if is_instance_valid(held):
			held.let_go(self, linear, angular)
			held = null

	func _pick_up_object(o: Node3D) -> void:
		held = o
		o.pick_up(self)


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7)
	get_tree().create_timer(150.0).timeout.connect(func() -> void:
		print("[hold] TIMED OUT")
		get_tree().quit(1))
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(12, 0.2, 12)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0, -0.1, 0)
	add_child(floor_body)
	if _want("held"):
		await _group_held()
	if _want("throw"):
		await _group_throw()
	print("[hold] %d checks, %d failed" % [_checks, _failed])
	print("[hold] RESULT=%s" % ("PASS" if _failed == 0 else "FAIL"))
	get_tree().quit(1 if _failed > 0 else 0)


func _ok(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
	print("[hold] %s  %s" % ["PASS" if ok else "FAIL", what])


func _want(group: String) -> bool:
	return _only.is_empty() or _only == group


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## A cabinet standing at `at`, dressed for `romset` (its guns, its bay: the things that ride with it).
func _cabinet(at: Vector3, romset: String = "") -> RetroSystem:
	var sys := SYSTEM_SCENE.instantiate() as RetroSystem
	sys.model_id = ArcadeProfiles.CABINET_MODEL_ID
	sys.systemid = "arcade"
	sys.position = at
	add_child(sys)
	sys.add_to_group("spawned")
	await _frames(20)
	if not romset.is_empty():
		var model := sys.get_model() as RetroSystemModelArcadeCabinet
		var base := ArcadeCabinetSpecs.variant("generic")
		base["variant"] = "generic"
		var profile := ArcadeGameProfile.for_romset(romset)
		model.morph_to(ArcadeCabinetSpecs.for_game(base, profile))
		model.apply_game_profile(profile)
		await _frames(30)
	return sys


func _group_held() -> void:
	var cab := await _cabinet(Vector3(-1.5, 0.0, 0.0), "timecris")
	var pad := PAD_SCENE.instantiate() as RetroController
	pad.position = Vector3(0.0, 0.3, 0.0)
	add_child(pad)
	var cart := CART_SCENE.instantiate() as Node3D
	cart.position = Vector3(0.4, 0.3, 0.1)
	add_child(cart)
	var other := await _cabinet(Vector3(1.4, 0.0, 0.0))
	await _frames(60)
	var hand := FakeHand.new()
	add_child(hand)
	hand.global_position = cab.global_position
	hand._pick_up_object(cab)
	await _frames(2)
	# Not solid: the cabinet, its bay and the guns it carries are on the held layer and see nothing.
	var held_layer := cab.picked_up_layer
	var carried: Array[RigidBody3D] = [cab]
	for gun: Variant in cab.captive_controllers():
		if is_instance_valid(gun):
			carried.append(gun as RigidBody3D)
	for unit in find_children("*", "ArcadeBayUnit", true, false):
		carried.append(unit as RigidBody3D)
	var solid: Array[String] = []
	for body: RigidBody3D in carried:
		if body.collision_layer != held_layer or body.collision_mask != 0:
			solid.append("%s %d/%d" % [body.name, body.collision_layer, body.collision_mask])
	_ok(carried.size() >= 2 and solid.is_empty(),
		"held: the cabinet and what rides with it (%d bodies) are on the held layer and see nothing%s" % [carried.size(), "" if solid.is_empty() else " (solid: " + ", ".join(solid) + ")"])
	# ... and what is loose has the held layer out of its own mask (HeldObjectPhysics): a loose body would otherwise go on colliding from its side.
	_ok((pad.collision_mask & held_layer) == 0 and (cart as RigidBody3D).collision_mask & held_layer == 0 and (other.collision_mask & held_layer) == 0,
		"held: and no loose pickable's mask has the held layer in it")
	# Carried through a pad, a cartridge and another cabinet at floor level, none of them is moved.
	var from := {"pad": pad.global_position, "cart": cart.global_position, "other": other.global_position}
	var moved := {"pad": 0.0, "cart": 0.0, "other": 0.0}
	var steps := 90
	for i in steps:
		hand.global_position = Vector3(lerpf(-1.5, 1.0, float(i) / float(steps - 1)), 0.0, 0.0)
		await _frames(1)
		moved["pad"] = maxf(moved["pad"], pad.global_position.distance_to(from["pad"]))
		moved["cart"] = maxf(moved["cart"], cart.global_position.distance_to(from["cart"]))
		moved["other"] = maxf(moved["other"], other.global_position.distance_to(from["other"]))
	_ok(cab.global_position.distance_to(Vector3(1.0, 0.0, 0.0)) < 0.05 and float(moved["pad"]) < 0.001 and float(moved["cart"]) < 0.001 and float(moved["other"]) < 0.001,
		"held: carried through a pad, a cartridge and another cabinet, none is moved (%.4f, %.4f, %.4f m)" % [moved["pad"], moved["cart"], moved["other"]])
	# Set down inside the other cabinet: nothing is flung.
	hand.global_position = Vector3(1.2, 0.0, 0.0)
	await _frames(5)
	hand.drop_object()
	var fastest := 0.0
	for i in 90:
		await _frames(1)
		fastest = maxf(fastest, maxf(cab.linear_velocity.length(), other.linear_velocity.length()))
	_ok(fastest < 1.0, "held: set down inside another cabinet, neither is flung (%.2f m/s at the most)" % fastest)
	# Set down on a cartridge and a pad lying on the floor.
	hand._pick_up_object(cab)
	hand.global_position = Vector3(-0.3, 0.0, 0.0)
	await _frames(5)
	pad.global_position = Vector3(-0.3, 0.013, 0.0)
	cart.global_position = Vector3(-0.1, 0.04, 0.1)
	for body: RigidBody3D in [pad, cart as RigidBody3D]:
		body.linear_velocity = Vector3.ZERO
	await _frames(3)
	hand.drop_object()
	var launched := 0.0
	for i in 90:
		await _frames(1)
		launched = maxf(launched, maxf(pad.linear_velocity.length(), (cart as RigidBody3D).linear_velocity.length()))
	_ok(launched < 0.5, "held: set down on a pad and a cartridge, neither is thrown (%.2f m/s at the most)" % launched)
	for n: Node in [cab, other, pad, cart, hand]:
		n.queue_free()
	await _frames(3)


func _group_throw() -> void:
	var cab := await _cabinet(Vector3(0.0, 0.0, 0.0))
	var pad := PAD_SCENE.instantiate() as RetroController
	pad.position = Vector3(3.0, 1.0, 0.0)
	add_child(pad)
	await _frames(5)
	_ok(is_equal_approx(cab.throw_scale(), 0.0) and not pad.has_method("throw_scale"),
		"throw: a cabinet answers that none of the hand's velocity is its own; a pad answers nothing, and is thrown as ever")
	# The arm swinging: 6 m/s sideways and 9 rad/s about the vertical.
	var hand := FakeHand.new()
	add_child(hand)
	hand.global_position = cab.global_position
	hand._pick_up_object(cab)
	await _frames(3)
	var rest := cab.global_position
	hand.drop_object(Vector3(6.0, 1.0, 0.0), Vector3(0.0, 9.0, 0.0))
	_ok(cab.linear_velocity.length() < 0.1 and cab.angular_velocity.length() < 0.1,
		"throw: a cabinet let go of with the arm swinging leaves at no speed and no turn (%.2f m/s, %.2f rad/s)" % [cab.linear_velocity.length(), cab.angular_velocity.length()])
	await _frames(45)
	var travelled := Vector2(cab.global_position.x - rest.x, cab.global_position.z - rest.z).length()
	_ok(travelled < 0.1 and cab.global_basis.y.dot(Vector3.UP) > 0.99,
		"throw: and 45 frames later it is where the hand was (%.3f m), upright" % travelled)
	# The control: a loose pad takes the hand's velocity, so the numbers above are the cabinet's doing and not the harness's.
	hand.global_position = pad.global_position
	hand._pick_up_object(pad)
	await _frames(3)
	hand.drop_object(Vector3(6.0, 1.0, 0.0), Vector3(0.0, 9.0, 0.0))
	_ok(pad.linear_velocity.x > 4.0 and pad.angular_velocity.y > 5.0,
		"throw: while a pad let go of the same way is thrown (%.1f m/s, %.1f rad/s)" % [pad.linear_velocity.x, pad.angular_velocity.y])
	# The laser's release is the headset's: it asks the same question (read from the source, as it cannot be driven without a controller).
	var ray := FileAccess.get_file_as_string("res://addons/godot-xr-tools/functions/function_pickup.gd")
	_ok(ray.contains("released.call(\"throw_scale\")") and ray.contains("* impulse_factor * throw"),
		"throw: a laser's release asks it too (function_pickup.gd, from the source)")
	for n: Node in [cab, pad, hand]:
		n.queue_free()
	await _frames(3)
