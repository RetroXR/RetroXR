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
const DRAWER_HANDLE := Vector3(0.0, 0.509, 0.203)
## The middle of the drawer's floor inside (drawer shut), the top and the shelf: +Y up.
const DRAWER_SEAT := Vector3(0.0, 0.458, 0.012)
const TOP_SURFACE := Vector3(0.0, 0.6, 0.0)
const SHELF_SURFACE := Vector3(0.0, 0.268, 0.004)

@onready var _model: ApplianceModel = get_node_or_null("Model") as ApplianceModel
@onready var _drawer_body: AnimatableBody3D = $DrawerBody
@onready var _drawer: VRDrawer = $DrawerHandle


func _ready() -> void:
	super()
	add_to_group("spawned")
	var n_case := _build_shapes(self, CASE_BOXES, "Case")
	for i in LEGS.size():
		var row: Array = LEGS[i]
		add_child(_leg_shape("LegShape%d" % i, row[0], row[1], row[2]))
	var n_drawer := _build_shapes(_drawer_body, DRAWER_BOXES, "Drawer")
	_drawer_body.add_collision_exception_with(self)
	add_collision_exception_with(_drawer_body)
	_dress()
	print("[Nightstand] %s: %d case boxes, %d legs, %d drawer boxes, drawer %.0f mm out of %.0f" % [name, n_case,
		LEGS.size(), n_drawer, _drawer.open_distance() * 1000.0, DRAWER_TRAVEL * 1000.0])


## The drawer, for a probe, a test or a caller that opens it.
func drawer() -> VRDrawer:
	return _drawer


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


## Put the model's drawer and pull (every level) on the drawer body, and the pull's mesh in the VRDrawer's hand.
func _dress() -> void:
	if _model == null or _model.levels.is_empty():
		push_warning("[Nightstand] %s: no model; the drawer has collision and no picture" % name)
		return
	var pull := _model.part("DrawerPull") as MeshInstance3D
	for part_name in ["Drawer", "DrawerPull"]:
		if _model.part(part_name) == null:
			push_warning("[Nightstand] %s: the model has no %s" % [name, part_name])
		_model.attach_part(part_name, _drawer_body)
	if pull != null:
		_drawer.set_handle_mesh(pull)
	for i in range(1, _model.levels.size()):
		for m in _model.levels[i].find_children("*", "MeshInstance3D", true, false):
			m.add_to_group("outline_exclude")
	print("[Nightstand] %s: dressed (%d levels), the pull %s" % [name, _model.levels.size(),
		"found" if pull != null else "MISSING"])
