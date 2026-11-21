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
## What it takes to spring the latch (rad/s^2).
var latch_break := 400.0
## How fast (rad/s) a free swing must come home to catch the latch.
var latch_speed := 3.5
var latched := true
## Set on the step the latch catches; the host reads and clears it.
var clicked := false


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
	for i in count:
		angles[i] = 0.0
		speeds[i] = 0.0
		levers[i] = maxf(float(lever_m[i]), 0.005)
		held[i] = false
	open_max = deg_to_rad(open_max_deg)
	friction = friction_share
	latch_break = break_accel
	latched = true


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


## A hand has the hinge (it follows set_held_angle_deg) or has let go of it, at `speed_deg` deg/s.
func set_held(i: int, on: bool, speed_deg := 0.0) -> void:
	held[i] = on
	if not on:
		speeds[i] = deg_to_rad(speed_deg)


func set_held_angle_deg(i: int, deg: float, dt: float) -> void:
	var a := clampf(deg_to_rad(deg), 0.0, open_max)
	speeds[i] = (a - angles[i]) / dt if dt > 0.0 else 0.0
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
	var t := angles[i]
	return 3.0 / (4.0 * levers[i]) * (g.x * -sin(t) + g.z * cos(t))


## True when nothing will move under this gravity: every hinge at rest and held there by its friction or a stop.
func settled(g: Vector3, spin := 0.0) -> bool:
	for i in count:
		if held[i] or absf(speeds[i]) > REST_SPEED:
			return false
		if latched:
			if pull(top(), g) + spin > latch_break:
				return false
			continue
		var p := pull(i, g) + spin
		var lo := angles[i - 1] if i > 0 else 0.0
		var hi := angles[i + 1] if i < top() else open_max
		var stuck := absf(p) <= _static(i, g) or (p < 0.0 and angles[i] <= lo + 1e-6) \
			or (p > 0.0 and angles[i] >= hi - 1e-6)
		if not stuck:
			return false
	return true


## Advance by dt (s) under an effective gravity `g` (m/s^2) in the case's frame, the case's turn about the hinge
## line speeding up by `spin` (rad/s^2).
func step(dt: float, g: Vector3, spin := 0.0) -> void:
	if count == 0 or dt <= 0.0:
		return
	var t := top()
	if latched and not held[t]:
		var opening := pull(t, g) + spin
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
		var acc := pull(i, g) + spin - DAMPING * speeds[i]
		var fs := _static(i, g)
		if absf(speeds[i]) <= REST_SPEED and absf(acc) <= fs:
			speeds[i] = 0.0
			continue
		# Kinetic friction opposes the motion (or the impending motion from rest).
		var dir := signf(speeds[i]) if absf(speeds[i]) > REST_SPEED else signf(acc)
		acc -= dir * fs * kinetic
		speeds[i] += acc * dt
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


func _static(i: int, _g: Vector3) -> float:
	return friction * 3.0 / (4.0 * levers[i]) * G


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
			if speeds[i] > 0.0:
				speeds[i] = -speeds[i] * STOP_RESTITUTION
	for i in count - 1:
		if angles[i] > angles[i + 1]:
			angles[i] = angles[i + 1]


func _knock(lo: int, hi: int) -> void:
	if held[lo] and held[hi]:
		return
	if held[hi]:
		angles[lo] = angles[hi]
		speeds[lo] = minf(speeds[lo], speeds[hi])
	elif held[lo]:
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
