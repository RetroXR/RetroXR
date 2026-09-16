## FamicomController — Controller I of an HVC-001: the pad with SELECT and START.
##
## Authored from primitives like the Virtual Boy's, because the asset library has
## no Famicom pad: a dark red shell with a gold face plate, a black cross D-pad,
## round red A and B, and two small red rectangles in the middle. The colours are
## read off photographs.
##
## Controller II is a subclass rather than a second copy of this, because the two
## pads differ in exactly one place: where SELECT and START sit here, II carries
## the microphone grille and its volume slider.
class_name FamicomController
extends AnimatedController

# Node path (from the pad root) -> RETRO_JOYPAD bit.
const FC_FACE: Dictionary = {
	"Model/Face/ButtonB": ControllerBindings.JOYPAD_B,
	"Model/Face/ButtonA": ControllerBindings.JOYPAD_A,
}
const FC_SMALL: Dictionary = {
	"Model/Face/Select": ControllerBindings.JOYPAD_SELECT,
	"Model/Face/Start":  ControllerBindings.JOYPAD_START,
}

## The cross rocks about the shell surface, which sits below its own origin.
const DPAD_PIVOT_DROP: float = 0.003


func _cache_meshes() -> void:
	_buttons.clear()
	for path: String in FC_FACE:
		_add_button(path, int(FC_FACE[path]), FACE_PRESS, PRESS_DIR)
	var small := small_controls()
	for path: String in small:
		_add_button(path, int(small[path]), SMALL_PRESS, PRESS_DIR)
	_dpad = _pivoted_control("Model/Face/DPad", DPAD_PIVOT_DROP)


## The two small buttons in the middle of the pad. Controller II answers with
## none: the microphone and its slider are moulded where they would be, and the
## hardware really does leave that pad without either button.
func small_controls() -> Dictionary:
	return FC_SMALL


## The authored cross's UP arm points -Z, the edge the cord leaves on and the far
## side from the holder's wrists, so the engine's default pitch would lift UP
## instead of pressing it.
func _dpad_pitch_sign() -> float:
	return -1.0


func _add_button(path: String, bit: int, depth: float, dir: Vector3) -> void:
	var m := get_node_or_null(path) as MeshInstance3D
	if m == null:
		push_warning("FamicomController: control mesh not found: " + path)
		return
	_buttons.append({"node": m, "rest": m.transform, "bit": bit, "depth": depth, "dir": dir})


func _pivoted_control(path: String, drop_dist: float) -> Dictionary:
	var m := get_node_or_null(path) as MeshInstance3D
	if m == null:
		push_warning("FamicomController: control mesh not found: " + path)
		return {}
	return {"node": m, "rest": m.transform, "pivot": m.position - Vector3(0.0, drop_dist, 0.0)}
