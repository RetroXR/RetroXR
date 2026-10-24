## GbPaperRim — the highlight round a sheet of paper, not over it.
##
## The house outlines inflate a copy of the mesh along its normals and draw it
## behind (PickableHighlight, WidgetOutline), or put a larger flat sheet behind it
## (Poster). A sheet of paper has no inside: its normals all point out of its
## face, so the inflated copy is a second sheet floating in front of it, and seen
## from behind a sheet "behind" it is in front. Either way the paper went yellow
## all over when it was aimed at or held.
##
## This is a band `rim` wide round the paper's edges, in the paper's own surface
## and following its bend: down both long sides, and across both ends, nothing
## over the paper itself. Seen from either side it is the same rim. Built from the
## paper's centerline: a point, its direction along the paper and the direction
## across it, for each row.
class_name GbPaperRim
extends RefCounted


## A rim round paper `half_width` either side of `centers`, `rim` wide. `along`
## is each row's unit direction along the paper, `across` the one direction it
## lies across in (the paper does not twist), `v` each row's place down the
## picture (0 at one end, 1 at the other) for a material that samples it.
static func build(centers: PackedVector3Array, along: PackedVector3Array, across: Vector3,
		half_width: float, rim: float, v: PackedFloat32Array) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var n := centers.size()
	if n < 2:
		return mesh
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var index := PackedInt32Array()
	# Each row: outer left, inner left, inner right, outer right.
	for i in n:
		var c := centers[i]
		verts.append(c - across * (half_width + rim))
		verts.append(c - across * half_width)
		verts.append(c + across * half_width)
		verts.append(c + across * (half_width + rim))
		uvs.append(Vector2(0.0, v[i]))
		uvs.append(Vector2(0.0, v[i]))
		uvs.append(Vector2(1.0, v[i]))
		uvs.append(Vector2(1.0, v[i]))
	for i in n - 1:
		var r := i * 4
		var s := r + 4
		# The left band and the right band; both faces are drawn.
		index.append_array([r, r + 1, s, r + 1, s + 1, s])
		index.append_array([r + 2, r + 3, s + 2, r + 3, s + 3, s + 2])
	# The two ends: a band across, `rim` out past the end row.
	for end: int in [0, n - 1]:
		var out := -along[0] if end == 0 else along[n - 1]
		var c := centers[end] + out * rim
		var base := verts.size()
		verts.append(c - across * (half_width + rim))
		verts.append(c + across * (half_width + rim))
		var vv := v[end]
		uvs.append(Vector2(0.0, vv))
		uvs.append(Vector2(1.0, vv))
		var row := end * 4
		index.append_array([row, row + 3, base, row + 3, base + 1, base])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = index
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## The rim's own material: flat, its color, both faces.
static func material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = color
	return mat
