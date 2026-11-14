## Nightstand — the RETRO XR mid-century bedside table: a walnut case on four splayed legs, an open shelf, and one
## drawer that pulls out by its brass bar (a VRDrawer) with whatever is in it riding along.
##
## The model is RetroXR-models generic/nightstand (imported-assets/furniture/nightstand/, three levels by distance on
## an ApplianceModel). Its drawer and pull are moved under `DrawerBody`, an AnimatableBody3D the VRDrawer slides, so a
## cartridge laid in the drawer is carried out and back in by friction. The drawer body never collides with the case
## it slides in (a collision exception both ways).
##
## Collision is built here from the contract's exact boxes, copied below because JSON is not exported:
## `nightstand_tests` checks the copies still match imported-assets/furniture/nightstand/nightstand_contract.json.
## The case is open where the shelf and the drawer are, so things go IN them; the legs are cylinders.
##
## Pose is the whole of its own state. How far the drawer is out is the VRDrawer's `value`, which ScenePersistence and
## netplay already record for every VRSlider (kind "slider"), so this class exists for the save row to match on.
class_name Nightstand
extends XRToolsPickable

## The model's contract, glTF frame, metres (origin = the footprint's middle on the floor, the drawer faces +Z).
## [centre, size] per box, the drawer SHUT.
const CASE_BOXES := [
	[Vector3(0.0, 0.589, 0.0), Vector3(0.5, 0.022, 0.38)],        # Top
	[Vector3(-0.226, 0.414, 0.0), Vector3(0.018, 0.328, 0.35)],   # SideL
	[Vector3(0.226, 0.414, 0.0), Vector3(0.018, 0.328, 0.35)],    # SideR
	[Vector3(0.0, 0.259, 0.0), Vector3(0.434, 0.018, 0.35)],      # Bottom
	[Vector3(0.0, 0.414, -0.171), Vector3(0.434, 0.328, 0.008)],  # Back
	[Vector3(0.0, 0.431, 0.004), Vector3(0.434, 0.018, 0.342)],   # Rail
]
## [top, foot, radius] per leg.
const LEGS := [
	[Vector3(-0.195, 0.25, 0.135), Vector3(-0.23, 0.0, 0.17), 0.015],
	[Vector3(-0.195, 0.25, -0.135), Vector3(-0.23, 0.0, -0.17), 0.015],
	[Vector3(0.195, 0.25, 0.135), Vector3(0.23, 0.0, 0.17), 0.015],
	[Vector3(0.195, 0.25, -0.135), Vector3(0.23, 0.0, -0.17), 0.015],
]
const DRAWER_BOXES := [
	[Vector3(0.0, 0.509, 0.166), Vector3(0.43, 0.134, 0.018)],    # Front
	[Vector3(0.0, 0.454, 0.012), Vector3(0.416, 0.008, 0.29)],    # Floor
	[Vector3(-0.203, 0.499, 0.012), Vector3(0.01, 0.082, 0.29)],  # WallL
	[Vector3(0.203, 0.499, 0.012), Vector3(0.01, 0.082, 0.29)],   # WallR
	[Vector3(0.0, 0.499, 0.152), Vector3(0.396, 0.082, 0.01)],    # WallF
	[Vector3(0.0, 0.499, -0.128), Vector3(0.396, 0.082, 0.01)],   # WallB
]
const DRAWER_TRAVEL := 0.25
## The drawer's inside (drawer shut, this node's frame).
const DRAWER_INNER := AABB(Vector3(-0.198, 0.458, -0.123), Vector3(0.396, 0.082, 0.27))
## Where the case's front is (this node's frame).
const CASE_FRONT_Z := 0.175
const DRAWER_HANDLE := Vector3(0.0, 0.509, 0.203)
## The middle of the drawer's floor inside (drawer shut), the top and the shelf: +Y up.
const DRAWER_SEAT := Vector3(0.0, 0.458, 0.012)
const TOP_SURFACE := Vector3(0.0, 0.6, 0.0)
const SHELF_SURFACE := Vector3(0.0, 0.268, 0.004)

@onready var _model: ApplianceModel = get_node_or_null("Model") as ApplianceModel
@onready var _drawer_body: AnimatableBody3D = $DrawerBody
@onready var _drawer: VRDrawer = $DrawerHandle
@onready var _drawer_visual: Node3D = $DrawerVisual

var _held := false
## Held and moved fast, what is in it is latched to it, or it is left behind or thrown (CarryContents).
var _carry := CarryContents.new()


func _ready() -> void:
	super()
	# After whatever holds it has moved it this tick (the grab driver, the laser's pickup): CarryContents measures that.
	process_physics_priority = 100
	add_to_group("spawned")
	var n_case := _build_shapes(self, CASE_BOXES, "Case")
	for i in LEGS.size():
		var row: Array = LEGS[i]
		add_child(_leg_shape("LegShape%d" % i, row[0], row[1], row[2]))
	var n_drawer := _build_shapes(_drawer_body, DRAWER_BOXES, "Drawer")
	_drawer_body.add_collision_exception_with(self)
	add_collision_exception_with(_drawer_body)
	_dress()
	# The inside of the drawer's front wall (DRAWER_INNER's front, up to the front's top): a hand in a part-open drawer
	# pushes it out there. In the handle's frame, as the push face in the scene.
	var front: Array = DRAWER_BOXES[0]
	var front_top: float = (front[0] as Vector3).y + (front[1] as Vector3).y * 0.5
	_drawer.pull_face_offset = DRAWER_INNER.end.z - DRAWER_HANDLE.z
	_drawer.pull_face_size = Vector2(DRAWER_INNER.size.x, front_top - DRAWER_INNER.position.y)
	_drawer.pull_face_centre = Vector2(DRAWER_INNER.get_center().x - DRAWER_HANDLE.x,
		(DRAWER_INNER.position.y + front_top) * 0.5 - DRAWER_HANDLE.y)
	# Where it carries things (CarryContents): the drawer's inside, the shelf and over the top.
	_carry.add_bin(self, _drawer_body, DRAWER_INNER.grow(0.01), collision_layer)
	_carry.add_bin(self, self, AABB(Vector3(-0.217, SHELF_SURFACE.y, -0.17), Vector3(0.434, 0.16, 0.35)), collision_layer)
	_carry.add_bin(self, self, AABB(Vector3(-0.25, TOP_SURFACE.y, -0.19), Vector3(0.5, 0.4, 0.38)), collision_layer)
	print("[Nightstand] %s: %d case boxes, %d legs, %d drawer boxes, drawer %.0f mm out of %.0f" % [name, n_case,
		LEGS.size(), n_drawer, _drawer.open_distance() * 1000.0, DRAWER_TRAVEL * 1000.0])


## The drawer, for a probe, a test or a caller that opens it.
func drawer() -> VRDrawer:
	return _drawer


## Held, the case goes on the held layer, which nothing loose collides with: what is in the drawer, on the shelf and
## on the top is held in place by CarryContents while it is carried, and let go to ordinary physics when it is put
## down. (The drawer had a held-only LID for this until 2026-11-14; CarryContents made it redundant.)
##
## The hold is POLLED (frozen, on the held layer), never `picked_up` / `dropped`: a ray grab emits neither (the addon
## restores the body itself; SurfaceStick's header has the story), so anything switched by the signals would stay on
## after a laser put the nightstand down. (An earlier version froze the drawer's contents for the hold, which read as
## frozen in a headset and was left frozen by the same missing signal.)
func _physics_process(delta: float) -> void:
	var held := freeze and collision_layer == picked_up_layer
	_carry.step(self, held, delta)
	if held != _held:
		_held = held
		print("[Nightstand] %s: %s" % [name, "held" if held else "put down"])
		if not held:
			_report_collision_later()


## What it holds in place while it is carried (a test, a probe).
func carry() -> CarryContents:
	return _carry


## What it carries things on when it is picked up (HeldObjectPhysics' riders): the top AND the shelf. Its first shape
## alone was the top, and whatever stood on the shelf hung in the air where the nightstand had been.
func rider_shapes() -> Array[CollisionShape3D]:
	var out: Array[CollisionShape3D] = []
	for shape_name in ["CaseTop", "CaseBottom"]:
		var cs := get_node_or_null(shape_name) as CollisionShape3D
		if cs != null:
			out.append(cs)
	return out


## The body things in the drawer rest on.
func drawer_body() -> AnimatableBody3D:
	return _drawer_body


## Where something laid in the drawer goes, in this node's frame, wherever the drawer is now.
func drawer_seat_local() -> Vector3:
	return DRAWER_SEAT + _drawer_body.position


func _build_shapes(body: Node, rows: Array, prefix: String) -> int:
	var names := ["Top", "SideL", "SideR", "Bottom", "Back", "Rail"] if prefix == "Case" \
		else ["Front", "Floor", "WallL", "WallR", "WallF", "WallB"]
	for i in rows.size():
		var row: Array = rows[i]
		var box := BoxShape3D.new()
		box.size = row[1]
		var cs := CollisionShape3D.new()
		cs.name = "%s%s" % [prefix, names[i]]
		cs.shape = box
		cs.position = row[0]
		body.add_child(cs)
	return rows.size()


## A cylinder from the leg's top to its foot (its Y along the leg).
static func _leg_shape(shape_name: String, top: Vector3, foot: Vector3, radius: float) -> CollisionShape3D:
	var cyl := CylinderShape3D.new()
	cyl.radius = radius
	cyl.height = top.distance_to(foot)
	var y := (top - foot).normalized()
	var x := y.cross(Vector3.FORWARD).normalized()
	var cs := CollisionShape3D.new()
	cs.name = shape_name
	cs.shape = cyl
	cs.transform = Transform3D(Basis(x, y, x.cross(y)), (top + foot) * 0.5)
	return cs


## Hang the model's drawer and pull (every level) on DrawerVisual, which the VRDrawer moves with the body, and put the
## pull's mesh in its hand.
func _dress() -> void:
	if _model == null or _model.levels.is_empty():
		push_warning("[Nightstand] %s: no model; the drawer has collision and no picture" % name)
		return
	var pull := _model.part("DrawerPull") as MeshInstance3D
	for part_name in ["Drawer", "DrawerPull"]:
		if _model.part(part_name) == null:
			push_warning("[Nightstand] %s: the model has no %s" % [name, part_name])
		_model.attach_part(part_name, _drawer_visual)
	if pull != null:
		_drawer.set_handle_mesh(pull)
	for i in range(1, _model.levels.size()):
		for m in _model.levels[i].find_children("*", "MeshInstance3D", true, false):
			m.add_to_group("outline_exclude")
	print("[Nightstand] %s: dressed (%d levels), the pull %s" % [name, _model.levels.size(),
		"found" if pull != null else "MISSING"])


## Put down: half a second on, where the physics engine has each drawer's handle and body against what is drawn. A
## report of "the collision is off after carrying it" is answered by this line.
func _report_collision_later() -> void:
	await get_tree().create_timer(0.5).timeout
	if not is_inside_tree():
		return
	var handles: Array = [_drawer]
	var rows := []
	for d: VRDrawer in handles:
		var r := d.collision_report()
		rows.append("%s area %.1f box %.1f body %.1f (node %.1f) mm" % [d.name, r["area"], r["box"], r["body"], r["node"]])
	print("[Nightstand] %s: put down at %s, collision against the nodes: %s" % [name, global_position, ", ".join(rows)])


func _exit_tree() -> void:
	super()
	_carry.release(self)
