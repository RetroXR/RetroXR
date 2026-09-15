## Does a real core's microphone hear the host microphone?
##
##     "$godot" --path RetroXR --resolution 320x240 --position 20,20 res://Tools/cores/mic_probe.tscn
##     ... -- --core=melondsds --rom=<file> --root=<libretro root> --seconds=6
##
## A probe, not a test: it wants a core that reads the libretro microphone, a ROM
## for it and a real capture device, so it runs windowed (the headless audio driver
## has no input). Exits non-zero when any oracle fails.
##
## Oracles, in order:
##   the core switches a microphone on          Libretro.IsMicrophoneActive()
##   the Microphone autoload opens the device    Microphone.is_capturing()
##   host frames reach the core                  frames pushed through the node
##
## The autoload is driven with this probe's machine in place of the room's, so the
## device switch and the AudioServer read are the shipped ones. The C++ side also
## logs "Microphone opened at <rate> Hz" and "Microphone on" to stdout.
##
## melonDS DS gets the DS model's pins, set live once the core is up; the core
## writes them to its .opt on shutdown, which is what a DS in the room does too.
extends Node

const MELONDS_PINS := {
	"melonds_mic_input": "microphone",
	"melonds_mic_input_active": "always",
}

var core := "melondsds"
var rom := ""
var root_dir := ""
var seconds := 6.0

var _lib: Node = null
var _failures := 0
var _pushed_frames := 0
var _pushes := 0


class ProbeMachine:
	extends RefCounted
	var probe: Node
	var audio_max_distance := 15.0

	func microphone_position() -> Vector3:
		return Vector3.ZERO

	func get_libretro_node() -> Object:
		return probe


func _ready() -> void:
	var home := OS.get_environment("USERPROFILE").replace("\\", "/")
	if home.is_empty():
		home = OS.get_environment("HOME")
	root_dir = home + "/retroxr/libretro"
	rom = home + "/retroxr/roms/nds/Super Mario 64 DS (USA) (Rev 1).nds"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rom="):
			rom = arg.trim_prefix("--rom=")
		elif arg.begins_with("--core="):
			core = arg.trim_prefix("--core=")
		elif arg.begins_with("--root="):
			root_dir = arg.trim_prefix("--root=")
		elif arg.begins_with("--seconds="):
			seconds = float(arg.trim_prefix("--seconds="))

	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("[mic] TIMEOUT")
		get_tree().quit(1))
	_run()


## Called by the autoload in place of Libretro.PushMicrophoneFrames.
func PushMicrophoneFrames(frames: PackedVector2Array, rate: float, gain: float) -> void:
	_pushes += 1
	_pushed_frames += frames.size()
	_lib.PushMicrophoneFrames(frames, rate, gain)


func _run() -> void:
	if not ClassDB.class_has_method("Libretro", "IsMicrophoneActive"):
		_fail("this libretro-godot build has no microphone support")
		get_tree().quit(1)
		return
	if not FileAccess.file_exists(rom):
		print("[mic] SKIP: no content at %s" % rom)
		get_tree().quit(0)
		return

	var mic := get_node_or_null("/root/Microphone")
	if mic == null:
		_fail("the Microphone autoload is missing")
		get_tree().quit(1)
		return

	_lib = ClassDB.instantiate("Libretro") as Node
	add_child(_lib)
	print("[mic] booting %s on %s" % [rom.get_file(), core])
	_lib.StartContent(root_dir, core, rom)

	var boot_deadline := Time.get_ticks_msec() + 60000
	while (_lib.GetCoreIdentity() as Dictionary).is_empty() and Time.get_ticks_msec() < boot_deadline:
		await get_tree().process_frame
	if (_lib.GetCoreIdentity() as Dictionary).is_empty():
		_fail("the core never came up")
		await _finish(mic)
		return
	if core.begins_with("melondsds"):
		for key in MELONDS_PINS:
			_lib.SetCoreOption(key, MELONDS_PINS[key])

	var active_deadline := int(_lib.GetFrameCount()) + 600
	while not _lib.IsMicrophoneActive() and int(_lib.GetFrameCount()) < active_deadline:
		await get_tree().process_frame
	if not _lib.IsMicrophoneActive():
		_fail("the core never switched a microphone on in 600 frames")
		await _finish(mic)
		return
	print("[mic] the core has a microphone on, %d frames in" % int(_lib.GetFrameCount()))

	var machine := ProbeMachine.new()
	machine.probe = self
	var prefs_saved: bool = AppPrefs.microphone_enabled
	AppPrefs.microphone_enabled = true
	mic.consumer_source = func() -> Array:
		return [machine] if _lib.IsMicrophoneActive() else []

	var until := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
	AppPrefs.microphone_enabled = prefs_saved

	if not mic.is_capturing():
		_fail("the Microphone autoload never opened the device")
	print("[mic] %d pushes, %d host frames over %.1f s at %.0f Hz"
		% [_pushes, _pushed_frames, seconds, AudioServer.get_input_mix_rate()])
	if _pushed_frames <= 0:
		_fail("no host frames reached the core")
	await _finish(mic)


func _fail(why: String) -> void:
	_failures += 1
	print("[mic] FAIL: %s" % why)


func _finish(mic: Node) -> void:
	if mic != null:
		mic.consumer_source = Callable(mic, "_running_machines")
	if _lib != null:
		_lib.StopContent()
	for i in range(60):
		await get_tree().process_frame
	print("[mic] %s" % ("PASS" if _failures == 0 else "FAILED %d" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)
