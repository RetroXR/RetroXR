## N64 cartridge shell colours: both regional bodies side by side in several
## presets, the gold/silver two-tone, and a light that moves so the metal flake can
## be inspected.
##
##     "$godot" --path RetroXR res://Tools/models/n64_cart_color_demo.tscn
##
## Interactive: the light orbits and the camera drifts. Space pauses the light,
## 1-9 put a preset on every cartridge, R resets them, T restores the showcase.
##
##     "$godot" --path RetroXR --resolution 320x240 --position 20,20 \
##         res://Tools/models/n64_cart_color_demo.tscn -- --out=<dir> \
##         [--stills] [--rom=<file.z64> ...]
##
## Capture: writes stills and the frames of two clips into <dir>, then quits;
## --stills skips the clips.
## Every --rom is spawned as a real RetroCartridge, so its body, shell and scraped
## label come from the same lookup the room uses. Windowed, never --headless: the
## dummy renderer returns a blank image of the right size.
extends Node3D

const CART_SCENE := preload("res://Scenes/Objects/media/cartridge.tscn")
const SPACING := 0.135

## [region, what to do, caption]
const SHOWCASE := [
	["usa", "", "USA - imported grey"],
	["usa", "blue", "blue"],
	["usa", "color:#c8305a", "apply_color #c8305a"],
	["usa", "gold", "gold (flake)"],
	["usa", "gold_silver", "gold / silver"],
	["jpn", "grey", "JPN - grey preset"],
	["jpn", "black", "black"],
	["jpn", "green", "green"],
	["jpn", "silver", "silver (flake)"],
	["jpn", "two:black:yellow", "two-tone black / yellow"],
]

var out_dir := ""
var roms: PackedStringArray = []
var stills_only := false
var _carts: Array[Node3D] = []
var _captions: Array[Label3D] = []
var _light: OmniLight3D
var _camera: Camera3D
var _hero: Node3D
var _t := 0.0
var _light_paused := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=").replace("\\", "/")
		elif arg == "--stills":
			stills_only = true
		elif arg.begins_with("--rom="):
			roms.append(arg.trim_prefix("--rom=").replace("\\", "/"))
	_build_stage()
	_build_showcase()
	if out_dir.is_empty():
		_camera = Camera3D.new()
		_camera.fov = 40.0
		add_child(_camera)
		_camera.current = true
		return
	get_tree().create_timer(600.0).timeout.connect(func() -> void:
		print("[cartdemo] TIMEOUT")
		get_tree().quit(1))
	_capture()


func _process(delta: float) -> void:
	if not out_dir.is_empty():
		return
	if not _light_paused:
		_t += delta
	_place_light(_t)
	var yaw := sin(Time.get_ticks_msec() * 0.0002) * 0.35
	var eye := Vector3(sin(yaw) * 0.62, 0.16, cos(yaw) * 0.62)
	_camera.look_at_from_position(eye, Vector3(0, 0.07, 0), Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	var ids := CartridgeColor.get_palette().ids()
	if key.keycode == KEY_SPACE:
		_light_paused = not _light_paused
	elif key.keycode == KEY_R:
		for c in _carts:
			CartridgeColor.reset_to_default(c)
	elif key.keycode == KEY_T:
		_dress_showcase()
	elif key.keycode >= KEY_1 and key.keycode <= KEY_9 and key.keycode - KEY_1 < ids.size():
		for c in _carts:
			CartridgeColor.apply_preset(c, StringName(ids[key.keycode - KEY_1]))


func _build_stage() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.55, 0.6, 0.68)
	sky_mat.sky_horizon_color = Color(0.72, 0.72, 0.7)
	sky_mat.ground_bottom_color = Color(0.16, 0.15, 0.14)
	sky_mat.ground_horizon_color = Color(0.45, 0.44, 0.42)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.17, 0.18, 0.2)
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.45
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, 30, 0)
	key.light_energy = 0.55
	add_child(key)

	_light = OmniLight3D.new()
	_light.omni_range = 4.0
	_light.light_color = Color(1.0, 0.97, 0.92)
	add_child(_light)

	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(3, 3)
	floor_mesh.mesh = plane
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.22, 0.22, 0.24)
	floor_mat.roughness = 0.9
	floor_mesh.material_override = floor_mat
	floor_mesh.position = Vector3(0, -0.12, 0)
	add_child(floor_mesh)


func _build_showcase() -> void:
	for i in SHOWCASE.size():
		var row: Array = SHOWCASE[i]
		var path := N64CartShell.BODY_JPN if row[0] == "jpn" else N64CartShell.BODY_USA
		var cart := (load(path) as PackedScene).instantiate() as Node3D
		var col := i % 5
		var line := i / 5
		cart.position = Vector3((col - 2) * SPACING, 0.13 - line * 0.13, 0)
		add_child(cart)
		_carts.append(cart)
		var caption := Label3D.new()
		caption.text = row[2]
		caption.pixel_size = 0.00022
		caption.font_size = 40
		caption.outline_size = 8
		caption.position = cart.position + Vector3(0, -0.046, 0.012)
		add_child(caption)
		_captions.append(caption)
	_hero = _carts[4]
	_dress_showcase()


func _dress_showcase() -> void:
	for i in SHOWCASE.size():
		var cart := _carts[i]
		var action: String = SHOWCASE[i][1]
		CartridgeColor.reset_to_default(cart)
		if action.is_empty():
			continue
		if action.begins_with("color:"):
			CartridgeColor.apply_color(cart, Color(action.trim_prefix("color:")))
		elif action.begins_with("two:"):
			var parts := action.split(":")
			CartridgeColor.apply_two_tone(cart, StringName(parts[1]), StringName(parts[2]))
		else:
			CartridgeColor.apply_preset(cart, StringName(action))


func _place_light(t: float) -> void:
	_move_light(Vector3(cos(t * 0.9) * 0.5, 0.25 + sin(t * 0.6) * 0.12, 0.35 + sin(t * 0.9) * 0.2))


## Energy follows the square of the distance, so the cartridges see the same
## light from a lamp beside them as from one across the stage.
func _move_light(at: Vector3, gain: float = 0.9) -> void:
	_light.position = at
	_light.light_energy = gain * at.length_squared()


# ── capture ───────────────────────────────────────────────────────────────────


func _capture() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var sv := SubViewport.new()
	sv.size = Vector2i(1600, 900)
	sv.own_world_3d = false
	sv.msaa_3d = Viewport.MSAA_4X
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sv)
	var cam := Camera3D.new()
	cam.fov = 36.0
	sv.add_child(cam)
	for o in LoadingOverlay.owners():
		LoadingOverlay.end(o)
	for i in 40:
		await get_tree().process_frame

	# Central and far, so every column is lit alike and the colours compare.
	_move_light(Vector3(0.0, 0.45, 1.3), 0.3)
	await _shot(sv, cam, Vector3(0.0, 0.08, 0.95), Vector3(0, 0.065, 0), "showcase_front.png")
	for c in _carts:
		c.rotation_degrees.y = 180.0
	await _shot(sv, cam, Vector3(0.0, 0.08, 0.95), Vector3(0, 0.065, 0), "showcase_rear.png")
	for c in _carts:
		c.rotation_degrees = Vector3(-90, 0, 0)
	await _shot(sv, cam, Vector3(0.0, -0.1, 0.95), Vector3(0, 0.03, 0), "showcase_bottom_raw.png")
	for c in _carts:
		c.rotation_degrees = Vector3.ZERO

	# The two-tone cartridges alone, underside toward the camera, so the latch tabs
	# can be compared with the rear shell.
	await _latch_shot(sv, cam)
	await _macro_shots(sv, cam)

	if not stills_only:
		await _flake_clip(sv, cam)
		await _switch_clip(sv, cam)
	if not roms.is_empty():
		await _rom_shot(sv, cam)
	print("[cartdemo] done")
	get_tree().quit(0)


func _latch_shot(sv: SubViewport, cam: Camera3D) -> void:
	for i in _carts.size():
		_carts[i].visible = i == 4 or i == 9
		_captions[i].visible = false
	var a := _carts[4]
	var b := _carts[9]
	var keep_a := a.transform
	var keep_b := b.transform
	a.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-60), deg_to_rad(200), 0)), Vector3(-0.07, 0.05, 0))
	b.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-60), deg_to_rad(160), 0)), Vector3(0.07, 0.05, 0))
	_move_light(Vector3(0.0, -0.1, 0.4))
	await _shot(sv, cam, Vector3(0, -0.12, 0.34), Vector3(0, 0.03, 0), "latches.png")
	a.transform = keep_a
	b.transform = keep_b
	for i in _carts.size():
		_carts[i].visible = true
		_captions[i].visible = true


## The gold front and the silver back of the two-tone cartridge from 55 mm.
func _macro_shots(sv: SubViewport, cam: Camera3D) -> void:
	for i in _carts.size():
		_carts[i].visible = _carts[i] == _hero
		_captions[i].visible = false
	var home := _hero.transform
	_hero.transform = Transform3D.IDENTITY
	var wing := Vector3(0.036, 0.004, 0.0093)
	_move_light(wing + Vector3(-0.06, 0.07, 0.08))
	await _shot(sv, cam, wing + Vector3(0, 0, 0.055), wing, "flake_macro_gold.png")
	_hero.rotation.y = PI
	var back := Vector3(-0.012, 0.024, -0.0093).rotated(Vector3.UP, PI)
	_move_light(back + Vector3(0.06, 0.07, 0.08))
	await _shot(sv, cam, back + Vector3(0, 0, 0.055), back, "flake_macro_silver.png")
	_hero.transform = home
	for i in _carts.size():
		_carts[i].visible = true
		_captions[i].visible = true


## The gold/silver cartridge close up while the light sweeps, then turned and
## pulled back until the flakes are well under a pixel.
func _flake_clip(sv: SubViewport, cam: Camera3D) -> void:
	sv.size = Vector2i(1280, 720)
	var dir := out_dir.path_join("flake_frames")
	DirAccess.make_dir_recursive_absolute(dir)
	for i in _carts.size():
		_carts[i].visible = _carts[i] == _hero
		_captions[i].visible = false
	var home := _hero.transform
	_hero.transform = Transform3D.IDENTITY
	var wing := Vector3(0.036, 0.004, 0.0093)
	var frames := 360
	for f in frames:
		var u := float(f) / float(frames - 1)
		var t := u * 12.0
		# Macro on the gold front, lamp sweeping; then out to hand distance while
		# the cartridge turns to its silver back; then out across the room.
		var target := wing.lerp(Vector3(0, 0.004, 0), smoothstep(0.35, 0.6, u))
		var dist := lerpf(0.055, 0.22, smoothstep(0.35, 0.6, u))
		dist = lerpf(dist, 1.8, smoothstep(0.62, 1.0, u))
		_hero.rotation.y = smoothstep(0.38, 0.6, u) * PI
		var lamp := target + Vector3(cos(t * 1.3) * 0.12, 0.03 + sin(t * 0.9) * 0.06, 0.09 + sin(t * 1.3) * 0.03)
		if u > 0.6:
			lamp = Vector3(cos(t * 0.8) * 0.45, 0.25, 0.5)
		_move_light(lamp)
		await _frame(sv, cam, target + Vector3(0.0, 0.0, dist), target, dir.path_join("f_%04d.png" % f))
	_hero.transform = home
	for i in _carts.size():
		_carts[i].visible = true
		_captions[i].visible = true
	sv.size = Vector2i(1600, 900)


## Every cartridge cycled through plain, flake and reset presets several times
## over, to show the switch is repeatable and each cartridge keeps its own.
func _switch_clip(sv: SubViewport, cam: Camera3D) -> void:
	sv.size = Vector2i(1280, 720)
	var dir := out_dir.path_join("switch_frames")
	DirAccess.make_dir_recursive_absolute(dir)
	var cycle := [&"red", &"gold", &"blue", &"gold_silver", &"", &"silver", &"yellow", &""]
	var frame := 0
	for step in cycle.size() * 2:
		for i in _carts.size():
			var id: StringName = cycle[(step + i) % cycle.size()]
			if id == &"":
				CartridgeColor.reset_to_default(_carts[i])
				_captions[i].text = "reset"
			else:
				CartridgeColor.apply_preset(_carts[i], id)
				_captions[i].text = String(id)
		for f in 12:
			_place_light(frame * 0.05)
			await _frame(sv, cam, Vector3(0.0, 0.08, 0.95), Vector3(0, 0.065, 0),
				dir.path_join("f_%04d.png" % frame))
			frame += 1
	for i in _captions.size():
		_captions[i].text = SHOWCASE[i][2]
	_dress_showcase()
	sv.size = Vector2i(1600, 900)


## Real cartridges from real ROM files: region body, looked-up shell and the
## scraped label, exactly as the room builds them.
func _rom_shot(sv: SubViewport, cam: Camera3D) -> void:
	for n in _carts:
		n.visible = false
	for c in _captions:
		c.visible = false
	var per_row := 4
	var spawned: Array[Node3D] = []
	for i in roms.size():
		var path := roms[i]
		var cart := CART_SCENE.instantiate() as RetroCartridge
		cart.systemid = "nintendo_64"
		cart.rom_path = path
		cart.game_label = path.get_file().get_basename()
		cart.freeze = true
		var col := i % per_row
		var line := i / per_row
		cart.position = Vector3((col - (per_row - 1) * 0.5) * 0.15, 0.13 - line * 0.155, 0)
		add_child(cart)
		spawned.append(cart)
		var market := N64CartShell.market("nintendo_64", path)
		var preset := N64CartShell.preset_for_rom(path, market)
		var caption := Label3D.new()
		caption.text = "%s\n%s body, %s" % [path.get_file().get_basename().left(34),
			"JPN" if market == "jp" else "USA", preset]
		caption.pixel_size = 0.0002
		caption.font_size = 36
		caption.outline_size = 8
		caption.position = cart.position + Vector3(0, -0.053, 0.012)
		add_child(caption)
		spawned.append(caption)
		print("[cartdemo] %s -> market '%s', preset %s" % [path.get_file(), market, preset])
	for i in 10:
		await get_tree().physics_frame
	_move_light(Vector3(0.0, 0.45, 1.3), 0.3)
	var rows := ceili(float(roms.size()) / per_row)
	await _shot(sv, cam, Vector3(0.0, 0.13 - (rows - 1) * 0.078, 0.62 + rows * 0.14),
		Vector3(0, 0.13 - (rows - 1) * 0.078, 0), "real_roms_front.png")
	for n in spawned:
		if n is RetroCartridge:
			n.rotation_degrees.y = 180.0
	await _shot(sv, cam, Vector3(0.0, 0.13 - (rows - 1) * 0.078, 0.62 + rows * 0.14),
		Vector3(0, 0.13 - (rows - 1) * 0.078, 0), "real_roms_rear.png")


func _shot(sv: SubViewport, cam: Camera3D, eye: Vector3, target: Vector3, file: String) -> void:
	cam.look_at_from_position(eye, target, Vector3.UP)
	cam.current = true
	for i in 8:
		await get_tree().process_frame
	await _save(sv, out_dir.path_join(file))


func _frame(sv: SubViewport, cam: Camera3D, eye: Vector3, target: Vector3, path: String) -> void:
	cam.look_at_from_position(eye, target, Vector3.UP)
	cam.current = true
	await get_tree().process_frame
	await _save(sv, path)


func _save(sv: SubViewport, path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := sv.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png(path)
