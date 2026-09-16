## Drives the flycast fork's Dreamcast Microphone with a real core and a real
## game: a pad in port A with a VMU in slot 1 and an HKT-7200 in slot 2, which
## is the arrangement Seaman refuses to start without.
##
##     "$godot" --path RetroXR --resolution 320x240 --position 20,20 \
##         res://Tools/cores/dc_mic_probe.tscn -- --root=<libretro root> \
##         --rom=<a dreamcast disc> --leg=seated
##
## The root holds cores/flycast_libretro.dll and system/flycast/dc/dc_boot.bin.
## Point it at a throwaway root: the probe writes its core_options there.
##
## ONE LEG PER PROCESS. --leg=control runs the same disc with slot 2 empty, and
## the two are told apart by the CORE's log, which the caller greps:
##
##     microphone: open, 48000 Hz from the frontend -> 11025 Hz for the game
##
## A probe: it wants the core, the BIOS and a disc, and exits non-zero when a
## check fails. Slot devices are bound when the machine powers on, so everything
## here is seated before the switch.
extends Node

var root_dir := ""
var rom_path := ""
var leg := "seated"
var seconds := 60.0
var _fail := 0
var _sys: RetroSystem = null


func _ok(name: String, cond: bool, detail := "") -> void:
	if cond:
		print("[dcmic] PASS  %s" % name)
	else:
		_fail += 1
		print("[dcmic] FAIL  %s%s" % [name, "  - " + detail if not detail.is_empty() else ""])


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var a := str(arg)
		if a.begins_with("--root="):
			root_dir = a.trim_prefix("--root=").replace("\\", "/")
		elif a.begins_with("--rom="):
			rom_path = a.trim_prefix("--rom=").replace("\\", "/")
		elif a.begins_with("--leg="):
			leg = a.trim_prefix("--leg=")
		elif a.begins_with("--seconds="):
			seconds = float(a.trim_prefix("--seconds="))
	get_tree().create_timer(seconds + 180.0).timeout.connect(func() -> void:
		print("[dcmic] TIMEOUT")
		get_tree().quit(1))

	if root_dir.is_empty() or not FileAccess.file_exists(root_dir.path_join("cores/flycast_libretro.dll")):
		print("[dcmic] need --root=<libretro root holding cores/flycast_libretro.dll>")
		get_tree().quit(1)
		return
	if rom_path.is_empty() or not FileAccess.file_exists(rom_path):
		print("[dcmic] need --rom=<a dreamcast disc>")
		get_tree().quit(1)
		return

	await _run()
	print("[dcmic] ---- %s ----" % ["FAIL" if _fail > 0 else "PASS"])
	get_tree().quit(1 if _fail > 0 else 0)


func _run() -> void:
	_sys = preload("res://Scenes/Objects/system.tscn").instantiate() as RetroSystem
	_sys.systemid = "dreamcast"
	_sys.core_directory = root_dir
	add_child(_sys)
	await get_tree().process_frame

	var pad: Node3D = preload("res://Scenes/Objects/controllers/retro_controller.tscn").instantiate()
	add_child(pad)
	pad.global_position = _sys.global_position + Vector3(0.5, 0.0, 0.0)
	for i in range(4):
		await get_tree().process_frame

	var plug: Node3D = pad.get("_cable_plug")
	_ok("the pad has a plug", plug != null)
	if plug == null:
		return
	_sys.restore_controller_plug(0, plug)
	await get_tree().process_frame
	_ok("the pad is in port A", _sys.get_port_controllers()[0] == pad)

	# Seaman will not start without a card in slot 1, and wants the microphone
	# in slot 2.
	var card: Node3D = preload("res://Scenes/Objects/controllers/dreamcast/vmu_card.tscn").instantiate()
	add_child(card)
	await get_tree().process_frame
	pad.restore_vmu(card, 0)

	var mic: DcMicrophone = null
	if leg == "seated":
		mic = preload("res://Scenes/Objects/controllers/dreamcast/dc_microphone.tscn") \
			.instantiate() as DcMicrophone
		add_child(mic)
		await get_tree().process_frame
		pad.restore_vmu(mic, 1)
	else:
		print("[dcmic] control leg: slot 2 is empty")
	await get_tree().process_frame

	_ok("slot 1 holds a card", pad.vmu_slot_option_value(0) == "VMU",
		pad.vmu_slot_option_value(0))
	_ok("slot 2 says what it holds",
		pad.vmu_slot_option_value(1) == ("Microphone" if leg == "seated" else "None"),
		pad.vmu_slot_option_value(1))

	_sys.rom_path = rom_path
	_sys.toggle_power()

	var lib := _sys.get_libretro_node()
	var deadline := Time.get_ticks_msec() + 120000
	while (lib.GetCoreIdentity() as Dictionary).is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_ok("the core came up", not (lib.GetCoreIdentity() as Dictionary).is_empty())
	if (lib.GetCoreIdentity() as Dictionary).is_empty():
		return

	var opts := _read_opt(root_dir, str(_sys.call("_resolve_core")))
	_ok("the core was told about slot 2",
		str(opts.get("reicast_device_port1_slot2", "")) == ("Microphone" if leg == "seated" else "None"),
		str(opts.get("reicast_device_port1_slot2", "(unset)")))

	# Long enough for the game to reach the point where it switches its
	# microphone on -- the core says so once, as a warning.
	var heard := false
	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		if lib.IsMicrophoneActive():
			heard = true
		await get_tree().process_frame
	_ok("the game ran", int(lib.GetFrameCount()) > 300, str(lib.GetFrameCount()))
	print("[dcmic] microphone active at some point: %s" % heard)

	_sys.toggle_power()
	for i in range(120):
		await get_tree().process_frame


func _read_opt(root: String, core: String) -> Dictionary:
	var out: Dictionary = {}
	var path := root.path_join("core_options").path_join(core + ".opt")
	if not FileAccess.file_exists(path):
		print("[dcmic] no options file at %s" % path)
		return out
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var eq := line.find("=")
		if eq < 0:
			continue
		out[line.substr(0, eq).strip_edges()] = \
			line.substr(eq + 1).strip_edges().trim_prefix("\"").trim_suffix("\"")
	return out
