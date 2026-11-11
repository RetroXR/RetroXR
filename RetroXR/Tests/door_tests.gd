## VRDoor: a leaf on a vertical hinge, shut by its latch until its knob is turned,
## then swung by the same hand; saved in the slot and announced in netplay as a
## room's own control. A hand here is an XRController3D on a tracker of its own.
##   godot --headless --path RetroXR res://Tests/door_tests.tscn [-- --only=<group>]
extends "res://Tests/test_suite.gd"

const DOOR_GLB := "res://imported-assets/bedroom/furniture/door.glb"

var _hands: Array[Dictionary] = []


## NetObjectSync asks its parent whether a session is up, every frame.
class StubNM extends Node:
	func is_host() -> bool: return true
	func is_client() -> bool: return false
	func is_active() -> bool: return false
	func world_root_node() -> Node: return null


func _ready() -> void:
	await _geometry()
	await _latch_refuses_the_leaf()
	await _turn_and_pull()
	await _short_turn_keeps_it_shut()
	await _release_near_shut_latches()
	await _swings_home_and_latches()
	await _pointer_toggles()
	await _model_split()
	await _save_records_room_doors()
	await _net_room_state_and_events()
	await _bar_geometry()
	await _bar_short_push()
	await _bar_push_through()
	await _bar_ends_do_nothing()
	await _closer()
	await _bar_pointer()
	await _bar_springs_home_asleep()
	for h in _hands:
		XRServer.remove_tracker(h["tracker"] as XRControllerTracker)
	_finish()


# --- rig ------------------------------------------------------------------------

func _hand(tracker_name: String) -> Dictionary:
	var origin := XROrigin3D.new()
	add_child(origin)
	var ctrl := XRController3D.new()
	ctrl.tracker = StringName(tracker_name)
	ctrl.pose = &"default"
	origin.add_child(ctrl)
	var tracker := XRControllerTracker.new()
	tracker.name = StringName(tracker_name)
	XRServer.add_tracker(tracker)
	tracker.set_pose(&"default", Transform3D.IDENTITY, Vector3.ZERO, Vector3.ZERO,
		XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	var h := {"origin": origin, "ctrl": ctrl, "tracker": tracker}
	_hands.append(h)
	_hand_at(h, Vector3(0, 10, 0))
	return h


## The hand's fingertip at `world` (6 cm ahead of the controller along its -Z),
## the controller rolled `roll_deg` about the world Z.
func _hand_at(h: Dictionary, world: Vector3, roll_deg: float = 0.0) -> void:
	var b := Basis(Vector3.BACK, deg_to_rad(roll_deg))
	(h["origin"] as XROrigin3D).global_transform = Transform3D(b,
		world + b * Vector3(0, 0, PokeTip.TIP_FORWARD))
	PokeTip._cache_frame = -1


func _trigger(h: Dictionary, value: float) -> void:
	(h["tracker"] as XRControllerTracker).set_input(&"trigger", value)


func _ticks(n: int) -> void:
	for i in n:
		PokeTip._cache_frame = -1
		await get_tree().process_frame


## A plain door at the world origin unless placed: hinges +X, swings toward +Z.
func _door(xf := Transform3D.IDENTITY, side := VRDoor.HingeSide.POSITIVE_X,
		swing := VRDoor.Swing.TOWARD_POSITIVE_Z) -> VRDoor:
	var d := VRDoor.new()
	d.hinge_side = side
	d.swing = swing
	d.width = 0.9
	d.log_name = "test"
	d.transform = xf
	add_child(d)
	await _ticks(2)   # the widgets collect their controllers a frame after _ready
	return d


func _free(n: Node) -> void:
	if is_instance_valid(n):
		n.free()
	await _ticks(1)


# --- cases ----------------------------------------------------------------------

## The axis is the door's vertical and the leaf swings toward the face it was told,
## about its hinge edge — every side and face, on a door yawed 30°, settled by
## where the knob (on the latch edge) ends up, never by reading the code.
func _geometry() -> void:
	var yaw := Basis(Vector3.UP, deg_to_rad(30.0))
	for side: int in [VRDoor.HingeSide.POSITIVE_X, VRDoor.HingeSide.NEGATIVE_X]:
		for swing: int in [VRDoor.Swing.TOWARD_POSITIVE_Z, VRDoor.Swing.TOWARD_NEGATIVE_Z]:
			var tag := "geometry/%s %s" % ["+X" if side == 0 else "-X", "+Z" if swing == 0 else "-Z"]
			var d := await _door(Transform3D(yaw, Vector3(1, 0, 2)), side, swing)
			var axis: Vector3 = (d.get_node("HingeFrame") as Node3D).global_basis.x
			_ok(absf(axis.normalized().dot(Vector3.UP)) > 0.9999,
				tag + ": the hinge axis is vertical", str(axis))
			var knob0 := d.to_local(d.knob.global_position)
			var latch_x := -1.0 if side == VRDoor.HingeSide.POSITIVE_X else 1.0
			_ok(signf(knob0.x) == latch_x and absf(knob0.x) > 0.3,
				tag + ": the knob is on the latch edge", str(knob0))
			d.open_to(90.0, false)
			var knob90 := d.to_local(d.knob.global_position)
			var s := 1.0 if swing == VRDoor.Swing.TOWARD_POSITIVE_Z else -1.0
			_ok(knob90.z * s > 0.3, tag + ": at 90 deg the latch edge stands out on the swing side",
				str(knob90))
			_ok(absf(knob90.x - (0.45 * -latch_x)) < 0.08,
				tag + ": ...in line with the hinge edge", str(knob90))
			_ok(is_equal_approx(knob90.y, knob0.y), tag + ": ...at the same height")
			# The leaf's collision goes with it: a ray through the middle of the doorway
			# meets nothing once it is open (it stood shut there once, an invisible wall).
			await get_tree().physics_frame
			await get_tree().physics_frame
			var space := get_viewport().world_3d.direct_space_state
			var through := PhysicsRayQueryParameters3D.create(d.to_global(Vector3(0, 1.0, -0.6)),
				d.to_global(Vector3(0, 1.0, 0.6)))
			var hit := space.intersect_ray(through)
			_ok(hit.is_empty(), tag + ": open, the doorway is clear (the leaf's collision swung too)",
				str(hit.get("position", "")))
			await _free(d)


## Shut, the leaf cannot be taken: a trigger on its face, away from the knob, does nothing.
func _latch_refuses_the_leaf() -> void:
	var h := _hand("door_a")
	var d := await _door()
	_ok(d.is_latched(), "latch/a new door starts latched")
	_hand_at(h, Vector3(0.0, 1.4, 0.03))
	_trigger(h, 1.0)
	await _ticks(4)
	_ok(not d.hinge.is_held(), "latch/a trigger on the shut leaf takes nothing")
	_hand_at(h, Vector3(0.0, 1.4, 0.5))
	await _ticks(4)
	_eq(d.get_angle_deg(), 0.0, "latch/...and pulling does not move it")
	_trigger(h, 0.0)
	# Parked away: a leaf swung later into a fingertip left here stops on it.
	_hand_at(h, Vector3(0, 10, 0))
	await _ticks(2)
	await _free(d)


## Turn the knob past unlatch_turn with the wrist, keep the trigger, pull: the latch
## lets go, the same hand swings the leaf, and released open it stays; the knob
## comes back to rest by itself.
func _turn_and_pull() -> void:
	var h := _hand("door_b")
	var d := await _door()
	var knob_at := d.knob.global_position + Vector3(0, 0, 0.09)
	_hand_at(h, knob_at)
	await _ticks(2)
	_trigger(h, 1.0)
	await _ticks(2)
	_ok(d.knob.is_held(), "pull/the trigger at the knob takes the knob")
	_ok(not d.hinge.is_held(), "pull/...not the leaf")
	for k in range(1, 11):
		_hand_at(h, knob_at, -5.0 * k)
		await _ticks(1)
	_ok(d.knob.turn() >= d.unlatch_turn, "pull/the wrist turned the knob",
		"turn %.2f" % d.knob.turn())
	await _ticks(1)
	_ok(not d.is_latched(), "pull/turned past unlatch_turn the latch lets go")
	_ok(d.hinge.is_held(), "pull/...and the same hand holds the leaf")
	# Pull the latch edge round the hinge to 40 degrees.
	var hinge_at := Vector3(0.45, knob_at.y, 0.0175)
	var r := hinge_at.distance_to(Vector3(knob_at.x, knob_at.y, 0.0175))
	for k in range(1, 9):
		var a := deg_to_rad(5.0 * k)
		_hand_at(h, hinge_at + Vector3(-r * cos(a), 0, r * sin(a) + 0.07), -50.0)
		await _ticks(1)
	var opened := d.get_angle_deg()
	_ok(opened > 30.0 and opened < 50.0, "pull/pulling swings the leaf", "%.1f deg" % opened)
	_trigger(h, 0.0)
	await _ticks(30)
	_ok(absf(d.get_angle_deg() - opened) < 0.5, "pull/let go open, it stays (no spring)",
		"%.1f -> %.1f" % [opened, d.get_angle_deg()])
	_ok(not d.is_latched(), "pull/...unlatched")
	_ok(is_equal_approx(d.knob.value, 0.5), "pull/the knob springs back to rest",
		"value %.2f" % d.knob.value)
	_hand_at(h, Vector3(0, 10, 0))
	await _free(d)


## The control leg: a knob turned only a little keeps the latch in, and a pull goes nowhere.
func _short_turn_keeps_it_shut() -> void:
	var h := _hand("door_c")
	var d := await _door()
	var knob_at := d.knob.global_position + Vector3(0, 0, 0.09)
	_hand_at(h, knob_at)
	await _ticks(2)
	_trigger(h, 1.0)
	await _ticks(2)
	for k in range(1, 5):
		_hand_at(h, knob_at, -5.0 * k)
		await _ticks(1)
	_ok(d.knob.turn() > 0.1 and d.knob.turn() < d.unlatch_turn,
		"short/the knob turned a little", "turn %.2f" % d.knob.turn())
	_hand_at(h, knob_at + Vector3(0, 0, 0.3), -20.0)
	await _ticks(4)
	_ok(d.is_latched(), "short/a short turn keeps it latched")
	_eq(d.get_angle_deg(), 0.0, "short/...and the pull does not open it")
	_trigger(h, 0.0)
	_hand_at(h, Vector3(0, 10, 0))
	await _ticks(2)
	await _free(d)


## A leaf let go within close_latch_deg latches; the knob turned and let go without
## a pull leaves the bolt back in, too.
func _release_near_shut_latches() -> void:
	var d := await _door()
	d.apply_state(2.0, false)
	await _ticks(2)
	d.hinge._held_prev = true    # as if a hand had just let go at 2 degrees
	await _ticks(2)
	_ok(d.is_latched(), "release/let go 2 deg from shut, it latches")
	d.apply_state(40.0, false)
	d.hinge._held_prev = true
	await _ticks(10)
	_ok(not d.is_latched() and absf(d.get_angle_deg() - 40.0) < 0.01,
		"release/let go at 40 deg, it stays at 40 unlatched")
	await _free(d)


## Swung home on its own (a push's momentum), an armed door latches; one unlatched
## at 0 and never opened does not (VRDoor decides that one when the knob comes back).
func _swings_home_and_latches() -> void:
	var d := await _door()
	d.apply_state(30.0, false)
	await _ticks(2)
	_ok(d.hinge.is_armed(), "home/opened past the latch angle, the bolt is armed")
	d.hinge.set_rotation_deg_no_signal(0.2)
	await _ticks(2)
	_ok(d.is_latched(), "home/swinging home it latches by itself")
	d.apply_state(0.0, false)
	await _ticks(4)
	_ok(not d.is_latched(), "home/unlatched at 0 and never opened, it does not latch itself")
	await _free(d)


## A pointer press on the knob (the desktop's click) swings a shut door open, and
## the next one swings it shut and latched.
func _pointer_toggles() -> void:
	var d := await _door()
	var reports: Array = []
	d.report_to = func(args: Dictionary) -> void: reports.append(args.duplicate())
	d.knob.pointer_pressed.emit()
	await _wait_until(func() -> bool: return absf(d.get_angle_deg() - d.desktop_open_deg) < 0.1, 3.0)
	await _ticks(3)   # the report that it stopped goes out the frame after it stops
	_ok(absf(d.get_angle_deg() - d.desktop_open_deg) < 0.1 and not d.is_latched(),
		"pointer/a press opens it to desktop_open_deg", "%.1f deg" % d.get_angle_deg())
	_ok(reports.size() >= 2 and reports.size() < 30,
		"pointer/...announced a few times, not every frame", "%d reports" % reports.size())
	_ok(not reports.is_empty() and absf(float(reports[-1]["deg"]) - d.desktop_open_deg) < 0.6,
		"pointer/...the last report is where it stopped")
	d.knob.pointer_pressed.emit()
	await _wait_until(func() -> bool: return d.is_latched(), 3.0)
	await _ticks(3)
	_ok(d.is_latched() and is_zero_approx(d.get_angle_deg()), "pointer/the next press shuts and latches it")
	_ok(not reports.is_empty() and bool(reports[-1]["latched"]), "pointer/...and says so")
	await _free(d)


## door.glb is one mesh: its leaf and lockset come out of it, the lockset split by
## triangle (bolt on the leaf, knobs on the spindle), and the frame keeps the rest.
func _model_split() -> void:
	var d := VRDoor.new()
	d.leaf_surfaces = PackedStringArray(["Trim_Door"])
	d.knob_surfaces = PackedStringArray(["Knob_Metal", "Knob_Metal_2", "NoSuchSurface"])
	var model := (load(DOOR_GLB) as PackedScene).instantiate()
	model.name = "Model"
	d.add_child(model)
	add_child(d)
	await _ticks(2)
	var frame_mi: MeshInstance3D = null
	for n in model.find_children("*", "MeshInstance3D", true, false):
		frame_mi = n as MeshInstance3D
	_ok(frame_mi != null and frame_mi.mesh != null and frame_mi.mesh.get_surface_count() == 2,
		"split/the frame keeps its trim and hinges (2 surfaces)",
		str(frame_mi.mesh.get_surface_count() if frame_mi != null and frame_mi.mesh != null else -1))
	var leaf := d.get_node_or_null("HingeFrame/HingePivot/Leaf") as MeshInstance3D
	var knob := d.get_node_or_null("HingeFrame/HingePivot/DoorKnob/KnobPivot/Knob") as MeshInstance3D
	_ok(leaf != null and leaf.mesh.get_surface_count() >= 2,
		"split/the leaf has its face and the lockset's in-leaf part")
	_ok(knob != null and knob.mesh.get_surface_count() >= 1, "split/the knob has its own mesh")
	_ok(absf(d._leaf_box.size.x - 0.9144) < 0.002 and absf(d._leaf_box.size.y - 2.032) < 0.002,
		"split/the leaf's own bounds size the door", str(d._leaf_box))
	if knob != null:
		var to_door := d.global_transform.affine_inverse() * knob.global_transform
		var ab := DoorModelSplit.bounds(knob.mesh, [0], to_door)
		_ok(ab.position.z < d._leaf_box.position.z or ab.end.z > d._leaf_box.end.z,
			"split/the knob is what stands out of the leaf", str(ab))
		_ok(absf(d.knob.position.length()) > 0.0 and absf(d.to_local(d.knob.global_position).y - 0.876) < 0.02,
			"split/the knob's axle is at the model's knob height",
			str(d.to_local(d.knob.global_position)))
	# The latch bolt is its own part: it slides into the edge with the knob, never turns with it.
	var bolt := d.get_node_or_null("HingeFrame/HingePivot/Bolt") as Node3D
	_ok(bolt != null and absf(d._bolt_travel - 0.0102) < 0.001,
		"split/the latch bolt is its own part, about 10 mm out of the edge",
		"travel %.4f" % d._bolt_travel)
	if bolt != null:
		var rest := bolt.transform
		var at0 := d.to_local(bolt.global_position)
		d.knob.return_speed_deg = 0.0   # held where it is put
		d.knob.set_value_no_signal(0.5 + 0.5 * d.unlatch_turn)
		await _ticks(2)
		var at1 := d.to_local(bolt.global_position)
		_ok(absf((at1.x - at0.x) - d._bolt_travel) < 0.0005 and absf(at1.y - at0.y) < 1e-5
			and absf(at1.z - at0.z) < 1e-5,
			"split/turned to the unlatch point, the bolt is in flush with the edge", str(at1 - at0))
		_ok(bolt.transform.basis.is_equal_approx(rest.basis), "split/...sliding, not turning")
		d.knob.set_value_no_signal(0.5 + 0.25 * d.unlatch_turn)
		await _ticks(2)
		_ok(absf(d.bolt_in() - 0.5) < 0.01, "split/half the turn, half way in", "%.2f" % d.bolt_in())
		d.knob.set_value_no_signal(0.5)
		await _ticks(2)
		_ok(bolt.transform.is_equal_approx(rest), "split/at rest, it is back out")
	d.open_to(90.0, false)
	var leaf_c := d.to_local(leaf.global_transform * leaf.mesh.get_aabb().get_center()) if leaf != null else Vector3.ZERO
	_ok(leaf_c.z > 0.3, "split/open, the model's leaf stands out on +Z", str(leaf_c))
	await _free(d)


## A room's door is in the slot beside its switches; one inside a spawned object is
## not (its controls are in that object's own entry). Restored, it stands as saved.
func _save_records_room_doors() -> void:
	var root := Node3D.new()
	root.name = "SaveRoot"
	add_child(root)
	var room_door := VRDoor.new()
	room_door.name = "Closet"
	root.add_child(room_door)
	var prop := Node3D.new()
	prop.add_to_group("spawned")
	root.add_child(prop)
	var prop_door := VRDoor.new()
	prop.add_child(prop_door)
	await _ticks(2)
	room_door.apply_state(55.0, false)
	var sp := ScenePersistence.new()
	var recs := sp._collect_doors(root)
	_eq(recs.size(), 1, "save/one record: the room's door, not the prop's")
	if recs.size() == 1:
		_eq(recs[0]["path"], "Closet", "save/keyed by path")
		_ok(absf(float(recs[0]["deg"]) - 55.0) < 0.01 and not bool(recs[0]["latched"]),
			"save/its angle and latch")
	room_door.apply_state(0.0, true)
	sp._restore_doors(root, JSON.parse_string(JSON.stringify(recs)))
	_ok(absf(room_door.get_angle_deg() - 55.0) < 0.01 and not room_door.is_latched(),
		"save/restored through JSON it stands as saved")
	sp._restore_doors(root, [{"path": "Gone", "deg": 10.0, "latched": false}, "junk"])
	_ok(true, "save/a missing door or a junk record is skipped")
	var reports: Array = []
	prop_door.report_to = func(args: Dictionary) -> void: reports.append(args)
	prop_door.open_to(30.0, false)
	await _ticks(3)
	_eq(reports.size(), 0, "save/a door in a spawned object never announces itself")
	await _free(root)


## A late joiner gets the room's doors; an EV_DOOR moves one there without echoing.
func _net_room_state_and_events() -> void:
	var root := Node3D.new()
	add_child(root)
	var nm := StubNM.new()
	add_child(nm)
	var sync := NetObjectSync.new()
	nm.add_child(sync)
	var d := VRDoor.new()
	d.name = "Door"
	root.add_child(d)
	await _ticks(2)
	var reports: Array = []
	d.report_to = func(args: Dictionary) -> void: reports.append(args)
	d.apply_state(70.0, false)
	var state := sync._capture_room_state(root)
	var rec: Dictionary = {}
	for r: Dictionary in state:
		if r.get("kind") == "door":
			rec = r
	_eq(rec.get("path"), "Door", "net/the room state carries the door")
	_ok(absf(float(rec.get("value", 0.0)) - 70.0) < 0.01 and not bool(rec.get("latched", true)),
		"net/...its angle and latch")
	d.apply_state(0.0, true)
	sync._apply_room_state(root, state)
	_ok(absf(d.get_angle_deg() - 70.0) < 0.01, "net/a late joiner's door stands where the host's does")
	sync._dispatch_event(NetEvents.Event.EV_DOOR, {"door": d, "deg": 20.0, "latched": false})
	await _wait_until(func() -> bool: return absf(d.get_angle_deg() - 20.0) < 0.01, 2.0)
	_ok(absf(d.get_angle_deg() - 20.0) < 0.01, "net/an EV_DOOR eases it to the sent angle")
	await _ticks(10)
	_eq(reports.size(), 0, "net/...and is not echoed back")
	sync._dispatch_event(NetEvents.Event.EV_DOOR, {"door": d, "deg": 0.0, "latched": true})
	await _wait_until(func() -> bool: return d.is_latched(), 2.0)
	_ok(d.is_latched(), "net/a remote shut latches it")
	_eq(reports.size(), 0, "net/...without an echo either")
	nm.free()
	await _free(root)


# --- the crash bar ---------------------------------------------------------------

## A crash-bar door at the origin: hinges +X, swings toward +Z, so the bar is on -Z.
func _bar_door(swing := VRDoor.Swing.TOWARD_POSITIVE_Z, closing := false) -> VRDoor:
	var d := VRDoor.new()
	d.opener = VRDoor.Opener.PUSH_BAR
	d.swing = swing
	d.width = 0.9
	d.self_closing = closing
	d.log_name = "bar"
	add_child(d)
	await _ticks(2)
	return d


## A point on the bar's face, `depth` metres in from where it rests (negative: in front).
func _on_bar(d: VRDoor, x: float, depth: float) -> Vector3:
	var half: Vector3 = d.bar._half_extents()
	return d.bar.to_global(Vector3(x, 0.0, -half.z + depth))


## The bar is on the face the door swings AWAY from, either way it swings.
func _bar_geometry() -> void:
	for swing: int in [VRDoor.Swing.TOWARD_POSITIVE_Z, VRDoor.Swing.TOWARD_NEGATIVE_Z]:
		var d := await _bar_door(swing)
		var s := 1.0 if swing == VRDoor.Swing.TOWARD_POSITIVE_Z else -1.0
		var at := d.to_local(d.bar.global_position)
		_ok(at.z * s < -0.04, "bar/geometry: the bar stands out of the push face (swing %+d)" % int(s),
			str(at))
		var into: Vector3 = d.global_basis.inverse() * (d.bar.global_basis * Vector3(0, 0, 1))
		_ok(into.z * s > 0.99, "bar/geometry: it is pushed the way the door swings (swing %+d)" % int(s),
			str(into))
		_ok(d.knob == null, "bar/geometry: a bar door has no knob")
		await _free(d)


## A fingertip pushes the bar part way: it goes in as far as the tip, the latch holds,
## and drawn back the bar springs out again.
func _bar_short_push() -> void:
	var h := _hand("bar_a")
	var d := await _bar_door()
	_hand_at(h, _on_bar(d, 0.1, -0.004))
	await _ticks(3)
	_ok(d.bar.is_pushed(), "bar/short: a fingertip at the bar's face takes it")
	_hand_at(h, _on_bar(d, 0.1, 0.01))
	await _ticks(3)
	_ok(absf(d.bar.value - 0.4) < 0.05, "bar/short: it goes in as far as the tip",
		"value %.2f" % d.bar.value)
	_ok(d.is_latched(), "bar/short: 40% of the way, the latch holds")
	_hand_at(h, _on_bar(d, 0.1, -0.15))
	await _ticks(20)
	_ok(not d.bar.is_pushed() and is_zero_approx(d.bar.value), "bar/short: let go, it springs back out",
		"value %.2f" % d.bar.value)
	_ok(d.is_latched(), "bar/short: ...still latched")
	_hand_at(h, Vector3(0, 10, 0))
	await _free(d)


## Pushed through, the latch goes and the same hand walks the leaf open; drawn back,
## the leaf carries on a little and stops (no closer).
func _bar_push_through() -> void:
	var h := _hand("bar_b")
	var d := await _bar_door()
	_hand_at(h, _on_bar(d, 0.0, -0.004))
	await _ticks(3)
	var tip0 := _on_bar(d, 0.0, 0.02)
	_hand_at(h, tip0)
	await _ticks(3)
	_ok(not d.is_latched(), "bar/through: pushed 80% in, the latch lets go")
	_ok(d.hinge.is_pushing(), "bar/through: ...and the hand pushes the leaf")
	var hinge_at := d.to_global(Vector3(0.45, 0.0, 0.0175))
	hinge_at.y = tip0.y
	for k in range(1, 9):
		var turn := Basis(Vector3.UP, deg_to_rad(5.0 * k))
		_hand_at(h, hinge_at + turn * (tip0 - hinge_at))
		await _ticks(1)
	var walked := d.get_angle_deg()
	_ok(walked > 30.0 and walked < 45.0, "bar/through: walking on swings the door away from the bar",
		"%.1f deg" % walked)
	_hand_at(h, tip0 + Vector3(0, 0, -0.4))
	await _ticks(40)
	_ok(not d.hinge.is_pushing(), "bar/through: drawn back, the hand lets go")
	_ok(d.get_angle_deg() >= walked - 0.01, "bar/through: ...and the leaf does not fall back (it coasts or stops)",
		"%.1f -> %.1f" % [walked, d.get_angle_deg()])
	_ok(is_zero_approx(d.bar.value), "bar/through: the bar is back out")
	_hand_at(h, Vector3(0, 10, 0))
	await _free(d)


## A fingertip just past the bar's end, or a hand pulling from the far side, does nothing.
func _bar_ends_do_nothing() -> void:
	var h := _hand("bar_c")
	var d := await _bar_door()
	var half: Vector3 = d.bar._half_extents()
	_hand_at(h, _on_bar(d, half.x + 0.05, -0.004))
	await _ticks(3)
	_hand_at(h, _on_bar(d, half.x + 0.05, 0.02))
	await _ticks(3)
	_ok(not d.bar.is_pushed() and is_zero_approx(d.bar.value), "bar/ends: past the bar's end it is not pushed")
	_ok(d.is_latched(), "bar/ends: ...and the door stays latched")
	_hand_at(h, Vector3(0, 10, 0))
	await _free(d)


## A door with a closer comes home and latches by itself; one without stays put.
func _closer() -> void:
	var d := await _bar_door(VRDoor.Swing.TOWARD_POSITIVE_Z, true)
	d.apply_state(30.0, false)
	await _wait_until(func() -> bool: return d.is_latched(), 8.0)
	_ok(d.is_latched() and is_zero_approx(d.get_angle_deg()), "closer/a self-closing door shuts and latches",
		"%.1f deg" % d.get_angle_deg())
	# Slowly, as an overhead closer does: from 30 degrees it takes seconds, not a snap.
	var slow := await _bar_door(VRDoor.Swing.TOWARD_POSITIVE_Z, true)
	slow.apply_state(30.0, false)
	await get_tree().create_timer(1.0).timeout
	_ok(slow.get_angle_deg() > 10.0 and not slow.is_latched(), "closer/...slowly (still open a second later)",
		"%.1f deg" % slow.get_angle_deg())
	await _free(slow)
	await _free(d)
	var still := await _bar_door()
	still.apply_state(30.0, false)
	await _ticks(60)
	_ok(absf(still.get_angle_deg() - 30.0) < 0.01, "closer/without a closer it stays open")
	await _free(still)


## A press on the bar from the desktop opens the door; a closer brings it back after a moment.
func _bar_pointer() -> void:
	var d := await _bar_door(VRDoor.Swing.TOWARD_POSITIVE_Z, true)
	d.bar.pointer_pressed.emit()
	await _wait_until(func() -> bool: return d.get_angle_deg() > d.desktop_open_deg - 0.5, 3.0)
	_ok(absf(d.get_angle_deg() - d.desktop_open_deg) < 0.5, "bar/pointer: a press opens it",
		"%.1f deg" % d.get_angle_deg())
	await _ticks(30)
	_ok(d.get_angle_deg() > d.desktop_open_deg - 1.0, "bar/pointer: it stands open a moment first")
	await _wait_until(func() -> bool: return d.is_latched(), 15.0)
	_ok(d.is_latched(), "bar/pointer: then the closer shuts and latches it")
	await _free(d)


## A spring-return slider let go part way keeps itself awake until it is home: PokeWake
## puts an idle one to sleep after 30 frames, and a slow spring outlasts that.
func _bar_springs_home_asleep() -> void:
	var d := await _bar_door()
	d.bar.return_speed = 0.5   # two seconds home
	d.bar.set_value_no_signal(1.0)
	await _wait_until(func() -> bool: return is_zero_approx(d.bar.value), 4.0)
	_ok(is_zero_approx(d.bar.value), "bar/spring: a slow spring still gets home (it does not fall asleep)",
		"value %.2f" % d.bar.value)
	await _free(d)
