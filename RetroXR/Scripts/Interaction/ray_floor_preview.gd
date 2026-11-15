## Shared desktop/VR ray placement. A local visual, never a networked object.
class_name RayFloorPreview
extends Node3D

const SHADER := preload("res://Shaders/ray_floor_preview.gdshader")
const ACTION := &"desktop_floor_preview"
const PLACING_META := &"_ray_floor_placing"
const SUPPORT_MASK := (1 << 0) | (1 << 2) | (1 << 18)
const CLEARANCE := 0.003
const MAX_DROP := 50.0

## Source supplies floor_preview_target() and floor_preview_modifier().
var source: Node3D
var _heading := Vector3.BACK
var _mesh: MeshInstance3D
var _material: ShaderMaterial
var _opacity := 0.0
var _hint_host: Node3D


func _ready() -> void:
	name = "RayFloorPreview"
	top_level = true
	process_physics_priority = 100 # after hands and grab drivers
	_mesh = MeshInstance3D.new()
	_mesh.mesh = QuadMesh.new()
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_mesh.material_override = _material
	add_child(_mesh)
	visible = false


static func enabled_for(object: Node3D, modifier: bool) -> bool:
	return is_instance_valid(object) and (bool(object.get("ray_floor_preview_default")) != modifier)


static func socket_engaged(object: Node3D) -> bool:
	var driver: Variant = object.get("_grab_driver")
	if not is_instance_valid(driver):
		return false
	var zone: Variant = driver.get("_preview_zone")
	return driver.get("_prev_previewing") == true and is_instance_valid(zone) \
		and zone.can_preview(object)


## The rectangle is a yaw-aligned enclosure of the actual transformed bounds.
## Keeping the last heading at vertical prevents a 180-degree jump while tipping.
static func footprint(box: AABB, pose: Transform3D, previous := Vector3.BACK) -> Dictionary:
	var z := pose.basis.z
	z.y = 0.0
	z = previous if z.length_squared() < 0.0001 else z.normalized()
	var frame := Basis(Vector3.UP.cross(z), Vector3.UP, z)
	var points: Array[Vector3] = []
	var flat := AABB()
	for i in 8:
		var p := pose * box.get_endpoint(i)
		points.append(p)
		var local := frame.transposed() * p
		flat = AABB(local, Vector3.ZERO) if i == 0 else flat.expand(local)
	return {"frame": frame, "bounds": flat, "points": points, "heading": z}


static func _exclude(node: Node, out: Array[RID]) -> void:
	if node is PhysicsBody3D:
		out.append(node.get_rid())
	for child in node.get_children():
		_exclude(child, out)


## Place in the object's authored upright orientation (+Y up), retaining yaw
## and scale. Preview and release share the last heading at a vertical hold.
static func upright_pose(pose: Transform3D, previous := Vector3.BACK) -> Transform3D:
	var z := pose.basis.z
	z.y = 0.0
	z = previous if z.length_squared() < 0.0001 else z.normalized()
	pose.basis = Basis(Vector3.UP.cross(z), Vector3.UP, z).scaled_local(pose.basis.get_scale())
	return pose


func release_solution(object: RigidBody3D, modifier: bool) -> Dictionary:
	return solve(object, modifier, _heading)


## Fresh query for BOTH drawing and release: never place on a stale/deleted table.
static func solve(object: RigidBody3D, modifier: bool, previous := Vector3.BACK) -> Dictionary:
	if not enabled_for(object, modifier) or not object.is_inside_tree() or socket_engaged(object):
		return {}
	if object.has_method("is_mounted") and object.call("is_mounted"):
		return {}
	var box := PointerFit.drawn_bounds(object)
	if box.size.is_zero_approx():
		return {}
	var pose := upright_pose(object.global_transform, previous)
	var fp := footprint(box, pose, previous)
	var frame: Basis = fp.frame
	var bounds: AABB = fp.bounds
	var centre: Vector3 = frame * bounds.get_center()
	var exclude: Array[RID] = []
	_exclude(object, exclude)
	var query := PhysicsRayQueryParameters3D.create(centre, centre + Vector3.DOWN * MAX_DROP,
		SUPPORT_MASK, exclude)
	query.collide_with_areas = false
	var hit := object.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {}
	var normal: Vector3 = hit.normal
	if normal.y < 0.5: # more than 60 degrees: not a supporting surface
		return {}
	var at: Vector3 = hit.position
	var shift := -INF
	for p: Vector3 in fp.points:
		shift = maxf(shift, (CLEARANCE - normal.dot(p - at)) / normal.y)
	# Standing a sideways object upright can require raising its origin. Seat
	# the upright bounds on the support rather than rejecting that correction.
	pose.origin.y += shift
	if object.has_method("get_tether"):
		var tether: Dictionary = object.call("get_tether")
		if not tether.is_empty():
			var anchor: Vector3 = tether.get("anchor", Vector3.ZERO)
			if pose.origin.distance_to(anchor) > maxf(float(tether.get("length", 0.0)) - 0.02, 0.0):
				return {}
	# Project the yaw rectangle vertically onto the support plane (including slopes).
	centre.y = at.y - (normal.x * (centre.x - at.x) + normal.z * (centre.z - at.z)) / normal.y
	centre += Vector3.UP * CLEARANCE
	var x := frame.x
	var z := frame.z
	x.y = -normal.dot(x) / normal.y
	z.y = -normal.dot(z) / normal.y
	return {"pose": pose, "surface": Transform3D(Basis(x, normal, z), centre),
		"size": Vector2(maxf(bounds.size.x, 0.005), maxf(bounds.size.z, 0.005)),
		"heading": fp.heading}


## Set the pose before release signals/network observers run. The desktop release
## uses PLACING_META to omit its normal downward wake-up nudge.
static func place(object: RigidBody3D, result: Dictionary) -> void:
	object.global_transform = result.pose
	object.force_update_transform()
	PhysicsServer3D.body_set_state(object.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, result.pose)
	object.linear_velocity = Vector3.ZERO
	object.angular_velocity = Vector3.ZERO
	PhysicsServer3D.body_set_state(object.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
	PhysicsServer3D.body_set_state(object.get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)


func _physics_process(delta: float) -> void:
	var object: RigidBody3D = source.call("floor_preview_target") if is_instance_valid(source) else null
	_hint(object)
	if not is_instance_valid(object):
		clear()
		return
	update_for(object, bool(source.call("floor_preview_modifier")), delta)


## Also used by the windowed visual probe, without creating interaction hints.
func update_for(object: RigidBody3D, modifier: bool, delta: float) -> void:
	var result := solve(object, modifier, _heading)
	_opacity = move_toward(_opacity, 0.0 if result.is_empty() else 1.0, delta * 12.0)
	if not result.is_empty():
		_heading = result.heading
		global_transform = result.surface
		var size: Vector2 = result.size
		# QuadMesh is XY: map its Y onto the surface's local Z.
		_mesh.transform = Transform3D(Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN), Vector3.ZERO)
		(_mesh.mesh as QuadMesh).size = size
		_material.set_shader_parameter("footprint_size", size)
	_material.set_shader_parameter("opacity", _opacity)
	visible = _opacity > 0.001


func clear() -> void:
	visible = false
	_opacity = 0.0
	_heading = Vector3.BACK
	_hint(null)


func _hint(object: Node3D) -> void:
	if object == _hint_host:
		return
	if is_instance_valid(_hint_host):
		var old := _hint_host.get_node_or_null("HeldHint")
		if old != null:
			old.remove_row(&"ray_floor")
	_hint_host = object
	if not is_instance_valid(object):
		return
	# Loaded here, not preloaded: HeldHint also reads DesktopPickup's inspect mode.
	var hints: Script = load("res://Scripts/Objects/highlights/held_hint.gd")
	var hint: Node3D = hints.for_node(object)
	var vr := source.has_method("is_ray_grabbing")
	var glyphs := ["quest_button_{ax}_outline"] if vr else ["keyboard_alt_outline"]
	var verb := "hide" if object.get("ray_floor_preview_default") == true else "show"
	hint.add_row(&"ray_floor", hints.PLATFORM_VR if vr else hints.PLATFORM_DESKTOP,
		glyphs, "Hold {g} to %s the footprint; release to place when shown" % verb, hints.WHEN_HELD)
	# Desktop's pivot and VR's pickup are the grabbers HeldHint already understands.
	var by: Node3D = source if vr else source.get("_hand_pivot")
	hint.on_grabbed(by)
