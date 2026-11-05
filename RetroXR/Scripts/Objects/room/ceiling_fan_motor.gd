## A ceiling fan's motor: the AnimationPlayer that spins the blades, run from a wall
## switch. The bedroom's three-gang plate points its middle gang (a LightSwitch,
## Target.GROUP) at the "ceiling_fan" group, and the switch calls set_lit(on) on
## every member, so saving and netplay need nothing new: both key the switch by
## its node path.
##
## A real fan does not stop dead. Off, the blades coast down over a few seconds;
## on, the motor brings them back up to speed a little faster. The animation's
## own length sets the full speed, so this only eases speed_scale between 0 and 1.
class_name CeilingFanMotor
extends AnimationPlayer


## Seconds to coast from full speed to a stop once switched off.
@export var spin_down_time: float = 6.0

## Seconds to come up from a stop to full speed once switched on.
@export var spin_up_time: float = 3.0

## Whether the motor is powered. The room is authored with the fan running.
var running: bool = true

var _speed: float = 1.0


func _ready() -> void:
	_speed = 1.0 if running else 0.0
	speed_scale = _speed
	set_process(false)


## The wall switch's call: coast down, or come back up to speed.
func set_lit(on: bool) -> void:
	running = on
	if not is_inside_tree():
		_speed = 1.0 if on else 0.0
		speed_scale = _speed
		set_process(false)
		return
	if on and not is_playing() and autoplay != &"":
		play(autoplay)
	set_process(true)


func _process(delta: float) -> void:
	var target := 1.0 if running else 0.0
	var rate := 1.0 / maxf(spin_up_time if running else spin_down_time, 0.01)
	_speed = move_toward(_speed, target, rate * delta)
	speed_scale = _speed
	if is_equal_approx(_speed, target):
		set_process(false)
