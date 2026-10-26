## arcade_memory_tests — an arcade game's own memory: what MAME keeps for it, what is set aside when a game rejects it, what a start may and may
## not do about it (ArcadeBackupMemory, docs/dev/arcade-backup-memory.md). Headless, no core, no ROM: a throw-away save directory under user://.
##
##   "$godot" --headless --path RetroXR res://Tests/arcade_memory_tests.tscn
##   "$godot" --headless --path RetroXR res://Tests/arcade_memory_tests.tscn -- --only=quarantine
##
## Groups:
##   paths/       where MAME keeps a romset's files and where they are set aside; which cores these are the files of
##   describe/    what is saved, in numbers and in words
##   damaged/     a file cannot be right only when a Timekeeper device's file is not the device's size: a file of the right size is never judged
##   quarantine/  the whole folder moves, with a manifest, nothing is deleted, a clone is a folder of its own, a pair stays a pair
##   restore/     the exact inverse, byte for byte, and itself reversible
##   prune/       the newest copies are kept
##   launch/      a start sets aside a damaged folder and touches nothing else
##   table/       the table's `b`: which games start from a memory built by hand
##   system/      the cabinet: what the DIP tab is told, when a Reset is refused, the start's hook
##   ui/          the DIP tab's Game memory section: Reset asks twice, the copies put back, nothing when there is none
extends Node

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")

var A := ArcadeBackupMemory

var _checks := 0
var _failed := 0
var _only := ""
var _root := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7)
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("[memory] TIMED OUT")
		get_tree().quit(1))
	_root = "user://arcade_memory_tests_%d" % (Time.get_ticks_usec() % 1000000)
	await _run()
	_remove_tree(_root)
	print("[memory] %d checks, %d failed" % [_checks, _failed])
	print("[memory] RESULT=%s" % ("PASS" if _failed == 0 else "FAIL"))
	get_tree().quit(1 if _failed > 0 else 0)


func _ok(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
	print("[memory] %s  %s" % ["PASS" if ok else "FAIL", what])


func _want(group: String) -> bool:
	return _only.is_empty() or _only == group


func _run() -> void:
	for g: Array in [["paths", _group_paths], ["describe", _group_describe], ["damaged", _group_damaged],
			["quarantine", _group_quarantine], ["restore", _group_restore], ["prune", _group_prune],
			["launch", _group_launch], ["table", _group_table], ["system", _group_system], ["ui", _group_ui]]:
		if _want(str(g[0])):
			await (g[1] as Callable).call()


# --- helpers -------------------------------------------------------------------

var _n := 0


## A fresh, empty save directory for one case.
func _save() -> String:
	_n += 1
	var dir := _root.path_join("save%d" % _n)
	DirAccess.make_dir_recursive_absolute(dir)
	return dir


## A file of `size` bytes whose content depends on `seed` (so a swap of two files shows), in `romset`'s memory folder.
func _put(save: String, romset: String, name: String, size: int, content_seed: int = 7) -> String:
	var dir := A.nvram_dir(save, romset)
	DirAccess.make_dir_recursive_absolute(dir)
	var bytes := PackedByteArray()
	bytes.resize(size)
	for i in size:
		bytes[i] = (i * 31 + content_seed) & 0xFF
	var f := FileAccess.open(dir.path_join(name), FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	return dir.path_join(name)


func _sha(path: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA1)
	ctx.update(FileAccess.get_file_as_bytes(path))
	return ctx.finish().hex_encode()


func _remove_tree(dir: String) -> void:
	for sub in DirAccess.get_directories_at(dir):
		_remove_tree(dir.path_join(sub))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func _names(rows: Array) -> Array:
	var out: Array = []
	for r in rows:
		out.append(str(r["name"]))
	return out


# --- paths ---------------------------------------------------------------------

func _group_paths() -> void:
	_ok(A.nvram_dir("/save/mame", "sscope") == "/save/mame/mame/nvram/sscope",
		"paths: MAME keeps a romset's files in <save dir>/mame/nvram/<romset>")
	_ok(A.quarantine_dir("/save/mame", "sscope") == "/save/mame/nvram_quarantine/sscope"
			and not A.quarantine_dir("/save/mame", "sscope").begins_with(A.nvram_dir("/save/mame", "sscope")),
		"paths: and the room sets copies aside beside it, never inside it (MAME must not see them)")
	_ok(A.supports_core("mame") and A.supports_core("mamearcade") and not A.supports_core("fbneo") and not A.supports_core("mame2003_plus")
			and not A.supports_core("mame2010") and not A.supports_core("hbmame") and not A.supports_core(""),
		"paths: only MAME 0.289's two builds (the desktop's, the Quest's) are managed: FinalBurn Neo and the old MAMEs keep another layout")


# --- describe ------------------------------------------------------------------

func _group_describe() -> void:
	var save := _save()
	var none := A.describe(save, "sscope2")
	_ok(not bool(none["exists"]) and (none["files"] as Array).is_empty() and int(none["bytes"]) == 0 and int(none["newest"]) == 0
			and A.is_first_run(save, "sscope2"),
		"describe: a game that never saved has no folder, no files, and its next start is a first start")
	DirAccess.make_dir_recursive_absolute(A.nvram_dir(save, "sscope2"))
	_ok(bool(A.describe(save, "sscope2")["exists"]) and A.is_first_run(save, "sscope2"),
		"describe: a folder with nothing in it is still a first start")
	_put(save, "sscope2", "m48t58", 8192)
	_put(save, "sscope2", "lan_eeprom", 128)
	var info := A.describe(save, "sscope2")
	_ok(bool(info["exists"]) and _names(info["files"]) == ["lan_eeprom", "m48t58"] and int(info["bytes"]) == 8320 and int(info["newest"]) > 0
			and not A.is_first_run(save, "sscope2"),
		"describe: Silent Scope 2's pair is two files by name, 8,320 bytes, and no longer a first start")
	_ok(A.summary({"files": []}) == "nothing saved yet", "describe: and says nothing saved yet")
	var said := A.summary({"files": [1, 2], "bytes": 8320, "newest": 1000}, 1000 + 3 * 86400)
	_ok(said == "2 files, 8.1 KB, saved 3 days ago", "describe: otherwise how much and how long ago (%s)" % said)
	_ok(A.summary({"files": [1], "bytes": 100, "newest": 1000}, 1030) == "1 file, 100 bytes, saved a moment ago"
			and A.summary({"files": [1], "bytes": 100, "newest": 1000}, 1000 + 3 * 3600).ends_with("3 hours ago"),
		"describe: in a singular and a moment and an hour")


# --- damaged -------------------------------------------------------------------

func _group_damaged() -> void:
	var save := _save()
	# Every device's own size is right, whichever it is.
	for device: String in A.DEVICE_SIZES:
		_put(save, "ok_" + device, device, int(A.DEVICE_SIZES[device]))
	var any_bad := false
	for device: String in A.DEVICE_SIZES:
		any_bad = any_bad or not A.damaged(save, "ok_" + device).is_empty()
	_ok(not any_bad and A.DEVICE_SIZES.size() == 7,
		"damaged: a file of the size its chip makes is never judged, for each of the seven chips")
	_ok(int(A.DEVICE_SIZES["m48t58"]) == 8192 and int(A.DEVICE_SIZES["m48t35"]) == 32768 and int(A.DEVICE_SIZES["m48t02"]) == 2048
			and int(A.DEVICE_SIZES["mk48t12"]) == 2048 and int(A.DEVICE_SIZES["ds1643"]) == 8192,
		"damaged: and those sizes are MAME's (timekpr.cpp: 0x2000, 0x8000, 0x800)")
	# What a write that never finished leaves: nothing, a part, a bit too much.
	for size: int in [0, 1, 4096, 8191, 8193, 9000, 16384]:
		var s2 := _save()
		_put(s2, "sscope", "m48t58", size)
		var bad := A.damaged(s2, "sscope")
		_ok(bad.size() == 1 and int(bad[0]["size"]) == size and int(bad[0]["want"]) == 8192 and str(bad[0]["name"]) == "m48t58",
			"damaged: an m48t58 of %d bytes cannot be right" % size)
	# What is not judged: another device, another name, a name that only contains a chip's.
	var s3 := _save()
	_put(s3, "sscope2", "lan_eeprom", 3)
	_put(s3, "sscope2", "eeprom", 0)
	_put(s3, "sscope2", "xm48t58", 5)
	_put(s3, "sscope2", "m48t58.bak", 5)
	_put(s3, "sscope2", "m48t58", 8192)
	_ok(A.damaged(s3, "sscope2").is_empty(),
		"damaged: an EEPROM of any size, or a file whose name only contains a chip's, is not judged: a size is only known for a chip's own file")
	# One bad file in a pair: the folder is damaged as a whole, and says which.
	_put(s3, "sscope2", "m48t58", 100)
	var pair := A.damaged(s3, "sscope2")
	_ok(pair.size() == 1 and str(pair[0]["name"]) == "m48t58", "damaged: one chip's file wrong in a pair is named, the pair's other file is not")
	_ok(A.damaged(_save(), "never_saved").is_empty(), "damaged: nothing saved is nothing damaged")


# --- quarantine ----------------------------------------------------------------

func _group_quarantine() -> void:
	var save := _save()
	var a := _put(save, "sscope2", "m48t58", 8192, 1)
	var b := _put(save, "sscope2", "lan_eeprom", 128, 2)
	var sha_a := _sha(a)
	var sha_b := _sha(b)
	var when := 1790000000
	var moved := A.quarantine(save, "sscope2", "a test", when)
	var held := A.quarantine_dir(save, "sscope2").path_join(A.stamp_of(when)).path_join("nvram")
	_ok(bool(moved["ok"]) and str(moved["stamp"]) == A.stamp_of(when) and str(moved["to"]) == held,
		"quarantine: the folder is set aside under a stamp of the moment (%s)" % str(moved["stamp"]))
	_ok(not DirAccess.dir_exists_absolute(A.nvram_dir(save, "sscope2")) and A.is_first_run(save, "sscope2"),
		"quarantine: it is gone from where MAME looks, so the next start is a first start and MAME seeds the game again")
	_ok(FileAccess.file_exists(held.path_join("m48t58")) and FileAccess.file_exists(held.path_join("lan_eeprom"))
			and _sha(held.path_join("m48t58")) == sha_a and _sha(held.path_join("lan_eeprom")) == sha_b,
		"quarantine: the whole pair moved, byte for byte, never one of them: the game checks the one against the other")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(held.get_base_dir().path_join(A.MANIFEST)))
	var rows: Array = manifest.get("files", [])
	_ok(str(manifest.get("reason")) == "a test" and str(manifest.get("romset")) == "sscope2" and int(manifest.get("when")) == when and rows.size() == 2
			and str(rows[0]["name"]) == "lan_eeprom" and int(rows[0]["size"]) == 128 and str(rows[0]["sha1"]) == sha_b
			and str(rows[1]["sha1"]) == sha_a,
		"quarantine: the manifest says why, when, and what was in it with its SHA-1")
	# Nothing to set aside: nothing is made.
	var none := A.quarantine(save, "sscope2", "again", when + 1)
	_ok(not bool(none["ok"]) and not DirAccess.dir_exists_absolute(A.quarantine_dir(save, "sscope2").path_join(A.stamp_of(when + 1))),
		"quarantine: with nothing saved there is nothing to set aside, and no empty copy is made")
	var empty_dir := A.nvram_dir(save, "empty_game")
	DirAccess.make_dir_recursive_absolute(empty_dir)
	_ok(not bool(A.quarantine(save, "empty_game", "x", when)["ok"]) and DirAccess.dir_exists_absolute(empty_dir),
		"quarantine: nor of an empty folder, which is left where it is")
	# The same second twice: two copies, neither lost.
	_put(save, "sscope2", "m48t58", 8192, 3)
	var second := A.quarantine(save, "sscope2", "same second", when)
	_ok(bool(second["ok"]) and str(second["stamp"]) == A.stamp_of(when) + "-2" and A.list_quarantines(save, "sscope2").size() == 2,
		"quarantine: a second in the same second is a copy of its own (%s)" % str(second["stamp"]))
	# A clone is a folder of its own: setting one aside leaves the other.
	var s2 := _save()
	var parent_file := _put(s2, "sscope", "m48t58", 8192, 4)
	var clone_file := _put(s2, "sscopeb", "m48t58", 8192, 5)
	A.quarantine(s2, "sscopeb", "clone", when)
	_ok(FileAccess.file_exists(parent_file) and not FileAccess.file_exists(clone_file),
		"quarantine: a clone has a folder of its own: its parent's memory is not touched")
	# Nothing outside the folder is touched either.
	var s3 := _save()
	var other := _put(s3, "gradius4", "m48t58", 8192, 6)
	_put(s3, "sscope", "m48t58", 8192, 7)
	A.quarantine(s3, "sscope", "x", when)
	_ok(FileAccess.file_exists(other), "quarantine: another game's memory is not touched")
	# Never a delete: every byte that went in is in the copy.
	var listed := A.list_quarantines(save, "sscope2")
	_ok(listed.size() == 2 and str(listed[0]["stamp"]) == A.stamp_of(when) + "-2" and str(listed[0]["reason"]) == "same second"
			and str(listed[1]["reason"]) == "a test" and (listed[1]["files"] as Array).size() == 2,
		"quarantine: the copies are listed newest first, each with its reason")


# --- restore -------------------------------------------------------------------

func _group_restore() -> void:
	var save := _save()
	var a := _put(save, "sscope2", "m48t58", 8192, 11)
	var b := _put(save, "sscope2", "lan_eeprom", 128, 12)
	var sha_a := _sha(a)
	var sha_b := _sha(b)
	var moved := A.quarantine(save, "sscope2", "to restore", 1790000000)
	var back := A.restore(save, "sscope2", str(moved["stamp"]), 1790000100)
	_ok(bool(back["ok"]) and str(back["replaced"]) == "" and FileAccess.file_exists(a) and FileAccess.file_exists(b)
			and _sha(a) == sha_a and _sha(b) == sha_b,
		"restore: the memory is back where MAME looks, byte for byte")
	_ok(A.list_quarantines(save, "sscope2").is_empty() and not DirAccess.dir_exists_absolute(A.quarantine_dir(save, "sscope2").path_join(str(moved["stamp"]))),
		"restore: and the copy is no longer set aside (a folder that is back is not also there)")
	# What is there when a restore comes is not lost: it goes into quarantine first, and can be had again.
	var first := A.quarantine(save, "sscope2", "first", 1790000200)
	var fresh := _put(save, "sscope2", "m48t58", 8192, 21)
	var sha_fresh := _sha(fresh)
	var swap := A.restore(save, "sscope2", str(first["stamp"]), 1790000300)
	_ok(bool(swap["ok"]) and str(swap["replaced"]) == A.stamp_of(1790000300) and _sha(a) == sha_a and FileAccess.file_exists(b),
		"restore: with a memory already there, the old one is restored and the one that was there is set aside first")
	var kept := A.list_quarantines(save, "sscope2")
	_ok(kept.size() == 1 and str(kept[0]["reason"]) == "before restoring " + str(first["stamp"]),
		"restore: under a reason that says what it was set aside for (%s)" % (str(kept[0]["reason"]) if kept.size() == 1 else "?"))
	var undo := A.restore(save, "sscope2", str(swap["replaced"]), 1790000400)
	_ok(bool(undo["ok"]) and _sha(a) == sha_fresh and not FileAccess.file_exists(b) and A.list_quarantines(save, "sscope2").size() == 1,
		"restore: and restoring THAT undoes it: the swap can be had either way round")
	# A copy that is not there changes nothing.
	var before := A.describe(save, "sscope2")
	var none := A.restore(save, "sscope2", "20990101T000000Z", 1790000500)
	_ok(not bool(none["ok"]) and A.describe(save, "sscope2")["bytes"] == before["bytes"] and A.list_quarantines(save, "sscope2").size() == 1
			and not bool(A.restore(save, "sscope2", "")["ok"]),
		"restore: a copy that is not there, or no name, moves nothing")
	# An empty folder MAME made since is no obstacle.
	var s2 := _save()
	_put(s2, "gradius4", "m48t58", 8192, 31)
	var set_aside := A.quarantine(s2, "gradius4", "x", 1790000000)
	DirAccess.make_dir_recursive_absolute(A.nvram_dir(s2, "gradius4"))
	_ok(bool(A.restore(s2, "gradius4", str(set_aside["stamp"]), 1790000100)["ok"]) and FileAccess.file_exists(A.nvram_dir(s2, "gradius4").path_join("m48t58")),
		"restore: an empty folder in its place is no obstacle")


# --- prune ---------------------------------------------------------------------

func _group_prune() -> void:
	var save := _save()
	for i in A.KEEP_NEWEST + 5:
		_put(save, "sscope", "m48t58", 8192, i)
		A.quarantine(save, "sscope", "copy %d" % i, 1790000000 + i * 10)
	var rows := A.list_quarantines(save, "sscope")
	_ok(rows.size() == A.KEEP_NEWEST and str(rows[0]["reason"]) == "copy %d" % (A.KEEP_NEWEST + 4) and str(rows[rows.size() - 1]["reason"]) == "copy 5",
		"prune: the newest %d copies are kept and the five oldest are the ones that go" % A.KEEP_NEWEST)
	_put(save, "gradius4", "m48t58", 8192)
	A.quarantine(save, "gradius4", "x", 1790009999)
	_ok(A.list_quarantines(save, "gradius4").size() == 1 and A.list_quarantines(save, "sscope").size() == A.KEEP_NEWEST,
		"prune: a game's copies are its own count")


# --- launch --------------------------------------------------------------------

func _group_launch() -> void:
	var save := _save()
	var fresh := A.prepare_launch(save, "sscope", 1790000000)
	_ok(str(fresh["action"]) == "none" and bool(fresh["first_run"]) and (fresh["damaged"] as Array).is_empty(),
		"launch: a game that never saved starts as a first start, and nothing is done")
	var good := _put(save, "sscope", "m48t58", 8192, 41)
	var sha := _sha(good)
	var again := A.prepare_launch(save, "sscope", 1790000001)
	_ok(str(again["action"]) == "none" and not bool(again["first_run"]) and _sha(good) == sha and A.list_quarantines(save, "sscope").is_empty(),
		"launch: a file of the right size is never touched, whatever it holds")
	# Whatever it holds: all zeros, all 0xFF, which a game may reject and a start may not judge.
	var zeros := FileAccess.open(good, FileAccess.WRITE)
	zeros.store_buffer(PackedByteArray([0]).duplicate())
	zeros.close()
	var s2 := _save()
	var blank := _put(s2, "sscope", "m48t58", 8192, 0)
	var f := FileAccess.open(blank, FileAccess.WRITE)
	var z := PackedByteArray()
	z.resize(8192)
	f.store_buffer(z)
	f.close()
	var sha_blank := _sha(blank)
	_ok(str(A.prepare_launch(s2, "sscope", 1790000002)["action"]) == "none" and _sha(blank) == sha_blank,
		"launch: not even a memory of 8,192 zeros, which the game may call an error but which is not damage: the player may reset it")
	# Damaged: the whole folder is set aside, with the reason.
	var s3 := _save()
	_put(s3, "sscope2", "m48t58", 0)
	_put(s3, "sscope2", "lan_eeprom", 128, 9)
	var cleared := A.prepare_launch(s3, "sscope2", 1790000003)
	var rows := A.list_quarantines(s3, "sscope2")
	_ok(str(cleared["action"]) == "set_aside" and A.is_first_run(s3, "sscope2") and rows.size() == 1
			and str(rows[0]["reason"]).begins_with("damaged at start: m48t58 is 0 bytes, not 8192") and (rows[0]["files"] as Array).size() == 2,
		"launch: an empty m48t58 sets the whole pair aside, and says why (%s)" % (str(rows[0]["reason"]) if rows.size() == 1 else "?"))
	var back := A.restore(s3, "sscope2", str(cleared["stamp"]))
	_ok(bool(back["ok"]) and FileAccess.file_exists(A.nvram_dir(s3, "sscope2").path_join("lan_eeprom")),
		"launch: and the player can have it back")
	# Another game's folder and a clone's are not looked at.
	var s4 := _save()
	_put(s4, "gradius4", "m48t58", 100)
	_put(s4, "sscope", "m48t58", 8192)
	_ok(str(A.prepare_launch(s4, "sscope", 1790000004)["action"]) == "none" and FileAccess.file_exists(A.nvram_dir(s4, "gradius4").path_join("m48t58")),
		"launch: only this game's folder is looked at")


# --- table ---------------------------------------------------------------------

func _group_table() -> void:
	var sscope := ArcadeGameProfile.for_romset("sscope")
	var sscope2 := ArcadeGameProfile.for_romset("sscope2")
	var sscope2a := ArcadeGameProfile.for_romset("sscope2a")
	var gradius := ArcadeGameProfile.for_romset("gradius4")
	var street := ArcadeGameProfile.for_romset("sf2")
	_ok(sscope.backup_class() == "h" and sscope2a.backup_class() == "h" and gradius.backup_class() == "h" and street.backup_class() == "",
		"table: Silent Scope, Silent Scope 2's Asia set and Gradius 4 start from a memory built by hand (h); Street Fighter II has none")
	_ok(sscope2.backup_class() == "g" and sscope2.has_backup_memory(),
		"table: Silent Scope 2's own set (MAME's `sscope2`) ships a real dump of the chip (g): the game may still reject it, and Reset is there all the same")
	var hand := 0
	var good := 0
	var none := 0
	for romset: String in ArcadeGameProfile._index.keys():
		match ArcadeGameProfile.for_romset(romset).backup_class():
			"h":
				hand += 1
			"g":
				good += 1
			"n":
				none += 1
	_ok(hand > 60 and hand < 120 and good > 200 and none > 300,
		"table: the census holds: %d romsets start from a hand-built memory, %d from a good dump, %d from none" % [hand, good, none])
	_ok(not ArcadeGameProfile.for_romset("not_a_real_romset").has_backup_memory() and sscope.has_backup_memory(),
		"table: a game the table does not know has none")


# --- system --------------------------------------------------------------------

func _wait(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


## A cabinet with Silent Scope 2's profile dressed on, its core MAME, its save directory a throw-away one.
func _cabinet(romset: String, save: String) -> RetroSystem:
	var sys := SYSTEM_SCENE.instantiate() as RetroSystem
	sys.model_id = ArcadeProfiles.CABINET_MODEL_ID
	sys.systemid = "arcade"
	sys.core_name = "mame"
	sys.freeze = true
	sys.position = Vector3(_n * 4.0, 0, 0)
	add_child(sys)
	sys.add_to_group("spawned")
	await _wait(8)
	sys.game_memory_root_override = save
	(sys.get_model() as RetroSystemModelArcadeCabinet).apply_game_profile(ArcadeGameProfile.for_romset(romset))
	return sys


## The words on a cabinet's notice card now (its labels), or [] while it shows nothing.
func _said(sys: RetroSystem) -> Array:
	var toast := sys._machine_toast_card
	if not is_instance_valid(toast) or not toast._showing or not is_instance_valid(toast._root):
		return []
	return toast._root.find_children("*", "Label", true, false).map(func(l: Node) -> String: return (l as Label).text)


func _group_system() -> void:
	var save := _save()
	var empty_cab := SYSTEM_SCENE.instantiate() as RetroSystem
	empty_cab.model_id = ArcadeProfiles.CABINET_MODEL_ID
	empty_cab.systemid = "arcade"
	empty_cab.core_name = "mame"
	empty_cab.freeze = true
	add_child(empty_cab)
	await _wait(8)
	_ok(empty_cab.game_memory_state().is_empty() and empty_cab.game_memory_context().is_empty(),
		"system: a cabinet with no game in it has no memory to manage")
	empty_cab.queue_free()
	var sys := await _cabinet("sscope2", save)
	var state := sys.game_memory_state()
	_ok(str(state["romset"]) == "sscope2" and str(state["summary"]) == "nothing saved yet" and not bool(state["has_files"])
			and bool(state["can_change"]) and (state["copies"] as Array).is_empty() and str(state["class"]) == "g",
		"system: Silent Scope 2 in the bay: nothing saved yet, nothing set aside, free to change")
	_put(save, "sscope2", "m48t58", 8192, 1)
	_put(save, "sscope2", "lan_eeprom", 128, 2)
	state = sys.game_memory_state()
	_ok(bool(state["has_files"]) and str(state["summary"]).begins_with("2 files, 8.1 KB, saved"),
		"system: and with its pair saved it says so (%s)" % str(state["summary"]))
	# Refused: a running game writes its memory when it stops.
	sys.is_powered_on = true
	var refused := sys.reset_game_memory()
	_ok(not bool(refused["ok"]) and not bool(sys.game_memory_state()["can_change"]) and FileAccess.file_exists(A.nvram_dir(save, "sscope2").path_join("m48t58"))
			and str(sys.game_memory_blocker()).begins_with("the game is running"),
		"system: a Reset is refused while the game runs, and nothing is touched (%s)" % str(refused["message"]))
	sys.is_powered_on = false
	_ok(sys.game_memory_blocker().is_empty() or sys.game_memory_blocker().begins_with("the game is still saving"),
		"system: switched off, it waits for MAME to finish writing")
	sys._game_memory_stopped_ms = Time.get_ticks_msec()
	_ok(str(sys.game_memory_blocker()).begins_with("the game is still saving") and not bool(sys.restore_game_memory("20260101T000000Z")["ok"]),
		"system: for %d seconds after the core stops, a Reset or a Restore is refused" % (RetroSystem.GAME_MEMORY_SETTLE_MS / 1000))
	sys._game_memory_stopped_ms = -RetroSystem.GAME_MEMORY_SETTLE_MS
	# Stopping the core is what starts that wait (the real path: the power switch).
	sys.is_powered_on = true
	sys.power_off()
	_ok(not sys.is_powered_on and str(sys.game_memory_blocker()).begins_with("the game is still saving"),
		"system: and the power switch is what starts it")
	sys._game_memory_stopped_ms = -RetroSystem.GAME_MEMORY_SETTLE_MS
	# Another cabinet running the same game shares the folder.
	var twin := await _cabinet("sscope2", save)
	twin.is_powered_on = true
	_ok(str(sys.game_memory_blocker()).begins_with("another cabinet is running this game") and not bool(sys.reset_game_memory()["ok"]),
		"system: another cabinet running the same game is a reason to wait")
	twin.is_powered_on = false
	twin._game_memory_stopped_ms = -RetroSystem.GAME_MEMORY_SETTLE_MS
	var other := await _cabinet("gradius4", save)
	other.is_powered_on = true
	_ok(sys.game_memory_blocker().is_empty(), "system: and a different game running is not")
	other.is_powered_on = false
	# The Reset itself, and the way back.
	var sha_before := _sha(A.nvram_dir(save, "sscope2").path_join("m48t58"))
	var reset := sys.reset_game_memory()
	var copies := sys.game_memory_state()["copies"] as Array
	_ok(bool(reset["ok"]) and not bool(sys.game_memory_state()["has_files"]) and copies.size() == 1 and str(copies[0]["reason"]) == "reset by the player",
		"system: Reset sets the pair aside, the next start is a first start, and the copy is listed (%s)" % str(reset["message"]))
	_ok(not bool(sys.reset_game_memory()["ok"]), "system: a second Reset has nothing to set aside and says so")
	var back := sys.restore_game_memory(str(copies[0]["stamp"]))
	_ok(bool(back["ok"]) and _sha(A.nvram_dir(save, "sscope2").path_join("m48t58")) == sha_before and (sys.game_memory_state()["copies"] as Array).is_empty(),
		"system: Restore brings it back byte for byte")
	# FinalBurn Neo keeps its memory another way: nothing is offered.
	sys.core_name = "fbneo"
	_ok(sys.game_memory_state().is_empty(), "system: with FinalBurn Neo as the core there is nothing to manage")
	sys.core_name = "mamearcade"
	_ok(not sys.game_memory_state().is_empty(), "system: the Quest's MAME is MAME all the same")
	sys.core_name = "mame"
	# The start's hook: a damaged memory is set aside, a good one is not, a first start of a hand-built one is told.
	var hook_save := _save()
	sys.game_memory_root_override = hook_save
	var good := _put(hook_save, "sscope2", "m48t58", 8192, 5)
	var sha_good := _sha(good)
	sys._game_memory_before_start()
	_ok(FileAccess.file_exists(good) and _sha(good) == sha_good and A.list_quarantines(hook_save, "sscope2").is_empty(),
		"system: a start leaves a memory of the right size exactly as it is")
	_ok(_said(sys).is_empty(), "system: and says nothing about it")
	_put(hook_save, "sscope2", "m48t58", 100, 6)
	sys._game_memory_before_start()
	_ok(not FileAccess.file_exists(good) and A.list_quarantines(hook_save, "sscope2").size() == 1,
		"system: and sets a damaged one aside, so MAME seeds the game again")
	var told := _said(sys)
	_ok(told.has("Game memory reset") and told.any(func(t: String) -> bool: return t.contains("set aside") and t.contains("DIP Switch")),
		"system: and tells the player what became of it and where it can be had back (%s)" % str(told))
	# A game whose default memory was built by hand says on its FIRST start what the game may do, once.
	var hand := await _cabinet("sscope", hook_save)
	hand._game_memory_before_start()
	var hint := _said(hand)
	_ok(str(hand.game_memory_context()["class"]) == "h" and hint.has("First start") and hint.any(func(t: String) -> bool: return t.contains("BACKUP DATA ERROR")),
		"system: Silent Scope's first start is told what the game may do (%s)" % str(hint))
	_put(hook_save, "sscope", "m48t58", 8192, 9)
	var again := await _cabinet("sscope", hook_save)
	again._game_memory_before_start()
	_ok(_said(again).is_empty(), "system: and its second start, with a memory of its own saved, is told nothing")
	var real := await _cabinet("sscope2", _save())
	real._game_memory_before_start()
	_ok(str(real.game_memory_context()["class"]) == "g" and _said(real).is_empty(),
		"system: a game whose default memory is a real dump is told nothing on its first start")
	for n: Node in [sys, twin, other, hand, again, real]:
		n.queue_free()
	await _wait(4)


# --- ui ------------------------------------------------------------------------

func _rows_of(ui: CoreOptions2D) -> Array:
	return ui._dip_rows.get_children().filter(func(c: Node) -> bool: return not c.is_queued_for_deletion())


func _buttons_of(ui: CoreOptions2D) -> Array:
	return _rows_of(ui).filter(func(c: Node) -> bool: return c is Button)


func _group_ui() -> void:
	var ui := preload("res://Scenes/UI/core_options_2d.tscn").instantiate() as CoreOptions2D
	add_child(ui)
	await _wait(4)
	ui.populate_dip(true, false, false, false)
	await _wait(2)
	var before := _rows_of(ui).size()
	_ok(not _rows_of(ui).any(func(c: Node) -> bool: return c is Label and (c as Label).text == "Game memory"),
		"ui: a cabinet with no game memory to manage has no such section")
	var state := {"romset": "sscope", "class": "h", "summary": "2 files, 8.1 KB, saved 3 days ago", "has_files": true, "can_change": true, "why_not": "",
		"copies": [{"stamp": "20261026T143005Z", "reason": "reset by the player"}, {"stamp": "20261020T090000Z", "reason": ""},
			{"stamp": "20261019T090000Z", "reason": ""}, {"stamp": "20261018T090000Z", "reason": ""}, {"stamp": "20261017T090000Z", "reason": ""},
			{"stamp": "20261016T090000Z", "reason": ""}, {"stamp": "20261015T090000Z", "reason": ""}]}
	ui.populate_dip(true, false, false, false, state)
	await _wait(2)
	var texts: Array = []
	for c in _rows_of(ui):
		if c is Label:
			texts.append((c as Label).text)
	_ok(texts.has("Game memory") and texts.any(func(t: String) -> bool: return t.contains("Saved: 2 files, 8.1 KB, saved 3 days ago."))
			and texts.any(func(t: String) -> bool: return t.contains("BACKUP DATA ERROR")) and texts.any(func(t: String) -> bool: return t.contains("Saved states keep their own copy")),
		"ui: the section says what is saved, what a first start may say for a hand-built memory, and what a Reset does not reach")
	var buttons := _buttons_of(ui)
	_ok(buttons.size() == 1 + 5 and (buttons[0] as Button).text == "Reset game memory" and not (buttons[0] as Button).disabled,
		"ui: a Reset button and the newest five copies to put back, not seven (%d buttons)" % buttons.size())
	_ok((buttons[1] as Button).text.begins_with("Put back 2026-10-26 14:30 UTC") and (buttons[1] as Button).text.contains("reset by the player"),
		"ui: each says when it was set aside and why (%s)" % (buttons[1] as Button).text)
	var asked := [0]
	ui.memory_reset_requested.connect(func() -> void: asked[0] += 1)
	(buttons[0] as Button).pressed.emit()
	await _wait(2)
	var armed := _buttons_of(ui)[0] as Button
	_ok(asked[0] == 0 and armed.text.begins_with("Press again"), "ui: the first press only asks again: nothing is set aside by one press")
	armed.pressed.emit()
	_ok(asked[0] == 1, "ui: the second sets it aside")
	# What the action said, shown, and the question forgotten.
	ui.show_memory_message("This game's memory is set aside. It starts as new.")
	await _wait(2)
	var said := _rows_of(ui).any(func(c: Node) -> bool: return c is Label and (c as Label).text.begins_with("This game's memory is set aside"))
	_ok(said and (_buttons_of(ui)[0] as Button).text == "Reset game memory", "ui: the result is shown, and the Reset asks twice again")
	var stamps: Array = []
	ui.memory_restore_requested.connect(func(stamp: String) -> void: stamps.append(stamp))
	(_buttons_of(ui)[2] as Button).pressed.emit()
	_ok(stamps == ["20261020T090000Z"], "ui: pressing a copy asks for that one (%s)" % str(stamps))
	# Not now: the buttons are off, and it says why.
	var blocked := state.duplicate(true)
	blocked["can_change"] = false
	blocked["why_not"] = "the game is running (switch the cabinet off first)"
	ui.populate_dip(true, false, true, false, blocked)
	await _wait(2)
	var all_off := true
	for b: Button in _buttons_of(ui):
		all_off = all_off and b.disabled
	_ok(all_off and _rows_of(ui).any(func(c: Node) -> bool: return c is Label and (c as Label).text == "Not now: the game is running (switch the cabinet off first)."),
		"ui: while the game runs every button is off, and the section says why")
	var nothing := state.duplicate(true)
	nothing["has_files"] = false
	nothing["summary"] = "nothing saved yet"
	ui.populate_dip(true, false, false, false, nothing)
	await _wait(2)
	_ok((_buttons_of(ui)[0] as Button).disabled and _rows_of(ui).any(func(c: Node) -> bool: return c is Label and (c as Label).text.begins_with("Nothing is saved yet")),
		"ui: with nothing saved there is nothing to reset, and it says so")
	ui.queue_free()
	await _wait(2)
