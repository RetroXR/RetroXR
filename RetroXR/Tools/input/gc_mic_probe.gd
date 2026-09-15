## Drives the Dolphin fork's GameCube Microphone with a real core and no game: a
## DOL-022 seated in memory card slot B at power-on, pulled mid-run and seated
## again.
##
##     "$godot" --path RetroXR --resolution 320x240 --position 20,20 \
##         res://Tools/input/gc_mic_probe.tscn -- --root=<libretro root>
##
## The root holds cores/dolphin_libretro.dll and system/dolphin/dolphin-emu/Sys
## with a GameCube IPL. Point it at a throwaway root: the probe writes its
## core_options there. Windowed, because Dolphin renders through the GPU.
##
## A probe: it wants the Dolphin core and the IPL, and exits non-zero when a
## check fails. The IPL never samples the microphone, so this proves the seat, the
## option value and the live swap, not a game hearing the player.
##
## The core's log is the rest of the oracle, read by the caller: a Dolphin build
## without "mic" refuses the value as a card path ("not an absolute path, so no
## card was seated").
extends Node

var root_dir := ""
var _fail := 0
var _sys: RetroSystem = null


func _ok(name: String, cond: bool, detail := "") -> void:
	if cond:
		print("[gcmic] PASS  %s" % name)
	else:
		_fail += 1
		print("[gcmic] FAIL  %s%s" % [name, "  - " + detail if not detail.is_empty() else ""])


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--root="):
			root_dir = str(arg).trim_prefix("--root=").replace("\\", "/")
	get_tree().create_timer(240.0).timeout.connect(func() -> void:
		print("[gcmic] TIMEOUT")
		get_tree().quit(1))
	if root_dir.is_empty() or not FileAccess.file_exists(root_dir.path_join("cores/dolphin_libretro.dll")):
		print("[gcmic] need --root=<libretro root holding cores/dolphin_libretro.dll>")
		get_tree().quit(1)
		return
	await _run()
	print("[gcmic] ---- %s ----" % ["FAIL" if _fail > 0 else "PASS"])
	get_tree().quit(1 if _fail > 0 else 0)


func _run() -> void:
	_sys = preload("res://Scenes/Objects/system.tscn").instantiate() as RetroSystem
	_sys.systemid = "gamecube"
	_sys.core_directory = root_dir
	add_child(_sys)
	var mic := preload("res://Scenes/Objects/controllers/gamecube/gc_microphone.tscn").instantiate() as GcMicrophone
	add_child(mic)
	mic.global_position = _sys.global_position + Vector3(0.3, 0.0, 0.0)
	for i in range(3):
		await get_tree().process_frame
	var plug := mic.get_plug()
	if plug == null:
		_ok("the microphone has a plug", false)
		return
	_sys.restore_memory_card(plug, 1)
	await get_tree().process_frame
	_ok("the plug is seated in slot B", _sys.get_snapped_memcard(1) == plug)

	_sys.toggle_power()
	var opts := _read_opt(root_dir, str(_sys.call("_resolve_core")))
	_ok("slot B's option is mic", str(opts.get("dolphin_memcard_b_path", "")) == "mic",
		str(opts.get("dolphin_memcard_b_path", "(unset)")))
	_ok("the microphone button is pinned to R3",
		str(opts.get("dolphin_hotkey_activate_microphone", "")) == "R3",
		str(opts.get("dolphin_hotkey_activate_microphone", "(unset)")))

	var lib := _sys.get_libretro_node()
	var deadline := Time.get_ticks_msec() + 90000
	while (lib.GetCoreIdentity() as Dictionary).is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_ok("Dolphin came up", not (lib.GetCoreIdentity() as Dictionary).is_empty())
	if (lib.GetCoreIdentity() as Dictionary).is_empty():
		return
	_ok("the IPL runs with the microphone seated", await _advance(lib, 300))

	# Both zones shut for the move: slot A sits beside B and catches a plug
	# dropped out of it.
	var slots := _sys.memcard_slots()
	for zone in slots:
		zone.enabled = false
	slots[1].drop_object()
	plug.freeze = true
	plug.global_position += Vector3(0.0, 1.0, 0.0)
	var ran := await _advance(lib, 240)
	_ok("pulled from slot B mid-run",
		_sys.get_snapped_memcard(1) == null and _sys.get_snapped_memcard(0) == null)
	_ok("and the core kept running", ran)

	slots[1].enabled = true
	_sys.restore_memory_card(plug, 1)
	ran = await _advance(lib, 240)
	_ok("seated again mid-run",
		_sys.get_snapped_memcard(1) == plug and _sys.get_snapped_memcard(0) == null)
	_ok("and the core kept running", ran)
	slots[0].enabled = true
	print("[gcmic] microphone active in the core: %s (the IPL does not sample it)"
		% lib.IsMicrophoneActive())

	_sys.toggle_power()
	for i in range(120):
		await get_tree().process_frame


## True once the core has run n more frames, false if it stalls.
func _advance(lib: Libretro, n: int) -> bool:
	var start := int(lib.GetFrameCount())
	var deadline := Time.get_ticks_msec() + n * 50 + 5000
	while int(lib.GetFrameCount()) - start < n and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return int(lib.GetFrameCount()) - start >= n


func _read_opt(root: String, core: String) -> Dictionary:
	var out: Dictionary = {}
	var path := root.path_join("core_options").path_join(core + ".opt")
	if not FileAccess.file_exists(path):
		print("[gcmic] no options file at %s" % path)
		return out
	for line in FileAccess.get_file_as_string(path).split("\n"):
		var eq := line.find("=")
		if eq < 0:
			continue
		out[line.substr(0, eq).strip_edges()] = \
			line.substr(eq + 1).strip_edges().trim_prefix("\"").trim_suffix("\"")
	return out
