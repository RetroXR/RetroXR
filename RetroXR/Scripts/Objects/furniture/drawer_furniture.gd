## DrawerFurniture — a piece of furniture with drawers, all of it built from its model's contract: the case's collision,
## and for every drawer a sliding body, the node that draws it and a VRDrawer handle across its pulls. The Mission
## nightstand and six-drawer chest (RetroXR-models
## generic/mission-bedroom, imported-assets/furniture/mission/) are two scenes on this one script.
##
## The contract is read at run time: a `.json` is a JSON resource and ships with the export (vcr_contract.json is read
## the same way on a Quest). Its frame is glTF metres, the origin the middle of the footprint on the floor, the
## drawers facing +Z, every drawer SHUT.
##
## The rules learned on the walnut nightstand (docs/dev/furniture.md) hold for every drawer here:
## - a drawer's body moves on the physics tick (VRDrawer), and is DRAWN from a plain node (`DrawerVisualN`), never from
##   its synced body, which trails its case with physics interpolation on;
## - while the piece is HELD, what lies in it is held in place by CarryContents (`_carry`): a bin per drawer (framed on
##   its body, so it slides with it) and per place the contract's `surfaces` name (every top, shelf, cubby and the
##   compartment behind a door; a contract with none, the Mission pair's, gets one over its top); the hold is POLLED
##   (frozen + held layer), because a ray grab emits no picked_up / dropped.
##
## Pose is the piece's own state; each drawer is a VRDrawer (a VRSlider), saved and synced as one by its path
## (`DrawerHandleN`). The type a save names is `type_id`, as a Seat's.
##
## The living-room set (RetroXR-models generic/living-room, 2026-11-14) adds two more moving parts from the contract:
## - SLIDING doors (`drawers` rows with `kind: "sliding_door"`), built by FurnitureDrawers as VRDrawers along ±X;
## - HINGED doors (`doors` rows): each a VRDoor (`DoorN`, a child of the piece) with no knob and no latch, a push door
##   whose leaf is the model's own `DoorN` part, on a vertical hinge at its `side`, opening `open_deg` toward the
##   front (+Z). A hand takes the leaf (trigger, or the grip at its edge) and swings it, a fingertip pushes it, a
##   laser drags it and a desktop press + wheel turns it (VRHinge). Inside a spawned object, its DoorHinge is one
##   of the object's articulated controls: saved and synced with it, never as a room door.
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
## One row per drawer: {body, visual, handle (VRDrawer), inner (AABB), row_top, sliding} (_built's own array).
var _drawers: Array[Dictionary] = []
## The hinged doors (`doors` rows): VRDoors, children named by the contract's node.
var _doors: Array[VRDoor] = []
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
	_build_doors(_contract.get("doors", []))
	# Where it carries things (CarryContents): every drawer's inside (on its body), and every surface the contract names
	# (on the piece), else over the top. A sliding door carries nothing; what is behind a door is its surface's.
	for d in _drawers:
		if d.get("sliding", false):
			continue
		_carry.add_bin(self, d["body"], (d["inner"] as AABB).grow(0.01), collision_layer)
	var surfaces: Array = _contract.get("surfaces", [])
	if surfaces.is_empty():
		for cs in rider_shapes():
			var size := (cs.shape as BoxShape3D).size
			_carry.add_bin(self, self, AABB(cs.position + Vector3(-size.x, size.y, -size.z) * 0.5,
				Vector3(size.x, 0.4, size.z)), collision_layer)
	else:
		for box: AABB in surface_bins(surfaces):
			_carry.add_bin(self, self, box, collision_layer)
	if _model != null:
		for i in range(1, _model.levels.size()):
			for m in _model.levels[i].find_children("*", "MeshInstance3D", true, false):
				m.add_to_group("outline_exclude")
	print("[DrawerFurniture] %s (%s): %d case boxes, %d drawers/sliders, %d hinged doors, from %s" % [name, type_id,
		n_case, _drawers.size(), _doors.size(), contract_path.get_file()])


## The drawers' handles, top row first, left to right (a test, a probe, a caller that opens one).
func drawers() -> Array[VRDrawer]:
	if _built == null:
		return []
	return _built.handles()


## The hinged doors (VRDoor), in contract order.
func doors() -> Array[VRDoor]:
	return _doors


## Build every hinged door of the contract: a VRDoor at the door's bottom middle (the piece's frame, its Z out of the
## front), its leaf the model's own part, no knob, no latch.
func _build_doors(rows: Array) -> void:
	for row: Dictionary in rows:
		var node := str(row.get("node", "Door%d" % (_doors.size() + 1)))
		var box: Dictionary = row.get("box", {})
		if box.is_empty():
			push_warning("[DrawerFurniture] %s: door %s has no box in the contract; not built" % [name, node])
			continue
		var c := _v3(box["centre"])
		var s := _v3(box["size"])
		var door := VRDoor.new()
		door.name = node
		door.log_name = "%s/%s" % [type_id, node]
		door.position = Vector3(c.x, c.y - s.y * 0.5, 0.0)
		door.hinge_side = VRDoor.HingeSide.NEGATIVE_X if str(row.get("side", "left")) == "left" \
			else VRDoor.HingeSide.POSITIVE_X
		door.swing = VRDoor.Swing.TOWARD_POSITIVE_Z
		door.open_deg = float(row.get("open_deg", 100.0))
		door.desktop_open_deg = door.open_deg
		door.opener = VRDoor.Opener.NONE
		door.latching = false
		door.latched_at_start = false
		door.width = s.x
		door.height = s.y
		door.thickness = s.z
		door.bottom_gap = 0.0
		door.leaf_center_z = c.z
		# The leaf: the model's own door, every level, placed where it stands shut (VRDoor adopts an authored `Leaf`).
		# It is hung in the tree first, at the door's own pose, so attach_part keeps each level where it stands; then it
		# goes under the door, which is only added (and builds its rig) once it has it.
		var leaf := Node3D.new()
		leaf.name = "Leaf"
		leaf.position = door.position
		add_child(leaf)
		if _model != null and not _model.levels.is_empty():
			if _model.part(node) == null:
				push_warning("[DrawerFurniture] %s: the model has no %s to hang on its door" % [name, node])
			_model.attach_part(node, leaf)
		remove_child(leaf)
		leaf.transform = Transform3D.IDENTITY
		door.add_child(leaf)
		add_child(door)
		var body := door.get_node_or_null("HingeFrame/HingePivot/LeafBody") as CollisionObject3D
		if body != null:
			# The piece's own layer: the player walks through a pickable's parts, as through its drawers.
			body.collision_layer = collision_layer
			add_collision_exception_with(body)
			(body as PhysicsBody3D).add_collision_exception_with(self)
		print("[DrawerFurniture] %s: hinged door %s, hinge %s, %.0f deg, leaf %.3f x %.3f m%s" % [name, node,
			str(row.get("side", "")), door.open_deg, s.x, s.y, " (glass)" if bool(row.get("glass", false)) else ""])
		_doors.append(door)


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


## The bins over a contract's `surfaces` (this node's frame): each the surface's footprint, from its top up to the
## underside of the nearest surface over it (a shelf under a shelf), or SURFACE_BIN_H over an open one. Shared with a
## test, which drops a thing on every one.
const SURFACE_BIN_H := 0.4
const SURFACE_BIN_GAP := 0.01


static func surface_bins(surfaces: Array) -> Array[AABB]:
	var out: Array[AABB] = []
	for s: Dictionary in surfaces:
		var c := _v3(s["centre"])
		var size := _v3(s["size"])
		var top := float(s.get("top_y", c.y + size.y * 0.5))
		var ceiling := top + SURFACE_BIN_H
		for o: Dictionary in surfaces:
			if o == s:
				continue
			var oc := _v3(o["centre"])
			var osz := _v3(o["size"])
			var under := oc.y - osz.y * 0.5
			var overlaps := absf(oc.x - c.x) < (osz.x + size.x) * 0.5 and absf(oc.z - c.z) < (osz.z + size.z) * 0.5
			if overlaps and under > top + 0.02 and under - SURFACE_BIN_GAP < ceiling:
				ceiling = under - SURFACE_BIN_GAP
		out.append(AABB(Vector3(c.x - size.x * 0.5, top, c.z - size.z * 0.5), Vector3(size.x, ceiling - top, size.z)))
	return out


## The things this piece holds in place while it is carried (a test, a probe).
func carry() -> CarryContents:
	return _carry


## Polls the hold every tick for CarryContents (POLLED: see the header); reports the drawers once it is put down.
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
