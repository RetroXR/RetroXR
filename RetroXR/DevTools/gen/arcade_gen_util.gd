## Shared helpers for the arcade scene generators (gen_arcade_board.gd,
## gen_arcade_cabinet.gd): build a node tree out of primitives, then pack it.
##
## A scene baked out of band rather than hand-written, because a cabinet is dozens
## of boxes and a .tscn typed by hand drifts from the numbers that placed them. The
## generator is the source and the .tscn is its output; re-run it to change one.
##
## The primitives themselves are ArcadeParts (Scripts/Objects/arcade/), which a cabinet
## also builds with at run time when it follows the game in its bay: one implementation,
## so a part baked and a part built in the room are the same part.
class_name ArcadeGenUtil
extends RefCounted


static func mat(color: Color, metallic: float = 0.0, rough: float = 0.7,
		emission: Color = Color.BLACK, emission_energy: float = 0.0) -> StandardMaterial3D:
	return ArcadeParts.mat(color, metallic, rough, emission, emission_energy)


## A node of `type` named `node_name` under `parent` (owner set to `root` so it is
## packed), optionally at `pos`.
static func node(root: Node, parent: Node, type: String, node_name: String,
		pos: Vector3 = Vector3.ZERO) -> Node:
	return ArcadeParts.node(root, parent, type, node_name, pos)


## The material goes on the MESH, not on the instance as an override (ArcadeParts.box).
static func box(root: Node, parent: Node, node_name: String, size: Vector3, pos: Vector3,
		material: Material) -> MeshInstance3D:
	return ArcadeParts.box(root, parent, node_name, size, pos, material)


## A cylinder standing along `axis` (Vector3.UP by default), with the sides its size can show.
static func cylinder(root: Node, parent: Node, node_name: String, radius: float, height: float,
		pos: Vector3, material: Material, axis: Vector3 = Vector3.UP) -> MeshInstance3D:
	return ArcadeParts.cylinder(root, parent, node_name, radius, height, pos, material, axis)


## A quad (faces +Z, UV 0..1), `size` metres.
static func quad(root: Node, parent: Node, node_name: String, size: Vector2, pos: Vector3,
		material: Material) -> MeshInstance3D:
	return ArcadeParts.quad(root, parent, node_name, size, pos, material)


## Pack `root` and save it to `path`; the generator's one exit.
static func save(root: Node, path: String) -> int:
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		push_error("pack failed: %d" % err)
		return err
	err = ResourceSaver.save(packed, path)
	if err != OK:
		push_error("save failed: %d (%s)" % [err, path])
	else:
		print("[gen] wrote ", path)
	return err
