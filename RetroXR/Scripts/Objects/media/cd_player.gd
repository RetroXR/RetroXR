## CDPlayer — a pickable CD deck that plays an inserted audio CD (AudioDisc). Adds
## Prev/Next track skipping on top of the shared RetroAudioPlayer transport; the
## TV remote shows the full set (prev / play / pause / stop / ff / rew / next).
##
## It wears the RETRO XR CD player (RetroXR-models generic/cd-player): a front tray
## like the DVD player's (a DeckDrawer on the model's Open / Close, carrying the
## disc on DiscSeat): OPEN/CLOSE slides it out, a disc let go on it is taken, and
## it rides in. The vacuum fluorescent display shows the tray, TRACK and the time,
## REPEAT / SHUFFLE and the 20-track music calendar. REPEAT plays the album round
## again, SHUFFLE picks what plays next. The model has no REW / FF keys: their
## buttons stay (the remote scans) but are out of play. PHONES is a 3.5 mm jack whose headphones take the sound
## (audio_player.gd, "PHONES"), at the level its LEVEL knob sets. The phono pair on its back is a line out.
class_name CDPlayer
extends RetroAudioPlayer

## The model's key for each scene button.
const KEYS := {"OpenButton": "ButtonOpenClose", "PrevButton": "ButtonPrev", "PlayButton": "ButtonPlay",
	"PauseButton": "ButtonPause", "StopButton": "ButtonStop", "NextButton": "ButtonNext",
	"RepeatButton": "ButtonRepeat", "ShuffleButton": "ButtonShuffle"}
## A disc's center stands this far over DiscSeat (the well's floor): half the 4 mm disc.
const DISC_LIFT := 0.002
## How long the display says LOADING after the tray has closed on a disc.
const LOADING_MSEC := 1200
## How many tracks the music calendar shows.
const CALENDAR := 20
## The fascia's face (the model's front, z +145 mm): the body's box stops there, the LEVEL knob standing out of it.
const FRONT := 0.145

## REPEAT: the album plays round again. SHUFFLE: the next track is any other one. The host's own in a session.
var repeat := false
var shuffle := false

var _slot: MediaSlot = null
var _model: ApplianceModel = null
var _drawer: DeckDrawer = null
var _vfd: VfdDisplay = null
var _vfd_state: Dictionary = {}
var _vfd_key := ""
var _loading_until := 0


func _ready() -> void:
	_media_group = "audio_disc"
	super._ready()
	add_to_group("cd_player")
	TransportGlyphs.label_buttons(self, {
		"OpenButton": "eject", "PrevButton": "prev", "RewindButton": "rew",
		"PlayButton": "play", "PauseButton": "pause", "StopButton": "stop",
		"FastForwardButton": "ff", "NextButton": "next",
	}, TransportGlyphs.DECK_SIZE)


## The tray, through the shared MediaSlot and the model's DeckDrawer; the keys, the display and the line out. Run from
## the base's _ready before it colours the transport keys, so the adopted ones keep the model's own.
func _setup_loader() -> void:
	_slot = MediaSlot.new()
	_slot.host = self
	_slot.slot = _media_slot
	add_child(_slot)
	_slot.inserted.connect(_on_disc_in)
	_slot.removed.connect(_media_unloaded)
	_model = get_node_or_null("Model") as ApplianceModel
	if _model == null or _model.levels.is_empty():
		push_warning("[CD] %s: no model; the deck has no tray" % name)
		return
	for button_name: String in KEYS:
		var b := get_node_or_null(button_name) as VRButton
		if b:
			DeckFace.adopt_front_key(_model, b, KEYS[button_name])
	# The model has no REW / FF: the buttons stay for the remote's scan (has_scan), out of play on the box.
	for n: String in ["RewindButton", "FastForwardButton"]:
		var b := get_node_or_null(n) as VRButton
		if b:
			b.set_active(false)
	_drawer = DeckDrawer.new()
	_drawer.name = "Tray"
	_drawer.host = self
	_drawer.model = _model
	_drawer.slot = _slot
	_drawer.zone = _media_slot
	_drawer.seat_part = "DiscSeat"
	_drawer.seat_offset = Vector3(0.0, DISC_LIFT, 0.0)
	_drawer.tag = "CD"
	add_child(_drawer)
	_drawer.setup()
	_drawer.settled.connect(func(open: bool) -> void:
		if not open and _slot.has_media():
			_loading_until = Time.get_ticks_msec() + LOADING_MSEC)
	(get_node("OpenButton") as VRButton).button_pressed.connect(_on_open_pressed)
	(get_node("RepeatButton") as VRButton).button_pressed.connect(_on_repeat_pressed)
	(get_node("ShuffleButton") as VRButton).button_pressed.connect(_on_shuffle_pressed)
	for port: String in ["AudioLOut", "AudioROut"]:
		DeckFace.seat_port(_model, get_node(port) as Node3D, port)
		# A recursive find on the deck must meet the port, not the model's empty of the same name.
		for mouth in _model.parts(port):
			mouth.name = port + "Mouth"
	_model.hide_part("Display")
	var panel := _model.part("Display") as MeshInstance3D
	var size := Vector2(0.198, 0.03)
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
	var nl := get_node_or_null("NameLabel") as Node3D
	if nl:
		nl.visible = false
	_dress_phones()
	# The body and the laser's box are what the model draws, no margin: less the tray, which goes out and in.
	_model.fit_shapes([get_node_or_null("CollisionShape3D") as CollisionShape3D,
		get_node_or_null("PointerArea/CollisionShape3D") as CollisionShape3D], ["Tray"], FRONT)
	_build_tray_body()
	print("[CD] %s: dressed with the RETRO XR model (%d levels, display %.0f x %.0f mm)"
		% [name, _model.levels.size(), size.x * 1000.0, size.y * 1000.0])


## PHONES and LEVEL: the jack on the model's PhonesOut mouth, and the model's PhonesLevel knob (every level) hung on
## the LevelKnob's pivot at the knob's axis, so turning the VRKnob turns it. The knob's box is the knob.
func _dress_phones() -> void:
	var jack := get_node_or_null("PhonesOut") as Node3D
	if jack != null and _model.part("PhonesOut") != null:
		DeckFace.seat_port(_model, jack, "PhonesOut")
		for mouth in _model.parts("PhonesOut"):
			mouth.name = "PhonesOutMouth"
	else:
		push_warning("[CD] %s: no PHONES jack (scene %s, model %s)" % [name, jack != null, _model.part("PhonesOut") != null])
	var knob := get_node_or_null("LevelKnob") as VRKnob
	var cap := _model.part("PhonesLevel")
	if knob == null or cap == null:
		push_warning("[CD] %s: no LEVEL knob (scene %s, model %s)" % [name, knob != null, cap != null])
		return
	var ab := ApplianceModel.node_bounds(cap, self)
	knob.position = Vector3(ab.get_center().x, ab.get_center().y, ab.position.z)
	var pivot := knob.get_node("KnobPivot") as Node3D
	var turned := pivot.rotation
	pivot.rotation = Vector3.ZERO
	_model.attach_part("PhonesLevel", pivot)
	var level := 0
	for part in pivot.get_children():
		part.name = "ModelLevel%d" % level       # one per level, siblings now: named apart
		level += 1
	# Fitted with the pivot at rest: the cap's box then, which turning a round cap about its axis keeps (a box taken
	# with the pivot turned would be the turned box's bounds, larger than the cap).
	var first := pivot.get_node_or_null("ModelLevel0")
	if first != null:
		ApplianceModel.fit_box(knob.get_node_or_null("CollisionShape3D") as CollisionShape3D,
			ApplianceModel.node_bounds(first, knob))
	pivot.rotation = turned
	knob.value_changed.connect(set_phones_level)
	set_phones_level(knob.value)
	print("[CD] %s: PHONES jack and LEVEL knob on the model (level %.2f)" % [name, phones_level])


## The tray is solid where it is drawn and nowhere else, as the DVD player's: a trimesh of the close level's own Tray
## mesh on a body riding that node, so it goes out and in with the drawer, on the player's layer and clear of it.
func _build_tray_body() -> void:
	var tray := _model.part("Tray") as MeshInstance3D
	if tray == null or tray.mesh == null:
		push_warning("[CD] %s: the model has no Tray mesh; the tray has no collision" % name)
		return
	var body := AnimatableBody3D.new()
	body.name = "TrayBody"
	body.sync_to_physics = false
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	shape.shape = tray.mesh.create_trimesh_shape()
	body.add_child(shape)
	tray.add_child(body)
	body.add_collision_exception_with(self)
	add_collision_exception_with(body)
	var sync_layer := func() -> void:
		if is_instance_valid(body):
			body.collision_layer = collision_layer
	sync_layer.call()
	picked_up.connect(func(_p: Variant) -> void: sync_layer.call_deferred())
	dropped.connect(func(_p: Variant) -> void: sync_layer.call_deferred())


## The disc is in: the transport's state; it plays when PLAY is pressed, once the tray is in.
func _on_disc_in(disc: Node3D) -> void:
	_media_loaded(disc)


## The CD never auto-plays — the user presses PLAY once the tray is in over a disc.
func _autoplay_on_load() -> bool:
	return false


## OPEN/CLOSE. Opening mid-play stops it, as a real player does.
func _on_open_pressed() -> void:
	_log_event("pressed OPEN/CLOSE")
	if _drawer == null:
		return
	if is_playing and not _drawer.is_open():
		stop()
	_drawer.press()


func _on_repeat_pressed() -> void:
	repeat = not repeat
	_log_event("REPEAT %s" % ("on" if repeat else "off"))
	_update_vfd()


func _on_shuffle_pressed() -> void:
	shuffle = not shuffle
	_log_event("SHUFFLE %s" % ("on" if shuffle else "off"))
	_update_vfd()


## What plays when `idx` ends: SHUFFLE any other track (repeating only with REPEAT on: a shuffled album otherwise ends
## once every track has had its turn), REPEAT round to the first, else the next one to the end.
func _track_after(idx: int) -> int:
	var count := _tracks.size()
	if count == 0:
		return -1
	if shuffle and count > 1:
		_shuffle_played[idx] = true
		var left: Array[int] = []
		for i in count:
			if not _shuffle_played.has(i):
				left.append(i)
		if left.is_empty():
			if not repeat:
				_shuffle_played.clear()
				return -1
			_shuffle_played.clear()
			for i in count:
				if i != idx:
					left.append(i)
		return left[randi() % left.size()]
	if idx + 1 < count:
		return idx + 1
	return 0 if repeat else -1


var _shuffle_played := {}


func restore_media(media: Node3D, yaw: float = 0.0) -> void:
	if _slot:
		_slot.restore(media, yaw)


func media_seat_yaw() -> float:
	return _slot.seat_yaw() if _slot else 0.0


## The disc goes out on the tray (the net layer's remove: a peer took it).
func remove_media() -> void:
	if _slot and _slot.has_media():
		_slot.eject()


## True while the tray is out (or going out).
func is_tray_open() -> bool:
	return _drawer != null and _drawer.is_open()


func _log_tag() -> String:
	return "CD"


func deck_save_type() -> String:
	return "cd_player"


func _process(delta: float) -> void:
	super._process(delta)
	_update_vfd()


# --- The display ---

## What the display shows now, and redraw it if that changed (the time once a second).
func _on_mains_redraw() -> void:
	_vfd_key = ""
	if _vfd != null:
		_vfd.refresh()


func _update_vfd() -> void:
	if _vfd == null:
		return
	var word := ""
	var moving := _drawer.moving() if _drawer else ""
	if moving == "Open" or (moving == "" and is_tray_open()):
		word = "OPEN"
	elif moving == "Close":
		word = "CLOSE"
	elif _slot == null or not _slot.has_media():
		word = "NO DISC"
	elif Time.get_ticks_msec() < _loading_until:
		word = "LOADING"
	var secs := int(_vlc_time_sec()) if is_playing else 0
	var tracks := _tracks.size()
	var key := "%s|%d|%d|%d|%d|%d|%d|%d" % [word, _track_idx, secs, tracks, int(is_playing), int(_paused),
		int(repeat), int(shuffle)]
	if key == _vfd_key:
		return
	_vfd_key = key
	_vfd_state = {"word": word, "track": _track_idx + 1, "secs": secs, "tracks": tracks, "playing": is_playing,
		"paused": _paused, "repeat": repeat, "shuffle": shuffle}
	_vfd.refresh()


## One word for the tray and the disc (OPEN, CLOSE, NO DISC, LOADING), or a play / pause mark, TRACK nn and m:ss in
## seven segments, REPEAT / SHUFFLE lamps, and under them the music calendar: the disc's tracks lit, the one playing
## boxed. RetroXR-models generic/cd-player tools/vfd.py's layout.
func _paint_vfd(c: Control, size: Vector2) -> void:
	# No power, no display.
	if not mains_live():
		return
	if _vfd_state.is_empty():
		return
	var h := size.y
	var word: String = _vfd_state["word"]
	var fs := int(h * 0.1)
	VfdDisplay.text(c, "REPEAT", Vector2(size.x - h * 1.6, h * 0.17), fs, _vfd_state["repeat"])
	VfdDisplay.text(c, "SHUFFLE", Vector2(size.x - h * 1.6, h * 0.34), fs, _vfd_state["shuffle"])
	if not word.is_empty():
		var wfs := int(h * 0.3)
		var w := VfdDisplay.font().get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, wfs).x
		VfdDisplay.text(c, word, Vector2((size.x - w) / 2.0, h * 0.5), wfs, true)
		return
	var x := h * 0.23
	if _vfd_state["paused"]:
		c.draw_rect(Rect2(x, h * 0.16, h * 0.055, h * 0.22), VfdDisplay.LIT)
		c.draw_rect(Rect2(x + h * 0.11, h * 0.16, h * 0.055, h * 0.22), VfdDisplay.LIT)
	else:
		c.draw_colored_polygon(PackedVector2Array([Vector2(x, h * 0.16), Vector2(x + h * 0.19, h * 0.27),
			Vector2(x, h * 0.38)]), VfdDisplay.LIT if _vfd_state["playing"] else VfdDisplay.GHOST)
	var dh := h * 0.4
	var dw := dh * 0.45
	var t := dh * 0.1
	var top := h * 0.07
	VfdDisplay.text(c, "TRACK", Vector2(h * 0.77, top + dh), fs, true)
	VfdDisplay.digits(c, "%02d" % clampi(int(_vfd_state["track"]), 0, 99), Vector2(h * 1.42, top), dw, dh, t,
		dw * 1.26)
	var secs: int = _vfd_state["secs"]
	@warning_ignore("integer_division")
	var mm := "%2d" % mini(secs / 60, 99)
	x = h * 2.4
	VfdDisplay.digits(c, mm, Vector2(x, top), dw, dh, t, dw * 1.26)
	x += dw * 2.52
	c.draw_rect(Rect2(x, top + dh * 0.28, t, t), VfdDisplay.LIT)
	c.draw_rect(Rect2(x, top + dh * 0.66, t, t), VfdDisplay.LIT)
	x += h * 0.1
	VfdDisplay.digits(c, "%02d" % (secs % 60), Vector2(x, top), dw, dh, t, dw * 1.26)
	var tracks: int = _vfd_state["tracks"]
	var cur: int = _vfd_state["track"]
	var pitch := (size.x - h * 0.4) / float(CALENDAR)
	var cfs := int(h * 0.087)
	for i in CALENDAR:
		var cx := h * 0.2 + pitch * (i + 0.5)
		var label := str(i + 1)
		var w := VfdDisplay.font().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, cfs).x
		VfdDisplay.text(c, label, Vector2(cx - w / 2.0, h * 0.9), cfs, i < tracks)
		if i + 1 == cur and tracks > 0:
			var sb := StyleBoxFlat.new()
			sb.draw_center = false
			sb.border_color = VfdDisplay.LIT
			sb.set_border_width_all(maxi(2, int(h * 0.012)))
			sb.draw(c.get_canvas_item(), Rect2(cx - pitch * 0.42, h * 0.78, pitch * 0.84, h * 0.17))
