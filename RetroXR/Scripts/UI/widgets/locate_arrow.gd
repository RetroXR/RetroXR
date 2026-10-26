## LocateArrow -- "it is over there": an arrow at the edge of the player's view
## pointing the way to turn, for the SCENE menu's Locate.
##
## The Objects list can name a cartridge eight metres away behind the bed, and an
## outline alone is no help when it is behind you. So while an object is being
## located its outline turns cyan (PickableHighlight.set_located) and this arrow
## rides the camera, on a ring round the line of sight, pointing the way to turn.
## It hides as soon as the object is within FOUND_DEG of where the player looks
## (the outline is enough from there) and gives up once the object has been in
## view for FOUND_SECONDS, or after GIVE_UP_SECONDS whatever happened.
##
## It outlives the menu on purpose: you press Locate, shut the menu, and turn.
## One per camera (`on()`), so a second Locate hands it the new object.
##
## A mesh, not a SubViewport like HudToasts: there is nothing to lay out, and a
## camera child is the same node on desktop and in the headset.
class_name LocateArrow
extends Node3D

## Within this angle of the view's centre the object counts as found.
const FOUND_DEG := 30.0
const FOUND_SECONDS := 2.0
const GIVE_UP_SECONDS := 10.0
## Where the arrow sits: DEPTH in front of the eye, RING off the line of sight
## (about 15 degrees, inside even a narrow headset's view).
const DEPTH := 0.55
const RING := 0.15
## How fast the arrow swings round the ring to a new bearing. Snapping it there
## every frame makes it twitch with every small turn of the head.
const SWING_RATE := 12.0
const COLOR := Color(0.2, 0.9, 1.0)
const RENDER_PRIORITY := 6

var _camera: Node3D = null
var _target: Node3D = null
var _target_name := ""
var _mesh: MeshInstance3D = null
var _material: StandardMaterial3D = null
var _bearing := 0.0
var _elapsed := 0.0
var _seen := 0.0


## The arrow riding `camera`, made the first time it is asked for.
static func on(camera: Node3D) -> LocateArrow:
	var existing := camera.get_node_or_null("LocateArrow") as LocateArrow
	if existing != null:
		return existing
	var arrow := LocateArrow.new()
	arrow.name = "LocateArrow"
	arrow._camera = camera
	camera.add_child(arrow)
	return arrow


## Where the arrow goes for an object whose direction from the eye, in the
## CAMERA's frame (-Z ahead, +Y up), is `dir`. `shown` false: it is in view.
## `bearing` is clockwise from straight up, so +PI/2 is the right edge. Straight
## behind there is no "up" to point to, so behind the player it is always left or
## right -- the way to turn -- and never an arrow pointing into their face.
static func place(dir: Vector3) -> Dictionary:
	var d := dir.normalized()
	if d.is_zero_approx():
		return {"shown": false, "bearing": 0.0}
	var off_axis := rad_to_deg(acos(clampf(-d.z, -1.0, 1.0)))
	if off_axis < FOUND_DEG:
		return {"shown": false, "bearing": 0.0}
	if d.z > 0.0:
		return {"shown": true, "bearing": PI / 2.0 if d.x >= 0.0 else -PI / 2.0}
	return {"shown": true, "bearing": atan2(d.x, d.y)}


## Point the player at `target` (and outline it), replacing whatever was being
## located before.
func locate(target: Node3D, display_name: String) -> void:
	if _target != null and _target != target:
		_end("replaced")
	_target = target
	_target_name = display_name
	_elapsed = 0.0
	_seen = 0.0
	_set_outline(true)
	print("[Locate] tracking '%s'" % display_name)
	set_process(true)


func is_locating() -> bool:
	return _target != null


func target() -> Node3D:
	return _target


func _ready() -> void:
	_build()
	visible = false
	set_process(_target != null)


func _build() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.no_depth_test = true
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.render_priority = RENDER_PRIORITY
	_material.albedo_color = COLOR

	_mesh = MeshInstance3D.new()
	_mesh.name = "Arrow"
	_mesh.mesh = _arrow_mesh()
	_mesh.material_override = _material
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh)


## A flat arrow in the XY plane pointing +Y, 6 cm long, its middle at the origin.
static func _arrow_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tri := func(a: Vector2, b: Vector2, c: Vector2) -> void:
		for p: Vector2 in [a, b, c]:
			st.add_vertex(Vector3(p.x, p.y, 0.0))
	# Head.
	tri.call(Vector2(0.0, 0.030), Vector2(-0.024, 0.002), Vector2(0.024, 0.002))
	# Shaft.
	tri.call(Vector2(-0.008, 0.002), Vector2(0.008, 0.002), Vector2(0.008, -0.030))
	tri.call(Vector2(-0.008, 0.002), Vector2(0.008, -0.030), Vector2(-0.008, -0.030))
	return st.commit()


func _process(delta: float) -> void:
	if _target == null:
		set_process(false)
		visible = false
		return
	if not is_instance_valid(_target) or not _target.is_inside_tree() \
			or Vanish.is_vanishing(_target):
		_end("target gone")
		return
	if _camera == null:
		_camera = get_parent() as Node3D
	_elapsed += delta
	var to := _target.global_position - _camera.global_position
	var where := place(_camera.global_transform.basis.inverse() * to)
	if not where["shown"]:
		_seen += delta
		visible = false
		if _seen >= FOUND_SECONDS:
			_end("found")
		return
	if _elapsed >= GIVE_UP_SECONDS:
		_end("timed out")
		return
	var want: float = where["bearing"]
	_bearing = want if not visible else lerp_angle(_bearing, want, clampf(SWING_RATE * delta, 0.0, 1.0))
	visible = true
	_pose(_bearing)
	_material.albedo_color.a = 0.7 + 0.3 * sin(_elapsed * TAU)


## Put the arrow on the ring at `bearing`, pointing outward along it.
func _pose(bearing: float) -> void:
	position = Vector3(sin(bearing) * RING, cos(bearing) * RING, -DEPTH)
	# The mesh points +Y; turning it by -bearing about Z points it at the bearing.
	rotation = Vector3(0.0, 0.0, -bearing)


func _end(why: String) -> void:
	print("[Locate] %s '%s' after %.1f s" % [why, _target_name, _elapsed])
	_set_outline(false)
	_target = null
	_target_name = ""
	visible = false
	set_process(false)


func _set_outline(on: bool) -> void:
	if not is_instance_valid(_target):
		return
	for child in _target.get_children():
		if child is PickableHighlight:
			(child as PickableHighlight).set_located(on)
			return
