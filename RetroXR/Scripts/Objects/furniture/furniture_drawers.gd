## FurnitureDrawers — the drawers of a piece of furniture, built from its model's contract: for every drawer a sliding
## body, the node that draws it and a VRDrawer handle across its pulls. What lies in a drawer while the whole piece is
## carried is the owner's CarryContents' (a bin per drawer, framed on its body): the held-only lids are gone (2026-11-14).
## Lifted out of DrawerFurniture (the Mission pair) so a piece that is something else as well (a bed, which is a Seat)
## builds its drawers the same way: one copy of the rules in docs/dev/furniture.md.
##
## A contract drawer row: `node`, `front` / `inner` {centre, size}, `pulls`, `travel_m`, `row_top_y`, and optionally
## `axis`, the way it slides out (default +Z, the Mission pair's; a bed's drawers come out of its SIDE, +X). Everything
## a drawer is built from is turned into the drawer's own frame (its Z the axis, Y up), built there as the +Z drawer
## always was, and turned back, so a +Z drawer is built exactly as before.
##
## The nodes are the HOST's children, named `DrawerBodyN` / `DrawerVisualN` / `DrawerHandleN` as DrawerFurniture's
## always were: a VRDrawer is saved and synced by its path.
##
## A row with `kind: "sliding_door"` (the living-room credenza and bookcase, 2026-11-14) is a door that slides across
## its bay along `axis` (±X): the same VRDrawer, but its body is the door's slab alone (no box, no floor, nothing rides in
## it), its handle is a box at its finger pull, and nothing pushes it from a face. Two doors that overlap run
## on two `track`s (depths), so they pass one in front of the other as real ones do; nothing else keeps them apart.
class_name FurnitureDrawers
extends RefCounted

## Drawer walls and floor, as built in the models (RetroXR-models params.py BOX_T, FLOOR_T).
const WALL_T := 0.011
const FLOOR_T := 0.008
## The handle box: past the outermost pulls by this much either side, this tall and deep.
const HANDLE_MARGIN := 0.05
const HANDLE_H := 0.06
const HANDLE_D := 0.04

## One row per drawer: {body, visual, handle (VRDrawer), inner (AABB, the host's frame), row_top, sliding}.
var rows: Array[Dictionary] = []

var _host: XRToolsPickable
var _model: ApplianceModel
var _tag := "Drawers"
var _held := false


func _init(host: XRToolsPickable, model: ApplianceModel, tag: String = "Drawers") -> void:
	_host = host
	_model = model
	_tag = tag


## Build every drawer row of a contract.
func build(contract_rows: Array) -> void:
	for row: Dictionary in contract_rows:
		_build_drawer(row)


## The drawers' handles, in contract order.
func handles() -> Array[VRDrawer]:
	var out: Array[VRDrawer] = []
	for d in rows:
		out.append(d["handle"] as VRDrawer)
	return out


## The body things in drawer `i` rest on.
func body(i: int) -> AnimatableBody3D:
	return rows[i]["body"] as AnimatableBody3D


## The middle of drawer `i`'s floor inside, in the host's frame, wherever the drawer is now.
func seat_local(i: int) -> Vector3:
	var inner: AABB = rows[i]["inner"]
	return Vector3(inner.get_center().x, inner.position.y, inner.get_center().z) + body(i).position


## The caller POLLS the hold (frozen + held layer: a ray grab emits no picked_up / dropped) and passes it; returns true
## when it changed (the owner reports where its drawers stand once it is put down).
func step(held: bool) -> bool:
	if held == _held:
		return false
	_held = held
	print("[%s] %s: %s, %d drawer(s)" % [_tag, _host.name, "held" if held else "put down", rows.size()])
	return true


## Whether row `i` is a sliding door (nothing rides in it).
func is_sliding_door(i: int) -> bool:
	return bool(rows[i].get("sliding", false))


## The basis of a drawer that slides out along `axis` (in the host's frame): its Z the axis, its Y up.
static func axis_basis(axis: Vector3) -> Basis:
	var z := axis.normalized()
	if z.is_equal_approx(Vector3.BACK):
		return Basis.IDENTITY
	var y := Vector3.UP
	var x := y.cross(z).normalized()
	return Basis(x, z.cross(x).normalized(), z)


func _build_drawer(row: Dictionary) -> void:
	if str(row.get("kind", "")) == "sliding_door":
		_build_sliding_door(row)
		return
	var node := String(row.get("node", "Drawer%d" % (rows.size() + 1)))
	var n := node.trim_prefix("Drawer")
	var b := axis_basis(_v3(row["axis"]) if row.has("axis") and row["axis"] != null else Vector3.BACK)
	var bt := b.transposed()
	var front: Dictionary = row["front"]
	# In the HOST's frame (what the carry bins, the tests and the caller see) ...
	var ic_h := _v3(row["inner"]["centre"])
	var isz_h := _v3(row["inner"]["size"])
	# ... and in the drawer's own (its Z out of the front), where it is built as a +Z drawer.
	var fc := bt * _v3(front["centre"])
	var fs := (bt * _v3(front["size"])).abs()
	var ic := bt * ic_h
	var isz := (bt * isz_h).abs()
	var inner := AABB(ic - isz * 0.5, isz)
	var body_ := AnimatableBody3D.new()
	body_.name = "DrawerBody" + n
	body_.collision_layer = _host.collision_layer
	body_.collision_mask = _host.collision_mask
	body_.physics_material_override = _host.physics_material_override
	# OFF: a plain child of the piece, turning and travelling with it (furniture.md: synced, it kept its own world pose).
	body_.sync_to_physics = false
	_host.add_child(body_)
	var back_of_front := fc.z - fs.z * 0.5
	var shapes := [
		["Front", fc, fs],
		["Floor", Vector3(ic.x, inner.position.y - FLOOR_T * 0.5, ic.z), Vector3(isz.x + 2 * WALL_T, FLOOR_T,
			isz.z + 2 * WALL_T)],
		["WallL", Vector3(inner.position.x - WALL_T * 0.5, ic.y, ic.z), Vector3(WALL_T, isz.y, isz.z + 2 * WALL_T)],
		["WallR", Vector3(inner.end.x + WALL_T * 0.5, ic.y, ic.z), Vector3(WALL_T, isz.y, isz.z + 2 * WALL_T)],
		["WallB", Vector3(ic.x, ic.y, inner.position.z - WALL_T * 0.5), Vector3(isz.x, isz.y, WALL_T)],
		["WallF", Vector3(ic.x, ic.y, (inner.end.z + back_of_front) * 0.5), Vector3(isz.x, isz.y,
			maxf(back_of_front - inner.end.z, WALL_T))],
	]
	for s: Array in shapes:
		body_.add_child(_box("Box" + String(s[0]), s[1], s[2], b))
	body_.add_collision_exception_with(_host)
	_host.add_collision_exception_with(body_)
	# What draws it: the model's drawer (front, box and pulls, every level) hangs here.
	var visual := Node3D.new()
	visual.name = "DrawerVisual" + n
	_host.add_child(visual)
	var mesh: MeshInstance3D = null
	if _model != null and not _model.levels.is_empty():
		mesh = _model.part(node) as MeshInstance3D
		_model.attach_part(node, visual)
		if mesh == null:
			push_warning("[%s] %s: the model has no %s to draw the drawer with" % [_tag, _host.name, node])
	else:
		push_warning("[%s] %s: no model to hang %s from" % [_tag, _host.name, node])
	# The handle: one box across all of its pulls, at the pulls' middle with the drawer shut.
	var pulls: Array = row.get("pulls", [])
	var at := Vector3.ZERO
	var x0 := INF
	var x1 := -INF
	for p: Array in pulls:
		var v := bt * _v3(p)
		at += v
		x0 = minf(x0, v.x)
		x1 = maxf(x1, v.x)
	at = at / maxf(pulls.size(), 1) if not pulls.is_empty() else Vector3(fc.x, fc.y, fc.z + fs.z * 0.5)
	if pulls.is_empty():
		x0 = fc.x
		x1 = fc.x
	var handle := VRDrawer.new()
	handle.name = "DrawerHandle" + n
	# Turned so its own Z is the way the drawer comes out: VRDrawer slides along its local axis (+Z).
	handle.transform = Transform3D(b, b * at)
	handle.target = body_
	handle.visual = visual
	handle.travel = float(row.get("travel_m", 0.25))
	var front_face_z := fc.z + fs.z * 0.5
	handle.push_face_offset = front_face_z - at.z
	handle.push_face_size = Vector2(fs.x, fs.y)
	handle.push_face_centre = Vector2(fc.x - at.x, fc.y - at.y)
	# The inside of the drawer's front wall, from its floor to the top of the front: a hand in a part-open drawer
	# pushes it out there.
	var front_top := fc.y + fs.y * 0.5
	handle.pull_face_offset = inner.end.z - at.z
	handle.pull_face_size = Vector2(inner.size.x, front_top - inner.position.y)
	handle.pull_face_centre = Vector2(inner.get_center().x - at.x, (inner.position.y + front_top) * 0.5 - at.y)
	var hb := _box("CollisionShape3D", Vector3(0, 0, (front_face_z - at.z) * 0.5 + HANDLE_D * 0.25),
		Vector3(x1 - x0 + 2 * HANDLE_MARGIN, HANDLE_H, HANDLE_D), Basis.IDENTITY)
	handle.add_child(hb)
	_host.add_child(handle)
	if mesh != null:
		handle.set_handle_mesh(mesh)
	rows.append({"body": body_, "visual": visual, "handle": handle,
		"inner": AABB(ic_h - isz_h * 0.5, isz_h), "row_top": float(row.get("row_top_y", inner.end.y + 0.02))})


## Size of a sliding door's handle box at its pull (across the door, up, along the slide), and how proud of the face.
const SLIDER_HANDLE := Vector3(0.05, 0.16, 0.10)


## A door sliding along `axis` across its bay: its slab is the body, a box at its pull the handle.
func _build_sliding_door(row: Dictionary) -> void:
	var node := String(row.get("node", "SlideDoor%d" % (rows.size() + 1)))
	var b := axis_basis(_v3(row["axis"]) if row.has("axis") and row["axis"] != null else Vector3.RIGHT)
	var bt := b.transposed()
	var fc_h := _v3(row["front"]["centre"])
	var fs_h := _v3(row["front"]["size"])
	var body_ := AnimatableBody3D.new()
	body_.name = "DrawerBody" + node
	body_.collision_layer = _host.collision_layer
	body_.collision_mask = _host.collision_mask
	body_.physics_material_override = _host.physics_material_override
	body_.sync_to_physics = false
	_host.add_child(body_)
	# The slab, placed straight in the host's frame (the body itself is never turned: it only slides).
	var slab := BoxShape3D.new()
	slab.size = fs_h
	var cs := CollisionShape3D.new()
	cs.name = "BoxFront"
	cs.shape = slab
	cs.position = fc_h
	body_.add_child(cs)
	body_.add_collision_exception_with(_host)
	_host.add_collision_exception_with(body_)
	var visual := Node3D.new()
	visual.name = "DrawerVisual" + node
	_host.add_child(visual)
	var mesh: MeshInstance3D = null
	if _model != null and not _model.levels.is_empty():
		mesh = _model.part(node) as MeshInstance3D
		_model.attach_part(node, visual)
		if mesh == null:
			push_warning("[%s] %s: the model has no %s to draw the sliding door with" % [_tag, _host.name, node])
	var pulls: Array = row.get("pulls", [])
	var at_h := _v3(pulls[0]) if not pulls.is_empty() else fc_h + Vector3(0, 0, fs_h.z * 0.5)
	var handle := VRDrawer.new()
	handle.name = "DrawerHandle" + node
	handle.transform = Transform3D(b, at_h)
	handle.target = body_
	handle.visual = visual
	handle.travel = float(row.get("travel_m", 0.3))
	# Nothing pushes a sliding door from a face, and nothing reaches into it.
	handle.push_face_size = Vector2.ZERO
	handle.pull_face_size = Vector2.ZERO
	# In the handle's own frame: its Z the slide, its X across the door's face (out of it, the host's +Z, is -X or +X).
	var hb := CollisionShape3D.new()
	hb.name = "CollisionShape3D"
	var hbox := BoxShape3D.new()
	hbox.size = (bt * Vector3(SLIDER_HANDLE.z, SLIDER_HANDLE.y, SLIDER_HANDLE.x)).abs()
	hb.shape = hbox
	hb.position = bt * Vector3(0, 0, SLIDER_HANDLE.x * 0.5 - 0.01)
	handle.add_child(hb)
	_host.add_child(handle)
	if mesh != null:
		handle.set_handle_mesh(mesh)
	var track: Array = row.get("track", [])
	print("[%s] %s: sliding door %s along %s, %.0f mm on track %s" % [_tag, _host.name, node,
		str(_v3(row.get("axis", [1, 0, 0]))), handle.travel * 1000.0, str(track)])
	rows.append({"body": body_, "visual": visual, "handle": handle, "sliding": true,
		"inner": AABB(fc_h - fs_h * 0.5, fs_h), "row_top": fc_h.y + fs_h.y * 0.5})


## A box built in the drawer's frame (centre and size there), placed in the host's by `b`.
static func _box(shape_name: String, centre: Vector3, size: Vector3, b: Basis) -> CollisionShape3D:
	var box := BoxShape3D.new()
	box.size = size
	var cs := CollisionShape3D.new()
	cs.name = shape_name
	cs.shape = box
	cs.transform = Transform3D(b, b * centre)
	return cs


static func _v3(a: Variant) -> Vector3:
	var arr := a as Array
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
