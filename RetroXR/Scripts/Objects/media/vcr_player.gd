## VCRPlayer — pickable VCR that plays a video from an inserted VCRTape and
## renders it onto a connected TV, reusing the same cable/plug/TV wiring as
## RetroSystem. Playback is driven by the libVLC-backed VlcPlayer GDExtension
## (the same engine as DVDPlayer): video is decoded to a texture and audio to a
## PCM ring buffer drained into a spatialised AudioStreamPlayer3D at the TV.
## Using libVLC gives broad codec support (incl. HEVC/x265) with one shared
## video backend.
class_name VCRPlayer
extends MediaTransport


## Fast-forward / rewind scan rate: seconds of video traversed per real second
## while scanning (e.g. 8.0 ≈ 8× speed).
@export var scan_speed: float = 8.0

## Human-readable label shown above the unit.
@export var vcr_label: String = "VCR"

## When true, the video is rendered through the VHS/VCR effect shader.
@export var vcr_effect_enabled: bool = true

const VCR_SHADER := preload("res://Shaders/vcr_effect.gdshader")

# Tunable VHS/VCR shader uniforms (vcr_effect.gdshader). Adjustable from the VCR
# options panel's "VHS Effect" tab; applied to the screen ShaderMaterial. Defaults
# mirror the shader's own defaults. (CRT display-stage uniforms are owned by the
# connected TV and tuned from the TV panel, so they're not duplicated here.)
var _vcr_params := {
	"effect_amount": 1.0,
	"aberration": 0.0025,
	"scanline_strength": 0.22,
	"noise_strength": 0.10,
	"wobble_strength": 0.0016,
	"tracking_strength": 0.02,
	"tracking_noise": 1.0,
	"tracking_speed": 0.18,
	"desaturation": 0.15,
	"brightness": 1.12,
	"roll_amount": 0.008,
	"roll_speed": 0.5,
	"banded_noise_opacity": 0.15,
	"noise_speed": 8.0,
	"vhs_contrast": 1.12,
	"pixelate": true,
}


# Runtime state
var video_path: String = ""
var is_playing: bool = false
# Scan direction: 0 = normal, +1 = fast-forward scan, -1 = rewind scan.
# While scanning the player keeps PLAYING (so it presents frames) but we jump
# the position ahead/back in throttled steps so the picture visibly races, with
# audio muted (real-VCR feel).
var _scan_dir: int = 0
var _scan_accum: float = 0.0            # time since the last scan seek
## Seconds into the recording that the next play() carries on from: a tape keeps
## its place (see _note_tape). It waits here because a seek means nothing until
## the recording is open and its length is known.
var _resume_at: float = 0.0
## Carry on from the recording's END instead: a rewind that has run off the start
## of one recording into the one before it.
var _resume_end := false
## Playing (or winding) the blank tape after the last recording: the player is
## stopped, the set has no picture, and the tape's place runs on by itself to the
## cassette's end (VCRTape.blank_seconds), where the deck stops and the tape has
## to be rewound.
var _blank := false
## The tape in the deck, kept from the moment it goes in: by the time the slot
## says a tape has left, it no longer has it to ask for.
var _tape: Node = null
# How often (seconds) to seek while scanning. Seeking every frame overloads the
# decoder; ~12 seeks/sec still reads as a smooth fast-scan.
const SCAN_SEEK_INTERVAL := 0.08
## Where a scan has got to, in seconds into the recording. Kept here rather than
## read back from the player, whose seeks land a frame or more late: a scan that
## had just stepped into another recording read 0 there and stepped back out.
var _scan_pos: float = 0.0

## What is on the tape, in the order it plays: its one file, or a playlist's
## entries (RomLibrary.video_recordings). _rec_idx is the one in the player, and
## the sizes on disk weigh how far through the whole tape a point is.
var _recordings := PackedStringArray()
var _rec_bytes := PackedInt64Array()
var _rec_idx: int = 0
## The tape path _recordings was read from.
var _recordings_of := ""
## When this deck last opened a recording. libVLC posts `finished` from its own
## thread, so one from the recording a scan has just left can arrive after the
## next is open, and must not be taken for the end of that one.
var _opened_msec: int = -100000
const STALE_FINISH_MSEC := 300
## How far short of its end a rewind into the previous recording starts: AT the
## end, the player reports that recording finished and winds on again.
const REW_END_MARGIN := 1.0


# Front-loading tape bay (insert ride, eject, grab hand-off, collision) — all owned
# by the shared MediaSlot; see media_slot.gd. The tape rides in 10 cm and lies flat
# (the mesh is authored standing, so it's rotated -90° about the slot's X axis).
const SLOT_INSET := 0.10        # how far inside the VCR a loaded tape rides

@onready var _tape_slot: XRToolsSnapZone = $TapeSlot
@onready var _play_button: VRButton = $PlayButton
@onready var _pause_button: VRButton = $PauseButton
@onready var _stop_button: VRButton = $StopButton
@onready var _rewind_button: VRButton = $RewindButton
@onready var _ff_button: VRButton = $FastForwardButton
@onready var _eject_button: VRButton = $EjectButton
@onready var _record_button: VRButton = $RecordButton
@onready var _power_button: VRButton = $PowerButton
@onready var _name_label: Label3D = $NameLabel
@onready var _options_panel: VCROptionsPanel = $VCROptionsPanel
@onready var _clock: VCRClock = $VCRClock
## The RETRO XR model (RetroXR-models generic/vcr): what is drawn, and the mechanism's animations.
@onready var _model: ApplianceModel = get_node_or_null("Model") as ApplianceModel

## The model's per-frame contract: the cassette's center and the flaps through Load and Eject, and the door
## against how far a held tape is in (door_vs_tape).
const CONTRACT := "res://imported-assets/appliances/vcr/vcr_contract.json"
## Load's first frames are the HAND pushing the tape from the shut flap to the holder; the deck's mechanism runs
## from here (the holder has it), which is where the slot takes it.
const LOAD_FROM_FRAME := 24
## How a seated tape lies in the deck: TapeSeat's basis (its top up, its flap into the bay).
const SEAT_BASIS := Basis(Vector3(1, 0, 0), -PI / 2.0)
## A tape held at the mouth pushes the flap only while it is lined up with the opening this well (m).
const MOUTH_SLACK := Vector2(0.03, 0.02)
## How fast a released flap falls shut (degrees a second).
const FLAP_CLOSE_SPEED := 420.0
## From a tape touching the shut flap to the holder gripping it (the contract's push), meters.
const TOUCH_TO_GRIP := 0.0685

var _contract: Dictionary = {}
var _vfd: VfdDisplay = null
## What the display shows, and its key: it is redrawn only when the key changes.
var _vfd_state: Dictionary = {}
var _vfd_key := ""
## The display and the lamp: POWER puts them to standby. The game has no power state for a deck, so nothing
## else follows it.
var _power_on := true
var _led_on_mat: StandardMaterial3D = null
var _led_off_mat: StandardMaterial3D = null
## The tape the mechanism is moving (MediaSlot.ride_driver), which animation, and how far into it.
var _ride_media: Node3D = null
var _ride_anim := ""
var _ride_t := 0.0
## The flap's angle (degrees) while no animation drives it: a tape in a hand pushes it, and it falls shut.
var _door_deg := 0.0

# Last known total duration (seconds), remembered so the readout keeps showing
# the tape length when paused/stopped. -1 = unknown.
var _last_total: float = -1.0


func _ready() -> void:
	super._ready()
	add_to_group("vcr_player")
	# The model prints its own AV OUT legends round its jacks, so there is no AvLegend.
	_float_lock = FloatLock.attach(self, ignore_gravity)
	TransportGlyphs.label_buttons(self, {
		"PlayButton": "play", "PauseButton": "pause", "StopButton": "stop",
		"RewindButton": "rew", "FastForwardButton": "ff", "EjectButton": "eject",
	}, TransportGlyphs.DECK_SIZE)
	_slot = MediaSlot.new()
	_slot.host = self
	_slot.slot = _tape_slot
	_slot.insert_depth = SLOT_INSET
	_slot.media_local_basis = Basis(Vector3(1, 0, 0), -PI / 2.0)   # lay the tape flat
	add_child(_slot)
	_slot.inserted.connect(_on_media_inserted)
	_slot.removed.connect(_on_media_removed)
	_dress()
	_play_button.button_pressed.connect(_on_play_pressed)
	_pause_button.button_pressed.connect(_on_pause_pressed)
	_stop_button.button_pressed.connect(_on_stop_pressed)
	_rewind_button.button_pressed.connect(_on_rewind_pressed)
	_ff_button.button_pressed.connect(_on_ff_pressed)
	_eject_button.button_pressed.connect(_on_eject_pressed)
	_record_button.button_pressed.connect(_on_record_pressed)
	_power_button.button_pressed.connect(_on_power_pressed)

	if ClassDB.class_exists("VlcPlayer"):
		_vlc = ClassDB.instantiate("VlcPlayer")
		_vlc.finished.connect(_on_video_finished)
		# Build the libVLC instance on its own thread now. Left to the first open(),
		# it walks the whole plugin tree on the main thread, a second-long freeze on
		# the first press of play.
		_vlc.warm_up()
	else:
		push_error("[VCRPlayer] VlcPlayer extension not loaded — video playback unavailable")

	_setup_audio()
	_update_name_label()


func _update_name_label() -> void:
	if _name_label:
		_name_label.text = vcr_label.to_upper()


## The cabinet a combo set builds this into is the housing: the model's body and lamp go with POWER; its flap,
## holder and transport keys stay, so a tape still goes in through the flap.
func _housing() -> Array[Node3D]:
	var out: Array[Node3D] = [$VCRBody, _name_label, _power_button]
	if _model:
		out.append_array(_model.parts("Body"))
		out.append_array(_model.parts("BodyPrint"))
		out.append_array(_model.parts("PowerLed"))
	return out


func _front_panel() -> bool:
	return true


## Dress the deck with its model: every key adopted onto the model's (DeckFace.adopt_front_key), the phono sockets
## on its jacks, and the vacuum fluorescent display over its display window. A deck with no Model node (an old
## scene) keeps its grey box.
func _dress() -> void:
	if _model == null:
		push_warning("[VCR] %s: no Model node; drawn as the old box" % name)
		return
	for pair: Array in [[_play_button, "ButtonPlay"], [_pause_button, "ButtonPause"], [_stop_button, "ButtonStop"],
			[_rewind_button, "ButtonRewind"], [_ff_button, "ButtonFastForward"], [_eject_button, "ButtonEject"],
			[_record_button, "ButtonRecord"], [_power_button, "ButtonPower"]]:
		DeckFace.adopt_front_key(_model, pair[0], pair[1])
	for port: String in ["VideoOut", "AudioLOut", "AudioROut"]:
		DeckFace.seat_port(_model, get_node(port) as Node3D, port)
	_model.hide_part("Display")
	_vfd = VfdDisplay.new()
	_vfd.name = "Vfd"
	_vfd.size_m = Vector2(0.126, 0.025)
	_vfd.painter = _paint_vfd
	# Behind the model's smoked glass a VFD at 1.0 reads gray.
	_vfd.glow = 2.2
	_vfd.transform = _model.part_transform("Display", self).translated_local(Vector3(0.0, 0.0, 0.0002))
	add_child(_vfd)
	# The old clock's viewport drew every frame; nothing shows it now.
	var clock_view := _clock.get_node_or_null("ClockViewport") as SubViewport if _clock else null
	if clock_view:
		clock_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_contract = DeckFace.contract(CONTRACT, "VCR")
	_slot.ride_driver = _ride_tape
	_led_on_mat = StandardMaterial3D.new()
	_led_on_mat.albedo_color = Color(0.05, 0.25, 0.08)
	_led_on_mat.emission_enabled = true
	_led_on_mat.emission = Color(0.25, 1.0, 0.35)
	_led_on_mat.emission_energy_multiplier = 2.5
	_led_off_mat = StandardMaterial3D.new()
	_led_off_mat.albedo_color = Color(0.04, 0.12, 0.05)
	_led_off_mat.roughness = 0.25
	_set_power(true)
	# The body and the laser's box are what the model draws, no margin: the keys stand proud of it.
	_model.fit_shapes([get_node_or_null("CollisionShape3D") as CollisionShape3D,
		get_node_or_null("PointerArea/CollisionShape3D") as CollisionShape3D])
	print("[VCR] %s: dressed with the RETRO XR model (%d levels)" % [name, _model.levels.size()])


## POWER: the display and the lamp go to standby and come back; the deck itself has no power state.
func _on_power_pressed() -> void:
	_log_event("pressed POWER")
	_set_power(not _power_on)


func _set_power(on: bool) -> void:
	_power_on = on
	for led in _model.parts("PowerLed"):
		(led as MeshInstance3D).material_override = _led_on_mat if on else _led_off_mat
	_vfd_key = ""
	print("[VCR] %s: display %s" % [name, "on" if on else "on standby"])


## REC: a key every deck of its day had. This one plays tapes and records nothing, and says so.
func _on_record_pressed() -> void:
	_log_event("pressed REC (this deck plays tapes; it records nothing)")
	_osd("REC: NO RECORDING", false)


# --- The mechanism: Load and Eject move the tape (MediaSlot.ride_driver) ---

## The slot hands the tape over: run the model's Load from where the holder takes it (or, `instant`, show it
## seated at once: a restore), or Eject it to the mouth. The tape follows the contract's poses frame by frame,
## and the model is held at the same time, so door, holder and tape move as one.
func _ride_tape(media: Node3D, to_seat: bool, instant: bool) -> void:
	_ride_media = media
	_ride_anim = "Load" if to_seat else "Eject"
	var rows := _ride_rows()
	if rows.is_empty():
		push_warning("[VCR] %s: no contract poses for %s; the tape is placed, not carried" % [name, _ride_anim])
		media.transform = Transform3D(SEAT_BASIS, Vector3(0, 0, -0.076 if to_seat else 0.0))
		_ride_media = null
		_slot.end_ride()
		return
	var fps := float(_contract.get("fps", 30))
	if instant:
		_ride_t = float(rows.size() - 1) / fps
	else:
		_ride_t = LOAD_FROM_FRAME / fps if to_seat else 0.0
	print("[VCR] %s: %s %s" % [name, _ride_anim, "(restored, seated at once)" if instant else "begins"])
	_step_ride(0.0)


func _ride_rows() -> Array:
	return _contract.get(_ride_anim.to_lower(), []) as Array


func _step_ride(delta: float) -> void:
	if _ride_media == null:
		return
	if not is_instance_valid(_ride_media) or _slot.get_media() != _ride_media:
		# A hand took it off the eject ride: the slot has already let it go.
		_ride_media = null
		_slot.end_ride()
		return
	var rows := _ride_rows()
	var fps := float(_contract.get("fps", 30))
	var length := float(rows.size() - 1) / fps
	_ride_t = minf(_ride_t + delta, length)
	if _model:
		_model.seek(_ride_anim, _ride_t)
	var center: Vector3 = DeckFace.sample(rows, _ride_t, fps, "tape_center")
	_ride_media.global_transform = global_transform * Transform3D(SEAT_BASIS, center)
	if _ride_media.has_method("set_flap"):
		_ride_media.call("set_flap", float(DeckFace.sample(rows, _ride_t, fps, "tape_door")))
	_door_deg = float(DeckFace.sample(rows, _ride_t, fps, "door_deg"))
	if _ride_t >= length:
		print("[VCR] %s: %s done" % [name, _ride_anim])
		_ride_media = null
		_slot.end_ride()


## With no tape in the mechanism, a tape a HAND holds at the mouth pushes the flap in (the contract's door_vs_tape,
## by how far it is in) and the flap falls shut behind it.
func _follow_hand(delta: float) -> void:
	if _model == null or _ride_media != null or _slot.has_media():
		return
	var target := 0.0
	var table: Array = (_contract.get("door_vs_tape", {}) as Dictionary).get("rows", []) as Array
	var mouth := _tape_slot.transform.origin
	for tape in get_tree().get_nodes_in_group("vcr_tape"):
		var t := tape as Node3D
		if t == null or t.global_position.distance_to(_tape_slot.global_position) > 0.25:
			continue
		var local := global_transform.affine_inverse() * t.global_transform
		var off := local.origin - mouth
		if absf(off.x) > MOUTH_SLACK.x or absf(off.y) > MOUTH_SLACK.y:
			continue
		# Flat, its flap leading into the deck: its top up and its +Y along the deck's -Z.
		if local.basis.z.normalized().dot(Vector3.UP) < 0.9 or local.basis.y.normalized().dot(Vector3.BACK) > -0.9:
			continue
		# door_vs_tape's depth 0 is the tape touching the shut flap, 68.5 mm out of the holder's grip.
		var depth := TOUCH_TO_GRIP - off.z
		target = maxf(target, DeckFace.lookup(table, depth) if depth > 0.0 else 0.0)
	var door := maxf(target, _door_deg - FLAP_CLOSE_SPEED * delta)
	if not is_equal_approx(door, _door_deg):
		_door_deg = maxf(door, 0.0)
		for d in _model.parts("Door"):
			d.rotation = Vector3(deg_to_rad(_door_deg), 0.0, 0.0)


# --- The display ---

## What the display shows now, and redraw it if that changed: the counter changes once a second.
func _update_vfd() -> void:
	if _vfd == null:
		return
	var secs := -1.0
	if is_playing and _blank:
		secs = _tape_time() + _tape_blank()
	elif is_playing:
		secs = _vlc_time_sec()
	elif not video_path.is_empty() or is_instance_valid(_tape):
		secs = _tape_time() + _tape_blank()
	var tape := is_instance_valid(_tape) or _slot.has_media()
	var key := "%d|%d|%d|%d|%d|%d" % [int(_power_on), int(secs) if secs >= 0.0 else -1, int(is_playing),
		int(_paused), _scan_dir, int(tape)]
	if key == _vfd_key:
		return
	_vfd_key = key
	_vfd_state = {"secs": secs, "playing": is_playing, "paused": _paused, "scan": _scan_dir, "tape": tape}
	_vfd.refresh()


## The approved layout (RetroXR-models generic/vcr, tools/vfd.py): VIDEO / SP and the cassette on the left, the
## tape counter H:MM:SS in seven segments, ST / SAP and the boxed lamps on the right. 1260 x 250 px.
func _paint_vfd(c: Control, _size: Vector2) -> void:
	if not _power_on or _vfd_state.is_empty():
		return
	var tape: bool = _vfd_state["tape"]
	var secs: float = _vfd_state["secs"]
	var scan: int = _vfd_state["scan"]
	var playing: bool = _vfd_state["playing"] and not _vfd_state["paused"] and scan == 0
	VfdDisplay.boxed(c, "VIDEO", Rect2(28, 52, 142, 48), 22, true)
	VfdDisplay.text(c, "SP", Vector2(184, 86), 20, tape)
	VfdDisplay.boxed(c, "", Rect2(52, 132, 94, 52), 10, tape)
	var reel := VfdDisplay.LIT if tape else VfdDisplay.GHOST
	c.draw_arc(Vector2(80, 158), 11.0, 0.0, TAU, 24, reel, 4.0)
	c.draw_arc(Vector2(118, 158), 11.0, 0.0, TAU, 24, reel, 4.0)
	VfdDisplay.minus(c, Rect2(286, 46, 64.6, 150), 13.0, false)
	var h := " "
	var mm := "  "
	var ss := "  "
	if secs >= 0.0:
		var s := int(secs)
		@warning_ignore("integer_division")
		h = str((s / 3600) % 10)
		@warning_ignore("integer_division")
		mm = "%02d" % ((s % 3600) / 60)
		ss = "%02d" % (s % 60)
	VfdDisplay.digits(c, h, Vector2(366, 46), 68.0, 150.0, 13.0, 84.0)
	VfdDisplay.text(c, "H", Vector2(442, 196), 20, secs >= 0.0)
	VfdDisplay.digits(c, mm, Vector2(478, 46), 68.0, 150.0, 13.0, 84.0)
	VfdDisplay.text(c, "M", Vector2(638, 196), 20, secs >= 0.0)
	VfdDisplay.digits(c, ss, Vector2(676, 46), 68.0, 150.0, 13.0, 84.0)
	VfdDisplay.text(c, "S", Vector2(836, 196), 20, secs >= 0.0)
	VfdDisplay.text(c, "ST", Vector2(960, 86), 22, _vfd_state["playing"] and not _blank)
	VfdDisplay.text(c, "SAP", Vector2(960, 146), 22, false)
	VfdDisplay.boxed(c, "REC", Rect2(1040, 44, 110, 46), 19, false, true)
	VfdDisplay.boxed(c, "PLAY", Rect2(1040, 102, 110, 46), 19, playing)
	VfdDisplay.boxed(c, "PAUSE", Rect2(1040, 160, 110, 46), 19, _vfd_state["paused"])
	VfdDisplay.boxed(c, "FF", Rect2(1160, 44, 78, 46), 19, scan == 1)
	VfdDisplay.boxed(c, "REW", Rect2(1160, 102, 78, 46), 19, scan == -1)


func _process(delta: float) -> void:
	if _vlc:
		# Pump the latest decoded frame + PCM every frame.
		_vlc.update_frame()
		_pump_audio()
		# Emanate the sound from the connected TV so it's spatialised there, aimed
		# the way its picture points -- a set heard from behind should be muted by
		# its own cabinet.
		if _emitter and is_instance_valid(connected_tv):
			_emit_through(connected_tv)
		elif _emitter:
			_emitter.clear_speaker_positions()
			_emitter.clear_emit_position()
			_emitter.clear_emit_direction()
	if _blank:
		_run_blank(delta)
	else:
		_update_scan(delta)
		# A scan that has just run off the recording into the blank tape leaves
		# the player stopped: its time is not the tape's any more.
		if not _blank:
			_resume_tape()
			_note_tape()
	_step_ride(delta)
	_follow_hand(delta)
	if is_playing and not _blank:
		_last_total = _vlc_length_sec()
	elif video_path.is_empty():
		_last_total = -1.0
	_update_vfd()


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


# --- Position helpers (VlcPlayer reports ms / 0..1; the VCR works in seconds) ---

func _vlc_time_sec() -> float:
	return (float(_vlc.get_time()) / 1000.0) if _vlc else 0.0


func _vlc_length_sec() -> float:
	if _vlc == null:
		return -1.0
	var ms: int = _vlc.get_length()
	return (float(ms) / 1000.0) if ms > 0 else -1.0


## Seek to an absolute time in seconds (needs a known length — libVLC seeks by
## fraction). No-op when the length isn't known yet.
func _vlc_seek_sec(sec: float) -> void:
	if _vlc == null:
		return
	var length := _vlc_length_sec()
	if length > 0.0:
		_vlc.set_position(clampf(sec / length, 0.0, 1.0))


## While scanning, jump the (still-playing) player's position forward/back in
## throttled steps so frames visibly race by at scan_speed. Running off either
## end of a recording winds on into the next one, or back into the one before;
## hitting either end of the TAPE stops the scan and holds there.
func _update_scan(delta: float) -> void:
	if _scan_dir == 0 or not is_playing or _resume_pending():
		return
	_scan_accum += delta
	if _scan_accum < SCAN_SEEK_INTERVAL:
		return
	var length := _vlc_length_sec()
	var pos := _scan_pos + _scan_accum * scan_speed * float(_scan_dir)
	_scan_accum = 0.0
	if pos <= 0.0:
		if _rec_idx > 0:
			_switch_recording(_rec_idx - 1, true)
			return
		_vlc_seek_sec(0.0)
		_end_scan_hold()   # reached the start; hold here
	elif length > 0.0 and pos >= length:
		if _rec_idx + 1 < _recordings.size():
			_switch_recording(_rec_idx + 1, false)
			return
		# Off the end of the last recording into the blank tape after it, still
		# winding on.
		if _blank_room() > 0.0:
			if is_instance_valid(_tape):
				_tape.set("tape_time", length)
			_enter_blank(0.0)
			_net_push_state()
			return
		_vlc_seek_sec(length)
		_end_scan_hold()   # reached the end; hold here
	else:
		_scan_pos = pos
		_vlc_seek_sec(pos)


## Stop an in-progress scan and freeze on the current frame (used at either end).
func _end_scan_hold() -> void:
	_scan_dir = 0
	if _vlc:
		_vlc.set_paused(true)
	_paused = true
	_apply_volume()
	_osd("PAUSE", true)


## Toggle the floating VCR settings panel (mirrors RetroSystem.toggle_options_ui).
## Called by SpawnMenuController when the menu button is pressed while pointing
## at this VCR.
func toggle_options_ui(camera: Node3D) -> void:
	if _options_panel == null:
		return
	if _options_panel.visible:
		_options_panel.hide_panel()
	else:
		_options_panel.show_for(self, camera)


# --- Tape slot callbacks ---

## MediaSlot accepted a tape (the insert ride has begun). Cache its path and report
## the insert; playback is user/host-started, never auto-played on insert.
func _on_media_inserted(tape: Node3D) -> void:
	if tape.has_method("get_video_path"):
		video_path = tape.get_video_path()
	_log_event("tape in: %s" % video_path)
	_take_tape_place(tape)
	NetworkManager.report_event(NetEvents.Event.EV_TAPE_INSERT,
		{"vcr": self, "tape": tape})


## MediaSlot reports the tape left (ejected, or pulled straight out). Stop playback
## and clear state.
func _on_media_removed() -> void:
	# The tape leaves with its place as last written, and is still from here on.
	if is_instance_valid(_tape):
		_tape.set("tape_speed", 0.0)
	_tape = null
	_resume_at = 0.0
	stop()
	video_path = ""
	_recordings = PackedStringArray()
	_recordings_of = ""
	_rec_idx = 0
	_log_event("tape out")
	NetworkManager.report_event(NetEvents.Event.EV_TAPE_REMOVE, {"vcr": self})


func _on_eject_pressed() -> void:
	_log_event("pressed EJECT")
	_slot.eject()


## Client-in-session: transport intents route to the host (authoritative
## transport). The host executes and its state broadcast drives every peer's
## LOCAL playback (M5) — video files arrive via NetFileTransfer.
## Returns true when the command was forwarded instead of handled locally.
func _net_forward_cmd(cmd: String) -> bool:
	if NetworkManager.is_client() and not NetworkManager.is_event_applying():
		NetworkManager.report_event(NetEvents.Event.EV_VCR_CMD, {"vcr": self, "cmd": cmd})
		return true
	return false


# ── Multiplayer playback sync (M5) ────────────────────────────────────────────
# Host is transport authority; every peer plays its own local copy of the video.
# Sync is drift-corrected, not lockstep: the host broadcasts
# (playing, paused, position) on transport changes plus a heartbeat, and a peer
# seeks whenever its position drifts past NET_DRIFT_TOLERANCE.

const NET_DRIFT_TOLERANCE := 0.75   # seconds off host before a corrective seek

## Host: push the current transport state to peers (no-op offline/client).
func _net_push_state() -> void:
	if NetworkManager.is_host() and not NetworkManager.is_event_applying():
		NetworkManager.report_media_state(self)


## Current transport state for the sync layer. `pos` is into recording `rec`.
func net_get_state() -> Dictionary:
	return {
		"playing": is_playing,
		"paused": is_playing and _paused,
		"rec": _rec_idx,
		"pos": _vlc_time_sec() if is_playing and not _blank else 0.0,
		# Seconds into the blank tape after the recordings, or -1 in them.
		"blank": _tape_blank() if is_playing and _blank else -1.0,
	}


## Client: mirror the host's transport state on the LOCAL player.
func net_apply_state(state: Dictionary) -> void:
	var playing := bool(state.get("playing", false))
	var paused := bool(state.get("paused", false))
	var rec := int(state.get("rec", 0))
	var pos := float(state.get("pos", 0.0))
	if not playing:
		if is_playing:
			stop()
		return
	# The host is on the blank tape after the recordings: so is this deck, with
	# no picture, its place kept near the host's.
	var blank := float(state.get("blank", -1.0))
	if blank >= 0.0:
		if not is_instance_valid(_tape):
			return
		_ensure_recordings()
		is_playing = true
		_paused = paused
		if not _blank:
			_enter_blank(blank)
		elif absf(_tape_blank() - blank) > NET_DRIFT_TOLERANCE:
			_tape.set("tape_blank", blank)
		return
	if _blank:
		# The host has wound back out of the blank into the recording.
		_blank = false
		is_playing = false
		if is_instance_valid(_tape):
			_tape.set("tape_blank", 0.0)
	# Ensure we have a local file — the tape's path is remapped/downloaded by
	# object_sync; refresh in case the transfer landed after insertion.
	var tape := _slot.get_media()
	if video_path.is_empty() and tape and tape.has_method("get_video_path"):
		video_path = tape.get_video_path()
	if not is_playing:
		if video_path.is_empty() or connected_tv == null:
			_osd("WAITING FOR TAPE…", true)
			return
		_rec_idx = rec
		play()
		if is_playing and pos > NET_DRIFT_TOLERANCE:
			_vlc_seek_sec(pos)
	elif rec != _rec_idx and rec >= 0 and rec < _recordings.size():
		# The host has played or wound on into another recording.
		_switch_recording(rec, false)
		_resume_at = pos
	if not is_playing:
		return
	if _vlc:
		_vlc.set_paused(paused)
	_paused = paused
	if not paused and absf(_vlc_time_sec() - pos) > NET_DRIFT_TOLERANCE:
		_vlc_seek_sec(pos)


# --- Playback controls ---

# Remote-control entry points (TVRemote): identical to pressing the unit's
# front-panel buttons, including FF/REW scan toggling and OSD messages.

func remote_play() -> void:
	_on_play_pressed()


func remote_pause() -> void:
	_on_pause_pressed()


func remote_stop() -> void:
	_on_stop_pressed()


func remote_ff() -> void:
	_on_ff_pressed()


func remote_rewind() -> void:
	_on_rewind_pressed()


func remote_eject() -> void:
	_on_eject_pressed()


## True when a tape is loaded (the remote greys its Eject cell otherwise).
func has_media() -> bool:
	return _slot.has_media()


## The menu's Debug tab: the tape, what the player is doing with it, the audio it
## decodes and where the picture goes. See DebugRows for the shape.
func debug_state() -> Array:
	var tape: VCRTape = _tape as VCRTape if is_instance_valid(_tape) else null
	var tape_rows: Array = []
	if tape == null:
		tape_rows.append(["Tape", "(none in the deck)"])
	else:
		tape_rows.append(["Label", tape.video_label if not tape.video_label.is_empty()
			else "(unlabelled)"])
		var path := _recordings[_rec_idx] if _rec_idx < _recordings.size() else tape.video_path
		tape_rows.append_array(MediaDebug.file_rows(path))
		if _recordings.size() > 1:
			tape_rows.append(["Recording", "%d of %d (playlist %s)" % [_rec_idx + 1,
				_recordings.size(), tape.video_path.get_file()]])
		tape_rows.append_array([
			["Cassette", "T-%d" % tape.cassette if tape.cassette > 0 else "not sized yet"],
			["Recording length", MediaDebug.time_text(int(tape.recording_seconds * 1000.0))],
			["Tape at", "%s (%.1f%%)%s" % [MediaDebug.time_text(int(tape.tape_time * 1000.0), true),
				tape.tape_progress * 100.0,
				"" if tape.tape_blank <= 0.0 else ", %.0f s into blank tape" % tape.tape_blank]],
			["Tape moving", "still" if is_zero_approx(tape.tape_speed)
				else "%+.1f×" % tape.tape_speed],
		])
	var out: Array = [["Tape", tape_rows]]
	out.append_array(MediaDebug.vlc_sections(_vlc, true))
	var deck: Array = MediaDebug.output_rows(self, connected_tv)
	deck.append_array([
		["VHS filter", "on" if vcr_effect_enabled else "off"],
		["Scan speed", "%d×" % int(scan_speed)],
	])
	out.append(["Deck", deck])
	return out


func _log_tag() -> String:
	return "VCR"


func _on_play_pressed() -> void:
	_log_event("pressed PLAY")
	if _net_forward_cmd("play"):
		return
	if is_playing and (_scan_dir != 0 or _paused):
		# Leaving a scan or resuming from pause both mean "back to normal play".
		_set_scan(0)
		if _vlc:
			_vlc.set_paused(false)
		_paused = false
		_osd("PLAY", false)
		_net_push_state()
		return
	# A tape played to its end plays nothing until it is wound back.
	if not is_playing and _tape_at_end():
		_osd("REWIND TAPE", false)
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
		_apply_volume()   # undo any scan mute
		_osd("PAUSE", true)
		_net_push_state()


func _on_stop_pressed() -> void:
	_log_event("pressed STOP")
	if _net_forward_cmd("stop"):
		return
	stop()


## Rewind button: toggle reverse scan (press again, or Play/Pause, to exit).
## From stop it plays from where the tape is and scans back from there: a tape
## played to its end from the end of its last recording.
func _on_rewind_pressed() -> void:
	_log_event("pressed REW")
	if _net_forward_cmd("rew"):
		return
	if not is_playing:
		if not is_instance_valid(_tape) or video_path.is_empty():
			return
		# A cassette with blank tape after its recordings stands in that blank:
		# play() starts it there, and the scan winds back through it.
		if _tape_at_end() and _tape_blank() <= 0.0:
			_ensure_recordings()
			_rec_idx = maxi(_recordings.size() - 1, 0)
			_resume_at = 0.0
			_resume_end = true
		elif _rec_idx == 0 and _tape_time() <= 0.0 and _tape_blank() <= 0.0:
			return   # already at the start
		play()
		if not is_playing:
			return
		_set_scan(-1)
		_osd("<< REW", true)
		return
	if _scan_dir == -1:
		_set_scan(0)
		_osd("PLAY", false)
	else:
		_set_scan(-1)
		_osd("<< REW", true)


## Fast-forward button: toggle forward scan (press again, or Play/Pause, to exit).
func _on_ff_pressed() -> void:
	_log_event("pressed FF")
	if _net_forward_cmd("ff"):
		return
	if not is_playing:
		return
	if _scan_dir == 1:
		_set_scan(0)
		_osd("PLAY", false)
	else:
		_set_scan(1)
		_osd("FF >>", true)


## Show an on-screen message on the connected TV (sticky, or auto-hiding after 3s).
func _osd(text: String, sticky: bool) -> void:
	var tv := _watching_tv()
	if tv == null:
		return
	if sticky:
		tv.show_osd(text)
	else:
		tv.show_osd_timed(text, 3.0)


## Enter (dir = ±1) or leave (dir = 0) a fast-forward/rewind scan.
## The player keeps playing during a scan (so frames present) but is muted;
## leaving restores normal-speed playback and the prior volume.
func _set_scan(dir: int) -> void:
	_scan_dir = dir
	_scan_accum = 0.0
	_scan_pos = _vlc_time_sec()
	if _vlc:
		_vlc.set_paused(false)
	_paused = false
	if _emitter:
		_emitter.set_volume(0.0 if dir != 0 else _volume_linear)
	_net_push_state()


func _apply_volume() -> void:
	if _emitter:
		_emitter.set_volume(_volume_linear)


func play() -> void:
	if connected_tv == null:
		push_error("[VCRPlayer] Cannot play - no TV connected")
		return
	if video_path.is_empty():
		push_error("[VCRPlayer] Cannot play - no tape inserted")
		return
	if _vlc == null:
		push_error("[VCRPlayer] VlcPlayer unavailable (extension not loaded)")
		return
	_ensure_recordings()
	if _recordings.is_empty():
		# A playlist naming nothing that is still there. Said on the set, because
		# the error log cannot be read in a headset.
		push_error("[VCRPlayer] Cannot play - no recording on the tape is there: ", video_path)
		_osd("BLANK TAPE", false)
		return
	if _tape_blank() > 0.0:
		# The tape stands in the blank after its recordings: it plays on there.
		is_playing = true
		_paused = false
		_scan_dir = 0
		_enter_blank(_tape_blank())
		_apply_volume()
		_osd("PLAY", false)
		_net_push_state()
		return
	_rec_idx = clampi(_rec_idx, 0, _recordings.size() - 1)
	if not _open_recording():
		return
	is_playing = true
	_paused = false
	_scan_dir = 0
	if _emitter:
		_emitter.flush()
		_apply_volume()
	_osd("PLAY", false)
	_net_push_state()


func stop() -> void:
	if not is_playing:
		return
	# A stopped tape stays where it stopped, and the next play carries on from
	# there.
	_resume_at = _tape_time()
	_resume_end = false
	_scan_dir = 0
	_blank = false
	if is_instance_valid(_tape):
		_tape.set("tape_speed", 0.0)
	if _vlc:
		_vlc.stop()
	is_playing = false
	_paused = false
	if _emitter:
		_emitter.flush()
	if _watching_tv():
		connected_tv.hide_osd()
	_net_push_state()


## Read what is on the tape, again whenever its path changes or nothing was
## there last time: a netplay peer's copy can land after the tape went in.
func _ensure_recordings() -> void:
	if video_path == _recordings_of and not _recordings.is_empty():
		return
	_recordings_of = video_path
	_recordings = RomLibrary.video_recordings(video_path)
	_rec_bytes = PackedInt64Array()
	for path: String in _recordings:
		var file := FileAccess.open(path, FileAccess.READ)
		_rec_bytes.append(file.get_length() if file != null else 0)


## Open the recording at _rec_idx and set it running. The transport around it
## (scan, mute, the OSD) is the caller's to keep or change.
func _open_recording() -> bool:
	if _vlc == null or _rec_idx < 0 or _rec_idx >= _recordings.size():
		return false
	# A netplay peer's copy lives under user://, which libVLC would take for a URL
	# scheme it has no module for; it needs the real path.
	var path := ProjectSettings.globalize_path(_recordings[_rec_idx])
	if not _vlc.open(path, false):
		push_error("[VCRPlayer] VlcPlayer.open failed for ", path)
		return false
	_vlc.play()
	# Full internal gain — level is controlled by the Godot 3D player (TV knob).
	_vlc.set_volume(100)
	_opened_msec = Time.get_ticks_msec()
	_log_event("playing %s" % path)
	return true


## Go on into another recording on the same tape without stopping it: the end
## of one playing into the next, or a scan running off either end of one. A scan
## carries on through it, from its start, or for a rewind, from its end.
func _switch_recording(idx: int, at_end: bool) -> void:
	_rec_idx = idx
	_resume_at = 0.0
	_resume_end = at_end
	_scan_pos = 0.0
	if not _open_recording():
		stop()


func _resume_pending() -> bool:
	return _resume_at > 0.0 or _resume_end


# --- TV connection contract ---
#
# on_tv_connected/on_tv_disconnected are gone: they were the captive lead's, called
# by the set when a CablePlug carrying a back-reference to its host arrived. A
# composite cable's plugs belong to no device, so the deck works out its own
# connection instead — see on_av_topology_changed. A console still uses the old
# path, which is why the set still has it.


## Set the audio volume (0.0 = silent, 1.0 = 100%). Called by the TV volume buttons.
func set_audio_volume(volume: float) -> void:
	_volume_linear = clampf(volume, 0.0, 1.0)
	# Don't fight an active scan mute; it restores on scan exit.
	if _scan_dir == 0:
		_apply_volume()


## Part of the TV contract: the set's mono switch, applied to the tape's own
## sound. See SpatialAudioEmitter.set_channel_mode.
func set_audio_channel_mode(mode: int) -> void:
	if _emitter:
		_emitter.set_channel_mode(mode)


# --- What the set reads ---
#
# The deck no longer paints anything. It answers two questions — is there a
# picture, and what should it be put through — and RetroTV builds the material.
# set_screen_enabled, _screen_allowed, _may_paint, _bind_screen_to_tv,
# _blank_screen, _make_screen_material and _material_matches_effect all existed to
# keep this deck's painting in step with a set that was painting too. There is one
# painter now.


## The tape's live frame, or null when there is nothing to show: stopped, on the
## blank tape after the recording, or the picture cord is not in the set's video
## socket. A different object after a resolution change, so the set re-reads it
## per frame.
func get_video_texture() -> Texture2D:
	if _vlc == null or not is_playing or _blank or not _feed_video:
		return null
	return _vlc.get_texture()


## The shader the set should put this deck's picture through, and the parameters
## for it. Empty means "no stage of my own" — the set uses its plain path, which is
## what the VHS effect being switched off asks for.
##
## The set owns the material; this only says what to run in it. That is the whole
## of what the deck used to build, install and keep in step by hand.
func get_video_stage(_tv: Node) -> Dictionary:
	if not vcr_effect_enabled:
		return {}
	return {"shader": VCR_SHADER, "params": _vcr_params}


## Toggle the VHS effect at runtime. The set notices the stage changed and rebuilds.
func set_vcr_effect_enabled(on: bool) -> void:
	vcr_effect_enabled = on


## Set one VHS uniform, remembering it. Called by VCROptionsPanel; the set pushes
## the stored values onto the material it owns.
func set_vcr_param(pname: String, value: Variant) -> void:
	if _vcr_params.has(pname):
		_vcr_params[pname] = value


## Current VHS uniform values, for the options panel to populate its controls.
func get_vcr_params() -> Dictionary:
	return _vcr_params.duplicate()


func _on_video_finished() -> void:
	# The end of a recording a scan or an earlier finish has already moved off.
	if Time.get_ticks_msec() - _opened_msec < STALE_FINISH_MSEC:
		return
	# More on the tape: it plays on into the next recording. In a session the
	# host decides that, and a peer follows its state there.
	if is_playing and _rec_idx + 1 < _recordings.size():
		if NetworkManager.is_client():
			return
		_switch_recording(_rec_idx + 1, false)
		_net_push_state()
		return
	# The end of the recording, with blank tape after it: the deck plays on into
	# that, with no picture, to the end of the cassette.
	if is_playing and _blank_room() > 0.0:
		var ran := _vlc_length_sec()
		if ran > 0.0 and is_instance_valid(_tape):
			_tape.set("tape_time", ran)
		_enter_blank(0.0)
		_net_push_state()
		return
	# The end of the tape: leave the last frame, and the tape where it ran out.
	# It has to be rewound before it plays again (_on_play_pressed,
	# _on_rewind_pressed), and it keeps that place out of the deck and in a save.
	_resume_at = 0.0
	_resume_end = false
	if is_instance_valid(_tape):
		_tape.set("tape_track", _rec_idx)
		var length := _vlc_length_sec()
		if length > 0.0:
			_tape.set("tape_time", length)
		_tape.set("tape_progress", 1.0)
		_tape.set("tape_speed", 0.0)
	_log_event("end of tape")
	is_playing = false
	_paused = false
	if _emitter:
		_emitter.flush()


# --- A/V out ---
#
# The deck has three sockets and no lead of its own. A composite cable is spawned
# and plugged in, and what plays depends entirely on which sockets its cords reach:
# picture only when a cord joins this VideoOut to the set's video in, the left
# channel only when one joins AudioLOut to an audio in — and if that one lands in
# the set's RIGHT socket, the left channel comes out of the right-hand speaker.
# CompositeCable works out the pairs; this only reads them.


# --- A tape keeps its place ---

## Take up where a tape was left: its recording, and how far into it. Called as
## it goes in. The recording is clamped when it plays, not here: a netplay peer's
## copy of a playlist may not have landed yet.
func _take_tape_place(tape: Node) -> void:
	_tape = tape if tape != null and "tape_time" in tape else null
	_resume_at = maxf(0.0, float(_tape.get("tape_time"))) if _tape != null else 0.0
	_resume_end = false
	_rec_idx = maxi(0, int(_tape.get("tape_track"))) if _tape != null and "tape_track" in _tape else 0


## True when the tape in the deck has been played to its end and not wound back.
func _tape_at_end() -> bool:
	if not is_instance_valid(_tape):
		return false
	if _tape.has_method("at_tape_end"):
		return bool(_tape.call("at_tape_end"))
	return "tape_progress" in _tape and float(_tape.get("tape_progress")) >= 1.0


## How far into the blank tape after the recordings the tape in the deck stands,
## in seconds; 0 in its recordings.
func _tape_blank() -> float:
	if not is_instance_valid(_tape) or not ("tape_blank" in _tape):
		return 0.0
	return float(_tape.get("tape_blank"))


## How much blank tape follows the recordings on the cassette in the deck.
func _blank_room() -> float:
	if not is_instance_valid(_tape) or not _tape.has_method("blank_seconds"):
		return 0.0
	return float(_tape.call("blank_seconds"))


## Go on into the blank tape after the last recording, `at` seconds into it. The
## transport (playing, paused, a scan) carries on as it was; only the picture and
## the sound stop.
func _enter_blank(at: float) -> void:
	_blank = true
	_resume_at = 0.0
	_resume_end = false
	_rec_idx = maxi(_recordings.size() - 1, 0)
	if _vlc:
		_vlc.stop()
	if _emitter:
		_emitter.flush()
	if is_instance_valid(_tape):
		_tape.set("tape_track", _rec_idx)
		_tape.set("tape_progress", 1.0)
		_tape.set("tape_blank", clampf(at, 0.0, _blank_room()))


## Run the tape on through the blank: at play speed, at scan speed either way, or
## not at all while paused. Off its end the deck stops; wound back off its start
## it goes back into the last recording, at its end, still winding back.
func _run_blank(delta: float) -> void:
	if not is_playing or not is_instance_valid(_tape):
		_blank = false
		return
	var speed := 0.0
	if _scan_dir != 0:
		speed = scan_speed * float(_scan_dir)
	elif not _paused:
		speed = 1.0
	_tape.set("tape_speed", speed)
	var at := _tape_blank() + delta * speed
	var room := _blank_room()
	if at >= room:
		_tape.set("tape_blank", room)
		_end_of_tape()
	elif at <= 0.0 and speed < 0.0:
		_tape.set("tape_blank", 0.0)
		_blank = false
		_switch_recording(_rec_idx, true)
	else:
		_tape.set("tape_blank", at)


## The end of the cassette: the deck stops, with the tape run out, and nothing
## plays until it is rewound.
func _end_of_tape() -> void:
	_log_event("end of tape")
	_blank = false
	_scan_dir = 0
	is_playing = false
	_paused = false
	_resume_at = 0.0
	_resume_end = false
	_apply_volume()
	if is_instance_valid(_tape):
		_tape.set("tape_speed", 0.0)
	if _watching_tv():
		connected_tv.hide_osd()
	_net_push_state()


## Where the tape in the deck stands, in seconds into its recording; 0 with none in it.
func _tape_time() -> float:
	return float(_tape.get("tape_time")) if is_instance_valid(_tape) else 0.0


## Seek to where the tape was, once the recording play() opened knows its length.
func _resume_tape() -> void:
	if not _resume_pending() or not is_playing:
		return
	var length := _vlc_length_sec()
	if length <= 0.0:
		return
	var at := maxf(0.0, length - REW_END_MARGIN) if _resume_end else _resume_at
	_vlc_seek_sec(at)
	_scan_pos = at
	_resume_at = 0.0
	_resume_end = false


## Write the tape's place back onto it, every frame it is in the deck. While
## stopped the place is left as it was: a stopped tape has not moved. How far
## through the whole tape is the cassette's measure, the recordings weighed by
## their sizes on disk; for a tape of one file it is just how far through that.
func _note_tape() -> void:
	if not is_instance_valid(_tape):
		return
	if not is_playing or _resume_pending():
		_tape.set("tape_speed", 0.0)
		return
	var at := _vlc_time_sec()
	var length := _vlc_length_sec()
	_tape.set("tape_track", _rec_idx)
	_tape.set("tape_time", at)
	_tape.set("tape_blank", 0.0)
	if length > 0.0:
		_tape.set("tape_progress", RetroAudioPlayer.album_progress(_rec_bytes, _rec_idx, at / length))
		_measure_tape(length)
	if _paused and _scan_dir == 0:
		_tape.set("tape_speed", 0.0)
	else:
		_tape.set("tape_speed", scan_speed * float(_scan_dir) if _scan_dir != 0 else 1.0)


## A tape whose recordings' header said nothing of their length (not an MP4 or
## a WAV) is measured here, by the recording playing, `length` seconds long: the
## whole of one file, or for a playlist, that one scaled up by its share of the
## tape's size on disk. The first length known picks the tape's cassette.
func _measure_tape(length: float) -> void:
	if not _tape.has_method("note_recording_seconds") or float(_tape.get("recording_seconds")) > 0.0:
		return
	var whole := length
	if _recordings.size() > 1:
		var share := RetroAudioPlayer.album_progress(_rec_bytes, _rec_idx, 1.0) \
			- RetroAudioPlayer.album_progress(_rec_bytes, _rec_idx, 0.0)
		if share <= 0.0:
			return
		whole = length / share
	_tape.call("note_recording_seconds", whole)


# --- Save/load restore (mirrors RetroSystem) ---

func get_snapped_tape() -> Node3D:
	return _slot.get_media()


## Seat a tape programmatically (event/save restore) — no ride, bypasses the filter.
func restore_media(tape: Node3D, _yaw: float = 0.0) -> void:
	_slot.restore(tape)


## The counterpart to restore_media, for a remote peer taking the tape out.
##
## Releases the snap zone rather than running the local eject ride: the tape is
## already gone on the peer that moved it, and object_sync positions it here.
## Which child holds the tape stays this deck's business.
func net_release_tape() -> void:
	_tape_slot.drop_object()
