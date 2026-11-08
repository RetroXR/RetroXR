## The RETRO XR television's key door (TvKeyDoor, RetroXRCrtShell._build_door): a flap on a push-push catch over the
## five keys in the bezel's bottom right. A fingertip pushed into the shut door unlatches it and it falls open; a
## pointer's press does the same; pushed back up (fingertip) or dragged home (mouse) it latches; let go of part-way
## it falls open again. The five keys are dead until it stands open, and its angle and latch are saved.
##
##   godot --headless --path RetroXR res://Tests/tv_key_door_tests.tscn [-- --only=poke]
##
## Groups: build/ pointer/ mouse/ poke/ keys/ save/
extends "res://Tests/test_suite.gd"

const FINGER := &"tv_key_door_test_finger"
const DOOR_KEYS := ["AudioModeButton", "AudioOutButton", "CRTButton", "AspectButton", "StereoButton"]

var _only := ""
var _finger: XRPositionalTracker
var _cam: Camera3D


func _ready() -> void:
	suite_tag = "tvdoor"
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("[tvdoor] TIMEOUT")
		get_tree().quit(1))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.split("=")[1]
	# Made before the set: a hinge gathers its controllers a frame after it enters the tree.
	_finger = _tracked_finger()
	_cam = Camera3D.new()
	add_child(_cam)
	_cam.look_at_from_position(Vector3(0.1, 0.95, 1.2), Vector3(0.1, 0.9, 0))
	_cam.current = true
	for group: String in ["build", "pointer", "mouse", "poke", "keys", "save"]:
		if not _only.is_empty() and not group.begins_with(_only):
			continue
		var tv := await _make_set()
		if tv == null:
			_ok(false, "%s/the RETRO XR set builds" % group)
			continue
		await call("_" + group, tv)
		tv.queue_free()
		await _ticks(2)
	XRServer.remove_tracker(_finger)
	_finish()


func _make_set() -> Node3D:
	var tv := (load("res://Scenes/Objects/tv.tscn") as PackedScene).instantiate() as Node3D
	tv.set("tv_model", "retroxr_crt")
	if tv is RigidBody3D:
		(tv as RigidBody3D).freeze = true
	add_child(tv)
	tv.global_position = Vector3(0, 1, 0)
	await _ticks(4)
	return tv if _door(tv) != null else null


func _door(tv: Node3D) -> TvKeyDoor:
	return tv.find_child("KeyDoorHinge", true, false) as TvKeyDoor


func _box(door: TvKeyDoor) -> CollisionShape3D:
	return door.get_node("CollisionShape3D") as CollisionShape3D


func _keys_live(tv: Node3D) -> Array:
	var out := []
	for k: String in DOOR_KEYS:
		var b := tv.find_child(k, true, false) as VRButton
		if b != null and b.collision_layer != 0:
			out.append(k)
	return out


func _press(door: TvKeyDoor, type: int) -> void:
	door.pointer_event(XRToolsPointerEvent.new(type, _cam, door, _box(door).global_position, _box(door).global_position))


## Frames until the door stops moving (or `frames` run out).
func _settle(door: TvKeyDoor, frames: int = 120) -> void:
	var last := INF
	for i in frames:
		await get_tree().process_frame
		var d := door.get_rotation_deg()
		if is_equal_approx(d, last):
			return
		last = d


# ── build/ ────────────────────────────────────────────────────────────────────

func _build(tv: Node3D) -> void:
	var door := _door(tv)
	_ok(door.is_latched_closed() and is_zero_approx(door.get_rotation_deg()), "build/the door starts latched shut",
		"%.1f deg, latched %s" % [door.get_rotation_deg(), door.is_latched_closed()])
	_ok(door.is_in_group(ScenePersistence.CONTROL_GROUP), "build/the door is a saved control (CONTROL_GROUP)")
	var pivot := door.target
	var drawn := ApplianceModel.node_bounds(pivot.get_child(0), pivot)
	var cs := _box(door)
	var box := (door.transform * cs.transform) * cs.shape.get_debug_mesh().get_aabb()
	var off := maxf((box.position - drawn.position).abs()[(box.position - drawn.position).abs().max_axis_index()],
		(box.end - drawn.end).abs()[(box.end - drawn.end).abs().max_axis_index()])
	_ok(off <= 0.0001, "build/the door's box is the door as drawn, no margin", "%.2f mm off" % (off * 1000.0))
	_ok(not cs.disabled and door.collision_layer != 0, "build/the shut door can be reached (its box is live)")
	var levels := 0
	for c in pivot.get_children():
		if c is MeshInstance3D:
			levels += 1
	_ok(levels == 3, "build/every level's door hangs on the pivot", "%d" % levels)
	_eq(_keys_live(tv), [], "build/the five keys behind the shut door are dead")


# ── pointer/ ──────────────────────────────────────────────────────────────────

func _pointer(tv: Node3D) -> void:
	var door := _door(tv)
	_press(door, XRToolsPointerEvent.Type.PRESSED)
	_ok(not door.is_latched_closed(), "pointer/a press on the shut door lets the catch go")
	_press(door, XRToolsPointerEvent.Type.RELEASED)
	await _settle(door)
	_ok(not door.is_latched_closed() and is_equal_approx(door.get_rotation_deg(), TvKeyDoor.OPEN_DEG),
		"pointer/released, it falls all the way open", "%.1f deg" % door.get_rotation_deg())
	_eq(_keys_live(tv), DOOR_KEYS, "pointer/open, the five keys are live")


# ── mouse/ ────────────────────────────────────────────────────────────────────

## The door's free edge's path on screen, as the drag reads it.
func _close_dir(door: TvKeyDoor) -> Vector2:
	return -(door.call("_edge_on_screen")["dir"] as Vector2)


func _mouse(tv: Node3D) -> void:
	var door := _door(tv)
	(tv.find_child("RetroXRCrt", true, false)).call("set_door_open", true)
	await _ticks(2)
	_press(door, XRToolsPointerEvent.Type.PRESSED)
	_ok(door.is_mouse_held(), "mouse/a press on the open door takes it with the mouse")
	# Part-way: drag it 60 deg up with real mouse motion through the viewport, let go: it falls open.
	var start := door.get_rotation_deg()
	for i in 12:
		var ev := InputEventMouseMotion.new()
		ev.relative = _close_dir(door) * (door.call("_px_per_deg") as float) * 5.0
		get_viewport().push_input(ev)
		await get_tree().process_frame
	_ok(door.get_rotation_deg() < start - 50.0 and not door.is_latched_closed(),
		"mouse/mouse motion swings the held door up", "%.1f -> %.1f deg" % [start, door.get_rotation_deg()])
	_ok(_keys_live(tv).is_empty(), "mouse/below 60 deg the keys go dead", str(_keys_live(tv)))
	_press(door, XRToolsPointerEvent.Type.RELEASED)
	await _settle(door)
	_ok(not door.is_latched_closed() and is_equal_approx(door.get_rotation_deg(), TvKeyDoor.OPEN_DEG),
		"mouse/let go of part-way, it falls open again", "%.1f deg" % door.get_rotation_deg())
	# All the way: dragged home, it latches there with the button still down.
	_press(door, XRToolsPointerEvent.Type.PRESSED)
	for i in 40:
		if door.is_latched_closed():
			break
		door.drag_by_pixels(_close_dir(door) * (door.call("_px_per_deg") as float) * 5.0)
		await get_tree().process_frame
	_ok(door.is_latched_closed() and is_zero_approx(door.get_rotation_deg()), "mouse/dragged home, it latches",
		"%.1f deg, latched %s" % [door.get_rotation_deg(), door.is_latched_closed()])
	_ok(not door.is_mouse_held(), "mouse/latching lets go of the mouse")
	_press(door, XRToolsPointerEvent.Type.RELEASED)
	await _ticks(10)
	_ok(door.is_latched_closed() and is_zero_approx(door.get_rotation_deg()), "mouse/and stays latched after the release")
	_eq(_keys_live(tv), [], "mouse/latched, the keys are dead")


# ── poke/ ─────────────────────────────────────────────────────────────────────

func _tracked_finger() -> XRPositionalTracker:
	var tr := XRPositionalTracker.new()
	tr.name = FINGER
	tr.type = XRServer.TRACKER_CONTROLLER
	XRServer.add_tracker(tr)
	var origin := XROrigin3D.new()
	origin.name = "TestOrigin"
	add_child(origin)
	var ctrl := XRController3D.new()
	ctrl.tracker = FINGER
	origin.add_child(ctrl)
	var tip := Node3D.new()
	tip.name = "PokeTip"
	ctrl.add_child(tip)
	_finger = tr
	_place(Vector3(0, 4, 0))
	return tr


func _place(at: Vector3) -> void:
	_finger.set_pose(&"default", Transform3D(Basis(), at), Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)


func _ticks(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## The fingertip along a list of points, a frame each.
func _walk(points: Array) -> void:
	for p: Vector3 in points:
		_place(p)
		await get_tree().process_frame


## A point on the door's outer face (its box's +Z), `out` metres off it, at the door's angle `deg` (the pivot's
## frame turned there), `up` of the way from its middle toward its free edge.
func _on_face(door: TvKeyDoor, deg: float, out: float, up: float = 0.0) -> Vector3:
	var pivot := door.target
	var box := (_box(door).shape as BoxShape3D).size
	var local := door.position + Vector3(0, box.y * 0.5 * up, box.z * 0.5 + out)
	var turned := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(deg)), pivot.position)
	return (pivot.get_parent() as Node3D).global_transform * turned * local


func _poke(tv: Node3D) -> void:
	var door := _door(tv)
	await _ticks(2)
	# Into the shut door's face, a millimetre a frame: it gives under the finger, then the catch lets go.
	var pts := []
	for mm in range(20, -5, -1):
		pts.append(_on_face(door, 0.0, mm * 0.001))
	var unlatched_at := INF
	var deepest := 0.0
	for p: Vector3 in pts:
		_place(p)
		await get_tree().process_frame
		deepest = minf(deepest, door.get_rotation_deg())
		if not door.is_latched_closed() and unlatched_at == INF:
			unlatched_at = (p - _on_face(door, 0.0, 0.0)).dot(door.target.get_parent().global_basis.z.normalized())
	_ok(unlatched_at < 0.0 and unlatched_at > -0.0035,
		"poke/a fingertip pushed into the shut door unlatches it a couple of millimetres in",
		"unlatched at %.1f mm" % (unlatched_at * 1000.0))
	_ok(deepest < -0.5, "poke/the door gives under the finger before the catch lets go", "%.2f deg" % deepest)
	# Drawn back out and away: it falls open.
	await _walk([_on_face(door, 0.0, 0.01), _on_face(door, 0.0, 0.05), Vector3(0, 4, 0)])
	await _settle(door)
	_ok(not door.is_latched_closed() and is_equal_approx(door.get_rotation_deg(), TvKeyDoor.OPEN_DEG),
		"poke/the fingertip drawn away, it falls open", "%.1f deg" % door.get_rotation_deg())
	_eq(_keys_live(tv), DOOR_KEYS, "poke/open, the five keys are live")
	# Pushed up part-way by its outer face from below, then the finger taken away: it falls open again.
	var arc := [_on_face(door, TvKeyDoor.OPEN_DEG, 0.03, 0.6), _on_face(door, TvKeyDoor.OPEN_DEG, 0.008, 0.6)]
	for d in range(100, 39, -4):
		arc.append(_on_face(door, d, 0.001, 0.6))
	await _walk(arc)
	var part := door.get_rotation_deg()
	_ok(part < 50.0 and not door.is_latched_closed(), "poke/a fingertip pushes the open door up", "%.1f deg" % part)
	await _walk([_on_face(door, part, 0.05, 0.6), Vector3(0, 4, 0)])
	await _settle(door)
	_ok(not door.is_latched_closed() and is_equal_approx(door.get_rotation_deg(), TvKeyDoor.OPEN_DEG),
		"poke/left part-way, it falls open again", "%.1f deg" % door.get_rotation_deg())
	# Pushed all the way up: home, it latches.
	arc = [_on_face(door, TvKeyDoor.OPEN_DEG, 0.03, 0.6), _on_face(door, TvKeyDoor.OPEN_DEG, 0.008, 0.6)]
	for d in range(100, -9, -4):
		arc.append(_on_face(door, d, 0.001, 0.6))
	await _walk(arc)
	_ok(door.is_latched_closed(), "poke/pushed all the way up, it latches", "%.1f deg" % door.get_rotation_deg())
	await _walk([_on_face(door, 0.0, 0.05, 0.6), Vector3(0, 4, 0)])
	await _settle(door)
	_ok(door.is_latched_closed() and is_zero_approx(door.get_rotation_deg()),
		"poke/the finger gone, it stays latched shut", "%.1f deg" % door.get_rotation_deg())
	_eq(_keys_live(tv), [], "poke/latched, the keys are dead")


# ── keys/ ─────────────────────────────────────────────────────────────────────

func _keys(tv: Node3D) -> void:
	var door := _door(tv)
	var shell := tv.find_child("RetroXRCrt", true, false)
	_eq(_keys_live(tv), [], "keys/shut: dead")
	door.set_state_remote(30.0, false, false)
	shell.call("_update_door_keys")
	_eq(_keys_live(tv), [], "keys/unlatched at 30 deg: still dead (no finger fits behind it)")
	await _settle(door)
	_eq(_keys_live(tv), DOOR_KEYS, "keys/fallen open: live")
	var crt := tv.find_child("CRTButton", true, false) as VRButton
	shell.call("set_door_open", false)
	await _ticks(2)
	_ok(crt.collision_layer == 0, "keys/shut again: the CRT key is out of the ray's reach")
	# The desktop ray aimed straight at the CRT key behind the shut door takes the DOOR (a press there unlatches it).
	var at := (crt.get_node("CollisionShape3D") as CollisionShape3D).global_position
	var front := tv.global_basis.z.normalized()
	var grabber := Node3D.new()
	add_child(grabber)
	var t := InteractionResolver.resolve_desktop(tv.get_world_3d().direct_space_state, at + front * 0.6, at - front * 0.05,
		grabber)
	_ok(t != null and t.action_node == door, "keys/shut: the ray aimed at a key behind the door takes the door",
		"it took %s" % (t.action_node.name if t != null and t.action_node != null else "-"))
	grabber.queue_free()


# ── save/ ─────────────────────────────────────────────────────────────────────

func _record(tv: Node3D) -> Dictionary:
	for r: Dictionary in ScenePersistence.new()._serialize_articulated_controls(tv):
		if str(r.get("path", "")).ends_with("KeyDoorHinge"):
			return r
	return {}


func _save(tv: Node3D) -> void:
	var door := _door(tv)
	var shut := _record(tv)
	_ok(not shut.is_empty() and bool(shut.get("latched", false)) and is_zero_approx(float(shut.get("value", -1))),
		"save/a shut door is saved latched at 0", str(shut))
	_press(door, XRToolsPointerEvent.Type.PRESSED)
	_press(door, XRToolsPointerEvent.Type.RELEASED)
	await _settle(door)
	var open := _record(tv)
	_ok(not open.is_empty() and not bool(open.get("latched", true))
		and is_equal_approx(float(open.get("value", -1)), TvKeyDoor.OPEN_DEG), "save/an open door is saved unlatched, open",
		str(open))
	var tv2 := await _make_set()
	ScenePersistence.new()._restore_articulated_controls(tv2, [open])
	await _ticks(3)
	var door2 := _door(tv2)
	_ok(not door2.is_latched_closed() and is_equal_approx(door2.get_rotation_deg(), TvKeyDoor.OPEN_DEG),
		"save/restored open", "%.1f deg, latched %s" % [door2.get_rotation_deg(), door2.is_latched_closed()])
	_eq(_keys_live(tv2), DOOR_KEYS, "save/restored open, its keys are live")
	ScenePersistence.new()._restore_articulated_controls(tv2, [shut])
	await _ticks(10)
	_ok(door2.is_latched_closed() and is_zero_approx(door2.get_rotation_deg()), "save/restored shut, it stays latched")
	_eq(_keys_live(tv2), [], "save/restored shut, its keys are dead")
	tv2.queue_free()
