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

## Ribbed gray plastic with a white trash symbol, wrapped once round the can
## with the symbol facing the player (the panel's +Z). Made with an image
## generator, then widened with its own ribs to the can's 3.1:1 so the symbol
## is not stretched.
const WRAP_TEXTURE := "res://Textures/trash_can_wrap.png"
## The can narrows toward its foot, like a real one.
const FOOT_SCALE := 0.82
## The lid rests shut and swings open on its hinge at the back, past upright,
## while something to delete is over the bin — so the bin answers the object
## before the outline does. After a delete it stays open while the object
## shrinks away (Vanish takes 0.3 s), then shuts.
const LID_OPEN_DEG := 105.0
const LID_HOLD_SECONDS := 0.45
## Easing rate toward the target angle: about 0.2 s to get there.
const LID_RATE := 14.0
const TRIM_COLOR := Color(0.36, 0.38, 0.41)
const INSIDE_COLOR := Color(0.07, 0.075, 0.08)
## Armed, every part takes this glow on top of its own color.
const ARMED_GLOW := Color(0.9, 0.08, 0.05)
const ARMED_TINT := Color(1.0, 0.4, 0.36)

var _area: Area3D = null
## The lit materials, each with its own color in meta "base".
var _mats: Array[StandardMaterial3D] = []
## Pickables currently outlined red (held and inside the zone), as a set.
var _armed: Dictionary = {}
## Bodies the zone has reported in and not yet out; the poll only runs while
## there is something to poll. Same scheme as StorageBox.
var _zone_bodies: Dictionary = {}
var _poll_frames: int = 0
var _active := false
var _hinge: Node3D = null
## Hinge angle in radians, 0 shut. Kept here rather than read off the node.
var _lid_angle := 0.0
## Seconds left to stay open after a delete.
var _lid_hold := 0.0


func _ready() -> void:
	var wall := _material(Color.WHITE)
	wall.albedo_texture = load(WRAP_TEXTURE) as Texture2D
	var trim := _material(TRIM_COLOR)
	# The inside is seen only from within, through the mouth: back faces of a
	# slightly smaller wall, unlit so it reads as shadow from any angle.
	var inside := StandardMaterial3D.new()
	inside.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	inside.albedo_color = INSIDE_COLOR
	inside.cull_mode = BaseMaterial3D.CULL_FRONT

	_add_part("Can", _wall_mesh(RADIUS), wall)
	_add_part("Inside", _wall_mesh(RADIUS - 0.002), inside)
	var floor_disk := CylinderMesh.new()
	floor_disk.top_radius = RADIUS * FOOT_SCALE - 0.002
	floor_disk.bottom_radius = floor_disk.top_radius
	floor_disk.height = 0.002
	floor_disk.radial_segments = 32
	_add_part("Floor", floor_disk, inside).position.y = -HEIGHT * 0.5 + 0.002

	var rim := TorusMesh.new()
	rim.inner_radius = RADIUS - 0.003
	rim.outer_radius = RADIUS + 0.005
	rim.rings = 32
	rim.ring_segments = 8
	_add_part("Rim", rim, trim).position.y = HEIGHT * 0.5

	# Lid: a disc hinged on the back of the rim, with a handle across its top.
	var hinge := Node3D.new()
	hinge.name = "LidHinge"
	hinge.position = Vector3(0.0, HEIGHT * 0.5, -RADIUS)
	add_child(hinge)
	_hinge = hinge
	var lid := CylinderMesh.new()
	lid.top_radius = RADIUS + 0.004
	lid.bottom_radius = RADIUS + 0.006
	lid.height = 0.007
	lid.radial_segments = 32
	_add_part("Lid", lid, trim, hinge).position = Vector3(0.0, 0.005, RADIUS)
	var handle := BoxMesh.new()
	handle.size = Vector3(0.032, 0.007, 0.009)
	_add_part("Handle", handle, trim, hinge).position = Vector3(0.0, 0.012, RADIUS)

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
		_set_armed_look(false)
		_lid_hold = 0.0
		_set_lid(0.0)


## True while the bin is live and has something red over it.
func is_armed() -> bool:
	return _active and not _armed.is_empty()


## How far open the lid is, 0 shut to 1 fully open.
func lid_openness() -> float:
	return _lid_angle / deg_to_rad(LID_OPEN_DEG)


func _on_zone_body_entered(body: Node3D) -> void:
	if body is XRToolsPickable:
		_zone_bodies[body] = true
	_poll_frames = POLL_GRACE_FRAMES


func _on_zone_body_exited(body: Node3D) -> void:
	_zone_bodies.erase(body)
	_poll_frames = POLL_GRACE_FRAMES


func _process(delta: float) -> void:
	if not _active:
		return
	if not (_zone_bodies.is_empty() and _armed.is_empty() and _poll_frames <= 0):
		_poll()
	_animate_lid(delta)


func _animate_lid(delta: float) -> void:
	if _lid_hold > 0.0:
		_lid_hold -= delta
	var open := not _armed.is_empty() or _lid_hold > 0.0
	var target := deg_to_rad(LID_OPEN_DEG) if open else 0.0
	if is_equal_approx(_lid_angle, target):
		return
	var angle := lerpf(_lid_angle, target, 1.0 - exp(-delta * LID_RATE))
	if absf(angle - target) < 0.002:
		angle = target
	_set_lid(angle)


func _set_lid(angle: float) -> void:
	_lid_angle = angle
	if _hinge != null:
		_hinge.rotation.x = -angle


func _poll() -> void:
	if _poll_frames > 0:
		_poll_frames -= 1

	var in_area := {}
	for body in _area.get_overlapping_bodies():
		if Trash.can_delete(body):
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
			_lid_hold = LID_HOLD_SECONDS

	_set_armed_look(not _armed.is_empty())


func _set_armed_look(on: bool) -> void:
	for m in _mats:
		var base: Color = m.get_meta("base")
		m.albedo_color = base * ARMED_TINT if on else base
		m.emission = ARMED_GLOW if on else Color.BLACK


func _material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.7
	m.emission_enabled = true
	m.emission = Color.BLACK
	m.set_meta("base", color)
	_mats.append(m)
	return m


func _add_part(part_name: String, mesh: Mesh, mat: Material, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	mi.mesh = mesh
	mi.material_override = mat
	parent.add_child(mi)
	return mi


## The tapered wall, open at both ends, with its texture wrapped once round:
## u runs round from the back so u = 0.5, the middle of the image, faces +Z.
func _wall_mesh(radius: float) -> ArrayMesh:
	const SEGMENTS := 40
	var foot := radius * FOOT_SCALE
	var h := HEIGHT * 0.5
	# The wall leans in toward the foot; its normal leans out by the same slope.
	var slope := (radius - foot) / HEIGHT
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in SEGMENTS:
		var u0 := float(i) / SEGMENTS
		var u1 := float(i + 1) / SEGMENTS
		var t0 := (u0 - 0.5) * TAU
		var t1 := (u1 - 0.5) * TAU
		var d0 := Vector3(sin(t0), 0.0, cos(t0))
		var d1 := Vector3(sin(t1), 0.0, cos(t1))
		var n0 := (d0 + Vector3(0.0, slope, 0.0)).normalized()
		var n1 := (d1 + Vector3(0.0, slope, 0.0)).normalized()
		var a := [d0 * radius + Vector3(0, h, 0), Vector2(u0, 0.0), n0]   # top left
		var b := [d0 * foot - Vector3(0, h, 0), Vector2(u0, 1.0), n0]     # foot left
		var c := [d1 * radius + Vector3(0, h, 0), Vector2(u1, 0.0), n1]   # top right
		var d := [d1 * foot - Vector3(0, h, 0), Vector2(u1, 1.0), n1]     # foot right
		# Clockwise seen from outside: Godot's front face.
		for v: Array in [a, c, d, a, d, b]:
			st.set_normal(v[2])
			st.set_uv(v[1])
			st.add_vertex(v[0])
	return st.commit()
