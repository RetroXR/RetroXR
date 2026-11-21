extends Node3D
## Every disc game in the player's roms folder in the case the spawn button gives it (GameCase.pick: system, market,
## disc count, box-art shape), with its own box art, disc labels and manual: shut, then opened, its trays turned and
## its manual laid open. Windowed; writes frames/NNNNN.png and stills/<n>_{shut,open}.png under --out.
##   godot --path RetroXR res://DevTools/cases/case_gallery_probe.tscn --resolution 1280x720 --position 20,20 -- --out=<dir>
## Prints [probe] lines; quits when done.

const CASE_SCENE := preload("res://Scenes/Objects/media/game_case.tscn")
const FPS := 30
const SYSTEMS := ["psx", "saturn", "segacd", "dreamcast", "3do", "cdi", "tg-cd", "neogeocd", "pcfx", "ps2", "gc", "wii",
	"wiiu", "xbox", "xbox360", "ps3", "psp"]
const SKIP_EXT := ["bin", "zip", "sav", "srm", "state", "txt", "json", "xml", "png", "jpg"]

var _out := ""
var _view: SubViewport
var _world: Node3D
var _cam: Camera3D
var _label: Label
var _frame := 0


func _ready() -> void:
	get_tree().create_timer(1200.0).timeout.connect(func() -> void:
		print("[probe] TIMEOUT")
		get_tree().quit(1))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
	if _out.is_empty():
		_out = ProjectSettings.globalize_path("user://case_gallery")
	DirAccess.make_dir_recursive_absolute(_out.path_join("frames"))
	DirAccess.make_dir_recursive_absolute(_out.path_join("stills"))
	get_tree().current_scene = self
	_stage()
	await _run()
	print("[probe] frames %d" % _frame)
	get_tree().quit(0)


func _stage() -> void:
	_view = SubViewport.new()
	_view.size = Vector2i(1280, 720)
	_view.own_world_3d = true
	_view.msaa_3d = Viewport.MSAA_4X
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_view)
	_world = Node3D.new()
	_view.add_child(_world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.16, 0.16, 0.17)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.62, 0.62, 0.64)
	env.environment.ambient_light_energy = 0.85
	env.environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	_world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 1.9
	sun.shadow_enabled = true
	_world.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(3, 3)
	floor_mesh.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.32, 0.30, 0.28)
	fm.roughness = 0.8
	floor_mesh.material_override = fm
	floor_mesh.position.y = -0.0005
	_world.add_child(floor_mesh)
	_cam = Camera3D.new()
	_cam.fov = 38.0
	_world.add_child(_cam)
	_cam.current = true
	var layer := CanvasLayer.new()
	_view.add_child(layer)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 24)
	_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_label.add_theme_constant_override("outline_size", 8)
	_label.position = Vector2(24, 646)
	layer.add_child(_label)


## The games on disk: one entry per game (the first disc of a set, a .cue over its .bin, a .zip beside a .cue left
## out), as [systemid, path].
func _games() -> Array:
	var out: Array = []
	for sys: String in SYSTEMS:
		var dir_path := RomLibrary.rom_dir_for_system(sys)
		var d := DirAccess.open(dir_path)
		if d == null:
			continue
		var names: Array = []
		for f in d.get_files():
			if not f.get_extension().to_lower() in SKIP_EXT:
				names.append(f)
		for f in d.get_directories():
			if f != "media" and not f.begins_with("."):
				names.append(f)
		names.sort()
		var seen := {}
		for n: String in names:
			var path := dir_path.path_join(n)
			var discs := GameCase.discs_of(path)
			var first := discs[0] if not discs.is_empty() else path
			if seen.has(first):
				continue
			seen[first] = true
			out.append([sys, first])
	return out


func _run() -> void:
	var games := _games()
	print("[probe] %d games" % games.size())
	var i := 0
	for g in games:
		var sys := str(g[0])
		var rom := str(g[1])
		var discs := GameCase.discs_of(rom)
		var art := RetroGameCase.box_art_path(sys, rom)
		var img: Image = null
		if not art.is_empty():
			img = await RetroGameCase.decode_image(get_tree(), art)
		var size := Vector2i(img.get_width(), img.get_height()) if img != null else Vector2i.ZERO
		var market := GameCase.market_of(sys, rom)
		var pick := GameCase.pick(sys, market, discs.size(), size, GameCase.release_of(sys, rom))
		var c := CASE_SCENE.instantiate() as RetroGameCase
		c.systemid = sys
		c.rom_path = rom
		c.game_label = rom.get_file().get_basename()
		c.case_family = str(pick["family"])
		c.case_variant = str(pick["variant"])
		c.case_color = str(pick["color"])
		c.box_image = img
		c.freeze = true
		_world.add_child(c)
		c.add_to_group("spawned")
		c.spawn_contents(discs)
		for _k in 3:
			await get_tree().physics_frame
		var csize := c.model.size_m()
		var span := maxf(csize.y, csize.x * 2.0)
		c.global_transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, -c._closed_box.position.z, 0.0))
		_label.text = "%s  [%s, %s]  ->  %s case: %s%s   (%d disc%s%s%s)" % [rom.get_file().get_basename(), sys, market,
			"Jewel" if pick["family"] == "jewel" else "DVD-style", pick["variant"],
			(" " + str(pick["color"])) if not str(pick["color"]).is_empty() else "", discs.size(),
			"" if discs.size() == 1 else "s", "" if img != null else ", no box art",
			"" if not c.manual_path().is_empty() else ", no manual"]
		print("[probe] %s" % _label.text)
		# Shut, turning to show its cover.
		var n := 30
		for k in n:
			var a := lerpf(-0.3, 0.3, float(k) / n)
			_cam.global_position = Vector3(sin(a) * span * 1.1, span * 1.25, cos(a) * span * 1.1 + span * 0.15)
			_cam.look_at(Vector3.ZERO)
			await _shot("%02d_shut" % i if k == n / 2 else "")
		# Opened: the lid, then any inner trays, then the manual out and open in front.
		var lid := csize.x
		n = 36
		for k in n:
			var t := float(k + 1) / n
			c.sim.set_angle_deg(c.sim.top(), 180.0 * (1.0 - pow(1.0 - t, 2.0)))
			c._apply_angles()
			var centre := Vector3(-lid * 0.5 * t, 0.0, 0.0)
			_cam.global_position = centre + Vector3(0.0, span * (1.25 + 0.35 * t), span * (1.25 - 0.55 * t))
			_cam.look_at(centre)
			await _shot()
		for k in range(c.sim.count - 2, -1, -1):
			for q in 24:
				c.sim.set_angle_deg(k, 175.0 * (1.0 - pow(1.0 - float(q + 1) / 24.0, 2.0)) - 4.0 * k)
				c._apply_angles()
				await _shot()
		var centre := Vector3(-lid * 0.5, 0.0, 0.0)
		var book := c.manual()
		if book != null:
			c._manual_zone.drop_object()
			book.freeze = true
			book.visible = true
			var depth := csize.y * 0.5 + book.book_height * 0.62
			book.global_transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(centre.x + lid * 0.5, 0.012, depth))
			book.set_page(1, 0)
			for k in 60:
				var t := clampf(float(k + 1) / 30.0, 0.0, 1.0)
				var mid := centre + Vector3(lid * 0.25 * t, 0.0, depth * 0.55 * t)
				_cam.global_position = mid + Vector3(0.0, span * (1.6 + 0.45 * t), span * (0.7 + 0.25 * t))
				_cam.look_at(mid)
				await _shot("%02d_open" % i if k == 59 else "")
		else:
			for k in 30:
				await _shot("%02d_open" % i if k == 29 else "")
		for nd in get_tree().get_nodes_in_group("spawned"):
			nd.queue_free()
		await get_tree().process_frame
		i += 1


func _shot(still := "") -> void:
	await RenderingServer.frame_post_draw
	var img := _view.get_texture().get_image()
	img.save_png(_out.path_join("frames/%05d.png" % _frame))
	if not still.is_empty():
		img.save_png(_out.path_join("stills/%s.png" % still))
	_frame += 1
