## GbPaperMotion — how a piece of paper is being moved, for GbPrinterStrip.
##
## From a pose each frame: gravity in that pose's frame less the acceleration of
## a point on it, that acceleration on its own (what swings the paper), and how
## fast its turn about its own X is changing. The Game Boy Printer's strip and a
## torn-off print in a hand both bend by these.
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
## In the pose's frame: the point's acceleration taken off, m/s^2.
var shove := Vector3.ZERO
## How fast the turn about the frame's X is speeding up, rad/s^2.
var spin_accel := 0.0
## Full local angular acceleration for the ribbon's bending and torsion.
var angular_accel := Vector3.ZERO
var _spin3 := Vector3.ZERO

var _pos := Vector3.ZERO
var _vel := Vector3.ZERO
var _accel := Vector3.ZERO
var _basis := Basis()
var _spin := 0.0
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
		_spin = 0.0
		spin_accel = 0.0
		angular_accel = Vector3.ZERO
		_spin3 = Vector3.ZERO
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
	var turn_x := turn.get_axis().x * turn.get_angle() if turn.get_angle() > 1e-6 else 0.0
	var spin := turn_x / delta
	var spin_f := lerpf(_spin, spin, k)
	var change := (spin_f - _spin) / delta
	if absf(spin) > SPIN_MAX or vel.length() > JUMP_SPEED:
		spin_f = 0.0
		change = 0.0
	_spin = spin_f
	spin_accel = lerpf(spin_accel, clampf(change, -SPIN_ACCEL_MAX, SPIN_ACCEL_MAX), k)
	var spin3 := turn.get_axis() * turn.get_angle() / delta if turn.get_angle() > 1e-6 else Vector3.ZERO
	var filtered := _spin3.lerp(spin3, k)
	var angular_change := (filtered - _spin3) / delta
	if spin3.length() > SPIN_MAX or vel.length() > JUMP_SPEED:
		filtered = Vector3.ZERO
		angular_change = Vector3.ZERO
	_spin3 = filtered
	angular_accel = angular_accel.lerp(angular_change.limit_length(SPIN_ACCEL_MAX), k)
	var g := ProjectSettings.get_setting("physics/3d/default_gravity", 9.8) as float \
		* (ProjectSettings.get_setting("physics/3d/default_gravity_vector", Vector3.DOWN) as Vector3)
	gravity = basis.inverse() * (g - _accel)
	shove = basis.inverse() * -_accel
