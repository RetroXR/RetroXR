## Two to eight Atari Lynxes on one ComLynx cable, a commercial game driven by a script.
##
##     "$godot" --headless --path RetroXR res://Tools/link/lynx_link_probe.tscn -- \
##         --rom="Z:/roms/atarilynx/Checkered Flag (USA, Europe).lnx" \
##         --seq="w300,s:title,0:A,w60,s:menu" [--count=3] [--stagger=7] [--nocable] [--out=name]
##
## Run ONE at a time: two cabled probes in parallel break each other.
##
## A probe rather than a test: it wants the mednafen_lynx core (RetroXR's build,
## which carries the ComLynx driver, beetle-lynx-libretro link.cpp), the Lynx
## BIOS and a real ROM.
##
## The script is comma-separated steps:
##   wN          wait N emulated frames
##   hN          hold every later press for N frames (default 3)
##   s:NAME      save every screen side by side to probe_out/lynx/<out>/NN_NAME.png
##   M:BTN[*K]   press BTN on machine M (a digit, or b for all) K times, one at a time
##   M:BTN+BTN   press a chord
## Buttons are the Lynx's own: U D L R A B O1 O2 P (Pause).
##
## One machine at a time is the default for the same reason as Tetris on the
## Game Boy (docs/dev/gb-link.md): two machines pressed on the same frame is a
## tie no two people manage, and a game settling who leads can stall on it.
##
## --nocable runs the identical script with the lead left out, which is the
## control leg: a multiplayer screen that appears without the cable proves nothing.
extends Node

const CORE := "mednafen_lynx"

## libretro joypad bits as beetle-lynx maps them (rotation off).
const BUTTONS := {
	"U": 1 << 4, "D": 1 << 5, "L": 1 << 6, "R": 1 << 7,
	"A": 1 << 8, "B": 1 << 0, "O1": 1 << 10, "O2": 1 << 11, "P": 1 << 3,
}

var _m: Array[Libretro] = []
var _shots := 0
var _out := "run"
var _cable := true
var _count := 2
## Frames between one machine being switched on and the next (--stagger=N).
var _stagger := 7
## Frames a press is held (hN sets it).
var _hold := 3


func _ready() -> void:
	get_tree().create_timer(600.0).timeout.connect(func() -> void:
		print("[lynx] TIMEOUT")
		get_tree().quit(1))
	await _run()


func _run() -> void:
	var rom := ""
	var rom2 := ""
	var seq := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rom="):
			rom = arg.substr(6)
		elif arg.begins_with("--rom2="):
			rom2 = arg.substr(7)
		elif arg.begins_with("--seq="):
			seq = arg.substr(6)
		elif arg.begins_with("--out="):
			_out = arg.substr(6)
		elif arg.begins_with("--stagger="):
			_stagger = maxi(0, int(arg.substr(10)))
		elif arg.begins_with("--count="):
			_count = clampi(int(arg.substr(8)), 2, 8)
		elif arg == "--nocable":
			_cable = false
	if rom.is_empty() or not FileAccess.file_exists(rom):
		print("[lynx] SKIP  pass --rom=<path to a .lnx>")
		get_tree().quit(0)
		return
	if rom2.is_empty():
		rom2 = rom
	var root := CoreDownloadManager.default_core_root()
	if not FileAccess.file_exists(root.path_join("cores").path_join(CORE + "_libretro.dll")) \
			and not FileAccess.file_exists(root.path_join("cores").path_join(CORE + "_libretro.so")):
		print("[lynx] SKIP  the %s core is not installed" % CORE)
		get_tree().quit(0)
		return

	for i in range(_count):
		var lib := Libretro.new()
		add_child(lib)
		_m.append(lib)
	if _cable:
		if _count == 2:
			print("[lynx] lead in: %s" % _m[0].LinkConnect(_m[1], 0, 0))
		else:
			var ports := PackedInt32Array()
			for i in range(_count):
				ports.append(0)
			print("[lynx] leads in: %s" % _m[0].LinkConnectGroup(_m.slice(1), ports))
	# Switched on one after another, never in the same instant. Identical code on
	# identical clocks transmits at identical ticks, every frame collides on the
	# wire, and the ANDed byte settles nothing; real units are never powered on
	# within a microsecond of each other, so a game's collision recovery assumes
	# they drift. An odd number of frames so no two share a phase.
	for i in range(_count):
		_m[i].StartContent(root, CORE, rom if i == 0 else rom2)
		if i < _count - 1:
			await _frames(_stagger)
	await _frames(30)
	print("[lynx] peers %s" % [_m.map(func(l: Libretro) -> int: return l.LinkPeerCount(0))])

	for step in seq.split(",", false):
		step = step.strip_edges()
		if step.begins_with("h"):
			_hold = maxi(1, int(step.substr(1)))
		elif step.begins_with("w"):
			await _frames(int(step.substr(1)))
		elif step.begins_with("s:"):
			_shot(step.substr(2))
		elif step.length() > 2 and step[1] == ":":
			var who := step[0]
			var what := step.substr(2)
			var times := 1
			if what.contains("*"):
				times = int(what.get_slice("*", 1))
				what = what.get_slice("*", 0)
			var mask := 0
			for b in what.split("+"):
				mask |= int(BUTTONS.get(b, 0))
			for _t in range(times):
				for i in range(_count):
					if who == "b" or who == str(i):
						_m[i].SetJoypadState(0, mask, 0, 0, 0, 0)
				await _frames(_hold)
				for i in range(_count):
					_m[i].SetJoypadState(0, 0, 0, 0, 0, 0)
				await _frames(12)
		else:
			print("[lynx] ? step %s" % step)

	print("[lynx] bytes: %s" % _traffic())
	for lib in _m:
		lib.StopContent()
	await get_tree().process_frame
	await get_tree().process_frame
	print("[lynx] done")
	get_tree().quit(0)


func _traffic() -> String:
	var parts: Array[String] = []
	for i in range(_count):
		parts.append("%d:%d/%d" % [i, _m[i].LinkSent(0), _m[i].LinkTraffic(0)])
	return " ".join(parts)


func _shot(name: String) -> void:
	var imgs: Array[Image] = []
	for lib in _m:
		var img := lib.GetVideoImage()
		if img == null or img.is_empty():
			print("[lynx] shot %s: no picture" % name)
			return
		imgs.append(img)
	var fmt := imgs[0].get_format()
	var w := 0
	var h := 0
	for img in imgs:
		img.convert(fmt)
		w = maxi(w, img.get_width())
		h = maxi(h, img.get_height())
	var pair := Image.create_empty((w + 8) * imgs.size() - 8, h, false, fmt)
	pair.fill(Color(0.1, 0.1, 0.12))
	for i in range(imgs.size()):
		pair.blit_rect(imgs[i], Rect2i(0, 0, imgs[i].get_width(), imgs[i].get_height()), Vector2i(i * (w + 8), 0))
	pair.resize(pair.get_width() * 2, pair.get_height() * 2, Image.INTERPOLATE_NEAREST)
	var dir := "res://probe_out/lynx/" + _out
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	_shots += 1
	pair.save_png("%s/%02d_%s.png" % [dir, _shots, name])
	print("[lynx] shot %02d_%s  bytes %s" % [_shots, name, _traffic()])


## Emulated frames, not host frames: two cores share the machine headless.
func _frames(n: int) -> void:
	var target: int = _m[0].GetFrameCount() + n
	var guard := n * 40 + 200
	while _m[0].GetFrameCount() < target and guard > 0:
		guard -= 1
		await get_tree().process_frame
