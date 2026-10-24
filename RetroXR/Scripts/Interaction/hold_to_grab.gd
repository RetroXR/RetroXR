## HoldToGrab — a grab that has to be EARNED: hold the grab control on the thing for a
## few seconds and a ring fills, then you have it.
##
## For objects too big or too fixed to be taken by a stray squeeze or click, like an
## arcade cabinet: an object opts in by answering `grab_hold_seconds()` (RetroSystem
## asks its model) with more than zero; everything else is grabbed at once, as before.
##
## This is the pure half, shared by the VR pickup (function_pickup.gd) and the desktop
## one (desktop_pickup.gd): which target is being held on, for how long, and whether it
## is done. Each caller decides what "still pointing at it" means for its own input and
## shows the ring its own way.
class_name HoldToGrab
extends RefCounted

## What a long-grab object asks for unless it says otherwise.
const DEFAULT_SECONDS := 1.0

var target: Node3D = null
var seconds: float = 0.0
var elapsed: float = 0.0
## True when the hold is on a ray target (the laser) rather than something in hand's reach.
var ranged: bool = false


## How long `obj` wants to be held on before it can be grabbed; 0 for an ordinary object.
static func seconds_for(obj: Object) -> float:
	if obj == null or not is_instance_valid(obj) or not obj.has_method("grab_hold_seconds"):
		return 0.0
	return maxf(float(obj.call("grab_hold_seconds")), 0.0)


func is_active() -> bool:
	return target != null and is_instance_valid(target)


## Start holding on `t`. Restarts if already holding on something.
func begin(t: Node3D, hold_seconds: float, is_ranged: bool = false) -> void:
	target = t
	seconds = hold_seconds
	elapsed = 0.0
	_off_aim = 0.0
	ranged = is_ranged


func cancel() -> void:
	target = null
	seconds = 0.0
	elapsed = 0.0
	_off_aim = 0.0
	ranged = false


## How full the ring is, 0..1.
func progress() -> float:
	if not is_active() or seconds <= 0.0:
		return 0.0
	return clampf(elapsed / seconds, 0.0, 1.0)


## How long the aim may wander off the target while the control stays down before the hold
## is given up. A hand shakes and a mouse drifts; the ring should not reset for a flicker.
const AIM_GRACE := 0.35

var _off_aim := 0.0


## Step the hold by `delta` seconds. `control_down` is the grab control itself (releasing it
## cancels at once); `aimed` is whether it is still on the target (leaving it for longer than
## AIM_GRACE cancels, and the ring waits while it is off). True the moment it completes, once:
## the hold is over by then and `target` is cleared, so ask `finished_target` afterwards.
func advance(delta: float, control_down: bool, aimed: bool = true) -> bool:
	if not is_active():
		return false
	if not control_down:
		cancel()
		return false
	if not aimed:
		_off_aim += delta
		if _off_aim > AIM_GRACE:
			cancel()
		return false
	_off_aim = 0.0
	elapsed += delta
	if elapsed < seconds:
		return false
	finished_target = target
	finished_ranged = ranged
	cancel()
	return true


## What the last completed hold was on (valid until the next completion).
var finished_target: Node3D = null
var finished_ranged: bool = false
