## Every object with a lift-off cover (CoverSlots), one still each: its collision boxes (orange), each seated
## cover's box (blue), the slot's old 2.5 cm grab ball (red) and its grab reach (green; CoverSlots.set_hand_reach,
## inner = loose, outer = held). The camera stands out along the covers' outer face. Windowed:
##   "$godot" --path RetroXR --resolution 960x720 res://DevTools/models/cover_reach_probe.tscn [-- --only=<tag>]
extends Node3D

const SYSTEM := preload("res://Scenes/Objects/system.tscn")
const EXPANSION := preload("res://Scenes/Objects/expansion.tscn")
const BRICK := preload("res://Scenes/Objects/power/power_brick.tscn")
const OUT_DIR := "user://probe_shots/covers/"

## [tag, kind, a, b]: system (systemid, model_id), scene (path), brick (brick_id, variant), expansion (id).
const ROWS := [
	["wiimote", "scene", "res://Scenes/Objects/controllers/wii/wiimote.tscn", ""],
	["game_boy", "system", "gb", "game_boy_primitive"],
	["game_boy_color", "system", "gbc", "game_boy_color_primitive"],
	["game_boy_advance", "system", "gba", "game_boy_advance_primitive"],
	["game_gear", "system", "gamegear", "game_gear"],
	["atari_lynx", "system", "atarilynx", "atari_lynx"],
	["wonderswan", "system", "wonderswan", "wonderswan"],
	["neo_geo_pocket", "system", "ngp", "neo_geo_pocket"],
	["pokemon_mini", "system", "pokemini", "pokemon_mini"],
	["supervision", "system", "supervision", "supervision"],
	["gb_printer", "scene", "res://Scenes/Objects/peripherals/gb_printer.tscn", ""],
	["super_scope", "scene", "res://Scenes/Objects/peripherals/super_scope.tscn", ""],
	["nes_satellite", "scene", "res://Scenes/Objects/controllers/nes/nes_satellite.tscn", ""],
	["tv_remote", "scene", "res://Scenes/Objects/appliances/tv_remote.tscn", ""],
	["vb_battery_pack", "scene", "res://Scenes/Objects/power/vb_battery_pack.tscn", ""],
	["vb_ac_tap", "scene", "res://Scenes/Objects/power/vb_ac_tap.tscn", ""],
	["dmg_battery_case", "brick", "dmg_battery_case", "jpn"],
	["fds", "expansion", "fds", ""],
	["rumble_pak", "scene", "res://Scenes/Objects/controllers/n64/rumble_pak.tscn", ""],
]

var _cam: Camera3D
var _drawn: Array[Node] = []
var _only := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7)
	get_tree().create_timer(240.0).timeout.connect(func() -> void: print("[probe] timeout"); get_tree().quit(1))
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.14, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.65)
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	_cam = Camera3D.new()
	_cam.fov = 35.0
	add_child(_cam)
	_cam.make_current()
	await _frames(10)
	for o in LoadingOverlay.owners():
		LoadingOverlay.end(o)
	LoadingOverlay.suspend()
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	for row: Array in ROWS:
		if _only.is_empty() or _only == row[0]:
			await _one(row)
	get_tree().quit(0)


func _spawn(row: Array) -> Node3D:
	match str(row[1]):
		"system":
			var sys := SYSTEM.instantiate() as RetroSystem
			sys.systemid = row[2]
			sys.model_id = row[3]
			return sys
		"expansion":
			var unit := EXPANSION.instantiate() as RetroExpansion
			unit.expansion_id = row[2]
			return unit
		"brick":
			var brick := BRICK.instantiate() as PowerBrick
			brick.brick_id = row[2]
			brick.variant = row[3]
			return brick
	return (load(str(row[2])) as PackedScene).instantiate() as Node3D


func _one(row: Array) -> void:
	var tag := str(row[0])
	var obj := _spawn(row)
	if obj is RigidBody3D:
		(obj as RigidBody3D).freeze = true
	add_child(obj)
	obj.add_to_group("spawned")
	await _frames(30)
	var zones: Array[XRToolsSnapZone] = []
	for n in obj.find_children("*", "XRToolsSnapZone", true, false):
		if n.is_in_group(CoverSlots.SLOT_GROUP):
			zones.append(n as XRToolsSnapZone)
	if zones.is_empty():
		print("[probe] %s: no cover slot" % tag)
		await _clear()
		return
	# Object collision: every body shape but pointer targets and the covers themselves.
	for shape: CollisionShape3D in obj.find_children("*", "CollisionShape3D", true, false):
		var body := shape.get_parent() as CollisionObject3D
		if body == null or body is Area3D or body is PortCover or body.collision_layer == 1048576 \
				or shape.disabled or shape.shape == null:
			continue
		if not body is PhysicsBody3D:
			continue
		_shape(shape, Color(1.0, 0.55, 0.1), 0.10)
	var mid := Vector3.ZERO
	var out := Vector3.ZERO
	var span := 0.0
	for zone in zones:
		var cover := zone.picked_up_object as PortCover
		if cover != null:
			_box(cover.global_transform, cover.size, Color(0.25, 0.55, 1.0), 0.35)
		_ball(zone.global_position, zone.grab_distance, Color(1.0, 0.15, 0.15), 0.35)
		var rb := zone.reach_box
		var note := "kept the ball"
		if rb.size != Vector3.ZERO:
			_box(zone.global_transform * Transform3D(Basis.IDENTITY, rb.get_center()), rb.size, Color(0.2, 1.0, 0.35), 0.10)
			var loose := AABB(rb.position, Vector3(rb.size.x, zone.reach_core.size.y + CoverSlots.HAND_REACH_OUT_LOOSE, rb.size.z))
			_box(zone.global_transform * Transform3D(Basis.IDENTITY, loose.get_center()), loose.size, Color(0.2, 1.0, 0.35), 0.12)
			note = "reach box %s" % rb.size
		print("[probe] %s: %s cover %s, %s" % [tag, zone.name, cover.size if cover != null else "none", note])
		mid += zone.global_position
		out += zone.global_basis.y.normalized()
		var sz: Vector3 = cover.size if cover != null else Vector3(0.05, 0, 0.05)
		span = maxf(span, maxf(sz.x, sz.z))
	mid /= zones.size()
	out = out.normalized() if out.length() > 0.01 else Vector3.UP
	var aabb := _bounds(obj)
	var reach := minf(aabb.size.length() * 1.7, (span + 0.08) * 2.6)
	# Out along the covers' face, tipped to one side so the reach box reads as a box.
	var side := out.cross(Vector3.UP if absf(out.y) < 0.9 else Vector3.RIGHT).normalized()
	var up := side.cross(out).normalized()
	var from := mid + (out * 0.8 + side * 0.45 + up * 0.35).normalized() * reach
	_cam.look_at_from_position(from, mid + out * 0.015, up)
	await _frames(4)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := OUT_DIR + tag + ".png"
	print("[probe] saved ", ProjectSettings.globalize_path(path), " err=", img.save_png(path))
	await _clear()


func _bounds(obj: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in obj.find_children("*", "MeshInstance3D", true, false):
		if not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		var b := mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _clear() -> void:
	for n in get_tree().get_nodes_in_group("spawned"):
		n.queue_free()
	for n in get_tree().get_nodes_in_group(PortCover.GROUP):
		n.queue_free()
	for n in _drawn:
		if is_instance_valid(n):
			n.queue_free()
	_drawn.clear()
	await _frames(4)


func _shape(cs: CollisionShape3D, col: Color, alpha: float) -> void:
	var s := cs.shape
	if s is BoxShape3D:
		_box(cs.global_transform, (s as BoxShape3D).size, col, alpha)
		return
	var mesh := s.get_debug_mesh()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(col, 0.12)
	add_child(mi)
	_drawn.append(mi)
	mi.global_transform = cs.global_transform


func _ball(at: Vector3, r: float, col: Color, alpha: float) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	mi.mesh = sm
	mi.material_override = _mat(col, alpha)
	add_child(mi)
	_drawn.append(mi)
	mi.global_position = at


func _box(at: Transform3D, size: Vector3, col: Color, alpha: float) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(col, alpha)
	add_child(mi)
	_drawn.append(mi)
	mi.global_transform = at
	var lines := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var h := size * 0.5
	for a in 3:
		for s1 in [-1.0, 1.0]:
			for s2 in [-1.0, 1.0]:
				var p := Vector3.ZERO
				p[(a + 1) % 3] = h[(a + 1) % 3] * s1
				p[(a + 2) % 3] = h[(a + 2) % 3] * s2
				var q := p
				p[a] = -h[a]
				q[a] = h[a]
				im.surface_add_vertex(p)
				im.surface_add_vertex(q)
	im.surface_end()
	lines.mesh = im
	lines.material_override = _mat(col, 1.0)
	add_child(lines)
	_drawn.append(lines)
	lines.global_transform = at


func _mat(col: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if alpha < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	else:
		m.no_depth_test = true
	return m


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
