## VbController — stand-in Virtual Boy controller.
##
## The real VB pad is unusual, and the model follows it: a butterfly of two
## rounded wings over two grips, with a D-pad on EACH wing, SELECT and START
## inboard of the left one, B and A inboard of the right one, L and R on the
## underside where the index fingers sit, and no analog sticks at all.
##
## It also carries the console's POWER switch and the battery pack on its back,
## because the head unit has neither. Sliding the switch powers the console it is
## plugged into, so the Virtual Boy is operated the way the hardware actually is.
##
## A proper model exists in the wild but isn't in our library yet, so this is
## authored from primitives.
class_name VbController
extends AnimatedController

## Fraction of travel past which the switch counts as ON.
const _ON_AT := 0.5

# Node path (from the pad root) -> RETRO_JOYPAD bit.
const VB_FACE: Dictionary = {
	"Model/WingR/ButtonB": ControllerBindings.JOYPAD_B,
	"Model/WingR/ButtonA": ControllerBindings.JOYPAD_A,
	"Model/WingL/Select":  ControllerBindings.JOYPAD_SELECT,
	"Model/WingL/Start":   ControllerBindings.JOYPAD_START,
}
const VB_SHOULDERS: Dictionary = {
	"Model/ShoulderL": ControllerBindings.JOYPAD_L,
	"Model/ShoulderR": ControllerBindings.JOYPAD_R,
}

## L and R are moulded into the pad's underside, so they travel UP into it.
const SHOULDER_DIR := Vector3.UP

## Bits the RIGHT D-pad rocks on, as [up, down, left, right]. The VB's fourteen
## controls outnumber the RetroPad bits its other controls already claim, so the
## second D-pad borrows the four left over. Cores differ on which they pick, and
## these bindings are user-remappable, so the rocker also follows the right
## analog stick — the other convention cores use for it.
const RIGHT_DPAD_BITS := [ControllerBindings.JOYPAD_X, ControllerBindings.JOYPAD_L2,
	ControllerBindings.JOYPAD_Y, ControllerBindings.JOYPAD_R2]

const DPAD_PIVOT_DROP: float = 0.003

var _slider: VRSlider = null
var _was_on := false


func _ready() -> void:
	super._ready()
	_slider = get_node_or_null("PowerSlider") as VRSlider
	if _slider != null:
		_slider.value_changed.connect(_on_power_slider)


func _cache_meshes() -> void:
	_anim.buttons.clear()
	for path: String in VB_FACE:
		_add_button(path, int(VB_FACE[path]), FACE_PRESS, PRESS_DIR)
	for path: String in VB_SHOULDERS:
		_add_button(path, int(VB_SHOULDERS[path]), TRIGGER_PRESS, SHOULDER_DIR)
	_anim.dpad = _rocker("Model/WingL/DPad")
	_anim.dpad2 = _rocker("Model/WingR/DPad")
	if not _anim.dpad2.is_empty():
		_anim.dpad2["bits"] = RIGHT_DPAD_BITS
		_anim.dpad2["axis"] = "right"


## The D-pads' UP arms point -Z, the edge the cable leaves by.
func _dpad_pitch_sign() -> float:
	return -1.0


func _add_button(path: String, bit: int, depth: float, dir: Vector3) -> void:
	var m := get_node_or_null(path) as MeshInstance3D
	if m == null:
		push_warning("VbController: control mesh not found: " + path)
		return
	_anim.buttons.append({"node": m, "rest": m.transform, "bit": bit, "depth": depth, "dir": dir})


func _rocker(path: String) -> Dictionary:
	var m := get_node_or_null(path) as MeshInstance3D
	if m == null:
		push_warning("VbController: control mesh not found: " + path)
		return {}
	return {"node": m, "rest": m.transform, "pivot": m.position - Vector3(0.0, DPAD_PIVOT_DROP, 0.0)}


## Drive the plugged-in console's power from the slider, latching on the
## crossing so a jittery hand doesn't toggle it repeatedly mid-slide.
func _on_power_slider(v: float) -> void:
	var on := v >= _ON_AT
	if on == _was_on:
		return
	_was_on = on
	# ObjectSync moves this cap on the other peers, but the authoritative power
	# intent travels separately. Do not turn their cores on/off from the visual
	# replay or the same physical move is applied twice.
	if NetworkManager.is_event_applying():
		return
	var sys := _connected_system
	if sys == null:
		return
	if on != sys.is_powered_on:
		sys.toggle_power()


## Reflect the console's state if it was powered some other way (the cabinet
## START button, a save restore), so the switch never sits at odds with it.
func on_plugged_in(system: RetroSystem, port_index: int) -> void:
	super.on_plugged_in(system, port_index)
	if _slider == null or system == null:
		return
	_was_on = system.is_powered_on
	_slider.set_value_no_signal(1.0 if _was_on else 0.0)
