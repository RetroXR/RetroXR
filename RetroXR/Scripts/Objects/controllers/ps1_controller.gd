## Ps1Controller — the original PlayStation pad (SCPH-1080).
##
## Every control animates: the four face buttons, SELECT and START, both shoulder
## pairs, and a rocking D-pad.
##
## That is only possible because of WHICH asset this is. The pad bundled with the
## console scene had its four face buttons, both shoulders and SELECT/START as one
## connected 11,784-triangle surface — a single island, so nothing could be pulled
## out and no button could travel on its own. This shell arrives as 105 disconnected
## islands, which Tools/glb/prepare_ps1_pad.py groups by region and joins into the
## named meshes bound below.
##
## Mapping follows the hardware's own labelling onto the RetroPad: cross is the
## primary button (B), circle A, square Y, triangle X. A PS1 core reads fire off B,
## so cross must be B and not the other way round.
class_name Ps1Controller
extends AnimatedController

## Measured by ray against the shell beside each cap, not taken from the recess
## depth: the caps stand 1.04 to 1.39 mm proud on both pads, NOT the ~2.6 mm this
## file used to claim. A 1.4 mm throw therefore pushed CIRCLE and TRIANGLE below
## the surface and they vanished at full press. 0.8 mm is a clear press that
## leaves a quarter of a millimetre still standing on the shallowest cap.
const PRESS_FACE: float = 0.0008
## SELECT and START are flush membrane buttons that barely travel, and on the
## DualShock they sit in a recess LOWER than the shell around them, so this is
## half what the face caps get rather than merely less.
const PRESS_SMALL: float = 0.0004
## Shoulders hinge more than they sink, but a short straight push reads correctly
## at the scale they are seen from.
const PRESS_SHOULDER: float = 0.0012

const FACE: Dictionary = {
	"BtnCross":    ControllerBindings.JOYPAD_B,
	"BtnCircle":   ControllerBindings.JOYPAD_A,
	"BtnSquare":   ControllerBindings.JOYPAD_Y,
	"BtnTriangle": ControllerBindings.JOYPAD_X,
}
const SMALL: Dictionary = {
	"BtnSelect": ControllerBindings.JOYPAD_SELECT,
	"BtnStart":  ControllerBindings.JOYPAD_START,
}
## Which way a shoulder travels, in the pad's own frame.
##
## NOT the -Y every other control uses. The shoulders are on the pad's REAR
## VERTICAL FACE, stacked 1 over 2, so pressing them down slides them ALONG that
## face instead of into it -- which is what a straight-down press looked like
## from behind. A finger curls over the top edge and pushes FORWARD, into the
## body, which is +Z here: the cord leaves the far edge on -Z, so the front of
## the pad is +Z.
const SHOULDER_DIR := Vector3(0.0, 0.0, 1.0)


const SHOULDERS: Dictionary = {
	"BtnL1": ControllerBindings.JOYPAD_L,
	"BtnR1": ControllerBindings.JOYPAD_R,
	"BtnL2": ControllerBindings.JOYPAD_L2,
	"BtnR2": ControllerBindings.JOYPAD_R2,
}

## The D-pad rocks about the shell surface, which sits below the cross's own
## centre. The model ships no pivot empty, and _find_pivot's AABB fallback would
## rock it about its own middle — the same correction the NES pad needs.
const DPAD_PIVOT_DROP: float = 0.0025


func _cache_meshes() -> void:
	_anim.buttons.clear()
	for stem: String in FACE:
		_add(stem, int(FACE[stem]), PRESS_FACE)
	for stem: String in SMALL:
		_add(stem, int(SMALL[stem]), PRESS_SMALL)
	for stem: String in SHOULDERS:
		_add(stem, int(SHOULDERS[stem]), PRESS_SHOULDER, SHOULDER_DIR)
	_anim.dpad = _rocker("DPad")


## The shell lies face-up — +Y out of the face — with the D-pad on -X, which puts
## its UP arm on -Z, so the engine's default pitch would lift UP instead of
## pressing it. Same as the NES pad.
func _dpad_pitch_sign() -> float:
	return -1.0


func _add(stem: String, bit: int, depth: float, dir: Vector3 = Vector3.ZERO) -> void:
	var m := _find_mesh(stem)
	if m == null:
		push_warning("[Ps1Controller] control mesh not found: " + stem)
		return
	var entry := {"node": m, "rest": m.transform, "bit": bit, "depth": depth}
	# Omitted rather than passed as the default: ControlAnimator falls back to its
	# own press_dir when an entry carries no "dir", and writing a zero vector here
	# would pin the control in place instead.
	if dir != Vector3.ZERO:
		entry["dir"] = dir
	_anim.buttons.append(entry)


func _rocker(stem: String) -> Dictionary:
	var m := _find_mesh(stem)
	if m == null:
		push_warning("[Ps1Controller] control mesh not found: " + stem)
		return {}
	var pivot: Vector3 = _find_pivot(m, "DPadPivot")
	pivot.y -= DPAD_PIVOT_DROP
	return {"node": m, "rest": m.transform, "pivot": pivot}
