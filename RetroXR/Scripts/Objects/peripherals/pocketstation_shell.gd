@tool
## PocketStationShell — one slab of the PocketStation's body, built from its real outline.
##
## The unit is a "tombstone": a semicircular top as wide as the body, straight sides, and
## rounded corners at the card end. Boxes and cylinders cannot make that for the LID, whose
## straight part (13.6 mm from the arc's centre to the hinge) is shorter than the arc's
## radius (20.5 mm): a whole cylinder pokes out past the hinge as a puck. So the outline is
## extruded here instead, flat caps and a smooth wall, and the scene keeps every number.
##
## Lying flat in the model's frame: the slab spans `thickness` along Y about this node, the
## outline lies in X/Z, its arc at -Z (the infrared end).
class_name PocketStationShell
extends MeshInstance3D

## Body width in metres; the top arc's radius is half of it.
@export var width := 0.042:
	set(v):
		width = v
		_rebuild()
## Z of the top of the arc (the infrared end).
@export var z_top := -0.032:
	set(v):
		z_top = v
		_rebuild()
## Z of the straight bottom edge (the card end for the base, the hinge for the lid).
@export var z_bottom := 0.032:
	set(v):
		z_bottom = v
		_rebuild()
## Slab thickness along Y, centred on this node.
@export var thickness := 0.0075:
	set(v):
		thickness = v
		_rebuild()
## Radius of the two bottom corners. Kept above zero so the wall's normals stay smooth.
@export var corner_radius := 0.003:
	set(v):
		corner_radius = v
		_rebuild()
## Segments in the top arc; each bottom corner gets a quarter as many.
@export var arc_segments := 48:
	set(v):
		arc_segments = maxi(8, v)
		_rebuild()
## The slab's material, set on the built mesh's surface.
@export var material: Material:
	set(v):
		material = v
		_rebuild()


func _ready() -> void:
	_rebuild()


## The closed outline in X/Z, wound one way round, with the outward normal at each point.
func outline() -> Array:
	var a := width * 0.5
	var zc := z_top + a
	var rc := clampf(corner_radius, 0.0002, a * 0.5)
	var pts: Array[Vector2] = []
	# Top arc, from the right side (angle 0) over the top to the left side (angle PI).
	for i in arc_segments + 1:
		var t := PI * float(i) / float(arc_segments)
		pts.append(Vector2(a * cos(t), zc - a * sin(t)))
	# Down the left side to the bottom-left corner, round it, across, round the right one.
	var corner_steps := maxi(2, arc_segments / 4)
	for i in corner_steps + 1:
		var t := PI + PI * 0.5 * float(i) / float(corner_steps)   # PI .. 1.5 PI
		pts.append(Vector2(-a + rc + rc * cos(t), z_bottom - rc - rc * sin(t)))
	for i in corner_steps + 1:
		var t := PI * 1.5 + PI * 0.5 * float(i) / float(corner_steps)   # 1.5 PI .. 2 PI
		pts.append(Vector2(a - rc + rc * cos(t), z_bottom - rc - rc * sin(t)))
	var centre := Vector2(0.0, (z_top + z_bottom) * 0.5)
	var out: Array = []
	var n := pts.size()
	for i in n:
		var tangent := pts[(i + 1) % n] - pts[(i - 1 + n) % n]
		var normal := Vector2(tangent.y, -tangent.x).normalized()
		if normal.dot(pts[i] - centre) < 0.0:
			normal = -normal
		out.append([pts[i], normal])
	return out


func _rebuild() -> void:
	if not is_inside_tree() and not Engine.is_editor_hint():
		return
	if z_bottom - z_top <= width * 0.5:
		push_warning("[PocketStation] shell %s: length %.4f m leaves no straight part below an arc of radius %.4f m" % [
			name, z_bottom - z_top, width * 0.5])
	var ring := outline()
	var h := thickness * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var centre := Vector3(0.0, 0.0, (z_top + z_bottom) * 0.5)
	var n := ring.size()
	for i in n:
		var p0: Vector2 = ring[i][0]
		var p1: Vector2 = ring[(i + 1) % n][0]
		var n0: Vector2 = ring[i][1]
		var n1: Vector2 = ring[(i + 1) % n][1]
		# Caps: a fan from the centre (the outline is convex).
		_tri(st, centre + Vector3(0, h, 0), Vector3(p0.x, h, p0.y), Vector3(p1.x, h, p1.y),
			Vector3.UP, Vector3.UP, Vector3.UP)
		_tri(st, centre - Vector3(0, h, 0), Vector3(p0.x, -h, p0.y), Vector3(p1.x, -h, p1.y),
			Vector3.DOWN, Vector3.DOWN, Vector3.DOWN)
		# Wall: smooth, its normal the outline's.
		var w0 := Vector3(n0.x, 0, n0.y)
		var w1 := Vector3(n1.x, 0, n1.y)
		_tri(st, Vector3(p0.x, -h, p0.y), Vector3(p1.x, -h, p1.y), Vector3(p1.x, h, p1.y), w0, w1, w1)
		_tri(st, Vector3(p0.x, -h, p0.y), Vector3(p1.x, h, p1.y), Vector3(p0.x, h, p0.y), w0, w1, w0)
	var built := st.commit()
	if material != null:
		built.surface_set_material(0, material)
	mesh = built


## One triangle, wound so it faces along `face` (Godot's front faces are clockwise).
func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3) -> void:
	var face := (na + nb + nc)
	if (c - a).cross(b - a).dot(face) < 0.0:
		var t := b
		b = c
		c = t
		var tn := nb
		nb = nc
		nc = tn
	st.set_normal(na)
	st.add_vertex(a)
	st.set_normal(nb)
	st.add_vertex(b)
	st.set_normal(nc)
	st.add_vertex(c)
