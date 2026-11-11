## VRSpringReturnSlider — a MOMENTARY slide switch: it can be pushed off its rest
## position, but springs back the instant you let go, and only does anything if
## you HELD it there long enough.
##
## This is the PSP's power switch. Sony's manual gives three positions, and only
## one of them latches:
##   • slide UP                     → turn the system on (or sleep, when running)
##   • slide UP and hold  > 3 s     → turn the system OFF
##   • slide DOWN                   → HOLD, locks the buttons (a latching detent)
## The UP end is spring-loaded and returns to the middle by itself — owners who
## reassemble a PSP-1000 with that spring missing report having to push the switch
## back down by hand "or it would turn off again", which is the same mechanism
## seen from the other side.
##
## The DOWN/HOLD detent is deliberately not modelled: RetroXR has nothing for a
## button lock to disable, so it would move the cap and change nothing.
##
## Unlike the plain VRSlider this reports an INTENT, not a position — a flick that
## springs back before the dwell elapses is not a power change, so the owner wires
## toggle_requested rather than value_changed. Leave `steps` at 0 in the scene:
## detents would snap the spring-back instead of letting it travel.
class_name VRSpringReturnSlider
extends VRSlider

## The switch was held at the active end long enough to mean it.
signal toggle_requested

## Seconds it must be held to power the system ON. Shorter than the hardware's
## power-off dwell on purpose — Sony documents no minimum for switching on, and a
## real PSP lights up after about a second.
@export var on_hold_sec: float = 1.0
## Seconds it must be held to power the system OFF. Sony: "slide up and hold for
## more than three seconds".
@export var off_hold_sec: float = 3.0
## Value at or above which the switch counts as pushed to the active end.
@export var active_threshold: float = 0.6
## Spring-back rate, in value units per second (value spans the whole travel).
@export var return_speed: float = 8.0

## Kept in step by the owner so the switch knows which dwell applies — the
## hardware powers on off a short push but needs a long one to power down.
var system_on := false

var _held := 0.0
var _fired := false


func _process(delta: float) -> void:
	super._process(delta)
	var engaged := _engaged_ctrl != null or _pointer_engaged
	if not engaged:
		# Let go — spring home. Silently: sliding back is not an input.
		_held = 0.0
		_fired = false
		if value > 0.0:
			set_value_no_signal(maxf(0.0, value - return_speed * delta))
		return
	if value < active_threshold:
		_held = 0.0
		return
	_held += delta
	if _fired:
		return
	if _held >= (off_hold_sec if system_on else on_hold_sec):
		_fired = true
		toggle_requested.emit()


## Springing home is moving by itself: stay awake until it is there. PokeWake puts
## an idle slider to sleep 30 frames after the last hand leaves, and a switch let
## go mid-travel used to stop wherever it was when that happened.
func _keep_awake() -> bool:
	return value > 0.0


## How far through the current hold the switch is, 0..1 — for a caller that wants
## to show progress. Zero whenever it is not being held at the active end.
func hold_progress() -> float:
	var need := off_hold_sec if system_on else on_hold_sec
	if need <= 0.0:
		return 0.0
	return clampf(_held / need, 0.0, 1.0)
