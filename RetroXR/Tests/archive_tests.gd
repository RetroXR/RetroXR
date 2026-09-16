## archive_tests — RommArchiveExtractor, the bounded-memory ZIP reader behind
## every RomM download.
##
## The five C++ GDExtensions had no self-checking coverage of any kind. This one
## is the one that can have it: it needs no display, no codec, no core and no
## server, so it can gate a commit the way the GDScript suites do. The other
## four are display- or hardware-bound and stay probes.
##
## Every fixture is built here at run time under user://, the way mod_tests
## builds its own, so the suite carries no binary and depends on nothing a
## player has installed.
##
##   "$godot" --headless --path RetroXR res://Tests/archive_tests.tscn
##   "$godot" --headless --path RetroXR res://Tests/archive_tests.tscn -- --only=corrupt
extends Node

## Scratch root. Removed at both ends, so a crashed run cannot leave a fixture
## behind that the next run reads as a real archive.
const WORK := "user://__archive_selftest"

var _passed := 0
var _failed := 0
var _only := ""


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.substr("--only=".length())
	# A suite that hangs reports nothing at all, so bound it.
	# Clean BEFORE quitting: a suite that dies on its watchdog would otherwise
	# leave its fixture archives under user://, and the next run reads whatever
	# is there as if it had just built it.
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		push_error("[archive] TIMEOUT")
		_clean()
		get_tree().quit(1))

	_clean()
	DirAccess.make_dir_recursive_absolute(WORK)

	_group_good()
	_group_plan()
	_group_corrupt()
	_group_cancel()
	await _group_firmware()
	_group_pack()

	_clean()
	print("[archive] %d checks, %d failed" % [_passed + _failed, _failed])
	print("[archive] RESULT=%s" % ("PASS" if _failed == 0 else "FAIL"))
	get_tree().quit(1 if _failed > 0 else 0)


# ── Harness ───────────────────────────────────────────────────────────────────
# Same argument order as every other suite: the thing under test first, the
# description last.

func _ok(cond: bool, what: String, detail := "") -> void:
	if not _wanted(what):
		return
	if cond:
		_passed += 1
		print("[archive] ok   %s" % what)
	else:
		_failed += 1
		print("[archive] FAIL %s%s" % [what, "" if detail.is_empty() else "  -- " + detail])


func _eq(got: Variant, want: Variant, what: String) -> void:
	_ok(got == want, what, "got %s, want %s" % [got, want])


## Group filter, matched on the name's leading "group/" the way the other
## suites do it.
func _wanted(what: String) -> bool:
	return _only.is_empty() or what.begins_with(_only)


func _clean() -> void:
	_remove_tree(WORK)


## Recursive, because firmware/ unpacks a directory tree.
func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for f: String in dir.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	for d: String in dir.get_directories():
		_remove_tree(path.path_join(d))
	DirAccess.remove_absolute(path)


# ── Fixtures ──────────────────────────────────────────────────────────────────

## A real archive, written by the engine's own writer so the bytes are a ZIP a
## third party produced rather than one shaped to match the reader.
func _write_zip(name: String, members: Dictionary) -> String:
	var path := WORK.path_join(name)
	var packer := ZIPPacker.new()
	if packer.open(path) != OK:
		push_error("[archive] could not open %s for writing" % path)
		return ""
	for member: String in members:
		packer.start_file(member)
		packer.write_file(members[member])
		packer.close_file()
	packer.close()
	return path


func _read_bytes(path: String) -> PackedByteArray:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_buffer(f.get_length()) if f != null else PackedByteArray()


func _write_bytes(path: String, bytes: PackedByteArray) -> String:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[archive] could not write %s" % path)
		return ""
	f.store_buffer(bytes)
	f.close()
	return path


func _plan(entry: String, out_name: String) -> Array:
	return [{
		"entry": entry,
		"path": WORK.path_join(out_name),
		"relative": out_name,
	}]


func _text(s: String) -> PackedByteArray:
	return s.to_utf8_buffer()


# ── good/ — a well-formed archive ─────────────────────────────────────────────

func _group_good() -> void:
	var body := _text("The quick brown fox jumps over the lazy dog. ".repeat(40))
	var zip := _write_zip("good.zip", {"rom.nes": body, "notes.txt": _text("hello")})
	var ex: Object = ClassDB.instantiate("RommArchiveExtractor")

	# inspect answers without writing anything: the caller uses it to size a
	# download before committing to it.
	var seen: Dictionary = ex.inspect(zip, _plan("rom.nes", "rom.nes"))
	_ok(bool(seen["ok"]), "good/inspect accepts a well-formed archive", str(seen["error"]))
	_eq(int(seen["total_size"]), body.size(), "good/inspect reports the uncompressed size")
	_ok(not FileAccess.file_exists(WORK.path_join("rom.nes")),
		"good/inspect writes nothing")

	var got: Dictionary = ex.extract(zip, _plan("rom.nes", "rom.nes"))
	_ok(bool(got["ok"]), "good/extract accepts a well-formed archive", str(got["error"]))
	_eq(_read_bytes(WORK.path_join("rom.nes")), body,
		"good/the extracted member is byte-for-byte the original")
	_eq((got["files"] as Array).size(), 1, "good/one planned member yields one file")

	# Two members in one call, which is what a multi-disc download does.
	var both: Array = _plan("rom.nes", "a.nes") + _plan("notes.txt", "b.txt")
	var pair: Dictionary = ex.extract(zip, both)
	_ok(bool(pair["ok"]), "good/extracts two members in one call", str(pair["error"]))
	_eq(_read_bytes(WORK.path_join("b.txt")), _text("hello"),
		"good/the second member is intact too")

	# The staged .part files are an implementation detail that must not survive.
	var leftovers := 0
	for f: String in DirAccess.open(WORK).get_files():
		if f.ends_with(".part"):
			leftovers += 1
	_eq(leftovers, 0, "good/no staging file is left behind")


# ── plan/ — the caller's request is validated before any I/O ──────────────────

func _group_plan() -> void:
	var zip := _write_zip("plan.zip", {"rom.nes": _text("data"), "other.nes": _text("x")})
	var ex: Object = ClassDB.instantiate("RommArchiveExtractor")

	_ok(not bool((ex.extract(zip, []) as Dictionary)["ok"]),
		"plan/an empty plan is refused")
	_ok(not bool((ex.extract(zip, ["not a dictionary"]) as Dictionary)["ok"]),
		"plan/a non-dictionary entry is refused")
	_ok(not bool((ex.extract(zip, [{"entry": "rom.nes"}]) as Dictionary)["ok"]),
		"plan/an entry missing path and relative is refused")
	_ok(not bool((ex.extract(zip, [{
			"entry": "", "path": WORK.path_join("e"), "relative": "e"}]) as Dictionary)["ok"]),
		"plan/an empty member name is refused")
	_ok(not bool((ex.extract(zip, _plan("absent.nes", "absent.nes")) as Dictionary)["ok"]),
		"plan/a member the archive does not hold is refused")

	# The same member twice, and two members onto one path: both would make the
	# result depend on which write landed last.
	var twice: Array = _plan("rom.nes", "dup_a.nes") + _plan("rom.nes", "dup_b.nes")
	_ok(not bool((ex.extract(zip, twice) as Dictionary)["ok"]),
		"plan/the same member requested twice is refused")
	var collide: Array = _plan("rom.nes", "same.nes") + _plan("other.nes", "same.nes")
	_ok(not bool((ex.extract(zip, collide) as Dictionary)["ok"]),
		"plan/two members onto one output path is refused")

	# A refused plan must not have written any of it. The name is unique to this
	# group on purpose: good/ extracts to a.nes, and reusing it here would check
	# that group's leftover rather than anything this one did.
	_ok(not FileAccess.file_exists(WORK.path_join("dup_a.nes")),
		"plan/a refused plan leaves no partial output")


# ── corrupt/ — a damaged or lying archive ─────────────────────────────────────

func _group_corrupt() -> void:
	var body := _text("payload bytes, long enough to deflate. ".repeat(30))
	var zip := _write_zip("corrupt.zip", {"rom.nes": body})
	var raw := _read_bytes(zip)
	var ex: Object = ClassDB.instantiate("RommArchiveExtractor")

	# Truncated: the central directory footer is at the END, so lopping the tail
	# is what a half-finished download actually looks like.
	var cut := raw.slice(0, raw.size() - 32)
	var cut_path := _write_bytes(WORK.path_join("truncated.zip"), cut)
	var cut_res: Dictionary = ex.extract(cut_path, _plan("rom.nes", "t.nes"))
	_ok(not bool(cut_res["ok"]), "corrupt/a truncated archive is refused")
	_ok(not FileAccess.file_exists(WORK.path_join("t.nes")),
		"corrupt/a truncated archive leaves no output")

	# Not a ZIP at all.
	var junk := _write_bytes(WORK.path_join("junk.zip"), _text("this is not a zip file"))
	_ok(not bool((ex.extract(junk, _plan("rom.nes", "j.nes")) as Dictionary)["ok"]),
		"corrupt/a file that is not a ZIP is refused")

	# Missing entirely.
	_ok(not bool((ex.extract(WORK.path_join("nope.zip"),
			_plan("rom.nes", "n.nes")) as Dictionary)["ok"]),
		"corrupt/a missing archive is refused")

	# Damaged payload: the deflate stream no longer decodes to the declared
	# length, which is what a corrupted download looks like.
	var flipped := raw.duplicate()
	var start := 30  # past the local header for a short member name
	for i in range(start, mini(start + 24, flipped.size())):
		flipped[i] = flipped[i] ^ 0xFF
	var bad_path := _write_bytes(WORK.path_join("damaged.zip"), flipped)
	var bad: Dictionary = ex.extract(bad_path, _plan("rom.nes", "c.nes"))
	_ok(not bool(bad["ok"]), "corrupt/a member with damaged payload bytes is refused")
	_ok(not FileAccess.file_exists(WORK.path_join("c.nes")),
		"corrupt/a damaged member promotes nothing into place")

	# And the CRC check on its own. Corrupting the DECLARED crc rather than the
	# data leaves a member that inflates perfectly and to exactly the right
	# length, so every other guard passes and only the checksum can object.
	# Written this way deliberately: damaging the payload instead never reaches
	# the CRC comparison — the size check fires first, and a test that flipped
	# data bytes went on passing with the CRC check compiled out.
	var lied := raw.duplicate()
	var cd := _find_central_directory(lied)
	_ok(cd >= 0, "corrupt/the fixture has a central directory to edit")
	if cd >= 0:
		# crc32 sits at +16 in a central directory entry.
		for b in range(4):
			lied[cd + 16 + b] = lied[cd + 16 + b] ^ 0xFF
		var lied_path := _write_bytes(WORK.path_join("badcrc.zip"), lied)
		var crc_res: Dictionary = ex.extract(lied_path, _plan("rom.nes", "crc.nes"))
		_ok(not bool(crc_res["ok"]),
			"corrupt/a member whose bytes do not match its declared CRC is refused",
			str(crc_res["error"]))
		_ok(not FileAccess.file_exists(WORK.path_join("crc.nes")),
			"corrupt/a CRC failure promotes nothing into place")

	# STORED members, where the extractor's own CRC comparison is the only thing
	# checking the bytes. A correct one must extract; a lying one must not.
	var stored_body := _text("stored payload, not deflated")
	var right := _write_stored_zip("stored_ok.zip", "s.bin", stored_body,
		_crc32(stored_body))
	var stored_res: Dictionary = ex.extract(right, _plan("s.bin", "s_ok.bin"))
	_ok(bool(stored_res["ok"]), "corrupt/an uncompressed member extracts",
		str(stored_res["error"]))
	_eq(_read_bytes(WORK.path_join("s_ok.bin")), stored_body,
		"corrupt/and an uncompressed member arrives intact")

	var wrong := _write_stored_zip("stored_bad.zip", "s.bin", stored_body,
		_crc32(stored_body) ^ 0xFFFF)
	var wrong_res: Dictionary = ex.extract(wrong, _plan("s.bin", "s_bad.bin"))
	_ok(not bool(wrong_res["ok"]),
		"corrupt/an uncompressed member with a wrong declared CRC is refused")
	_ok(not FileAccess.file_exists(WORK.path_join("s_bad.bin")),
		"corrupt/and promotes nothing into place")


## A one-member STORED archive, built by hand.
##
## ZIPPacker always deflates, and for a deflated member the declared CRC is fed
## to StreamPeerGZIP as a gzip trailer — so a wrong CRC fails inside
## decompression and the extractor's own crc comparison is never reached. Only
## a STORED member exercises that comparison, and METHOD_STORED is a path the
## reader supports and nothing else here covers.
##
## `crc` is passed in so the caller can declare a deliberately wrong one.
func _write_stored_zip(name: String, member: String, body: PackedByteArray,
		crc: int) -> String:
	var n := member.to_utf8_buffer()
	var local := PackedByteArray()
	_put32(local, 0x04034b50)
	_put16(local, 20)      # version needed
	_put16(local, 0)       # flags
	_put16(local, 0)       # method 0 = stored
	_put16(local, 0)       # mod time
	_put16(local, 0)       # mod date
	_put32(local, crc)
	_put32(local, body.size())
	_put32(local, body.size())
	_put16(local, n.size())
	_put16(local, 0)       # extra length
	local.append_array(n)
	local.append_array(body)

	var central := PackedByteArray()
	_put32(central, 0x02014b50)
	_put16(central, 20)    # version made by
	_put16(central, 20)    # version needed
	_put16(central, 0)
	_put16(central, 0)     # method 0 = stored
	_put16(central, 0)
	_put16(central, 0)
	_put32(central, crc)
	_put32(central, body.size())
	_put32(central, body.size())
	_put16(central, n.size())
	_put16(central, 0)     # extra
	_put16(central, 0)     # comment
	_put16(central, 0)     # disk
	_put16(central, 0)     # internal attrs
	_put32(central, 0)     # external attrs
	_put32(central, 0)     # local header offset
	central.append_array(n)

	var eocd := PackedByteArray()
	_put32(eocd, 0x06054b50)
	_put16(eocd, 0)
	_put16(eocd, 0)
	_put16(eocd, 1)
	_put16(eocd, 1)
	_put32(eocd, central.size())
	_put32(eocd, local.size())
	_put16(eocd, 0)

	var all := PackedByteArray()
	all.append_array(local)
	all.append_array(central)
	all.append_array(eocd)
	return _write_bytes(WORK.path_join(name), all)


func _put16(buf: PackedByteArray, v: int) -> void:
	buf.append(v & 0xFF)
	buf.append((v >> 8) & 0xFF)


func _put32(buf: PackedByteArray, v: int) -> void:
	for shift in [0, 8, 16, 24]:
		buf.append((v >> shift) & 0xFF)


## CRC-32 as ZIP uses it, so a fixture can declare the RIGHT checksum and the
## suite is asserting the extractor's arithmetic rather than its own.
func _crc32(bytes: PackedByteArray) -> int:
	var crc := 0xFFFFFFFF
	for b: int in bytes:
		crc ^= b
		for _bit in range(8):
			crc = (crc >> 1) ^ 0xEDB88320 if (crc & 1) else (crc >> 1)
	return crc ^ 0xFFFFFFFF


## Offset of the first central directory entry (signature 0x02014b50), or -1.
func _find_central_directory(bytes: PackedByteArray) -> int:
	for i in range(bytes.size() - 4):
		if bytes[i] == 0x50 and bytes[i + 1] == 0x4b 				and bytes[i + 2] == 0x01 and bytes[i + 3] == 0x02:
			return i
	return -1


# ── cancel/ — the caller can stop a long extraction ───────────────────────────

func _group_cancel() -> void:
	var zip := _write_zip("cancel.zip", {"rom.nes": _text("x".repeat(2048))})
	var ex: Object = ClassDB.instantiate("RommArchiveExtractor")
	ex.request_cancel()

	var res: Dictionary = ex.extract(zip, _plan("rom.nes", "cancelled.nes"))
	_ok(not bool(res["ok"]), "cancel/a cancelled extraction does not succeed")
	_ok(bool(res["cancelled"]), "cancel/and says it was cancelled rather than failed")
	_ok(not FileAccess.file_exists(WORK.path_join("cancelled.nes")),
		"cancel/a cancelled extraction leaves no output")

	var seen: Dictionary = ex.inspect(zip, _plan("rom.nes", "cancelled.nes"))
	_ok(bool(seen["cancelled"]), "cancel/inspect reports the cancellation too")


# ── firmware/ — FirmwareInstaller unpacking a support archive ─────────────────
# The BIOS / Extras tab's archive button used ZIPReader.read_file per member,
# which walks the central directory from the top each time. Dolphin.zip, the
# Wii's required download, is 2,720 members and took 26 s on a desktop that way
# with nothing moving on screen.

const FW_DIRS := 60
const FW_HALF_DIRS := 30
const FW_PER_DIR := 50
## Full-fixture unpack time over half-fixture time. The extractor measures 2.0;
## a ZIPReader.read_file loop measures 3.2-3.6.
const FW_MAX_SCALING := 2.5


func _fw_members(dirs: int) -> Dictionary:
	var members := {"sys/top.txt": _text("fresh")}
	for d in range(dirs):
		for i in range(FW_PER_DIR):
			members["sys/d%02d/f%03d.bin" % [d, i]] = _text("member %d/%d" % [d, i])
	return members


func _group_firmware() -> void:
	var members := _fw_members(FW_DIRS)
	var zip := _write_zip("fw.zip", members)
	var half_members := _fw_members(FW_HALF_DIRS)
	var half_zip := _write_zip("fw_half.zip", half_members)
	var dest := WORK.path_join("system")
	DirAccess.make_dir_recursive_absolute(dest.path_join("sys"))
	_write_bytes(dest.path_join("sys/top.txt"), _text("stale"))

	var fw := FirmwareInstaller.new()
	var half_started := Time.get_ticks_msec()
	fw._extract_preserving_paths("fw", half_zip, WORK.path_join("system_half"))
	var half_elapsed := maxi(Time.get_ticks_msec() - half_started, 1)
	await get_tree().process_frame

	var reports: Array[Vector2i] = []
	fw.job_unpacking.connect(func(_k: String, done: int, total: int) -> void:
		reports.append(Vector2i(done, total)))

	var started := Time.get_ticks_msec()
	var res: Dictionary = fw._extract_preserving_paths("fw", zip, dest)
	var elapsed := Time.get_ticks_msec() - started
	_ok(bool(res["ok"]), "firmware/a many-member archive unpacks", str(res.get("error", "")))
	_ok(float(elapsed) / half_elapsed < FW_MAX_SCALING, "firmware/and in time linear in its members",
		"%d members took %d ms, %d took %d ms" % [members.size(), elapsed, half_members.size(), half_elapsed])

	var missing := 0
	for m: String in members:
		if _read_bytes(dest.path_join(m)) != members[m]:
			missing += 1
	_eq(missing, 0, "firmware/every member arrives at its own path, intact")
	_eq(_read_bytes(dest.path_join("sys/top.txt")), _text("fresh"),
		"firmware/a file already installed is replaced, which is how a repair works")
	_ok(not DirAccess.dir_exists_absolute(WORK.path_join("fw.unpack")),
		"firmware/no scratch tree is left behind")

	await get_tree().process_frame
	_ok(reports.size() > 2, "firmware/progress is reported during the unpack, not only at the end",
		"%d reports" % reports.size())
	_eq(reports.back() if not reports.is_empty() else Vector2i(), Vector2i(members.size(), members.size()),
		"firmware/and the last report is every member")

	# A cancel raised while the download was finishing must not install anything.
	var cancel_zip := _write_zip("fw_cancel.zip", {"sys/cancelled.txt": _text("no")})
	fw._abort = true
	var cancelled: Dictionary = fw._extract_preserving_paths("fw", cancel_zip, dest)
	fw._abort = false
	_ok(bool(cancelled.get("cancelled", false)), "firmware/a cancelled unpack says so")
	_ok(not FileAccess.file_exists(dest.path_join("sys/cancelled.txt")),
		"firmware/and installs nothing")
	_ok(not DirAccess.dir_exists_absolute(WORK.path_join("fw_cancel.unpack")),
		"firmware/and leaves no scratch tree")

	var evil_zip := _write_zip("fw_evil.zip", {"../escaped.txt": _text("out")})
	var evil: Dictionary = fw._extract_preserving_paths("fw", evil_zip, dest)
	_ok(not bool(evil["ok"]), "firmware/a member naming a path outside the system dir is refused")
	_ok(not FileAccess.file_exists(WORK.path_join("escaped.txt")),
		"firmware/and writes nothing outside it")

	fw.free()


# ── pack/ — a download from its own host, unpacked to where the core reads ─────
# The Voice Recognition Unit's speech pack: Vosk publishes each zip with its own
# top folder, and the mupen64plus_next fork reads <system>/vru/libvosk.* and
# vru/model-en-us / vru/model-ja. A remap that went wrong would install every
# file and leave the core finding none of them, so these check the landing path.

func _group_pack() -> void:
	var fw := FirmwareInstaller.new()
	var dest := WORK.path_join("pack_system")

	var lib_zip := _write_zip("pack_lib.zip", {
		"vosk-win64-0.3.45/libvosk.dll": _text("dll"),
		"vosk-win64-0.3.45/libstdc++-6.dll": _text("stdc++"),
		"vosk-win64-0.3.45/libvosk.lib": _text("import library"),
		"vosk-win64-0.3.45/vosk_api.h": _text("header"),
	})
	var lib: Dictionary = fw._extract("pack", lib_zip, dest, "vosk-win64-0.3.45/", "vru/",
		PackedStringArray(["libvosk.dll", "libstdc++-6.dll"]))
	_ok(bool(lib["ok"]), "pack/a library zip unpacks", str(lib.get("error", "")))
	_eq(_read_bytes(dest.path_join("vru/libvosk.dll")), _text("dll"),
		"pack/its library lands in vru/, out of the zip's own folder")
	_ok(FileAccess.file_exists(dest.path_join("vru/libstdc++-6.dll")),
		"pack/and so does the runtime it needs")
	_ok(not FileAccess.file_exists(dest.path_join("vru/libvosk.lib"))
		and not FileAccess.file_exists(dest.path_join("vru/vosk_api.h")),
		"pack/and nothing the list leaves out")
	_ok(not DirAccess.dir_exists_absolute(dest.path_join("vosk-win64-0.3.45")),
		"pack/and the zip's folder name never reaches the system dir")

	var model_zip := _write_zip("pack_model.zip", {
		"vosk-model-small-ja-0.22/graph/words.txt": _text("ピカチュウ 1"),
		"vosk-model-small-ja-0.22/am/final.mdl": _text("model"),
		"README.md": _text("outside the folder"),
	})
	var model: Dictionary = fw._extract("pack", model_zip, dest, "vosk-model-small-ja-0.22/",
		"vru/model-ja/", PackedStringArray())
	_ok(bool(model["ok"]), "pack/a model zip unpacks", str(model.get("error", "")))
	_eq(_read_bytes(dest.path_join("vru/model-ja/graph/words.txt")), _text("ピカチュウ 1"),
		"pack/a model keeps its own tree below the renamed folder")
	_ok(not FileAccess.file_exists(dest.path_join("README.md"))
		and not FileAccess.file_exists(dest.path_join("vru/model-ja/README.md")),
		"pack/a member outside the named folder is not unpacked")

	var short_zip := _write_zip("pack_short.zip", {"vosk-win64-0.3.45/libvosk.dll": _text("dll")})
	var short: Dictionary = fw._extract("pack", short_zip, WORK.path_join("pack_short"),
		"vosk-win64-0.3.45/", "vru/", PackedStringArray(["libvosk.dll", "libgcc_s_seh-1.dll"]))
	_ok(not bool(short["ok"]), "pack/a zip missing a file the list names is refused")
	_ok(not FileAccess.file_exists(WORK.path_join("pack_short/vru/libvosk.dll")),
		"pack/and installs none of it, since a library without its runtime will not load")

	var moved_zip := _write_zip("pack_moved.zip", {"vosk-win64-0.3.46/libvosk.dll": _text("dll")})
	var moved: Dictionary = fw._extract("pack", moved_zip, WORK.path_join("pack_moved"),
		"vosk-win64-0.3.45/", "vru/", PackedStringArray(["libvosk.dll"]))
	_ok(not bool(moved["ok"]) and str(moved["error"]).contains("vosk-win64-0.3.45/"),
		"pack/a zip whose folder was renamed says which folder it lacks", str(moved.get("error", "")))

	var evil_zip := _write_zip("pack_evil.zip", {"vosk-model-small-ja-0.22/../../escaped.txt": _text("out")})
	var evil: Dictionary = fw._extract("pack", evil_zip, dest, "vosk-model-small-ja-0.22/",
		"vru/model-ja/", PackedStringArray())
	_ok(not bool(evil["ok"]), "pack/a member climbing out of the renamed folder is refused")
	_ok(not FileAccess.file_exists(dest.path_join("vru/escaped.txt"))
		and not FileAccess.file_exists(dest.path_join("escaped.txt")),
		"pack/and writes nothing")

	# GitHub hands a release asset over as a redirect to a signed link, and the
	# client opens a host and requests a path, so a URL has to come apart cleanly.
	_eq(FirmwareInstaller.split_url("https://release-assets.githubusercontent.com/a/b?sig=x%2F&se=1"),
		{"base_url": "https://release-assets.githubusercontent.com", "path": "/a/b?sig=x%2F&se=1"},
		"pack/a signed link splits into host and path, query kept")
	_eq(FirmwareInstaller.split_url("http://192.168.0.106:8080/x.zip"),
		{"base_url": "http://192.168.0.106:8080", "path": "/x.zip"}, "pack/and a port stays with the host")
	_eq(FirmwareInstaller.split_url("https://alphacephei.com"),
		{"base_url": "https://alphacephei.com", "path": "/"}, "pack/a bare host asks for /")
	_eq(FirmwareInstaller.split_url("ftp://example.com/x.zip"), {}, "pack/and anything but HTTP is refused")

	# The library the core opens is named per platform in vru_recognizer.c.
	var expect_lib := {
		"Windows": ["x86_64", "libvosk.dll"], "Linux": ["x86_64", "libvosk.so"],
		"macOS": ["arm64", "libvosk.dylib"], "Android": ["arm64", "libvosk.so"],
	}
	for os_name: String in expect_lib:
		var arch: String = expect_lib[os_name][0]
		for pack: Dictionary in SystemAssetCatalog.packs_for("mupen64plus_next", os_name, arch):
			var parts := SystemAssetCatalog.pack_parts(pack, os_name, arch)
			_eq(str(parts[0]["marker"]), "vru/" + str(expect_lib[os_name][1]),
				"pack/%s %s installs the library the core opens there" % [os_name, pack["id"]])
	_eq(SystemAssetCatalog.packs_for("mupen64plus_next", "Android", "x86_64").size(), 0,
		"pack/a platform Vosk publishes no library for is offered no pack")
	_eq(SystemAssetCatalog.packs_for("mupen64plus_next_gles3", "Android", "arm64").size(), 2,
		"pack/the Quest's gles3 core, a system dir of its own, is offered both")

	var models := {}
	for pack: Dictionary in SystemAssetCatalog.packs_for("mupen64plus_next", "Windows", "x86_64"):
		for part: Dictionary in SystemAssetCatalog.pack_parts(pack, "Windows", "x86_64"):
			if str(part["id"]).begins_with("vosk_model_"):
				models[str(part["into"])] = pack["id"]
	_eq(models, {"vru/model-en-us/": "vru_en", "vru/model-ja/": "vru_ja"},
		"pack/each language unpacks to the folder name the core chooses between")
	for id: String in SystemAssetCatalog.PARTS:
		var part: Dictionary = SystemAssetCatalog.PARTS[id]
		_ok(str(part["marker"]).begins_with(str(part["into"])),
			"pack/%s's marker is a file it installs" % id, str(part["marker"]))

	# Installed means every part: the library alone, which both packs share,
	# must not make either language read as there.
	var sys := WORK.path_join("pack_installed")
	var ja := SystemAssetCatalog.pack_for("mupen64plus_next", "vru_ja")
	var parts_here := SystemAssetCatalog.pack_parts(ja)
	_ok(not SystemAssetCatalog.pack_installed(sys, ja), "pack/nothing on disk is not installed")
	if not parts_here.is_empty():
		DirAccess.make_dir_recursive_absolute(sys.path_join(str(parts_here[0]["marker"])).get_base_dir())
		_write_bytes(sys.path_join(str(parts_here[0]["marker"])), _text("lib"))
		_ok(not SystemAssetCatalog.pack_installed(sys, ja),
			"pack/the shared library alone does not install a language")
		DirAccess.make_dir_recursive_absolute(sys.path_join(str(parts_here[1]["marker"])).get_base_dir())
		_write_bytes(sys.path_join(str(parts_here[1]["marker"])), _text("words"))
		_ok(SystemAssetCatalog.pack_installed(sys, ja), "pack/the library and its model do")

	fw.free()
