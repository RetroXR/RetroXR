## A surround amplifier: a stereo line in, a matrix decoder, and the six outputs a
## surround rig is cabled to — FL, FR, C, SUB, SL, SR.
##
## ── Why there is so little audio code here ───────────────────────────────────
## The same reason a television has none. The SOURCE owns its voices and decodes its
## own stereo (SystemAudio, through the libretro extension's FreeSurround), so being a
## decoder is three answers: "decode", "with this decoder", and "here is where the six
## channels land". The landing is the television's own SPEAKERS-row logic, shared
## through SpeakerRig, so a channel with no cabinet folds exactly as it does there.
##
## ── Two ways to reach it ─────────────────────────────────────────────────────
## A machine's own white and red cords into AUDIO IN: the amplifier is that machine's
## SOUND sink (AvSource), is told so through on_av_source_found, and pushes its decoder
## and its level at it. The picture can go to a set as usual; the set then leaves the
## sound alone (TvAudio.carries_sound).
##
## Or a set's FL and FR into AUDIO IN, with the set on STEREO OUT — its line out. The
## set finds the amplifier on its front pair (TvFit.decoder), asks its machines to
## decode with this amplifier's decoder, and answers for the six from here. The set is
## told when anything here changes (on_decoder_changed).
##
## ── The decoder switch ───────────────────────────────────────────────────────
## SURROUND MODE steps between the two matrix decoders of the era: PRO LOGIC II, two
## full-range surrounds, and the first-generation DOLBY SURROUND decoder — ONE
## surround, 100 Hz to 7 kHz and 20 ms late, from both rears (ProLogicSurround in
## surround-godot). The names are the formats a game's own options menu prints;
## nothing here claims certification, and there is no logo on the panel.
##
## ── The sink contract ────────────────────────────────────────────────────────
## Duck-typed, as Loudspeaker and SpeakerPair answer it:
##   on_av_topology_changed  — what RcaPort.get_device() looks for
##   get_speaker_positions   — the front pair, for a source that plays stereo
##   get_surround_positions / gains / targets — the six, as RetroTV answers them
##   has_cabled_speakers, is_surround_decoder — what makes it an amplifier
##   on_av_source_found/lost — who it is carrying
##   show_osd_timed/hide_osd, get_screen_mesh — absorbed; there is no screen
class_name SurroundAmp
extends XRToolsPickable

## Which decoder. The values ARE SurroundDecoder::Mode in surround-godot and cross the
## libretro extension unchanged; they are also saved and sent over the wire, so this
## list only grows at the end.
enum DecodeMode { PRO_LOGIC_II, DOLBY_SURROUND }

## What the display and the logs call each, indexed by DecodeMode.
const DECODE_NAMES := ["PRO LOGIC II", "DOLBY SURROUND"]

const GROUP := "surround_amp"

## The six outputs, in RcaPort.SPEAKER_OUT_CHANNELS order. The scene authors them.
const SPEAKER_OUT_NAMES := ["SpeakerOutL", "SpeakerOutR", "SpeakerOutC",
	"SpeakerOutLfe", "SpeakerOutSl", "SpeakerOutSr"]

## The display's glow when a decode has somewhere to go, and with nothing cabled to
## the back — dimmed, as a real unit's VFD reads "NO SPEAKER" in a darker segment.
const DISPLAY_LIT := Color(0.42, 0.95, 0.88)
const DISPLAY_DIM := Color(0.16, 0.36, 0.34)

## The front-panel VFD (a VfdDisplay on the model's window): 301 x 39 mm, drawn at
## 6 px/mm. With no speaker cabled everything lit drops to VFD_DIM, as the Label3D it
## replaced did; a speaker lamp is lit only while its own output has a cabinet.
const VFD_PX_PER_MM := 6.0
const VFD_DIM := Color8(52, 84, 96)
## How far past 1 the display is driven so it reads lit through the 60 % smoked glass.
const VFD_GLOW := 2.2
## Segments in the level bar: the knob's position, a step per segment.
const VFD_BARS := 30
## The speaker map, in SPEAKER_OUT_NAMES order: the word a VFD prints and where its lamp
## sits about the seat, in units of a sixth of the panel's height.
const VFD_LAMPS := [["L", Vector2(-3.2, -2.1)], ["R", Vector2(3.2, -2.1)], ["C", Vector2(0.0, -2.3)],
	["SW", Vector2(0.0, 2.3)], ["SL", Vector2(-4.2, 0.3)], ["SR", Vector2(4.2, 0.3)]]

var decode_mode: int = DecodeMode.PRO_LOGIC_II

@onready var _model: ApplianceModel = $Model
@onready var _mode_btn: VRButton = $ModeButton
@onready var _knob: VRKnob = $VolumeKnob
@onready var _display: Label3D = $DisplayText
@onready var _inputs: Array[RcaPort] = [$AudioInL, $AudioInR]

var _outputs: Array[RcaPort] = []

## 0..1, the knob's position.
var _volume: float = 0.75

## Machines whose sound this amplifier carries, from on_av_source_found.
var _sources: Array[Node3D] = []

## Where each output goes, keyed by RcaPort.Channel — TvPanel._speaker_dest's shape.
## Resolved when a plug moves, never walked per frame.
var _speaker_dest: Dictionary = {}

var _vfd: VfdDisplay = null
## The level bar's step last drawn, so turning the knob redraws only on a new step.
var _vfd_step: int = -1


func _ready() -> void:
	super()
	add_to_group("spawned")
	add_to_group(GROUP)
	for out_name in SPEAKER_OUT_NAMES:
		var out := get_node_or_null(out_name) as RcaPort
		if out != null:
			_outputs.append(out)
	_volume = _knob.value
	_knob.value_changed.connect(_on_volume)
	_mode_btn.button_pressed.connect(cycle_mode)
	_dress()
	_print_legends()
	_refresh_display()


# ── the sink contract ────────────────────────────────────────────────────────

## What makes this a decoder rather than a cabinet. A set's front pair cabled here is
## how TvFit.decoder recognises it, and SpeakerRig.cabinet_of refuses to treat one with
## no speakers of its own as somewhere to play.
func is_surround_decoder() -> bool:
	return true


## A plug moved somewhere in the room. Re-resolve the OUTPUTS — a link where this is
## the IN end belongs to whatever is feeding it — and tell everyone who reads them.
func on_av_topology_changed(_links: Array) -> void:
	var had := has_cabled_speakers()
	_speaker_dest = AvSource.resolve(self, true).audio_dest
	_refresh_display()
	# The first speaker plugged in, or the last pulled, lifts or brings back the
	# silence; the routing itself is read per frame and needs no push.
	if had != has_cabled_speakers():
		_push_volume_all()
	_notify_upstream()


## Where a stereo source's left and right come out: where FL and FR go, folds and all.
## With nothing cabled that is the amplifier's own box, at a gain of zero — a source
## that plays stereo is silenced by the volume this pushes instead.
func get_speaker_positions() -> PackedVector3Array:
	var pos: PackedVector3Array = _route()[0]
	return PackedVector3Array([pos[0], pos[1]])


func get_surround_positions() -> PackedVector3Array:
	return _route()[0]


func get_surround_gains() -> PackedFloat32Array:
	return _route()[1]


func get_surround_targets() -> Array:
	return _route()[2]


func has_cabled_speakers() -> bool:
	return SpeakerRig.has_cabled(_speaker_dest)


## Sound leaves the cabinets wherever a hand put them, not along any one facing.
func is_sound_external() -> bool:
	return true


func on_av_source_found(source: Node3D) -> void:
	if not _sources.has(source):
		_sources.append(source)
	_push_to(source)
	print("[SurroundAmp] %s: carrying %s on %s" % [name, source.name, DECODE_NAMES[decode_mode]])


## Hand the machine back in the state a set expects to find it in: not decoding, and
## on Pro Logic II. Called BEFORE the next sink is told it has the machine (RetroSystem
## loses old sinks first), so a set that takes it over sets its own mode on top.
func on_av_source_lost(source: Node3D) -> void:
	if not _sources.has(source):
		return          # already replaced by another source
	_sources.erase(source)
	if not is_instance_valid(source):
		return
	if source.has_method("set_audio_out_mode"):
		source.set_audio_out_mode(RetroTV.AudioOut.TV_SPEAKERS)
	if source.has_method("set_surround_mode"):
		source.set_surround_mode(DecodeMode.PRO_LOGIC_II)


## No screen here. Present because the DVD player reads it without guarding.
func get_screen_mesh() -> MeshInstance3D:
	return null


func show_osd_timed(_text: String, _seconds: float = 2.0) -> void:
	pass


func hide_osd() -> void:
	pass


# ── the switch and the knob ──────────────────────────────────────────────────

## SURROUND MODE: the next decoder.
func cycle_mode() -> void:
	set_decode_mode((decode_mode + 1) % DECODE_NAMES.size())


## Switch decoders. Tells every machine this carries, and every set feeding it, and
## the other peers in a session — each peer decodes its own sound, but they share the
## room, and the switch on the panel has to read the same for all of them.
func set_decode_mode(mode: int) -> void:
	mode = clampi(mode, 0, DECODE_NAMES.size() - 1)
	if mode == decode_mode:
		return
	decode_mode = mode
	_refresh_display()
	for source in _live_sources():
		if source.has_method("set_surround_mode"):
			source.set_surround_mode(decode_mode)
	_notify_upstream()
	print("[SurroundAmp] %s: SURROUND MODE -> %s" % [name, DECODE_NAMES[decode_mode]])
	NetworkManager.report_event(NetEvents.Event.EV_AMP_MODE, {"amp": self, "mode": decode_mode})


func get_volume() -> float:
	return _volume


## Set the knob and the level together — used by save/restore, which has no hand to
## turn it with.
func set_volume(v: float) -> void:
	_volume = clampf(v, 0.0, 1.0)
	if _knob != null:
		_knob.set_value_no_signal(_volume)
	_push_volume_all()
	_notify_upstream()
	_refresh_level()


func _on_volume(v: float) -> void:
	_volume = v
	_push_volume_all()
	_notify_upstream()
	_refresh_level()


## The level bar redraws on a new step only, not on every frame of a turn.
func _refresh_level() -> void:
	if _vfd != null and roundi(_volume * VFD_BARS) != _vfd_step:
		_vfd_step = roundi(_volume * VFD_BARS)
		_vfd.refresh()


# ── pushing ──────────────────────────────────────────────────────────────────

## What reaches the speakers: the knob, or nothing with no speaker plugged in — the
## same rule a set switched to external speakers follows.
func effective_volume() -> float:
	return _volume if has_cabled_speakers() else 0.0


## Everything a machine needs to be decoding through this amplifier. The decoder
## first, so the first block decoded is already the right one. Stereo, because the
## amplifier has no speaker switch to leave a set's mono setting standing.
func _push_to(source: Node3D) -> void:
	if not is_instance_valid(source):
		return
	if source.has_method("set_audio_channel_mode"):
		source.set_audio_channel_mode(SpatialAudioEmitter.ChannelMode.STEREO)
	if source.has_method("set_surround_mode"):
		source.set_surround_mode(decode_mode)
	if source.has_method("set_audio_out_mode"):
		source.set_audio_out_mode(RetroTV.AudioOut.SURROUND)
	if source.has_method("set_audio_volume"):
		source.set_audio_volume(effective_volume())


func _push_volume_all() -> void:
	for source in _live_sources():
		if source.has_method("set_audio_volume"):
			source.set_audio_volume(effective_volume())


func _live_sources() -> Array[Node3D]:
	var live: Array[Node3D] = []
	for source in _sources:
		if is_instance_valid(source):
			live.append(source)
	_sources = live
	return live


## Tell every set whose front pair feeds AUDIO IN that something here moved, so it
## re-reads the decoder, the speakers and the level. Asked of the cable graph each
## time rather than remembered: it runs on a press or a plug move, never per frame.
func _notify_upstream() -> void:
	var told: Array[Node3D] = []
	for link: Dictionary in AvGraph.links_for(self):
		var in_port := link["in"] as RcaPort
		if in_port == null or in_port.get_device() != self:
			continue
		var up := (link["out"] as RcaPort).get_device()
		if up == null or up == self or told.has(up) or not up.has_method("on_decoder_changed"):
			continue
		told.append(up)
		up.on_decoder_changed()


func _route() -> Array:
	# A channel with nowhere to go waits silent at the front of the box, mid-height.
	var rest: Vector3 = global_transform * Vector3(0.0, 0.0575, 0.17)
	return SpeakerRig.route(_speaker_dest, rest)


# ── the panel ────────────────────────────────────────────────────────────────

func _refresh_display() -> void:
	if _display == null:
		return
	_display.text = DECODE_NAMES[decode_mode]
	_display.modulate = DISPLAY_LIT if has_cabled_speakers() else DISPLAY_DIM
	if _vfd != null:
		_vfd_step = roundi(_volume * VFD_BARS)
		_vfd.refresh()


## Dress the scene's controls from the model (RetroXR-models generic/surround-receiver):
## the key's mesh into ModeButton, the knob under KnobPivot, a VfdDisplay on the window.
## Every level but the close one, and the display's own quad, stay out of the outline —
## three levels traced on top of each other would draw it three times.
func _dress() -> void:
	if _model == null or _model.levels.is_empty():
		push_warning("[SurroundAmp] %s: no model to dress the panel from" % name)
		return
	_model.adopt_button(_mode_btn, "ButtonSurroundMode")
	# adopt_button hands the key to VRButton.set_button_mesh, which hides whatever node
	# is named ButtonMesh — the cap adopt_button just filled. Shown again here.
	var cap := _mode_btn.get_node_or_null("ButtonMesh") as MeshInstance3D
	if cap != null:
		cap.visible = true
	# attach_part keeps where the knob is, so take the pivot to its rest first: the
	# model's knob is authored with its dot at 12 o'clock, VRKnob's 0 degrees.
	var pivot := _knob.get_node("KnobPivot") as Node3D
	var turned := pivot.rotation
	pivot.rotation = Vector3.ZERO
	_model.attach_part("VolumeKnob", pivot)
	# One knob per level, siblings now: named apart, or Godot names them @VolumeKnob@n.
	var level := 0
	for knob_part in pivot.get_children():
		knob_part.name = "ModelKnob%d" % level
		level += 1
	pivot.rotation = turned
	if _model.part("Display") == null:
		push_warning("[SurroundAmp] %s: the model has no Display" % name)
	else:
		_vfd = VfdDisplay.new()
		_vfd.name = "Vfd"
		_vfd.size_m = Vector2(0.301, 0.039)
		_vfd.px_per_mm = VFD_PX_PER_MM
		_vfd.painter = _paint_vfd
		_vfd.transform = _model.part_transform("Display").translated_local(Vector3(0.0, 0.0, 0.0003))
		add_child(_vfd)
		_model.hide_part("Display")
		# Behind the model's smoked glass (alpha 0.6) a plain unshaded quad reads grey: a
		# VFD glows through it, so its colour is driven past 1.
		var glow := _vfd.screen().material_override as StandardMaterial3D
		if glow != null:
			glow.albedo_color = Color(VFD_GLOW, VFD_GLOW, VFD_GLOW)
		_vfd.screen().add_to_group("outline_exclude")
	for i in range(1, _model.levels.size()):
		for m in _model.levels[i].find_children("*", "MeshInstance3D", true, false):
			m.add_to_group("outline_exclude")
	# The model marks each jack's mouth with an empty named like the RcaPort on it. The
	# Model node comes first in the tree, so a find_child for a port's name would reach
	# the empty before the port: the empties take a suffix.
	for port_name in ["AudioInL", "AudioInR"] + SPEAKER_OUT_NAMES:
		for mouth in _model.parts(port_name):
			mouth.name = port_name + "Mouth"
	print("[SurroundAmp] %s: dressed from the model (%d levels)" % [name, _model.levels.size()])


## Whether output `i` (SPEAKER_OUT_NAMES order) has a cabinet on it.
func is_output_cabled(i: int) -> bool:
	return SpeakerRig.cabinet_of(_speaker_dest.get(RcaPort.SPEAKER_OUT_CHANNELS[i])) != null


## Whether the VFD's lamp for output `i` is lit: a cabinet on that output.
func vfd_lamp_lit(i: int) -> bool:
	return has_cabled_speakers() and is_output_cabled(i)


## The VFD: the decoder's name large on the left with the knob's level bar under it, and
## the speaker map on the right, a lamp per output round the seat.
func _paint_vfd(c: Control, s: Vector2) -> void:
	var on := has_cabled_speakers()
	var ink := VfdDisplay.LIT if on else VFD_DIM
	c.draw_string(VfdDisplay.font(), Vector2(s.x * 0.03, s.y * 0.52), DECODE_NAMES[decode_mode],
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(s.y * 0.31), ink)
	var lit := roundi(_volume * VFD_BARS)
	var pitch := s.x * 0.55 / VFD_BARS
	for i in VFD_BARS:
		c.draw_rect(Rect2(s.x * 0.03 + i * pitch, s.y * 0.66, pitch * 0.62, s.y * 0.13),
			ink if i < lit else VfdDisplay.GHOST)
	var u := s.y / 6.0
	var seat := Vector2(s.x * 0.80, s.y * 0.5)
	c.draw_rect(Rect2(seat - Vector2(u * 0.9, u * 0.45), Vector2(u * 1.8, u * 0.9)), ink, false, 4.0)
	for i in VFD_LAMPS.size():
		var at: Vector2 = seat + (VFD_LAMPS[i][1] as Vector2) * u
		VfdDisplay.boxed(c, VFD_LAMPS[i][0], Rect2(at - Vector2(u * 0.75, u * 0.5), Vector2(u * 1.5, u * 1.0)),
			int(u * 0.55), vfd_lamp_lit(i))


## The two plates on the back: AUDIO IN over the pair, SPEAKERS over the six, in the
## words the television's own SPEAKERS row prints so the two panels read alike.
func _print_legends() -> void:
	var inputs := AvLegend.attach(self, _inputs)
	if inputs != null:
		inputs.name = "AvLegendIn"
		inputs.heading_override = "AUDIO IN"
		inputs.word_override = {RcaPort.Channel.AUDIO_L: "L", RcaPort.Channel.AUDIO_R: "R"}
		inputs.rebuild()
	var outputs := AvLegend.attach(self, _outputs)
	if outputs != null:
		outputs.name = "AvLegendSpeakers"
		outputs.heading_override = "SPEAKERS"
		outputs.word_override = TvPanel.SPEAKER_WORDS
		outputs.rebuild()
	# The model prints these same words on its back panel; the plates are still built,
	# as the measured statement of what the panel says, but hidden so the words are not
	# printed twice.
	if _model != null and not _model.levels.is_empty():
		for plate: AvLegend in [inputs, outputs]:
			if plate != null:
				plate.visible = false


# ── save / restore ───────────────────────────────────────────────────────────

## Put a saved switch back without a hand, and without announcing it: a room being
## loaded is not a player pressing SURROUND MODE. The knob needs nothing here — it is
## a VRKnob, which ScenePersistence restores with every other articulated control.
func restore_state(mode: int) -> void:
	decode_mode = clampi(mode, 0, DECODE_NAMES.size() - 1)
	_refresh_display()
	for source in _live_sources():
		_push_to(source)
	_notify_upstream()


## Release every seated lead before this amplifier is freed.
##
## ScenePersistence.clear_scene and StorageBox look for this by name. Without it a
## socket is left holding a freed pickable and XRToolsPickable._exit_tree walks a
## dangling grab driver — the trap CompositeCable.drop_and_free records.
func drop_and_free() -> void:
	for port: RcaPort in _inputs + _outputs:
		if is_instance_valid(port):
			port.drop_object()
	Vanish.free_node(self)
