## Does mGBA publish the e-Reader's card slot, and only for an e-Reader cartridge?
##
## Needs a real core and a real ROM, so it is a probe. The slot is published two
## ways -- as disk control (for RetroArch) and as an accessory media reader
## (AccessoryMediaInterface.hpp, kind DOT_CODE) -- and an ORDINARY Game Boy
## Advance game must get neither. Publishing unconditionally would give every
## GBA game a disc menu, and that is the mistake this guards.
##
##   godot --headless --path RetroXR res://Tools/cores/ereader_disk_probe.tscn -- \
##     --core=mgba --rom="$HOME/retroxr/roms/game_boy_advance/game.gba" --expect=none
##
## --expect=none  no disk control and no accessory reader  (an ordinary GBA game)
## --expect=disk  disk control and one e-Reader reader     (the e-Reader cart)
##
## With --expect=disk it also hands the reader two files through
## InsertAccessoryMedia: a 10-byte one, which must be refused, and a zero-filled
## strip of a length the reader decodes (2112 bytes), which must be taken, show
## as present, and be gone again once a frame has swiped it. The strip carries no
## card, so this proves the hand-over, not a scan; ereader_scan_probe is the scan.
##
## Exits non-zero when the answer is not the one expected, so it can gate.
extends Node

const KIND_DOT_CODE := 1

var _lib: Node = null
var _core := "mgba"
var _rom := ""
var _root := ""
var _expect := "none"
var _seen := false
var _has_control := false
var _count := 0
var _failed := ""
var _readers: Array = []
var _readers_seen := 0
var _done: Array = []


func _ready() -> void:
	get_tree().create_timer(40.0).timeout.connect(func() -> void:
		print("[edp] FAIL: timed out")
		get_tree().quit(1))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--core="):
			_core = a.substr(7)
		elif a.begins_with("--rom="):
			_rom = a.substr(6)
		elif a.begins_with("--root="):
			_root = a.substr(7)
		elif a.begins_with("--expect="):
			_expect = a.substr(9)
	if _root.is_empty():
		_root = CoreDownloadManager.default_core_root()
	if _rom.is_empty() or not FileAccess.file_exists(_rom):
		print("[edp] FAIL: --rom must name a file that exists (got '%s')" % _rom)
		get_tree().quit(1)
		return

	var lib: Object = ClassDB.instantiate("Libretro")
	_lib = lib as Node
	if _lib == null:
		print("[edp] FAIL: could not instantiate Libretro")
		get_tree().quit(1)
		return
	add_child(_lib)
	_lib.connect("content_load_failed", func(reason: String) -> void:
		_failed = reason)
	_lib.connect("disk_control_ready", _on_disk_control_ready)
	var accessory := _lib.has_signal("accessory_readers_changed")
	if accessory:
		_lib.connect("accessory_readers_changed", _on_readers)
		_lib.connect("accessory_media_done", func(reader: int, inserted: bool, ok: bool) -> void:
			print("[edp] accessory_media_done reader=%d inserted=%s ok=%s" % [reader, inserted, ok])
			_done.append(ok))
	else:
		print("[edp] this libretro-godot has no accessory media interface")

	print("[edp] core=%s expect=%s root=%s" % [_core, _expect, _root])
	print("[edp] rom=%s" % _rom)
	_lib.StartContent(_root, _core, _rom)

	# The core comes up asynchronously; a real one took 34 frames in an earlier
	# probe, so poll rather than sampling once.
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 12000:
		await get_tree().process_frame
		if not _failed.is_empty():
			break
		if _lib.has_method("GetCoreIdentity"):
			var ident: Dictionary = _lib.call("GetCoreIdentity")
			if not ident.is_empty():
				break
	if _failed.is_empty():
		print("[edp] core up: %s" % str(_lib.call("GetCoreIdentity")))
		_lib.RequestDiskInfo()
		var t1 := Time.get_ticks_msec()
		while not _seen and Time.get_ticks_msec() - t1 < 5000:
			await get_tree().process_frame

	var reader_ok := true
	if _failed.is_empty() and accessory:
		reader_ok = await _check_reader()
	_report(reader_ok)


func _on_disk_control_ready(has_control: bool, count: int, index: int, ejected: bool) -> void:
	_seen = true
	_has_control = has_control
	_count = count
	print("[edp] disk_control_ready has=%s images=%d index=%d ejected=%s"
		% [has_control, count, index, ejected])


func _on_readers(readers: Array) -> void:
	_readers = readers
	_readers_seen += 1
	print("[edp] accessory_readers_changed %s" % str(readers))


func _wait_readers(after: int) -> void:
	var t := Time.get_ticks_msec()
	while _readers_seen <= after and Time.get_ticks_msec() - t < 5000:
		await get_tree().process_frame


func _wait_done(count: int) -> void:
	var t := Time.get_ticks_msec()
	while _done.size() < count and Time.get_ticks_msec() - t < 5000:
		await get_tree().process_frame


func _scratch_file(name: String, size: int) -> String:
	var path := OS.get_user_data_dir().path_join(name)
	var f := FileAccess.open(path, FileAccess.WRITE)
	var bytes := PackedByteArray()
	bytes.resize(size)
	f.store_buffer(bytes)
	f.close()
	return path


func _check_reader() -> bool:
	var before := _readers_seen
	_lib.call("RequestAccessoryReaders")
	await _wait_readers(before)
	if _expect != "disk":
		if _readers.is_empty():
			print("[edp] reader PASS: no accessory reader, as an ordinary game should have")
			return true
		print("[edp] reader FAIL: an ordinary game published %s" % str(_readers))
		return false

	if _readers.size() != 1:
		print("[edp] reader FAIL: want one reader, got %s" % str(_readers))
		return false
	var r: Dictionary = _readers[0]
	if int(r.kind) != KIND_DOT_CODE or int(r.port) != -1 or not bool(r.momentary):
		print("[edp] reader FAIL: want a momentary dot-code reader on the console, got %s" % str(r))
		return false

	# Refused: not a strip length.
	var bad := _scratch_file("edp_bad_strip.raw", 10)
	_lib.call("InsertAccessoryMedia", 0, bad)
	await _wait_done(1)
	if _done.size() < 1 or bool(_done[0]):
		print("[edp] reader FAIL: a 10-byte file was not refused (%s)" % str(_done))
		return false

	# Taken, then swiped by the next frame.
	var good := _scratch_file("edp_blank_strip.raw", 2112)
	before = _readers_seen
	_lib.call("InsertAccessoryMedia", 0, good)
	await _wait_done(2)
	await _wait_readers(before)
	if _done.size() < 2 or not bool(_done[1]):
		print("[edp] reader FAIL: a 2112-byte strip was refused (%s)" % str(_done))
		return false
	var present_after_insert := int((_readers[0] as Dictionary).present)
	for i in 10:
		await get_tree().process_frame
	before = _readers_seen
	_lib.call("RequestAccessoryReaders")
	await _wait_readers(before)
	var present_later := int((_readers[0] as Dictionary).present)
	print("[edp] present right after insert=%d, after frames=%d" % [present_after_insert, present_later])
	if present_later != 0:
		print("[edp] reader FAIL: the strip was never swiped")
		return false
	print("[edp] reader PASS: one e-Reader reader, a bad file refused, a strip taken and swiped")
	return true


func _report(reader_ok: bool) -> void:
	if not _failed.is_empty():
		print("[edp] FAIL: content load failed — %s" % _failed)
		get_tree().quit(1)
		return
	if not _seen:
		print("[edp] FAIL: no disk_control_ready answer within 5 s")
		get_tree().quit(1)
		return
	var want := _expect == "disk"
	if _has_control == want and reader_ok:
		print("[edp] PASS: has_control=%s and the reader as %s expects" % [_has_control, _expect])
		get_tree().quit(0)
	else:
		print("[edp] FAIL: has_control=%s reader_ok=%s, --expect=%s" % [_has_control, reader_ok, _expect])
		get_tree().quit(1)
