extends Node3D
## How disc games' cases LOOK, windowed (game_case_tests checks them headless):
##   godot --path RetroXR res://DevTools/cases/case_probe.tscn --resolution 1280x720 --position 20,20 -- --out=<dir>
## Builds cases for the games in the player's roms folder (their real box-texture, discs and manual), plus the
## variants no game there calls for with one game's art, and shoots them shut, open and swinging under gravity.
## Prints [probe] lines; quits when done.

const CASE_SCENE := preload("res://Scenes/Objects/media/game_case.tscn")
const GAMES := [
	["psx", "CTR - Crash Team Racing (USA).chd"],
	["psx", "Crash Bandicoot 3 - Buttobi! Sekai Isshuu (Japan, Asia).cue"],
	["segacd", "Sonic CD (USA).chd"],
	["ps2", "Gran Turismo 4 (USA).bin"],
	["gc", "Mario Kart - Double Dash!! (USA).rvz"],
]
## Variants with no game here: [family, variant, game index whose art it wears].
const EXTRA := [["jewel", "pal", 0], ["jewel", "fatbox4", 0], ["keep", "multi5", 3], ["keep", "wiiu", 4]]

var _out := ""
var _view: SubViewport
var _world: Node3D
var _cam: Camera3D
var _cases: Array[RetroGameCase] = []


func _ready() -> void:
	get_tree().create_timer(180.0).timeout.connect(func() -> void:
		print("[probe] TIMEOUT")
		get_tree().quit(1))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
	if _out.is_empty():
		_out = ProjectSettings.globalize_path("user://case_probe")
	DirAccess.make_dir_recursive_absolute(_out)
	get_tree().current_scene = self
	_stage()
	await _run()
	get_tree().quit(0)


func _stage() -> void:
	# Its own world: the desktop loading screen covers the main view.
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
	env.environment.background_color = Color(0.2, 0.2, 0.21)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.62)
	env.environment.ambient_light_energy = 0.9
	env.environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	_world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -25, 0)
	sun.light_energy = 2.0
	sun.shadow_enabled = true
	_world.add_child(sun)
	_cam = Camera3D.new()
	_cam.fov = 40.0
	_world.add_child(_cam)
	_cam.current = true


func _rom(sys: String, file: String) -> String:
	return RomLibrary.rom_dir_for_system(sys).path_join(file)


func _make(sys: String, rom: String, fam := "", variant := "", art_from := "") -> RetroGameCase:
	var c := CASE_SCENE.instantiate() as RetroGameCase
	c.systemid = sys
	c.rom_path = rom
	c.game_label = rom.get_file().get_basename()
	var art := RetroGameCase.box_art_path(sys, art_from if not art_from.is_empty() else rom)
	var img: Image = null
	if not art.is_empty():
		img = await RetroGameCase.decode_image(get_tree(), art)
	if fam.is_empty():
		var size := Vector2i(img.get_width(), img.get_height()) if img != null else Vector2i.ZERO
		var pick := GameCase.pick(sys, GameCase.market_of(sys, rom), GameCase.discs_of(rom).size(), size,
			GameCase.release_of(sys, rom))
		fam = str(pick["family"])
		variant = str(pick["variant"])
		c.case_color = str(pick["color"])
	c.case_family = fam
	c.case_variant = variant
	c.box_image = img
	c.freeze = true
	_world.add_child(c)
	c.add_to_group("spawned")
	var discs := GameCase.discs_of(rom)
	if fam == "jewel" and GameCase.capacity(variant) > discs.size():
		while discs.size() < GameCase.capacity(variant):
			discs.append(rom)
	elif fam == "keep" and GameCase.capacity(variant) > discs.size():
		while discs.size() < GameCase.capacity(variant):
			discs.append(rom)
	c.spawn_contents(discs)
	print("[probe] %s %s -> %s/%s art=%s discs=%d manual=%s" % [sys, rom.get_file(), fam, variant,
		"yes" if img != null else "no", c.discs().size(), not c.manual_path().is_empty()])
	return c


func _run() -> void:
	for g in GAMES:
		_cases.append(await _make(str(g[0]), _rom(str(g[0]), str(g[1]))))
	for e in EXTRA:
		var g: Array = GAMES[int(e[2])]
		var rom := _rom(str(g[0]), str(g[1]))
		_cases.append(await _make(str(g[0]), rom, str(e[0]), str(e[1]), rom))
	# A row lying face up, read from above the front.
	var x := 0.0
	for c in _cases:
		var w := c.model.size_m().x
		c.global_transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(x + w * 1.5, 0.0, 0.0))
		x += w * 2.0 + 0.03
	var mid := x * 0.5
	_cam.global_position = Vector3(mid, 0.55, 0.42)
	_cam.look_at(Vector3(mid, 0.0, -0.02))
	await _settle(20)
	await _shot("cases_shut")
	for c in _cases:
		var bk := c.manual()
		if bk != null:
			var local := c.global_transform.affine_inverse() * bk.global_transform
			print("[probe] manual %s: at %s basis_z %s page %s height %.3f case %s" % [c.case_variant,
				local.origin, local.basis.z, bk.page_size(), bk.book_height, c.model.size_m()])
	for c in _cases:
		c.sim.set_angle_deg(c.sim.top(), 180.0)
		c._apply_angles()
	await _settle(30)
	await _shot("cases_open")
	# Close up of each open case.
	for i in _cases.size():
		var c := _cases[i]
		var at := c.global_position + Vector3(0.0, 0.0, 0.0)
		var w := c.model.size_m().x
		_cam.global_position = at + Vector3(-w * 0.45, 0.32, 0.22)
		_cam.look_at(at + Vector3(-w * 0.45, 0.0, 0.0))
		await _settle(4)
		await _shot("open_%d_%s" % [i, c.case_variant])
	# Gravity: the first case stood on its spine edge with its lid at 30: it falls open.
	var j := _cases[0]
	for c in _cases:
		if c != j:
			c.visible = false
	j.sim.set_angle_deg(j.sim.top(), 30.0)
	j._apply_angles()
	j.global_transform = Transform3D(Basis(Vector3.FORWARD, -PI * 0.5), Vector3(0.0, 0.0, 0.0))
	_cam.global_position = Vector3(0.0, 0.05, 0.55)
	_cam.look_at(Vector3(0.0, 0.0, 0.0))
	for k in 6:
		await _settle(6)
		await _shot("swing_%d" % k)
		print("[probe] spine down t=%.2fs lid=%.1f latched=%s" % [k * 6.0 / 60.0, j.lid_deg(), j.is_latched()])


func _settle(frames: int) -> void:
	for _i in frames:
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw


func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	var img := _view.get_texture().get_image()
	img.save_png(_out.path_join(n + ".png"))
	print("[probe] wrote %s" % n)
