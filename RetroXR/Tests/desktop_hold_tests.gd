extends Node

## The desktop hand: how a handheld is held (screen to you, top edge up), how the hand trails
## your gaze, and how the pull-in / click-to-drop rules of DesktopPickup are laid out.
##
##   godot --headless --path RetroXR res://Tests/desktop_hold_tests.tscn
##
## Pure: no room, no console, no mouse. That a switch can be aimed at while a console is in the
## hand, and that pressing it does not drop the console, is `Tools/room/hold_probe --scenario`
## (windowed).

var _fail := 0
var _ran := 0


func _ready() -> void:
	_facing()
	_follow()
	_focus()
	_bounds()
	_assist()
	await _assist_hidden()
	_stale_left()
	_rules()
	_capture_hides_reticle()
	print("[hold] %d cases, %s" % [_ran, "PASS" if _fail == 0 else "%d FAILURE(S)" % _fail])
	get_tree().quit(0 if _fail == 0 else 1)


func _ok(cond: bool, what: String, detail := "") -> void:
	_ran += 1
	if cond:
		print("[hold] ok   %s" % what)
	else:
		_fail += 1
		print("[hold] FAIL %s%s" % [what, "" if detail.is_empty() else "  -- " + detail])


func _near(a: float, b: float, eps := 0.0001) -> bool:
	return absf(a - b) <= eps


func _facing() -> void:
	for at: Vector3 in [Vector3(0, -0.07, -0.4), Vector3(0, 0, -0.5), Vector3(0.1, -0.2, -0.3),
			Vector3(0, -0.3, -0.05)]:
		var b := DesktopPickup.screen_facing_basis(at)
		var to_eye := (-at).normalized()
		_ok(_near(b.y.dot(to_eye), 1.0), "facing/the screen (+Y) points at the eye from %s" % at)
		_ok(_near(b.determinant(), 1.0), "facing/%s is a proper rotation, not a mirror" % at)
		_ok(b.is_conformal(), "facing/%s keeps its proportions" % at)
		# Up to as much as the line of sight allows: nearly straight down at it, "up" is a sliver.
		var allowed := sqrt(maxf(1.0 - to_eye.y * to_eye.y, 0.0))
		_ok(_near((-b.z).dot(Vector3.UP), allowed, 0.001), "facing/the top edge (-Z) is as upright as the view allows from %s" % at,
			str((-b.z).dot(Vector3.UP)))
		_ok(_near(b.x.dot(b.y), 0.0) and _near(b.x.dot(b.z), 0.0) and _near(b.y.dot(b.z), 0.0),
			"facing/%s axes are at right angles" % at)
	# Straight overhead: no "up" to choose, and it must not fall over.
	var over := DesktopPickup.screen_facing_basis(Vector3(0, 0.5, 0))
	_ok(over.is_finite() and _near(over.determinant(), 1.0), "facing/a thing straight above is still a rotation")
	# Directly in front at eye height the console is upright: its screen vertical, top edge up.
	var upright := DesktopPickup.screen_facing_basis(Vector3(0, 0, -0.4))
	_ok(_near((-upright.z).dot(Vector3.UP), 1.0), "facing/dead ahead it stands exactly upright")


func _follow() -> void:
	var dead := deg_to_rad(20.0)
	_ok(_near(DesktopPickup.follow_toward(0.0, deg_to_rad(15.0), dead, 1.0), 0.0),
		"follow/looking inside the dead zone moves nothing")
	_ok(_near(DesktopPickup.follow_toward(0.0, deg_to_rad(-20.0), dead, 1.0), 0.0),
		"follow/looking exactly at its edge moves nothing")
	var moved := DesktopPickup.follow_toward(0.0, deg_to_rad(50.0), dead, 1.0)
	_ok(_near(moved, deg_to_rad(30.0)), "follow/past the zone it ends at the zone's near edge (30, not 50)")
	var half := DesktopPickup.follow_toward(0.0, deg_to_rad(50.0), dead, 0.5)
	_ok(_near(half, deg_to_rad(15.0)), "follow/half a step goes half way to that edge")
	_ok(DesktopPickup.follow_toward(0.0, deg_to_rad(-50.0), dead, 1.0) < 0.0, "follow/it follows to the left too")
	# Across the wrap-around: from just under +180 deg to just past it is a short way, not 360.
	var across := DesktopPickup.follow_toward(deg_to_rad(170.0), deg_to_rad(-170.0), deg_to_rad(5.0), 1.0)
	_ok(absf(angle_difference(across, deg_to_rad(-175.0))) < 0.001, "follow/the wrap at 180 degrees is crossed the short way",
		str(rad_to_deg(across)))
	# Settling: repeated steps converge on the zone edge and stay.
	var a := 0.0
	for i in 200:
		a = DesktopPickup.follow_toward(a, deg_to_rad(80.0), dead, 0.2)
	_ok(_near(a, deg_to_rad(60.0), 0.001), "follow/it settles at target minus the zone", str(rad_to_deg(a)))
	_ok(_near(DesktopPickup.ease_in_out(0.0), 0.0) and _near(DesktopPickup.ease_in_out(1.0), 1.0)
		and _near(DesktopPickup.ease_in_out(0.5), 0.5), "follow/the catch blend starts, ends and passes the middle where it should")
	_ok(DesktopPickup.ease_in_out(0.1) < 0.1 and DesktopPickup.ease_in_out(0.9) > 0.9, "follow/and eases at both ends")


func _focus() -> void:
	# The GBA's screen is about 6 cm wide.
	var d_zoom2 := DesktopPickup.focus_distance(0.061, 42.0, 16.0 / 9.0)
	var d_zoom1 := DesktopPickup.focus_distance(0.061, 75.0, 16.0 / 9.0)
	_ok(d_zoom2 >= DesktopPickup.HAND_FOCUS_MIN and d_zoom2 <= DesktopPickup.HAND_FOCUS_MAX, "focus/stays between the limits", str(d_zoom2))
	_ok(d_zoom2 < 0.2, "focus/a GBA is held close, a hand's breadth or less away", str(d_zoom2))
	_ok(d_zoom2 >= d_zoom1, "focus/a narrower (zoomed) view needs it no nearer", "%s vs %s" % [d_zoom2, d_zoom1])
	_ok(DesktopPickup.focus_distance(0.12, 42.0, 16.0 / 9.0) > d_zoom2, "focus/a wider screen stands further off")
	_ok(DesktopPickup.focus_distance(5.0, 42.0, 16.0 / 9.0) == DesktopPickup.HAND_FOCUS_MAX, "focus/an enormous one is held at the far limit")
	_ok(DesktopPickup.focus_distance(0.001, 75.0, 16.0 / 9.0) == DesktopPickup.HAND_FOCUS_MIN, "focus/a tiny one at the near limit")
	# At the distance it picks the screen takes the fraction asked (when not clamped).
	var w := 0.08
	var dist := DesktopPickup.focus_distance(w, 42.0, 16.0 / 9.0)
	var shown := w / (2.0 * dist * tan(deg_to_rad(42.0) * 0.5) * (16.0 / 9.0))
	_ok(absf(shown - DesktopPickup.HAND_SCREEN_FRACTION) < 0.001, "focus/it fills the fraction of the width that was asked for", str(shown))
	_ok(is_finite(DesktopPickup.focus_distance(0.06, 0.0, 0.0)), "focus/a degenerate camera does not blow up")


func _assist() -> void:
	var box := AABB(Vector3(-0.005, -0.001, -0.002), Vector3(0.010, 0.002, 0.004))
	var identity := Transform3D.IDENTITY
	# A ray straight through the box: no gap.
	var through := InteractionResolver.ray_box_gap(Vector3(0, 0, 0.5), Vector3(0, 0, -1), identity, 1.0, box, 1.5)
	_ok(float(through["gap"]) < 0.0001, "assist/a ray through the box has no gap", str(through))
	# A ray passing 4 mm above it: the gap is 3 mm (the box is 1 mm tall) .
	var above := InteractionResolver.ray_box_gap(Vector3(0, 0.005, 0.5), Vector3(0, 0, -1), identity, 1.0, box, 1.5)
	_ok(absf(float(above["gap"]) - 0.004) < 0.0002, "assist/a ray passing above it is that far from it", str(above))
	_ok(absf(float(above["t"]) - 0.5) < 0.01, "assist/at the point where it passes", str(above["t"]))
	# The gap is in metres whatever the box's own scale.
	var scaled := InteractionResolver.ray_box_gap(Vector3(0, 0.05, 0.5), Vector3(0, 0, -1),
		Transform3D(Basis.from_scale(Vector3(0.1, 0.1, 0.1)), Vector3.ZERO), 10.0, box, 1.5)
	# In the box's space the world is shrunk 10x: the box is 10x bigger in the world.
	_ok(float(scaled["gap"]) < 0.06, "assist/a scaled box is measured in world metres", str(scaled))
	# Pointing away from it: the nearest the ray comes is where it starts.
	var away := InteractionResolver.ray_box_gap(Vector3(0, 0, 0.5), Vector3(0, 0, 1), identity, 1.0, box, 1.5)
	_ok(absf(float(away["gap"]) - 0.498) < 0.002 and float(away["t"]) < 0.05, "assist/a ray pointing away never gets nearer than its start", str(away))
	# Convexity: a long diagonal ray still finds its closest approach.
	var diag := InteractionResolver.ray_box_gap(Vector3(0.3, 0.3, 0.3), (Vector3(-0.3, -0.3, -0.3)).normalized(), identity, 1.0, box, 1.5)
	_ok(float(diag["gap"]) < 0.0005, "assist/an oblique ray that crosses it is found too", str(diag))


## A control the crosshair reaches only THROUGH the held object's body is out of sight. The held
## thing is a 4 cm deep box on the held layer; one control sits on its near face, one on its far.
func _assist_hidden() -> void:
	var control_src := GDScript.new()
	control_src.source_code = """extends Node3D
var box := AABB()
func pointer_event(_e: Variant) -> void:
	pass
func desktop_aim_volume() -> Dictionary:
	return {"to_local": global_transform.affine_inverse(), "box": box, "scale": 1.0}
"""
	control_src.reload()
	var held := StaticBody3D.new()
	held.collision_layer = 1 << 16
	var shape := CollisionShape3D.new()
	var cube := BoxShape3D.new()
	cube.size = Vector3(0.10, 0.10, 0.04)
	shape.shape = cube
	held.add_child(shape)
	var rear := Node3D.new()
	rear.set_script(control_src)
	rear.set("box", AABB(Vector3(-0.005, -0.005, -0.022), Vector3(0.01, 0.01, 0.002)))
	held.add_child(rear)
	add_child(held)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var from := Vector3(0, 0, 0.5)
	var to := Vector3(0, 0, -1.0)
	_ok(absf(InteractionResolver.held_body_distance(held, from, to) - 0.48) < 0.001,
		"assist/the ray meets the held body at its near face")
	var none := InteractionResolver.assist_held(held, from, to, InteractionTarget.none())
	_ok(not none.is_valid() or none.hit_node != rear,
		"assist/a control on the far side is not lit through the body")
	var through := InteractionResolver._make_target(InteractionTarget.KIND_POINTER, rear, rear, rear,
		rear, Vector3(0, 0, -0.02), 0.52, true, false)
	var kept := InteractionResolver.assist_held(held, from, to, through)
	_ok(not kept.is_valid() or kept.hit_node != rear,
		"assist/nor kept when the plain ray reached it through the body")
	var front := Node3D.new()
	front.set_script(control_src)
	front.set("box", AABB(Vector3(-0.005, -0.005, 0.020), Vector3(0.01, 0.01, 0.002)))
	held.add_child(front)
	InteractionResolver._assist_held_id = 0
	var lit := InteractionResolver.assist_held(held, from, to, InteractionTarget.none())
	_ok(lit.is_valid() and lit.hit_node == front, "assist/a control on the near face is lit")
	held.free()
	InteractionResolver._assist_held_id = 0


## A left press whose release went somewhere else (a menu opened mid-press) ends anyway once the
## button is not down, or every later mouse motion would turn the held object.
func _stale_left() -> void:
	var pickup := DesktopPickup.new()
	DesktopPickup.left_drag = true
	pickup._drop_armed = true
	pickup._left_turning = true
	pickup._clear_stale_left()
	_ok(not DesktopPickup.left_drag and not pickup._drop_armed and not pickup._left_turning,
		"left/a release that never arrived: the drag and the turn end with the button up")
	pickup.free()


func _bounds() -> void:
	var root := Node3D.new()
	add_child(root)
	_ok(DesktopPickup.visual_bounds(root).size == Vector3.ZERO, "bounds/nothing to see gives no box")
	var a := MeshInstance3D.new()
	a.mesh = BoxMesh.new()
	(a.mesh as BoxMesh).size = Vector3(0.2, 0.2, 0.2)
	a.position = Vector3(1.0, 0.0, 0.0)
	root.add_child(a)
	var box := DesktopPickup.visual_bounds(root)
	_ok(box.get_center().is_equal_approx(Vector3(1.0, 0.0, 0.0)), "bounds/the middle is where the mesh is", str(box))
	_ok(box.size.is_equal_approx(Vector3(0.2, 0.2, 0.2)), "bounds/and its size is the mesh's", str(box.size))
	# A second mesh far off, then hidden: only what shows counts.
	var b := MeshInstance3D.new()
	b.mesh = BoxMesh.new()
	(b.mesh as BoxMesh).size = Vector3(0.2, 0.2, 0.2)
	b.position = Vector3(-1.0, 0.0, 0.0)
	root.add_child(b)
	_ok(DesktopPickup.visual_bounds(root).get_center().is_equal_approx(Vector3.ZERO), "bounds/two meshes are held by their common middle")
	b.visible = false
	_ok(DesktopPickup.visual_bounds(root).get_center().is_equal_approx(Vector3(1.0, 0.0, 0.0)), "bounds/a hidden mesh does not count")
	# Scale and turn are applied.
	a.scale = Vector3(2.0, 1.0, 1.0)
	_ok(absf(DesktopPickup.visual_bounds(root).size.x - 0.4) < 0.001, "bounds/a scaled mesh is measured as scaled")
	a.scale = Vector3.ONE
	a.rotation_degrees = Vector3(0, 0, 45)
	_ok(DesktopPickup.visual_bounds(root).size.x > 0.25, "bounds/a turned one is measured by its corners")
	# Measured from the root's own space, wherever the root is.
	root.global_position = Vector3(5, 5, 5)
	root.rotation_degrees = Vector3(0, 90, 0)
	a.rotation = Vector3.ZERO
	_ok(DesktopPickup.visual_bounds(root).get_center().is_equal_approx(Vector3(1.0, 0.0, 0.0)), "bounds/the box is in the root's space however the root sits")
	root.free()


func _capture_hides_reticle() -> void:
	# The crosshair hides while a held device has the keyboard (F3), and comes back with it.
	var host := Node3D.new()
	add_child(host)
	var eligible := [true]
	var cap := ScrollLockCapture.attach(host, func() -> bool: return eligible[0], 0xF11C)
	_ok(not ScrollLockCapture.any_active(), "reticle/nothing captured: the crosshair stays")
	cap.set_active(true)
	eligible[0] = false
	_ok(not ScrollLockCapture.any_active(),
		"reticle/the device stops being eligible with no refresh(): it is back")
	eligible[0] = true
	cap.set_active(false)
	cap.set_active(true)
	_ok(ScrollLockCapture.any_active(), "reticle/a device has the keyboard: the crosshair hides")
	ScrollLockCapture.set_suspended(true)
	_ok(not ScrollLockCapture.any_active(), "reticle/typing in a text field: it is back")
	ScrollLockCapture.set_suspended(false)
	cap.set_active(false)
	_ok(not ScrollLockCapture.any_active(), "reticle/capture off: it is back")
	cap.set_active(true)
	cap.release()
	_ok(not ScrollLockCapture.any_active(), "reticle/the device let go: it is back")
	host.free()


func _rules() -> void:
	var pickup := DesktopPickup.new()
	pickup._hand_hold = true
	pickup._grab_dist = 1.0
	pickup._release_to_ray()
	_ok(not pickup._hand_hold, "rules/a notch out of the hand puts it back on the ray")
	_ok(is_equal_approx(pickup._grab_dist, DesktopPickup.MIN_DIST),
		"rules/at the pull-in limit, one notch from catching it again", str(pickup._grab_dist))
	pickup.free()
	_ok(DesktopPickup.HAND_LOCAL.z < 0.0, "rules/the hand is in front of the camera")
	_ok(DesktopPickup.HAND_DEADZONE_YAW > 0.0 and DesktopPickup.HAND_DEADZONE_YAW <= 8.0
		and DesktopPickup.HAND_DEADZONE_PITCH > 0.0 and DesktopPickup.HAND_DEADZONE_PITCH <= 8.0,
		"rules/the dead zone is small: what is in the hand stays in front of you, not trailing")
