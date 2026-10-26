## RetroPadController — the universal RetroXR pad (retro_controller.tscn).
##
## Unlike the console pads this one has no imported model; the shell and every
## control are primitives authored in the scene. It carries the complete libretro
## joypad: a rocking D-pad (UP/DOWN/LEFT/RIGHT), the A/B/X/Y face diamond,
## SELECT/START, L/R shoulders, L2/R2 triggers and two analog sticks that also
## click (L3/R3) — all 16 buttons plus both axes.
##
## Animation is AnimatedController's engine. Because the meshes are authored
## here rather than imported, controls are bound by node path instead of the
## fuzzy mesh-name search the console models need.
class_name RetroPadController
extends AnimatedController

# Node path (from the pad root) -> RETRO_JOYPAD bit.
const PAD_FACE: Dictionary = {
	"Model/FaceB": ControllerBindings.JOYPAD_B,
	"Model/FaceA": ControllerBindings.JOYPAD_A,
	"Model/FaceY": ControllerBindings.JOYPAD_Y,
	"Model/FaceX": ControllerBindings.JOYPAD_X,
}
const PAD_SMALL: Dictionary = {
	"Model/Select": ControllerBindings.JOYPAD_SELECT,
	"Model/Start":  ControllerBindings.JOYPAD_START,
}
const PAD_EDGE: Dictionary = {
	"Model/ShoulderL": ControllerBindings.JOYPAD_L,
	"Model/ShoulderR": ControllerBindings.JOYPAD_R,
	"Model/TriggerL":  ControllerBindings.JOYPAD_L2,
	"Model/TriggerR":  ControllerBindings.JOYPAD_R2,
}

## Shoulders and triggers are mounted on the far face (-Z) and travel into it,
## not down into the top surface like the face buttons.
const EDGE_DIR := Vector3.BACK

## The D-pad and sticks rock about the shell surface, which sits below each
## control's own origin by these amounts.
const DPAD_PIVOT_DROP:  float = 0.003
const STICK_PIVOT_DROP: float = 0.0055


func _cache_meshes() -> void:
	_anim.buttons.clear()
	for path: String in PAD_FACE:
		_add_button(path, int(PAD_FACE[path]), FACE_PRESS, PRESS_DIR)
	for path: String in PAD_SMALL:
		_add_button(path, int(PAD_SMALL[path]), SMALL_PRESS, PRESS_DIR)
	for path: String in PAD_EDGE:
		_add_button(path, int(PAD_EDGE[path]), TRIGGER_PRESS, EDGE_DIR)
	_anim.dpad    = _pivoted_control("Model/DPad", DPAD_PIVOT_DROP)
	_anim.stick_l = _pivoted_control("Model/StickL", STICK_PIVOT_DROP)
	_anim.stick_r = _pivoted_control("Model/StickR", STICK_PIVOT_DROP)


## The authored D-pad's UP arm points -Z (away from the holder, the edge the
## cable and shoulders sit on), so the engine's default pitch would lift it.
func _dpad_pitch_sign() -> float:
	return -1.0


func _add_button(path: String, bit: int, depth: float, dir: Vector3) -> void:
	var m := get_node_or_null(path) as MeshInstance3D
	if m == null:
		push_warning("RetroPadController: control mesh not found: " + path)
		return
	_anim.buttons.append({"node": m, "rest": m.transform, "bit": bit, "depth": depth, "dir": dir})


func _pivoted_control(path: String, drop_dist: float) -> Dictionary:
	var m := get_node_or_null(path) as MeshInstance3D
	if m == null:
		push_warning("RetroPadController: control mesh not found: " + path)
		return {}
	return {"node": m, "rest": m.transform, "pivot": m.position - Vector3(0.0, drop_dist, 0.0)}
