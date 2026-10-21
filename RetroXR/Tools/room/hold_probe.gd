## What the desktop crosshair is aimed at while a Game Boy Advance is in the hand, where that is
## on the screen, and what a click does there.
##
## Opens the bedroom, spawns a GBA in front of the camera and picks it up through DesktopPickup
## as a click would. Then, with --scenario:
##   1. pulls it all the way in, one more notch: it is CAUGHT into the hand (screen to you);
##   2. tips it so the power switch on its edge shows, finds the pixels that answer the
##      switch, and aims the crosshair at them;
##   3. presses and releases left there: the switch's, the hand keeps the console;
##   4. looks away and clicks: the console is let go when the button comes back UP.
## WINDOWED, scratch XDG_DATA_HOME:
##
##     XDG_DATA_HOME=/tmp/scratch "$godot" --path RetroXR --resolution 1280x720 \
##         res://Tools/room/hold_probe.tscn -- --dist=0.45 --scenario --out=/tmp/hold
extends Node

const SCENE := preload("res://Scenes/BedroomScene.tscn")
const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")

var _dist := 0.45
var _out := ""
var _pose := "flat"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--dist="):
			_dist = float(a.trim_prefix("--dist="))
		elif a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
		elif a.begins_with("--pose="):
			_pose = a.trim_prefix("--pose=")
	DirAccess.make_dir_recursive_absolute(_out)
	get_tree().create_timer(190.0).timeout.connect(func() -> void: get_tree().quit(1))
	add_child(SCENE.instantiate())
	await get_tree().create_timer(10.0).timeout
	var cam := get_viewport().get_camera_3d()
	var sys := SYSTEM_SCENE.instantiate() as RetroSystem
	sys.systemid = "gba"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sys="):
			sys.systemid = a.trim_prefix("--sys=")
	sys.ignore_gravity = true
	get_tree().current_scene.add_child(sys)
	sys.add_to_group("spawned")
	await get_tree().create_timer(3.0).timeout
	var fwd := -cam.global_transform.basis.z
	sys.global_position = cam.global_position + fwd * _dist
	if _pose == "face":
		sys.global_basis = cam.global_basis * Basis(Vector3.RIGHT, deg_to_rad(90.0))
	cam.call("grab_spawned", sys)
	await get_tree().create_timer(1.5).timeout
	print("[hold] held: %s  object %.3f m from the camera" % [cam.call("held_object") != null,
		sys.global_position.distance_to(cam.global_position)])
	if OS.get_cmdline_user_args().has("--leftdrag"):
		await _left_drag_run(cam, sys)
		get_tree().quit(0)
		return
	if OS.get_cmdline_user_args().has("--catch-only"):
		cam.set("_grab_dist", 0.15)
		_mouse(MOUSE_BUTTON_WHEEL_DOWN, true)
		await get_tree().create_timer(1.2).timeout
		var seen := DesktopPickup.visual_bounds(sys)
		var middle := cam.global_transform.affine_inverse() * (sys.global_transform * seen.get_center())
		print("[hold] caught %s; what is seen of it is %.2f m wide, its middle at camera-local %s" % [
			cam.get("_hand_hold"), seen.size.length(), middle])
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_out.path_join("catch_only.png"))
		get_tree().quit(0)
		return
	var sw := _find_power(sys)
	if sw == null:
		print("[hold] no power switch found")
		get_tree().quit(1)
		return
	await _report(cam, sys, sw, "ray-held")
	if OS.get_cmdline_user_args().has("--scenario"):
		await _scenario(cam, sys, sw)
	get_tree().quit(0)


## Where the knob is on screen, and which pixels the resolver answers "the switch" to.
func _report(cam: Camera3D, sys: RetroSystem, sw: Node3D, label: String) -> Array[Vector2]:
	var knob := sw.get("_knob") as MeshInstance3D
	var size := get_viewport().get_visible_rect().size
	var knob_px := cam.unproject_position(knob.global_transform * knob.mesh.get_aabb().get_center())
	var hits := _pixels(cam, sw, 4)
	if hits.is_empty():
		print("[hold] %s: knob at %s (%s mm); no pixel resolves to the switch" % [label, knob_px,
			knob.mesh.get_aabb().size * 1000.0])
		return hits
	var lo := hits[0]
	var hi := hits[0]
	var sum := Vector2.ZERO
	for h in hits:
		lo = Vector2(minf(lo.x, h.x), minf(lo.y, h.y))
		hi = Vector2(maxf(hi.x, h.x), maxf(hi.y, h.y))
		sum += h
	print("[hold] %s: knob at %s; %d pixels answer the switch, box %s..%s, centre %s (view centre %s)" % [
		label, knob_px, hits.size(), lo, hi, sum / hits.size(), size * 0.5])
	return hits


func _pixels(cam: Camera3D, sw: Node3D, step: int) -> Array[Vector2]:
	var size := get_viewport().get_visible_rect().size
	var space := cam.get_world_3d().direct_space_state
	var pivot := get_tree().get_first_node_in_group("desktop_hand") as Node3D
	var hits: Array[Vector2] = []
	for y in range(0, int(size.y), step):
		for x in range(0, int(size.x), step):
			var from := cam.project_ray_origin(Vector2(x, y))
			var to := from + cam.project_ray_normal(Vector2(x, y)) * 5.0
			var t: InteractionTarget = InteractionResolver.resolve_desktop(space, from, to, pivot)
			# What the pointer does with the object in the hand.
			t = InteractionResolver.assist_held(cam.call("held_object") as Node3D, from, to, t)
			if t != null and t.is_valid() and t.pointer_event_target != null \
					and (t.pointer_event_target == sw or sw.is_ancestor_of(t.pointer_event_target)):
				hits.append(Vector2(x, y))
	return hits


func _mouse(button: int, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = pressed
	e.position = get_viewport().get_visible_rect().size * 0.5
	Input.parse_input_event(e)
	if button == MOUSE_BUTTON_LEFT:
		if pressed:
			Input.action_press("trigger_left")
		else:
			Input.action_release("trigger_left")


func _held(cam: Node) -> bool:
	return cam.call("held_object") != null


## Catch, tip it to show the switch, aim at it, click, look away, click.
func _scenario(cam: Camera3D, sys: RetroSystem, sw: Node3D) -> void:
	# One notch past the pull-in limit catches it.
	cam.set("_grab_dist", 0.15)
	_mouse(MOUSE_BUTTON_WHEEL_DOWN, true)
	await get_tree().create_timer(1.2).timeout
	var local := cam.global_transform.affine_inverse() * sys.global_position
	var to_eye := (cam.global_position - sys.global_position).normalized()
	print("[hold] caught: %s, object at camera-local %s; screen normal . to-eye %.3f; top edge . up %.3f" % [
		cam.get("_hand_hold"), local, sys.global_basis.y.normalized().dot(to_eye),
		(-sys.global_basis.z.normalized()).dot(cam.global_basis.y)])
	var screen := sys.get("_model").call("get_builtin_screen") as MeshInstance3D
	if screen != null:
		var box := screen.mesh.get_aabb()
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for i in 8:
			var px := cam.unproject_position(screen.global_transform * box.get_endpoint(i))
			lo = Vector2(minf(lo.x, px.x), minf(lo.y, px.y))
			hi = Vector2(maxf(hi.x, px.x), maxf(hi.y, px.y))
		var view := get_viewport().get_visible_rect().size
		print("[hold] the screen covers %.0f%% of the width, its middle at %s (view centre %s), %.2f m ahead" % [
			(hi.x - lo.x) / view.x * 100.0, (lo + hi) * 0.5, view * 0.5,
			cam.global_position.distance_to(screen.global_transform * box.get_center())])
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join("caught.png"))

	# Tip it toward you, either way, until the switch shows.
	var hits: Array[Vector2] = []
	var base: Basis = cam.get("_hand_cam_basis")
	for deg: float in [-50.0, 50.0, -80.0, 80.0, -30.0, 30.0]:
		cam.set("_hand_cam_basis", Basis(Vector3.RIGHT, deg_to_rad(deg)) * base)
		await get_tree().create_timer(0.4).timeout
		hits = _pixels(cam, sw, 3)
		if not hits.is_empty():
			print("[hold] tipped %.0f deg: the switch shows (%d pixels)" % [deg, hits.size()])
			break
	if hits.is_empty():
		print("[hold] the switch never shows in the hand pose")
		return
	await _report(cam, sys, sw, "in the hand, tipped")
	var tipped_normal := sys.global_basis.y.normalized().dot((cam.global_position - sys.global_position).normalized())
	_mouse(MOUSE_BUTTON_WHEEL_DOWN, true)
	await get_tree().create_timer(1.0).timeout
	var squared := sys.global_basis.y.normalized().dot((cam.global_position - sys.global_position).normalized())
	print("[hold] scrolled in again while tipped: screen faces the eye %.3f -> %.3f, still in hand %s" % [tipped_normal, squared, _held(cam)])
	# tip it again for the rest of the run
	cam.set("_hand_cam_basis", Basis(Vector3.RIGHT, deg_to_rad(-50.0)) * (cam.get("_hand_default_basis") as Basis))
	await get_tree().create_timer(0.6).timeout
	for i in 40:
		if float(cam.get("_hold_blend")) >= 1.0:
			break
		await get_tree().create_timer(0.1).timeout
	print("[hold] after re-tipping: still held %s, hand hold %s" % [_held(cam), cam.get("_hand_hold")])
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join("tipped.png"))

	# Aim the crosshair at the middle of the answering pixels, again as the hand follows.
	var t: InteractionTarget = null
	for attempt in 5:
		hits = _pixels(cam, sw, 3)
		if hits.is_empty():
			print("[hold] aiming: the switch is out of sight on attempt %d" % attempt)
			break
		var sum := Vector2.ZERO
		for h in hits:
			sum += h
		var mid := sum / hits.size()
		cam.look_at(cam.global_position + cam.project_ray_normal(mid), Vector3.UP)
		await get_tree().create_timer(0.5).timeout
		t = cam.call("aimed_target")
		print("[hold] aim %d: crosshair on pixel %s -> kind %s, control %s" % [attempt, mid, t.kind, t.can_activate])
		if t.can_activate:
			break
	var outline := sw.get("_outline") as MeshInstance3D
	print("[hold] the switch's own outline: hovered %s, outline node %s, visible %s, mesh %s" % [sw.get("_pointer_hovered"),
		outline != null, outline.visible if outline != null else "-", outline.mesh != null if outline != null else "-"])
	if outline != null and outline.mesh != null:
		var ab := outline.mesh.get_aabb()
		print("[hold] outline aabb %s at pixel %s, source %s visible %s, material %s" % [ab.size, cam.unproject_position(outline.global_transform * ab.get_center()),
			(sw.get("_knob") as Node3D).name, (sw.get("_knob") as Node3D).is_visible_in_tree(), outline.material_override])
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join("aimed.png"))
	if OS.get_cmdline_user_args().has("--thinyellow"):
		for n in sys.find_children("*", "MeshInstance3D", true, false):
			if n.get_parent() is PickableHighlight:
				var m := (n as MeshInstance3D).material_override as ShaderMaterial
				print("[hold] console overlay %s: mask prio %d, ring prio %d" % [n.name, m.render_priority, (m.next_pass as ShaderMaterial).render_priority])
				(m.next_pass as ShaderMaterial).set_shader_parameter("outline_width", 0.0)
		await get_tree().create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_out.path_join("thinyellow.png"))
	if OS.get_cmdline_user_args().has("--noyellow"):
		for n in sys.find_children("*", "MeshInstance3D", true, false):
			if n.get_parent() is PickableHighlight:
				(n as MeshInstance3D).visible = false
		var hl := sys.find_children("*", "PickableHighlight", true, false)
		print("[hold] noyellow: %d highlight node(s)" % hl.size())
		for h in hl:
			(h as Node3D).visible = false
		await get_tree().create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_out.path_join("noyellow.png"))
	var lit := 0
	for n in sys.find_children("*", "MeshInstance3D", true, false):
		if n.get_parent() is PickableHighlight and (n as MeshInstance3D).visible:
			lit += 1
	print("[hold] crosshair on the switch: the console's own outline shows on %d mesh(es), the switch's outline %s" % [lit, sw.get("_outline").visible])
	var value_before: float = sw.get("value")
	_mouse(MOUSE_BUTTON_LEFT, true)
	await get_tree().create_timer(0.3).timeout
	print("[hold] press on the switch: still held %s, drop armed %s" % [_held(cam), cam.get("_drop_armed")])
	_mouse(MOUSE_BUTTON_LEFT, false)
	await get_tree().create_timer(0.5).timeout
	print("[hold] release on the switch: still held %s (slider value %.2f -> %.2f)" % [
		_held(cam), value_before, sw.get("value")])

	# A near miss: the crosshair a little above the cap, on the shell, still lights the control.
	var knob := sw.get("_knob") as MeshInstance3D
	var knob_px := cam.unproject_position(knob.global_transform * knob.mesh.get_aabb().get_center())
	for lift: float in [10.0, 20.0, 35.0, 60.0]:
		cam.look_at(cam.global_position + cam.project_ray_normal(knob_px + Vector2(0.0, -lift)), Vector3.UP)
		await get_tree().create_timer(0.35).timeout
		var near: InteractionTarget = cam.call("aimed_target")
		print("[hold] crosshair %.0f px above the knob: kind %s, control %s" % [lift, near.kind, near.can_activate])
		await get_tree().create_timer(0.1).timeout
		# the hand follows the gaze past its dead zone, so re-aim from the new knob position
		knob_px = cam.unproject_position(knob.global_transform * knob.mesh.get_aabb().get_center())

	# Look away and click: let go on the way UP.
	cam.rotation_degrees.y += 90.0
	await get_tree().create_timer(0.4).timeout
	_mouse(MOUSE_BUTTON_LEFT, true)
	await get_tree().create_timer(0.3).timeout
	print("[hold] away, press: still held %s, drop armed %s" % [_held(cam), cam.get("_drop_armed")])
	_mouse(MOUSE_BUTTON_LEFT, false)
	await get_tree().create_timer(0.5).timeout
	print("[hold] away, release: still held %s" % _held(cam))


func _find_power(root: Node) -> Node3D:
	# The node that answers the pointer, not the mesh of the same name.
	for n: Node in root.find_children("*", "Node3D", true, false):
		if n is VRSlider and "ower" in str(n.name):
			return n as Node3D
	return null


func _motion(rel: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.relative = rel
	e.position = get_viewport().get_visible_rect().size * 0.5
	Input.parse_input_event(e)


## Hold left on the held object and drag: it turns and is NOT let go; a click with no travel still drops.
func _left_drag_run(cam: Camera3D, sys: RetroSystem) -> void:
	for leg in ["ray", "hand"]:
		if leg == "hand":
			cam.set("_grab_dist", 0.15)
			_mouse(MOUSE_BUTTON_WHEEL_DOWN, true)
			await get_tree().create_timer(1.0).timeout
		var before := sys.global_basis
		var cam_before := cam.global_basis
		var hand_before: Basis = cam.get("_hand_cam_basis")
		_mouse(MOUSE_BUTTON_LEFT, true)
		await get_tree().create_timer(0.1).timeout
		for i in 10:
			_motion(Vector2(80.0, 0.0))
			await get_tree().create_timer(0.03).timeout
			var pvs := (get_tree().get_first_node_in_group("desktop_hand") as Node3D).global_basis
			print("[hold]   pivot %.1f deg, object %.1f deg, camera %.1f deg from before" % [
				rad_to_deg(before.get_rotation_quaternion().angle_to(pvs.get_rotation_quaternion())),
				rad_to_deg(before.get_rotation_quaternion().angle_to(sys.global_basis.get_rotation_quaternion())),
				rad_to_deg(cam_before.get_rotation_quaternion().angle_to(cam.global_basis.get_rotation_quaternion()))])
			print("[hold]   step %d: drag %.1f, turning %s, hand basis %.1f deg" % [i, cam.get("_left_drag"), cam.get("_left_turning"),
				rad_to_deg(hand_before.get_rotation_quaternion().angle_to((cam.get("_hand_cam_basis") as Basis).get_rotation_quaternion()))])
		print("[hold] %s: dragging with left down: held %s, turning %s" % [leg, _held(cam), cam.get("_left_turning")])
		_mouse(MOUSE_BUTTON_LEFT, false)
		await get_tree().create_timer(0.4).timeout
		var turned := rad_to_deg(before.get_rotation_quaternion().angle_to(sys.global_basis.get_rotation_quaternion()))
		var hand_turned := rad_to_deg((hand_before.get_rotation_quaternion()).angle_to((cam.get("_hand_cam_basis") as Basis).get_rotation_quaternion()))
		print("[hold] %s: hand hold %s, blend %s, grab dist %s" % [leg, cam.get("_hand_hold"), cam.get("_hold_blend"), cam.get("_grab_dist")])
		var pv := (get_tree().get_first_node_in_group("desktop_hand") as Node3D).global_basis
		print("[hold] %s: pivot vs object %.1f deg, pivot turned %.1f deg" % [leg,
			rad_to_deg(pv.get_rotation_quaternion().angle_to(sys.global_basis.get_rotation_quaternion())),
			rad_to_deg(before.get_rotation_quaternion().angle_to(pv.get_rotation_quaternion()))])
		print("[hold] %s: after release: held %s; the object turned %.1f deg (hand basis %.1f deg), turning flag %s" % [
			leg, _held(cam), turned, hand_turned, cam.get("_left_turning")])
	# control: a click with no travel lets go
	_mouse(MOUSE_BUTTON_LEFT, true)
	await get_tree().create_timer(0.1).timeout
	_mouse(MOUSE_BUTTON_LEFT, false)
	await get_tree().create_timer(0.4).timeout
	print("[hold] a click without moving: held %s (want false)" % _held(cam))
