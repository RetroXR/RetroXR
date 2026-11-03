## Four Game Boys on the DMG-07 4 Player Adapter, on the bus directly: the
## adapter's core (dmg07) and N Game Boy cores, Game Boy k's link port 0 cabled to
## the adapter's port k-1. Each Game Boy is pressed on a script of frames and the
## four screens are saved side by side, so what the GAME made of the players is
## read off its own screens.
##
##     "$godot" --headless --path RetroXR res://Tools/link/dmg07_probe.tscn -- \
##         --root=<scratch root: cores/dmg07_libretro.dll + cores/gambatte_libretro.dll> \
##         --rom="<a DMG-07 game>.gb" --players=4 --out=<dir> \
##         --steps="400-406:1:start" --shots=300,600 [--every=N] [--nolink]
##
##   --players=N  Game Boys on the adapter (1-4); player 1 powers it
##   --nolink     the control: the same Game Boys, no cable anywhere
##   --core=      the Game Boy core (gambatte; mgba)
##   --stagger=N  frames between switching each Game Boy on (identical machines
##                on identical clocks otherwise do everything on the same tick)
##
## --steps: `from-to:player:buttons`, buttons joined by `+` from a b select start
## up down left right, held over player 1's frames from..to.
##
## Wario Blast featuring Bomberman! is what this was first run against
## (docs/dev/gb-link.md "The DMG-07").
extends Node

const BITS := {"b": 0, "select": 2, "start": 3, "up": 4, "down": 5, "left": 6, "right": 7, "a": 8}
const CORE_OPTIONS := {
	"gambatte": [["gambatte_gb_link_mode", "Link Cable"], ["gambatte_gb_bootloader", "disabled"]],
	"mgba": [["mgba_link_cable", "ON"], ["mgba_use_bios", "OFF"]],
}

var root_dir := ""
var rom_path := ""
var out_dir := ""
var core := "gambatte"
var players := 4
var stagger := 30
var every := 0
var nolink := false
var _steps: Array = []
var _shots: Array[int] = []
var _hub: Node = null
var _gbs: Array = []
var _masks: Array[int] = [0, 0, 0, 0]


func _ready() -> void:
	var steps_arg := ""
	var shots_arg := ""
	for arg in OS.get_cmdline_user_args():
		var a := str(arg)
		if a.begins_with("--root="):
			root_dir = a.trim_prefix("--root=").replace("\\", "/")
		elif a.begins_with("--rom="):
			rom_path = a.trim_prefix("--rom=").replace("\\", "/")
		elif a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=").replace("\\", "/")
		elif a.begins_with("--players="):
			players = clampi(int(a.trim_prefix("--players=")), 1, 4)
		elif a.begins_with("--core="):
			core = a.trim_prefix("--core=")
		elif a.begins_with("--stagger="):
			stagger = maxi(0, int(a.trim_prefix("--stagger=")))
		elif a.begins_with("--every="):
			every = int(a.trim_prefix("--every="))
		elif a == "--nolink":
			nolink = true
		elif a.begins_with("--steps="):
			steps_arg = a.trim_prefix("--steps=")
		elif a.begins_with("--shots="):
			shots_arg = a.trim_prefix("--shots=")
	get_tree().create_timer(900.0).timeout.connect(func() -> void:
		print("[dmg07] TIMEOUT")
		get_tree().quit(1))
	if root_dir.is_empty() or out_dir.is_empty() or not FileAccess.file_exists(rom_path):
		print("[dmg07] need --root=, --rom= and --out=")
		get_tree().quit(1)
		return
	for s in steps_arg.split(",", false):
		var parts := s.split(":")
		var span := parts[0].split("-")
		var mask := 0
		for b in parts[2].split("+", false):
			if not BITS.has(b):
				print("[dmg07] unknown button %s" % b)
			mask |= 1 << int(BITS.get(b, 0))
		_steps.append({"from": int(span[0]), "to": int(span[1]), "player": int(parts[1]) - 1, "mask": mask})
	for f in shots_arg.split(",", false):
		_shots.append(int(f))
	_write_options()
	await _run()


func _write_options() -> void:
	var path := "%s/core_options/%s.opt" % [root_dir, core]
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var lines: PackedStringArray = []
	for pair: Array in CORE_OPTIONS.get(core, []):
		lines.append('%s = "%s"' % [pair[0], pair[1]])
	var w := FileAccess.open(path, FileAccess.WRITE)
	if w != null:
		w.store_string("\n".join(lines) + "\n")
		w.close()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _run() -> void:
	print("[dmg07] %d x %s <- %s%s" % [players, core, rom_path.get_file(), ", NO CABLE" if nolink else ""])
	if not nolink:
		_hub = ClassDB.instantiate("Libretro") as Node
		add_child(_hub)
		_hub.StartContent(root_dir, "dmg07", "")
	for i in players:
		var gb := ClassDB.instantiate("Libretro") as Node
		add_child(gb)
		_gbs.append(gb)
	# Cabled before any Game Boy runs, as four people plug in before switching on.
	for i in players:
		(_gbs[i] as Node).StartContent(root_dir, core, rom_path)
		await _frames(2)
		if not nolink:
			var ok: bool = (_gbs[i] as Node).LinkConnect(_hub, 0, i)
			print("[dmg07] Game Boy %d cabled to adapter port %d: %s" % [i + 1, i, ok])
		if stagger > 0 and i < players - 1:
			await _frames(stagger)
	var last := 0
	for f: int in _shots:
		last = maxi(last, f)
	for st: Dictionary in _steps:
		last = maxi(last, int(st["to"]) + 1)
	var sorted := _shots.duplicate()
	sorted.sort()
	var shot_i := 0
	var next_every := every
	var t0 := Time.get_ticks_usec()
	var f0: Array[int] = []
	for gb: Node in _gbs:
		f0.append(int(gb.GetFrameCount()))
	var window_t := t0
	var window_f := int((_gbs[0] as Node).GetFrameCount())
	while true:
		var frame := int((_gbs[0] as Node).GetFrameCount())
		_drive(frame)
		while shot_i < sorted.size() and frame >= sorted[shot_i]:
			_shot(sorted[shot_i])
			shot_i += 1
		if every > 0 and frame >= next_every:
			_shot(frame)
			next_every += every
		if frame > last:
			break
		# Every 600 of player 1's frames: the rate over that window.
		if frame - window_f >= 600:
			var now_t := Time.get_ticks_usec()
			print("[dmg07] frames %d-%d: %.2f fps" % [window_f, frame, float(frame - window_f) * 1e6 / float(now_t - window_t)])
			window_t = now_t
			window_f = frame
		await get_tree().process_frame
	var secs := float(Time.get_ticks_usec() - t0) / 1e6
	var rates: Array = []
	for i in _gbs.size():
		rates.append("%.2f" % (float(int((_gbs[i] as Node).GetFrameCount()) - f0[i]) / secs))
	print("[dmg07] frame rate over %.1f s, players 1-%d: %s fps (a Game Boy is 59.73)" % [secs, _gbs.size(), ", ".join(rates)])
	if _hub != null:
		print("[dmg07] adapter peers on ports 0-3: %s" % str(range(4).map(func(p: int) -> int: return int(_hub.LinkPeerCount(p)))))
	for gb: Node in _gbs:
		gb.StopContent()
	if _hub != null:
		_hub.StopContent()
	await _frames(30)
	print("[dmg07] done")
	get_tree().quit(0)


func _drive(frame: int) -> void:
	for p in players:
		var mask := 0
		for st: Dictionary in _steps:
			if int(st["player"]) == p and frame >= int(st["from"]) and frame <= int(st["to"]):
				mask |= int(st["mask"])
		if mask != _masks[p]:
			print("[dmg07] frame %d: player %d buttons %d" % [frame, p + 1, mask])
		_masks[p] = mask
		(_gbs[p] as Node).SetJoypadState(0, mask, 0, 0, 0, 0)


## The players' screens side by side, 2x.
func _shot(frame: int) -> void:
	var sheet := Image.create(160 * 2 * players, 144 * 2, false, Image.FORMAT_RGB8)
	for p in players:
		var img: Image = (_gbs[p] as Node).call("GetVideoImage")
		if img == null or img.is_empty():
			continue
		img.convert(Image.FORMAT_RGB8)
		img.resize(320, 288, Image.INTERPOLATE_NEAREST)
		sheet.blit_rect(img, Rect2i(0, 0, 320, 288), Vector2i(320 * p, 0))
	var path := out_dir.path_join("%s_%05d.png" % ["nolink" if nolink else "p%d" % players, frame])
	sheet.save_png(path)
	print("[dmg07] frame %d -> %s" % [frame, path])
