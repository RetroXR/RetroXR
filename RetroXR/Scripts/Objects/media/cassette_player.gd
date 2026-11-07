## CassettePlayer — a pickable cassette deck that plays an inserted audio tape
## (AudioCassette). A linear tape: play / pause / stop / ff / rew only (no track
## skip). Tracks in a multi-song album still auto-advance as the tape "plays
## through"; the remote shows the same reduced control set.
##
## It wears the RETRO XR cassette deck (RetroXR-models generic/cassette-deck): the
## cassette stands in a door that tips out (a DeckDrawer on the model's Open /
## Close, carrying it on TapeSeat), the reel spindles behind it turn with the
## cassette's own hubs, and a vacuum fluorescent display shows the tape counter,
## the play direction, NR B/C and TYPE II and two peak meters. COUNTER RESET zeroes
## the counter; REC presses and does nothing more (the deck plays, it does not
## record). The phono pair on its back is a line out; PHONES under EJECT is a 3.5 mm jack whose headphones take the
## sound instead (audio_player.gd, "PHONES"), at the level the small LEVEL knob under it sets (PhonesKnob). The big
## knob at the right (LevelKnob, the model's REC LEVEL) is the deck's output level.
class_name CassettePlayer
extends RetroAudioPlayer

## The model's key for each scene button.
const KEYS := {"EjectButton": "ButtonEject", "RewindButton": "ButtonRewind", "PlayButton": "ButtonPlay",
	"StopButton": "ButtonStop", "FastForwardButton": "ButtonFastForward", "RecordButton": "ButtonRecord",
	"PauseButton": "ButtonPause", "CounterResetButton": "ButtonCounterReset"}
## Meter segments, as the display draws them (the VFD's resolution, so it redraws only when one changes).
const METER_SEGMENTS := 28
## The meters redraw at most this often while the tape plays (a SubViewport each time).
const METER_HZ := 12.0
## The fascia's face (the model's front, z +150 mm): the body's box stops there, the REC LEVEL knob standing out of it.
const FRONT := 0.150

var _slot: MediaSlot = null
var _model: ApplianceModel = null
var _drawer: DeckDrawer = null
var _vfd: VfdDisplay = null
var _vfd_state: Dictionary = {}
var _vfd_key := ""
var _vfd_meters := ""
var _vfd_wait := 0.0
## What the counter showed when COUNTER RESET was pressed: it counts from there.
var _counter_zero := 0
## The count it last read off a tape.
var _counter_last := 0


func _ready() -> void:
	_media_group = "audio_cassette"
	wants_levels = true
	# After the cassette's own shell has turned its hubs this frame, so the spindles stand at their angle, not last
	# frame's.
	process_priority = 1
	super._ready()
	add_to_group("cassette_player")
	TransportGlyphs.label_buttons(self, {
		"RewindButton": "rew", "PlayButton": "play", "PauseButton": "pause",
		"StopButton": "stop", "FastForwardButton": "ff", "EjectButton": "eject",
	}, TransportGlyphs.DECK_SIZE)


## The door, through the shared MediaSlot and the model's DeckDrawer; the keys, the display and the line out. Run from
## the base's _ready before it colours the transport keys, so the adopted ones keep the model's own.
func _setup_loader() -> void:
	_slot = MediaSlot.new()
	_slot.host = self
	_slot.slot = _media_slot
	add_child(_slot)
	_slot.inserted.connect(_media_loaded)
	_slot.removed.connect(_media_unloaded)
	_model = get_node_or_null("Model") as ApplianceModel
	if _model == null or _model.levels.is_empty():
		push_warning("[Cassette] %s: no model; the deck has no door" % name)
		return
	for button_name: String in KEYS:
		var b := get_node_or_null(button_name) as VRButton
		if b:
			DeckFace.adopt_front_key(_model, b, KEYS[button_name])
	_drawer = DeckDrawer.new()
	_drawer.name = "Door"
	_drawer.host = self
	_drawer.model = _model
	_drawer.slot = _slot
	_drawer.zone = _media_slot
	_drawer.seat_part = "TapeSeat"
	_drawer.tag = "Cassette"
	add_child(_drawer)
	_drawer.setup()
	(get_node("EjectButton") as VRButton).button_pressed.connect(_drawer.press)
	(get_node("CounterResetButton") as VRButton).button_pressed.connect(_on_counter_reset)
	(get_node("RecordButton") as VRButton).button_pressed.connect(func() -> void:
		_log_event("pressed REC: this deck plays tapes, it does not record"))
	for port: String in ["AudioLOut", "AudioROut"]:
		DeckFace.seat_port(_model, get_node(port) as Node3D, port)
		# The model marks each jack's mouth with an empty of the port's name; a recursive find on the deck must
		# meet the port, not the empty (the Model node comes first).
		for mouth in _model.parts(port):
			mouth.name = port + "Mouth"
	_dress_level_knob()
	DeckFace.dress_phones(self, _model, "PhonesKnob", "Cassette")
	_model.hide_part("Display")
	var panel := _model.part("Display") as MeshInstance3D
	var size := Vector2(0.19, 0.036)
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
	# The body and the laser's box are what the model draws, no margin: less the door, which tips out.
	_model.fit_shapes([get_node_or_null("CollisionShape3D") as CollisionShape3D,
		get_node_or_null("PointerArea/CollisionShape3D") as CollisionShape3D], ["Door", "DoorGlass"], FRONT)
	print("[Cassette] %s: dressed with the RETRO XR model (%d levels, display %.0f x %.0f mm)"
		% [name, _model.levels.size(), size.x * 1000.0, size.y * 1000.0])


## The front knob's axis on the model's face (x, y; m) and how far round it a triangle is
## still the knob's. The model draws the knob in its Body (it has no part of its own),
## standing 11 mm out of the fascia from FRONT.
const KNOB_AT := Vector2(0.186, -0.022)
const KNOB_REACH := 0.018
## Each Body mesh, cut in two: [the body less the knob, the knob]. Shared by every deck.
static var _knob_split := {}


## LEVEL: the model's front knob made a VRKnob that sets the deck's output level, as the CD
## player's LEVEL knob is. The knob's triangles are cut out of every level's Body onto the
## knob's pivot, so turning the VRKnob turns the knob that is drawn, and the knob's box is
## the knob: the body's boxes stop at FRONT, so a pointer reaches it.
func _dress_level_knob() -> void:
	var knob := get_node_or_null("LevelKnob") as VRKnob
	var bodies := _model.parts("Body")
	if knob == null or bodies.is_empty():
		push_warning("[Cassette] %s: no LEVEL knob (scene %s, model body %s)" % [name, knob != null, not bodies.is_empty()])
		return
	var pivot := knob.get_node("KnobPivot") as Node3D
	var caps: Array[MeshInstance3D] = []
	var hosts: Array[MeshInstance3D] = []
	for i in bodies.size():
		var body := bodies[i] as MeshInstance3D
		if body == null or body.mesh == null:
			continue
		var split := _split_knob(body.mesh)
		if split.is_empty():
			push_warning("[Cassette] %s: no knob found in level %d's Body" % [name, i])
			continue
		body.mesh = split[0]
		var cap := MeshInstance3D.new()
		cap.name = "ModelLevel%d" % i
		cap.mesh = split[1]
		cap.material_override = body.material_override
		cap.cast_shadow = body.cast_shadow
		cap.layers = body.layers
		cap.visibility_range_begin = body.visibility_range_begin
		cap.visibility_range_end = body.visibility_range_end
		cap.visibility_range_begin_margin = body.visibility_range_begin_margin
		cap.visibility_range_end_margin = body.visibility_range_end_margin
		cap.visibility_range_fade_mode = body.visibility_range_fade_mode
		for g in body.get_groups():
			if not str(g).begins_with("_"):
				cap.add_to_group(g)
		caps.append(cap)
		hosts.append(body)
	if caps.is_empty():
		return
	# The axis: the middle of the close level's knob, at its back (where it meets the fascia).
	var box := caps[0].mesh.get_aabb()
	var axis := global_transform.affine_inverse() * hosts[0].global_transform \
		* Vector3(box.get_center().x, box.get_center().y, box.position.z)
	knob.position = axis
	var turned := pivot.rotation
	pivot.rotation = Vector3.ZERO
	for i in caps.size():
		pivot.add_child(caps[i])
		caps[i].global_transform = hosts[i].global_transform
	ApplianceModel.fit_box(knob.get_node_or_null("CollisionShape3D") as CollisionShape3D,
		ApplianceModel.node_bounds(caps[0], knob))
	pivot.rotation = turned
	knob.value_changed.connect(_on_level_knob)
	set_output_level(knob.value)
	print("[Cassette] %s: LEVEL knob cut out of the model at (%.3f, %.3f, %.3f), %.0f mm across, level %.2f"
		% [name, axis.x, axis.y, axis.z, box.size.x * 1000.0, output_level])


func _on_level_knob(v: float) -> void:
	set_output_level(v)


## [body less the knob, the knob] for one of the model's Body meshes, or [] if no triangle
## stands out of the fascia round KNOB_AT. Cut once per mesh and shared.
static func _split_knob(src: Mesh) -> Array:
	if _knob_split.has(src):
		return _knob_split[src]
	var rest := ArrayMesh.new()
	var knob := ArrayMesh.new()
	var found := false
	for s in src.get_surface_count():
		var arr := src.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.is_empty():
			idx = PackedInt32Array(range(v.size()))
		var keep := PackedInt32Array()
		var take := PackedInt32Array()
		for i in range(0, idx.size() - 2, 3):
			var mine := true
			for k in 3:
				var p := v[idx[i + k]]
				if p.z <= FRONT + 0.0002 or Vector2(p.x, p.y).distance_to(KNOB_AT) > KNOB_REACH:
					mine = false
					break
			# Packed arrays are values: append to the one meant, not to a copy of it.
			if mine:
				take.append_array([idx[i], idx[i + 1], idx[i + 2]])
			else:
				keep.append_array([idx[i], idx[i + 1], idx[i + 2]])
		var mat := src.surface_get_material(s)
		if not keep.is_empty():
			var a := arr.duplicate()
			a[Mesh.ARRAY_INDEX] = keep
			rest.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
			rest.surface_set_material(rest.get_surface_count() - 1, mat)
		if not take.is_empty():
			found = true
			knob.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _compact(arr, take))
			knob.surface_set_material(knob.get_surface_count() - 1, mat)
	var out: Array = [rest, knob] if found else []
	_knob_split[src] = out
	return out


## A surface's arrays holding only the vertices `indices` use, renumbered: the knob's own
## mesh, whose bounds are then the knob's (with the body's whole vertex buffer they were the body's).
static func _compact(arr: Array, indices: PackedInt32Array) -> Array:
	var count := (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var remap := {}
	var order := PackedInt32Array()
	var new_idx := PackedInt32Array()
	for i in indices:
		if not remap.has(i):
			remap[i] = order.size()
			order.append(i)
		new_idx.append(remap[i])
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	for t in Mesh.ARRAY_MAX:
		if t == Mesh.ARRAY_INDEX or arr[t] == null:
			continue
		var src: Variant = arr[t]
		@warning_ignore("integer_division")
		var per: int = src.size() / count
		var dst: Variant = src.slice(0, 0)
		for i in order:
			dst.append_array(src.slice(i * per, i * per + per))
		out[t] = dst
	out[Mesh.ARRAY_INDEX] = new_idx
	return out


## A tape has no spin to keep; `_yaw` is accepted for the shared deck contract.
func restore_media(media: Node3D, _yaw: float = 0.0) -> void:
	if _slot:
		_slot.restore(media)


## Ejecting IS how a tape leaves a front loader — the door tips out with it.
func remove_media() -> void:
	if _slot:
		_slot.eject()


## True while the door is out (or going out).
func is_door_open() -> bool:
	return _drawer != null and _drawer.is_open()


func _log_tag() -> String:
	return "Cassette"


func deck_save_type() -> String:
	return "cassette_player"


func _process(delta: float) -> void:
	super._process(delta)
	_turn_spindles(delta)
	if not is_playing:
		levels = Vector2.ZERO
	_vfd_wait -= delta
	_update_vfd()


# --- The spindles ---

## A spindle's turn at play speed with no drawn hubs to follow (rad/s): a half-full reel's.
const SPINDLE_PLAY_RATE := 2.4

## The spindles turn the cassette's hubs. A drawn cassette (the xenu.cassette mod's shell, or any shell with hubs named
## HubSupply / HubTakeup) turns its hubs from the tape's own place, and each spindle stands at its hub's angle; a
## cassette with none (the stand-in box) has them turned at the tape's speed.
func _turn_spindles(delta: float) -> void:
	if _model == null:
		return
	var tape := _snapped_media if is_instance_valid(_snapped_media) else null
	if tape == null:
		return
	for pair: Array in [["ReelL", "HubSupply"], ["ReelR", "HubTakeup"]]:
		var hub := tape.find_child(pair[1], true, false) as Node3D
		for spindle in _model.parts(pair[0]):
			if hub != null:
				spindle.rotation.z = hub.rotation.z
			else:
				spindle.rotation.z = wrapf(spindle.rotation.z + float(tape.get("tape_speed")) * SPINDLE_PLAY_RATE * delta,
					0.0, TAU)


# --- The counter ---

## What the counter mechanism has counted: how far through the tape it is, a side's worth 0 .. 999. With the tape
## out it keeps the count it stopped at, as a mechanical counter does.
func _counter_raw() -> int:
	var tape := _tape()
	if tape:
		_counter_last = int(float(tape.get("tape_progress")) * 999.0)
	return _counter_last


## What the display shows: from the last reset, four digits.
func counter() -> int:
	return posmod(_counter_raw() - _counter_zero, 10000)


func _on_counter_reset() -> void:
	_counter_zero = _counter_raw()
	_log_event("COUNTER RESET at %d" % _counter_zero)
	_update_vfd()


# --- The display ---

## What the display shows now, and redraw it if that changed (the meters at most METER_HZ).
func _on_mains_redraw() -> void:
	_vfd_key = ""
	if _vfd != null:
		_vfd.refresh()


func _update_vfd() -> void:
	if _vfd == null:
		return
	var tape := _tape() != null or (_slot != null and _slot.has_media())
	var l := int(round(levels.x * METER_SEGMENTS))
	var r := int(round(levels.y * METER_SEGMENTS))
	var key := "%d|%d|%d|%d" % [counter(), int(tape), int(is_playing and not _paused), _scan_dir]
	var meters := "%d|%d" % [l, r]
	if key == _vfd_key and meters == _vfd_meters:
		return
	# Only the meters moved: no faster than METER_HZ.
	if key == _vfd_key and _vfd_wait > 0.0:
		return
	_vfd_wait = 1.0 / METER_HZ
	_vfd_key = key
	_vfd_meters = meters
	_vfd_state = {"counter": counter(), "tape": tape, "playing": is_playing and not _paused, "scan": _scan_dir,
		"l": l, "r": r}
	_vfd.refresh()


## The counter in seven segments with the play direction under it, NR B/C and TYPE II CrO2 (lit with a tape in), and
## two peak meters on a -20 .. +6 scale: RetroXR-models generic/cassette-deck tools/vfd.py's layout.
func _paint_vfd(c: Control, size: Vector2) -> void:
	# No power, no display.
	if not mains_live():
		return
	if _vfd_state.is_empty():
		return
	var h := size.y
	var dh := h * 0.44
	var dw := dh * 0.46
	var t := dh * 0.1
	var top := h * 0.11
	VfdDisplay.digits(c, "%04d" % int(_vfd_state["counter"]), Vector2(h * 0.17, top), dw, dh, t, dw * 1.27)
	var fwd: bool = _vfd_state["playing"] and int(_vfd_state["scan"]) >= 0
	var back: bool = int(_vfd_state["scan"]) < 0
	var ay := h * 0.73
	c.draw_colored_polygon(PackedVector2Array([Vector2(h * 0.31, ay), Vector2(h * 0.44, ay - h * 0.07),
		Vector2(h * 0.44, ay + h * 0.07)]), VfdDisplay.LIT if back else VfdDisplay.GHOST)
	c.draw_colored_polygon(PackedVector2Array([Vector2(h * 0.92, ay - h * 0.07), Vector2(h * 0.92, ay + h * 0.07),
		Vector2(h * 1.05, ay)]), VfdDisplay.LIT if fwd else VfdDisplay.GHOST)
	var lit: bool = _vfd_state["tape"]
	var fs := int(h * 0.095)
	VfdDisplay.text(c, "NR B/C", Vector2(h * 1.45, h * 0.31), fs, lit)
	VfdDisplay.text(c, "TYPE II CrO2", Vector2(h * 1.45, h * 0.49), fs, lit)
	var mx := size.x * 0.526
	var mw := size.x * 0.43
	var seg := mw / float(METER_SEGMENTS)
	for row: Array in [["L", int(_vfd_state["l"]), h * 0.19], ["R", int(_vfd_state["r"]), h * 0.58]]:
		VfdDisplay.text(c, row[0], Vector2(mx - h * 0.14, row[2] + h * 0.075), fs, true)
		for i in METER_SEGMENTS:
			var red := i >= METER_SEGMENTS - 6
			var on := i < int(row[1])
			var col := (VfdDisplay.RED if on else VfdDisplay.RED_GHOST) if red else (VfdDisplay.LIT if on else VfdDisplay.GHOST)
			c.draw_rect(Rect2(mx + i * seg + 1.0, row[2], seg - 3.0, h * 0.075), col)
	var marks := ["-20", "-10", "-6", "-3", "0", "+3", "+6"]
	var sfs := int(h * 0.07)
	for i in marks.size():
		var w := VfdDisplay.font().get_string_size(marks[i], HORIZONTAL_ALIGNMENT_LEFT, -1, sfs).x
		VfdDisplay.text(c, marks[i], Vector2(mx + mw * (0.06 + i * 0.148) - w / 2.0, h * 0.47), sfs, true)
