## kavita_tests — KavitaConfig's OPDS URL reading and KavitaClient's sign-in,
## against a scripted local server (no Kavita, no network).
##
##   opds/     an OPDS URL is cut into server + Auth Key; anything else is not one
##   config/   normalising, the header, a save/load round trip (the real file is
##             snapshotted and restored byte for byte)
##   client/   x-api-key on every call; a 401 falls back to /api/Plugin/authenticate
##             ONCE and its token is used after; a redirect is never followed
##   comic/    a CBR from Kavita is saved as a CBZ of its page images, in order
##   browser/  which chapters get a row, what they are named, what they save as
##   profile/  which way a book reads: series profile, library profile, default, Manga
##   cache/    the download budget removes the least recently used, never a kept one
##   stream/   a kavita://chapter/<id> book opens off the server with nothing downloaded
extends "res://Tests/test_suite.gd"


func _ready() -> void:
	suite_tag = "kavita"
	_opds()
	_config()
	await _client()
	await _comic()
	_browser()
	_profiles()
	_cache()
	await _stream()
	_finish()


func _opds() -> void:
	var p := KavitaConfig.parse_opds_url("https://kavita.example.com/api/opds/abc123")
	_eq(p.get("base_url"), "https://kavita.example.com", "opds/ server from a plain OPDS URL")
	_eq(p.get("auth_key"), "abc123", "opds/ key from a plain OPDS URL")
	p = KavitaConfig.parse_opds_url("  http://10.0.0.5:5000/kavita/api/opds/K3y-9/  ")
	_eq(p.get("base_url"), "http://10.0.0.5:5000/kavita", "opds/ a sub-path stays part of the server")
	_eq(p.get("auth_key"), "K3y-9", "opds/ trailing slash and spaces are not the key")
	p = KavitaConfig.parse_opds_url("https://h/api/opds/key/libraries?x=1")
	_eq(p.get("auth_key"), "key", "opds/ a deeper OPDS path still gives the key alone")
	p = KavitaConfig.parse_opds_url("kavita.lan/api/opds/zz")
	_eq(p.get("base_url"), "https://kavita.lan", "opds/ a bare host gets https, as RomM's")
	_ok(KavitaConfig.parse_opds_url("https://kavita.example.com").is_empty(), "opds/ a server URL is not an OPDS URL")
	_ok(KavitaConfig.parse_opds_url("https://h/api/opds/").is_empty(), "opds/ no key, no OPDS URL")
	_ok(KavitaConfig.parse_opds_url("abc123").is_empty(), "opds/ a bare key is not an OPDS URL")
	var cfg := KavitaConfig.new()
	_ok(not cfg.apply_opds_url("https://h"), "opds/ apply refuses a non-OPDS URL")
	_ok(cfg.base_url.is_empty() and cfg.auth_key.is_empty(), "opds/ and leaves the fields alone")
	_ok(cfg.apply_opds_url("https://h/api/opds/kk"), "opds/ apply takes an OPDS URL")
	_ok(cfg.base_url == "https://h" and cfg.auth_key == "kk", "opds/ and fills both fields")


func _config() -> void:
	_eq(KavitaConfig.normalize_url("kavita.lan/"), "https://kavita.lan", "config/ bare host normalised")
	_eq(KavitaConfig.normalize_url("https://h/api/opds/k"), "https://h", "config/ an OPDS URL in the URL field is cut back to the server")
	var cfg := KavitaConfig.new()
	_eq(cfg.auth_headers(), PackedStringArray(), "config/ no key, no header")
	cfg.auth_key = "abc"
	_eq(cfg.auth_headers(), PackedStringArray(["x-api-key: abc"]), "config/ the key goes in x-api-key")
	cfg.base_url = "https://h"
	_ok(not cfg.is_configured(), "config/ not configured while switched off")
	cfg.enabled = true
	_ok(cfg.is_configured(), "config/ configured with server, key and the switch")
	cfg.base_url = "http://h"
	_ok(not cfg.is_encrypted(), "config/ http is flagged as unencrypted")

	var path := KavitaConfig.config_path()
	var saved: Variant = _snapshot_file(path)
	cfg.save_config()
	var back := KavitaConfig.new()
	back.load_config()
	_ok(back.base_url == "http://h" and back.auth_key == "abc" and back.enabled, "config/ save/load round trip")
	var text := FileAccess.get_file_as_string(path)
	_ok(not text.contains("password"), "config/ no password is written")
	_restore_file(path, saved)


func _client() -> void:
	var cfg := KavitaConfig.new()
	cfg.enabled = true
	cfg.auth_key = "KEY1"

	# 0.8.9: the header is enough.
	var srv := MultiServer.new()
	_ok(srv.start(func(head: String) -> String:
		if head.contains("x-api-key: KEY1"):
			return _reply(200, '[{"id":1,"name":"Books"},{"id":2,"name":"Comics"}]')
		return _reply(401, "")), "client/ fake server listens")
	cfg.base_url = "http://127.0.0.1:%d" % srv.port
	var res: Dictionary = await KavitaClient.test_connection(self, cfg)
	srv.stop()
	_ok(res.ok, "client/ x-api-key accepted", str(res))
	_eq(str(res.summary), "Kavita connected: 2 libraries", "client/ the test names what the key can see")
	_eq(srv.heads.size(), 1, "client/ one request, no key exchange")

	# An older server: 401 on the header, a JWT from Plugin/authenticate, then Bearer.
	srv = MultiServer.new()
	srv.start(func(head: String) -> String:
		if head.begins_with("POST /api/Plugin/authenticate?apiKey=KEY2&pluginName=RetroXR "):
			return _reply(200, '{"token":"JWT9"}')
		if head.contains("Authorization: Bearer JWT9"):
			return _reply(200, "[]")
		return _reply(401, ""))
	cfg.base_url = "http://127.0.0.1:%d" % srv.port
	cfg.auth_key = "KEY2"
	res = await KavitaClient.request_json(self, cfg, "/api/Library/libraries")
	_ok(res.ok, "client/ a 401 falls back to the key exchange", str(res))
	var again: Dictionary = await KavitaClient.request_json(self, cfg, "/api/Library/libraries")
	srv.stop()
	_ok(again.ok, "client/ the exchanged token is used after")
	_eq(srv.heads.size(), 4, "client/ header, exchange, retry, then the token straight away")
	_ok(not srv.heads[3].contains("x-api-key"), "client/ the token replaces the header")

	# A bad key: one exchange, refused, then no more exchanges.
	srv = MultiServer.new()
	srv.start(func(_head: String) -> String: return _reply(401, ""))
	cfg.base_url = "http://127.0.0.1:%d" % srv.port
	cfg.auth_key = "BAD"
	res = await KavitaClient.request_json(self, cfg, "/api/Library/libraries")
	again = await KavitaClient.request_json(self, cfg, "/api/Library/libraries")
	srv.stop()
	_ok(not res.ok and int(res.code) == 401, "client/ a refused key reports 401")
	_ok(KavitaClient.describe_error(res).contains("Auth Key"), "client/ and says it is the key")
	_eq(srv.heads.size(), 3, "client/ a refused key is exchanged once, not on every call")

	# A redirect is not followed, so the key never goes to another host.
	srv = MultiServer.new()
	srv.start(func(_head: String) -> String:
		return "HTTP/1.1 302 Found\r\nLocation: http://127.0.0.1:1/elsewhere\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
	cfg.base_url = "http://127.0.0.1:%d" % srv.port
	cfg.auth_key = "KEY3"
	res = await KavitaClient.request_json(self, cfg, "/api/Library/libraries")
	srv.stop()
	_ok(not res.ok and int(res.code) == 302, "client/ a redirect is refused, not followed", str(res))

	# Download lands in place, and a failed one leaves no file behind.
	srv = MultiServer.new()
	srv.start(func(head: String) -> String:
		return _reply(200, "EPUBDATA") if head.contains("chapterId=7 ") else _reply(403, ""))
	cfg.base_url = "http://127.0.0.1:%d" % srv.port
	cfg.auth_key = "KEY4"
	var out := "user://__kavita_test_download.epub"
	DirAccess.remove_absolute(out)
	res = await KavitaClient.download(self, cfg, "/api/Download/chapter?chapterId=7", out)
	_ok(res.ok and FileAccess.get_file_as_string(out) == "EPUBDATA", "client/ a download lands at its path", str(res))
	DirAccess.remove_absolute(out)
	res = await KavitaClient.download(self, cfg, "/api/Download/chapter?chapterId=8", out)
	srv.stop()
	_ok(not res.ok and not FileAccess.file_exists(out) and not FileAccess.file_exists(out + ".part"),
		"client/ a refused download leaves no file or .part")


func _comic() -> void:
	var png := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	png.fill(Color.BLUE)
	var png_bytes := png.save_png_to_buffer()
	var jpg_bytes := png.save_jpg_to_buffer()
	_eq(KavitaClient.image_extension(png_bytes), "png", "comic/ a PNG is known by its bytes")
	_eq(KavitaClient.image_extension(jpg_bytes), "jpg", "comic/ a JPEG is known by its bytes")
	_eq(KavitaClient.image_extension("not an image at all".to_utf8_buffer()), "", "comic/ text is no image")

	var cfg := KavitaConfig.new()
	cfg.enabled = true
	cfg.auth_key = "CK"
	var srv := MultiServer.new()
	srv.start(func(head: String) -> String:
		if head.contains("chapterId=5&page=0&") and head.contains("apiKey=CK"):
			return _reply_bytes(200, png_bytes)
		if head.contains("chapterId=5&page=1&") and head.contains("apiKey=CK"):
			return _reply_bytes(200, jpg_bytes)
		return _reply(404, ""))
	cfg.base_url = "http://127.0.0.1:%d" % srv.port
	var out := "user://__kavita_test_comic.cbz"
	DirAccess.remove_absolute(out)
	var seen: Array = []
	var res: Dictionary = await KavitaClient.fetch_comic_as_cbz(self, cfg, 5, 2, out,
		func(done: int, total: int) -> void: seen.append([done, total]))
	_ok(res.ok, "comic/ two pages fetched", str(res))
	var zip := ZIPReader.new()
	_ok(zip.open(out) == OK, "comic/ the result is a ZIP")
	_eq(zip.get_files(), PackedStringArray(["0001.png", "0002.jpg"]), "comic/ pages in order, named by their own format")
	_eq(zip.read_file("0001.png"), png_bytes, "comic/ a page's bytes as served")
	zip.close()
	_eq(seen, [[1, 2], [2, 2]], "comic/ progress after each page")
	DirAccess.remove_absolute(out)
	# A missing page fails the whole book, and leaves nothing behind.
	res = await KavitaClient.fetch_comic_as_cbz(self, cfg, 5, 3, out)
	srv.stop()
	_ok(not res.ok and not FileAccess.file_exists(out) and not FileAccess.file_exists(out + ".part")
		and not FileAccess.file_exists(out + ".page"), "comic/ a page that fails leaves no file")


func _browser() -> void:
	var b := KavitaBrowser.new()
	b._identity = "https://h|K"
	b._series = {"name": "Saga"}
	var vol := {"name": "-100000"}
	var cbr := b._book_of(vol, {"id": 9, "pages": 30, "range": "3", "files": [{"extension": ".cbr", "bytes": 5000}]})
	_ok(bool(cbr.get("comic", false)), "browser/ a CBR is a comic to fetch page by page")
	_ok(str(cbr.get("path", "")).ends_with(".cbz"), "browser/ and saves as a CBZ")
	_eq(cbr.get("name"), "Chapter 3", "browser/ Kavita's loose volume number is left out of the name")
	var epub := b._book_of({"name": "2"}, {"id": 4, "titleName": "The Return", "files": [{"extension": "epub", "bytes": 1}]})
	_ok(not bool(epub.get("comic", true)) and str(epub.get("path", "")).ends_with(".epub"), "browser/ an EPUB downloads as itself")
	_eq(epub.get("name"), "The Return", "browser/ a chapter's own title wins")
	_eq(b._book_of({"name": "1"}, {"id": 2, "files": [{"extension": "mobi", "bytes": 1}]}), {}, "browser/ a format the reader cannot open gets no row")
	var two := b._book_of({"name": "1"}, {"id": 3, "files": [{"extension": "pdf"}, {"extension": "pdf"}]})
	_eq(two, {}, "browser/ a PDF chapter of two files gets no row")
	_eq(b._book_of({"name": "1"}, {"id": 3, "files": []}), {}, "browser/ a chapter with no file gets no row")
	# A comic trade as Kavita lists it (Batgirl v01): one stand-in chapter whose
	# title and number are -100000.
	var trade := b._book_of({"name": "1"}, {"id": 100, "title": "-100000", "titleName": "", "range": "-100000",
		"number": "-100000", "files": [{"extension": ".cbr", "bytes": 1}]})
	_eq(trade.get("name"), "Volume 1", "browser/ a volume-only book is named by its volume, not -100000")
	var special := b._book_of({"name": "100000"}, {"id": 101, "title": "Annual", "files": [{"extension": "cbz"}]})
	_eq(special.get("name"), "Annual", "browser/ a real title still wins")
	b._library = {"name": "Manga", "type": KavitaBrowser.LIBRARY_MANGA}
	_ok(bool(b._book_of(vol, {"id": 11, "files": [{"extension": "cbz"}]}).get("right_to_left")),
		"browser/ a book from a Manga library reads right to left")
	b._library = {"name": "Comics", "type": 1}
	_ok(not bool(b._book_of(vol, {"id": 12, "files": [{"extension": "cbz"}]}).get("right_to_left", true)),
		"browser/ a book from a Comic library reads left to right")
	b.free()


func _profiles() -> void:
	var b := KavitaBrowser.new()
	var manga := {"id": 4, "type": KavitaBrowser.LIBRARY_MANGA}
	var comics := {"id": 2, "type": 1}
	_ok(b._right_to_left_for(10, manga), "profile/ no profiles: a Manga library reads right to left")
	_ok(not b._right_to_left_for(10, comics), "profile/ no profiles: a Comic library reads left to right")
	b._profiles = [{"kind": 0, "readingDirection": 0, "seriesIds": [], "libraryIds": []},
		{"kind": 1, "readingDirection": 1, "seriesIds": [58.0], "libraryIds": []},
		{"kind": 1, "readingDirection": 0, "seriesIds": [], "libraryIds": [4.0]}]
	_ok(b._right_to_left_for(58, comics), "profile/ a series profile set right to left wins")
	_ok(not b._right_to_left_for(10, manga), "profile/ a library profile set left to right beats the Manga type")
	_ok(not b._right_to_left_for(11, comics), "profile/ the default profile left to right leaves a Comic library alone")
	b._profiles = [{"kind": 0, "readingDirection": 1, "seriesIds": [], "libraryIds": []}]
	_ok(b._right_to_left_for(11, comics), "profile/ a default profile set right to left reads everything that way")
	b.free()


func _cache() -> void:
	var dir := "user://__kavita_cache_test"
	DirAccess.make_dir_recursive_absolute(dir)
	for f: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	var write := func(name: String, kb: int) -> String:
		var path := dir.path_join(name)
		var fa := FileAccess.open(path, FileAccess.WRITE)
		var bytes := PackedByteArray()
		bytes.resize(kb * 1024)
		fa.store_buffer(bytes)
		fa.close()
		return path
	var old: String = write.call("1-old.cbz", 400)
	var mid: String = write.call("2-mid.epub", 400)
	var open_book: String = write.call("3-open.pdf", 400)
	var fresh: String = write.call("4-new.cbz", 400)
	write.call("5-partial.cbz.part", 900)
	JsonStore.write_dict(dir.path_join(KavitaCache.USED_FILE), {"1-old.cbz": 100.0, "2-mid.epub": 200.0,
		"3-open.pdf": 50.0, "4-new.cbz": 300.0})
	# 1600 KB of books under a 900 KB budget: the open one and the new one are kept.
	var removed := KavitaCache.evict(dir, 900 * 1024, PackedStringArray([open_book, fresh]))
	_eq(removed, 2, "cache/ two books go to fit the budget")
	_ok(not FileAccess.file_exists(old) and not FileAccess.file_exists(mid), "cache/ the least recently used go first")
	_ok(FileAccess.file_exists(open_book), "cache/ a book open in the room is never removed, however old")
	_ok(FileAccess.file_exists(fresh), "cache/ the book just fetched is kept")
	_ok(FileAccess.file_exists(dir.path_join("5-partial.cbz.part")), "cache/ a partial download is not a book")
	KavitaCache.touch(open_book)
	var used := JsonStore.read_dict(dir.path_join(KavitaCache.USED_FILE))
	_ok(float(used.get("3-open.pdf", 0.0)) > 300.0 and not used.has("1-old.cbz"), "cache/ opening a book marks it used; removed ones leave the record")
	for f: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func _stream() -> void:
	_eq(KavitaPages.chapter_of(KavitaPages.path_for(42)), 42, "stream/ a chapter id round trips through its path")
	_ok(not KavitaPages.is_remote("C:/books/a.cbz"), "stream/ a file is not a stream")
	var red := Image.create(20, 30, false, Image.FORMAT_RGBA8)
	red.fill(Color.RED)
	var blue := Image.create(20, 30, false, Image.FORMAT_RGBA8)
	blue.fill(Color.BLUE)
	var pages := [red.save_png_to_buffer(), blue.save_png_to_buffer()]
	var srv := MultiServer.new()
	srv.start(func(head: String) -> String:
		if head.contains("/api/Reader/chapter-info?chapterId=7 "):
			return _reply(200, '{"pages": 2, "fileName": "Batgirl v01.cbr"}')
		if head.contains("/api/Reader/file-dimensions?chapterId=7&"):
			return _reply(200, '[{"width": 400, "height": 600, "pageNumber": 0}]')
		for i in 2:
			if head.contains("/api/Reader/image?chapterId=7&page=%d&" % i):
				return _reply_bytes(200, pages[i])
		return _reply(404, ""))
	# The book reads the real config, which is put back byte for byte after.
	var path := KavitaConfig.config_path()
	var saved: Variant = _snapshot_file(path)
	var cfg := KavitaConfig.new()
	cfg.enabled = true
	cfg.base_url = "http://127.0.0.1:%d" % srv.port
	cfg.auth_key = "SK"
	cfg.save_config()
	var book := (load("res://Scenes/Objects/media/pdf_book.tscn") as PackedScene).instantiate() as PDFBook
	book.freeze = true
	book.pdf_path = KavitaPages.path_for(7)
	add_child(book)
	var ok := await _wait_until(func() -> bool: return book._page_count > 0, 8.0)
	_ok(ok and book._page_count == 2, "stream/ the book opens with Kavita's page count", "pages %d" % book._page_count)
	_ok(absf(book._page_width / book._page_height - 400.0 / 600.0) < 1e-3, "stream/ and the first page's shape")
	book._get_page_texture(1)
	var landed := await _wait_until(func() -> bool:
		var t := book._texture_cache.get(1) as ImageTexture
		return t != null, 8.0)
	_ok(landed and (book._texture_cache[1] as ImageTexture).get_image().get_pixel(1, 1).is_equal_approx(Color.BLUE),
		"stream/ a page is fetched, decoded and shown")
	var cached := FileAccess.file_exists(book._cache_dir + "page_001.png") or FileAccess.file_exists(book._cache_dir + "page_001.etc2")
	_ok(cached, "stream/ and kept in the page cache for next time")
	var cache_dir := book._cache_dir
	book.queue_free()
	srv.stop()
	_restore_file(path, saved)
	for f: String in DirAccess.get_files_at(cache_dir):
		DirAccess.remove_absolute(cache_dir.path_join(f))
	DirAccess.remove_absolute(cache_dir)


static func _reply_bytes(code: int, body: PackedByteArray) -> String:
	# Raw bytes as a Latin-1 string, so _serve's to_utf8_buffer() is not used for these.
	return "BYTES:%d:%s" % [code, Marshalls.raw_to_base64(body)]


static func _reply(code: int, body: String) -> String:
	var text: String = {200: "OK", 401: "Unauthorized", 403: "Forbidden"}.get(code, "X")
	return "HTTP/1.1 %d %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" % [
		code, text, body.to_utf8_buffer().size(), body]


## Answers every connection from `answer(request_head) -> raw reply`, one request
## per connection, on its own thread. `heads` holds each request's head, in order;
## read it after stop().
class MultiServer extends RefCounted:
	var port := 0
	var heads: Array[String] = []
	var _server := TCPServer.new()
	var _thread := Thread.new()
	var _stop := false

	func start(answer: Callable) -> bool:
		for p in range(49600, 49660):
			if _server.listen(p, "127.0.0.1") == OK:
				port = p
				break
		if port == 0:
			return false
		_thread.start(_serve.bind(answer))
		return true

	func stop() -> void:
		_stop = true
		if _thread.is_started():
			_thread.wait_to_finish()
		_server.stop()

	func _serve(answer: Callable) -> void:
		while not _stop:
			if not _server.is_connection_available():
				OS.delay_msec(5)
				continue
			var peer := _server.take_connection()
			var got := PackedByteArray()
			var give_up := Time.get_ticks_msec() + 3000
			while Time.get_ticks_msec() < give_up and not _stop:
				peer.poll()
				var n := peer.get_available_bytes()
				if n > 0:
					got.append_array(peer.get_data(n)[1])
					if got.get_string_from_utf8().contains("\r\n\r\n"):
						break
				else:
					OS.delay_msec(2)
			var head := got.get_string_from_utf8().get_slice("\r\n\r\n", 0)
			heads.append(head)
			var reply := answer.call(head) as String
			if reply.begins_with("BYTES:"):
				var body := Marshalls.base64_to_raw(reply.get_slice(":", 2))
				var code := int(reply.get_slice(":", 1))
				peer.put_data(("HTTP/1.1 %d OK\r\nContent-Type: image/png\r\nContent-Length: %d\r\nConnection: close\r\n\r\n"
					% [code, body.size()]).to_utf8_buffer())
				peer.put_data(body)
			else:
				peer.put_data(reply.to_utf8_buffer())
			OS.delay_msec(20)
			peer.disconnect_from_host()
