## A thermal sheet with two longitudinal rails. Stretch and shear constraints
## keep its dimensions; signed bending constraints retain the roll's curvature.
## All constraints distribute their corrections between the participating
## particles. Only an explicitly held row is pinned -- a released sheet has no
## hidden midpoint support. Coordinates and velocities are in the body's frame.
class_name GbThermalRibbon
extends RefCounted

const CURL_RADIUS := 0.065
const MAX_STEP := 1.0 / 240.0
const ITERATIONS := 8
const SKIN := 0.0004
const DRAG := 6.0
const MAX_SPEED := 0.5
const EI := 3.2e-5

var length := 0.0
var width := 0.038
var segments := 0
var positions := PackedVector3Array()
var velocities := PackedVector3Array()
var pin_row := -1
var pin_positions := PackedVector3Array()
## Surface patches: [normal, offset, center, reach, depth] in the body's frame.
var patches: Array = []
var move_speed := 0.0
## Loose-sheet contact recovery belongs to the rigid body, not to a crease.
## The caller applies this local translation after step(). Patches are shifted
## into the recovered body's frame as the solve advances.
var body_shift := Vector3.ZERO
var support_normal := Vector3.ZERO
var _edges: Array[Vector2i] = []
var _rest := PackedFloat64Array()
var _mass := 0.0
var _contact_normals := PackedVector3Array()


func configure(sheet_length: float, sheet_width: float, curvature := 1.0 / CURL_RADIUS) -> void:
	length = sheet_length
	width = sheet_width
	segments = clampi(ceili(length / 0.006), 2, 48)
	var ds := length / segments
	positions.resize((segments + 1) * 2)
	velocities.resize(positions.size())
	velocities.fill(Vector3.ZERO)
	var center := Vector3.ZERO
	# Start with an open arc even for a very long print. Contact, rather than an
	# initially intersecting circle, decides how subsequent turns lie together.
	var turn := clampf(curvature * ds, -(TAU - 0.2) / segments, (TAU - 0.2) / segments)
	for row in segments + 1:
		positions[2 * row] = center + Vector3.RIGHT * width * 0.5
		positions[2 * row + 1] = center - Vector3.RIGHT * width * 0.5
		var angle := (row + 0.5 - segments * 0.5) * turn
		center += Vector3(0.0, cos(angle), -sin(angle)) * ds
	_center()
	_constraints()
	unpin()


## Exact snapshot of a sheet at tear time. Each row contains its two edges.
func restore(state: Dictionary) -> void:
	positions = (state["positions"] as PackedVector3Array).duplicate()
	velocities = (state["velocities"] as PackedVector3Array).duplicate()
	length = float(state["length"])
	width = float(state["width"])
	segments = positions.size() / 2 - 1
	_constraints()
	unpin()


func snapshot() -> Dictionary:
	return {"positions": positions.duplicate(), "velocities": velocities.duplicate(), "length": length, "width": width}


func _constraints() -> void:
	_edges.clear()
	_rest.clear()
	_mass = maxf(length * 0.0057 / positions.size(), 1e-7)
	var ds := length / segments
	for row in segments + 1:
		_edge(2 * row, 2 * row + 1, width)
		if row < segments:
			_edge(2 * row, 2 * row + 2, ds)
			_edge(2 * row + 1, 2 * row + 3, ds)
			_edge(2 * row, 2 * row + 3, sqrt(ds * ds + width * width))
			_edge(2 * row + 1, 2 * row + 2, sqrt(ds * ds + width * width))


func _edge(a: int, b: int, rest: float) -> void:
	_edges.append(Vector2i(a, b))
	_rest.append(rest)


func centers() -> PackedVector3Array:
	var out := PackedVector3Array()
	for row in segments + 1:
		out.append((positions[2 * row] + positions[2 * row + 1]) * 0.5)
	return out


func across() -> PackedVector3Array:
	var out := PackedVector3Array()
	for row in segments + 1:
		out.append((positions[2 * row] - positions[2 * row + 1]).normalized())
	return out


func mean_curvature() -> float:
	var mid := centers()
	var axes := across()
	var total := 0.0
	for i in range(1, segments):
		var a := (mid[i] - mid[i - 1]).normalized()
		var b := (mid[i + 1] - mid[i]).normalized()
		total += atan2(-a.cross(b).dot(axes[i]), a.dot(b))
	return total / maxf(length * float(segments - 1) / segments, 1e-8)


func pin_nearest(at: Vector3) -> void:
	var nearest := INF
	var row := 0
	var mid := centers()
	for i in mid.size():
		var distance := mid[i].distance_squared_to(at)
		if distance < nearest:
			nearest = distance
			row = i
	pin_row = row
	pin_positions = PackedVector3Array([positions[2 * row], positions[2 * row + 1]])


func unpin() -> void:
	pin_row = -1
	pin_positions.clear()


func _weight(i: int) -> float:
	return 0.0 if pin_row >= 0 and i / 2 == pin_row else 1.0 / _mass


## Relative gravity includes the body's acceleration; angular acceleration is
## applied at each particle, so turning the hand excites bending and torsion
## without changing the paper's remembered curl.
func step(delta: float, gravity: Vector3, angular_accel := Vector3.ZERO) -> void:
	body_shift = Vector3.ZERO
	support_normal = Vector3.ZERO
	if delta <= 0.0 or segments == 0:
		return
	if pin_row < 0:
		_recover_body_contacts()
	var before := positions.duplicate()
	var steps := maxi(1, ceili(delta / MAX_STEP))
	var h := delta / steps
	for substep in steps:
		_substep(h, gravity, angular_accel)
	move_speed = 0.0
	for i in positions.size():
		move_speed = maxf(move_speed, positions[i].distance_to(before[i]) / delta)


func _substep(h: float, gravity: Vector3, angular_accel: Vector3) -> void:
	var before := positions.duplicate()
	_contact_normals.resize(positions.size())
	_contact_normals.fill(Vector3.ZERO)
	var ds := length / segments
	var lambda_bend := PackedVector3Array()
	lambda_bend.resize(positions.size())
	for i in positions.size():
		if _weight(i) == 0.0:
			continue
		velocities[i] = (velocities[i] * exp(-DRAG * h) + (gravity - angular_accel.cross(positions[i])) * h).limit_length(MAX_SPEED)
		positions[i] += velocities[i] * h
	var alpha := (ds * ds * ds / EI) / (h * h)
	var bend := 2.0 * ds * sin(ds / CURL_RADIUS * 0.5)
	for iteration in ITERATIONS:
		# Signed curvature, separately on both rails. The local transverse axis
		# follows the sheet, allowing twist instead of locking it to a world plane.
		for row in range(1, segments):
			var transverse := (positions[row * 2] - positions[row * 2 + 1]).normalized()
			for side in 2:
				var b := row * 2 + side
				var a := b - 2
				var c := b + 2
				var normal := (positions[c] - positions[a]).normalized().cross(transverse).normalized()
				var error := positions[a] - 2.0 * positions[b] + positions[c] - normal * bend
				var wa := _weight(a)
				var wb := _weight(b)
				var wc := _weight(c)
				var change := (-error - alpha * lambda_bend[b]) / (wa + 4.0 * wb + wc + alpha)
				lambda_bend[b] += change
				positions[a] += wa * change
				positions[b] -= 2.0 * wb * change
				positions[c] += wc * change
		for e in _edges.size():
			var a := _edges[e].x
			var b := _edges[e].y
			var d := positions[b] - positions[a]
			var distance := d.length()
			var wa := _weight(a)
			var wb := _weight(b)
			if distance < 1e-9 or wa + wb == 0.0:
				continue
			var change := -(distance - _rest[e]) / (wa + wb)
			positions[a] -= d / distance * change * wa
			positions[b] += d / distance * change * wb
		_surface_contacts()
		if pin_row >= 0:
			positions[2 * pin_row] = pin_positions[0]
			positions[2 * pin_row + 1] = pin_positions[1]
	_self_contacts(before)
	# Keep local coordinates centered, but hand contact displacement to the body
	# below. Discarding it drove the recovered sheet straight back into the floor.
	var shift := Vector3.ZERO
	if pin_row < 0:
		shift = _mean(positions) - _mean(before)
		for i in positions.size():
			positions[i] -= shift
	var farthest := 0.0
	for i in positions.size():
		farthest = maxf(farthest, positions[i].distance_to(before[i]))
	var fraction := minf(1.0, MAX_SPEED * h / maxf(farthest, 1e-9))
	for i in positions.size():
		positions[i] = before[i].lerp(positions[i], fraction)
		velocities[i] = (positions[i] - before[i]) / h
		# Depenetration is positional repair, not a new bounce or bending impulse.
		var normal := _contact_normals[i].normalized()
		velocities[i] -= normal * normal.dot(velocities[i])
		support_normal += normal
	if pin_row < 0 and not patches.is_empty():
		shift *= fraction
		body_shift += shift
		_shift_patches(shift)


func _shift_patches(shift: Vector3) -> void:
	for patch: Array in patches:
		patch[1] -= (patch[0] as Vector3).dot(shift)
		patch[2] -= shift


func _recover_body_contacts() -> void:
	# First recover penetration caused by the body's fall as a whole. Letting
	# the individual rails do this buckled the print around its fixed centroid.
	# Subsequent bending still meets the surface in _surface_contacts().
	for patch: Array in patches:
		var normal: Vector3 = patch[0]
		var depth := 0.0
		for p in positions:
			var under := float(patch[1]) + SKIN - normal.dot(p)
			var d := p - (patch[2] as Vector3)
			if under > depth and under < float(patch[4]) and (d - normal * normal.dot(d)).length() < float(patch[3]):
				depth = under
		if depth > 0.0:
			var shift := normal * depth
			body_shift += shift
			support_normal += normal
			_shift_patches(shift)


func _surface_contacts() -> void:
	for i in positions.size():
		if _weight(i) == 0.0:
			continue
		for patch: Array in patches:
			var normal: Vector3 = patch[0]
			var p := positions[i]
			var under := float(patch[1]) + SKIN - normal.dot(p)
			var d := p - (patch[2] as Vector3)
			if under > 0.0 and under < float(patch[4]) and (d - normal * normal.dot(d)).length() < float(patch[3]):
				positions[i] += normal * under
				_contact_normals[i] += normal


func _self_contacts(before: PackedVector3Array) -> void:
	var mid := centers()
	for row in segments:
		var box := AABB(mid[row], Vector3.ZERO).expand(mid[row + 1]).grow(SKIN * 2.0)
		for other in range(row + 2, segments):
			if not box.intersects(AABB(mid[other], Vector3.ZERO).expand(mid[other + 1]).grow(SKIN)):
				continue
			var nearest := Geometry3D.get_closest_points_between_segments(mid[row], mid[row + 1], mid[other], mid[other + 1])
			var d := nearest[0] - nearest[1]
			if d.length_squared() >= SKIN * SKIN * 4.0:
				continue
			var normal := d.normalized()
			if d.length_squared() < 1e-14:
				var old := (before[2 * row] + before[2 * row + 1]) * 0.5
				normal = (old - Geometry3D.get_closest_point_to_segment(old, mid[other], mid[other + 1])).normalized()
			var push := normal * (SKIN * 2.0 - d.length()) * 0.5
			for i in [row * 2, row * 2 + 1, row * 2 + 2, row * 2 + 3]:
				if _weight(i) > 0.0:
					positions[i] += push
			for i in [other * 2, other * 2 + 1, other * 2 + 2, other * 2 + 3]:
				if _weight(i) > 0.0:
					positions[i] -= push


static func _mean(points: PackedVector3Array) -> Vector3:
	var sum := Vector3.ZERO
	for p in points:
		sum += p
	return sum / maxi(points.size(), 1)


func _center() -> void:
	var center := _mean(positions)
	for i in positions.size():
		positions[i] -= center
