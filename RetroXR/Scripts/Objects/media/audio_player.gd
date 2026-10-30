## RetroAudioPlayer — shared base for the pickable CD and cassette players. Plays
## an inserted audio album (a folder of tracks, or a single audio file) through
## the libVLC-backed VlcPlayer GDExtension — the same engine as the VCR/DVD, but
## audio-only and self-contained: the sound emanates from the unit's own
## spatialised AudioStreamPlayer3D, so no TV or cable is needed.
##
## Subclasses (CDPlayer / CassettePlayer) provide the scene + button set. The CD
## has Prev/Next track buttons (and the remote shows them); the cassette is a
## linear tape (play/pause/stop/ff/rew only, tracks auto-advance, no skip).
##
## Transport is host-authoritative in a netplay session (mirrors VCR/DVD): a
## client's button/remote intent is forwarded to the host, which executes it and
## broadcasts the transport state; every peer plays its own local copy of the
## album (verify-by-name — albums are never transferred; see NetObjectSync).
class_name RetroAudioPlayer
extends XRToolsPickable

## Human-readable label shown above the unit.
@export var player_label: String = "AUDIO"

## Fast-forward / rewind scan rate: seconds of audio traversed per real second.
@export var scan_speed: float = 8.0

# The snap-zone group the media item must belong to (set by subclass _ready).
@warning_ignore("unused_private_class_variable")
var _media_group: String = ""

# Runtime state
var album_path: String = ""
var is_playing: bool = false
var _paused: bool = false
var _tracks: PackedStringArray = PackedStringArray()
var _track_idx: int = 0

# FF/REW scan: 0 = normal, +1 = forward, -1 = reverse. The player keeps playing
# (so it presents audio position) but we jump the position in throttled steps and
# mute, exactly like the VCR's video scan.
var _scan_dir: int = 0
var _scan_accum: float = 0.0
## Seconds into the selected track that the next play() carries on from, for a
## medium that keeps its place (a tape; see _tape). 0 for a disc or a record,
## which start a track at its start. It waits here because a seek means nothing
## until the track is open and its length is known.
var _resume_at: float = 0.0
## Each track's size on disk, beside _tracks: what a tape's progress is weighed by.
var _track_bytes: PackedInt64Array = PackedInt64Array()
const SCAN_SEEK_INTERVAL := 0.08
## If Prev is pressed past this point in a track, it restarts the track instead
## of skipping to the previous one (standard CD behaviour).
const PREV_RESTART_SEC := 3.0

var _vlc: Object = null                 # VlcPlayer (GDExtension)
var _emitter: SpatialAudioEmitter = null
var _volume_linear: float = 1.0

var _snapped_media: Node3D = null

## A deck with level meters (the RETRO XR cassette deck) sets this, and `levels` then holds the peak of what played,
## each channel 0..1, falling back over about half a second. Off, nothing is measured.
var wants_levels := false
var levels := Vector2.ZERO
const LEVEL_FALL := 1.8           # per second

@warning_ignore("unused_private_class_variable")
@onready var _media_slot: XRToolsSnapZone = $MediaSlot
@onready var _name_label: Label3D = $NameLabel
@onready var _play_button: VRButton = $PlayButton
@onready var _pause_button: VRButton = $PauseButton
@onready var _stop_button: VRButton = $StopButton
@onready var _rewind_button: VRButton = get_node_or_null("RewindButton")
@onready var _ff_button: VRButton = get_node_or_null("FastForwardButton")
@onready var _prev_button: VRButton = get_node_or_null("PrevButton")
@onready var _next_button: VRButton = get_node_or_null("NextButton")


func _ready() -> void:
	super._ready()
	add_to_group("audio_player")
	_float_lock = FloatLock.attach(self, ignore_gravity)
	# Physical media handling (how the disc/tape loads, ejects, rides, and collides)
	# is provided by the subclass: the cassette front-loads through a MediaSlot like
	# the VCR; the CD drops into a MediaTray (flip-up lid) like a PlayStation. Both
	# call _media_loaded/_media_unloaded for the transport-side state.
	_setup_loader()
	_play_button.button_pressed.connect(_on_play_pressed)
	_pause_button.button_pressed.connect(_on_pause_pressed)
	_stop_button.button_pressed.connect(_on_stop_pressed)
	_play_button.set_color(Color(0.0, 0.9, 0.0))     # green
	_pause_button.set_color(Color(0.9, 0.8, 0.0))     # amber
	_stop_button.set_color(Color(0.9, 0.1, 0.1))      # red
	# Scan is optional hardware: a turntable has no FF/REW at all — you move the
	# needle instead. Same shape as prev/next below.
	if _rewind_button:
		_rewind_button.button_pressed.connect(_on_rewind_pressed)
		_rewind_button.set_color(Color(0.1, 0.4, 0.9))    # blue
	if _ff_button:
		_ff_button.button_pressed.connect(_on_ff_pressed)
		_ff_button.set_color(Color(0.1, 0.4, 0.9))        # blue
	if _prev_button:
		_prev_button.button_pressed.connect(_on_prev_pressed)
		_prev_button.set_color(Color(0.5, 0.5, 0.55))
	if _next_button:
		_next_button.button_pressed.connect(_on_next_pressed)
		_next_button.set_color(Color(0.5, 0.5, 0.55))

	if ClassDB.class_exists("VlcPlayer"):
		_vlc = ClassDB.instantiate("VlcPlayer")
		_vlc.finished.connect(_on_track_finished)
		# Build the libVLC instance on its own thread now. Left to the first open(),
		# it walks the whole plugin tree on the main thread, a second-long freeze on
		# the first press of play.
		_vlc.warm_up()
	else:
		push_error("[RetroAudioPlayer] VlcPlayer extension not loaded — audio playback unavailable")

	_setup_audio()
	_update_status()


## The menu's Debug tab: the record, tape or disc in the deck, what the player is
## doing with it and the audio it decodes. A deck adds its own mechanics through
## _debug_deck_rows (a turntable's speed and arm). See DebugRows for the shape.
func debug_state() -> Array:
	var media_rows: Array = []
	if not is_instance_valid(_snapped_media):
		media_rows.append(["In the deck", "(nothing)"])
	else:
		media_rows.append(["In the deck", _media_word(_snapped_media)])
		media_rows.append(["Album", album_path.get_file() if not album_path.is_empty()
			else "(none)"])
		media_rows.append(["Track", "%d of %d" % [_track_idx + 1, _tracks.size()]
			if not _tracks.is_empty() else "—"])
		var path := _tracks[_track_idx] if _track_idx < _tracks.size() else ""
		media_rows.append_array(MediaDebug.file_rows(path))
		var tape := _tape()
		if tape != null:
			media_rows.append(["Tape at", "%s (%.1f%% of the tape)" % [
				MediaDebug.time_text(int(float(tape.get("tape_time")) * 1000.0), true),
				float(tape.get("tape_progress")) * 100.0 if "tape_progress" in tape else 0.0]])
	var out: Array = [["Media", media_rows]]
	out.append_array(MediaDebug.vlc_sections(_vlc, false))
	var deck: Array = [["Deck", player_label]]
	deck.append_array(_debug_deck_rows())
	deck.append(["Volume", "%d%%" % roundi(_volume_linear * 100.0)])
	out.append(["Deck", deck])
	return out


## A deck's own mechanics for its Debug tab, as [label, value] rows.
func _debug_deck_rows() -> Array:
	return []


## What kind of medium a node is, in a word.
static func _media_word(media: Node) -> String:
	if media is VinylRecord:
		return "Vinyl record"
	if media is AudioCassette:
		return "Audio cassette"
	if media is AudioDisc:
		return "Compact disc"
	return String(media.name)


## Whether this player offers manual track skipping (CD yes, cassette no). Read by
## the TV remote to pick its row set and by the net layer to gate skip commands.
func has_track_skip() -> bool:
	return _prev_button != null


## Whether this deck can scan (FF/REW). A tape and a CD can; a turntable cannot —
## there is no such control on one, you move the needle. Read by the TV remote to
## grey those two cells, and enforced in the handlers so a remote or a stale peer's
## command cannot scan a deck that has no scan.
func has_scan() -> bool:
	return _ff_button != null


## True while playback is paused (used by the TV remote's play/pause cell).
func is_paused() -> bool:
	return _paused


## One line in the log for something done to the deck: a button pressed, a
## cassette, CD or record going in or out, what it opened to play. Playing well prints nothing
## else, so this is how a log shows what was tried before whatever went wrong.
func _log_event(what: String) -> void:
	print("[%s] %s: %s" % [_log_tag(), name, what])


## The deck's name in those lines; each deck says its own.
func _log_tag() -> String:
	return "AudioPlayer"


## Build the spatialised audio player fed by VlcPlayer's PCM ring buffer. As a
## child of the (pickable) unit it follows the device around automatically.
## The distance law's reference (m) for the deck's own speakers; a sink with its own (get_audio_unit_size: headphones,
## or a set whose jack has headphones in it) replaces it while it carries the sound.
const UNIT_SIZE := 2.0


func _setup_audio() -> void:
	_emitter = SpatialAudioEmitter.new()
	_emitter.name = "SpatialAudioEmitter"
	_emitter.unit_size = UNIT_SIZE
	_emitter.max_distance = 12.0
	# A hi-fi has two speakers a little way apart; hearing them separately is
	# most of what makes it feel like an object in the room.
	_emitter.speaker_separation = 0.18
	add_child(_emitter)


func _process(delta: float) -> void:
	if _vlc:
		_vlc.update_frame()
		_pump_audio()
	_follow_sink()
	_update_scan(delta)
	_resume_tape()
	_note_tape()


# --- A medium that keeps its place (a tape) ---

## The medium in the deck if it keeps its place, else null. A cassette does: it
## has the fields. A disc and a record do not, and none of this touches them.
func _tape() -> Node:
	if is_instance_valid(_snapped_media) and "tape_time" in _snapped_media:
		return _snapped_media
	return null


## Take up where a tape was left: its track, and how far into it. Called as the
## medium is loaded, with the track list already built.
func _take_tape_place(media: Node) -> void:
	_resume_at = 0.0
	if media == null or not ("tape_time" in media) or _tracks.is_empty():
		return
	_track_idx = clampi(int(media.get("tape_track")), 0, _tracks.size() - 1)
	_resume_at = maxf(0.0, float(media.get("tape_time")))


## Seek to where the tape was, once the track play() opened knows its length.
func _resume_tape() -> void:
	if _resume_at <= 0.0 or not is_playing:
		return
	if _vlc_length_sec() <= 0.0:
		return
	_vlc_seek_sec(_resume_at)
	_resume_at = 0.0


## Write the tape's place back onto it, every frame it is in a deck. While
## stopped the place is left as it was, which is the point: a stopped tape has
## not moved.
func _note_tape() -> void:
	var tape := _tape()
	if tape == null:
		return
	if not is_playing or _resume_at > 0.0:
		tape.set("tape_speed", 0.0)
		return
	var at := _vlc_time_sec()
	var length := _vlc_length_sec()
	tape.set("tape_track", _track_idx)
	tape.set("tape_time", at)
	if length > 0.0:
		tape.set("tape_progress", album_progress(_track_bytes, _track_idx, at / length))
	if _paused and _scan_dir == 0:
		tape.set("tape_speed", 0.0)
	else:
		tape.set("tape_speed", scan_speed * float(_scan_dir) if _scan_dir != 0 else 1.0)


## How far through an album a point is, 0 to 1: `into` (0 to 1) of track `idx`,
## the tracks weighed by `bytes`, their sizes on disk. With no sizes to go by
## every track counts the same.
static func album_progress(bytes: PackedInt64Array, idx: int, into: float) -> float:
	var count := bytes.size()
	if count == 0:
		return 0.0
	idx = clampi(idx, 0, count - 1)
	into = clampf(into, 0.0, 1.0)
	var total := 0.0
	var before := 0.0
	for i in count:
		total += float(bytes[i])
		if i < idx:
			before += float(bytes[i])
	if total <= 0.0:
		return (float(idx) + into) / float(count)
	return clampf((before + float(bytes[idx]) * into) / total, 0.0, 1.0)


## Drain decoded PCM from VlcPlayer into the generator (fills only what's free).
##
## Stops dead while paused. Pausing the source does not stop the sound on its
## own: libVLC has handed over a second or more of PCM by then, and it keeps
## playing out of the ring until the drain stops as well.
func _pump_audio() -> void:
	if _emitter == null or _paused:
		return
	# frames_wanted, not "all free space": queue depth is latency.
	var want := _emitter.frames_wanted()
	if want <= 0:
		return
	var frames: PackedVector2Array = _vlc.read_audio(want)
	if frames.size() > 0:
		_emitter.push_stereo(frames)
		if wants_levels:
			_measure(frames)


## The peak of this batch of PCM, each channel, over what the meters already show falling back.
func _measure(frames: PackedVector2Array) -> void:
	var peak := Vector2.ZERO
	for f in frames:
		peak = Vector2(maxf(peak.x, absf(f.x)), maxf(peak.y, absf(f.y)))
	var fall := LEVEL_FALL * get_process_delta_time()
	levels = Vector2(maxf(levels.x - fall, peak.x), maxf(levels.y - fall, peak.y)).clampf(0.0, 1.0)


# --- Position helpers (VlcPlayer reports ms / 0..1) ---

func _vlc_time_sec() -> float:
	return (float(_vlc.get_time()) / 1000.0) if _vlc else 0.0


func _vlc_length_sec() -> float:
	if _vlc == null:
		return -1.0
	var ms: int = _vlc.get_length()
	return (float(ms) / 1000.0) if ms > 0 else -1.0


func _vlc_seek_sec(sec: float) -> void:
	if _vlc == null:
		return
	var length := _vlc_length_sec()
	if length > 0.0:
		_vlc.set_position(clampf(sec / length, 0.0, 1.0))


## While scanning, jump the position forward/back in throttled steps. Hitting
## either end of the current track stops the scan and holds there.
func _update_scan(delta: float) -> void:
	if _scan_dir == 0 or not is_playing:
		return
	_scan_accum += delta
	if _scan_accum < SCAN_SEEK_INTERVAL:
		return
	var length := _vlc_length_sec()
	var pos := _vlc_time_sec() + _scan_accum * scan_speed * float(_scan_dir)
	_scan_accum = 0.0
	if pos <= 0.0:
		_vlc_seek_sec(0.0)
		_end_scan_hold()
	elif length > 0.0 and pos >= length:
		_vlc_seek_sec(length)
		_end_scan_hold()
	else:
		_vlc_seek_sec(pos)


func _end_scan_hold() -> void:
	_scan_dir = 0
	if _vlc:
		_vlc.set_paused(true)
	_paused = true
	_apply_volume()
	_update_status()


# --- Media load/unload (called by the subclass's loader) ---

## Install the physical media loader — MediaSlot for the cassette, MediaTray for
## the CD. Every deck supplies its own; there is no default.
func _setup_loader() -> void:
	pass


## Media accepted into the deck (loader owns the physical ride + collision). Reads
## the album, resets tracks, reports the insert. Offline, auto-starts; in a session
## playback is host-authoritative (transport commands / state broadcast) like DVD/VCR.
func _media_loaded(media: Node3D) -> void:
	_snapped_media = media
	if media.has_method("get_album_path"):
		album_path = media.get_album_path()
	_log_event("in: %s" % album_path)
	_track_idx = 0
	_rebuild_tracks()
	_take_tape_place(media)
	NetworkManager.report_event(NetEvents.Event.EV_AUDIO_INSERT,
		{"player": self, "media": media, "yaw": media_seat_yaw()})
	if _autoplay_on_load() and not NetworkManager.is_active():
		play()
	_update_status()


## Whether inserting media auto-starts playback offline. The cassette does (it
## front-loads and plays); the CD waits for the lid to close over the disc.
func _autoplay_on_load() -> bool:
	return true


## Media left the deck (ejected / lid opened and taken). Stops and clears state.
func _media_unloaded() -> void:
	# A tape leaves with its place as last written, and is still from here on.
	var tape := _tape()
	if tape != null:
		tape.set("tape_speed", 0.0)
	_snapped_media = null
	_resume_at = 0.0
	stop()
	album_path = ""
	_tracks = PackedStringArray()
	_log_event("out")
	NetworkManager.report_event(NetEvents.Event.EV_AUDIO_REMOVE, {"player": self})
	_update_status()


func _rebuild_tracks() -> void:
	_tracks = RomLibrary.music_tracks(album_path)
	_track_idx = clampi(_track_idx, 0, maxi(0, _tracks.size() - 1))
	_track_bytes = PackedInt64Array()
	for path: String in _tracks:
		var file := FileAccess.open(path, FileAccess.READ)
		_track_bytes.append(file.get_length() if file != null else 0)


func get_snapped_media() -> Node3D:
	return _snapped_media


## Seat a media item programmatically (event / save restore). Each deck seats it
## through its own loader (MediaSlot / MediaTray). `yaw` is the spin a round
## disc was seated at (media_seat_yaw) when saved or inserted remotely; a tape
## deck ignores it.
func restore_media(_media: Node3D, _yaw: float = 0.0) -> void:
	pass


## The spin the seated media is at, relative to the authored seat, in radians.
## Zero on a deck whose loader has nothing seated, and always for a tape.
func media_seat_yaw() -> float:
	return 0.0


## Unseat whatever is loaded, through this deck's own loader. The net layer used to
## do this by reaching for get_node("MediaSlot").drop_object(), which is a no-op for
## any TRAY deck: MediaTray.accept already dropped the zone and reparented the media
## to its own holder, so the zone holds nothing to drop. Each deck answers for
## itself instead.
func remove_media() -> void:
	pass


## The type string this deck saves under. A virtual rather than a chain of `is`
## tests at the call site, so a new deck that forgets to override is a missing
## method rather than something silently serialised as another deck.
func deck_save_type() -> String:
	return ""


# --- Transport (front-panel buttons + remote entry points) ---

func remote_play() -> void: _on_play_pressed()
func remote_pause() -> void: _on_pause_pressed()
func remote_stop() -> void: _on_stop_pressed()
func remote_ff() -> void: _on_ff_pressed()
func remote_rewind() -> void: _on_rewind_pressed()
func remote_next() -> void: _on_next_pressed()
func remote_prev() -> void: _on_prev_pressed()


## Play a specific track. The public entry point for the net layer, which must not
## reach into the private _goto_track (that one does no command forwarding, and is
## also the tail of _on_next_pressed). A caller that could be a client forwards the
## intent itself before calling this.
func remote_goto_track(idx: int) -> void:
	_goto_track(idx)


func _on_play_pressed() -> void:
	_log_event("pressed PLAY")
	if _net_forward_cmd("play"):
		return
	if is_playing and (_scan_dir != 0 or _paused):
		_scan_dir = 0
		if _vlc:
			_vlc.set_paused(false)
		_paused = false
		_apply_volume()
		_update_status()
		_net_push_state()
		return
	play()


func _on_pause_pressed() -> void:
	_log_event("pressed PAUSE")
	if _net_forward_cmd("pause"):
		return
	if is_playing:
		_scan_dir = 0
		if _vlc:
			_vlc.set_paused(true)
		_paused = true
		_apply_volume()
		_update_status()
		_net_push_state()


func _on_stop_pressed() -> void:
	_log_event("pressed STOP")
	if _net_forward_cmd("stop"):
		return
	stop()


func _on_rewind_pressed() -> void:
	_log_event("pressed REW")
	if not has_scan():
		return
	if _net_forward_cmd("rew"):
		return
	if not is_playing:
		return
	_scan_dir = 0 if _scan_dir == -1 else -1
	_apply_scan_mute()
	_update_status()
	_net_push_state()


func _on_ff_pressed() -> void:
	_log_event("pressed FF")
	if not has_scan():
		return
	if _net_forward_cmd("ff"):
		return
	if not is_playing:
		return
	_scan_dir = 0 if _scan_dir == 1 else 1
	_apply_scan_mute()
	_update_status()
	_net_push_state()


func _on_next_pressed() -> void:
	_log_event("pressed NEXT")
	if not has_track_skip():
		return
	if _net_forward_cmd("next"):
		return
	_goto_track(_track_idx + 1)


func _on_prev_pressed() -> void:
	_log_event("pressed PREV")
	if not has_track_skip():
		return
	if _net_forward_cmd("prev"):
		return
	# Past the restart threshold, "previous" restarts the current track.
	if is_playing and _vlc_time_sec() > PREV_RESTART_SEC:
		_vlc_seek_sec(0.0)
		_net_push_state()
		return
	_goto_track(_track_idx - 1)


## Load and play a specific track index (clamped). No-op past the ends.
func _goto_track(idx: int) -> void:
	if _tracks.is_empty():
		return
	if idx < 0 or idx >= _tracks.size():
		return
	_track_idx = idx
	_scan_dir = 0
	_resume_at = 0.0
	play()


func play() -> void:
	if _vlc == null:
		push_error("[RetroAudioPlayer] VlcPlayer unavailable (extension not loaded)")
		return
	if _tracks.is_empty():
		_rebuild_tracks()
	if _tracks.is_empty():
		push_error("[RetroAudioPlayer] cannot play — no album inserted")
		return
	_track_idx = clampi(_track_idx, 0, _tracks.size() - 1)
	# A netplay peer's copy lives under user://, which libVLC would take for a URL
	# scheme it has no module for; it needs the real path.
	if not _vlc.open(ProjectSettings.globalize_path(_tracks[_track_idx]), false):
		push_error("[RetroAudioPlayer] VlcPlayer.open failed for ", _tracks[_track_idx])
		return
	_log_event("playing track %d of %d: %s" % [_track_idx + 1, _tracks.size(), _tracks[_track_idx]])
	_vlc.play()
	_vlc.set_volume(100)
	is_playing = true
	_paused = false
	_scan_dir = 0
	if _emitter:
		_emitter.flush()
		_apply_volume()
	_update_status()
	_net_push_state()


func stop() -> void:
	if not is_playing:
		return
	# A stopped tape stays where it stopped, and the next play carries on from
	# there. A disc goes back to the start of its track, as before.
	var tape := _tape()
	_resume_at = float(tape.get("tape_time")) if tape != null else 0.0
	_scan_dir = 0
	if _vlc:
		_vlc.stop()
	is_playing = false
	_paused = false
	if _emitter:
		_emitter.flush()
	_update_status()
	_net_push_state()


## A track reached its end. Auto-advance to the next one (both CD and cassette
## play through an album); stop at the end of the last track.
func _on_track_finished() -> void:
	if NetworkManager.is_client():
		return   # the host drives advancement; clients follow its state
	_resume_at = 0.0
	var after := _track_after(_track_idx)
	if after >= 0:
		_track_idx = after
		play()
	else:
		_log_event("end of album")
		# The end of the tape. It is wound back to the start, so that PLAY plays
		# it again: the deck has no way to wind a whole album back by hand.
		var tape := _tape()
		if tape != null:
			_track_idx = 0
			tape.set("tape_track", 0)
			tape.set("tape_time", 0.0)
			tape.set("tape_progress", 0.0)
		is_playing = false
		_paused = false
		if _emitter:
			_emitter.flush()
		_update_status()
		_net_push_state()


## The track that plays when `idx` ends, or -1 to stop: the next one, to the album's end. A deck with REPEAT or
## SHUFFLE (the CD player) answers for itself.
func _track_after(idx: int) -> int:
	return idx + 1 if idx + 1 < _tracks.size() else -1


# --- Volume / status ---

func _apply_volume() -> void:
	if _emitter:
		_emitter.set_volume(0.0 if _scan_dir != 0 else _volume_linear)


func _apply_scan_mute() -> void:
	if _vlc:
		_vlc.set_paused(false)
	_paused = false
	_scan_accum = 0.0
	_apply_volume()


func set_audio_volume(volume: float) -> void:
	_volume_linear = clampf(volume, 0.0, 1.0)
	if _scan_dir == 0:
		_apply_volume()


## A sink that also sets a set's speaker switch (mono / stereo) asks the source for it.
func set_audio_channel_mode(mode: int) -> void:
	if _emitter:
		_emitter.set_channel_mode(mode as SpatialAudioEmitter.ChannelMode)


# --- Line out (a deck with phono outputs) ---
#
# A deck with an `AudioLOut` / `AudioROut` pair (RcaPort, OUT; the RETRO XR turntable)
# is a SOURCE on the cable graph the way a VCR is: a lead into a set's audio input or
# the surround amplifier's AUDIO IN carries its sound THERE, and with no lead it plays
# from the deck itself, as every deck did. Resolved through AvSource, the same answer a
# VCR and a console get, on a plug or unplug and never per frame. The sink is told
# (on_av_source_found) and pushes its level back through set_audio_volume: a set its
# input's volume, the amplifier its knob (and silence with no speaker on its back). The
# deck has no FreeSurround of its own, so through the amplifier it plays its stereo on
# FL / FR, folded wherever those have no cabinet, and is not matrix-decoded.

## PHONES. A deck with a `PhonesOut` jack (TrsPort, OUT; the RETRO XR CD player) sends its sound to whatever a lead
## in it reaches (a pair of headphones) INSTEAD of its line out and its own speakers, as a real headphone jack does,
## at the level `phones_level` sets (the LEVEL knob beside it). The line out is resolved as before when nothing is in
## the jack.

## Where the sound goes while a lead carries it, and onto which of its speakers each
## channel lands (-1 nowhere). Null: the deck's own speakers.
var _sound_sink: Node3D = null
## Whether that lead is the one in PHONES.
var _via_phones := false
## The headphones' level, 0..1 (the LEVEL knob's value), applied only through PHONES.
var phones_level := 0.75
var _sink_left := -1
var _sink_right := -1
## The deck's own level, put back when the last lead leaves (a sink sets its own).
var _own_volume := 1.0


func has_line_out() -> bool:
	return get_node_or_null("AudioLOut") is RcaPort or get_node_or_null("AudioROut") is RcaPort 		or get_node_or_null("PhonesOut") is RcaPort


## What RcaPort.get_device() walks up for. A deck with no sockets ignores it.
func on_av_topology_changed(_links: Array) -> void:
	if not has_line_out():
		return
	var phones := phones_sink()
	if phones != null:
		_via_phones = true
		_route_sound(phones, 0, 1)
		return
	_via_phones = false
	var feed := AvSource.resolve(self, true)
	_route_sound(feed.audio_sink, feed.left, feed.right)


## What a lead in PHONES reaches (a sink with speakers: a pair of headphones), or null.
func phones_sink() -> Node3D:
	var jack := get_node_or_null("PhonesOut") as RcaPort
	if jack == null:
		return null
	for link in AvGraph.links_for(self):
		if link["out"] != jack:
			continue
		var target := (link["in"] as RcaPort).get_device()
		if target != null and target != self and target.has_method("get_speaker_positions"):
			return target
	return null


## The LEVEL knob: the headphones' level, applied at once if they carry the sound now.
func set_phones_level(v: float) -> void:
	phones_level = clampf(v, 0.0, 1.0)
	_apply_channel_gains()


## The sink carrying this deck's sound, or null while it plays from itself.
func sound_sink() -> Node3D:
	return _sound_sink if is_instance_valid(_sound_sink) else null


func _route_sound(sink: Node3D, l: int, r: int) -> void:
	_sink_left = l
	_sink_right = r
	if sink != _sound_sink:
		var previous := _sound_sink if is_instance_valid(_sound_sink) else null
		if previous == null:
			_own_volume = _volume_linear
		_sound_sink = sink
		if previous != null and previous.has_method("on_av_source_lost"):
			previous.on_av_source_lost(self)
		if sink != null:
			# The sink pushes its level (set_audio_volume) from here.
			if sink.has_method("on_av_source_found"):
				sink.on_av_source_found(self)
			print("[%s] %s: sound -> %s's speakers (L to %d, R to %d)%s" % [_log_tag(), name, sink.name, l, r,
				", through PHONES at level %.2f" % phones_level if _via_phones else ""])
		else:
			set_audio_volume(_own_volume)
			if _emitter:
				_emitter.clear_speaker_positions()
				_emitter.clear_emit_position()
			print("[%s] %s: sound back on its own speakers%s" % [_log_tag(), name,
				" (was %s)" % previous.name if previous != null else ""])
	if _sound_sink == null and _emitter:
		_emitter.unit_size = UNIT_SIZE
	_apply_channel_gains()


## A channel whose cord reaches nothing is silenced at its voice; the other plays on. Through PHONES both carry the
## LEVEL knob's level.
func _apply_channel_gains() -> void:
	if _emitter == null:
		return
	var cabled := _sound_sink != null
	var g := phones_level if cabled and _via_phones else 1.0
	_emitter.set_channel_gains((1.0 if not cabled or _sink_left >= 0 else 0.0) * g,
		(1.0 if not cabled or _sink_right >= 0 else 0.0) * g)


## Each frame while cabled: the deck's two voices stand on the sink's speakers (an
## amplifier folds them wherever a hand moved its cabinets, so this is read live).
func _follow_sink() -> void:
	if _sound_sink == null or _emitter == null:
		return
	if not is_instance_valid(_sound_sink):
		_route_sound(null, -1, -1)
		return
	# The sink's own distance law (headphones: full level at the head, a leak past it), read live: a set's answer
	# changes as headphones go in and out of ITS jack.
	var unit: float = float(_sound_sink.call("get_audio_unit_size")) if _sound_sink.has_method("get_audio_unit_size") 		else -1.0
	_emitter.unit_size = unit if unit > 0.0 else UNIT_SIZE
	if _sound_sink.has_method("get_speaker_positions"):
		var sp: PackedVector3Array = _sound_sink.get_speaker_positions()
		if sp.size() >= 2:
			_emitter.set_speaker_positions(sp[_sink_left] if _sink_left >= 0 else sp[0],
				sp[_sink_right] if _sink_right >= 0 else sp[1])
			return
	_emitter.set_emit_position(_sound_sink.global_position)


## A NAMEPLATE, not a readout. This used to append the track number and a transport
## caret, which made a piece of hi-fi wear a caption describing itself — and none of
## it was information the deck was not already giving: the tape rides in or out, the
## disc spins or it does not, a record's needle is down or parked. The label is still
## driven from here rather than left to the scene so that a deck renamed at runtime,
## and the download status below, both still land somewhere.
func _update_status() -> void:
	if _name_label:
		_name_label.text = player_label.to_upper()


# ── Multiplayer sync ──────────────────────────────────────────────────────────
# Host is transport authority; every peer plays its own local copy of the album.
# Drift-corrected, not lockstep: the host broadcasts (playing, paused, track,
# pos) on transport changes plus a heartbeat, and a peer switches track / seeks
# when it diverges.

const NET_DRIFT_TOLERANCE := 0.75   # seconds off host before a corrective seek


## Client-in-session: route a transport intent to the host instead of acting
## locally. Returns true when forwarded (caller must then return).
func _net_forward_cmd(cmd: String) -> bool:
	if NetworkManager.is_client() and not NetworkManager.is_event_applying():
		NetworkManager.report_event(NetEvents.Event.EV_AUDIO_CMD, {"player": self, "cmd": cmd})
		return true
	return false


## Host: broadcast the current transport state for peer drift sync.
func _net_push_state() -> void:
	if NetworkManager.is_host() and not NetworkManager.is_event_applying():
		NetworkManager.report_media_state(self)


## Current transport state for the sync layer. The "track" key is the state-shape
## discriminator the heartbeat uses to route audio states (vs VCR/DVD).
func net_get_state() -> Dictionary:
	return {
		"playing": is_playing,
		"paused": is_playing and _paused,
		"track": _track_idx,
		"pos": _vlc_time_sec() if is_playing else 0.0,
	}


## Client: mirror the host's transport state on the LOCAL player.
func net_apply_state(state: Dictionary) -> void:
	var playing := bool(state.get("playing", false))
	var paused := bool(state.get("paused", false))
	var track := int(state.get("track", 0))
	var pos := float(state.get("pos", 0.0))
	if not playing:
		if is_playing:
			stop()
		return
	# The album path is resolved by object_sync after insertion (verify-by-name);
	# refresh in case it landed after the insert event.
	if _tracks.is_empty():
		if album_path.is_empty() and _snapped_media and _snapped_media.has_method("get_album_path"):
			album_path = _snapped_media.get_album_path()
		_rebuild_tracks()
	if _tracks.is_empty():
		_update_status()
		return
	track = clampi(track, 0, _tracks.size() - 1)
	if not is_playing or _track_idx != track:
		_track_idx = track
		play()
	if not is_playing or _vlc == null:
		return
	if not paused and absf(_vlc_time_sec() - pos) > NET_DRIFT_TOLERANCE:
		_vlc_seek_sec(pos)
	if _vlc:
		_vlc.set_paused(paused)
	_paused = paused
	_apply_volume()
	_update_status()


## Optional download-status hook (albums are verify-by-name, so this is only used
## to surface an "album not found on this peer" state).
func net_set_download_status(status: String) -> void:
	if _name_label:
		if status.is_empty():
			_update_status()
		else:
			_name_label.text = "%s  %s" % [player_label.to_upper(), status]


## Ignore-gravity: the device floats where it is put instead of falling. Restored
## from a save through this flag, which FloatLock reads once at _ready.
var ignore_gravity: bool = false
var _float_lock: FloatLock = null

const OPTIONS_PANEL_SCENE := preload("res://Scenes/UI/audio_options_panel.tscn")
var _options_panel: AudioOptionsPanel = null


## Toggle the floating settings panel. Called by SpawnMenuController when the
## menu button is pressed while pointing at this unit (mirrors RetroMouse).
func toggle_options_ui(camera: Node3D) -> void:
	if _options_panel == null:
		_options_panel = OPTIONS_PANEL_SCENE.instantiate()
		add_child(_options_panel)
	if _options_panel.visible:
		_options_panel.hide_panel()
	else:
		_options_panel.show_for(self, camera)


func get_ignore_gravity() -> bool:
	return _float_lock != null and _float_lock.enabled


func set_ignore_gravity(on: bool) -> void:
	ignore_gravity = on
	if _float_lock != null:
		_float_lock.set_enabled(on)
