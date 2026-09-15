## RommSaves — RomM's battery-save endpoints.
##
##   GET  /api/saves?rom_id=N            list a ROM's saves
##   GET  /api/saves/{id}/content        download one
##   POST /api/saves?rom_id&emulator&slot&overwrite=true   create
##   PUT  /api/saves/{id}                replace an existing one
##
## Every call blocks, so all of this is worker-thread-only — same contract as
## RommHttp itself. RommSaveSync is the only caller and owns the thread.
##
## Every call takes an `abort` predicate, polled by RommHttp between chunks.
## Passing one is what makes the worker joinable on demand: without it the call
## runs to its own timeout no matter what the main thread wants, and a teardown
## that joins the thread waits out the whole request.
class_name RommSaves


## A save's identity on the server, from RomM's SaveSchema.
## `content_hash` is what makes three-way sync possible; RomM computes it, so a
## local md5 can be compared against what the server believes it holds.
static func from_schema(d: Dictionary) -> Dictionary:
	return {
		"id": int(d.get("id", 0)),
		"rom_id": int(d.get("rom_id", 0)),
		"file_name": str(d.get("file_name", "")),
		"size": int(d.get("file_size_bytes", 0)),
		"slot": str(d.get("slot", "")) if d.get("slot") != null else "",
		"emulator": str(d.get("emulator", "")) if d.get("emulator") != null else "",
		"content_hash": str(d.get("content_hash", "")) if d.get("content_hash") != null else "",
		"updated_at": str(d.get("updated_at", "")),
		"missing": bool(d.get("missing_from_fs", false)),
	}


## Every save the server holds for this user on one platform.
##
## `platform_id` is RomM's NUMERIC id (PlayStation is 178 here) — passing a slug
## is a 422, which is what made this look unfilterable at first. It genuinely
## filters: asking for NES returns none of the PlayStation saves.
##
## Narrowing on the server matters. Picking memory-card saves out by their .mcs
## extension alone would happily offer a save uploaded against some other
## console, and the restore path writes into a card.
##
## platform_id <= 0 asks for everything, which is only useful for diagnostics.
## Returns {ok: bool, saves: Array[Dictionary], error: String}.
static func list_all(http: RommHttp, headers: PackedStringArray,
					 platform_id: int = 0, abort: Callable = Callable()) -> Dictionary:
	var path := "/api/saves"
	if platform_id > 0:
		path += "?platform_id=%d" % platform_id
	var out: Dictionary = http.get_json(path, headers, abort)
	if int(out["result"]) != RommHttp.Result.OK:
		return {"ok": false, "saves": [], "error": _describe(out)}
	var saves: Array[Dictionary] = []
	if out["data"] is Array:
		for item: Variant in out["data"]:
			if item is Dictionary:
				var s := from_schema(item as Dictionary)
				if not s["missing"]:
					saves.append(s)
	return {"ok": true, "saves": saves, "error": ""}


## A ROM's display name, or "" — used to say which game a save belongs to.
static func rom_info(http: RommHttp, headers: PackedStringArray, rom_id: int,
					 abort: Callable = Callable()) -> Dictionary:
	var info := {"name": "", "md5": ""}
	var out: Dictionary = http.get_json("/api/roms/%d" % rom_id, headers, abort)
	if int(out["result"]) != RommHttp.Result.OK or not (out["data"] is Dictionary):
		return info
	var data := out["data"] as Dictionary
	info["name"] = str(data.get("name", ""))
	# Null when the server has not hashed the ROM.
	var md5: Variant = data.get("md5_hash")
	info["md5"] = (md5 as String).to_lower() if md5 is String else ""
	return info


## Every save the server holds for one ROM, newest first.
## Returns {ok: bool, saves: Array[Dictionary], error: String}.
static func list(http: RommHttp, headers: PackedStringArray, rom_id: int,
				 abort: Callable = Callable()) -> Dictionary:
	var out: Dictionary = http.get_json("/api/saves?rom_id=%d" % rom_id, headers, abort)
	if int(out["result"]) != RommHttp.Result.OK:
		return {"ok": false, "saves": [], "error": _describe(out)}

	var saves: Array[Dictionary] = []
	if out["data"] is Array:
		for item: Variant in out["data"]:
			if item is Dictionary:
				var s := from_schema(item as Dictionary)
				# A record whose file is gone cannot be downloaded; leaving it
				# out makes the row read "not on the server", which is true.
				if not s["missing"]:
					saves.append(s)
	return {"ok": true, "saves": saves, "error": ""}


## Fetch one save's bytes.
## Returns {ok: bool, bytes: PackedByteArray, error: String}.
static func download(http: RommHttp, headers: PackedStringArray, save_id: int,
					 abort: Callable = Callable()) -> Dictionary:
	# Straight into memory rather than download_to_file: saves are small, and
	# the caller has to hash the bytes before deciding where they go.
	var tmp := FileAccess.open(_scratch_path(save_id), FileAccess.WRITE)
	if tmp == null:
		return {"ok": false, "bytes": PackedByteArray(), "error": "Cannot write scratch file"}

	var out: Dictionary = http.download_to_file(
		"/api/saves/%d/content" % save_id, headers, tmp, Callable(), abort)
	tmp.close()

	if int(out["result"]) != RommHttp.Result.OK:
		DirAccess.remove_absolute(_scratch_path(save_id))
		return {"ok": false, "bytes": PackedByteArray(), "error": _describe(out)}

	var bytes := FileAccess.get_file_as_bytes(_scratch_path(save_id))
	DirAccess.remove_absolute(_scratch_path(save_id))
	return {"ok": true, "bytes": bytes, "error": ""}


## Create a save on the server.
## Returns {ok: bool, save: Dictionary, error: String} — `save` is the created
## record when RomM echoes one back, so the caller learns its id.
static func create(http: RommHttp, headers: PackedStringArray, rom_id: int,
				   emulator: String, slot: String, filename: String,
				   bytes: PackedByteArray) -> Dictionary:
	var path := "/api/saves?rom_id=%d&emulator=%s&slot=%s&overwrite=true" % [
		rom_id, emulator.uri_encode(), slot.uri_encode()]
	var out: Dictionary = http.upload_multipart(
		HTTPClient.METHOD_POST, path, headers, "saveFile", filename, bytes)
	if int(out["result"]) != RommHttp.Result.OK:
		return {"ok": false, "save": {}, "error": _describe(out)}
	var rec: Dictionary = out["data"] as Dictionary if out["data"] is Dictionary else {}
	return {"ok": true, "save": from_schema(rec) if not rec.is_empty() else {}, "error": ""}


## Replace an existing save's contents.
static func update(http: RommHttp, headers: PackedStringArray, save_id: int,
				   filename: String, bytes: PackedByteArray) -> Dictionary:
	var out: Dictionary = http.upload_multipart(
		HTTPClient.METHOD_PUT, "/api/saves/%d" % save_id, headers,
		"saveFile", filename, bytes)
	if int(out["result"]) != RommHttp.Result.OK:
		return {"ok": false, "save": {}, "error": _describe(out)}
	var rec: Dictionary = out["data"] as Dictionary if out["data"] is Dictionary else {}
	return {"ok": true, "save": from_schema(rec) if not rec.is_empty() else {}, "error": ""}


static func _scratch_path(save_id: int) -> String:
	var dir := CoreDownloadManager.default_core_root().path_join("temp")
	DirAccess.make_dir_recursive_absolute(dir)
	return dir.path_join("romm_save_%d.part" % save_id)


## Same vocabulary the ROM downloader uses, so a save failure and a ROM failure
## read the same way in the notification bar.
static func _describe(out: Dictionary) -> String:
	return RommHttp.describe_error(int(out["result"]), int(out.get("code", 0)))
