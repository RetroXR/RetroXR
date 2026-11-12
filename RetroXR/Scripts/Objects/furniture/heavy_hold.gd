## HeavyHold — a held piece of furniture moves like the heavy thing it is: it goes where the hold puts it (a hand, the
## desktop hand, a laser), but with a limited speed and acceleration, turning likewise.
##
## Why: what lies in its drawers is ordinary physics, carried by the drawer's floor and walls. A hold moves a held body
## wherever the hand is, at once: the pull-in starts at 2.5 m/s in one tick and stops dead, and a turn of the head
## swings a desktop-held chest round at several metres a second. The drawer's 8 mm floor then moved 28 mm in a tick: a
## TV remote went out through it, and a quarter turn's walls cut through a box and Jolt threw it 100 m
## (2026-11-12, vr_drawer_tests again/ "picked up by"). Limited to what friction can carry, it stays in.
##
## The owner calls `step()` from its _physics_process, AFTER whatever moves it this tick (its
## process_physics_priority above the grab driver's and the pickup's), every tick, held or not. What moved it is read
## back as the pose it was moved to; the piece is put where it has got to on its way there instead.
class_name HeavyHold
extends RefCounted

## m/s and m/s^2: under what friction holds (0.8 g) and under g, so nothing lifts off the floor of a drawer lowered.
## The speed is held to 1 m/s by how JOLT carries things on a moving kinematic floor (measured 2026-11-12, not the
## damping first blamed): every pickable has continuous collision on (HeldObjectPhysics), settles a few mm INTO a floor
## and stays there, and a floor lifting faster than about 1.2-1.3 m/s then outruns it and it drops through. Switching
## its continuous collision off once it has settled does not lift it back out, a deeper floor does not help, nor does
## cancelling its damping: only a body that never had it rides at 4 m/s. So the hold stays slow enough.
const MAX_SPEED := 1.0
const MAX_ACCEL := 5.0
## rad/s and rad/s^2.
const MAX_TURN := 2.0
const MAX_TURN_ACCEL := 10.0

var _held := false
## Where it is now on its way (what it was last put at), and where the hold wants it.
var _at := Transform3D()
var _want := Transform3D()
var _v := Vector3.ZERO
var _w := 0.0
## Its pose at the end of every tick it was NOT held: on the first held tick the hold has already moved it.
var _rest := Transform3D()


## `held` is the owner's own polled answer (frozen, on the held layer).
func step(body: RigidBody3D, held: bool, delta: float) -> void:
	if not held:
		if _held:
			_held = false
			# Let go with the speed it HAS (not its turn: heavy furniture let go does not spin on): a hold may end while it
			# is still on its way, as it trails the hand, and let go at rest it stopped dead from up to 1 m/s. Moving on,
			# it and what is in its drawers slow down together.
			if not body.freeze:
				body.linear_velocity = _v
				body.angular_velocity = Vector3.ZERO
			print("[HeavyHold] %s: let go moving %.2f m/s" % [body.name, _v.length()])
		_rest = body.global_transform
		return
	if not _held:
		_held = true
		_at = _rest
		_want = body.global_transform
		_v = Vector3.ZERO
		_w = 0.0
		print("[HeavyHold] %s: held; following the hold at up to %.1f m/s, %.0f m/s^2" % [body.name, MAX_SPEED, MAX_ACCEL])
	elif not body.global_transform.is_equal_approx(_at):
		# Something moved it this tick (the grab driver pushes only when its destination changes): that is where the
		# hold wants it now. Unmoved, it keeps going where it last wanted to.
		_want = body.global_transform
	var scale := _want.basis.get_scale()
	# Along: as fast as it can still stop in the distance left, never past MAX_SPEED, and changing speed by MAX_ACCEL.
	var gap := _want.origin - _at.origin
	var dist := gap.length()
	var want_v := gap / dist * minf(MAX_SPEED, sqrt(2.0 * MAX_ACCEL * dist)) if dist > 0.0001 else Vector3.ZERO
	_v = _v.move_toward(want_v, MAX_ACCEL * delta)
	var move := _v * delta
	var origin := _want.origin if move.length() >= dist else _at.origin + move
	# Turning: the same, on the angle left.
	var q_at := _at.basis.get_rotation_quaternion()
	var q_want := _want.basis.get_rotation_quaternion()
	var angle := q_at.angle_to(q_want)
	var want_w := minf(MAX_TURN, sqrt(2.0 * MAX_TURN_ACCEL * angle))
	_w = move_toward(_w, want_w, MAX_TURN_ACCEL * delta)
	var q := q_want if angle < 0.0001 or _w * delta >= angle else q_at.slerp(q_want, _w * delta / angle)
	_at = Transform3D(Basis(q).scaled(scale), origin)
	body.global_transform = _at
	# A frozen body can drop the node's write: the physics server is told too (function_pickup's ray hold does the same).
	PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, _at)
