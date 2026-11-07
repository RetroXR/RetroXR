## MusicLengths — how long each music track is, without playing it: what a cassette's or an LP's sides are laid out by
## (TapeSides). VLC tells a track's length only once it is opened, so the lengths come from VlcPlayer.probe_length_ms
## (libVLC's preparser) on a worker thread, and are kept in user://music_lengths.json against each file's size and
## modification time. Until a track is measured (or if it cannot be) its length is ESTIMATED from its size, logged.
## Every peer measures its own copy of the same files, so nothing about it goes on the wire.
class_name MusicLengths
extends RefCounted

const CACHE := "user://music_lengths.json"
## Bytes a second, by kind, for an estimate: CD PCM for WAV, a typical FLAC, 192 kbit/s for everything else.
const ESTIMATE_BPS := {"wav": 176400.0, "flac": 100000.0}
const ESTIMATE_DEFAULT_BPS := 24000.0
## How long one probe may take, ms.
const PROBE_TIMEOUT_MS := 3000

## path -> [size, mtime, seconds]
static var _cache := {}
static var _loaded := false
static var _mutex := Mutex.new()
## A VlcPlayer kept for probing only (its own libVLC instance, made once, on the main thread).
static var _probe: Object = null
static var _warned_no_probe := false
## A suite sets this: nothing is read from or written to CACHE, and nothing is probed.
static var test_mode := false


## Each of `paths`' length in seconds: measured when known, else estimated from its size.
static func lengths_now(paths: PackedStringArray) -> PackedFloat64Array:
	_load()
	var out := PackedFloat64Array()
	for p in paths:
		var known := _known(p)
		out.append(known if known > 0.0 else estimate(p))
	return out


## Whether every one of `paths` has a measured length.
static func all_known(paths: PackedStringArray) -> bool:
	_load()
	for p in paths:
		if _known(p) <= 0.0:
			return false
	return true


## Measure every one of `paths` not yet known, off the main thread; `done` is called (deferred, on the main thread)
## once they are, whether or not any could be measured. Nothing to measure: `done` is not called (nothing changed).
static func request(paths: PackedStringArray, done: Callable) -> void:
	_load()
	var missing := PackedStringArray()
	for p in paths:
		if _known(p) <= 0.0:
			missing.append(p)
	if missing.is_empty() or test_mode or not _make_probe():
		return
	var probe := _probe
	print("[MusicLengths] measuring %d track(s), e.g. %s" % [missing.size(), missing[0].get_file()])
	WorkerThreadPool.add_task(func() -> void:
		var measured := 0
		for p in missing:
			var ms: int = probe.call("probe_length_ms", ProjectSettings.globalize_path(p), PROBE_TIMEOUT_MS)
			if ms > 0:
				_remember_locked(p, ms / 1000.0)
				measured += 1
			else:
				print("[MusicLengths] could not measure %s: its length stays estimated" % p.get_file())
		MusicLengths._finish.call_deferred(measured, missing.size(), done))


## Record a track's length (seconds) as measured. Also how a suite sets the lengths it lays sides out by.
static func remember(path: String, seconds: float) -> void:
	_load()
	_remember_locked(path, seconds)


## A length from the file's size alone, seconds.
static func estimate(path: String) -> float:
	var size := _size_of(path)
	if size <= 0:
		return 0.0
	var bps: float = ESTIMATE_BPS.get(path.get_extension().to_lower(), ESTIMATE_DEFAULT_BPS)
	return float(size) / bps


static func _finish(measured: int, of: int, done: Callable) -> void:
	print("[MusicLengths] measured %d of %d track(s)" % [measured, of])
	_save()
	if done.is_valid():
		done.call()


static func _known(path: String) -> float:
	_mutex.lock()
	var row: Variant = _cache.get(path)
	_mutex.unlock()
	if not (row is Array) or (row as Array).size() < 3:
		return -1.0
	if int(row[0]) != _size_of(path) or int(row[1]) != int(FileAccess.get_modified_time(path)):
		return -1.0
	return float(row[2])


static func _remember_locked(path: String, seconds: float) -> void:
	var row := [_size_of(path), int(FileAccess.get_modified_time(path)), seconds]
	_mutex.lock()
	_cache[path] = row
	_mutex.unlock()


static func _size_of(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	return f.get_length() if f != null else 0


static func _make_probe() -> bool:
	if _probe != null:
		return true
	if not ClassDB.class_exists("VlcPlayer"):
		if not _warned_no_probe:
			_warned_no_probe = true
			print("[MusicLengths] no VlcPlayer: track lengths are estimated from their sizes")
		return false
	var p: Object = ClassDB.instantiate("VlcPlayer")
	if not p.has_method("probe_length_ms"):
		if not _warned_no_probe:
			_warned_no_probe = true
			push_warning("[MusicLengths] this vlc-godot build has no probe_length_ms (rebuild it): lengths are estimated")
		return false
	# On the main thread: on Android the JavaVM handoff is made here, and the probe runs on a worker.
	p.call("warm_up")
	_probe = p
	return true


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if test_mode or not FileAccess.file_exists(CACHE):
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(CACHE))
	if data is Dictionary:
		_mutex.lock()
		_cache = data
		_mutex.unlock()
	else:
		push_warning("[MusicLengths] %s did not parse: starting it again" % CACHE)


static func _save() -> void:
	if test_mode:
		return
	_mutex.lock()
	var text := JSON.stringify(_cache)
	_mutex.unlock()
	var f := FileAccess.open(CACHE, FileAccess.WRITE)
	if f == null:
		push_warning("[MusicLengths] cannot write %s (%s)" % [CACHE, error_string(FileAccess.get_open_error())])
		return
	f.store_string(text)
