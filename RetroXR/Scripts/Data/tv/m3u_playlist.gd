## M3uPlaylist — reads an IPTV channel list in the extended M3U format.
##
## The shape every IPTV provider and iptv-org publishes:
##
##   #EXTM3U
##   #EXTINF:-1 tvg-id="X.us" tvg-chno="4" tvg-logo="…" group-title="News",Channel X
##   #EXTVLCOPT:http-user-agent=Mozilla/5.0
##   https://example.com/x/index.m3u8
##
## One #EXTINF line names a channel; the next line that is not a comment is its
## stream. Pure: no file or network access, so the suite drives it with strings.
## Fetching is M3uFetcher's, and the lineup merge is TVLineup's.
##
## A channel comes out in TVChannels' shape ({number, name, url, source, hd}) plus
## `group`, `logo`, `tvg_id` and `vlc_options`, so every reader of the lineup takes
## it unchanged.
class_name M3uPlaylist
extends RefCounted

## The #EXTVLCOPT options passed on to libVLC. Everything else is DROPPED: a
## playlist is downloaded from anywhere, and libVLC's options reach far past
## playback (`sout` writes files, `sout-keep`, module selection…). These are the
## ones IPTV lists actually carry. VlcPlayer checks the same list in C++.
const ALLOWED_VLC_OPTIONS := [
	"http-user-agent",
	"http-referrer",
	"http-referer",     # the spelling the HTTP header uses; some lists write it
	"network-caching",
	"adaptive-logic",
]

## The dial is walked a channel at a time, and iptv-org's whole-world list runs
## past ten thousand. More than this is a list for browsing, not a set's dial.
const MAX_CHANNELS := 5000

## Tags that only an HLS MEDIA playlist (one stream's segments) carries. A file
## with any of them is a stream, not a channel list.
const _HLS_MEDIA_TAGS := ["#EXT-X-TARGETDURATION", "#EXT-X-MEDIA-SEQUENCE",
	"#EXT-X-STREAM-INF"]

static var _hd_regex: RegEx = null


## Parse `text`. `base_url` resolves relative stream paths (a playlist downloaded
## from a server, or read from a folder). `number_start` > 0 numbers channels that
## carry no number of their own, counting up from it.
##
## Returns {channels: Array[Dictionary], skipped: int, dropped_options: Array,
##          is_media_playlist: bool, truncated: bool, has_header: bool}.
static func parse(text: String, base_url: String = "", number_start: int = 0) -> Dictionary:
	var out := {
		"channels": [] as Array[Dictionary],
		"skipped": 0,
		"dropped_options": [],
		"is_media_playlist": false,
		"truncated": false,
		"has_header": false,
	}
	if text.begins_with("﻿"):
		text = text.substr(1)
	var lines := text.replace("\r\n", "\n").replace("\r", "\n").split("\n")

	var channels: Array[Dictionary] = out["channels"]
	var dropped: Array = out["dropped_options"]
	# What the lines since the last stream said about the next one.
	var pending_info: Dictionary = {}
	var pending_group := ""
	var pending_opts := PackedStringArray()
	var auto_number := number_start

	for raw: String in lines:
		var line := raw.strip_edges()
		if line.is_empty():
			continue
		if line.begins_with("#"):
			var upper := line.to_upper()
			if upper.begins_with("#EXTM3U"):
				out["has_header"] = true
			elif upper.begins_with("#EXTINF:"):
				# A second #EXTINF before a URL: the first named nothing playable.
				if not pending_info.is_empty():
					out["skipped"] = int(out["skipped"]) + 1
				pending_info = parse_extinf(line.substr(8))
			elif upper.begins_with("#EXTGRP:"):
				pending_group = line.substr(8).strip_edges()
			elif upper.begins_with("#EXTVLCOPT:"):
				var opt := line.substr(11).strip_edges()
				if is_allowed_option(opt):
					pending_opts.append(opt)
				elif not dropped.has(_option_name(opt)):
					dropped.append(_option_name(opt))
			else:
				for tag: String in _HLS_MEDIA_TAGS:
					if upper.begins_with(tag):
						out["is_media_playlist"] = true
			continue

		# A stream line. Without an #EXTINF in front it is still a channel (a plain
		# M3U is a list of bare URLs); it is named after its own address.
		if channels.size() >= MAX_CHANNELS:
			out["truncated"] = true
			break
		var url := resolve_url(line, base_url)
		var attrs: Dictionary = pending_info.get("attrs", {})
		var title := str(pending_info.get("title", "")).strip_edges()
		if title.is_empty():
			title = str(attrs.get("tvg-name", "")).strip_edges()
		if title.is_empty():
			title = url.get_file() if not url.get_file().is_empty() else url
		var number := str(attrs.get("tvg-chno", attrs.get("channel-number", ""))).strip_edges()
		if number.is_empty() and number_start > 0:
			number = str(auto_number)
		auto_number += 1
		var group := str(attrs.get("group-title", "")).strip_edges()
		if group.is_empty():
			group = pending_group
		# iptv-org (and lists made by its tools) also put the headers on the #EXTINF
		# line as attributes, and some lists carry them only there.
		for header: String in ["http-user-agent", "http-referrer"]:
			var value := str(attrs.get(header, "")).strip_edges()
			if value.is_empty():
				continue
			var already := false
			for o in pending_opts:
				already = already or _option_name(o) == header
			if not already:
				pending_opts.append("%s=%s" % [header, value])
		channels.append({
			"number": number,
			"name": title,
			"url": url,
			"source": "m3u",
			"hd": looks_hd(title),
			"group": group,
			"logo": str(attrs.get("tvg-logo", "")),
			"tvg_id": str(attrs.get("tvg-id", "")),
			"vlc_options": pending_opts,
		})
		pending_info = {}
		pending_group = ""
		pending_opts = PackedStringArray()

	# A media playlist's lines are segments, not channels.
	if out["is_media_playlist"]:
		channels.clear()
		out["truncated"] = false
	return out


## The part of an #EXTINF line after the colon: `<duration> key="v" key=v,Title`.
## The title starts at the first comma OUTSIDE quotes -- `tvg-name="A, B"` is one
## attribute, and splitting on the first comma cut every such channel's name.
## Returns {duration: float, attrs: Dictionary, title: String}.
static func parse_extinf(rest: String) -> Dictionary:
	var in_quotes := false
	var comma := -1
	for i in rest.length():
		var c := rest[i]
		if c == "\"":
			in_quotes = not in_quotes
		elif c == "," and not in_quotes:
			comma = i
			break
	var head := rest if comma < 0 else rest.substr(0, comma)
	var title := "" if comma < 0 else rest.substr(comma + 1)

	var attrs: Dictionary = {}
	var duration := -1.0
	var i := 0
	var n := head.length()
	# Leading duration, up to the first space.
	while i < n and head[i] != " " and head[i] != "\t":
		i += 1
	var dur_text := head.substr(0, i)
	if dur_text.is_valid_float():
		duration = float(dur_text)
	# key=value pairs; a value is quoted or runs to the next space.
	while i < n:
		while i < n and (head[i] == " " or head[i] == "\t"):
			i += 1
		var key_start := i
		while i < n and head[i] != "=" and head[i] != " " and head[i] != "\t":
			i += 1
		var key := head.substr(key_start, i - key_start).strip_edges().to_lower()
		if i >= n or head[i] != "=":
			continue   # a bare word with no value: nothing to keep
		i += 1
		var value := ""
		if i < n and head[i] == "\"":
			i += 1
			var v_start := i
			while i < n and head[i] != "\"":
				i += 1
			value = head.substr(v_start, i - v_start)
			i += 1
		else:
			var v_start := i
			while i < n and head[i] != " " and head[i] != "\t":
				i += 1
			value = head.substr(v_start, i - v_start)
		if not key.is_empty():
			attrs[key] = value
	return {"duration": duration, "attrs": attrs, "title": title.strip_edges()}


## Whether an #EXTVLCOPT option may reach libVLC. `opt` is `name=value` or `name`.
static func is_allowed_option(opt: String) -> bool:
	return ALLOWED_VLC_OPTIONS.has(_option_name(opt))


static func _option_name(opt: String) -> String:
	var name := opt.strip_edges().trim_prefix(":")
	var eq := name.find("=")
	if eq >= 0:
		name = name.substr(0, eq)
	return name.strip_edges().to_lower()


## A stream line as an address libVLC opens. Absolute URLs and absolute paths pass
## through; anything else is relative to the playlist's own location.
static func resolve_url(line: String, base_url: String) -> String:
	if line.contains("://") or base_url.is_empty():
		return line
	if line.begins_with("/") or (line.length() > 2 and line[1] == ":"):
		# An absolute path; for a web playlist "/x" is the server's root.
		var scheme_end := base_url.find("://")
		if line.begins_with("/") and scheme_end >= 0:
			var host_end := base_url.find("/", scheme_end + 3)
			return (base_url if host_end < 0 else base_url.substr(0, host_end)) + line
		return line
	var dir := base_url
	var q := dir.find("?")
	if q >= 0:
		dir = dir.substr(0, q)
	var slash := dir.rfind("/")
	if slash >= 0:
		dir = dir.substr(0, slash)
	return dir + "/" + line


static func looks_hd(title: String) -> bool:
	if _hd_regex == null:
		_hd_regex = RegEx.create_from_string("(?i)\\b(HD|FHD|UHD|4K|1080[pi]?|720p)\\b")
	return _hd_regex.search(title) != null
