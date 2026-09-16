## Drives the fceumm fork's Famicom Controller II microphone with a real core and
## a real game.
##
##     "$godot" --headless --path RetroXR res://Tools/cores/famicom_mic_probe.tscn -- \
##         --root=<libretro root holding cores/fceumm_libretro.dll> \
##         --rom="Z:/roms/nes/Bokosuka Wars (Japan).nes" --leg=mic
##
## Point --root at a throwaway root: the probe writes its core_options there.
##
## ONE LEG PER PROCESS:
##
##   --leg=mic   a Famicom, the microphone bit held on player 2's port
##   --leg=nes   the same ROM on an NES, which must not be offered the option
##
## The oracle that can go red is the CORE's own line, which only the fork prints
## and only when the option is on, so the caller greps the run for it:
##
##     Famicom Controller II microphone on
##
## A warning rather than an info line on purpose: libretro-godot passes nothing
## below a warning, and fceumm's FCEUD_Message logs at info.
##
## Wipe <root>/core_options between legs. A core serialises its whole option set
## on shutdown, so the famicom leg leaves the key behind and the NES leg would
## otherwise be reading the previous run's file rather than its own.
##
## What this deliberately does NOT do is compare the console's RAM between a run
## with the bit held and one without. SnapshotMappedRam() is read on the main
## thread while emulation runs on its own, so the frame it catches varies: the
## same leg run three times gave two different digests, and the mic and quiet
## legs gave the SAME one. The measurement is a race, not a difference -- and
## 1800 frames of Bokosuka Wars is its title screen, which samples nothing. A
## real "the game answered" oracle needs the emulation gated to an exact frame
## and a ROM driven to the moment it listens; neither is here yet.
extends Node

var root_dir := ""
var rom_path := ""
var leg := "mic"
var core := "fceumm"
var frames := 1800
var _fail := 0
var _sys: RetroSystem = null


func _ok(name: String, cond: bool, detail := "") -> void:
	if cond:
		print("[fcmic] PASS  %s" % name)
	else:
		_fail += 1
		print("[fcmic] FAIL  %s%s" % [name, "  - " + detail if not detail.is_empty() else ""])


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var a := str(arg)
		if a.begins_with("--root="):
			root_dir = a.trim_prefix("--root=").replace("\\", "/")
		elif a.begins_with("--rom="):
			rom_path = a.trim_prefix("--rom=").replace("\\", "/")
		elif a.begins_with("--leg="):
			leg = a.trim_prefix("--leg=")
		elif a.begins_with("--frames="):
			frames = int(a.trim_prefix("--frames="))
		elif a.begins_with("--core="):
			core = a.trim_prefix("--core=")
	get_tree().create_timer(300.0).timeout.connect(func() -> void:
		print("[fcmic] TIMEOUT")
		get_tree().quit(1))

	if root_dir.is_empty() or not FileAccess.file_exists(root_dir.path_join("cores/fceumm_libretro.dll")):
		print("[fcmic] need --root=<libretro root holding cores/fceumm_libretro.dll>")
		get_tree().quit(1)
		return
	if rom_path.is_empty() or not FileAccess.file_exists(rom_path):
		print("[fcmic] need --rom=<a Famicom cartridge>")
		get_tree().quit(1)
		return

	await _run()
	print("[fcmic] ---- %s ----" % ["FAIL" if _fail > 0 else "PASS"])
	get_tree().quit(1 if _fail > 0 else 0)


func _run() -> void:
	_sys = preload("res://Scenes/Objects/system.tscn").instantiate() as RetroSystem
	_sys.systemid = "nes" if leg == "nes" else "famicom"
	_sys.core_directory = root_dir
	# Named rather than resolved. A player's Famicom picks this up on its own --
	# fceumm declares famicom in secondary_systemids, so the Cores panel adopts a
	# default for it the first time it lists installed cores -- but a probe must
	# not depend on whose machine it is running on.
	_sys.core_name = core
	add_child(_sys)
	await get_tree().process_frame

	_sys.rom_path = rom_path
	_sys.toggle_power()

	var lib := _sys.get_libretro_node()
	var deadline := Time.get_ticks_msec() + 120000
	while (lib.GetCoreIdentity() as Dictionary).is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_ok("the core came up", not (lib.GetCoreIdentity() as Dictionary).is_empty())
	if (lib.GetCoreIdentity() as Dictionary).is_empty():
		return
	print("[fcmic] core: %s" % str(lib.GetCoreIdentity()))

	# The option file is written before the core starts, so it says what the
	# machine asked for whether or not this build understands the key.
	var opts := _read_opt(root_dir, core)
	var got := str(opts.get("fceumm_famicom_microphone", "(unset)"))
	# Not "unset" for the NES leg: the core serialises its whole option set on
	# shutdown, so a build that knows the key writes its own default into the
	# file. What an NES must never see is "enabled".
	if leg == "nes":
		_ok("an NES is not offered the microphone", got != "enabled", got)
	else:
		_ok("the core was asked for the microphone", got == "enabled", got)

	# Held from the cold start. This is the same call the pad makes, on the same
	# port, so it proves the route survives a real core -- not that the game
	# understood it, which is the check noted as missing above.
	if leg == "mic":
		lib.SetJoypadExtraButtons(FamicomControllerII.MIC_PORT, FamicomControllerII.MIC_BITS)

	var target := int(lib.GetFrameCount()) + frames
	while int(lib.GetFrameCount()) < target:
		await get_tree().process_frame
	_ok("the game ran", int(lib.GetFrameCount()) >= frames, str(lib.GetFrameCount()))

	_ok("it is still running with the bit held" if leg == "mic"
			else "it is still running", _sys.is_powered_on)
	print("[fcmic] grep this run for: Famicom Controller II microphone on")

	_sys.toggle_power()
	for i in range(120):
		await get_tree().process_frame



func _read_opt(root: String, core_name: String) -> Dictionary:
	var out: Dictionary = {}
	var path := root.path_join("core_options").path_join(core_name + ".opt")
	if not FileAccess.file_exists(path):
		print("[fcmic] no options file at %s" % path)
		return out
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var eq := line.find("=")
		if eq < 0:
			continue
		out[line.substr(0, eq).strip_edges()] = \
			line.substr(eq + 1).strip_edges().trim_prefix("\"").trim_suffix("\"")
	return out
