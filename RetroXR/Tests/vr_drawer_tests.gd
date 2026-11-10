## VRDrawer and the nightstand that uses it: a drawer taken by its handle (trigger or grip) follows the hand along its
## runners from where it was taken, stops at both ends, coasts on a flick and eases itself shut, a fingertip on its
## front pushes it in (but never one reaching INTO it), the grip never lifts the furniture, its open amount saves, and
## what rests in it rides out with it. The nightstand is turned 90 degrees and moved, so a frame mix-up shows.
##   godot --headless --path RetroXR res://Tests/vr_drawer_tests.tscn [-- --only=<group>]
## Groups: rig contract latch grip coast soft push save carry
extends "res://Tests/test_suite.gd"

const HAND := &"/vr_drawer_tests/hand"
const FAR := Vector3(0, 5, 0)
const NIGHTSTAND := preload("res://Scenes/Objects/furniture/nightstand.tscn")
const CONTRACT := "res://imported-assets/furniture/nightstand/nightstand_contract.json"

class FakePickup extends Node:
	var enabled := true
	var picked_up_object: Node = null

var _hand: XRPositionalTracker
var _ctrl: XRController3D
var _pickup: FakePickup
var _only := ""
var _max_fps := 0


func _ready() -> void:
	suite_tag = "vr_drawer"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7)
	_max_fps = Engine.max_fps
	Engine.max_fps = 60
	_tracked_hand()
	_floor()
	var ns := NIGHTSTAND.instantiate() as Nightstand
	ns.position = Vector3(1.0, 0.0, -0.5)
	ns.rotation_degrees = Vector3(0, 90, 0)
	add_child(ns)
	await _ticks(3)
	if _group("rig"):
		_rig(ns)
	if _group("contract"):
		_contract()
	if _group("latch"):
		await _latch(ns)
	if _group("grip"):
		await _grip(ns)
	if _group("coast"):
		await _coast(ns)
	if _group("soft"):
		await _soft(ns)
	if _group("push"):
		await _push(ns)
	if _group("save"):
		await _save(ns)
	if _group("carry"):
		await _carry(ns)
	XRServer.remove_tracker(_hand)
	Engine.max_fps = _max_fps
	_finish()


func _group(g: String) -> bool:
	return _only == "" or _only == g


# --- the hand ---------------------------------------------------------------------------------------------------------
func _tracked_hand() -> void:
	_hand = XRPositionalTracker.new()
	_hand.name = HAND
	_hand.type = XRServer.TRACKER_CONTROLLER
	XRServer.add_tracker(_hand)
	var origin := XROrigin3D.new()
	add_child(origin)
	_ctrl = XRController3D.new()
	_ctrl.tracker = HAND
	origin.add_child(_ctrl)
	var tip := Node3D.new()
	tip.name = "PokeTip"
	_ctrl.add_child(tip)
	_pickup = FakePickup.new()
	_pickup.name = "FunctionPickup"
	_ctrl.add_child(_pickup)
	_place(FAR)
	_buttons(0.0, 0.0)


func _place(at: Vector3) -> void:
	_hand.set_pose(&"default", Transform3D(Basis(), at), Vector3.ZERO, Vector3.ZERO,
		XRPose.XR_TRACKING_CONFIDENCE_HIGH)


func _buttons(trigger: float, grip: float) -> void:
	_hand.set_input("trigger", trigger)
	_hand.set_input("grip", grip)


func _ticks(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _floor() -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10, 0.2, 10)
	cs.shape = box
	cs.position = Vector3(0, -0.1, 0)
	body.add_child(cs)
	add_child(body)


## The pull's middle in the world, wherever the drawer is now.
func _handle(ns: Nightstand) -> Vector3:
	return ns.global_transform * (Nightstand.DRAWER_HANDLE + ns.drawer_body().position)


## The way the drawer comes out, in the world: the nightstand's +Z.
func _out(ns: Nightstand) -> Vector3:
	return ns.global_basis.z.normalized()


## Shut and still, the hand away with nothing pressed.
func _reset(ns: Nightstand) -> void:
	_buttons(0.0, 0.0)
	_place(FAR)
	await _ticks(3)
	ns.drawer().set_value_no_signal(0.0)
	await _ticks(2)


## Take the handle with `action` ("trigger" / "grip"), the hand `off` metres along the drawer from the pull's middle.
func _take(ns: Nightstand, trigger: float, grip: float, off := 0.0) -> void:
	_place(_handle(ns) + _out(ns) * off)
	await _ticks(3)
	_buttons(trigger, grip)
	await _ticks(3)


# --- groups -----------------------------------------------------------------------------------------------------------
func _rig(ns: Nightstand) -> void:
	var d := ns.drawer()
	_ok(d is VRDrawer and d is VRSlider, "rig/the drawer handle is a VRDrawer (a VRSlider, so saves and netplay know it)")
	_ok(d.is_in_group(ScenePersistence.CONTROL_GROUP), "rig/the drawer is in the save's control group")
	var body_shapes := ns.drawer_body().find_children("Drawer*", "CollisionShape3D", false, false).size()
	_eq(body_shapes, Nightstand.DRAWER_BOXES.size(), "rig/the drawer body has its front, floor and four walls")
	var case_shapes := ns.find_children("Case*", "CollisionShape3D", false, false).size()
	var leg_shapes := ns.find_children("LegShape*", "CollisionShape3D", false, false).size()
	_ok(case_shapes == 6 and leg_shapes == 4, "rig/the case has six boxes and four legs (%d, %d)" % [case_shapes,
		leg_shapes])
	_ok(ns.drawer_body().find_child("Drawer", true, false) is MeshInstance3D
		and ns.drawer_body().find_child("DrawerPull", true, false) is MeshInstance3D,
		"rig/the model's drawer and pull ride on the drawer body")
	_ok(d.handle_mesh != null and d.handle_mesh.name == "DrawerPull", "rig/the handle outlined is the pull")
	_ok(ns.get_collision_exceptions().has(ns.drawer_body()), "rig/the drawer never collides with its own case")
	var leg := ns.get_node("LegShape0") as CollisionShape3D
	var foot_local := leg.transform * Vector3(0, -(leg.shape as CylinderShape3D).height / 2, 0)
	_ok(foot_local.distance_to(Nightstand.LEGS[0][1]) < 0.001, "rig/a leg's cylinder reaches its foot",
		str(foot_local))


func _contract() -> void:
	var c: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT))
	_ok(c is Dictionary, "contract/the model's contract reads")
	if not c is Dictionary:
		return
	var col: Dictionary = c["collision"]
	var same := true
	for pair: Array in [[col["carcass"], Nightstand.CASE_BOXES], [col["drawer"], Nightstand.DRAWER_BOXES]]:
		var rows: Array = pair[0]
		var mine: Array = pair[1]
		same = same and rows.size() == mine.size()
		for i in mini(rows.size(), mine.size()):
			same = same and _v3(rows[i]["centre"]).distance_to(mine[i][0]) < 1e-4 \
				and _v3(rows[i]["size"]).distance_to(mine[i][1]) < 1e-4
	_ok(same, "contract/the case and drawer boxes are the contract's")
	var legs_same := true
	for i in Nightstand.LEGS.size():
		var row: Dictionary = col["legs"][i]
		legs_same = legs_same and _v3(row["top"]).distance_to(Nightstand.LEGS[i][0]) < 1e-4 \
			and _v3(row["foot"]).distance_to(Nightstand.LEGS[i][1]) < 1e-4
	_ok(legs_same, "contract/the legs are the contract's")
	_ok(is_equal_approx(float(c["drawer_travel_m"]), Nightstand.DRAWER_TRAVEL), "contract/the drawer's travel")
	var marks := {}
	for m: Dictionary in c["markers"]:
		marks[m["node"]] = _v3(m["position"])
	_ok(marks.get("DrawerHandle", Vector3.INF).distance_to(Nightstand.DRAWER_HANDLE) < 1e-4
		and marks.get("DrawerSeat", Vector3.INF).distance_to(Nightstand.DRAWER_SEAT) < 1e-4
		and marks.get("TopSurface", Vector3.INF).distance_to(Nightstand.TOP_SURFACE) < 1e-4
		and marks.get("ShelfSurface", Vector3.INF).distance_to(Nightstand.SHELF_SURFACE) < 1e-4,
		"contract/the handle, drawer seat, top and shelf are the contract's markers")


func _v3(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


func _latch(ns: Nightstand) -> void:
	var d := ns.drawer()
	await _reset(ns)
	# Taken 2 cm off the pull's middle (inside its box): the drawer must not jump to the hand.
	await _take(ns, 0.9, 0.0, 0.012)
	_ok(d.is_held(), "latch/the trigger in the handle box takes hold")
	_ok(d.value < 0.01, "latch/taking hold does not jump the drawer to the hand (%.3f)" % d.value)
	var start := _handle(ns)
	for i in 10:
		_place(start + _out(ns) * (0.012 + 0.012 * (i + 1)))
		await _ticks(1)
	await _ticks(2)
	_ok(absf(d.open_distance() - 0.12) < 0.006, "latch/pulled 12 cm, it is 12 cm out (%.1f mm)" % (
		d.open_distance() * 1000.0))
	# The hand roams sideways and up; only the motion along the runners counts.
	_place(start + _out(ns) * 0.132 + Vector3(0, 0.15, 0) + ns.global_basis.x * 0.2)
	await _ticks(3)
	_ok(absf(d.open_distance() - 0.12) < 0.01 and d.is_held(),
		"latch/moving across the runners leaves it where it is, still held (%.1f mm)" % (d.open_distance() * 1000.0))
	_place(_handle(ns) + _out(ns) * 0.6)
	await _ticks(3)
	_ok(is_equal_approx(d.value, 1.0), "latch/pulled past the end it stops at its full travel (%.3f)" % d.value)
	_place(_handle(ns) - _out(ns) * 0.6)
	await _ticks(3)
	_ok(is_equal_approx(d.value, 0.0), "latch/pushed past shut it stops shut (%.3f)" % d.value)
	await _wait_until(func() -> bool: return ns.drawer_body().position.length() < 0.001, 1.0)
	var body_at := ns.drawer_body().position
	_ok(body_at.length() < 0.001, "latch/shut, the drawer body follows back to where it was modelled", str(body_at))
	_buttons(0.0, 0.0)
	await _ticks(3)
	_ok(not d.is_held(), "latch/letting the trigger go lets go")
	# A trigger already held as the hand arrives does not take hold (re-arm).
	_place(FAR)
	_buttons(0.9, 0.0)
	await _ticks(3)
	_place(_handle(ns))
	await _ticks(3)
	_ok(not d.is_held(), "latch/a trigger already down as the hand arrives does not take hold")
	await _reset(ns)


func _grip(ns: Nightstand) -> void:
	var d := ns.drawer()
	await _reset(ns)
	_place(_handle(ns))
	await _ticks(3)
	_ok(not _pickup.enabled, "grip/a hand in the handle box has its pickup muted, so a squeeze cannot lift the nightstand")
	_buttons(0.0, 0.9)
	await _ticks(3)
	_ok(d.is_held(), "grip/the grip takes hold too")
	_place(_handle(ns) + _out(ns) * 0.08)
	await _ticks(3)
	_ok(d.open_distance() > 0.06, "grip/and the drawer follows it (%.1f mm)" % (d.open_distance() * 1000.0))
	_ok(not _pickup.enabled, "grip/the pickup stays muted while held")
	_buttons(0.0, 0.0)
	_place(FAR)
	await _ticks(4)
	_ok(_pickup.enabled, "grip/the pickup is handed back once the hand leaves")
	d.grip_engages = false
	await _ticks(2)
	_place(_handle(ns))
	await _ticks(3)
	_ok(_pickup.enabled, "grip/control: with grip_engages off nothing is muted")
	d.grip_engages = true
	await _reset(ns)


func _coast(ns: Nightstand) -> void:
	var d := ns.drawer()
	await _reset(ns)
	await _take(ns, 0.9, 0.0)
	var start := _handle(ns)
	# A flick: 1 m/s for six frames, then let go moving.
	for i in 6:
		_place(start + _out(ns) * (0.0167 * (i + 1)))
		await _ticks(1)
	_buttons(0.0, 0.0)
	var at_release := d.open_distance()
	await _ticks(2)
	_place(FAR)
	_ok(d.is_moving(), "coast/let go moving, it slides on")
	var t0 := Time.get_ticks_msec()
	await _wait_until(func() -> bool: return not d.is_moving(), 3.0)
	_ok(d.open_distance() > at_release + 0.05,
		"coast/it slid on past where it was let go (%.0f -> %.0f mm)" % [at_release * 1000.0, d.open_distance() * 1000.0])
	_ok(not d.is_moving(), "coast/and came to rest by friction (%d ms)" % (Time.get_ticks_msec() - t0))
	# A slow let-go does not coast.
	await _take(ns, 0.9, 0.0)
	var s2 := _handle(ns)
	_place(s2 + _out(ns) * 0.03)
	await _ticks(20)
	_buttons(0.0, 0.0)
	await _ticks(2)
	_ok(not d.is_moving(), "coast/control: let go still, it stays")
	_place(FAR)
	await _ticks(3)
	# Coasting outlasts the widget sleep (PokeWake: 30 idle frames with no hand near).
	d.friction = 0.25
	d.restitution = 0.0
	d.set_value_no_signal(0.1)
	d._speed = 0.5
	d._coasting = true
	d.set_process(true)
	await _ticks(PokeWake.SLEEP_AFTER + 12)
	_ok(d.is_processing() and (d.is_moving() or is_equal_approx(d.value, 1.0)),
		"coast/a coasting drawer does not fall asleep mid-slide (%.2f)" % d.value)
	await _wait_until(func() -> bool: return not d.is_moving(), 4.0)
	_ok(is_equal_approx(d.value, 1.0), "coast/a hard flick runs it to the open stop (%.3f)" % d.value)
	d.friction = 1.6
	d.restitution = 0.15
	await _reset(ns)


func _soft(ns: Nightstand) -> void:
	var d := ns.drawer()
	await _reset(ns)
	d.set_value(0.01 / Nightstand.DRAWER_TRAVEL)
	await _wait_until(func() -> bool: return d.value <= 0.0, 2.0)
	_ok(d.value <= 0.0, "soft/left 10 mm out, it eases itself shut (%.1f mm)" % (d.open_distance() * 1000.0))
	d.set_value(0.03 / Nightstand.DRAWER_TRAVEL)
	await _ticks(20)
	_ok(absf(d.open_distance() - 0.03) < 0.0005, "soft/control: left 30 mm out, it stays (%.1f mm)" % (
		d.open_distance() * 1000.0))
	await _reset(ns)


func _push(ns: Nightstand) -> void:
	var d := ns.drawer()
	await _reset(ns)
	d.set_value_no_signal(0.6)
	await _ticks(2)
	var out := _out(ns)
	var right := ns.global_basis.x.normalized()
	# The front's face is 28 mm behind the pull's axis; a fingertip 10 cm to the right of the pull, on the front.
	var face := _handle(ns) - out * 0.028 + right * 0.1
	_place(face + out * 0.03)
	await _ticks(3)
	for i in 8:
		_place(face - out * 0.01 * (i + 1))
		await _ticks(1)
	await _ticks(2)
	_ok(d.open_distance() < 0.15 - 0.05, "push/a fingertip pressing the front pushes it in (%.0f -> %.0f mm)" % [
		150.0, d.open_distance() * 1000.0])
	_place(FAR)
	await _ticks(3)
	# Reaching INTO the open drawer (arriving behind the front, inside the box) never shuts it.
	d.set_value_no_signal(0.6)
	await _ticks(2)
	var inside := _handle(ns) - out * 0.1 + right * 0.1
	_place(inside)
	await _ticks(3)
	_place(inside - out * 0.05)
	await _ticks(3)
	_ok(absf(d.open_distance() - 0.15) < 0.001, "push/a hand reaching into the drawer does not shut it (%.0f mm)" % (
		d.open_distance() * 1000.0))
	_place(FAR)
	await _ticks(3)
	# A still fingertip just in front of the drawer, and the drawer slides out onto it (set from code, as a peer's
	# move or a coast would): the face passing the tip is not the tip pushing.
	d.set_value_no_signal(0.2)
	await _ticks(2)
	_place(_handle(ns) - out * 0.028 + right * 0.1 + out * 0.01)
	await _ticks(3)
	d.set_value(0.4)
	await _ticks(6)
	_ok(absf(d.value - 0.4) < 0.001, "push/the drawer sliding out onto a still fingertip is not pushed back (%.3f)" % d.value)
	await _reset(ns)


func _save(ns: Nightstand) -> void:
	var d := ns.drawer()
	await _reset(ns)
	d.set_value(0.6)
	await _ticks(2)
	var sp := ScenePersistence.new()
	var records: Array = sp._serialize_articulated_controls(ns)
	var found := false
	for rec: Dictionary in records:
		if str(rec.get("path", "")) == "DrawerHandle" and str(rec.get("kind", "")) == "slider" \
				and is_equal_approx(float(rec.get("value", -1.0)), 0.6):
			found = true
	_ok(found, "save/the drawer is saved as DrawerHandle's slider value", str(records))
	var ns2 := NIGHTSTAND.instantiate() as Nightstand
	ns2.position = Vector3(-1.5, 0, 1.0)
	add_child(ns2)
	await _ticks(3)
	_ok(ns2.drawer().value == 0.0, "save/control: a fresh nightstand's drawer is shut")
	sp._restore_articulated_controls(ns2, records)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_ok(absf(ns2.drawer_body().position.z - 0.15) < 0.001, "save/a restore puts the drawer straight there, no slide (%.1f mm two ticks on)" % (
		ns2.drawer_body().position.z * 1000.0))
	await _ticks(3)
	_ok(absf(ns2.drawer().open_distance() - 0.15) < 0.001
		and absf(ns2.drawer_body().position.z - 0.15) < 0.001,
		"save/restored, the drawer is 150 mm out and its body with it (%.1f mm)" % (
			ns2.drawer_body().position.z * 1000.0))
	_ok(not ns2.drawer().is_moving(), "save/a restore does not set it sliding")
	_ok(ScenePersistence.PLAIN_SCENES.has("nightstand") and ScenePersistence.saved_kind_types().has("nightstand"),
		"save/the nightstand spawns and saves as nightstand")
	var spawnable := false
	for row: Array in SpawnCatalog.OBJECTS:
		spawnable = spawnable or row[1] == "nightstand"
	_ok(spawnable, "save/it is on the spawn menu's Objects tab")
	ns2.queue_free()
	await _reset(ns)


func _carry(ns: Nightstand) -> void:
	var d := ns.drawer()
	await _reset(ns)
	await _ticks(30)
	var cube := RigidBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.08, 0.03, 0.1)
	cs.shape = box
	cube.add_child(cs)
	cube.mass = 0.2
	cube.collision_layer = 4          # a room object's layer and mask, as the nightstand's own
	cube.collision_mask = 196613
	var pm := PhysicsMaterial.new()
	pm.friction = 0.8
	cube.physics_material_override = pm
	add_child(cube)
	cube.global_position = ns.global_transform * (Nightstand.DRAWER_SEAT + Vector3(0, 0.02, 0))
	for i in 45:
		await get_tree().physics_frame
	var rest := cube.global_position
	var seat := ns.global_transform * Nightstand.DRAWER_SEAT
	_ok(absf(rest.y - (seat.y + 0.015)) < 0.006, "carry/a box laid in the drawer rests on its floor (%.1f mm up)" % (
		(rest.y - seat.y) * 1000.0))
	await _take(ns, 0.9, 0.0)
	var start := _handle(ns)
	for i in 40:
		_place(start + _out(ns) * (0.005 * (i + 1)))
		await get_tree().physics_frame
	for i in 20:
		await get_tree().physics_frame
	var moved := (cube.global_position - rest).dot(_out(ns))
	_ok(absf(moved - d.open_distance()) < 0.03 and d.open_distance() > 0.15,
		"carry/pulled out %.0f mm, the box rode %.0f mm with it" % [d.open_distance() * 1000.0, moved * 1000.0])
	_ok(cube.global_position.y > seat.y, "carry/and is still in the drawer, not through its floor")
	_buttons(0.0, 0.0)
	_place(FAR)
	cube.queue_free()
	await _reset(ns)
