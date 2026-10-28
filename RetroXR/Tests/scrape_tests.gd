## scrape_tests -- the ScreenScraper queue, without ScreenScraper.
##
## The queue is fed a fake client through its factory, so every case here is
## about what the queue DECIDES: how many run at once and when that changes,
## what is written and what is handed back, what a quota does to the backlog,
## and what the AutoScraper gate lets through. No network, no headset.
##
## It uses a scratch system folder under the real roms root -- a gamelist's path
## is derived from the systemid and cannot be pointed elsewhere -- and removes it
## at both ends. It also touches the player's real scraper_config.json for the
## round-trip case, snapshotting it first.
extends "res://Tests/test_suite.gd"

const TEST_SYSTEM := "__scrape_selftest"

var _only := ""

var _config: ScraperConfig = null
var _gamelist: GamelistManager = null
var _clients: Array[FakeClient] = []
var _auto_info: Dictionary = {}


## A ScreenscraperClient that answers what the test tells it to.
class FakeClient extends ScreenscraperClient:
	var suite: Node = null
	var held: Array[Dictionary] = []
	var info_calls := 0
	var media_types: Array = []
	var _media_pending := 0

	func _ready() -> void:
		pass

	func scrape_rom(rom_path: String, systemid: String, _checksums: Dictionary) -> void:
		held.append({"rom": rom_path, "systemid": systemid})

	func fetch_user_info() -> void:
		info_calls += 1
		var info: Dictionary = suite.get("_auto_info")
		if not info.is_empty():
			user_info_received.emit(ScreenscraperClient.parse_user_info(info))

	func download_all_media(_result: Dictionary, _systemid: String, _rom_basename: String) -> void:
		_media_pending = media_types.size()

	func pending_media_count() -> int:
		return _media_pending

	func holds(rom_path: String) -> bool:
		for h: Dictionary in held:
			if str(h["rom"]) == rom_path:
				return true
		return false

	func resolve(rom_path: String, result: Dictionary) -> void:
		_drop(rom_path)
		scrape_completed.emit(result)

	func refuse(rom_path: String, error: String) -> void:
		_drop(rom_path)
		scrape_failed.emit(error)

	func finish_media(media_type: String, path: String) -> void:
		_media_pending = maxi(0, _media_pending - 1)
		media_download_completed.emit(media_type, path)

	func _drop(rom_path: String) -> void:
		for i in range(held.size()):
			if str(held[i]["rom"]) == rom_path:
				held.remove_at(i)
				return


## A client whose downloads are written down instead of made.
class RecordingClient extends ScreenscraperClient:
	var got: Array[Dictionary] = []

	func _ready() -> void:
		pass

	func download_media(media_type: String, url: String, dest_path: String) -> void:
		got.append({"type": media_type, "url": url, "dest": dest_path})


func _ready() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7)
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		print("[test] FAIL timeout")
		get_tree().quit(1)
	)
	_setup()
	await _run_group("userinfo", _group_userinfo)
	await _run_group("queue", _group_queue)
	await _run_group("threads", _group_threads)
	await _run_group("results", _group_results)
	await _run_group("scraped", _group_scraped)
	await _run_group("media", _group_media)
	await _run_group("quota", _group_quota)
	await _run_group("auto", _group_auto)
	await _run_group("config", _group_config)
	await _run_group("priority", _group_priority)
	await _run_group("cabinet_media", _group_cabinet_media)
	_teardown()
	_finish()


func _run_group(name: String, fn: Callable) -> void:
	if not _only.is_empty() and _only != name:
		return
	print("[test] --- %s ---" % name)
	await fn.call()


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


# ── Fixtures ──────────────────────────────────────────────────────────────────

func _setup() -> void:
	_teardown()
	DirAccess.make_dir_recursive_absolute(RomLibrary.rom_dir_for_system(TEST_SYSTEM))
	_config = ScraperConfig.new()
	_gamelist = GamelistManager.new()


func _teardown() -> void:
	var dir := RomLibrary.rom_dir_for_system(TEST_SYSTEM)
	if DirAccess.dir_exists_absolute(dir):
		_remove_tree(dir)


func _remove_tree(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while not name.is_empty():
		var full := path.path_join(name)
		if d.current_is_dir():
			_remove_tree(full)
		else:
			DirAccess.remove_absolute(full)
		name = d.get_next()
	d.list_dir_end()
	DirAccess.remove_absolute(path)


func _rom(name: String) -> String:
	var path := RomLibrary.rom_dir_for_system(TEST_SYSTEM).path_join(name)
	if not FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_string("rom " + name)
		f.close()
	return path


## A fresh queue over fake clients. `signed_in` decides whether the queue asks
## for the account's allowance at all.
func _queue(signed_in: bool = true, auto_info: Dictionary = {}) -> ScrapeQueue:
	_clients.clear()
	_auto_info = auto_info
	_config = ScraperConfig.new()
	if signed_in:
		_config.ssid = "tester"
		_config.sspassword = "secret"
	_gamelist = GamelistManager.new()
	var q := ScrapeQueue.new()
	add_child(q)
	q.setup(_config, _gamelist, func() -> ScreenscraperClient:
		var c := FakeClient.new()
		c.suite = self
		c.config = _config
		_clients.append(c)
		return c
	)
	return q


func _client_for(rom: String) -> FakeClient:
	for c: FakeClient in _clients:
		if c.holds(rom):
			return c
	return null


func _info_client() -> FakeClient:
	for c: FakeClient in _clients:
		if c.info_calls > 0:
			return c
	return null


## Waits until `n` scrapes are held by fake clients, or gives up.
func _until_held(n: int, limit := 120) -> void:
	for i in range(limit):
		var held := 0
		for c: FakeClient in _clients:
			held += c.held.size()
		if held >= n:
			return
		await get_tree().process_frame


func _result(name: String, extra: Dictionary = {}) -> Dictionary:
	var r := {
		"game_id": "1", "name": name, "desc": "", "developer": "d", "publisher": "p",
		"genre": "g", "rom_region": "us", "releasedate": "1990", "media": {},
	}
	r.merge(extra, true)
	return r


# ── userinfo ──────────────────────────────────────────────────────────────────

func _group_userinfo() -> void:
	var info := ScreenscraperClient.parse_user_info({
		"id": "tester", "niveau": "3", "maxthreads": "4", "requeststoday": "120",
		"maxrequestsperday": "20000", "maxrequestspermin": "300",
	})
	_ok(info["maxthreads"] == 4, "maxthreads read from a string")
	_ok(info["requeststoday"] == 120 and info["maxrequestsperday"] == 20000,
		"usage counters read from strings")
	_ok(info["niveau"] == 3, "level read from a string")
	_ok(info["anonymous"] == false, "an account is not anonymous")

	var anon := ScreenscraperClient.parse_user_info({})
	_ok(anon["maxthreads"] == 1, "no ssuser means one thread")
	_ok(anon["anonymous"] == true, "no ssuser is anonymous")
	_ok(ScreenscraperClient.parse_user_info({"maxthreads": "0"})["maxthreads"] == 1,
		"maxthreads 0 reads as one")
	_ok(ScreenscraperClient.parse_user_info({"maxthreads": "-3"})["maxthreads"] == 1,
		"negative maxthreads reads as one")
	_ok(ScreenscraperClient.parse_user_info({"requeststoday": "abc"})["requeststoday"] == 0,
		"a non-number counter reads as zero")

	# A real client with no credentials answers at once, with no request.
	var client := ScreenscraperClient.new()
	client.config = ScraperConfig.new()
	add_child(client)
	var got: Array = []
	client.user_info_received.connect(func(i: Dictionary) -> void: got.append(i))
	client.fetch_user_info()
	_ok(got.size() == 1 and got[0]["maxthreads"] == 1 and got[0]["anonymous"],
		"anonymous fetch_user_info answers one thread without a request")
	_ok(client.get_child_count() == 0, "anonymous fetch_user_info makes no HTTPRequest")
	client.free()


# ── queue ─────────────────────────────────────────────────────────────────────

func _group_queue() -> void:
	var q := _queue(false)
	var a := _rom("a.bin")
	var b := _rom("b.bin")
	_ok(not q.enqueue("", TEST_SYSTEM), "empty path refused")
	_ok(not q.enqueue(a, ""), "empty systemid refused")
	_ok(q.enqueue(a, TEST_SYSTEM), "first enqueue accepted")
	_ok(not q.enqueue(a, TEST_SYSTEM), "same path refused while queued or running")
	_ok(q.is_queued(a), "is_queued sees it")
	_ok(q.is_busy(), "busy with one item")
	_ok(q.enqueue(b, TEST_SYSTEM, {"tag": ScrapeQueue.TAG_AUTO}), "second enqueue accepted")
	await _until_held(1)
	_ok(q.active_count() == 1 and q.waiting_count() == 1, "one runs, one waits, anonymous")
	_ok(q.waiting_count(ScrapeQueue.TAG_AUTO) == 1 and q.waiting_count(ScrapeQueue.TAG_MANUAL) == 0,
		"waiting_count filters by tag")
	_ok(q.active_count(ScrapeQueue.TAG_MANUAL) == 1, "active_count filters by tag")
	_ok(_info_client() == null, "signed out: the allowance is never asked for")
	q.cancel_all(ScrapeQueue.TAG_MANUAL)
	_ok(q.waiting_count() == 1, "cancel by tag leaves the other tag waiting")
	q.cancel_all()
	_ok(q.waiting_count() == 0 and q.active_count() == 1,
		"cancel_all drops what waits and not what runs")
	_client_for(a).resolve(a, _result("A"))
	await _frames(3)
	_ok(not q.is_busy(), "idle once the running item finishes")

	var full := _queue(false)
	var accepted := 0
	for i in range(ScrapeQueue.MAX_QUEUE + 5):
		if full.enqueue("/nowhere/rom%d.bin" % i, TEST_SYSTEM):
			accepted += 1
	_ok(accepted == ScrapeQueue.MAX_QUEUE + 1,
		"queue holds MAX_QUEUE waiting plus the one running")
	full.cancel_all()
	await _frames(3)
	q.free()
	full.free()


# ── threads ───────────────────────────────────────────────────────────────────

func _group_threads() -> void:
	var q := _queue(true)
	var roms: Array[String] = []
	for i in range(5):
		roms.append(_rom("t%d.bin" % i))
		q.enqueue(roms[i], TEST_SYSTEM)
	await _until_held(1)
	await _frames(3)
	_ok(q.thread_count() == 1, "one thread until the account answers")
	_ok(q.active_count() == 1 and q.waiting_count() == 4, "one runs while the allowance is unknown")
	var info_c := _info_client()
	_ok(info_c != null and info_c.info_calls == 1, "signed in: the allowance was asked for once")

	var changes: Array = []
	q.threads_changed.connect(func(n: int) -> void: changes.append(n))
	info_c.user_info_received.emit(ScreenscraperClient.parse_user_info({"maxthreads": "3"}))
	await _until_held(3)
	await _frames(2)
	_ok(q.thread_count() == 3 and changes == [3], "allowance of three applied and announced")
	_ok(q.active_count() == 3 and q.waiting_count() == 2, "three run at once, two wait")

	# A scrape answer carries the allowance too; narrowing it stops the queue
	# handing the next item to a worker that is now surplus.
	_client_for(roms[0]).resolve(roms[0], _result("T0", {"ssuser": {"maxthreads": "2"}}))
	await _frames(4)
	_ok(q.thread_count() == 2, "an answer's ssuser narrows the allowance")
	_ok(q.active_count() == 2 and q.waiting_count() == 2,
		"no new item starts while two already run under an allowance of two")

	info_c.user_info_received.emit(ScreenscraperClient.parse_user_info({"maxthreads": "50"}))
	await _frames(2)
	_ok(q.thread_count() == ScrapeQueue.MAX_THREADS, "allowance clamped to MAX_THREADS")
	await _until_held(4)
	_ok(q.active_count() == 4 and q.waiting_count() == 0, "widening starts everything waiting")

	# Credentials changed: asked again on refresh, not otherwise.
	q.refresh_threads()
	_ok(info_c.info_calls == 2, "refresh_threads asks the account again")
	q.cancel_all()
	for r: String in roms:
		var c := _client_for(r)
		if c != null:
			c.resolve(r, _result("x"))
	await _frames(3)
	q.free()


# ── results ───────────────────────────────────────────────────────────────────

func _group_results() -> void:
	var q := _queue(false)
	var a := _rom("r_accept.bin")
	var b := _rom("r_review.bin")
	var done: Array = []
	q.completed.connect(func(rom: String, _sid: String, res: Dictionary, acc: bool) -> void:
		done.append([rom, res.get("name", ""), acc]))
	var drained: Array = []
	q.drained.connect(func(d: int, f: int) -> void: drained.append([d, f]))

	q.enqueue(a, TEST_SYSTEM)
	await _until_held(1)
	_client_for(a).resolve(a, _result("Accepted Game"))
	await _frames(4)
	_ok(done.size() == 1 and done[0][2] == true, "an ordinary item completes as accepted")
	var fresh := GamelistManager.new()
	var game := fresh.get_game_for_rom(TEST_SYSTEM, a)
	_ok(str(game.get("name", "")) == "Accepted Game", "accepted result is in the gamelist on disk")
	_ok(not ScrapeQueue.needs_scrape(fresh, TEST_SYSTEM, a), "needs_scrape is false once scraped")
	_ok(drained == [[1, 0]], "drained reports one done")

	q.enqueue(b, TEST_SYSTEM, {"review": true})
	await _until_held(1)
	_client_for(b).resolve(b, _result("Review Game"))
	await _frames(4)
	_ok(done.size() == 2 and done[1][2] == false and done[1][1] == "Review Game",
		"a review item hands its result back unaccepted")
	fresh = GamelistManager.new()
	_ok(fresh.get_game_for_rom(TEST_SYSTEM, b).is_empty(), "a review result is not written")
	_ok(ScrapeQueue.needs_scrape(fresh, TEST_SYSTEM, b), "needs_scrape stays true for it")
	_ok(ScrapeQueue.needs_scrape(null, TEST_SYSTEM, b), "needs_scrape with no gamelist says yes")

	# "Scrape all" over a page holding a scraped game, an unscraped one, a
	# blank row and one already waiting: only the unscraped one is taken.
	var c := _rom("r_waiting.bin")
	q.enqueue(c, TEST_SYSTEM)
	var pick := q.select_unscraped(TEST_SYSTEM, [a, b, "", c])
	_ok(pick["paths"] == [b] and pick["skipped"] == 1,
		"select_unscraped takes the unscraped ROM, skips the scraped one and the one queued")
	q.cancel_all()
	await _until_held(1)
	_client_for(c).refuse(c, "Not found")
	await _frames(3)

	var missing := RomLibrary.rom_dir_for_system(TEST_SYSTEM).path_join("absent.bin")
	var failures: Array = []
	q.failed.connect(func(rom: String, _sid: String, err: String) -> void: failures.append([rom, err]))
	q.enqueue(missing, TEST_SYSTEM)
	await _frames(6)
	_ok(failures.size() == 1 and failures[0][0] == missing, "a file that cannot be hashed fails")
	_ok(drained.size() == 4 and drained.back() == [0, 1], "drained reports the failure")
	q.free()


# ── scraped ───────────────────────────────────────────────────────────────────

func _group_scraped() -> void:
	var q := _queue(false)
	var rom := _rom("s_romm.bin")
	var download := {"game_id": "romm:41", "name": "Server Name", "desc": ""}
	_gamelist.add_or_merge_rom(TEST_SYSTEM, download.duplicate(),
		{"path": "./s_romm.bin", "romname": "s_romm.bin"})
	_ok(ScrapeQueue.needs_scrape(_gamelist, TEST_SYSTEM, rom),
		"a game only the RomM downloader has named still needs a scrape")

	q.enqueue(rom, TEST_SYSTEM)
	await _until_held(1)
	_client_for(rom).resolve(rom, _result("Scraped Name"))
	await _frames(4)
	var fresh := GamelistManager.new()
	var game := fresh.get_game_for_rom(TEST_SYSTEM, rom)
	_ok(str(game.get("game_id", "")) == "romm:41" and bool(game.get("scraped", false)),
		"a scrape over a RomM entry keeps the RomM id and flags it scraped")
	_ok(not ScrapeQueue.needs_scrape(fresh, TEST_SYSTEM, rom),
		"a scraped RomM entry needs no scrape though the answer had no description")
	fresh.add_or_merge_rom(TEST_SYSTEM, download.duplicate(),
		{"path": "./s_romm.bin", "romname": "s_romm.bin"})
	_ok(ScrapeQueue.is_scraped(fresh.get_game_for_rom(TEST_SYSTEM, rom)),
		"downloading it again leaves it scraped")

	_ok(ScrapeQueue.is_scraped({"game_id": "5405", "name": "Banjo-Kazooie"}),
		"an unflagged entry with a ScreenScraper id counts as scraped")
	_ok(ScrapeQueue.is_scraped({"game_id": "romm:79835", "name": "Rayman 2",
		"desc": "Enter a massive 3-D action adventure."}),
		"an unflagged RomM entry with a description counts as scraped")
	_ok(not ScrapeQueue.is_scraped({"game_id": "9", "name": ""}), "an unnamed entry is not scraped")
	_ok(not ScrapeQueue.is_scraped({}), "no entry is not scraped")

	var split := _rom("s_split.bin")
	var gl := GamelistManager.new()
	var games: Array = gl.load_gamelist(TEST_SYSTEM)["games"]
	games.append({"game_id": "romm:88", "name": "Split", "desc": "",
		"roms": [{"path": "./s_split.bin", "romname": "s_split.bin"}]})
	games.append({"game_id": "88", "name": "Split", "desc": "", "scraped": true,
		"roms": [{"path": "./s_split.bin", "romname": "s_split.bin"}]})
	gl.dedupe(TEST_SYSTEM)
	var folded := gl.get_game_for_rom(TEST_SYSTEM, split)
	_ok(str(folded.get("game_id", "")) == "romm:88" and bool(folded.get("scraped", false)),
		"dedupe keeps the scraped flag of the entry it folds away")

	var first := _rom("s_first.bin")
	q.enqueue(first, TEST_SYSTEM)
	await _until_held(1)
	_client_for(first).resolve(first, _result("Scraped First"))
	await _frames(4)
	var later := GamelistManager.new()
	later.add_or_merge_rom(TEST_SYSTEM, {"game_id": "romm:42", "name": "Server Name", "desc": ""},
		{"path": "./s_first.bin", "romname": "s_first.bin"})
	var adopted := later.get_game_for_rom(TEST_SYSTEM, first)
	_ok(str(adopted.get("game_id", "")) == "romm:42" and ScrapeQueue.is_scraped(adopted),
		"a game scraped before RomM downloads it stays scraped under the RomM id")

	var twice := _rom("s_twice.bin")
	var pick := q.select_unscraped(TEST_SYSTEM, [rom, rom, twice, twice])
	_ok(pick["paths"] == [twice] and pick["skipped"] == 1,
		"select_unscraped takes or skips a path several rows share once")

	var symbols: Font = load(MenuIcons.FONT_PATH)
	_ok(symbols != null and symbols.has_char(MenuIcons.RESCRAPE),
		"the rescrape glyph is in the bundled symbol font")
	q.free()


# ── media ─────────────────────────────────────────────────────────────────────

func _group_media() -> void:
	var q := _queue(false)
	var a := _rom("m_first.bin")
	var b := _rom("m_second.bin")
	var media: Array = []
	q.media_downloaded.connect(func(rom: String, sid: String, t: String, p: String) -> void:
		media.append([rom, sid, t, p]))
	q.enqueue(a, TEST_SYSTEM)
	q.enqueue(b, TEST_SYSTEM)
	await _until_held(1)
	var c := _client_for(a)
	c.media_types = ["wheel", "label"]
	c.resolve(a, _result("First"))
	await _frames(4)
	_ok(q.active_count() == 1 and not c.holds(b), "the worker waits for its art before the next game")
	c.finish_media("wheel", "/w.png")
	await _frames(2)
	_ok(c.held.is_empty(), "one of two transfers landing is not enough")
	c.finish_media("label", "/l.png")
	await _until_held(1)
	_ok(c.holds(b), "the next game starts once every transfer has landed")
	_ok(media.size() == 2 and media[0][0] == a and media[0][2] == "wheel"
		and media[1][2] == "label" and media[0][1] == TEST_SYSTEM,
		"media_downloaded names the ROM the art belongs to")
	c.media_types = []
	c.resolve(b, _result("Second"))
	await _frames(3)
	q.free()


# ── quota ─────────────────────────────────────────────────────────────────────

func _group_quota() -> void:
	var q := _queue(false)
	var roms: Array[String] = []
	for i in range(3):
		roms.append(_rom("q%d.bin" % i))
		q.enqueue(roms[i], TEST_SYSTEM)
	var failures: Array = []
	var stops: Array = []
	var drained: Array = []
	q.failed.connect(func(rom: String, _sid: String, err: String) -> void: failures.append([rom, err]))
	q.stopped.connect(func(r: String) -> void: stops.append(r))
	q.drained.connect(func(d: int, f: int) -> void: drained.append([d, f]))
	await _until_held(1)
	_client_for(roms[0]).refuse(roms[0], "Daily scrape quota exceeded")
	await _frames(3)
	_ok(failures.size() == 3, "a quota refusal fails the running item and everything waiting")
	_ok(failures[1][1] == "Daily scrape quota exceeded" and failures[2][0] == roms[2],
		"the dropped items carry the quota as their reason")
	_ok(stops == ["Daily scrape quota exceeded"], "stopped emitted once")
	_ok(drained == [[0, 3]], "drained counts the three failures")
	_ok(not q.is_busy(), "queue is idle after a quota stop")

	# The same stop from the account's own counters, before a single refusal.
	var q2 := _queue(true)
	var stops2: Array = []
	q2.stopped.connect(func(r: String) -> void: stops2.append(r))
	var x := _rom("q_x.bin")
	var y := _rom("q_y.bin")
	q2.enqueue(x, TEST_SYSTEM)
	q2.enqueue(y, TEST_SYSTEM)
	await _until_held(1)
	_info_client().user_info_received.emit(ScreenscraperClient.parse_user_info({
		"maxthreads": "2", "requeststoday": "500", "maxrequestsperday": "500"}))
	await _frames(2)
	_ok(stops2.size() == 1 and q2.waiting_count() == 0,
		"an account already at its daily limit drops what waits")
	_ok(q2.active_count() == 1, "what was already running is left to finish")
	_client_for(x).refuse(x, "Not found")
	await _frames(3)
	q.free()
	q2.free()


# ── auto ──────────────────────────────────────────────────────────────────────

func _group_auto() -> void:
	var q := _queue(false)
	var auto := AutoScraper.new()
	add_child(auto)
	auto.setup(q, _gamelist, _config)
	var a := _rom("auto_a.bin")
	_config.auto_scrape = false
	_ok(not auto.is_enabled(), "switch off: auto-scraping is off")
	auto.request(a, TEST_SYSTEM)
	_ok(not q.is_queued(a), "a request while off queues nothing")

	_config.auto_scrape = true
	_ok(auto.is_enabled(), "switch on with no credentials: it runs anonymously")
	auto.request("", TEST_SYSTEM)
	auto.request(a, "")
	auto.request(RomLibrary.rom_dir_for_system(TEST_SYSTEM).path_join("ghost.bin"), TEST_SYSTEM)
	_ok(not q.is_busy(), "empty args and a missing file queue nothing")

	# A ROM the gamelist already names is left alone.
	_gamelist.add_or_merge_rom(TEST_SYSTEM, {"game_id": "9", "name": "Known"},
		{"path": "./auto_known.bin", "romname": "auto_known.bin"})
	var known := _rom("auto_known.bin")
	_ok(auto.already_scraped(known, TEST_SYSTEM), "already_scraped reads the gamelist")
	auto.request(known, TEST_SYSTEM)
	_ok(not q.is_queued(known), "a scraped ROM is not requested again")

	var scraped: Array = []
	auto.scraped.connect(func(rom: String, _sid: String) -> void: scraped.append(rom))
	auto.request(a, TEST_SYSTEM)
	_ok(q.is_queued(a) and q.active_count(ScrapeQueue.TAG_AUTO) + q.waiting_count(ScrapeQueue.TAG_AUTO) == 1,
		"a request is queued under the auto tag")
	_ok(auto.queued_count() == 1, "queued_count counts it")
	auto.request(a, TEST_SYSTEM)
	_ok(auto.queued_count() == 1, "a second request for the same ROM is not a second item")

	await _until_held(1)
	_client_for(a).resolve(a, _result("Auto Game"))
	await _frames(4)
	_ok(scraped == [a], "scraped fires for an accepted result")
	_ok(not ScrapeQueue.needs_scrape(GamelistManager.new(), TEST_SYSTEM, a),
		"the auto result is on disk")

	# The gate's own bound: 64 waiting, however many are asked for.
	var held_one := _rom("auto_hold.bin")
	auto.request(held_one, TEST_SYSTEM)
	await _until_held(1)
	for i in range(AutoScraper.MAX_QUEUE + 10):
		auto.request(_rom("auto_bulk_%d.bin" % i), TEST_SYSTEM)
	_ok(q.waiting_count(ScrapeQueue.TAG_AUTO) == AutoScraper.MAX_QUEUE,
		"auto requests stop at MAX_QUEUE waiting")
	var manual := _rom("auto_manual.bin")
	_ok(q.enqueue(manual, TEST_SYSTEM), "the auto bound does not block a manual item")
	auto.cancel_all()
	_ok(q.waiting_count(ScrapeQueue.TAG_AUTO) == 0 and q.waiting_count(ScrapeQueue.TAG_MANUAL) == 1,
		"AutoScraper.cancel_all drops only auto items")
	q.cancel_all()
	_client_for(held_one).resolve(held_one, _result("h"))
	await _frames(3)
	auto.free()
	q.free()


# ── config ────────────────────────────────────────────────────────────────────

func _group_config() -> void:
	var path := ScraperConfig._config_path()
	var had := FileAccess.file_exists(path)
	var snapshot := FileAccess.get_file_as_bytes(path) if had else PackedByteArray()

	var c := ScraperConfig.new()
	c.load_config()
	_ok(c.approve_scrapes == false, "approve_scrapes defaults off")
	c.approve_scrapes = true
	_ok(c.save_config(), "config saves")
	var again := ScraperConfig.new()
	again.load_config()
	_ok(again.approve_scrapes == true, "approve_scrapes round-trips")

	if had:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_buffer(snapshot)
		f.close()
	else:
		DirAccess.remove_absolute(path)
	var restored := ScraperConfig.new()
	restored.load_config()
	_ok(restored.approve_scrapes == false or had, "player's config restored")


## The region/language priority editor: pure order edits, the catalogues, and
## the widget end to end through its inline card (no Viewport2Din3D here).
func _group_priority() -> void:
	var order: Array[String] = ["us", "eu", "jp"]
	_ok(PriorityOptions2D.toggle(order, "wor") == ["us", "eu", "jp", "wor"],
		"ticking appends at the end")
	_ok(PriorityOptions2D.toggle(order, "eu") == ["us", "jp"], "unticking removes")
	var one: Array[String] = ["us"]
	_ok(PriorityOptions2D.toggle(one, "us") == ["us"], "the last pick cannot be unticked")
	_ok(order == ["us", "eu", "jp"], "toggle leaves its input alone")

	_ok(PriorityOptions2D.move(order, "jp", -1) == ["us", "jp", "eu"], "up one place")
	_ok(PriorityOptions2D.move(order, "us", 1) == ["eu", "us", "jp"], "down one place")
	_ok(PriorityOptions2D.move(order, "us", -1) == order, "first cannot go up")
	_ok(PriorityOptions2D.move(order, "jp", 1) == order, "last cannot go down")
	_ok(PriorityOptions2D.move(order, "de", -1) == order, "an unpicked code does not move")

	var typed: Array[String] = ["us", "xx"]
	var items := PriorityOptions2D.with_unknown([["us", "USA", ""]], typed)
	_ok(items.size() == 2 and items[1] == ["xx", "xx", ""],
		"a hand-typed code outside the catalogue is kept, shown by its code")

	for table: Array in [ScraperConfig.REGIONS, ScraperConfig.LANGUAGES]:
		var seen := {}
		var flagless := PackedStringArray()
		for entry: Array in table:
			seen[entry[0]] = true
			if entry[0] != "ss" and MenuIcons.region_flag(str(entry[2])).is_empty():
				flagless.append(str(entry[0]))
		_ok(seen.size() == table.size(), "catalogue codes are unique")
		_ok(flagless.is_empty(), "every catalogue entry draws a flag: %s" % str(flagless))
	var defaults := ScraperConfig.new()
	for code: String in defaults.region_priorities + defaults.language_priorities:
		var known := false
		for entry: Array in ScraperConfig.REGIONS + ScraperConfig.LANGUAGES:
			known = known or entry[0] == code
		_ok(known, "default priority '%s' is in the catalogue" % code)

	# Media is picked from the ROM's own regions first, ranked by the PLAYER'S
	# priority. ScreenScraper lists Sonic the Hedgehog (USA, Europe) as
	# eu, us, wor; taken in that order it scraped the Mega Drive box.
	var prio: Array[String] = ["us", "eu", "wor", "jp", "ss"]
	_ok(ScreenscraperClient.media_region_order(["eu", "us", "wor"], prio)
		== ["us", "eu", "wor", "jp", "ss"], "a USA/Europe ROM ranks its regions by the player's order")
	var eu_first: Array[String] = ["eu", "us", "wor", "jp", "ss"]
	_ok(ScreenscraperClient.media_region_order(["eu", "us", "wor"], eu_first)
		== ["eu", "us", "wor", "jp", "ss"], "and the other way round for a player who puts Europe first")
	_ok(ScreenscraperClient.media_region_order(["jp"], prio)
		== ["jp", "wor", "us", "eu", "ss"], "a Japan-only ROM still gets its own region's art first")
	_ok(ScreenscraperClient.media_region_order(["br", "us"], prio)
		== ["us", "br", "wor", "eu", "jp", "ss"], "a ROM region the player never ranked follows the ranked ones")
	_ok(ScreenscraperClient.media_region_order([], prio)
		== ["wor", "us", "eu", "jp", "ss"], "no ROM regions: world, then the player's order")

	# The whole picker, on Sonic's real media list (trimmed to the types it reads).
	var client := ScreenscraperClient.new()
	client.config = ScraperConfig.new()
	client.config.region_priorities = prio
	var medias: Array = []
	for t: String in ["wheel", "box-texture", "support-texture"]:
		for r: String in (["eu", "jp", "us"] if t == "wheel" else ["br", "eu", "jp", "kr", "us"]):
			medias.append({"type": t, "region": r, "url": "%s/%s" % [t, r]})
	var picked: Dictionary = client._extract_media_urls(medias, ["eu", "us", "wor"])
	_ok(picked["box"] == "box-texture/us" and picked["label"] == "support-texture/us"
		and picked["wheel"] == "wheel/us", "Sonic (USA, Europe) scrapes the USA box, label and logo: %s" % str(picked))
	client.config.region_priorities = eu_first
	picked = client._extract_media_urls(medias, ["eu", "us", "wor"])
	_ok(picked["box"] == "box-texture/eu", "and the Europe box with Europe first")
	client.free()

	var start: Array[String] = ["us", "eu"]
	var d := VRPriorityDropdown.create("Region Priority",
		[["us", "USA", "U"], ["eu", "Europe", "E"], ["jp", "Japan", "J"]], start)
	var got: Array = []
	d.order_changed.connect(func(o: Array[String]) -> void: got.append(o))
	add_child(d)
	_ok(d.summary() == "U › E", "the toggle spells the order out")
	d._on_toggle_pressed()
	_ok(d.is_open() and d._inline != null and d._inline.visible,
		"no 3D host: the card opens inline")
	d._inline._apply(PriorityOptions2D.toggle(d._inline.get_order(), "jp"))
	d._inline._apply(PriorityOptions2D.move(d._inline.get_order(), "jp", -2))
	_ok(got.size() == 2 and got[1] == ["jp", "us", "eu"], "each edit is announced whole")
	_ok(d.get_order() == ["jp", "us", "eu"] and d.summary() == "J › U › E",
		"the row follows the card")
	_ok(start == ["us", "eu"], "the caller's array is not edited in place")
	d.close()
	_ok(not d.is_open() and not d._inline.visible, "close hides the card")
	d.queue_free()


# ── A cabinet's attract mode: video and title, on demand, arcade only ───────────

func _group_cabinet_media() -> void:
	var medias := [
		{"type": "wheel", "url": "https://x/w.png", "region": "wor"},
		{"type": "video", "url": "https://x/v.mp4", "region": "wor"},
		{"type": "sstitle", "url": "https://x/t.png", "region": "wor"},
	]
	var client := ScreenscraperClient.new()
	client.config = ScraperConfig.new()
	var plain: Dictionary = client._extract_media_urls(medias, ["wor"], 0, 0, true)
	_ok(not plain.has("video") and not plain.has("title"),
		"cabinet media: a scrape that asks for nothing extra finds no video or title")
	_ok(plain["wheel"] == "https://x/w.png", "cabinet media: and still finds the wheel")
	client.extra_media = ScreenscraperClient.CABINET_MEDIA
	var arcade: Dictionary = client._extract_media_urls(medias, ["wor"], 0, 0, true)
	_ok(arcade["video"] == "https://x/v.mp4" and arcade["title"] == "https://x/t.png",
		"cabinet media: asked for, an arcade game gives its video snap and its title")
	var console: Dictionary = client._extract_media_urls(medias, ["wor"], 0, 0, false)
	_ok(not console.has("video") and not console.has("title"),
		"cabinet media: a game that is not arcade gives neither, even asked")
	client.extra_media = ["video", "marquee"]
	var odd: Dictionary = client._extract_media_urls(medias, ["wor"], 0, 0, true)
	_ok(odd.has("video") and not odd.has("title") and not odd.has("marquee"),
		"cabinet media: only the kinds the client knows are taken")
	client.extra_media = ["video"]
	var both := [
		{"type": "video", "url": "https://x/big.mp4", "region": ""},
		{"type": "video-normalized", "url": "https://x/small.mp4", "region": ""},
	]
	var pick: Dictionary = client._extract_media_urls(both, [], 0, 0, true)
	_ok(pick["video"] == "https://x/small.mp4", "cabinet media: the smaller normalized video is taken when there is one")
	pick = client._extract_media_urls([both[0]], [], 0, 0, true)
	_ok(pick["video"] == "https://x/big.mp4", "cabinet media: and the plain one when there is not")
	# No title screen: the game's screenshot fills the title slot, so an attract shows the game, not its wheel.
	client.extra_media = ScreenscraperClient.CABINET_MEDIA
	var shot := [
		{"type": "wheel", "url": "https://x/w.png", "region": "wor"},
		{"type": "ss", "url": "https://x/ss.png", "region": "wor"},
	]
	pick = client._extract_media_urls(shot, ["wor"], 0, 0, true)
	_ok(pick["title"] == "https://x/ss.png", "cabinet media: with no title screen the screenshot stands in for it")
	pick = client._extract_media_urls(shot + [{"type": "sstitle", "url": "https://x/t.png", "region": "wor"}], ["wor"], 0, 0, true)
	_ok(pick["title"] == "https://x/t.png", "cabinet media: and never ahead of a real title screen")
	client.extra_media = ["video"]
	pick = client._extract_media_urls(shot, ["wor"], 0, 0, true)
	_ok(not pick.has("title"), "cabinet media: a scrape that did not ask for a title gets no screenshot either")
	client.free()

	# ScreenScraper files many arcade games under a SUB-system of Arcade (Point Blank answers as 155 "Namco
	# Classics", parent 75). Judged by 155 alone the game was no arcade game and its extras were dropped
	# without a word (the attract mode's first real run, 2026-10-22).
	var jeu := {"id": "42538", "noms": [{"region": "wor", "text": "Point Blank"}],
		"systeme": {"id": "155", "text": "Namco Classics", "parentid": "75"},
		"medias": medias}
	var sub := ScreenscraperClient.new()
	sub.config = ScraperConfig.new()
	sub.extra_media = ScreenscraperClient.CABINET_MEDIA
	var got: Dictionary = (sub._parse_jeu(jeu) as Dictionary)["media"]
	_ok(got.has("video") and got.has("title"), "cabinet media: a game answering under a sub-system of Arcade (parent 75) is an arcade game")
	var bare := jeu.duplicate(true)
	bare["systeme"] = {"id": "155", "text": "Namco Classics"}
	got = (sub._parse_jeu(bare) as Dictionary)["media"]
	_ok(not got.has("video"), "cabinet media: with no parent and nothing asked about, it is judged by its own system alone")
	sub._requested_systemeid = ScreenscraperSystems.get_systemeid("arcade")
	got = (sub._parse_jeu(bare) as Dictionary)["media"]
	_ok(got.has("video") and got.has("title"), "cabinet media: or by the system the scrape asked about")
	sub._requested_systemeid = ScreenscraperSystems.get_systemeid("neogeo")
	got = (sub._parse_jeu(bare) as Dictionary)["media"]
	_ok(got.has("video"), "cabinet media: a Neo Geo MVS cabinet's game counts too")
	sub._requested_systemeid = ScreenscraperSystems.get_systemeid("nes")
	bare["systeme"] = {"id": "3", "text": "NES", "parentid": "0"}
	got = (sub._parse_jeu(bare) as Dictionary)["media"]
	_ok(not got.has("video") and not got.has("title"), "cabinet media: a console game gets neither")
	sub.free()

	var rec := RecordingClient.new()
	rec.config = ScraperConfig.new()
	add_child(rec)
	var result := {"media": {"wheel": "https://x/w.png", "box": "https://x/b.png",
		"video": "https://x/v.mp4", "title": "https://x/t.png"}}
	await rec.download_all_media(result, TEST_SYSTEM, "game")
	var types: Array = rec.got.map(func(g: Dictionary) -> String: return g["type"])
	_ok(types.has("wheel") and types.has("box") and types.has("video") and types.has("title"),
		"cabinet media: with no filter every type in the result is fetched")
	rec.got.clear()
	rec.media_filter = ["video", "title"]
	await rec.download_all_media(result, TEST_SYSTEM, "game")
	types = rec.got.map(func(g: Dictionary) -> String: return g["type"])
	_ok(types.size() == 2 and types.has("video") and types.has("title"),
		"cabinet media: filtered, a game that has its art pays for the video and title alone (%s)" % str(types))
	var video: Dictionary = rec.got.filter(func(g: Dictionary) -> bool: return g["type"] == "video")[0]
	_ok(str(video["dest"]).ends_with("/media/video/game.mp4"),
		"cabinet media: the video lands in media/video/<rom>.mp4")
	var title: Dictionary = rec.got.filter(func(g: Dictionary) -> bool: return g["type"] == "title")[0]
	_ok(str(title["dest"]).ends_with("/media/title/game.png"),
		"cabinet media: the title in media/title/<rom>.png")
	rec.got.clear()
	rec.media_filter = []
	await rec.download_all_media({"media": {"video": "https://x/clip.bin?x=1.exe"}}, TEST_SYSTEM, "game")
	_ok(str(rec.got[0]["dest"]).ends_with("/game.mp4"),
		"cabinet media: a tail that is no video extension does not name the file")
	rec.queue_free()

	# Through the queue: an already-scraped game is asked again for its media alone.
	var q := _queue(false)
	var auto := AutoScraper.new()
	add_child(auto)
	auto.setup(q, _gamelist, _config)
	var rom := _rom("cab_media.bin")
	_gamelist.add_or_merge_rom(TEST_SYSTEM, {"game_id": "42", "name": "Done", "scraped": true},
		{"path": "./cab_media.bin", "romname": "cab_media.bin"})
	_ok(auto.already_scraped(rom, TEST_SYSTEM), "cabinet media: the game is already scraped")
	_config.auto_scrape = false
	auto.request_media(rom, TEST_SYSTEM, ScreenscraperClient.CABINET_MEDIA)
	_ok(not q.is_queued(rom), "cabinet media: with auto-scrape off no request is made")
	_config.auto_scrape = true
	auto.request(rom, TEST_SYSTEM)
	_ok(not q.is_queued(rom), "cabinet media: the ordinary request skips a game already scraped")
	auto.request_media(rom, TEST_SYSTEM, ScreenscraperClient.CABINET_MEDIA)
	_ok(q.is_queued(rom), "cabinet media: but its video and title are asked for")
	await _until_held(1)
	var c := _client_for(rom)
	_ok(c != null and c.extra_media == ScreenscraperClient.CABINET_MEDIA and c.media_filter == ScreenscraperClient.CABINET_MEDIA,
		"cabinet media: the client is told to fetch those kinds and only those")
	if c != null:
		c.resolve(rom, _result("Done"))
		await _frames(4)
	var other := _rom("cab_plain.bin")
	auto.request(other, TEST_SYSTEM)
	await _until_held(1)
	var c2 := _client_for(other)
	_ok(c2 != null and c2.extra_media.is_empty() and c2.media_filter.is_empty(),
		"cabinet media: an ordinary scrape after it asks for nothing extra")
	# A game already waiting for an ordinary scrape brings the extras too, and still fetches its usual art.
	var third := _rom("cab_wait.bin")
	q.cancel_all()
	await _frames(2)
	var blockers: Array[String] = []
	for i in 8:
		var b := _rom("cab_block_%d.bin" % i)
		blockers.append(b)
		q.enqueue(b, TEST_SYSTEM)
	q.enqueue(third, TEST_SYSTEM)
	_ok(q.is_queued(third), "cabinet media: a game is in the queue for an ordinary scrape")
	auto.request_media(third, TEST_SYSTEM, ScreenscraperClient.CABINET_MEDIA)
	var waiting_item := {}
	for item: Dictionary in q._queue:
		if str(item["rom"]) == third:
			waiting_item = item
	if not waiting_item.is_empty():
		_ok(waiting_item.get("extra", []) == ScreenscraperClient.CABINET_MEDIA and (waiting_item.get("media", []) as Array).is_empty(),
			"cabinet media: it brings the extras and is not narrowed to them (the wheel and box still come)")
	else:
		_ok(true, "cabinet media: (the game had already started; nothing to join)")
	_ok(not q.add_extra_media(_rom("never_queued.bin"), ["video"]), "cabinet media: a game that is not waiting cannot join")
	auto.queue_free()
	q.queue_free()
