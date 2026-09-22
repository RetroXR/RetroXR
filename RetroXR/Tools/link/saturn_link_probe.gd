## Two Saturns in one process, joined by a Link Cable over the real bus.
##
## A probe, not a test: it wants Beetle Saturn built with the SCI (RetroXR's
## fork), the BIOS, and a commercial disc. Each console gets its own button
## script, because a link game's two screens diverge within a menu or two and
## one shared script drives the second console into the wrong option.
##
##   "$godot" --headless --path RetroXR res://Tools/link/saturn_link_probe.tscn -- \
##       --root=<root with system/mednafen_saturn and cores/> \
##       --rom=<disc> [--rom2=<disc>] [--nolink] [--cable-at=2] \
##       [--press=12:start,14:down] [--press2=12:start] \
##       [--at=10,20,30] [--shot=<dir>/name.png]
##
## Times are EMULATED seconds (frames / 60), per console for its presses.
## A press is time:button[:hold_ms], 200 ms by default -- long enough to
## auto-repeat in some menus (Daytona's moves two rows), so pass 80 there.
## Button names are libretro's: a b x y l r start up down left right.
## Prints [satlink] lines; the core's own [link] lines come out beside them at WARN,
## and with SS_SCI_TRACE=1 in the environment every SCI register access too.
extends Node

const BUTTONS := {"b": 0, "y": 1, "select": 2, "start": 3, "up": 4, "down": 5,
	"left": 6, "right": 7, "a": 8, "x": 9, "l": 10, "r": 11}
const PRESS_MS := 200
const CORE := "mednafen_saturn"

var root_dir := ""
var rom := ""
var rom2 := ""
var link := true
var cable_at := 2.0
var sample_at: Array[float] = [10.0, 20.0, 30.0]
var presses: Array = [[], []]
var shot := ""

var _libs: Array[Node] = []
var _failed := ["", ""]


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--root="):
			root_dir = arg.trim_prefix("--root=")
		elif arg.begins_with("--rom2="):
			rom2 = arg.trim_prefix("--rom2=")
		elif arg.begins_with("--rom="):
			rom = arg.trim_prefix("--rom=")
		elif arg == "--nolink":
			link = false
		elif arg.begins_with("--cable-at="):
			cable_at = float(arg.trim_prefix("--cable-at="))
		elif arg.begins_with("--shot="):
			shot = arg.trim_prefix("--shot=")
		elif arg.begins_with("--at="):
			sample_at.clear()
			for piece: String in arg.trim_prefix("--at=").split(",", false):
				sample_at.append(float(piece))
		elif arg.begins_with("--press2=") or arg.begins_with("--press="):
			var which := 1 if arg.begins_with("--press2=") else 0
			for piece: String in arg.get_slice("=", 1).split(",", false):
				var bits := piece.split(":")
				if bits.size() >= 2 and BUTTONS.has(bits[1]):
					var hold := int(bits[2]) if bits.size() > 2 else PRESS_MS
					presses[which].append([float(bits[0]), int(BUTTONS[bits[1]]), hold])
				else:
					print("[satlink] bad press %s" % piece)
	if rom2.is_empty():
		rom2 = rom
	get_tree().create_timer(900.0).timeout.connect(func() -> void:
		print("[satlink] TIMEOUT")
		get_tree().quit(1))
	if root_dir.is_empty() or rom.is_empty() or not FileAccess.file_exists(rom):
		print("[satlink] SKIP: pass --root=<root> --rom=<disc>")
		get_tree().quit(2)
		return
	await _run()


func _run() -> void:
	var save_dir := root_dir.path_join("save").path_join(CORE)
	DirAccess.make_dir_recursive_absolute(save_dir)
	for i in 2:
		var lib := ClassDB.instantiate("Libretro") as Node
		lib.name = "Saturn%s" % ["A", "B"][i]
		add_child(lib)
		var idx := i
		lib.connect("content_load_failed", func(reason: String) -> void: _failed[idx] = reason)
		# Each console its own System Memory, or the second would read the
		# first's half-written image.
		lib.SetSramPath(save_dir.path_join("satlink_%s.bkr" % ["a", "b"][i]))
		_libs.append(lib)
	print("[satlink] A=%s" % rom)
	print("[satlink] B=%s  link=%s" % [rom2, link])
	_libs[0].StartContent(root_dir, CORE, rom)
	_libs[1].StartContent(root_dir, CORE, rom2)

	var end_at := 0.0
	for t: float in sample_at:
		end_at = maxf(end_at, t)
	for which in 2:
		for p: Array in presses[which]:
			end_at = maxf(end_at, float(p[0]) + 0.5)
	var sorted := sample_at.duplicate()
	sorted.sort()
	var next_sample := 0
	var cabled := false
	var t0 := Time.get_ticks_msec()
	while _failed[0].is_empty() and _failed[1].is_empty():
		# EMULATED time, from console A's frame count: a script replays the same
		# way however loaded the machine is, which wall-clock presses did not.
		var now := int(_libs[0].GetFrameCount()) * 1000 / 60
		if Time.get_ticks_msec() - t0 > int(end_at * 4000.0) + 60000:
			print("[satlink] STALLED at frame %d" % int(_libs[0].GetFrameCount()))
			break
		if link and not cabled and now >= int(cable_at * 1000.0):
			cabled = true
			print("[satlink] t=%.1f LinkConnect -> %s" % [now / 1000.0, _libs[0].LinkConnect(_libs[1], 0, 0)])
		for which in 2:
			var mask := 0
			var mine := int(_libs[which].GetFrameCount()) * 1000 / 60
			for p: Array in presses[which]:
				var at := int(float(p[0]) * 1000.0)
				if mine >= at and mine < at + int(p[2]):
					mask |= 1 << int(p[1])
			_libs[which].SetJoypadState(0, mask, 0, 0, 0, 0)
		if next_sample < sorted.size() and now >= int(float(sorted[next_sample]) * 1000.0):
			_sample(float(sorted[next_sample]))
			next_sample += 1
		if now >= int(end_at * 1000.0):
			break
		await get_tree().process_frame
	for i in 2:
		if not _failed[i].is_empty():
			print("[satlink] %s refused: %s" % [_libs[i].name, _failed[i]])

	if cabled:
		_libs[0].LinkDisconnect(0)
		_libs[1].LinkDisconnect(0)
	for lib in _libs:
		lib.StopContent()
	await get_tree().create_timer(2.0).timeout
	print("[satlink] done")
	get_tree().quit(0)


func _sample(at: float) -> void:
	var line := "[satlink] t=%5.1f" % at
	for i in 2:
		var lib := _libs[i]
		var img: Image = lib.GetVideoImage()
		var size := "(no image)"
		if img != null and not img.is_empty():
			size = "%dx%d" % [img.get_width(), img.get_height()]
			if not shot.is_empty():
				var flat := img.duplicate() as Image
				flat.convert(Image.FORMAT_RGB8)
				flat.save_png("%s_%s_%05.1f.%s" % [shot.get_basename(), ["A", "B"][i], at,
					shot.get_extension()])
		line += "  %s frames=%d %s" % [lib.name, int(lib.GetFrameCount()), size]
	print(line)
