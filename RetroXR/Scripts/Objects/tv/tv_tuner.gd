## TVTuner — the set's built-in tuner: it plays ONE channel through libVLC.
##
## Owned by RetroTV, which decides when it is on screen. The tuner never touches
## the screen mesh itself, so all screen arbitration stays in one place (tv.gd's
## _update_screen_source and _update_crt already fight over that surface and do
## not need a third party).
##
## What it can tune is not its own. The channel list belongs to the aerial on the
## far end of the set's coax socket (TVLineup, owned by an Antenna) and is handed
## over with set_lineup; with no aerial there is no list and nothing to play. This
## half used to own discovery and channels.json as well, which is how every set in
## the room had broadcast channels with nothing plugged into it.
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

## The aerial's list, read through rather than copied: discovery replaces it
## wholesale, and a copy would go on naming channels the box no longer offers.
var channels: Array[Dictionary]:
	get:
		return _lineup.channels if is_instance_valid(_lineup) else _no_channels
var current_index: int = -1

var _vlc: Object = null
var _lineup: TVLineup = null
var _no_channels: Array[Dictionary] = []
var _emitter: SpatialAudioEmitter = null

var _static_material: ShaderMaterial = null

var _active := false
var _error := ""
var _tuning := false
# A tune waiting on libVLC to finish coming up; see _start_current.
var _pending_tune := false
# The stream the viewer asked for, so a re-sorted list can be followed by station
# rather than by slot. See _on_lineup_changed.
var _tuned_url := ""
var _since_tune := 0.0
var _last_frames := 0
var _since_frame := 0.0
var _have_picture := false
var _volume_linear := 1.0
var _muted := false


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

## Take the list of whatever aerial the set's coax socket now reaches, or null
## when it reaches none. Called by RetroTV whenever a plug moves at either end.
func set_lineup(lineup: TVLineup) -> void:
	if _lineup == lineup:
		return
	if is_instance_valid(_lineup) 			and _lineup.channels_changed.is_connected(_on_lineup_changed):
		_lineup.channels_changed.disconnect(_on_lineup_changed)
	_lineup = lineup
	if is_instance_valid(_lineup):
		_lineup.channels_changed.connect(_on_lineup_changed)
	_on_lineup_changed()


func lineup() -> TVLineup:
	return _lineup if is_instance_valid(_lineup) else null


## The list moved under the tuned channel: discovery answered, the panel refreshed,
## or the aerial was pulled.
##
## Followed by URL, not by index. Discovery replaces the cached lineup wholesale and
## re-sorts, so the same index is routinely a different station a second later — and
## a viewer watching 4.1 should go on watching 4.1 rather than be restarted onto
## whatever slid into its slot.
func _on_lineup_changed() -> void:
	var was := _tuned_url
	var found := -1
	if not was.is_empty():
		for i in channels.size():
			if str(channels[i].get("url", "")) == was:
				found = i
				break
	if found >= 0:
		current_index = found
	elif channels.is_empty():
		current_index = -1
		_tuned_url = ""
		if _vlc:
			_vlc.stop()
		_have_picture = false
		_tuning = false
		_pending_tune = false
	else:
		current_index = clampi(current_index, 0, channels.size() - 1)
		if _active:
			_start_current()
	var fault := _lineup.fault_text() if is_instance_valid(_lineup) else ""
	if not fault.is_empty():
		_set_error(fault)
	elif _error.begins_with("TUNER") or _error.begins_with("NO CHANNELS") 			or _error.begins_with("CHANNEL LIST"):
		_set_error("")
	channels_changed.emit()


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
	_tuned_url = str(ch.get("url", ""))
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

## Called by the TV when the dial lands on (or leaves) one of the aerial's channels.
func set_active(active: bool) -> void:
	if _active == active:
		return
	_active = active
	set_process(active)
	if active:
		if is_instance_valid(_lineup) and not _lineup.is_loaded():
			_lineup.reload_channels()
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
