## Drives the mupen64plus-next fork's Voice Recognition Unit with a real core: a
## NUS-020 seated in socket 4 before power-on, against any N64 game.
##
##     "$godot" --path RetroXR --resolution 320x240 --position 20,20 \
##         res://Tools/input/vru_probe.tscn -- --root=<libretro root> \
##         --rom=<n64 rom> --leg=seated
##
## The root holds cores/mupen64plus_next_libretro.dll, and for the speech half
## system/mupen64plus_next/vru/{libvosk,model-en-us}. Point it at a throwaway
## root: the probe writes its core_options there.
##
## ONE LEG PER PROCESS. --leg=control runs the same game with nothing in socket
## 4, and the two runs are told apart by the CORE's log, which the caller greps:
##
##     [BOOT] Game controller 3 (VRU controller) attached
##
## A probe: it wants the core and a ROM, and exits non-zero when a check fails.
## No game here asks for speech -- Hey You, Pikachu! is the only one that does --
## so this proves the device reaches the core and attaches, not a game hearing
## the player.
extends Node

var root_dir := ""
var rom_path := ""
var leg := "seated"
var speak_path := ""
var settle_seconds := 30.0
var attempts := 6
var _fail := 0
var _sys: RetroSystem = null


func _ok(name: String, cond: bool, detail := "") -> void:
	if cond:
		print("[vru] PASS  %s" % name)
	else:
		_fail += 1
		print("[vru] FAIL  %s%s" % [name, "  - " + detail if not detail.is_empty() else ""])


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var a := str(arg)
		if a.begins_with("--root="):
			root_dir = a.trim_prefix("--root=").replace("\\", "/")
		elif a.begins_with("--rom="):
			rom_path = a.trim_prefix("--rom=").replace("\\", "/")
		elif a.begins_with("--leg="):
			leg = a.trim_prefix("--leg=")
		elif a.begins_with("--speak="):
			speak_path = a.trim_prefix("--speak=").replace("\\", "/")
		elif a.begins_with("--settle="):
			settle_seconds = float(a.trim_prefix("--settle="))
		elif a.begins_with("--attempts="):
			attempts = int(a.trim_prefix("--attempts="))
	get_tree().create_timer(240.0).timeout.connect(func() -> void:
		print("[vru] TIMEOUT")
		get_tree().quit(1))

	var core_path := root_dir.path_join("cores/mupen64plus_next_libretro.dll")
	if root_dir.is_empty() or not FileAccess.file_exists(core_path):
		print("[vru] need --root=<libretro root holding cores/mupen64plus_next_libretro.dll>")
		get_tree().quit(1)
		return
	if rom_path.is_empty() or not FileAccess.file_exists(rom_path):
		print("[vru] need --rom=<an N64 rom>")
		get_tree().quit(1)
		return

	await _run()
	print("[vru] ---- %s ----" % ["FAIL" if _fail > 0 else "PASS"])
	get_tree().quit(1 if _fail > 0 else 0)


func _run() -> void:
	_sys = preload("res://Scenes/Objects/system.tscn").instantiate() as RetroSystem
	_sys.systemid = "nintendo_64"
	_sys.core_directory = root_dir
	add_child(_sys)
	await get_tree().process_frame

	var unit: N64Vru = null
	if leg == "seated":
		unit = preload("res://Scenes/Objects/controllers/n64/n64_vru.tscn").instantiate() as N64Vru
		add_child(unit)
		unit.global_position = _sys.global_position + Vector3(0.4, 0.0, 0.0)
		for i in range(3):
			await get_tree().process_frame
		_sys.restore_controller_plug(3, unit)
		await get_tree().process_frame
		_ok("the unit is in socket 4", unit.seated_port_index == 3,
			str(unit.seated_port_index))
		_ok("and it announces a VRU", unit.device_type == N64Vru.DEVICE_VRU,
			str(unit.device_type))
	else:
		print("[vru] control leg: socket 4 is empty")

	_sys.rom_path = rom_path
	_sys.toggle_power()
	# The core says what the game asked it to listen for, which is the only way
	# to see a word list arrive.
	# The prefix is the core's own CORE_NAME, "mupen64plus", not the library's
	# name -- a key the core never declared is dropped without a word.
	_sys.set_core_option("mupen64plus-vru-log", "enabled")

	var lib := _sys.get_libretro_node()
	var deadline := Time.get_ticks_msec() + 90000
	while (lib.GetCoreIdentity() as Dictionary).is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_ok("the core came up", not (lib.GetCoreIdentity() as Dictionary).is_empty())
	if (lib.GetCoreIdentity() as Dictionary).is_empty():
		return

	_ok("the game runs", await _advance(lib, 300))

	# The frontend's own view. A game that never asks for speech leaves the
	# microphone switched off, so this is not the oracle -- the core's log is.
	print("[vru] microphone active in the core: %s" % lib.IsMicrophoneActive())

	if unit != null:
		var mic := unit.get_mic()
		_ok("the microphone came with it", mic != null)
		_ok("the machine hears from the microphone",
			_sys.microphone_position().is_equal_approx(mic.global_position))

	if unit != null and not speak_path.is_empty():
		await _speak_to_the_game(lib, unit)

	_sys.toggle_power()
	for i in range(120):
		await get_tree().process_frame


## Say a word into the game, the way a player does: hold the microphone's Z on
## the VRU's own port, push the utterance through the frontend's microphone
## interface, then let go. The core's log is the oracle -- it prints what the
## recognizer heard when mupen64plus-next-vru-log is on.
func _speak_to_the_game(lib: Libretro, unit: N64Vru) -> void:
	var frames := _load_wav(speak_path)
	_ok("the utterance loaded", frames.size() > 0, "%d frames" % frames.size())
	if frames.is_empty():
		return

	# The room's own capture must not talk over it.
	AppPrefs.microphone_enabled = false

	print("[vru] letting the game settle for %.0f s before speaking" % settle_seconds)
	await _advance(lib, int(settle_seconds * 60.0))

	for attempt in range(attempts):
		print("[vru] attempt %d: holding Z on port %d and speaking"
			% [attempt + 1, unit.seated_port_index + 1])
		lib.SetJoypadExtraButtons(unit.seated_port_index, N64VruMic.TALK_BITS)
		var at := 0
		while at < frames.size():
			var take: int = mini(800, frames.size() - at)
			lib.PushMicrophoneFrames(frames.slice(at, at + take), 48000.0, 1.0)
			at += take
			await get_tree().process_frame
		# A moment of held silence, so the decoder sees the end of the word.
		for i in range(12):
			await get_tree().process_frame
		lib.SetJoypadExtraButtons(unit.seated_port_index, 0)
		await _advance(lib, 180)


## Mono or stereo 16-bit PCM, as PushMicrophoneFrames wants it.
func _load_wav(path: String) -> PackedVector2Array:
	var out := PackedVector2Array()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	if f.get_buffer(4).get_string_from_ascii() != "RIFF":
		return out
	f.get_32()
	if f.get_buffer(4).get_string_from_ascii() != "WAVE":
		return out
	var channels := 1
	while f.get_position() < f.get_length() - 8:
		var id := f.get_buffer(4).get_string_from_ascii()
		var size := f.get_32()
		if id == "fmt ":
			f.get_16()
			channels = f.get_16()
			f.get_32()
			f.get_32()
			f.get_16()
			f.get_16()
			if size > 16:
				f.seek(f.get_position() + size - 16)
		elif id == "data":
			var count := size / 2
			for i in range(count):
				var v := float(f.get_16())
				if v > 32767.0:
					v -= 65536.0
				v /= 32768.0
				if channels == 1:
					out.append(Vector2(v, v))
				elif i % 2 == 0:
					out.append(Vector2(v, v))
			break
		else:
			f.seek(f.get_position() + size + (size & 1))
	return out


## True once the core has run n more frames, false if it stalls.
func _advance(lib: Libretro, n: int) -> bool:
	var start := int(lib.GetFrameCount())
	var deadline := Time.get_ticks_msec() + n * 50 + 5000
	while int(lib.GetFrameCount()) - start < n and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return int(lib.GetFrameCount()) - start >= n
