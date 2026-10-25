## GroundPlacement — set a big thing down on the floor by pointing at the spot.
##
## An arcade cabinet is 1.8 m tall and heavy, and dropped from a hand it lands wherever it falls,
## tipped and in the way of the next one. Hold it and AIM AT THE FLOOR instead and a yellow rectangle
## the size of its base shows on the ground where it will stand; let go, and it is stood there,
## upright, its front toward you, with no fall. Aim anywhere else (level, up, or too far) and it is
## dropped as ever. So a row of cabinets is a row of rectangles.
##
## The aim is the holding hand's pointing direction in a headset (the controller's -Z), the camera's
## on the desktop, where the hand is the gaze. `placement_for` is the whole decision and is pure:
## what the rectangle shows is what a release does, because the release uses the last answer it gave.
class_name GroundPlacement
extends Node

## How far below level the aim must point to count as "at the floor": the sine of the angle (0.30 is
## about 17 degrees). A hand held out in front is level or a little down; this is pointing at the ground.
const MIN_DOWN := 0.30
## Farthest the spot may be from the one aiming, along the floor.
const MAX_REACH := 4.0
const YELLOW := Color(1.0, 0.85, 0.10)
const EDGE := 0.025
const HEIGHT := 0.012

## The pickable this places (a RetroSystem).
var host: Node3D = null
## The base of the thing, metres: width across its front, depth front to back, with its front toward +Z.
var footprint := Vector2(0.66, 0.80)
## Where the middle of that rectangle is from the thing's origin, (x, z): zero when the origin is its middle,
## forward of it for a cabinet whose cockpit or stage stands in front.
var footprint_center := Vector2.ZERO

var _marker: Node3D = null
var _placement := {}
var _previewed := false


## Where a thing aimed at the floor stands. `origin` and `dir` are the aim; `eye` is where the player
## is, so the front of the thing turns to face them. {} when the aim is not at the floor. Pure.
static func placement_for(origin: Vector3, dir: Vector3, floor_y: float, eye: Vector3) -> Dictionary:
	if dir.length_squared() < 0.000001:
		return {}
	var d := dir.normalized()
	if d.y > -MIN_DOWN:
		return {}
	var t := (floor_y - origin.y) / d.y
	if t <= 0.0:
		return {}
	var hit := origin + d * t
	if Vector2(hit.x - origin.x, hit.z - origin.z).length() > MAX_REACH:
		return {}
	var toward := Vector3(eye.x - hit.x, 0.0, eye.z - hit.z)
	var yaw := atan2(toward.x, toward.z) if toward.length_squared() > 0.0001 else 0.0
	return {"position": Vector3(hit.x, floor_y, hit.z), "yaw": yaw}


## The pose a placement stands the thing at.
static func pose_of(placement: Dictionary) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, float(placement["yaw"])), placement["position"] as Vector3)


func _ready() -> void:
	if host != null and host.has_signal("dropped"):
		host.connect("dropped", _on_dropped)


## A new base (a cabinet that took another form): the rectangle is drawn again the next time it shows.
func set_footprint(size: Vector2, center: Vector2 = Vector2.ZERO) -> void:
	if size.is_equal_approx(footprint) and center.is_equal_approx(footprint_center):
		return
	footprint = size
	footprint_center = center
	if is_instance_valid(_marker):
		var shown := _marker.visible
		_marker.queue_free()
		_marker = null
		if shown:
			_show(true)


func _exit_tree() -> void:
	if is_instance_valid(_marker):
		_marker.queue_free()
	_marker = null


func _physics_process(_delta: float) -> void:
	if _previewed:
		return
	if host == null or not is_instance_valid(host) or not host.has_method("is_picked_up") \
			or not bool(host.call("is_picked_up")):
		_placement = {}
		_show(false)
		return
	var aim := _aim()
	if aim.is_empty():
		_placement = {}
		_show(false)
		return
	_set_marker(placement_for(aim["origin"], aim["dir"], _floor_y(), aim["eye"]))


## Show the rectangle at `placement` and keep it there ({} gives the aim back its say): for a probe to
## photograph, since nothing is holding the cabinet.
func preview(placement: Dictionary) -> void:
	_previewed = not placement.is_empty()
	_set_marker(placement)


func _set_marker(placement: Dictionary) -> void:
	_placement = placement
	_show(not _placement.is_empty())
	if not _placement.is_empty():
		_marker.global_transform = pose_of(_placement).translated_local(Vector3(0, HEIGHT, 0))


## The rectangle on the ground now, or {}: for the tests.
func current_placement() -> Dictionary:
	return _placement


## Stand the thing at `placement`, upright and at rest.
func apply(placement: Dictionary) -> void:
	if placement.is_empty() or host == null or not is_instance_valid(host):
		return
	var pose := pose_of(placement)
	host.global_transform = pose
	if host is RigidBody3D:
		var body := host as RigidBody3D
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, pose)
		PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
		PhysicsServer3D.body_set_state(body.get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)


## Let go while the rectangle was showing: stand it there, once the release has finished with it.
func _on_dropped(_pickable: Variant = null) -> void:
	if _placement.is_empty():
		return
	var chosen := _placement
	_placement = {}
	_show(false)
	apply.call_deferred(chosen)


## The aim: {origin, dir, eye}, or {} with nothing to aim from.
func _aim() -> Dictionary:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null:
		return {}
	var controller: Node3D = null
	if host.has_method("get_picked_up_by_controller"):
		controller = host.call("get_picked_up_by_controller") as Node3D
	if controller != null:
		return {"origin": controller.global_position, "dir": -controller.global_basis.z,
			"eye": cam.global_position}
	return {"origin": cam.global_position, "dir": -cam.global_basis.z, "eye": cam.global_position}


## The floor under the player: the XR origin's height, else the world's zero.
func _floor_y() -> float:
	var cam := get_viewport().get_camera_3d()
	var node: Node = cam.get_parent() if cam != null else null
	while node != null:
		if node is XROrigin3D:
			return (node as XROrigin3D).global_position.y
		node = node.get_parent()
	return 0.0


func _show(on: bool) -> void:
	if on and not is_instance_valid(_marker):
		_build_marker()
	if is_instance_valid(_marker):
		_marker.visible = on


## A frame and a faint fill in the size of the base, and a thicker bar along the FRONT so the player
## sees which way it will face. Unshaded and off the shadow pass, so it reads the same in any room.
func _build_marker() -> void:
	var root := get_tree().current_scene if is_inside_tree() else null
	if root == null:
		return
	_marker = Node3D.new()
	_marker.name = "GroundPlacementMarker"
	root.add_child(_marker)
	var edge := _mat(Color(YELLOW, 1.0))
	var fill := _mat(Color(YELLOW, 0.22))
	var w := footprint.x
	var d := footprint.y
	var c := Vector3(footprint_center.x, 0.0, footprint_center.y)
	_box(Vector3(w, 0.002, d), c, fill)
	for side in [-1.0, 1.0]:
		_box(Vector3(EDGE, HEIGHT * 0.5, d), c + Vector3(side * (w - EDGE) * 0.5, 0, 0), edge)
		_box(Vector3(w, HEIGHT * 0.5, EDGE), c + Vector3(0, 0, side * (d - EDGE) * 0.5), edge)
	# The front (+Z): a second, wider bar just inside the edge.
	_box(Vector3(w * 0.6, HEIGHT * 0.5, EDGE * 2.0), c + Vector3(0, 0, d * 0.5 - EDGE * 3.0), edge)


func _box(size: Vector3, at: Vector3, material: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = material
	mi.mesh = bm
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.add_child(mi)


func _mat(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m
