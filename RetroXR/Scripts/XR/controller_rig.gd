## ControllerRig — how a controller model's own rig moves each of its inputs.
##
## A runtime model (Meta's, through XR_FB_render_model) comes with an
## AnimationPlayer whose one clip runs every input in turn across five seconds,
## a button's stretch of it pressing twice. So the timeline is no use as a dial:
## what is wanted from each track is only where the bone rests and how far it
## travels, and a press interpolates between the two. Nothing here chooses an
## axis or a travel distance, so a rig from another vendor, with other geometry
## and other bone axes, moves for the same reason.
##
## Static, and shared by the two things that press a model's buttons: the
## controller in the player's hand (ControllerModel, from the real inputs) and
## the copy the welcome page shows (ControllerDemo, from a script of steps).
class_name ControllerRig
extends RefCounted


## Bone name -> { bone, rot_rest, rot_far, pos_rest, pos_far } for every bone
## `clip` moves on `skeleton`.
static func read(skeleton: Skeleton3D, clip: Animation) -> Dictionary:
	var out := {}
	if skeleton == null or clip == null:
		return out
	for track in clip.get_track_count():
		var kind := clip.track_get_type(track)
		if kind != Animation.TYPE_ROTATION_3D and kind != Animation.TYPE_POSITION_3D:
			continue
		var bone_name := String(clip.track_get_path(track).get_concatenated_subnames())
		var bone := skeleton.find_bone(bone_name)
		if bone < 0:
			continue
		var driven: Dictionary = out.get(bone_name, {"bone": bone})
		_read_extremes(clip, track, kind, driven)
		out[bone_name] = driven
	return out


## Put a bone `amount` of the way from where the rig rests it to as far as the
## rig ever takes it. The caller checks the skeleton is still alive: a runtime
## may replace it between two calls. `turn` / `move` leave the rotation or the
## position alone: a stick's rotation track is its lean, which a click is not.
static func actuate(skeleton: Skeleton3D, driven_bones: Dictionary, bone_name: String,
		amount: float, turn := true, move := true) -> void:
	var driven: Variant = driven_bones.get(bone_name)
	if driven == null:
		return
	var t := clampf(amount, 0.0, 1.0)
	if turn and driven.has("rot_rest"):
		skeleton.set_bone_pose_rotation(driven["bone"],
			(driven["rot_rest"] as Quaternion).slerp(driven["rot_far"], t))
	if move and driven.has("pos_rest"):
		skeleton.set_bone_pose_position(driven["bone"],
			(driven["pos_rest"] as Vector3).lerp(driven["pos_far"], t))


static func _read_extremes(clip: Animation, track: int, kind: int, driven: Dictionary) -> void:
	var count := clip.track_get_key_count(track)
	if count == 0:
		return
	var rest: Variant = clip.track_get_key_value(track, 0)
	var far: Variant = rest
	var furthest := 0.0
	for k in count:
		var v: Variant = clip.track_get_key_value(track, k)
		var dist: float = _deviation(rest, v)
		if dist > furthest:
			furthest = dist
			far = v
	if kind == Animation.TYPE_ROTATION_3D:
		driven["rot_rest"] = rest
		driven["rot_far"] = far
	else:
		driven["pos_rest"] = rest
		driven["pos_far"] = far


static func _deviation(rest: Variant, v: Variant) -> float:
	if rest is Quaternion:
		return (rest as Quaternion).angle_to(v as Quaternion)
	if rest is Vector3:
		return (rest as Vector3).distance_to(v as Vector3)
	return 0.0
