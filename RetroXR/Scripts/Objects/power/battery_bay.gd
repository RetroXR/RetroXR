## BatteryBay — a primitive handheld's battery compartment: a pocket cut into the back
## of its body, the contacts, a seat for every cell (BatteryAA<n> markers CellSlots
## seats) and the cover that closes it flush with the back (a CoverSlots cover, taken
## off by hand, laser or mouse, saved and synced as every cover in the room is).
## docs/dev/power.md.
##
## Built from a PowerProfiles row's "bay", so a handheld's compartment is data:
##   size     "AA" or "AAA"
##   count    cells in it (a split bay: in each half)
##   along    "x" or "z": which way a cell lies in the model's frame
##   at       [u, v]: the bay's middle as fractions of the body's width (x) and
##            length (z) from its middle; +v toward +Z
##   split    two compartments either side of the middle at +-u (the Game Gear's
##            grips), each with its own cover
## The body box is replaced by the same box with a pocket in its back (-Y) for each
## compartment (`pocketed_box`): the cells lie inside the shell, under a cover whose
## outer face is the back's, as on the hardware. The body's collision box is the
## whole box still, so the cells are inside it. Measured against the hardware the
## bay's place is not; the cell count and size are (PowerProfiles).
class_name BatteryBay
extends RefCounted

## Cell sizes in mm: diameter and length (IEC LR6 / LR03).
const CELLS := {"AA": Vector2(14.5, 50.5), "AAA": Vector2(10.5, 44.5)}
const GAP := 0.001
const COVER_THICK := 0.0016
## Between the cover's inside and the cells, and the cells and the pocket's floor.
const CLEARANCE := 0.0005
## How much smaller than its opening the cover is, all round.
const COVER_PLAY := 0.0003
## The least body left in front of a pocket's floor.
const MIN_FRONT := 0.004
## How far out of the back a seated cover's pointer target reaches: past the 5 mm the
## console's grab box stands round its body.
const POINTER_REACH := 0.007
const SHELL := Color(0.62, 0.62, 0.6)
const INSIDE := Color(0.06, 0.06, 0.065)
const CONTACT := Color(0.8, 0.78, 0.7)


## Build `spec`'s bay into `model` (a HandheldModel), its body box `body` in the
## model's frame, cutting the pockets into `body_mesh` (the HandheldBody). Returns how
## many seats were made. Does nothing for a model whose object already has cells (a
## mod's shell built its own).
static func build(model: Node3D, body: AABB, spec: Dictionary, socket_prefix: String,
		shell := SHELL, body_mesh: MeshInstance3D = null) -> int:
	var host := CoverSlots.host_of(model)
	if host == null or spec.is_empty():
		return 0
	if CellSlots.of(host) != null and not CellSlots.of(host).seats().is_empty():
		print("[Power] %s already has battery seats; its own bay stays" % host.name)
		return 0
	var size := str(spec.get("size", "AA"))
	var cell: Vector2 = CELLS.get(size, CELLS["AA"]) * 0.001
	var count := int(spec.get("count", 2))
	var along := str(spec.get("along", "x"))
	var at: Array = spec.get("at", [0.0, 0.0])
	var halves: Array = [float(at[0])]
	if bool(spec.get("split", false)):
		halves = [-absf(float(at[0])), absf(float(at[0]))]
	var depth := pocket_depth(cell)
	if depth > body.size.y - MIN_FRONT:
		push_warning("[Power] %s: a %s bay %.1f mm deep does not fit a %.1f mm body"
			% [host.name, size, depth * 1000.0, body.size.y * 1000.0])
		return 0
	var foot := _footprint(cell, count, along)
	var centers: Array[Vector3] = []
	for u: Variant in halves:
		centers.append(Vector3(body.get_center().x + float(u) * body.size.x,
			body.position.y, body.get_center().z + float(at[1]) * body.size.z))
	if body_mesh != null:
		_cut(model, body_mesh, centers, foot, depth)
	else:
		push_warning("[Power] %s: no body mesh to cut the bay into" % host.name)
	var root := Node3D.new()
	root.name = "BatteryBay"
	model.add_child(root)
	var made := 0
	var n := 0
	for i in centers.size():
		var center := centers[i]
		made += _compartment(root, center, cell, count, along, size, n, depth)
		var socket := socket_prefix if centers.size() == 1 else "%s%d" % [socket_prefix, i + 1]
		_cover(host, root, center, foot, socket, shell)
		n += count
	CellSlots.build_seats(root)
	return made


## How deep a pocket for cells of `cell` (diameter, length; m) is: the cover, the
## cells, a clearance either side.
static func pocket_depth(cell: Vector2) -> float:
	return COVER_THICK + CLEARANCE * 2.0 + cell.x


## The footprint of `count` cells lying `along`, side by side: x and z extents.
static func _footprint(cell: Vector2, count: int, along: String) -> Vector2:
	var length := cell.y + 0.004
	var across := count * cell.x + (count - 1) * GAP + 0.003
	return Vector2(length, across) if along == "x" else Vector2(across, length)


## Swap the body's box for the same box with the pockets cut into its back. The body
## is axis-aligned in the model (every primitive's is); one that is not keeps its box.
static func _cut(model: Node3D, body_mesh: MeshInstance3D, centers: Array[Vector3], foot: Vector2,
		depth: float) -> void:
	var box := body_mesh.mesh as BoxMesh
	if box == null:
		push_warning("[Power] %s: the body is not a box; no pocket cut" % body_mesh.name)
		return
	var xf := model.global_transform.affine_inverse() * body_mesh.global_transform
	if not xf.basis.orthonormalized().is_equal_approx(Basis.IDENTITY):
		push_warning("[Power] %s: the body is turned in its model; no pocket cut" % body_mesh.name)
		return
	var to_local := xf.affine_inverse()
	var holes: Array[Rect2] = []
	for c: Vector3 in centers:
		var a := to_local * Vector3(c.x - foot.x * 0.5, c.y, c.z - foot.y * 0.5)
		var b := to_local * Vector3(c.x + foot.x * 0.5, c.y, c.z + foot.y * 0.5)
		holes.append(Rect2(Vector2(minf(a.x, b.x), minf(a.z, b.z)), Vector2(absf(b.x - a.x), absf(b.z - a.z))))
	body_mesh.mesh = pocketed_box(box.size, holes, depth, box.material)
	print("[Power] %s: %d battery pocket(s) cut, %.1f x %.1f x %.1f mm" % [body_mesh.name, holes.size(),
		foot.x * 1000.0, foot.y * 1000.0, depth * 1000.0])


## A box of `size` centred on the origin with a pocket `depth` deep in its back (-Y)
## face for each rect in `holes` (x, z in the box's frame), in `material`.
static func pocketed_box(size: Vector3, holes: Array[Rect2], depth: float, material: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := size * 0.5
	var back := -h.y
	# The five whole faces.
	_quad(st, [Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)],
		Vector3.UP, size)
	_quad(st, [Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, -h.y, h.z)],
		Vector3.RIGHT, size)
	_quad(st, [Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, -h.y, h.z)],
		Vector3.LEFT, size)
	_quad(st, [Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)],
		Vector3.BACK, size)
	_quad(st, [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z)],
		Vector3.FORWARD, size)
	# The back, round the holes: a grid on every edge, each cell outside them a quad.
	var xs: Array[float] = [-h.x, h.x]
	var zs: Array[float] = [-h.z, h.z]
	for r: Rect2 in holes:
		xs.append_array([clampf(r.position.x, -h.x, h.x), clampf(r.end.x, -h.x, h.x)])
		zs.append_array([clampf(r.position.y, -h.z, h.z), clampf(r.end.y, -h.z, h.z)])
	xs.sort()
	zs.sort()
	for i in xs.size() - 1:
		for j in zs.size() - 1:
			var x0 := xs[i]
			var x1 := xs[i + 1]
			var z0 := zs[j]
			var z1 := zs[j + 1]
			if x1 - x0 < 1e-6 or z1 - z0 < 1e-6:
				continue
			var mid := Vector2((x0 + x1) * 0.5, (z0 + z1) * 0.5)
			var open := false
			for r: Rect2 in holes:
				open = open or r.has_point(mid)
			if not open:
				_quad(st, [Vector3(x0, back, z0), Vector3(x1, back, z0), Vector3(x1, back, z1), Vector3(x0, back, z1)],
					Vector3.DOWN, size)
	# Each pocket: four walls facing into it, and its floor.
	var floor_y := back + depth
	for r: Rect2 in holes:
		var x0 := r.position.x
		var x1 := r.end.x
		var z0 := r.position.y
		var z1 := r.end.y
		_quad(st, [Vector3(x0, back, z0), Vector3(x0, floor_y, z0), Vector3(x0, floor_y, z1), Vector3(x0, back, z1)],
			Vector3.RIGHT, size)
		_quad(st, [Vector3(x1, back, z0), Vector3(x1, floor_y, z0), Vector3(x1, floor_y, z1), Vector3(x1, back, z1)],
			Vector3.LEFT, size)
		_quad(st, [Vector3(x0, back, z0), Vector3(x1, back, z0), Vector3(x1, floor_y, z0), Vector3(x0, floor_y, z0)],
			Vector3.BACK, size)
		_quad(st, [Vector3(x0, back, z1), Vector3(x1, back, z1), Vector3(x1, floor_y, z1), Vector3(x0, floor_y, z1)],
			Vector3.FORWARD, size)
		_quad(st, [Vector3(x0, floor_y, z0), Vector3(x1, floor_y, z0), Vector3(x1, floor_y, z1), Vector3(x0, floor_y, z1)],
			Vector3.DOWN, size)
	var mesh := st.commit()
	if material != null:
		mesh.surface_set_material(0, material)
	return mesh


## Two triangles over the four corners of a flat quad, facing `normal` (Godot's front
## faces wind clockwise as seen from in front), UVs projected from the box.
static func _quad(st: SurfaceTool, corners: Array, normal: Vector3, size: Vector3) -> void:
	var a: Vector3 = corners[0]
	var b: Vector3 = corners[1]
	var c: Vector3 = corners[2]
	var d: Vector3 = corners[3]
	if (b - a).cross(c - a).dot(normal) > 0.0:
		var t := b
		b = d
		d = t
	for v: Vector3 in [a, b, c, a, c, d]:
		st.set_normal(normal)
		var p := v / size + Vector3(0.5, 0.5, 0.5)
		st.set_uv(Vector2(p.x, p.z) if absf(normal.y) > 0.5 else (Vector2(p.z, p.y) if absf(normal.x) > 0.5
			else Vector2(p.x, p.y)))
		st.add_vertex(v)


static func _compartment(root: Node3D, center: Vector3, cell: Vector2, count: int, along: String,
		size: String, first: int, depth: float) -> int:
	var foot := _footprint(cell, count, along)
	# The pocket's floor, dark, just in front of the body's own floor face.
	_box(root, Vector3(foot.x, 0.0004, foot.y), center + Vector3(0, depth - 0.0003, 0), INSIDE)
	# The cells' middles: under the cover, inside the body (+Y from the back).
	var y := center.y + COVER_THICK + CLEARANCE + cell.x * 0.5
	var axis := Vector3.RIGHT if along == "x" else Vector3.BACK
	var side := Vector3.BACK if along == "x" else Vector3.RIGHT
	for k in count:
		var offset := (float(k) - (count - 1) * 0.5) * (cell.x + GAP)
		var mid := Vector3(center.x, y, center.z) + side * offset
		# Cells go in head to tail, as in every bay with a row of them.
		var plus := axis if k % 2 == 0 else -axis
		var marker := Node3D.new()
		marker.name = "Battery%s%d" % [size, first + k + 1]
		# +Z toward the + terminal, +Y out of the bay (-Y of the model: the back).
		var z := plus
		var yb := Vector3.DOWN
		marker.transform = Transform3D(Basis(yb.cross(z), yb, z), mid)
		root.add_child(marker)
		# The contacts at either end: a spring at the minus end, a plate at the plus.
		for e: int in [-1, 1]:
			_box(root, Vector3(0.006, 0.006, 0.0008) if along == "z" else Vector3(0.0008, 0.006, 0.006),
				mid + plus * (cell.y * 0.5 + 0.0012) * e, CONTACT)
	return count


## The cover in the pocket's mouth, its outer face flush with the back.
static func _cover(host: Node, root: Node3D, center: Vector3, foot: Vector2, socket: String,
		shell: Color) -> void:
	var out := Vector3.DOWN
	var x := Vector3.RIGHT
	var z := x.cross(out).normalized()
	var seat := Transform3D(Basis(x, out, z), center + Vector3(0, COVER_THICK * 0.5, 0))
	var cover_size := Vector3(foot.x - COVER_PLAY * 2.0, COVER_THICK, foot.y - COVER_PLAY * 2.0)
	var zone := CoverSlots.on(host).build(socket, root, seat, cover_size)
	var fit := _reachable.bind(shell)
	zone.has_picked_up.connect(fit)
	if zone.picked_up_object != null:
		fit.call(zone.picked_up_object)


## A cover flush in the back sits inside the console's own grab box (the body and 5 mm
## all round, HandheldModel.configure_handheld_body), which the desktop ray and the
## laser meet first. Seated, it is aimed at by a box of its own width standing
## POINTER_REACH out of the back, past that box, so aiming at the cover takes the
## cover and nothing round it (PortCover.set_pointer_hull; loose, its own box again).
static func _reachable(what: Node3D, shell: Color) -> void:
	var cover := what as PortCover
	if cover == null:
		return
	# The shell's colour, while nothing (a mod's dressing) has given it another; kept off.
	var mesh := cover.get_node_or_null("Mesh") as MeshInstance3D
	if mesh != null and mesh.material_override == null:
		var paint := StandardMaterial3D.new()
		paint.albedo_color = shell
		paint.roughness = 0.6
		mesh.material_override = paint
	var hull := BoxShape3D.new()
	hull.size = Vector3(cover.size.x, cover.size.y + POINTER_REACH, cover.size.z)
	cover.set_pointer_hull(hull, Transform3D(Basis(), Vector3(0.0, POINTER_REACH * 0.5, 0.0)))


static func _box(root: Node3D, size: Vector3, at: Vector3, color: Color) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.7 if color != CONTACT else 0.3
	m.metallic = 0.9 if color == CONTACT else 0.0
	box.material = m
	mi.mesh = box
	mi.position = at
	root.add_child(mi)
