## SystemAudio — where a running machine's sound comes from, and how loud.
##
## A child of the RetroSystem it serves, created unconditionally because every
## machine makes sound, in the same shape as SaveStateController, MemoryCardController,
## HandheldInput and WiiLink.
##
## Lifted out of system.gd whole. It was the cleanest seam left in that file: no
## NetworkManager anywhere in it, no reach into the shell model beyond one
## is_handheld() test, and it owns every one of its fields outright.
##
## The two entry points stay on RetroSystem and forward here, because they are
## reached by DUCK TYPING rather than by type — tv.gd, speaker_pair.gd and the
## handheld/PSP/Virtual Boy models all call
## `x.has_method("set_audio_volume")` on whatever is plugged in, and a VCR and a
## DVD player answer the same two names. Moving them would have been a rename
## disguised as a refactor.
##
## The five audio_* tuning knobs also stay on RetroSystem: they are @export, so
## they are that node's authored inspector surface, and spatial_audio_emitter.gd
## documents one of them BY NAME as RetroSystem.audio_directivity.
##
## What this does NOT know is cabling. Which set the sound reaches, and which of
## that set's speakers each channel lands on, is the A/V cluster's business and
## arrives through one call — _host.audio_route(). Reading _av_ports and
## _av_speaker_l/_r from here would have put a second owner on the routing.
class_name SystemAudio
extends Node

## The machine this belongs to. Set by RetroSystem in setup(), never by _ready:
## the node is added before the host can hand itself over.
var _host: RetroSystem = null

## The Meta XR Audio mixer, when the core came up on that backend. Null on the
## AudioStreamPlayer3D fallback, which is the whole branch below.
var _mx: Object = null

## Voice ids the libretro AudioHandler created, empty on the fallback backend.
var _voices: PackedInt32Array = PackedInt32Array()

## The fallback backend's node, null when the voices are in use.
var _player: AudioStreamPlayer3D = null

## Whether a backend has actually been chosen yet. See ensure_bound().
var _bind_settled := false

## The level the TV last asked for, remembered so a core started later comes up
## at the volume the set is on.
var _last_volume: float = 1.0

## The set's mono switch, remembered for the same reason. See set_channel_mode.
var _channel_mode: int = 0

## Where the set is sending its sound — RetroTV.AudioOut. Remembered for the same
## reason as the mono switch: a core started later has to come up on it.
var _audio_out: int = 0

## Whether the extension really engaged the decoder. Asking for surround is not
## the same as getting it: the mixer can be out of voices, the decoder extension
## can be absent, and the fallback backend has no voices to place at all — in
## every case SetSurroundEnabled answers false and this stays on the stereo pair.
var _surround := false

## Per-channel trim the set last reported, in the decoder's order. A folded
## surround is 3 dB down; everything else is 1.0. Cached because _send_voice_gain
## is also reached from set_volume, which has no set to ask.
var _surround_gains := PackedFloat32Array()

## The base gain and the per-channel trims last fanned across the six, so an
## unchanged frame costs no call. The trims are memoised too, not only the base: a
## speaker plugged in mid-game moves a channel from 0 to full while the base stays
## put, and a memo on the base alone never sent it.
var _sent_surround_gain: float = -1.0
var _sent_surround_trims := PackedFloat32Array()

## Whether the six are going to the output device's own speakers as well, which a
## head-locked machine does on a PC wired for more than stereo. The voices keep
## playing silently beside them: they are what the extension's brake measures.
var _discrete := false
## The routing at full volume, input major, 6 x 8 -- see discrete_matrix. The
## level is folded in when it is sent, on the one gain path.
var _discrete_base := PackedFloat32Array()
var _sent_discrete := PackedFloat32Array()

## Cached body measurement, keyed on the model instance it was taken from.
var _geom_model_id: int = 0
var _centre_local: Vector3 = Vector3.ZERO
var _half_sep: float = 0.0

## The listener autoload, resolved once.
var _listener: Node = null

## Set while the desktop overlay has this machine's picture in the window: the
## two channels sit at these points rather than on the set or the shell.
var _head_lock := false
var _head_l := Vector3.ZERO
var _head_r := Vector3.ZERO

## Last values actually pushed to the mixer, so an unchanged frame costs no call.
var _sent_gain_l: float = -1.0
var _sent_gain_r: float = -1.0
var _sent_directivity: float = -1.0

## The distance law's current multiplier, folded into every gain we send.
var _dist_factor: float = 1.0


func setup(host: RetroSystem) -> void:
	_host = host


# ---------------------------------------------------------------------------
# What the television asks for
# ---------------------------------------------------------------------------


## Set the audio volume for the running libretro instance (0.0 = silent, 1.0 = 100%).
func set_volume(volume: float) -> void:
	_last_volume = clampf(volume, 0.0, 1.0)
	if not _host.is_powered_on:
		return
	if not _voices.is_empty() and _mx != null:
		# Applied here and now against the distance factor already measured, not
		# left for the next _process. A set being switched off has to go quiet at
		# once, and must not depend on this node being processed to do it.
		_send_voice_gain(_last_volume * _dist_factor)
		return
	_apply_player_volume()


## Part of the TV contract: the set's mono switch, applied to the core's own
## sound. The core's samples are deinterleaved into its voices inside the
## extension, so the mode is handed there rather than applied to a buffer here.
## Remembered so a core started later comes up on the set's current setting.
func set_channel_mode(mode: int) -> void:
	_channel_mode = clampi(mode, 0, 2)
	if _host.get_libretro_node() != null:
		_host.get_libretro_node().SetAudioChannelMode(_channel_mode)


## Part of the TV contract: where the set is sending its sound.
##
## SURROUND asks the extension to decode; anything else asks it to stop. The
## voice list changes with it — six while decoding, two otherwise — so it is
## re-read and the voices re-placed, which is also what releases the four extra
## ones back to a mixer that only has 32.
##
## Returns whether this machine is really decoding, which is not the same as having
## been asked to.
func set_audio_out_mode(mode: int) -> bool:
	_audio_out = mode
	_apply_audio_out()
	return _surround


func _apply_audio_out() -> void:
	var node: Libretro = _host.get_libretro_node()
	if node == null:
		return
	var want: bool = _audio_out == RetroTV.AudioOut.SURROUND
	var got: bool = node.SetSurroundEnabled(want)
	if got != _surround:
		_surround = got
		# The ids change wholesale, so re-read rather than patch: the front pair gets
		# voices of its own while decoding and hands them back afterwards.
		_voices = node.GetAudioVoiceIds()
		_sent_directivity = -1.0
		_sent_gain_l = -1.0
		_sent_gain_r = -1.0
		_sent_surround_gain = -1.0
		_sent_surround_trims = PackedFloat32Array()
		_surround_gains = PackedFloat32Array()
		# The extension let the device output go with the decode.
		_forget_discrete()
		update_position()
		_apply_bound_volume()
	# After the re-read, so an engaged machine reports the six it now has.
	if want:
		print("[SystemAudio] %s: surround %s" % [_log_label(), _surround_verdict(got)])


# ---------------------------------------------------------------------------
# Core lifecycle
# ---------------------------------------------------------------------------


## A fresh run re-asks which backend came up — that is decided per core start,
## and the first attempt is expected to find neither.
func rebind() -> void:
	_bind_settled = false
	bind()


## Bind whichever audio backend the core came up on. With Meta XR Audio the
## handler has already created a pair of voices and only needs them placed;
## otherwise it made an AudioStreamPlayer3D that needs this system's tuning.
func bind() -> void:
	# A fresh handler starts on stereo, so a set left on mono has to say so again —
	# and a set left on surround, likewise. Before GetAudioVoiceIds, because that
	# is what decides whether the list is two ids or six.
	_host.get_libretro_node().SetAudioChannelMode(_channel_mode)
	_surround = _host.get_libretro_node().SetSurroundEnabled(
		_audio_out == RetroTV.AudioOut.SURROUND)
	_forget_discrete()
	_voices = _host.get_libretro_node().GetAudioVoiceIds()
	if not _voices.is_empty():
		if Engine.has_singleton("MetaXRAudio"):
			_mx = Engine.get_singleton("MetaXRAudio")
		_player = null
		_sent_directivity = -1.0     # fresh voices start omni; force a re-send
		update_position()
		_apply_bound_volume()
		return

	_player = _host.get_libretro_node().get_node_or_null("AudioStreamPlayer3D") as AudioStreamPlayer3D
	if _player == null:
		return
	_player.unit_size        = _host.audio_unit_size
	_player.max_distance     = _host.audio_max_distance
	_player.panning_strength = _host.audio_panning_strength
	update_position()
	_apply_bound_volume()


## Drop both backends when the core stops. The nodes and voice ids belong to the
## run that just ended and mean nothing to the next one.
func on_core_stopped() -> void:
	_player = null
	_voices = PackedInt32Array()
	_forget_discrete()


## Keep trying to bind until it takes. StartContent only ENQUEUES the audio
## init — Wrapper posts a ThreadCommandInitAudio that the Libretro node drains in
## a later _process — so neither the voices nor the AudioStreamPlayer3D exist yet
## when _power_on calls bind() on the very next line.
##
## Binding once therefore left BOTH backends unset, and update_position()
## returned early for the rest of the session. The voices still played, from the
## SDK's default position: the world origin. Hardware that sits near the middle
## of the room sounds about right like that, which is why this went unnoticed
## until a handheld was carried around and its sound stayed behind.
##
## The wait ends on the handler's ANSWER, never on a deadline. It used to give up
## after 300 frames, which at 72 Hz is 4.2 s — and Dolphin reported its voices
## 8.1 s after power-on. The window closed first, the empty voice list was read as
## "this core runs on the fallback", and the AudioStreamPlayer3D was bound for the
## rest of the run. Nothing feeds that player once the handler picks the SDK, and
## the two voices it did create are never placed, so they never publish a pose —
## and the mixer does not mix a voice that has not said where it is. A silent Wii
## in a room where everything else could be heard.
##
## Elapsed frames only ever stood in for "a backend has been chosen", and the two
## agree solely for cores that come up fast. fceumm answers in about 34 frames and
## never noticed; Dolphin straddles the deadline, which is why the same build was
## silent on one launch and fine on the next — a warm shader cache decided it.
func ensure_bound() -> void:
	if _bind_settled or not _host.is_powered_on:
		return
	# IsAudioReady is the whole question. Before the sink is up an empty voice
	# list means "not asked yet"; after it, the same empty list means the fallback
	# backend, and that is the distinction nothing on this side could draw. A
	# non-null _player never could either: Wrapper creates that node
	# unconditionally, before the handler has chosen anything, so it is already
	# sitting there on the first attempt — keying the retry off it stopped the
	# retry dead.
	if not _host.get_libretro_node().IsAudioReady():
		return
	bind()
	_bind_settled = true


## Push the remembered level onto whichever backend was just bound. A voice is
## created at gain 1.0 and a fresh AudioStreamPlayer3D at 0 dB, so without this
## a restart resurrects the sound at full volume regardless of the TV.
func _apply_bound_volume() -> void:
	if not _voices.is_empty() and _mx != null:
		_sent_gain_l = -1.0        # see set_volume
		_sent_gain_r = -1.0
	else:
		_apply_player_volume()


# ---------------------------------------------------------------------------
# Cabling moved
# ---------------------------------------------------------------------------


## The A/V cluster telling us a cord was seated or pulled.
##
## The cached pair is keyed on the gains last sent, not on the routing, so a cord
## moving between sockets has to invalidate it or the new silence (or the new
## sound) never reaches the mixer. That cache belongs to the voices; the
## AudioStreamPlayer3D backend has its own level and is re-gated here, since
## nothing else re-reads the routing for it.
func route_changed() -> void:
	_sent_gain_l = -1.0
	_sent_gain_r = -1.0
	_apply_player_volume()


# ---------------------------------------------------------------------------
# Placing the sound
# ---------------------------------------------------------------------------


## A spawned machine's node is called "@RigidBody3D@4765", which names nothing a
## player can find in the room; its platform and game do.
func _log_label() -> String:
	var label := String(_host.name)
	if label.begins_with("@"):
		label = _host.systemid if not _host.systemid.is_empty() else "machine"
	if not _host.rom_path.is_empty():
		label += " (%s)" % _host.rom_path.get_file().get_basename()
	return label


## Why a machine is or is not decoding, for the log. The voices are what decide it:
## an empty list means the core came up on Godot's own stereo player, which is what
## the spatial audio SDK being off looks like from here.
func _surround_verdict(engaged: bool) -> String:
	if engaged:
		return "on, %d voices" % _voices.size()
	if not _host.is_powered_on:
		return "waiting — the machine is off, and takes it up when it starts"
	if _voices.is_empty() or _mx == null:
		return "declined — spatial audio is off, so this core plays through Godot's stereo player"
	return "declined — the decoder extension or the mixer's voices are unavailable"


## Put the six decoded voices on the six points the set reports, in the decoder's
## own order — FL, FR, C, LFE, SL, SR.
##
## OMNIDIRECTIONAL, always. update_position aims the stereo pair along the set's
## screen normal, which is right for a sound leaving one cabinet; a rig scattered
## round a room has no single baffle to point along, and two of the six are behind
## the listener. Same judgement speaker_pair.gd made.
##
## The LFE is placed but NOT spatialised any differently — Meta's own guidance is
## that a predominantly low-frequency source wants pan and attenuation rather than
## the HRTF, and a matrix source carries no discrete LFE anyway: ours is a
## synthesised sub-120 Hz band. It costs a voice either way, so it rides with the
## rest rather than earning a special case that buys nothing.
func _place_surround(tv: Node3D) -> void:
	var pos: PackedVector3Array = tv.get_surround_positions()
	if pos.size() != _voices.size():
		return
	var gains := PackedFloat32Array()
	if tv.has_method("get_surround_gains"):
		gains = tv.get_surround_gains()
	var ln := _listener_node()
	var lp := Vector3.ZERO
	if ln != null:
		lp = ln.get_listener_position()
	var centre := Vector3.ZERO
	for i in pos.size():
		var p: Vector3 = pos[i]
		centre += p
		if ln != null:
			p = SpatialAudioEmitter.hold_off_head(p, lp)
		_mx.set_voice_position(_voices[i], p)
	_apply_voice_directivity(Vector3.ZERO)
	# Cached rather than applied here, so the ONE gain path fans it — set_volume
	# reaches _send_voice_gain directly and has no set to ask for these.
	_surround_gains = gains
	# The distance law measures from the middle of the rig rather than from each
	# cabinet: a player standing beside the sub must not have the whole mix follow
	# them, and the per-voice HRTF already carries the individual distances.
	_apply_voice_distance_gain(centre / float(pos.size()))


## The six while the picture is in the window, desktop or focus mode: the room's
## speakers are no longer what the player is facing, so the channels leave the
## room with the picture -- but keep the layout the room gave them. A channel with
## its own speaker plugged in keeps it, one that folded keeps its fold, and nothing
## plugged in is still silence.
##
## Where they go depends on what the player is listening through. A PC wired for
## 5.1 or 7.1 gets them on its own speakers, one channel to one speaker, which
## beats any rendering of a speaker. Headphones and stereo speakers -- and every
## headset -- get a 5.1 room drawn around the head instead, turning with it, with
## no distance law: the player is sitting in the middle of it.
func _place_surround_held(tv: Node3D) -> void:
	var targets: Array = tv.get_surround_targets()
	var gains: PackedFloat32Array = tv.get_surround_gains()
	if targets.size() != 6 or gains.size() != 6:
		return
	_dist_factor = 1.0
	var mode := _device_speaker_mode()
	if mode != AudioServer.SPEAKER_MODE_STEREO and _set_discrete(discrete_matrix(targets, gains, mode)):
		# Still posed, so the mixer keeps draining them in step with the device's
		# queue; silent, so the room's speakers are heard once.
		_surround_gains = PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
		_send_voice_gain(_last_volume)
		return
	_set_discrete(PackedFloat32Array())
	var ln := _listener_node()
	var lp: Vector3 = ln.get_listener_position() if ln != null else Vector3.ZERO
	var ring := SpatialAudioEmitter.surround_ring(lp, _head_l, _head_r)
	var pos := ring_positions(ring, lp, targets)
	for i in pos.size():
		_mx.set_voice_position(_voices[i], pos[i])
	_apply_voice_directivity(Vector3.ZERO)
	_surround_gains = gains
	_send_voice_gain(_last_volume)


## What the output device can take, as an AudioServer.SpeakerMode. Stereo for a
## headset whatever the PC is wired for: the sound is going to the player's ears.
func _device_speaker_mode() -> int:
	var vp := get_viewport()
	if vp == null or vp.use_xr:
		return AudioServer.SPEAKER_MODE_STEREO
	return AudioServer.get_speaker_mode()


## Engage, re-route or (with an empty base) drop the device output. Answers whether
## it is engaged, which is false wherever the extension cannot make one -- the
## caller then draws the room around the head instead.
func _set_discrete(base: PackedFloat32Array) -> bool:
	var node: Libretro = _host.get_libretro_node()
	if base.is_empty():
		if _discrete and node != null:
			node.SetSurroundDiscrete(PackedFloat32Array())
			print("[SystemAudio] %s: surround back off this PC's own speakers" % _log_label())
		_forget_discrete()
		return false
	_discrete_base = base
	if _discrete:
		return true
	if node == null or not node.SetSurroundDiscrete(_scaled_discrete(_last_volume)):
		return false
	_discrete = true
	_sent_discrete = PackedFloat32Array()
	# The voices go silent on the next gain push, and their memo has to let it by.
	_sent_surround_gain = -1.0
	print("[SystemAudio] %s: surround to this PC's own %s speakers" % [_log_label(),
		SPEAKER_MODE_NAMES.get(AudioServer.get_speaker_mode(), "multichannel")])
	return true


func _forget_discrete() -> void:
	_discrete = false
	_discrete_base = PackedFloat32Array()
	_sent_discrete = PackedFloat32Array()


func _scaled_discrete(g: float) -> PackedFloat32Array:
	var m := _discrete_base.duplicate()
	for i in m.size():
		m[i] *= g
	return m


const SPEAKER_MODE_NAMES := {
	AudioServer.SPEAKER_SURROUND_31: "3.1",
	AudioServer.SPEAKER_SURROUND_51: "5.1",
	AudioServer.SPEAKER_SURROUND_71: "7.1",
}

## -10 dB on anything sent to the device's LFE channel. By the 5.1 convention the
## playback chain adds 10 dB to that channel, and ours carries the bass the decoder
## took out of the other five at the level it was taken, so without this the sub
## plays it 10 dB hot. Dolphin, the source of our decoder, sends it at unity; if
## players report a thin sub, this is the number.
const DISCRETE_LFE_TRIM := 0.3162278

## Which of the device's outputs one of the room's six speakers lands on, with a
## gain: `{output: gain}`, outputs numbered in Godot's pair order -- FL, FR, C,
## LFE, back L, back R, side L, side R. The surrounds are the fifth and sixth
## channels of a 5.1 device and the SIDE pair of a 7.1 one, which is where a 7.1
## room puts a 5.1 mix's surrounds; a 3.1 device has none, so they fold onto the
## fronts 3 dB down.
static func discrete_outputs(speaker: int, speaker_mode: int) -> Dictionary:
	match speaker:
		0:
			return {0: 1.0}
		1:
			return {1: 1.0}
		2:
			return {2: 1.0}
		3:
			return {3: DISCRETE_LFE_TRIM}
		4:
			if speaker_mode == AudioServer.SPEAKER_SURROUND_71:
				return {6: 1.0}
			if speaker_mode == AudioServer.SPEAKER_SURROUND_51:
				return {4: 1.0}
			return {0: TvFit.FOLD_GAIN}
		5:
			if speaker_mode == AudioServer.SPEAKER_SURROUND_71:
				return {7: 1.0}
			if speaker_mode == AudioServer.SPEAKER_SURROUND_51:
				return {5: 1.0}
			return {1: TvFit.FOLD_GAIN}
	return {}


## The 6 x 8 routing for the device, input major, from the set's own routing: each
## channel goes to the device output of the room speaker it landed on, at the gain
## it landed at. A channel between a PAIR of speakers plays from both, each 3 dB
## down, which is the same power the room's single phantom voice carries. Empty on
## a stereo device, which has no speakers of its own to give.
static func discrete_matrix(targets: Array, gains: PackedFloat32Array, speaker_mode: int) -> PackedFloat32Array:
	if speaker_mode == AudioServer.SPEAKER_MODE_STEREO:
		return PackedFloat32Array()
	var m := PackedFloat32Array()
	m.resize(48)
	m.fill(0.0)
	for ch in mini(targets.size(), gains.size()):
		var on: PackedInt32Array = targets[ch]
		var share: float = 1.0 if on.size() == 1 else TvFit.FOLD_GAIN
		for speaker in on:
			var outs := discrete_outputs(speaker, speaker_mode)
			for out: int in outs:
				m[ch * 8 + out] += gains[ch] * share * float(outs[out])
	return m


## The ring point each channel plays from: its speaker's, or for a pair the point
## between them pushed back out to the ring, so a centre folded between the fronts
## is dead ahead rather than a third of the way in. A channel with nowhere to go
## keeps its own point, where it is silent.
static func ring_positions(ring: PackedVector3Array, listener: Vector3, targets: Array) -> PackedVector3Array:
	var out := PackedVector3Array()
	var radius: float = ring[0].distance_to(listener) if ring.size() > 0 else 0.0
	for ch in ring.size():
		var on: PackedInt32Array = targets[ch] if ch < targets.size() else PackedInt32Array()
		if on.size() == 1:
			out.push_back(ring[on[0]])
		elif on.size() == 2:
			var mid := (ring[on[0]] + ring[on[1]]) * 0.5 - listener
			out.push_back(listener + mid.normalized() * radius if mid.length() > 0.0001 else ring[on[0]])
		else:
			out.push_back(ring[ch])
	return out


## Measure where this hardware's own sound should come from: the middle of its
## body, and a stereo gap of a fifth of its width, never wider than
## audio_speaker_separation. A fifth keeps a handheld's two voices well inside
## the shell while still reading as stereo, and leaves anything console-sized on
## the old figure.
##
## The body centre matters as much as the gap. A model's origin is not
## necessarily in the middle of it — the GBA's sits 1.6 cm off in Z — and at the
## distance a handheld is held that is an audible angle.
func _refresh_hardware_geometry() -> void:
	var mid := _host.get_model().get_instance_id() if _host.get_model() != null else 0
	if mid == _geom_model_id:
		return
	var aabb := _host.body_aabb()
	if aabb.size.x <= 0.0:
		return          # meshes not up yet; try again next frame
	_geom_model_id = mid
	_centre_local = aabb.get_center()
	_half_sep = minf(_host.audio_speaker_separation, aabb.size.x * 0.2)


## The listener autoload, resolved once. Null before it exists.
func _listener_node() -> Node:
	if _listener == null or not is_instance_valid(_listener):
		_listener = get_node_or_null("/root/SpatialAudioListener")
	return _listener


## Switch the voices between directional and omnidirectional, following whether
## this frame found a facing to give them. Decided per frame rather than once,
## because a system's sound moves between its own shell and a connected set as
## cables come and go, and those point different ways. Cached, since the answer
## almost never changes.
func _apply_voice_directivity(forward: Vector3) -> void:
	if _mx == null or _voices.is_empty():
		return
	var k: float = _host.audio_directivity if forward != Vector3.ZERO else 0.0
	if is_equal_approx(k, _sent_directivity):
		return
	_sent_directivity = k
	for v in _voices:
		_mx.set_voice_directivity(v, k)


## Fold the distance law into the voice gain. The SDK applies none of its own --
## a source four metres away measures the same level as one a metre away -- so
## without this a running game is exactly as loud from across the room as from
## in front of the set, and audio_max_distance means nothing.
##
## Shared with SpatialAudioEmitter so that hardware and everything else fall off
## identically. RetroSystem cannot simply use an emitter here: the libretro
## AudioHandler owns these voices and only hands back their ids.
func _apply_voice_distance_gain(centre: Vector3) -> void:
	if _mx == null or _voices.is_empty():
		return
	var ln := _listener_node()
	if ln == null:
		return
	_dist_factor = SpatialAudioEmitter.distance_gain(
		centre, ln.get_listener_position(),
		_host.audio_unit_size, _host.audio_max_distance)
	_send_voice_gain(_last_volume * _dist_factor)


## Gain to the voices, silencing a channel whose cord is not plugged in.
##
## Only hardware with sockets can have half its sound connected; a captive lead
## carries everything or nothing, so it keeps the single shared gain. The two
## voices are separate sample streams, so silencing one is a gain of zero on it —
## the same trick SpatialAudioEmitter.set_channel_gains uses on the decks.
func _send_voice_gain(g: float) -> void:
	# Six decoded channels, each with its own trim. The stereo rule below does not
	# apply: there is no half-connected pair to silence — a channel with no cabinet
	# FOLDS onto one that has, which is a position, not a mute — and fanning "voice
	# 0 left, the rest right" across six would put the base gain on all of them and
	# lose the 3 dB on a folded surround.
	if _surround and _voices.size() == 6 and _surround_gains.size() == 6:
		if _discrete:
			var m := _scaled_discrete(g)
			if m != _sent_discrete:
				_sent_discrete = m
				var node: Libretro = _host.get_libretro_node()
				if node == null or not node.SetSurroundDiscrete(m):
					# Refused (the decode stopped under it): back to the voices, and
					# the next frame draws the room around the head instead.
					_forget_discrete()
					_surround_gains = PackedFloat32Array()
					return
		if is_equal_approx(g, _sent_surround_gain) and _surround_gains == _sent_surround_trims:
			return
		_sent_surround_gain = g
		_sent_surround_trims = _surround_gains.duplicate()
		for i in _voices.size():
			_mx.set_voice_gain(_voices[i], g * _surround_gains[i])
		return
	var route: Dictionary = _host.audio_speakers()
	var gl := g
	var gr := g
	if route.get("socketed", false):
		gl = g if int(route.get("left", -1)) >= 0 else 0.0
		gr = g if int(route.get("right", -1)) >= 0 else 0.0
	if is_equal_approx(gl, _sent_gain_l) and is_equal_approx(gr, _sent_gain_r):
		return
	_sent_gain_l = gl
	_sent_gain_r = gr
	_mx.set_voice_gain(_voices[0], gl)
	for i in range(1, _voices.size()):
		_mx.set_voice_gain(_voices[i], gr)


## Whether this hardware's sound can be heard at all as it is currently cabled.
##
## The single-answer form of the rule _send_voice_gain applies per channel, for a
## backend that has one volume rather than two voices. Hardware with sockets is
## silent until an audio cord reaches a set, exactly as the real thing is; hardware
## on a captive lead carries its own speaker (the handhelds, the Virtual Boy) and
## is always live.
func _is_live() -> bool:
	var route: Dictionary = _host.audio_speakers()
	if not route.get("socketed", false):
		return true
	return int(route.get("left", -1)) >= 0 or int(route.get("right", -1)) >= 0


## Push the remembered level onto the AudioStreamPlayer3D backend, through the same
## cabling gate the voices get.
##
## The only writer of volume_db, so the gate cannot be bypassed by a caller that
## forgets it. Reached whenever the level changes, the backend is bound, or the
## cabling moves — a socketed console left ungated here plays at full volume out of
## its own shell with nothing plugged into it.
func _apply_player_volume() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var v: float = _last_volume if _is_live() else 0.0
	_player.volume_db = linear_to_db(v) if v > 0.001 else -80.0


## Put this machine's two channels at a fixed pair of points instead of on the
## thing showing its picture. Expected every frame, like the rest of the
## positioning here, because the points are given in the listener's frame and the
## head moves.
##
## The desktop fullscreen overlay is the caller: once a machine's picture has
## left the room for the window, its sound coming from a cabinet off to one side
## is the thing that gives the illusion away. See SpatialAudioEmitter.head_lock_positions.
func set_head_lock(left: Vector3, right: Vector3) -> void:
	_head_lock = true
	_head_l = left
	_head_r = right


func clear_head_lock() -> void:
	_head_lock = false


## Where the two channels actually radiate from, given where the cabling above
## would have put them. The head lock is the last word over every route: a
## machine whose picture is filling the window is not heard from across the room.
##
## Split out from update_position because it is the whole of the rule and the
## only part of it a headless test can reach -- the two backends that consume it
## both need a running core to exist at all.
func resolve_emission(left: Vector3, right: Vector3, forward: Vector3) -> Dictionary:
	if not _head_lock:
		return {"left": left, "right": right, "forward": forward}
	# Omnidirectional with it: a source still aimed along the screen normal of a
	# set the player has stopped facing would be quietened for facing away.
	return {"left": _head_l, "right": _head_r, "forward": Vector3.ZERO}


## Sound comes from whatever is showing the picture: a connected TV takes the
## audio, and the hardware takes it back when the cable is pulled. Driven every
## frame because both the system and the TV can be picked up and carried.
func update_position() -> void:
	var route: Dictionary = _host.audio_route()
	var tv: Node3D = route.get("tv", null) as Node3D
	var socketed: bool = route.get("socketed", false)
	var spk_l: int = int(route.get("left", -1))
	var spk_r: int = int(route.get("right", -1))

	if not _voices.is_empty():
		if _mx == null:
			return
		# Six decoded channels go where the SET says, which is a cabled cabinet's
		# cone or the fold-down point for a channel with no cabinet. Handled before
		# the stereo geometry below rather than inside it: none of that applies —
		# there is no left/right pair to cross, no hardware fallback (a machine
		# with no set is not decoding), and no baffle to aim along.
		if _surround and _voices.size() == 6 and tv != null \
				and tv.has_method("get_surround_positions"):
			if _head_lock:
				_place_surround_held(tv)
			else:
				_set_discrete(PackedFloat32Array())
				_place_surround(tv)
			return
		# A TV radiates from two speakers on its front baffle, so ask the set
		# where they are -- it knows its own geometry, and a shell can move or
		# rescale the screen. Emitting from the TV's node origin instead puts
		# the sound inside the cabinet, which amplitude panning hides but HRTF
		# makes obvious.
		var left_pos: Vector3
		var right_pos: Vector3
		# Which way the sound radiates. ZERO leaves the source omnidirectional,
		# which is right for anything playing through a TV -- only hardware
		# carried in the hand has a facing worth tracking.
		var emit_forward := Vector3.ZERO
		var emit_up := Vector3.UP
		if tv != null and tv.has_method("get_speaker_positions"):
			var sp: PackedVector3Array = tv.get_speaker_positions()
			left_pos = sp[0]
			right_pos = sp[1]
			# Each channel plays at the speaker its cord actually reaches, so a
			# crossed pair swaps them and mono hardware — whose one cord sets both
			# — puts both voices on the same speaker, where they sum. A real
			# downmix without touching a sample.
			if socketed:
				if spk_l >= 0:
					left_pos = sp[spk_l]
				if spk_r >= 0:
					right_pos = sp[spk_r]
			# Sound leaves a set the way the picture does — unless the set has sent
			# it to external speakers, which point wherever a hand put them.
			if tv.has_method("get_screen_normal") and not (tv.has_method("is_sound_external")
					and tv.is_sound_external()):
				emit_forward = tv.get_screen_normal()
				emit_up = tv.get_screen_up()
		elif tv != null:
			# A set that predates get_speaker_positions: spread across its own
			# local X, which for something TV-sized the default already suits.
			var right := tv.global_transform.basis.x.normalized() * _host.audio_speaker_separation
			left_pos = tv.global_position - right
			right_pos = tv.global_position + right
		else:
			# Unplugged, so the hardware radiates for itself -- and then the gap
			# has to come from the hardware's own size. A flat 9 cm is a console
			# figure: on a 14.5 cm GBA it puts both voices outside the shell you
			# are holding, 18 cm apart and subtending 33 degrees at arm's length,
			# which is a sound far wider than the object making it. Amplitude
			# panning hides that; HRTF in a headset does not.
			_refresh_hardware_geometry()
			var centre := _host.global_transform * _centre_local
			var right := _host.global_transform.basis.x.normalized() * _half_sep
			left_pos = centre - right
			right_pos = centre + right
			# A handheld radiates out of its face, and its face is the shell's
			# local +Y -- the same axis the tilt sensor above calls the screen
			# normal. Sending that lets the SDK quieten it as you turn it away.
			if _host.get_model() != null and _host.get_model().is_handheld():
				emit_forward = _host.global_transform.basis.y.normalized()
				emit_up = -_host.global_transform.basis.z.normalized()
		# The mixer skips the SDK call when a position has not changed, so
		# writing every frame is safe -- it saves a lock on a position that
		# usually has not moved.
		# Hold a handheld off the face: the SDK's HRTF goes dull and quiet inside
		# a quarter metre, and a handheld raised to look at lands well inside it.
		# The gain still uses the true centre, since holding off is about keeping
		# the model usable, not about making a close source quieter.
		var emission := resolve_emission(left_pos, right_pos, emit_forward)
		left_pos = emission["left"]
		right_pos = emission["right"]
		emit_forward = emission["forward"]
		var centre_true := (left_pos + right_pos) * 0.5
		var ln := _listener_node()
		if ln != null:
			var lp: Vector3 = ln.get_listener_position()
			left_pos = SpatialAudioEmitter.hold_off_head(left_pos, lp)
			right_pos = SpatialAudioEmitter.hold_off_head(right_pos, lp)
		_apply_voice_directivity(emit_forward)
		if emit_forward == Vector3.ZERO:
			_mx.set_voice_position(_voices[0], left_pos)
			if _voices.size() > 1:
				_mx.set_voice_position(_voices[1], right_pos)
		else:
			_mx.set_voice_pose(_voices[0], left_pos, emit_forward, emit_up)
			if _voices.size() > 1:
				_mx.set_voice_pose(_voices[1], right_pos, emit_forward, emit_up)
		_apply_voice_distance_gain(centre_true)
		return

	if _player == null or not is_instance_valid(_player):
		return
	if _head_lock:
		_player.global_position = (_head_l + _head_r) * 0.5
	elif tv != null and tv.has_method("get_speaker_positions"):
		# Between the speakers the set is using, which on external speakers is not
		# the set.
		var pair: PackedVector3Array = tv.get_speaker_positions()
		_player.global_position = (pair[0] + pair[1]) * 0.5
	elif tv != null:
		_player.global_position = tv.global_position
	elif not _player.position.is_zero_approx():
		_player.position = Vector3.ZERO
