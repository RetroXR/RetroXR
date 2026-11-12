## FurnitureDrawers — the drawers of a piece of furniture, built from its model's contract: for every drawer a sliding
## body, the node that draws it, a VRDrawer handle across its pulls, and the lid it gets while the piece is carried.
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
class_name FurnitureDrawers
extends RefCounted

## Drawer walls and floor, as built in the models (RetroXR-models params.py BOX_T, FLOOR_T).
const WALL_T := 0.011
const FLOOR_T := 0.008
## The handle box: past the outermost pulls by this much either side, this tall and deep.
const HANDLE_MARGIN := 0.05
const HANDLE_H := 0.06
const HANDLE_D := 0.04
## The lid's clearance under the rail above and over the drawer's walls.
const LID_GAP := 0.002

## One row per drawer: {body, visual, handle (VRDrawer), lid, inner (AABB, the host's frame), row_top}.
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


## Whether drawer `i`'s lid is on (the piece held).
func lid_on(i: int) -> bool:
	return not (rows[i]["lid"] as CollisionShape3D).disabled


## Held, every drawer gets its lid; put down, none has one. The caller POLLS the hold (frozen + held layer: a ray grab
## emits no picked_up / dropped) and passes it; returns true when it changed.
func step(held: bool) -> bool:
	if held == _held:
		return false
	_held = held
	print("[%s] %s: %s; %d drawer lid(s) %s" % [_tag, _host.name, "held" if held else "put down", rows.size(),
		"on" if held else "off"])
	for d in rows:
		var lid := d["lid"] as CollisionShape3D
		lid.disabled = not held or lid.has_meta(&"no_room")
	return true


## The basis of a drawer that slides out along `axis` (in the host's frame): its Z the axis, its Y up.
static func axis_basis(axis: Vector3) -> Basis:
	var z := axis.normalized()
	if z.is_equal_approx(Vector3.BACK):
		return Basis.IDENTITY
	var y := Vector3.UP
	var x := y.cross(z).normalized()
	return Basis(x, z.cross(x).normalized(), z)


func _build_drawer(row: Dictionary) -> void:
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
	# The lid: over the WHOLE drawer, under the rail above, sized once. It is only switched on and off (while the piece is
	# held). Fitted every tick to the part still inside the case, it was a shape rebuilt every tick on a moving body, and
	# what lay in the drawer fell through its floor or was thrown out of it as the piece was picked up (2026-11-12).
	var lid_y0 := inner.end.y + LID_GAP
	var lid_y1 := float(row.get("row_top_y", inner.end.y + 0.02)) - LID_GAP
	var lid := _box("Lid", Vector3(inner.get_center().x, (lid_y0 + lid_y1) * 0.5, inner.get_center().z),
		Vector3(inner.size.x, maxf(lid_y1 - lid_y0, 0.002), inner.size.z), b)
	lid.disabled = true
	if lid_y1 - lid_y0 < 0.002:
		lid.set_meta(&"no_room", true)
		push_warning("[%s] %s: no room for %s's lid under the rail above it" % [_tag, _host.name, node])
	body_.add_child(lid)
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
	var hb := _box("CollisionShape3D", Vector3(0, 0, (front_face_z - at.z) * 0.5 + HANDLE_D * 0.25),
		Vector3(x1 - x0 + 2 * HANDLE_MARGIN, HANDLE_H, HANDLE_D), Basis.IDENTITY)
	handle.add_child(hb)
	_host.add_child(handle)
	if mesh != null:
		handle.set_handle_mesh(mesh)
	rows.append({"body": body_, "visual": visual, "handle": handle, "lid": lid,
		"inner": AABB(ic_h - isz_h * 0.5, isz_h), "row_top": float(row.get("row_top_y", inner.end.y + 0.02))})


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
