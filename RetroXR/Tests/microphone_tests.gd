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

	## The level route, which only a Famicom's Controller II takes. Answered here
	## so the ordinary cases below drive the service through the same contract a
	## real machine offers it.
	func hears_microphone_level() -> bool:
		return false

	func push_microphone_level(_level: Vector2) -> void:
		pass


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.substr(7)
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("[microphone] TIMEOUT")
		get_tree().quit(1))

	var saved_pref: bool = AppPrefs.microphone_enabled
	if _wants("gain"):
		_test_gain()
	if _wants("decision"):
		_test_decision()
	if _wants("device"):
		_test_device()
	if _wants("input"):
		_test_input_device()
	if _wants("fanout"):
		_test_fanout()
	if _wants("binding"):
		_test_binding()
	if _wants("ds"):
		_test_ds_pins()
	if _wants("gc"):
		await _test_gc()
	if _wants("persist"):
		await _test_gc_persist()
	if _wants("dreamcast"):
		await _test_dreamcast()
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


## Which input the service opens, and when it re-opens one.
func _test_input_device() -> void:
	var available := PackedStringArray(["Default", "Webcam", "Headset"])
	var R := SERVICE.resolve_device

	_ok(R.call("", available) == SERVICE.DEFAULT_DEVICE,
		"input/no preference follows the system")
	_ok(R.call("Default", available) == SERVICE.DEFAULT_DEVICE,
		"input/and so does the word Default, which is not a device name")
	_ok(R.call("Headset", available) == "Headset",
		"input/a microphone that is plugged in is the one opened")
	# The case a player actually hits: a USB microphone chosen last week and not
	# plugged in today. Capturing from nothing would read as a broken microphone
	# rather than a missing one.
	_ok(R.call("Studio USB", available) == SERVICE.DEFAULT_DEVICE,
		"input/one that is not falls back rather than capturing silence")
	_ok(R.call("Headset", PackedStringArray()) == SERVICE.DEFAULT_DEVICE,
		"input/and a platform offering no list at all falls back too")

	# End to end through the service, with the platform faked.
	var saved_device: String = AppPrefs.microphone_device
	AppPrefs.microphone_enabled = true
	var consumers: Array = [FakeMachine.new()]
	var switches: Array = []
	var chosen: Array = []
	var svc := _service(consumers, {}, switches)
	svc.device_list_source = func() -> PackedStringArray: return available
	svc.device_select = func(name: String) -> void: chosen.append(name)

	AppPrefs.microphone_device = "Webcam"
	svc.tick()
	# Selected BEFORE the switch: a driver opens the device it was pointed at, so
	# choosing one afterwards would leave the old input feeding the ring.
	_ok(chosen == ["Webcam"] and switches == [true],
		"input/the input is chosen before the device is opened",
		"%s / %s" % [str(chosen), str(switches)])
	svc.tick()
	_ok(chosen == ["Webcam"], "input/and is not re-chosen every frame")

	AppPrefs.microphone_device = "Headset"
	svc.tick()
	_ok(chosen == ["Webcam", "Headset"], "input/changing it picks the new one up")
	_ok(switches == [true, false, true],
		"input/closing and re-opening, because a live device keeps the one it opened",
		str(switches))

	AppPrefs.microphone_device = saved_device

	# What the list CALLS each one. Windows names an input after its driver and
	# then repeats itself, so a column of these is the word "Microphone" with the
	# half that identifies the hardware pushed off the panel.
	var OV := preload("res://Scripts/UI/spawn_menu/views/options_view.gd")
	var windows := PackedStringArray([
		"Microphone (HD Pro Webcam C920)",
		"Headset Microphone (Oculus Virtual Audio Device)"])
	_ok(OV._input_label("Microphone (HD Pro Webcam C920)", windows) == "HD Pro Webcam C920",
		"input/the label is the part that names the hardware")
	_ok(OV._input_label("Headset Microphone (Oculus Virtual Audio Device)", windows)
			== "Oculus Virtual Audio Device",
		"input/whatever the driver called itself in front of it")
	_ok(OV._input_label("Some Plain Name", windows) == "Some Plain Name",
		"input/a name with no brackets is left alone")
	# Two rows reading the same thing would be worse than two wide ones.
	var clash := PackedStringArray(["Rear (Line In)", "Front (Line In)"])
	_ok(OV._input_label("Rear (Line In)", clash) == "Rear (Line In)",
		"input/and names that would collide keep theirs in full")


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



## Which way the cord leaves the body, which is not something a look settles:
## a rope exits a directional endpoint along its local -Z BY DEFAULT, and both
## microphones are built nose-at-minus-Z with the cord boss at plus-Z. Left at
## the default the cord came out of the grille and doubled back through the
## body, and the only honest oracle is the sign of this dot.
func _check_cord(what: String, rope: VerletRope, host: Node3D,
		nose_local: Vector3, boss_local: Vector3) -> void:
	var basis := host.global_transform.basis.orthonormalized()
	var exit: Vector3 = (basis * Vector3(rope.start_exit_axis)).normalized()
	var body_dir: Vector3 = (basis * (boss_local - nose_local)).normalized()
	var d := exit.dot(body_dir)
	_ok(d > 0.5, "%s the cord leaves away from the nose, not back through it" % what,
		"dot %+.2f" % d)
	var end_exit: Vector3 = Vector3(rope.end_exit_axis).normalized()
	_ok(end_exit.dot(Vector3(0, 0, 1)) > 0.5,
		"%s and so does the end a hand is holding" % what, str(end_exit))

func _test_gc() -> void:
	var loose := GcMicrophonePlug.new()
	_ok(MemoryCardController.dolphin_slot_value("C:/cards/a.raw", null) == "C:/cards/a.raw",
		"gc/a card's image is passed through")
	_ok(MemoryCardController.dolphin_slot_value("", loose) == "mic", "gc/a seated microphone mounts as mic")
	_ok(MemoryCardController.dolphin_slot_value("", null) == "none", "gc/an empty slot is none")
	loose.free()

	_ok(str(ForcedCoreOptions.microphone_hotkey("dolphin", "gamecube")
			.get("dolphin_hotkey_activate_microphone", "")) == "R3",
		"gc/the microphone button is pinned to R3")
	_ok(ForcedCoreOptions.microphone_hotkey("dolphin", "wii").is_empty(), "gc/not on a Wii")
	_ok(ForcedCoreOptions.microphone_hotkey("snes9x", "gamecube").is_empty(), "gc/not on another core")

	# The stick: grille and aqua button at -Z, cord boss at +Z.
	var stick: GcMicrophone = preload(
		"res://Scenes/Objects/controllers/gamecube/gc_microphone.tscn").instantiate()
	add_child(stick)
	stick.freeze = true
	for i in range(30):
		await get_tree().physics_frame
	var stick_rope: VerletRope = null
	for n: Node in get_tree().current_scene.find_children("*", "VerletRope", true, false):
		stick_rope = n as VerletRope
	if stick_rope != null:
		_check_cord("gc/", stick_rope, stick.get_node("CableAttachPoint"),
			Vector3(0, 0, -0.068), Vector3(0, 0, 0.07))
	else:
		_ok(false, "gc/the stick built its cord")
	stick.drop_and_free() if stick.has_method("drop_and_free") else stick.queue_free()
	for i in range(6):
		await get_tree().process_frame
	_ok(CoreOptionsStore.HARDWARE_PINNED.has("dolphin_hotkey_activate_microphone"),
		"gc/the hotkey is hardware-pinned for the core manager")

	var gc := preload("res://Scenes/Objects/system.tscn").instantiate() as RetroSystem
	gc.systemid = "gamecube"
	add_child(gc)
	var mic := preload("res://Scenes/Objects/controllers/gamecube/gc_microphone.tscn").instantiate() as GcMicrophone
	add_child(mic)
	mic.global_position = gc.global_position + Vector3(0, 0, 3.0)
	for i in range(3):
		await get_tree().process_frame
	var plug := mic.get_plug()
	_ok(plug != null, "gc/the stick grows its cord and plug")
	if plug == null:
		gc.queue_free()
		mic.queue_free()
		return

	var slots := gc.memcard_slots()
	_ok(slots.size() == 2 and slots[0].can_preview(plug) and slots[1].can_preview(plug),
		"gc/the plug is offered by both card slots")
	gc.restore_memory_card(plug, 1)
	await get_tree().process_frame
	_ok(gc.get_snapped_memcard(1) == plug, "gc/seated in slot B")
	_ok(plug.seated_system() == gc and plug.seated_slot() == 1, "gc/and knows where it is")
	_ok(gc.microphone_position().is_equal_approx(mic.global_position),
		"gc/the machine hears from the stick, not the slot")

	# On desktop the aqua button is the left mouse button, which is also the click
	# that puts a held object down.
	var desktop := Node3D.new()
	desktop.set_script(load("res://Scripts/Desktop/desktop_pickup.gd"))
	add_child(desktop)
	desktop.grab_spawned(mic)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	desktop._unhandled_input(click)
	_ok(mic.is_picked_up(), "gc/on desktop a left click keeps the stick in hand")
	gc.is_powered_on = true
	Input.action_press("trigger_left")
	for i in range(2):
		await get_tree().process_frame
	_ok(mic._pressed_on == gc.get_libretro_node(), "gc/and holds its button on the machine")
	Input.action_release("trigger_left")
	await get_tree().process_frame
	_ok(mic._pressed_on == null, "gc/and lets the button go")
	gc.is_powered_on = false
	click.shift_pressed = true
	desktop._unhandled_input(click)
	_ok(not mic.is_picked_up(), "gc/Shift+click puts it down")
	desktop.queue_free()

	gc.queue_free()
	mic.drop_and_free()
	for i in range(30):
		await get_tree().process_frame


func _test_gc_persist() -> void:
	const SLOT := "__microphone_selftest"
	var slot_file := "user://scenes/arcade/%s.json" % SLOT
	get_tree().current_scene = self

	var gc := preload("res://Scenes/Objects/system.tscn").instantiate() as RetroSystem
	gc.systemid = "gamecube"
	add_child(gc)
	gc.add_to_group("spawned")
	var mic := preload("res://Scenes/Objects/controllers/gamecube/gc_microphone.tscn").instantiate() as GcMicrophone
	add_child(mic)
	for i in range(3):
		await get_tree().process_frame
	gc.restore_memory_card(mic.get_plug(), 1)
	await get_tree().process_frame

	var sp := ScenePersistence.new("arcade")
	_ok(sp.save_slot(self, SLOT), "persist/the room saves")
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(slot_file))
	var entry: Dictionary = {}
	if raw is Dictionary:
		for o: Variant in (raw as Dictionary).get("objects", []):
			if str((o as Dictionary).get("type", "")) == "gc_microphone":
				entry = o as Dictionary
	_ok(int(entry.get("slot", -1)) == 1 and entry.get("system") != null,
		"persist/the stick records slot B of its console")

	sp.clear_scene(self)
	for i in range(20):
		await get_tree().physics_frame
	await sp.load_slot_async(self, SLOT)
	for i in range(40):
		await get_tree().physics_frame

	var back_mic: GcMicrophone = null
	var back_sys: RetroSystem = null
	for n in get_tree().get_nodes_in_group("spawned"):
		if n is GcMicrophone:
			back_mic = n as GcMicrophone
		elif n is RetroSystem:
			back_sys = n as RetroSystem
	_ok(back_mic != null and back_sys != null and back_mic.seated_system() == back_sys
			and back_mic.seated_slot() == 1,
		"persist/and comes back seated there")

	sp.clear_scene(self)
	for i in range(10):
		await get_tree().physics_frame
	DirAccess.remove_absolute(ProjectSettings.globalize_path(slot_file))


## The Dreamcast Microphone (HKT-7200), which goes in a pad's expansion slot
## rather than into the console.
func _test_dreamcast() -> void:
	var mic := preload("res://Scenes/Objects/controllers/dreamcast/dc_microphone.tscn") \
		.instantiate() as DcMicrophone
	add_child(mic)
	await get_tree().process_frame

	_ok(DcMicrophone.OPTION_VALUE == "Microphone",
		"dreamcast/the core's own spelling for the slot", DcMicrophone.OPTION_VALUE)
	_ok(mic.slot_option_value() == "Microphone", "dreamcast/and that is what it answers")
	_ok(mic.is_in_group("controller_plug") and mic.is_in_group(DcMicrophone.SLOT_GROUP),
		"dreamcast/seatable, and only in a VMU slot")
	_ok(mic.seated_slot() == -1, "dreamcast/loose, it is in no slot")

	var pad: Node3D = preload("res://Scenes/Objects/controllers/retro_controller.tscn").instantiate()
	add_child(pad)
	for i in range(3):
		await get_tree().process_frame

	_ok(pad.vmu_slot_count() == 2, "dreamcast/a pad has two slots", str(pad.vmu_slot_count()))
	pad.restore_vmu(mic, 1)
	await get_tree().process_frame

	# Seaman's arrangement: the card in slot 1, the microphone in slot 2.
	_ok(pad.vmu_slot_option_value(1) == "Microphone",
		"dreamcast/the pad tells the core what is in slot 2", pad.vmu_slot_option_value(1))
	_ok(pad.vmu_slot_option_value(0) == "None",
		"dreamcast/and that slot 1 is empty", pad.vmu_slot_option_value(0))
	_ok(mic.seated_slot() == 1, "dreamcast/the microphone knows where it is")
	_ok(pad.seated_microphone() == mic, "dreamcast/and the pad knows it is one")
	_ok(pad.get_vmu_device(1) == mic, "dreamcast/a save would keep it")

	mic.global_position = pad.global_position + Vector3(0, 0.3, 0)
	_ok(mic.microphone_position().is_equal_approx(mic.global_position),
		"dreamcast/it hears from where it is")

	_ok(ScenePersistence.PLAIN_SCENES.has("dc_microphone"),
		"dreamcast/a saved room knows how to build one")
	var listed := false
	for row: Variant in SpawnCatalog.items_for("dreamcast"):
		if SpawnCatalog.spawn_token("dreamcast", row as Dictionary) == "dc_microphone":
			listed = true
	_ok(listed, "dreamcast/the Dreamcast card offers one")

	pad.queue_free()
	mic.queue_free()
	await get_tree().process_frame
