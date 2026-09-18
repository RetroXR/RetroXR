## Proves the surround path with a REAL core: six voices, a real decoder, and the
## six placed points a television reports.
##
##   godot --path RetroXR --resolution 320x240 --position 20,20 \
##     res://Tools/av/surround_probe.tscn -- \
##     --root=<libretro root> --core=fceumm --rom=<a ROM>
##
## A probe rather than a suite for two reasons, and both are hard requirements:
## it wants a core and a ROM, and it wants the Meta XR Audio SDK — the voices ARE
## the surround here, and the fallback backend has none to place.
##
## WINDOWED, never --headless. Under --headless the SDK reports itself
## unavailable, so there are no voices, SetSurroundEnabled answers false and the
## probe would report "no surround" for a reason the player never sees. The same
## trap wiimote_speaker_probe documents.
##
## It also enables the SDK for its own run: SpatialAudioListener applies
## AppPrefs.spatial_audio_sdk at boot, and is_available() answers false while that
## option is off even with the library loaded.
extends Node3D

const TV_SCENE := preload("res://Scenes/Objects/tv.tscn")
const SATELLITE := preload("res://Scenes/Objects/appliances/loudspeaker.tscn")
const SPEAKER_CABLE := preload("res://Scenes/Objects/cables/speaker_cable.tscn")

var _root := ""
var _core := "fceumm"
var _rom := ""
var _failures: Array[String] = []


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--root="):
			_root = arg.split("=", true, 1)[1]
		elif arg.begins_with("--core="):
			_core = arg.split("=", true, 1)[1]
		elif arg.begins_with("--rom="):
			_rom = arg.split("=", true, 1)[1]
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("[surround] TIMEOUT")
		get_tree().quit(2))
	_run.call_deferred()


func _ok(cond: bool, what: String) -> void:
	print("[surround] %s %s" % ["PASS" if cond else "FAIL", what])
	if not cond:
		_failures.append(what)


func _run() -> void:
	if _rom.is_empty():
		print("[surround] need --rom")
		get_tree().quit(2)
		return

	# set_enabled on the mixer, NOT AppPrefs.spatial_audio_sdk: the preference is
	# applied by SpatialAudioListener at BOOT, so writing it here is too late and
	# is_available() goes on answering false with an empty error. Enabled for this
	# process only; the stored preference is untouched.
	_ok(Engine.has_singleton("MetaXRAudio"), "the Meta XR Audio extension is present")
	if Engine.has_singleton("MetaXRAudio"):
		var mx: Object = Engine.get_singleton("MetaXRAudio")
		# Through the listener, not the singleton: poking set_enabled directly left
		# its is_spatialised() flag stale, and the set read that flag.
		SpatialAudioListener.set_sdk_enabled(true)
		_ok(bool(mx.call("is_available")), "and the SDK is available (windowed run)")
	_ok(Engine.has_singleton("SurroundAudio"), "the decoder extension is present")

	var tv := TV_SCENE.instantiate() as RetroTV
	tv.freeze = true
	tv.position = Vector3(0.0, 1.0, 0.0)
	add_child(tv)
	await _wait(8)
	_ok(tv.panel().has_speaker_outs(), "the set carries its six speaker outputs")

	# One cabinet on the centre socket, so at least one channel is off the set and
	# the fold-down is not the only thing being measured.
	var outs := tv.panel().speaker_outs()
	var cab := await _cable_up(outs[2], Vector3(0.0, 0.0, -2.0))
	tv.on_av_topology_changed([])
	_ok(tv.panel().speaker_destinations().has(RcaPort.Channel.AUDIO_C),
		"and a cabinet on the centre output resolves")

	var sys := await _boot_machine()
	if sys == null:
		get_tree().quit(1)
		return
	# Cabled to the set through its own captive lead, and the set switched to that
	# input. Not optional scaffolding: a machine finds its television by walking its
	# own cord, so without this update_position has no set, the six voices never get
	# a pose, and the mixer never admits them — AdmitOnFirstPose drops the backlog
	# of a voice that has never been placed. The first run of this probe called
	# set_audio_out_mode on an uncabled machine and measured 480 underruns.
	# The cabling is STOOD IN, both ends, the way av_tests' _seat_stub does it —
	# and for the same reason: the real captive lead comes from the machine's
	# MODEL, which loads through ModelWarmer and never spawns in a bare probe
	# scene, so restore_cable_connection defers for ever. What this probe is for is
	# the audio path; which socket a cord reaches is av_tests' and speaker_tests'.
	#
	# Both ends are needed and they answer different questions. The set's
	# _connected_systems is what TvAudio.apply_audio_out fans the route over. The
	# machine's own _channels[0].tv is what _audio_tv() reads, and without it
	# update_position has no set, the six voices never get a pose, and the mixer
	# never admits them — AdmitOnFirstPose drops the backlog of a voice that has
	# never been placed. The first run of this probe missed the second and measured
	# 480 underruns with all six voices at depth zero.
	tv._panel._connected_systems[RetroTV.Source.COMPOSITE_1] = sys
	# Which of the machine's two routing fields to write depends on the hardware:
	# _audio_tv() reads _av_tv for a machine with PHONO SOCKETS and only falls
	# through to the channels for one wearing a captive lead. A stand-in has to set
	# whichever applies, so it sets both and lets the machine pick.
	sys._channels[0].tv = tv
	sys._av_tv = tv
	if not sys._av_ports.is_empty():
		sys._av_speaker_l = 0
		sys._av_speaker_r = 1
	tv.set_source(RetroTV.Source.COMPOSITE_1)
	# Switched ON, or the set passes zero volume: _effective_volume() is 0 while a
	# set is off or muted, and volume_for() is 0 for any input but the selected one.
	if not tv.is_on():
		tv.remote_power_toggle()
	await _wait(12)
	_ok(sys.audio_route().get("tv", null) == tv, "the machine's cord reaches the set")

	var node: Libretro = sys.get_libretro_node()
	# "A machine wired to nothing is silent" is a real rule, and the stand-in
	# cabling above never reached the code that lifts it (_has_display, driven from
	# _apply_av_feed). Said here explicitly, and said AFTER the volume is applied,
	# or the probe measures the silence the rule intends rather than the decode.
	node.SetAudioPlaying(true)
	sys.set_audio_volume(1.0)
	await _wait(10)

	var stereo_ids: PackedInt32Array = node.GetAudioVoiceIds()
	print("[surround] stereo voices: %s" % str(stereo_ids))
	_ok(stereo_ids.size() == 2, "a running core starts on two voices")

	# The POSITIVE CONTROL, and the run is meaningless without it. A depth of zero
	# and a pile of underruns can mean the decode is broken or it can mean this
	# machine is silent for a reason that has nothing to do with surround — so the
	# stereo pair is measured the same way first, and surround is judged against
	# it rather than against zero.
	var stereo_feed := await _measure(stereo_ids, "stereo")

	# Through the SET, not the machine: set_audio_out is what the bezel key calls,
	# and TvAudio.apply_audio_out fans it across every connected host. Driving the
	# machine directly would skip the half of the path a player uses.
	tv.set_audio_out(RetroTV.AudioOut.SURROUND)
	await _wait(40)
	var ids: PackedInt32Array = node.GetAudioVoiceIds()
	print("[surround] surround voices: %s" % str(ids))
	_ok(ids.size() == 6, "SURROUND engages six voices")
	var distinct := {}
	for v in ids:
		distinct[v] = true
	_ok(distinct.size() == ids.size(), "and every one is a voice of its own")

	# voice_frames_available on its own is not an oracle: a voice that is PLAYING is
	# drained continuously, so a sample taken between blocks legitimately reads 0.
	# What distinguishes "being fed" from "silent" is the mixer's own active-voice
	# count and its underrun counter — a voice pushed nothing underruns every block.
	var surround_feed := await _measure(ids, "surround")
	if stereo_feed.get("fed", false):
		_ok(surround_feed.get("fed", false),
			"the six are fed as the stereo pair was")
	else:
		print("[surround] SKIP the feed check: the stereo control was not fed either,")
		print("[surround]      so this run cannot tell a broken decode from a silent machine")

	var pos: PackedVector3Array = tv.get_surround_positions()
	var gains: PackedFloat32Array = tv.get_surround_gains()
	var names := ["FL", "FR", "C", "LFE", "SL", "SR"]
	for i in pos.size():
		print("[surround]   %-3s at %.3v gain=%.3f" % [names[i], pos[i], gains[i]])
	_ok(pos[2].distance_to(cab.get_speaker_positions()[0]) < 0.001,
		"the centre channel is placed on its own cabinet")
	_ok(is_equal_approx(gains[4], 0.7071068) and is_equal_approx(gains[5], 0.7071068),
		"and the two uncabled surrounds are 3 dB down")

	# Back off, which is what releases the four extra voices to a mixer with 32.
	tv.set_audio_out(RetroTV.AudioOut.TV_SPEAKERS)
	await _wait(20)
	var back: PackedInt32Array = node.GetAudioVoiceIds()
	print("[surround] after TV SPEAKERS: %s" % str(back))
	_ok(back.size() == 2, "switching back gives up the four extra voices")

	print("[surround] RESULT=%s" % ("PASS" if _failures.is_empty() else "FAIL"))
	for f in _failures:
		print("[surround]   failed: %s" % f)
	get_tree().quit(1 if not _failures.is_empty() else 0)


## Is a voice list actually receiving audio? Reported rather than asserted, so the
## caller can compare surround against the stereo control.
##
## voice_frames_available alone is not an oracle: a voice that is PLAYING is
## drained continuously, so a sample between blocks legitimately reads 0. What
## separates "fed" from "silent" is whether the depth is ever non-zero over a
## window AND whether the mixer is underrunning.
func _measure(ids: PackedInt32Array, label: String) -> Dictionary:
	if not Engine.has_singleton("MetaXRAudio") or ids.is_empty():
		return {"fed": false}
	var mx: Object = Engine.get_singleton("MetaXRAudio")
	mx.call("reset_underrun_count")
	var peak := PackedInt32Array()
	peak.resize(ids.size())
	peak.fill(0)
	for _f in 90:
		await get_tree().process_frame
		for i in ids.size():
			peak[i] = maxi(peak[i], int(mx.call("voice_frames_available", ids[i])))
	var runs := int(mx.call("get_underrun_count"))
	var fed := 0
	for d in peak:
		if d > 0:
			fed += 1
	print("[surround] %s: peak depth %s, %d underruns over 90 frames, %d/%d fed"
		% [label, str(peak), runs, fed, ids.size()])
	return {"fed": fed == ids.size(), "peak": peak, "underruns": runs}


func _wait(frames: int) -> void:
	for _i in frames:
		await get_tree().process_frame


func _cable_up(out_port: RcaPort, at: Vector3) -> Loudspeaker:
	var cab := SATELLITE.instantiate() as Loudspeaker
	cab.position = at
	cab.freeze = true
	add_child(cab)
	var lead := SPEAKER_CABLE.instantiate() as Node3D
	add_child(lead)
	await _wait(4)
	out_port.pick_up_object(lead.get_node("PlugA0") as Node3D)
	(cab.get_node("SpeakerIn") as RcaPort).pick_up_object(lead.get_node("PlugB0") as Node3D)
	await _wait(6)
	return cab


## A machine on the given core and ROM, powered on and running.
func _boot_machine() -> RetroSystem:
	var sys := preload("res://Scenes/Objects/system.tscn").instantiate() as RetroSystem
	sys.systemid = "nes"
	# Named rather than resolved, so the probe does not depend on whose machine it
	# is running on. core_directory before add_child, as famicom_mic_probe does.
	if not _root.is_empty():
		sys.core_directory = _root
	sys.core_name = _core
	sys.freeze = true
	sys.position = Vector3(0.0, 0.0, 1.5)
	add_child(sys)
	await get_tree().process_frame
	sys.rom_path = _rom
	sys.toggle_power()
	# A core comes up ASYNCHRONOUSLY — StartContent spins the emulation thread and
	# returns. A real fceumm took 34 frames in an earlier probe, so this waits on
	# the identity dictionary rather than on a frame count.
	var deadline := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		var ident: Dictionary = sys.get_libretro_node().GetCoreIdentity()
		if not ident.is_empty():
			print("[surround] core up: %s" % str(ident.get("library_name", "?")))
			break
	_ok(not sys.get_libretro_node().GetCoreIdentity().is_empty(),
		"the core loaded content")
	await _wait(30)
	return sys
