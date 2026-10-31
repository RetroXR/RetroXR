## DrumSide — a stick striking the SIDE of a Taiko drum: the ka of the rim, brought in from the side.
##
## The rim zones on top are a ring 4 cm wide, and a real drum is struck on its edge as well (a fuchi hit); a stick swung in from the right or the left found no zone to land in, which was "the drum is not
## sensitive at the sides". Pure (no native class, no node of its own): `crossing` takes where the head's points were and are, and the drum's zones as ArcadeDrumstick.zones_of lists them.
##
## A point of the head that goes from OUTSIDE the shell's radius (plus MARGIN: a stick is not a thread) to inside it, at the height of the shell (a little under its bottom, a little over its top), is a ka on
## the half it came in at (left of the drum's middle or right), PROVIDED the move is a sideways one: inward along the drum's face at SPEED, and no more along its normal than across (a head coming DOWN onto the
## face near the edge is the top's hit, not this). Every point it is given is tried (ArcadeDrumstick gives seven, from the tip to the hand): ANY part of the stick strikes the side.
class_name DrumSide
extends RefCounted

## ArcadeDrumstick.KA, restated: this class stands alone.
const KA := &"ka"
## Inward speed at the side (m/s) that counts: gentler than the face's 0.45, a side is brushed.
const SPEED := 0.30
## How far OUT of the shell's wall (m) the head already strikes it.
const MARGIN := 0.015
## How far over the shell's top, and under its bottom (m), the side is struck.
const OVER := 0.05
const UNDER := 0.03
## How far out (m) a head must go before it can strike the side again.
const REARM := 0.03


## The drum's shell (the cylinder the zones stand on), from its zones, or null.
static func shell_of(zones: Array) -> MeshInstance3D:
	for zone: Dictionary in zones:
		var cap := zone["cap"] as MeshInstance3D
		if is_instance_valid(cap) and cap.get_parent() != null:
			var shell := cap.get_parent().get_node_or_null("DrumShell") as MeshInstance3D
			if shell != null and shell.mesh is CylinderMesh:
				return shell
	return null


## The strike, if one of the head's points (`prev` and `now`: the same points, Vector3 in the world, a frame apart, `delta` seconds) went in through the drum's side: `{zone, cap, speed, point}` of the ka zone
## of the half it came in at, the fastest of the points that did; or {}.
static func crossing(prev: Array, now: Array, delta: float, zones: Array) -> Dictionary:
	var shell := shell_of(zones)
	if shell == null or delta <= 0.0 or not shell.is_visible_in_tree():
		return {}
	var cylinder := shell.mesh as CylinderMesh
	var wall := cylinder.top_radius + MARGIN
	var half_height := cylinder.height * 0.5
	var inverse := shell.global_transform.affine_inverse()
	var best := {}
	var best_speed := 0.0
	for i in mini(prev.size(), now.size()):
		var a := inverse * (prev[i] as Vector3)
		var b := inverse * (now[i] as Vector3)
		var ra := Vector2(a.x, a.z).length()
		var rb := Vector2(b.x, b.z).length()
		if not (ra > wall and rb <= wall):
			continue
		var at := a.lerp(b, (ra - wall) / (ra - rb))
		if at.y < -half_height - UNDER or at.y > half_height + OVER:
			continue
		var inward := (ra - rb) / delta
		# Sideways, not down: along the drum's face at least as much as along its normal.
		if inward < SPEED or inward < absf(b.y - a.y) / delta:
			continue
		if inward <= best_speed:
			continue
		var half := 0 if at.x < 0.0 else 1
		for zone: Dictionary in zones:
			if zone["kind"] == KA and int(zone["half"]) == half:
				best = {"zone": zone, "cap": zone["cap"], "speed": inward, "point": i}
				best_speed = inward
				break
	return best


## Are all of the head's points far enough off the drum's side for it to strike it again?
static func clear(points: Array, zones: Array) -> bool:
	var shell := shell_of(zones)
	if shell == null:
		return true
	var inverse := shell.global_transform.affine_inverse()
	var gone := (shell.mesh as CylinderMesh).top_radius + MARGIN + REARM
	for point: Variant in points:
		var local := inverse * (point as Vector3)
		if Vector2(local.x, local.z).length() <= gone:
			return false
	return true
