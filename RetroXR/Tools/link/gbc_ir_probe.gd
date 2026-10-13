## Mystery Gift, two Game Boy Colors, no lead — the infrared port carrying a real
## game.
##
##     python Tools/gs_save.py <a Gold or Silver save> --unlock a.srm
##     python Tools/gs_save.py <a Gold or Silver save> --unlock b.srm --id 12345 --name PROBE
##     "$godot" --headless --path RetroXR res://Tools/link/gbc_ir_probe.tscn -- \
##         "--rom=<Pokemon Gold or Silver>" --save=a.srm --save2=b.srm
##     ... -- ... --nolink                      # the control leg: must NOT trade
##     ... -- ... --core=mgba --core2=gambatte  # a unit of each, facing each other
##     ... -- ... --reload                      # each loads a state first
##     ... -- ... --cabled                      # and a link cable between them too
##     ... -- ... --stress=20 [--reload]        # twenty calls: how many are answered
##
## A probe rather than a test: it wants a real core built with the port
## (libretro/link_infrared.cpp in the gambatte fork, gb_ir_netlink.c in mGBA's),
## a real ROM, and a save that has been through the Goldenrod Department Store.
##
## RP, 0xFF56, is an LED and a photodiode. There is no byte to count and no
## handshake to watch: Pokemon flashes the one and times the other against its
## own timer, telling a 0 from a 1 by whether the gap between two flashes is 183
## or 366 microseconds. So there is nothing synthetic worth asserting on -- an
## edge that crosses proves a wire, and only a protocol surviving it proves the
## TIMING, which is the whole of what this port is.
##
## Mystery Gift is that protocol, and it says what it heard. Each machine writes
## its partner's trainer id and name into its own cartridge when the exchange
## completes, in bytes no checksum covers and nothing else touches. So the two
## saves are made to differ in exactly that -- same game, different trainer --
## and each cartridge is read for the OTHER one's. A machine that only ever
## talked to itself cannot have written it.
##
## The saves are WRITTEN: the game stores the gift. Pass scratch copies, never a
## player's own file, and make them afresh for each run -- a pair that has
## already traded is told "only one gift a day per person" and exchanges nothing.
extends Node

const BTN_B := 1 << 0
const BTN_START := 1 << 3
const BTN_DOWN := 1 << 5
const BTN_A := 1 << 8

## pokegold's addresses (pret/pokegold, symbols branch).
const RP := 0xFF56
const H_MG_ROLE := 0xFFBD
const H_MG_STATUS := 0xFFBE
const W_TILEMAP := 0xC3A0
const TILEMAP_SIZE := 360
const S_BACKUP_ITEM := 0xABE4
const S_PARTNER_COUNT := 0xABE5
const S_PARTNER_IDS := 0xABE6
const S_DECORATIONS := 0xABF0
const DECORATION_BYTES := 10
const S_PARTNER_NAME := 0xABFE
## Where the trainer sits in the save FILE: bank 1's sGameData, id then name.
const FILE_TRAINER := 0x2009
const NAME_LENGTH := 11

const MG_OKAY := 0x6C

## The infrared port's link port. The cable is 0.
const IR_PORT := 1

## How often the calling machine will press A before the probe gives up.
const MAX_PRESSES := 5

var _cores: Array[String] = ["gambatte", "gambatte"]
var _roms: Array[String] = ["", ""]
var _saves: Array[String] = ["", ""]
var _root := ""
var _out := "res://probe_out/gbc_ir"
var _linked := true
var _cabled_too := false
var _reload := false
var _stress := 0

var _pass := 0
var _fail := 0
var _m: Array[Libretro] = []
var _shots := 0


func _ready() -> void:
	get_tree().create_timer(420.0).timeout.connect(func() -> void:
		print("[gbc-ir] TIMEOUT")
		get_tree().quit(1))
	await _run()


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
		elif arg == "--nolink":
			_linked = false
		elif arg == "--cabled":
			_cabled_too = true
		elif arg == "--reload":
			_reload = true
		elif arg.begins_with("--stress="):
			_stress = int(arg.substr(9))
	if _root.is_empty():
		_root = CoreDownloadManager.default_core_root()

	for i in range(2):
		if _roms[i].is_empty() or not FileAccess.file_exists(_roms[i]):
			print("[gbc-ir] SKIP  pass --rom=<Pokemon Gold or Silver>")
			get_tree().quit(0)
			return
		if _saves[i].is_empty() or not FileAccess.file_exists(_saves[i]):
			print("[gbc-ir] SKIP  pass --save= and --save2=, scratch copies made by Tools/gs_save.py")
			get_tree().quit(0)
			return
		if not FileAccess.file_exists("%s/cores/%s_libretro.dll" % [_root, _cores[i]]) \
				and not FileAccess.file_exists("%s/cores/%s_libretro.so" % [_root, _cores[i]]):
			print("[gbc-ir] SKIP  no %s core under %s" % [_cores[i], _root])
			get_tree().quit(0)
			return
	print("[gbc-ir] cores %s and %s, %s" % [_cores[0], _cores[1],
			"facing each other" if _linked else "NOT in view of each other (control)"])

	# Who each cartridge belongs to, read from the files before a core has them.
	var trainers: Array[PackedByteArray] = [_trainer_of(_saves[0]), _trainer_of(_saves[1])]
	for i in range(2):
		print("[gbc-ir] machine %d is trainer %05d '%s'" % [i, _id_of(trainers[i]),
				_text(trainers[i].slice(2))])
	_ok("the two cartridges belong to different trainers",
			trainers[0].slice(0, 2) != trainers[1].slice(0, 2))

	for i in range(2):
		var lib := Libretro.new()
		add_child(lib)
		_m.append(lib)
		lib.SetSramPath(_saves[i])

	# In view before either is switched on, and again that is the easy ordering
	# rather than the hard one: the port samples nothing at boot.
	if _linked:
		_ok("the two ports are put in view of each other",
				_m[0].LinkConnect(_m[1], IR_PORT, IR_PORT))
	if _cabled_too:
		# A link cable between the same pair as well. The port goes deaf rather
		# than have a machine wait on two buses at once, so this leg is about
		# nothing freezing; the exchange is expected NOT to happen.
		_ok("and a link cable is seated between them too", _m[0].LinkConnect(_m[1], 0, 0))
	for i in range(2):
		_m[i].StartContent(_root, _cores[i], _roms[i])
	await _frames(240)

	if _linked:
		_eq("machine 0 sees one other unit", _m[0].LinkPeerCount(IR_PORT), 2)
		_eq("machine 1 sees one other unit", _m[1].LinkPeerCount(IR_PORT), 2)
	else:
		_eq("machine 0 sees nobody", _m[0].LinkPeerCount(IR_PORT), 0)
		_eq("machine 1 sees nobody", _m[1].LinkPeerCount(IR_PORT), 0)

	# One machine at a time, to the screen that says "Press A to link IR-Device".
	for i in range(2):
		var menu := await _to_main_menu(i)
		_ok("machine %d reaches a main menu offering MYSTERY GIFT" % i, menu,
				"" if menu else "is Mystery Gift unlocked in %s?" % _saves[i].get_file())
		if not menu:
			await _shot("no_menu")
			_finish()
			return
	await _shot("main_menu")
	for i in range(2):
		await _tap(i, BTN_DOWN, 4, 16)
		await _tap(i, BTN_DOWN, 4, 16)
		await _tap(i, BTN_DOWN, 4, 16)
		await _tap(i, BTN_A, 6, 30)
		# The receiver switched on is the game saying it is listening, and is the
		# one sign of this screen that does not depend on what is drawn.
		var listening := await _until(func() -> bool: return (_peek(i, RP) & 0xC0) == 0xC0, 900)
		_ok("machine %d switches its receiver on" % i, listening,
				"RP reads %02X" % _peek(i, RP))
	await _frames(60)
	await _shot("press_a_to_link")

	if _stress > 0:
		await _stress_run()
		return

	if _reload:
		# A loaded state replaces the machine's clock and its registers behind
		# the port's back, and in mGBA it clears the schedule the port's driver
		# lives on. A driver that does not come back is not merely deaf: it
		# stops publishing, and the OTHER machine waits on it for ever. So each
		# loads its own state here, and everything after has to work anyway.
		for i in range(2):
			_ok("machine %d loads a state it has just saved" % i, await _save_and_load(i))
			await _frames(30)
		_ok("machine 0 runs on after the loads", await _runs(0))
		_ok("machine 1 runs on after the loads", await _runs(1))
	_eq("neither has traded yet (0)", _peek(0, S_PARTNER_COUNT), 0)
	_eq("neither has traded yet (1)", _peek(1, S_PARTNER_COUNT), 0)

	var sent_before := [_m[0].LinkSent(IR_PORT), _m[1].LinkSent(IR_PORT)]
	var cost_before := [_m[0].LinkCost(IR_PORT), _m[1].LinkCost(IR_PORT)]
	var clock := Time.get_ticks_msec()
	var frame_before: int = _m[0].GetFrameCount()

	# Machine 0 calls; machine 1 is already listening and answers. Pressing both
	# would make two senders, which the game does recover from -- each waits a
	# random while and tries again -- but then which one ends up sending is a
	# matter of its random number, and a probe wants one answer.
	#
	# And it calls AGAIN if nothing comes of it, because the game's own greeting
	# can miss, and not for any fault of the port. The listener polls it from a
	# loop a few hundred cycles long and, having seen the caller's first flash,
	# halts until its next timer tick before it looks again -- and that flash
	# lasts 640 cycles. Caught late in its life it is already over at the second
	# look: the listener takes the second flash for the first and waits out its
	# timeout for one that is never sent. The caller waits a random while before
	# it flashes, so which press misses is luck: about one call in six
	# (--stress counts them), with every edge arriving on its tick. A player
	# presses A again, and so does this.
	#
	# The whole exchange is two blocks each way and takes about a second. It is
	# over when both cartridges have been written.
	var presses := 0
	var done := false
	while presses < MAX_PRESSES and not done:
		presses += 1
		await _tap(0, BTN_A, 6, 0)
		done = await _until(func() -> bool:
			return _peek(0, S_PARTNER_COUNT) == 1 and _peek(1, S_PARTNER_COUNT) == 1, 240)
	print("[gbc-ir] machine 0 pressed A %d time(s)" % presses)
	var frames_taken: int = _m[0].GetFrameCount() - frame_before
	var wall := Time.get_ticks_msec() - clock
	await _frames(90)
	await _shot("after")

	for i in range(2):
		var cost: Dictionary = _m[i].LinkCost(IR_PORT)
		print("[gbc-ir] machine %d: status %02X role %d, flashed %d edges, %d rendezvous (%d waited)" % [
				i, _peek(i, H_MG_STATUS), _peek(i, H_MG_ROLE),
				_m[i].LinkSent(IR_PORT) - sent_before[i],
				int(cost.get("advance_calls", 0)) - int(cost_before[i].get("advance_calls", 0)),
				int(cost.get("advance_waits", 0)) - int(cost_before[i].get("advance_waits", 0))])
	print("[gbc-ir] %d emulated frames in %d ms of wall clock (%.2fx real time)" % [
			frames_taken, wall, (frames_taken / 59.7275) / maxf(wall / 1000.0, 0.001)])

	if _linked and not _cabled_too:
		_ok("the exchange completes on both machines", done, "after %d presses" % presses)
		for i in range(2):
			var other := 1 - i
			_eq("machine %d records one partner today" % i, _peek(i, S_PARTNER_COUNT), 1)
			_eq("machine %d's cartridge holds machine %d's trainer id" % [i, other],
					_read(i, S_PARTNER_IDS, 2), trainers[other].slice(0, 2))
			_eq("machine %d's cartridge holds machine %d's name" % [i, other],
					_text(_read(i, S_PARTNER_NAME, NAME_LENGTH)), _text(trainers[other].slice(2)))
			# An item waits at the counter; a decoration goes straight home and
			# is only ticked off. Which one arrives is the partner's to choose.
			var decorations := _read(i, S_DECORATIONS, DECORATION_BYTES)
			_ok("machine %d was given an item or a decoration" % i,
					_peek(i, S_BACKUP_ITEM) != 0 or decorations.count(0) != decorations.size(),
					"item %02X, decorations %s" % [_peek(i, S_BACKUP_ITEM), decorations.hex_encode()])
		_ok("both units flashed", _m[0].LinkSent(IR_PORT) > sent_before[0]
				and _m[1].LinkSent(IR_PORT) > sent_before[1])
	else:
		# The control. Same cartridges, same buttons, and either nobody in view
		# or a receiver made deaf by the cable: the calling machine flashes into
		# the dark and nothing may be written anywhere.
		var why := "while the cable carries the other machine" if _cabled_too else "with nobody in view"
		_ok("nothing completes %s" % why, not done)
		_eq("machine 0's cartridge is untouched", _peek(0, S_PARTNER_COUNT), 0)
		_eq("machine 1's cartridge is untouched", _peek(1, S_PARTNER_COUNT), 0)
		_ok("machine 0 was not left frozen", await _runs(0))
		_ok("machine 1 was not left frozen", await _runs(1))

	# Out of the screen the way a player leaves it, so the receiver goes off.
	for i in range(2):
		await _tap(i, BTN_A, 6, 40)
		await _tap(i, BTN_B, 6, 40)
		await _tap(i, BTN_B, 6, 40)
	await _frames(120)
	await _shot("left")

	for lib in _m:
		lib.StopContent()
	await _frames(120)
	_finish()


## --stress=N: call N times and count the greetings that are answered.
##
## One exchange says the port works; it cannot say how OFTEN the game's own
## greeting misses, and that is the number that tells a port losing flashes
## from a game that was always a little unlucky. An answer is the listening
## machine flashing back within a few frames of the call. After the first
## exchange the game refuses a second gift from the same trainer, but only once
## the whole conversation has been had, so every call after it is as good a
## measurement as the first.
##
## With --reload each machine loads a state it has just saved before every
## call, which is what rollback does to a machine all day.
func _stress_run() -> void:
	var answered := 0
	var made := 0
	for n in range(_stress):
		var ready := true
		for i in range(2):
			if not await _enter_mystery_gift(i):
				ready = false
		if not ready:
			print("[gbc-ir] call %d: could not get both machines back to the prompt" % n)
			break
		await _frames(30)
		if _reload:
			for i in range(2):
				if not await _save_and_load(i):
					ready = false
				await _frames(20)
			if not ready:
				print("[gbc-ir] call %d: a state would not load" % n)
				break
		var before: int = _m[1].LinkSent(IR_PORT)
		await _tap(0, BTN_A, 6, 0)
		made += 1
		# The caller waits up to 27 ms at random, greets for 3, and the listener
		# answers 2 ms after that: three frames at the outside.
		var heard := await _until(func() -> bool: return _m[1].LinkSent(IR_PORT) > before, 40)
		if heard:
			answered += 1
			# Both receivers go off when the conversation is over.
			await _until(func() -> bool:
				return (_peek(0, RP) & 0xC0) == 0 and (_peek(1, RP) & 0xC0) == 0, 600)
			await _frames(30)
		else:
			await _frames(40)
	print("[gbc-ir] %d of %d greetings answered%s" % [answered, made,
			" (a state loaded on each machine before every call)" if _reload else ""])
	_ok("every call was made", made == _stress, "%d of %d" % [made, _stress])
	_ok("most greetings are answered", answered * 4 >= made * 3, "%d of %d" % [answered, made])
	_ok("machine 0 was not left frozen", await _runs(0))
	_ok("machine 1 was not left frozen", await _runs(1))
	for lib in _m:
		lib.StopContent()
	await _frames(120)
	_finish()


## Back to "Press A to link IR-Device" from wherever the last call left the
## machine: at the prompt already, or behind a message that A dismisses to the
## main menu.
func _enter_mystery_gift(index: int) -> bool:
	for attempt in range(8):
		if (_peek(index, RP) & 0xC0) == 0xC0:
			return true
		if _on_screen(index, "CONTINUE"):
			break
		await _tap(index, BTN_A, 6, 50)
	if (_peek(index, RP) & 0xC0) == 0xC0:
		return true
	if not _on_screen(index, "MYSTERY"):
		return false
	await _frames(20)
	for n in range(3):
		await _tap(index, BTN_DOWN, 4, 16)
	await _tap(index, BTN_A, 6, 30)
	return await _until(func() -> bool: return (_peek(index, RP) & 0xC0) == 0xC0, 900)


## START until the main menu is drawn, then say whether it offers Mystery Gift.
##
## START and not A: it leaves the intro and the title screen exactly as A does,
## and the main menu ignores it, so one press too many is harmless where an A
## would have picked CONTINUE and walked into the game.
func _to_main_menu(index: int) -> bool:
	for attempt in range(14):
		if _on_screen(index, "CONTINUE"):
			break
		await _tap(index, BTN_START, 6, 0)
		await _until(func() -> bool: return _on_screen(index, "CONTINUE"), 150)
	await _frames(20)
	return _on_screen(index, "MYSTERY")


## Whether `word` is on this machine's screen, read from the game's own tilemap.
func _on_screen(index: int, word: String) -> bool:
	var tiles := _read(index, W_TILEMAP, TILEMAP_SIZE)
	if tiles.is_empty():
		return false
	var want := PackedByteArray()
	for c in word.to_upper():
		want.append(0x80 + (c.unicode_at(0) - 65))
	for at in range(tiles.size() - want.size() + 1):
		if tiles.slice(at, at + want.size()) == want:
			return true
	return false


## Save a state and load it straight back, as a player reaching for a
## savestate does.
func _save_and_load(index: int) -> bool:
	var lib := _m[index]
	lib.RequestSaveState()
	var saved: Array = await lib.savestate_ready
	var data: PackedByteArray = saved[0]
	if data.is_empty():
		return false
	await _frames(10)
	lib.RequestLoadState(data, int(saved[1]))
	var loaded: Variant = await lib.savestate_loaded
	return bool(loaded)


## Whether a machine is still running: its frame counter has to move.
func _runs(index: int) -> bool:
	var was: int = _m[index].GetFrameCount()
	for i in range(240):
		await get_tree().process_frame
		if _m[index].GetFrameCount() > was + 5:
			return true
	return false


## `n` bytes of a machine's address space, through the map its core declared.
##
## Read while the core runs, which is a race for anything that moves. These are
## bytes that are written once and then left, and are read after they settle.
func _read(index: int, address: int, n: int) -> PackedByteArray:
	var snap: Dictionary = _m[index].SnapshotMappedRam()
	var data: PackedByteArray = snap.get("data", PackedByteArray())
	for region: Dictionary in snap.get("regions", []):
		var start: int = region["start"]
		var length: int = region["len"]
		if address >= start and address + n <= start + length:
			var at: int = int(region["offset"]) + (address - start)
			return data.slice(at, at + n)
	return PackedByteArray()


func _peek(index: int, address: int) -> int:
	var got := _read(index, address, 1)
	return got[0] if got.size() == 1 else -1


func _trainer_of(save_path: String) -> PackedByteArray:
	var f := FileAccess.open(save_path, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	f.seek(FILE_TRAINER)
	return f.get_buffer(2 + NAME_LENGTH)


func _id_of(trainer: PackedByteArray) -> int:
	return (trainer[0] << 8) | trainer[1] if trainer.size() >= 2 else -1


## The game's text, as far as its terminator. Letters and digits are all a
## trainer's name is made of; anything else shows as '?'.
func _text(raw: PackedByteArray) -> String:
	var out := ""
	for b in raw:
		if b == 0x50:
			break
		if b >= 0x80 and b <= 0x99:
			out += char(65 + b - 0x80)
		elif b >= 0xA0 and b <= 0xB9:
			out += char(97 + b - 0xA0)
		elif b >= 0xF6:
			out += char(48 + b - 0xF6)
		elif b == 0x7F:
			out += " "
		else:
			out += "?"
	return out


func _tap(index: int, mask: int, press_frames: int, gap_frames: int) -> void:
	_m[index].SetJoypadState(0, mask, 0, 0, 0, 0)
	await _frames(press_frames)
	_m[index].SetJoypadState(0, 0, 0, 0, 0, 0)
	await _frames(gap_frames)


## Wait `n` frames of EMULATED time on machine 0: see gb_tetris_link_probe.
func _frames(n: int) -> void:
	var target: int = _m[0].GetFrameCount() + n
	var guard := n * 40 + 400
	while _m[0].GetFrameCount() < target and guard > 0:
		guard -= 1
		await get_tree().process_frame


## Wait until `cond` holds, or `frames` of emulated time have gone by.
func _until(cond: Callable, frames: int) -> bool:
	var target: int = _m[0].GetFrameCount() + frames
	var guard := frames * 40 + 400
	while guard > 0:
		if cond.call():
			return true
		if _m[0].GetFrameCount() >= target:
			return false
		guard -= 1
		await get_tree().process_frame
	return false


## Both screens, side by side, into one PNG.
func _shot(name: String) -> void:
	var a := _m[0].GetVideoImage()
	var b := _m[1].GetVideoImage()
	if a == null or b == null or a.is_empty() or b.is_empty():
		print("[gbc-ir] shot %s: no picture" % name)
		return
	if a.get_format() != Image.FORMAT_RGBA8:
		a = a.duplicate()
		a.convert(Image.FORMAT_RGBA8)
	if b.get_format() != Image.FORMAT_RGBA8 or b.get_size() != a.get_size():
		b = b.duplicate()
		b.convert(Image.FORMAT_RGBA8)
		if b.get_size() != a.get_size():
			b.resize(a.get_width(), a.get_height(), Image.INTERPOLATE_NEAREST)
	var w := a.get_width()
	var h := a.get_height()
	var pair := Image.create_empty(w * 2 + 8, h, false, Image.FORMAT_RGBA8)
	pair.fill(Color(0.1, 0.1, 0.12))
	pair.blit_rect(a, Rect2i(0, 0, w, h), Vector2i(0, 0))
	pair.blit_rect(b, Rect2i(0, 0, w, h), Vector2i(w + 8, 0))
	var dir := _out
	if dir.begins_with("res://") or dir.begins_with("user://"):
		dir = ProjectSettings.globalize_path(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	_shots += 1
	pair.save_png("%s/%02d_%s.png" % [dir, _shots, name])
	print("[gbc-ir] shot %s" % name)


func _ok(name: String, cond: bool, detail := "") -> void:
	if cond:
		_pass += 1
		print("[gbc-ir] PASS  %s" % name)
	else:
		_fail += 1
		print("[gbc-ir] FAIL  %s%s" % [name, "  — " + detail if not detail.is_empty() else ""])


func _eq(name: String, got: Variant, want: Variant) -> void:
	_ok(name, got == want, "got %s, want %s" % [str(got), str(want)])


func _finish() -> void:
	print("[gbc-ir] ---- %d passed, %d failed ----" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)
