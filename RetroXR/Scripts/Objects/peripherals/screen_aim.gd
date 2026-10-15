## ScreenAim — where a ray lands on the PICTURE, met on a set's real glass.
##
## A tube bulges toward the player (the stock one 9 mm, the Panasonic
## CT-20D10B's 24.9 mm), the picture is laid on that bulge by its UVs, and the
## CRT stage shrinks it about the centre to the set's aspect fit. LightGun used
## to meet a flat plane through the mesh origin, which is the RIM, behind the
## glass, and read x and y off the mesh's bounds. A ray from above carried on
## past the point aimed at and the core was told a point below it: 40 px on a
## 448-line frame from a standing desktop eye 1.5 m from the Panasonic, 17 px
## on the stock set, and on the stock set's 1.4:1 glass up to 11 px across as
## well, because its 4:3 picture is narrower than the glass it is measured on.
##
## So the ray meets the glass's own triangles, the UV is interpolated where it
## lands, and that UV goes through the stage's own sums (crt_warp, then
## fit_scale): what comes out is the source texel drawn where the ray points.
## Tools/av/lightgun_aim_probe measures it on any shell.
class_name ScreenAim
extends RefCounted

## Off a shared edge, in mesh units: ten micrometres, about a sixtieth of a
## pixel on the picture, in two directions that are neither an axis nor a
## diagonal, so a ray down an edge or through a corner comes out inside a face.
const NUDGES: Array[Vector3] = [Vector3(1e-5, 3.7e-6, 0.0), Vector3(-4.1e-6, 1e-5, 0.0)]

var _screen: MeshInstance3D
var _mesh: Mesh
var _triangles := TriangleMesh.new()
## Per face, in the order the TriangleMesh numbers them: three corners each.
var _faces := PackedVector3Array()
var _uvs := PackedVector2Array()


func _init(screen: MeshInstance3D) -> void:
	_screen = screen
	_mesh = screen.mesh
	for s in _mesh.get_surface_count():
		var arrays := _mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var uvs: Variant = arrays[Mesh.ARRAY_TEX_UV]
		if not (uvs is PackedVector2Array) or (uvs as PackedVector2Array).size() != verts.size():
			continue
		var index: Variant = arrays[Mesh.ARRAY_INDEX]
		var count: int = (index as PackedInt32Array).size() if index is PackedInt32Array \
			else verts.size()
		for i in count:
			var k: int = (index as PackedInt32Array)[i] if index is PackedInt32Array else i
			_faces.append(verts[k])
			_uvs.append((uvs as PackedVector2Array)[k])
	_triangles.create_from_faces(_faces)


## True while this still describes `screen` as it stands: a set can be recabled,
## and a cabinet swaps its own tube in after the set's ready.
func is_for(screen: MeshInstance3D) -> bool:
	return screen == _screen and is_instance_valid(screen) and screen.mesh == _mesh


## Where a world-space ray meets the picture: {"picture": Vector2, (0,0) the
## frame's top left and (1,1) its bottom right, "point": the world hit}. Empty
## when it misses the glass, meets it from behind, or lands on a bar.
func hit(origin: Vector3, dir: Vector3) -> Dictionary:
	if _faces.is_empty() or not is_instance_valid(_screen):
		return {}
	var xf := _screen.global_transform
	var inv := xf.affine_inverse()
	var local_origin := inv * origin
	var local_dir := inv.basis * dir
	var got := _triangles.intersect_ray(local_origin, local_dir)
	# The triangle test is not watertight: a ray straight down an edge two faces
	# share can pass between them and meet neither. Both tubes are grids with
	# edges on the picture's centre lines, and aiming at the top middle of the
	# picture fell through. Off the edge and try again, only after a miss.
	for nudge: Vector3 in NUDGES:
		if not got.is_empty():
			break
		got = _triangles.intersect_ray(local_origin + nudge, local_dir)
	if got.is_empty():
		return {}
	var p: Vector3 = got["position"]
	var f: int = int(got["face_index"]) * 3
	# The glass from behind the set is no picture. The query's own normal is
	# turned to face whoever asked, so it cannot say which side was hit. The
	# glass faces +Z (the old plane's normal) and every face of a tube that
	# bulges toward the player leans that way, so the face's normal turned to
	# +Z is the front.
	var normal := (_faces[f + 1] - _faces[f]).cross(_faces[f + 2] - _faces[f])
	if normal.z < 0.0:
		normal = -normal
	if normal.dot(local_dir) >= 0.0:
		return {}
	var w := Geometry3D.get_triangle_barycentric_coords(p, _faces[f], _faces[f + 1], _faces[f + 2])
	var glass_uv := _uvs[f] * w.x + _uvs[f + 1] * w.y + _uvs[f + 2] * w.z
	var picture := picture_at(glass_uv)
	if picture.x < 0.0 or picture.x > 1.0 or picture.y < 0.0 or picture.y > 1.0:
		return {}
	return {"picture": picture, "point": xf * p}


## The source coordinate the glass shows at `glass_uv`: crt_effect's fragment()
## (and its mobile twin's) to the letter. Any other material draws the picture
## straight across the glass.
func picture_at(glass_uv: Vector2) -> Vector2:
	var mat := _screen.get_surface_override_material(0) as ShaderMaterial
	if mat == null or not RetroTV.is_crt_shader(mat.shader):
		return glass_uv
	var uv := glass_uv
	var curvature := float(_param(mat, "crt_curvature", 0.0))
	if bool(_param(mat, "crt_enabled", true)) and curvature > 0.0:
		var cc := uv * 2.0 - Vector2.ONE
		cc *= 1.0 + curvature * cc.dot(cc)
		uv = cc * 0.5 + Vector2(0.5, 0.5)
	var fit: Vector2 = _param(mat, "fit_scale", Vector2.ONE)
	return (uv - Vector2(0.5, 0.5)) / fit + Vector2(0.5, 0.5)


## A uniform the material has not been given reads null; the shader then uses
## its own default, which is `fallback`.
static func _param(mat: ShaderMaterial, uniform: StringName, fallback: Variant) -> Variant:
	var v: Variant = mat.get_shader_parameter(uniform)
	return fallback if v == null else v
