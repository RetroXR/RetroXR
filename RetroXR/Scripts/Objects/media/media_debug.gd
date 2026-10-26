## MediaDebug — the Debug-page rows every libVLC deck shares: what the player is
## doing, the audio stream it decodes, and where the deck's picture and sound go.
##
## Static, and every VlcPlayer getter it reads is guarded on the player side (no
## media open answers 0 / an empty list), so a deck with nothing in it can ask.
class_name MediaDebug
extends RefCounted


## "1:02:03" / "4:05" from milliseconds; "—" for an unknown length.
static func time_text(ms: int) -> String:
	if ms <= 0:
		return "—"
	var s := ms / 1000
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
	return "%d:%02d" % [s / 60, s % 60]


## The Playback and Audio stream sections for a deck's VlcPlayer, or [] without
## one (the extension is not loaded).
static func vlc_sections(vlc: Object, video: bool) -> Array:
	if vlc == null:
		return [["Playback", [["Player", "VlcPlayer not loaded"]]]]
	var length := int(vlc.call("get_length"))
	var playback: Array = [
		["State", "playing" if bool(vlc.call("is_playing")) else "stopped / paused"],
		["Time", "%s / %s" % [time_text(int(vlc.call("get_time"))), time_text(length)]],
		["Position", "%.1f%%" % (float(vlc.call("get_position")) * 100.0)],
		["Rate", "%.2f×" % float(vlc.call("get_rate"))],
	]
	if video:
		var size: Vector2i = vlc.call("get_video_size")
		playback.append_array([
			["Video size", "%d × %d" % [size.x, size.y] if size.x > 0 else "—"],
			["Frames drawn", str(int(vlc.call("get_frame_count")))],
		])
	var tracks: Array = vlc.call("get_audio_tracks")
	# What VLC decodes the sound TO for the room: always S16 at this rate and
	# channel count, whatever the file is (see VlcPlayer.open). The file's own
	# figures are the Source section's.
	var rate := int(vlc.call("get_audio_rate"))
	var channels := int(vlc.call("get_audio_channels"))
	var audio: Array = [
		["Output", "%d Hz, %d ch (resampled for the room)" % [rate, channels]],
		["Audio tracks", "%d (current id %d)" % [tracks.size(), int(vlc.call("get_audio_track"))]
			if not tracks.is_empty() else "—"],
		["Buffered", "%d ms" % int(vlc.call("get_audio_backlog_ms"))],
		["A/V lead", "%d ms (target %d)" % [int(vlc.call("get_audio_lead_ms")),
			int(vlc.call("get_audio_lead_target_ms"))]],
	]
	var out: Array = [["Playback", playback]]
	var source := source_rows(vlc)
	if not source.is_empty():
		out.append(["Source", source])
	out.append(["Audio output", audio])
	return out


## What the open media IS: each stream's codec and its own format, and what the
## input is running at. From VlcPlayer.get_media_info, asked only where the build
## has it (a Quest left on an older vlc-godot would otherwise fail on the call);
## empty until VLC has read the file's streams, which is once it is playing.
static func source_rows(vlc: Object) -> Array:
	if not vlc.has_method("get_media_info"):
		return []
	var info: Dictionary = vlc.call("get_media_info")
	var rows: Array = []
	for t: Dictionary in info.get("tracks", []):
		var codec := str(t.get("codec_name", ""))
		if codec.is_empty():
			codec = str(t.get("codec", "?"))
		elif not str(t.get("codec", "")).is_empty():
			codec += " (%s)" % t["codec"]
		var kbps := int(t.get("bitrate", 0)) / 1000
		match str(t.get("type", "")):
			"video":
				var num := int(t.get("fps_num", 0))
				var den := int(t.get("fps_den", 0))
				rows.append_array([
					["Video codec", codec],
					["Video size", "%d × %d" % [int(t.get("width", 0)), int(t.get("height", 0))]],
					["Frame rate", "%.3f fps" % (float(num) / den) if num > 0 and den > 0 else "—"],
				])
				if int(t.get("sar_num", 0)) > 0 and int(t.get("sar_num", 0)) != int(t.get("sar_den", 0)):
					rows.append(["Pixel aspect", "%d:%d" % [int(t["sar_num"]), int(t["sar_den"])]])
				if kbps > 0:
					rows.append(["Video bitrate", "%d kbit/s" % kbps])
			"audio":
				rows.append_array([
					["Audio codec", codec],
					["Sample rate", "%d Hz" % int(t.get("rate", 0)) if int(t.get("rate", 0)) > 0 else "—"],
					["Channels", str(int(t.get("channels", 0))) if int(t.get("channels", 0)) > 0 else "—"],
				])
				if kbps > 0:
					rows.append(["Audio bitrate", "%d kbit/s" % kbps])
				if not str(t.get("language", "")).is_empty():
					rows.append(["Language", str(t["language"])])
			"text":
				rows.append(["Subtitles", codec])
	if info.has("input_kbps") and float(info["input_kbps"]) > 0.0:
		rows.append(["Input bitrate", "%.0f kbit/s" % float(info["input_kbps"])])
	if int(info.get("lost_pictures", 0)) > 0 or int(info.get("lost_abuffers", 0)) > 0:
		rows.append(["Dropped", "%d pictures, %d audio buffers" % [
			int(info.get("lost_pictures", 0)), int(info.get("lost_abuffers", 0))]])
	if int(info.get("demux_corrupted", 0)) > 0:
		rows.append(["Corrupt packets", str(int(info["demux_corrupted"]))])
	return rows


## A file as the page shows it: its name and its format, from the extension.
static func file_rows(path: String) -> Array:
	if path.is_empty():
		return [["File", "(none)"]]
	return [
		["File", path.get_file()],
		["Format", path.get_extension().to_upper()],
		["Folder", path.get_base_dir()],
	]


## Where a cabled deck's signal goes: the set and input it reaches (found through
## its cords, so a deck with no picture anywhere still names the set it is wired
## to), and any cord in the wrong jack there.
static func output_rows(dev: Node3D, connected_tv: RetroTV) -> Array:
	var tv: RetroTV = connected_tv if is_instance_valid(connected_tv) else null
	var picture := tv != null
	if tv == null:
		for link: Dictionary in AvGraph.links_for(dev):
			var to := (link["in"] as RcaPort).get_device()
			if to is RetroTV and (link["out"] as RcaPort).get_device() == dev:
				tv = to as RetroTV
				break
	if tv == null:
		return [["Showing on", "nothing (no lead to a set)"]]
	var input := tv.input_for_device(dev)
	var rows: Array = [["Showing on", "TV, %s%s" % [
		tv.source_name(input) if input >= 0 else "not on an input",
		"" if picture else " (no picture)"]]]
	if input >= 0:
		var crossed := tv.panel().miswired(input)
		rows.append(["Cords", "crossed: " + ", ".join(crossed) if not crossed.is_empty()
			else "right"])
	return rows
