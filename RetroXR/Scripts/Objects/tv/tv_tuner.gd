## TVTuner — the set's built-in TV input: a channel list and a libVLC stream.
##
## Owned by RetroTV, which decides when it is on screen. The tuner never touches
## the screen mesh itself, so all screen arbitration stays in one place (tv.gd's
## _update_screen_source and _update_crt already fight over that surface and do
## not need a third party).
##
## Two states, and which one is current is the whole state machine:
##   picture — the decoded frame, offered as a texture for the set to sample
##   static  — tv_static.gdshader, shown for every failure, with the reason in
##             the OSD
class_name TVTuner
extends Node

const STATIC_SHADER := preload("res://Shaders/tv_static.gdshader")

## Emitted when the channel list changes (discovery finished, refresh, load).
signal channels_changed
## Emitted when the tuned channel or the error text changes; the TV puts `banner`
## in the OSD. Empty banner means "nothing to say".
signal status_changed(banner: String)

## A stream that has not produced a picture in this long is not going to. Covers
## the case libVLC does not report at all: an unreachable host answers with
## MediaPlayerStopped and no error event, so a timeout is the only honest test.
const TUNE_TIMEOUT := 8.0
## Frames must keep arriving. A source that dies mid-programme leaves the last
## picture frozen on the texture, which is otherwise indistinguishable from a
## still frame in the content.
const STALL_TIMEOUT := 6.0

var channels: Array[Dictionary] = []
var current_index: int = -1

var _vlc: Object = null
var _hdhr: HDHomeRun = null
var _emitter: SpatialAudioEmitter = null

var _static_material: ShaderMaterial = null

var _active := false
var _error := ""
var _tuning := false
# A tune waiting on libVLC to finish coming up; see _start_current.
var _pending_tune := false
var _since_tune := 0.0
var _last_frames := 0
var _since_frame := 0.0
var _have_picture := false
var _volume_linear := 1.0
var _muted := false
var _cfg: TVChannels = null
# What discovery reported, for the options panel's status line. Kept separate
# from _error: a missing tuner is worth saying in the panel but is not a fault
# on the glass while a hand-written stream list is playing perfectly well.
var _tuner_info: Dictionary = {}
var _tuner_error := ""
# Whether a look is actually in flight. Without it the status line cannot tell
# "searching" from "never started", and reports the former for both.
var _searching := false


func _ready() -> void:
	set_process(false)

	if ClassDB.class_exists("VlcPlayer"):
		_vlc = ClassDB.instantiate("VlcPlayer")
		# error fires for a decode failure but NOT for an unreachable host --
		# libVLC 3 answers that with Stopped alone. Both are wired, and the
		# frame timeout above catches what neither reports.
		_vlc.error.connect(_on_vlc_error)
		_vlc.stopped.connect(_on_vlc_stopped)
		# This node is built by the first press of SOURCE, which activates it in
		# the same call, so the thread has only the frames the tune spends on
		# static to work in -- but that is the whole of the stall it removes.
		_vlc.warm_up()
	else:
		push_error("TVTuner: VlcPlayer extension not loaded — TV input unavailable")

	_hdhr = HDHomeRun.new()
	_hdhr.name = "HDHomeRun"
	_hdhr.lineup_ready.connect(_on_lineup_ready)
	_hdhr.discovery_failed.connect(_on_discovery_failed)
	add_child(_hdhr)

	_emitter = SpatialAudioEmitter.new()
	_emitter.name = "SpatialAudioEmitter"
	_emitter.unit_size = 3.0
	_emitter.max_distance = 15.0
	_emitter.speaker_separation = 0.25
	_emitter.directivity = SpatialAudioEmitter.SPEAKER_DIRECTIVITY
	add_child(_emitter)

	_static_material = ShaderMaterial.new()
	_static_material.shader = STATIC_SHADER


# ── channel list ──────────────────────────────────────────────────────────────

## Read channels.json and, if it names a tuner, go and find it. Safe to call
## repeatedly; the panel's Refresh button does exactly this.
func reload_channels() -> void:
	_cfg = TVChannels.load_config()
	channels.clear()

	# Show the cached lineup immediately so a list exists before the network
	# answers -- and so a cold start with the tuner asleep still has channels.
	var cache := HDHomeRun.load_cache()
	if cache.has("channels"):
		for c: Variant in cache["channels"]:
			if c is Dictionary:
				channels.append(c as Dictionary)

	for c in _cfg.stream_channels:
		channels.append(c)
	_sort_channels()
	channels_changed.emit()

	# A broken file is worth saying out loud. A MISSING one is not: discovery
	# needs no configuration at all, so the normal case for a fresh install is
	# no file and a tuner found anyway.
	if _cfg.status == TVChannels.Status.PARSE_ERROR:
		_set_error("CHANNEL LIST ERROR\n%s" % _cfg.error_message)

	# Always go looking. This used to be gated on the file naming a tuner, which
	# dated from before broadcast discovery worked -- and meant a machine with no
	# channels.json (every fresh install, and every headset) never even started
	# looking, then sat on "Looking for a tuner..." forever because nothing ever
	# reported success or failure.
	_searching = true
	_hdhr.find_lineup(_cfg.tuner_host(), _cfg.tuner_auto())


# ── tuner configuration (the options panel's Tuner box) ───────────────────────

func tuner_auto() -> bool:
	return _cfg.tuner_auto() if _cfg else true


func tuner_host() -> String:
	return _cfg.tuner_host() if _cfg else ""


## The address discovery actually reached, so the panel can show it even when the
## user never typed one.
func discovered_host() -> String:
	return str(_tuner_info.get("host", ""))


## One already-worded line for the panel's status label.
func tuner_status_line() -> String:
	if not _tuner_error.is_empty():
		return _tuner_error
	if _tuner_info.is_empty():
		return "Looking for a tuner…" if _searching else "No tuner searched for yet"
	return "%s — %s — %d tuner(s) — %d channels" % [
		_tuner_info.get("name", "HDHomeRun"),
		_tuner_info.get("host", "?"),
		int(_tuner_info.get("tuners", 0)),
		_hdhr_channel_count(),
	]


func _hdhr_channel_count() -> int:
	var n := 0
	for c in channels:
		if str(c.get("source", "")) == "hdhomerun":
			n += 1
	return n


## Persist auto/address to channels.json and go looking again.
func set_tuner_config(auto: bool, host: String) -> void:
	if _cfg == null:
		_cfg = TVChannels.load_config()
	if _cfg.tuner_auto() == auto and _cfg.tuner_host() == host.strip_edges():
		return
	_cfg.set_tuner(auto, host)
	_tuner_info = {}
	_tuner_error = ""
	_searching = true
	_hdhr.find_lineup(_cfg.tuner_host(), _cfg.tuner_auto())
	channels_changed.emit()


func _on_lineup_ready(found: Array, info: Dictionary) -> void:
	_searching = false
	_tuner_info = info
	_tuner_error = ""
	# Replace the tuner's channels wholesale; hand-written streams are untouched.
	var kept: Array[Dictionary] = []
	for c in channels:
		if str(c.get("source", "")) != "hdhomerun":
			kept.append(c)
	channels = kept
	for c: Variant in found:
		if c is Dictionary:
			channels.append(c as Dictionary)
	_sort_channels()
	if _error.begins_with("TUNER") or _error.begins_with("NO CHANNELS"):
		_set_error("")
	channels_changed.emit()


func _on_discovery_failed(message: String) -> void:
	_searching = false
	_tuner_error = message
	_tuner_info = {}
	# Only complain on screen if there is nothing else to watch -- a hand-written
	# stream list is a perfectly good TV input without any tuner.
	if channels.is_empty():
		_set_error("TUNER NOT FOUND\n%s" % message.to_upper())
	channels_changed.emit()


## Broadcast numbering is "4.1", "10.2" — sort on the pair, not the string, or
## channel 10 lands between 1 and 2.
func _sort_channels() -> void:
	channels.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa := _number_key(str(a.get("number", "")))
		var pb := _number_key(str(b.get("number", "")))
		if pa != pb:
			return pa < pb
		return str(a.get("name", "")).naturalnocasecmp_to(str(b.get("name", ""))) < 0)


func _number_key(number: String) -> float:
	if number.is_empty():
		return 1e9          # unnumbered entries sort last, not first
	var parts := number.split(".")
	var major := float(parts[0]) if parts[0].is_valid_float() else 1e8
	var minor := 0.0
	if parts.size() > 1 and parts[1].is_valid_float():
		minor = float(parts[1])
	return major * 1000.0 + minor


# ── tuning ────────────────────────────────────────────────────────────────────

func tune(index: int) -> void:
	if channels.is_empty():
		return
	current_index = clampi(index, 0, channels.size() - 1)
	_start_current()


func channel_up() -> void:
	if channels.is_empty():
		return
	if current_index < 0:
		tune(0)
	else:
		tune((current_index + 1) % channels.size())


func channel_down() -> void:
	if channels.is_empty():
		return
	if current_index < 0:
		tune(channels.size() - 1)
	else:
		tune((current_index - 1 + channels.size()) % channels.size())


func current_channel() -> Dictionary:
	if current_index < 0 or current_index >= channels.size():
		return {}
	return channels[current_index]


## The tuner is the deck that actually earns the budget: its sources are URLs, and
## a host that has stopped answering makes libvlc_media_player_stop block for as
## long as it takes to give up. Freeing the node used to pay that on the main
## thread, mid-room-change. See VlcPlayer::shutdown.
func _exit_tree() -> void:
	if _vlc:
		_vlc.shutdown()


func _start_current() -> void:
	if _vlc == null:
		_set_error("VIDEO ENGINE UNAVAILABLE")
		return
	var ch := current_channel()
	if ch.is_empty():
		return
	_vlc.stop()
	_have_picture = false
	_tuning = true
	_since_tune = 0.0
	_since_frame = 0.0
	_last_frames = 0
	_set_error("")
	status_changed.emit(_banner())

	# The first open() in the process builds the libVLC instance, and doing that
	# walks the whole plugin tree -- long enough to drop frames, and it landed on
	# the frame the viewer pressed SOURCE. warm_up() is already running it on its
	# own thread, so hold the tune until it lands: the screen shows static and the
	# channel banner for the stream's own buffering anyway, and this hides inside
	# that.
	if not _vlc.is_ready():
		_pending_tune = true
		return
	_open_current()


func _open_current() -> void:
	_pending_tune = false
	var ch := current_channel()
	if ch.is_empty():
		return
	if not _vlc.open(str(ch["url"]), false):
		_set_error("CANNOT TUNE\n%s" % str(ch.get("name", "")).to_upper())
		return
	_vlc.play()
	# Full internal gain; the level the viewer hears is the set's own knob,
	# applied on the emitter.
	_vlc.set_volume(100)


func _on_vlc_error() -> void:
	if _active:
		_set_error("NO SIGNAL\n%s" % str(current_channel().get("name", "")).to_upper())


func _on_vlc_stopped() -> void:
	# Stopped while we still expect a picture means the stream never opened.
	# Stopped after we asked it to is normal and must not paint an error.
	if _active and _tuning and not _have_picture:
		_set_error("NO SIGNAL\n%s" % str(current_channel().get("name", "")).to_upper())


# ── activation ────────────────────────────────────────────────────────────────

## Called by the TV when the SOURCE button selects (or leaves) the TV input.
func set_active(active: bool) -> void:
	if _active == active:
		return
	_active = active
	set_process(active)
	if active:
		if channels.is_empty() and _cfg == null:
			reload_channels()
		if current_index < 0 and not channels.is_empty():
			current_index = 0
		if not channels.is_empty():
			_start_current()
		else:
			status_changed.emit(_banner())
	else:
		if _vlc:
			_vlc.stop()
		_have_picture = false
		_tuning = false
		_pending_tune = false
		if _emitter:
			_emitter.flush()
			_emitter.clear_speaker_positions()
			_emitter.clear_emit_position()
			_emitter.clear_emit_direction()


func is_active() -> bool:
	return _active


func _process(delta: float) -> void:
	if _vlc == null:
		return
	if _pending_tune:
		if not _vlc.is_ready():
			return
		# The tune clock starts here: what came before it was libVLC coming up,
		# and charging that to TUNE_TIMEOUT would report a fault on the channel.
		_since_tune = 0.0
		_open_current()
		return
	_vlc.update_frame()
	_pump_audio()

	var frames: int = _vlc.get_frame_count()
	if frames > _last_frames:
		_last_frames = frames
		_since_frame = 0.0
		if not _have_picture:
			_have_picture = true
			_tuning = false
			_set_error("")
			status_changed.emit(_banner())
	else:
		_since_frame += delta

	if _tuning:
		_since_tune += delta
		if _since_tune > TUNE_TIMEOUT and _error.is_empty():
			_tuning = false
			_set_error("NO SIGNAL\n%s" % str(current_channel().get("name", "")).to_upper())
	elif _have_picture and _since_frame > STALL_TIMEOUT:
		_have_picture = false
		_set_error("SIGNAL LOST\n%s" % str(current_channel().get("name", "")).to_upper())


func _pump_audio() -> void:
	if _emitter == null or not _have_picture:
		return
	var want := _emitter.frames_wanted()
	if want <= 0:
		return
	var frames: PackedVector2Array = _vlc.read_audio(want)
	if frames.size() > 0:
		_emitter.push_stereo(frames)


# ── what the TV puts on the glass ─────────────────────────────────────────────

## The decoded frame, or null when there is nothing to show and the set should
## put this tuner's static up instead.
##
## A TEXTURE, not a material: the set samples every picture into a display
## material of its own, and handing it a finished material was what kept the
## aspect fit, the tube stage and the OSD off a broadcast. update_frame()
## replaces the ImageTexture outright on a resolution change, so this is read
## per frame rather than cached.
func picture_texture() -> Texture2D:
	if not _have_picture or _vlc == null:
		return null
	return _vlc.get_texture() as Texture2D


## Snow, for every state that has no picture. The set installs this one directly:
## static is generated across the whole tube whatever shape a picture would have
## been, so there is nothing for it to sample and nothing to fit.
func static_material() -> ShaderMaterial:
	return _static_material


func has_picture() -> bool:
	return _have_picture


func error_text() -> String:
	return _error


## The line the TV shows in its OSD: the fault if there is one, else the channel.
func status_banner() -> String:
	return _banner()


func _banner() -> String:
	if not _error.is_empty():
		return _error
	var ch := current_channel()
	if ch.is_empty():
		return ""
	var number := str(ch.get("number", ""))
	var label := str(ch.get("name", "")).to_upper()
	return ("%s  %s" % [number, label]) if not number.is_empty() else label


func _set_error(text: String) -> void:
	if _error == text:
		return
	_error = text
	status_changed.emit(_banner())


# ── audio routing ─────────────────────────────────────────────────────────────

func set_volume(linear: float) -> void:
	_volume_linear = linear
	if _emitter:
		_emitter.set_volume(0.0 if _muted else _volume_linear)


func set_muted(muted: bool) -> void:
	_muted = muted
	set_volume(_volume_linear)


func set_channel_mode(mode: int) -> void:
	if _emitter:
		_emitter.set_channel_mode(mode)


## Put the sound where the picture is, aimed the way the tube points.
func emit_through(tv: Node3D) -> void:
	if _emitter == null:
		return
	if tv.has_method("get_speaker_positions"):
		var sp: PackedVector3Array = tv.get_speaker_positions()
		if sp.size() >= 2:
			_emitter.set_speaker_positions(sp[0], sp[1])
	else:
		_emitter.set_emit_position(tv.global_position)
	# Omnidirectional once the set has sent its sound to external speakers: they
	# point wherever a hand put them, not the way the picture faces.
	if tv.has_method("is_sound_external") and tv.is_sound_external():
		_emitter.clear_emit_direction()
	elif tv.has_method("get_screen_normal"):
		_emitter.set_emit_direction(tv.get_screen_normal(), tv.get_screen_up())
