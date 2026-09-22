## Two Neo Geo Pockets, one SNK link cable, a commercial game driven by a script.
##
##     "$godot" --headless --path RetroXR res://Tools/link/ngp_link_probe.tscn -- \
##         --rom="Z:/roms/ngpc/Puzzle Link 2 (USA, Europe).ngc" \
##         --seq="w300,s:title,0:A,w60,s:menu,1:A,w120,s:versus" [--nocable] [--out=name]
##
## A probe rather than a test: it wants the mednafen_ngp core (RetroXR's build,
## which carries the link driver) and a real ROM.
##
## The script is comma-separated steps:
##   wN          wait N emulated frames
##   s:NAME      save both screens side by side to probe_out/ngp/<out>/NN_NAME.png
##   M:BTN[*K]   press BTN on machine M (0, 1 or b for both) K times, one at a time
##   M:BTN+BTN   press a chord;  M:BTN~N  hold it N frames (default 3)
##   S:NAME      save both machines' states to probe_out/ngp/states/NAME_<i>.state
##
## --load=NAME restores both from such a pair after boot, so a game whose link
## mode is hours into it (Card Fighters' Clash) is reached in stages, each run
## starting where the last good one saved.
## Buttons are the NGP's own: U D L R A B OPT. A is the confirm button.
##
## One machine at a time is the default for the same reason as Tetris on the
## Game Boy (docs/dev/gb-link.md): a game settling which end leads can stall for
## ever on two machines pressed on the same frame, which no two people manage.
##
## --nocable runs the identical script with the lead left out, which is the
## control leg: a versus screen that appears without the cable proves nothing.
## Every run ends with the byte counts, and screens in probe_out to look at.
extends Node

const CORE := "mednafen_ngp"

## libretro joypad bits as beetle-ngp maps them onto the pad: the core reads
## RetroPad B as the NGP's A (confirm), RetroPad A as its B, START as Option.
const BUTTONS := {
	"U": 1 << 4, "D": 1 << 5, "L": 1 << 6, "R": 1 << 7,
	"A": 1 << 0, "B": 1 << 8, "OPT": 1 << 3,
}

var _m: Array[Libretro] = []
var _shots := 0
var _out := "run"
var _cable := true
var _load := ""
const STATES := "res://probe_out/ngp/states"


func _ready() -> void:
	get_tree().create_timer(600.0).timeout.connect(func() -> void:
		print("[ngp] TIMEOUT")
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
		elif arg.begins_with("--load="):
			_load = arg.substr(7)
		elif arg == "--nocable":
			_cable = false
	if rom.is_empty() or not FileAccess.file_exists(rom):
		print("[ngp] SKIP  pass --rom=<path to a .ngp/.ngc>")
		get_tree().quit(0)
		return
	if rom2.is_empty():
		rom2 = rom
	var root := CoreDownloadManager.default_core_root()
	if not FileAccess.file_exists(root.path_join("cores").path_join(CORE + "_libretro.dll")) \
			and not FileAccess.file_exists(root.path_join("cores").path_join(CORE + "_libretro.so")):
		print("[ngp] SKIP  the %s core is not installed" % CORE)
		get_tree().quit(0)
		return

	for i in range(2):
		var lib := Libretro.new()
		add_child(lib)
		_m.append(lib)
	if _cable:
		print("[ngp] lead in: %s" % _m[0].LinkConnect(_m[1], 0, 0))
	_m[0].StartContent(root, CORE, rom)
	_m[1].StartContent(root, CORE, rom2)
	await _frames(30)
	print("[ngp] peers %d / %d" % [_m[0].LinkPeerCount(0), _m[1].LinkPeerCount(0)])
	if not _load.is_empty():
		for i in range(2):
			var f := FileAccess.open("%s/%s_%d.state" % [STATES, _load, i], FileAccess.READ)
			if f == null:
				print("[ngp] no state %s_%d" % [_load, i])
				get_tree().quit(1)
				return
			_m[i].RequestLoadState(f.get_buffer(f.get_length()), _m[i].GetFrameCount())
			var ok: bool = await _m[i].savestate_loaded
			print("[ngp] loaded %s_%d: %s" % [_load, i, ok])
		await _frames(10)

	for step in seq.split(",", false):
		step = step.strip_edges()
		if step.begins_with("w"):
			await _frames(int(step.substr(1)))
		elif step.begins_with("s:"):
			_shot(step.substr(2))
		elif step.begins_with("S:"):
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(STATES))
			for i in range(2):
				_m[i].RequestSaveState()
				var got: Array = await _m[i].savestate_ready
				var f := FileAccess.open("%s/%s_%d.state" % [STATES, step.substr(2), i], FileAccess.WRITE)
				f.store_buffer(got[0] as PackedByteArray)
				f.close()
			print("[ngp] saved %s" % step.substr(2))
		elif step.length() > 2 and step[1] == ":":
			var who := step[0]
			var what := step.substr(2)
			var times := 1
			var hold := 3
			if what.contains("~"):
				hold = int(what.get_slice("~", 1))
				what = what.get_slice("~", 0)
			if what.contains("*"):
				times = int(what.get_slice("*", 1))
				what = what.get_slice("*", 0)
			var mask := 0
			for b in what.split("+"):
				mask |= int(BUTTONS.get(b, 0))
			for _t in range(times):
				for i in range(2):
					if who == "b" or who == str(i):
						_m[i].SetJoypadState(0, mask, 0, 0, 0, 0)
				await _frames(hold)
				for i in range(2):
					_m[i].SetJoypadState(0, 0, 0, 0, 0, 0)
				await _frames(12)
		else:
			print("[ngp] ? step %s" % step)

	print("[ngp] bytes: 0 sent %d took %d | 1 sent %d took %d" % [
		_m[0].LinkSent(0), _m[0].LinkTraffic(0), _m[1].LinkSent(0), _m[1].LinkTraffic(0)])
	for lib in _m:
		lib.StopContent()
	# Let both emulation threads finish tearing down (detaching from the bus)
	# before the process goes.
	await get_tree().create_timer(1.5).timeout
	print("[ngp] done")
	get_tree().quit(0)


func _shot(name: String) -> void:
	var a := _m[0].GetVideoImage()
	var b := _m[1].GetVideoImage()
	if a == null or b == null or a.is_empty() or b.is_empty():
		print("[ngp] shot %s: no picture" % name)
		return
	b.convert(a.get_format())
	var w := a.get_width()
	var h := a.get_height()
	var pair := Image.create_empty(w * 2 + 8, h, false, a.get_format())
	pair.fill(Color(0.1, 0.1, 0.12))
	pair.blit_rect(a, Rect2i(0, 0, w, h), Vector2i(0, 0))
	pair.blit_rect(b, Rect2i(0, 0, b.get_width(), b.get_height()), Vector2i(w + 8, 0))
	pair.resize(pair.get_width() * 2, pair.get_height() * 2, Image.INTERPOLATE_NEAREST)
	var dir := "res://probe_out/ngp/" + _out
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	_shots += 1
	pair.save_png("%s/%02d_%s.png" % [dir, _shots, name])
	print("[ngp] shot %02d_%s  bytes 0:%d/%d 1:%d/%d" % [_shots, name,
		_m[0].LinkSent(0), _m[0].LinkTraffic(0), _m[1].LinkSent(0), _m[1].LinkTraffic(0)])


## Emulated frames, not host frames: two cores share the machine headless.
func _frames(n: int) -> void:
	var target: int = _m[0].GetFrameCount() + n
	var guard := n * 40 + 200
	while _m[0].GetFrameCount() < target and guard > 0:
		guard -= 1
		await get_tree().process_frame
