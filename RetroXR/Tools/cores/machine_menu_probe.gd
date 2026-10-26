## Windowed: a real NES running a real game, and its menu's Controls and Debug tabs
## filled from it. The suite cannot start a core, so this is what shows the Debug
## page's numbers are the core's (an NES is 256 wide at ~60.1 fps) and that the
## menu's Power row really switches a running machine off.
##
##   godot --path RetroXR --resolution 640x520 --position 20,20 \
##     res://Tools/cores/machine_menu_probe.tscn -- "--rom=C:/…/Duck Hunt (World).nes"
##
## PNGs land in res://probe_out/machine_menu_{controls,debug}.png (gitignored).
## --core= picks another NES core (default fceumm).
extends Node3D

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const UI_SCENE := preload("res://Scenes/UI/core_options_2d.tscn")

var _rom := ""
var _core := "fceumm"
var _sys: RetroSystem = null
var _failed := false


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--rom="):
			_rom = arg.trim_prefix("--rom=")
		elif arg.begins_with("--core="):
			_core = arg.trim_prefix("--core=")
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		print("[mm] TIMEOUT")
		get_tree().quit(1))
	if _rom.is_empty() or not FileAccess.file_exists(_rom):
		print("[mm] SKIP: need --rom= pointing at an NES game")
		get_tree().quit(0)
		return
	_run()


func _check(cond: bool, what: String) -> void:
	print("[mm] %s  %s" % ["PASS" if cond else "FAIL", what])
	if not cond:
		_failed = true


## A row's value out of debug_state(), or "" if it is not there.
func _row(sections: Array, section: String, label: String) -> String:
	for s: Array in sections:
		if s[0] == section:
			for r: Array in s[1]:
				if r[0] == label:
					return str(r[1])
	return ""


func _run() -> void:
	_sys = SYSTEM_SCENE.instantiate() as RetroSystem
	_sys.systemid = "nes"
	_sys.model_id = "nes"
	_sys.core_name = _core
	_sys.freeze = true
	add_child(_sys)
	for i in 120:
		await get_tree().process_frame
	_sys.rom_path = _rom
	_sys.set_power(true)
	var lib := _sys.get_libretro_node()
	var deadline := Time.get_ticks_msec() + 20000
	while (not _sys.is_powered_on or int(lib.GetFrameCount()) < 120) \
			and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	_check(_sys.is_powered_on, "the menu's Power row switched the NES on")

	var dbg := _sys.debug_state()
	for s: Array in dbg:
		for r: Array in s[1]:
			print("[mm]   %-8s %-22s %s" % [s[0], r[0], r[1]])
	# 240 lines, or 224 with the core's overscan crop on (fceumm's default).
	var frame := _row(dbg, "Video", "Frame")
	_check(frame == "256 × 240" or frame == "256 × 224",
		"the frame is the NES's 256 wide, 240 or 224 tall (%s)" % frame)
	var fps := float(_row(dbg, "Video", "Declared FPS"))
	_check(fps > 59.0 and fps < 61.0, "it declares ~60 fps (%.3f)" % fps)
	var rate := float(_row(dbg, "Audio", "Declared sample rate").trim_suffix(" Hz"))
	_check(rate >= 8000.0, "it declares a real sample rate (%.1f Hz)" % rate)
	_check(_row(dbg, "Core", "Library").to_lower().contains("fce"),
		"the library is the core that was asked for: %s" % _row(dbg, "Core", "Library"))
	# The extension's own snapshot (GetCoreDebugInfo), present once it is rebuilt.
	if not lib.has_method("GetCoreDebugInfo"):
		_check(false, "this extension build has GetCoreDebugInfo (rebuild it)")
	else:
		var pf := _row(dbg, "Video", "Pixel format")
		_check(pf in ["0RGB1555", "XRGB8888", "RGB565"], "a software core names its pixel format: %s" % pf)
		_check(_row(dbg, "Video", "Renderer") == "Software", "fceumm renders in software")
		var mx := _row(dbg, "Video", "Max")
		_check(not mx.is_empty() and not mx.begins_with("0"), "the max geometry is the core's: %s" % mx)
		_check(_row(dbg, "Memory", "Save RAM") == "none", "Duck Hunt has no battery RAM")
		_check(_row(dbg, "Memory", "System RAM") != "none",
			"the NES's 2 KB work RAM is reported: %s" % _row(dbg, "Memory", "System RAM"))
		_check(_row(dbg, "Core", "Extensions").contains("nes"),
			"the core's extensions include nes: %s" % _row(dbg, "Core", "Extensions"))
		_check(not _row(dbg, "Timing", "Core frame time").is_empty(), "the frame time is reported")

	# The two tabs, photographed from the live machine.
	var sv := SubViewport.new()
	sv.size = Vector2i(550, 500)
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sv)
	var ui := UI_SCENE.instantiate() as CoreOptions2D
	sv.add_child(ui)
	await get_tree().process_frame
	await get_tree().process_frame
	ui.populate_controls(_sys.controls_state())
	await _shoot(sv, ui, 0, "controls")
	ui.populate_debug(_sys.debug_state())
	await _shoot(sv, ui, ui._debug_tab_idx, "debug")

	_sys.set_power(false)
	for i in 30:
		await get_tree().process_frame
	_check(not _sys.is_powered_on, "and switched it off again")
	print("[mm] RESULT=%s" % ("FAIL" if _failed else "PASS"))
	get_tree().quit(1 if _failed else 0)


func _shoot(sv: SubViewport, ui: CoreOptions2D, tab: int, name: String) -> void:
	ui._tabs.current_tab = tab
	for f in 12:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://probe_out")
	var out := "res://probe_out/machine_menu_%s.png" % name
	sv.get_texture().get_image().save_png(out)
	print("[mm] saved %s" % out)
