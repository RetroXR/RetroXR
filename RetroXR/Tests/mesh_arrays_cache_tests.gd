## MeshArraysCache self-tests -- a mesh's geometry, read back once and then kept, is the geometry Godot gives.
##
##     "$godot" --headless --path RetroXR res://Tests/mesh_arrays_cache_tests.tscn
##
## Exits 0 when everything passes, 1 otherwise. appliance_model, cover_slots and the DVD and CD trays read their
## meshes through the cache instead of get_faces() / create_trimesh_shape() / surface_get_arrays(), each a GPU read
## back every launch (MeshArraysCache says why); what they get must be what those gave. ShadowMerge's own cache cases
## (metering, the disk across launches, a changed mesh) are in shadow_merge_tests.
extends "res://Tests/test_suite.gd"

const CACHE_DIR := "user://mesh_arrays_cache_tests"


func _ready() -> void:
	suite_tag = "mesh_arrays_cache"
	MeshArraysCache.cache_dir = CACHE_DIR
	_remove_dir(CACHE_DIR)
	MeshArraysCache.reset()
	_run()
	_remove_dir(CACHE_DIR)
	_finish()


func _same_faces(got: PackedVector3Array, want: PackedVector3Array) -> bool:
	if got.size() != want.size():
		return false
	for i in got.size():
		if got[i].distance_to(want[i]) > 1e-6:
			return false
	return true


func _run() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(0.3, 0.2, 0.1)
	_ok(_same_faces(MeshArraysCache.faces(box), box.get_faces()), "faces/a primitive's are get_faces()'",
		"%d against %d" % [MeshArraysCache.faces(box).size(), box.get_faces().size()])

	# An ArrayMesh of two triangle surfaces (one indexed, one not) and a line surface between them.
	var am := ArrayMesh.new()
	var prism := PrismMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, prism.get_mesh_arrays())
	var lines := []
	lines.resize(Mesh.ARRAY_MAX)
	lines[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3(1, 0, 0)])
	am.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, lines)
	var tri := []
	tri.resize(Mesh.ARRAY_MAX)
	tri[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(0, 1, 1)])
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, tri)
	_ok(_same_faces(MeshArraysCache.faces(am), am.get_faces()),
		"faces/a mesh of indexed and unindexed triangles and a line surface gives get_faces()'")
	_ok(_same_faces(MeshArraysCache.trimesh_shape(am).get_faces(), am.create_trimesh_shape().get_faces()),
		"faces/its trimesh shape has create_trimesh_shape()'s faces")
	_eq(MeshArraysCache.vertices(am, 2).size(), 3, "vertices/a surface's positions, each once")
	_ok(MeshArraysCache.faces(null).is_empty(), "faces/no mesh has none")

	# Read once, then from memory, then (a new launch: memory gone) from disk, never from the GPU again.
	var kept := ArrayMesh.new()
	kept.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, prism.get_mesh_arrays())
	kept.resource_path = "res://Tests/__mesh_arrays_cache_probe.mesh"
	MeshArraysCache.reset()
	MeshArraysCache.faces(kept)
	MeshArraysCache.faces(kept)
	_eq(int(MeshArraysCache.counts["readbacks"]), 1, "cache/read back once, then kept in memory")
	MeshArraysCache.reset()
	var again := MeshArraysCache.faces(kept)
	_ok(int(MeshArraysCache.counts["readbacks"]) == 0 and int(MeshArraysCache.counts["disk_hits"]) == 1
		and _same_faces(again, kept.get_faces()), "cache/the next launch reads it from disk, the same faces",
		str(MeshArraysCache.counts))


func _remove_dir(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
