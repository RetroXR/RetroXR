## M3uFetcher — fetches the IPTV playlists an aerial's lineup names.
##
## A child of TVLineup, as HDHomeRun is (it needs the tree for HTTPRequest). Give it
## TVChannels.playlist_sources() and it reads them one after another -- a file from
## the tv folder at once, a URL over HTTP -- and reports each through
## `playlist_ready` or `playlist_failed`, keyed by the source's `key`.
##
## The last good copy of every DOWNLOADED list is kept in user://tv_m3u_cache.json,
## so a cold start with the network down still has its channels (TVLineup shows the
## cache before the fetch answers). A file in the tv folder is read fresh each time
## and never cached: deleting it is how a player takes its channels away.
class_name M3uFetcher
extends Node

## One playlist read. `info`: {name, count, dropped_options, truncated, media}.
signal playlist_ready(key: String, channels: Array, info: Dictionary)
signal playlist_failed(key: String, message: String)
## Every source of the last fetch() has answered one way or the other.
signal fetch_finished

const CACHE_PATH := "user://tv_m3u_cache.json"
const HTTP_TIMEOUT := 15.0
## A whole-world iptv-org list is about 2 MB; this is far past any real one.
const BODY_LIMIT := 20 * 1024 * 1024

var _http: HTTPRequest = null
# Bumped by every fetch(), so a run overtaken by a Refresh stops reporting.
var _generation := 0
var _busy := false


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.name = "HTTP"
	_http.timeout = HTTP_TIMEOUT
	_http.body_size_limit = BODY_LIMIT
	_http.max_redirects = 4
	add_child(_http)


func is_busy() -> bool:
	return _busy


## Read every source in `sources` (TVChannels.playlist_sources()). A fetch already
## running is abandoned: its remaining sources are not reported.
func fetch(sources: Array[Dictionary]) -> void:
	_generation += 1
	var gen := _generation
	if _http and _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_http.cancel_request()
	if sources.is_empty():
		_busy = false
		fetch_finished.emit.call_deferred()
		return
	_busy = true
	print("[M3U] Fetching %d playlist(s)" % sources.size())
	for s: Dictionary in sources:
		if gen != _generation:
			return
		await _fetch_one(s, gen)
	if gen == _generation:
		_busy = false
		fetch_finished.emit()


func _fetch_one(s: Dictionary, gen: int) -> void:
	var key := str(s.get("key", s.get("location", "")))
	var loc := str(s.get("location", key))
	var name := str(s.get("name", loc.get_file()))
	var text := ""
	var remote := loc.begins_with("http://") or loc.begins_with("https://")
	if remote:
		var got: Variant = await _download(loc)
		if gen != _generation:
			return
		if got is String:
			# _download answers a String body, or a Dictionary {error}.
			text = got
		else:
			var msg := str((got as Dictionary).get("error", "download failed"))
			push_warning("[M3U] %s: %s" % [loc, msg])
			playlist_failed.emit(key, msg)
			return
	else:
		if not FileAccess.file_exists(loc):
			push_warning("[M3U] %s: no such file" % loc)
			playlist_failed.emit(key, "No file %s" % loc.get_file())
			return
		text = FileAccess.get_file_as_string(loc)
		if text.is_empty() and FileAccess.get_open_error() != OK:
			push_warning("[M3U] %s: cannot read (error %d)" % [loc, FileAccess.get_open_error()])
			playlist_failed.emit(key, "Cannot read %s" % loc.get_file())
			return

	var channels := build_channels(text, s)
	var parsed_info: Dictionary = channels.pop_back()
	var info := {
		"name": name,
		"count": channels.size(),
		"dropped_options": parsed_info.get("dropped_options", []),
		"truncated": bool(parsed_info.get("truncated", false)),
		"media": bool(parsed_info.get("media", false)),
	}
	print("[M3U] %s: %d bytes -> %d channel(s)%s%s%s" % [loc, text.length(), channels.size(),
		" (HLS stream, one channel)" if info["media"] else "",
		" (truncated at %d)" % M3uPlaylist.MAX_CHANNELS if info["truncated"] else "",
		"; dropped options %s" % str(info["dropped_options"])
			if not (info["dropped_options"] as Array).is_empty() else ""])
	if channels.is_empty():
		playlist_failed.emit(key, "%s lists no channels" % name)
		return
	if remote:
		_save_cache(key, name, channels)
	playlist_ready.emit(key, channels, info)


## Parse a playlist's text into lineup rows for source `s`: tagged with the source's
## key, filtered to its `groups` if it names any. An HLS media playlist is one
## channel, the source's own address. The LAST element is the parse summary
## ({dropped_options, truncated, media}); the caller pops it. Static so the suite
## needs no node.
static func build_channels(text: String, s: Dictionary) -> Array:
	var key := str(s.get("key", s.get("location", "")))
	var loc := str(s.get("location", key))
	var parsed := M3uPlaylist.parse(text, loc, int(s.get("number_start", 0)))
	var out: Array = []
	if parsed["is_media_playlist"]:
		out.append({"number": str(s.get("number", "")), "name": str(s.get("name", loc.get_file())),
			"url": loc, "source": "m3u", "hd": false, "group": "", "logo": "",
			"tvg_id": "", "vlc_options": PackedStringArray()})
	else:
		var wanted: Array = s.get("groups", []) if s.get("groups") is Array else []
		for c: Dictionary in parsed["channels"]:
			if not wanted.is_empty() and not _in_groups(str(c.get("group", "")), wanted):
				continue
			out.append(c)
	for c: Dictionary in out:
		c["source_key"] = key
	out.append({"dropped_options": parsed["dropped_options"],
		"truncated": parsed["truncated"], "media": parsed["is_media_playlist"]})
	return out


## Whether a channel's group-title is one of `wanted`. iptv-org writes several
## groups in one, separated by ';' ("News;Science"); any one of them counts.
static func _in_groups(group: String, wanted: Array) -> bool:
	for g in group.split(";", false):
		if wanted.has(g.strip_edges()):
			return true
	return false


## GET `url`. Answers the body as a String, or {error: String}.
func _download(url: String) -> Variant:
	if _http.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		_http.cancel_request()
	var err := _http.request(url)
	if err != OK:
		return {"error": "Cannot request (error %d)" % err}
	var result: Array = await _http.request_completed
	var transport := int(result[0])
	var code := int(result[1])
	var body: PackedByteArray = result[3]
	if transport == HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
		return {"error": "Playlist too large"}
	if transport == HTTPRequest.RESULT_TIMEOUT:
		return {"error": "Timed out"}
	if transport != HTTPRequest.RESULT_SUCCESS:
		return {"error": "Cannot reach server (result %d)" % transport}
	if code != 200:
		return {"error": "HTTP %d" % code}
	return body.get_string_from_utf8()


# ── cache ─────────────────────────────────────────────────────────────────────

## The cached channels for `key`, or [] (an entry is replaced whole on each save).
static func cached_channels(key: String) -> Array:
	var cache := load_cache()
	var entry: Variant = cache.get(key)
	if entry is Dictionary and (entry as Dictionary).get("channels") is Array:
		return (entry as Dictionary)["channels"]
	return []


static func load_cache() -> Dictionary:
	if not FileAccess.file_exists(CACHE_PATH):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(CACHE_PATH)) != OK:
		return {}
	var data: Variant = json.data
	if not (data is Dictionary) or not ((data as Dictionary).get("playlists") is Dictionary):
		return {}
	return (data as Dictionary)["playlists"]


func _save_cache(key: String, name: String, channels: Array) -> void:
	# Disposable, like HDHomeRun's: an unwritable cache costs channels on the next
	# offline cold start and nothing else.
	var all := load_cache()
	var rows: Array = []
	for c: Dictionary in channels:
		var row := c.duplicate()
		row["vlc_options"] = Array(PackedStringArray(row.get("vlc_options", PackedStringArray())))
		rows.append(row)
	all[key] = {"name": name, "saved": Time.get_unix_time_from_system(), "channels": rows}
	JsonStore.write_dict(CACHE_PATH, {"version": 1, "playlists": all})
