## Does a cartridge's real-time clock survive a power cycle? One core and one leg
## per process, the second leg in a NEW process, as a real power-off is.
##
## The cartridge is built here: MBC3 + TIMER + RAM + BATTERY, and a program that
## on its first boot stops the clock, sets it to day 100 and marks its RAM, and on
## any later boot latches the clock and copies the day it reads into RAM. The
## oracle is that copy — what the GAME saw — so it cannot pass by accident: a clock
## the bridge failed to restore starts at day 0.
##
##   leg=set    deletes the probe's battery and clock files, boots, stops.
##   leg=read   boots again and reads RAM[1]. PASS when it is day 100.
##
## Point --root at a throwaway root holding cores/<core>_libretro.dll: a core
## writes its options back on shutdown.
##
##   godot --headless --path RetroXR res://Tools/cores/rtc_probe.tscn -- \
##     --root=<throwaway root> --core=gambatte --leg=set
##   godot --headless --path RetroXR res://Tools/cores/rtc_probe.tscn -- \
##     --root=<throwaway root> --core=gambatte --leg=read
extends Node

const DAY := 100
const MARK := 0x5A
const READ_MARK := 0xA5

var _root := ""
var _core := "gambatte"
var _leg := "set"
var _lib: Node = null


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--root="):
			_root = arg.trim_prefix("--root=")
		elif arg.begins_with("--core="):
			_core = arg.trim_prefix("--core=")
		elif arg.begins_with("--leg="):
			_leg = arg.trim_prefix("--leg=")
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("[rtc] TIMEOUT leg=%s" % _leg)
		get_tree().quit(2))
	if _root.is_empty():
		print("[rtc] SKIP: pass --root=<throwaway root>")
		get_tree().quit(0)
		return

	var rom := _root.path_join("rtc_probe.gb")
	var srm := _root.path_join("probe").path_join("rtc_probe.srm")
	var rtc := SramPaths.rtc_path(srm, _core)
	DirAccess.make_dir_recursive_absolute(srm.get_base_dir())
	var f := FileAccess.open(rom, FileAccess.WRITE)
	f.store_buffer(build_rom())
	f.close()
	if _leg == "set":
		DirAccess.remove_absolute(srm)
		DirAccess.remove_absolute(rtc)

	_lib = ClassDB.instantiate("Libretro") as Node
	add_child(_lib)
	if not _lib.has_method("SetRtcPath"):
		print("[rtc] FAIL: this build of the extension has no SetRtcPath")
		get_tree().quit(1)
		return
	_lib.SetSramPath(srm)
	_lib.SetRtcPath(rtc)
	_lib.StartContent(_root, _core, rom)
	var target := 300
	while int(_lib.GetFrameCount()) < target:
		await get_tree().process_frame
	_lib.StopContent()
	for i in 30:
		await get_tree().process_frame

	var ram := FileAccess.get_file_as_bytes(srm)
	var clock := FileAccess.get_file_as_bytes(rtc)
	print("[rtc] leg=%s core=%s battery=%d bytes clock=%d bytes %s"
		% [_leg, _core, ram.size(), clock.size(), clock.hex_encode()])
	if _leg == "set":
		var ok := ram.size() > 0 and ram[0] == MARK and clock.size() > 0
		print("[rtc] %s set: battery marked and a clock file written" % ("PASS" if ok else "FAIL"))
		get_tree().quit(0 if ok else 1)
		return
	if ram.size() < 3 or ram[2] != READ_MARK:
		print("[rtc] FAIL read: the program never reached its read (RAM %s)"
			% ram.slice(0, 4).hex_encode())
		get_tree().quit(1)
		return
	var day := int(ram[1])
	print("[rtc] %s read: the game saw day %d (want %d)" % ["PASS" if day == DAY else "FAIL", day, DAY])
	get_tree().quit(0 if day == DAY else 1)


## 32 KiB, MBC3 with a clock and 8 KiB of battery RAM.
static func build_rom() -> PackedByteArray:
	var rom := PackedByteArray()
	rom.resize(0x8000)
	rom.fill(0)
	_put(rom, 0x100, [0x00, 0xC3, 0x50, 0x01])          # nop; jp $0150
	# The first four bytes of the header logo, which is all a loader matches.
	_put(rom, 0x104, [0xCE, 0xED, 0x66, 0x66])
	_put(rom, 0x134, "RTC PROBE".to_ascii_buffer())
	rom[0x147] = 0x10                                    # MBC3+TIMER+RAM+BATTERY
	rom[0x148] = 0x00                                    # 32 KiB
	rom[0x149] = 0x02                                    # 8 KiB
	rom[0x14B] = 0x33
	var sum := 0
	for i in range(0x134, 0x14D):
		sum = (sum - rom[i] - 1) & 0xFF
	rom[0x14D] = sum

	var head := [
		0xF3,                           # di
		0x31, 0xFE, 0xFF,               # ld sp,$FFFE
		0x3E, 0x0A, 0xEA, 0x00, 0x00,   # enable RAM and clock
		0x3E, 0x00, 0xEA, 0x00, 0x40,   # RAM bank 0
		0xFA, 0x00, 0xA0,               # ld a,($A000)
		0xFE, MARK,                     # cp MARK
	]
	# Latch, halt the clock, set its day, run it, mark RAM.
	var set_clock := [
		0x3E, 0x00, 0xEA, 0x00, 0x60, 0x3E, 0x01, 0xEA, 0x00, 0x60,
		0x3E, 0x0C, 0xEA, 0x00, 0x40, 0x3E, 0x40, 0xEA, 0x00, 0xA0,
		0x3E, 0x0B, 0xEA, 0x00, 0x40, 0x3E, DAY, 0xEA, 0x00, 0xA0,
		0x3E, 0x0C, 0xEA, 0x00, 0x40, 0x3E, 0x00, 0xEA, 0x00, 0xA0,
		0x3E, 0x00, 0xEA, 0x00, 0x40, 0x3E, MARK, 0xEA, 0x00, 0xA0,
		0x18, 0xFE,                     # jr $
	]
	# Latch, copy the day into RAM[1], mark RAM[2].
	var read_clock := [
		0x3E, 0x00, 0xEA, 0x00, 0x60, 0x3E, 0x01, 0xEA, 0x00, 0x60,
		0x3E, 0x0B, 0xEA, 0x00, 0x40, 0xFA, 0x00, 0xA0, 0x47,
		0x3E, 0x00, 0xEA, 0x00, 0x40, 0x78, 0xEA, 0x01, 0xA0,
		0x3E, READ_MARK, 0xEA, 0x02, 0xA0,
		0x18, 0xFE,                     # jr $
	]
	_put(rom, 0x150, head + [0x28, set_clock.size()] + set_clock + read_clock)
	return rom


static func _put(rom: PackedByteArray, at: int, bytes: Variant) -> void:
	var i := at
	for b: int in bytes:
		rom[i] = b
		i += 1
