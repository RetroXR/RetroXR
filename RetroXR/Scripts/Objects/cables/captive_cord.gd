## CaptiveCord — the two things a hardwired cord needs that a pluggable one does not: its
## length set to the machine's, and a first lay that follows a route authored for where
## it rests rather than the straight line VerletRope draws between its anchors.
##
## Shared by every device a machine can be WIRED to (RetroController for a Famicom's
## pads, LightGun for an arcade cabinet's guns). See RetroSystemModel.captive_cord_routes
## for why a stowed cord needs a route: a pad or a gun at rest sits a few centimetres from
## the hole its metre of cord leaves by, so a straight lay packs the particles into a
## fraction of their rest length and the solver answers with standing arches.
class_name CaptiveCord
extends RefCounted


## Resize the cord to `length`, before _init_points lays the particles out.
##
## Segment COUNT carries the length; the segment length is then nudged by well under a
## percent so the total is exact instead of rounding to a whole segment. Doing it the
## other way -- same count, longer segments -- would move the boot taper and the minimum
## bend radius, which are tuned in millimetres. A `length` of 0 keeps what the scene ships.
static func resize(rope: VerletRope, length: float) -> void:
	if rope == null or length <= 0.0:
		return
	var seg: float = rope.segment_length
	if seg <= 0.0:
		return
	var count: int = maxi(2, int(round(length / seg)))
	rope.segment_count = count
	rope.segment_length = length / float(count)


## Put the cord on `route` (world space) instead of the straight line _init_points drew.
## The route is resampled at equal arc length onto the particles the rope already has, so
## a route about as long as the rope starts it a rest length apart. False when there is
## nothing to lay or the rope refused it.
static func lay(rope: VerletRope, route: PackedVector3Array) -> bool:
	if route.size() < 2 or rope == null:
		return false
	var count: int = rope.point_count()
	if count < 2:
		return false
	var spans := PackedFloat32Array()
	var total := 0.0
	for i in range(1, route.size()):
		var d: float = route[i].distance_to(route[i - 1])
		spans.append(d)
		total += d
	if total <= 0.0:
		return false
	var points := PackedVector3Array()
	var span := 0
	var walked := 0.0
	for k in count:
		var want: float = total * float(k) / float(count - 1)
		while span < spans.size() - 1 and walked + spans[span] < want:
			walked += spans[span]
			span += 1
		var t: float = 0.0 if spans[span] <= 0.0 else clampf((want - walked) / spans[span], 0.0, 1.0)
		points.append(route[span].lerp(route[span + 1], t))
	return rope.restore_points(points)


## The length of a polyline, for sizing a route against its cord.
static func polyline_length(route: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, route.size()):
		total += route[i].distance_to(route[i - 1])
	return total


## A cord that hangs from `boss` down the front of a cabinet in a U and comes back up to `entry`, as long as `length` (the lay a stowed cord is started on: see the head of this file).
## `boss` is where the cord leaves what it is tied to, `entry` where it goes into the cabinet, both in one frame in which +Y is up and `front` (a unit vector) is horizontal and points away from
## the cabinet's face toward the player: the cord goes down `STAND_OFF` in front of the face, turns at the bottom and rises against it. How deep the U goes is solved against `length`: the
## floor is as low as it goes (a cord longer than that lies on the floor in slack), a U hardly deeper than the entry is as short as it gets (a cord shorter than that is the shortest, and the
## rope's own length decides the rest).
const STAND_OFF := 0.04
const HANG_FLOOR := 0.03


static func hanging_route(boss: Vector3, entry: Vector3, length: float, front: Vector3 = Vector3.BACK) -> PackedVector3Array:
	var lo := HANG_FLOOR
	var hi := minf(boss.y, entry.y) - 0.10
	hi = maxf(hi, lo + 0.01)
	if polyline_length(_hanging_route_at(boss, entry, front, lo)) <= length:
		return _hanging_route_at(boss, entry, front, lo)
	if polyline_length(_hanging_route_at(boss, entry, front, hi)) >= length:
		return _hanging_route_at(boss, entry, front, hi)
	for _i in 24:
		var mid := (lo + hi) * 0.5
		# The higher the bottom of the U, the shorter the cord it uses.
		if polyline_length(_hanging_route_at(boss, entry, front, mid)) > length:
			lo = mid
		else:
			hi = mid
	return _hanging_route_at(boss, entry, front, (lo + hi) * 0.5)


static func _hanging_route_at(boss: Vector3, entry: Vector3, front: Vector3, bottom: float) -> PackedVector3Array:
	var out := front * STAND_OFF
	var down_at := Vector3(boss.x, 0.0, boss.z) + out
	var up_at := Vector3(entry.x, 0.0, entry.z) + front * 0.012
	var mid_at := (down_at + up_at) * 0.5
	var pts := PackedVector3Array([
		boss,
		Vector3(boss.x, boss.y - 0.03, boss.z) + out * 0.5,
		Vector3(down_at.x, boss.y - 0.08, down_at.z),
		Vector3(down_at.x, bottom + 0.06, down_at.z),
		Vector3(mid_at.x, bottom, mid_at.z),
		Vector3(up_at.x, bottom + 0.06, up_at.z),
	])
	if entry.y - 0.05 > bottom + 0.06:
		pts.append(Vector3(up_at.x, entry.y - 0.05, up_at.z))
	pts.append(Vector3(entry.x, entry.y, entry.z) + front * 0.004)
	pts.append(entry)
	return pts
