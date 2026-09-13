## Does a Wii Remote's speaker reach a voice of its own?
##
##     "$godot" --path RetroXR res://Tools/cores/wiimote_speaker_probe.tscn
##     "$godot" --path RetroXR res://Tools/cores/wiimote_speaker_probe.tscn -- --rom=<disc>
##
## A probe, not a test: it wants the Dolphin core and a Wii disc. It exits
## non-zero when the remote's sound never arrives.
##
## The oracle is GetControllerAudioVoiceId(0). The frontend creates that voice on
## the first NON-SILENT block the core offers for port 0, so it stays -1 when the
## speaker is switched off in the core, when the core does not know the controller
## audio interface, and when the frontend does not answer it -- however many
## buttons are pressed. Nothing but remote audio arriving can turn it.
##
## The disc is pressed through with A and A+B in bursts, the way nunchuk_probe gets
## past Wii Sports' health screen and title; the menus beyond them click through the
## remote. Meta XR Audio has to be available, because the fallback backend has no
## voices to give and the sound goes to the main mix instead.
##
## What it does NOT show is where the sound is heard from. The voice is never
## posed here, so the mixer never plays it; that half is wiimote.gd's.
extends Node

const RETRO_DEVICE_WIIMOTE := 1
const BTN_B := 1 << 0
const BTN_A := 1 << 8
## The menus debounce a held button, so a press is a short hold and a gap.
const PRESS_FRAMES := 8
const GAP_FRAMES := 40
## How long to keep pressing before calling the speaker silent.
const MAX_FRAMES := 7200

var core := "dolphin"
var rom := ""
var root_dir := ""

var _lib: Node = null
var _mx: Object = null
var _voice := -1
var _failures := 0


func _ready() -> void:
	var home := OS.get_environment("USERPROFILE").replace("\\", "/")
	if home.is_empty():
		home = OS.get_environment("HOME")
	root_dir = home + "/retroxr/libretro"
	rom = home + "/retroxr/roms/wii/Wii Sports (USA) (Rev 1).rvz"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rom="):
			rom = arg.trim_prefix("--rom=")
		elif arg.begins_with("--core="):
			core = arg.trim_prefix("--core=")
		elif arg.begins_with("--root="):
			root_dir = arg.trim_prefix("--root=")

	get_tree().create_timer(900.0).timeout.connect(func() -> void:
		print("[speaker] TIMEOUT")
		get_tree().quit(1))
	_run()


func _run() -> void:
	_check_marker()

	if not FileAccess.file_exists(rom):
		print("[speaker] SKIP: no disc at %s" % rom)
		get_tree().quit(0)
		return
	if Engine.has_singleton("MetaXRAudio"):
		_mx = Engine.get_singleton("MetaXRAudio")
		# The desktop player can switch the SDK off in Options, and
		# SpatialAudioListener applies that at boot. Enabled for this process only;
		# the stored preference is untouched.
		_mx.set_enabled(true)
	if _mx == null or not _mx.is_available():
		_fail("Meta XR Audio is not available, so there is no voice to hand out")
		get_tree().quit(1)
		return

	var obj: Object = ClassDB.instantiate("Libretro")
	_lib = obj as Node
	add_child(_lib)
	print("[speaker] booting %s on %s" % [rom.get_file(), core])
	_lib.StartContent(root_dir, core, rom)

	var boot_deadline := Time.get_ticks_msec() + 60000
	while (_lib.GetCoreIdentity() as Dictionary).is_empty() and Time.get_ticks_msec() < boot_deadline:
		await get_tree().process_frame
	if (_lib.GetCoreIdentity() as Dictionary).is_empty():
		_fail("the core never came up")
		await _finish()
		return
	_lib.SetControllerPortDevice(0, RETRO_DEVICE_WIIMOTE)

	var start := int(_lib.GetFrameCount())
	var burst := 0
	while _voice < 0 and int(_lib.GetFrameCount()) - start < MAX_FRAMES:
		await _hold(BTN_A | BTN_B if burst % 2 == 0 else BTN_A, PRESS_FRAMES)
		await _hold(0, GAP_FRAMES)
		burst += 1

	if _voice < 0:
		_fail("port 0 never got a voice in %d core frames: no remote sound arrived"
			% (int(_lib.GetFrameCount()) - start))
		await _finish()
		return
	print("[speaker] port 0 plays on voice %d, %d core frames in"
		% [_voice, int(_lib.GetFrameCount()) - start])

	var mains: PackedInt32Array = _lib.GetAudioVoiceIds()
	print("[speaker] main voices %s" % mains)
	if mains.has(_voice):
		_fail("the remote's voice is one of the main voices")

	var peak := 0
	for i in range(12):
		await _hold(BTN_A, PRESS_FRAMES)
		await _hold(0, GAP_FRAMES)
		peak = maxi(peak, int(_mx.voice_frames_available(_voice)))
	print("[speaker] most frames queued on the remote's voice: %d" % peak)
	if peak <= 0:
		_fail("the remote's voice exists but nothing ever queued on it")

	for port in range(1, 4):
		if int(_lib.GetControllerAudioVoiceId(port)) >= 0:
			_fail("port %d got a voice with no remote on it" % port)
	await _finish()


## The marker the voice is posed on must be on the grille: between Home and 1,
## on the face.
func _check_marker() -> void:
	var scene: PackedScene = load("res://Scenes/Objects/controllers/wii/wiimote.tscn")
	var wm: Node = scene.instantiate()
	var speaker := wm.get_node_or_null("Speaker") as Node3D
	var home := wm.get_node_or_null("HomeButton") as Node3D
	var one := wm.get_node_or_null("OneButton") as Node3D
	if speaker == null:
		_fail("wiimote.tscn has no Speaker marker")
	elif not (home.position.z < speaker.position.z and speaker.position.z < one.position.z):
		_fail("the Speaker marker at %s is not between Home and 1" % speaker.position)
	elif absf(speaker.position.y - home.position.y) > 0.002:
		_fail("the Speaker marker at %s is not on the face" % speaker.position)
	else:
		print("[speaker] marker at %s" % speaker.position)
	wm.free()


## Hold a button mask for n core frames, watching for the remote's voice.
func _hold(mask: int, n: int) -> void:
	var target: int = int(_lib.GetFrameCount()) + n
	var deadline := Time.get_ticks_msec() + int(n * 1000.0 / 10.0) + 8000
	while int(_lib.GetFrameCount()) < target and Time.get_ticks_msec() < deadline:
		_lib.SetJoypadState(0, mask, 0, 0, 0, 0)
		if _voice < 0:
			_voice = int(_lib.GetControllerAudioVoiceId(0))
		await get_tree().process_frame


func _fail(why: String) -> void:
	_failures += 1
	print("[speaker] FAIL: %s" % why)


## Stop the core and give the audio server the frames it needs to reclaim the
## mixer's playback before quitting.
func _finish() -> void:
	if _lib != null:
		_lib.StopContent()
	for i in range(60):
		await get_tree().process_frame
	print("[speaker] %s" % ("PASS" if _failures == 0 else "FAILED %d" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)
