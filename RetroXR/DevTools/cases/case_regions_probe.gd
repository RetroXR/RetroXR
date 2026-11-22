extends Node3D
## A game case being opened, with what the game tests against drawn over it: its collision (the body's hull, the
## lid's and the base's own test boxes), its snap zones (where a thing let go is taken in, where a grip takes the
## manual out), the hands' regions (each handle's trigger reach and fingertip panel, the base's handle live only
## when the case is held by its lid, the quiet over a seated manual) and the desktop pointer's targets.
## Windowed. One PNG per case, angle and layer under --out: <family>_<variant>_<angle|held>_<layer>.png.
##   godot --path RetroXR res://DevTools/cases/case_regions_probe.tscn --resolution 640x360 --position 20,20 -- --out=<dir> [--cases=keep/multi5/ps2,...]
## Prints [viz] lines; quits when done.
const CASE_SCENE := preload("res://Scenes/Objects/media/game_case.tscn")
const DISC_SCENE := preload("res://Scenes/Objects/media/disc.tscn")
const BOOK_SCENE := preload("res://Scenes/Objects/media/pdf_book.tscn")
const ANGLES := [0.0, 60.0, 120.0, 180.0]
const LAYERS := ["collision", "snap", "grab", "pointer"]
const CASES := [["jewel", "single", "psx"], ["keep", "ps2", "ps2"], ["jewel", "fatbox2", "psx"]]

class StandInHand extends Node3D:
	var picked_up_ranged := false


var _out := ""
var _view: SubViewport
var _world: Node3D
var _cam: Camera3D
var _overlay: Node3D


func _ready() -> void:
	get_tree().create_timer(300.0).timeout.connect(func() -> void:
		print("[viz] TIMEOUT")
		get_tree().quit(1))
	var cases: Array = CASES
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
		elif arg.begins_with("--cases="):                # family/variant/system, comma separated
			cases = []
			for one in arg.substr(8).split(",", false):
				cases.append(Array(one.split("/")))
	if _out.is_empty():
		_out = ProjectSettings.globalize_path("user://case_regions")
	DirAccess.make_dir_recursive_absolute(_out)
	_stage()
	for row: Array in cases:
		await _case(row[0], row[1], row[2])
	print("[viz] done")
	get_tree().quit(0)


func _stage() -> void:
	_view = SubViewport.new()
	_view.size = Vector2i(720, 540)
	_view.own_world_3d = true
	_view.msaa_3d = Viewport.MSAA_4X
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_view)
	_world = Node3D.new()
	_view.add_child(_world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.13, 0.13, 0.15)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.75, 0.75, 0.78)
	env.environment.ambient_light_energy = 0.9
	_world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 1.4
	_world.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2, 2)
	floor_mesh.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.23, 0.22, 0.21)
	fm.roughness = 0.9
	floor_mesh.material_override = fm
	_world.add_child(floor_mesh)
	_cam = Camera3D.new()
	_cam.fov = 30.0
	_world.add_child(_cam)
	_cam.current = true
	_overlay = Node3D.new()
	_world.add_child(_overlay)


func _manual_fixture() -> String:
	var path := OS.get_user_data_dir().path_join("__game_case_viz_manual.cbz")
	var zip := ZIPPacker.new()
	zip.open(path)
	for i in 8:
		var img := Image.create(200, 300, false, Image.FORMAT_RGB8)
		img.fill(Color(0.85, 0.83, 0.78) if i > 0 else Color(0.75, 0.2, 0.2))
		zip.start_file("page_%02d.png" % i)
		zip.write_file(img.save_png_to_buffer())
		zip.close_file()
	zip.close()
	return path


func _case(family: String, variant: String, sys: String) -> void:
	var c := CASE_SCENE.instantiate() as RetroGameCase
	c.systemid = sys
	c.case_family = family
	c.case_variant = variant
	c.case_color = "" if family == "jewel" else "silver"
	c.freeze = true
	_world.add_child(c)
	await get_tree().physics_frame
	var bottom := -c._closed_box.position.z
	c.global_transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, bottom + 0.0005, 0.0))
	for i in c._zones.size():
		var d := DISC_SCENE.instantiate() as RetroDisc
		d.systemid = sys
		_world.add_child(d)
		c.disc_zone(i).pick_up_object(d)
	if c._manual_zone != null:
		var book := BOOK_SCENE.instantiate() as PDFBook
		book.freeze = true
		book.book_height = c.model.manual_size_m().y
		book.pdf_path = _manual_fixture()
		_world.add_child(book)
		for _i in 4:
			await get_tree().process_frame
		for _i in 4:
			await get_tree().physics_frame
		for _i in 300:
			if book._pending_renders.is_empty():
				break
			await get_tree().process_frame
		# Opened first: a manual goes in under an open lid.
		c.sim.set_angle_deg(c.sim.top(), 120.0)
		c._apply_angles()
		c._manual_zone.pick_up_object(book)
	for _i in 6:
		await get_tree().physics_frame
	for _i in 3:
		await get_tree().process_frame
	# From here the probe poses the hinge itself.
	c.set_physics_process(false)
	var top := c.sim.top()
	var open_max := rad_to_deg(c.sim.open_max)
	for want: float in ANGLES:
		var deg := minf(want, open_max)
		c.sim.set_angle_deg(top, deg)
		if deg <= 0.0:
			c.sim.latched = true
		for i in top:                                   # inner trays: half way under an open lid
			c.sim.set_angle_deg(i, clampf(deg * 0.5, 0.0, deg))
		c._apply_angles()
		for _i in 4:
			await get_tree().physics_frame
		c._apply_angles()
		var span := c.model.size_m()
		var target := Vector3(-span.x * (0.55 if deg > 90.0 else 0.15), 0.03, 0.0)
		_cam.global_position = target + Vector3(0.12, 0.36, 0.44)
		_cam.look_at(target)
		for layer: String in LAYERS:
			for n in _overlay.get_children():
				n.queue_free()
			await get_tree().process_frame
			call("_draw_" + layer, c)
			for _i in 3:
				await RenderingServer.frame_post_draw
			_view.get_texture().get_image().save_png(_out.path_join("%s_%s_%03d_%s.png" % [family, variant, int(want), layer]))
	# Held by its lid at 120: the base's handle is the live one, and the base's box is what is tested.
	c.sim.set_angle_deg(top, 120.0)
	for i in top:
		c.sim.set_angle_deg(i, 60.0)
	c._apply_angles()
	for _i in 4:
		await get_tree().physics_frame
	c._apply_angles()
	var hand := StandInHand.new()
	_world.add_child(hand)
	hand.global_transform = c.global_transform * Transform3D(Basis.IDENTITY, c._lid_swing() * c._lid_box.get_center())
	c.pick_up(hand)
	var span2 := c.model.size_m()
	var target2 := Vector3(-span2.x * 0.55, 0.03, 0.0)
	_cam.global_position = target2 + Vector3(0.12, 0.36, 0.44)
	_cam.look_at(target2)
	for layer: String in LAYERS:
		for n in _overlay.get_children():
			n.queue_free()
		await get_tree().process_frame
		call("_draw_" + layer, c)
		for _i in 3:
			await RenderingServer.frame_post_draw
		_view.get_texture().get_image().save_png(_out.path_join("%s_%s_held_%s.png" % [family, variant, layer]))
	print("[viz]    held by the lid: %s" % c.held_by_lid())
	c.let_go(hand, Vector3.ZERO, Vector3.ZERO)
	hand.queue_free()
	print("[viz] %s/%s: open max %.1f, zones %d, manual %s" % [family, variant, open_max, c._zones.size(), c.manual() != null])
	for n in _overlay.get_children():
		n.queue_free()
	for n in _world.get_children():
		if n is RetroGameCase or n is RetroDisc or n is PDFBook:
			n.queue_free()
	for _i in 3:
		await get_tree().process_frame


# ------------------------------------------------------------------ what is drawn
func _draw_collision(c: RetroGameCase) -> void:
	# The body's one convex hull: what the case collides with the world by.
	var hull := MeshInstance3D.new()
	hull.mesh = c._body_shape.shape.get_debug_mesh()
	hull.material_override = _fill_mat(Color(1.0, 0.25, 0.2), 0.3)
	_overlay.add_child(hull)
	hull.global_transform = c._body_shape.global_transform
	# The lid's own test against the world (its box, 1.5 mm smaller all round), and the base's for a case held by its lid.
	var deg := c.lid_deg()
	c._lid_blocked(deg)
	_box(c.global_transform * c._swing_at(deg) * Transform3D(Basis.IDENTITY, c._lid_box.get_center()), c._lid_probe.size, Color(1.0, 0.65, 0.1), 0.35)
	_box(c.global_transform * Transform3D(Basis.IDENTITY, c._base_box.get_center()), c._base_probe.size, Color(0.35, 0.6, 1.0),
		0.4 if c.held_by_lid() else 0.12)


func _draw_snap(c: RetroGameCase) -> void:
	var zones: Array = []
	for z in c._zones:
		zones.append(z)
	for z: XRToolsSnapZone in [c._holder_zone, c._card_zone, c._manual_zone]:
		if z != null:
			zones.append(z)
	for z: XRToolsSnapZone in zones:
		var on := z.enabled
		var col := Color(0.2, 0.85, 1.0) if on else Color(0.5, 0.5, 0.55)
		var ball := z.get_node_or_null("CollisionShape3D") as CollisionShape3D
		var at := ball.global_position if ball != null else z.global_position
		_sphere(at, z.grab_distance, col)                # where a thing let go is taken in
		_cross(z.global_position, 0.006, Color(1, 1, 1))  # the zone's own origin: where its thing's origin goes
		if z.reach_box.size != Vector3.ZERO and on:       # where a grip takes its thing out, when not that ball
			_shell(z.global_transform, z.reach_box, func(at: Vector3) -> bool: return z.reaches(at) >= 0.0,
				Color(0.3, 1.0, 0.35))


func _draw_grab(c: RetroGameCase) -> void:
	var handles: Array = []
	for i in c._rigs.size():
		handles.append([c.hinge(i), Color(1.0, 0.9, 0.2)])
	handles.append([c._base_hinge, Color(1.0, 0.3, 0.9)])
	for row: Array in handles:
		var h := row[0] as CaseHinge
		var live := h._can_engage()
		var col := (row[1] as Color) if live else Color(0.5, 0.5, 0.55)
		_sphere(h.global_position, h.engage_radius, col)                       # the trigger's reach
		var panel := h.get_node_or_null("PokePanel") as CollisionShape3D
		if panel != null:                                                      # the fingertip's faces
			_box(panel.global_transform, (panel.shape as BoxShape3D).size, col, 0.2 if live else 0.08)
	# Where the lid's handle is quiet: over the manual, by the case's own test.
	if c._manual_zone != null and c.manual() != null and c._manual_zone.reach_box.size != Vector3.ZERO:
		var z := c._manual_zone
		_shell(z.global_transform, z.reach_box, c._lid_quiet, Color(0.3, 1.0, 0.35))


func _draw_pointer(c: RetroGameCase) -> void:
	# The case's own pointer target (white), each hinge's grab box (yellow) and what is seated in it (green).
	for cs in c.get_node("PointerArea").get_children():
		var shape := cs as CollisionShape3D
		if shape != null and not shape.disabled and shape.shape is BoxShape3D:
			_box(shape.global_transform, (shape.shape as BoxShape3D).size, Color(1, 1, 1), 0.18)
	for i in c._rigs.size():
		var grab := c.hinge(i).get_node_or_null("CollisionShape3D") as CollisionShape3D
		if grab != null and not grab.disabled:
			_box(grab.global_transform, (grab.shape as BoxShape3D).size, Color(1.0, 0.9, 0.2), 0.25)
	var held: Array = []
	for z in c._zones:
		held.append(z.picked_up_object)
	held.append(c.manual())
	for obj in held:
		var body := obj as Node3D
		if body == null:
			continue
		var area := body.get_node_or_null("PointerArea")
		if area == null:
			continue
		for cs in area.get_children():
			var shape := cs as CollisionShape3D
			if shape == null or shape.disabled or shape.shape == null:
				continue
			var mesh := MeshInstance3D.new()
			mesh.mesh = shape.shape.get_debug_mesh()
			mesh.material_override = _fill_mat(Color(0.3, 1.0, 0.35), 0.35)
			_overlay.add_child(mesh)
			mesh.global_transform = shape.global_transform


# ------------------------------------------------------------------ drawing
func _line_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.no_depth_test = true
	m.render_priority = 5
	return m


func _fill_mat(col: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = true
	m.render_priority = 3
	return m


func _lines(points: PackedVector3Array, col: Color) -> void:
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _line_mat(col)
	_overlay.add_child(mi)


func _box(xf: Transform3D, size: Vector3, col: Color, alpha := 0.2) -> void:
	var fill := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	fill.mesh = bm
	fill.material_override = _fill_mat(col, alpha)
	_overlay.add_child(fill)
	fill.global_transform = xf
	var h := size * 0.5
	var corners: Array[Vector3] = []
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				corners.append(xf * Vector3(h.x * sx, h.y * sy, h.z * sz))
	var pts := PackedVector3Array()
	for a in 8:
		for b in range(a + 1, 8):
			var differ := 0
			for bit in 3:
				if ((a >> bit) & 1) != ((b >> bit) & 1):
					differ += 1
			if differ == 1:
				pts.append(corners[a])
				pts.append(corners[b])
	_lines(pts, col)


## The part of `box` (in `xf`'s space) that `keep` (a world point -> bool) says yes to, as dots on its surface: the
## game's own test asked point by point, not a shape redrawn here.
func _shell(xf: Transform3D, box: AABB, keep: Callable, col: Color, step := 0.005) -> void:
	var n := Vector3i(maxi(2, int(box.size.x / step) + 1), maxi(2, int(box.size.y / step) + 1), maxi(2, int(box.size.z / step) + 1))
	var yes := PackedByteArray()
	yes.resize(n.x * n.y * n.z)
	var world: Array[Vector3] = []
	world.resize(yes.size())
	for ix in n.x:
		for iy in n.y:
			for iz in n.z:
				var local := box.position + Vector3(box.size.x * ix / (n.x - 1), box.size.y * iy / (n.y - 1), box.size.z * iz / (n.z - 1))
				var at := xf * local
				var k := (ix * n.y + iy) * n.z + iz
				world[k] = at
				yes[k] = 1 if keep.call(at) else 0
	var pts := PackedVector3Array()
	for ix in n.x:
		for iy in n.y:
			for iz in n.z:
				var k := (ix * n.y + iy) * n.z + iz
				if yes[k] == 0:
					continue
				var edge := ix == 0 or iy == 0 or iz == 0 or ix == n.x - 1 or iy == n.y - 1 or iz == n.z - 1
				if not edge:
					edge = yes[k - n.y * n.z] == 0 or yes[k + n.y * n.z] == 0 or yes[k - n.z] == 0 or yes[k + n.z] == 0
				if not edge:
					edge = yes[k - 1] == 0 or yes[k + 1] == 0
				if edge:
					pts.append(world[k])
	if pts.is_empty():
		return
	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pts
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays)
	var m := _line_mat(col)
	m.use_point_size = true
	m.point_size = 2.5
	m.albedo_color = Color(col.r, col.g, col.b, 0.75)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	_overlay.add_child(mi)


func _sphere(at: Vector3, r: float, col: Color) -> void:
	var pts := PackedVector3Array()
	for axis in 3:
		for k in 48:
			for step in [k, k + 1]:
				var a := TAU * float(step) / 48.0
				var p := Vector3.ZERO
				p[(axis + 1) % 3] = cos(a) * r
				p[(axis + 2) % 3] = sin(a) * r
				pts.append(at + p)
	_lines(pts, col)


func _cross(at: Vector3, r: float, col: Color) -> void:
	var pts := PackedVector3Array()
	for axis in 3:
		var d := Vector3.ZERO
		d[axis] = r
		pts.append(at - d)
		pts.append(at + d)
	_lines(pts, col)
