## Contacts crossed between rendered poses. The periodic room rays discover
## nearby surfaces; these rays catch fast movement through a surface, even when
## the next pose is already beyond the ordinary patch's depth cutoff.
class_name GbPaperSweep
extends RefCounted

var _previous := PackedVector3Array()
## [world position, world normal, recovery depth, collider RID]. Kept until the paper clears
## the surface or moves past its edge; recovery can take more than one frame.
var hits: Array = []


func reset() -> void:
	_previous.clear()
	hits.clear()


func update(space: PhysicsDirectSpaceState3D, points: PackedVector3Array,
		exclude: Array[RID], reach: float) -> void:
	if _previous.size() == points.size():
		for i in points.size():
			if _previous[i].distance_squared_to(points[i]) < 1e-10:
				continue
			var query := PhysicsRayQueryParameters3D.create(_previous[i], points[i])
			query.exclude = exclude
			var hit := space.intersect_ray(query)
			if hit.is_empty():
				continue
			var at: Vector3 = hit["position"]
			var normal: Vector3 = hit["normal"]
			# Only entry from the front; leaving a surface does not pin paper to it.
			if normal.dot(points[i] - _previous[i]) >= 0.0:
				continue
			var known := false
			for old: Array in hits:
				# Recovery through a thin solid leaves through its opposite face.
				# Catching that face would trap paper between two opposing patches.
				if old[3] == hit["rid"] and (old[1] as Vector3).dot(normal) < -0.5:
					known = true
					break
				if (old[0] as Vector3).distance_to(at) < reach * 0.5 and (old[1] as Vector3).dot(normal) > 0.99:
					known = true
					break
			if not known:
				hits.append([at, normal, 0.0, hit["rid"]])
	_previous = points.duplicate()
	for i in range(hits.size() - 1, -1, -1):
		var at: Vector3 = hits[i][0]
		var normal: Vector3 = hits[i][1]
		var depth := -INF
		for p in points:
			var d := p - at
			var under := -normal.dot(d)
			if (d + normal * under).length() <= reach:
				depth = maxf(depth, under)
		if depth < -GbPrinterStrip.SKIN:
			hits.remove_at(i)
		else:
			hits[i][2] = maxf(GbPrinterStrip.PATCH_DEPTH, depth + GbPrinterStrip.SKIN * 2.0)
