extends Node3D
## A video of every game case, windowed: each variant in turn, shut with its cover art, turning, then its lid swung
## open on its discs and manual. Writes frames to <out>/frames/NNNNN.png (encode them to an mp4 outside).
##   godot --path RetroXR res://DevTools/cases/case_video_probe.tscn --resolution 1280x720 --position 20,20 -- --out=<dir>
## Uses the games in the player's roms folder: a variant no game there calls for wears one of their art and discs.
## Prints [probe] lines; quits when done.

const CASE_SCENE := preload("res://Scenes/Objects/media/game_case.tscn")
const FPS := 30
const SHUT_S := 1.2
const OPEN_S := 1.4
const HOLD_S := 1.6
## Which game each variant shows: [systemid, rom file].
const PSX := ["psx", "CTR - Crash Team Racing (USA).chd"]
const SEGACD := ["segacd", "Sonic CD (USA).chd"]
const PS2 := ["ps2", "Gran Turismo 4 (USA).bin"]
const GC := ["gc", "Mario Kart - Double Dash!! (USA).rvz"]
const JEWEL_GAME := {"longbox": SEGACD}
const KEEP_GAME := {"gc": GC, "gc_jp": GC, "wiiu": GC}

var _out := ""
var _view: SubViewport
var _world: Node3D
var _cam: Camera3D
var _label: Label
var _frame := 0


func _ready() -> void:
	get_tree().create_timer(900.0).timeout.connect(func() -> void:
		print("[probe] TIMEOUT")
		get_tree().quit(1))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
	if _out.is_empty():
		_out = ProjectSettings.globalize_path("user://case_video")
	DirAccess.make_dir_recursive_absolute(_out.path_join("frames"))
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
	_label.add_theme_font_size_override("font_size", 26)
	_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_label.add_theme_constant_override("outline_size", 8)
	_label.position = Vector2(28, 640)
	layer.add_child(_label)


func _rom(g: Array) -> String:
	return RomLibrary.rom_dir_for_system(str(g[0])).path_join(str(g[1]))


func _make(fam: String, variant: String) -> RetroGameCase:
	var g: Array = (JEWEL_GAME if fam == "jewel" else KEEP_GAME).get(variant, PSX if fam == "jewel" else PS2)
	var rom := _rom(g)
	var c := CASE_SCENE.instantiate() as RetroGameCase
	c.systemid = "psp" if variant == "umd" else str(g[0])
	c.rom_path = rom
	c.game_label = rom.get_file().get_basename()
	c.case_family = fam
	c.case_variant = variant
	var art := RetroGameCase.box_art_path(str(g[0]), rom)
	if not art.is_empty():
		c.box_image = await RetroGameCase.decode_image(get_tree(), art)
	c.freeze = true
	_world.add_child(c)
	c.add_to_group("spawned")
	var discs := PackedStringArray()
	for _i in maxi(1, GameCase.capacity(variant)):
		discs.append(rom)
	c.spawn_contents(discs)
	if c.card_zone() != null:
		var scene := "res://Scenes/Objects/media/%s_memory_card.tscn" % ("ps2" if variant == "ps2" else "gc")
		var card := (load(scene) as PackedScene).instantiate() as MemoryCard
		_world.add_child(card)
		card.global_transform = c.card_zone().global_transform
		c.card_zone().pick_up_object(card)
	return c


func _run() -> void:
	var order: Array = []
	for fam: String in GameCaseModel.FAMILIES:
		for v: String in GameCaseModel.variants_of(fam):
			order.append([fam, v])
	for e in order:
		var c := await _make(str(e[0]), str(e[1]))
		await get_tree().physics_frame
		await get_tree().physics_frame
		var size := c.model.size_m()
		var span := maxf(size.y, size.x * 2.0)
		var turn := Basis(Vector3.RIGHT, -PI * 0.5)
		# Lying on the floor by its back.
		c.global_transform = Transform3D(turn, Vector3(0.0, -c._closed_box.position.z, 0.0))
		var g: Array = (JEWEL_GAME if e[0] == "jewel" else KEEP_GAME).get(e[1], PSX if e[0] == "jewel" else PS2)
		var art_note := "" if (e[1] in JEWEL_GAME or e[1] in KEEP_GAME or e[1] in ["single", "ps2", "pal", "pal_mini"]) \
			else "  [another game's art]"
		_label.text = "%s case: %s   -   %s%s" % ["Jewel" if e[0] == "jewel" else "DVD-style", e[1],
			str(g[1]).get_basename(), art_note]
		print("[probe] %s/%s discs %d manual %s" % [e[0], e[1], c.discs().size(), c.manual() != null])
		# Shut, turning to show the cover.
		var n := int(SHUT_S * FPS)
		for i in n:
			var a := lerpf(-0.35, 0.35, float(i) / n)
			_cam.global_position = Vector3(sin(a) * span * 1.1, span * 1.25, cos(a) * span * 1.1 + span * 0.15)
			_cam.look_at(Vector3(0.0, 0.0, 0.0))
			await _shot()
		# The lid swings open (left), the camera drawing back over the open case.
		var lid := size.x
		n = int(OPEN_S * FPS)
		for i in n:
			var t := float(i + 1) / n
			var deg := 180.0 * (1.0 - pow(1.0 - t, 2.0))
			c.sim.set_angle_deg(c.sim.top(), deg)
			c._apply_angles()
			var centre := Vector3(-lid * 0.5 * t, 0.0, 0.0)
			_cam.global_position = centre + Vector3(0.0, span * (1.25 + 0.35 * t), span * (1.25 - 0.55 * t))
			_cam.look_at(centre)
			await _shot()
		n = int(HOLD_S * FPS)
		for i in n:
			await _shot()
		_clear()
		await get_tree().process_frame


func _clear() -> void:
	for n in get_tree().get_nodes_in_group("spawned"):
		n.queue_free()


func _shot() -> void:
	await RenderingServer.frame_post_draw
	_view.get_texture().get_image().save_png(_out.path_join("frames/%05d.png" % _frame))
	_frame += 1
