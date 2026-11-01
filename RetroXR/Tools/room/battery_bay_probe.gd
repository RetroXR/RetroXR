extends Node3D
## Every primitive handheld's battery bay, seen: the back of each with its cover on,
## then off with its cells in (BatteryBay, docs/dev/power.md). Checks each cover sits
## flush with the back and each cell inside the body. Windowed only:
##
##     godot --path RetroXR res://Tools/room/battery_bay_probe.tscn --resolution 320x240 --position 20,20 -- --out=<dir>

const SYSTEM := preload("res://Scenes/Objects/system.tscn")
const CELLS := {"aa": preload("res://Scenes/Objects/batteries/battery_aa.tscn"),
	"aaa": preload("res://Scenes/Objects/batteries/battery_aaa.tscn")}
const MACHINES := [["gb", "game_boy_primitive"], ["gbc", "game_boy_color_primitive"],
	["gba", "game_boy_advance_primitive"], ["gamegear", "game_gear"], ["atarilynx", "atari_lynx"],
	["wonderswan", "wonderswan"], ["ngp", "neo_geo_pocket"], ["pokemini", "pokemon_mini"],
	["supervision", "supervision"]]

var _vp: SubViewport
var _cam: Camera3D
var _out := "user://battery_bay_probe"
var _fails := 0
var _grabber: Node3D


func _ready() -> void:
	get_tree().create_timer(240.0).timeout.connect(func(): print("[bayprobe] timeout"); get_tree().quit(1))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	_stage()
	_grabber = Node3D.new()
	add_child(_grabber)
	if not "--no-mods" in OS.get_cmdline_user_args():
		print("[bayprobe] mods are mounted: pass -- --no-mods to see the primitives' own bays")
	for row: Array in MACHINES:
		await _one(str(row[0]), str(row[1]))
	print("[bayprobe] ---- %d failed ----" % _fails)
	get_tree().quit(1 if _fails > 0 else 0)


func _one(systemid: String, model_id: String) -> void:
	var sys := SYSTEM.instantiate() as RetroSystem
	sys.systemid = systemid
	sys.model_id = model_id
	sys.freeze = true
	# Face down, so the back looks up at the camera.
	sys.transform = Transform3D(Basis(Vector3.FORWARD, PI), Vector3(0, 0.1, 0))
	add_child(sys)
	sys.add_to_group("spawned")
	await _frames(12)
	var body := sys.find_child("HandheldBody", true, false) as MeshInstance3D
	var slots := CellSlots.of(sys)
	var covers := CoverSlots.of(sys)
	if body == null or slots == null or covers == null:
		_check(false, "%s: a body, seats and covers" % model_id)
		sys.queue_free()
		await _frames(3)
		return
	_check(body.mesh is ArrayMesh, "%s: its body has the pocket cut in" % model_id)
	var back_y := body.get_aabb().position.y
	var to_body := body.global_transform.affine_inverse()
	for socket: String in covers.sockets():
		var lid := covers.slot(socket).picked_up_object as Node3D
		await _frames(2)
		if lid == null:
			_check(false, "%s: cover %s on" % [model_id, socket])
			continue
		var size: Vector3 = lid.get("size")
		var outer := (to_body * (lid.global_transform * Vector3(0, size.y * 0.5, 0))).y
		_check(absf(outer - back_y) < 0.0003, "%s: cover %s flush with the back (%.2f mm off)"
			% [model_id, socket, (outer - back_y) * 1000.0])
		# The desktop ray, straight down onto the cover's middle, takes the cover.
		await get_tree().physics_frame
		var at := lid.global_position
		var t := InteractionResolver.resolve_desktop(get_world_3d().direct_space_state,
			at + Vector3(0.05, 0.25, 0.05), at - Vector3(0.0, 0.01, 0.0) + (at - (at + Vector3(0.05, 0.25, 0.05))).normalized() * 0.0,
			_grabber)
		var took: Node3D = t.action_node if t != null else null
		# Seated, the cover answers as its slot (pull it out), the way a seated cartridge does.
		var seated: Node3D = InteractionResolver.held_pickable(took as XRToolsSnapZone) 			if took is XRToolsSnapZone else took
		_check(seated == lid, "%s: the desktop ray takes cover %s (took %s, %s)" % [model_id, socket,
			str(took.name) if took != null else "-", str(t.kind) if t != null else "-"])
	var aabb := body.get_aabb()
	for seat: String in slots.seats():
		var marker := sys.find_child(seat, true, false) as Node3D
		var p := to_body * marker.global_position
		_check(aabb.grow(-0.001).has_point(p), "%s: seat %s inside the body" % [model_id, seat])
	var size_mm := aabb.size
	var mid := sys.global_position
	var reach := maxf(size_mm.x, size_mm.z) * 1.6 + 0.08
	_cam.look_at_from_position(mid + Vector3(reach * 0.25, reach, reach * 0.55), mid)
	await _shot("%s_shut" % model_id)
	for socket: String in covers.sockets():
		var zone := covers.slot(socket)
		var lid := zone.picked_up_object as RigidBody3D
		zone.drop_object()
		await _frames(2)
		if lid != null:
			lid.freeze = true
			lid.process_mode = Node.PROCESS_MODE_DISABLED
			lid.global_position = mid + Vector3(size_mm.x * 0.5 + 0.06, -0.08, 0)
	var seats := slots.seats()
	for i in seats.size():
		if i % 2 == 1 and seats.size() > 1:
			continue
		var cell := (CELLS[CellSlots.size_of_seat(seats[i]).to_lower()] as PackedScene).instantiate() as Node3D
		add_child(cell)
		cell.add_to_group("spawned")
		slots.slot(seats[i]).pick_up_object(cell)
	await _frames(6)
	await _shot("%s_open" % model_id)
	for n in get_tree().get_nodes_in_group("spawned"):
		n.queue_free()
	await _frames(4)


func _stage() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.3, 0.31, 0.33)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.62)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, -30, 0)
	sun.light_energy = 1.8
	sun.shadow_enabled = true
	add_child(sun)
	_vp = SubViewport.new()
	_vp.size = Vector2i(640, 480)
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_cam = Camera3D.new()
	_cam.fov = 35
	_vp.add_child(_cam)


func _check(ok: bool, what: String) -> void:
	print("[bayprobe] %s: %s" % ["OK" if ok else "FAIL", what])
	if not ok:
		_fails += 1


func _frames(k: int) -> void:
	for i in k:
		await get_tree().process_frame


func _shot(shot_name: String) -> void:
	await _frames(8)
	var path := _out.path_join(shot_name + ".png")
	_vp.get_texture().get_image().save_png(path)
	print("[bayprobe] wrote ", path)
