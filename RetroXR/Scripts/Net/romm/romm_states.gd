## RommStates — RomM's save-state endpoints.
##
##   GET  /api/states?rom_id=N                 list a ROM's states
##   GET  /api/states/{id}/content             download one
##   POST /api/states?rom_id&emulator          create (state + screenshot)
##   PUT  /api/states/{id}                     replace an existing one
##   POST /api/states/delete   {states: [id]}  delete some
##
## A sibling of RommSaves, and deliberately shaped like it — but the API is not
## the same one, and three differences bite:
##
##  1. **There is no `slot`.** POST takes only rom_id and emulator, and
##     StateSchema has no slot field, so identity has to be `file_name` — which
##     is ours to choose. Ours is `<state_id>.state`, minted locally.
##  2. **Deleting is a POST with a list**, not DELETE /api/states/{id}.
##  3. **There is no `overwrite` parameter**, unlike /api/saves. Overwriting is
##     PUT /api/states/{id}, which is why the ledger has to remember the id the
##     server gave a state at upload.
##
## The screenshot is the reason any of this is worth doing over /api/saves:
## StateSchema carries a `screenshot` object, and POST/PUT take `stateFile` and
## `screenshotFile` in ONE multipart body, so a state and its picture come back
## linked and travel together to a new device.
##
## Verified against RomM API 5.1.1-beta.1 (/openapi.json).
##
## Every call blocks, so all of this is worker-thread-only — same contract as
## RommHttp itself. Every call takes an `abort` predicate for the same reason
## RommSaves' do: without one, a teardown that joins the worker waits out the
## whole request.
class_name RommStates

## A state upload can be tens of megabytes, which is minutes on a slow link and
## far past the default response timeout that suits a KB-sized battery save.
const UPLOAD_TIMEOUT_SEC := 300.0


## One state's identity on the server, from RomM's StateSchema.
##
## `screenshot` is a required field of the schema and may be null; flattening it
## to a path here keeps every caller from having to know that.
static func from_schema(raw: Dictionary) -> Dictionary:
	var shot: Variant = raw.get("screenshot")
	return {
		"id": int(raw.get("id", 0)),
		"rom_id": int(raw.get("rom_id", 0)),
		"file_name": str(raw.get("file_name", "")),
		"size": int(raw.get("file_size_bytes", 0)),
		"emulator": str(raw.get("emulator", "")) if raw.get("emulator") != null else "",
		"updated_at": str(raw.get("updated_at", "")),
		"created_at": str(raw.get("created_at", "")),
		"missing": bool(raw.get("missing_from_fs", false)),
		"screenshot_path": str((shot as Dictionary).get("download_path", "")) \
			if shot is Dictionary else "",
	}


## The state_id this filename carries, or "" when the server holds a state some
## other client wrote. A foreign name is listed but never matched against a
## local file, because it would collide with an id we might mint later.
static func id_from_filename(file_name: String) -> String:
	var stem := file_name.get_basename()
	return stem if StatePaths.is_state_id(stem) else ""


## Every state the server holds for one ROM.
## Returns {ok: bool, states: Array[Dictionary], error: String}.
static func list_for_rom(http: RommHttp, headers: PackedStringArray, rom_id: int,
						 abort: Callable = Callable()) -> Dictionary:
	if rom_id <= 0:
		return {"ok": false, "states": [], "error": "This game is not on RomM"}
	var out: Dictionary = http.get_json("/api/states?rom_id=%d" % rom_id, headers, abort)
	if int(out["result"]) != RommHttp.Result.OK:
		return {"ok": false, "states": [], "error": _describe(out)}
	var states: Array[Dictionary] = []
	if out["data"] is Array:
		for item: Variant in out["data"]:
			if item is Dictionary:
				var st := from_schema(item as Dictionary)
				if not st["missing"]:
					states.append(st)
	return {"ok": true, "states": states, "error": ""}


## Pull one state's bytes. Straight to a scratch file and back rather than into
## memory twice: these run to tens of megabytes.
## Returns {ok: bool, bytes: PackedByteArray, error: String}.
static func download(http: RommHttp, headers: PackedStringArray, state_id: int,
					 abort: Callable = Callable()) -> Dictionary:
	var scratch := _scratch_path(state_id)
	var tmp := FileAccess.open(scratch, FileAccess.WRITE)
	if tmp == null:
		return {"ok": false, "bytes": PackedByteArray(), "error": "Cannot write scratch file"}
	var out: Dictionary = http.download_to_file(
		"/api/states/%d/content" % state_id, headers, tmp, Callable(), abort)
	tmp.close()
	if int(out["result"]) != RommHttp.Result.OK:
		DirAccess.remove_absolute(scratch)
		return {"ok": false, "bytes": PackedByteArray(), "error": _describe(out)}
	var bytes := FileAccess.get_file_as_bytes(scratch)
	DirAccess.remove_absolute(scratch)
	return {"ok": true, "bytes": bytes, "error": ""}


## The picture the server holds for a state, or empty bytes. Its path comes off
## StateSchema and is served by nginx with no auth gate, exactly like cover art.
static func download_screenshot(http: RommHttp, headers: PackedStringArray,
								download_path: String,
								abort: Callable = Callable()) -> PackedByteArray:
	if download_path.is_empty():
		return PackedByteArray()
	var scratch := _scratch_path(0) + ".png"
	var tmp := FileAccess.open(scratch, FileAccess.WRITE)
	if tmp == null:
		return PackedByteArray()
	var path := download_path if download_path.begins_with("/") else "/" + download_path
	var out: Dictionary = http.download_to_file(path, headers, tmp, Callable(), abort)
	tmp.close()
	if int(out["result"]) != RommHttp.Result.OK:
		DirAccess.remove_absolute(scratch)
		return PackedByteArray()
	var bytes := FileAccess.get_file_as_bytes(scratch)
	DirAccess.remove_absolute(scratch)
	return bytes


## Create a state on the server, with its picture in the same request.
## Returns {ok: bool, state: Dictionary, error: String} — `state` is the created
## record when RomM echoes one back, so the caller learns its id.
static func create(http: RommHttp, headers: PackedStringArray, rom_id: int,
				   emulator: String, filename: String, bytes: PackedByteArray,
				   shot: PackedByteArray = PackedByteArray(),
				   abort: Callable = Callable()) -> Dictionary:
	var path := "/api/states?rom_id=%d&emulator=%s" % [rom_id, emulator.uri_encode()]
	return _upload(http, HTTPClient.METHOD_POST, path, headers, filename, bytes, shot, abort)


## Replace an existing state's contents — what the tab's overwrite button does
## on the server side. The row keeps its id, so the copy the player is looking
## at is the copy that gets replaced.
static func update(http: RommHttp, headers: PackedStringArray, state_id: int,
				   filename: String, bytes: PackedByteArray,
				   shot: PackedByteArray = PackedByteArray(),
				   abort: Callable = Callable()) -> Dictionary:
	return _upload(http, HTTPClient.METHOD_PUT, "/api/states/%d" % state_id,
		headers, filename, bytes, shot, abort)


static func _upload(http: RommHttp, method: int, path: String,
					headers: PackedStringArray, filename: String,
					bytes: PackedByteArray, shot: PackedByteArray,
					abort: Callable) -> Dictionary:
	var parts: Array = [{
		"field": "stateFile", "filename": filename, "bytes": bytes,
		"mime": "application/octet-stream",
	}]
	# Optional on both verbs, so a state whose thumbnail failed to encode still
	# uploads rather than being held back by its picture.
	if not shot.is_empty():
		parts.append({
			"field": "screenshotFile", "filename": filename.get_basename() + ".png",
			"bytes": shot, "mime": "image/png",
		})
	var out: Dictionary = http.upload_parts(method, path, headers, parts, abort,
		UPLOAD_TIMEOUT_SEC)
	if int(out["result"]) != RommHttp.Result.OK:
		return {"ok": false, "state": {}, "error": _describe(out)}
	var rec: Dictionary = out["data"] as Dictionary if out["data"] is Dictionary else {}
	return {"ok": true, "state": from_schema(rec) if not rec.is_empty() else {}, "error": ""}


## Delete states by server id. POST with a list, NOT DELETE /api/states/{id} —
## that route does not exist.
static func delete(http: RommHttp, headers: PackedStringArray, ids: Array,
				   abort: Callable = Callable()) -> Dictionary:
	if ids.is_empty():
		return {"ok": true, "error": ""}
	var out: Dictionary = http.post_json("/api/states/delete", headers,
		JSON.stringify({"states": ids}), abort)
	if int(out["result"]) != RommHttp.Result.OK:
		return {"ok": false, "error": _describe(out)}
	return {"ok": true, "error": ""}


static func _scratch_path(state_id: int) -> String:
	var dir := CoreDownloadManager.default_core_root().path_join("temp")
	DirAccess.make_dir_recursive_absolute(dir)
	return dir.path_join("romm_state_%d.part" % state_id)


## Same vocabulary as saves and ROM downloads, with one addition: a token minted
## by QR pairing asks for roms.read, platforms.read and collections.read only,
## so the FIRST thing an upload does on a freshly paired device is 403. Saying
## "upload failed" there sends the player looking for a network fault.
## A 403 here is not the read-side "sign in again": a QR-paired token with no
## write access will never be able to upload, and telling that player to sign in
## again sends them round a loop that cannot help them.
static func _describe(out: Dictionary) -> String:
	return RommHttp.describe_error(int(out["result"]), int(out.get("code", 0)),
		"RomM will not accept uploads from this device — its sign-in has no write access")
