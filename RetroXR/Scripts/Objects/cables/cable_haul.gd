## How a cord drags the thing on the end of it.
##
## A pinned rope particle has inverse mass zero, so a body drives the rope and the rope
## can never drive a body. Everything that hangs off a cord therefore has to close that
## loop itself: pick up one end, walk away, and without this the far end sits exactly
## where it was while the cable stretches without limit.
##
## ── Why it is a haul and not a move ─────────────────────────────────────────
## Adding the slack straight onto the far body's global_position is a pure translation:
## it tracks the held end perfectly, at a fixed attitude, like a prop being slid along a
## table. A lump on the end of a cord does not do that — the cord pulls at the boss where
## it leaves the case, which is nowhere near the centre of mass, so the thing turns as it
## is dragged and hangs from whichever lead is taut.
##
## So the slack becomes an IMPULSE APPLIED AT THE BOSS. Godot's solver turns the offset
## into torque against the body's own inertia, which is what buys the droop and the
## swing, and gravity does the rest for free. The impulse is scaled by mass, so the
## response is the same on an 80 g switch box and a 600 g speaker cabinet.
##
## The hard positional clamp is kept, but only past LIMIT — far enough out that it never
## fires during ordinary dragging and only catches a hand moving faster than the impulse
## can answer, which is the case the bound exists for. A clamp rather than a spring
## there, for the reason CompositeCable records: over-extension reaches a metre or more,
## and a spring stiff enough to drag a body at that distance launches it.
##
## Used by RfSwitch (its grey box, hauled by two leads at once) and SpeakerPair (the
## cabinet that is not in your hand).
class_name CableHaul
extends RefCounted

## Impulse per metre of over-extension, per kilogram.
const GAIN := 14.0

## How far past the rest length the body may get before the positional backstop fires,
## as a multiple of that length.
const LIMIT := 1.25


## Pull `body` toward `to` by however much its cord is over-extended.
##
## `at` is where the cord leaves the body and `to` the far end of it, both in world
## space; `reach` is the cord's rest length. Only the far end's own attitude is touched —
## a held body is somebody else's to move, so callers decide WHICH end is loose before
## calling. A frozen body ignores impulses outright.
##
## Returns the positional backstop, which the caller adds to the body's global_position.
## It is returned rather than applied so that a body on the end of two cords resolves
## both before it moves: applying them one at a time lets two over-extended leads shove
## it back and forth every frame, where summing them leaves a body stretched between two
## anchors simply where it is, which is what a real one does.
static func haul(body: RigidBody3D, at: Vector3, to: Vector3, reach: float) -> Vector3:
	if not is_instance_valid(body):
		return Vector3.ZERO
	var away := to - at
	var d := away.length()
	if d <= reach or d < 0.0001:
		return Vector3.ZERO
	var slack := away * ((d - reach) / d)
	# At the boss, not at the origin — the offset is the whole point.
	body.apply_impulse(slack * (body.mass * GAIN), at - body.global_position)
	if d <= reach * LIMIT:
		return Vector3.ZERO
	# Only the overshoot PAST the limit is taken out by hand, so the impulse still does
	# the visible work and this never reads as a snap.
	return slack * ((d - reach * LIMIT) / (d - reach))
