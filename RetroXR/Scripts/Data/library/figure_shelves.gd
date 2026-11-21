## FigureShelves — the shelves of figures a reader or a base takes, one folder of
## dumps each under roms/<systemid>, subfolders and all:
##
##   amiibo          NTAG215, 540 bytes (572 with the signature), on the Wii U
##                   GamePad's NFC touchpoint (NfcTouchZone)
##   skylanders      MIFARE Classic 1K, 1024 bytes, on the Portal of Power
##   disneyinfinity  320 bytes, on the Infinity Base
##   legodimensions  NTAG213, 180 bytes, on the Toy Pad
##
## A file counts when it is that tag: an amiibo by its lock and config bytes,
## the test Cemu's nn_nfp makes (the 2048-byte Switch 2 dumps fail it); a
## Skylander, an Infinity figure or a Dimensions tag by its size, a Skylander's
## UID check byte and a Dimensions tag's NXP maker byte. So a stray .bin in a
## folder is left off its shelf, and a figure is never offered to another
## line's base. No key is needed: Cemu decrypts with its own.
##
## A figure's name is its file's, and its series the folder it is in, since one
## character comes in several ("Donkey Kong" is a Smash amiibo and a Mario
## Sports card). An amiibo under a folder with "card" in its name is a card.
class_name FigureShelves
extends RefCounted

const AMIIBO := "amiibo"
const SKYLANDERS := "skylanders"
const INFINITY := "disneyinfinity"
const DIMENSIONS := "legodimensions"
const SYSTEMIDS: Array[String] = [AMIIBO, SKYLANDERS, INFINITY, DIMENSIONS]

## The accessory interface's kind for each base's figures (AccessoryInterface.hpp).
const KIND_SKYLANDER := 1
const KIND_INFINITY := 2
const KIND_DIMENSIONS := 3

const SPECS := {
	AMIIBO: {"exts": ["bin"], "read": 540},
	SKYLANDERS: {"exts": ["sky", "bin", "dump", "dmp"], "size": 1024, "kind": KIND_SKYLANDER},
	INFINITY: {"exts": ["bin"], "size": 320, "kind": KIND_INFINITY},
	DIMENSIONS: {"exts": ["bin"], "size": 180, "kind": KIND_DIMENSIONS},
}

## amiibo: what the room's NFC reader (NfcReader.hpp) serves, the tag's 135 pages.
const TAG_BYTES := 540
const _LOCK_AT := 0x0A
const _LOCK := [0x0F, 0xE0]
const _CC_AT := 0x0C
const _CC := [0xF1, 0x10, 0xFF, 0xEE]
const _CFG_AT := 0x20C
const _CFG := [0x00, 0x00, 0x00, 0x04, 0x5F, 0x00, 0x00, 0x00]
## Character, variant, type, model number and series: pages 21-22, in the clear.
const _ID_AT := 0x54

## systemid -> {rows, dir, by_path}, each shelf scanned once per folder.
static var _shelves: Dictionary = {}
## systemid -> {id, dir, rows, listeners}, the worker scan in flight.
static var _tasks: Dictionary = {}
static var _task_mutex := Mutex.new()


static func handles(systemid: String) -> bool:
	return SPECS.has(systemid)


## The accessory kind a base reads this shelf's figures as, or -1 (amiibo: NFC).
static func kind_of(systemid: String) -> int:
	return int((SPECS.get(systemid, {}) as Dictionary).get("kind", -1))


## True when `bytes` (a file's first bytes; `length` the file's) is one of this
## shelf's figures.
static func is_dump(systemid: String, bytes: PackedByteArray, length: int = -1) -> bool:
	if length < 0:
		length = bytes.size()
	match systemid:
		AMIIBO:
			if bytes.size() < TAG_BYTES:
				return false
			return _has(bytes, _LOCK_AT, _LOCK) and _has(bytes, _CC_AT, _CC) and _has(bytes, _CFG_AT, _CFG)
		SKYLANDERS:
			# Block 0: the four-byte UID and its check byte, their XOR.
			return length == 1024 and bytes.size() >= 5 \
				and (bytes[0] ^ bytes[1] ^ bytes[2] ^ bytes[3]) == bytes[4]
		INFINITY:
			return length == 320
		DIMENSIONS:
			# Page 0 opens with NXP's maker code, as every NTAG's UID does.
			return length == 180 and bytes.size() >= 1 and bytes[0] == 0x04
	return false


static func _has(bytes: PackedByteArray, at: int, want: Array) -> bool:
	for i in want.size():
		if bytes[at + i] != int(want[i]):
			return false
	return true


## An amiibo's 8-byte id (character, variant, type, model, series) as 16 hex
## digits, the key amiibo databases use.
static func figure_id(bytes: PackedByteArray) -> String:
	return bytes.slice(_ID_AT, _ID_AT + 8).hex_encode() if bytes.size() >= _ID_AT + 8 else ""


## True when an amiibo at this path is a card rather than a figure.
static func is_card_path(path: String) -> bool:
	return path.replace("\\", "/").get_base_dir().to_lower().contains("card")


## One shelf row for a dump, or {} when the file is not one of this shelf's.
static func row_for(systemid: String, path: String, root: String = "") -> Dictionary:
	var spec: Dictionary = SPECS.get(systemid, {})
	if spec.is_empty() or path.get_extension().to_lower() not in (spec["exts"] as Array):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var length := int(f.get_length())
	var bytes := f.get_buffer(int(spec.get("read", 8)))
	f.close()
	if not is_dump(systemid, bytes, length):
		return {}
	var name := path.get_file().get_basename()
	var series := path.get_base_dir().get_file()
	if not root.is_empty() and path.get_base_dir().simplify_path() == root.simplify_path():
		series = ""
	return {
		"systemid": systemid,
		"path": path,
		"name": name,
		"series": series,
		"label": name if series.is_empty() else "%s (%s)" % [name, series],
		"is_card": systemid == AMIIBO and is_card_path(path),
		"id": figure_id(bytes) if systemid == AMIIBO else "",
	}


static func _dir(systemid: String, dir: String) -> String:
	return dir if not dir.is_empty() else RomLibrary.rom_dir_for_system(systemid)


## Every dump on a shelf (default: its folder under roms), by label.
static func figures(systemid: String, dir: String = "") -> Array[Dictionary]:
	var path := _dir(systemid, dir)
	var shelf: Dictionary = _shelves.get(systemid, {})
	if str(shelf.get("dir", "")) == path:
		return shelf["rows"]
	if _tasks.has(systemid) and str(_tasks[systemid]["dir"]) == path:
		_finish_async(systemid)
		return (_shelves[systemid] as Dictionary)["rows"]
	_store(systemid, path, list_dumps(systemid, path))
	return (_shelves[systemid] as Dictionary)["rows"]


static func is_warm(systemid: String, dir: String = "") -> bool:
	return str((_shelves.get(systemid, {}) as Dictionary).get("dir", "")) == _dir(systemid, dir)


## Scan on a worker thread, then call `on_done` on the main thread.
static func warm_async(systemid: String, dir: String = "", on_done: Callable = Callable()) -> void:
	var path := _dir(systemid, dir)
	if is_warm(systemid, path):
		if on_done.is_valid():
			on_done.call_deferred()
		return
	if _tasks.has(systemid):
		if str(_tasks[systemid]["dir"]) == path:
			if on_done.is_valid():
				(_tasks[systemid]["listeners"] as Array).append(on_done)
			return
		_finish_async(systemid)
	var task := {"dir": path, "rows": [], "listeners": [on_done] if on_done.is_valid() else []}
	_tasks[systemid] = task
	task["id"] = WorkerThreadPool.add_task(_scan_task.bind(systemid, path), false, "FigureShelves scan")


static func _scan_task(systemid: String, path: String) -> void:
	var rows := list_dumps(systemid, path)
	_task_mutex.lock()
	if _tasks.has(systemid):
		_tasks[systemid]["rows"] = rows
	_task_mutex.unlock()
	FigureShelves._finish_async.call_deferred(systemid)


static func _finish_async(systemid: String) -> void:
	if not _tasks.has(systemid):
		return
	var task: Dictionary = _tasks[systemid]
	WorkerThreadPool.wait_for_task_completion(int(task["id"]))
	_tasks.erase(systemid)
	_task_mutex.lock()
	var rows: Array[Dictionary] = []
	rows.assign(task["rows"])
	_task_mutex.unlock()
	_store(systemid, str(task["dir"]), rows)
	for cb: Callable in task["listeners"]:
		if cb.is_valid():
			cb.call()


## The dumps under `root`, every subfolder included. Pure file I/O, safe off-thread.
static func list_dumps(systemid: String, root: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dirs: Array[String] = [root]
	while not dirs.is_empty():
		var at: String = dirs.pop_back()
		var d := DirAccess.open(at)
		if d == null:
			continue
		d.list_dir_begin()
		var name := d.get_next()
		while not name.is_empty():
			if name.begins_with("."):
				pass
			elif d.current_is_dir():
				dirs.append(at.path_join(name))
			else:
				var row := row_for(systemid, at.path_join(name), root)
				if not row.is_empty():
					out.append(row)
			name = d.get_next()
		d.list_dir_end()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a["label"]).naturalnocasecmp_to(str(b["label"])) < 0)
	return out


static func _store(systemid: String, path: String, rows: Array[Dictionary]) -> void:
	var by_path: Dictionary = {}
	for r: Dictionary in rows:
		by_path[_key(str(r["path"]))] = r
	_shelves[systemid] = {"rows": rows, "dir": path, "by_path": by_path}


static func _key(path: String) -> String:
	return path.replace("\\", "/").to_lower()


## Forget a shelf's scan (every shelf's with ""), after its folder is written to.
static func invalidate(systemid: String = "") -> void:
	for sid: String in (SYSTEMIDS if systemid.is_empty() else [systemid] as Array[String]):
		if _tasks.has(sid):
			_finish_async(sid)
		_shelves.erase(sid)


## The shelf row for a dump's path, or {} when it is not one of the shelf's. Falls
## back to reading the one file, so a figure from a save outside the folder still
## names itself.
static func figure_for_path(systemid: String, path: String) -> Dictionary:
	if path.is_empty():
		return {}
	var shelf: Dictionary = _shelves.get(systemid, {})
	var hit: Variant = (shelf.get("by_path", {}) as Dictionary).get(_key(path))
	if hit != null:
		return hit as Dictionary
	return row_for(systemid, path)
