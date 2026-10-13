## Mystery Gift under the netplay gate — does the infrared port replay?
##
##     python Tools/gs_save.py <a Gold or Silver save> --unlock a.srm
##     python Tools/gs_save.py <a Gold or Silver save> --unlock b.srm --id 12345 --name PROBE
##     "$godot" --headless --path RetroXR res://Tools/netplay/gbc_ir_netplay_probe.tscn -- \
##         "--rom=<Pokemon Gold or Silver>" --save=a.srm --save2=b.srm
##     ... -- ... --mutate     # the control: one replica is fed ONE frame out, and must diverge
##     ... -- ... --one        # only the near machines are fed: they must stop, not run on
##     ... -- ... --core=mgba [--core2=gambatte]
##
## A probe, not a test: real cores built with the port, a real ROM, and a save
## that has been through the Goldenrod Department Store. See
## Tools/link/gbc_ir_probe for what the exchange is and why its outcome can be
## read off the cartridges.
##
## WHAT IT IS FOR. Nothing crosses the network for a link, cable or light: every
## peer in a session runs BOTH machines, and it is determinism that keeps their
## two copies of the pair agreeing. So the question a session asks of this port
## is whether two copies of the same pair, fed the same inputs on the same
## frames, stay identical while the port carries a protocol timed to the tens of
## microseconds -- with two emulation threads a copy, racing each other on
## whatever the scheduler felt like.
##
## So this runs two copies. Four machines, two buses, one process: every frame
## is posted to both copies at once, and each machine's RAM is checksummed every
## thirty frames and compared against its twin. They have to agree at every
## checkpoint, the exchange has to complete in both, and both have to have
## flashed the same number of edges.
##
## One process rather than two runs compared afterwards, because the cartridge
## has a clock: gambatte and mGBA both read the host's time for it, so two runs
## a minute apart disagree before the port is ever touched. Two copies running
## together read the same second. (That clock is its own netplay problem, and
## not this probe's.)
##
## --mutate is what makes the comparison worth anything: the second copy's
## calling press lands one frame later than the first's. If the checksums still
## agreed, they would be agreeing about nothing.
##
## The saves are COPIED into the output folder and the copies are what run; the
## files passed in are only read.
extends Node

const BTN_B := 1 << 0
const BTN_START := 1 << 3
const BTN_DOWN := 1 << 5
const BTN_A := 1 << 8

const RP := 0xFF56
const W_TILEMAP := 0xC3A0
const TILEMAP_SIZE := 360
const S_PARTNER_COUNT := 0xABE5
const S_PARTNER_IDS := 0xABE6
const FILE_TRAINER := 0x2009

const IR_PORT := 1
const CRC_INTERVAL := 30
const FEED_AHEAD := 4
const MAX_AHEAD := 8
const MAX_PRESSES := 5
## The frame the two ports come into view of each other, with every machine
## stopped on it.
##
## Not before the cores start, which is the obvious place and wedges: a bus lines
## its machines up from wherever each first speaks, and four cores starting on
## four threads do not first speak on the same frame. The pair is then held a few
## frames apart by the bus while lockstep hands both the same frame, and neither
## can ever move. A session lands every link change this way for that reason
## (NetplaySession._land_link_ops), and a port coming into view is one.
const JOIN := 12
## Options a session pins for these cores (NetplayCores).
const PINS := {"gambatte": {"gambatte_frame_dupe": "disabled"}, "mgba": {}}

var _cores: Array[String] = ["gambatte", "gambatte"]
var _roms: Array[String] = ["", ""]
var _saves: Array[String] = ["", ""]
var _root := ""
var _out := "res://probe_out/gbc_ir_netplay"
var _mutate := false
var _one := false

## _lib[copy][machine]
var _lib: Array = [[null, null], [null, null]]
var _crc: Array = [[{}, {}], [{}, {}]]
## Per machine: [from_frame, until_frame, mask, copies] -- `copies` is a bit per
## copy, so the control can press on one and not the other.
var _holds: Array = [[], []]
var _posted := 0
var _running := false
## Nothing past this frame is fed until the ports are in view.
var _hold_at := JOIN
var _pass := 0
var _fail := 0


func _ready() -> void:
	get_tree().create_timer(540.0).timeout.connect(func() -> void:
		print("[gbc-ir-np] TIMEOUT")
		get_tree().quit(1))
	await _run()


func _process(_delta: float) -> void:
	if not _running:
		return
	var front := _front()
	while _posted < mini(front + FEED_AHEAD, _hold_at):
		for copy in range(2):
			for machine in range(2):
				if _one and machine == 1:
					continue
				_lib[copy][machine].PostNetplayInputs(_posted, _frame(_mask(copy, machine, _posted)))
		_posted += 1


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--core="):
			_cores = [arg.substr(7), arg.substr(7)]
		elif arg.begins_with("--core2="):
			_cores[1] = arg.substr(8)
		elif arg.begins_with("--rom="):
			_roms = [arg.substr(6), arg.substr(6)]
		elif arg.begins_with("--rom2="):
			_roms[1] = arg.substr(7)
		elif arg.begins_with("--save="):
			_saves[0] = arg.substr(7)
		elif arg.begins_with("--save2="):
			_saves[1] = arg.substr(8)
		elif arg.begins_with("--root="):
			_root = arg.substr(7)
		elif arg.begins_with("--out="):
			_out = arg.substr(6)
		elif arg == "--mutate":
			_mutate = true
		elif arg == "--one":
			_one = true
	if _root.is_empty():
		_root = CoreDownloadManager.default_core_root()
	if _out.begins_with("res://") or _out.begins_with("user://"):
		_out = ProjectSettings.globalize_path(_out)
	DirAccess.make_dir_recursive_absolute(_out)

	for i in range(2):
		if _roms[i].is_empty() or not FileAccess.file_exists(_roms[i]) \
				or _saves[i].is_empty() or not FileAccess.file_exists(_saves[i]):
			print("[gbc-ir-np] SKIP  pass --rom=, --save= and --save2= (see the header)")
			get_tree().quit(0)
			return
		if not FileAccess.file_exists("%s/cores/%s_libretro.dll" % [_root, _cores[i]]) \
				and not FileAccess.file_exists("%s/cores/%s_libretro.so" % [_root, _cores[i]]):
			print("[gbc-ir-np] SKIP  no %s core under %s" % [_cores[i], _root])
			get_tree().quit(0)
			return
	print("[gbc-ir-np] two copies of a %s / %s pair%s" % [_cores[0], _cores[1],
			", the second fed one frame out (control)" if _mutate
			else (", near machines only (control)" if _one else "")])

	var trainers: Array[PackedByteArray] = [_trainer_of(_saves[0]), _trainer_of(_saves[1])]

	for copy in range(2):
		for machine in range(2):
			var lib := Libretro.new()
			add_child(lib)
			_lib[copy][machine] = lib
			var scratch := "%s/copy%d_machine%d.srm" % [_out, copy, machine]
			DirAccess.copy_absolute(_saves[machine], scratch)
			lib.SetSramPath(scratch)
			lib.netplay_crc.connect(func(frame: int, crc: int) -> void:
				_crc[copy][machine][frame] = crc)
			var pins: Dictionary = PINS.get(_cores[machine], {})
			for key: String in pins:
				lib.SetCoreOption(key, str(pins[key]))
			lib.SetNetplayRollback(false, 0, MAX_AHEAD)
			lib.SetNetplayCrcInterval(CRC_INTERVAL)
			lib.SetNetplayMode(true, 1, 0)
	for copy in range(2):
		for machine in range(2):
			_lib[copy][machine].StartContent(_root, _cores[machine], _roms[machine])
	_running = true

	# Every machine to the joining frame and stopped there, then the ports.
	var stopped := await _all_at(JOIN)
	_ok("every machine being fed stops on frame %d" % JOIN, stopped)
	for copy in range(2):
		_ok("copy %d: the two ports come into view on that frame" % copy,
				_lib[copy][0].LinkConnect(_lib[copy][1], IR_PORT, IR_PORT))
	_hold_at = 1 << 30

	if _one:
		await _leg_one()
		return

	await _reach(300)
	for machine in range(2):
		var menu := await _to_main_menu(machine)
		_ok("machine %d reaches a main menu offering MYSTERY GIFT" % machine, menu)
		if not menu:
			_finish()
			return
	for machine in range(2):
		await _tap(machine, BTN_DOWN, 4, 16)
		await _tap(machine, BTN_DOWN, 4, 16)
		await _tap(machine, BTN_DOWN, 4, 16)
		await _tap(machine, BTN_A, 6, 30)
		var listening := await _until(func() -> bool:
			return (_peek(0, machine, RP) & 0xC0) == 0xC0, 900)
		_ok("machine %d switches its receiver on" % machine, listening)
	await _reach(_posted + 60)

	var sent_before := _sent()
	var presses := 0
	var done := false
	while presses < MAX_PRESSES and not done:
		presses += 1
		# The control's whole difference: the same press, a frame later, on the
		# second copy only.
		var at := _posted + 2
		_holds[0].append([at, at + 6, BTN_A, 1])
		_holds[0].append([at + (1 if _mutate else 0), at + 6 + (1 if _mutate else 0), BTN_A, 2])
		done = await _until(func() -> bool:
			return _peek(0, 0, S_PARTNER_COUNT) == 1 and _peek(0, 1, S_PARTNER_COUNT) == 1, 240)
	print("[gbc-ir-np] machine 0 pressed A %d time(s)" % presses)
	await _reach(_posted + 120)

	# Stop feeding and let every machine run out what it has been given, so all
	# four stand on the same frame and every checksum up to it is in.
	_running = false
	await _settle()
	var sent := _sent()

	_ok("the exchange completes in the first copy", done)
	for copy in range(2):
		for machine in range(2):
			var other := 1 - machine
			var got := _read(copy, machine, S_PARTNER_IDS, 2)
			if _mutate and copy == 1:
				continue
			_eq("copy %d machine %d's cartridge holds machine %d's trainer id" % [copy, machine, other],
					got, trainers[other].slice(0, 2))

	# The comparison. Every checkpoint both copies have, on both machines.
	for machine in range(2):
		var frames: Array = _crc[0][machine].keys()
		frames.sort()
		var compared := 0
		var first_bad := -1
		for frame: int in frames:
			if not _crc[1][machine].has(frame):
				continue
			compared += 1
			if _crc[0][machine][frame] != _crc[1][machine][frame] and first_bad < 0:
				first_bad = frame
		var flashed := "flashed %d / %d edges" % [
				sent[0][machine] - sent_before[0][machine], sent[1][machine] - sent_before[1][machine]]
		print("[gbc-ir-np] machine %d: %d checkpoints compared, first difference %s; %s" % [
				machine, compared, "none" if first_bad < 0 else "at frame %d" % first_bad, flashed])
		_ok("machine %d has checkpoints to compare" % machine, compared >= 20, "%d" % compared)
		if _mutate:
			_ok("machine %d: a copy fed one frame out DIVERGES" % machine, first_bad >= 0)
		else:
			_ok("machine %d: the two copies agree at every checkpoint" % machine, first_bad < 0,
					"first difference at frame %d" % first_bad)
			_eq("machine %d flashed the same number of edges in both copies" % machine,
					sent[0][machine] - sent_before[0][machine], sent[1][machine] - sent_before[1][machine])
			_ok("machine %d flashed at all" % machine, sent[0][machine] > sent_before[0][machine])
	_finish()


## Only the near machine of each pair is fed, as a client looked before a session
## knew a link made a group. It must stop where the ports came into view: the bus
## waits for a peer that is behind, and a machine that ran on instead would be a
## pair that desyncs.
func _leg_one() -> void:
	var last := -1
	var still := 0
	for tick in range(1200):
		await get_tree().process_frame
		var f: int = _lib[0][0].GetFrameCount()
		still = still + 1 if f == last else 0
		last = f
		if still > 180:
			break
	_running = false
	print("[gbc-ir-np] near machines reached frame %d / %d and %s" % [
			_lib[0][0].GetFrameCount(), _lib[1][0].GetFrameCount(),
			"stopped" if still > 180 else "KEPT RUNNING"])
	_ok("a machine whose partner is never fed stops and waits", still > 180,
			"reached frame %d" % last)
	_ok("and it stopped within a frame of the ports coming into view", last <= JOIN + 1,
			"frame %d" % last)
	_finish()


func _front() -> int:
	var front := 1 << 30
	for copy in range(2):
		for machine in range(2):
			if _one and machine == 1:
				continue
			front = mini(front, int(_lib[copy][machine].GetFrameCount()))
	return front


func _mask(copy: int, machine: int, frame: int) -> int:
	var mask := 0
	for hold: Array in _holds[machine]:
		if frame >= int(hold[0]) and frame < int(hold[1]) and (int(hold[3]) & (1 << copy)) != 0:
			mask |= int(hold[2])
	return mask


func _frame(buttons: int) -> PackedInt32Array:
	var a := PackedInt32Array()
	a.resize(20)
	a[0] = buttons
	return a


## Press on both copies, starting a couple of frames past anything already posted.
func _tap(machine: int, mask: int, hold: int, gap: int) -> void:
	var at := _posted + 2
	_holds[machine].append([at, at + hold, mask, 3])
	await _reach(at + hold + gap)


func _reach(frame: int) -> void:
	var guard := 40000
	while _front() < frame and guard > 0:
		guard -= 1
		await get_tree().process_frame


func _until(cond: Callable, frames: int) -> bool:
	var target := _front() + frames
	var guard := 40000
	while guard > 0:
		if cond.call():
			return true
		if _front() >= target:
			return false
		guard -= 1
		await get_tree().process_frame
	return false


## Whether every machine that is being fed is standing on `frame`, waiting for
## the next.
func _all_at(frame: int) -> bool:
	for tick in range(3000):
		await get_tree().process_frame
		var there := true
		for copy in range(2):
			for machine in range(2):
				if _one and machine == 1:
					continue
				if int(_lib[copy][machine].GetFrameCount()) != frame:
					there = false
		if there:
			return true
	return false


## Every machine on the frame the feeding stopped at.
func _settle() -> void:
	for tick in range(600):
		await get_tree().process_frame
		var lo := 1 << 30
		var hi := 0
		for copy in range(2):
			for machine in range(2):
				var f: int = _lib[copy][machine].GetFrameCount()
				lo = mini(lo, f)
				hi = maxi(hi, f)
		if lo == hi and lo >= _posted - 1:
			break
	for tick in range(30):
		await get_tree().process_frame


func _sent() -> Array:
	var out := [[0, 0], [0, 0]]
	for copy in range(2):
		for machine in range(2):
			out[copy][machine] = int(_lib[copy][machine].LinkSent(IR_PORT))
	return out


func _to_main_menu(machine: int) -> bool:
	for attempt in range(14):
		if _on_screen(machine, "CONTINUE"):
			break
		await _tap(machine, BTN_START, 6, 0)
		await _until(func() -> bool: return _on_screen(machine, "CONTINUE"), 150)
	await _reach(_posted + 20)
	return _on_screen(machine, "MYSTERY")


## Read off the FIRST copy. What is decided from it is applied to both by frame
## number, so the two are fed the same timeline whatever this saw and whenever.
func _on_screen(machine: int, word: String) -> bool:
	var tiles := _read(0, machine, W_TILEMAP, TILEMAP_SIZE)
	if tiles.is_empty():
		return false
	var want := PackedByteArray()
	for c in word.to_upper():
		want.append(0x80 + (c.unicode_at(0) - 65))
	for at in range(tiles.size() - want.size() + 1):
		if tiles.slice(at, at + want.size()) == want:
			return true
	return false


func _read(copy: int, machine: int, address: int, n: int) -> PackedByteArray:
	var snap: Dictionary = _lib[copy][machine].SnapshotMappedRam()
	var data: PackedByteArray = snap.get("data", PackedByteArray())
	for region: Dictionary in snap.get("regions", []):
		var start: int = region["start"]
		var length: int = region["len"]
		if address >= start and address + n <= start + length:
			var at: int = int(region["offset"]) + (address - start)
			return data.slice(at, at + n)
	return PackedByteArray()


func _peek(copy: int, machine: int, address: int) -> int:
	var got := _read(copy, machine, address, 1)
	return got[0] if got.size() == 1 else -1


func _trainer_of(save_path: String) -> PackedByteArray:
	var f := FileAccess.open(save_path, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	f.seek(FILE_TRAINER)
	return f.get_buffer(2)


func _ok(name: String, cond: bool, detail := "") -> void:
	if cond:
		_pass += 1
		print("[gbc-ir-np] PASS  %s" % name)
	else:
		_fail += 1
		print("[gbc-ir-np] FAIL  %s%s" % [name, "  — " + detail if not detail.is_empty() else ""])


func _eq(name: String, got: Variant, want: Variant) -> void:
	_ok(name, got == want, "got %s, want %s" % [str(got), str(want)])


func _finish() -> void:
	_running = false
	for copy in range(2):
		for machine in range(2):
			_lib[copy][machine].StopContent()
	for tick in range(90):
		await get_tree().process_frame
	print("[gbc-ir-np] ---- %d passed, %d failed ----" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)
