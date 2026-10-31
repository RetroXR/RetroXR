## ControllerStandIn — a plain controller for the welcome page's demo
## (ControllerDemo) when the headset has handed over no model of its own: hand
## tracking, a runtime with no render-model extension, or a desktop probe.
##
## Built the way Meta's runtime model arrives (XR_FB_render_model), so the demo
## drives it through the same ControllerRig as the real one: a Skeleton3D with
## Meta's bone names, the parts riding on the bones, and an AnimationPlayer whose
## one clip runs every input in turn. Authored in the controller's AIM frame,
## which is where ControllerDemo lays a runtime model too: -Z the way the laser
## points, the stick standing up out of the face and leaning back a little (the
## shaft render_model_probe uses), the handle running down and back under it.
##
## Not a likeness of any controller: a grip, a head, a stick, two face buttons,
## a trigger and a grip button, enough to show which one to press.
class_name ControllerStandIn
extends RefCounted

const CLIP := "All Animations"

## The stick's shaft in the aim frame: up out of the face, leaning back a little.
const SHAFT := Vector3(0.0, 0.94, -0.34)
## The handle's axis from the head down to its end.
const HANDLE := Vector3(0.0, -0.75, 0.66)

## How far each part travels on a full press, as the rig clip moves it.
const BUTTON_TRAVEL := 0.0015
const STICK_TRAVEL := 0.0015
const GRIP_TRAVEL := 0.003
const TRIGGER_TURN := 18.0

const COLOR_BODY := Color(0.34, 0.34, 0.37)
const COLOR_FACE := Color(0.12, 0.12, 0.13)
const COLOR_PART := Color(0.7, 0.7, 0.74)


## A controller for the `left` hand or the right, as a model root holding
## "Skeleton3D" and "AnimationPlayer" the way a runtime model does.
static func build(left: bool) -> Node3D:
	var root := Node3D.new()
	root.name = "StandIn%s" % ("Left" if left else "Right")
	var skel := Skeleton3D.new()
	skel.name = "Skeleton3D"
	root.add_child(skel)

	var shaft := SHAFT.normalized()
	var root_bone := _bone(skel, "b_root", -1, Transform3D.IDENTITY)

	# Head and handle: not bones that move, so straight on the root.
	_part(skel, root_bone, _cylinder(0.032, 0.022, COLOR_BODY),
		Transform3D(_axis_basis(shaft), Vector3.ZERO))
	_part(skel, root_bone, _cylinder(0.033, 0.003, COLOR_FACE),
		Transform3D(_axis_basis(shaft), shaft * 0.0115))
	var handle_axis := HANDLE.normalized()
	_part(skel, root_bone, _cylinder(0.019, 0.105, COLOR_BODY),
		Transform3D(_axis_basis(handle_axis), handle_axis * 0.06))

	# The stick stands at the middle of the face, the two face buttons toward the
	# inside of the hand, as a pair of controllers mirror them.
	var inward := 1.0 if left else -1.0
	var on_face := shaft * 0.013
	var side := Vector3.RIGHT * inward
	# Along the face toward its back edge.
	var up_face := -shaft.cross(Vector3.RIGHT).normalized()
	var stick := _bone(skel, "b_thumbstick", root_bone,
		Transform3D(_axis_basis(shaft), on_face - side * 0.006))
	_part(skel, stick, _cylinder(0.004, 0.012, COLOR_PART), Transform3D(Basis.IDENTITY, Vector3(0, 0.006, 0)))
	_part(skel, stick, _cylinder(0.0095, 0.004, COLOR_PART), Transform3D(Basis.IDENTITY, Vector3(0, 0.013, 0)))
	var b1 := "b_button_x" if left else "b_button_a"
	var b2 := "b_button_y" if left else "b_button_b"
	var near := _bone(skel, b1, root_bone,
		Transform3D(_axis_basis(shaft), on_face + side * 0.013 + up_face * 0.006))
	_part(skel, near, _cylinder(0.0055, 0.004, COLOR_PART), Transform3D(Basis.IDENTITY, Vector3(0, 0.002, 0)))
	var far := _bone(skel, b2, root_bone,
		Transform3D(_axis_basis(shaft), on_face + side * 0.008 - up_face * 0.012))
	_part(skel, far, _cylinder(0.0055, 0.004, COLOR_PART), Transform3D(Basis.IDENTITY, Vector3(0, 0.002, 0)))

	# The trigger hangs under the front of the head, turning about the side axis;
	# the grip button is on the front of the handle where the middle finger lies.
	var trigger := _bone(skel, "b_trigger_front", root_bone,
		Transform3D(Basis.IDENTITY, Vector3(0, -0.014, -0.024)))
	_part(skel, trigger, _box(Vector3(0.016, 0.022, 0.008), COLOR_PART),
		Transform3D(Basis.IDENTITY, Vector3(0, -0.011, -0.004)))
	var grip := _bone(skel, "b_trigger_grip", root_bone,
		Transform3D(Basis.IDENTITY, handle_axis * 0.055 + Vector3(0, 0, -0.018)))
	_part(skel, grip, _box(Vector3(0.016, 0.03, 0.006), COLOR_PART), Transform3D.IDENTITY)

	var anim := AnimationPlayer.new()
	anim.name = "AnimationPlayer"
	root.add_child(anim)
	var lib := AnimationLibrary.new()
	lib.add_animation(CLIP, _clip(skel, b1, b2))
	anim.add_animation_library("", lib)
	return root


## The rig clip, Meta's shape: every input in turn, each pressing and coming back.
static func _clip(skel: Skeleton3D, b1: String, b2: String) -> Animation:
	var clip := Animation.new()
	clip.length = 5.0
	var t := 0.0
	for bone_name: String in [b1, b2]:
		_press_pos(clip, skel, bone_name, Vector3(0, -BUTTON_TRAVEL, 0), t)
		t += 0.6
	_press_pos(clip, skel, "b_thumbstick", Vector3(0, -STICK_TRAVEL, 0), t)
	t += 0.6
	_press_pos(clip, skel, "b_trigger_grip", Vector3(0, 0, GRIP_TRAVEL), t)
	t += 0.6
	var bone := skel.find_bone("b_trigger_front")
	var rest := skel.get_bone_rest(bone).basis.get_rotation_quaternion()
	var track := clip.add_track(Animation.TYPE_ROTATION_3D)
	clip.track_set_path(track, NodePath("Skeleton3D:b_trigger_front"))
	clip.rotation_track_insert_key(track, t, rest)
	clip.rotation_track_insert_key(track, t + 0.25,
		rest * Quaternion(Vector3.RIGHT, deg_to_rad(TRIGGER_TURN)))
	clip.rotation_track_insert_key(track, t + 0.5, rest)
	return clip


## A press along `travel` (in the bone's own frame) and back.
static func _press_pos(clip: Animation, skel: Skeleton3D, bone_name: String, travel: Vector3,
		at: float) -> void:
	var bone := skel.find_bone(bone_name)
	var rest := skel.get_bone_rest(bone)
	var track := clip.add_track(Animation.TYPE_POSITION_3D)
	clip.track_set_path(track, NodePath("Skeleton3D:%s" % bone_name))
	clip.position_track_insert_key(track, at, rest.origin)
	clip.position_track_insert_key(track, at + 0.25, rest.origin + rest.basis * travel)
	clip.position_track_insert_key(track, at + 0.5, rest.origin)


static func _bone(skel: Skeleton3D, bone_name: String, parent: int, rest: Transform3D) -> int:
	var bone := skel.get_bone_count()
	skel.add_bone(bone_name)
	if parent >= 0:
		skel.set_bone_parent(bone, parent)
	skel.set_bone_rest(bone, rest)
	skel.reset_bone_pose(bone)
	return bone


## A part riding `bone`, at `offset` in the bone's frame.
static func _part(skel: Skeleton3D, bone: int, mesh: MeshInstance3D, offset: Transform3D) -> void:
	var attach := BoneAttachment3D.new()
	attach.bone_name = skel.get_bone_name(bone)
	skel.add_child(attach)
	mesh.transform = offset
	attach.add_child(mesh)


## A basis whose +Y is `axis`, which is the way a CylinderMesh stands.
static func _axis_basis(axis: Vector3) -> Basis:
	var y := axis.normalized()
	var x := Vector3.RIGHT if absf(y.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var z := x.cross(y).normalized()
	x = y.cross(z).normalized()
	return Basis(x, y, z)


static func _cylinder(radius: float, height: float, color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 32
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _material(color)
	return mi


static func _box(size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _material(color)
	return mi


static func _material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.55
	return m
