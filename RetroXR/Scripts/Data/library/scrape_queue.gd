## ScrapeQueue -- every ScreenScraper lookup in the app goes through here.
##
## A row's Scrape button, a platform's "Scrape all" and the AutoScraper all
## enqueue; the queue runs as many at once as the account allows. ScreenScraper
## grants each account a number of parallel connections (`maxthreads`: one for
## an anonymous caller, more for members and contributors), so one
## ScreenscraperClient per thread is spun up lazily and each keeps its own
## request spacing. The allowance is asked for once credentials exist, and every
## scrape answer carries it again beside the game, so it is kept current for
## free while a batch runs.
##
## A result is written straight into the gamelist and its media fetched, unless
## the item asked for review, in which case it is handed back untouched for the
## popup. The queue never shows anything itself: signals carry what happened
## and the menu decides what a player sees.
class_name ScrapeQueue
extends Node

signal started(rom_path: String, systemid: String)
## `accepted` is false for a review item, whose result the UI now owns.
signal completed(rom_path: String, systemid: String, result: Dictionary, accepted: bool)
signal failed(rom_path: String, systemid: String, error: String)
signal media_downloaded(rom_path: String, systemid: String, media_type: String, path: String)
signal progress(active: int, waiting: int, done: int, failed_count: int, threads: int)
signal threads_changed(threads: int)
## Nothing left waiting or running.
signal drained(done: int, failed_count: int)
## The queue emptied itself: the account cannot scrape any more today.
signal stopped(reason: String)

## A bound rather than an unbounded backlog: a first sweep over a large library
## would otherwise queue everything and scrape for hours.
const MAX_QUEUE := 1000
## Each thread is an HTTPRequest with its own thread plus a hashing thread while
## a ROM is read; a Quest does not want fifteen of each however generous the
## account.
const MAX_THREADS := 8

const TAG_MANUAL := "manual"
const TAG_AUTO := "auto"

var _config: ScraperConfig = null
var _gamelist: GamelistManager = null
var _client_factory: Callable = Callable()

var _queue: Array[Dictionary] = []
## One entry per worker: {client, item} -- item is {} while idle.
var _workers: Array[Dictionary] = []
var _threads := 1
var _info_client: ScreenscraperClient = null
var _info_ssid_asked := ""
var _info_pending := false
var _done := 0
var _failed := 0


func setup(config: ScraperConfig, gamelist: GamelistManager,
		client_factory: Callable = Callable()) -> void:
	_config = config
	_gamelist = gamelist
	_client_factory = client_factory


# ── Public ────────────────────────────────────────────────────────────────────

## True when scraping this ROM would learn something: no game in the gamelist
## holds it, or the one that does has no name.
static func needs_scrape(gamelist: GamelistManager, systemid: String, rom_path: String) -> bool:
	if gamelist == null:
		return true
	var game := gamelist.get_game_for_rom(systemid, rom_path)
	return game.is_empty() or str(game.get("name", "")).is_empty()


## What "Scrape all" takes from a page: the paths that need a scrape and are not
## already waiting or running. The second value is how many were passed over
## as already scraped, for the notice.
func select_unscraped(systemid: String, paths: Array) -> Dictionary:
	var take: Array[String] = []
	var skipped := 0
	for p in paths:
		var path := str(p)
		if path.is_empty():
			continue
		if not needs_scrape(_gamelist, systemid, path):
			skipped += 1
			continue
		if is_queued(path):
			continue
		take.append(path)
	return {"paths": take, "skipped": skipped}


## Queue a ROM. opts: `tag` (TAG_MANUAL / TAG_AUTO), `review` (hand the result
## back instead of writing it). False when it is already queued or running, or
## the queue is full.
func enqueue(rom_path: String, systemid: String, opts: Dictionary = {}) -> bool:
	if rom_path.is_empty() or systemid.is_empty():
		return false
	if is_queued(rom_path):
		return false
	if _queue.size() >= MAX_QUEUE:
		return false
	_queue.append({
		"rom": rom_path,
		"systemid": systemid,
		"tag": str(opts.get("tag", TAG_MANUAL)),
		"review": bool(opts.get("review", false)),
	})
	_pump()
	_emit_progress()
	return true


func is_queued(rom_path: String) -> bool:
	for q: Dictionary in _queue:
		if str(q["rom"]) == rom_path:
			return true
	for w: Dictionary in _workers:
		if str((w["item"] as Dictionary).get("rom", "")) == rom_path:
			return true
	return false


func is_busy() -> bool:
	return active_count() > 0 or not _queue.is_empty()


func waiting_count(tag: String = "") -> int:
	if tag.is_empty():
		return _queue.size()
	var n := 0
	for q: Dictionary in _queue:
		if str(q["tag"]) == tag:
			n += 1
	return n


func active_count(tag: String = "") -> int:
	var n := 0
	for w: Dictionary in _workers:
		var item: Dictionary = w["item"]
		if not item.is_empty() and (tag.is_empty() or str(item["tag"]) == tag):
			n += 1
	return n


func thread_count() -> int:
	return _threads


## Drop what is waiting. A running scrape finishes on its own; it cannot be
## recalled from the server.
func cancel_all(tag: String = "") -> void:
	if tag.is_empty():
		_queue.clear()
	else:
		_queue = _queue.filter(func(q: Dictionary) -> bool: return str(q["tag"]) != tag)
	_emit_progress()
	if not is_busy():
		_finish_run()


## Ask the account's allowance again -- after credentials change, say.
func refresh_threads() -> void:
	_info_ssid_asked = ""
	_request_user_info()


# ── Workers ───────────────────────────────────────────────────────────────────

func _pump() -> void:
	if _config == null:
		return
	_request_user_info()
	while not _queue.is_empty():
		var w := _idle_worker()
		if w.is_empty():
			return
		var item: Dictionary = _queue.pop_front()
		w["item"] = item
		_run_item(w, item)


## The allowance can shrink mid-run, so it is the RUNNING count that is held
## to it; a worker left over from a wider allowance sits idle rather than
## being handed the next item.
func _idle_worker() -> Dictionary:
	if active_count() >= _threads:
		return {}
	for w: Dictionary in _workers:
		if (w["item"] as Dictionary).is_empty():
			return w
	var client := _make_client()
	if client == null:
		return {}
	var w := {"client": client, "item": {}}
	client.scrape_completed.connect(_on_scrape_completed.bind(w))
	client.scrape_failed.connect(_on_scrape_failed.bind(w))
	client.media_download_completed.connect(_on_media_completed.bind(w))
	_workers.append(w)
	return w


func _make_client() -> ScreenscraperClient:
	var client: ScreenscraperClient = null
	if _client_factory.is_valid():
		client = _client_factory.call()
	else:
		client = ScreenscraperClient.new()
		client.config = _config
	if client == null:
		return null
	if client.get_parent() == null:
		add_child(client)
	return client


func _run_item(w: Dictionary, item: Dictionary) -> void:
	var rom := str(item["rom"])
	var systemid := str(item["systemid"])
	started.emit(rom, systemid)
	_emit_progress()

	# On a thread: a disc image is hundreds of megabytes, and the cache in
	# checksums_of only helps the second time.
	var thread := Thread.new()
	thread.start(func() -> Dictionary: return NetFileTransfer.checksums_of(rom))
	while thread.is_alive():
		await get_tree().process_frame
	var sums: Dictionary = thread.wait_to_finish()
	if not is_inside_tree() or w["item"] != item:
		return
	if sums.is_empty():
		_item_failed(w, "Could not read ROM file checksums")
		return

	var client: ScreenscraperClient = w["client"]
	client.scrape_rom(rom, systemid, sums)


func _on_scrape_completed(result: Dictionary, w: Dictionary) -> void:
	var item: Dictionary = w["item"]
	if item.is_empty():
		return
	var rom := str(item["rom"])
	var systemid := str(item["systemid"])
	if result.get("ssuser", null) is Dictionary:
		_apply_user_info(result["ssuser"])

	if bool(item["review"]):
		_done += 1
		w["item"] = {}
		completed.emit(rom, systemid, result, false)
		_after_item()
		return

	_write_result(rom, systemid, result)
	var client: ScreenscraperClient = w["client"]
	await client.download_all_media(result, systemid, rom.get_file().get_basename())
	# Not the next game until this one's art has landed: the client keys its
	# transfers by media type, so a second "wheel" would collide with the first.
	while is_inside_tree() and client.pending_media_count() > 0:
		await get_tree().process_frame
	if w["item"] != item:
		return
	_done += 1
	w["item"] = {}
	completed.emit(rom, systemid, result, true)
	_after_item()


func _on_scrape_failed(error: String, w: Dictionary) -> void:
	if (w["item"] as Dictionary).is_empty():
		return
	_item_failed(w, error)


func _item_failed(w: Dictionary, error: String) -> void:
	var item: Dictionary = w["item"]
	var rom := str(item["rom"])
	var systemid := str(item["systemid"])
	_failed += 1
	w["item"] = {}
	failed.emit(rom, systemid, error)
	if _is_quota_error(error):
		_stop("Daily scrape quota exceeded")
	_after_item()


func _on_media_completed(media_type: String, path: String, w: Dictionary) -> void:
	var item: Dictionary = w["item"]
	if item.is_empty():
		return
	media_downloaded.emit(str(item["rom"]), str(item["systemid"]), media_type, path)


func _after_item() -> void:
	_pump()
	_emit_progress()
	if not is_busy():
		_finish_run()


func _finish_run() -> void:
	if _done == 0 and _failed == 0:
		return
	var done := _done
	var failed_count := _failed
	_done = 0
	_failed = 0
	drained.emit(done, failed_count)


## Same shape as spawn_view._on_scrape_accepted writes, and saved: the gamelist
## does not save itself on a merge.
func _write_result(rom: String, systemid: String, result: Dictionary) -> void:
	if _gamelist == null or result.is_empty():
		return
	var game_data := {
		"game_id": result.get("game_id", ""),
		"name": result.get("name", ""),
		"desc": result.get("desc", ""),
		"developer": result.get("developer", ""),
		"publisher": result.get("publisher", ""),
		"genre": result.get("genre", ""),
	}
	var rom_data := {
		"path": "./" + rom.get_file(),
		"romname": rom.get_file(),
		"releasedate": result.get("releasedate", ""),
		"region": result.get("rom_region", ""),
	}
	_gamelist.add_or_merge_rom(systemid, game_data, rom_data)
	_gamelist.save_gamelist(systemid)


# ── Account ───────────────────────────────────────────────────────────────────

func _request_user_info() -> void:
	if _config == null or _info_pending:
		return
	if _config.ssid == _info_ssid_asked:
		return
	_info_ssid_asked = _config.ssid
	if _info_client == null:
		_info_client = _make_client()
		if _info_client == null:
			return
		_info_client.user_info_received.connect(_on_user_info)
		_info_client.user_info_failed.connect(_on_user_info_failed)
	_info_pending = true
	_info_client.fetch_user_info()


func _on_user_info(info: Dictionary) -> void:
	_info_pending = false
	_apply_user_info(info)


## Left at whatever it was: a failed lookup is not a reason to slow a run that
## already learnt its allowance from a scrape answer.
func _on_user_info_failed(error: String) -> void:
	_info_pending = false
	push_warning("[ScrapeQueue] account lookup failed: %s" % error)


func _apply_user_info(info: Dictionary) -> void:
	# The limit first: a wider allowance pumps, and an account already at its
	# daily limit must not start anything on the way to being told so.
	var per_day := int(info.get("maxrequestsperday", 0))
	if per_day > 0 and int(info.get("requeststoday", 0)) >= per_day and not _queue.is_empty():
		_stop("Daily scrape quota exceeded")
	var threads := clampi(int(info.get("maxthreads", 1)), 1, MAX_THREADS)
	if threads != _threads:
		_threads = threads
		print("[ScrapeQueue] %d scrape thread(s)" % _threads)
		threads_changed.emit(_threads)
		_pump()
		_emit_progress()


func _is_quota_error(error: String) -> bool:
	return error.find("quota") >= 0


func _stop(reason: String) -> void:
	if _queue.is_empty():
		return
	var dropped := _queue
	_queue = []
	for q: Dictionary in dropped:
		_failed += 1
		failed.emit(str(q["rom"]), str(q["systemid"]), reason)
	stopped.emit(reason)


func _emit_progress() -> void:
	progress.emit(active_count(), _queue.size(), _done, _failed, _threads)
