## DoorModelSplit — take a door model that is ONE mesh (frame, leaf and knob as
## surfaces of it, which is how most door models come) apart at run time, so VRDoor
## can swing the leaf and turn the knob without anyone re-exporting the asset.
##
## Surfaces are named by their surface name or their material's name, whichever the
## model carries. The knob's surfaces are split once more, by TRIANGLE: what lies
## wholly outside the leaf's two faces is the knob (it turns), what is in the leaf's
## thickness (the latch bolt in its edge, the spindle through the bore) stays on the
## leaf — a model's "knob" material is usually the whole lockset, bolt and all.
##
## Pure and static: nothing here touches the scene tree.
class_name DoorModelSplit
extends RefCounted

## A surface's index by name, or -1.
static func find_surface(mesh: Mesh, surface_name: String) -> int:
	if mesh == null or surface_name.is_empty():
		return -1
	for i in mesh.get_surface_count():
		if mesh is ArrayMesh and (mesh as ArrayMesh).surface_get_name(i) == surface_name:
			return i
		var mat := mesh.surface_get_material(i)
		if mat != null and mat.resource_name == surface_name:
			return i
	return -1


## The indices of `names` that the mesh has; any it lacks are appended to `missing`.
static func find_surfaces(mesh: Mesh, names: PackedStringArray,
		missing: PackedStringArray) -> Array[int]:
	var out: Array[int] = []
	for n in names:
		var i := find_surface(mesh, n)
		if i < 0:
			missing.append(n)
		elif not out.has(i):
			out.append(i)
	return out


## The bounds of some surfaces' vertices, seen through `xf`. An empty AABB (size 0)
## when there are none.
static func bounds(mesh: Mesh, surfaces: Array[int], xf: Transform3D) -> AABB:
	var ab := AABB()
	var first := true
	for i in surfaces:
		var verts: PackedVector3Array = mesh.surface_get_arrays(i)[Mesh.ARRAY_VERTEX]
		for v in verts:
			var p := xf * v
			if first:
				ab = AABB(p, Vector3.ZERO)
				first = false
			else:
				ab = ab.expand(p)
	return ab


## Split a triangle surface in two by where its triangles lie along `xf`'s Z: the
## triangles with EVERY vertex outside [z_min, z_max] first, the rest second, each
## as an index array over the surface's own vertices.
static func split_outside_slab(mesh: Mesh, surface: int, xf: Transform3D,
		z_min: float, z_max: float) -> Array[PackedInt32Array]:
	var arrays := mesh.surface_get_arrays(surface)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var index: PackedInt32Array = _indices(arrays)
	var outside := PackedByteArray()
	outside.resize(verts.size())
	for k in verts.size():
		var z := (xf * verts[k]).z
		outside[k] = 1 if (z < z_min or z > z_max) else 0
	var outer := PackedInt32Array()
	var inner := PackedInt32Array()
	for t in range(0, index.size() - 2, 3):
		var a := index[t]
		var b := index[t + 1]
		var c := index[t + 2]
		var dst := outer if outside[a] == 1 and outside[b] == 1 and outside[c] == 1 else inner
		dst.append(a)
		dst.append(b)
		dst.append(c)
	return [outer, inner]


## A triangle surface's connected PIECES (vertices welded by position, to 0.1 mm, so
## a piece's split normals and seams do not cut it), each as
## {"tris": PackedInt32Array (an index array), "box": AABB through `xf`}. A lockset
## is several parts in one material: the knobs and their roses, the latch bolt, the
## faceplate on the edge and its screws; what moves is a whole part, never part of one.
static func pieces(mesh: Mesh, surface: int, xf: Transform3D) -> Array[Dictionary]:
	var arrays := mesh.surface_get_arrays(surface)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var index: PackedInt32Array = _indices(arrays)
	var parent := PackedInt32Array()
	parent.resize(verts.size())
	for k in verts.size():
		parent[k] = k
	var seen := {}
	for k in verts.size():
		var key := (verts[k] * 10000.0).round()
		if seen.has(key):
			_union(parent, k, seen[key])
		else:
			seen[key] = k
	for t in range(0, index.size() - 2, 3):
		_union(parent, index[t], index[t + 1])
		_union(parent, index[t], index[t + 2])
	var by_root := {}
	for t in range(0, index.size() - 2, 3):
		var r := _find(parent, index[t])
		if not by_root.has(r):
			by_root[r] = {"tris": PackedInt32Array(), "box": AABB(xf * verts[index[t]], Vector3.ZERO)}
		var piece: Dictionary = by_root[r]
		var tris: PackedInt32Array = piece["tris"]
		var box: AABB = piece["box"]
		for j in 3:
			tris.append(index[t + j])
			box = box.expand(xf * verts[index[t + j]])
		piece["tris"] = tris
		piece["box"] = box
	var out: Array[Dictionary] = []
	for r in by_root:
		out.append(by_root[r])
	return out


static func _find(parent: PackedInt32Array, a: int) -> int:
	while parent[a] != a:
		parent[a] = parent[parent[a]]
		a = parent[a]
	return a


static func _union(parent: PackedInt32Array, a: int, b: int) -> void:
	var ra := _find(parent, a)
	var rb := _find(parent, b)
	if ra != rb:
		parent[ra] = rb


## Copy one surface of `mesh` onto `dst` (only `triangles` of it, when given), with
## its material — `material` instead, when a node overrode it.
static func append_surface(dst: ArrayMesh, mesh: Mesh, surface: int,
		material: Material = null, triangles: PackedInt32Array = PackedInt32Array()) -> void:
	if mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
		push_warning("[Door] surface %d is not triangles: copied whole" % surface)
		triangles = PackedInt32Array()
	var arrays := mesh.surface_get_arrays(surface)
	if not triangles.is_empty():
		arrays[Mesh.ARRAY_INDEX] = triangles
	# A custom channel's array is only readable with its format, which lives in the
	# surface's flags, not in the array: copy those bits or the surface is refused.
	var fmt: int = mesh.surface_get_format(surface)
	var flags := 0
	for c in 4:
		var shift: int = Mesh.ARRAY_FORMAT_CUSTOM_BASE + c * Mesh.ARRAY_FORMAT_CUSTOM_BITS
		flags |= fmt & (Mesh.ARRAY_FORMAT_CUSTOM_MASK << shift)
	dst.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	var s := dst.get_surface_count() - 1
	dst.surface_set_material(s, material if material != null else mesh.surface_get_material(surface))
	if mesh is ArrayMesh:
		dst.surface_set_name(s, (mesh as ArrayMesh).surface_get_name(surface))


static func _indices(arrays: Array) -> PackedInt32Array:
	var index: Variant = arrays[Mesh.ARRAY_INDEX]
	if index is PackedInt32Array and not (index as PackedInt32Array).is_empty():
		return index
	var n := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var out := PackedInt32Array()
	out.resize(n)
	for k in n:
		out[k] = k
	return out
