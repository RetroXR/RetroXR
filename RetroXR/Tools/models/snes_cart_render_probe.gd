## Renders the Super NES cartridges as the spawn menu makes them: Type A and Type
## B wearing a scraped label, Killer Instinct's black shell, a mixed metal-flake
## shell, and the Super Famicom / PAL body with the label — from the front, the
## back, below, and each label up close.
##
##     "$godot" --path RetroXR --resolution 1600x900 --position 20,20 \
##         res://Tools/models/snes_cart_render_probe.tscn -- --out=<dir> [--label=<png>]
##
## Windowed: the headless renderer returns a blank image at the right size.
## `--label` is copied into the snes media/label folder as the Type A, Type B and
## Super Famicom carts' scraped art for the run, and removed again (with any folder made for it).
## The flat grey studio is for shape and label placement, not for judging colour.
extends Node

const CART_SCENE := preload("res://Scenes/Objects/media/cartridge.tscn")
const FIXTURE := "__snescart_render"

var out_dir := ""
var _created_dirs: Array[String] = []
var _labels: Array[String] = []


func _ready() -> void:
	out_dir = OS.get_user_data_dir().path_join(FIXTURE)
	var label_src := ""
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--out="):
			out_dir = str(arg).trim_prefix("--out=").replace("\\", "/")
		elif str(arg).begins_with("--label="):
			label_src = str(arg).trim_prefix("--label=").replace("\\", "/")
	DirAccess.make_dir_recursive_absolute(out_dir)
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("[snesrender] TIMEOUT")
		_cleanup()
		get_tree().quit(1))
	_run(label_src)


func _run(label_src: String) -> void:
	_build_studio()
	# [rom file, internal title, forced body, mixed colour, flake]
	var carts := [
		["a.sfc", "SUPER MARIOWORLD", SnesCartShell.TYPE_A, "", false],
		["b.sfc", "BUBSY II", SnesCartShell.TYPE_B, "", false],
		["ki.sfc", "KILLER INSTINCT", "", "", false],
		["flake.sfc", "SUPER MARIOWORLD", SnesCartShell.TYPE_B, "#2a6fd6", true],
		["sfc.sfc", "SUPER MARIO RPG", SnesCartShell.SFC, "", false],
	]
	if not label_src.is_empty():
		var img := Image.load_from_file(label_src)
		if img == null:
			push_error("[snesrender] cannot read %s" % label_src)
		else:
			_make_label_dir()
			for c: Array in carts.slice(0, 2) + carts.slice(4, 5):
				var path := _label_dir().path_join(FIXTURE + "_" + str(c[0]).get_basename() + ".png")
				img.save_png(path)
				_labels.append(path)
	var spawned: Array[RetroCartridge] = []
	for i in carts.size():
		var c: Array = carts[i]
		var cart := CART_SCENE.instantiate() as RetroCartridge
		cart.systemid = SnesCartShell.SYSTEMID
		cart.rom_path = _write_rom(FIXTURE + "_" + str(c[0]), _rom(str(c[1])))
		cart.body_region = c[2]
		cart.shell_color = c[3]
		cart.shell_flake = c[4]
		cart.game_label = str(c[1])
		cart.freeze = true
		add_child(cart)
		cart.global_position = Vector3((i - 1.5) * 0.15, 0.0, 0.0)
		spawned.append(cart)
		var model := cart.get_node_or_null("CartModel")
		print("[snesrender] %s: %s" % [c[1], model.scene_file_path.get_file() if model != null else "no model"])
	for i in 6:
		await get_tree().physics_frame

	# A SubViewport of the same world, as genesis_render_probe does: the root
	# viewport carries the boot overlay.
	var sv := SubViewport.new()
	sv.size = Vector2i(1600, 900)
	sv.own_world_3d = false
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sv)
	var cam := Camera3D.new()
	cam.fov = 30.0
	cam.near = 0.01
	sv.add_child(cam)
	for o in LoadingOverlay.owners():
		LoadingOverlay.end(o)
	# Long enough for every shader the first shot needs to have compiled.
	for i in 60:
		await get_tree().process_frame
	await _shot(sv, cam, Vector3(0, 0.03, 0.95), Vector3.ZERO, "front.png")
	await _shot(sv, cam, Vector3(0, 0.03, -0.95), Vector3.ZERO, "back.png")
	await _shot(sv, cam, Vector3(0.35, -0.55, 0.55), Vector3(0, -0.03, 0), "below.png")
	await _shot(sv, cam, Vector3(-0.28, 0.10, 0.30), Vector3(-0.225, 0.01, 0.0), "type_a_close.png")
	await _shot(sv, cam, Vector3(-0.13, 0.10, 0.30), Vector3(-0.075, 0.01, 0.0), "type_b_close.png")
	await _shot(sv, cam, Vector3(0.43, 0.10, 0.30), Vector3(0.375, 0.01, 0.0), "sfc_close.png")
	await _shot(sv, cam, Vector3(0.32, 0.10, -0.30), Vector3(0.375, 0.01, 0.0), "sfc_back_close.png")
	_cleanup()
	get_tree().quit(0)


func _shot(sv: SubViewport, cam: Camera3D, eye: Vector3, target: Vector3, file: String) -> void:
	cam.look_at_from_position(eye, target, Vector3.UP)
	cam.current = true
	for i in 8:
		await RenderingServer.frame_post_draw
	var img := sv.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png(out_dir.path_join(file))
	print("[snesrender] wrote %s" % out_dir.path_join(file))


func _build_studio() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.30, 0.31, 0.34)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.55, 0.58)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 30, 0)
	key.light_energy = 1.4
	key.shadow_enabled = true
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 200, 0)
	fill.light_energy = 0.6
	add_child(fill)


## A 64 KB HiROM image whose internal header names `title`, sold in North America,
## checksum and complement paired.
func _rom(title: String) -> PackedByteArray:
	var rom := PackedByteArray()
	rom.resize(0x10000)
	var h := 0xFFC0
	for i in SnesCartShell.TITLE_BYTES:
		rom[h + i] = title.unicode_at(i) if i < title.length() else 0x20
	rom[h + SnesCartShell.DESTINATION_AT] = 0x01
	rom.encode_u16(h + SnesCartShell.CHECKSUM_AT, 0x5A3C)
	rom.encode_u16(h + SnesCartShell.CHECKSUM_COMPLEMENT_AT, ~0x5A3C & 0xFFFF)
	return rom


func _write_rom(file_name: String, bytes: PackedByteArray) -> String:
	var dir := ProjectSettings.globalize_path("user://" + FIXTURE)
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join(file_name)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	return path


func _label_dir() -> String:
	return RomLibrary.rom_dir_for_system(SnesCartShell.SYSTEMID).path_join("media").path_join("label")


func _make_label_dir() -> void:
	var missing: Array[String] = []
	var d := _label_dir()
	while not DirAccess.dir_exists_absolute(d):
		missing.push_front(d)
		d = d.get_base_dir()
	DirAccess.make_dir_recursive_absolute(_label_dir())
	missing.reverse()
	_created_dirs.append_array(missing)


func _cleanup() -> void:
	for p in _labels:
		DirAccess.remove_absolute(p)
	_labels.clear()
	for d in _created_dirs:
		DirAccess.remove_absolute(d)
	_created_dirs.clear()
	var dir := ProjectSettings.globalize_path("user://" + FIXTURE)
	if DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".sfc"):
				DirAccess.remove_absolute(dir.path_join(f))
