## The RETRO XR appliances (VCR, DVD player, surround amp, record player, cassette deck, CD player, the RETRO XR
## television): what the desktop
## ray meets is what the model draws. No box is bigger than the model it stands for, every key's box IS its key, and
## the ray aimed at a control along the way it faces takes THAT control, in every state that shows it (the set's key
## door shut and open, the deck's dust cover open and shut).
##
##   godot --headless --path RetroXR res://Tests/appliance_pointer_tests.tscn
##   godot --headless --path RetroXR res://Tests/appliance_pointer_tests.tscn -- --only=tv
##
## Body and pointer boxes were padded 5-20 mm past the models and every key 1.5 mm a side; the padded shell stood in
## front of the television's keys and the amplifier's SURROUND MODE key, deeper than InteractionResolver lets a
## control win from inside one (ENCLOSURE_DEPTH), so the desktop ray could not press them at all.
## Tools/av/appliance_ray_probe prints the same measurements for every direction.
extends "res://Tests/test_suite.gd"

## Close enough to call two boxes the same: a tenth of a millimeter.
const TOLERANCE := 0.0001
## The ray starts this far out from the control (a desktop player at arm's length is farther; nothing stands between).
const AIM_FROM := 0.6

const ITEMS := {
	"vcr": "res://Scenes/Objects/appliances/vcr_player.tscn",
	"dvd": "res://Scenes/Objects/appliances/dvd_player.tscn",
	"amp": "res://Scenes/Objects/appliances/surround_amp.tscn",
	"turntable": "res://Scenes/Objects/appliances/record_player.tscn",
	"cassette": "res://Scenes/Objects/appliances/cassette_player.tscn",
	"cd": "res://Scenes/Objects/appliances/cd_player.tscn",
	"tv": "res://Scenes/Objects/tv.tscn",
}

var _grabber: Node3D
var _only := ""
var _finger: XRPositionalTracker
const FINGER := &"appliance_test_finger"


func _ready() -> void:
	suite_tag = "applray"
	quiet_passes = true
	get_tree().create_timer(150.0).timeout.connect(func() -> void:
		print("[applray] TIMEOUT")
		get_tree().quit(1))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.split("=")[1]
	_grabber = Node3D.new()
	add_child(_grabber)
	# Made before any appliance: a key gathers its controllers when it enters the tree.
	_finger = _tracked_finger()
	for item: String in ITEMS:
		if not _only.is_empty() and not item.begins_with(_only):
			continue
		await _item(item)
	XRServer.remove_tracker(_finger)
	_finish()


func _item(item: String) -> void:
	var root := (load(ITEMS[item]) as PackedScene).instantiate() as Node3D
	if item == "tv":
		root.set("tv_model", "retroxr_crt")
	if root is RigidBody3D:
		(root as RigidBody3D).freeze = true      # held still in the air: the poke takes frames, and it would fall
	add_child(root)
	root.global_position = Vector3(0, 1, 0)
	await _settle()
	var model := root.find_child("Model", true, false) as ApplianceModel
	_ok(model != null and not model.levels.is_empty(), "%s: wears its model" % item)
	if model == null:
		root.queue_free()
		return
	_boxes(item, root, model)
	_knob_boxes(item, root)
	await _poke(item, root, [])
	match item:
		"tv":
			var shell := root.find_child("RetroXRCrt", true, false)
			_reach(item + "/door shut", root, ["AudioModeButton", "CRTButton", "AudioOutButton", "AspectButton"])
			shell.call("set_door_open", true)
			await _settle()
			_reach(item + "/door open", root, ["KeyDoorButton"])
			await _poke(item + "/door open", root, ["MuteButton", "VolumeDownButton", "VolumeUpButton",
				"ChannelDownButton", "ChannelUpButton", "TVToggleButton", "SourceButton"])
		"turntable":
			var lever := root.get_node("CoverPivot/CoverLever") as VRLever
			lever.set_value(1.0)
			await _settle()
			_reach(item + "/cover open", root, [])
			lever.set_value(0.0)
			await _settle()
			# Shut, the cover is over the deck plate (as drawn): the 33/45 keys are taken from the front, the arm not at all.
			_reach(item + "/cover shut", root, ["TonearmLever"], {"Speed33Button": Vector3.BACK, "Speed45Button": Vector3.BACK})
		"dvd":
			_reach(item, root, [])
			_dvd_ring(root)
		_:
			_reach(item, root, [])
	root.queue_free()
	await get_tree().process_frame


func _settle() -> void:
	for i in 12:
		await get_tree().physics_frame


func _is_control(n: Node) -> bool:
	return n is VRButton or n is VRKnob or n is VRHinge or n is VRLever or n is VRSlider


## A collision object's shapes as world boxes.
func _shape_boxes(obj: Node) -> Array[AABB]:
	var out: Array[AABB] = []
	for c in obj.get_children():
		var cs := c as CollisionShape3D
		if cs and cs.shape and not cs.disabled:
			out.append(cs.global_transform * cs.shape.get_debug_mesh().get_aabb())
	return out


## The DVD player's navigation ring (the RETRO XR remote's: generic/dvd-player/params.py RING_*): four arcs round OK,
## whose boxes would overlap. Each is its own triangles, a ray into a gap between keys takes none of them, and a
## fingertip presses only the key it is over (ApplianceModel.footprint_gate).
const RING_MID := 0.0098       # the arcs' middle radius: (7.1 + 12.5) / 2 mm
const RING_OK_GAP := 0.0065    # between OK (5.9) and the arcs (7.1)
const RING := ["UpButton", "DownButton", "LeftButton", "RightButton", "SelectButton"]


func _dvd_ring(root: Node3D) -> void:
	var ok_cap := root.get_node("SelectButton/ButtonMesh") as MeshInstance3D
	var c := ok_cap.global_position
	var x := ok_cap.global_basis.x.normalized()
	var y := ok_cap.global_basis.y.normalized()
	var n := ok_cap.global_basis.z.normalized()        # out of the front
	for k: String in RING:
		var b := root.get_node(k) as VRButton
		var shape := (b.get_node("CollisionShape3D") as CollisionShape3D).shape
		var cap := b.get_node("ButtonMesh") as MeshInstance3D
		_ok(shape is ConcavePolygonShape3D and (shape as ConcavePolygonShape3D).get_faces().size() == cap.mesh.get_faces().size(),
			"dvd/ring: %s's shape is its own triangles" % k, str(shape))
		_ok(b.press_gate.is_valid(), "dvd/ring: %s is pressed by a fingertip only over its face" % k)
	var space := root.get_world_3d().direct_space_state
	var gaps := {"the slot between UP and RIGHT": c + (x + y).normalized() * RING_MID,
		"the slot between DOWN and LEFT": c - (x + y).normalized() * RING_MID,
		"the ring between OK and RIGHT": c + x * RING_OK_GAP, "the ring between OK and UP": c + y * RING_OK_GAP}
	for label: String in gaps:
		var at: Vector3 = gaps[label]
		var t := InteractionResolver.resolve_desktop(space, at + n * AIM_FROM, at - n * 0.01, _grabber)
		var took: String = str(t.action_node.name) if t != null and t.action_node != null else "-"
		_ok(not RING.has(took), "dvd/ring: a ray into %s takes no key" % label, "it took %s" % took)
	var over := {"SelectButton": c, "RightButton": c + x * RING_MID, "UpButton": c + y * RING_MID,
		"LeftButton": c - x * RING_MID, "DownButton": c - y * RING_MID}
	for key: String in over:
		var tip: Vector3 = (over[key] as Vector3) + n * 0.001
		var yes: Array[String] = []
		for k: String in RING:
			if bool((root.get_node(k) as VRButton).press_gate.call(tip)):
				yes.append(k)
		_ok(yes.size() == 1 and yes[0] == key, "dvd/ring: a fingertip over %s presses it and no other" % key, "pressed %s" % str(yes))
	for label: String in gaps:
		var tip: Vector3 = (gaps[label] as Vector3) + n * 0.001
		var any := false
		for k: String in RING:
			any = any or bool((root.get_node(k) as VRButton).press_gate.call(tip))
		_ok(not any, "dvd/ring: a fingertip in %s presses nothing" % label)
	_ok(not bool((root.get_node("SelectButton") as VRButton).press_gate.call(c + n * 0.01)),
		"dvd/ring: a fingertip 10 mm off OK's face presses nothing")


## The body's and the pointer's boxes are inside what the model draws; every key's box is the key it shows.
func _boxes(item: String, root: Node3D, model: ApplianceModel) -> void:
	var drawn: AABB = root.global_transform * model.bounds(root)
	for obj: Node in [root, root.get_node_or_null("PointerArea")]:
		if obj == null:
			continue
		var boxes := _shape_boxes(obj)
		var worst := 0.0
		for b in boxes:
			for i in 3:
				worst = maxf(worst, maxf(b.end[i] - drawn.end[i], drawn.position[i] - b.position[i]))
		_ok(not boxes.is_empty() and worst <= TOLERANCE, "%s/box: %s is no bigger than the model" % [item, obj.name],
			"%.1f mm past it" % (worst * 1000.0))
	for n in root.find_children("*", "VRButton", true, false):
		var b := n as VRButton
		var cap := b.get_node_or_null("ButtonMesh") as MeshInstance3D
		if not b.is_visible_in_tree() or cap == null or cap.mesh == null:
			continue
		var shown := cap.global_transform * cap.get_aabb()
		var boxes := _shape_boxes(b)
		_ok(boxes.size() == 1 and (boxes[0].position - shown.position).length() < TOLERANCE
			and (boxes[0].size - shown.size).length() < TOLERANCE,
			"%s/key: %s's box is its key" % [item, b.name],
			"box %s, key %s" % [boxes[0].size if not boxes.is_empty() else Vector3.ZERO, shown.size])


## Every knob's box is the knob it turns (the model's cap hung under its KnobPivot, the close level's), within half a
## millimeter. Measured in the pivot's frame: the pivot turns only about the knob's own Z, and a round cap's box is the
## same at any turn, where its bounds in the knob's frame grow with the turn.
func _knob_boxes(item: String, root: Node3D) -> void:
	for n in root.find_children("*", "VRKnob", true, false):
		var k := n as VRKnob
		var pivot := k.get_node_or_null("KnobPivot") as Node3D
		var cs := k.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if pivot == null or pivot.get_child_count() == 0 or cs == null or not k.is_visible_in_tree():
			continue
		var drawn := ApplianceModel.node_bounds(pivot.get_child(0), pivot)
		var box := cs.transform * cs.shape.get_debug_mesh().get_aabb()
		var off := maxf((box.position - drawn.position).abs()[(box.position - drawn.position).abs().max_axis_index()],
			(box.end - drawn.end).abs()[(box.end - drawn.end).abs().max_axis_index()])
		_ok(off <= 0.0005 and pivot.position.is_zero_approx(), "%s/knob: %s's box is its knob" % [item, k.name],
			"%.2f mm off" % (off * 1000.0))


## Aim at every live control along the way it faces (a key: against its press; anything else: whichever way it is
## taken from first of front, top, sides) and check the desktop ray takes it. `skip` names controls this state hides;
## `from` overrides the direction for one.
func _reach(label: String, root: Node3D, skip: Array, from: Dictionary = {}) -> void:
	var space := root.get_world_3d().direct_space_state
	for n in root.find_children("*", "Node3D", true, false):
		if not _is_control(n) or skip.has(String(n.name)):
			continue
		var c := n as Node3D
		# Out of play (a key behind the shut door, the cover's arm): nothing for the ray to take.
		if not c.is_visible_in_tree() or (c is CollisionObject3D and (c as CollisionObject3D).collision_layer == 0):
			continue
		var boxes := _shape_boxes(c)
		if boxes.is_empty():
			continue
		var box := boxes[0]
		for b in boxes:
			box = box.merge(b)
		var mid := box.get_center()
		var dirs: Array[Vector3] = []
		if from.has(String(c.name)):
			dirs = [root.global_basis * (from[String(c.name)] as Vector3)]
		elif c is VRButton:
			dirs = [-(c.global_basis * (c as VRButton).depress_axis).normalized()]
		else:
			dirs = [root.global_basis * Vector3.BACK, root.global_basis * Vector3.UP,
				root.global_basis * Vector3.RIGHT, root.global_basis * Vector3.LEFT]
		var took := false
		var got := "-"
		for d in dirs:
			var t := InteractionResolver.resolve_desktop(space, mid + d * AIM_FROM, mid - d * 0.05, _grabber)
			if t != null and (t.action_node == c or t.highlight_node == c):
				took = true
				break
			if t != null and t.action_node != null:
				got = String(t.action_node.name)
		_ok(took, "%s/reach: the desktop ray takes %s" % [label, c.name], "it took %s" % got)


# ── poke/ ─────────────────────────────────────────────────────────────────────

## A tracked hand: an XRController3D on a tracker of our own with a PokeTip at its origin (VRButton's own touch path,
## as tv_remote_tests drives it).
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


## Push the fingertip into every live key (less `skip`) along its press and out again: it must sink by its travel,
## fire once with no other key firing, and come back up. A press box with no travel (the set's key door) is a door,
## not a key.
func _poke(label: String, root: Node3D, skip: Array) -> void:
	var keys: Array[VRButton] = []
	for n in root.find_children("*", "VRButton", true, false):
		var b := n as VRButton
		var cap := b.get_node_or_null("ButtonMesh") as MeshInstance3D
		if skip.has(String(b.name)) or not b.is_visible_in_tree() or b.collision_layer == 0 or b.depress_depth <= 0.0 				or cap == null or cap.mesh == null:
			continue
		keys.append(b)
	var fired := {}
	for b in keys:
		fired[b] = 0
		b.button_pressed.connect(func() -> void: fired[b] += 1)
	for b in keys:
		var cap := b.get_node("ButtonMesh") as MeshInstance3D
		var rest := cap.global_position
		var axis := (b.global_basis * b.depress_axis).normalized()
		var out := -axis
		var travel := b.depress_depth * (b.global_basis * b.depress_axis).length()
		for k in fired:
			fired[k] = 0
		for d: float in [0.03, 0.012, 0.004, 0.001, -travel, -travel, -travel]:
			_place(rest + out * d)
			await _ticks(2)
		var sunk := (cap.global_position - rest).dot(axis)
		var others: Array[String] = []
		for k in fired:
			if k != b and int(fired[k]) > 0:
				others.append(String((k as Node).name))
		var once := int(fired[b])
		for d: float in [0.002, 0.012, 0.03]:
			_place(rest + out * d)
			await _ticks(2)
		# A press is held through VRButton.CONTACT_GRACE (50 ms) after the tip leaves: a hand takes longer than that to
		# back off, a headless frame much less.
		await _wait_until(func() -> bool: return cap.global_position.distance_to(rest) < 0.00001, 0.5)
		var back := cap.global_position.distance_to(rest)
		_ok(absf(sunk - travel) < 0.0002 and once == 1 and others.is_empty() and back < 0.00001,
			"%s/poke: %s sinks under the fingertip, fires once, alone, and comes back up" % [label, b.name],
			"sank %.2f of %.2f mm, fired %d, others fired %s, %.3f mm off rest after" % [sunk * 1000.0, travel * 1000.0,
				once, others, back * 1000.0])
	_place(Vector3(0, 4, 0))
	await _ticks(2)
