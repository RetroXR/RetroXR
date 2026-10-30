## The RETRO XR appliances (VCR, DVD player, surround amp, record player, the RETRO XR television): what the desktop
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
	"tv": "res://Scenes/Objects/tv.tscn",
}

var _grabber: Node3D
var _only := ""


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
	for item: String in ITEMS:
		if not _only.is_empty() and not item.begins_with(_only):
			continue
		await _item(item)
	_finish()


func _item(item: String) -> void:
	var root := (load(ITEMS[item]) as PackedScene).instantiate() as Node3D
	if item == "tv":
		root.set("tv_model", "retroxr_crt")
	add_child(root)
	root.global_position = Vector3(0, 1, 0)
	await _settle()
	var model := root.find_child("Model", true, false) as ApplianceModel
	_ok(model != null and not model.levels.is_empty(), "%s: wears its model" % item)
	if model == null:
		root.queue_free()
		return
	_boxes(item, root, model)
	match item:
		"tv":
			var shell := root.find_child("RetroXRCrt", true, false)
			_reach(item + "/door shut", root, ["AudioModeButton", "CRTButton", "AudioOutButton", "AspectButton"])
			shell.call("set_door_open", true)
			await _settle()
			_reach(item + "/door open", root, ["KeyDoorButton"])
		"turntable":
			var lever := root.get_node("CoverPivot/CoverLever") as VRLever
			lever.set_value(1.0)
			await _settle()
			_reach(item + "/cover open", root, [])
			lever.set_value(0.0)
			await _settle()
			# Shut, the cover is over the deck plate (as drawn): the 33/45 keys are taken from the front, the arm not at all.
			_reach(item + "/cover shut", root, ["TonearmLever"], {"Speed33Button": Vector3.BACK, "Speed45Button": Vector3.BACK})
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
