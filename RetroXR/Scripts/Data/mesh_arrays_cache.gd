## MeshArraysCache — a mesh's geometry without a GPU read back, after the first time ever.
##
## Godot keeps no CPU copy of a mesh: surface_get_arrays(), get_faces(), create_trimesh_shape() and
## create_convex_shape() all read it back from the GPU, and RenderingDevice.buffer_get_data waits out every frame in
## flight to do it — 11-12 ms a surface on the desktop, 17 ms on a Quest 3 (Starlight Arcade, 2026-11-18;
## performance.md "Mesh reads"). Mesh.get_faces() keeps its triangles for the session only, so every launch paid
## again for every button cap, cover and tray a room's objects read.
##
## Here a surface is read back ONCE: kept in memory while the mesh lives, and on disk under a key that needs no GPU
## (_disk_key), so every later launch reads it from the file. ShadowMerge's proxies and the objects' own
## geometry (footprints, cover extents, tray shapes) share it. Meshes made at run time have no key and are read back
## every launch, as before (memory only).
class_name MeshArraysCache
extends RefCounted

## Where surfaces are kept. The folder ShadowMerge used, so caches it already wrote stay good.
static var cache_dir := "user://shadow_merge_cache"
## Where surfaces came from: read back from the GPU, from the disk cache, written to it.
static var counts := {"readbacks": 0, "disk_hits": 0, "disk_writes": 0}

## "mesh id:surface" -> [WeakRef mesh, PackedVector3Array verts, PackedVector3Array normals, PackedInt32Array indices]
static var _arrays: Dictionary = {}
static var _build_key := ""


## One surface's positions, normals and indices: from memory, the disk, or (only then) the GPU.
static func surface(mesh: Mesh, s: int) -> Array:
	var hit := known(mesh, s)
	return hit if not hit.is_empty() else read_back(mesh, s)


## The surface's positions.
static func vertices(mesh: Mesh, s: int) -> PackedVector3Array:
	return surface(mesh, s)[1]


## What Mesh.get_faces() gives — every triangle of every triangle surface, three positions each — from the cache.
static func faces(mesh: Mesh) -> PackedVector3Array:
	var out := PackedVector3Array()
	if mesh == null:
		return out
	for s in mesh.get_surface_count():
		# Lines and points have no faces (a primitive mesh is triangles throughout).
		if mesh is ArrayMesh and (mesh as ArrayMesh).surface_get_primitive_type(s) != Mesh.PRIMITIVE_TRIANGLES:
			continue
		var arr := surface(mesh, s)
		var verts: PackedVector3Array = arr[1]
		var indices: PackedInt32Array = arr[3]
		var at := out.size()
		out.resize(at + indices.size())
		for k in indices.size():
			out[at + k] = verts[indices[k]]
	return out


## A trimesh collision shape of the mesh, as Mesh.create_trimesh_shape() makes, from the cache.
static func trimesh_shape(mesh: Mesh) -> ConcavePolygonShape3D:
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces(mesh))
	return shape


## One surface's arrays without touching the GPU: from memory or from the disk cache. Empty if only a read back
## would do. (A primitive is no exception: PrimitiveMesh.get_mesh_arrays() is surface_get_arrays(0), a read back.)
static func known(mesh: Mesh, s: int) -> Array:
	var key := "%d:%d" % [mesh.get_instance_id(), s]
	if _arrays.has(key):
		var hit: Array = _arrays[key]
		if (hit[0] as WeakRef).get_ref() == mesh:
			return hit
	var disk_key := _disk_key(mesh, s)
	if disk_key.is_empty():
		return []
	var f := FileAccess.open(_disk_file(disk_key), FileAccess.READ)
	if f == null:
		return []
	var stored: Variant = f.get_var()
	f.close()
	# A file from another key that hashed alike, or one cut short, is a miss: it is rewritten after the read.
	if not (stored is Array) or (stored as Array).size() != 4 or not (stored[0] is String) or stored[0] != disk_key \
			or not (stored[1] is PackedVector3Array) or not (stored[2] is PackedVector3Array) \
			or not (stored[3] is PackedInt32Array):
		return []
	counts["disk_hits"] += 1
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = stored[1]
	arr[Mesh.ARRAY_NORMAL] = stored[2]
	arr[Mesh.ARRAY_INDEX] = stored[3]
	return _keep(mesh, s, arr)


## Read one surface back from the GPU (the stall) and keep it, on disk too if it can be found again next launch.
static func read_back(mesh: Mesh, s: int) -> Array:
	counts["readbacks"] += 1
	var out := _keep(mesh, s, mesh.surface_get_arrays(s))
	var disk_key := _disk_key(mesh, s)
	if not disk_key.is_empty():
		DirAccess.make_dir_recursive_absolute(cache_dir)
		var f := FileAccess.open(_disk_file(disk_key), FileAccess.WRITE)
		if f != null:
			f.store_var([disk_key, out[1], out[2], out[3]])
			f.close()
			counts["disk_writes"] += 1
	return out


## Forget what is in memory and the counts, as a new launch would (the disk cache stays). For the tests.
static func reset() -> void:
	_arrays.clear()
	counts = {"readbacks": 0, "disk_hits": 0, "disk_writes": 0}


## What names a surface across launches without asking the GPU, or "" for a mesh that cannot be found again (one
## made at run time). A primitive is its class and stored properties under this engine. An ArrayMesh is its path
## and what it keeps on the CPU — the surface's lengths and format, the mesh's box — and the build: an export's
## own name, or in a checkout the time of the file the mesh came from, which a re-import changes.
static func _disk_key(mesh: Mesh, s: int) -> String:
	if mesh is PrimitiveMesh:
		return _primitive_key(mesh as PrimitiveMesh)
	var am := mesh as ArrayMesh
	if am == null or am.resource_path.is_empty():
		return ""
	if _build_key.is_empty():
		_build_key = BuildInfo.describe() if OS.has_feature("template") else "dev"
	var path := am.resource_path
	var stamp := _build_key
	if stamp == "dev":
		var file := path.get_slice("::", 0)
		stamp = str(FileAccess.get_modified_time(file)) if FileAccess.file_exists(file) else "0"
	return "%s|%d|%d|%d|%d|%s|%s" % [path, s, am.surface_get_array_len(s), am.surface_get_array_index_len(s),
		am.surface_get_format(s), am.get_aabb(), stamp]


## Everything a primitive's triangles are made from: its class (and script), each stored property but its
## material and the resource's own, and the engine that generates them.
static func _primitive_key(mesh: PrimitiveMesh) -> String:
	var script := mesh.get_script() as Script
	var parts := PackedStringArray(["primitive", Engine.get_version_info()["hash"], mesh.get_class(),
		script.resource_path if script != null else ""])
	for p: Dictionary in mesh.get_property_list():
		var name: String = p["name"]
		if not (int(p["usage"]) & PROPERTY_USAGE_STORAGE) or name == "material" or name.begins_with("resource_") \
				or name == "script":
			continue
		parts.append("%s=%s" % [name, var_to_str(mesh.get(name))])
	return "|".join(parts)


static func _disk_file(disk_key: String) -> String:
	return cache_dir.path_join(disk_key.sha256_text().substr(0, 32) + ".bin")


## Keep one surface's positions, normals and indices (made whole: an unindexed surface gets its own, missing
## normals point up).
static func _keep(mesh: Mesh, s: int, arr: Array) -> Array:
	var key := "%d:%d" % [mesh.get_instance_id(), s]
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX] if arr.size() > Mesh.ARRAY_VERTEX and arr[Mesh.ARRAY_VERTEX] != null \
		else PackedVector3Array()
	var normals: PackedVector3Array = arr[Mesh.ARRAY_NORMAL] if arr.size() > Mesh.ARRAY_NORMAL and arr[Mesh.ARRAY_NORMAL] != null \
		else PackedVector3Array()
	var indices: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr.size() > Mesh.ARRAY_INDEX and arr[Mesh.ARRAY_INDEX] != null \
		else PackedInt32Array()
	if indices.is_empty():
		indices.resize(verts.size())
		for i in verts.size():
			indices[i] = i
	if normals.size() != verts.size():
		normals.resize(verts.size())
		normals.fill(Vector3.UP)
	var out := [weakref(mesh), verts, normals, indices]
	_arrays[key] = out
	if _arrays.size() > 4096:
		for k: String in _arrays.keys():
			if ((_arrays[k] as Array)[0] as WeakRef).get_ref() == null:
				_arrays.erase(k)
	return out
