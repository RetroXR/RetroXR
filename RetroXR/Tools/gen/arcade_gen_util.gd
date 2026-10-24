## Shared helpers for the arcade scene generators (gen_arcade_board.gd,
## gen_arcade_cabinet.gd): build a node tree out of primitives, then pack it.
##
## A scene baked out of band rather than hand-written, because a cabinet is dozens
## of boxes and a .tscn typed by hand drifts from the numbers that placed them. The
## generator is the source and the .tscn is its output; re-run it to change one.
class_name ArcadeGenUtil
extends RefCounted


static func mat(color: Color, metallic: float = 0.0, rough: float = 0.7,
		emission: Color = Color.BLACK, emission_energy: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = rough
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = emission_energy
	return m


## A node of `type` named `node_name` under `parent` (owner set to `root` so it is
## packed), optionally at `pos`.
static func node(root: Node, parent: Node, type: String, node_name: String,
		pos: Vector3 = Vector3.ZERO) -> Node:
	var n := ClassDB.instantiate(type) as Node
	n.name = node_name
	parent.add_child(n)
	n.owner = root
	if n is Node3D:
		(n as Node3D).position = pos
	return n


## The material goes on the MESH, not on the instance as an override: an override
## would shadow every surface override set later (CartridgeLabel paints a board's
## sticker that way), and a baked scene should be repainted the ordinary way.
static func box(root: Node, parent: Node, node_name: String, size: Vector3, pos: Vector3,
		material: Material) -> MeshInstance3D:
	var mi := node(root, parent, "MeshInstance3D", node_name, pos) as MeshInstance3D
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = material
	mi.mesh = bm
	return mi


## A cylinder standing along `axis` (Vector3.UP by default).
static func cylinder(root: Node, parent: Node, node_name: String, radius: float, height: float,
		pos: Vector3, material: Material, axis: Vector3 = Vector3.UP) -> MeshInstance3D:
	var mi := node(root, parent, "MeshInstance3D", node_name, pos) as MeshInstance3D
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	# Godot's default is 64 sides and 4 rings: 768 triangles for a button 3 cm across. A cabinet has dozens
	# of these and each is a draw call in a room that may hold twenty cabinets, so a part gets the sides its
	# size can show (12 at 1.5 cm, 40 at 5 cm and up) and no inner rings.
	cm.radial_segments = clampi(int(radius * 800.0), 12, 40)
	cm.rings = 1
	cm.material = material
	mi.mesh = cm
	if not axis.is_equal_approx(Vector3.UP):
		mi.basis = Basis(Quaternion(Vector3.UP, axis.normalized()))
	return mi


## A quad (faces +Z, UV 0..1), `size` metres.
static func quad(root: Node, parent: Node, node_name: String, size: Vector2, pos: Vector3,
		material: Material) -> MeshInstance3D:
	var mi := node(root, parent, "MeshInstance3D", node_name, pos) as MeshInstance3D
	var qm := QuadMesh.new()
	qm.size = size
	qm.material = material
	mi.mesh = qm
	return mi


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
