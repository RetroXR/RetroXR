## Two real Atari Jaguars on one JagLink cable, running a JagLink game.
##
##   "$godot" --headless --path RetroXR res://Tools/link/jag_link_probe.tscn -- \
##       "--rom=Z:/roms/atarijaguar/Doom (World).j64" --game=doom
##
## A probe, not a test: it wants the RetroXR virtualjaguar fork (JERRY UART on
## the link bus, protocol `jag-uart-1`) and commercial cartridges.
##
## `--game=` picks the menu walk for doom / aircars / battlesphere; `--steps=`
## overrides it with a script of comma-separated steps, which is how the walks
## were found:
##   a:start:10   hold START on machine A for 10 frames (a, b, or ab)
##   wait:300     run 300 emulated frames
##   shot:name    save both screens side by side to probe_out/jag/
##   mark         print the traffic so far
## Buttons: b y select start up down left right a x l r l2 r2 l3 r3.
##
## `--no-cable` is the control leg: the same walk with nothing seated. The
## oracle is traffic, not the picture -- see psx_link_probe.gd -- so a walk that
## only reaches a linked game WITH the cable, and moves real bytes both ways,
## is what passes.
extends Node3D

const CORE := "virtualjaguar"

const BUTTONS := {
	"b": 0, "y": 1, "select": 2, "start": 3, "up": 4, "down": 5, "left": 6,
	"right": 7, "a": 8, "x": 9, "l": 10, "r": 11, "l2": 12, "r2": 13,
	"l3": 14, "r3": 15,
}

# Found by hand with --steps and the shots; each comment says what screen the
# step is meant to reach.
const WALKS := {
	# A opens the main menu, RIGHT turns Game Mode from Single to a two-player
	# mode, B starts it on A and then on B. Uncabled both sit on ATTEMPTING TO
	# CONNECT; cabled it is Deathmatch, YOUR/HIS FRAGS, ~2600 bytes each way.
	"doom": "wait:60,ab:a:10,wait:60,ab:right:8,wait:30,shot:mode,a:b:10,wait:60,b:b:10,wait:900,mark,shot:linked",
	# A leaves the title for Game Selection, DOWN to Two Player Direct Serial
	# (the menu ignores input for a moment after it appears, hence the waits),
	# B takes Player 2, then difficulty and name on both, and Player 1 picks the
	# mission. Both then show the same briefing and fly the same clock.
	"aircars": "wait:600,ab:a:10,wait:200,ab:down:6,wait:60,ab:a:10,wait:200,b:down:6,wait:60,ab:a:10,wait:200,ab:a:10,wait:200,ab:a:10,wait:300,a:a:10,wait:600,ab:a:10,wait:300,ab:a:10,wait:600,shot:linked,ab:up:200,wait:60,shot:flying,mark",
	# EVERY press staggered between the machines: two Jaguars on the bus are
	# bit-identical, and pressed on the same frame BattleSphere's player
	# discovery picks the same id on both and reports "Network Failure". A leaves
	# the title, DOWN to Network Mode, B, B (Free-For-All), then fire through
	# ship select into the arena. Past launch it is NOT a working dogfight -- one
	# console flies, the other goes black -- and over the core's own TCP link it
	# is the same, so that is the emulator, not the wire.
	"battlesphere": "wait:600,a:a:10,wait:37,b:a:10,wait:300,a:down:20,wait:23,b:down:20,wait:100,a:b:10,wait:41,b:b:10,wait:300,a:b:10,wait:29,b:b:10,wait:800,shot:lobby,a:b:10,wait:400,b:b:10,wait:600,shot:ships,a:a:10,wait:31,b:a:10,wait:300,a:b:10,wait:27,b:b:10,wait:300,a:b:10,wait:560,shot:arena,mark",
}

var rom := ""
var steps := ""
var no_cable := false
# The core's own TCP transport instead of the bus: a comparison leg, to tell
# a game that fails over any wire from one the bus breaks.
var tcp := false
var min_bytes := 200
var _a: Node = null
var _b: Node = null
var _pass := 0
var _fail := 0
var _shots := 0
var _out := "res://probe_out/jag"


func _ok(name: String, cond: bool, detail := "") -> void:
	if cond:
		_pass += 1
		print("[jag-link] PASS  %s" % name)
	else:
		_fail += 1
		print("[jag-link] FAIL  %s%s" % [name, "  - " + detail if detail else ""])


func _ready() -> void:
	var game := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rom="):
			rom = a.trim_prefix("--rom=")
		elif a.begins_with("--game="):
			game = a.trim_prefix("--game=")
		elif a.begins_with("--steps="):
			steps = a.trim_prefix("--steps=")
		elif a.begins_with("--min-bytes="):
			min_bytes = int(a.trim_prefix("--min-bytes="))
		elif a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
		elif a == "--no-cable":
			no_cable = true
		elif a == "--tcp":
			tcp = true
	if steps.is_empty():
		steps = WALKS.get(game, "")
	if rom.is_empty() or steps.is_empty():
		print("[jag-link] need --rom= and --game= or --steps=")
		get_tree().quit(2)
		return
	get_tree().create_timer(1500.0).timeout.connect(func() -> void:
		print("[jag-link] TIMEOUT")
		get_tree().quit(2))
	await _run()


## Emulated frames, on BOTH machines -- see psx_link_probe.gd's _wait.
func _wait(n: int) -> void:
	var target_a: int = int(_a.GetFrameCount()) + n
	var target_b: int = int(_b.GetFrameCount()) + n
	var guard := n * 200 + 200
	while (int(_a.GetFrameCount()) < target_a or int(_b.GetFrameCount()) < target_b) and guard > 0:
		guard -= 1
		await get_tree().process_frame


func _shot(name: String) -> void:
	var a: Image = _a.GetVideoImage()
	var b: Image = _b.GetVideoImage()
	if a == null or b == null or a.is_empty() or b.is_empty():
		print("[jag-link] shot %s: no picture" % name)
		return
	var w := a.get_width()
	var h := a.get_height()
	var pair := Image.create_empty(w * 2 + 8, h, false, a.get_format())
	pair.fill(Color(0.1, 0.1, 0.12))
	pair.blit_rect(a, Rect2i(0, 0, w, h), Vector2i(0, 0))
	pair.blit_rect(b, Rect2i(0, 0, mini(w, b.get_width()), mini(h, b.get_height())), Vector2i(w + 8, 0))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	_shots += 1
	var path := "%s/%02d_%s.png" % [_out, _shots, name]
	pair.save_png(path)
	print("[jag-link] shot %s  (%dx%d)" % [ProjectSettings.globalize_path(path), w, h])


func _traffic(lib: Node) -> Array:
	return [int(lib.LinkTraffic(0)), int(lib.LinkSent(0))]


func _mark(label: String) -> void:
	print("[jag-link] %s  frame A=%d B=%d  A recv/sent=%s  B recv/sent=%s" % [
		label, _a.GetFrameCount(), _b.GetFrameCount(), _traffic(_a), _traffic(_b)])


func _step(s: String) -> void:
	var p := s.strip_edges().split(":")
	match p[0]:
		"wait":
			await _wait(int(p[1]))
		"shot":
			_shot(p[1] if p.size() > 1 else "shot")
		"mark":
			_mark("mark")
		"a", "b", "ab":
			var mask := 0
			for name in p[1].split("+"):
				mask |= 1 << int(BUTTONS[name])
			var hold := int(p[2]) if p.size() > 2 else 8
			var libs: Array = [_a, _b] if p[0] == "ab" else ([_a] if p[0] == "a" else [_b])
			for lib: Node in libs:
				lib.SetJoypadState(0, mask, 0, 0, 0, 0)
			await _wait(hold)
			for lib: Node in libs:
				lib.SetJoypadState(0, 0, 0, 0, 0, 0)
			await _wait(12)
		_:
			print("[jag-link] unknown step %s" % s)


func _run() -> void:
	var root: String = CoreDownloadManager.default_core_root()
	print("[jag-link] rom  %s  %s" % [rom.get_file(), "(NO CABLE)" if no_cable else ""])

	var oa: Object = ClassDB.instantiate("Libretro")
	var ob: Object = ClassDB.instantiate("Libretro")
	_a = oa as Node
	_b = ob as Node
	add_child(_a)
	add_child(_b)
	# SetCoreOption persists to the player's real core_options/virtualjaguar.opt,
	# so the file is snapshotted here and put back byte-for-byte at the end, and
	# the mode is pinned both ways: a TCP leg left behind would silently turn
	# every later bus run into a TCP one.
	var opt_path := root.path_join("core_options/virtualjaguar.opt")
	var opt_before: Variant = FileAccess.get_file_as_bytes(opt_path) if FileAccess.file_exists(opt_path) else null
	if tcp:
		_a.SetCoreOption("virtualjaguar_netlink", "tcp_server")
		_b.SetCoreOption("virtualjaguar_netlink", "tcp_client")
		no_cable = true
	else:
		_a.SetCoreOption("virtualjaguar_netlink", "auto")
		_b.SetCoreOption("virtualjaguar_netlink", "auto")
	_a.StartContent(root, CORE, rom)
	_b.StartContent(root, CORE, rom)
	# After the core is up: a port device set before it lands nowhere.
	await _wait(300)
	_a.SetControllerPortDevice(0, 1)
	_b.SetControllerPortDevice(0, 1)
	_ok("both cores came up",
		int(_a.GetFrameCount()) > 0 and int(_b.GetFrameCount()) > 0)

	if not no_cable:
		_ok("cabling them together succeeds", bool(_a.LinkConnect(_b, 0, 0)))
		await _wait(4)
		_ok("both ends see the bus",
			int(_a.LinkPeerCount(0)) == 2 and int(_b.LinkPeerCount(0)) == 2,
			"A=%d B=%d" % [_a.LinkPeerCount(0), _b.LinkPeerCount(0)])

	var before := [_traffic(_a), _traffic(_b)]
	for s in steps.split(","):
		await _step(s)
	var after := [_traffic(_a), _traffic(_b)]
	_mark("end")

	if not no_cable:
		for i in 2:
			var who := "AB"[i]
			_ok("machine %s sent a game's worth of bytes" % who,
				after[i][1] - before[i][1] >= min_bytes,
				"sent %d, want >= %d" % [after[i][1] - before[i][1], min_bytes])
			_ok("machine %s received what the other sent" % who,
				after[i][0] - before[i][0] >= min_bytes,
				"received %d, want >= %d" % [after[i][0] - before[i][0], min_bytes])

	_a.StopContent()
	_b.StopContent()
	await get_tree().create_timer(2.0).timeout
	if opt_before == null:
		DirAccess.remove_absolute(opt_path)
	else:
		var f := FileAccess.open(opt_path, FileAccess.WRITE)
		f.store_buffer(opt_before)
		f.close()
	print("[jag-link] ---- %d passed, %d failed ----" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)
