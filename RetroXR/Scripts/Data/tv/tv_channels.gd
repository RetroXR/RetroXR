## TVChannels — the set's channel list, read from a user-editable channels.json.
##
## The file lives in RomLibrary.default_tv_root() and names *sources*, never
## channels: an "hdhomerun" source stands for a whole tuner and expands to its
## lineup at runtime via HDHomeRun.discover(), and an "m3u" source is an IPTV
## playlist (a `url`, or a `path` relative to this folder) that expands to its
## channels via M3uFetcher. Every `.m3u` file lying in this folder is a playlist
## too, unnamed here (playlist_sources). Resolving both is asynchronous and
## belongs to the caller — this class only parses, holds and saves.
##
## There used to be a third kind, "stream": one channel typed as a {name, link}
## entry. It was removed 2026-11-08 -- a two-line .m3u does the same and more.
## Such an entry is now IGNORED (counted in `ignored`, logged), but kept in
## `sources` as written, so a save from the antenna panel never deletes a line
## the player wrote.
class_name TVChannels
extends RefCounted

const FILE_NAME := "channels.json"

## Parse outcome, so the TV can tell "you have no channel list" (show a hint)
## from "your channel list is broken" (show the parser's complaint).
enum Status { OK, MISSING, PARSE_ERROR }

var status: int = Status.MISSING
var error_message := ""
## Source entries exactly as written, order preserved. Saving rewrites these.
var sources: Array[Dictionary] = []
## Entries that are neither a tuner nor a playlist (the old "stream" channels).
var ignored := 0


static func config_path() -> String:
	return RomLibrary.default_tv_root().path_join(FILE_NAME)


## Read channels.json. Never throws: inspect `status` afterwards.
static func load_config() -> TVChannels:
	var cfg := TVChannels.new()
	var path := config_path()
	if not FileAccess.file_exists(path):
		cfg.status = Status.MISSING
		cfg.error_message = "No %s in %s" % [FILE_NAME, RomLibrary.default_tv_root()]
		return cfg

	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		cfg.status = Status.PARSE_ERROR
		cfg.error_message = "Cannot open %s" % path
		push_warning("[TVChannels] %s" % cfg.error_message)
		return cfg

	# JSON.new().parse() rather than JSON.parse_string(): this file is written by
	# hand, so a typo has to name itself instead of vanishing into a null.
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		cfg.status = Status.PARSE_ERROR
		cfg.error_message = "line %d: %s" % [json.get_error_line(), json.get_error_message()]
		push_warning("[TVChannels] JSON parse error, %s" % cfg.error_message)
		return cfg

	cfg._ingest(json.data)
	cfg.status = Status.OK
	print("[TVChannels] Loaded %d source(s)" % cfg.sources.size())
	if cfg.ignored > 0:
		push_warning(("[TVChannels] Ignoring %d stream entr%s in %s: channels are no longer "
			+ "typed there; put them in a .m3u playlist in %s") % [cfg.ignored,
			"y" if cfg.ignored == 1 else "ies", FILE_NAME, RomLibrary.default_tv_root()])
	return cfg


## Accepts either the documented object form or a bare array of sources. The bare
## array is the shape people reach for first, and rejecting it would make a file
## that reads as obviously correct look broken.
func _ingest(data: Variant) -> void:
	var raw: Array = []
	if data is Array:
		raw = data as Array
	elif data is Dictionary:
		var doc := data as Dictionary
		if doc.get("sources") is Array:
			raw = doc["sources"] as Array
		elif doc.get("channels") is Array:
			raw = doc["channels"] as Array

	for entry_v: Variant in raw:
		if not (entry_v is Dictionary):
			continue
		var entry: Dictionary = (entry_v as Dictionary).duplicate()
		# A kind can go unsaid: a host with no link is a tuner, a link to a .m3u
		# is a playlist (a .m3u8 is not: that extension is almost always ONE HLS
		# stream, which is what the removed "stream" entries were).
		var kind := str(entry.get("type", "")).to_lower()
		if kind == "":
			if entry.has("host") and not entry.has("link"):
				kind = "hdhomerun"
			elif is_playlist_link(str(entry.get("link", entry.get("url", entry.get("path", ""))))):
				kind = "m3u"
		if kind == "hdhomerun" or kind == "m3u":
			entry["type"] = kind
		else:
			# Kept exactly as written (no type stamped on it), read as nothing.
			ignored += 1
			print("[TVChannels] Ignoring '%s' (%s): not a tuner or a playlist"
				% [str(entry.get("name", "(unnamed)")),
				   str(entry.get("link", entry.get("url", "no link")))])
		sources.append(entry)


## Whether a link names an M3U channel list rather than a stream. Only `.m3u`;
## `.m3u8` is the HLS extension and nearly always one stream.
static func is_playlist_link(link: String) -> bool:
	var l := link.strip_edges().to_lower()
	var q := l.find("?")
	if q >= 0:
		l = l.substr(0, q)
	return l.ends_with(".m3u")


## Every playlist to read: the m3u sources written in channels.json, then every
## `.m3u` file lying in the tv folder (sorted by name), which is how a player adds
## one -- drop the file in, or upload it there through the Web File Manager. A
## folder file a source already names is not read twice. The folder's are marked
## `implicit` and never written back by save().
##
## Each comes back with `key` (what the lineup and the cache file it under) and
## `location` (a URL, or an absolute path for a file).
func playlist_sources() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var named: Dictionary = {}
	var root := RomLibrary.default_tv_root()
	for s: Dictionary in sources:
		if str(s.get("type", "")) != "m3u" or not bool(s.get("enabled", true)):
			continue
		var loc := playlist_location(s, root)
		if loc.is_empty():
			push_warning("[TVChannels] Skipping playlist '%s': no url or path"
				% str(s.get("name", "(unnamed)")))
			continue
		var entry := s.duplicate()
		entry["location"] = loc
		entry["key"] = loc
		named[loc.simplify_path() if not loc.contains("://") else loc] = true
		out.append(entry)

	var dir := DirAccess.open(root)
	if dir:
		var files: Array[String] = []
		for f in dir.get_files():
			if f.to_lower().ends_with(".m3u"):
				files.append(f)
		files.sort()
		for f in files:
			var path := root.path_join(f)
			if named.has(path.simplify_path()):
				continue
			out.append({"type": "m3u", "name": f.get_basename(), "path": path,
				"location": path, "key": path, "implicit": true})
	return out


## Where a playlist source points: its `url`, or its `path` (a relative path is
## relative to the tv folder, where the player keeps channels.json beside it).
static func playlist_location(s: Dictionary, root: String) -> String:
	var url := str(s.get("url", s.get("link", ""))).strip_edges()
	if not url.is_empty():
		if url.begins_with("file://"):
			return url.substr(7)
		return url
	var path := str(s.get("path", "")).strip_edges()
	if path.is_empty():
		return ""
	if path.is_absolute_path():
		return path
	return root.path_join(path)


## The playlist URL the antenna menu edits: the first m3u source written in
## channels.json that names a url. Empty when there is none.
func playlist_url() -> String:
	for s: Dictionary in sources:
		if str(s.get("type", "")) == "m3u" and s.has("url"):
			return str(s.get("url", "")).strip_edges()
	return ""


func playlist_enabled() -> bool:
	for s: Dictionary in sources:
		if str(s.get("type", "")) == "m3u" and s.has("url"):
			return bool(s.get("enabled", true))
	return true


## Point the menu's playlist at `url` (or switch it off) and persist. Creates the
## source when the file has none; an empty url removes it.
func set_playlist(url: String, enabled: bool) -> void:
	url = url.strip_edges()
	for i in sources.size():
		if str(sources[i].get("type", "")) == "m3u" and sources[i].has("url"):
			if url.is_empty():
				sources.remove_at(i)
			else:
				sources[i]["url"] = url
				sources[i]["enabled"] = enabled
			save()
			return
	if url.is_empty():
		return
	sources.append({"type": "m3u", "name": "Playlist", "url": url, "enabled": enabled})
	save()


## The first hdhomerun source, or {} when the list names no tuner.
func tuner_source() -> Dictionary:
	for s: Dictionary in sources:
		if str(s.get("type", "")) == "hdhomerun":
			return s
	return {}


## Whether the tuner should be discovered rather than addressed directly.
## Defaults to true so a source written as {"type":"hdhomerun"} just works.
func tuner_auto() -> bool:
	var s := tuner_source()
	return bool(s.get("auto", true)) if not s.is_empty() else true


func tuner_host() -> String:
	var s := tuner_source()
	return str(s.get("host", "")).strip_edges() if not s.is_empty() else ""


## Point the tuner at a specific address (or back at discovery) and persist.
## Creates the hdhomerun source if the file did not have one, so the options
## panel can turn a playlist-only list into a tuned set.
func set_tuner(auto: bool, host: String) -> void:
	var found := false
	for i in sources.size():
		if str(sources[i].get("type", "")) == "hdhomerun":
			sources[i]["auto"] = auto
			sources[i]["host"] = host.strip_edges()
			found = true
			break
	if not found:
		sources.insert(0, {
			"type": "hdhomerun",
			"name": "Antenna",
			"auto": auto,
			"host": host.strip_edges(),
		})
	save()


## Write the source list back, preserving every key the user put there.
func save() -> bool:
	var path := config_path()
	if not JsonStore.write_dict(path, {"version": 1, "sources": sources},
			"TVChannels"):
		return false
	print("[TVChannels] Saved %d source(s) to %s" % [sources.size(), path])
	return true


## Write a commented starter file so a first run has something to edit rather
## than an empty folder. Only ever called when nothing is there.
static func write_default_config() -> void:
	var path := config_path()
	if FileAccess.file_exists(path):
		return
	RomLibrary.ensure_tv_root()
	var defaults := {
		"version": 1,
		"sources": [
			{"type": "hdhomerun", "name": "Antenna", "auto": true, "host": ""},
		],
	}
	if JsonStore.write_dict(path, defaults, "TVChannels"):
		print("[TVChannels] Wrote starter channel list: %s" % path)
