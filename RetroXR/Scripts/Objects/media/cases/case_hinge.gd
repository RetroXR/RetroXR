## CaseHinge — the hand's grip on a game case's lid, flip tray or flipper.
##
## VRHinge's grab, poke and pointer plumbing with nothing of its own motion: while a hand has it, GameCase hands the
## angle it reads here to CaseHingeSim; let go, the sim swings the panel and writes the angle back through
## set_angle_quiet(). `gate` (a Callable returning bool) says whether a hand may take it now: a flip tray under a
## shut lid may not.
class_name CaseHinge
extends VRHinge

var gate: Callable
## The angle speed (deg/s) of the last frames a hand held it, for the sim on release.
var release_speed_deg := 0.0
var _prev_deg := 0.0


func is_held() -> bool:
	return _trigger_ctrl != null or _pointer_held or _poke_ctrl != null


## Write the sim's angle without emitting (the hand is not moving it) and without the base class's momentum.
func set_angle_quiet(deg: float) -> void:
	_release_angular_velocity_deg = 0.0
	if target != null:
		target.rotation.x = deg_to_rad(clampf(deg, min_deg, max_deg))
	_prev_deg = deg


func _process(delta: float) -> void:
	super(delta)
	var now := get_rotation_deg()
	if is_held() and delta > 0.0:
		release_speed_deg = lerpf(release_speed_deg, (now - _prev_deg) / delta, 0.5)
	_prev_deg = now


func _can_engage() -> bool:
	return gate.call() if gate.is_valid() else true


## Hold the angle the hand left: no spring, no latch of the base class's (the sim does both).
func _on_released() -> void:
	pass


func _open_toward_max() -> bool:
	return true
