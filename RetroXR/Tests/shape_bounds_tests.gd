## ShapeBounds self-tests -- a collision shape's box, worked out on the CPU, is the box the debug mesh gave.
##
##     "$godot" --headless --path RetroXR res://Tests/shape_bounds_tests.tscn
##
## Exits 0 when everything passes, 1 otherwise. held_object_physics, scroll_lock_capture and tv_resize asked
## `shape.get_debug_mesh().get_aabb()`, which reads the filled debug faces back from the GPU (ShapeBounds says why);
## they now ask ShapeBounds.aabb(), which must answer the same box for every shape they meet.
extends "res://Tests/test_suite.gd"

const EPS := 0.001


func _ready() -> void:
	suite_tag = "shape_bounds"
	_run()
	_finish()


func _same(shape: Shape3D, what: String) -> void:
	var want := shape.get_debug_mesh().get_aabb()
	var got := ShapeBounds.aabb(shape)
	var ok := got.position.distance_to(want.position) < EPS and got.size.distance_to(want.size) < EPS
	_ok(ok, "bounds/%s is the debug mesh's box" % what, "got %s, debug mesh %s" % [got, want])


func _run() -> void:
	for size: Vector3 in [Vector3(1, 1, 1), Vector3(0.3, 1.2, 0.05)]:
		var box := BoxShape3D.new()
		box.size = size
		_same(box, "a box %s" % size)
	for r: float in [0.5, 0.02]:
		var sphere := SphereShape3D.new()
		sphere.radius = r
		_same(sphere, "a sphere of radius %s" % r)
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.1
	capsule.height = 0.7
	_same(capsule, "a capsule")
	var cylinder := CylinderShape3D.new()
	cylinder.radius = 0.25
	cylinder.height = 0.4
	_same(cylinder, "a cylinder")
	var hull := ConvexPolygonShape3D.new()
	hull.points = PackedVector3Array([Vector3(-0.2, 0, 0.1), Vector3(0.3, 0.5, -0.2), Vector3(0.1, -0.4, 0.6),
		Vector3(-0.1, 0.2, -0.3), Vector3(0.05, 0.1, 0.05)])
	_same(hull, "a convex hull off its origin")
	var faces := ConcavePolygonShape3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(0.4, 0.3, 0.9)
	faces.set_faces(prism.get_faces())
	_same(faces, "a triangle-mesh shape")
	_eq(ShapeBounds.aabb(null), AABB(), "bounds/no shape is an empty box")
	_eq(ShapeBounds.aabb(ConvexPolygonShape3D.new()), AABB(), "bounds/a hull with no points is an empty box")
