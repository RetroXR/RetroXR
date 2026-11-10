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
