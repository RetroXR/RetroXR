## Microphone self-tests — the capture service, headless.
##
##     "$godot" --headless --path RetroXR res://Tests/microphone_tests.tscn
##     "$godot" --headless --path RetroXR res://Tests/microphone_tests.tscn -- --only=fanout
##
## Exits 0 when everything passes, 1 otherwise.
##
## The service reads the device, finds machines and switches capture through
## Callables, so every case here drives it with fakes. That a core hears what is
## pushed needs a real core and lives in Tools/cores/mic_probe.
extends Node

const SERVICE := preload("res://Scripts/Audio/microphone_input.gd")

var _pass := 0
var _fail := 0
var _only := ""


class FakeLibretro:
	extends RefCounted
	var pushes: Array = []

	func PushMicrophoneFrames(frames: PackedVector2Array, rate: float, gain: float) -> void:
		pushes.append({"frames": frames, "rate": rate, "gain": gain})


class FakeMachine:
	extends RefCounted
	var lib := FakeLibretro.new()
	var position := Vector3.ZERO
	var audio_max_distance := 15.0

	func microphone_position() -> Vector3:
		return position

	func get_libretro_node() -> FakeLibretro:
		return lib


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.substr(7)
	get_tree().create_timer(30.0).timeout.connect(func() -> void:
		print("[microphone] TIMEOUT")
		get_tree().quit(1))

	var saved_pref: bool = AppPrefs.microphone_enabled
	if _wants("gain"):
		_test_gain()
	if _wants("decision"):
		_test_decision()
	if _wants("device"):
		_test_device()
	if _wants("fanout"):
		_test_fanout()
	if _wants("binding"):
		_test_binding()
	if _wants("ds"):
		_test_ds_pins()
	AppPrefs.microphone_enabled = saved_pref

	print("[microphone] ---- %d passed, %d failed ----" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _wants(group: String) -> bool:
	return _only.is_empty() or _only == group


func _ok(cond: bool, test_name: String, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("[microphone] PASS  %s" % test_name)
	else:
		_fail += 1
		print("[microphone] FAIL  %s%s" % [test_name, "  — " + detail if not detail.is_empty() else ""])


func _service(consumers: Array, capture: Dictionary, switches: Array) -> Node:
	var svc: Node = SERVICE.new()
	svc.consumer_source = func() -> Array: return consumers
	svc.frame_source = func() -> Dictionary: return capture
	svc.device_switch = func(on: bool) -> bool:
		switches.append(on)
		return true
	svc.head_source = func() -> Vector3: return Vector3.ZERO
	return svc


func _test_gain() -> void:
	var head := Vector3.ZERO
	_ok(is_equal_approx(SERVICE.gain_for(Vector3(0.3, 0, 0), head, 15.0), 1.0),
		"gain/full level inside half a meter")
	_ok(is_equal_approx(SERVICE.gain_for(Vector3(0, 0, 2.0), head, 15.0), 0.25),
		"gain/a quarter at two meters")
	_ok(is_equal_approx(SERVICE.gain_for(Vector3(0, 15.0, 0), head, 15.0), 0.0),
		"gain/silent at the machine's max distance")
	_ok(is_equal_approx(SERVICE.gain_for(Vector3(0, 0, 20.0), head, 15.0), 0.0),
		"gain/silent beyond it")


func _test_decision() -> void:
	var one: Array = [FakeMachine.new()]
	_ok(not SERVICE.should_capture(true, []), "decision/no machine listening, no capture")
	_ok(not SERVICE.should_capture(false, one), "decision/the player turned it off, no capture")
	_ok(SERVICE.should_capture(true, one), "decision/a listening machine and the pref on, capture")


func _test_device() -> void:
	AppPrefs.microphone_enabled = true
	var consumers: Array = []
	var switches: Array = []
	var svc := _service(consumers, {}, switches)

	svc.tick()
	_ok(switches.is_empty() and not svc.is_capturing(), "device/stays closed with nobody listening")

	consumers.append(FakeMachine.new())
	svc.tick()
	_ok(switches == [true] and svc.is_capturing(), "device/opens when a machine listens")
	svc.tick()
	_ok(switches == [true], "device/is not reopened every frame")

	AppPrefs.microphone_enabled = false
	svc.tick()
	_ok(switches == [true, false] and not svc.is_capturing(), "device/closes when the player turns it off")

	AppPrefs.microphone_enabled = true
	svc.tick()
	consumers.clear()
	svc.tick()
	_ok(switches == [true, false, true, false], "device/closes when the last machine stops listening")
	svc.free()


func _test_fanout() -> void:
	AppPrefs.microphone_enabled = true
	var near := FakeMachine.new()
	near.position = Vector3(0.2, 0, 0)
	var far := FakeMachine.new()
	far.position = Vector3(0, 0, 4.0)
	var frames := PackedVector2Array([Vector2(0.1, 0.1), Vector2(0.2, 0.2)])
	var switches: Array = []
	var svc := _service([near, far], {"frames": frames, "rate": 44100.0}, switches)

	svc.tick()
	_ok(near.lib.pushes.size() == 1 and far.lib.pushes.size() == 1, "fanout/every listening machine gets one push")
	_ok(near.lib.pushes[0].frames == frames and far.lib.pushes[0].frames == frames,
		"fanout/both get the same frames")
	_ok(is_equal_approx(near.lib.pushes[0].rate, 44100.0), "fanout/with the capture rate")
	_ok(is_equal_approx(near.lib.pushes[0].gain, 1.0), "fanout/the near machine at full level")
	_ok(is_equal_approx(far.lib.pushes[0].gain, 0.125), "fanout/the far one at 0.5 / 4 m")
	svc.free()

	var quiet := FakeMachine.new()
	var empty_svc := _service([quiet], {}, [])
	empty_svc.tick()
	_ok(quiet.lib.pushes.is_empty(), "fanout/nothing captured, nothing pushed")
	empty_svc.free()

	AppPrefs.microphone_enabled = false
	var off := FakeMachine.new()
	var off_svc := _service([off], {"frames": frames, "rate": 44100.0}, [])
	off_svc.tick()
	_ok(off.lib.pushes.is_empty(), "fanout/the pref off pushes nothing")
	off_svc.free()


func _test_binding() -> void:
	_ok(ClassDB.class_has_method("Libretro", "PushMicrophoneFrames"), "binding/PushMicrophoneFrames is bound")
	_ok(ClassDB.class_has_method("Libretro", "IsMicrophoneActive"), "binding/IsMicrophoneActive is bound")
	_ok(ClassDB.class_has_method("Libretro", "SetJoypadExtraButtons"), "binding/SetJoypadExtraButtons is bound")
	if not ClassDB.class_exists("Libretro"):
		return
	var lib: Node = ClassDB.instantiate("Libretro")
	_ok(not lib.IsMicrophoneActive(), "binding/a node with no core has no active microphone")
	lib.PushMicrophoneFrames(PackedVector2Array([Vector2(0.5, 0.5)]), 48000.0, 1.0)
	lib.SetJoypadExtraButtons(0, 1 << 15)
	_ok(not lib.IsMicrophoneActive(), "binding/a push and extra buttons with no core change nothing")
	lib.free()


func _test_ds_pins() -> void:
	var ds := RetroSystemModelNDS.new()
	var pins: Dictionary = ds.get_forced_core_options()
	_ok(str(pins.get("melonds_mic_input", "")) == "microphone", "ds/melonDS DS takes the real microphone")
	_ok(str(pins.get("melonds_mic_input_active", "")) == "always", "ds/and listens without a button")
	_ok(CoreOptionsStore.HARDWARE_PINNED.has("melonds_mic_input")
			and CoreOptionsStore.HARDWARE_PINNED.has("melonds_mic_input_active"),
		"ds/both keys are hardware-pinned for the core manager")
	ds.free()

