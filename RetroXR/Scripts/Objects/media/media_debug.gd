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
	var rate := int(vlc.call("get_audio_rate"))
	var channels := int(vlc.call("get_audio_channels"))
	var audio: Array = [
		["Sample rate", "%d Hz" % rate if rate > 0 else "—"],
		["Channels", str(channels) if channels > 0 else "—"],
		["Audio tracks", "%d (current id %d)" % [tracks.size(), int(vlc.call("get_audio_track"))]
			if not tracks.is_empty() else "—"],
		["Buffered", "%d ms" % int(vlc.call("get_audio_backlog_ms"))],
		["A/V lead", "%d ms (target %d)" % [int(vlc.call("get_audio_lead_ms")),
			int(vlc.call("get_audio_lead_target_ms"))]],
	]
	return [["Playback", playback], ["Audio stream", audio]]


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
