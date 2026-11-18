## ShapeBounds — a collision shape's box in its own frame, worked out on the CPU.
##
## `shape.get_debug_mesh().get_aabb()` gives the same box, but building the debug mesh reads geometry back from the
## GPU: Godot 4.7.2's Shape3D::get_debug_mesh() makes its filled faces as an ArrayMesh and then calls
## surface_get_arrays() on it, which waits for every frame in flight. Measured in the Starlight Arcade (2026-11-18):
## 11-12 ms a call on the desktop, 17 ms on a Quest 3, once for every shape the first time it is asked, which
## held_object_physics alone did 72 times while the room loaded on the headset (performance.md, "Mesh reads").
##
## Exact for the shapes these scripts meet; a shape it does not know falls back to the debug mesh.
class_name ShapeBounds
extends RefCounted


static func aabb(shape: Shape3D) -> AABB:
	if shape is BoxShape3D:
		var size := (shape as BoxShape3D).size
		return AABB(-size * 0.5, size)
	if shape is SphereShape3D:
		var r := (shape as SphereShape3D).radius
		return AABB(Vector3(-r, -r, -r), Vector3(r, r, r) * 2.0)
	if shape is CapsuleShape3D:
		var c := shape as CapsuleShape3D
		return AABB(Vector3(-c.radius, -c.height * 0.5, -c.radius), Vector3(c.radius * 2.0, c.height, c.radius * 2.0))
	if shape is CylinderShape3D:
		var y := shape as CylinderShape3D
		return AABB(Vector3(-y.radius, -y.height * 0.5, -y.radius), Vector3(y.radius * 2.0, y.height, y.radius * 2.0))
	if shape is ConvexPolygonShape3D:
		return _of_points((shape as ConvexPolygonShape3D).points)
	if shape is ConcavePolygonShape3D:
		return _of_points((shape as ConcavePolygonShape3D).get_faces())
	if shape is SeparationRayShape3D:
		return AABB(Vector3.ZERO, Vector3(0, 0, (shape as SeparationRayShape3D).length))
	if shape == null:
		return AABB()
	return shape.get_debug_mesh().get_aabb()


static func _of_points(points: PackedVector3Array) -> AABB:
	if points.is_empty():
		return AABB()
	var box := AABB(points[0], Vector3.ZERO)
	for p in points:
		box = box.expand(p)
	return box
