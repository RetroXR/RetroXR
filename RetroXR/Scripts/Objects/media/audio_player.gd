## RetroAudioPlayer — shared base for the pickable CD and cassette players. Plays
## an inserted audio album (a folder of tracks, or a single audio file) through
## the libVLC-backed VlcPlayer GDExtension — the same engine as the VCR/DVD, but
## audio-only. A deck has no speaker of its own: its sound comes out only of what
## a lead carries it to -- headphones in PHONES first, else the speakers its line
## out reaches (a set, the surround amplifier) -- and with no lead it is SILENT,
## the transport running on as a real deck's does. See "Line out" below.
##
## Subclasses (CDPlayer / CassettePlayer) provide the scene + button set. The CD
## has Prev/Next track buttons (and the remote shows them); the cassette is a
## linear tape (play/pause/stop/ff/rew only, tracks auto-advance, no skip). A
## tape's FF/REW winds THROUGH the tracks to the side's end or start, from play
## or from stop, and the tape stays where it ran out (no rewind of its own).
##
## SIDES. A cassette and an LP play one side of their album (plays_sides()): the
## tracks before the playlist's `#SIDE B` line are side A, the rest side B
## (RomLibrary.music_sides), laid out by their real lengths (TapeSides,
## MusicLengths). Which side plays is the side the medium went in facing out, or
## up (MediaSide). A tape runs on as BLANK tape after its side's last track to the
## side's end (_blank), as a real one does; a record's run-out groove plays nothing.
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
## A two-sided medium's side playing (0 A, 1 B), both sides' tracks and lengths (seconds), the playing side's lengths
## beside _tracks, and the side's running length: a tape's side, or an LP's longer side (_side_length).
var _side := 0
var _side_tracks: Array[PackedStringArray] = [PackedStringArray(), PackedStringArray()]
var _side_lens: Array[PackedFloat64Array] = [PackedFloat64Array(), PackedFloat64Array()]
var _lens := PackedFloat64Array()
var _side_len := 0.0
## Whether the album's playlist marks side B (`#SIDE B`); with none, side B is blank.
var _album_marked := false
## Seconds into the blank tape after the side's last track, while the tape runs there (playing or winding); -1
## otherwise. _track_idx is then the track count.
var _blank := -1.0
## Blank tape is not silence: a little hiss, linear amplitude.
const TAPE_HISS := 0.0025
## Less blank than this after a side's last track is no blank run: the side just ends.
const BLANK_MIN := 0.05
var _hiss_rng := RandomNumberGenerator.new()
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


## What the deck runs on: its own mains cord. With no power its keys do nothing,
## what is playing stops and its display is dark.
var _mains: PowerInput = null


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
	# Its own mains cord, from the model's PowerCordExit (docs/dev/power.md).
	_mains = ApplianceMains.hook_up(self, get_node_or_null("Model"))
	_mains.power_changed.connect(_on_mains_changed)


## Whether the deck has power (its own mains cord, docs/dev/power.md).
func mains_live() -> bool:
	return _mains == null or _mains.is_live()


## The deck's intake, for its menu's Power section.
func power_input() -> PowerInput:
	return _mains


## A key on a deck with no power does nothing, as on the hardware, and says why in
## the log. A peer's event is the host's, already decided.
func _mains_gate(what: String) -> bool:
	if mains_live() or NetworkManager.is_event_applying():
		return true
	print("[%s] %s: %s -- no power (%s)" % [_log_tag(), name, what, _mains.why_not()])
	return false


## The supply came or went: with none, what is playing stops and the display goes
## dark (a deck redraws it in _on_mains_redraw).
func _on_mains_changed(live: bool) -> void:
	print("[%s] %s: %s" % [_log_tag(), name, "power came back" if live else "lost its power"])
	if not live and is_playing:
		stop()
	_on_mains_redraw()


## Redraw what shows power (a display, a lamp, a motor). Each deck its own.
func _on_mains_redraw() -> void:
	pass


## Put the deck's own cord away (plugged in out of sight) or bring it back: the System
## tab's Show Power Cord, and a peer's EV_MAINS_CORD_HIDDEN.
func set_mains_cord_hidden(on: bool) -> void:
	var cord: CaptiveMainsCord = _mains.captive as CaptiveMainsCord if _mains != null else null
	if cord == null or cord.hidden == on:
		return
	cord.set_hidden(on)
	NetworkManager.report_event(NetEvents.Event.EV_MAINS_CORD_HIDDEN, {"obj": self, "hidden": on})


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
		media_rows.append(["Album path", album_path if not album_path.is_empty() else "(none)"])
		var playlist := RomLibrary.music_playlist(album_path)
		var from_folder := DirAccess.dir_exists_absolute(album_path)
		media_rows.append(["Playlist (m3u)", playlist if not playlist.is_empty()
			else ("none: tracks from the folder" if from_folder else "none")])
		if plays_sides():
			media_rows.append(["Side", "%s (A %d tracks, B %d; %s)" % [TapeSides.side_name(_side),
				_side_tracks[0].size(), _side_tracks[1].size(),
				"#SIDE B in the playlist" if _album_marked else "no #SIDE B: side B is blank"]])
			media_rows.append(["Side length", "%s of music, %s in all%s" % [
				MediaDebug.time_text(int(TapeSides.music_s(_lens) * 1000.0), true),
				MediaDebug.time_text(int(_side_len * 1000.0), true),
				", lengths measured" if MusicLengths.all_known(_tracks) else ", lengths ESTIMATED from file sizes"]])
		media_rows.append(["Track", "blank tape, %.1f of %.1f s" % [_blank, _blank_len()] if _blank >= 0.0
			else ("%d of %d" % [_track_idx + 1, _tracks.size()] if _track_idx < _tracks.size() else "—")])
		var path := _tracks[_track_idx] if _track_idx < _tracks.size() else ""
		media_rows.append_array(MediaDebug.file_rows(path))
		var tape := _tape()
		if tape != null:
			media_rows.append(["Tape at", "%s (%.1f%% of the tape)" % [
				MediaDebug.time_text(int(float(tape.get("tape_time")) * 1000.0), true),
				float(tape.get("tape_progress")) * 100.0 if "tape_progress" in tape else 0.0]])
	var out: Array = [["Media", media_rows]]
	if is_instance_valid(_snapped_media):
		out.append(["Tracks", track_rows(_tracks, _track_idx, album_path)])
	out.append(["Audio out", audio_out_rows()])
	out.append_array(MediaDebug.vlc_sections(_vlc, false))
	var deck: Array = [["Deck", player_label]]
	deck.append_array(_debug_deck_rows())
	deck.append(["Volume (the sink's)", "%d%%" % roundi(_volume_linear * 100.0)])
	deck.append(["Output level", "%d%%" % roundi(output_level * 100.0)])
	if get_node_or_null("PhonesOut") != null:
		deck.append(["PHONES level", "%d%%" % roundi(phones_level * 100.0)])
	out.append(["Deck", deck])
	return out


## Every track the album lists (its m3u's order, else the folder's), one row each: the
## file's name, then the folder it is in. The one in the deck is marked.
static func track_rows(tracks: PackedStringArray, current: int, album: String) -> Array:
	if tracks.is_empty():
		return [["Tracks", "none found in %s" % album if not album.is_empty() else "none"]]
	var rows: Array = []
	for i in tracks.size():
		var path := tracks[i]
		var missing := "" if FileAccess.file_exists(path) else "  MISSING"
		rows.append(["%s %d" % ["▶" if i == current else "  ", i + 1],
			"%s%s   (%s)" % [path.get_file(), missing, path.get_base_dir()]])
	return rows


## Where the deck's sound goes, for the Debug tab: what is in PHONES and in each line-out
## jack, and what carries the sound now (or that nothing does, so it is silent).
func audio_out_rows() -> Array:
	var rows: Array = []
	var sink := sound_sink()
	if sink == null:
		rows.append(["Sound to", "nothing: silent (no lead to headphones or speakers)"
			if has_line_out() else "the deck's own speakers (it has no outputs)"])
	else:
		rows.append(["Sound to", "%s via %s" % [_device_word(sink), "PHONES" if _via_phones else "LINE OUT"]])
	for jack: String in ["PhonesOut", "AudioLOut", "AudioROut"]:
		var port := get_node_or_null(jack) as RcaPort
		if port == null:
			continue
		var word: String = {"PhonesOut": "PHONES", "AudioLOut": "Line out L", "AudioROut": "Line out R"}[jack]
		rows.append([word, _jack_target(port)])
	if sink != null and not _via_phones:
		rows.append(["Speakers", "L -> %s, R -> %s" % [
			"speaker %d" % _sink_left if _sink_left >= 0 else "nowhere",
			"speaker %d" % _sink_right if _sink_right >= 0 else "nowhere"]])
	return rows


## What a lead in one of the deck's jacks reaches: the device and the socket on it.
func _jack_target(port: RcaPort) -> String:
	for link: Dictionary in AvGraph.links_for(self):
		if link["out"] != port:
			continue
		var to := link["in"] as RcaPort
		var dev := to.get_device()
		if dev == null:
			return "a lead, to nothing"
		var where := to.port_label()
		if dev is RetroTV:
			var input := (dev as RetroTV).input_for_device(self)
			if input >= 0:
				where = "%s %s" % [(dev as RetroTV).source_name(input), where]
		return "%s, %s" % [_device_word(dev), where]
	return "empty"


static func _device_word(dev: Node) -> String:
	if dev is RetroTV:
		return "TV (%s)" % dev.name
	return String(dev.name)


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


# ── What the remote shows and does on a deck (RemoteTarget) ───────────────────

func _init() -> void:
	RemoteTarget.join(self)


## Transport grid: prev/play/next over rew/stop/ff.
func remote_layout() -> Array:
	return [
		{"id": "prev", "glyph": "prev", "col": 0, "row": 0},
		{"id": "playpause", "glyph": "play", "col": 1, "row": 0},
		{"id": "next", "glyph": "next", "col": 2, "row": 0},
		{"id": "rew", "glyph": "rew", "col": 0, "row": 1},
		{"id": "stop", "glyph": "stop", "col": 1, "row": 1},
		{"id": "ff", "glyph": "ff", "col": 2, "row": 1},
	]


## prev/next only on a deck that skips tracks (a CD); rew/ff greyed on a turntable,
## which has no scan — you move the needle, as prev/next are greyed on a cassette.
func remote_cell_enabled(id: String) -> bool:
	if id == "prev" or id == "next":
		return has_track_skip()
	if id == "rew" or id == "ff":
		return has_scan()
	return true


func remote_cell_face(id: String) -> Dictionary:
	return RemoteTarget.play_face(self) if id == "playpause" else {}


func remote_cell_faces(id: String) -> Array:
	return RemoteTarget.PLAY_FACES if id == "playpause" else []


func remote_activate(id: String) -> void:
	match id:
		"playpause": RemoteTarget.toggle_play(self)
		"stop": remote_stop()
		"rew": remote_rewind()
		"ff": remote_ff()
		"prev": remote_prev()
		"next": remote_next()
		_: print("[AudioPlayer] %s: the remote's %s is no key of a deck's" % [name, id])


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
	# Silent until a lead carries the sound somewhere (on_av_topology_changed).
	_apply_channel_gains()


func _process(delta: float) -> void:
	if _vlc:
		_vlc.update_frame()
		_pump_audio()
	_follow_sink()
	_update_scan(delta)
	_run_blank(delta)
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
	_blank = -1.0
	if media == null or not ("tape_time" in media):
		return
	if _laid_out():
		var was := int(media.get("tape_side")) if "tape_side" in media else 0
		var track := int(media.get("tape_track"))
		var t := _tape_side_time(media)
		if was == _side and track >= 0 and track <= _tracks.size():
			# The same side as last written: its track and time are exact.
			_track_idx = track
			_resume_at = maxf(0.0, float(media.get("tape_time")))
		else:
			# Turned over, or a track this side has not: from the tape's one place.
			var at := TapeSides.locate(_lens, t)
			_track_idx = int(at["track"])
			_resume_at = float(at["blank"]) if float(at["blank"]) >= 0.0 else float(at["into"])
		media.set("tape_side", _side)
		media.set("tape_track", _track_idx)
		media.set("tape_time", _resume_at)
		_log_event("tape place: side %s, %s at %.1f s (%.1f s into the %.0f s side%s)" % [TapeSides.side_name(_side),
			"blank tape" if _track_idx >= _tracks.size() else "track %d" % (_track_idx + 1), _resume_at, t, _side_len,
			", turned over" if was != _side else ""])
		return
	if _tracks.is_empty():
		return
	_track_idx = clampi(int(media.get("tape_track")), 0, _tracks.size() - 1)
	_resume_at = maxf(0.0, float(media.get("tape_time")))


## Seconds into the playing side the tape stands at, from what is written on it: its track and time when they were
## written for this side, else its one place (tape_progress) read from this side.
func _tape_side_time(tape: Node) -> float:
	var same := int(tape.get("tape_side")) == _side if "tape_side" in tape else _side == 0
	if same:
		var track := int(tape.get("tape_track"))
		if track >= 0 and track <= _tracks.size():
			return TapeSides.time_of(_lens, track, maxf(0.0, float(tape.get("tape_time"))))
	return TapeSides.side_time(float(tape.get("tape_progress")), _side, _side_len)


## Seek to where the tape was, once the track play() opened knows its length.
func _resume_tape() -> void:
	if _resume_at <= 0.0 or not is_playing or _blank >= 0.0:
		return
	var length := _vlc_length_sec()
	if length <= 0.0:
		return
	# A scan opening a track (INF: at its end) lands short of the end, where a seek
	# would finish the track rather than wind it.
	_vlc_seek_sec(minf(_resume_at, length - SCAN_TRACK_EDGE * 2.0) if _scan_dir != 0 else _resume_at)
	_resume_at = 0.0


## Write the tape's place back onto it, every frame it is in a deck. While
## stopped the place is left as it was, which is the point: a stopped tape has
## not moved.
func _note_tape() -> void:
	var tape := _tape()
	if tape == null:
		return
	if not is_playing or (_resume_at > 0.0 and _blank < 0.0):
		tape.set("tape_speed", 0.0)
		return
	if _laid_out():
		var t: float
		if _blank >= 0.0:
			t = TapeSides.music_s(_lens) + _blank
			tape.set("tape_track", _tracks.size())
			tape.set("tape_time", _blank)
		else:
			var into := _vlc_time_sec()
			tape.set("tape_track", _track_idx)
			tape.set("tape_time", into)
			if _track_idx < _lens.size():
				into = minf(into, _lens[_track_idx])
			t = TapeSides.time_of(_lens, _track_idx, into)
		tape.set("tape_side", _side)
		tape.set("tape_progress", TapeSides.pos_of(_side, t, _side_len))
	else:
		var at := _vlc_time_sec()
		var length := _vlc_length_sec()
		tape.set("tape_track", _track_idx)
		tape.set("tape_time", at)
		if length > 0.0:
			tape.set("tape_progress", album_progress(_track_bytes, _track_idx, at / length))
	# The tape's own way: side B runs it back along side A.
	var way := -1.0 if _side == 1 else 1.0
	if _paused and _scan_dir == 0:
		tape.set("tape_speed", 0.0)
	else:
		tape.set("tape_speed", way * (scan_speed * float(_scan_dir) if _scan_dir != 0 else 1.0))


# --- Sides (a cassette, an LP) ---

## Whether this deck plays one side of a two-sided medium (the cassette deck, the record player). The CD does not.
func plays_sides() -> bool:
	return false


## Whether the playing side is laid out: its tracks read by _rebuild_tracks, each with a length, and a side length.
## Until then (or for a track list set by hand) a tape keeps the one-run behaviour: its ends are the tracks' ends.
func _laid_out() -> bool:
	return plays_sides() and _lens.size() == _tracks.size() and _side_len > 0.0


## The side the loader seated the medium with (0 A, 1 B). A deck that plays sides answers from its loader.
func _seated_side() -> int:
	return 0


## A side's running length, seconds, for an album whose sides hold `a_s` and `b_s` of music: an LP's longer side
## (the arm's band); the cassette deck answers with its tape's side.
func _side_length(a_s: float, b_s: float) -> float:
	return maxf(a_s, b_s)


## The side playing, 0 A or 1 B.
func side_playing() -> int:
	return _side


## Lay both sides out by their tracks' lengths (MusicLengths: measured, else estimated) and the playing side's.
func _measure_sides() -> void:
	_side_lens = [MusicLengths.lengths_now(_side_tracks[0]), MusicLengths.lengths_now(_side_tracks[1])]
	_lens = _side_lens[_side]
	var a_s := TapeSides.music_s(_side_lens[0])
	var b_s := TapeSides.music_s(_side_lens[1])
	# An album with no tracks on either side (one not found) has no sides at all: nothing to run on as blank tape.
	_side_len = _side_length(a_s, b_s) if not (_side_tracks[0].is_empty() and _side_tracks[1].is_empty()) else 0.0
	_log_event("sides: A %d tracks %.0f s, B %d tracks %.0f s; side %s plays, %.0f s long (%s)" % [
		_side_tracks[0].size(), a_s, _side_tracks[1].size(), b_s, TapeSides.side_name(_side), _side_len,
		"#SIDE B marked" if _album_marked else "no #SIDE B: side B blank"])


## The tracks' lengths were measured: lay the sides out again. While playing, the track and time are the truth and
## stay; the tape's place follows from them.
func _on_lengths_measured(for_album: String) -> void:
	if for_album != album_path or album_path.is_empty():
		return
	_measure_sides()


## Seconds of blank tape after the playing side's last track.
func _blank_len() -> float:
	return maxf(0.0, _side_len - TapeSides.music_s(_lens))


## The tape runs on into its blank, `at` seconds in, still winding if it was (FF / REW keep their way). The sound is
## the hiss of blank tape; nothing is open in libVLC.
func _enter_blank(at: float) -> void:
	_blank = clampf(at, 0.0, _blank_len())
	_track_idx = _tracks.size()
	_resume_at = 0.0
	if _vlc:
		_vlc.stop()
	is_playing = true
	_paused = false
	if _emitter:
		_emitter.flush()
	_log_event("blank tape on side %s: %.1f of %.1f s%s" % [TapeSides.side_name(_side), _blank, _blank_len(),
		", winding %s" % ("on" if _scan_dir > 0 else "back") if _scan_dir != 0 else ""])
	_apply_volume()
	_update_status()
	_net_push_state()


## Run the blank tape on: in play at its own speed, winding at the scan's. Off the side's end it stops there; wound
## back past the last track it winds on into that track (or, with none on the side, stops at the side's start).
func _run_blank(delta: float) -> void:
	if _blank < 0.0 or not is_playing:
		return
	if _paused and _scan_dir == 0:
		return
	_blank += delta * (scan_speed * float(_scan_dir) if _scan_dir != 0 else 1.0)
	if _blank >= _blank_len():
		_blank = -1.0
		_log_event("end of side %s" % TapeSides.side_name(_side))
		_end_scan_tape(1)
	elif _blank < 0.0:
		_blank = -1.0
		if _tracks.is_empty():
			_end_scan_tape(-1)
		else:
			_track_idx = _tracks.size() - 1
			_log_event("REW winds out of the blank into track %d" % _tracks.size())
			_open_scanning(INF)


## The blank tape's hiss, into the emitter as the tracks' PCM goes.
func _pump_hiss() -> void:
	if _emitter == null or _paused or _scan_dir != 0:
		return
	var want := _emitter.frames_wanted()
	if want <= 0:
		return
	var frames := PackedVector2Array()
	frames.resize(want)
	for i in want:
		frames[i] = Vector2(_hiss_rng.randf_range(-TAPE_HISS, TAPE_HISS), _hiss_rng.randf_range(-TAPE_HISS, TAPE_HISS))
	_emitter.push_stereo(frames)
	if wants_levels:
		_measure(frames)


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
	if _blank >= 0.0:
		_pump_hiss()
		return
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


## While scanning, jump the position forward/back in throttled steps. On a disc,
## hitting either end of the current track stops the scan and holds there. A tape
## winds on THROUGH its tracks (_scan_cross) and stops only at the album's ends.
func _update_scan(delta: float) -> void:
	if _scan_dir == 0 or not is_playing or _blank >= 0.0:
		return
	if _resume_at > 0.0:
		return      # a track just opened mid-scan: wait for _resume_tape's seek
	_scan_accum += delta
	if _scan_accum < SCAN_SEEK_INTERVAL:
		return
	var length := _vlc_length_sec()
	if length <= 0.0 and _tape() != null:
		return      # the track the scan crossed into has not told its length yet
	var pos := _vlc_time_sec() + _scan_accum * scan_speed * float(_scan_dir)
	_scan_accum = 0.0
	if _tape() != null:
		if pos <= 0.0:
			_scan_cross(-1)
		elif pos >= length - SCAN_TRACK_EDGE:
			_scan_cross(1)
		else:
			_vlc_seek_sec(pos)
		return
	if pos <= 0.0:
		_vlc_seek_sec(0.0)
		_end_scan_hold()
	elif length > 0.0 and pos >= length:
		_vlc_seek_sec(length)
		_end_scan_hold()
	else:
		_vlc_seek_sec(pos)


## How near a track's end a tape's scan crosses into the next one: short of the very
## end, where libVLC would finish the track instead of seeking.
const SCAN_TRACK_EDGE := 0.25


## A tape's scan ran off one end of its track: open the next (or the previous, near its
## end) and wind on, still scanning. Off the album's end or start the tape stops there.
func _scan_cross(dir: int) -> void:
	var to := _track_idx + dir
	if to < 0 or to >= _tracks.size():
		if dir > 0 and _laid_out() and _tape() != null and _blank_len() > BLANK_MIN:
			_log_event("FF winds off the last track into the blank tape")
			_enter_blank(0.0)
			return
		_end_scan_tape(dir)
		return
	_log_event("%s winds into track %d of %d" % ["FF" if dir > 0 else "REW", to + 1, _tracks.size()])
	_track_idx = to
	# Going back, the scan carries on from the end of the track before.
	_open_scanning(INF if dir < 0 else 0.0)


## Open the selected track at `at` seconds (INF: at its end) and keep the scan running,
## muted. play() resets the scan; it is put back here.
func _open_scanning(at: float) -> void:
	var dir := _scan_dir
	_resume_at = 0.0
	play()
	if not is_playing:
		return
	_scan_dir = dir
	_scan_accum = 0.0
	_resume_at = at
	_apply_volume()
	_update_status()


## A tape wound to the end (dir +1) or the start (-1) of the album: it stops there, and
## stays there. Its place is written onto the cassette so PLAY, a save or an eject find it.
func _end_scan_tape(dir: int) -> void:
	var tape := _tape()
	var last := maxi(0, _tracks.size() - 1)
	_scan_dir = 0
	_blank = -1.0
	if dir > 0:
		_park_tape_at_end(tape, last)
	else:
		_track_idx = 0
		if tape != null:
			tape.set("tape_track", 0)
			tape.set("tape_time", 0.0)
			tape.set("tape_side", _side)
			tape.set("tape_progress", TapeSides.pos_of(_side, 0.0, _side_len) if _laid_out() else 0.0)
	_log_event("tape wound to its %s" % ("END" if dir > 0 else "START"))
	_resume_at = 0.0
	if _vlc:
		_vlc.stop()
	is_playing = false
	_paused = false
	if _emitter:
		_emitter.flush()
	_apply_volume()
	_update_status()
	_net_push_state()


## The tape run out at the end of its last track, written onto the cassette.
func _park_tape_at_end(tape: Node, last: int) -> void:
	if _laid_out():
		# The end of the SIDE: past its last track and its blank.
		_blank = -1.0
		_track_idx = _tracks.size()
		if tape == null:
			return
		tape.set("tape_side", _side)
		tape.set("tape_track", _tracks.size())
		tape.set("tape_time", _blank_len())
		tape.set("tape_progress", TapeSides.pos_of(_side, _side_len, _side_len))
		return
	_track_idx = last
	if tape == null:
		return
	var length := _vlc_length_sec()
	tape.set("tape_track", last)
	if length > 0.0:
		tape.set("tape_time", length)
	tape.set("tape_progress", 1.0)


## Whether the tape in the deck is wound all the way to its end.
func tape_at_end() -> bool:
	var tape := _tape()
	if tape != null and _laid_out():
		return _tape_side_time(tape) >= _side_len - BLANK_MIN
	return tape != null and not _tracks.is_empty() \
		and int(tape.get("tape_track")) >= _tracks.size() - 1 \
		and float(tape.get("tape_progress")) >= 0.999


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
	_side = _seated_side() if plays_sides() else 0
	_log_event("in: %s%s" % [album_path, ", side %s" % TapeSides.side_name(_side) if plays_sides() else ""])
	_track_idx = 0
	_rebuild_tracks()
	_take_tape_place(media)
	NetworkManager.report_event(NetEvents.Event.EV_AUDIO_INSERT,
		{"player": self, "media": media, "yaw": media_seat_yaw(), "side": _side})
	if _autoplay_on_load() and not NetworkManager.is_active():
		if tape_at_end():
			_log_event("the tape is at its end: not played (rewind it)")
		else:
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
	_blank = -1.0
	stop()
	album_path = ""
	_tracks = PackedStringArray()
	_log_event("out")
	NetworkManager.report_event(NetEvents.Event.EV_AUDIO_REMOVE, {"player": self})
	_update_status()


func _rebuild_tracks() -> void:
	if plays_sides():
		var sides := RomLibrary.music_sides(album_path)
		_album_marked = bool(sides["marked"])
		_side_tracks = [sides["a"] as PackedStringArray, sides["b"] as PackedStringArray]
		_tracks = _side_tracks[_side]
		_measure_sides()
		var every := PackedStringArray()
		every.append_array(_side_tracks[0])
		every.append_array(_side_tracks[1])
		MusicLengths.request(every, _on_lengths_measured.bind(album_path))
	else:
		_tracks = RomLibrary.music_tracks(album_path)
	# A tape may stand in its blank, past the last track.
	var top := _tracks.size() if _laid_out() and _tape() != null else maxi(0, _tracks.size() - 1)
	_track_idx = clampi(_track_idx, 0, top)
	_track_bytes = PackedInt64Array()
	for path: String in _tracks:
		var file := FileAccess.open(path, FileAccess.READ)
		_track_bytes.append(file.get_length() if file != null else 0)


func get_snapped_media() -> Node3D:
	return _snapped_media


## Seat a media item programmatically (event / save restore). Each deck seats it
## through its own loader (MediaSlot / MediaTray). `yaw` is the spin a round
## disc was seated at (media_seat_yaw) when saved or inserted remotely; a tape
## deck ignores it. `_side_out` is the side a two-sided medium faces out / up with (MediaSide); the CD ignores it.
func restore_media(_media: Node3D, _yaw: float = 0.0, _side_out: int = 0) -> void:
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
	if not _mains_gate("PLAY"):
		return
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
	if not is_playing and tape_at_end():
		# A tape that ran out stays out: nothing plays until it is rewound.
		_log_event("PLAY: the tape is at its end; rewind it first")
		return
	play()


func _on_pause_pressed() -> void:
	if not _mains_gate("PAUSE"):
		return
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
	if not _mains_gate("REW"):
		return
	_log_event("pressed REW")
	if not has_scan():
		return
	if _net_forward_cmd("rew"):
		return
	if not is_playing:
		_scan_from_stop(-1)
		return
	_scan_dir = 0 if _scan_dir == -1 else -1
	_apply_scan_mute()
	_update_status()
	_net_push_state()


func _on_ff_pressed() -> void:
	if not _mains_gate("FF"):
		return
	_log_event("pressed FF")
	if not has_scan():
		return
	if _net_forward_cmd("ff"):
		return
	if not is_playing:
		_scan_from_stop(1)
		return
	_scan_dir = 0 if _scan_dir == 1 else 1
	_apply_scan_mute()
	_update_status()
	_net_push_state()


## FF / REW on a stopped deck. A tape winds from where it stands (a real deck winds with
## no play pressed), and stops at the album's end or start; a disc does nothing, as before.
func _scan_from_stop(dir: int) -> void:
	var tape := _tape()
	if tape == null:
		return
	if _tracks.is_empty():
		_rebuild_tracks()
	if _tracks.is_empty() and not _laid_out():
		return
	if dir > 0 and tape_at_end():
		_log_event("FF: the tape is already at its end")
		return
	if _laid_out():
		var t := _tape_side_time(tape)
		if dir < 0 and t <= 0.0:
			_log_event("REW: the tape is already at its start")
			return
		var loc := TapeSides.locate(_lens, t)
		_log_event("%s from stop, side %s at %.1f s" % ["FF" if dir > 0 else "REW", TapeSides.side_name(_side), t])
		_scan_dir = dir
		if float(loc["blank"]) >= 0.0:
			_enter_blank(float(loc["blank"]))
		else:
			_track_idx = int(loc["track"])
			_open_scanning(float(loc["into"]))
		_net_push_state()
		return
	var at := float(tape.get("tape_time"))
	if dir < 0 and int(tape.get("tape_track")) <= 0 and at <= 0.0:
		_log_event("REW: the tape is already at its start")
		return
	_track_idx = clampi(int(tape.get("tape_track")), 0, _tracks.size() - 1)
	_log_event("%s from stop, track %d at %.1f s" % ["FF" if dir > 0 else "REW", _track_idx + 1, at])
	_scan_dir = dir
	_open_scanning(at)
	_net_push_state()


func _on_next_pressed() -> void:
	if not _mains_gate("NEXT"):
		return
	_log_event("pressed NEXT")
	if not has_track_skip():
		return
	if _net_forward_cmd("next"):
		return
	_goto_track(_track_idx + 1)


func _on_prev_pressed() -> void:
	if not _mains_gate("PREV"):
		return
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
	if not _mains_gate("play"):
		return
	if _vlc == null:
		push_error("[RetroAudioPlayer] VlcPlayer unavailable (extension not loaded)")
		return
	if _tracks.is_empty():
		_rebuild_tracks()
	if _laid_out() and _tape() != null and _track_idx >= _tracks.size():
		# Past the side's last track (or a side with none): blank tape, from where it stands.
		_scan_dir = 0
		_enter_blank(_resume_at)
		return
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
	_blank = -1.0
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
	var tape := _tape()
	if tape != null and _scan_dir != 0:
		# libVLC ran a scanning tape off its track before the scan crossed: wind on.
		_scan_cross(_scan_dir)
		return
	_resume_at = 0.0
	var after := _track_after(_track_idx)
	if after >= 0:
		_track_idx = after
		play()
	elif tape != null and _laid_out() and _blank_len() > BLANK_MIN:
		_log_event("the last track of side %s played: the blank tape runs on" % TapeSides.side_name(_side))
		_enter_blank(0.0)
	else:
		_log_event("end of side %s" % TapeSides.side_name(_side) if plays_sides() else "end of album")
		# The end of the tape. It STAYS at the end, as a real one does: PLAY does
		# nothing there until it is rewound (REW winds back through every track).
		# It used to wind itself back to the start.
		if tape != null:
			_park_tape_at_end(tape, maxi(0, _tracks.size() - 1))
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
# the surround amplifier's AUDIO IN carries its sound THERE (a lead straight into loudspeaker
# cabinets too: LineOutCabinets, one sink for the pair), and with no lead it is
# SILENT (2026-11-03: a deck has no speaker; it used to play from the deck itself,
# heard "through the air" with nothing plugged in). Resolved through AvSource, the same answer a
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
## The deck's own output level, 0..1, on whatever carries its sound (the cassette deck's
## LEVEL knob); a deck with no such knob leaves it at 1.
var output_level := 1.0
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


## The deck's output level (a LEVEL knob on the deck itself), applied at once.
func set_output_level(v: float) -> void:
	output_level = clampf(v, 0.0, 1.0)
	_apply_channel_gains()


## The sink carrying this deck's sound, or null while it is silent (no lead).
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
			print("[%s] %s: no lead carries the sound now: %s%s" % [_log_tag(), name,
				"silent" if has_line_out() else "on its own speakers (it has no outputs)",
				" (was %s)" % previous.name if previous != null else ""])
	if _sound_sink == null and _emitter:
		_emitter.unit_size = UNIT_SIZE
	_apply_channel_gains()


## A channel whose cord reaches nothing is silenced at its voice; the other plays on. Through PHONES both carry the
## LEVEL knob's level. With no lead at all both are silent: a deck has no speaker (a deck with no outputs whatever,
## which nothing ships, plays from itself rather than never).
func _apply_channel_gains() -> void:
	if _emitter == null:
		return
	var cabled := _sound_sink != null
	if not cabled and has_line_out():
		_emitter.set_channel_gains(0.0, 0.0)
		return
	var g := (phones_level if cabled and _via_phones else 1.0) * output_level
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
		"blank": _blank,
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
	# The host's tape runs in its blank: so does this one, at the host's place.
	var blank := float(state.get("blank", -1.0))
	if blank >= 0.0 and plays_sides():
		if _blank < 0.0:
			_scan_dir = 0
			_enter_blank(blank)
		elif absf(_blank - blank) > NET_DRIFT_TOLERANCE:
			_blank = blank
		_paused = paused
		_update_status()
		return
	_blank = -1.0
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
