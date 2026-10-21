## Consoles on one Ethernet hub, with the real cores: GameCubes with Broadband
## Adapters, or PlayStation 2s with Network Adapters.
##
##   "$godot" --path RetroXR --resolution 320x240 --position 20,20 \
##       res://Tools/link/lan_probe.tscn -- --core=pcsx2 --count=2 \
##       "--rom=C:/…/Gran Turismo 4 (USA).chd" --roots=C:/…/lanroots \
##       --cmd=C:/…/lan_cmd.txt --out=C:/…/lan_out
##
## --stagger=<seconds> starts the consoles that far apart. Six PS2s started in one
## frame have taken the process down at startup with nothing logged.
##
## A probe: it wants real cores and commercial discs, so it cannot live in Tests/.
## WINDOWED, never --headless: both cores render in hardware and the dummy
## renderer has no context for them to draw into.
##
## Each console boots from its own root, `<roots>/c<i>`, laid out as the room's
## (cores/, system/<core>/, core_options/<core>.opt, save/<core>/), so memory
## cards and settings are never shared between two machines. The core option
## that puts the adapter's socket on the bus must already be in each root's .opt
## -- `pcsx2_dev9_eth = "link"`, `dolphin_gc_sp1 = "15"` -- because both cores
## read it once, at load, which is exactly when the room pins it.
##
## The hub is what EthernetHub does when a lead is seated: one LinkConnectGroup
## over every console's Ethernet port. Nothing here is a shortcut past it.
##
## DRIVEN FROM A FILE, so a person (or an agent) can walk menus on several
## machines while they run. Lines appended to --cmd are run in order, once each:
##
##   press <console|all> <button> [frames]   tap a button (default 8 frames)
##   hold <console|all> <button>             press and keep it down
##   release <console|all> [button]          let go (of everything)
##   stick <console|all> <lx> <ly>           left stick, -32768..32767
##   wait <frames>                           pause the queue
##   shot [name]                             every screen in one PNG in --out
##   cable on|off                            seat or pull every lead at once
##   reset [console|all]                     press the reset button
##   device <console|all> <port> <id>        what is in a controller socket
##   status                                  frames, fps and bus traffic
##   quit
##
## A line starting with ! skips the queue and runs at once (!cable off, !quit).
##
## Frames are EMULATED frames -- the furthest console's for a wait, each
## console's own for a press -- not Godot's: a small window ticks the scene far faster than 60 Hz,
## and a press counted in Godot ticks is a couple of frames to the game, which a
## menu polling every other frame can miss.
##
## Buttons are libretro's names: b y select start up down left right a x l r l2
## r2 l3 r3. On a PS2 cross is b, circle a, square y, triangle x; on a
## GameCube A is a and B is b.
extends Node

const BUTTONS := {
	"b": 0, "y": 1, "select": 2, "start": 3, "up": 4, "down": 5, "left": 6,
	"right": 7, "a": 8, "x": 9, "l": 10, "r": 11, "l2": 12, "r2": 13, "l3": 14,
	"r3": 15,
}
## Matches the cores: the PS2's i.LINK cable has port 0 and its Ethernet 1; a
## GameCube's controller sockets are 0-3 and its Broadband Adapter 4.
const ETHERNET_PORT := {"pcsx2": 1, "dolphin": 4}

var core := "pcsx2"
var rom := ""
var count := 2
var roots := ""
var cmd_path := ""
var out_dir := ""
var cabled_at_start := true
var status_every := 600
## Seconds between one console's start and the next; 0 starts them all at once.
var stagger := 0.0

var _consoles: Array[Node] = []
var _masks: Array[int] = []
var _sticks: Array[Vector2i] = []
## Per console: {button: the console's frame count to let go at}, for taps.
var _taps: Array[Dictionary] = []
var _queue: Array[String] = []
var _lines_read := 0
## Console 0's frame count the queue waits for.
var _wait_until := 0
var _ticks := 0
var _cabled := false
var _pads_seated := false
var _want_cable := true
var _frames_at := []
var _ms_at := 0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		arg = arg.strip_edges()
		if arg.begins_with("--core="):
			core = arg.trim_prefix("--core=")
		elif arg.begins_with("--rom="):
			rom = arg.trim_prefix("--rom=")
		elif arg.begins_with("--count="):
			count = clampi(int(arg.trim_prefix("--count=")), 1, 8)
		elif arg.begins_with("--roots="):
			roots = arg.trim_prefix("--roots=")
		elif arg.begins_with("--cmd="):
			cmd_path = arg.trim_prefix("--cmd=")
		elif arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=")
		elif arg == "--no-cable":
			cabled_at_start = false
		elif arg.begins_with("--status-every="):
			status_every = maxi(60, int(arg.trim_prefix("--status-every=")))
		elif arg.begins_with("--stagger="):
			stagger = maxf(0.0, float(arg.trim_prefix("--stagger=")))
	_want_cable = cabled_at_start
	if rom.is_empty() or roots.is_empty():
		print("[lan] --rom and --roots are required")
		get_tree().quit(2)
		return
	if not out_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(out_dir)

	for i in range(count):
		# Six PS2s bringing up six Vulkan devices in one frame has taken the
		# process down with nothing logged; one at a time, it starts.
		if stagger > 0.0 and i > 0:
			await get_tree().create_timer(stagger).timeout
		var obj: Object = ClassDB.instantiate("Libretro")
		var lib: Node = obj as Node
		add_child(lib)
		# Deliberately not SetInputEnabled: that lets the wrapper poll the host's
		# own devices and throws away what SetJoypadState puts there.
		lib.StartContent("%s/c%d" % [roots, i], core, rom)
		_consoles.append(lib)
		_masks.append(0)
		_sticks.append(Vector2i.ZERO)
		_taps.append({})
	print("[lan] %d x %s <- %s, Ethernet on port %d" % [count, core, rom.get_file(), _port()])


func _port() -> int:
	return int(ETHERNET_PORT.get(core, 1))


func _process(_d: float) -> void:
	_ticks += 1
	_read_commands()

	if _want_cable != _cabled and _all_up():
		_set_cable(_want_cable)
	# A GameCube has nothing in its first controller socket until the frontend
	# says so, which the room does when a pad is seated.
	if core == "dolphin" and not _pads_seated and _all_up():
		_pads_seated = true
		for lib: Node in _consoles:
			lib.SetControllerPortDevice(0, 1)

	while _consoles.size() == count and _furthest() >= _wait_until and not _queue.is_empty():
		_run(_queue.pop_front())

	for i in range(_consoles.size()):
		var taps: Dictionary = _taps[i]
		for button: int in taps.keys():
			if _frame(i) >= int(taps[button]):
				taps.erase(button)
				_masks[i] &= ~(1 << button)
		_consoles[i].SetJoypadState(0, _masks[i], _sticks[i].x, _sticks[i].y, 0, 0)

	if _ticks % status_every == 0:
		_status()


func _frame(i: int) -> int:
	return int(_consoles[i].GetFrameCount())


## The furthest console's frame count, which is what a wait counts: one console
## stalled on the cable must not stop the queue that would unstick it.
func _furthest() -> int:
	var most := 0
	for i in range(_consoles.size()):
		most = maxi(most, _frame(i))
	return most


func _all_up() -> bool:
	if _consoles.size() < count:
		return false
	for lib: Node in _consoles:
		if (lib.GetCoreIdentity() as Dictionary).is_empty():
			return false
	return true


func _set_cable(on: bool) -> void:
	var head: Node = _consoles[0]
	if on:
		var others: Array = _consoles.slice(1)
		var ports := PackedInt32Array()
		for i in range(_consoles.size()):
			ports.append(_port())
		var ok: bool = head.LinkConnectGroup(others, ports)
		print("[lan] hub: %d console(s) cabled -> %s" % [_consoles.size(), ok])
	else:
		for lib: Node in _consoles:
			lib.LinkDisconnect(_port())
		print("[lan] hub: every lead pulled")
	_cabled = on


func _read_commands() -> void:
	if cmd_path.is_empty() or not FileAccess.file_exists(cmd_path):
		return
	var text := FileAccess.get_file_as_string(cmd_path)
	var lines := text.split("\n")
	# The last piece may be half-written; only take what ends in a newline.
	var complete := lines.size() - 1
	while _lines_read < complete:
		var line := lines[_lines_read].strip_edges()
		_lines_read += 1
		if line.begins_with("!"):
			_run(line.substr(1).strip_edges())
		elif not line.is_empty() and not line.begins_with("#"):
			_queue.append(line)


func _targets(who: String) -> Array[int]:
	var out: Array[int] = []
	if who == "all":
		for i in range(_consoles.size()):
			out.append(i)
	elif who.is_valid_int() and int(who) >= 0 and int(who) < _consoles.size():
		out.append(int(who))
	return out


func _run(line: String) -> void:
	var w := line.split(" ", false)
	if w.is_empty():
		return
	print("[lan] > %s" % line)
	match w[0]:
		"press":
			if w.size() >= 3 and BUTTONS.has(w[2]):
				var frames := int(w[3]) if w.size() >= 4 else 8
				for i in _targets(w[1]):
					_masks[i] |= 1 << int(BUTTONS[w[2]])
					(_taps[i] as Dictionary)[int(BUTTONS[w[2]])] = _frame(i) + frames
		"hold":
			if w.size() >= 3 and BUTTONS.has(w[2]):
				for i in _targets(w[1]):
					_masks[i] |= 1 << int(BUTTONS[w[2]])
		"release":
			for i in _targets(w[1] if w.size() >= 2 else "all"):
				if w.size() >= 3 and BUTTONS.has(w[2]):
					_masks[i] &= ~(1 << int(BUTTONS[w[2]]))
				else:
					_masks[i] = 0
					_sticks[i] = Vector2i.ZERO
		"stick":
			if w.size() >= 4:
				for i in _targets(w[1]):
					_sticks[i] = Vector2i(int(w[2]), int(w[3]))
		"wait":
			_wait_until = _furthest() + maxi(0, int(w[1]) if w.size() >= 2 else 60)
		"shot":
			_shot(w[1] if w.size() >= 2 else "shot_%06d" % _ticks)
		"device":
			# device <console|all> <port> <libretro device id>
			if w.size() >= 4:
				for i in _targets(w[1]):
					_consoles[i].SetControllerPortDevice(int(w[2]), int(w[3]))
		"reset":
			for i in _targets(w[1] if w.size() >= 2 else "all"):
				_consoles[i].RequestReset()
		"cable":
			_want_cable = w.size() >= 2 and w[1] == "on"
		"status":
			_status()
		"quit":
			_status()
			get_tree().quit(0)
		_:
			print("[lan] ? %s" % line)


func _status() -> void:
	var now := Time.get_ticks_msec()
	var parts: Array[String] = []
	for i in range(_consoles.size()):
		var lib: Node = _consoles[i]
		var frames: int = lib.GetFrameCount()
		var fps := 0.0
		if _frames_at.size() == _consoles.size() and now > _ms_at:
			fps = float(frames - int(_frames_at[i])) * 1000.0 / float(now - _ms_at)
		parts.append("c%d f=%d %.1ffps peers=%d in=%d out=%d" % [i, frames, fps,
			lib.LinkPeerCount(_port()), lib.LinkTraffic(_port()), lib.LinkSent(_port())])
	_frames_at = []
	for lib: Node in _consoles:
		_frames_at.append(lib.GetFrameCount())
	_ms_at = now
	print("[lan] status t=%d | %s" % [_ticks, " | ".join(parts)])


## Every screen in one picture, three to a row, each labelled by position.
func _shot(name: String) -> void:
	if out_dir.is_empty():
		print("[lan] shot: no --out")
		return
	var cell := Vector2i(400, 300)
	var cols := mini(3, _consoles.size())
	var rows := int(ceil(float(_consoles.size()) / float(cols)))
	# RGB, not RGBA: an XRGB frame's padding byte is not its alpha, and a core
	# that leaves it zero would come out as a transparent (blank) picture.
	var canvas := Image.create(cell.x * cols, cell.y * rows, false, Image.FORMAT_RGB8)
	canvas.fill(Color(0.1, 0.1, 0.1))
	for i in range(_consoles.size()):
		# The texture, read back: a core rendering in hardware never fills the
		# CPU-side image GetVideoImage hands out.
		var img: Image = null
		var tex: Texture2D = _consoles[i].GetVideoTexture()
		if tex != null:
			img = tex.get_image()
		if img == null or img.is_empty():
			img = _consoles[i].GetVideoImage()
		if img == null or img.is_empty():
			continue
		var copy := img.duplicate() as Image
		copy.convert(Image.FORMAT_RGB8)
		copy.resize(cell.x - 4, cell.y - 4, Image.INTERPOLATE_BILINEAR)
		canvas.blit_rect(copy, Rect2i(Vector2i.ZERO, copy.get_size()),
			Vector2i((i % cols) * cell.x + 2, (i / cols) * cell.y + 2))
	var path := "%s/%s.png" % [out_dir, name]
	canvas.save_png(path)
	print("[lan] shot %s" % path)
