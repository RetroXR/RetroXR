## MountAim self-tests -- what a gun on a pivot tells the game about where it points, headless and with no native extension.
##
##     "$godot" --headless --path RetroXR res://Tests/mount_aim_tests.tscn
##
## Exits 0 when everything passes, 1 otherwise.
##
## The travel is spread over the whole picture: the ends of the yaw are the picture's left and right edges, the ends of the pitch its bottom and top, whichever way the rifle faces at rest, and the aim
## never leaves the picture. The pitch is not symmetrical (12 down, 28 up), so the middle of the picture is the middle of the travel, not the rest.
extends "res://Tests/test_suite.gd"

const YAW := deg_to_rad(40.0)
const PITCH := Vector2(deg_to_rad(-12.0), deg_to_rad(28.0))


func _ready() -> void:
	suite_tag = "mount_aim"
	var middle := MountAim.picture(0.0, deg_to_rad(8.0), YAW, PITCH)
	_ok(middle == Vector2i.ZERO, "mount/the middle of the travel (straight ahead, 8 degrees up) is the middle of the picture", str(middle))
	var left := MountAim.picture(YAW, deg_to_rad(8.0), YAW, PITCH)
	var right := MountAim.picture(-YAW, deg_to_rad(8.0), YAW, PITCH)
	_ok(left.x == -32767 and right.x == 32767 and left.y == 0, "mount/turned all the way to the left is the picture's left edge, to the right its right edge (%s, %s)" % [str(left), str(right)])
	var top := MountAim.picture(0.0, PITCH.y, YAW, PITCH)
	var bottom := MountAim.picture(0.0, PITCH.x, YAW, PITCH)
	_ok(top.y == -32767 and bottom.y == 32767 and top.x == 0, "mount/up as far as it goes is the picture's top (y grows downward), down as far as it goes its bottom (%s, %s)" % [str(top), str(bottom)])
	# The old way: at the rifle's very top (28 degrees) the glass was still 30 degrees above it; the aim now says the TOP of the picture there, not the bottom.
	_ok(MountAim.picture(0.0, PITCH.y, YAW, PITCH).y < MountAim.picture(0.0, 0.0, YAW, PITCH).y, "mount/raising the barrel raises the aim")
	# Past the travel (a hand that goes on) it stays on the edge.
	var past := MountAim.picture(3.0, 2.0, YAW, PITCH)
	var under := MountAim.picture(-3.0, -2.0, YAW, PITCH)
	_ok(past == Vector2i(-32767, -32767) and under == Vector2i(32767, 32767), "mount/past the travel the aim stays at the picture's edge (%s, %s)" % [str(past), str(under)])
	_ok(MountAim.picture(0.0, 0.0, YAW, PITCH).y > 0, "mount/straight ahead at rest is a little BELOW the middle: the travel reaches higher than it does lower")
	_finish()
