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

@onready var _model: ApplianceModel = get_node_or_null("Model") as ApplianceModel

var _contract: Dictionary = {}
## The drawers: FurnitureDrawers builds them (a bed's drawers are built by the same code).
var _built: FurnitureDrawers = null
## One row per drawer: {body, visual, handle (VRDrawer), lid, inner (AABB), row_top} (_built's own array).
var _drawers: Array[Dictionary] = []
var _case_front_z := 0.0
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
	_built = FurnitureDrawers.new(self, _model, "DrawerFurniture")
	_built.build(_contract.get("drawers", []))
	_drawers = _built.rows
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
	if _built == null:
		return []
	return _built.handles()


## The body things in drawer `i` rest on.
func drawer_body(i: int) -> AnimatableBody3D:
	return _built.body(i)


## The middle of drawer `i`'s floor inside, in this node's frame, wherever the drawer is now.
func drawer_seat_local(i: int) -> Vector3:
	return _built.seat_local(i)


## What it carries things on when it is picked up (HeldObjectPhysics' riders): its top.
func rider_shapes() -> Array[CollisionShape3D]:
	var out: Array[CollisionShape3D] = []
	for c in get_children():
		if c is CollisionShape3D and String(c.name).begins_with("CaseTop_"):
			out.append(c as CollisionShape3D)
	return out


## Whether drawer `i`'s lid is on (the piece held).
func lid_on(i: int) -> bool:
	return _built.lid_on(i)


## Held, every drawer gets its lid; put down, none has one. POLLED: see the header.
func _physics_process(delta: float) -> void:
	var held := freeze and collision_layer == picked_up_layer
	_carry.step(self, held, delta)
	if _built != null and _built.step(held) and not held:
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
