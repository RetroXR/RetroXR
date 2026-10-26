## Windowed: the Debug tabs of a VCR, a cassette deck and a turntable, filled from
## real media playing. The suite has no media and no libVLC playback, so this is
## what shows the numbers are the file's: a 1080p clip reads 1920 × 1080, a 44.1 kHz
## stereo WAV reads 44100 Hz and 2 channels.
##
##   godot --path RetroXR --resolution 640x520 --position 20,20 \
##     res://Tools/av/media_debug_probe.tscn -- "--video=C:/…/clip.mp4" "--wav=C:/…/tone.wav"
##
## --wav must be a 44.1 kHz stereo WAV (the probe checks for exactly that).
## PNGs land in res://probe_out/media_debug_{vcr,cassette}.png (gitignored).
extends Node3D

const VCR_SCENE := preload("res://Scenes/Objects/appliances/vcr_player.tscn")
const TV_SCENE := preload("res://Scenes/Objects/tv.tscn")
const CABLE_SCENE := preload("res://Scenes/Objects/cables/composite_cable.tscn")
const TAPE_SCENE := preload("res://Scenes/Objects/media/vcr_tape.tscn")
const CASSETTE_DECK := preload("res://Scenes/Objects/appliances/cassette_player.tscn")
const CASSETTE := preload("res://Scenes/Objects/media/audio_cassette.tscn")
const TURNTABLE := preload("res://Scenes/Objects/appliances/record_player.tscn")
const RECORD := preload("res://Scenes/Objects/media/vinyl_record.tscn")
const VCR_UI := preload("res://Scenes/UI/vcr_options_2d.tscn")
const AUDIO_UI := preload("res://Scenes/UI/audio_options_2d.tscn")

var _video := ""
var _wav := ""
var _failed := false


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--video="):
			_video = arg.trim_prefix("--video=")
		elif arg.begins_with("--wav="):
			_wav = arg.trim_prefix("--wav=")
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		print("[md] TIMEOUT")
		get_tree().quit(1))
	if not FileAccess.file_exists(_video) or not FileAccess.file_exists(_wav):
		print("[md] SKIP: need --video= and --wav= files")
		get_tree().quit(0)
		return
	_run()


func _check(cond: bool, what: String) -> void:
	print("[md] %s  %s" % ["PASS" if cond else "FAIL", what])
	if not cond:
		_failed = true


func _row(sections: Array, section: String, label: String) -> String:
	for s: Array in sections:
		if s[0] == section:
			for r: Array in s[1]:
				if r[0] == label:
					return str(r[1])
	return ""


func _dump(tag: String, sections: Array) -> void:
	for s: Array in sections:
		for r: Array in s[1]:
			print("[md]   %-9s %-13s %-20s %s" % [tag, s[0], r[0], r[1]])


func _spawn(scene: PackedScene, at: Vector3) -> Node3D:
	var n := scene.instantiate() as Node3D
	if n is RigidBody3D:
		(n as RigidBody3D).freeze = true
	n.position = at
	add_child(n)
	return n


func _run() -> void:
	# ── VCR ──────────────────────────────────────────────────────────────────
	var vcr := _spawn(VCR_SCENE, Vector3(0, 1, 0)) as VCRPlayer
	var tape := _spawn(TAPE_SCENE, Vector3(0, 2, 0)) as VCRTape
	tape.video_path = _video
	tape.video_label = "PROBE CLIP"
	await _frames(20)
	_dump("vcr-empty", vcr.debug_state())
	_check(_row(vcr.debug_state(), "Tape", "Tape") == "(none in the deck)",
		"an empty VCR says no tape")
	# A deck plays only into a set (VCRPlayer.play), so cable it to one.
	var tv := _spawn(TV_SCENE, Vector3(0, 1, -2)) as RetroTV
	await _frames(30)
	var cable := _spawn(CABLE_SCENE, Vector3(0, 1, -1))
	await _frames(20)
	var names := [["VideoOut", "CompositePort"], ["AudioLOut", "AudioLIn"], ["AudioROut", "AudioRIn"]]
	for c in 3:
		(vcr.get_node(names[c][0]) as RcaPort).pick_up_object(cable.get_node("PlugA%d" % c) as RcaPlug)
		(tv.get_node(names[c][1]) as RcaPort).pick_up_object(cable.get_node("PlugB%d" % c) as RcaPlug)
		await _frames(6)
	await _frames(30)
	_check(vcr.connected_tv == tv, "the VCR is cabled to a set")
	vcr.restore_tape(tape)
	await _frames(10)
	vcr.play()
	var vlc: Object = vcr.get("_vlc")
	var deadline := Time.get_ticks_msec() + 15000
	while Time.get_ticks_msec() < deadline and (vlc == null
			or (vlc.call("get_video_size") as Vector2i).x <= 0 or int(vlc.call("get_audio_rate")) <= 0):
		await get_tree().process_frame
	await _frames(30)
	var dbg := vcr.debug_state()
	_dump("vcr", dbg)
	_check(_row(dbg, "Tape", "Format") == "MP4", "the tape's file is an MP4")
	_check(_row(dbg, "Source", "Video size") == "1920 × 1080",
		"the 1080p clip's own stream is 1920 × 1080: %s" % _row(dbg, "Source", "Video size"))
	_check(_row(dbg, "Source", "Video codec") != "",
		"and has a codec: %s" % _row(dbg, "Source", "Video codec"))
	_check(_row(dbg, "Source", "Frame rate").ends_with("fps"),
		"and a frame rate: %s" % _row(dbg, "Source", "Frame rate"))
	_check(_row(dbg, "Source", "Sample rate").ends_with("Hz"),
		"its own audio has a sample rate: %s" % _row(dbg, "Source", "Sample rate"))
	_check(_row(dbg, "Playback", "State") == "playing", "and it is playing")
	_check(_row(dbg, "Deck", "Showing on") == "TV, COMPOSITE 1",
		"the deck says where it shows: %s" % _row(dbg, "Deck", "Showing on"))
	await _shoot_ui(VCR_UI.instantiate() as VCROptions2D, dbg, "vcr")
	vcr.stop()

	# ── Cassette ─────────────────────────────────────────────────────────────
	var deck := _spawn(CASSETTE_DECK, Vector3(2, 1, 0)) as RetroAudioPlayer
	var cas := _spawn(CASSETTE, Vector3(2, 2, 0))
	cas.set("album_path", _wav)
	await _frames(20)
	deck.restore_media(cas)
	await _frames(10)
	deck.play()
	var dvlc: Object = deck.get("_vlc")
	deadline = Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline and int(dvlc.call("get_audio_rate")) <= 0:
		await get_tree().process_frame
	await _frames(20)
	dbg = deck.debug_state()
	_dump("cassette", dbg)
	_check(_row(dbg, "Media", "In the deck") == "Audio cassette", "the deck names a cassette")
	_check(_row(dbg, "Media", "Format") == "WAV", "its track is a WAV")
	_check(_row(dbg, "Source", "Sample rate") == "44100 Hz",
		"the 44.1 kHz WAV's own rate reads 44100 Hz: %s" % _row(dbg, "Source", "Sample rate"))
	_check(_row(dbg, "Source", "Channels") == "2", "and two channels")
	_check(_row(dbg, "Audio output", "Output").begins_with("48000 Hz"),
		"while the room is fed 48 kHz: %s" % _row(dbg, "Audio output", "Output"))
	_check(_row(dbg, "Media", "Tape at") != "", "a tape says where it is")
	await _shoot_ui(AUDIO_UI.instantiate() as AudioOptions2D, dbg, "cassette")
	deck.stop()

	# ── Turntable ────────────────────────────────────────────────────────────
	var tt := _spawn(TURNTABLE, Vector3(4, 1, 0)) as RetroAudioPlayer
	var lp := _spawn(RECORD, Vector3(4, 2, 0))
	lp.set("album_path", _wav)
	await _frames(20)
	tt.restore_media(lp)
	await _frames(10)
	dbg = tt.debug_state()
	_dump("turntable", dbg)
	_check(_row(dbg, "Media", "In the deck") == "Vinyl record", "the turntable names a record")
	_check(_row(dbg, "Deck", "Speed").contains("rpm"), "and its speed: %s" % _row(dbg, "Deck", "Speed"))
	_check(_row(dbg, "Deck", "Arm") != "", "and its arm: %s" % _row(dbg, "Deck", "Arm"))

	print("[md] RESULT=%s" % ("FAIL" if _failed else "PASS"))
	get_tree().quit(1 if _failed else 0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## The menu's Debug tab, filled with `sections`, photographed at the panel's size.
func _shoot_ui(ui: Control, sections: Array, name: String) -> void:
	var sv := SubViewport.new()
	sv.size = Vector2i(550, 500)
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sv)
	sv.add_child(ui)
	await _frames(3)
	ui.call("populate_debug", sections)
	(ui.get("_tabs") as TabContainer).current_tab = (ui.get("_tabs") as TabContainer).get_tab_count() - 1
	await _frames(12)
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://probe_out")
	sv.get_texture().get_image().save_png("res://probe_out/media_debug_%s.png" % name)
	print("[md] saved media_debug_%s.png" % name)
	sv.queue_free()
