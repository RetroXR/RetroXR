extends "res://Tests/test_suite.gd"

const Preview := preload("res://Scripts/Interaction/ray_floor_preview.gd")

class Tethered extends XRToolsPickable:
	var reach := 0.1
	func get_tether() -> Dictionary:
		return {"anchor": Vector3(0, 3, 0), "length": reach}

class Mounted extends XRToolsPickable:
	func is_mounted() -> bool: return true

class RayPickup extends XRToolsFunctionPickup:
	var modifier := true
	func _ready() -> void: pass
	func _process(_delta: float) -> void: pass
	func _physics_process(_delta: float) -> void: pass
	func floor_preview_modifier() -> bool: return modifier


func _ready() -> void:
	suite_tag = "ray_floor"
	get_tree().create_timer(45.0).timeout.connect(func() -> void: get_tree().quit(1))
	var object := _object(XRToolsPickable.new())
	for default_on in [false, true]:
		object.ray_floor_preview_default = default_on
		for modifier in [false, true]:
			_eq(Preview.enabled_for(object, modifier), default_on != modifier,
				"mode/default %s modifier %s" % [default_on, modifier])
	object.ray_floor_preview_default = false
	_ok(InputMap.has_action(Preview.ACTION), "input/desktop action exists")
	var events := InputMap.action_get_events(Preview.ACTION)
	_ok(not events.is_empty() and events[0] is InputEventKey and events[0].physical_keycode == KEY_ALT,
		"input/default is Alt")
	_bounds()
	var floor_body := _surface(Vector3(12, 0.2, 12), Vector3(0, -0.1, 0))
	await _frames()
	_ok(Preview.solve(object, false).is_empty(), "mode/default off does not produce a destination")
	var result := Preview.solve(object, true)
	_ok(not result.is_empty(), "query/floor found")
	if result.is_empty():
		object.free()
		floor_body.free()
		_finish()
		return # a broken query must fail, not abort assertions with a script error
	if not result.is_empty():
		_near(result.pose.origin.y, 0.25 + Preview.CLEARANCE, "query/bottom rests on floor")
		_ok(result.pose.basis.is_equal_approx(object.global_basis), "query/rotation preserved")
		_near(result.pose.origin.x, object.position.x, "query/no horizontal movement")
		_near(result.surface.origin.y, Preview.CLEARANCE, "query/marker on surface")
	_upright(object)
	var table := _surface(Vector3(3, 0.2, 3), Vector3(0, 0.9, 0))
	await _frames()
	result = Preview.solve(object, true)
	_near(result.pose.origin.y, 1.25 + Preview.CLEARANCE, "query/table before floor")
	table.collision_layer = 4
	await _frames()
	_near(Preview.solve(object, true).pose.origin.y, 1.25 + Preview.CLEARANCE, "query/pickable support")
	table.free()
	await _frames()
	_near(Preview.solve(object, true).pose.origin.y, 0.25 + Preview.CLEARANCE, "query/deleted table not cached")
	# Query starts inside the held body, but must exclude it even on a world layer.
	object.collision_layer = 1
	await _frames()
	_near(Preview.solve(object, true).pose.origin.y, 0.25 + Preview.CLEARANCE, "query/held body excluded")
	object.collision_layer = 4
	var child_body := _surface(Vector3(2, 0.2, 2), Vector3(0, 2, 0))
	child_body.reparent(object)
	await _frames()
	_near(Preview.solve(object, true).pose.origin.y, 0.25 + Preview.CLEARANCE, "query/held assembly excluded")
	child_body.free()
	var tether := _object(Tethered.new()) as Tethered
	_ok(Preview.solve(tether, true).is_empty(), "constraints/short tether suppresses destination")
	tether.reach = 5.0
	_ok(not Preview.solve(tether, true).is_empty(), "constraints/reachable tether allowed")
	tether.free()
	var mounted := _object(Mounted.new())
	_ok(Preview.solve(mounted, true).is_empty(), "constraints/mounted object suppressed")
	mounted.free()
	object.position.x = 20
	_ok(Preview.solve(object, true).is_empty(), "query/no surface hides marker")
	object.position = Vector3(0, 3, 0)
	floor_body.rotation.z = deg_to_rad(25)
	await _frames()
	result = Preview.solve(object, true)
	_ok(not result.is_empty(), "query/sloped support accepted")
	if not result.is_empty():
		var normal := floor_body.global_basis.y
		for i in 8:
			var p: Vector3 = result.pose * PointerFit.drawn_bounds(object).get_endpoint(i)
			_ok(normal.dot(p - floor_body.to_global(Vector3(0, 0.1, 0))) >= Preview.CLEARANCE - 0.0001,
				"slope/corner %d above plane" % i)
	floor_body.rotation.z = deg_to_rad(70)
	await _frames()
	_ok(Preview.solve(object, true).is_empty(), "query/steep support rejected")
	floor_body.rotation = Vector3.ZERO
	await _frames()
	await _desktop_release(object)
	_vr_release(object)
	await _socket_and_visual(object)
	object.free()
	floor_body.free()
	_finish()


func _frames() -> void:
	for i in 3:
		await get_tree().physics_frame


func _upright(object: XRToolsPickable) -> void:
	var scale_now := Vector3(1.4, 1.7, 0.8)
	for rotation_now: Vector3 in [Vector3(0.6, 0.7, 0.4), Vector3(0, -0.8, PI), Vector3(PI / 2, 0.3, 0)]:
		object.global_transform = Transform3D(Basis.from_euler(rotation_now).scaled_local(scale_now), Vector3(0, 3, 0))
		var result := Preview.solve(object, true, Vector3.RIGHT)
		_ok(not result.is_empty(), "upright/tilted or inverted hold has a landing %s" % rotation_now)
		if result.is_empty():
			continue
		var landing: Transform3D = result.pose
		_ok(landing.basis.y.normalized().is_equal_approx(Vector3.UP), "upright/local up always faces sky %s" % rotation_now)
		_ok(landing.basis.get_scale().is_equal_approx(scale_now), "upright/scale retained %s" % rotation_now)
		_near(landing.origin.y, 0.25 * scale_now.y + Preview.CLEARANCE, "upright/base rests flat %s" % rotation_now)
		_near(result.size.x, scale_now.x, "upright/preview width is upright width %s" % rotation_now)
		_near(result.size.y, 0.4 * scale_now.z, "upright/preview depth is upright depth %s" % rotation_now)
		var heading := object.global_basis.z
		heading.y = 0
		heading = Vector3.RIGHT if heading.length_squared() < 0.0001 else heading.normalized()
		_ok(landing.basis.z.normalized().is_equal_approx(heading), "upright/heading preserved including vertical fallback %s" % rotation_now)
	# Close to the floor, standing upright needs to RAISE the origin to fit.
	object.global_transform = Transform3D(Basis(Vector3.FORWARD, PI / 2), Vector3(0, 0.1, 0))
	var low := Preview.solve(object, true)
	_ok(not low.is_empty(), "upright/low sideways hold can still stand upright")
	if not low.is_empty():
		_near(low.pose.origin.y, 0.25 + Preview.CLEARANCE, "upright/low origin raised to seat base")
	var preview := Preview.new()
	add_child(preview)
	preview.set_physics_process(false)
	object.global_transform = Transform3D(Basis(Vector3.UP, 0.7), Vector3(0, 3, 0))
	preview.update_for(object, true, 1.0)
	var shown_heading := object.global_basis.z
	object.global_basis = Basis(Vector3.RIGHT, PI / 2)
	preview.update_for(object, true, 1.0)
	var vertical := preview.release_solution(object, true)
	_ok(not vertical.is_empty() and vertical.pose.basis.z.is_equal_approx(shown_heading),
		"upright/vertical release retains the preview heading")
	preview.free()
	object.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 3, 0))


func _near(got: float, want: float, what: String) -> void:
	_ok(absf(got - want) < 0.001, what, "%f versus %f" % [got, want])


func _object(body: XRToolsPickable) -> XRToolsPickable:
	body.freeze = true
	body.collision_layer = 4
	body.collision_mask = 1
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1, 0.5, 0.4)
	mesh.mesh = box
	body.add_child(mesh)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	col.shape = shape
	body.add_child(col)
	add_child(body)
	body.position = Vector3(0, 3, 0)
	return body


func _surface(size: Vector3, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	add_child(body)
	body.position = at
	return body


func _bounds() -> void:
	var box := AABB(Vector3(-0.1, -0.2, 0.3), Vector3(0.4, 0.8, 1.2))
	for angle in [0.0, 0.6, 1.3]:
		var pose := Transform3D(Basis.from_euler(Vector3(angle, 0.7, angle * 0.4)).scaled_local(Vector3(2, 1, 0.5)), Vector3(1, 3, 2))
		var fp := Preview.footprint(box, pose)
		for i in 8:
			var p: Vector3 = fp.frame.transposed() * (pose * box.get_endpoint(i))
			_ok((fp.bounds as AABB).grow(0.00001).has_point(p), "bounds/tilt %s encloses corner %d" % [angle, i])
		_near(fp.frame.z.y, 0.0, "bounds/heading remains horizontal %s" % angle)
	var vertical := Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3.ZERO)
	var last := Vector3(1, 0, 1).normalized()
	_ok(Preview.footprint(box, vertical, last).heading.is_equal_approx(last), "bounds/vertical keeps last heading")


func _desktop_release(object: XRToolsPickable) -> void:
	var pickup := DesktopPickup.new()
	add_child(pickup)
	pickup.set_physics_process(false)
	pickup._floor_preview.set_physics_process(false)
	for modifier in [false, true]:
		object.position = Vector3(0, 3, 0)
		object.rotation = Vector3(0.6, 0.7, 0.4)
		var held_basis := object.global_basis
		object.freeze = true
		pickup._grab_target(object)
		if modifier: Input.action_press(Preview.ACTION)
		else: Input.action_release(Preview.ACTION)
		var release_seen: Array = []
		object.dropped.connect(func(p: Node3D) -> void:
			release_seen.append([p.global_position, p.linear_velocity]), CONNECT_ONE_SHOT)
		pickup._drop()
		_near(object.position.y, 0.25 + Preview.CLEARANCE if modifier else 3.0, "desktop/release mode %s" % modifier)
		_ok(object.freeze, "desktop/original freeze preserved %s" % modifier)
		_ok(not object.is_picked_up(), "desktop/driver released %s" % modifier)
		_ok(object.global_basis.y.normalized().is_equal_approx(Vector3.UP) if modifier else object.global_basis.is_equal_approx(held_basis),
			"desktop/only placement straightens the object %s" % modifier)
		_ok(not release_seen.is_empty() and release_seen[0][0].is_equal_approx(object.position),
			"desktop/drop observers see final pose %s" % modifier)
	Input.action_release(Preview.ACTION)
	object.release_mode = XRToolsPickable.ReleaseMode.UNFROZEN
	object.ray_floor_preview_default = true
	object.position.y = 3
	pickup._grab_target(object)
	pickup._drop()
	_ok(not object.freeze, "desktop/unfrozen release policy preserved")
	_ok(object.linear_velocity.is_zero_approx(), "desktop/placement has no wake-up nudge")
	object.freeze = true
	object.release_mode = XRToolsPickable.ReleaseMode.ORIGINAL
	object.ray_floor_preview_default = false
	pickup.free()
	await _frames()


func _vr_release(object: XRToolsPickable) -> void:
	var pickup := RayPickup.new()
	add_child(pickup)
	for modifier in [false, true]:
		object.position = Vector3(0, 3, 0)
		object.rotation = Vector3(0.6, 0.7, 0.4)
		var held_basis := object.global_basis
		object.freeze = true
		pickup._start_ray_grab_at(object, 3.0)
		pickup.modifier = modifier
		pickup._end_ray_grab()
		_near(object.position.y, 0.25 + Preview.CLEARANCE if modifier else 3.0, "vr/release mode %s" % modifier)
		_ok(object.freeze, "vr/freeze preserved %s" % modifier)
		_ok(not pickup.is_ray_grabbing(), "vr/hold ended %s" % modifier)
		_ok(object.global_basis.y.normalized().is_equal_approx(Vector3.UP) if modifier else object.global_basis.is_equal_approx(held_basis),
			"vr/only placement straightens the object %s" % modifier)
		if modifier:
			_ok(object.linear_velocity.is_zero_approx() and object.angular_velocity.is_zero_approx(), "vr/no throw on placement")
	object.release_mode = XRToolsPickable.ReleaseMode.UNFROZEN
	object.position.y = 3
	pickup._start_ray_grab_at(object, 3)
	pickup._end_ray_grab()
	_ok(not object.freeze, "vr/explicit unfrozen release policy")
	object.freeze = true
	object.release_mode = XRToolsPickable.ReleaseMode.ORIGINAL
	pickup.free()


func _socket_and_visual(object: XRToolsPickable) -> void:
	object.position = Vector3(0, 3, 0)
	var preview := Preview.new()
	add_child(preview)
	preview.set_physics_process(false)
	preview.update_for(object, true, 1.0)
	_ok(preview.visible, "visual/valid destination displays marker")
	var want := Preview.solve(object, true)
	_ok(preview.global_position.is_equal_approx(want.surface.origin), "visual/marker uses release support")
	preview.update_for(object, false, 0.001)
	_ok(preview.visible and Preview.solve(object, false).is_empty(), "visual/fade never enables placement")
	preview.clear()
	_ok(not preview.visible, "visual/clear hides immediately")
	preview.free()
	var zone := XRToolsSnapZone.new()
	zone.snap_require = "floor_test_socket"
	object.add_to_group("floor_test_socket")
	add_child(zone)
	zone.position = object.position
	var pickup := RayPickup.new()
	add_child(pickup)
	pickup._start_ray_grab_at(object, 3)
	pickup._ray_preview_zone = zone
	pickup._ray_previewing = true
	_ok(pickup.floor_preview_target() == null, "socket/VR preview suppresses floor")
	pickup._end_ray_grab()
	_ok(object.get_picked_up_by() == zone, "socket/VR release seats instead of placing")
	zone.drop_object()
	zone.free()
	pickup.free()
	await _frames()
