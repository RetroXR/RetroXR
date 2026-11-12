## GbPaperMotion — how a piece of paper's body is being moved, for GbThermalRibbon.
##
## From a pose each frame: gravity in that pose's frame less the acceleration of
## a point on it, how fast its turn is speeding up, and how the frame itself is
## moving (what paper lying on the ROOM rubs against). The Game Boy Printer's
## paper and a torn-off print in a hand both bend by these.
##
## Read off the pose a thing is DRAWN at (get_global_transform_interpolated), not
## its last physics tick: a held thing moves only on ticks, and a frame sees one
## tick's move or two (90 ticks a second against 72, 90 or 120 frames), so read
## off the ticks its speed stutters frame to frame and the paper buzzes with it.
##
## Speed and acceleration, and the turn rate and its change, are each smoothed:
## a hand's tracking jitters by a millimeter or so a frame, and differenced twice
## that is meters per second squared of shaking. Faster than JUMP_SPEED or
## SPIN_MAX is a jump (a snap into a hand), not a push.
class_name GbPaperMotion
extends RefCounted

## Smoothed over this long, seconds, and never taken as more than the MAXes.
const ACCEL_SMOOTH := 0.08
const ACCEL_MAX := 20.0
const SPIN_MAX := 12.0
const SPIN_ACCEL_MAX := 150.0
## m/s: faster is a jump.
const JUMP_SPEED := 4.0

## In the pose's frame: gravity less the point's acceleration, m/s^2.
var gravity := Vector3.ZERO
## The frame's angular acceleration, in its own axes, rad/s^2.
var angular_accel := Vector3.ZERO
## The point's velocity and the frame's turn rate, in the frame's own axes.
var velocity := Vector3.ZERO
var spin := Vector3.ZERO

var _pos := Vector3.ZERO
var _vel := Vector3.ZERO
var _accel := Vector3.ZERO
var _basis := Basis()
var _known := false


## Start again from the next pose: nothing it did before is a move.
func reset() -> void:
	_known = false


## Take the pose `xf` (drawn, in the room) after `delta` seconds; `point` is where
## on it the paper is held, in its frame.
func update(xf: Transform3D, point: Vector3, delta: float) -> void:
	if delta <= 0.0:
		return
	var basis := xf.basis.orthonormalized()
	var at := xf * point
	if not _known:
		_known = true
		_pos = at
		_vel = Vector3.ZERO
		_accel = Vector3.ZERO
		_basis = basis
		angular_accel = Vector3.ZERO
		spin = Vector3.ZERO
	var k := clampf(delta / ACCEL_SMOOTH, 0.0, 1.0)
	var vel := (at - _pos) / delta
	var vel_f := _vel.lerp(vel, k)
	var accel := (vel_f - _vel) / delta
	if vel.length() > JUMP_SPEED:
		vel_f = Vector3.ZERO
		accel = Vector3.ZERO
	_accel = _accel.lerp(accel.limit_length(ACCEL_MAX), k)
	_vel = vel_f
	_pos = at
	var turn := (_basis.inverse() * basis).get_rotation_quaternion()
	_basis = basis
	var spin_now := turn.get_axis() * turn.get_angle() / delta if turn.get_angle() > 1e-6 else Vector3.ZERO
	var filtered := spin.lerp(spin_now, k)
	var change := (filtered - spin) / delta
	if spin_now.length() > SPIN_MAX or vel.length() > JUMP_SPEED:
		filtered = Vector3.ZERO
		change = Vector3.ZERO
	spin = filtered
	angular_accel = angular_accel.lerp(change.limit_length(SPIN_ACCEL_MAX), k)
	var g := ProjectSettings.get_setting("physics/3d/default_gravity", 9.8) as float \
		* (ProjectSettings.get_setting("physics/3d/default_gravity_vector", Vector3.DOWN) as Vector3)
	gravity = basis.inverse() * (g - _accel)
	velocity = basis.inverse() * _vel
