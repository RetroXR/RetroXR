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
