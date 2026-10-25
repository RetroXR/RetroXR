## RealRoomSurface — one thing in the player's real room, as something to rest on.
##
## OpenXRFbSceneManager instances this scene under an anchor for everything the
## player scanned in Space Setup and calls setup_scene() with it: the room's mesh
## (GLOBAL_MESH, a Quest 3's scan of every surface), a piece of furniture drawn as
## a box (a table, a couch), or a flat face of the room (the floor, a wall). Each
## becomes a static body on layer 1, the layer every room's shelves and tables are
## on, so whatever a player drops on it lands there as on any table in the game
## (HeldPhysics needs nothing new). RealRoom decides which kinds are solid: the
## furniture boxes only when there is no mesh, which already has the furniture's
## real shape.
class_name RealRoomSurface
extends StaticBody3D

enum Kind { NONE, MESH, FURNITURE, FACE }

## Room geometry is world geometry: layer 1, World.
const WORLD_LAYER := 1
const FURNITURE_LABELS: PackedStringArray = [
	"TABLE", "COUCH", "BED", "STORAGE", "SCREEN", "LAMP", "PLANT", "OTHER",
]
const FACE_LABELS: PackedStringArray = ["FLOOR", "CEILING", "WALL_FACE", "INVISIBLE_WALL_FACE"]
## Faces a poster is pressed flat against (PosterConform's group).
const WALL_LABELS: PackedStringArray = ["WALL_FACE", "INVISIBLE_WALL_FACE"]
const POSTER_GROUP := &"poster_flat"
const GROUP := &"real_room_surface"

## Debug > Overlays > Real Room Surfaces: every surface drawn as what it is, so
## what the game has made of the room can be looked at in it. Not saved, like
## the collision overlay. Per kind, and bolder where things rest on it.
static var debug_visible := false
const DEBUG_COLORS := {
	Kind.MESH: Color(1.0, 0.55, 0.15),
	Kind.FURNITURE: Color(0.25, 0.55, 1.0),
	Kind.FACE: Color(0.3, 0.9, 0.4),
}
const DEBUG_ALPHA_SOLID := 0.35
const DEBUG_ALPHA_NOT_SOLID := 0.08

var kind := Kind.NONE
var labels := PackedStringArray()
var _debug_mesh: MeshInstance3D = null


## Show or hide every surface's overlay, now and for surfaces made later.
static func set_debug_visible(tree: SceneTree, on: bool) -> void:
	debug_visible = on
	if tree != null:
		tree.call_group(GROUP, "refresh_debug")


## What `labels` (Meta's semantic labels, any case) make of a surface.
static func kind_for(of: PackedStringArray) -> Kind:
	var upper := PackedStringArray()
	for l in of:
		upper.append(l.to_upper())
	if "GLOBAL_MESH" in upper:
		return Kind.MESH
	for l in upper:
		if l in FURNITURE_LABELS:
			return Kind.FURNITURE
	for l in upper:
		if l in FACE_LABELS:
			return Kind.FACE
	return Kind.NONE


## Called by the scene manager with the spatial entity this anchor is.
func setup_scene(entity: Object) -> void:
	labels = PackedStringArray(entity.call("get_semantic_labels"))
	kind = kind_for(labels)
	collision_mask = 0
	set_solid(kind != Kind.NONE)
	if kind == Kind.NONE:
		return
	var shape: Variant = entity.call("create_collision_shape")
	if shape is Node:
		add_child(shape as Node)
	add_to_group(GROUP)
	for l in labels:
		if l.to_upper() in WALL_LABELS:
			add_to_group(POSTER_GROUP)
			break
	refresh_debug()


func set_solid(on: bool) -> void:
	collision_layer = WORLD_LAYER if on else 0
	refresh_debug()


func is_solid() -> bool:
	return collision_layer != 0


func has_debug_mesh() -> bool:
	return _debug_mesh != null and _debug_mesh.visible


## Build, tint or hide this surface's overlay to match debug_visible.
func refresh_debug() -> void:
	if not debug_visible or kind == Kind.NONE:
		if _debug_mesh != null:
			_debug_mesh.visible = false
		return
	if _debug_mesh == null:
		var mesh := _overlay_mesh()
		if mesh == null:
			return
		_debug_mesh = MeshInstance3D.new()
		_debug_mesh.name = "DebugOverlay"
		_debug_mesh.mesh = mesh
		_debug_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		# Drawn over everything, as CollisionDebug's are. Each overlay lies on
		# the real surface it was made from, so with "Real Objects Hide Virtual"
		# on, Meta's coarse, noisy depth of that same surface hid it in patches
		# that moved with the head (Quest 3, 2026-10-25).
		mat.no_depth_test = true
		_debug_mesh.material_override = mat
		add_child(_debug_mesh)
	var color: Color = DEBUG_COLORS.get(kind, Color.WHITE)
	color.a = DEBUG_ALPHA_SOLID if is_solid() else DEBUG_ALPHA_NOT_SOLID
	(_debug_mesh.material_override as StandardMaterial3D).albedo_color = color
	_debug_mesh.visible = true


## The surface's collision shape as something to draw, where its CollisionShape3D
## sits: a box for a box, the triangles themselves for the scanned mesh.
func _overlay_mesh() -> Mesh:
	for c in get_children():
		if not (c is CollisionShape3D) or (c as CollisionShape3D).shape == null:
			continue
		var shape := (c as CollisionShape3D).shape
		var at := (c as CollisionShape3D).transform
		if shape is BoxShape3D:
			var box := BoxMesh.new()
			box.size = (shape as BoxShape3D).size
			return _placed(box, at)
		if shape is ConcavePolygonShape3D:
			var faces := (shape as ConcavePolygonShape3D).get_faces()
			if faces.is_empty():
				return null
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			var placed := PackedVector3Array()
			placed.resize(faces.size())
			for i in faces.size():
				placed[i] = at * faces[i]
			arrays[Mesh.ARRAY_VERTEX] = placed
			var am := ArrayMesh.new()
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			return am
	return null


## A primitive moved to where the collision shape is, baked into an ArrayMesh.
func _placed(primitive: PrimitiveMesh, at: Transform3D) -> Mesh:
	if at.is_equal_approx(Transform3D.IDENTITY):
		return primitive
	var arrays := primitive.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in verts.size():
		verts[i] = at * verts[i]
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = null
	arrays[Mesh.ARRAY_TANGENT] = null
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return am
