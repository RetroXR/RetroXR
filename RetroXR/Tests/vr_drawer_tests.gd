## VRDrawer and the nightstand that uses it: a drawer taken by its handle (trigger or grip) follows the hand along its
## runners from where it was taken, stops at both ends, coasts on a flick and eases itself shut, a fingertip on its
## front pushes it in (but never one reaching INTO it), the grip never lifts the furniture, its open amount saves, and
## what rests in it rides out with it. The nightstand is turned 90 degrees and moved, so a frame mix-up shows.
##   godot --headless --path RetroXR res://Tests/vr_drawer_tests.tscn [-- --only=<group>]
## Groups: rig contract latch grip coast soft push pull save carry haul real mission beds again
extends "res://Tests/test_suite.gd"

const HAND := &"/vr_drawer_tests/hand"
const FAR := Vector3(0, 5, 0)
const NIGHTSTAND := preload("res://Scenes/Objects/furniture/nightstand.tscn")
const CONTRACT := "res://imported-assets/furniture/nightstand/nightstand_contract.json"

## Moves the held nightstand on the physics tick at the grab driver's priority (-80), as a hand does.
class Mover extends Node:
	var step: Callable
	func _init() -> void:
		process_physics_priority = -80
	func _physics_process(delta: float) -> void:
		step.call(delta)

class FakePickup extends Node:
	var enabled := true
	var picked_up_object: Node = null

var _hand: XRControllerTracker
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
	if _group("pull"):
		await _pull(ns)
	if _group("save"):
		await _save(ns)
	if _group("carry"):
		await _carry(ns)
	if _group("haul"):
		await _haul(ns)
		await _rough_haul(ns)
	if _group("mission"):
		await _mission()
	if _group("beds"):
		await _beds()
	if _group("real"):
		await _real_hold(ns)
		await _ray_hold(ns)
	if _group("again"):
		await _again(ns)
		await _again_by_buttons()
		await _ray_carry_collision()
		await _debug_view_after_carry(ns)
		await _angled_drop()
		await _drag_lag()
		await _pickup_spill()
		await _small_items()
		await _held_only_while_carried()
	XRServer.remove_tracker(_hand)
	Engine.max_fps = _max_fps
	_finish()


func _group(g: String) -> bool:
	return _only == "" or _only == g


# --- the hand ---------------------------------------------------------------------------------------------------------
func _tracked_hand() -> void:
	_hand = XRControllerTracker.new()
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
	_hand.set_input("trigger_click", trigger > 0.5)
	_hand.set_input("grip_click", grip > 0.5)


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
	var drawn := ns.get_node("DrawerVisual")
	_ok(drawn.find_child("Drawer", true, false) is MeshInstance3D
		and drawn.find_child("DrawerPull", true, false) is MeshInstance3D
		and ns.drawer_body().find_children("*", "MeshInstance3D", true, false).is_empty(),
		"rig/the model's drawer and pull are drawn from DrawerVisual, not the synced body")
	_ok(ns.drawer().visual == drawn, "rig/the VRDrawer moves DrawerVisual with its body")
	var riders := ns.rider_shapes()
	_ok(riders.size() == 2 and riders[0].name == "CaseTop" and riders[1].name == "CaseBottom",
		"rig/it carries things on its top and its shelf")
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


## A hand INSIDE a part-open drawer pushing out against the inside of its front opens it, following the fingertip; a
## hand resting in it, or moving back in, does not; and one outside the drawer moving away is not inside it.
func _pull(ns: Nightstand) -> void:
	var d := ns.drawer()
	await _reset(ns)
	d.set_value_no_signal(0.4)
	await _ticks(2)
	var out := _out(ns)
	var up := ns.global_basis.y.normalized()
	var right := ns.global_basis.x.normalized()
	# The inside of the front is 56 mm behind the pull's axis; the pull is 51 mm over the drawer's floor. A fingertip
	# 6 cm inside the drawer, 3 cm below the pull, 10 cm right of the middle.
	var inner_face := _handle(ns) - out * 0.056 - up * 0.03 + right * 0.1
	var start := d.open_distance()
	_place(inner_face - out * 0.06)
	await _ticks(4)
	_ok(absf(d.open_distance() - start) < 0.001, "pull/a hand resting inside the drawer moves nothing (%.0f mm)" % (
		d.open_distance() * 1000.0))
	for i in 18:
		_place(inner_face - out * 0.06 + out * 0.006 * (i + 1))
		await _ticks(1)
	await _ticks(2)
	_ok(d.open_distance() - start > 0.035, "pull/a fingertip inside pushing out on the inside of the front opens it (%.0f -> %.0f mm)" % [
		start * 1000.0, d.open_distance() * 1000.0])
	# And back in: the drawer stays where it was pushed (the hand leaving it is not a pull).
	var at := d.open_distance()
	var tip := inner_face - out * 0.06 + out * 0.108
	for i in 10:
		_place(tip - out * 0.01 * (i + 1))
		await _ticks(1)
	await _ticks(10)
	_ok(absf(d.open_distance() - at) < 0.01, "pull/the hand going back in leaves it out (%.0f mm, was %.0f)" % [
		d.open_distance() * 1000.0, at * 1000.0])
	_place(FAR)
	await _ticks(3)
	# Arriving from OUTSIDE (in front of the drawer) and moving away: not a hand in the drawer.
	d.set_value_no_signal(0.4)
	await _ticks(2)
	var before := d.open_distance()
	var outside := _handle(ns) + out * 0.06 - up * 0.03 + right * 0.1
	_place(outside)
	await _ticks(3)
	for i in 6:
		_place(outside + out * 0.01 * (i + 1))
		await _ticks(1)
	await _ticks(2)
	_ok(absf(d.open_distance() - before) < 0.001, "pull/a hand outside the drawer moving away does not pull it (%.0f mm)" % (
		d.open_distance() * 1000.0))
	await _reset(ns)
	# The Mission chest's drawers are built by FurnitureDrawers from its contract: its bottom drawer, from inside.
	var chest := (ScenePersistence.PLAIN_SCENES["mission_chest"] as PackedScene).instantiate() as DrawerFurniture
	chest.position = Vector3(-3.0, 0.0, 3.0)
	add_child(chest)
	await _ticks(3)
	var cd: VRDrawer = chest.drawers()[chest.drawers().size() - 1]
	cd.set_value_no_signal(0.4)
	await _ticks(3)
	var c0 := cd.open_distance()
	var face_at := func(along: float) -> Vector3:
		return cd.global_transform * Vector3(cd.pull_face_centre.x + 0.05, cd.pull_face_centre.y,
			cd.pull_face_offset + cd.open_distance() + along)
	var first: Vector3 = face_at.call(-0.06)
	_place(first)
	await _ticks(4)
	for i in 18:
		_place(first + cd.global_basis.z.normalized() * 0.006 * (i + 1))
		await _ticks(1)
	await _ticks(2)
	_ok(cd.open_distance() - c0 > 0.035, "pull/the Mission chest's drawer, pushed out from inside, opens (%.0f -> %.0f mm)" % [
		c0 * 1000.0, cd.open_distance() * 1000.0])
	_place(FAR)
	chest.queue_free()
	await _ticks(3)


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
	# As every pickable in the game has it (HeldObjectPhysics): a body that settles with it rests a few mm INTO a floor,
	# and without it these boxes rode a lifted drawer at speeds where a real thing fell out (2026-11-12).
	cube.continuous_cd = true
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


## Pick the nightstand up as xr-tools does (frozen, on the held layer, nothing collides with it, its riders noted) and
## carry it as a hand would: 1.1 m across, 0.25 m up and a quarter turn in 1.6 s, with an 8 Hz tremor. A box in the
## drawer, one on the shelf and one on the top must come with it, and the drawer must never trail the case.
func _haul(ns: Nightstand) -> void:
	var d := ns.drawer()
	await _reset(ns)
	var boxes := {}
	for spot: String in ["drawer", "shelf", "top"]:
		var at: Vector3 = {"drawer": Nightstand.DRAWER_SEAT, "shelf": Nightstand.SHELF_SURFACE,
			"top": Nightstand.TOP_SURFACE}[spot]
		boxes[spot] = _loose_box(ns.global_transform * (at + Vector3(0.0, 0.03, 0.0)))
	for i in 60:
		await get_tree().physics_frame
	var local_before := {}
	for spot: String in boxes:
		local_before[spot] = ns.global_transform.affine_inverse() * (boxes[spot] as RigidBody3D).global_position
	var start := ns.global_transform
	ns.freeze = true
	ns.collision_layer = 1 << 16
	ns.collision_mask = 0
	ns.picked_up.emit(ns)          # as pick_up() does: HeldPhysics notes the riders, the nightstand couples its drawer
	var t := [0.0]
	var worst_lag := [0.0]
	var worst_body := [0.0]
	var mid := [false]
	var mover := Mover.new()
	mover.step = func(delta: float) -> void:
		t[0] += delta
		var u := clampf(t[0] / 1.6, 0.0, 1.0)
		var e := u * u * (3.0 - 2.0 * u)
		var tremor := Vector3(sin(t[0] * TAU * 8.0), sin(t[0] * TAU * 7.0 + 1.0), 0.0) * 0.004
		var turned := start.basis.rotated(Vector3.UP, e * PI * 0.5)
		ns.global_transform = Transform3D(turned, start.origin + Vector3(1.1 * e, 0.25 * sin(PI * u), 0.0) + tremor)
	add_child(mover)
	for i in 160:
		await get_tree().process_frame
		# What is DRAWN: the drawer's front against the case it belongs in, interpolated as the renderer sees them.
		var drawn := _drawn_drawer(ns)
		var want := ns.get_global_transform_interpolated() * Vector3(0, 0, d.open_distance())
		worst_lag[0] = maxf(worst_lag[0], drawn.distance_to(want))
		# What COLLIDES: the drawer body as the physics server has it, against the case as it is now.
		worst_body[0] = maxf(worst_body[0], _drawer_body_error(ns))
		if i == 80:
			# About 1 m/s here: under CarryContents' latch speed, so what is in it is ordinary physics, not frozen.
			# Carried: what is in it is held in place (CarryContents), and let go again once it is put down.
			mid[0] = ns.lid_on() and (boxes["drawer"] as RigidBody3D).freeze
	mover.queue_free()
	for i in 10:
		await get_tree().physics_frame
	ns.freeze = false
	ns.collision_layer = 4
	ns.collision_mask = 196613
	ns.dropped.emit(ns)
	for i in 90:
		await get_tree().physics_frame
	_ok(worst_lag[0] < 0.004, "haul/the drawer never trails the case it is carried in (worst %.1f mm)" % (
		worst_lag[0] * 1000.0))
	_ok(mid[0], "haul/carried, the drawer has its lid on and what is in it is held in place")
	_ok(not ns.lid_on(), "haul/put down, the lid is off: nothing invisible left in the drawer")
	_ok(worst_body[0] < 0.02, "haul/the drawer's COLLISION body keeps up with the case while carried (worst %.1f mm)" % (
		worst_body[0] * 1000.0))
	_ok(_drawer_body_error(ns) < 0.001, "haul/put down, the drawer's collision body is where the drawer is drawn (%.1f mm)" % (
		_drawer_body_error(ns) * 1000.0))
	for spot: String in boxes:
		var b := boxes[spot] as RigidBody3D
		var local_after := ns.global_transform.affine_inverse() * b.global_position
		var moved: float = (local_after - local_before[spot]).length()
		# Ordinary physics carries these at ~1 m/s (under CarryContents' latch speed for a 30 mm box), and they slide
		# a little as it turns and stops: 30-33 mm, flapping on a 30 mm limit with the machine's load. "Comes with it"
		# means not left behind or lost, which is metres, not centimetres.
		_ok(moved < 0.05, "haul/a box %s comes with it (%.0f mm from where it lay in it)" % [
			"in the drawer" if spot == "drawer" else "on the " + spot, moved * 1000.0])
		b.queue_free()
	ns.global_transform = start
	for i in 10:
		await get_tree().physics_frame
	await _reset(ns)


## Where the drawer's pull is DRAWN this frame: the model's pull node (its origin is the model's, the nightstand's
## own origin with the drawer shut), interpolated as the renderer sees it.
func _drawn_drawer(ns: Nightstand) -> Vector3:
	var pull := ns.drawer().handle_mesh
	return pull.get_global_transform_interpolated().origin if pull != null else Vector3.INF


func _loose_box(at: Vector3) -> RigidBody3D:
	var cube := RigidBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.08, 0.03, 0.1)
	cs.shape = box
	cube.add_child(cs)
	cube.mass = 0.2
	# As every pickable in the game has it (HeldObjectPhysics): a body that settles with it rests a few mm INTO a floor,
	# and without it these boxes rode a lifted drawer at speeds where a real thing fell out (2026-11-12).
	cube.continuous_cd = true
	cube.collision_layer = 4
	cube.collision_mask = 196613
	var pm := PhysicsMaterial.new()
	pm.friction = 0.8
	cube.physics_material_override = pm
	add_child(cube)
	cube.global_position = at
	return cube


## Hauled hard: the same path in 0.3 s (peaks near 6 m/s) tipped 25 degrees on the way, and stopped dead. Things in the
## SHUT drawer must still be IN it. Riding by friction with nothing over them, two of three boxes left it; the drawer
## has a lid while the nightstand is held (Nightstand._physics_process).
func _rough_haul(ns: Nightstand) -> void:
	await _reset(ns)
	var inner := AABB(Vector3(-0.198, 0.458, -0.123), Vector3(0.396, 0.082, 0.27))
	var boxes: Array[RigidBody3D] = []
	for x: float in [-0.12, 0.0, 0.12]:
		boxes.append(_loose_box(ns.global_transform * (Nightstand.DRAWER_SEAT + Vector3(x, 0.03, 0.0))))
	for i in 60:
		await get_tree().physics_frame
	var start := ns.global_transform
	ns.freeze = true
	ns.collision_layer = 1 << 16
	ns.collision_mask = 0
	ns.picked_up.emit(ns)          # as pick_up() does: HeldPhysics notes the riders, the nightstand couples its drawer
	var t := [0.0]
	var mover := Mover.new()
	mover.step = func(delta: float) -> void:
		t[0] += delta
		var u := clampf(t[0] / 0.3, 0.0, 1.0)
		var e := u * u * (3.0 - 2.0 * u)
		ns.global_transform = Transform3D(start.basis.rotated(Vector3.UP, e * PI * 0.5).rotated(Vector3.RIGHT,
			sin(PI * u) * 0.44),
			start.origin + Vector3(1.1 * e, 0.25 * sin(PI * u), 0.0))
	add_child(mover)
	for i in 70:
		await get_tree().physics_frame
	# Gone NOW, not at the frame's end: queued, it moved the nightstand once more after it was let go, a teleport with
	# nothing carrying what is in it (CarryContents follows a HELD piece). A hand lets go outside the physics step.
	mover.free()
	ns.freeze = false
	ns.collision_layer = 4
	ns.collision_mask = 196613
	ns.dropped.emit(ns)
	for i in 60:
		await get_tree().physics_frame
	_ok(boxes.all(func(b: RigidBody3D) -> bool: return not b.freeze) and not ns.lid_on(),
		"haul/put down, nothing in the drawer is frozen and the lid is off")
	var kept := 0
	var where := []
	for b in boxes:
		var local := ns.global_transform.affine_inverse() * b.global_position
		where.append((local * 1000.0).round())
		if inner.grow(0.012).has_point(local):
			kept += 1
		b.queue_free()
	_ok(kept == boxes.size(), "haul/hauled hard and stopped dead, every box is still in the drawer (%d of %d: %s)" % [
		kept, boxes.size(), str(where)])
	ns.global_transform = start
	for i in 10:
		await get_tree().physics_frame
	await _reset(ns)


## How far the drawer body the PHYSICS SERVER has (what things in the drawer collide with) is from where the drawer is.
func _drawer_body_error(ns: Nightstand) -> float:
	var server: Transform3D = PhysicsServer3D.body_get_state(ns.drawer_body().get_rid(),
		PhysicsServer3D.BODY_STATE_TRANSFORM)
	var want := ns.global_transform * Transform3D(Basis(), Vector3(0, 0, ns.drawer().open_distance()))
	return server.origin.distance_to(want.origin)


## The REAL hold: xr-tools' own pick_up() by a real XRToolsFunctionPickup on the hand, carried by moving the hand, and
## let_go() with the nightstand 0.3 m up, so it drops. What is in the drawer must come along and, once it has all
## settled, the drawer must hold nothing invisible: a box put in afterwards lies on the drawer's floor.
func _real_hold(ns: Nightstand) -> void:
	await _reset(ns)
	var drawer_box := _loose_box(ns.global_transform * (Nightstand.DRAWER_SEAT + Vector3(0.0, 0.03, 0.0)))
	for i in 60:
		await get_tree().physics_frame
	var local_before := ns.global_transform.affine_inverse() * drawer_box.global_position
	var hand := load("res://addons/godot-xr-tools/functions/function_pickup.tscn").instantiate() as Node3D
	hand.name = "RealPickup"
	_ctrl.add_child(hand)
	var start := ns.global_transform
	# The hand where the nightstand's origin is, so the grab's pull-in has nothing to pull.
	_place(start.origin)
	await _ticks(3)
	ns.pick_up(hand)
	var worst_body := 0.0
	for i in 120:
		var u := clampf(i / 90.0, 0.0, 1.0)
		var e := u * u * (3.0 - 2.0 * u)
		_place(start.origin + Vector3(0.9 * e, 0.3 * e, 0.0))
		await get_tree().physics_frame
		worst_body = maxf(worst_body, _drawer_body_error(ns))
	ns.let_go(hand, Vector3.ZERO, Vector3.ZERO)
	for i in 150:
		await get_tree().physics_frame
	var settled_err := _drawer_body_error(ns)
	var local_after := ns.global_transform.affine_inverse() * drawer_box.global_position
	_ok(worst_body < 0.02, "real/held by xr-tools, the drawer's collision body keeps up (worst %.1f mm)" % (
		worst_body * 1000.0))
	_ok(settled_err < 0.002, "real/dropped and settled, the collision body is where the drawer is (%.1f mm)" % (
		settled_err * 1000.0))
	_ok((local_after - local_before).length() < 0.03 and not drawer_box.freeze,
		"real/the box in the drawer came along and is loose again (%.0f mm, frozen %s)" % [
		(local_after - local_before).length() * 1000.0, drawer_box.freeze])
	var probe := _loose_box(ns.global_transform * (Nightstand.DRAWER_SEAT + Vector3(0.1, 0.03, 0.06)))
	for i in 90:
		await get_tree().physics_frame
	var up := (ns.global_transform.affine_inverse() * probe.global_position).y - Nightstand.DRAWER_SEAT.y
	_ok(absf(up - 0.015) < 0.004, "real/a box put in afterwards lies on the drawer's floor, nothing invisible under it (%.1f mm up)" % (
		up * 1000.0))
	print("[vr_drawer] real: nightstand at %s, drawer body server %s" % [ns.global_position,
		(PhysicsServer3D.body_get_state(ns.drawer_body().get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM) as Transform3D).origin])
	probe.queue_free()
	drawer_box.queue_free()
	hand.queue_free()
	ns.global_transform = start
	for i in 10:
		await get_tree().physics_frame
	await _reset(ns)


## Held the way a RAY grab holds (frozen, on the held layer, and no picked_up / dropped from the pickable at all):
## the lid must still go on and, the most important half, come OFF when it is let go.
func _ray_hold(ns: Nightstand) -> void:
	await _reset(ns)
	ns.freeze = true
	ns.collision_layer = ns.picked_up_layer
	ns.collision_mask = 0
	for i in 5:
		await get_tree().physics_frame
	var on := ns.lid_on()
	ns.freeze = false
	ns.collision_layer = 4
	ns.collision_mask = 196613
	for i in 5:
		await get_tree().physics_frame
	_ok(on and not ns.lid_on(), "real/held and let go by a ray (no signals), the lid goes on and comes off again")
	await _reset(ns)


## The Mission pair, built from their contracts by DrawerFurniture: every drawer is its own VRDrawer that moves its
## own body and drawing and no other, carries what is in it, gets a lid while the piece is held, and saves.
func _mission() -> void:
	for v: Array in [["mission_nightstand", 2], ["mission_chest", 6]]:
		var piece := (ScenePersistence.PLAIN_SCENES[v[0]] as PackedScene).instantiate() as DrawerFurniture
		piece.position = Vector3(-3.0, 0.0, 2.0) if v[0] == "mission_chest" else Vector3(3.0, 0.0, 2.0)
		add_child(piece)
		await _ticks(3)
		var ds := piece.drawers()
		_eq(ds.size(), v[1], "mission/%s has its %d drawers" % [v[0], v[1]])
		if ds.size() != v[1]:
			piece.queue_free()
			continue
		# Its type comes from the instance (`type_id`, as a Seat's), so saved_kind_types() cannot list it: save one.
		var saved_type := str(ScenePersistence.new()._serialize_kind(piece, 1, {}).get("type", ""))
		_ok(ScenePersistence.PLAIN_SCENES.has(v[0]) and saved_type == v[0],
			"mission/%s spawns and saves as itself (saved as '%s')" % [v[0], saved_type])
		var tops := piece.rider_shapes()
		_ok(tops.size() == 1 and String(tops[0].name).begins_with("CaseTop_"),
			"mission/%s carries things on its top (and not its top rail)" % v[0])
		_ok(ds.all(func(d: VRDrawer) -> bool: return d.handle_mesh != null and d.visual != null),
			"mission/%s: every drawer is drawn from its own visual and outlined" % v[0])
		# Pull the LAST drawer out by its handle; only it moves.
		var k := ds.size() - 1
		var d := ds[k]
		var others_before := []
		for j in ds.size():
			others_before.append(piece.drawer_body(j).position)
		var box := _loose_box(piece.global_transform * (piece.drawer_seat_local(k) + Vector3(0, 0.03, 0)))
		for i in 45:
			await get_tree().physics_frame
		var rest := box.global_position
		var start := d.global_position
		var out := piece.global_basis.z
		_place(start)
		await _ticks(3)
		_buttons(0.9, 0.0)
		await _ticks(3)
		for i in 40:
			_place(start + out * (0.005 * (i + 1)))
			await get_tree().physics_frame
		_buttons(0.0, 0.0)
		_place(FAR)
		for i in 30:
			await get_tree().physics_frame
		var opened := d.open_distance()
		var moved_ok := absf(piece.drawer_body(k).position.z - opened) < 0.003 			and absf((piece.get_node("DrawerVisual%d" % (k + 1)) as Node3D).position.z - opened) < 0.003
		var others_still := true
		for j in ds.size():
			if j != k:
				others_still = others_still and piece.drawer_body(j).position.is_equal_approx(others_before[j])
		_ok(opened > 0.15 and moved_ok, "mission/%s: its bottom drawer pulls out %.0f mm, body and drawing with it" % [
			v[0], opened * 1000.0])
		_ok(others_still, "mission/%s: the other drawers stay shut" % v[0])
		var rode := (box.global_position - rest).dot(out)
		_ok(absf(rode - opened) < 0.03, "mission/%s: a box in it rode out %.0f of %.0f mm" % [v[0], rode * 1000.0,
			opened * 1000.0])
		box.queue_free()
		# Held, every drawer has a lid; put down, none.
		piece.freeze = true
		piece.collision_layer = piece.picked_up_layer
		piece.collision_mask = 0
		for i in 4:
			await get_tree().physics_frame
		var lids := 0
		for j in ds.size():
			lids += 1 if piece.lid_on(j) else 0
		piece.freeze = false
		piece.collision_layer = 4
		piece.collision_mask = 196613
		for i in 4:
			await get_tree().physics_frame
		var any_left := false
		for j in ds.size():
			any_left = any_left or piece.lid_on(j)
		_ok(lids == ds.size() and not any_left, "mission/%s: held, every drawer has its lid (%d of %d); put down, none" % [
			v[0], lids, ds.size()])
		# Saved and restored on a fresh piece.
		var sp := ScenePersistence.new()
		var records: Array = sp._serialize_articulated_controls(piece)
		var fresh := (ScenePersistence.PLAIN_SCENES[v[0]] as PackedScene).instantiate() as DrawerFurniture
		fresh.position = piece.position + Vector3(0, 0, 2.0)
		add_child(fresh)
		await _ticks(3)
		sp._restore_articulated_controls(fresh, records)
		for i in 3:
			await get_tree().physics_frame
		_ok(absf(fresh.drawers()[k].open_distance() - opened) < 0.001
			and absf(fresh.drawer_body(k).position.z - opened) < 0.002,
			"mission/%s: saved and restored, that drawer is %.0f mm out again" % [v[0], opened * 1000.0])
		fresh.queue_free()
		piece.queue_free()
		await _ticks(2)


## The beds with drawers (ContractSeat, its drawers built by FurnitureDrawers as the Mission pair's): they come out of
## the bed's SIDE (+X), each moves its own body and drawing, clear of the mattress at full travel, gets a lid while
## the bed is held, and saves. The bed is turned, so a drawer that slid along the bed's Z instead shows.
func _beds() -> void:
	for v: Array in [["bed_captain", 3], ["bed_waterbed", 2]]:
		var piece := (ScenePersistence.PLAIN_SCENES[v[0]] as PackedScene).instantiate() as ContractSeat
		piece.transform = Transform3D(Basis(Vector3.UP, 0.6), Vector3(4.0, 0.0, -3.0))
		add_child(piece)
		await _ticks(3)
		var ds := piece.drawers()
		_eq(ds.size(), v[1], "beds/%s has its %d drawers" % [v[0], v[1]])
		if ds.size() != v[1]:
			piece.queue_free()
			continue
		_ok(ds.all(func(d: VRDrawer) -> bool: return d.handle_mesh != null and d.visual != null),
			"beds/%s: every drawer is drawn from its own visual and outlined" % v[0])
		var out := piece.global_basis.x
		_ok(ds.all(func(d: VRDrawer) -> bool: return (d.global_basis * d.axis_local).normalized().dot(out) > 0.999),
			"beds/%s: every drawer slides out of the bed's side (+X)" % v[0])
		var k := 0
		var d := ds[k]
		var body := piece.get_node("DrawerBody%d" % (k + 1)) as Node3D
		var others_before := []
		for j in ds.size():
			others_before.append((piece.get_node("DrawerBody%d" % (j + 1)) as Node3D).position)
		var start := d.global_position
		_place(start)
		await _ticks(3)
		_buttons(0.9, 0.0)
		await _ticks(3)
		for i in 120:
			_place(start + out * (0.005 * (i + 1)))
			await get_tree().physics_frame
		_buttons(0.0, 0.0)
		_place(FAR)
		for i in 30:
			await get_tree().physics_frame
		var opened := d.open_distance()
		var visual := piece.get_node("DrawerVisual%d" % (k + 1)) as Node3D
		_ok(opened > d.travel - 0.01 and absf(body.position.x - opened) < 0.003 and absf(body.position.z) < 0.001
			and absf(visual.position.x - opened) < 0.003,
			"beds/%s: its first drawer pulls all the way out of the side, %.0f of %.0f mm, body and drawing with it" % [
			v[0], opened * 1000.0, d.travel * 1000.0])
		var others_still := true
		for j in ds.size():
			if j != k:
				others_still = others_still and (piece.get_node("DrawerBody%d" % (j + 1)) as Node3D).position.is_equal_approx(others_before[j])
		_ok(others_still, "beds/%s: the other drawers stay shut" % v[0])
		# At full travel the drawer (its walls and its lid) is below the mattress and every bedding box, so the bedding
		# never stands in its way.
		var bedding_floor := INF
		for row: Dictionary in (piece.contract()["collision"] as Dictionary).get("bedding", []):
			bedding_floor = minf(bedding_floor, float(row["centre"][1]) - float(row["size"][1]) * 0.5)
		var drawer_top := -INF
		for j in ds.size():
			var b := piece.get_node("DrawerBody%d" % (j + 1)) as Node3D
			for cs: CollisionShape3D in b.find_children("*", "CollisionShape3D", false, false):
				drawer_top = maxf(drawer_top, cs.position.y + (cs.shape as BoxShape3D).size.y * 0.5)
		_ok(drawer_top < bedding_floor, "beds/%s: the drawers' tops (lids included, %.0f mm) are under the bedding (%.0f mm)" % [
			v[0], drawer_top * 1000.0, bedding_floor * 1000.0])
		# Held, every drawer has a lid; put down, none.
		piece.freeze = true
		piece.collision_layer = piece.picked_up_layer
		piece.collision_mask = 0
		for i in 4:
			await get_tree().physics_frame
		var lids := 0
		for j in ds.size():
			lids += 1 if piece.lid_on(j) else 0
		piece.freeze = false
		piece.collision_layer = 4
		piece.collision_mask = 196613
		for i in 4:
			await get_tree().physics_frame
		var any_left := false
		for j in ds.size():
			any_left = any_left or piece.lid_on(j)
		_ok(lids == ds.size() and not any_left, "beds/%s: held, every drawer has its lid (%d of %d); put down, none" % [
			v[0], lids, ds.size()])
		# Saved and restored on a fresh bed.
		var sp := ScenePersistence.new()
		var records: Array = sp._serialize_articulated_controls(piece)
		var fresh := (ScenePersistence.PLAIN_SCENES[v[0]] as PackedScene).instantiate() as ContractSeat
		fresh.position = Vector3(-4.0, 0.0, -6.0)
		add_child(fresh)
		await _ticks(3)
		sp._restore_articulated_controls(fresh, records)
		for i in 3:
			await get_tree().physics_frame
		var fresh_body := fresh.get_node("DrawerBody%d" % (k + 1)) as Node3D
		_ok(absf(fresh.drawers()[k].open_distance() - opened) < 0.001 and absf(fresh_body.position.x - opened) < 0.002,
			"beds/%s: saved and restored, that drawer is %.0f mm out again" % [v[0], opened * 1000.0])
		fresh.queue_free()
		piece.queue_free()
		await _ticks(2)


## Opened, then the piece carried and put down, the drawer must still be taken by its handle: with xr-tools' REAL
## pickup as the hand's FunctionPickup (what PokeTip and the mute read), by a hand grab and by a ray grab.
func _again(ns: Nightstand) -> void:
	_pickup.name = "FakePickupAside"
	var real := load("res://addons/godot-xr-tools/functions/function_pickup.tscn").instantiate() as Node3D
	real.name = "FunctionPickup"
	_ctrl.add_child(real)
	await _ticks(3)
	for how in ["hand", "ray"]:
		await _reset(ns)
		var d := ns.drawer()
		await _take(ns, 0.9, 0.0)
		var s0 := _handle(ns)
		for i in 10:
			_place(s0 + _out(ns) * 0.012 * (i + 1))
			await _ticks(1)
		_buttons(0.0, 0.0)
		_place(FAR)
		await _ticks(5)
		var opened := d.open_distance()
		var start := ns.global_transform
		_place(start.origin)
		await _ticks(3)
		if how == "hand":
			real._pick_up_object(ns)
		else:
			real._start_ray_grab_at(ns, 0.5)
		for i in 60:
			_place(start.origin + Vector3(0.4 * i / 60.0, 0.1, 0.0))
			if how == "ray":
				ns.global_position = start.origin + Vector3(0.4 * i / 60.0, 0.1, 0.0)
			await get_tree().physics_frame
		if how == "hand":
			real.drop_object()
		else:
			real._end_ray_grab()
		_place(FAR)
		for i in 120:
			await get_tree().physics_frame
		print("[vr_drawer] again/%s: enabled %s poking %s held_obj %s value %.2f layer %d mask %d frozen %s processing %s" % [
			how, real.get("enabled"), PokeTip.is_poking(_ctrl), real.get("picked_up_object"), d.value,
			ns.collision_layer, ns.collision_mask, ns.freeze, d.is_processing()])
		await _take(ns, 0.9, 0.0)
		var took_trigger := d.is_held()
		_buttons(0.0, 0.0)
		await _ticks(3)
		await _take(ns, 0.0, 0.9)
		var took_grip := d.is_held()
		_buttons(0.0, 0.0)
		await _ticks(3)
		_ok(took_trigger and took_grip, "again/opened %.0f mm, carried by %s and put down, the handle is taken again (trigger %s, grip %s)" % [
			opened * 1000.0, how, took_trigger, took_grip])
		ns.global_transform = start
		for i in 10:
			await get_tree().physics_frame
	real.queue_free()
	_pickup.name = "FunctionPickup"
	await _ticks(2)
	await _reset(ns)


## As a hand does it: the grip squeezed ON the piece's top picks it up (FunctionPickup's own _process), let go puts
## it down, then the trigger and the grip on each drawer's handle.
func _again_by_buttons() -> void:
	_pickup.name = "FakePickupAside"
	var real := load("res://addons/godot-xr-tools/functions/function_pickup.tscn").instantiate() as Node3D
	real.name = "FunctionPickup"
	_ctrl.add_child(real)
	var laser := load("res://addons/godot-xr-tools/functions/function_pointer.tscn").instantiate() as Node3D
	laser.name = "FunctionPointer"
	laser.position = Vector3(0.02, 0.05, -0.1)
	_ctrl.add_child(laser)
	for kind in ["mission_nightstand", "mission_chest"]:
		var piece := (ScenePersistence.PLAIN_SCENES[kind] as PackedScene).instantiate() as DrawerFurniture
		piece.position = Vector3(3.0, 0.0, 2.0)
		add_child(piece)
		for i in 30:
			await get_tree().physics_frame
		for d in piece.drawers():
			var at := d._reach_point()
			_place(at)
			await _ticks(4)
			_buttons(0.9, 0.0)
			await _ticks(3)
			for i in 20:
				_place(at + piece.global_basis.z * 0.008 * (i + 1))
				await _ticks(1)
			_buttons(0.0, 0.0)
			await _ticks(2)
			_place(FAR)
			await _ticks(3)
		print("[vr_drawer] again/buttons %s opened by hand: %s" % [kind, piece.drawers().map(func(d: VRDrawer) -> String:
			return "%.2f" % d.value)])
		for i in 30:
			await get_tree().physics_frame
		var top := piece.global_transform * Vector3(0, piece.get_node("Model").get("levels")[0].get_aabb().end.y if false else 0.0, 0)
		var tops := piece.rider_shapes()
		var top_at := tops[0].global_position + Vector3(0, (tops[0].shape as BoxShape3D).size.y * 0.5 + 0.03, 0)
		_place(top_at)
		await _ticks(6)
		_buttons(0.0, 0.9)
		await _ticks(6)
		var held := piece.is_picked_up()
		for i in 60:
			_place(top_at + Vector3(0.3 * i / 60.0, 0.05, 0.0))
			await get_tree().physics_frame
		_buttons(0.0, 0.0)
		await _ticks(4)
		var dropped := not piece.is_picked_up()
		_place(FAR)
		for i in 150:
			await get_tree().physics_frame
		var took := 0
		var why := []
		for d in piece.drawers():
			for b: Vector2 in [Vector2(0.9, 0.0), Vector2(0.0, 0.9)]:
				_place(d._reach_point())
				await _ticks(4)
				_buttons(b.x, b.y)
				await _ticks(4)
				if d.is_held():
					took += 1
				else:
					why.append("%s %s val %.2f inbox %s proc %s pickup-enabled %s poking %s ptr %s push %s" % [d.name, b, d.value,
						d._tip_in_box(PokeTip.tip_of(_ctrl)), d.is_processing(), real.get("enabled"), PokeTip.is_poking(_ctrl),
						d._pointer_engaged, d._push_ctrl])
				_buttons(0.0, 0.0)
				await _ticks(3)
				_place(FAR)
				await _ticks(3)
		print("[vr_drawer] again/buttons %s: held %s dropped %s at %s up %s; not taken: %s" % [kind, held, dropped,
			piece.global_position, piece.global_basis.y, why])
		_ok(held and dropped and took == 2 * piece.drawers().size(),
			"again/%s picked up by the grip on its top and put down: %d of %d takes" % [kind, took, 2 * piece.drawers().size()])
		piece.queue_free()
		await _ticks(2)
	laser.queue_free()
	real.queue_free()
	_pickup.name = "FunctionPickup"
	await _ticks(2)


## Carried by the LASER (the pickup's own _process_ray_grab), turned a quarter and moved, let go: the physics engine
## must have every drawer's handle area, handle box and body where the nodes are, and a ray at a handle must meet it.
func _ray_carry_collision() -> void:
	_pickup.name = "FakePickupAside"
	var real := load("res://addons/godot-xr-tools/functions/function_pickup.tscn").instantiate() as Node3D
	real.name = "FunctionPickup"
	_ctrl.add_child(real)
	var laser := load("res://addons/godot-xr-tools/functions/function_pointer.tscn").instantiate() as Node3D
	laser.name = "FunctionPointer"
	_ctrl.add_child(laser)
	await _ticks(3)
	for kind in ["nightstand", "mission_chest"]:
		var piece := (ScenePersistence.PLAIN_SCENES[kind] as PackedScene).instantiate() as XRToolsPickable
		piece.position = Vector3(3.0, 0.0, 2.0)
		add_child(piece)
		for i in 30:
			await get_tree().physics_frame
		var ds: Array = piece.drawers() if piece is DrawerFurniture else [(piece as Nightstand).drawer()]
		for d: VRDrawer in ds:
			d.set_value(0.6)
		for i in 30:
			await get_tree().physics_frame
		var hand_at := piece.global_position + Vector3(0, 1.2, 1.5)
		_place(hand_at)
		await _ticks(3)
		_hand.set_pose(&"default", Transform3D(Basis.looking_at(piece.global_position + Vector3(0, 0.4, 0) - hand_at),
			hand_at), Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
		await _ticks(3)
		var aim := Basis.looking_at(piece.global_position + Vector3(0, 0.4, 0) - hand_at)
		real._start_ray_grab_at(piece, hand_at.distance_to(piece.global_position))
		for i in 90:
			_hand.set_pose(&"default", Transform3D(Basis(Vector3.UP, 0.8 * i / 90.0) * aim, hand_at + Vector3(0.5 * i / 90.0, 0, 0)),
				Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
			real.set("_ray_grab_basis", Basis(Vector3.UP, 1.4 * i / 90.0))
			await get_tree().physics_frame
		var mid := piece.global_transform
		real._end_ray_grab()
		_place(FAR)
		for i in 120:
			await get_tree().physics_frame
		_ok(mid.origin.distance_to(piece.global_position) > 0.0 and absf(piece.global_basis.get_euler().y) > 1.2,
			"again/%s: the laser carried it and turned it" % kind)
		print("[vr_drawer] again %s: held at %s, landed at %s yaw %.0f deg" % [kind, mid.origin, piece.global_position,
			rad_to_deg(piece.global_basis.get_euler().y)])
		var space := get_viewport().get_world_3d().direct_space_state
		for d: VRDrawer in ds:
			var c := d._knob_collision.global_position
			var q := PhysicsRayQueryParameters3D.create(c + piece.global_basis.z * 0.5, c, VRButton.POINTABLE_LAYER)
			q.collide_with_areas = true
			q.collide_with_bodies = false
			var hit := space.intersect_ray(q)
			var r := d.collision_report()
			_ok(r["area"] < 1.0 and r["box"] < 1.0 and r["body"] < 1.0 and hit.get("collider") == d,
				"again/%s %s carried by the laser and put down: collision where it is drawn (area %.1f, box %.1f, body %.1f mm, ray meets %s)" % [
				kind, d.name, r["area"], r["box"], r["body"], hit.get("collider")])
		piece.queue_free()
		await _ticks(2)
	laser.queue_free()
	real.queue_free()
	_pickup.name = "FunctionPickup"
	await _ticks(2)


## The collision VIEW (OPTIONS > Collision Debug, CollisionDebug) after a carry: the lid it drew while the nightstand was
## held must not stay drawn once the lid is off. It did, as a box in the drawer, and read as "the collision is off after
## I carried it" (2026-11-12; the physics engine had everything right). Every switched-off shape is hidden.
func _debug_view_after_carry(ns: Nightstand) -> void:
	await _reset(ns)
	ns.drawer().set_value(0.5)
	for i in 30:
		await get_tree().physics_frame
	CollisionDebug.set_enabled(self, true)
	ns.freeze = true
	ns.collision_layer = ns.picked_up_layer
	ns.collision_mask = 0
	for i in 70:
		await get_tree().physics_frame
	var lid_owner := -1
	var lid_node := ns.drawer_body().get_node_or_null("Lid")
	for id in ns.drawer_body().get_shape_owners():
		if ns.drawer_body().shape_owner_get_owner(id) == lid_node:
			lid_owner = int(id)
	var lid_drawn := false
	for o in ns.drawer_body().get_children():
		if o is MeshInstance3D and o.has_meta(&"owner_id") and (o as MeshInstance3D).visible:
			lid_drawn = lid_drawn or int(o.get_meta(&"owner_id", -2)) == lid_owner
	ns.freeze = false
	ns.collision_layer = 4
	ns.collision_mask = 196613
	for i in 70:
		await get_tree().physics_frame
	var stale := 0
	var bodies: Array[CollisionObject3D] = [ns, ns.drawer_body()]
	for body in bodies:
		for o in body.get_children():
			if o is MeshInstance3D and o.has_meta(&"owner_id") and (o as MeshInstance3D).visible \
					and body.is_shape_owner_disabled(int(o.get_meta(&"owner_id", 0))):
				stale += 1
	CollisionDebug.set_enabled(self, false)
	_ok(lid_drawn and stale == 0 and not ns.lid_on(),
		"again/the collision view drew the lid while carried and draws no switched-off shape after (lid drawn %s, %d stale)" % [
		lid_drawn, stale])
	await _reset(ns)


## Dropped at an ANGLE (the owner's repro, 2026-11-12): the piece hits the floor tipped, turns as it settles, and the
## drawer bodies must turn WITH it. They kept their old world rotation (the follow wrote back only a position), so the
## drawn drawers were right and their collision swung out of them, more with every knock.
func _angled_drop() -> void:
	for kind in ["nightstand", "mission_chest"]:
		var piece := (ScenePersistence.PLAIN_SCENES[kind] as PackedScene).instantiate() as XRToolsPickable
		piece.position = Vector3(-3.0, 0.0, -3.0)
		add_child(piece)
		for i in 30:
			await get_tree().physics_frame
		var ds: Array = piece.drawers() if piece is DrawerFurniture else [(piece as Nightstand).drawer()]
		for d: VRDrawer in ds:
			d.set_value(0.6)
		for i in 30:
			await get_tree().physics_frame
		# Held tipped over 35 degrees, 25 cm up, and let go.
		piece.freeze = true
		piece.collision_layer = piece.picked_up_layer
		piece.collision_mask = 0
		await get_tree().physics_frame
		piece.global_transform = Transform3D(Basis(Vector3(1, 0, 0.4).normalized(), deg_to_rad(35.0)), Vector3(-3.0, 0.25, -3.0))
		for i in 5:
			await get_tree().physics_frame
		piece.freeze = false
		piece.collision_layer = 4
		piece.collision_mask = 196613
		for i in 240:
			await get_tree().physics_frame
		var worst := 0.0
		var worst_turn := 0.0
		for d: VRDrawer in ds:
			var r := d.collision_report()
			worst = maxf(worst, r["body"])
			var b_srv := PhysicsServer3D.body_get_state(d.target.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM) as Transform3D
			worst_turn = maxf(worst_turn, rad_to_deg(b_srv.basis.get_rotation_quaternion().angle_to(
				piece.global_basis.get_rotation_quaternion())))
		_ok(worst < 2.0 and worst_turn < 0.5,
			"again/%s dropped tipped 35 deg, landed and settled (tilt now %.0f deg): every drawer's collision is with it (%.1f mm at the handle, turned %.2f deg)" % [
			kind, rad_to_deg(piece.global_basis.y.angle_to(Vector3.UP)), worst, worst_turn])
		piece.queue_free()
		await _ticks(2)


## Pulled steadily (0.6 m/s, as a hand or a mouse drag does): how far behind the DRAWN drawer the physics engine has
## its collision, and how far the body's own node (what the collision VIEW rides) is behind it.
func _drag_lag() -> void:
	for kind in ["nightstand", "mission_chest"]:
		var piece := (ScenePersistence.PLAIN_SCENES[kind] as PackedScene).instantiate() as XRToolsPickable
		piece.position = Vector3(-3.0, 0.0, 3.0)
		add_child(piece)
		for i in 30:
			await get_tree().physics_frame
		var d: VRDrawer = piece.drawers()[0] if piece is DrawerFurniture else (piece as Nightstand).drawer()
		var worst_srv := 0.0
		var worst_node := 0.0
		var t := 0.0
		while t < 0.4:
			d.set_value(clampf(t * 0.6 / d.travel, 0.0, 1.0))
			await get_tree().process_frame
			t += get_process_delta_time()
			var drawn := d.visual.get_global_transform_interpolated()
			var srv := PhysicsServer3D.body_get_state(d.target.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM) as Transform3D
			worst_srv = maxf(worst_srv, srv.origin.distance_to(drawn.origin))
			worst_node = maxf(worst_node, d.target.get_global_transform_interpolated().origin.distance_to(drawn.origin))
		_ok(worst_srv < 0.010, "again/%s pulled at 0.6 m/s: its collision is within a physics tick of the drawn drawer (%.1f mm; the body's node, which a view riding it would show, %.1f mm)" % [
			kind, worst_srv * 1000.0, worst_node * 1000.0])
		piece.queue_free()
		await _ticks(2)


## PICKED UP with things in an open drawer ("objects sometimes fall through as I pick it up", 2026-11-12): the
## hand's pull-in (origin to the hand at 2.5 m/s, a metre up for a grab at the top), a desktop-style swing (a quarter
## turn round a point 1.5 m off in 0.35 s) and a stop dead. What was in the drawer must still be in it.
func _pickup_spill() -> void:
	const REMOTE := preload("res://Scenes/Objects/appliances/tv_remote.tscn")
	for kind in ["nightstand", "mission_chest"]:
		for how in ["pull_in", "swing"]:
			var piece := (ScenePersistence.PLAIN_SCENES[kind] as PackedScene).instantiate() as XRToolsPickable
			piece.position = Vector3(3.0, 0.0, -3.5)
			add_child(piece)
			for i in 30:
				await get_tree().physics_frame
			var d: VRDrawer = piece.drawers()[0] if piece is DrawerFurniture else (piece as Nightstand).drawer()
			d.set_value(0.6)
			for i in 30:
				await get_tree().physics_frame
			var seat: Vector3 = (piece as DrawerFurniture).drawer_seat_local(0) if piece is DrawerFurniture \
				else (piece as Nightstand).drawer_seat_local()
			var things: Array[RigidBody3D] = []
			things.append(_loose_box(piece.global_transform * (seat + Vector3(-0.06, 0.03, 0.0))))
			var remote := REMOTE.instantiate() as RigidBody3D
			add_child(remote)
			remote.global_transform = piece.global_transform * Transform3D(Basis(), seat + Vector3(0.08, 0.02, 0.0))
			things.append(remote)
			for i in 60:
				await get_tree().physics_frame
			var body := d.target as Node3D
			var start := piece.global_transform
			piece.freeze = true
			piece.collision_layer = piece.picked_up_layer
			piece.collision_mask = 0
			var t := [0.0]
			var mover := Mover.new()
			if how == "pull_in":
				mover.step = func(delta: float) -> void:
					t[0] += delta
					var up := minf(t[0] * 2.5, 1.0)
					piece.global_transform = Transform3D(start.basis, start.origin + Vector3(0, up, 0))
			else:
				var pivot := start.origin + Vector3(0, 1.0, 1.5)
				mover.step = func(delta: float) -> void:
					t[0] += delta
					var a := clampf(t[0] / 0.35, 0.0, 1.0) * PI * 0.5
					var off := start.origin + Vector3(0, 1.0, 0) - pivot
					piece.global_transform = Transform3D(start.basis.rotated(Vector3.UP, a),
						pivot + off.rotated(Vector3.UP, a))
			add_child(mover)
			for i in 90:
				await get_tree().physics_frame
			mover.queue_free()
			for i in 30:
				await get_tree().physics_frame
			var kept := 0
			var where := []
			for th in things:
				var local := body.global_transform.affine_inverse() * th.global_position
				var inner: AABB = (piece as DrawerFurniture)._drawers[0]["inner"] if piece is DrawerFurniture \
					else Nightstand.DRAWER_INNER
				if inner.grow(0.02).has_point(local):
					kept += 1
				else:
					where.append("%s at %s" % [th.name, local])
			_ok(kept == things.size(), "again/%s picked up by %s with a box and a remote in its open drawer: %d of %d still in it %s" % [
				kind, how, kept, things.size(), where])
			# Back down where it stood (in one tick: latched and carried), held still (let go to physics), put down.
			piece.global_transform = start
			for i in 40:
				await get_tree().physics_frame
			# Held still, still carried: held in place until it is put down.
			var latched_held := things.all(func(th: RigidBody3D) -> bool: return th.freeze)
			piece.freeze = false
			piece.collision_layer = 4
			piece.collision_mask = 196613
			for i in 60:
				await get_tree().physics_frame
			var still := 0
			for th in things:
				var inner: AABB = (piece as DrawerFurniture)._drawers[0]["inner"] if piece is DrawerFurniture 					else Nightstand.DRAWER_INNER
				if not th.freeze and inner.grow(0.02).has_point(body.global_transform.affine_inverse() * th.global_position):
					still += 1
			_ok(latched_held and still == things.size(),
				"again/%s by %s, set down and let go: everything in it is ordinary physics again and still in it (%d of %d; held in place while carried: %s)" % [
				kind, how, still, things.size(), latched_held])
			for th in things:
				th.queue_free()
			piece.queue_free()
			await _ticks(3)


## A Game Boy cartridge as the room has one (cartridge.tscn: the 1 kg default, damping 5 / 8, friction 0.8; the shell
## 57 x 65 x 7.5 mm, here lying flat), with continuous collision on as HeldObjectPhysics gives every pickable.
func _cart(at: Vector3) -> RigidBody3D:
	var c := _loose_box(at)
	((c.get_child(0) as CollisionShape3D).shape as BoxShape3D).size = Vector3(0.057, 0.0075, 0.065)
	c.mass = 1.0
	c.linear_damp = 5.0
	c.angular_damp = 8.0
	c.name = "GbCart"
	return c


## Small things ("Game Boy games fall through sometimes", 2026-11-12): cartridges DROPPED into an open drawer (15, 30,
## 60 cm, and thrown down at 4 m/s) must land in it; then lifted at 2.5 m/s and swung, they must still be in it.
func _small_items() -> void:
	for kind in ["nightstand", "mission_chest"]:
		for how in ["pull_in", "swing"]:
			var piece := (ScenePersistence.PLAIN_SCENES[kind] as PackedScene).instantiate() as XRToolsPickable
			piece.position = Vector3(-3.0, 0.0, -3.5)
			add_child(piece)
			for i in 30:
				await get_tree().physics_frame
			var d: VRDrawer = piece.drawers()[0] if piece is DrawerFurniture else (piece as Nightstand).drawer()
			d.set_value(0.8)
			for i in 40:
				await get_tree().physics_frame
			var body := d.target as Node3D
			var inner: AABB = (piece as DrawerFurniture)._drawers[0]["inner"] if piece is DrawerFurniture \
				else Nightstand.DRAWER_INNER
			var floor_y := inner.position.y
			var carts: Array[RigidBody3D] = []
			var spots := [[-0.1, 0.15, 0.0], [0.0, 0.30, 0.0], [0.1, 0.60, 0.0], [0.0, 0.25, 0.08]]
			for k in spots.size():
				var sp: Array = spots[k]
				var local := Vector3(inner.get_center().x + float(sp[0]) * inner.size.x * 2.0, floor_y + float(sp[1]),
					inner.get_center().z + float(sp[2]))
				var c := _cart(body.global_transform * local)
				if k == 3:
					c.linear_velocity = Vector3(0, -4.0, 0)
				carts.append(c)
			for i in 90:
				await get_tree().physics_frame
			var in_it := func() -> Array:
				var out := []
				for c in carts:
					var l := body.global_transform.affine_inverse() * c.global_position
					if not inner.grow(0.015).has_point(l):
						out.append("%s at %.0f mm over the floor" % [c.name, (l.y - floor_y) * 1000.0])
				return out
			var landed: Array = in_it.call()
			if how == "pull_in":
				_ok(landed.is_empty(), "again/%s: cartridges dropped into its open drawer land in it %s" % [kind, landed])
			# Picked up and moved as a hand moves it.
			var start := piece.global_transform
			piece.freeze = true
			piece.collision_layer = piece.picked_up_layer
			piece.collision_mask = 0
			var t := [0.0]
			var mover := Mover.new()
			if how == "pull_in":
				mover.step = func(delta: float) -> void:
					t[0] += delta
					piece.global_transform = Transform3D(start.basis, start.origin + Vector3(0, minf(t[0] * 2.5, 1.0), 0))
			else:
				var pivot := start.origin + Vector3(0, 0.0, 1.5)
				mover.step = func(delta: float) -> void:
					t[0] += delta
					var a := clampf(t[0] / 0.6, 0.0, 1.0)
					a = a * a * (3.0 - 2.0 * a) * PI * 0.5
					piece.global_transform = Transform3D(start.basis.rotated(Vector3.UP, a),
						pivot + (start.origin - pivot).rotated(Vector3.UP, a))
			add_child(mover)
			for i in 90:
				await get_tree().physics_frame
			mover.free()
			for i in 40:
				await get_tree().physics_frame
			var carried: Array = in_it.call()
			_ok(landed.is_empty() and carried.is_empty(), "again/%s: cartridges in its open drawer, picked up by %s: still in it %s" % [
				kind, how, carried])
			piece.freeze = false
			piece.collision_layer = 4
			piece.collision_mask = 196613
			for c in carts:
				c.queue_free()
			piece.queue_free()
			await _ticks(3)

## The whole unit carried holds what is in it in place; a drawer slid with the unit standing does not (what is in it
## rides and jostles by physics); and a thing a hand takes out of a carried drawer is loose again when it is let go,
## never left frozen in the air (xr-tools restores the freeze it FOUND, which was the carry's).
func _held_only_while_carried() -> void:
	var piece := (ScenePersistence.PLAIN_SCENES["nightstand"] as PackedScene).instantiate() as Nightstand
	piece.position = Vector3(2.5, 0.0, 3.5)
	add_child(piece)
	for i in 30:
		await get_tree().physics_frame
	var d := piece.drawer()
	d.set_value_no_signal(0.3)
	for i in 10:
		await get_tree().physics_frame
	# A plain pickable (the TV remote's own toggle-hold re-grabs it after a drop, which is the remote's business):
	# a box as a cartridge or a book is held, with continuous collision on as HeldObjectPhysics gives every pickable.
	var remote := XRToolsPickable.new()
	remote.name = "PlainPickable"
	var rcs := CollisionShape3D.new()
	var rbox := BoxShape3D.new()
	rbox.size = Vector3(0.05, 0.0225, 0.175)
	rcs.shape = rbox
	remote.add_child(rcs)
	remote.collision_layer = 4
	remote.collision_mask = 196613
	remote.linear_damp = 5.0
	add_child(remote)
	remote.global_transform = piece.global_transform * Transform3D(Basis(), piece.drawer_seat_local() + Vector3(0.06, 0.02, 0.0))
	for i in 60:
		await get_tree().physics_frame
	# Standing, the drawer slid out: what is in it is never frozen and rides out with it.
	var rest := remote.global_position
	var ever_frozen := false
	d.set_value(0.9)
	for i in 60:
		await get_tree().physics_frame
		ever_frozen = ever_frozen or remote.freeze
	var rode := (remote.global_position - rest).dot(piece.global_basis.z)
	_ok(not ever_frozen and rode > 0.1, "again/a drawer slid with the unit standing leaves what is in it loose; it rides (%.0f mm, frozen %s)" % [
		rode * 1000.0, ever_frozen])
	# Carried (held, standing still even): held in place.
	piece.freeze = true
	piece.collision_layer = piece.picked_up_layer
	piece.collision_mask = 0
	for i in 4:
		await get_tree().physics_frame
	_ok(remote.freeze and remote.collision_layer == piece.picked_up_layer,
		"again/the unit carried, what is in it is held in place, on the held layer (frozen %s, layer %d)" % [
		remote.freeze, remote.collision_layer])
	# A hand takes it out of the carried drawer and lets it go: loose, on its own layer.
	_pickup.name = "FakePickupAside"
	var hand := load("res://addons/godot-xr-tools/functions/function_pickup.tscn").instantiate() as Node3D
	hand.name = "FunctionPickup"
	_ctrl.add_child(hand)
	_place(remote.global_position)
	await _ticks(3)
	hand._pick_up_object(remote)
	for i in 6:
		await get_tree().physics_frame
	_place(remote.global_position + Vector3(0.3, 0.3, 0.0))
	for i in 6:
		await get_tree().physics_frame
	hand.drop_object()
	for i in 10:
		await get_tree().physics_frame
	_ok(not remote.freeze and remote.collision_layer == 4,
		"again/taken out of a carried drawer by a hand and let go, it is loose (frozen %s, layer %d)" % [
		remote.freeze, remote.collision_layer])
	piece.freeze = false
	piece.collision_layer = 4
	piece.collision_mask = 196613
	hand.queue_free()
	_pickup.name = "FunctionPickup"
	_place(FAR)
	remote.queue_free()
	piece.queue_free()
	await _ticks(3)
