## PosterConform — wraps a poster's sheet onto the real shape of what it is stuck to.
##
## WHY IT SAMPLES THE VISUAL MESH AND NOT THE COLLIDER. Walls are honest — a
## StaticBody3D whose BoxShape3D IS the wall — but most furniture is a GLB with one
## crude box around it, and several loose props carry no collider at all. A poster
## conformed to a CRT's box collider is a flat poster floating in front of the CRT,
## which is the exact case this mode exists for.
##
## So the target's visible meshes are cooked into a throwaway trimesh body on a
## private layer, and the grid is raycast against THAT. Jolt is then the broadphase;
## the alternative is a per-triangle loop in GDScript over a 15k-triangle shell for
## every one of a few hundred grid points.
##
## Walls skip all of it: a body in the "poster_flat" group means "this collider is
## the surface", and the sheet stays flat. That is author intent because it cannot
## be inferred — a box that IS the shape and a box that LIES about the shape look
## identical from here. It also matters for cost: a room's walls are all one
## StaticBody3D, so cooking "the target" there would cook the entire room.
class_name PosterConform
extends RefCounted

## Private layer for the sampling body — nothing else in the project uses 16.
const SAMPLE_LAYER := 1 << 15
## Grid density in samples per metre, and the per-axis clamp. Sized by chord sag:
## on a CRT shoulder (R ~ 0.3 m) desktop holds sag under 0.2 mm, Quest under 0.6.
const DENSITY_DESKTOP := 56.0
const DENSITY_QUEST := 32.0
const SUBDIV_MIN := 6
const SUBDIV_MAX_DESKTOP := 28
const SUBDIV_MAX_QUEST := 16
## Refuse to cook more than this — a hitch in VR is a comfort problem.
const MAX_TRIANGLES := 20000
## How far behind the sheet a sample may find surface before it counts as a miss.
const MAX_DEPTH := 0.06
## Start the probe this far in front, so a surface slightly proud is still found.
const PROBE_OUT := 0.04
## Clear of the surface. Larger than the flat sheet's skin: the polyline sags
## INSIDE the true surface between samples.
const SKIN := 0.002
## A hit whose normal turns further than this from the anchor is a ray that slipped
## past an edge and landed on something behind — the classic spike.
const MAX_NORMAL_TURN_DOT := 0.26
## Past this fraction of bad samples the wrap is meaningless; stay flat instead.
const MAX_INVALID_FRACTION := 0.4

## Cooked shapes live as long as the process, keyed on the source mesh, because a
## GLB shell is shared by every instance of that model.
static var _shape_cache: Dictionary = {}


## Sample `target` through `anchor` (world) and return arrays for an ArrayMesh, or
## an empty dictionary when the surface cannot be described and the caller should
## stay flat.
##
## A coroutine: the sampling body needs one physics frame to exist before it can
## be queried.
static func build(target: Node3D, anchor: Transform3D, size: Vector2,
		tree: SceneTree, exclude: Node = null) -> Dictionary:
	if target == null or tree == null or tree.current_scene == null:
		return {}
	if _is_flat_surface(target):
		return {}

	var meshes := _candidates(target, anchor, size, exclude)
	if meshes.is_empty():
		return {}

	var body := _cook(meshes)
	if body == null:
		return {}
	tree.current_scene.add_child(body)
	# Now that it is in the tree, each cooked shape can be put where its mesh is.
	for entry: Variant in body.get_meta("poses", []):
		var pair := entry as Array
		(pair[0] as Node3D).global_transform = pair[1] as Transform3D
	await tree.physics_frame

	var out := _sample(body, anchor, size)
	body.queue_free()
	return out


## A collider that IS its surface — a room shell — needs no sampling at all.
static func _is_flat_surface(target: Node3D) -> bool:
	var node: Node = target
	while node != null:
		if node.is_in_group("poster_flat"):
			return true
		node = node.get_parent()
	return false


## Visible meshes under the target whose bounds could reach the sheet.
## `exclude` is the poster itself. It matters: a stuck poster is REPARENTED under
## its host, so its own sheet is one of the host's meshes — cook that in and every
## interior ray hits the poster at depth zero, leaving only the samples that
## overhang the edges to find the real surface.
static func _candidates(target: Node3D, anchor: Transform3D, size: Vector2,
		exclude: Node) -> Array:
	var probe := AABB(anchor.origin, Vector3.ZERO)
	var half := Vector3(size.x, size.y, 0.0) * 0.5
	for corner: Vector3 in [Vector3(half.x, half.y, 0), Vector3(-half.x, half.y, 0),
			Vector3(half.x, -half.y, 0), Vector3(-half.x, -half.y, 0)]:
		probe = probe.expand(anchor * corner)
	probe = probe.grow(MAX_DEPTH + PROBE_OUT)

	var out: Array = []
	var total := 0
	for node: Node in _all_mesh_instances(target):
		var mi := node as MeshInstance3D
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		if exclude != null and (mi == exclude or exclude.is_ancestor_of(mi)):
			continue
		var world := mi.global_transform * mi.get_aabb()
		if not probe.intersects(world):
			continue
		@warning_ignore("integer_division")
		total += int(mi.mesh.get_faces().size() / 3)
		if total > MAX_TRIANGLES:
			return []
		out.append(mi)
	return out


static func _all_mesh_instances(root: Node) -> Array:
	var out: Array = []
	if root is MeshInstance3D:
		out.append(root)
	for c in root.get_children():
		out.append_array(_all_mesh_instances(c))
	return out


static func _cook(meshes: Array) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "PosterSampleBody"
	body.collision_layer = SAMPLE_LAYER
	body.collision_mask = 0
	var placed: Array = []
	for m: Variant in meshes:
		var mi := m as MeshInstance3D
		var shape := _shape_for(mi.mesh)
		if shape == null:
			continue
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		placed.append([cs, mi.global_transform])
	if placed.is_empty():
		body.free()
		return null
	# Poses are applied by the caller once the body is in the tree — a global
	# transform written before that has nothing to be global to.
	body.set_meta("poses", placed)
	return body


static func _shape_for(mesh: Mesh) -> ConcavePolygonShape3D:
	var key := mesh.get_rid()
	if _shape_cache.has(key):
		return _shape_cache[key]
	var shape := mesh.create_trimesh_shape()
	if shape != null:
		# A trimesh is single-sided, so a ray from the wrong side passes straight
		# through and the surface silently stops existing.
		shape.backface_collision = true
	_shape_cache[key] = shape
	return shape


static func _sample(body: StaticBody3D, anchor: Transform3D, size: Vector2) -> Dictionary:
	var desktop: bool = QualityManager.is_desktop()
	var density := DENSITY_DESKTOP if desktop else DENSITY_QUEST
	var cap := SUBDIV_MAX_DESKTOP if desktop else SUBDIV_MAX_QUEST
	var nx := clampi(int(round(size.x * density)), SUBDIV_MIN, cap)
	var ny := clampi(int(round(size.y * density)), SUBDIV_MIN, cap)

	var space := body.get_world_3d().direct_space_state
	var inv := anchor.affine_inverse()
	var n_anchor := anchor.basis.z.normalized()
	var pts: Array[Vector3] = []
	var valid: Array[bool] = []
	var invalid := 0

	for j in range(ny + 1):
		for i in range(nx + 1):
			var lx := (float(i) / float(nx) - 0.5) * size.x
			var ly := (float(j) / float(ny) - 0.5) * size.y
			var base := anchor * Vector3(lx, ly, 0.0)
			var q := PhysicsRayQueryParameters3D.create(
				base + n_anchor * PROBE_OUT, base - n_anchor * MAX_DEPTH)
			q.collision_mask = SAMPLE_LAYER
			var hit := space.intersect_ray(q)
			var ok := not hit.is_empty()
			if ok and (hit["normal"] as Vector3).normalized().dot(n_anchor) < MAX_NORMAL_TURN_DOT:
				ok = false
			if ok:
				pts.append(inv * (hit["position"] as Vector3))
			else:
				pts.append(Vector3(lx, ly, 0.0))
				invalid += 1
			valid.append(ok)

	var total := (nx + 1) * (ny + 1)
	if float(invalid) / float(total) > MAX_INVALID_FRACTION:
		return {}

	_diffuse(pts, valid, nx, ny)
	return _arrays(pts, nx, ny)


## Fill rejected samples from their valid neighbours, so the sheet runs off an edge
## or crosses a vent slot smoothly instead of leaving a crater or a spike.
static func _diffuse(pts: Array[Vector3], valid: Array[bool], nx: int, ny: int) -> void:
	for _pass in range(8):
		for j in range(ny + 1):
			for i in range(nx + 1):
				var idx := j * (nx + 1) + i
				if valid[idx]:
					continue
				var sum := Vector3.ZERO
				var count := 0
				for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var ni := i + d.x
					var nj := j + d.y
					if ni < 0 or nj < 0 or ni > nx or nj > ny:
						continue
					sum += pts[nj * (nx + 1) + ni]
					count += 1
				if count > 0:
					pts[idx] = sum / float(count)


## Vertices, normals, UVs and indices for the sampled grid.
##
## Normals come from central differences across the finished grid, NOT from the
## physics hits: a trimesh reports the FACE normal, so a smooth GLB shell would come
## back faceted and the poster would read as a low-poly gem.
##
## UVs are reparameterized by mean arc length per row and column — the principle
## the curved menu panel states — so the art keeps a uniform density per unit of
## SURFACE rather than per unit of flat projection. Separable, so it is right for
## cylinders and CRT shoulders and approximate on a saddle.
static func _arrays(pts: Array[Vector3], nx: int, ny: int) -> Dictionary:
	var w := nx + 1
	var h := ny + 1
	var normals := PackedVector3Array()
	normals.resize(w * h)
	for j in range(h):
		for i in range(w):
			var a := pts[j * w + mini(i + 1, nx)] - pts[j * w + maxi(i - 1, 0)]
			var b := pts[mini(j + 1, ny) * w + i] - pts[maxi(j - 1, 0) * w + i]
			var n := a.cross(b)
			if n.length_squared() < 1e-12:
				n = Vector3(0, 0, 1)
			n = n.normalized()
			if n.z < 0.0:
				n = -n
			normals[j * w + i] = n

	var us := _axis_param(pts, w, h, true)
	var vs := _axis_param(pts, w, h, false)

	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	verts.resize(w * h)
	uvs.resize(w * h)
	for j in range(h):
		for i in range(w):
			var idx := j * w + i
			verts[idx] = pts[idx] + normals[idx] * SKIN
			uvs[idx] = Vector2(us[i], 1.0 - vs[j])

	var indices := PackedInt32Array()
	for j in range(ny):
		for i in range(nx):
			var a := j * w + i
			var c := a + w
			indices.append_array([a, c, a + 1, a + 1, c, c + 1])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	return {"arrays": arrays, "nx": nx, "ny": ny}


## Normalised cumulative chord length, averaged over the rows (or the columns).
static func _axis_param(pts: Array[Vector3], w: int, h: int, along_x: bool) -> PackedFloat32Array:
	var n := w if along_x else h
	var other := h if along_x else w
	var acc := PackedFloat32Array()
	acc.resize(n)
	acc.fill(0.0)
	for o in range(other):
		var run := 0.0
		for k in range(1, n):
			var prev: Vector3 = pts[o * w + (k - 1)] if along_x else pts[(k - 1) * w + o]
			var cur: Vector3 = pts[o * w + k] if along_x else pts[k * w + o]
			run += prev.distance_to(cur)
			acc[k] += run
	var last: float = acc[n - 1]
	if last <= 0.0:
		for k in range(n):
			acc[k] = float(k) / float(n - 1)
		return acc
	for k in range(n):
		acc[k] = acc[k] / last
	return acc
