class_name FarIdle
extends RefCounted
## A machine nobody is near and nothing is running on does not need its controls stepped every frame.
##
## `step()` returns the delta to run this frame with, or -1.0 to skip it: while `idle` is true and the player's
## camera is more than DISTANCE away, the owner runs every INTERVAL seconds with the time that has passed; anything
## else runs every frame. With no 3D camera (a headless suite) it never skips.
##
## Measured in the Starlight Arcade on a Quest 3 (2026-11-13): nine arcade cabinets' module ticks and inputs and
## twelve handhelds' inputs were 3.2 ms of every frame with every one of them switched off and out of reach.

const DISTANCE := 2.5
const INTERVAL := 0.1

var _acc := 0.0


func step(node: Node3D, delta: float, idle: bool) -> float:
	if idle and node.is_inside_tree():
		var cam := node.get_viewport().get_camera_3d()
		if cam != null and cam.global_position.distance_squared_to(node.global_position) > DISTANCE * DISTANCE:
			_acc += delta
			if _acc < INTERVAL:
				return -1.0
			var run := _acc
			_acc = 0.0
			return run
	if _acc > 0.0:
		delta += _acc
		_acc = 0.0
	return delta
