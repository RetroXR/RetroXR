## TvAudio — the set's volume, mute and speaker switch, and pushing the result to
## whatever is making the sound.
##
## A child of the RetroTV it serves, created unconditionally in _init, in the same
## shape as TvResize, TvFit and TvOsd.
##
## The set owns no emitter of its own except the tuner's, so nothing here mixes
## anything: it decides a level and a channel routing and hands both to the
## connected host, which owns the samples.
##
## _volume, _muted and audio_mode stay on RetroTV. get_control_state and
## restore_control_state read them by name, object_sync replicates them, and
## object_sync_tests writes all three directly — the same reason scale_factor stays
## there rather than moving into TvResize.
class_name TvAudio
extends Node

## The set this listens for. Every level below is pushed to its connected hosts.
var _tv: RetroTV = null



## Loudness and mute live here rather than on RetroTV, because this helper is
## the only thing that changes them: the set reads them back for its OSD and its
## save file. Mute is sticky and deliberately does NOT alter the volume, so
## un-muting returns to whatever the player had set.
var _volume: float = 1.0        # 0.0-1.0, default 100%
var _muted: bool = false

## The amplifier and the decoder it was switched to when the set last told its
## machines what to decode, so a plug moving anywhere in the room re-tells them only
## when that actually changed. An instance id rather than the node, because the
## amplifier can be put in the bin between two calls.
var _applied_decoder_id: int = 0
var _applied_decode: int = 0


func volume() -> float:
	return _volume


func is_muted() -> bool:
	return _muted


## Put back a saved level. The set applies it through apply_volume() afterwards,
## the same as any other change.
func restore(level: float, muted: bool) -> void:
	_volume = clampf(level, 0.0, 1.0)
	_muted = muted

func setup(tv: RetroTV) -> void:
	_tv = tv


## Cycle the speaker switch: stereo -> the left channel from both speakers -> the
## right from both. Called by the front-panel key and by the remote.
func set_mode(mode: int) -> void:
	_tv.audio_mode = clampi(mode, 0, 2)
	apply_channel_mode()
	update_mode_button()
	_tv.show_osd_timed(RetroTV.AUDIO_MODE_NAMES[_tv.audio_mode], 2.0)
	NetworkManager.report_event(NetEvents.Event.EV_TV_AUDIO_MODE,
		{"tv": _tv, "mode": _tv.audio_mode})


func on_mode_toggle() -> void:
	set_mode((_tv.audio_mode + 1) % 3)


## Choose where the sound goes: the set's own pair, a stereo pair outside it, or the
## full surround decode. Called by the front-panel key, the remote and object_sync.
func set_audio_out(mode: int) -> void:
	var want := clampi(mode, 0, RetroTV.AUDIO_OUT_NAMES.size() - 1)
	_tv.audio_out = nearest_audio_out(want)
	if _tv.audio_out != want:
		print("[RetroTV] %s: this cabinet has no %s, so %s" % [_tv.name,
			RetroTV.AUDIO_OUT_NAMES[want], RetroTV.AUDIO_OUT_NAMES[_tv.audio_out]])
	var decoding := apply_audio_out()
	# The external positions are silent with nothing plugged in, and that is a volume.
	apply_volume()
	update_audio_out_button()
	# A machine that is decoding proves the SDK is on, whatever the listener's flag
	# says. The flag is only as fresh as the last set_sdk_enabled, and something that
	# switches the SDK on behind the listener's back leaves it stale — which put
	# "spatial audio is off" in the log beside a machine reporting six voices.
	var spatialised := SpatialAudioListener.is_spatialised() or decoding > 0
	var speakers := _tv.has_cabled_speakers()
	var amp := _tv.surround_decoder()
	var amp_decode: int = int(amp.get("decode_mode")) if amp != null else -1
	_tv.show_osd_timed(audio_out_osd(_tv.audio_out, spatialised, speakers, amp_decode), 2.0)
	var result := ""
	if _tv.is_sound_external() and not speakers:
		result = "  (no speakers connected, so the set is silent)"
	elif amp != null:
		result = "  (through an amplifier on %s, decoding on %d machine(s))" % [
			SurroundAmp.DECODE_NAMES[amp_decode], decoding]
	elif _tv.audio_out == RetroTV.AudioOut.SURROUND:
		if spatialised:
			result = "  (decoding on %d machine(s))" % decoding
		else:
			result = "  (spatial audio is off, so every machine stays in stereo)"
	print("[RetroTV] %s: audio output -> %s%s" % [_tv.name,
		RetroTV.AUDIO_OUT_NAMES[_tv.audio_out], result])
	NetworkManager.report_event(NetEvents.Event.EV_TV_AUDIO_OUT,
		{"tv": _tv, "mode": _tv.audio_out})


## What the OSD says for a position, most urgent reason first.
##
## No speakers comes first because it is why nothing can be heard at all: STEREO OUT
## and SURROUND send the sound to the speakers plugged into the back and leave the
## set silent, so with none plugged in the set goes quiet, and the OSD is the only
## thing that says why. The position is named with it, or two presses in a row read
## the same.
##
## Then SURROUND with the spatial audio SDK off: surround needs the six voices the SDK
## hands out, and without it every machine plays through Godot's stereo player and
## the decoder declines. Naming the format there claimed a decode that was not
## happening — a player pressed the key, read "PRO LOGIC II" and heard nothing change.
##
## STEREO OUT into a surround amplifier says so and names the amplifier's decoder
## (`amp_decode`, -1 for none), because that is where the format is now chosen — the
## set is only a line out — and with spatial audio off it says what SURROUND says,
## since the decode needs the voices just the same.
##
## Static so every answer can be checked without an SDK or a rig.
static func audio_out_osd(mode: int, spatialised: bool, speakers: bool,
		amp_decode: int = -1) -> String:
	if mode != RetroTV.AudioOut.TV_SPEAKERS and not speakers:
		return "%s — %s" % [RetroTV.AUDIO_OUT_NAMES[mode], RetroTV.AUDIO_OUT_NO_SPEAKERS]
	var decoding := mode == RetroTV.AudioOut.SURROUND or amp_decode >= 0
	if decoding and not spatialised:
		return RetroTV.AUDIO_OUT_NEEDS_SPATIAL
	if amp_decode >= 0:
		return "%s — AMPLIFIER, %s" % [RetroTV.AUDIO_OUT_NAMES[mode],
			SurroundAmp.DECODE_NAMES[amp_decode]]
	return RetroTV.AUDIO_OUT_OSD[mode]


## Step to the next position THIS cabinet has. Every one is distinguishable from the
## others: TV SPEAKERS plays from the set, and the other two play from the speakers
## plugged in or, with none, go silent and say so.
func on_audio_out_toggle() -> void:
	var options := audio_out_options()
	var at := options.find(_tv.audio_out)
	set_audio_out(options[(at + 1) % options.size()] if at >= 0 else options[0])


## The AUDIO OUTPUT positions this cabinet can be in, from the speaker outputs it
## actually carries: TV SPEAKERS always, STEREO OUT with the front pair, SURROUND
## only with all six — the set's decode has nowhere to go without the centre, LFE
## and rears. A shell retires an output by disabling its socket (the Panasonic
## CT-20D10B keeps only its L/R pair), and this follows it; it used to be all three
## on every set, so that set offered a SURROUND it has no jacks for.
func audio_out_options() -> Array[int]:
	var out: Array[int] = [RetroTV.AudioOut.TV_SPEAKERS]
	var ports := _tv.panel().speaker_outs()
	var live := ports.filter(func(p: RcaPort) -> bool: return p != null and p.enabled)
	if ports.size() >= 2 and ports[0].enabled and ports[1].enabled:
		out.append(RetroTV.AudioOut.STEREO)
		if live.size() == ports.size() and ports.size() == TvPanel.SPEAKER_OUT_NAMES.size():
			out.append(RetroTV.AudioOut.SURROUND)
	return out


## `mode` if this cabinet has it, else the nearest below it that it does: SURROUND
## asked of a stereo-only set (a save, a peer, an older menu) lands on STEREO OUT.
func nearest_audio_out(mode: int) -> int:
	var options := audio_out_options()
	for m in range(mode, -1, -1):
		if options.has(m):
			return m
	return RetroTV.AudioOut.TV_SPEAKERS


## Tell every connected host where the sound is going, the way apply_channel_mode
## does and for the same reason: the route is a property of the SET, so an input
## selected later must already be on it rather than reverting for one press.
##
## Through an amplifier the machines are asked for SURROUND whatever the key says —
## STEREO OUT is the set's line out, and the amplifier on it is what decodes — and
## for the amplifier's own decoder. Otherwise Pro Logic II, which is what the set's
## own SURROUND has always been.
##
## Returns how many of them are really decoding, which is what the log reports.
func apply_audio_out() -> int:
	var amp := _tv.surround_decoder()
	var mode: int = _tv.audio_out
	var decode: int = SurroundAmp.DecodeMode.PRO_LOGIC_II
	if amp != null:
		mode = RetroTV.AudioOut.SURROUND
		decode = int(amp.get("decode_mode"))
	_applied_decoder_id = amp.get_instance_id() if amp != null else 0
	_applied_decode = decode
	var decoding := 0
	for system in _tv.panel()._connected_systems:
		if not is_instance_valid(system) or not carries_sound(system):
			continue
		# The decoder first, so the first block decoded is already the right one.
		if system.has_method("set_surround_mode"):
			system.set_surround_mode(decode)
		if system.has_method("set_audio_out_mode"):
			if system.set_audio_out_mode(mode):
				decoding += 1
	if _tv.tuner() and _tv.tuner().has_method("set_audio_out_mode"):
		_tv.tuner().set_audio_out_mode(_tv.audio_out)
	return decoding


## Re-tell the machines what to decode, but only when the amplifier on the front
## pair — or its switch — has changed since they were last told. Reached from every
## plug move in the room, so it must cost nothing when nothing changed.
func refresh_decoder() -> void:
	var amp := _tv.surround_decoder()
	var id: int = amp.get_instance_id() if amp != null else 0
	var decode: int = int(amp.get("decode_mode")) if amp != null \
		else SurroundAmp.DecodeMode.PRO_LOGIC_II
	if id == _applied_decoder_id and decode == _applied_decode:
		return
	var decoding := apply_audio_out()
	if amp != null:
		print("[RetroTV] %s: STEREO OUT into an amplifier on %s (decoding on %d machine(s))"
			% [_tv.name, SurroundAmp.DECODE_NAMES[decode], decoding])
	else:
		print("[RetroTV] %s: no amplifier on the front pair any more" % _tv.name)


## Whether this set carries `system`'s sound, and so gets to set its level and its
## decode.
##
## A machine can put its picture on one box and its sound on another — a console's
## yellow cord in the set and its white and red in a surround amplifier — and the set
## then has to leave the sound alone: the amplifier is deciding its level and its
## decoder, and a set that went on pushing its own over the top would undo the
## amplifier on every plug moved anywhere in the room. A machine whose sound reaches
## nothing at all is still the set's to quieten, which changes nothing it can hear.
##
## Asked through audio_route(), which only RetroSystem answers. A deck has no
## separate sound route — it plays wherever its picture is — so it stays the set's.
func carries_sound(system: Node3D) -> bool:
	if not system.has_method("audio_route"):
		return true
	var sink: Variant = system.audio_route().get("tv")
	return sink == null or sink == _tv


## One fixed glyph, like SourceButton: what the key is doing is reported by the OSD
## and by the cap's colour, so there is nothing for the symbol to track.
func update_audio_out_button() -> void:
	TransportGlyphs.set_glyph(_tv, "AudioOutButton", "audio_out",
		TransportGlyphs.TV_SIZE)
	if _tv.audio_out_btn() == null:
		return
	# Deliberately NOT audio_mode's palette, though both keys wear a speaker. The
	# two sit in the same bezel row, and at mode 0 / TV SPEAKERS they were the same
	# blue on the same symbol — rendered side by side they read as one control
	# pressed twice. Grey is the resting state here, and violet is unused
	# elsewhere on this row.
	match _tv.audio_out:
		RetroTV.AudioOut.TV_SPEAKERS:
			_tv.audio_out_btn().set_color(Color(0.55, 0.58, 0.62))
		RetroTV.AudioOut.STEREO:
			_tv.audio_out_btn().set_color(Color(0.35, 0.8, 0.6))
		RetroTV.AudioOut.SURROUND:
			_tv.audio_out_btn().set_color(Color(0.75, 0.45, 0.95))


## The routing itself belongs to whoever owns the samples, so it is handed to the
## connected deck rather than done here — the set has no emitter of its own.
func apply_channel_mode() -> void:
	# Every connected host, not just the one showing: the speaker switch is a
	# property of the SET, so an input switched to later has to already be routed
	# the way the switch says rather than reverting to stereo for one press.
	for system in _tv.panel()._connected_systems:
		if is_instance_valid(system) and carries_sound(system) \
				and system.has_method("set_audio_channel_mode"):
			system.set_audio_channel_mode(_tv.audio_mode)
	# The tuner is the one source the set does own an emitter for, so it takes the
	# same routing directly rather than being asked to do it.
	if _tv.tuner():
		_tv.tuner().set_channel_mode(_tv.audio_mode)


## Stereo gets the two-speaker symbol; a mono mode gets a single speaker leaning
## to the channel it is carrying, matching how the 3D key shows its eye.
func update_mode_button() -> void:
	match _tv.audio_mode:
		0:
			TransportGlyphs.set_glyph(_tv, "AudioModeButton", "audio_stereo",
				TransportGlyphs.TV_SIZE)
		1:
			TransportGlyphs.set_glyph(_tv, "AudioModeButton", "audio_mono",
				TransportGlyphs.TV_SIZE, -1.0)
		2:
			TransportGlyphs.set_glyph(_tv, "AudioModeButton", "audio_mono",
				TransportGlyphs.TV_SIZE, 1.0)
	if _tv.audio_mode_btn():
		_tv.audio_mode_btn().set_color(Color(0.35, 0.55, 0.9) if _tv.audio_mode == 0
			else Color(0.9, 0.65, 0.25))


## What the set's own amplifier is passing: silence while off or muted, and while it
## is switched to external speakers with none plugged in — a real set does the same.
func _effective_volume() -> float:
	if not _tv.is_on() or _muted:
		return 0.0
	if _tv.is_sound_external() and not _tv.has_cabled_speakers():
		return 0.0
	# Through an amplifier its knob is the second volume in the chain, as on the real
	# pair: the set's level into the line out, the amplifier's out of its speakers.
	var amp := _tv.surround_decoder()
	if amp != null:
		return _volume * float(amp.call("get_volume"))
	return _volume


## …and what reaches one input, which is nothing at all unless that input is the
## one SOURCE has selected.
##
## The set has five sound sources and only ever plays one. Deselecting an input
## used to silence only its PICTURE (set_screen_enabled) and leave its sound
## running, so switching a console to the tuner played the channel over the top
## of the game you had just been playing.
func volume_for(source: RetroTV.Source) -> float:
	if _tv.current_source != source:
		return 0.0
	# The aerial socket can carry two sources at once — a console through an RF
	# switch and an Antenna in the switch's ANT socket — and the DIAL picks between
	# them, not SOURCE. On a broadcast channel the console is a channel away and
	# must be as silent as one on another input.
	if source == RetroTV.Source.RF and _tv.showing_broadcast():
		return 0.0
	# ...and so must one the set is simply not tuned to. A Famicom modulating on
	# CH1 into a set standing on CH3 is snow on the glass, and used to be heard
	# through it anyway: the picture had a channel and the sound did not.
	if source == RetroTV.Source.RF and not _tv.panel().rf_tuned():
		return 0.0
	return _effective_volume()


## What reaches the built-in tuner: the set's volume while the dial is on one of the
## aerial's channels, and nothing otherwise.
func tuner_volume() -> float:
	return _effective_volume() if _tv.showing_broadcast() else 0.0


## Push the current volume to every connected device and to the built-in tuner, so
## one knob governs whichever input is showing and the other four are quiet.
func apply_volume() -> void:
	# Every slot, not just the composite ones: a console reached through an RF switch
	# is on Source.RF and has to be silenced with the rest when it is not showing.
	for i in _tv.panel()._connected_systems.size():
		var system: Node3D = _tv.panel()._connected_systems[i]
		if is_instance_valid(system) and carries_sound(system):
			system.set_audio_volume(volume_for(i))
	if _tv.tuner():
		_tv.tuner().set_volume(tuner_volume())


## A volume key clears mute (like a real set) so the change is audible.
func _clear_mute_silently() -> void:
	if _muted:
		_muted = false
		_tv.hide_osd()


func on_volume_down() -> void:
	_clear_mute_silently()
	_volume = maxf(0.0, _volume - 0.1)
	if _tv.is_on():
		_tv.osd().show_volume()
	if _tv.is_on():
		apply_volume()
	NetworkManager.report_event(NetEvents.Event.EV_TV_VOL_DOWN, {"tv": _tv})


func on_volume_up() -> void:
	_clear_mute_silently()
	_volume = minf(1.0, _volume + 0.1)
	if _tv.is_on():
		_tv.osd().show_volume()
	if _tv.is_on():
		apply_volume()
	NetworkManager.report_event(NetEvents.Event.EV_TV_VOL_UP, {"tv": _tv})


## Toggle mute: silence (or restore) the connected device and show/clear a sticky
## "MUTE" OSD in the same corner "POWER" uses. No-op audibility change while off.
## Red while muted, matching the remote's own mute tint. Driven from here rather
## than the button so the remote's mute lands on the same cap.
func update_mute_button() -> void:
	if _tv.mute_btn():
		_tv.mute_btn().set_color(Color(1.0, 0.35, 0.35) if _muted else Color(0.35, 0.35, 0.35))


func on_mute_toggle() -> void:
	_muted = not _muted
	update_mute_button()
	update_mode_button()
	apply_volume()
	if _muted:
		_tv.show_osd("MUTE")
	else:
		_tv.hide_osd()
	NetworkManager.report_event(NetEvents.Event.EV_TV_MUTE, {"tv": _tv})
