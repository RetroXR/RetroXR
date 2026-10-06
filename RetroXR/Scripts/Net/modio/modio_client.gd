## ModioClient — the mod.io catalogue for this game, read-only.
##
## mod.io hosts the mods; this asks it what there is. Everything here is a GET
## with the game's API key, which is all a key may do: mod.io's own words are
## that it is "limited to read-only GET requests, due to the limited security it
## offers", sent in the query string by the game client. Nothing a player owns is
## behind it, so it is a constant rather than a secret — rotating it is one line.
##
## No login, and so no subscribing, rating or commenting: those need an OAuth
## token and are not built.
##
## Nothing but the terms themselves is asked for until the player has agreed to
## them (ModioConsent). The gate is HERE, in the one function every request goes
## through, so a page that forgets to ask cannot send one.
##
## HTTPRequest rather than RommHttp: a catalogue page is tens of kilobytes, not
## the megabytes a RomM page is, and HTTPRequest follows mod.io's redirects and
## speaks gzip without being asked.
class_name ModioClient
extends Node

const GAME_ID := 14432
const API_KEY := "5e898902a9362fd045ab31c6bf9df2ca"
## mod.io's per-game host. api.mod.io still answers, as the legacy form.
const BASE_URL := "https://g-14432.modapi.io/v1"
## The game's page, for the "browse on mod.io" link and the QR to it.
const PROFILE_URL := "https://mod.io/g/retroxr"

const PAGE_SIZE := 24
const REQUEST_TIMEOUT := 20.0
## A collection's members are asked for a page at a time, and no pack is allowed
## to turn into an unbounded run of requests.
const MEMBER_PAGE := 100
const MEMBER_PAGES_MAX := 5

## What a refused request says, so a page can tell "ask the player" from "broken".
const NEEDS_CONSENT := "Agree to mod.io's terms to browse mods"

## modfile.virus_status, as mod.io numbers it. Only a finished scan that found
## nothing is a file this game will fetch.
const VIRUS_SCANNED := 1

## What the sort dropdown offers: label, then mod.io's `_sort` value.
const SORTS := [
	["Most popular", "-downloads_total"],
	["Newest", "-date_live"],
	["Recently updated", "-date_updated"],
	["Top rated", "-ratings_weighted_aggregate"],
	["Name", "name"],
]

## What the pack sort dropdown offers. Collections have no rating to sort by.
const COLLECTION_SORTS := [
	["Most popular", "-downloads_total"],
	["Newest", "-date_live"],
	["Recently updated", "-date_updated"],
	["Name", "name"],
]

## Overridden by mod_browser_tests to point at a local server.
var base_url := BASE_URL
var api_key := API_KEY
var consent := ModioConsent.new()


## One page of the catalogue.
##   search  matched against the mod's name; "" for everything
##   sort    a `_sort` value from SORTS
## callback(ok: bool, mods: Array[Dictionary], total: int, error: String)
## Each mod is what parse_mod returns.
func list_mods(search: String, sort: String, offset: int, callback: Callable,
		tag: String = "") -> void:
	_fetch_json(list_path(search, sort, offset, PAGE_SIZE, api_key, tag),
		func(ok: bool, data: Variant, error: String) -> void:
			if not ok or not (data is Dictionary):
				callback.call(false, _no_rows(), 0, error if not error.is_empty() else "Unexpected reply from mod.io")
				return
			var mods: Array[Dictionary] = []
			var rows: Variant = (data as Dictionary).get("data", [])
			if rows is Array:
				for row: Variant in (rows as Array):
					if row is Dictionary:
						var mod := parse_mod(row)
						if int(mod["id"]) > 0:
							mods.append(mod)
			callback.call(true, mods, int((data as Dictionary).get("result_total", mods.size())), ""))


## One mod, asked for again just before a download: mod.io signs each download
## address and lets it expire, so the one in a listing fetched a while ago may
## already be dead.
## callback(ok: bool, mod: Dictionary, error: String)
func get_mod(mod_id: int, callback: Callable) -> void:
	_fetch_json("/games/%d/mods/%d?api_key=%s" % [GAME_ID, mod_id, api_key],
		func(ok: bool, data: Variant, error: String) -> void:
			if not ok or not (data is Dictionary):
				callback.call(false, {}, error if not error.is_empty() else "Unexpected reply from mod.io")
				return
			callback.call(true, parse_mod(data), ""))


## The request path for a page. Static so the suite can read it without a socket.
static func list_path(search: String, sort: String, offset: int, limit: int,
		key: String = API_KEY, tag: String = "") -> String:
	var path := _page_path("/games/%d/mods" % GAME_ID, search, sort, offset, limit, key)
	if not tag.is_empty():
		path += "&tags=" + tag.uri_encode()
	return path


static func _page_path(resource: String, search: String, sort: String, offset: int,
		limit: int, key: String) -> String:
	var path := "%s?api_key=%s&_limit=%d&_offset=%d" % [resource, key, limit, maxi(0, offset)]
	if not sort.is_empty():
		path += "&_sort=" + sort.uri_encode()
	var q := search.strip_edges()
	if not q.is_empty():
		path += "&_q=" + q.uri_encode()
	return path


## The tags a mod can be filed under, flattened out of mod.io's tag groups.
## callback(ok: bool, tags: PackedStringArray, error: String)
func list_tags(callback: Callable) -> void:
	_fetch_json("/games/%d/tags?api_key=%s" % [GAME_ID, api_key],
		func(ok: bool, data: Variant, error: String) -> void:
			if not ok or not (data is Dictionary):
				callback.call(false, PackedStringArray(), error)
				return
			callback.call(true, parse_tags((data as Dictionary).get("data")), ""))


static func parse_tags(groups: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if not (groups is Array):
		return out
	for group: Variant in (groups as Array):
		if not (group is Dictionary) or not ((group as Dictionary).get("tags") is Array):
			continue
		if (group as Dictionary).get("hidden") is bool and bool((group as Dictionary)["hidden"]):
			continue
		for tag: Variant in ((group as Dictionary)["tags"] as Array):
			if tag is String and not (tag as String).is_empty() and not out.has(tag):
				out.append(tag)
	return out


# ── terms ─────────────────────────────────────────────────────────────────────

## mod.io's own consent text, buttons and links: the one request allowed before
## the player has agreed, because it is what they are agreeing to.
## callback(ok: bool, terms: Dictionary, error: String) -- see parse_terms.
func get_terms(callback: Callable) -> void:
	_fetch_json("/authenticate/terms?api_key=%s" % api_key,
		func(ok: bool, data: Variant, error: String) -> void:
			if not ok or not (data is Dictionary):
				callback.call(false, {}, error if not error.is_empty() else "Unexpected reply from mod.io")
				return
			var terms := parse_terms(data)
			if str(terms["text"]).is_empty():
				callback.call(false, {}, "Unexpected reply from mod.io")
				return
			callback.call(true, terms, ""), false)


## {text, agree, disagree, links: Array of {text, url}}. The REQUIRED links come
## first; the wording of both buttons is mod.io's, with plain defaults.
static func parse_terms(d: Dictionary) -> Dictionary:
	var buttons := _dict(d.get("buttons"))
	var links: Array[Dictionary] = []
	var raw := _dict(d.get("links"))
	for required: bool in [true, false]:
		for key: Variant in raw:
			var link := _dict(raw[key])
			var url := str(link.get("url", ""))
			var is_required: bool = link.get("required") is bool and bool(link["required"])
			if is_required == required and url.begins_with("https://") \
					and not str(link.get("text", "")).is_empty():
				links.append({"text": str(link["text"]), "url": url})
	var agree := str(_dict(buttons.get("agree")).get("text", ""))
	var disagree := str(_dict(buttons.get("disagree")).get("text", ""))
	return {
		"text": str(d.get("plaintext", "")).strip_edges(),
		"agree": agree if not agree.is_empty() else "I Agree",
		"disagree": disagree if not disagree.is_empty() else "No, Thanks",
		"links": links,
	}


# ── collections ───────────────────────────────────────────────────────────────

## One page of this game's collections -- mod packs.
## callback(ok: bool, packs: Array[Dictionary], total: int, error: String)
func list_collections(search: String, sort: String, offset: int, callback: Callable) -> void:
	_fetch_json(collections_path(search, sort, offset, PAGE_SIZE, api_key),
		func(ok: bool, data: Variant, error: String) -> void:
			if not ok or not (data is Dictionary):
				callback.call(false, _no_rows(), 0, error if not error.is_empty() else "Unexpected reply from mod.io")
				return
			var packs: Array[Dictionary] = []
			var rows: Variant = (data as Dictionary).get("data", [])
			if rows is Array:
				for row: Variant in (rows as Array):
					if row is Dictionary:
						var pack := parse_collection(row)
						if int(pack["id"]) > 0:
							packs.append(pack)
			callback.call(true, packs, int((data as Dictionary).get("result_total", packs.size())), ""))


static func collections_path(search: String, sort: String, offset: int, limit: int,
		key: String = API_KEY) -> String:
	return _page_path("/games/%d/collections" % GAME_ID, search, sort, offset, limit, key)


## Every mod in a collection, asked for fresh: their download addresses expire
## like any other. Stops after MEMBER_PAGES_MAX pages; `total` is what mod.io
## says the pack holds, so a caller can tell when it was cut short.
## callback(ok: bool, mods: Array[Dictionary], total: int, error: String)
func list_collection_mods(collection_id: int, callback: Callable) -> void:
	var so_far: Array[Dictionary] = []
	_collect_members(collection_id, 0, so_far, callback)


func _collect_members(collection_id: int, page: int, so_far: Array[Dictionary],
		callback: Callable) -> void:
	_fetch_json(members_path(collection_id, page * MEMBER_PAGE, MEMBER_PAGE, api_key),
		func(ok: bool, data: Variant, error: String) -> void:
			if not ok or not (data is Dictionary):
				callback.call(false, _no_rows(), 0, error if not error.is_empty() else "Unexpected reply from mod.io")
				return
			var rows: Variant = (data as Dictionary).get("data", [])
			var got := 0
			if rows is Array:
				got = (rows as Array).size()
				for row: Variant in (rows as Array):
					if row is Dictionary:
						var mod := parse_mod(row)
						if int(mod["id"]) > 0:
							so_far.append(mod)
			var total := int((data as Dictionary).get("result_total", so_far.size()))
			if got < MEMBER_PAGE or (page + 1) * MEMBER_PAGE >= total or page + 1 >= MEMBER_PAGES_MAX:
				callback.call(true, so_far, total, "")
			else:
				_collect_members(collection_id, page + 1, so_far, callback))


static func members_path(collection_id: int, offset: int, limit: int,
		key: String = API_KEY) -> String:
	return "/games/%d/collections/%d/mods?api_key=%s&_limit=%d&_offset=%d" % [
		GAME_ID, collection_id, key, limit, maxi(0, offset)]


## mod.io's Mod Collection object, reduced the way parse_mod reduces a mod.
static func parse_collection(d: Dictionary) -> Dictionary:
	var logo: Dictionary = _dict(d.get("logo"))
	var stats: Dictionary = _dict(d.get("stats"))
	var by: Dictionary = _dict(d.get("submitted_by"))
	return {
		"id": int(d.get("id", 0)),
		"name": str(d.get("name", "")),
		"summary": str(d.get("summary", "")),
		"author": str(by.get("username", "")),
		"profile_url": str(d.get("profile_url", "")),
		"logo_small": str(logo.get("thumb_320x180", "")),
		"logo_large": str(logo.get("thumb_640x360", "")),
		"file_size": int(d.get("filesize", 0)),
		"downloads": int(stats.get("downloads_total", 0)),
		"date_updated": int(d.get("date_updated", 0)),
		# mod.io's own flag for a pack with a member that is no longer available.
		"incomplete": int(d.get("incomplete", 0)) != 0,
	}


## mod.io's Mod object, reduced to what the browser shows and the downloader
## needs. Every field is present whatever the reply left out, so no caller has to
## guard: an absent number is 0, an absent string "".
##
## `file_id` is 0 for a mod with no file to download yet -- a page somebody has
## made and not uploaded to -- and the tile says so instead of offering one.
static func parse_mod(d: Dictionary) -> Dictionary:
	var logo: Dictionary = _dict(d.get("logo"))
	var file: Dictionary = _dict(d.get("modfile"))
	var hash: Dictionary = _dict(file.get("filehash"))
	var download: Dictionary = _dict(file.get("download"))
	var stats: Dictionary = _dict(d.get("stats"))
	var by: Dictionary = _dict(d.get("submitted_by"))
	var tags := PackedStringArray()
	if d.get("tags") is Array:
		for tag: Variant in (d["tags"] as Array):
			if tag is Dictionary and not str((tag as Dictionary).get("name", "")).is_empty():
				tags.append(str((tag as Dictionary)["name"]))
	return {
		"id": int(d.get("id", 0)),
		"name": str(d.get("name", "")),
		"summary": str(d.get("summary", "")),
		"author": str(by.get("username", "")),
		"profile_url": str(d.get("profile_url", "")),
		"logo_small": str(logo.get("thumb_320x180", "")),
		"logo_large": str(logo.get("thumb_640x360", "")),
		"tags": tags,
		"downloads": int(stats.get("downloads_total", 0)),
		"rating": str(stats.get("ratings_display_text", "")),
		"date_updated": int(d.get("date_updated", 0)),
		"file_id": int(file.get("id", 0)),
		"file_name": str(file.get("filename", "")),
		"file_size": int(file.get("filesize", 0)),
		"file_md5": str(hash.get("md5", "")).to_lower(),
		"file_version": str(file.get("version", "")),
		"download_url": str(download.get("binary_url", "")),
		"virus_status": int(file.get("virus_status", 0)),
		"virus_positive": int(file.get("virus_positive", 0)),
	}


## "" when mod.io's scan of this mod's file finished and found nothing, else the
## sentence a player is shown instead of a download. A file that was never
## scanned is refused with the rest: the scan is the one check this game cannot
## make for itself.
static func scan_problem(mod: Dictionary) -> String:
	if int(mod.get("virus_positive", 0)) != 0:
		return "mod.io's scan flagged this file"
	if int(mod.get("virus_status", 0)) != VIRUS_SCANNED:
		return "mod.io has not finished scanning this file"
	return ""


## What X-Modio-Platform says for this device, so mod.io returns the mods and
## files approved for it once the game turns per-platform files on. A Quest is
## "oculus"; whether a sideloaded build may claim that is an open question with
## mod.io, and "android" is the fallback.
static func platform_header(os_name: String = OS.get_name()) -> String:
	match os_name:
		"Windows": return "windows"
		"Linux":   return "linux"
		"macOS":   return "mac"
		"Android": return "oculus"
	return ""


## Where a player reports a mod. mod.io's game terms require that everything a
## game shows can be reported; this page takes a report without a login.
static func report_url(mod_id: int) -> String:
	return "https://mod.io/report/mods/%d/widget" % mod_id


## The empty page handed to a callback on failure. Typed: a callback declared
## to take Array[Dictionary] refuses a bare [] outright, and the error it came
## with is then never seen.
static func _no_rows() -> Array[Dictionary]:
	var none: Array[Dictionary] = []
	return none


static func _dict(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}


## One sentence a player can act on, for a failed catalogue request.
static func describe(result: int, code: int, retry_after: String = "") -> String:
	if result != HTTPRequest.RESULT_SUCCESS:
		if result == HTTPRequest.RESULT_TIMEOUT:
			return "mod.io took too long to answer"
		return "Cannot reach mod.io"
	if code == 429:
		var wait := int(retry_after) if retry_after.is_valid_int() else 0
		# mod.io sends 0 for a rolling limit, which means the minute has to pass.
		return "mod.io is busy — try again in %d s" % (wait if wait > 0 else 60)
	if code == 401 or code == 403:
		return "mod.io refused this copy of RetroXR (%d)" % code
	if code == 404:
		return "Not on mod.io any more"
	if code >= 500:
		return "mod.io is having trouble (%d)" % code
	return "mod.io refused the request (%d)" % code


## callback(ok: bool, parsed: Variant, error: String)
func _fetch_json(path: String, callback: Callable, needs_consent: bool = true) -> void:
	if needs_consent and not consent.granted():
		callback.call(false, null, NEEDS_CONSENT)
		return
	if not is_inside_tree():
		callback.call(false, null, "Cannot reach mod.io")
		return
	var http := HTTPRequest.new()
	http.use_threads = true
	http.timeout = REQUEST_TIMEOUT
	add_child(http)
	http.request_completed.connect(
		func(result: int, code: int, headers: PackedStringArray, raw: PackedByteArray) -> void:
			http.queue_free()
			if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
				var retry := ""
				for h: String in headers:
					if h.to_lower().begins_with("retry-after:"):
						retry = h.substr(12).strip_edges()
				callback.call(false, null, describe(result, code, retry))
				return
			var json := JSON.new()
			if json.parse(raw.get_string_from_utf8()) != OK:
				callback.call(false, null, "Unexpected reply from mod.io")
				return
			callback.call(true, json.data, ""))
	# Says who is asking, as the core downloader does for GitHub.
	var headers := PackedStringArray(["Accept: application/json", "User-Agent: RetroXR"])
	if not platform_header().is_empty():
		headers.append("X-Modio-Platform: " + platform_header())
	var err := http.request(base_url + path, headers)
	if err != OK:
		http.queue_free()
		callback.call(false, null, "Cannot reach mod.io")
