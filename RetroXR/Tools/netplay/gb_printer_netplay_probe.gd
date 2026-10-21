## A Game Boy and its printer, replicated on two netplay peers in LOCKSTEP.
##
##   "$godot" --headless --path RetroXR res://Tools/netplay/gb_printer_netplay_probe.tscn [-- --core=mgba]
##
## A link cable never crosses the network (netplay.md §2g): every peer runs every
## machine on the wire, and determinism is what keeps them agreeing. So a session
## over a Game Boy cabled to a printer is, on each peer, a Game Boy core and a
## printer core joined on that peer's own bus, both gated frame by frame. This
## builds two such pairs in one process -- peer A and peer B -- feeds all four
## cores the same agreed inputs, and holds them all at the same frames to compare.
##
## What has to hold, at every checkpoint, between the two peers:
##   * the printer's paper, every dot;
##   * the printer's whole savestate, every byte (what a late join would ship);
##   * the Game Boy's screen.
## And the pairs must keep moving: the printer's frames are exactly the Game Boy's,
## so neither waits on the other however long they run. A printer with a frame of
## its own length would drift on the bus and wedge the gate (netplay_link_probe).
##
## At each checkpoint only the PRINTERS are held at the frame; the Game Boys are
## fed two frames past it, as inputs run ahead of the cores in a live session.
## Holding every core at one frame while they are cabled is what a session does
## only for a lead pulled mid-game, and on mGBA that can wedge (gb-printer.md);
## the cable is seated here with every core held, as a session seats one, which
## is the case that matters for a print.
##
## FEED and TEAR go in as agreed input on chosen frames, as a holder's presses
## reach every peer in a session.
##
## A probe: it needs the real cores. ROM from Tools/gen_gblink_rom.py.
extends Node

const ROM := "res://Tools/gblink/printer.gb"
const EXPECTED := "res://Tools/gblink/printer_expected.png"
const OPTIONS := {
	"gambatte": [["gambatte_gb_link_mode", "Link Cable"], ["gambatte_gb_bootloader", "disabled"]],
	"mgba": [["mgba_link_cable", "ON"], ["mgba_use_bios", "OFF"],
		["mgba_gb_model", "Game Boy"], ["mgba_sgb_borders", "OFF"]],
}
const BTN_B := 1 << 0
const BTN_A := 1 << 8
## The port blocks are five ints each, then sensors and keyboard (Wrapper).
const FLAT_SIZE := 20 + 7 + 8

## When things happen, in agreed frames. The test ROM has found the printer and
## its print is out by ~800.
const FEED_FROM := 1000
const FEED_TO := 1060
const TEAR_AT := 1100
const TEAR_LINES := 50
## 1100 is TEAR_AT: every core held just before the frame that tears.
const SEAT_AT := 60
const CHECKPOINTS := [950, 1050, 1100, 1200, 2400]

var _core := "gambatte"
## [gb_A, printer_A, gb_B, printer_B]
var _libs: Array = []
## Frames posted so far: the Game Boys', and the printers', which stop at each
## checkpoint while the Game Boys run on.
var _posted_gb := 0
var _posted_pr := 0
var _fail := 0
var _pass := 0
var _opt_path := ""
var _opt_backup := ""
var _had_opt := false
var _state := {}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--core="):
			_core = arg.substr(7)
	get_tree().create_timer(300.0).timeout.connect(func() -> void:
		print("[np-print] TIMEOUT at frame %s" % _frames())
		_finish())
	await _run()


func _run() -> void:
	var root := CoreDownloadManager.default_core_root()
	for core in [_core, GbPrinter.CORE]:
		if CoreDownloadManager.installed_core_lib(core).is_empty():
			print("[np-print] SKIP  %s is not installed" % core)
			get_tree().quit(0)
			return
	_write_options(root)
	var rom := ProjectSettings.globalize_path(ROM)
	for i in range(4):
		var lib := ClassDB.instantiate("Libretro") as Node
		add_child(lib)
		lib.SetNetplayMode(true, 0x1, 0)
		if i % 2 == 0:
			lib.StartContent(root, _core, rom)
		else:
			lib.StartContent(root, GbPrinter.CORE, "")
		_libs.append(lib)
	for _i in range(600):
		await get_tree().process_frame
		if _libs.all(func(l: Node) -> bool: return not (l.GetCoreIdentity() as Dictionary).is_empty()):
			break
	# The lead goes in with every core held at one frame, as a session lands a
	# cable (NetplaySession._land_link_ops). That is what puts the two machines'
	# frame edges on the same tick of the bus: the bus anchors each one's clock
	# where it stands when the wire is made. Seated at an arbitrary moment, the
	# two would be out of step by however far apart they happened to be.
	if not await _run_to(SEAT_AT, 0):
		_bad("the cores never reached frame %d to be cabled: %s" % [SEAT_AT, _frames()])
		_finish()
		return
	_ok("peer A's Game Boy and printer share a wire",
		_libs[0].LinkConnectGroup([_libs[1]], PackedInt32Array([0, 0])))
	_ok("so do peer B's", _libs[2].LinkConnectGroup([_libs[3]], PackedInt32Array([0, 0])))

	var expected := Image.load_from_file(ProjectSettings.globalize_path(EXPECTED))
	expected.convert(Image.FORMAT_L8)

	for at: int in CHECKPOINTS:
		if not await _run_to(at):
			_bad("the cores stopped short of frame %d: %s" % [at, _frames()])
			break
		var pa := _paper(_libs[1])
		var pb := _paper(_libs[3])
		print("[np-print] frame %d: paper A %s, B %s" % [at, pa.get_size(), pb.get_size()])
		_ok("frame %d: both peers' paper is the same, dot for dot" % at,
			pa.get_size() == pb.get_size() and pa.get_data() == pb.get_data())
		_ok("frame %d: both Game Boys show the same screen" % at,
			_screen(_libs[0]) == _screen(_libs[2]))
		var sa: PackedByteArray = await _save(_libs[1])
		var sb: PackedByteArray = await _save(_libs[3])
		_ok("frame %d: both printers' savestates are the same, byte for byte (%d bytes)"
			% [at, sa.size()], not sa.is_empty() and sa == sb)
		match at:
			950:
				_ok("the print is the picture the ROM sent",
					pa.get_size() == expected.get_size() and pa.get_data() == expected.get_data())
			1050:
				_ok("FEED, as agreed input, is feeding paper on both",
					pa.get_height() > expected.get_height())
			1100:
				_fed_height = pa.get_height()
			1200:
				_ok("TEAR with its count took exactly those lines off both",
					pa.get_height() == _fed_height - TEAR_LINES,
					"%d, want %d" % [pa.get_height(), _fed_height - TEAR_LINES])

	_finish()


var _fed_height := -1


## Post agreed inputs up to `frame` for the printers -- `frame + lead` for the
## Game Boys -- and wait until the printers are held there and the Game Boys have
## stopped moving. `lead` 0 holds every core at the frame (the cable is seated
## that way).
func _run_to(frame: int, lead := 2) -> bool:
	var flat := PackedInt32Array()
	flat.resize(FLAT_SIZE)
	var deadline := Time.get_ticks_msec() + 120000
	while true:
		# Keep a few frames posted ahead, as a session's input delay does, but
		# never past the checkpoint.
		var lowest := frame + lead
		for lib: Node in _libs:
			lowest = mini(lowest, int(lib.GetFrameCount()))
		while _posted_gb < frame + lead and _posted_gb < lowest + 8:
			_post_gb(_posted_gb, flat)
			_posted_gb += 1
		while _posted_pr < frame and _posted_pr < lowest + 8:
			_post_pr(_posted_pr, flat)
			_posted_pr += 1
		var printers_there: bool = int(_libs[1].GetFrameCount()) >= frame 			and int(_libs[3].GetFrameCount()) >= frame
		if printers_there and int(_libs[0].GetFrameCount()) >= frame 				and int(_libs[2].GetFrameCount()) >= frame:
			break
		if Time.get_ticks_msec() > deadline:
			return false
		await get_tree().process_frame
	# Until the Game Boys stand still: each blocks where the held printer's
	# horizon stops it, the same tick on both peers.
	var last := []
	var still := 0
	while still < 6 and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var now := _frames()
		still = still + 1 if now == last else 0
		last = now
	return true


func _post_gb(frame: int, flat: PackedInt32Array) -> void:
	_libs[0].PostNetplayInputs(frame, flat)
	_libs[2].PostNetplayInputs(frame, flat)


func _post_pr(frame: int, flat: PackedInt32Array) -> void:
	var pr := flat.duplicate()
	if frame >= FEED_FROM and frame < FEED_TO:
		pr[0] = BTN_A
	if frame >= TEAR_AT and frame < TEAR_AT + 4:
		pr[0] = BTN_B
		pr[1] = TEAR_LINES
	_libs[1].PostNetplayInputs(frame, pr)
	_libs[3].PostNetplayInputs(frame, pr)


func _paper(lib: Node) -> Image:
	var img: Image = lib.GetVideoImage()
	if img == null:
		return Image.create(1, 1, false, Image.FORMAT_L8)
	img.convert(Image.FORMAT_L8)
	return img


func _screen(lib: Node) -> PackedByteArray:
	var img: Image = lib.GetVideoImage()
	return img.get_data() if img != null else PackedByteArray()


func _save(lib: Node) -> PackedByteArray:
	_state.erase(lib)
	var cb := func(data: PackedByteArray, _frame: int) -> void: _state[lib] = data
	lib.savestate_ready.connect(cb, CONNECT_ONE_SHOT)
	lib.RequestSaveState()
	var deadline := Time.get_ticks_msec() + 5000
	while not _state.has(lib) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return _state.get(lib, PackedByteArray())


func _frames() -> Array:
	var out := []
	for lib: Node in _libs:
		out.append(int(lib.GetFrameCount()))
	return out


func _ok(name: String, cond: bool, detail := "") -> void:
	if cond:
		_pass += 1
		print("[np-print] PASS  %s" % name)
	else:
		_bad(name + ("  — " + detail if not detail.is_empty() else ""))


func _bad(why: String) -> void:
	_fail += 1
	print("[np-print] FAIL  %s" % why)


func _finish() -> void:
	for lib: Node in _libs:
		lib.StopContent()
	for _i in range(60):
		await get_tree().process_frame
	if not _opt_path.is_empty():
		if _had_opt:
			var w := FileAccess.open(_opt_path, FileAccess.WRITE)
			w.store_string(_opt_backup)
			w.close()
		else:
			DirAccess.remove_absolute(_opt_path)
	print("[np-print] ---- %s: %d passed, %d failed ----" % [_core, _pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _write_options(root: String) -> void:
	_opt_path = "%s/core_options/%s.opt" % [root, _core]
	_had_opt = FileAccess.file_exists(_opt_path)
	_opt_backup = FileAccess.get_file_as_string(_opt_path) if _had_opt else ""
	var lines: PackedStringArray = []
	for line in _opt_backup.split("\n", false):
		var keep := true
		for pair: Array in OPTIONS[_core]:
			if line.begins_with(str(pair[0])):
				keep = false
		if keep:
			lines.append(line)
	for pair: Array in OPTIONS[_core]:
		lines.append('%s = "%s"' % [pair[0], pair[1]])
	DirAccess.make_dir_recursive_absolute(_opt_path.get_base_dir())
	var w := FileAccess.open(_opt_path, FileAccess.WRITE)
	w.store_string("\n".join(lines) + "\n")
	w.close()
