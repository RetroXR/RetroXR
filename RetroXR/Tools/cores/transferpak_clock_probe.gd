## Does the clock of a Game Boy cartridge in a Transfer Pak survive a power cycle?
## One core and one leg per process.
##
## The cartridge is rtc_probe's: MBC3 + TIMER + RAM + BATTERY. It is seated in
## port 0's pak the way RetroSystem seats one -- SetTransferPakClock, then
## SetTransferPak -- on a plain load, so the interfaces are the only route.
##
## THE ORACLE IS THE SAVESTATE. savestates.c writes, per port with a cartridge, the
## 28 fingerprint bytes at 0x134 of the ROM, five uint32s, the clock's int64
## last_time and then its five counters: the clock the core actually holds.
##
##   leg=fresh  no clock file. The clock must start NOW, not at 1970, and the core
##              must have written a 48-byte file holding that time.
##   leg=kept   a clock file at day 100, five hours old. The core must hold day 100
##              and that time.
##
##   godot --headless --path RetroXR res://Tools/cores/transferpak_clock_probe.tscn -- \
##     --root=<throwaway root with cores/mupen64plus_next_libretro.dll> \
##     "--n64=<Pokemon Stadium (USA).z64>" --leg=fresh
extends Node

const CORE := "mupen64plus_next"
const DAY := 100
const FINGERPRINT_OFFSET := 0x134
const FINGERPRINT_SIZE := 28

var _root := ""
var _n64 := ""
var _leg := "fresh"
var _lib: Libretro
var _rom := PackedByteArray()
var _ram := ""
var _rtc := ""
var _kept_time := 0
var _asked := false


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--root="):
			_root = arg.trim_prefix("--root=")
		elif arg.begins_with("--n64="):
			_n64 = arg.trim_prefix("--n64=")
		elif arg.begins_with("--leg="):
			_leg = arg.trim_prefix("--leg=")
	get_tree().create_timer(180.0).timeout.connect(func() -> void:
		print("[tpclock] FAIL timeout")
		get_tree().quit(2))
	if _root.is_empty() or _n64.is_empty():
		print("[tpclock] SKIP: pass --root= and --n64=")
		get_tree().quit(0)
		return

	var gb := _root.path_join("probe").path_join("pak_clock.gb")
	_ram = _root.path_join("probe").path_join("pak_clock.srm")
	_rtc = SramPaths.rtc_path(_ram, CORE)
	DirAccess.make_dir_recursive_absolute(gb.get_base_dir())
	_rom = load("res://Tools/cores/rtc_probe.gd").build_rom()
	var f := FileAccess.open(gb, FileAccess.WRITE)
	f.store_buffer(_rom)
	f.close()
	DirAccess.remove_absolute(_rtc)
	if _leg == "kept":
		_kept_time = int(Time.get_unix_time_from_system()) - 5 * 3600
		var clock := PackedByteArray()
		clock.resize(48)
		clock.encode_u32(8, 2)          # hours
		clock.encode_u32(12, DAY)       # days low
		clock.encode_s64(40, _kept_time)
		var c := FileAccess.open(_rtc, FileAccess.WRITE)
		c.store_buffer(clock)
		c.close()

	_lib = Libretro.new()
	add_child(_lib)
	if not _lib.has_method("SetTransferPakClock"):
		print("[tpclock] FAIL this build of the extension has no SetTransferPakClock")
		get_tree().quit(1)
		return
	_lib.options_ready.connect(_on_options_ready)
	_lib.savestate_ready.connect(_on_savestate_ready)
	_lib.content_load_failed.connect(func(reason: String) -> void:
		print("[tpclock] FAIL content_load_failed %s" % reason)
		get_tree().quit(1))
	_lib.SetTransferPakClock(0, _rtc)
	_lib.SetTransferPak(0, gb, _ram)
	_lib.StartContent(_root, CORE, _n64)


func _on_options_ready(_categories: Dictionary, definitions: Dictionary, _current: Dictionary) -> void:
	for key: String in definitions:
		if key.ends_with("-pak1"):
			_lib.SetCoreOption(key, "transfer")
			return
	print("[tpclock] FAIL the core published no -pak1 option")
	get_tree().quit(1)


func _process(_delta: float) -> void:
	if _lib != null and not _asked and _lib.GetFrameCount() >= 300:
		_asked = true
		_lib.RequestSaveState()


func _on_savestate_ready(data: PackedByteArray, frame: int) -> void:
	var fingerprint := _rom.slice(FINGERPRINT_OFFSET, FINGERPRINT_OFFSET + FINGERPRINT_SIZE)
	var at := _find(data, fingerprint)
	if at < 0:
		print("[tpclock] FAIL the cartridge is not in the savestate (frame %d)" % frame)
		_finish(1)
		return
	var last_time := data.decode_s64(at + FINGERPRINT_SIZE + 20)
	var regs := data.slice(at + FINGERPRINT_SIZE + 28, at + FINGERPRINT_SIZE + 33)
	var now := int(Time.get_unix_time_from_system())
	print("[tpclock] leg=%s frame=%d last_time=%d (now %d) regs=%s"
		% [_leg, frame, last_time, now, regs.hex_encode()])

	var ok := false
	if _leg == "fresh":
		ok = absi(last_time - now) < 600 and regs[3] == 0 and regs[4] & 0x80 == 0
		print("[tpclock] %s fresh: the clock started now, not at 1970" % ("PASS" if ok else "FAIL"))
	else:
		ok = regs[3] == DAY and last_time >= _kept_time and last_time <= now
		print("[tpclock] %s kept: the core holds day %d from the kept clock" % ["PASS" if ok else "FAIL", regs[3]])
	_lib.StopContent()
	await get_tree().create_timer(2.0).timeout

	var clock := FileAccess.get_file_as_bytes(_rtc)
	var file_ok := clock.size() == 48
	if _leg == "fresh":
		file_ok = file_ok and clock.decode_s64(40) == last_time
	print("[tpclock] %s the clock file is 48 bytes%s (%d bytes %s)"
		% ["PASS" if file_ok else "FAIL", " holding that time" if _leg == "fresh" else "",
			clock.size(), clock.hex_encode()])
	get_tree().quit(0 if ok and file_ok else 1)


func _find(haystack: PackedByteArray, needle: PackedByteArray) -> int:
	var at := 0
	while true:
		var i := haystack.find(needle[0], at)
		if i < 0 or i + needle.size() > haystack.size():
			return -1
		if haystack.slice(i, i + needle.size()) == needle:
			return i
		at = i + 1
	return -1


func _finish(code: int) -> void:
	_lib.StopContent()
	get_tree().create_timer(1.0).timeout.connect(func() -> void: get_tree().quit(code))
