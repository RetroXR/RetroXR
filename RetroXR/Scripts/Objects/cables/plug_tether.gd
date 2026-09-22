## How the owner of a lead keeps a LOOSE plug within its cord's reach.
##
## A pinned rope particle has inverse mass zero, so a plug drives its rope and the
## rope never carries a plug's weight (docs/dev/rope.md). Whatever owns the cord
## closes that loop with a hard tether: past the cord's reach, the plug is reeled
## back in. Every owner used to write that for itself — twelve copies across the
## consoles, controllers and peripherals, and four more with their own twist
## (RfSwitch, Antenna, PowerStrip, CompositeCable) — and the copies disagreed on the
## three things that matter:
##
##   * SWEPT, not a position write. A write bypasses collision; it rescued nothing
##     the physics server did not happen to rescue, and it could carry a plug
##     through a partition. The move slides along whatever it meets.
##   * It KILLS the velocity it undoes. Without that a plug hanging past its reach
##     fell a tick's worth under gravity, was hauled back, and fell again for ever;
##     neither it nor its cord ever slept.
##   * It leaves SLACK and holds the plug AT the slack's edge. The rope's solver
##     leaves a taut cord a few millimetres long, and a clamp at exactly the reach
##     dragged a resting plug back into its neighbour every tick, inside the rope's
##     0.5 mm wake threshold, under a cord that never woke to let it go.
##
## Callers decide WHICH end is loose (a held plug is somebody else's to move) and
## which point on the plug the reach is measured from — the cord boss for a lead
## whose reach is boss to boss, the origin for the controllers whose reach was
## always measured that way. A body on the end of cords that must be HAULED rather
## than reeled (a switch box, a cabinet) is CableHaul's job, not this.
class_name PlugTether
extends RefCounted

## How far past its reach a plug may lie before it is reeled in, metres.
const SLACK := 0.005


## Reel `plug` in so that `point`, a point on it in world space, lies no further
## than `reach` + SLACK from `from`. Returns whether it had to move.
static func reel_in(plug: RigidBody3D, point: Vector3, from: Vector3, reach: float) -> bool:
	if plug == null or not is_instance_valid(plug) or reach <= 0.0:
		return false
	var away := point - from
	var d := away.length()
	if d <= reach + SLACK or d < 0.0001:
		return false
	var motion := away * ((reach + SLACK - d) / d)
	var hit := plug.move_and_collide(motion)
	if hit != null:
		plug.move_and_collide(hit.get_remainder().slide(hit.get_normal()))
	var inward := motion.normalized()
	var outward := -inward.dot(plug.linear_velocity)
	if outward > 0.0:
		plug.linear_velocity += inward * outward
	return true
