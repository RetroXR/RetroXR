## DrawerFurniture — a piece of furniture with drawers, all of it built from its model's contract: the case's collision,
## and for every drawer a sliding body, the node that draws it, a VRDrawer handle across its pulls, and the lid it
## gets while the piece is carried. The Mission nightstand and six-drawer chest (RetroXR-models
## generic/mission-bedroom, imported-assets/furniture/mission/) are two scenes on this one script.
##
## The contract is read at run time: a `.json` is a JSON resource and ships with the export (vcr_contract.json is read
## the same way on a Quest). Its frame is glTF metres, the origin the middle of the footprint on the floor, the
## drawers facing +Z, every drawer SHUT.
##
## The rules learned on the walnut nightstand (docs/dev/furniture.md) hold for every drawer here:
## - a drawer's body moves on the physics tick (VRDrawer), and is DRAWN from a plain node (`DrawerVisualN`), never from
##   its synced body, which trails its case with physics interpolation on;
## - while the piece is HELD, its case is on the held layer and nothing loose meets it, so each drawer gets a lid
##   under the rail above it, over the part still inside the case; the hold is POLLED (frozen + held layer), because
##   a ray grab emits no picked_up / dropped;
## - what stands on the top rides through HeldObjectPhysics (`rider_shapes`).
##
## Pose is the piece's own state; each drawer is a VRDrawer (a VRSlider), saved and synced as one by its path
## (`DrawerHandleN`). The type a save names is `type_id`, as a Seat's.
class_name DrawerFurniture
extends XRToolsPickable

## The model's contract.
@export_file("*.json") var contract_path := ""
## The type the scene is saved and spawned as.
@export var type_id := ""

## Drawer walls and floor, as built in the model (RetroXR-models params.py BOX_T, FLOOR_T).
const WALL_T := 0.011
const FLOOR_T := 0.008
## The handle box: past the outermost pulls by this much either side, this tall and deep.
const HANDLE_MARGIN := 0.05
const HANDLE_H := 0.06
const HANDLE_D := 0.04
## The lid's clearance under the rail above and over the drawer's walls.
const LID_GAP := 0.002

@onready var _model: ApplianceModel = get_node_or_null("Model") as ApplianceModel

var _contract: Dictionary = {}
## One row per drawer: {body, visual, handle (VRDrawer), lid, inner (AABB), row_top}.
var _drawers: Array[Dictionary] = []
var _case_front_z := 0.0
var _held := false
## Held and moved fast, what is in it is latched to it, or it is left behind or thrown (CarryContents).
var _carry := CarryContents.new()


func _ready() -> void:
	super()
	# After whatever holds it has moved it this tick (the grab driver, the laser's pickup): CarryContents measures that.
	process_physics_priority = 100
	add_to_group("spawned")
	_contract = DeckFace.contract(contract_path, "DrawerFurniture")
	if _contract.is_empty():
		push_warning("[DrawerFurniture] %s: no contract at %s; nothing to build" % [name, contract_path])
		return
	_case_front_z = float(_contract.get("case_front_z", 0.0))
	var n_case := 0
	var collision: Dictionary = _contract.get("collision", {})
	for row: Dictionary in collision.get("case", []):
		var cs := _box("Case%s_%d" % [row.get("name", "Box"), n_case], _v3(row["centre"]), _v3(row["size"]))
		add_child(cs)
		n_case += 1
	for row: Dictionary in _contract.get("drawers", []):
		_build_drawer(row)
	# Where it carries things (CarryContents): every drawer's inside, and over the top.
	for d in _drawers:
		_carry.add_bin(self, d["body"], (d["inner"] as AABB).grow(0.01), collision_layer)
	for cs in rider_shapes():
		var size := (cs.shape as BoxShape3D).size
		_carry.add_bin(self, self, AABB(cs.position + Vector3(-size.x, size.y, -size.z) * 0.5,
			Vector3(size.x, 0.4, size.z)), collision_layer)
	if _model != null:
		for i in range(1, _model.levels.size()):
			for m in _model.levels[i].find_children("*", "MeshInstance3D", true, false):
				m.add_to_group("outline_exclude")
	print("[DrawerFurniture] %s (%s): %d case boxes, %d drawers, from %s" % [name, type_id, n_case, _drawers.size(),
		contract_path.get_file()])


## The drawers' handles, top row first, left to right (a test, a probe, a caller that opens one).
func drawers() -> Array[VRDrawer]:
	var out: Array[VRDrawer] = []
	for d in _drawers:
		out.append(d["handle"] as VRDrawer)
	return out


## The body things in drawer `i` rest on.
func drawer_body(i: int) -> AnimatableBody3D:
	return _drawers[i]["body"] as AnimatableBody3D


## The middle of drawer `i`'s floor inside, in this node's frame, wherever the drawer is now.
func drawer_seat_local(i: int) -> Vector3:
	var inner: AABB = _drawers[i]["inner"]
	return Vector3(inner.get_center().x, inner.position.y, inner.get_center().z) + drawer_body(i).position


## What it carries things on when it is picked up (HeldObjectPhysics' riders): its top.
func rider_shapes() -> Array[CollisionShape3D]:
	var out: Array[CollisionShape3D] = []
	for c in get_children():
		if c is CollisionShape3D and String(c.name).begins_with("CaseTop_"):
			out.append(c as CollisionShape3D)
	return out


## Whether drawer `i`'s lid is on (the piece held).
func lid_on(i: int) -> bool:
	return not (_drawers[i]["lid"] as CollisionShape3D).disabled


func _build_drawer(row: Dictionary) -> void:
	var node := String(row.get("node", "Drawer%d" % (_drawers.size() + 1)))
	var n := node.trim_prefix("Drawer")
	var front: Dictionary = row["front"]
	var fc := _v3(front["centre"])
	var fs := _v3(front["size"])
	var ic := _v3(row["inner"]["centre"])
	var isz := _v3(row["inner"]["size"])
	var inner := AABB(ic - isz * 0.5, isz)
	# The body things in the drawer rest on: its front, floor and four walls, all collision, drawn by nothing.
	var body := AnimatableBody3D.new()
	body.name = "DrawerBody" + n
	body.collision_layer = collision_layer
	body.collision_mask = collision_mask
	body.physics_material_override = physics_material_override
	# OFF: a plain child of the piece, turning and travelling with it (furniture.md: synced, it kept its own world pose).
	body.sync_to_physics = false
	add_child(body)
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
		body.add_child(_box("Box" + String(s[0]), s[1], s[2]))
	# The lid: over the WHOLE drawer, under the rail above, sized once. It is only switched on and off (while the piece is
	# held). Fitted every tick to the part still inside the case, it was a shape rebuilt every tick on a moving body, and
	# what lay in the drawer fell through its floor or was thrown out of it as the piece was picked up (2026-11-12).
	var lid := CollisionShape3D.new()
	lid.name = "Lid"
	var lid_box := BoxShape3D.new()
	var lid_y0 := inner.end.y + LID_GAP
	var lid_y1 := float(row.get("row_top_y", inner.end.y + 0.02)) - LID_GAP
	lid_box.size = Vector3(inner.size.x, maxf(lid_y1 - lid_y0, 0.002), inner.size.z)
	lid.shape = lid_box
	lid.position = Vector3(inner.get_center().x, (lid_y0 + lid_y1) * 0.5, inner.get_center().z)
	lid.disabled = true
	if lid_y1 - lid_y0 < 0.002:
		lid.set_meta(&"no_room", true)
		push_warning("[DrawerFurniture] %s: no room for %s's lid under the rail above it" % [name, node])
	body.add_child(lid)
	body.add_collision_exception_with(self)
	add_collision_exception_with(body)
	# What draws it: the model's drawer (front, box and pulls, every level) hangs here.
	var visual := Node3D.new()
	visual.name = "DrawerVisual" + n
	add_child(visual)
	var mesh: MeshInstance3D = null
	if _model != null and not _model.levels.is_empty():
		mesh = _model.part(node) as MeshInstance3D
		_model.attach_part(node, visual)
	else:
		push_warning("[DrawerFurniture] %s: no model to hang %s from" % [name, node])
	# The handle: one box across all of its pulls, at the pulls' middle with the drawer shut.
	var pulls: Array = row.get("pulls", [])
	var at := Vector3.ZERO
	var x0 := INF
	var x1 := -INF
	for p: Array in pulls:
		var v := _v3(p)
		at += v
		x0 = minf(x0, v.x)
		x1 = maxf(x1, v.x)
	at = at / maxf(pulls.size(), 1) if not pulls.is_empty() else Vector3(fc.x, fc.y, fc.z + fs.z * 0.5)
	if pulls.is_empty():
		x0 = fc.x
		x1 = fc.x
	var handle := VRDrawer.new()
	handle.name = "DrawerHandle" + n
	handle.position = at
	handle.target = body
	handle.visual = visual
	handle.travel = float(row.get("travel_m", 0.25))
	var front_face_z := fc.z + fs.z * 0.5
	handle.push_face_offset = front_face_z - at.z
	handle.push_face_size = Vector2(fs.x, fs.y)
	handle.push_face_centre = Vector2(fc.x - at.x, fc.y - at.y)
	var hb := _box("CollisionShape3D", Vector3(0, 0, (front_face_z - at.z) * 0.5 + HANDLE_D * 0.25),
		Vector3(x1 - x0 + 2 * HANDLE_MARGIN, HANDLE_H, HANDLE_D))
	handle.add_child(hb)
	add_child(handle)
	if mesh != null:
		handle.set_handle_mesh(mesh)
	_drawers.append({"body": body, "visual": visual, "handle": handle, "lid": lid, "inner": inner,
		"row_top": float(row.get("row_top_y", inner.end.y + 0.02))})


## Held, every drawer gets its lid; put down, none has one. POLLED: see the header.
func _physics_process(delta: float) -> void:
	var held := freeze and collision_layer == picked_up_layer
	_carry.step(self, held, delta)
	if held != _held:
		_held = held
		print("[DrawerFurniture] %s: %s; %d drawer lid(s) %s" % [name, "held" if held else "put down",
			_drawers.size(), "on" if held else "off"])
		for d in _drawers:
			var lid := d["lid"] as CollisionShape3D
			lid.disabled = not held or lid.has_meta(&"no_room")
		if not held:
			_report_collision_later()


func _box(shape_name: String, centre: Vector3, size: Vector3) -> CollisionShape3D:
	var box := BoxShape3D.new()
	box.size = size
	var cs := CollisionShape3D.new()
	cs.name = shape_name
	cs.shape = box
	cs.position = centre
	return cs


static func _v3(a: Variant) -> Vector3:
	var arr := a as Array
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))


## Put down: half a second on, where the physics engine has each drawer's handle and body against what is drawn. A
## report of "the collision is off after carrying it" is answered by this line.
func _report_collision_later() -> void:
	await get_tree().create_timer(0.5).timeout
	if not is_inside_tree():
		return
	var handles: Array = drawers()
	var rows := []
	for d: VRDrawer in handles:
		var r := d.collision_report()
		rows.append("%s area %.1f box %.1f body %.1f (node %.1f) mm" % [d.name, r["area"], r["box"], r["body"], r["node"]])
	print("[DrawerFurniture] %s: put down at %s, collision against the nodes: %s" % [name, global_position, ", ".join(rows)])


func _exit_tree() -> void:
	super()
	_carry.release(self)
