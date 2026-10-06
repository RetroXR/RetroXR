## ModDownloader — fetches a mod pack from mod.io and hands it to the loader.
##
## One job at a time, on its own thread, through RommHttp: the same resumable
## Range requests, retry shape and completeness checks FirmwareInstaller uses,
## for the same reason — a pack is tens of megabytes and a headset's connection
## drops.
##
## What is different here is where the redirect is followed. mod.io answers a
## download with a hop to a signed address on its CDN, and a signature made for
## a GET need not answer a HEAD, so the hops are followed on the GET itself
## rather than probed first.
##
## A finished download is NOT an installed mod. The file is checked against
## mod.io's own MD5, renamed from `.part` to its real extension inside the
## loader's incoming folder, and passed to `install_hook` — ModManager.install by
## default — which vets it exactly as a boot would. Only that can put a file in
## the mods root, and a pack it refuses is deleted with its reason shown.
class_name ModDownloader
extends Node

## key identifies the job for the UI and the toast; it is the caller's to choose.
signal job_started(key: String, label: String, total_bytes: int)
signal job_progress(key: String, received: int, total: int)
signal job_retrying(key: String, attempt: int, max_attempts: int, reason: String)
## `result` is what the install hook returned: {ok, id, error, restart}.
signal job_finished(key: String, ok: bool, error: String, result: Dictionary)
signal job_cancelled(key: String)

const MAX_RETRIES := 3
const MAX_REDIRECTS := 5
## Room asked for beyond the file itself: twice its size, because a bundle is
## opened beside the download before the download is deleted, plus this.
const SPACE_MARGIN := 16 * 1024 * 1024

## func(staged_path: String, source: Dictionary) -> {ok, id, error, restart}.
## Called on the main thread.
var install_hook: Callable = Callable()
## Where a download waits. Empty means the loader's own incoming folder.
var staging_dir_override := ""
## The first retry waits twice this, the second four times. A var so the suite
## can exercise three attempts without sitting through six seconds of backoff.
var backoff_ms := 1000
## Free bytes to believe instead of asking the disk. -1 asks. For the suite.
var free_space_override := -1

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


func is_queued(key: String) -> bool:
	if _current_key == key:
		return true
	for j: Dictionary in _queue:
		if str(j["key"]) == key:
			return true
	return false


## Fetch `url` and install it.
##   size    the file's size as mod.io states it, 0 when unknown
##   md5     mod.io's checksum, "" to skip the check
##   source  kept against the installed mod (the mod.io mod and file ids)
func enqueue(key: String, label: String, url: String, size: int, md5: String,
		source: Dictionary) -> void:
	if key.is_empty() or url.is_empty() or is_queued(key):
		return
	_queue.append({"key": key, "label": label, "url": url, "size": size,
		"md5": md5.to_lower(), "source": source})
	_pump()


## Stop one job by key, whether it is running or still waiting. A queued job
## never reached the worker, so it is announced here.
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


func _staging_dir() -> String:
	return Mods.incoming_dir() if staging_dir_override.is_empty() else staging_dir_override


## "" when a file of `size` bytes will fit in `free` bytes, else a sentence the
## player can act on. Nothing is refused on a size or a free figure of 0: mod.io
## does not always state one, and a volume that reports none is unknown, not full.
static func space_problem(size: int, free: int, have: int = 0) -> String:
	if size <= 0 or free <= 0:
		return ""
	var need := maxi(0, size - have) + size + SPACE_MARGIN
	if free >= need:
		return ""
	return "Not enough space: needs %s, %s free" % [
		MenuStyle.human_bytes(need), MenuStyle.human_bytes(free)]


## The staging name is the key with nothing a path could use, so a retry of the
## same mod finds its own partial file and resumes it.
func _part_path(key: String) -> String:
	var safe := ""
	for c: String in key:
		safe += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "-" else "_"
	return _staging_dir().path_join(safe + ".zip.part")


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
	# Resolved here, on the main thread: the worker must not reach for an autoload.
	job["part"] = _part_path(_current_key)
	job_started.emit(_current_key, str(job["label"]), int(job["size"]))
	_thread = Thread.new()
	_thread.start(_worker.bind(job))


func _worker(job: Dictionary) -> void:
	var key := str(job["key"])
	var part := str(job["part"])
	if DirAccess.make_dir_recursive_absolute(part.get_base_dir()) != OK \
			and not DirAccess.dir_exists_absolute(part.get_base_dir()):
		# The mods folder is one the app may not be able to write: a directory
		# made by `adb push` belongs to the shell. Said plainly, because nothing
		# the player does inside the headset can fix it.
		_finish.call_deferred(job, false, "RetroXR cannot write to its mods folder")
		return

	# Asked before the first byte, not found out forty megabytes in.
	var free := free_space_override
	if free < 0:
		var dir := DirAccess.open(part.get_base_dir())
		free = int(dir.get_space_left()) if dir != null else 0
	var cramped := space_problem(int(job.get("size", 0)), free, ByteSize.on_disk(part))
	if not cramped.is_empty():
		_finish.call_deferred(job, false, cramped)
		return

	var fetched := _transfer(job, part)
	if str(fetched["state"]) == "cancelled":
		_cancelled.call_deferred(key)
		return
	if str(fetched["state"]) == "failed":
		_finish.call_deferred(job, false, str(fetched["error"]))
		return

	# ModPackReader picks its reader by extension, so the vetting below needs the
	# real one. Still inside incoming, which discovery never reads.
	var staged := part.trim_suffix(".part")
	DirAccess.remove_absolute(staged)
	if DirAccess.rename_absolute(part, staged) != OK:
		DirAccess.remove_absolute(part)
		_finish.call_deferred(job, false, "RetroXR cannot write to its mods folder")
		return
	_install.call_deferred(job, staged)


## Main thread. The loader is not shared with the worker.
func _install(job: Dictionary, staged: String) -> void:
	var hook := install_hook if install_hook.is_valid() else Callable(Mods, "install")
	var result: Dictionary = hook.call(staged, job["source"])
	_current_key = ""
	job_finished.emit(str(job["key"]), bool(result.get("ok", false)),
		str(result.get("error", "")), result)
	_pump()


func _finish(job: Dictionary, ok: bool, error: String) -> void:
	_current_key = ""
	job_finished.emit(str(job["key"]), ok, error, {})
	_pump()


func _cancelled(key: String) -> void:
	_current_key = ""
	job_cancelled.emit(key)
	_pump()


func _progress(key: String, received: int, total: int) -> void:
	job_progress.emit(key, received, total)


func _retrying(key: String, attempt: int, total: int, reason: String) -> void:
	job_retrying.emit(key, attempt, total, reason)


# ── Transfer (worker thread) ──────────────────────────────────────────────────

## Download into `part`, retrying what is worth retrying.
## Returns {state: "ok" | "cancelled" | "failed", error: String}.
func _transfer(job: Dictionary, part: String) -> Dictionary:
	var key := str(job["key"])
	var attempt := 0
	var last_error := ""
	while attempt < MAX_RETRIES:
		if _abort:
			return {"state": "cancelled", "error": ""}
		if attempt > 0:
			_retrying.call_deferred(key, attempt + 1, MAX_RETRIES, last_error)
			# Sliced so a cancel lands during the backoff, not after it.
			var wait_ms := int(pow(2.0, attempt) * float(backoff_ms))
			var waited := 0
			while waited < wait_ms and not _abort:
				OS.delay_msec(100)
				waited += 100
			if _abort:
				return {"state": "cancelled", "error": ""}

		var res := _attempt(job, part)
		var status := str(res["status"])
		last_error = str(res.get("error", ""))
		if status == "ok":
			return {"state": "ok", "error": ""}
		if status == "cancelled":
			return {"state": "cancelled", "error": ""}
		if status == "terminal":
			return {"state": "failed", "error": last_error}
		if status == "restart":
			DirAccess.remove_absolute(part)
		attempt += 1
	return {"state": "failed", "error": last_error}


## One transfer into the staging file, following redirects. Resumes when a
## partial is already there.
func _attempt(job: Dictionary, part: String) -> Dictionary:
	var key := str(job["key"])
	var expected := int(job.get("size", 0))

	var have := 0
	var f: FileAccess = null
	if FileAccess.file_exists(part):
		f = FileAccess.open(part, FileAccess.READ_WRITE)
		if f != null:
			f.seek_end()
			have = int(f.get_position())
	if f == null:
		f = FileAccess.open(part, FileAccess.WRITE)
	if f == null:
		return {"status": "terminal", "error": "RetroXR cannot write to its mods folder"}

	var progress := func(received: int, total: int) -> void:
		_progress.call_deferred(key, have + received, have + total if total > 0 else expected)

	var url := str(job["url"])
	var out: Dictionary = {}
	for hop in range(MAX_REDIRECTS + 1):
		var split := FirmwareInstaller.split_url(url)
		if split.is_empty():
			f.close()
			return {"status": "terminal", "error": "Bad download address"}
		var http := RommHttp.new()
		var opened := http.open(str(split["base_url"]), func() -> bool: return _abort)
		if opened == RommHttp.Result.ABORTED:
			f.close()
			return {"status": "cancelled"}
		if opened != RommHttp.Result.OK:
			f.close()
			return {"status": "transient", "error": "Cannot reach the download server"}
		out = http.download_to_file(str(split["path"]),
			PackedStringArray(["Range: bytes=%d-" % have, "User-Agent: RetroXR"]),
			f, progress, func() -> bool: return _abort)
		http.close()
		var hop_code := int(out.get("code", 0))
		if int(out["result"]) != RommHttp.Result.HTTP_ERROR \
				or not (hop_code in [301, 302, 303, 307, 308]):
			break
		var location := RommHttp.header_value(out.get("headers", {}), "location")
		if location.is_empty():
			f.close()
			return {"status": "terminal", "error": "The server redirected nowhere"}
		if hop == MAX_REDIRECTS:
			f.close()
			return {"status": "terminal", "error": "Too many redirects"}
		url = location if location.contains("://") \
			else str(split["base_url"]) + ("" if location.begins_with("/") else "/") + location
	f.close()

	var result := int(out["result"])
	var code := int(out.get("code", 0))
	if result == RommHttp.Result.ABORTED:
		return {"status": "cancelled"}
	if result == RommHttp.Result.WRITE_FAILED:
		return {"status": "terminal", "error": "Not enough space, or the mods folder is unwritable"}
	if result == RommHttp.Result.CONNECT_FAILED or result == RommHttp.Result.REQUEST_FAILED:
		return {"status": "transient", "error": "Connection lost"}
	if result == RommHttp.Result.TIMED_OUT:
		return {"status": "transient", "error": "The server took too long to answer"}
	if result == RommHttp.Result.HTTP_ERROR:
		if code == 404 or code == 410:
			DirAccess.remove_absolute(part)
			return {"status": "terminal", "error": "This file is no longer on mod.io"}
		if code == 416:
			# Already had the whole thing, or the file changed underneath us.
			return {"status": "restart", "error": "The file changed on the server"}
		if code >= 500 or code == 429:
			return {"status": "transient", "error": "The server is busy (%d)" % code}
		return {"status": "terminal", "error": "The server refused the download (%d)" % code}

	# Range ignored: the full body was appended onto the partial. Caught by
	# status, since have + total then equals the corrupt length.
	if have > 0 and code == 200:
		return {"status": "restart", "error": "The server did not resume the download"}

	# Completeness against THIS response's Content-Length. HTTPClient leaves the
	# body state the same way whether the body ended or the socket died.
	var got := ByteSize.on_disk(part)
	var whole := have + int(out.get("total", 0))
	if whole > have and got != whole:
		return {"status": "restart",
			"error": "Incomplete download (%d of %d bytes)" % [got, whole]}

	var want := str(job.get("md5", ""))
	if not want.is_empty() and FileAccess.get_md5(part).to_lower() != want:
		return {"status": "restart", "error": "The downloaded file was corrupt"}
	return {"status": "ok"}
