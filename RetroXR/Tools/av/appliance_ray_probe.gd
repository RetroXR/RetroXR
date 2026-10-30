## Every control on the RETRO XR appliances: its collider against what it draws, and what the desktop ray takes
## when aimed at its middle from each side. Headless is fine (physics only).
##   "$godot" --headless --path RetroXR res://Tools/av/appliance_ray_probe.tscn
extends Node

const SCENES := {
	"vcr": "res://Scenes/Objects/appliances/vcr_player.tscn",
	"dvd": "res://Scenes/Objects/appliances/dvd_player.tscn",
	"amp": "res://Scenes/Objects/appliances/surround_amp.tscn",
	"turntable": "res://Scenes/Objects/appliances/record_player.tscn",
	"tv": "res://Scenes/Objects/tv.tscn",
}
const DIRS := {"+X": Vector3.RIGHT, "-X": Vector3.LEFT, "+Y": Vector3.UP, "+Z": Vector3.BACK, "-Z": Vector3.FORWARD}

var _grabber: Node3D


func _ready() -> void:
	get_tree().create_timer(80.0).timeout.connect(func() -> void: get_tree().quit(2))
	_grabber = Node3D.new()
	add_child(_grabber)
	for key in SCENES:
		await _probe(key, SCENES[key])
	get_tree().quit(0)


func _is_control(n: Node) -> bool:
	return n is VRButton or n is VRKnob or n is VRHinge or n is VRLever or n is VRSlider


func _shown(n: Node3D, skip_controls: bool) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		if c != n and skip_controls and _is_control(c):
			continue
		if c is GeometryInstance3D and (c as GeometryInstance3D).is_visible_in_tree() \
				and (c as GeometryInstance3D).visibility_range_begin <= 0.0 and not (c is Label3D):
			var g := c as GeometryInstance3D
			var box: AABB = g.global_transform * g.get_aabb()
			if box.size.length() > 0.0:
				out = box if first else out.merge(box)
				first = false
		for k in c.get_children():
			stack.append(k)
	return out


func _shapes(n: Node3D, skip_controls: bool) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		if c != n and (_is_control(c) if skip_controls else false):
			continue
		if c is CollisionShape3D and (c as CollisionShape3D).shape != null and not (c as CollisionShape3D).disabled:
			var cs := c as CollisionShape3D
			var owner_obj := cs.get_parent()
			if owner_obj is CollisionObject3D and not (owner_obj is XRToolsSnapZone):
				var box: AABB = cs.global_transform * cs.shape.get_debug_mesh().get_aabb()
				out = box if first else out.merge(box)
				first = false
		for k in c.get_children():
			stack.append(k)
	return out


func _excess(coll: AABB, shown: AABB) -> float:
	var e := 0.0
	for i in 3:
		e = maxf(e, coll.end[i] - shown.end[i])
		e = maxf(e, shown.position[i] - coll.position[i])
	return e


func _probe(key: String, path: String) -> void:
	var scene := load(path) as PackedScene
	var root := scene.instantiate() as Node3D
	if key == "tv":
		root.set("tv_model", "retroxr_crt")
	add_child(root)
	root.global_position = Vector3(0, 1, 0)
	for i in 40:
		await get_tree().physics_frame
	var body_shown := _shown(root, true)
	var body_coll := _shapes(root, true)
	print("[probe] %s body shown %s coll %s excess %.1f mm" % [key, body_shown.size, body_coll.size, _excess(body_coll, body_shown) * 1000.0])
	var model := root.find_child("Model", true, false) as ApplianceModel
	if model and key in ["turntable", "tv"]:
		for g in model.levels[0].find_children("*", "GeometryInstance3D", true, false):
			var gi := g as GeometryInstance3D
			if not gi.is_visible_in_tree():
				continue
			var bb: AABB = (root.global_transform.affine_inverse() * gi.global_transform) * gi.get_aabb()
			print("[probe]  part %s %s: y %.3f..%.3f z %.3f..%.3f x %.3f..%.3f" % [key, gi.name, bb.position.y, bb.end.y, bb.position.z, bb.end.z, bb.position.x, bb.end.x])
	await _controls(key, root, body_shown)
	if key == "tv":
		var shell := root.find_child("RetroXRCrt", true, false)
		if shell:
			shell.call("set_door_open", true)
			for i in 5:
				await get_tree().physics_frame
			await _controls(key + "(door open)", root, body_shown)
	if key == "turntable":
		for v in [0.0, 1.0]:
			var lever := root.get_node("CoverPivot/CoverLever")
			lever.call("set_value", v)
			for i in 10:
				await get_tree().physics_frame
			await _controls(key + "(cover %s)" % ("shut" if v == 0.0 else "open"), root, body_shown)
	root.queue_free()
	for i in 3:
		await get_tree().process_frame


func _controls(key: String, root: Node3D, body_shown: AABB) -> void:
	var space := root.get_world_3d().direct_space_state
	for n in root.find_children("*", "Node3D", true, false):
		if not _is_control(n) or not (n as Node3D).is_visible_in_tree():
			continue
		var c := n as Node3D
		var shown := _shown(c, false)
		var coll := _shapes(c, false)
		var mid := shown.get_center() if shown.size.length() > 0.0 else coll.get_center()
		var takes: Array[String] = []
		var miss: Array[String] = []
		for d in DIRS:
			var dir: Vector3 = DIRS[d]
			var t := InteractionResolver.resolve_desktop(space, mid + dir * 0.6, mid - dir * 0.05, _grabber)
			if t != null and (t.action_node == c or t.highlight_node == c):
				takes.append(d)
			else:
				if d == "+Z" or d == "+Y":
					var q := PhysicsRayQueryParameters3D.create(mid + dir * 0.6, mid - dir * 0.05, InteractionResolver.QUERY_MASK)
					q.collide_with_areas = true
					var ex: Array[RID] = []
					for k in 3:
						q.exclude = ex
						var h := space.intersect_ray(q)
						if h.is_empty():
							break
						print("[probe]    %s hit %d: %s shape %d at %.1f mm" % [d, k, root.get_path_to(h.collider), h.shape, (h.position - mid).dot(dir) * 1000.0])
						ex.append(h.rid)
				miss.append("%s=%s" % [d, (t.action_node.name if t != null and t.action_node != null else "-")])
		var rec := -1.0
		if c is VRButton:
			var out_dir: Vector3 = -(c.global_basis * (c as VRButton).depress_axis).normalized()
			var ax := 0 if absf(out_dir.x) > 0.7 else (1 if absf(out_dir.y) > 0.7 else 2)
			var sgn := signf(out_dir[ax])
			var key_face: float = shown.end[ax] if sgn > 0 else shown.position[ax]
			var body_face: float = body_shown.end[ax] if sgn > 0 else body_shown.position[ax]
			rec = (body_face - key_face) * sgn * 1000.0
		print("[probe] %s recess %.1f mm" % [c.name, rec])
		print("[probe] %s %s %s shown %s coll %s excess %.1f mm | takes %s | %s" % [key, c.get_class() if c.get_script() == null else (c.get_script() as Script).get_global_name(),
			root.get_path_to(c), (shown.size * 1000.0).snapped(Vector3.ONE * 0.1), (coll.size * 1000.0).snapped(Vector3.ONE * 0.1),
			_excess(coll, shown) * 1000.0, ",".join(takes), " ".join(miss)])
