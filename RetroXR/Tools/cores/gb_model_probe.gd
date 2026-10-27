## Which Game Boy gambatte is, measured on the real core with real cartridges.
##
##     "$godot" --headless --path RetroXR res://Tools/cores/gb_model_probe.tscn -- \
##         --system=gb|gbc --rom=<a .gb or .gbc> [--expect=mono|color] [--out=<dir>]
##
## ForcedCoreOptions.game_boy_model pins gambatte_gb_hwmode and
## gambatte_gb_colorization from the machine. gb_camera_tests checks the table;
## this checks what the core does with it: the machine boots the cartridge, the
## .opt it started from holds the pinned values, and the picture after ten
## seconds is four shades of gray (a Game Boy, whatever is in it) or in color (a
## Game Boy Color, with an original Game Boy game colored by its palette table).
##
## The pictures it saves are what the claim about a Color-only game rests on: in
## a Game Boy it is a DMG, and the game's own "Game Boy Color only" screen is on
## them. One core and one cartridge a process.
##
## The cartridge's battery is written under a save id of its own (gbmodelprobe),
## and the core's .opt with the pinned values -- the ones a player's next run
## would write anyway.
extends Node3D

const SYS_SCENE := "res://Scenes/Objects/system.tscn"
const CART_SCENE := "res://Scenes/Objects/media/cartridge.tscn"
const CORE := "gambatte"
const BOOT_FRAMES := 600

var _rom := ""
var _system := "gb"
var _expect := ""
var _out := "res://probe_out/gb_model"

var _pass := 0
var _fail := 0
var _sys: RetroSystem = null
var _lib: Libretro = null


func _ready() -> void:
	get_tree().create_timer(300.0).timeout.connect(func() -> void:
		print("[gb-model] TIMEOUT")
		get_tree().quit(1))
	await _run()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rom="):
			_rom = arg.substr(6)
		elif arg.begins_with("--system="):
			_system = arg.substr(9)
		elif arg.begins_with("--expect="):
			_expect = arg.substr(9)
		elif arg.begins_with("--out="):
			_out = arg.substr(6)
	if _rom.is_empty() or not FileAccess.file_exists(_rom):
		print("[gb-model] SKIP  pass --rom=<a Game Boy or Game Boy Color ROM>")
		get_tree().quit(0)
		return
	if CoreDownloadManager.installed_core_lib(CORE).is_empty():
		print("[gb-model] SKIP  no %s core under %s" % [CORE, CoreDownloadManager.default_core_root()])
		get_tree().quit(0)
		return
	var media := "gbc" if _rom.get_extension().to_lower() == "gbc" else "gb"
	print("[gb-model] a %s cartridge in a %s: %s" % [media, _system, _rom.get_file()])

	_sys = (load(SYS_SCENE) as PackedScene).instantiate() as RetroSystem
	_sys.systemid = _system
	_sys.core_name = CORE
	add_child(_sys)
	_sys.freeze = true
	_sys.gravity_scale = 0.0
	await _room_frames(6)
	_lib = _sys.get_libretro_node()

	var cart := (load(CART_SCENE) as PackedScene).instantiate() as RetroCartridge
	cart.systemid = media
	cart.rom_path = _rom
	cart.game_label = "Model probe"
	cart.save_id = "gbmodelprobe"
	add_child(cart)
	cart.global_position = _sys.global_position + Vector3(0, 0.3, 0)
	await _room_frames(4)
	_ok("the machine's slot takes the cartridge", _sys.accepts_media(cart))
	_sys.restore_cartridge(cart)
	await _room_frames(10)

	_sys.power_on()
	_ok("it switches on", _sys.is_powered_on)
	if not _sys.is_powered_on:
		return _finish()
	_ok("and the core runs", await _runs())
	var opt := CoreOptionsStore.load_values(CoreDownloadManager.default_core_root(), CORE)
	for key: String in ForcedCoreOptions.game_boy_model(CORE, _system):
		_eq("the run's .opt has %s pinned" % key, str(opt.get(key, "")),
			str(ForcedCoreOptions.game_boy_model(CORE, _system)[key]))
	await _emulated(BOOT_FRAMES)

	var screen: Image = _lib.GetVideoImage()
	if screen == null or screen.is_empty():
		_ok("the core has a picture", false)
		return _finish()
	screen = screen.duplicate() as Image
	screen.convert(Image.FORMAT_RGBA8)
	var stats := _colors(screen)
	print("[gb-model] picture %s: %d colors, %d of them not gray" % [str(screen.get_size()),
		stats["colors"], stats["chroma"]])
	_ok("the picture is not blank", int(stats["colors"]) > 1)
	if _expect == "mono":
		_eq("every shade on it is a gray", int(stats["chroma"]), 0)
	elif _expect == "color":
		_ok("it is in color", int(stats["chroma"]) > 0)

	var dir := _out
	if dir.begins_with("res://") or dir.begins_with("user://"):
		dir = ProjectSettings.globalize_path(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var stem := "%s/%s_%s" % [dir, _system, _rom.get_file().get_basename().left(24).validate_filename()]
	screen.resize(screen.get_width() * 3, screen.get_height() * 3, Image.INTERPOLATE_NEAREST)
	screen.save_png(stem + ".png")
	print("[gb-model] picture %s.png" % stem)
	_sys.power_off()
	await _room_frames(10)
	_finish()


## How many colors the picture holds, and how many of those are not a gray.
func _colors(image: Image) -> Dictionary:
	var seen := {}
	var chroma := 0
	for y in image.get_height():
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			var key := c.to_rgba32()
			if seen.has(key):
				continue
			seen[key] = true
			if max(absf(c.r - c.g), absf(c.g - c.b), absf(c.r - c.b)) > 0.04:
				chroma += 1
	return {"colors": seen.size(), "chroma": chroma}


func _runs() -> bool:
	var was: int = _lib.GetFrameCount()
	for i in range(600):
		await get_tree().process_frame
		if _lib.GetFrameCount() > was + 5:
			return true
	return false


func _emulated(n: int) -> void:
	var target: int = _lib.GetFrameCount() + n
	var guard := n * 40 + 400
	while _lib.GetFrameCount() < target and guard > 0:
		guard -= 1
		await get_tree().process_frame


func _room_frames(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame


func _ok(check: String, cond: bool, detail := "") -> void:
	if cond:
		_pass += 1
		print("[gb-model] PASS  %s" % check)
	else:
		_fail += 1
		print("[gb-model] FAIL  %s%s" % [check, "  — " + detail if not detail.is_empty() else ""])


func _eq(check: String, got: Variant, want: Variant) -> void:
	_ok(check, got == want, "got %s, want %s" % [str(got), str(want)])


func _finish() -> void:
	print("[gb-model] ---- %d passed, %d failed ----" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)
