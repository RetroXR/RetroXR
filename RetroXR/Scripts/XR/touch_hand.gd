class_name TouchHand
extends Node3D

## A hand posed from the controller's own sensors, for runtimes that give no hand
## joints (Meta's PC runtime over Link among them): the index finger from the
## trigger's touch, proximity and pull, the other three from the grip, the thumb
## from whether it rests on the stick, a face button or the thumbrest. Each group
## blends on its own between the xr-tools open and closed poses. Shown by
## CapsenseHand, which also takes its index tip as the poke point.

const SCENES: Array[PackedScene] = [
	preload("res://addons/godot-xr-tools/hands/scenes/lowpoly/left_hand_low.tscn"),
	preload("res://addons/godot-xr-tools/hands/scenes/lowpoly/right_hand_low.tscn"),
]
const MATERIAL := preload("res://Scenes/Objects/hand_poses/held_hand_material.tres")

## How far a finger closes, 0 the open pose to 1 the closed one.
const INDEX_NEAR := 0.2
const INDEX_RESTING := 0.4
const THUMB_NEAR := 0.45
const THUMB_DOWN := 0.85
## The sensors are on/off; this many full ranges a second takes the snap out.
const SPEED := 14.0

const THUMB_TOUCHES: Array[StringName] = [
	&"primary_touch", &"secondary_touch", &"ax_touch", &"by_touch", &"thumbrest_touch",
]

## 0 left, 1 right.
var hand := 0
var controller: XRController3D

var _xr_hand: Node3D
var _tree: AnimationTree
var _skeleton: Skeleton3D
var _tip_bone := -1
var _index := 0.0
var _grip := 0.0
var _thumb := 0.0


func _ready() -> void:
	visible = false
	_xr_hand = SCENES[hand].instantiate() as Node3D
	_xr_hand.set("hand_blend_tree", _split_thumb(_xr_hand.get("hand_blend_tree")))
	_xr_hand.set("hand_material_override", MATERIAL)
	add_child(_xr_hand)
	_tree = _xr_hand.get_node("AnimationTree") as AnimationTree
	# xr-tools names the closed pose into ClosedHand1/2 only.
	var root := _tree.tree_root as AnimationNodeBlendTree
	(root.get_node("ClosedThumb") as AnimationNodeAnimation).animation = \
		(root.get_node("ClosedHand1") as AnimationNodeAnimation).animation
	_skeleton = _xr_hand.find_child("Skeleton3D", true, false) as Skeleton3D
	if _skeleton != null:
		_tip_bone = _skeleton.find_bone("Index_Tip_" + ("L" if hand == 0 else "R"))


func _physics_process(delta: float) -> void:
	if controller == null or _tree == null:
		return
	var step := SPEED * delta
	var pull := controller.get_float(&"trigger")
	var index := 0.0
	if controller.is_button_pressed(&"trigger_touch"):
		index = lerpf(INDEX_RESTING, 1.0, pull)
	elif controller.is_button_pressed(&"trigger_proximity"):
		index = INDEX_NEAR
	_index = move_toward(_index, maxf(index, pull), step)
	_grip = move_toward(_grip, controller.get_float(&"grip"), step)

	var thumb := 0.0
	for action in THUMB_TOUCHES:
		if controller.is_button_pressed(action):
			thumb = THUMB_DOWN
			break
	if thumb == 0.0 and controller.is_button_pressed(&"thumb_proximity"):
		thumb = THUMB_NEAR
	_thumb = move_toward(_thumb, thumb, step)

	_xr_hand.call("force_grip_trigger", _grip, _index)
	_tree.set("parameters/Thumb/blend_amount", _thumb)


## World position of the drawn index fingertip, or null while hidden.
func index_tip() -> Variant:
	if not is_visible_in_tree() or _skeleton == null or _tip_bone < 0:
		return null
	return _skeleton.global_transform * _skeleton.get_bone_global_pose(_tip_bone).origin


## The xr-tools tree with the thumb taken out of Grip into a Thumb blend of its
## own: Trigger (index) -> Grip (middle, ring, little) -> Thumb -> output.
static func _split_thumb(base: AnimationNodeBlendTree) -> AnimationNodeBlendTree:
	var base_grip := base.get_node("Grip") as AnimationNodeBlend2
	var base_index := base.get_node("Trigger") as AnimationNodeBlend2
	var open_name := (base.get_node("OpenHand") as AnimationNodeAnimation).animation
	var closed_name := (base.get_node("ClosedHand1") as AnimationNodeAnimation).animation

	var index := _filtered(base_index.get("filters"), func(_p: String) -> bool: return true)
	var fingers := _filtered(base_grip.get("filters"), func(p: String) -> bool: return not p.contains(":Thumb_"))
	var thumb := _filtered(base_grip.get("filters"), func(p: String) -> bool: return p.contains(":Thumb_"))

	var tree := AnimationNodeBlendTree.new()
	tree.add_node(&"OpenHand", _anim(open_name))
	tree.add_node(&"ClosedHand1", _anim(closed_name))
	tree.add_node(&"ClosedHand2", _anim(closed_name))
	tree.add_node(&"ClosedThumb", _anim(closed_name))
	tree.add_node(&"Trigger", index)
	tree.add_node(&"Grip", fingers)
	tree.add_node(&"Thumb", thumb)
	tree.connect_node(&"Trigger", 0, &"OpenHand")
	tree.connect_node(&"Trigger", 1, &"ClosedHand1")
	tree.connect_node(&"Grip", 0, &"Trigger")
	tree.connect_node(&"Grip", 1, &"ClosedHand2")
	tree.connect_node(&"Thumb", 0, &"Grip")
	tree.connect_node(&"Thumb", 1, &"ClosedThumb")
	tree.connect_node(&"output", 0, &"Thumb")
	return tree


static func _anim(anim_name: StringName) -> AnimationNodeAnimation:
	var a := AnimationNodeAnimation.new()
	a.animation = anim_name
	return a


static func _filtered(paths: Array, keep: Callable) -> AnimationNodeBlend2:
	var b := AnimationNodeBlend2.new()
	b.filter_enabled = true
	for p in paths:
		if keep.call(String(p)):
			b.set_filter_path(NodePath(p), true)
	return b
