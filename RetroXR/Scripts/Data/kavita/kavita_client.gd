## KavitaClient — the one place that talks to a Kavita server.
##
## Every call sends the Auth Key as `x-api-key` (Kavita 0.8.9's way for a client).
## A server that refuses that header (an older Kavita, whose per-user API key is
## only exchanged for a JWT) gets one exchange through /api/Plugin/authenticate,
## and the token it returns is used from then on for that server and key.
##
## Redirects are never followed: a redirect to another host would carry the key
## with it.
class_name KavitaClient
extends RefCounted


const PLUGIN_NAME := "RetroXR"

## A JWT from /api/Plugin/authenticate, and the server + key it was issued for.
static var _bearer := ""
static var _bearer_for := ""


## {ok, code, error, data} for a JSON endpoint. `host` parents the HTTPRequest.
static func request_json(host: Node, cfg: KavitaConfig, endpoint: String,
		method: int = HTTPClient.METHOD_GET, body: Variant = null) -> Dictionary:
	return await _send(host, cfg, endpoint, method, body, "", 30.0)


## Download `endpoint` into `path` (via a .part file). {ok, code, error}.
## `on_progress(received: int, total: int)` is called once a frame while the body
## arrives; total is -1 when the server does not say.
static func download(host: Node, cfg: KavitaConfig, endpoint: String, path: String,
		on_progress: Callable = Callable()) -> Dictionary:
	var part := path + ".part"
	var res: Dictionary = await _send(host, cfg, endpoint, HTTPClient.METHOD_GET, null, part, 0.0, on_progress)
	if not res.ok:
		DirAccess.remove_absolute(part)
		return res
	if DirAccess.rename_absolute(part, path) != OK:
		DirAccess.remove_absolute(part)
		push_warning("[Kavita] could not move %s into place" % part)
		return {"ok": false, "code": 0, "error": "could not save the file", "data": null}
	return res


## A comic of any archive Kavita reads (CBR, CB7, CBT, CBZ) saved as a CBZ at
## `path`. Kavita serves each page as an image through /api/Reader/image, so a
## RAR or 7z never has to be opened here; the pages go into a plain ZIP the book
## reader already opens. `pages` is the chapter's page count (0: asked first).
## `on_progress(done: int, total: int)` after each page. {ok, code, error}.
static func fetch_comic_as_cbz(host: Node, cfg: KavitaConfig, chapter_id: int, pages: int,
		path: String, on_progress: Callable = Callable()) -> Dictionary:
	if pages <= 0:
		var info: Dictionary = await request_json(host, cfg, "/api/Reader/chapter-info?chapterId=%d" % chapter_id)
		if info.ok and info.data is Dictionary:
			pages = int((info.data as Dictionary).get("pages", 0))
	if pages <= 0:
		return {"ok": false, "code": 0, "error": "Kavita gave no page count", "data": null}
	var part := path + ".part"
	var page_tmp := path + ".page"
	var zip := ZIPPacker.new()
	if zip.open(part) != OK:
		return {"ok": false, "code": 0, "error": "could not write the file", "data": null}
	print("[Kavita] chapter %d: fetching %d pages into a CBZ" % [chapter_id, pages])
	var res: Dictionary = {"ok": true, "code": 200, "error": "", "data": null}
	for page in pages:
		# apiKey in the query as well as the header: Kavita's image endpoints read it there.
		res = await _send(host, cfg, "/api/Reader/image?chapterId=%d&page=%d&extractPdf=false&apiKey=%s"
			% [chapter_id, page, cfg.auth_key.uri_encode()], HTTPClient.METHOD_GET, null, page_tmp, 60.0)
		if not res.ok:
			break
		var bytes := FileAccess.get_file_as_bytes(page_tmp)
		var ext := image_extension(bytes)
		if ext.is_empty():
			res = {"ok": false, "code": 0, "error": "page %d is not an image" % (page + 1), "data": null}
			break
		zip.start_file("%04d.%s" % [page + 1, ext])
		zip.write_file(bytes)
		zip.close_file()
		if on_progress.is_valid():
			on_progress.call(page + 1, pages)
	zip.close()
	DirAccess.remove_absolute(page_tmp)
	if not res.ok:
		DirAccess.remove_absolute(part)
		return res
	if DirAccess.rename_absolute(part, path) != OK:
		DirAccess.remove_absolute(part)
		return {"ok": false, "code": 0, "error": "could not save the file", "data": null}
	print("[Kavita] chapter %d saved as %s" % [chapter_id, path])
	return res


## "png", "jpg" or "webp" from an image's first bytes, "" for anything else.
static func image_extension(bytes: PackedByteArray) -> String:
	if bytes.size() < 12:
		return ""
	if bytes[0] == 0x89 and bytes[1] == 0x50:
		return "png"
	if bytes[0] == 0xFF and bytes[1] == 0xD8:
		return "jpg"
	if bytes.slice(0, 4).get_string_from_ascii() == "RIFF" and bytes.slice(8, 12).get_string_from_ascii() == "WEBP":
		return "webp"
	return ""


## Ask the server whether this key works: its libraries, so a pass also says what
## the key can see. {ok: bool, summary: String}.
static func test_connection(host: Node, cfg: KavitaConfig) -> Dictionary:
	if cfg.base_url.is_empty() or cfg.auth_key.is_empty():
		return {"ok": false, "summary": "Enter a server URL and an Auth Key"}
	var res: Dictionary = await request_json(host, cfg, "/api/Library/libraries")
	if not res.ok:
		return {"ok": false, "summary": "Kavita: " + describe_error(res)}
	var count: int = (res.data as Array).size() if res.data is Array else 0
	return {"ok": true, "summary": "Kavita connected: %d librar%s" % [count, "y" if count == 1 else "ies"]}


## What to tell the player about a failed reply.
static func describe_error(res: Dictionary) -> String:
	var code := int(res.get("code", 0))
	if code == 401 or code == 403:
		return "the Auth Key was refused (HTTP %d)" % code
	if code >= 300 and code < 400:
		return "the server redirected (HTTP %d); check the URL and its scheme" % code
	return str(res.get("error", "no reply"))


static func _identity(cfg: KavitaConfig) -> String:
	return cfg.base_url + "\n" + cfg.auth_key


static func _headers(cfg: KavitaConfig) -> PackedStringArray:
	if not _bearer.is_empty() and _bearer_for == _identity(cfg):
		return PackedStringArray(["Authorization: Bearer " + _bearer])
	return cfg.auth_headers()


static func _send(host: Node, cfg: KavitaConfig, endpoint: String, method: int,
		body: Variant, download_to: String, timeout: float,
		on_progress: Callable = Callable()) -> Dictionary:
	if cfg.base_url.is_empty() or cfg.auth_key.is_empty():
		return {"ok": false, "code": 0, "error": "Kavita is not set up", "data": null}
	var res := await _raw(host, cfg.base_url + endpoint, _headers(cfg), method, body, download_to, timeout, on_progress)
	# Refused the header and no token tried yet: the older exchange, then once more.
	if int(res.code) == 401 and _bearer_for != _identity(cfg):
		print("[Kavita] %s refused x-api-key (401); trying /api/Plugin/authenticate" % endpoint)
		if await _exchange_key(host, cfg):
			res = await _raw(host, cfg.base_url + endpoint, _headers(cfg), method, body, download_to, timeout, on_progress)
	if not res.ok:
		push_warning("[Kavita] %s %s failed: %s (HTTP %d)" % [
			"POST" if method == HTTPClient.METHOD_POST else "GET", endpoint, res.error, int(res.code)])
	return res


## The pre-0.8.9 way: the key for a JWT. Remembers a refusal too, so a bad key
## is not exchanged again on every call.
static func _exchange_key(host: Node, cfg: KavitaConfig) -> bool:
	_bearer = ""
	_bearer_for = _identity(cfg)
	var url := "%s/api/Plugin/authenticate?apiKey=%s&pluginName=%s" % [
		cfg.base_url, cfg.auth_key.uri_encode(), PLUGIN_NAME]
	var res := await _raw(host, url, PackedStringArray(), HTTPClient.METHOD_POST, null, "", 30.0)
	if res.ok and res.data is Dictionary:
		_bearer = str((res.data as Dictionary).get("token", ""))
	print("[Kavita] key exchange %s (HTTP %d)" % ["gave a token" if not _bearer.is_empty() else "failed", int(res.code)])
	return not _bearer.is_empty()


static func _raw(host: Node, url: String, headers: PackedStringArray, method: int,
		body: Variant, download_to: String, timeout: float,
		on_progress: Callable = Callable()) -> Dictionary:
	if not is_instance_valid(host) or not host.is_inside_tree():
		return {"ok": false, "code": 0, "error": "menu closed", "data": null}
	var req := HTTPRequest.new()
	req.use_threads = true
	req.max_redirects = 0
	req.timeout = timeout
	if not download_to.is_empty():
		req.download_file = download_to
	host.add_child(req)
	var all := PackedStringArray(headers)
	if download_to.is_empty():
		all.append("Accept: application/json")
	var payload := ""
	if body != null:
		all.append("Content-Type: application/json")
		payload = JSON.stringify(body)
	var err := req.request(url, all, method, payload)
	if err != OK:
		req.queue_free()
		return {"ok": false, "code": 0, "error": "request failed (%s)" % error_string(err), "data": null}
	var result: Array = []
	if on_progress.is_valid():
		# Polled a frame at a time, so the caller can draw a bar while it runs.
		var box := {"done": false, "result": []}
		req.request_completed.connect(func(r: int, c: int, h: PackedStringArray, b: PackedByteArray) -> void:
			box.result = [r, c, h, b]
			box.done = true, CONNECT_ONE_SHOT)
		while not box.done and is_instance_valid(req) and req.is_inside_tree():
			on_progress.call(req.get_downloaded_bytes(), req.get_body_size())
			await req.get_tree().process_frame
		if not box.done:
			return {"ok": false, "code": 0, "error": "menu closed", "data": null}
		result = box.result
	else:
		result = await req.request_completed
	req.queue_free()
	var code := int(result[1])
	if int(result[0]) != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "code": code, "error": "no reply (result %d)" % int(result[0]), "data": null}
	if code < 200 or code >= 300:
		return {"ok": false, "code": code, "error": "HTTP %d" % code, "data": null}
	var data: Variant = null
	if download_to.is_empty():
		data = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())
	return {"ok": true, "code": code, "error": "", "data": data}
