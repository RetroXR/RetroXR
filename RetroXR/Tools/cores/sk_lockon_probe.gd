## Sonic & Knuckles lock-on probe: does a Genesis built with the S&K cartridge and
## a game in its roof really play the locked-on game?
##
## Driven through the ROOM, not straight at the core: a RetroSystem, the
## sonic_knuckles unit in its slot and a cartridge in the unit's, then power_on.
## So the stack's content choice (ExpansionLaunch), the pinned
## genesis_plus_gx_lock_on (ForcedCoreOptions) and the .opt it writes are all
## exercised, and the core is genesis_plus_gx with sk.bin + sk2chip.bin from its
## own system folder (install them through BIOS / Extras, or copy them in).
##
## ONE LEG PER PROCESS (one core start per process, the bios_boot_survey rule):
##   --leg=lock   the unit in the Genesis, --rom in the unit's slot
##   --leg=bare   --rom straight in the Genesis: the CONTROL. Same game, no
##                lock-on; its pictures must differ from `lock`'s.
##   --leg=alone  the unit with its slot empty: plain Sonic & Knuckles.
##
## THE ORACLE IS THE PICTURE, compared across legs: a lock leg whose frames match
## the bare leg's at every sample did not lock on, whatever the log says (the core
## falls back to the top game alone, silently, when either file is missing).
## Each sample prints an md5 of the frame and saves a PNG to look at.
##
##   godot --path RetroXR --resolution 320x240 --position 20,20 \
##       res://Tools/cores/sk_lockon_probe.tscn -- --leg=lock \
##       --rom="C:/.../Sonic The Hedgehog 3 (USA).md" [--out=<dir>] [--at=600,1200,1800]
##
## A pressed START is sent once between samples (--start=<frame>, default 900)
## so a title screen gives way to the game's own lock-on screen; --press=abc sends
## A+B+C instead (Sonic 1's "NO WAY?" screen -> Blue Sphere).
##
## Measured 2026-11-01 (genesis_plus_gx v4, the No-Intro dumps): Sonic 3 -> the
## Sonic 3 & Knuckles title; Sonic 2 -> Knuckles in Sonic 2; Sonic 1 -> "NO WAY?"
## then Blue Sphere on A+B+C; The Lion King (3 MB) -> plain Sonic & Knuckles,
## frame for frame the alone leg's, which is the real cartridge's behaviour for a
## game over 2 MB (its mapper shows the game's LAST 2 MB, where there is no header).
extends Node3D

const SYS_SCENE := "res://Scenes/Objects/system.tscn"
const CART_SCENE := "res://Scenes/Objects/media/cartridge.tscn"
const UNIT_SCENE := "res://Scenes/Objects/expansion.tscn"
const CORE := "genesis_plus_gx"

var _leg := "lock"
var _rom := ""
var _out := "res://probe_out/sk_lockon"
var _at: Array[int] = [600, 1200, 1800]
var _start_at := 900
## What is pressed at _start_at: "start", or "abc" (A+B+C together, which turns
## Sonic 1's "NO WAY?" screen into Blue Sphere).
var _press := "start"

var _pass := 0
var _fail := 0
var _sys: RetroSystem = null
var _lib: Libretro = null


func _ready() -> void:
	get_tree().create_timer(300.0).timeout.connect(func() -> void:
		print("[sk-lockon] TIMEOUT")
		get_tree().quit(1))
	await _run()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--leg="):
			_leg = arg.substr(6)
		elif arg.begins_with("--rom="):
			_rom = arg.substr(6)
		elif arg.begins_with("--out="):
			_out = arg.substr(6)
		elif arg.begins_with("--press="):
			_press = arg.substr(8)
		elif arg.begins_with("--start="):
			_start_at = arg.substr(8).to_int()
		elif arg.begins_with("--at="):
			_at.clear()
			for piece: String in arg.substr(5).split(",", false):
				_at.append(piece.to_int())
			_at.sort()
	if _leg != "alone" and (_rom.is_empty() or not FileAccess.file_exists(_rom)):
		print("[sk-lockon] SKIP  pass --rom=<a Genesis ROM> (legs lock and bare)")
		get_tree().quit(0)
		return
	if CoreDownloadManager.installed_core_lib(CORE).is_empty():
		print("[sk-lockon] SKIP  no %s core under %s" % [CORE, CoreDownloadManager.default_core_root()])
		get_tree().quit(0)
		return
	if _leg != "bare" and not ExpansionCatalog.firmware_present("sonic_knuckles"):
		print("[sk-lockon] SKIP  missing %s" % ExpansionCatalog.missing_row("sonic_knuckles").get("path", ""))
		get_tree().quit(0)
		return
	print("[sk-lockon] leg=%s rom=%s" % [_leg, _rom.get_file()])

	_sys = (load(SYS_SCENE) as PackedScene).instantiate() as RetroSystem
	_sys.systemid = "genesis"
	_sys.core_name = CORE
	add_child(_sys)
	_sys.freeze = true
	_sys.gravity_scale = 0.0
	await _room_frames(6)
	_lib = _sys.get_libretro_node()

	var cart: RetroCartridge = null
	if _leg != "alone":
		cart = (load(CART_SCENE) as PackedScene).instantiate() as RetroCartridge
		cart.systemid = "genesis"
		cart.rom_path = _rom
		cart.game_label = "Lock-on probe"
		cart.save_id = "sklockonprobe"
		add_child(cart)
		cart.global_position = _sys.global_position + Vector3(0, 0.4, 0)
		cart.freeze = true
		await _room_frames(4)

	if _leg == "bare":
		_sys.restore_cartridge(cart)
	else:
		var unit := (load(UNIT_SCENE) as PackedScene).instantiate() as RetroExpansion
		unit.expansion_id = "sonic_knuckles"
		add_child(unit)
		unit.global_position = _sys.global_position + Vector3(0, 0.25, 0)
		unit.freeze = true
		await _room_frames(4)
		_sys.restore_cartridge(unit)
		if cart != null:
			await _room_frames(4)
			unit.restore_media_in_slot(cart)
	await _room_frames(10)

	_sys.power_on()
	_ok("it switches on", _sys.is_powered_on)
	if not _sys.is_powered_on:
		return _finish()
	_ok("and the core runs", await _runs())
	var opt := CoreOptionsStore.load_values(CoreDownloadManager.default_core_root(), CORE)
	var want := "sonic & knuckles" if _leg == "lock" else "disabled"
	_eq("the run's .opt pins genesis_plus_gx_lock_on", str(opt.get("genesis_plus_gx_lock_on", "")), want)
	_eq("the content is the right ROM", _sys.rom_path.get_file(),
		"sk.bin" if _leg == "alone" else _rom.get_file())

	var dir := _out
	if dir.begins_with("res://") or dir.begins_with("user://"):
		dir = ProjectSettings.globalize_path(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var base: int = _lib.GetFrameCount()
	var pressed := false
	for at: int in _at:
		if not pressed and _start_at > 0 and at > _start_at:
			await _emulated(base + _start_at - _lib.GetFrameCount())
			await _press_start()
			pressed = true
		await _emulated(base + at - _lib.GetFrameCount())
		_shot(dir, at)
	_sys.power_off()
	await _room_frames(10)
	_finish()


func _press_start() -> void:
	# The player-1 pad's START, held for a few frames, through the machine's own
	# input path as a controller would.
	# genesis_plus_gx's 3-button pad: B is RetroPad B (0), A is Y (1), C is A (8).
	var mask := (1 << 0) | (1 << 1) | (1 << 8) if _press == "abc" else 1 << 3
	for i in 8:
		_lib.SetJoypadState(0, mask, 0.0, 0.0, 0.0, 0.0)
		await get_tree().process_frame
	_lib.SetJoypadState(0, 0, 0.0, 0.0, 0.0, 0.0)
	print("[sk-lockon] pressed %s at frame %d" % [_press.to_upper(), _lib.GetFrameCount()])


func _shot(dir: String, at: int) -> void:
	var screen: Image = _lib.GetVideoImage()
	if screen == null or screen.is_empty():
		_ok("a picture at frame %d" % at, false)
		return
	screen = screen.duplicate() as Image
	screen.convert(Image.FORMAT_RGB8)
	var hash := screen.get_data().hex_encode().md5_text()
	var stem := "%s/%s_%s_%05d" % [dir, _leg,
		(_rom.get_file().get_basename().left(20) if not _rom.is_empty() else "sk").validate_filename(), at]
	screen.resize(screen.get_width() * 2, screen.get_height() * 2, Image.INTERPOLATE_NEAREST)
	screen.save_png(stem + ".png")
	print("[sk-lockon] frame %d %s md5=%s %s.png" % [at, str(screen.get_size() / 2), hash, stem])


func _runs() -> bool:
	var was: int = _lib.GetFrameCount()
	for i in range(600):
		await get_tree().process_frame
		if _lib.GetFrameCount() > was + 5:
			return true
	return false


func _emulated(n: int) -> void:
	if n <= 0:
		return
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
		print("[sk-lockon] PASS  %s" % check)
	else:
		_fail += 1
		print("[sk-lockon] FAIL  %s%s" % [check, "  — " + detail if not detail.is_empty() else ""])


func _eq(check: String, got: Variant, want: Variant) -> void:
	_ok(check, got == want, "got %s, want %s" % [str(got), str(want)])


func _finish() -> void:
	print("[sk-lockon] RESULT %d passed, %d failed: %s" % [_pass, _fail, "PASS" if _fail == 0 else "FAIL"])
	get_tree().quit(0 if _fail == 0 else 1)
