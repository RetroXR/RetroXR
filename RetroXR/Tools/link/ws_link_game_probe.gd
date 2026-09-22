## Two WonderSwans, one Communication Cable, a commercial game driven by a script.
##
##     "$godot" --headless --path RetroXR res://Tools/link/ws_link_game_probe.tscn -- \
##         --rom="Z:/roms/wonderswan/Puyo Puyo Tsuu (Japan).ws" --tag=puyo \
##         --script="w:300 b:start:6:60 shot:title 0:a:6:40 ..." [--rom2=...] [--nocable]
##
## A game's versus mode negotiates over the wire before it moves, so reaching the
## match on BOTH units is the assertion, and the pictures in
## probe_out/ws/<tag>/ are the proof. Run the same script with --nocable for the
## control leg: a game that shows the same screens without a cable proved
## nothing. One leg per process.
##
## Steps, separated by spaces:
##   w:N                wait N emulated frames
##   0|1|b:BTN[:H[:G]]  hold BTN on unit 0, 1 or both for H frames, then G idle
##                      (BTN: a b start select up down left right yup ydown yleft
##                      yright, '+'-joined for chords)
##   s                  wait until both screens stop changing (menus that blink count as still)
##   c:WHO:BTN[:MAX]    press BTN on WHO (0, 1 or b) until that screen changes, MAX tries
##   shot:NAME          save both screens side by side (--every: after each step)
##
## The core's own "[ws-sio] N bytes received" WARN lines say how much crossed.
extends Node

const CORE := "mednafen_wswan"
const BUTTONS := {
	"b": 1 << 0, "start": 1 << 3, "up": 1 << 4, "down": 1 << 5,
	"left": 1 << 6, "right": 1 << 7, "a": 1 << 8,
	# The Y cursor, as this core maps it: L, R, L2, R2.
	"yleft": 1 << 10, "yright": 1 << 11, "ydown": 1 << 12, "yup": 1 << 13,
	"select": 1 << 2,
}

var _m: Array[Libretro] = []
var _tag := "ws"
var _shots := 0
var _every := false


func _ready() -> void:
	get_tree().create_timer(900.0).timeout.connect(func() -> void:
		print("[ws-game] TIMEOUT")
		get_tree().quit(1))
	var beat := Timer.new()
	beat.wait_time = 3.0
	beat.autostart = true
	beat.timeout.connect(func() -> void:
		if _m.size() == 2:
			print("[ws-game] beat frames %d / %d" % [_m[0].GetFrameCount(), _m[1].GetFrameCount()]))
	add_child(beat)
	await _run()


func _run() -> void:
	var rom := ""
	var rom2 := ""
	var script := ""
	var cable := true
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rom="):
			rom = arg.substr(6)
		elif arg.begins_with("--rom2="):
			rom2 = arg.substr(7)
		elif arg.begins_with("--script="):
			script = arg.substr(9)
		elif arg.begins_with("--tag="):
			_tag = arg.substr(6)
		elif arg == "--every":
			_every = true
		elif arg == "--nocable":
			cable = false
	if rom2.is_empty():
		rom2 = rom
	if not FileAccess.file_exists(rom) or not FileAccess.file_exists(rom2):
		print("[ws-game] SKIP  no ROM; pass --rom=<path>")
		get_tree().quit(0)
		return
	var root := CoreDownloadManager.default_core_root()
	if not FileAccess.file_exists(root.path_join("cores").path_join(CORE + "_libretro.dll")) \
			and not FileAccess.file_exists(root.path_join("cores").path_join(CORE + "_libretro.so")):
		print("[ws-game] SKIP  the %s core is not installed" % CORE)
		get_tree().quit(0)
		return

	for i in range(2):
		var lib := Libretro.new()
		add_child(lib)
		_m.append(lib)
	if cable:
		print("[ws-game] cable seated: %s" % _m[0].LinkConnect(_m[1], 0, 0))
	else:
		print("[ws-game] CONTROL LEG: no cable")
	_m[0].StartContent(root, CORE, rom)
	_m[1].StartContent(root, CORE, rom2)
	await _frames(30)
	print("[ws-game] peers %d / %d" % [_m[0].LinkPeerCount(0), _m[1].LinkPeerCount(0)])

	for step in script.split(" ", false):
		var parts := step.split(":")
		match parts[0]:
			"w":
				await _frames(int(parts[1]))
			"shot":
				_shot(parts[1])
			"s":
				await _stable()
			"c":
				var who := int(parts[1]) if parts[1] != "b" else -1
				var tries := int(parts[3]) if parts.size() > 3 else 10
				await _press_until_change(who, int(BUTTONS.get(parts[2], 0)), tries)
			"0", "1", "b":
				var mask := 0
				for name in parts[1].split("+"):
					mask |= int(BUTTONS.get(name, 0))
				var hold := int(parts[2]) if parts.size() > 2 else 6
				var gap := int(parts[3]) if parts.size() > 3 else 30
				var who: Array[Libretro] = []
				if parts[0] == "b":
					who.assign(_m)
				else:
					who.append(_m[int(parts[0])])
				for lib in who:
					lib.SetJoypadState(0, mask, 0, 0, 0, 0)
				await _frames(hold)
				for lib in who:
					lib.SetJoypadState(0, 0, 0, 0, 0, 0)
				await _frames(gap)
			_:
				print("[ws-game] bad step %s" % step)
		if _every and not step.begins_with("shot"):
			_shot(step.replace(":", "_").replace("+", "-"))
		print("[ws-game] %s -> frames %d / %d" % [step, _m[0].GetFrameCount(), _m[1].GetFrameCount()])
	_shot("end")
	for lib in _m:
		lib.StopContent()
	await get_tree().process_frame
	print("[ws-game] done, %d shots in probe_out/ws/%s" % [_shots, _tag])
	get_tree().quit(0)


func _shot(name: String) -> void:
	var a := _m[0].GetVideoImage()
	var b := _m[1].GetVideoImage()
	if a == null or b == null or a.is_empty() or b.is_empty():
		print("[ws-game] shot %s: no picture" % name)
		return
	# Copies: the image handed back is the one the core keeps drawing into.
	a = a.duplicate() as Image
	b = b.duplicate() as Image
	a.convert(Image.FORMAT_RGB8)
	b.convert(Image.FORMAT_RGB8)
	var pair := Image.create(a.get_width() + b.get_width() + 8,
		maxi(a.get_height(), b.get_height()), false, Image.FORMAT_RGB8)
	pair.fill(Color(1, 0, 1))
	pair.blit_rect(a, Rect2i(Vector2i.ZERO, a.get_size()), Vector2i.ZERO)
	pair.blit_rect(b, Rect2i(Vector2i.ZERO, b.get_size()), Vector2i(a.get_width() + 8, 0))
	var dir := "res://probe_out/ws/%s" % _tag
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	_shots += 1
	pair.save_png("%s/%02d_%s.png" % [dir, _shots, name])
	print("[ws-game] shot %02d_%s" % [_shots, name])


## The share of pixels that differ between two pictures of the same size.
func _diff(a: Image, b: Image) -> float:
	if a == null or b == null or a.get_size() != b.get_size():
		return 1.0
	var n := 0
	var total := 0
	for y in range(0, a.get_height(), 4):
		for x in range(0, a.get_width(), 4):
			total += 1
			if not a.get_pixel(x, y).is_equal_approx(b.get_pixel(x, y)):
				n += 1
	return float(n) / float(maxi(total, 1))


func _snap(i: int) -> Image:
	var img := _m[i].GetVideoImage()
	return img.duplicate() as Image if img != null and not img.is_empty() else null


## A title that has finished drawing: less than 3% of either screen moves over
## 20 frames. Capped, so an animated screen cannot hang the script.
func _stable() -> void:
	for attempt in range(60):
		var a0 := _snap(0)
		var b0 := _snap(1)
		await _frames(20)
		if _diff(a0, _snap(0)) < 0.03 and _diff(b0, _snap(1)) < 0.03:
			return


## Press until the screen moves on, because when a title starts listening is
## not the same frame from one run to the next.
func _press_until_change(who: int, mask: int, tries: int) -> void:
	var units: Array[int] = [0, 1]
	if who >= 0:
		units = [who]
	for attempt in range(tries):
		await _stable()
		var before: Array = units.map(func(i: int) -> Image: return _snap(i))
		for i in units:
			_m[i].SetJoypadState(0, mask, 0, 0, 0, 0)
		await _frames(8)
		for i in units:
			_m[i].SetJoypadState(0, 0, 0, 0, 0, 0)
		await _frames(40)
		var moved := true
		for k in range(units.size()):
			if _diff(before[k], _snap(units[k])) < 0.03:
				moved = false
		if moved:
			return
	print("[ws-game] no change after %d presses" % tries)


## Emulated frames, not host frames: two cores headless run at whatever speed.
func _frames(n: int) -> void:
	var target: int = _m[0].GetFrameCount() + n
	var guard := n * 40
	while _m[0].GetFrameCount() < target and guard > 0:
		guard -= 1
		await get_tree().process_frame
