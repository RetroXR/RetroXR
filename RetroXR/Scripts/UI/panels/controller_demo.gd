## ControllerDemo — the welcome page's "which button": the player's own two
## controllers, the models their headset hands over through OpenXR, standing in
## front of the page and pressing each button the page talks about, in turn.
##
## The models are COPIES of what the hands already show (ControllerArt), taken
## from under the controllers and laid in the AIM frame they hang in there, so the
## demo is whatever the player is holding — a Quest 2's, a 3's, a Pro's — and asks
## the runtime for nothing. Meta's model brings a rig, and the presses go through
## the same ControllerRig the hand's own buttons do. A hand with no model yet (the
## runtime retries for half a minute after a controller wakes) shows the stand-in
## (ControllerStandIn) and swaps when one arrives; a model with no rig (the core
## XR_EXT_render_model tier) stands still and the marker alone says which button.
##
## Nothing here is tracked, pointable or saved. It lives and dies with the page.
class_name ControllerDemo
extends Node3D

## A step began: its number, how many there are, and what it says.
signal step_changed(index: int, count: int, caption: String)

## What the demo presses, in order. `press` names bones in Meta's rig (the names
## ControllerModel.ACTION_BONES drives); several are pressed one after another
## and held together. `view` is which way the controllers turn for it: "top" as
## you see your own hand, from behind and above, for the stick and the buttons on
## the face; "side" in profile for the trigger and the grip, which are on its
## front edge and hidden from above.
const STEPS: Array[Dictionary] = [
	{"hand": "left", "press": ["b_thumbstick"], "view": "top",
		"caption": "Click the LEFT stick: the menu opens. Pointing at something, its options."},
	{"hand": "right", "press": ["b_trigger_front"], "view": "side",
		"caption": "Point the laser and pull the TRIGGER: press a menu button."},
	{"hand": "right", "press": ["b_trigger_grip"], "view": "side",
		"caption": "Squeeze the GRIP: grab what your hand or the laser is on."},
	{"hand": "right", "press": ["b_trigger_grip", "b_trigger_front", "b_thumbstick"], "view": "side",
		"caption": "GRIP + TRIGGER + stick click: put down what stays in your hand."},
	{"hand": "right", "press": ["b_thumbstick"], "view": "top",
		"caption": "Point at a TV and click the RIGHT stick: its picture comes to you."},
]
const STEP_SECONDS := 3.6

## Metres between the two controllers' centres, and how much smaller the one not
## in use stands.
const SPACING := 0.16
const IDLE_SCALE := 0.8
## The two views, in degrees: "top" tips the controller's top toward the player
## and turns each in toward the other a little, as a pair of hands holds them;
## "side" turns its outer side to the player. A slow sway either side on top.
const TOP_TILT_DEG := 35.0
const TOP_TURN_DEG := 20.0
const SIDE_TILT_DEG := 10.0
const SWAY_DEG := 10.0
const SWAY_SECONDS := 7.0
## How quickly a controller turns to a new step's view (1/s, eased).
const TURN_RATE := 5.0
## A model this big along its longest side is shown as it is; anything else is
## scaled to it, so a stand-in and a runtime model read the same size. Under the
## page's stage height (0.2 m) whichever way a view turns it.
const SHOW_SIZE := 0.12

const MARKER_COLOR := Color(0.35, 0.95, 1.0)
const MARKER_RADIUS := 0.007

## Set before the first frame to start on a step and stop the clock; for probes
## and tests. -1 runs the loop.
var hold_step := -1

var _arts := {}              # "left"/"right" -> ControllerArt or null
var _slots := {}             # hand -> Node3D the model is laid under
var _models := {}            # hand -> {root, skeleton, driven, real}
var _markers: Array[MeshInstance3D] = []
var _t := 0.0
var _step := -1


## Show the hands' models from `left_art` / `right_art` (either may be null).
func setup(left_art: ControllerArt, right_art: ControllerArt) -> void:
	_arts = {"left": left_art, "right": right_art}
	_add_light()
	for hand: String in ["left", "right"]:
		var slot := Node3D.new()
		slot.name = "Slot_%s" % hand
		slot.position = Vector3((-0.5 if hand == "left" else 0.5) * SPACING, 0, 0)
		add_child(slot)
		_slots[hand] = slot
		_load_model(hand)
		var art: ControllerArt = _arts[hand]
		if is_instance_valid(art):
			art.art_changed.connect(_on_art_changed.bind(hand))
	_set_step(maxi(hold_step, 0))


## Which hand shows the runtime's model ("real") or the stand-in, for the log
## and the probes.
func source_of(hand: String) -> String:
	var m: Dictionary = _models.get(hand, {})
	return "none" if m.is_empty() else ("runtime" if m["real"] else "stand-in")


func _exit_tree() -> void:
	for hand: String in _arts:
		var art: ControllerArt = _arts[hand]
		if is_instance_valid(art) and art.art_changed.is_connected(_on_art_changed):
			art.art_changed.disconnect(_on_art_changed)


func _on_art_changed(hand: String) -> void:
	# The runtime model arrived (or was replaced) after the page went up.
	var m: Dictionary = _models.get(hand, {})
	if m.is_empty() or not m["real"]:
		print("[Welcome] demo: the %s controller's model arrived; showing it" % hand)
		_load_model(hand)
		_apply_step()


## Lay `hand`'s model under its slot: a copy of the runtime's, else the stand-in.
func _load_model(hand: String) -> void:
	var old: Dictionary = _models.get(hand, {})
	if not old.is_empty() and is_instance_valid(old["root"]):
		(old["root"] as Node).queue_free()
	var art: ControllerArt = _arts.get(hand)
	var root := copy_art(art)
	var real := root != null
	if root == null:
		root = ControllerStandIn.build(hand == "left")
	var holder := Node3D.new()
	holder.name = "Model"
	holder.add_child(root)
	(_slots[hand] as Node3D).add_child(holder)
	holder.basis = _view_basis(hand, _view_of_step())
	_fit(holder, root)
	var model := {"root": holder, "skeleton": null, "driven": {}, "real": real}
	var skel := _first(root, "Skeleton3D") as Skeleton3D
	var anim := _first(root, "AnimationPlayer") as AnimationPlayer
	if skel != null and anim != null and not anim.get_animation_list().is_empty():
		# The clip describes the motion; it must not play it.
		anim.stop()
		model["skeleton"] = skel
		model["driven"] = ControllerRig.read(skel, anim.get_animation(anim.get_animation_list()[0]))
		for bone_name: String in model["driven"]:
			ControllerRig.actuate(skel, model["driven"], bone_name, 0.0)
	_models[hand] = model
	print("[Welcome] demo: %s controller is the %s (%d bones it can press)" % [hand,
		"runtime's model" if real else "stand-in", (model["driven"] as Dictionary).size()])


## A copy of what a ControllerArt shows, laid in its controller's aim frame, or
## null when it shows nothing yet. Meta's model is copied whole (skeleton, rig and
## all); the core tier's runtime-animated nodes cannot be, so their meshes are.
static func copy_art(art: ControllerArt) -> Node3D:
	if not is_instance_valid(art) or not art.has_art() or not art.is_inside_tree():
		return null
	var to_aim := art.global_transform.affine_inverse()
	var out := Node3D.new()
	out.name = "RuntimeModel"
	if art.source == ControllerArt.Source.VENDOR_FB:
		var fb := art.get_node_or_null("GripAnchor/FbRenderModel")
		if fb == null:
			return null
		for child: Node in fb.get_children():
			var n3 := child as Node3D
			if n3 == null:
				continue
			var copy := n3.duplicate() as Node3D
			copy.transform = to_aim * n3.global_transform
			out.add_child(copy)
	else:
		for mesh: Node in art.find_children("*", "MeshInstance3D", true, false):
			var mi := mesh as MeshInstance3D
			var copy := MeshInstance3D.new()
			copy.mesh = mi.mesh
			copy.skin = null
			copy.transform = to_aim * mi.global_transform
			out.add_child(copy)
	if out.get_child_count() == 0:
		out.free()
		return null
	# The hand's surfaces carry ControllerArt's fade materials, which a grab turns
	# see-through; the copy goes back to the model's own.
	for mesh: Node in out.find_children("*", "MeshInstance3D", true, false):
		var mi := mesh as MeshInstance3D
		for i in mi.get_surface_override_material_count():
			mi.set_surface_override_material(i, null)
	return out


## How `hand`'s controller is turned for `view`. The model is in its aim frame:
## +Y up out of the face, -Z the laser's way, the handle running down and back.
func _view_basis(hand: String, view: String) -> Basis:
	var left := hand == "left"
	if view == "side":
		# The outer side to the player: +X for the right hand, -X for the left.
		return Basis(Vector3.RIGHT, deg_to_rad(SIDE_TILT_DEG)) \
			* Basis(Vector3.UP, deg_to_rad(90.0 if left else -90.0))
	return Basis(Vector3.RIGHT, deg_to_rad(TOP_TILT_DEG)) \
		* Basis(Vector3.UP, deg_to_rad(-TOP_TURN_DEG if left else TOP_TURN_DEG))


func _view_of_step() -> String:
	return str(STEPS[maxi(_step, 0)].get("view", "top"))


## A light of the demo's own, in front of and above the controllers: the room can
## be anything from daylight to a dark arcade, and a dark model on a dark stage
## says nothing about which button.
func _add_light() -> void:
	var light := OmniLight3D.new()
	light.name = "DemoLight"
	light.position = Vector3(0.0, 0.18, 0.3)
	light.omni_range = 0.8
	light.light_energy = 1.6
	light.shadow_enabled = false
	add_child(light)


## Scale and centre `root` inside `holder` so its longest side is SHOW_SIZE.
func _fit(holder: Node3D, root: Node3D) -> void:
	var box := _bounds(root, Transform3D.IDENTITY)
	if box.size.length() < 0.001:
		return
	var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
	var k := SHOW_SIZE / longest
	root.scale = Vector3.ONE * k
	root.position = -box.get_center() * k


func _bounds(node: Node, xf: Transform3D) -> AABB:
	var box := AABB()
	var first := true
	var here := xf * _local_xf(node)
	var vi := node as VisualInstance3D
	if vi != null:
		var b := here * vi.get_aabb()
		box = b
		first = false
	for child: Node in node.get_children():
		var sub := _bounds(child, here)
		if sub.size.length() < 0.000001:
			continue
		box = sub if first else box.merge(sub)
		first = false
	return box


## A node's place in its parent. A part riding a bone is placed by the bone's
## rest: the attachment only follows the skeleton once it has been posed, which
## is after this measures it.
func _local_xf(node: Node) -> Transform3D:
	var att := node as BoneAttachment3D
	if att != null:
		var skel := att.get_parent() as Skeleton3D
		var bone := skel.find_bone(att.bone_name) if skel != null else -1
		if bone >= 0:
			return skel.get_bone_global_rest(bone)
	return (node as Node3D).transform if node is Node3D else Transform3D.IDENTITY


func _first(root: Node, type: String) -> Node:
	if root.is_class(type):
		return root
	var found := root.find_children("*", type, true, false)
	return found[0] if not found.is_empty() else null


func _process(delta: float) -> void:
	if hold_step < 0:
		_t += delta
		var index := int(_t / STEP_SECONDS) % STEPS.size()
		if index != _step:
			_set_step(index)
	_apply_step()
	rotation.y = deg_to_rad(SWAY_DEG) * sin(TAU * Time.get_ticks_msec() / 1000.0 / SWAY_SECONDS)


func _set_step(index: int) -> void:
	_step = index
	var step: Dictionary = STEPS[index]
	step_changed.emit(index, STEPS.size(), str(step["caption"]))


## Press this step's buttons along the step's clock, and pulse a marker on each.
func _apply_step() -> void:
	if _step < 0:
		return
	var step: Dictionary = STEPS[_step]
	# Held, 2 s in: a single button is in its second press, a combination all down.
	var local := fmod(_t, STEP_SECONDS) if hold_step < 0 else 2.0
	var presses: Array = step["press"]
	var turn := 1.0 - exp(-TURN_RATE * get_process_delta_time())
	for hand: String in _models:
		var slot := _slots[hand] as Node3D
		var active: bool = hand == step["hand"]
		var want := 1.0 if active else IDLE_SCALE
		slot.scale = slot.scale.lerp(Vector3.ONE * want, turn)
		var m: Dictionary = _models[hand]
		var holder := m["root"] as Node3D
		if is_instance_valid(holder):
			holder.basis = holder.basis.slerp(_view_basis(hand, str(step.get("view", "top"))),
				turn if hold_step < 0 else 1.0)
		var skel := m["skeleton"] as Skeleton3D
		if skel == null or not is_instance_valid(skel):
			continue
		for bone_name: String in m["driven"]:
			var i := presses.find(bone_name)
			var amount := _press_amount(local, i, presses.size()) if active and i >= 0 else 0.0
			# A stick's rotation is its lean; a click only moves it.
			ControllerRig.actuate(skel, m["driven"], bone_name, amount,
				bone_name != "b_thumbstick", true)
	_place_markers(step, local)


## How far down the `i`th of `n` buttons is, `local` seconds into a step: pressed
## one after another, held together, let go together, twice for a single button.
func _press_amount(local: float, i: int, n: int) -> float:
	if n > 1:
		var start := 0.4 + 0.45 * i
		return _ramp(local, start, 2.6)
	return maxf(_ramp(local, 0.4, 1.1), _ramp(local, 1.6, 2.3))


func _ramp(t: float, on: float, off: float) -> float:
	var up := clampf((t - on) / 0.18, 0.0, 1.0)
	var down := clampf((off - t) / 0.18, 0.0, 1.0)
	return smoothstep(0.0, 1.0, minf(up, down))


## A glowing dot on each button of the step, drawn over the model so it shows
## through a stick or a trigger's own plastic.
func _place_markers(step: Dictionary, local: float) -> void:
	var presses: Array = step["press"]
	var m: Dictionary = _models.get(step["hand"], {})
	var skel: Skeleton3D = m.get("skeleton") if not m.is_empty() else null
	while _markers.size() < presses.size():
		_markers.append(_marker())
	for i in _markers.size():
		var marker := _markers[i]
		var bone := -1
		if i < presses.size() and skel != null and is_instance_valid(skel):
			bone = skel.find_bone(presses[i])
		marker.visible = bone >= 0
		if bone < 0:
			continue
		marker.global_position = skel.global_transform * skel.get_bone_global_pose(bone).origin
		var pulse := 1.0 + 0.35 * sin(local * TAU * 1.5)
		marker.scale = Vector3.ONE * pulse


func _marker() -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = MARKER_RADIUS
	mesh.height = MARKER_RADIUS * 2.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = MARKER_COLOR
	mat.no_depth_test = true
	mat.render_priority = 1
	var mi := MeshInstance3D.new()
	mi.name = "Marker"
	mi.mesh = mesh
	mi.material_override = mat
	mi.top_level = true
	add_child(mi)
	return mi
