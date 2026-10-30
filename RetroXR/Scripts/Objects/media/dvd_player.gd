## DVDPlayer — a pickable DVD deck that plays a real DVD image (VIDEO_TS/.iso/.img)
## onto a connected TV, with working disc menus + chapter navigation driven by the
## TV remote. Playback is handled by the libVLC-backed VlcPlayer GDExtension, which
## renders the disc's own menus into the picture; the remote forwards D-pad/OK and
## chapter presses into libVLC navigation.
##
## Reuses the same cable/plug/TV wiring as VCRPlayer / RetroSystem.
class_name DVDPlayer
extends MediaTransport

## Human-readable label shown above the unit.
@export var dvd_label: String = "DVD"

## Fast-forward / rewind scan rate: seconds of video traversed per real second.
@export var scan_speed: float = 8.0

# Runtime state
var dvd_path: String = ""
var is_playing: bool = false

# FF/REW scan (only meaningful during title playback, not in a disc menu):
# 0 = normal, +1 = forward, -1 = reverse. Mirrors the VCR's scan.
var _scan_dir: int = 0
var _scan_accum: float = 0.0
const SCAN_SEEK_INTERVAL := 0.08


# Front-loading disc bay (insert ride, eject, grab hand-off, collision) — all owned
# by the shared MediaSlot; see media_slot.gd. Disc rides in 10 cm, lies flat.
const SLOT_INSET := 0.10       # how far inside the player a loaded disc rides


# Cached track counts for the remote's audio/subtitle greying (-1 = not yet
# known; libVLC populates the lists a beat after play()). Refreshed on a low-rate
# throttle in _process and after each cycle.
var _n_audio: int = -1
var _n_sub: int = -1
var _track_refresh_accum: float = 0.0

# Multiplayer (Phase 5): the host is the transport + menu authority; every peer
# plays its own local copy of the disc (verify-only by MD5, never transferred —
# same legal stance as ROMs). Sync is drift-corrected on title/chapter/time, not
# lockstep; the disc's menu-VM highlight state is not replicated (both peers boot
# the same root menu, and content transitions resync via title/chapter). See the
# NetObjectSync header.
const NET_DRIFT_TOLERANCE := 1.0   # seconds of content drift before a seek


@onready var _disc_slot: XRToolsSnapZone = $DiscSlot
@onready var _play_button: VRButton = $PlayButton
@onready var _pause_button: VRButton = $PauseButton
@onready var _stop_button: VRButton = $StopButton
@onready var _menu_button: VRButton = $MenuButton
@onready var _prev_button: VRButton = $PrevChapterButton
@onready var _next_button: VRButton = $NextChapterButton
@onready var _rewind_button: VRButton = $RewindButton
@onready var _ff_button: VRButton = $FastForwardButton
@onready var _eject_button: VRButton = $EjectButton
@onready var _name_label: Label3D = $NameLabel
@onready var _options_panel: DVDOptionsPanel = $DVDOptionsPanel
## The RETRO XR model (RetroXR-models generic/dvd-player): what is drawn, and the tray's Open / Close.
@onready var _model: ApplianceModel = get_node_or_null("Model") as ApplianceModel

## The model's key for each scene button.
const KEYS := {"PlayButton": "ButtonPlay", "PauseButton": "ButtonPause", "StopButton": "ButtonStop",
	"MenuButton": "ButtonMenu", "PrevChapterButton": "ButtonPrevChapter", "NextChapterButton": "ButtonNextChapter",
	"EjectButton": "ButtonOpenClose", "RewindButton": "ButtonRewind", "FastForwardButton": "ButtonFastForward",
	"LanguageButton": "ButtonAudio", "SubtitleButton": "ButtonSubtitle", "UpButton": "ButtonUp",
	"DownButton": "ButtonDown", "LeftButton": "ButtonLeft", "RightButton": "ButtonRight", "SelectButton": "ButtonEnter"}
## A disc's center stands this far over DiscSeat (the well's floor): half the 4 mm disc.
const DISC_LIFT := 0.002
## How long the display says LOADING after the tray has closed on a disc.
const LOADING_MSEC := 1500

var _vfd: VfdDisplay = null
var _vfd_state: Dictionary = {}
var _vfd_key := ""
## The tray: out or in, and Open / Close while it moves (with how far into it).
var _tray_open := false
var _tray_anim := ""
var _tray_t := 0.0
## The tray's collision (_build_tray_body), or null.
var _tray_body: AnimatableBody3D
## The disc the tray is carrying (MediaSlot.ride_driver), or null.
var _ride_media: Node3D = null
var _loading_until := 0

# The box's copy of the remote's menu cluster + track cycling: same ids, same
# enable rules, same actions. Lit colour per id; greyed to COLOR_BTN_OFF whenever
# the remote would grey the matching cell.
const BOX_BTN_COLOR := {
	"up": Color(0.35, 0.45, 0.62), "down": Color(0.35, 0.45, 0.62),
	"left": Color(0.35, 0.45, 0.62), "right": Color(0.35, 0.45, 0.62),
	"ok": Color(0.2, 0.7, 0.95),
	"audio": Color(0.6, 0.35, 0.8), "subtitle": Color(0.85, 0.55, 0.15),
}
const COLOR_BTN_OFF := Color(0.22, 0.22, 0.24)
var _box_buttons: Dictionary = {}      # id -> VRButton
var _box_button_lit: Dictionary = {}   # id -> bool, last colour applied


func _ready() -> void:
	super._ready()
	add_to_group("dvd_player")
	# The model prints its own AV OUT legends round its jacks, so there is no AvLegend.
	_float_lock = FloatLock.attach(self, ignore_gravity)
	TransportGlyphs.label_buttons(self, {
		"PlayButton": "play", "PauseButton": "pause", "StopButton": "stop",
		"MenuButton": "menu", "PrevChapterButton": "prev", "NextChapterButton": "next",
		"EjectButton": "eject", "RewindButton": "rew", "FastForwardButton": "ff",
		"LanguageButton": "audio", "SubtitleButton": "subtitle",
		"UpButton": "up", "DownButton": "down", "LeftButton": "left",
		"RightButton": "right", "SelectButton": "ok",
	}, TransportGlyphs.DECK_SIZE)
	_slot = MediaSlot.new()
	_slot.host = self
	_slot.slot = _disc_slot
	_slot.insert_depth = SLOT_INSET
	add_child(_slot)
	_slot.inserted.connect(_on_media_inserted)
	_slot.removed.connect(_on_media_removed)
	_dress()
	_play_button.button_pressed.connect(_on_play_pressed)
	_pause_button.button_pressed.connect(_on_pause_pressed)
	_stop_button.button_pressed.connect(_on_stop_pressed)
	_menu_button.button_pressed.connect(_on_menu_pressed)
	_prev_button.button_pressed.connect(dvd_prev_chapter)
	_next_button.button_pressed.connect(dvd_next_chapter)
	_rewind_button.button_pressed.connect(_on_rewind_pressed)
	_ff_button.button_pressed.connect(_on_ff_pressed)
	_eject_button.button_pressed.connect(_on_eject_pressed)
	_setup_box_buttons()

	if ClassDB.class_exists("VlcPlayer"):
		_vlc = ClassDB.instantiate("VlcPlayer")
		_vlc.finished.connect(_on_disc_finished)
		# Build the libVLC instance on its own thread now. Left to the first open(),
		# it walks the whole plugin tree on the main thread, a second-long freeze on
		# the first press of play.
		_vlc.warm_up()
	else:
		push_error("[DVDPlayer] VlcPlayer extension not loaded — DVD playback unavailable")

	_setup_audio()
	_update_name_label()


## Wire the D-pad / select / language / subtitle caps on the box. They exist so the
## deck is usable without hunting for the remote; every one of them lands on the
## same method the remote's matching cell calls.
func _setup_box_buttons() -> void:
	_box_buttons = {
		"up": $UpButton, "down": $DownButton,
		"left": $LeftButton, "right": $RightButton,
		"ok": $SelectButton,
		"audio": $LanguageButton, "subtitle": $SubtitleButton,
	}
	for id: String in _box_buttons:
		var button := _box_buttons[id] as VRButton
		button.button_pressed.connect(_on_box_button.bind(id))
	_refresh_box_buttons()


func _on_box_button(id: String) -> void:
	if not _box_button_enabled(id, is_in_menu()):
		return
	match id:
		"up": dvd_menu_up()
		"down": dvd_menu_down()
		"left": dvd_menu_left()
		"right": dvd_menu_right()
		"ok": dvd_ok()
		"audio": dvd_cycle_audio()
		"subtitle": dvd_cycle_subtitle()


## Same rules the remote applies to its equivalent cells: the nav cluster only
## does anything inside a disc menu, the two track buttons only outside one.
func _box_button_enabled(id: String, in_menu: bool) -> bool:
	match id:
		"audio":
			return not in_menu and has_audio_options()
		"subtitle":
			return not in_menu and has_subtitle_options()
	return in_menu


func _refresh_box_buttons() -> void:
	var in_menu := is_in_menu()
	for id: String in _box_buttons:
		var lit := _box_button_enabled(id, in_menu)
		if _box_button_lit.get(id) == lit:
			continue
		_box_button_lit[id] = lit
		var button := _box_buttons[id] as VRButton
		# A key the model gave its cap keeps the model's own colour and icon.
		if not button.state_tint:
			continue
		var col: Color = BOX_BTN_COLOR[id] if lit else COLOR_BTN_OFF
		button.set_color(col)


func _update_name_label() -> void:
	if _name_label:
		_name_label.text = dvd_label.to_upper()


## The cabinet a combo set builds this into is the housing: the model's body goes, its tray and keys stay.
func _housing() -> Array[Node3D]:
	var out: Array[Node3D] = [$DVDBody, _name_label]
	if _model:
		out.append_array(_model.parts("Body"))
		out.append_array(_model.parts("BodyPrint"))
	return out


func _front_panel() -> bool:
	return true


## Dress the player with its model: every key adopted onto the model's, the phono sockets on its jacks, the
## vacuum fluorescent display over its window, and the tray as the disc's way in (MediaSlot.ride_driver).
func _dress() -> void:
	if _model == null:
		push_warning("[DVD] %s: no Model node; drawn as the old box" % name)
		return
	for button_name: String in KEYS:
		DeckFace.adopt_front_key(_model, get_node(button_name) as VRButton, KEYS[button_name])
	for port: String in ["VideoOut", "AudioLOut", "AudioROut"]:
		DeckFace.seat_port(_model, get_node(port) as Node3D, port)
	_model.hide_part("Display")
	var panel := _model.part("Display") as MeshInstance3D
	var size := Vector2(0.154, 0.015)
	if panel != null and panel.mesh != null:
		var ab := panel.mesh.get_aabb()
		size = Vector2(ab.size.x, ab.size.y)
	_vfd = VfdDisplay.new()
	_vfd.name = "Vfd"
	_vfd.size_m = size
	_vfd.painter = _paint_vfd
	# Behind the model's smoked glass a VFD at 1.0 reads gray.
	_vfd.glow = 2.2
	_vfd.transform = _model.part_transform("Display", self).translated_local(Vector3(0.0, 0.0, 0.0002))
	add_child(_vfd)
	_slot.ride_driver = _ride_disc
	_sync_slot()
	# The body and the laser's box are what the model draws, no margin: the keys stand proud of it. Less the tray,
	# which has its own collision and goes out and in (_build_tray_body).
	_model.fit_shapes([get_node_or_null("CollisionShape3D") as CollisionShape3D,
		get_node_or_null("PointerArea/CollisionShape3D") as CollisionShape3D], ["Tray"])
	_build_tray_body()
	print("[DVD] %s: dressed with the RETRO XR model (%d levels, display %.0f x %.0f mm)"
		% [name, _model.levels.size(), size.x * 1000.0, size.y * 1000.0])


# --- The tray ---

## The tray is solid where it is drawn and nowhere else: a trimesh of the close level's own Tray mesh (no padding,
## the U-cutout and the well open), on a body riding on that Tray node, so it goes out and in with the drawer. The
## player's box ends at the fascia, so without it the open tray was air. A concave shape cannot be on a body that
## moves under physics, so it is an AnimatableBody3D of its own, on the player's layer (the desktop ray finds the
## player through it) and clear of the player it hangs on.
func _build_tray_body() -> void:
	var tray := _model.part("Tray") as MeshInstance3D
	if tray == null or tray.mesh == null:
		push_warning("[DVD] %s: the model has no Tray mesh; the tray has no collision" % name)
		return
	_tray_body = AnimatableBody3D.new()
	_tray_body.name = "TrayBody"
	_tray_body.sync_to_physics = false
	_tray_body.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var trimesh := tray.mesh.create_trimesh_shape()
	shape.shape = trimesh
	_tray_body.add_child(shape)
	tray.add_child(_tray_body)
	_tray_body.add_collision_exception_with(self)
	add_collision_exception_with(_tray_body)
	_sync_tray_layer()
	# Held, a pickable moves to its picked-up layer; the tray goes with it.
	picked_up.connect(func(_p: Variant) -> void: _sync_tray_layer.call_deferred())
	dropped.connect(func(_p: Variant) -> void: _sync_tray_layer.call_deferred())
	print("[DVD] %s: tray collision is its mesh, %d triangles" % [name, trimesh.get_faces().size() / 3])


func _sync_tray_layer() -> void:
	if is_instance_valid(_tray_body):
		_tray_body.collision_layer = collision_layer


## OPEN/CLOSE: a disc in the player goes out on the tray (or back in from it); an empty tray opens or closes.
func _on_tray_key() -> void:
	if _tray_anim != "":
		print("[DVD] %s: OPEN/CLOSE while the tray is moving; ignored" % name)
		return
	if _slot.has_media():
		_slot.toggle_eject()
		return
	_start_tray("Close" if _tray_open else "Open", false)


## The slot hands the disc to the tray (MediaSlot.ride_driver): in on Close, out on Open, or `instant`, seated
## with the tray shut (a restore).
func _ride_disc(media: Node3D, to_seat: bool, instant: bool) -> void:
	_ride_media = media
	_start_tray("Close" if to_seat else "Open", instant)


func _start_tray(anim: String, instant: bool) -> void:
	if _model == null or not _model.has_animation(anim):
		push_warning("[DVD] %s: the model has no %s; the tray does not move" % [name, anim])
		_tray_open = anim == "Open"
		if _ride_media != null:
			_ride_media = null
			_slot.end_ride()
		_sync_slot()
		return
	_tray_anim = anim
	_tray_t = _model.animation_length(anim) if instant else 0.0
	print("[DVD] %s: tray %s%s" % [name, anim, " (restored shut)" if instant else ""])
	_sync_slot()
	_step_tray(0.0)


func _step_tray(delta: float) -> void:
	if _tray_anim == "":
		return
	var length := _model.animation_length(_tray_anim)
	_tray_t = minf(_tray_t + delta, length)
	_model.seek(_tray_anim, _tray_t)
	if _ride_media != null:
		if is_instance_valid(_ride_media) and _slot.get_media() == _ride_media:
			_lay_on_seat(_ride_media)
		else:
			_ride_media = null
			_slot.end_ride()
	if _tray_t < length:
		return
	_tray_open = _tray_anim == "Open"
	print("[DVD] %s: tray %s" % [name, "out" if _tray_open else "in"])
	_tray_anim = ""
	if _ride_media != null:
		_ride_media = null
		_slot.end_ride()
		if not _tray_open:
			_loading_until = Time.get_ticks_msec() + LOADING_MSEC
	_sync_slot()


## Lay the disc on the tray's DiscSeat, at the spin it went in at.
func _lay_on_seat(media: Node3D) -> void:
	var seat := _model.part_transform("DiscSeat", self)
	media.global_transform = global_transform * Transform3D(_slot.seat_basis(),
		seat.origin + Vector3(0.0, DISC_LIFT, 0.0))


## A disc goes in only onto the tray, out and still and empty.
func _sync_slot() -> void:
	_disc_slot.enabled = _tray_open and _tray_anim == "" and not _slot.has_media()


## True while the tray is out (or going out).
func is_tray_open() -> bool:
	return _tray_open if _tray_anim == "" else _tray_anim == "Open"


# --- The display ---

## What the display shows now, and redraw it if that changed.
func _update_vfd() -> void:
	if _vfd == null:
		return
	var word := ""
	if _tray_anim == "Open" or (_tray_open and _tray_anim == ""):
		word = "OPEN"
	elif _tray_anim == "Close":
		word = "CLOSE"
	elif not _slot.has_media():
		word = "NO DISC"
	elif Time.get_ticks_msec() < _loading_until:
		word = "LOADING"
	elif not is_playing:
		word = "STOP"
	elif is_in_menu():
		word = "MENU"
	var title := -1
	var chapter := -1
	var secs := -1
	if word.is_empty() and _vlc != null:
		title = int(_vlc.get_title())
		chapter = int(_vlc.get_chapter())
		secs = int(float(_vlc.get_time()) / 1000.0)
	var key := "%s|%d|%d|%d|%d|%d" % [word, title, chapter, secs, int(_paused), _scan_dir]
	if key == _vfd_key:
		return
	_vfd_key = key
	_vfd_state = {"word": word, "title": title, "chapter": chapter, "secs": secs, "paused": _paused,
		"scan": _scan_dir}
	_vfd.refresh()


## TITLE nn CHP nn H:MM:SS in seven segments after a play or pause symbol, or one word for the tray and the disc
## (OPEN, CLOSE, NO DISC, LOADING, STOP, MENU), in Michroma. 10 px a millimeter of panel.
func _paint_vfd(c: Control, size: Vector2) -> void:
	if _vfd_state.is_empty():
		return
	var word: String = _vfd_state["word"]
	var h := size.y
	if not word.is_empty():
		var fs := int(h * 0.62)
		var w := VfdDisplay.font().get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		VfdDisplay.text(c, word, Vector2((size.x - w) / 2.0, h * 0.74), fs, true)
		return
	var paused: bool = _vfd_state["paused"]
	var x := h * 0.25
	var mid := h * 0.5
	if paused:
		c.draw_rect(Rect2(x, h * 0.25, h * 0.14, h * 0.5), VfdDisplay.LIT)
		c.draw_rect(Rect2(x + h * 0.26, h * 0.25, h * 0.14, h * 0.5), VfdDisplay.LIT)
	else:
		c.draw_colored_polygon(PackedVector2Array([Vector2(x, h * 0.25), Vector2(x + h * 0.42, mid),
			Vector2(x, h * 0.75)]), VfdDisplay.LIT)
	var dh := h * 0.72
	var dw := dh * 0.46
	var t := dh * 0.09
	var pitch := dw * 1.22
	var top := (h - dh) / 2.0
	var lbl := int(h * 0.2)
	x = h * 1.05
	VfdDisplay.text(c, "TITLE", Vector2(x, top + dh), lbl, true)
	x += h * 0.95
	VfdDisplay.digits(c, "%02d" % clampi(int(_vfd_state["title"]), 0, 99), Vector2(x, top), dw, dh, t, pitch)
	x += pitch * 2.0 + h * 0.3
	VfdDisplay.text(c, "CHP", Vector2(x, top + dh), lbl, true)
	x += h * 0.7
	VfdDisplay.digits(c, "%02d" % clampi(int(_vfd_state["chapter"]), 0, 99), Vector2(x, top), dw, dh, t, pitch)
	var secs: int = maxi(int(_vfd_state["secs"]), 0)
	@warning_ignore("integer_division")
	var clock := "%d%02d%02d" % [(secs / 3600) % 10, (secs % 3600) / 60, secs % 60]
	x = size.x - (pitch * 5.0 + h * 0.6) - h * 0.3
	for i in 5:
		VfdDisplay.digit(c, clock[i], Rect2(x, top, dw, dh), t)
		x += pitch
		if i == 0 or i == 2:
			# The colon: two dots between the hours and minutes, and the minutes and seconds.
			c.draw_rect(Rect2(x - h * 0.02, top + dh * 0.3, t, t), VfdDisplay.LIT)
			c.draw_rect(Rect2(x - h * 0.06, top + dh * 0.68, t, t), VfdDisplay.LIT)
			x += h * 0.3


func _process(delta: float) -> void:
	_refresh_box_buttons()
	_step_tray(delta)
	_update_vfd()
	if _vlc == null:
		return
	# Pump the latest decoded frame into the VLC texture every frame.
	_vlc.update_frame()
	_pump_audio()
	_update_scan(delta)
	# Low-rate refresh of the cached audio/subtitle track counts (the remote reads
	# these to grey its Audio/Subtitle cells).
	if is_playing:
		_track_refresh_accum += delta
		if _track_refresh_accum >= 0.5:
			_track_refresh_accum = 0.0
			_refresh_track_counts()
	# Emanate the sound from the connected TV so it's spatialised there, aimed the
	# way its picture points -- a set heard from behind should be muted by its own
	# cabinet.
	if _emitter and is_instance_valid(connected_tv):
		_emit_through(connected_tv)
	elif _emitter:
		_emitter.clear_speaker_positions()
		_emitter.clear_emit_position()
		_emitter.clear_emit_direction()


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


## Toggle the disc menu-control routing is done via the remote; the front Menu
## button just returns to the disc's root menu.
func _on_menu_pressed() -> void:
	dvd_root_menu()


# --- Disc slot callbacks ---

## MediaSlot accepted a disc (the insert ride has begun). Cache its path and report
## the insert; playback is user-started (remote / Play button) or host-driven in a
## session — insert never auto-plays.
func _on_media_inserted(disc: Node3D) -> void:
	if disc.has_method("get_dvd_path"):
		dvd_path = disc.get_dvd_path()
	_log_event("disc in: %s" % dvd_path)
	NetworkManager.report_event(NetEvents.Event.EV_DVD_INSERT,
		{"dvd": self, "disc": disc, "yaw": disc_seat_yaw()})


## MediaSlot reports the disc left (ejected, or pulled straight out). Stop playback
## and clear state.
func _on_media_removed() -> void:
	stop()
	dvd_path = ""
	_log_event("disc out")
	NetworkManager.report_event(NetEvents.Event.EV_DVD_REMOVE, {"dvd": self})


func _on_eject_pressed() -> void:
	_log_event("pressed OPEN/CLOSE")
	_on_tray_key()


# --- Playback controls ---

func remote_play() -> void: _on_play_pressed()
func remote_pause() -> void: _on_pause_pressed()
func remote_stop() -> void: _on_stop_pressed()
func remote_ff() -> void: _on_ff_pressed()
func remote_rewind() -> void: _on_rewind_pressed()
func remote_eject() -> void: _on_eject_pressed()
## True when a disc is loaded (the remote greys its Eject cell otherwise).
func has_media() -> bool: return _slot.has_media()


func _log_tag() -> String:
	return "DVD"


func _on_play_pressed() -> void:
	_log_event("pressed PLAY")
	if _net_forward_cmd("play"):
		return
	if not is_playing:
		play()
	else:
		# Leaving a scan or resuming from pause both mean "back to normal play".
		_set_scan(0)
		_vlc.set_paused(false)
		_paused = false
		_osd("PLAY")
		_net_push_state()


func _on_pause_pressed() -> void:
	_log_event("pressed PAUSE")
	if _net_forward_cmd("pause"):
		return
	if is_playing and _vlc:
		_set_scan(0)
		_vlc.set_paused(true)
		_paused = true
		_osd("PAUSE")
		_net_push_state()


## Fast-forward button: toggle forward scan (press again, or Play/Pause, to exit).
## No-op while showing a disc menu (there's nothing to scan through there).
func _on_ff_pressed() -> void:
	_log_event("pressed FF")
	if _net_forward_cmd("ff"):
		return
	if not is_playing or is_in_menu():
		return
	if _scan_dir == 1:
		_set_scan(0)
		_osd("PLAY")
	else:
		_set_scan(1)
		_osd("FF >>")


## Rewind button: toggle reverse scan (press again, or Play/Pause, to exit).
func _on_rewind_pressed() -> void:
	_log_event("pressed REW")
	if _net_forward_cmd("rew"):
		return
	if not is_playing or is_in_menu():
		return
	if _scan_dir == -1:
		_set_scan(0)
		_osd("PLAY")
	else:
		_set_scan(-1)
		_osd("<< REW")


## Enter (dir = ±1) or leave (dir = 0) a scan. The player keeps playing (frames
## present) but is muted while scanning; leaving restores the prior volume.
func _set_scan(dir: int) -> void:
	_scan_dir = dir
	_scan_accum = 0.0
	if _vlc:
		_vlc.set_paused(false)
	_paused = false
	if _emitter:
		_emitter.set_volume(0.0 if dir != 0 else _volume_linear)


## While scanning, jump the (still-playing) position forward/back in throttled
## steps so frames visibly race by; hold at either end of the title.
func _update_scan(delta: float) -> void:
	if _scan_dir == 0 or not is_playing or _vlc == null:
		return
	if is_in_menu():
		_set_scan(0)
		return
	_scan_accum += delta
	if _scan_accum < SCAN_SEEK_INTERVAL:
		return
	var length := float(_vlc.get_length())
	var pos := float(_vlc.get_time()) + _scan_accum * scan_speed * 1000.0 * float(_scan_dir)
	_scan_accum = 0.0
	if length <= 0.0:
		return
	if pos <= 0.0:
		_vlc.set_position(0.0)
		_end_scan_hold()
	elif pos >= length:
		_vlc.set_position(1.0)
		_end_scan_hold()
	else:
		_vlc.set_position(clampf(pos / length, 0.0, 1.0))


func _end_scan_hold() -> void:
	_set_scan(0)
	if _vlc:
		_vlc.set_paused(true)
	_paused = true
	_osd("PAUSE")
	_net_push_state()


func _on_stop_pressed() -> void:
	_log_event("pressed STOP")
	if _net_forward_cmd("stop"):
		return
	stop()


func play() -> void:
	if _vlc == null:
		push_error("[DVDPlayer] VlcPlayer unavailable (extension not loaded)")
		return
	if connected_tv == null:
		push_error("[DVDPlayer] cannot play - no TV connected")
		return
	if dvd_path.is_empty():
		push_error("[DVDPlayer] cannot play - no disc inserted")
		return
	if not _vlc.open(dvd_path, true):
		push_error("[DVDPlayer] VlcPlayer.open failed for ", dvd_path)
		return
	_vlc.play()
	# Full internal gain — level is controlled by the Godot 3D player (TV knob).
	_vlc.set_volume(100)
	is_playing = true
	_paused = false
	_scan_dir = 0
	_n_audio = -1        # unknown until libVLC parses the new disc
	_n_sub = -1
	if _emitter:
		_emitter.flush()
		_emitter.set_volume(_volume_linear)
	_log_event("playing %s" % dvd_path)
	_osd("DVD")
	_net_push_state()


func stop() -> void:
	if not is_playing:
		return
	_scan_dir = 0
	if _vlc:
		_vlc.stop()
	is_playing = false
	_paused = false
	_n_audio = -1
	_n_sub = -1
	if _emitter:
		_emitter.flush()
	if _watching_tv():
		connected_tv.hide_osd()
	_net_push_state()


func _on_disc_finished() -> void:
	_log_event("disc finished")
	is_playing = false


# --- DVD menu / chapter control (called by the remote) ---

func dvd_menu_up() -> void:
	_log_event("pressed UP")
	if _net_forward_cmd("menu_up"): return
	if _vlc: _vlc.menu_up()
	_net_push_state()


func dvd_menu_down() -> void:
	_log_event("pressed DOWN")
	if _net_forward_cmd("menu_down"): return
	if _vlc: _vlc.menu_down()
	_net_push_state()


func dvd_menu_left() -> void:
	_log_event("pressed LEFT")
	if _net_forward_cmd("menu_left"): return
	if _vlc: _vlc.menu_left()
	_net_push_state()


func dvd_menu_right() -> void:
	_log_event("pressed RIGHT")
	if _net_forward_cmd("menu_right"): return
	if _vlc: _vlc.menu_right()
	_net_push_state()


func dvd_ok() -> void:
	_log_event("pressed OK")
	if _net_forward_cmd("ok"): return
	if _vlc: _vlc.menu_activate()
	_net_push_state()


func dvd_root_menu() -> void:
	_log_event("pressed MENU")
	if _net_forward_cmd("root"): return
	if _vlc:
		# Real "Menu" button: return to the disc's root menu from anywhere (a
		# popup navigate does nothing mid-title on most discs).
		_vlc.go_to_menu()
		_osd("MENU")
	_net_push_state()


func dvd_next_chapter() -> void:
	_log_event("pressed NEXT CHAPTER")
	if _net_forward_cmd("next_ch"): return
	if _vlc:
		_vlc.next_chapter()
		_osd("NEXT")
	_net_push_state()


func dvd_prev_chapter() -> void:
	_log_event("pressed PREV CHAPTER")
	if _net_forward_cmd("prev_ch"): return
	if _vlc:
		_vlc.prev_chapter()
		_osd("PREV")
	_net_push_state()


## Whether the disc is currently showing a menu (drives the remote's button set).
func is_in_menu() -> bool:
	return _vlc != null and _vlc.is_in_menu()


# --- Audio-track / subtitle cycling (called by the remote) ---

func dvd_cycle_audio() -> void:
	_log_event("pressed AUDIO")
	if _net_forward_cmd("audio"): return
	_cycle_audio_local()
	_net_push_state()


func dvd_cycle_subtitle() -> void:
	_log_event("pressed SUBTITLE")
	if _net_forward_cmd("subtitle"): return
	_cycle_subtitle_local()
	_net_push_state()


## Advance to the next audio track (wraps), OSD the new track name.
func _cycle_audio_local() -> void:
	if _vlc == null:
		return
	var tracks: Array = _vlc.get_audio_tracks()
	if tracks.size() <= 1:
		_osd("AUDIO: —")
		return
	var id := _next_track_id(tracks, _vlc.get_audio_track())
	_vlc.set_audio_track(id)
	_log_event("audio track %s" % _track_name(tracks, id))
	_osd("AUDIO: " + _track_name(tracks, id))
	_refresh_track_counts()


## Advance to the next subtitle track (wraps; libVLC's list includes a -1 "Disable"
## entry, so cycling naturally passes through subtitles-off).
func _cycle_subtitle_local() -> void:
	if _vlc == null:
		return
	var tracks: Array = _vlc.get_subtitle_tracks()
	if tracks.is_empty():
		_osd("SUB: —")
		return
	var id := _next_track_id(tracks, _vlc.get_subtitle())
	_vlc.set_subtitle(id)
	_log_event("subtitles %s" % _track_name(tracks, id))
	_osd("SUB: " + _track_name(tracks, id))
	_refresh_track_counts()


## Next id after `cur` in a [{id,name}] track list, wrapping around.
func _next_track_id(tracks: Array, cur: int) -> int:
	var ids: Array = []
	for t: Dictionary in tracks:
		ids.append(int(t["id"]))
	if ids.is_empty():
		return cur
	var idx := ids.find(cur)
	return int(ids[(idx + 1) % ids.size()])


## Human label for a track id (falls back to "Off" for -1, else the raw id).
func _track_name(tracks: Array, id: int) -> String:
	for t: Dictionary in tracks:
		if int(t["id"]) == id:
			var n := str(t["name"])
			if not n.is_empty():
				return n
			return "Off" if id == -1 else str(id)
	return "—"


## Refresh the cached audio/subtitle track counts used for remote greying.
func _refresh_track_counts() -> void:
	if _vlc == null or not is_playing:
		_n_audio = -1
		_n_sub = -1
		return
	_n_audio = (_vlc.get_audio_tracks() as Array).size()
	_n_sub = (_vlc.get_subtitle_tracks() as Array).size()


## Whether the disc offers more than one audio track (read by the TV remote to
## grey the Audio cell). Optimistic while the count is still unknown (-1).
func has_audio_options() -> bool:
	return _n_audio < 0 or _n_audio > 1


## Whether the disc offers a real subtitle beyond libVLC's "Disable" entry.
func has_subtitle_options() -> bool:
	return _n_sub < 0 or _n_sub > 1


# ── Multiplayer sync (Phase 5) ────────────────────────────────────────────────
# Host is transport + menu authority. A client's transport/menu intent is
# forwarded to the host, which executes it and broadcasts DVD state; every peer
# plays its own local disc copy and drift-corrects to the host's title/chapter/
# time. Disc images are verify-only (MD5), never sent (see file_transfer.gd).

## Client-in-session: route a transport/menu intent to the host instead of
## acting locally. Returns true when forwarded (caller must then return).
func _net_forward_cmd(cmd: String) -> bool:
	if NetworkManager.is_client() and not NetworkManager.is_event_applying():
		NetworkManager.report_event(NetEvents.Event.EV_DVD_CMD, {"dvd": self, "cmd": cmd})
		return true
	return false


## Host: broadcast the current transport state for peer drift sync (no-op
## offline / on clients / while applying a remote event).
func _net_push_state() -> void:
	if NetworkManager.is_host() and not NetworkManager.is_event_applying():
		NetworkManager.report_media_state(self)


## Current transport state for the sync layer.
func net_get_state() -> Dictionary:
	if not is_playing or _vlc == null:
		return {"playing": false, "paused": false, "title": 0, "chapter": 0,
			"time": 0, "length": 0, "menu": false, "audio": -1, "sub": -1}
	return {
		"playing": true,
		"paused": _paused,
		"title": _vlc.get_title(),
		"chapter": _vlc.get_chapter(),
		"time": _vlc.get_time(),
		"length": _vlc.get_length(),
		"menu": _vlc.is_in_menu(),
		"audio": _vlc.get_audio_track(),
		"sub": _vlc.get_subtitle(),
	}


## Client: mirror the host's transport state on the LOCAL player.
func net_apply_state(state: Dictionary) -> void:
	var playing := bool(state.get("playing", false))
	var paused := bool(state.get("paused", false))
	var title := int(state.get("title", 0))
	var chapter := int(state.get("chapter", 0))
	var time_ms := int(state.get("time", 0))
	var length_ms := int(state.get("length", 0))
	var menu := bool(state.get("menu", false))
	var audio_id := int(state.get("audio", -1))
	var sub_id := int(state.get("sub", -1))
	if not playing:
		if is_playing:
			stop()
		return
	# The disc path is resolved by object_sync after insertion (verify-only);
	# refresh in case it landed after the insert event.
	var disc := _slot.get_media()
	if dvd_path.is_empty() and disc and disc.has_method("get_dvd_path"):
		dvd_path = disc.get_dvd_path()
	if not is_playing:
		if dvd_path.is_empty() or connected_tv == null:
			_osd("WAITING FOR DISC…")
			return
		play()
	if not is_playing or _vlc == null:
		return
	# Follow the host's title so menu↔playback transitions (incl. the "Menu"
	# button returning to a menu title) track on every peer. Chapter/time drift
	# is only corrected during actual playback; the menu-highlight VM state is
	# not replicated (host is the menu authority).
	if _vlc.get_title() != title:
		_vlc.set_title(title)
	if not menu:
		if _vlc.get_chapter() != chapter:
			_vlc.set_chapter(chapter)
		if length_ms > 0 and absf(float(_vlc.get_time() - time_ms)) > NET_DRIFT_TOLERANCE * 1000.0:
			_vlc.set_position(clampf(float(time_ms) / float(length_ms), 0.0, 1.0))
	_vlc.set_paused(paused)
	_paused = paused
	# Follow the host's audio/subtitle selection (shared TV screen).
	if audio_id >= 0 and _vlc.get_audio_track() != audio_id:
		_vlc.set_audio_track(audio_id)
	if _vlc.get_subtitle() != sub_id:
		_vlc.set_subtitle(sub_id)


# ── Save/load + net restore ───────────────────────────────────────────────────

func get_snapped_disc() -> Node3D:
	return _slot.get_media()


## The spin the seated disc is at, relative to the authored seat (MediaSlot.seat_yaw).
func disc_seat_yaw() -> float:
	return _slot.seat_yaw()


## Seat a disc programmatically (event/save restore) — no ride, bypasses the filter.
## `yaw` is the spin it was seated at (disc_seat_yaw) when saved or inserted remotely.
func restore_media(disc: Node3D, yaw: float = 0.0) -> void:
	_slot.restore(disc, yaw)


## The counterpart to restore_media, for a remote peer taking the disc out.
##
## Releases the snap zone rather than running the local eject ride: the disc is
## already gone on the peer that moved it, and object_sync positions it here.
## Which child holds the disc stays this deck's business.
func net_release_disc() -> void:
	_disc_slot.drop_object()


# --- Options panel (audio track / subtitles) ---

## Toggle the floating DVD settings panel. Called by SpawnMenuController when the
## menu button is pressed while pointing at this player.
func toggle_options_ui(camera: Node3D) -> void:
	if _options_panel == null:
		return
	if _options_panel.visible:
		_options_panel.hide_panel()
	else:
		_options_panel.show_for(self, camera)


func get_audio_tracks() -> Array:
	return _vlc.get_audio_tracks() if _vlc else []


func get_audio_track() -> int:
	return _vlc.get_audio_track() if _vlc else -1


func set_audio_track(id: int) -> void:
	_log_event("audio track set to %d" % id)
	if _vlc:
		_vlc.set_audio_track(id)


func get_subtitle_tracks() -> Array:
	return _vlc.get_subtitle_tracks() if _vlc else []


func get_subtitle() -> int:
	return _vlc.get_subtitle() if _vlc else -1


func set_subtitle(id: int) -> void:
	_log_event("subtitles set to %d" % id)
	if _vlc:
		_vlc.set_subtitle(id)


func _osd(text: String) -> void:
	var tv := _watching_tv()
	if tv:
		tv.show_osd_timed(text, 2.0)


# --- TV connection contract ---
#
# on_tv_connected/on_tv_disconnected are gone: they were the captive lead's, called
# by the set when a CablePlug carrying a back-reference to its host arrived. A
# composite cable's plugs belong to no device, so the deck works out its own
# connection instead — see on_av_topology_changed. A console still uses the old
# path, which is why the set still has it.


func set_audio_volume(volume: float) -> void:
	_volume_linear = clampf(volume, 0.0, 1.0)
	# Don't fight an active scan mute; it restores on scan exit.
	if _emitter and _scan_dir == 0:
		_emitter.set_volume(_volume_linear)


## Part of the TV contract: the set's mono switch, applied to the disc's own
## sound. See SpatialAudioEmitter.set_channel_mode.
func set_audio_channel_mode(mode: int) -> void:
	if _emitter:
		_emitter.set_channel_mode(mode)


# --- What the set reads ---
#
# The deck no longer paints anything. It answers one question — is there a picture
# — and RetroTV builds the material. set_screen_enabled, _screen_allowed,
# _may_paint, _bind_screen_to_tv and _blank_screen all existed to keep this deck's
# painting in step with a set that was painting too. There is one painter now.


## The disc's live frame, or null when there is nothing to show: stopped, or the
## picture cord is not in the set's video socket. A different object after a
## resolution change, so the set re-reads it per frame.
func get_video_texture() -> Texture2D:
	if _vlc == null or not is_playing or not _feed_video:
		return null
	return _vlc.get_texture()


# --- A/V out ---
#
# The deck has three sockets and no lead of its own. A composite cable is spawned
# and plugged in, and what plays depends entirely on which sockets its cords reach:
# picture only when a cord joins this VideoOut to the set's video in, the left
# channel only when one joins AudioLOut to an audio in — and if that one lands in
# the set's RIGHT socket, the left channel comes out of the right-hand speaker.
# CompositeCable works out the pairs; this only reads them.


