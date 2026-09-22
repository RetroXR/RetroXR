## FirmwareInstaller — fetches BIOS files and core support archives into the
## per-core libretro system directories.
##
## Three job kinds:
##   FILE    one firmware file written to N destinations. A BIOS is often
##           declared by several cores for the same machine, and the system dir
##           is per-core, so one download fans out to every core that wants it.
##   ARCHIVE a buildbot support zip, unpacked into one core's system dir with
##           its internal paths preserved.
##   PACK    several zips from their own hosts, each unpacked from a folder
##           inside it into a folder of one core's system dir
##           (SystemAssetCatalog.PACKS).
##   WII_MENU the Wii System Menu, installed into dolphin's NAND by the core
##           itself (WiiSystemMenu). No file passes through here: the core
##           downloads, decrypts and imports each title, and reports progress
##           in titles, not bytes.
##
## Deliberately not built on RommDownloader: that class keys everything on a
## rom_id, writes into the ROM dir, merges gamelist.json and takes part in LRU
## cache eviction — none of which applies here, and a BIOS must never be evicted
## out from under a core. The retry/backoff shape and the error classification
## are the same, because those parts were right.
##
## RommHttp is reused verbatim for both sources. It is a plain blocking
## HTTPClient with no RomM in it beyond the name, and it brings resumable Range
## requests, which HTTPRequest does not — worth having for a 79 MB archive.
class_name FirmwareInstaller
extends Node


## key identifies the job for the UI and the toast; it is the caller's to choose.
signal job_started(key: String, label: String, total_bytes: int)
signal job_progress(key: String, received: int, total: int)
## An archive's second phase, counted in files: Dolphin.zip is 3 MB to fetch and
## 2,720 files to write, and the bar sat at 100% for all of the second part.
signal job_unpacking(key: String, done: int, total: int)
signal job_retrying(key: String, attempt: int, max_attempts: int, reason: String)
signal job_finished(key: String, ok: bool, error: String)
signal job_cancelled(key: String)

const MAX_RETRIES := 3

## Members per RommArchiveExtractor call. Each call re-reads the central
## directory, so this trades that cost against how often progress and a cancel
## get a word in.
const UNPACK_BATCH := 250

## GitHub answers a release asset with one hop to a signed link; the rest is slack.
const MAX_REDIRECTS := 5

enum Kind { FILE, ARCHIVE, PACK, WII_MENU }

var _queue: Array[Dictionary] = []
var _thread: Thread = null
var _abort := false
var _current_key := ""


func _exit_tree() -> void:
	cancel_all()
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
		_thread = null


func is_busy() -> bool:
	return _current_key != ""


func current_key() -> String:
	return _current_key


func queued_count() -> int:
	return _queue.size()


func is_queued(key: String) -> bool:
	if _current_key == key:
		return true
	for j: Dictionary in _queue:
		if str(j["key"]) == key:
			return true
	return false


## Fetch one firmware file and write it to every path in `dests`.
##   base_url  server root, e.g. "http://192.168.0.106:8080"
##   path      absolute request path, e.g. "/api/firmware/24/content/gba_bios.bin"
##   headers   auth headers, or empty for an unauthenticated host
##   md5       expected checksum, "" to skip verification
func enqueue_file(key: String, label: String, base_url: String, path: String,
				  headers: PackedStringArray, dests: Array[String],
				  expected_size: int = 0, md5: String = "") -> void:
	if key.is_empty() or dests.is_empty() or is_queued(key):
		return
	_queue.append({
		"kind": Kind.FILE, "key": key, "label": label,
		"base_url": base_url, "path": path, "headers": headers,
		"dests": dests, "size": expected_size, "md5": md5.to_lower(),
	})
	_pump()


## Fetch a buildbot support archive and unpack it into `core_name`'s system dir.
func enqueue_archive(key: String, core_name: String) -> void:
	if key.is_empty() or is_queued(key):
		return
	var a := SystemAssetCatalog.archive_for(core_name)
	if a.is_empty():
		return
	_queue.append({
		"kind": Kind.ARCHIVE, "key": key,
		"label": str(a["label"]), "core_name": core_name,
		"base_url": SystemAssetCatalog.BASE_URL,
		"path": SystemAssetCatalog.archive_path(core_name),
		"headers": PackedStringArray(), "size": 0,
	})
	_pump()


## Fetch a pack into `core_name`'s system dir. Parts already installed are
## skipped, so the library two packs share is downloaded once; `repair` fetches
## every part again, which is how a damaged file is replaced.
func enqueue_pack(key: String, core_name: String, pack_id: String, repair: bool = false) -> void:
	if key.is_empty() or is_queued(key):
		return
	var pack := SystemAssetCatalog.pack_for(core_name, pack_id)
	var dir := CoreDownloadManager.default_system_dir(core_name)
	var parts: Array[Dictionary] = []
	for part: Dictionary in SystemAssetCatalog.pack_parts(pack):
		if repair or not SystemAssetCatalog.part_installed(dir, part):
			parts.append(part)
	if parts.is_empty():
		return
	_queue.append({
		"kind": Kind.PACK, "key": key, "label": str(pack["label"]),
		"dir": dir, "parts": parts,
	})
	_pump()


## Install the Wii System Menu for `region` ("USA", "EUR", "JPN", "KOR").
## Refused while a Dolphin machine is switched on: the core would be writing
## the NAND that machine has open.
func enqueue_wii_menu(key: String, region: String) -> void:
	if key.is_empty() or is_queued(key):
		return
	var busy := _dolphin_machines_on()
	if not busy.is_empty():
		var label := "Wii System Menu"
		var why := "switch off %s first" % ", ".join(busy)
		(func() -> void:
			job_started.emit(key, label, 0)
			job_finished.emit(key, false, why)).call_deferred()
		return
	_queue.append({
		"kind": Kind.WII_MENU, "key": key,
		"label": "Wii System Menu (%s)" % region, "region": region,
	})
	_pump()


## Stop the running job. Its partial file is kept, so a retry resumes.
func cancel_current() -> void:
	_abort = true


## Stop one job by key, whether it is running or still waiting.
##
## The fetch-all button queues dozens at once, and `cancel_current` on a row
## whose turn has not come yet would abort a stranger's download instead. A
## queued job never reached the worker, so it is dropped here and announced
## directly — `_emit_cancelled` must not run for it: that clears `_current_key`
## and pumps, which would strand the job actually in flight.
func cancel(key: String) -> void:
	if _current_key == key:
		_abort = true
		return
	for i in range(_queue.size()):
		if str(_queue[i]["key"]) == key:
			_queue.remove_at(i)
			job_cancelled.emit(key)
			return


func cancel_all() -> void:
	_queue.clear()
	_abort = true


# ── Queue ─────────────────────────────────────────────────────────────────────

func _pump() -> void:
	if is_busy() or _queue.is_empty():
		return
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()
		_thread = null

	var job: Dictionary = _queue.pop_front()
	_abort = false
	_current_key = str(job["key"])

	_thread = Thread.new()
	_thread.start(_worker.bind(job))


func _worker(job: Dictionary) -> void:
	if int(job["kind"]) == Kind.PACK:
		_run_pack(job)
		return
	if int(job["kind"]) == Kind.WII_MENU:
		_run_wii_menu(job)
		return

	var key := str(job["key"])
	var staging := _staging_path(key)
	DirAccess.make_dir_recursive_absolute(staging.get_base_dir())

	# Announced from here, not from _pump, because the size has to be asked for
	# and asking blocks. A caller that already knows it (RomM states a firmware
	# file's size in its API) is taken at its word; an archive costs one HEAD.
	job["size"] = _probe_size(job)
	_emit_started.call_deferred(key, str(job["label"]), int(job["size"]))

	var fetched := _transfer(job, staging)
	if str(fetched["state"]) == "cancelled":
		_emit_cancelled.call_deferred(key)
		return
	if str(fetched["state"]) == "failed":
		_emit_finished.call_deferred(key, false, str(fetched["error"]))
		return

	var placed := _place(job, staging)
	DirAccess.remove_absolute(staging)
	if bool(placed.get("cancelled", false)):
		_emit_cancelled.call_deferred(key)
		return
	_emit_finished.call_deferred(key, bool(placed["ok"]), str(placed.get("error", "")))


## Each part is its own download and its own bar, announced under the part's
## label, so a toast says which of the pack's zips is moving. The job finishes
## once, after the last part, or at the first part that fails.
func _run_pack(job: Dictionary) -> void:
	var key := str(job["key"])
	var parts: Array = job["parts"]
	for i in range(parts.size()):
		var part: Dictionary = parts[i]
		var sub := {
			"kind": Kind.PACK, "key": key, "url": str(part["url"]),
			"headers": PackedStringArray(), "size": 0,
		}
		var staging := _staging_path("%s-%s" % [key, str(part.get("id", i))])
		DirAccess.make_dir_recursive_absolute(staging.get_base_dir())

		sub["size"] = _probe_size(sub)
		_emit_started.call_deferred(key, str(part["label"]), int(sub["size"]))

		var fetched := _transfer(sub, staging)
		if str(fetched["state"]) == "cancelled":
			_emit_cancelled.call_deferred(key)
			return
		if str(fetched["state"]) == "failed":
			_emit_finished.call_deferred(key, false, str(fetched["error"]))
			return

		var placed := _extract(key, staging, str(job["dir"]),
			str(part.get("from", "")), str(part.get("into", "")),
			PackedStringArray(part.get("only", [])))
		DirAccess.remove_absolute(staging)
		if bool(placed.get("cancelled", false)):
			_emit_cancelled.call_deferred(key)
			return
		if not bool(placed["ok"]):
			_emit_finished.call_deferred(key, false, str(placed.get("error", "")))
			return

	_emit_finished.call_deferred(key, true, "")


## The core does all of it, so there is no retry loop here: Dolphin's updater
## skips every title already installed, so pressing the button again resumes.
## A cancel lands between titles, not inside one.
func _run_wii_menu(job: Dictionary) -> void:
	var key := str(job["key"])
	_emit_started.call_deferred(key, str(job["label"]), 0)
	var progress := func(processed: int, total: int, _title: String) -> bool:
		_emit_progress.call_deferred(key, processed, total)
		return not _abort
	var result := WiiSystemMenu.run(str(job["region"]), progress)
	if result == WiiSystemMenu.RESULT_CANCELLED or (_abort and not WiiSystemMenu.succeeded(result)):
		_emit_cancelled.call_deferred(key)
		return
	_emit_finished.call_deferred(key, WiiSystemMenu.succeeded(result),
		WiiSystemMenu.result_text(result))


static func _dolphin_machines_on() -> PackedStringArray:
	var out := PackedStringArray()
	if not Engine.get_main_loop() is SceneTree:
		return out
	for node: Node in (Engine.get_main_loop() as SceneTree).get_nodes_in_group("retro_system"):
		if not is_instance_valid(node) or not bool(node.get("is_powered_on")):
			continue
		if node.has_method("resolve_core_name") and str(node.resolve_core_name()) == WiiSystemMenu.CORE:
			out.append(str(node.get("system_label")) if node.get("system_label") != null else node.name)
	return out


## Download into `staging`, retrying what is worth retrying.
## Returns {state: "ok" | "cancelled" | "failed", error: String}.
func _transfer(job: Dictionary, staging: String) -> Dictionary:
	var key := str(job["key"])
	var attempt := 0
	var last_error := ""
	while attempt < MAX_RETRIES:
		if _abort:
			return {"state": "cancelled", "error": ""}

		if attempt > 0:
			_emit_retrying.call_deferred(key, attempt + 1, MAX_RETRIES, last_error)
			# Sliced so a cancel lands during the backoff, not after it.
			var wait_ms := int(pow(2.0, attempt) * 1000.0)
			var waited := 0
			while waited < wait_ms and not _abort:
				OS.delay_msec(100)
				waited += 100
			if _abort:
				return {"state": "cancelled", "error": ""}

		var res := _attempt(job, staging)
		var status := str(res["status"])
		last_error = str(res.get("error", ""))

		if status == "ok":
			return {"state": "ok", "error": ""}
		if status == "cancelled":
			return {"state": "cancelled", "error": ""}
		if status == "terminal":
			return {"state": "failed", "error": last_error}
		if status == "restart":
			DirAccess.remove_absolute(staging)
		attempt += 1

	return {"state": "failed", "error": last_error}


## Ask the server how big the download is, for the toast and the progress bar.
## Purely cosmetic: a probe that fails leaves the size unknown, which the UI
## already renders as a bare label, and the transfer proceeds regardless.
func _probe_size(job: Dictionary) -> int:
	var declared := int(job.get("size", 0))
	if declared > 0:
		return declared
	if job.has("url"):
		var where := _resolve(str(job["url"]))
		return int(where.get("total", 0)) if str(where["status"]) == "ok" else 0

	var http := RommHttp.new()
	if http.open(str(job["base_url"])) != RommHttp.Result.OK:
		return 0
	var out := http.head(str(job["path"]), PackedStringArray(job["headers"]))
	http.close()

	var code := int(out.get("code", 0))
	if int(out["result"]) != RommHttp.Result.OK or code < 200 or code >= 300:
		return 0
	return int(out["total"])


## One transfer into the staging file. Resumes when a partial is already there.
func _attempt(job: Dictionary, staging: String) -> Dictionary:
	var key := str(job["key"])
	# Resolved on every attempt, not once: GitHub's signed link expires within
	# the hour, and a retry after a long stall would otherwise ask for a dead one.
	if job.has("url"):
		var where := _resolve(str(job["url"]))
		if str(where["status"]) != "ok":
			return where
		job["base_url"] = where["base_url"]
		job["path"] = where["path"]
	var expected := int(job.get("size", 0))

	var have := 0
	var f: FileAccess = null
	if FileAccess.file_exists(staging):
		f = FileAccess.open(staging, FileAccess.READ_WRITE)
		if f != null:
			f.seek_end()
			have = int(f.get_position())
	if f == null:
		f = FileAccess.open(staging, FileAccess.WRITE)
	if f == null:
		return {"status": "terminal", "error": "Cannot write to %s" % staging.get_base_dir()}

	var http := RommHttp.new()
	var opened := http.open(str(job["base_url"]))
	if opened != RommHttp.Result.OK:
		f.close()
		return {"status": "transient", "error": "Cannot reach the server"}

	var headers := PackedStringArray(job["headers"])
	headers.append("Range: bytes=%d-" % have)

	var progress := func(received: int, total: int) -> void:
		_emit_progress.call_deferred(
			key, have + received, have + total if total > 0 else expected)

	var out: Dictionary = http.download_to_file(
		str(job["path"]), headers, f, progress, func() -> bool: return _abort)
	f.close()
	http.close()

	var result := int(out["result"])
	var code := int(out.get("code", 0))

	if result == RommHttp.Result.ABORTED:
		return {"status": "cancelled"}
	if result == RommHttp.Result.WRITE_FAILED:
		return {"status": "terminal", "error": "Not enough space, or the disk is unwritable"}
	if result == RommHttp.Result.CONNECT_FAILED or result == RommHttp.Result.REQUEST_FAILED:
		return {"status": "transient", "error": "Connection lost"}
	if result == RommHttp.Result.TIMED_OUT:
		return {"status": "transient", "error": "The server took too long to answer"}
	if result == RommHttp.Result.HTTP_ERROR:
		if code == 401 or code == 403:
			if job.has("url"):
				return {"status": "terminal", "error": "The server refused the download (%d)" % code}
			return {"status": "terminal", "error": "Sign in to RomM again"}
		if code == 404:
			DirAccess.remove_absolute(staging)
			return {"status": "terminal", "error": "Not available on the server"}
		if code == 416:
			# Already had the whole thing, or the file changed underneath us.
			return {"status": "restart", "error": "File changed on the server"}
		if code >= 500:
			return {"status": "transient", "error": "Server error (%d)" % code}
		return {"status": "terminal", "error": "Server refused the download (%d)" % code}

	# Completeness is judged against this response's Content-Length and nothing
	# else. HTTPClient leaves STATUS_BODY both when the body ends and when the
	# socket dies mid-stream, so without this a truncated archive would install
	# silently; and any size known ahead of the request would only be a guess.
	if have > 0 and code == 200:
		# Range ignored — the full body was appended onto the partial. Must be
		# caught by status, since have + total then equals the corrupt length.
		return {"status": "restart", "error": "The server did not resume the download"}

	var got := ByteSize.on_disk(staging)
	var whole := have + int(out.get("total", 0))
	if whole > have and got != whole:
		return {"status": "restart",
			"error": "Incomplete download (%d of %d bytes)" % [got, whole]}

	var want := str(job.get("md5", ""))
	if not want.is_empty() and FileAccess.get_md5(staging).to_lower() != want:
		return {"status": "restart", "error": "Downloaded file was corrupt"}

	return {"status": "ok"}


## Move the staged download into place. Runs on the worker thread.
func _place(job: Dictionary, staging: String) -> Dictionary:
	if int(job["kind"]) == Kind.ARCHIVE:
		var dir := CoreDownloadManager.default_system_dir(str(job["core_name"]))
		return _extract_preserving_paths(str(job["key"]), staging, dir)

	var written := 0
	for dest: String in job["dests"]:
		DirAccess.make_dir_recursive_absolute(dest.get_base_dir())
		var bytes := FileAccess.get_file_as_bytes(staging)
		if bytes.is_empty():
			return {"ok": false, "error": "Staged file vanished"}
		var out := FileAccess.open(dest, FileAccess.WRITE)
		if out == null:
			return {"ok": false, "error": "Cannot write %s" % dest.get_file()}
		out.store_buffer(bytes)
		var err := out.get_error()
		out.close()
		if err != OK:
			return {"ok": false, "error": "Write failed for %s" % dest.get_file()}
		written += 1
	return {"ok": written > 0, "error": "" if written > 0 else "Nothing was written"}


## Unpack keeping the archive's own directory structure.
##
## Explicitly NOT CoreDownloadManager._extract_zip, which flattens every entry
## into one directory. That is right for a core zip (a single .dll) and wrong
## here: PPSSPP.zip's ppge_atlas.zim has to land in PPSSPP/, and ScummVM.zip
## carries a two-level theme/extra tree.
##
## Not ZIPReader.read_file either: it finds a member by walking the central
## directory from the top, so an archive costs the square of its member count.
## Dolphin.zip's 2,720 files took 26 s that way on a desktop, and minutes on a
## headset. RommArchiveExtractor indexes the directory once and streams.
##
## That extractor refuses to overwrite, and re-running an archive is how a bad
## file gets repaired, so the members land in a scratch tree beside the download
## and are then moved over the system dir.
func _extract_preserving_paths(key: String, zip_path: String, dest_dir: String) -> Dictionary:
	return _extract(key, zip_path, dest_dir, "", "", PackedStringArray())


## Unpack the members under `from` to `into` inside dest_dir, keeping their
## paths below it: `vosk-model-small-ja-0.22/graph/words.txt` with from
## `vosk-model-small-ja-0.22/` and into `vru/model-ja/` lands at
## `vru/model-ja/graph/words.txt`. A non-empty `only` keeps just those paths
## below `from`, which is how a library zip leaves its headers and import
## library behind. Members outside `from` are not unpacked at all.
func _extract(key: String, zip_path: String, dest_dir: String,
		from: String, into: String, only: PackedStringArray) -> Dictionary:
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		return {"ok": false, "error": "Could not open the downloaded archive"}
	var members := reader.get_files()
	reader.close()

	var scratch := zip_path.get_basename() + ".unpack"
	_remove_tree(scratch)

	var plan: Array[Dictionary] = []
	for entry: String in members:
		if entry.ends_with("/"):
			continue
		if not from.is_empty() and not entry.begins_with(from):
			continue
		var inner := entry.substr(from.length())
		if not only.is_empty() and not only.has(inner):
			continue
		# The member names come from the server that built the archive, not from
		# the player. Joining a raw one to dest_dir is zip-slip: an entry named
		# ../../../x walks straight out of the firmware folder. `into` is ours,
		# but checked joined, since `inner` can still climb out of it.
		var relative := ArchiveSafety.safe_member(into + inner)
		if relative.is_empty():
			return {"ok": false, "error": "Unsafe path in archive: %s" % entry}
		if not into.is_empty() and not relative.begins_with(into):
			return {"ok": false, "error": "Unsafe path in archive: %s" % entry}
		plan.append({"entry": entry, "relative": relative, "path": scratch.path_join(relative)})
	if plan.is_empty():
		if from.is_empty():
			return {"ok": false, "error": "The archive was empty"}
		return {"ok": false, "error": "The archive has nothing under %s" % from}
	if not only.is_empty() and plan.size() != only.size():
		return {"ok": false, "error": "The archive is missing files it should carry"}

	var result := _unpack_batches(key, zip_path, plan)
	if bool(result["ok"]):
		result = _move_into(plan, dest_dir)
	_remove_tree(scratch)
	return result


func _unpack_batches(key: String, zip_path: String, plan: Array[Dictionary]) -> Dictionary:
	var extractor := RommArchiveExtractor.new()
	var done := 0
	_emit_unpacking.call_deferred(key, 0, plan.size())
	while done < plan.size():
		if _abort:
			return {"ok": false, "cancelled": true, "error": ""}
		var batch := plan.slice(done, done + UNPACK_BATCH)
		var out: Dictionary = extractor.extract(zip_path, batch)
		if not bool(out.get("ok", false)):
			return {"ok": false, "error": str(out.get("error", "Could not unpack the archive"))}
		done += batch.size()
		_emit_unpacking.call_deferred(key, done, plan.size())
	return {"ok": true, "error": ""}


## Not cancellable: by now every member has been verified, and stopping part way
## would leave the system dir holding half of one archive and half of another.
func _move_into(plan: Array[Dictionary], dest_dir: String) -> Dictionary:
	# A link check per directory rather than per file. Once a parent has passed
	# and been created here it stays a real directory for the rest of the move.
	var checked := {}
	for item: Dictionary in plan:
		var relative := str(item["relative"])
		var parent := relative.get_base_dir()
		if not checked.has(parent):
			if ArchiveSafety.parent_is_link(dest_dir, relative):
				return {"ok": false, "error": "Archive path crosses a link: %s" % relative}
			checked[parent] = true
		var out_path := dest_dir.path_join(relative)
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		if FileAccess.file_exists(out_path) and DirAccess.remove_absolute(out_path) != OK:
			return {"ok": false, "error": "Cannot replace %s" % relative}
		if DirAccess.rename_absolute(str(item["path"]), out_path) != OK:
			return {"ok": false, "error": "Cannot write %s" % relative}
	return {"ok": true, "error": ""}


# ── Helpers ───────────────────────────────────────────────────────────────────

## Follow a URL to where the file really is, with HEAD requests.
## Returns {status: "ok", base_url, path, total} or {status, error} with the
## same status words `_attempt` uses.
func _resolve(url: String) -> Dictionary:
	var current := url
	for hop in range(MAX_REDIRECTS + 1):
		var split := split_url(current)
		if split.is_empty():
			return {"status": "terminal", "error": "Bad download address"}
		var http := RommHttp.new()
		var opened := http.open(str(split["base_url"]), func() -> bool: return _abort)
		if opened == RommHttp.Result.ABORTED:
			return {"status": "cancelled"}
		if opened != RommHttp.Result.OK:
			return {"status": "transient", "error": "Cannot reach %s" % str(split["base_url"]).get_slice("//", 1)}
		var out := http.head(str(split["path"]), PackedStringArray())
		http.close()

		var code := int(out.get("code", 0))
		if int(out["result"]) == RommHttp.Result.TIMED_OUT:
			return {"status": "transient", "error": "The server took too long to answer"}
		if int(out["result"]) != RommHttp.Result.OK:
			return {"status": "transient", "error": "Connection lost"}
		if code in [301, 302, 303, 307, 308]:
			var location := RommHttp.header_value(out["headers"], "location")
			if location.is_empty():
				return {"status": "terminal", "error": "The server redirected nowhere"}
			current = location if location.contains("://") \
				else str(split["base_url"]) + ("" if location.begins_with("/") else "/") + location
			continue
		if code >= 200 and code < 300:
			return {"status": "ok", "base_url": split["base_url"], "path": split["path"],
				"total": int(out["total"])}
		if code == 404:
			return {"status": "terminal", "error": "Not available on the server"}
		if code >= 500:
			return {"status": "transient", "error": "Server error (%d)" % code}
		return {"status": "terminal", "error": "The server refused the download (%d)" % code}
	return {"status": "terminal", "error": "Too many redirects"}


## "https://host:8443/a/b?x=1" -> {base_url: "https://host:8443", path: "/a/b?x=1"}.
## RommHttp.open takes the first and a request the second.
static func split_url(url: String) -> Dictionary:
	var scheme_end := url.find("://")
	if scheme_end <= 0:
		return {}
	var scheme := url.substr(0, scheme_end).to_lower()
	if scheme != "http" and scheme != "https":
		return {}
	var slash := url.find("/", scheme_end + 3)
	var base := url if slash < 0 else url.substr(0, slash)
	var path := "/" if slash < 0 else url.substr(slash)
	if base.length() <= scheme_end + 3:
		return {}
	return {"base_url": base, "path": path}


## Staged outside the system dir so a half-finished transfer is never mistaken
## for an installed file by the status scan.
static func _staging_path(key: String) -> String:
	var safe := key.replace("/", "_").replace(":", "_").replace("\\", "_")
	return CoreDownloadManager.default_core_root().path_join("temp").path_join(safe + ".part")


static func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.include_hidden = true
	for f: String in dir.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	for d: String in dir.get_directories():
		_remove_tree(path.path_join(d))
	DirAccess.remove_absolute(path)


# ── Main-thread emitters ──────────────────────────────────────────────────────

func _emit_started(key: String, label: String, total: int) -> void:
	job_started.emit(key, label, total)


func _emit_progress(key: String, received: int, total: int) -> void:
	job_progress.emit(key, received, total)


func _emit_unpacking(key: String, done: int, total: int) -> void:
	job_unpacking.emit(key, done, total)


func _emit_retrying(key: String, attempt: int, total: int, reason: String) -> void:
	job_retrying.emit(key, attempt, total, reason)


func _emit_cancelled(key: String) -> void:
	_current_key = ""
	job_cancelled.emit(key)
	_pump()


func _emit_finished(key: String, ok: bool, error: String) -> void:
	_current_key = ""
	job_finished.emit(key, ok, error)
	_pump()
