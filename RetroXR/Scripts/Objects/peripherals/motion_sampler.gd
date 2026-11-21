## MotionSampler — what an accelerometer and a gyroscope on a held object read,
## derived from the object's pose each physics tick: proper acceleration (motion
## minus gravity, so +1 g up at rest) and angular velocity, both in WORLD space and
## smoothed. The caller turns them onto its device's own axes.
##
## Position is differentiated rather than linear_velocity read, because a held
## pickable is frozen and moved by the grab driver: its velocities are not its
## motion. Run it on the physics clock (see the note in wiimote.gd's _send_accel).
class_name MotionSampler
extends RefCounted

const G := 9.80665
const ACCEL_SMOOTHING := 0.25
const GYRO_SMOOTHING := 0.45
## Below this a frame's rotation is tracking jitter, not a turn.
const GYRO_MIN_ANGLE := 0.00001

var accel_world := Vector3.UP * G
var gyro_world := Vector3.ZERO

var _have_prev := false
var _prev_pos := Vector3.ZERO
var _prev_vel := Vector3.ZERO
var _prev_basis := Basis.IDENTITY


## Forget the history: a device carried while nothing read it must not report that
## carry as one frame's motion.
func reset() -> void:
	_have_prev = false
	accel_world = Vector3.UP * G
	gyro_world = Vector3.ZERO
	_prev_vel = Vector3.ZERO


## One physics tick of the device at `xform`.
func sample(xform: Transform3D, delta: float) -> void:
	if delta <= 0.0:
		return
	var basis_now := xform.basis.orthonormalized()
	if not _have_prev:
		_have_prev = true
		_prev_pos = xform.origin
		_prev_basis = basis_now
		_prev_vel = Vector3.ZERO
		return
	var vel := (xform.origin - _prev_pos) / delta
	var a := (vel - _prev_vel) / delta + Vector3.UP * G
	_prev_pos = xform.origin
	_prev_vel = vel
	accel_world = accel_world.lerp(a, ACCEL_SMOOTHING)

	var q_prev := _prev_basis.get_rotation_quaternion()
	var q_now := basis_now.get_rotation_quaternion()
	_prev_basis = basis_now
	if q_prev.dot(q_now) < 0.0:
		q_prev = -q_prev   # the short way round
	var w := Vector3.ZERO
	var turn := tick_rotation(q_prev, q_now)
	if turn.length() > GYRO_MIN_ANGLE:
		w = turn / delta
	gyro_world = gyro_world.lerp(w, GYRO_SMOOTHING)


## One tick's rotation from `q_prev` to `q_now`, as axis * angle (radians, world).
##
## NEVER Quaternion.get_angle() here: it is 2 * acos(w), and for the rotation of
## one tick w is so close to 1 that in 32-bit floats it IS 1. Measured: every turn
## up to 0.05 degrees a tick came out as exactly 0, and 0.1 degrees as 0.0885. A
## slow turn of a held GamePad (1.3 deg/s at 90 Hz) was thrown away whole, while
## the quick parts of the same movement got through -- so slow turns did not count
## and the pointer went off in odd directions. atan2 of the vector part and w is
## exact at any size.
static func tick_rotation(q_prev: Quaternion, q_now: Quaternion) -> Vector3:
	var dq := (q_now * q_prev.inverse()).normalized()
	if dq.w < 0.0:
		dq = -dq   # the short way round
	var v := Vector3(dq.x, dq.y, dq.z)
	var s := v.length()
	if s <= 0.0:
		return Vector3.ZERO
	return v / s * (2.0 * atan2(s, dq.w))


## Acceleration in g on the axes of `basis` (the device's own frame in the world).
func accel_local(basis: Basis) -> Vector3:
	var a := MotionFilter.deadband_motion(accel_world, G)
	return basis.orthonormalized().inverse() * (a / G)


## Angular velocity in rad/s on the axes of `basis`.
func gyro_local(basis: Basis) -> Vector3:
	return basis.orthonormalized().inverse() * gyro_world
