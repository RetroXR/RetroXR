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
extends Node

const TEST_SYSTEM := "__scrape_selftest"

var _checks := 0
var _fail := 0
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
	_teardown()
	print("[test] %d checks, %d failures" % [_checks, _fail])
	get_tree().quit(1 if _fail else 0)


func _run_group(name: String, fn: Callable) -> void:
	if not _only.is_empty() and _only != name:
		return
	print("[test] --- %s ---" % name)
	await fn.call()


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fail += 1
	print("[test] %s %s" % ["PASS" if ok else "FAIL", label])


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
	_check(info["maxthreads"] == 4, "maxthreads read from a string")
	_check(info["requeststoday"] == 120 and info["maxrequestsperday"] == 20000,
		"usage counters read from strings")
	_check(info["niveau"] == 3, "level read from a string")
	_check(info["anonymous"] == false, "an account is not anonymous")

	var anon := ScreenscraperClient.parse_user_info({})
	_check(anon["maxthreads"] == 1, "no ssuser means one thread")
	_check(anon["anonymous"] == true, "no ssuser is anonymous")
	_check(ScreenscraperClient.parse_user_info({"maxthreads": "0"})["maxthreads"] == 1,
		"maxthreads 0 reads as one")
	_check(ScreenscraperClient.parse_user_info({"maxthreads": "-3"})["maxthreads"] == 1,
		"negative maxthreads reads as one")
	_check(ScreenscraperClient.parse_user_info({"requeststoday": "abc"})["requeststoday"] == 0,
		"a non-number counter reads as zero")

	# A real client with no credentials answers at once, with no request.
	var client := ScreenscraperClient.new()
	client.config = ScraperConfig.new()
	add_child(client)
	var got: Array = []
	client.user_info_received.connect(func(i: Dictionary) -> void: got.append(i))
	client.fetch_user_info()
	_check(got.size() == 1 and got[0]["maxthreads"] == 1 and got[0]["anonymous"],
		"anonymous fetch_user_info answers one thread without a request")
	_check(client.get_child_count() == 0, "anonymous fetch_user_info makes no HTTPRequest")
	client.free()


# ── queue ─────────────────────────────────────────────────────────────────────

func _group_queue() -> void:
	var q := _queue(false)
	var a := _rom("a.bin")
	var b := _rom("b.bin")
	_check(not q.enqueue("", TEST_SYSTEM), "empty path refused")
	_check(not q.enqueue(a, ""), "empty systemid refused")
	_check(q.enqueue(a, TEST_SYSTEM), "first enqueue accepted")
	_check(not q.enqueue(a, TEST_SYSTEM), "same path refused while queued or running")
	_check(q.is_queued(a), "is_queued sees it")
	_check(q.is_busy(), "busy with one item")
	_check(q.enqueue(b, TEST_SYSTEM, {"tag": ScrapeQueue.TAG_AUTO}), "second enqueue accepted")
	await _until_held(1)
	_check(q.active_count() == 1 and q.waiting_count() == 1, "one runs, one waits, anonymous")
	_check(q.waiting_count(ScrapeQueue.TAG_AUTO) == 1 and q.waiting_count(ScrapeQueue.TAG_MANUAL) == 0,
		"waiting_count filters by tag")
	_check(q.active_count(ScrapeQueue.TAG_MANUAL) == 1, "active_count filters by tag")
	_check(_info_client() == null, "signed out: the allowance is never asked for")
	q.cancel_all(ScrapeQueue.TAG_MANUAL)
	_check(q.waiting_count() == 1, "cancel by tag leaves the other tag waiting")
	q.cancel_all()
	_check(q.waiting_count() == 0 and q.active_count() == 1,
		"cancel_all drops what waits and not what runs")
	_client_for(a).resolve(a, _result("A"))
	await _frames(3)
	_check(not q.is_busy(), "idle once the running item finishes")

	var full := _queue(false)
	var accepted := 0
	for i in range(ScrapeQueue.MAX_QUEUE + 5):
		if full.enqueue("/nowhere/rom%d.bin" % i, TEST_SYSTEM):
			accepted += 1
	_check(accepted == ScrapeQueue.MAX_QUEUE + 1,
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
	_check(q.thread_count() == 1, "one thread until the account answers")
	_check(q.active_count() == 1 and q.waiting_count() == 4, "one runs while the allowance is unknown")
	var info_c := _info_client()
	_check(info_c != null and info_c.info_calls == 1, "signed in: the allowance was asked for once")

	var changes: Array = []
	q.threads_changed.connect(func(n: int) -> void: changes.append(n))
	info_c.user_info_received.emit(ScreenscraperClient.parse_user_info({"maxthreads": "3"}))
	await _until_held(3)
	await _frames(2)
	_check(q.thread_count() == 3 and changes == [3], "allowance of three applied and announced")
	_check(q.active_count() == 3 and q.waiting_count() == 2, "three run at once, two wait")

	# A scrape answer carries the allowance too; narrowing it stops the queue
	# handing the next item to a worker that is now surplus.
	_client_for(roms[0]).resolve(roms[0], _result("T0", {"ssuser": {"maxthreads": "2"}}))
	await _frames(4)
	_check(q.thread_count() == 2, "an answer's ssuser narrows the allowance")
	_check(q.active_count() == 2 and q.waiting_count() == 2,
		"no new item starts while two already run under an allowance of two")

	info_c.user_info_received.emit(ScreenscraperClient.parse_user_info({"maxthreads": "50"}))
	await _frames(2)
	_check(q.thread_count() == ScrapeQueue.MAX_THREADS, "allowance clamped to MAX_THREADS")
	await _until_held(4)
	_check(q.active_count() == 4 and q.waiting_count() == 0, "widening starts everything waiting")

	# Credentials changed: asked again on refresh, not otherwise.
	q.refresh_threads()
	_check(info_c.info_calls == 2, "refresh_threads asks the account again")
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
	_check(done.size() == 1 and done[0][2] == true, "an ordinary item completes as accepted")
	var fresh := GamelistManager.new()
	var game := fresh.get_game_for_rom(TEST_SYSTEM, a)
	_check(str(game.get("name", "")) == "Accepted Game", "accepted result is in the gamelist on disk")
	_check(not ScrapeQueue.needs_scrape(fresh, TEST_SYSTEM, a), "needs_scrape is false once scraped")
	_check(drained == [[1, 0]], "drained reports one done")

	q.enqueue(b, TEST_SYSTEM, {"review": true})
	await _until_held(1)
	_client_for(b).resolve(b, _result("Review Game"))
	await _frames(4)
	_check(done.size() == 2 and done[1][2] == false and done[1][1] == "Review Game",
		"a review item hands its result back unaccepted")
	fresh = GamelistManager.new()
	_check(fresh.get_game_for_rom(TEST_SYSTEM, b).is_empty(), "a review result is not written")
	_check(ScrapeQueue.needs_scrape(fresh, TEST_SYSTEM, b), "needs_scrape stays true for it")
	_check(ScrapeQueue.needs_scrape(null, TEST_SYSTEM, b), "needs_scrape with no gamelist says yes")

	# "Scrape all" over a page holding a scraped game, an unscraped one, a
	# blank row and one already waiting: only the unscraped one is taken.
	var c := _rom("r_waiting.bin")
	q.enqueue(c, TEST_SYSTEM)
	var pick := q.select_unscraped(TEST_SYSTEM, [a, b, "", c])
	_check(pick["paths"] == [b] and pick["skipped"] == 1,
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
	_check(failures.size() == 1 and failures[0][0] == missing, "a file that cannot be hashed fails")
	_check(drained.size() == 4 and drained.back() == [0, 1], "drained reports the failure")
	q.free()


# ── scraped ───────────────────────────────────────────────────────────────────

func _group_scraped() -> void:
	var q := _queue(false)
	var rom := _rom("s_romm.bin")
	var download := {"game_id": "romm:41", "name": "Server Name", "desc": ""}
	_gamelist.add_or_merge_rom(TEST_SYSTEM, download.duplicate(),
		{"path": "./s_romm.bin", "romname": "s_romm.bin"})
	_check(ScrapeQueue.needs_scrape(_gamelist, TEST_SYSTEM, rom),
		"a game only the RomM downloader has named still needs a scrape")

	q.enqueue(rom, TEST_SYSTEM)
	await _until_held(1)
	_client_for(rom).resolve(rom, _result("Scraped Name"))
	await _frames(4)
	var fresh := GamelistManager.new()
	var game := fresh.get_game_for_rom(TEST_SYSTEM, rom)
	_check(str(game.get("game_id", "")) == "romm:41" and bool(game.get("scraped", false)),
		"a scrape over a RomM entry keeps the RomM id and flags it scraped")
	_check(not ScrapeQueue.needs_scrape(fresh, TEST_SYSTEM, rom),
		"a scraped RomM entry needs no scrape though the answer had no description")
	fresh.add_or_merge_rom(TEST_SYSTEM, download.duplicate(),
		{"path": "./s_romm.bin", "romname": "s_romm.bin"})
	_check(ScrapeQueue.is_scraped(fresh.get_game_for_rom(TEST_SYSTEM, rom)),
		"downloading it again leaves it scraped")

	_check(ScrapeQueue.is_scraped({"game_id": "5405", "name": "Banjo-Kazooie"}),
		"an unflagged entry with a ScreenScraper id counts as scraped")
	_check(ScrapeQueue.is_scraped({"game_id": "romm:79835", "name": "Rayman 2",
		"desc": "Enter a massive 3-D action adventure."}),
		"an unflagged RomM entry with a description counts as scraped")
	_check(not ScrapeQueue.is_scraped({"game_id": "9", "name": ""}), "an unnamed entry is not scraped")
	_check(not ScrapeQueue.is_scraped({}), "no entry is not scraped")

	var split := _rom("s_split.bin")
	var gl := GamelistManager.new()
	var games: Array = gl.load_gamelist(TEST_SYSTEM)["games"]
	games.append({"game_id": "romm:88", "name": "Split", "desc": "",
		"roms": [{"path": "./s_split.bin", "romname": "s_split.bin"}]})
	games.append({"game_id": "88", "name": "Split", "desc": "", "scraped": true,
		"roms": [{"path": "./s_split.bin", "romname": "s_split.bin"}]})
	gl.dedupe(TEST_SYSTEM)
	var folded := gl.get_game_for_rom(TEST_SYSTEM, split)
	_check(str(folded.get("game_id", "")) == "romm:88" and bool(folded.get("scraped", false)),
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
	_check(str(adopted.get("game_id", "")) == "romm:42" and ScrapeQueue.is_scraped(adopted),
		"a game scraped before RomM downloads it stays scraped under the RomM id")

	var twice := _rom("s_twice.bin")
	var pick := q.select_unscraped(TEST_SYSTEM, [rom, rom, twice, twice])
	_check(pick["paths"] == [twice] and pick["skipped"] == 1,
		"select_unscraped takes or skips a path several rows share once")

	var symbols: Font = load(MenuIcons.FONT_PATH)
	_check(symbols != null and symbols.has_char(MenuIcons.RESCRAPE),
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
	_check(q.active_count() == 1 and not c.holds(b), "the worker waits for its art before the next game")
	c.finish_media("wheel", "/w.png")
	await _frames(2)
	_check(c.held.is_empty(), "one of two transfers landing is not enough")
	c.finish_media("label", "/l.png")
	await _until_held(1)
	_check(c.holds(b), "the next game starts once every transfer has landed")
	_check(media.size() == 2 and media[0][0] == a and media[0][2] == "wheel"
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
	_check(failures.size() == 3, "a quota refusal fails the running item and everything waiting")
	_check(failures[1][1] == "Daily scrape quota exceeded" and failures[2][0] == roms[2],
		"the dropped items carry the quota as their reason")
	_check(stops == ["Daily scrape quota exceeded"], "stopped emitted once")
	_check(drained == [[0, 3]], "drained counts the three failures")
	_check(not q.is_busy(), "queue is idle after a quota stop")

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
	_check(stops2.size() == 1 and q2.waiting_count() == 0,
		"an account already at its daily limit drops what waits")
	_check(q2.active_count() == 1, "what was already running is left to finish")
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
	_check(not auto.is_enabled(), "switch off: auto-scraping is off")
	auto.request(a, TEST_SYSTEM)
	_check(not q.is_queued(a), "a request while off queues nothing")

	_config.auto_scrape = true
	_check(auto.is_enabled(), "switch on with no credentials: it runs anonymously")
	auto.request("", TEST_SYSTEM)
	auto.request(a, "")
	auto.request(RomLibrary.rom_dir_for_system(TEST_SYSTEM).path_join("ghost.bin"), TEST_SYSTEM)
	_check(not q.is_busy(), "empty args and a missing file queue nothing")

	# A ROM the gamelist already names is left alone.
	_gamelist.add_or_merge_rom(TEST_SYSTEM, {"game_id": "9", "name": "Known"},
		{"path": "./auto_known.bin", "romname": "auto_known.bin"})
	var known := _rom("auto_known.bin")
	_check(auto.already_scraped(known, TEST_SYSTEM), "already_scraped reads the gamelist")
	auto.request(known, TEST_SYSTEM)
	_check(not q.is_queued(known), "a scraped ROM is not requested again")

	var scraped: Array = []
	auto.scraped.connect(func(rom: String, _sid: String) -> void: scraped.append(rom))
	auto.request(a, TEST_SYSTEM)
	_check(q.is_queued(a) and q.active_count(ScrapeQueue.TAG_AUTO) + q.waiting_count(ScrapeQueue.TAG_AUTO) == 1,
		"a request is queued under the auto tag")
	_check(auto.queued_count() == 1, "queued_count counts it")
	auto.request(a, TEST_SYSTEM)
	_check(auto.queued_count() == 1, "a second request for the same ROM is not a second item")

	await _until_held(1)
	_client_for(a).resolve(a, _result("Auto Game"))
	await _frames(4)
	_check(scraped == [a], "scraped fires for an accepted result")
	_check(not ScrapeQueue.needs_scrape(GamelistManager.new(), TEST_SYSTEM, a),
		"the auto result is on disk")

	# The gate's own bound: 64 waiting, however many are asked for.
	var held_one := _rom("auto_hold.bin")
	auto.request(held_one, TEST_SYSTEM)
	await _until_held(1)
	for i in range(AutoScraper.MAX_QUEUE + 10):
		auto.request(_rom("auto_bulk_%d.bin" % i), TEST_SYSTEM)
	_check(q.waiting_count(ScrapeQueue.TAG_AUTO) == AutoScraper.MAX_QUEUE,
		"auto requests stop at MAX_QUEUE waiting")
	var manual := _rom("auto_manual.bin")
	_check(q.enqueue(manual, TEST_SYSTEM), "the auto bound does not block a manual item")
	auto.cancel_all()
	_check(q.waiting_count(ScrapeQueue.TAG_AUTO) == 0 and q.waiting_count(ScrapeQueue.TAG_MANUAL) == 1,
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
	_check(c.approve_scrapes == false, "approve_scrapes defaults off")
	c.approve_scrapes = true
	_check(c.save_config(), "config saves")
	var again := ScraperConfig.new()
	again.load_config()
	_check(again.approve_scrapes == true, "approve_scrapes round-trips")

	if had:
		var f := FileAccess.open(path, FileAccess.WRITE)
		f.store_buffer(snapshot)
		f.close()
	else:
		DirAccess.remove_absolute(path)
	var restored := ScraperConfig.new()
	restored.load_config()
	_check(restored.approve_scrapes == false or had, "player's config restored")
