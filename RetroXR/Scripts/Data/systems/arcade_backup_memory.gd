## ArcadeBackupMemory — an arcade game's own memory: the files MAME keeps for it, and what the room does when the game rejects them
## (docs/dev/arcade-backup-memory.md).
##
## A game with a battery (a Timekeeper chip, an EEPROM) keeps its settings, high scores, bookkeeping and sometimes the machine's calibration in files that
## libretro-mame writes when it stops: `<the core's save directory>/mame/nvram/<romset>/<device>`, one file a device, a folder a romset. A game that finds
## them wrong says so (Silent Scope: BACKUP DATA ERROR), and they stay wrong for ever: MAME seeds a chip from the ROM's default image only when NO file
## exists, so a file that is there wins whatever it holds. Nothing here knows what a game wants in its memory; what it does is put the whole folder
## aside, reversibly, so the next start is a first start.
##
## The rules (each one a test, `arcade_memory_tests`):
##  - NEVER DELETE, never touch a file that is valid. A folder is MOVED into `<save dir>/nvram_quarantine/<romset>/<UTC stamp>/` with a manifest that says
##    why, what was in it and its SHA-1; `restore` is the exact inverse and is itself reversible (what is there goes into quarantine first).
##  - THE WHOLE FOLDER, never a file of it: Silent Scope 2 keeps `m48t58` and `lan_eeprom`, and the game checks the one against the other.
##  - A FILE IS CALLED DAMAGED only when it cannot be right: a Timekeeper device's file is exactly the device's size, and MAME writes it whole, so a file of
##    another size is what a write that never finished leaves (it reads short, runs on the part it got and logs "Error reading NVRAM file"). The size is
##    the only judge: a file of the right size is never touched, whatever it holds.
##  - NOT WHILE A CORE HOLDS THE GAME: MAME writes at teardown, so the caller asks first (`RetroSystem.game_memory_state`).
##  - Plain `DirAccess` and `FileAccess` on a path under the libretro root, so the same code runs on the desktop and on the Quest.
class_name ArcadeBackupMemory
extends RefCounted

## Where MAME 0.289 (libretro-mame) keeps a romset's memory under the core's save directory, and where the room sets it aside.
const NVRAM_SUBDIR := "mame/nvram"
const QUARANTINE_DIR := "nvram_quarantine"
const MANIFEST := "manifest.json"
## A romset keeps this many set-aside copies: the newest.
const KEEP_NEWEST := 20

## The Timekeeper-class chips (a battery RAM and a clock in one) and the size of the file each makes (MAME's timekpr.cpp: the constructor's last argument).
## The file is named after the device's tag, which for every game that has one is the chip's own name.
const DEVICE_SIZES := {
	"m48t02": 0x800, "m48t35": 0x8000, "m48t37": 0x8000, "m48t58": 0x2000,
	"mk48t08": 0x2000, "mk48t12": 0x800, "ds1643": 0x2000,
}

## What the first start of a game whose default memory was built by hand may do (the table's `bh`), said once, when no memory is saved yet. The words are
## the game's manual's as far as a summary of it goes (Konami's: TEST at the error screen restores the settings, then the test menu's adjustments),
## and they are not a promise about any one game.
const FIRST_RUN_HINT := "First start: the game may say BACKUP DATA ERROR. Press TEST (the red button in the compartment) and follow its menu, then switch the cabinet off with its power switch, so the game's memory is saved."


## MAME 0.289 is the core whose files these are (`mame` on the desktop, `mamearcade` on the Quest). FinalBurn Neo keeps one `.fs` file a romset, and
## the old MAMEs another layout: not managed here.
static func supports_core(core_name: String) -> bool:
	return core_name == "mame" or core_name == "mamearcade"


## The folder MAME keeps `romset`'s files in, under the core's save directory `save_root`.
static func nvram_dir(save_root: String, romset: String) -> String:
	return save_root.path_join(NVRAM_SUBDIR).path_join(romset)


## Where `romset`'s set-aside copies are kept.
static func quarantine_dir(save_root: String, romset: String) -> String:
	return save_root.path_join(QUARANTINE_DIR).path_join(romset)


## What is saved for `romset` now: {"exists": the folder is there, "files": [{"name", "size", "mtime"}] by name, "bytes": the sum, "newest": the
## newest file's modification time (unix seconds, 0 for none)}.
static func describe(save_root: String, romset: String) -> Dictionary:
	var dir := nvram_dir(save_root, romset)
	var files := _files_of(dir)
	var bytes := 0
	var newest := 0
	for f in files:
		bytes += int(f["size"])
		newest = maxi(newest, int(f["mtime"]))
	return {"exists": DirAccess.dir_exists_absolute(dir), "files": files, "bytes": bytes, "newest": newest}


## True when `romset` has never saved anything: no folder, or one with no file in it.
static func is_first_run(save_root: String, romset: String) -> bool:
	return (describe(save_root, romset)["files"] as Array).is_empty()


## The files of `romset`'s memory that cannot be right: [{"name", "size", "want"}] for each file named after a Timekeeper device (`m48t58`) whose size is
## not that device's. A file of any other name (an EEPROM, a device this does not know) is not judged, and one of the right size never is.
static func damaged(save_root: String, romset: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f: Dictionary in describe(save_root, romset)["files"]:
		var name := str(f["name"]).get_file()
		if DEVICE_SIZES.has(name) and int(f["size"]) != int(DEVICE_SIZES[name]):
			out.append({"name": str(f["name"]), "size": int(f["size"]), "want": int(DEVICE_SIZES[name])})
	return out


## What a start does about `romset`'s memory before the core runs: if a file of it cannot be right (`damaged`) the whole folder is set aside, so MAME seeds
## the game from its default image again, and nothing else is ever done: a file of the right size is never touched. Returns {"action": "none" or
## "set_aside", "damaged": the files, "stamp": the copy's stamp, "first_run": nothing was saved before this start}.
static func prepare_launch(save_root: String, romset: String, now: int = -1) -> Dictionary:
	var first := is_first_run(save_root, romset)
	var bad := damaged(save_root, romset)
	if bad.is_empty():
		return {"action": "none", "damaged": bad, "stamp": "", "first_run": first}
	var names: Array[String] = []
	for f in bad:
		names.append("%s is %d bytes, not %d" % [f["name"], f["size"], f["want"]])
	var moved := quarantine(save_root, romset, "damaged at start: " + ", ".join(names), now)
	return {"action": "set_aside" if bool(moved["ok"]) else "none", "damaged": bad, "stamp": str(moved["stamp"]), "first_run": first}


## Set `romset`'s whole memory folder aside. Returns {"ok", "stamp", "to", "error"}: `to` is where the folder now is. `reason` goes in the manifest;
## `now` is a time for the stamp (unix seconds; the clock when negative). Moves, never deletes; fails (and moves nothing) when there is nothing to set aside.
static func quarantine(save_root: String, romset: String, reason: String, now: int = -1) -> Dictionary:
	var src := nvram_dir(save_root, romset)
	var files := _files_of(src)
	if files.is_empty():
		return {"ok": false, "stamp": "", "to": "", "error": "nothing is saved for this game"}
	var when := int(Time.get_unix_time_from_system()) if now < 0 else now
	var stamp := _unique_stamp(save_root, romset, when)
	var box := quarantine_dir(save_root, romset).path_join(stamp)
	var held := box.path_join("nvram")
	if DirAccess.make_dir_recursive_absolute(box) != OK:
		return {"ok": false, "stamp": "", "to": "", "error": "cannot make %s" % box}
	var rows: Array = []
	for f in files:
		rows.append({"name": f["name"], "size": f["size"], "sha1": _sha1_of(src.path_join(str(f["name"])))})
	# The move, a rename on one volume: a folder either moves whole or does not move.
	if DirAccess.rename_absolute(src, held) != OK:
		DirAccess.remove_absolute(box)
		return {"ok": false, "stamp": "", "to": "", "error": "cannot move %s" % src}
	var manifest := {"romset": romset, "stamp": stamp, "when": when, "reason": reason, "files": rows}
	var f_out := FileAccess.open(box.path_join(MANIFEST), FileAccess.WRITE)
	if f_out != null:
		f_out.store_string(JSON.stringify(manifest, "\t"))
		f_out.close()
	prune(save_root, romset)
	return {"ok": true, "stamp": stamp, "to": held, "error": ""}


## Every copy set aside for `romset`, newest first: [{"stamp", "dir", "reason", "when", "files": [{name, size, sha1}]}]. A copy whose manifest is gone or
## unreadable is still listed (it can still be restored): its reason is "".
static func list_quarantines(save_root: String, romset: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var root := quarantine_dir(save_root, romset)
	if not DirAccess.dir_exists_absolute(root):
		return out
	for stamp: String in DirAccess.get_directories_at(root):
		if not DirAccess.dir_exists_absolute(root.path_join(stamp).path_join("nvram")):
			continue
		var row := {"stamp": stamp, "dir": root.path_join(stamp), "reason": "", "when": 0, "files": []}
		var path := root.path_join(stamp).path_join(MANIFEST)
		if FileAccess.file_exists(path):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:
				row["reason"] = str((parsed as Dictionary).get("reason", ""))
				row["when"] = int((parsed as Dictionary).get("when", 0))
				row["files"] = (parsed as Dictionary).get("files", [])
		out.append(row)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["stamp"]) > str(b["stamp"]))
	return out


## Put a set-aside copy back: the exact inverse of `quarantine`, byte for byte. What is in the game's folder now goes into quarantine first (reason "before
## restoring <stamp>"), so a restore never loses what it replaces and can be undone by restoring that. Returns {"ok", "error", "replaced": the stamp the old
## folder was set aside under, or ""}.
static func restore(save_root: String, romset: String, stamp: String, now: int = -1) -> Dictionary:
	var box := quarantine_dir(save_root, romset).path_join(stamp)
	var held := box.path_join("nvram")
	if stamp.is_empty() or not DirAccess.dir_exists_absolute(held):
		return {"ok": false, "error": "that copy is not there", "replaced": ""}
	var replaced := ""
	if not _files_of(nvram_dir(save_root, romset)).is_empty():
		var moved := quarantine(save_root, romset, "before restoring %s" % stamp, now)
		if not bool(moved["ok"]):
			return {"ok": false, "error": str(moved["error"]), "replaced": ""}
		replaced = str(moved["stamp"])
	var dest := nvram_dir(save_root, romset)
	if DirAccess.make_dir_recursive_absolute(dest.get_base_dir()) != OK:
		return {"ok": false, "error": "cannot make %s" % dest.get_base_dir(), "replaced": replaced}
	# An empty folder MAME may have made since is in the way of the rename.
	if DirAccess.dir_exists_absolute(dest):
		DirAccess.remove_absolute(dest)
	if DirAccess.rename_absolute(held, dest) != OK:
		return {"ok": false, "error": "cannot move %s back" % held, "replaced": replaced}
	# The copy is no longer set aside: its manifest and its folder go (the only things this deletes, both ours).
	DirAccess.remove_absolute(box.path_join(MANIFEST))
	DirAccess.remove_absolute(box)
	return {"ok": true, "error": "", "replaced": replaced}


## Keep the newest KEEP_NEWEST copies of `romset`'s: the older ones are the one place this class deletes, and only what it set aside itself.
static func prune(save_root: String, romset: String) -> void:
	var rows := list_quarantines(save_root, romset)
	for i in range(KEEP_NEWEST, rows.size()):
		_remove_tree(str(rows[i]["dir"]))


## The stamp of a moment: UTC, sortable ("20261026T143005Z").
static func stamp_of(unix: int) -> String:
	var d := Time.get_datetime_dict_from_unix_time(unix)
	return "%04d%02d%02dT%02d%02d%02dZ" % [d["year"], d["month"], d["day"], d["hour"], d["minute"], d["second"]]


## A line for a player: what is saved, in words ("2 files, 8.2 KB, saved 3 days ago", "nothing saved yet").
static func summary(info: Dictionary, now: int = -1) -> String:
	var files := info.get("files", []) as Array
	if files.is_empty():
		return "nothing saved yet"
	var when := int(Time.get_unix_time_from_system()) if now < 0 else now
	var age := maxi(0, when - int(info.get("newest", 0)))
	var bytes := int(info.get("bytes", 0))
	var size := ("%d bytes" % bytes) if bytes < 1024 else ("%.1f KB" % (float(bytes) / 1024.0))
	return "%d file%s, %s, saved %s" % [files.size(), "" if files.size() == 1 else "s", size, _ago(age)]


static func _ago(seconds: int) -> String:
	if seconds < 90:
		return "a moment ago"
	if seconds < 3600 * 2:
		return "%d minutes ago" % int(seconds / 60.0)
	if seconds < 86400 * 2:
		return "%d hours ago" % int(seconds / 3600.0)
	return "%d days ago" % int(seconds / 86400.0)


## A stamp no copy of `romset` has yet: the second's own, then -2, -3 for a second that was already used.
static func _unique_stamp(save_root: String, romset: String, when: int) -> String:
	var base := stamp_of(when)
	var stamp := base
	var n := 2
	while DirAccess.dir_exists_absolute(quarantine_dir(save_root, romset).path_join(stamp)):
		stamp = "%s-%d" % [base, n]
		n += 1
	return stamp


## Every file under `dir` (the folder holds one a device, no deeper, but a device's tag may one day carry a path), as {"name": relative, "size", "mtime"} by name.
static func _files_of(dir: String, prefix: String = "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(dir):
		return out
	for name: String in DirAccess.get_files_at(dir):
		var path := dir.path_join(name)
		out.append({"name": prefix + name, "size": _size_of(path), "mtime": FileAccess.get_modified_time(path)})
	for sub: String in DirAccess.get_directories_at(dir):
		out.append_array(_files_of(dir.path_join(sub), prefix + sub + "/"))
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a["name"]) < str(b["name"]))
	return out


static func _size_of(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0
	var n := f.get_length()
	f.close()
	return n


static func _sha1_of(path: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA1)
	ctx.update(FileAccess.get_file_as_bytes(path))
	return ctx.finish().hex_encode()


## A folder and all of it, for a copy this class set aside and is done with.
static func _remove_tree(dir: String) -> void:
	for sub: String in DirAccess.get_directories_at(dir):
		_remove_tree(dir.path_join(sub))
	for name: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(name))
	DirAccess.remove_absolute(dir)
