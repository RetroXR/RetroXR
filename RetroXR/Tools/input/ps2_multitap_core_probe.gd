## Drives the PS2 Multitap option into a RUNNING LRPS2 (or pcee2) and says what the
## core did with it. One core per process (CLAUDE.md), one leg per run:
##
##   --leg=tap    pcsx2_multitap port1 once the core is up, then both, then
##                disabled again: the core must lay its ports out each time
##   --leg=none   the control: the option never touched, so no layout line
##
## The check is the core's own WARN line, which this probe cannot read itself, so
## the run greps it (docs/dev/four-player-adapters.md "PS2 Multitap"):
##
##     "$godot" --headless --path RetroXR res://Tools/input/ps2_multitap_core_probe.tscn \
##         -- --root=<data root with cores/ and system/pcsx2> --rom=<a PS2 game> --leg=tap \
##         2>&1 | grep -a -E "\[ps2mt\]|\[PAD\]"
##
## Expected for `tap`: "[PAD] multitap in port 1: 5 libretro ports, the console's
## port 2 is libretro port 4", then "in ports 1 and 2: 8 ... port 4", then "off: 2
## ... port 1". For `none`: no [PAD] line. A build without the option (v6 and
## older, the buildbot's) prints no [PAD] line on either leg, and the probe says
## the option is undeclared.
extends Node

var core := "pcsx2"
var root := ""
var rom := ""
var leg := "tap"
var _lib: Node = null
var _ticks := 0
var _step := 0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--core="):
			core = arg.trim_prefix("--core=")
		elif arg.begins_with("--root="):
			root = arg.trim_prefix("--root=")
		elif arg.begins_with("--rom="):
			rom = arg.trim_prefix("--rom=")
		elif arg.begins_with("--leg="):
			leg = arg.trim_prefix("--leg=")
	if root.is_empty() or rom.is_empty():
		print("[ps2mt] --root and --rom are required")
		get_tree().quit(2)
		return
	get_tree().create_timer(150.0).timeout.connect(func() -> void:
		print("[ps2mt] TIMEOUT at step %d" % _step)
		get_tree().quit(1))
	var obj: Object = ClassDB.instantiate("Libretro")
	_lib = obj as Node
	add_child(_lib)
	_lib.StartContent(root, core, rom)
	print("[ps2mt] %s <- %s, leg %s" % [core, rom.get_file(), leg])


func _process(_d: float) -> void:
	if _lib == null:
		return
	_ticks += 1
	var frames := int(_lib.GetFrameCount())
	# Each step waits for the core to run on, so retro_run has read the change.
	match _step:
		0:
			if frames >= 120:
				print("[ps2mt] core up at frame %d" % frames)
				if leg == "tap":
					_set_tap("port1")
				_step = 1
				_mark = frames
		1:
			if frames >= _mark + 60:
				if leg == "tap":
					_set_tap("both")
				_step = 2
				_mark = frames
		2:
			if frames >= _mark + 60:
				if leg == "tap":
					_set_tap("disabled")
				_step = 3
				_mark = frames
		3:
			if frames >= _mark + 60:
				print("[ps2mt] done at frame %d" % frames)
				_lib.StopContent()
				get_tree().quit(0)
				_step = 4

var _mark := 0


func _set_tap(value: String) -> void:
	print("[ps2mt] pcsx2_multitap = %s" % value)
	_lib.SetCoreOption("pcsx2_multitap", value)
