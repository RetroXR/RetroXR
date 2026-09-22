## Two real Genesis Plus GX cores on one Gear-to-Gear cable.
##
##     python Tools/gen_gglink_rom.py     # once
##     "$godot" --headless --path RetroXR res://Tools/link/gg_link_probe.tscn
##     "$godot" --headless --path RetroXR res://Tools/link/gg_link_probe.tscn -- --rom="Z:/roms/gamegear/Columns (USA, Europe).gg"
##
## A probe rather than a test: it needs a genesis_plus_gx built with the link
## driver (libretro/gg_link.c in the RetroXR fork), which is not in CI.
##
## The ROMs (Tools/gen_gglink_rom.py) use the EXT port the way the commercial
## link games do -- UART on, NMI on receive -- and paint the backdrop with what
## the NMI saw: blue for "the other Game Gear is not there", green for the right
## byte, red for a wrong one, and black if no NMI ever fired. The master sends,
## the slave answers from its NMI, so each screen is green only because the
## OTHER machine's byte reached it.
##
## With --rom (and optionally --rom2, default the same file) it runs a real game
## on both ends instead, cabled, and saves both screens after --seconds, for a
## person to read: there is no oracle for a commercial menu.
extends Node

const CORE := "genesis_plus_gx"

var _pass := 0
var _fail := 0


func _ready() -> void:
	get_tree().create_timer(240.0).timeout.connect(func() -> void:
		print("[gg-link] TIMEOUT")
		get_tree().quit(1))
	await _run()


func _ok(name: String, cond: bool, detail := "") -> void:
	if cond:
		_pass += 1
		print("[gg-link] PASS  %s" % name)
	else:
		_fail += 1
		print("[gg-link] FAIL  %s%s" % [name, "  — " + detail if not detail.is_empty() else ""])


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


## Wait until both screens read `want`, or give up after `seconds` of wall time.
## A headless run spins frames far faster than the core emulates them, so a
## fixed frame count says nothing about how much emulated time has passed.
func _until(a: Libretro, b: Libretro, want: String, seconds := 15.0) -> void:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if _name(_shade(a.GetVideoImage())) == want and _name(_shade(b.GetVideoImage())) == want:
			return
		await _frames(10)


func _run() -> void:
	var rom := ""
	var rom2 := ""
	var seconds := 20.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rom="):
			rom = arg.substr(6)
		elif arg.begins_with("--rom2="):
			rom2 = arg.substr(7)
		elif arg.begins_with("--seconds="):
			seconds = float(arg.substr(10))

	var root := CoreDownloadManager.default_core_root()
	if not FileAccess.file_exists("%s/cores/%s_libretro.dll" % [root, CORE]) \
			and not FileAccess.file_exists("%s/cores/%s_libretro.so" % [root, CORE]):
		print("[gg-link] SKIP  no %s core under %s" % [CORE, root])
		get_tree().quit(0)
		return

	if not rom.is_empty():
		await _game(root, rom, rom2 if not rom2.is_empty() else rom, seconds)
		get_tree().quit(0)
		return

	var master_rom := ProjectSettings.globalize_path("res://Tools/gglink/link_master.gg")
	var slave_rom := ProjectSettings.globalize_path("res://Tools/gglink/link_slave.gg")
	if not FileAccess.file_exists(master_rom):
		print("[gg-link] SKIP  run Tools/gen_gglink_rom.py first")
		get_tree().quit(0)
		return

	var a := Libretro.new()
	var b := Libretro.new()
	add_child(a)
	add_child(b)
	a.StartContent(root, CORE, master_rom)
	b.StartContent(root, CORE, slave_rom)
	await _until(a, b, "blue")

	# Control leg: attached but cabled to nothing. A machine with its UART on and
	# nobody at the far end takes the "not there" NMI every frame -- which is the
	# driver talking; a core without one would sit on black.
	var ca := _shade(a.GetVideoImage())
	var cb := _shade(b.GetVideoImage())
	print("[gg-link] uncabled: master %s, slave %s" % [_name(ca), _name(cb)])
	_ok("uncabled master is told nobody is there", _name(ca) == "blue", _name(ca))
	_ok("uncabled slave is told nobody is there", _name(cb) == "blue", _name(cb))

	_ok("cabling them together succeeds", a.LinkConnect(b, 0, 0))
	await _frames(2)
	_ok("both machines on the wire", a.LinkPeerCount(0) == 2 and b.LinkPeerCount(0) == 2,
			"%d / %d" % [a.LinkPeerCount(0), b.LinkPeerCount(0)])
	await _until(a, b, "green")

	var la := _shade(a.GetVideoImage())
	var lb := _shade(b.GetVideoImage())
	print("[gg-link] cabled: master %s, slave %s, master sent %d" % [_name(la), _name(lb), a.LinkSent(0)])
	_save(a.GetVideoImage(), "master")
	_save(b.GetVideoImage(), "slave")
	_ok("the slave received the master's byte", _name(lb) == "green", _name(lb))
	_ok("the master received the slave's answer", _name(la) == "green", _name(la))

	# Pull the lead: both are told the far end has gone.
	a.LinkDisconnect(0)
	await _until(a, b, "blue")
	_ok("pulling the lead is felt on the master", _name(_shade(a.GetVideoImage())) == "blue",
			_name(_shade(a.GetVideoImage())))
	_ok("and on the slave", _name(_shade(b.GetVideoImage())) == "blue", _name(_shade(b.GetVideoImage())))

	# And back: the master's send buffer was emptied when the cable moved, so it
	# starts sending again of its own accord.
	_ok("re-cabling succeeds", a.LinkConnect(b, 0, 0))
	await _until(a, b, "green")
	_ok("the link comes back on its own",
			_name(_shade(a.GetVideoImage())) == "green" and _name(_shade(b.GetVideoImage())) == "green",
			"%s / %s" % [_name(_shade(a.GetVideoImage())), _name(_shade(b.GetVideoImage()))])

	a.StopContent()
	await _frames(60)
	_ok("stopping one end leaves the other alone", b.LinkPeerCount(0) == 0)
	b.StopContent()
	await _frames(60)
	print("[gg-link] ---- %d passed, %d failed ----" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


## A real game on both ends, cabled from the start, for `seconds` of wall time.
##
## --press=START@3,DOWN@5,B@6 taps a button on BOTH machines at that many seconds
## (a tenth of a second held); --press2= gives the second machine its own list.
## A frame from each is saved every two seconds, for a person to read.
const _BUTTONS := {"B": 0, "Y": 1, "SELECT": 2, "START": 3, "UP": 4, "DOWN": 5,
		"LEFT": 6, "RIGHT": 7, "A": 8}


func _presses(spec: String) -> Array:
	var out := []
	for item in spec.split(",", false):
		var parts := item.split("@")
		if parts.size() == 2 and _BUTTONS.has(parts[0]):
			out.append([float(parts[1]), 1 << int(_BUTTONS[parts[0]])])
	return out


func _game(root: String, rom: String, rom2: String, seconds: float) -> void:
	var press_a := []
	var press_b := []
	var both := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--press="):
			both = arg.substr(8)
		elif arg.begins_with("--press2="):
			press_b = _presses(arg.substr(9))
	press_a = _presses(both)
	if press_b.is_empty():
		press_b = _presses(both)

	var a := Libretro.new()
	var b := Libretro.new()
	add_child(a)
	add_child(b)
	a.StartContent(root, CORE, rom)
	b.StartContent(root, CORE, rom2)
	await _frames(120)
	if not "--nolink" in OS.get_cmdline_user_args():
		a.LinkConnect(b, 0, 0)
	var start := Time.get_ticks_msec()
	var next_shot := 0.0
	var shot := 0
	while true:
		var t := (Time.get_ticks_msec() - start) / 1000.0
		if t > seconds:
			break
		a.SetJoypadState(0, _held(press_a, t), 0, 0, 0, 0)
		b.SetJoypadState(0, _held(press_b, t), 0, 0, 0, 0)
		if t >= next_shot:
			_save(a.GetVideoImage(), "game_a_%02d" % shot)
			_save(b.GetVideoImage(), "game_b_%02d" % shot)
			shot += 1
			next_shot += 2.0
		await _frames(1)
	print("[gg-link] %s: peers %d/%d, sent %d/%d" % [rom.get_file(), a.LinkPeerCount(0),
			b.LinkPeerCount(0), a.LinkSent(0), b.LinkSent(0)])
	_save(a.GetVideoImage(), "game_a")
	_save(b.GetVideoImage(), "game_b")
	a.StopContent()
	b.StopContent()
	await _frames(60)


func _held(presses: Array, t: float) -> int:
	var mask := 0
	for p in presses:
		if t >= p[0] and t < p[0] + 0.1:
			mask |= p[1]
	return mask


func _shade(img: Image) -> Color:
	if img == null or img.is_empty():
		return Color(0, 0, 0, 0)
	# The colour on most of the screen, not all of it: the core draws a small
	# on-screen message over the corner for a while after loading.
	var counts := {}
	for y in range(0, img.get_height(), 2):
		for x in range(0, img.get_width(), 2):
			var key := img.get_pixel(x, y).to_html(false)
			counts[key] = counts.get(key, 0) + 1
	var best := ""
	var total := 0
	for k: String in counts:
		total += counts[k]
		if best.is_empty() or counts[k] > counts[best]:
			best = k
	if counts[best] * 10 < total * 8:
		return Color(1, 1, 1, 0)
	var c := Color.html(best)
	return Color(c.r, c.g, c.b, 1)


func _name(c: Color) -> String:
	if c.a == 0:
		return "<no picture>" if c.r == 0 else "<not flat>"
	if c.r < 0.1 and c.g < 0.1 and c.b < 0.1:
		return "black"
	for pair in [[c.b, c.r, c.g, "blue"], [c.g, c.r, c.b, "green"], [c.r, c.g, c.b, "red"]]:
		if pair[0] > 0.7 and pair[1] < 0.2 and pair[2] < 0.2:
			return pair[3]
	return "#" + c.to_html(false)


func _save(img: Image, name: String) -> void:
	if img == null or img.is_empty():
		return
	var dir := ProjectSettings.globalize_path("res://probe_out")
	DirAccess.make_dir_recursive_absolute(dir)
	img.save_png("%s/gg_link_%s.png" % [dir, name])
	if not name.begins_with("game_") or name in ["game_a", "game_b"]:
		print("[gg-link] wrote res://probe_out/gg_link_%s.png" % name)
