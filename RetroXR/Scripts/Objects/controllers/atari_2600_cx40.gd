## Atari2600CX40 — the 2600's one-button digital joystick.
##
## The stick IS the D-pad. It has no analogue axis: the shaft closes one of four
## leaf switches, which is exactly what AnimatedController's rocker already
## models, and that base even anticipates this case — "a real joystick shaft
## swings much further. Override per controller." So the only differences from a
## flat pad are how far it leans and that there is a single button beside it.
##
## Everything else — the per-frame joypad state, the lerp, hold/plug/cable/rumble
## /netplay — comes from the base unchanged.
class_name Atari2600CX40
extends AnimatedController

## The shaft swings far further than a moulded D-pad's few degrees.
const SHAFT_TILT_DEG: float = 18.0

## Fire is JOYPAD_B, not A. B is bit 0, the RetroPad's primary face button, and
## single-button hardware maps its one control there — a 2600 core reads fire off
## B. Binding A would leave the stick's button doing nothing in-game.
const FIRE_BIT: int = ControllerBindings.JOYPAD_B

## The button cap is only 2.3 mm thick, so the engine's 2.2 mm FACE_PRESS sank it
## almost exactly its own depth and it disappeared into the shell. 1 mm leaves
## 1.3 mm proud at full press, which is about the CX40's real throw.
const FIRE_PRESS: float = 0.0010


func _cache_meshes() -> void:
	_anim.buttons.clear()
	var m := _find_mesh("Button")
	if m == null:
		push_warning("Atari2600CX40: Button mesh not found")
	else:
		_anim.buttons.append({"node": m, "rest": m.transform,
			"bit": FIRE_BIT, "depth": FIRE_PRESS})
	_anim.dpad = _rocker("Stick")


## No pivot drop. The shell was exported with the shaft's origin already AT its
## base, where it enters the boot, so the mesh rocks about the right point on its
## own — unlike the NES pad, which needs its pivot pushed down to the shell face.
func _rocker(stem: String) -> Dictionary:
	var m := _find_mesh(stem)
	if m == null:
		push_warning("Atari2600CX40: control mesh not found: " + stem)
		return {}
	return {"node": m, "rest": m.transform, "pivot": m.position}


func _dpad_tilt_deg() -> float:
	return SHAFT_TILT_DEG


## The shell lies face-up with the fire button and the cord both on -Z, which is
## the edge that points AWAY from the holder — so UP leans the shaft to -Z and
## the engine's default pitch would push it the wrong way.
func _dpad_pitch_sign() -> float:
	return -1.0
