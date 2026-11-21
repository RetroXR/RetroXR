## CaseHingeSim — how a game case's lid and inner trays swing under gravity and snap shut.
##
## Not a rigid-body joint: each hinge is one damped pendulum about the case's spine axis, a handful of scalars
## stepped at the physics tick, whose only output is the angles GameCaseModel poses. Pure and deterministic on
## purpose, like BookFlop: no nodes, no engine time, so game_case_tests can step it with a fixed dt.
##
## Frame: the case's own (GameCaseModel): x across the front with the spine at -x, y up, z out of the front. A hinge
## at angle t (rad) has its panel's centre of mass at lever * (cos t, 0, sin t) from the hinge line: 0 lying shut over
## the back, 90 standing out of the front, 180 laid open flat beside it.
##
## Hinges are ordered from the back: a jewel case's flip tray then its lid; a keep case's flippers then its cover
## (the last is the "top" one, the one with the latch). They cannot pass through each other: 0 <= a0 <= a1 <= ... <=
## open_max. Two that meet move on together (an inelastic knock).
##
## The latch takes force (the owner, 2026-11-20): a hand pushing the top hinge within SNAP_DEG of shut (the trigger
## or a poke) catches it; a free swing catches it only if it comes home faster than `latch_speed` (rad/s), a case
## flicked shut. One that drifts shut slower rests there unlatched, and gravity can open it again. Caught (`clicked`
## is set for the host's haptic), it stays shut until a hand opens it or a jolt beyond `latch_break` (rad/s^2, far
## more than gravity) springs it: a shut case held upside down stays shut.
##
## Friction is a share of gravity's full pull: a jewel case's knuckles turn freely (its lid falls the way the case
## is tilted or waved), a keep case's polypropylene living hinge is stiffer than gravity (share above 1: it holds any
## angle until the case is shaken or a hand moves it). `kinetic` is the share of that still felt once it moves: a
## knuckle slips a little, a living hinge not at all (it stops when the push does).
##
## A keep case's cover is a living hinge (set_living_hinge): molded lying open, it will not rest shut unlatched but
## springs a few degrees ajar, and let go by a hand it eases a little back the way it came. Its flippers are trays
## clipped on pins, free like a jewel case's (set_hinge_friction).
##
## `spin` is the case's own turn about the hinge line speeding up (rad/s^2, about its +y): the panel stays behind,
## so a flick of the wrist swings it as gravity does.
class_name CaseHingeSim
extends RefCounted

const G := 9.81
## A hand pushing the top hinge within this of shut catches the latch.
const SNAP_DEG := 6.0
## Viscous damping on every hinge (1/s).
const DAMPING := 2.0
## Below this speed (rad/s) a hinge whose pull is within its friction stops dead.
const REST_SPEED := 0.05
## Bounce off the hinge's open stop.
const STOP_RESTITUTION := 0.15

var count := 0
## Per hinge: angle (rad), speed (rad/s), lever to the panel's centre of mass (m), held by a hand.
var angles := PackedFloat64Array()
var speeds := PackedFloat64Array()
var levers := PackedFloat64Array()
var held: Array[bool] = []
var open_max := PI
## Static friction as a share of the strongest pull gravity can give the hinge (k * g).
var friction := 0.15
## Sliding friction as a share of the static.
var kinetic := 0.8
## Per hinge: its static friction share and the sliding share of it (the case's, unless set_hinge_friction).
var frictions := PackedFloat64Array()
var kinetics := PackedFloat64Array()
## The top hinge as a living hinge: unlatched it rests `ajar` (rad) or so off shut; let go by a hand, it eases
## `springback` (rad) back the way it came.
var ajar := 0.0
var springback := 0.0
var _dir := PackedFloat64Array()
var _ease := PackedFloat64Array()
## What it takes to spring the latch (rad/s^2).
var latch_break := 400.0
## How fast (rad/s) a free swing must come home to catch the latch.
var latch_speed := 3.5
var latched := true
## Set on the step the latch catches; the host reads and clears it.
var clicked := false
## How fast (rad/s) the top hinge last hit its open stop, or came home without catching; the host reads and clears it.
var knocked := 0.0
## The case is held by its lid: the top hinge's angle is then the BASE swinging from it, a panel of `base_lever` (m)
## whose pull is gravity across the base's own face (the frame `g` is given in). The step's `top_spin` is then the
## hand's own turn speeding up, as `spin` is the base's for the trays that still hang from it.
var base_swings := false
var base_lever := 0.06


## `lever_m`: each hinge's pivot-to-centre-of-mass distance, from the back. `friction_share`: static friction as a
## share of gravity's full pull (a jewel hinge is free, a keep case's living hinge stiffer).
func configure(lever_m: Array, open_max_deg := 180.0, friction_share := 0.15, break_accel := 400.0,
		catch_speed := 3.5, kinetic_share := 0.8) -> void:
	latch_speed = catch_speed
	kinetic = kinetic_share
	count = lever_m.size()
	angles.resize(count)
	speeds.resize(count)
	levers.resize(count)
	held.resize(count)
	frictions.resize(count)
	kinetics.resize(count)
	_dir.resize(count)
	_ease.resize(count)
	ajar = 0.0
	springback = 0.0
	for i in count:
		angles[i] = 0.0
		speeds[i] = 0.0
		levers[i] = maxf(float(lever_m[i]), 0.005)
		held[i] = false
		frictions[i] = friction_share
		kinetics[i] = kinetic_share
		_dir[i] = 0.0
		_ease[i] = 0.0
	open_max = deg_to_rad(open_max_deg)
	friction = friction_share
	latch_break = break_accel
	latched = true


func set_hinge_friction(i: int, share: float, kinetic_share: float) -> void:
	frictions[i] = share
	kinetics[i] = kinetic_share


func set_living_hinge(ajar_deg: float, springback_deg: float) -> void:
	ajar = deg_to_rad(ajar_deg)
	springback = deg_to_rad(springback_deg)


func top() -> int:
	return count - 1


func angle_deg(i: int) -> float:
	return rad_to_deg(angles[i])


## Put a hinge at an angle with no speed (a restore, or the hand's angle while held). Opening the top hinge from
## shut lifts the latch; putting it back at 0 does not catch it (only a release does).
func set_angle_deg(i: int, deg: float) -> void:
	var a := clampf(deg_to_rad(deg), 0.0, open_max)
	angles[i] = a
	speeds[i] = 0.0
	if i == top() and a > 0.0:
		latched = false
	_order(i)


## Something in the way has the hinge: it stands at `deg`, at rest. Not a hand's push: the latch does not catch.
func push_to_deg(i: int, deg: float) -> void:
	angles[i] = clampf(deg_to_rad(deg), 0.0, open_max)
	speeds[i] = 0.0
	_ease[i] = 0.0
	_order(i)


## A hand has the hinge (it follows set_held_angle_deg) or has let go of it, at `speed_deg` deg/s.
func set_held(i: int, on: bool, speed_deg := 0.0) -> void:
	held[i] = on
	_ease[i] = 0.0
	if not on:
		speeds[i] = deg_to_rad(speed_deg)
		if i == top() and not latched:
			_ease[i] = -_dir[i] * springback


func set_held_angle_deg(i: int, deg: float, dt: float) -> void:
	var a := clampf(deg_to_rad(deg), 0.0, open_max)
	speeds[i] = (a - angles[i]) / dt if dt > 0.0 else 0.0
	if absf(a - angles[i]) > 0.001:
		_dir[i] = signf(a - angles[i])
	if i == top() and a >= open_max - 1e-4 and angles[i] < open_max - 1e-4:
		knocked = maxf(knocked, speeds[i])               # the hand threw it open against its stop
	angles[i] = a
	if i == top():
		# The hand pushes it home: within SNAP_DEG it catches, and it stays caught as the hand lets go.
		if a <= deg_to_rad(SNAP_DEG):
			if not latched:
				clicked = true
			latched = true
			angles[i] = 0.0
			speeds[i] = 0.0
		else:
			latched = false
	_order(i)


## The pull of gravity on hinge i (rad/s^2), for an effective gravity `g` in the case's frame (gravity less the
## case's own acceleration). Positive opens.
func pull(i: int, g: Vector3) -> float:
	if base_swings and i == top():
		return -3.0 / (4.0 * base_lever) * g.z
	var t := angles[i]
	return 3.0 / (4.0 * levers[i]) * (g.x * -sin(t) + g.z * cos(t))


## True when nothing will move under this gravity: every hinge at rest and held there by its friction or a stop.
func settled(g: Vector3, spin := 0.0, top_spin := NAN) -> bool:
	var spin_t := spin if is_nan(top_spin) else top_spin
	for i in count:
		if held[i] or absf(speeds[i]) > REST_SPEED:
			return false
		if latched:
			if pull(top(), g) + spin_t > latch_break:
				return false
			continue
		if _ease[i] != 0.0:
			return false
		var p := pull(i, g) + (spin_t if i == top() else spin) + _lift(i)
		var lo := angles[i - 1] if i > 0 else 0.0
		var hi := angles[i + 1] if i < top() else open_max
		var stuck := absf(p) <= _static(i) or (p < 0.0 and angles[i] <= lo + 1e-6) \
			or (p > 0.0 and angles[i] >= hi - 1e-6)
		if not stuck:
			return false
	return true


## Advance by dt (s) under an effective gravity `g` (m/s^2) in the case's frame, the case's turn about the hinge
## line speeding up by `spin` (rad/s^2).
func step(dt: float, g: Vector3, spin := 0.0, top_spin := NAN) -> void:
	if count == 0 or dt <= 0.0:
		return
	var t := top()
	var spin_t := spin if is_nan(top_spin) else top_spin
	if latched and not held[t]:
		var opening := pull(t, g) + spin_t
		if opening > latch_break:
			latched = false
	for i in count:
		if held[i]:
			continue
		# A caught lid holds everything under it shut too.
		if latched:
			angles[i] = 0.0
			speeds[i] = 0.0
			continue
		if _ease[i] != 0.0:
			var d := _ease[i] * minf(1.0, dt * 15.0)
			angles[i] = clampf(angles[i] + d, 0.0, open_max)
			_ease[i] = _ease[i] - d if absf(_ease[i] - d) > 1e-4 else 0.0
		var acc := pull(i, g) + (spin_t if i == t else spin) + _lift(i) - DAMPING * speeds[i]
		var fs := _static(i)
		if absf(speeds[i]) <= REST_SPEED and absf(acc) <= fs:
			speeds[i] = 0.0
			continue
		# Kinetic friction opposes the motion (or the impending motion from rest).
		var dir := signf(speeds[i]) if absf(speeds[i]) > REST_SPEED else signf(acc)
		var next := speeds[i] + acc * dt
		var drag := fs * kinetics[i] * dt
		# Friction stops a panel, it never turns it round: one it would reverse this step stops if it can hold it.
		if absf(speeds[i]) > REST_SPEED and absf(next) <= drag and absf(acc) <= fs:
			speeds[i] = 0.0
			continue
		speeds[i] = next - dir * drag
		angles[i] += speeds[i] * dt
	# Coming home: fast enough, the latch catches; slower, it only stops there.
	var arriving := -speeds[t] if not held[t] and not latched and angles[t] <= 0.0 else 0.0
	_resolve()
	if arriving > 0.0:
		angles[t] = 0.0
		speeds[t] = 0.0
		if arriving >= latch_speed:
			latched = true
			clicked = true
		else:
			knocked = maxf(knocked, arriving)


func _static(i: int) -> float:
	return frictions[i] * 3.0 / (4.0 * levers[i]) * G


## A living hinge's push off shut (rad/s^2): at 0 enough to beat its friction and the cover's weight, none at `ajar`.
func _lift(i: int) -> float:
	if i != top() or ajar <= 0.0 or angles[i] >= ajar:
		return 0.0
	return (_static(i) + 2.0 * 3.0 / (4.0 * levers[i]) * G) * (1.0 - angles[i] / ajar)


## Keep the hinges in order and within their stops; two that meet go on together.
func _resolve() -> void:
	for _pass in 2:
		for i in count - 1:
			if angles[i] > angles[i + 1]:
				_knock(i, i + 1)
	for i in count:
		if angles[i] < 0.0:
			angles[i] = 0.0
			if speeds[i] < 0.0:
				speeds[i] = 0.0
		if angles[i] > open_max:
			angles[i] = open_max
			if i == count - 1:
				knocked = maxf(knocked, speeds[i])
			if speeds[i] > 0.0:
				speeds[i] = -speeds[i] * STOP_RESTITUTION
	for i in count - 1:
		if angles[i] > angles[i + 1]:
			angles[i] = angles[i + 1]


func _knock(lo: int, hi: int) -> void:
	if held[lo] and held[hi]:
		return
	# A free tray landing on a panel stiffer than gravity stops against it as against a hand.
	var wall_hi := held[hi] or (frictions[hi] >= 1.0 and frictions[lo] < 1.0 and not held[lo])
	var wall_lo := held[lo] or (frictions[lo] >= 1.0 and frictions[hi] < 1.0 and not held[hi])
	if wall_hi:
		angles[lo] = angles[hi]
		speeds[lo] = minf(speeds[lo], speeds[hi])
	elif wall_lo:
		angles[hi] = angles[lo]
		speeds[hi] = maxf(speeds[hi], speeds[lo])
	else:
		var a := (angles[lo] + angles[hi]) * 0.5
		var v := (speeds[lo] + speeds[hi]) * 0.5
		angles[lo] = a
		angles[hi] = a
		speeds[lo] = v
		speeds[hi] = v


## After a hand moved hinge i: push the others out of its way.
func _order(i: int) -> void:
	for j in range(i + 1, count):
		if angles[j] < angles[j - 1]:
			angles[j] = angles[j - 1]
	for j in range(i - 1, -1, -1):
		if angles[j] > angles[j + 1]:
			angles[j] = angles[j + 1]
