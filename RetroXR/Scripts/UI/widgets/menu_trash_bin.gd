## MenuTrashBin — a small bin floating just outside the spawn menu's lower-left
## corner, so anything can be deleted without walking it over to the StorageBox.
##
## Works like the box: carry an object into it, by hand, on the desktop or on
## the laser, and the object's outline turns red; let go while it is red and it
## is deleted with everything it owns (Trash.delete_with_dependents). The can
## itself turns red too, since a laser-carried object can be metres away from the
## hand and the outline alone is easy to miss at the far end of a ray.
##
## Only objects that belong to something in the "spawned" group are taken, so the
## room's own furniture can be waved through it safely.
##
## Built and placed by CurvedPanel (the arc decides where the corner is). It lives
## under the menu's Viewport2DIn3D, and hiding the menu only hides that node — an
## Area3D goes on monitoring while invisible — so the bin switches itself off
## whenever it stops being visible in the tree.
class_name MenuTrashBin
extends Node3D

## Can size, in metres.
const RADIUS := 0.045
const HEIGHT := 0.09
## The catch zone is a cube a good deal bigger than the can: a carried object's
## origin is rarely where the hand is, and on the laser it is hard to place
## precisely at a distance.
const ZONE := 0.16
## The held layer (17) plus the default object layer (3), as on the StorageBox's
## TrashArea.
const ZONE_MASK := 65540
const POLL_GRACE_FRAMES := 4

const COLOR_IDLE := Color(0.42, 0.45, 0.55)
const COLOR_ARMED := Color(0.95, 0.22, 0.2)

var _area: Area3D = null
var _mat: StandardMaterial3D = null
## Pickables currently outlined red (held and inside the zone), as a set.
var _armed: Dictionary = {}
## Bodies the zone has reported in and not yet out; the poll only runs while
## there is something to poll. Same scheme as StorageBox.
var _zone_bodies: Dictionary = {}
var _poll_frames: int = 0
var _active := false


func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = COLOR_IDLE
	_mat.roughness = 0.6
	# Open-topped: the inside of the can has to draw too.
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var can := CylinderMesh.new()
	can.top_radius = RADIUS
	can.bottom_radius = RADIUS * 0.82
	can.height = HEIGHT
	can.cap_top = false
	can.radial_segments = 24
	can.rings = 1
	var can_mi := MeshInstance3D.new()
	can_mi.name = "Can"
	can_mi.mesh = can
	can_mi.material_override = _mat
	add_child(can_mi)

	var rim := TorusMesh.new()
	rim.inner_radius = RADIUS - 0.004
	rim.outer_radius = RADIUS + 0.004
	rim.rings = 24
	rim.ring_segments = 8
	var rim_mi := MeshInstance3D.new()
	rim_mi.name = "Rim"
	rim_mi.mesh = rim
	rim_mi.material_override = _mat
	rim_mi.position.y = HEIGHT * 0.5
	add_child(rim_mi)

	_area = Area3D.new()
	_area.name = "TrashArea"
	_area.collision_layer = 0
	_area.collision_mask = ZONE_MASK
	_area.monitorable = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(ZONE, ZONE, ZONE)
	shape.shape = box
	_area.add_child(shape)
	add_child(_area)
	_area.body_entered.connect(_on_zone_body_entered)
	_area.body_exited.connect(_on_zone_body_exited)

	_set_active(is_visible_in_tree())


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and _area != null:
		_set_active(is_visible_in_tree())


func _set_active(on: bool) -> void:
	if on == _active:
		return
	_active = on
	# Deferred: a hide can land inside a physics callback, where flipping
	# monitoring is refused.
	_area.set_deferred("monitoring", on)
	if not on:
		for body in _armed.keys():
			Trash.set_highlight(body as XRToolsPickable, false)
		_armed.clear()
		_zone_bodies.clear()
		_poll_frames = 0
		_mat.albedo_color = COLOR_IDLE


## True while the bin is live and has something red over it.
func is_armed() -> bool:
	return _active and not _armed.is_empty()


## Whether `body` is something the bin may delete: it, or a node above it (a
## lead's plug, a cover on its slot), is in the "spawned" group.
static func binnable(body: Node) -> bool:
	var n := body
	while n != null:
		if n.is_in_group("spawned"):
			return true
		n = n.get_parent()
	return false


func _on_zone_body_entered(body: Node3D) -> void:
	if body is XRToolsPickable:
		_zone_bodies[body] = true
	_poll_frames = POLL_GRACE_FRAMES


func _on_zone_body_exited(body: Node3D) -> void:
	_zone_bodies.erase(body)
	_poll_frames = POLL_GRACE_FRAMES


func _process(_delta: float) -> void:
	if not _active:
		return
	if _zone_bodies.is_empty() and _armed.is_empty() and _poll_frames <= 0:
		return
	if _poll_frames > 0:
		_poll_frames -= 1

	var in_area := {}
	for body in _area.get_overlapping_bodies():
		if body is XRToolsPickable and binnable(body):
			in_area[body] = true
	for body in _zone_bodies.keys():
		if not is_instance_valid(body):
			_zone_bodies.erase(body)

	for body in in_area.keys():
		if not _armed.has(body) and Trash.is_held(body as XRToolsPickable):
			_armed[body] = true
			Trash.set_highlight(body as XRToolsPickable, true)

	for body in _armed.keys():
		if not is_instance_valid(body):
			_armed.erase(body)
			continue
		var pickable := body as XRToolsPickable
		if not in_area.has(body):
			_armed.erase(body)
			Trash.set_highlight(pickable, false)
		elif not Trash.is_held(pickable):
			# Let go over the bin.
			_armed.erase(body)
			Trash.set_highlight(pickable, false)
			print("[MenuTrashBin] deleting '%s'" % pickable.name)
			Trash.delete_with_dependents(pickable)

	_mat.albedo_color = COLOR_ARMED if not _armed.is_empty() else COLOR_IDLE
