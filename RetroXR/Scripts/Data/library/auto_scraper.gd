## AutoScraper -- scrape a ROM's metadata once it lands, without being asked.
##
## Scraping was manual and per-row: a button in the spawn list, one game at a
## time, pressed by hand. A ROM that arrives some other way -- pulled off the
## shelf for the first time, downloaded from RomM, resolved by hash to join a
## netplay session -- has a name, a hash and no artwork, and nobody is going to
## go and press that button for it.
##
## It is a gate in front of the shared ScrapeQueue rather than a queue of its
## own: the queue owns the account's thread allowance and the request spacing,
## so every scrape in the app has to go through it or the server sees a burst.
## What lives here is the decision to scrape at all.
##
## It is also deliberately quiet about failure. A scrape is decoration: the game
## runs, the session starts, the file is already correct. A missing cover must
## never turn into an error a player has to dismiss.
class_name AutoScraper
extends Node

## A scrape finished and wrote metadata for this ROM. The library refreshes on
## it; nothing depends on it having succeeded.
signal scraped(rom_path: String, systemid: String)

## A bound rather than an unbounded backlog: a first run over a large library
## would otherwise queue thousands and scrape for hours.
const MAX_QUEUE := 64

var _queue: ScrapeQueue = null
var _gamelist: GamelistManager = null
var _config: ScraperConfig = null


func setup(queue: ScrapeQueue, gamelist: GamelistManager,
		config: ScraperConfig) -> void:
	_queue = queue
	_gamelist = gamelist
	_config = config
	if _queue != null:
		_queue.completed.connect(_on_completed)


## True when auto-scraping can run at all.
##
## Credentials are the gate: ScreenScraper's anonymous quota is small enough
## that a library sweep would exhaust it, and a player who has not signed in has
## not opted into anything. Checked per request rather than cached because the
## account can be entered while the app is running.
func is_enabled() -> bool:
	return _config != null and _queue != null \
		and not _config.ssid.is_empty() and not _config.sspassword.is_empty()


## The systemid a ROM path sits under, or "".
##
## Derived from the path rather than passed in, because the two callers know it
## in different forms -- the downloader enqueued with one, the netplay resolver
## only has a file it matched by hash -- and the layout (<roms_root>/<systemid>/)
## is the one thing both agree on.
static func systemid_for_path(rom_path: String) -> String:
	var root := RomLibrary.default_roms_root().simplify_path()
	var full := rom_path.simplify_path()
	if not full.begins_with(root):
		return ""
	var rest := full.substr(root.length()).lstrip("/")
	var parts := rest.split("/", false)
	return parts[0] if parts.size() > 1 else ""


## Queue a ROM for scraping if it needs it. Safe to call on every resolve.
func request(rom_path: String, systemid: String) -> void:
	if not is_enabled() or rom_path.is_empty() or systemid.is_empty():
		return
	if not FileAccess.file_exists(rom_path):
		return
	if already_scraped(rom_path, systemid):
		return
	if _queue.is_queued(rom_path):
		return
	if _queue.waiting_count(ScrapeQueue.TAG_AUTO) >= MAX_QUEUE:
		return
	_queue.enqueue(rom_path, systemid, {"tag": ScrapeQueue.TAG_AUTO})


## True when this ROM already has metadata, so scraping it again would spend a
## request to learn nothing.
func already_scraped(rom_path: String, systemid: String) -> bool:
	return not ScrapeQueue.needs_scrape(_gamelist, systemid, rom_path)


func queued_count() -> int:
	if _queue == null:
		return 0
	return _queue.waiting_count(ScrapeQueue.TAG_AUTO) + _queue.active_count(ScrapeQueue.TAG_AUTO)


func cancel_all() -> void:
	if _queue != null:
		_queue.cancel_all(ScrapeQueue.TAG_AUTO)


## Every accepted result is announced, whoever queued it: a scraped game is a
## scraped game to the library that refreshes on this.
func _on_completed(rom_path: String, systemid: String, _result: Dictionary, accepted: bool) -> void:
	if accepted:
		scraped.emit(rom_path, systemid)
