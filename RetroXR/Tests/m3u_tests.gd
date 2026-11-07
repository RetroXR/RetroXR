## m3u_tests — IPTV channels from M3U playlists, on the aerial's lineup.
##
## The parser (M3uPlaylist) is driven with strings; the config (TVChannels) and the
## fetcher (M3uFetcher) with files written into the REAL tv folder, because
## RomLibrary.default_tv_root() cannot be pointed elsewhere -- each file a case
## writes is removed, and channels.json is put back byte for byte. No network: the
## fetcher only ever reads a local file here, and the lineup under test has no
## HDHomeRun child, so nothing broadcasts for a tuner.
##
##   "$godot" --headless --path RetroXR res://Tests/m3u_tests.tscn [-- --only=parse/]
extends "res://Tests/test_suite.gd"

const PREFIX := "zz_m3u_tests_"

var _only := ""
var _written: Array[String] = []


## A lineup with the playlist fetcher and no tuner: TVLineup's own merge and
## status code, without the HDHomeRun child reload_channels would send looking.
class PlaylistOnlyLineup extends TVLineup:
	func _ready() -> void:
		_m3u = M3uFetcher.new()
		_m3u.name = "M3uFetcher"
		_m3u.playlist_ready.connect(_on_playlist_ready)
		_m3u.playlist_failed.connect(_on_playlist_failed)
		add_child(_m3u)

	func fetch(sources: Array[Dictionary]) -> void:
		_playlists.clear()
		for s in sources:
			_playlists[str(s["key"])] = {"name": str(s.get("name", "")), "count": 0,
				"error": "", "pending": true}
		_m3u.fetch(sources)


func _ready() -> void:
	suite_tag = "m3u"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7)
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		push_error("[m3u] TIMEOUT")
		_cleanup()
		get_tree().quit(1))

	var cfg_path := TVChannels.config_path()
	var saved_cfg: Variant = _snapshot_file(cfg_path)
	RomLibrary.ensure_tv_root()

	_parse_cases()
	_option_cases()
	_config_cases()
	_build_cases()
	await _lineup_cases()

	_cleanup()
	_restore_file(cfg_path, saved_cfg)
	_ok(_snapshot_file(cfg_path) == saved_cfg, "cleanup/channels.json is as it was")
	_finish()


func _wanted(what: String) -> bool:
	return _only.is_empty() or what.begins_with(_only)


func _write(name: String, text: String) -> String:
	var path := RomLibrary.default_tv_root().path_join(PREFIX + name)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
	_written.append(path)
	return path


func _cleanup() -> void:
	for p in _written:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	_written.clear()


static func _lines(rows: Array) -> String:
	return "\n".join(PackedStringArray(rows))


# ── parse/ ────────────────────────────────────────────────────────────────────

func _parse_cases() -> void:
	if not _wanted("parse/"):
		return
	var text := _lines([
		"#EXTM3U x-tvg-url=\"http://epg/guide.xml\"",
		"#EXTINF:-1 tvg-id=\"One.us\" tvg-chno=\"4\" tvg-logo=\"http://l/1.png\" group-title=\"News\",One News",
		"http://s/one.m3u8",
		"#EXTINF:-1 tvg-name=\"Two, The Channel\" group-title=\"Kids, Family\",Two, The Channel HD",
		"http://s/two.m3u8",
		"#EXTINF:-1,Three",
		"http://s/three.ts",
	])
	var r := M3uPlaylist.parse(text)
	var ch: Array = r["channels"]
	_ok(bool(r["has_header"]), "parse/the #EXTM3U header is seen")
	_eq(ch.size(), 3, "parse/three entries are three channels")
	if ch.size() == 3:
		_eq(ch[0]["name"], "One News", "parse/the title follows the comma")
		_eq(ch[0]["number"], "4", "parse/tvg-chno is the channel number")
		_eq(ch[0]["group"], "News", "parse/group-title is the group")
		_eq(ch[0]["logo"], "http://l/1.png", "parse/tvg-logo is kept")
		_eq(ch[0]["tvg_id"], "One.us", "parse/tvg-id is kept")
		_eq(ch[0]["url"], "http://s/one.m3u8", "parse/the next line is the stream")
		_eq(ch[0]["source"], "m3u", "parse/rows are tagged as playlist channels")
		_eq(ch[1]["name"], "Two, The Channel HD",
			"parse/a comma inside a quoted attribute does not start the title")
		_eq(ch[1]["group"], "Kids, Family", "parse/a quoted value keeps its comma")
		_ok(bool(ch[1]["hd"]) and not bool(ch[0]["hd"]), "parse/HD is read from the title")
		_eq(ch[2]["number"], "", "parse/no number and no start leaves it unnumbered")

	var crlf := "\uFEFF#EXTM3U\r\n#EXTINF:-1 group-title=Sports tvg-chno=7,Seven\r\nhttp://s/7\r\n"
	var r2 := M3uPlaylist.parse(crlf)
	_eq((r2["channels"] as Array).size(), 1, "parse/BOM and CRLF are tolerated")
	if (r2["channels"] as Array).size() == 1:
		var c: Dictionary = r2["channels"][0]
		_eq(c["url"], "http://s/7", "parse/no carriage return is left on the URL")
		_eq(c["group"], "Sports", "parse/an unquoted attribute value is read")
		_eq(c["number"], "7", "parse/an unquoted attribute after another is read")

	var bare := M3uPlaylist.parse(_lines(["http://a/x/first.ts", "", "http://a/x/second.ts"]))
	_ok(not bool(bare["has_header"]), "parse/a list with no header still parses")
	_eq((bare["channels"] as Array).size(), 2, "parse/bare URLs are channels")
	if (bare["channels"] as Array).size() == 2:
		_eq(bare["channels"][0]["name"], "first.ts", "parse/a bare URL is named after its file")

	var grp := M3uPlaylist.parse(_lines([
		"#EXTINF:-1,A", "#EXTGRP:Movies", "http://s/a",
		"#EXTINF:-1 group-title=\"News\",B", "#EXTGRP:Movies", "http://s/b",
		"#EXTINF:-1,C", "http://s/c"]))
	var g: Array = grp["channels"]
	if g.size() == 3:
		_eq(g[0]["group"], "Movies", "parse/#EXTGRP gives the group")
		_eq(g[1]["group"], "News", "parse/group-title wins over #EXTGRP")
		_eq(g[2]["group"], "", "parse/#EXTGRP does not carry to the next entry")
	else:
		_ok(false, "parse/#EXTGRP list has three channels", "got %d" % g.size())

	var numbered := M3uPlaylist.parse(_lines([
		"#EXTINF:-1,A", "http://s/a",
		"#EXTINF:-1 tvg-chno=\"50\",B", "http://s/b",
		"#EXTINF:-1,C", "http://s/c"]), "", 100)
	var nb: Array = numbered["channels"]
	if nb.size() == 3:
		_eq([nb[0]["number"], nb[1]["number"], nb[2]["number"]], ["100", "50", "102"],
			"parse/number_start counts up, a channel's own number wins")

	var rel := M3uPlaylist.parse(_lines(["#EXTINF:-1,R", "live/r.m3u8",
		"#EXTINF:-1,S", "/root/s.m3u8"]), "https://host.tv/lists/all.m3u?token=1")
	var rl: Array = rel["channels"]
	if rl.size() == 2:
		_eq(rl[0]["url"], "https://host.tv/lists/live/r.m3u8",
			"parse/a relative stream is relative to the playlist's folder")
		_eq(rl[1]["url"], "https://host.tv/root/s.m3u8",
			"parse/a rooted stream is on the playlist's server")
	_eq(M3uPlaylist.resolve_url("v/a.mp4", "C:/media/tv/list.m3u"), "C:/media/tv/v/a.mp4",
		"parse/a relative stream in a local playlist is beside the file")

	var media := M3uPlaylist.parse(_lines(["#EXTM3U", "#EXT-X-TARGETDURATION:6",
		"#EXT-X-MEDIA-SEQUENCE:1", "#EXTINF:6.0,", "seg1.ts", "#EXTINF:6.0,", "seg2.ts"]))
	_ok(bool(media["is_media_playlist"]), "parse/an HLS media playlist is recognised")
	_eq((media["channels"] as Array).size(), 0, "parse/an HLS playlist's segments are not channels")

	var twice := M3uPlaylist.parse(_lines(["#EXTINF:-1,Lost", "#EXTINF:-1,Kept", "http://s/k"]))
	_eq(int(twice["skipped"]), 1, "parse/an #EXTINF with no stream is counted as skipped")
	if (twice["channels"] as Array).size() == 1:
		_eq(twice["channels"][0]["name"], "Kept", "parse/the later #EXTINF names the stream")

	var many: Array = ["#EXTM3U"]
	for i in M3uPlaylist.MAX_CHANNELS + 3:
		many.append("#EXTINF:-1,C%d" % i)
		many.append("http://s/%d" % i)
	var big := M3uPlaylist.parse(_lines(many))
	_eq((big["channels"] as Array).size(), M3uPlaylist.MAX_CHANNELS,
		"parse/a list past the cap is cut at the cap")
	_ok(bool(big["truncated"]), "parse/and says it was cut")

	_ok(M3uPlaylist.looks_hd("ABC 1080p") and M3uPlaylist.looks_hd("XYZ FHD")
		and not M3uPlaylist.looks_hd("SHADOW") and not M3uPlaylist.looks_hd("Channel 7"),
		"parse/HD is a word, not letters inside one")


# ── options/ ──────────────────────────────────────────────────────────────────

func _option_cases() -> void:
	if not _wanted("options/"):
		return
	var r := M3uPlaylist.parse(_lines([
		"#EXTINF:-1,A",
		"#EXTVLCOPT:http-user-agent=Mozilla/5.0 (X11)",
		"#EXTVLCOPT:http-referrer=https://site.tv/",
		"#EXTVLCOPT:sout=#file{dst=C:/evil.ts}",
		"#EXTVLCOPT::SOUT-KEEP",
		"http://s/a",
		"#EXTINF:-1,B",
		"http://s/b",
	]))
	var ch: Array = r["channels"]
	if ch.size() != 2:
		_ok(false, "options/two channels parsed", "got %d" % ch.size())
		return
	var a_opts := PackedStringArray(ch[0]["vlc_options"])
	_eq(a_opts, PackedStringArray(["http-user-agent=Mozilla/5.0 (X11)",
		"http-referrer=https://site.tv/"]), "options/the allowed options are kept, in order")
	_ok(not str(a_opts).contains("sout"), "options/sout never reaches the channel")
	_ok((r["dropped_options"] as Array).has("sout")
		and (r["dropped_options"] as Array).has("sout-keep"),
		"options/a refused option is reported by name, colon and case aside")
	_eq(PackedStringArray(ch[1]["vlc_options"]).size(), 0,
		"options/options belong to the next stream only")
	# iptv-org's shape: the header as an #EXTINF attribute, alone or repeated.
	var attr := M3uPlaylist.parse(_lines([
		"#EXTINF:-1 http-referrer=\"https://ref.tv/\" http-user-agent=\"UA/1\",Only attrs",
		"http://s/c",
		"#EXTINF:-1 http-user-agent=\"UA/1\",Both",
		"#EXTVLCOPT:http-user-agent=UA/1",
		"http://s/d"]))
	var ac: Array = attr["channels"]
	if ac.size() == 2:
		_eq(PackedStringArray(ac[0]["vlc_options"]),
			PackedStringArray(["http-user-agent=UA/1", "http-referrer=https://ref.tv/"]),
			"options/#EXTINF header attributes become options")
		_eq(PackedStringArray(ac[1]["vlc_options"]).size(), 1,
			"options/an attribute repeated as #EXTVLCOPT is sent once")
	_ok(M3uPlaylist.is_allowed_option(":network-caching=3000")
		and not M3uPlaylist.is_allowed_option("demux=ts"),
		"options/the allowlist is by option name")

	# The C++ half, when the extension is loaded: the method exists and accepts a
	# mixed list without complaint about the allowed ones (it is not observable
	# further without opening a stream).
	if ClassDB.class_exists("VlcPlayer"):
		var vlc: Object = ClassDB.instantiate("VlcPlayer")
		_ok(vlc.has_method("set_media_options"),
			"options/VlcPlayer has set_media_options (rebuild vlc-godot if not)")
		if vlc is RefCounted:
			vlc = null
		elif vlc != null:
			vlc.free()


# ── config/ ───────────────────────────────────────────────────────────────────

func _config_cases() -> void:
	if not _wanted("config/"):
		return
	var cfg := TVChannels.new()
	cfg._ingest({"sources": [
		{"name": "List", "link": "http://h/list.m3u"},
		{"name": "Query list", "url": "http://h/get.m3u?user=a&pass=b"},
		{"name": "HLS", "link": "http://h/live.m3u8"},
		{"type": "m3u", "name": "Typed", "url": "http://h/typed.m3u8"},
		{"type": "m3u", "name": "Off", "url": "http://h/off.m3u", "enabled": false},
	]})
	var kinds: Array = []
	for s in cfg.sources:
		kinds.append(s["type"])
	_eq(kinds, ["m3u", "m3u", "stream", "m3u", "m3u"],
		"config/a .m3u link is a playlist, a .m3u8 link a stream unless typed")
	_eq(cfg.stream_channels.size(), 1, "config/only the stream is a channel of its own")

	var before := _tv_folder_m3u()
	var dropped := _write("folder.m3u", "#EXTM3U\n")
	var hls := _write("folder.m3u8", "#EXTM3U\n")
	var srcs := cfg.playlist_sources()
	var keys: Array = []
	for s in srcs:
		keys.append(s["key"])
	_ok(keys.has("http://h/list.m3u") and keys.has("http://h/typed.m3u8"),
		"config/named playlists are sources")
	_ok(not keys.has("http://h/off.m3u"), "config/a playlist switched off is not read")
	_ok(keys.has(dropped), "config/a .m3u dropped in the tv folder is a source")
	_ok(not keys.has(hls), "config/a .m3u8 in the tv folder is not")
	_eq(srcs.size(), 3 + before.size() + 1, "config/nothing else is read")
	for s in srcs:
		if s["key"] == dropped:
			_ok(bool(s.get("implicit", false)), "config/the folder's file is marked implicit")

	# A source that names the folder's file reads it once, by a relative path.
	var cfg2 := TVChannels.new()
	cfg2._ingest({"sources": [{"type": "m3u", "name": "Mine", "path": PREFIX + "folder.m3u"}]})
	var once := 0
	for s in cfg2.playlist_sources():
		if str(s["location"]).simplify_path() == dropped.simplify_path():
			once += 1
	_eq(once, 1, "config/a relative path is in the tv folder, and read once")

	# The panel's URL round-trips through channels.json and the folder's files do not.
	var cfg3 := TVChannels.new()
	cfg3._ingest({"sources": [{"type": "hdhomerun", "name": "Antenna", "auto": true, "host": ""}]})
	cfg3.set_playlist("http://h/panel.m3u", true)
	var back := TVChannels.load_config()
	_eq(back.playlist_url(), "http://h/panel.m3u", "config/the panel's playlist is saved")
	_ok(back.tuner_source().size() > 0, "config/the tuner's source is kept beside it")
	var text := FileAccess.get_file_as_string(TVChannels.config_path())
	_ok(not text.contains(PREFIX), "config/a folder playlist is never written to channels.json")
	back.set_playlist("http://h/panel.m3u", false)
	_ok(not TVChannels.load_config().playlist_enabled(), "config/switching it off is saved")
	back.set_playlist("", false)
	_eq(TVChannels.load_config().playlist_url(), "", "config/an empty URL removes it")


func _tv_folder_m3u() -> Array:
	var out: Array = []
	var dir := DirAccess.open(RomLibrary.default_tv_root())
	if dir:
		for f in dir.get_files():
			if f.to_lower().ends_with(".m3u") and not f.begins_with(PREFIX):
				out.append(f)
	return out


# ── build/ ────────────────────────────────────────────────────────────────────

func _build_cases() -> void:
	if not _wanted("build/"):
		return
	var text := _lines(["#EXTM3U",
		"#EXTINF:-1 group-title=\"News\",N1", "http://s/n1",
		"#EXTINF:-1 group-title=\"Sports\",S1", "http://s/s1",
		"#EXTINF:-1 group-title=\"News\",N2", "http://s/n2",
		"#EXTINF:-1 group-title=\"Kids;News\",N3", "http://s/n3",
		"#EXTINF:-1 group-title=\"Newsreel\",X", "http://s/x"])
	var rows := M3uFetcher.build_channels(text,
		{"key": "K", "location": "http://h/a.m3u", "groups": ["News"]})
	var summary: Dictionary = rows.pop_back()
	_eq(rows.map(func(c: Dictionary) -> String: return c["name"]), ["N1", "N2", "N3"],
		"build/a source's groups keep only those, any one of a ';' list, whole names only")
	_ok(rows.all(func(c: Dictionary) -> bool: return c["source_key"] == "K"),
		"build/every row carries its source's key")
	_ok(summary.has("truncated") and summary.has("dropped_options"),
		"build/the summary comes last")
	var media := M3uFetcher.build_channels("#EXTM3U\n#EXT-X-TARGETDURATION:4\nseg.ts\n",
		{"key": "L", "location": "http://h/live.m3u8", "name": "Live One", "number": "9"})
	media.pop_back()
	_eq(media.size(), 1, "build/an HLS playlist is one channel")
	if media.size() == 1:
		_eq([media[0]["url"], media[0]["name"], media[0]["number"]],
			["http://h/live.m3u8", "Live One", "9"], "build/...the source's own address and name")


# ── lineup/ ───────────────────────────────────────────────────────────────────

func _lineup_cases() -> void:
	if not _wanted("lineup/"):
		return
	var path := _write("lineup.m3u", _lines(["#EXTM3U",
		"#EXTINF:-1 tvg-chno=\"10.2\",Ten Two", "http://s/102",
		"#EXTINF:-1 tvg-chno=\"3\",Three", "http://s/3"]))
	var lineup := PlaylistOnlyLineup.new()
	add_child(lineup)
	# A stream from channels.json and a tuner channel already on the list.
	lineup.channels.append({"number": "5", "name": "Typed", "url": "http://t/5", "source": "stream"})
	lineup.channels.append({"number": "4.1", "name": "Air", "url": "http://hd/4.1", "source": "hdhomerun"})

	var src: Array[Dictionary] = [{"key": path, "location": path, "name": "lineup"}]
	lineup.fetch(src)
	var done := await _wait_until(func() -> bool: return not lineup._m3u.is_busy(), 5.0)
	_ok(done, "lineup/a local playlist is read")
	var numbers: Array = lineup.channels.map(func(c: Dictionary) -> String: return c["number"])
	_eq(numbers, ["3", "4.1", "5", "10.2"],
		"lineup/playlist channels join the list in dial order")
	_ok(lineup.playlist_status_line().contains("2 channels"), "lineup/the status line counts them",
		lineup.playlist_status_line())

	# The file changes: its rows are replaced whole, nobody else's are touched.
	_write("lineup.m3u", _lines(["#EXTINF:-1 tvg-chno=\"20\",Twenty", "http://s/20"]))
	lineup.fetch(src)
	await _wait_until(func() -> bool: return not lineup._m3u.is_busy(), 5.0)
	numbers = lineup.channels.map(func(c: Dictionary) -> String: return c["number"])
	_eq(numbers, ["4.1", "5", "20"], "lineup/a re-read replaces only that playlist's rows")

	# The file goes away: what is on the list stays, the status says why.
	DirAccess.remove_absolute(path)
	lineup.fetch(src)
	await _wait_until(func() -> bool: return not lineup._m3u.is_busy(), 5.0)
	_eq(lineup.channels.size(), 3, "lineup/a playlist that cannot be read leaves its rows")
	_ok(lineup.playlist_status_line().contains("No file"), "lineup/and the status says so",
		lineup.playlist_status_line())
	_eq(lineup.fault_text(), "", "lineup/no fault on the glass while there are channels")
	lineup.channels.clear()
	_ok(lineup.fault_text().begins_with("PLAYLIST ERROR"),
		"lineup/a playlist error is the fault when nothing else is on the list", lineup.fault_text())

	lineup.queue_free()
