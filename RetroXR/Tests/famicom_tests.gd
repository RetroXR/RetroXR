## Famicom self-tests — the Controller II microphone and the platform it needs.
##
##     "$godot" --headless --path RetroXR res://Tests/famicom_tests.tscn
##     "$godot" --headless --path RetroXR res://Tests/famicom_tests.tscn -- --only=gate
##
## Exits 0 when everything passes, 1 otherwise.
##
## The microphone here is not a capture device: it reaches the console as one bit
## of player 2's pad, so what is testable without a core is the DECISION — how
## loud the room has to be, where the volume slider is, and which port the bit is
## allowed to reach. That a game answers a real voice needs the forked core and a
## mic ROM, and lives in Tools/cores/famicom_mic_probe.
extends Node

const PAD_I := preload("res://Scenes/Objects/controllers/famicom/famicom_controller_i.tscn")
const PAD_II := preload("res://Scenes/Objects/controllers/famicom/famicom_controller_ii.tscn")
const SERVICE := preload("res://Scripts/Audio/microphone_input.gd")

var _pass := 0
var _fail := 0
var _only := ""


## Stands in for a machine with a Controller II on it. The service asks every
## consumer these five things; this one says yes to the level and records it.
class FakeLibretro:
	extends RefCounted
	var pushes := 0

	func PushMicrophoneFrames(_frames: PackedVector2Array, _rate: float, _gain: float) -> void:
		pushes += 1


class FakeMachine:
	extends RefCounted
	var lib := FakeLibretro.new()
	var position := Vector3.ZERO
	var audio_max_distance := 15.0
	var wants_level := true
	var levels: Array[Vector2] = []

	func microphone_position() -> Vector3:
		return position

	func get_libretro_node() -> FakeLibretro:
		return lib

	func hears_microphone_level() -> bool:
		return wants_level

	func push_microphone_level(level: Vector2) -> void:
		levels.append(level)


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.substr(7)
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("[famicom] TIMEOUT")
		get_tree().quit(1))

	if _wants("threshold"):
		_test_threshold()
	if _wants("gate"):
		_test_gate()
	if _wants("level"):
		_test_level()
	if _wants("fanout"):
		_test_fanout()
	if _wants("port"):
		_test_port()
	if _wants("pads"):
		await _test_pads()
	if _wants("platform"):
		_test_platform()

	await _settle_warm()
	print("[famicom] ---- %d passed, %d failed ----" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


## SceneManager's boot warm fires four process frames in and pulls every model in
## the registry onto the loader threads. Quitting while those are in flight makes
## a worker finish its parse after the class cache has gone, which prints a
## screenful of "Could not resolve class" at shutdown -- noise, since run_tests
## judges on the exit code, but noise in exactly the place a reader looks when a
## run has gone red. This suite is short enough to land in that window; the long
## ones never noticed.
func _settle_warm() -> void:
	for i in range(1200):
		if ModelWarmer.is_warmed():
			return
		await get_tree().process_frame


func _wants(group: String) -> bool:
	return _only.is_empty() or _only == group


func _ok(cond: bool, test_name: String, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("[famicom] PASS  %s" % test_name)
	else:
		_fail += 1
		print("[famicom] FAIL  %s%s" % [test_name, "  — " + detail if not detail.is_empty() else ""])


## What the volume slider asks of the room.
func _test_threshold() -> void:
	var off := FamicomControllerII.threshold_for(0.0)
	_ok(off == 0.0, "threshold/the far left switches the microphone off", str(off))
	_ok(FamicomControllerII.threshold_for(FamicomControllerII.OFF_BELOW) == 0.0,
		"threshold/and so does the whole dead zone at that end")

	# Just past the stop rather than at it: the curve reaches LOUD_RMS in the
	# limit, so a millimetre of travel is already a per-cent below it.
	var quietest := FamicomControllerII.threshold_for(FamicomControllerII.OFF_BELOW + 0.001)
	_ok(abs(quietest - FamicomControllerII.LOUD_RMS) < FamicomControllerII.LOUD_RMS * 0.01,
		"threshold/just off the stop, it wants a shout", str(quietest))
	var loudest := FamicomControllerII.threshold_for(1.0)
	_ok(is_equal_approx(loudest, FamicomControllerII.QUIET_RMS),
		"threshold/wide open, it wants very little", str(loudest))

	# Monotonic, so every position of the slider is a different sensitivity and
	# the travel is not wasted at one end.
	var prev := 1.0
	var falling := true
	for i in 21:
		var t := FamicomControllerII.threshold_for(0.05 + 0.0475 * float(i))
		if t >= prev:
			falling = false
		prev = t
	_ok(falling, "threshold/turning it up asks for less, all the way along")


## The decision itself.
func _test_gate() -> void:
	const OPEN := 0.6
	var th := FamicomControllerII.threshold_for(OPEN)

	_ok(not FamicomControllerII.hears(0.0, OPEN, false),
		"gate/a silent room never sets the bit")
	_ok(FamicomControllerII.hears(th * 1.2, OPEN, false),
		"gate/a room above the threshold does")
	_ok(not FamicomControllerII.hears(th * 0.5, OPEN, false),
		"gate/one below it does not")

	# However loud the room is, the slider at its stop is the microphone's own
	# switch -- the one thing a player can do that no game can override.
	_ok(not FamicomControllerII.hears(10.0, 0.0, false),
		"gate/the slider at the stop beats any amount of noise")
	_ok(not FamicomControllerII.hears(10.0, 0.0, true),
		"gate/and drops a bit that was already set")

	# Hysteresis. Without it a voice sitting on the threshold would open and shut
	# the bit every frame, which is a different signal from the core's own toggle.
	var between := th * ((FamicomControllerII.RELEASE + 1.0) * 0.5)
	_ok(FamicomControllerII.hears(between, OPEN, true),
		"gate/once set, it holds through a dip")
	_ok(not FamicomControllerII.hears(between, OPEN, false),
		"gate/but that same level would not have set it")
	_ok(not FamicomControllerII.hears(th * FamicomControllerII.RELEASE * 0.5, OPEN, true),
		"gate/and a real silence releases it")


## The C++ measure, read back from GDScript. MicrophoneLevel.hpp's own cases are
## the detail; these are the four properties this pad depends on.
func _test_level() -> void:
	_ok(ClassDB.class_has_method("Libretro", "MeasureMicrophoneLevel"),
		"level/the measure is bound")
	const RATE := 48000.0
	var tone := PackedVector2Array()
	tone.resize(960)
	for i in 960:
		var v := 0.5 * sin(TAU * 1000.0 * float(i) / RATE)
		tone[i] = Vector2(v, v)

	var lvl: Vector2 = Libretro.MeasureMicrophoneLevel(tone, RATE)
	_ok(abs(lvl.x - 0.5 / sqrt(2.0)) < 0.01, "level/a tone reads its own rms", str(lvl.x))
	_ok(lvl.y > lvl.x, "level/and a peak above it", str(lvl.y))

	var silence := PackedVector2Array()
	silence.resize(960)
	_ok(Libretro.MeasureMicrophoneLevel(silence, RATE) == Vector2.ZERO,
		"level/silence measures zero")

	var offset := PackedVector2Array()
	offset.resize(960)
	for i in 960:
		offset[i] = Vector2(0.5, 0.5)
	_ok(Libretro.MeasureMicrophoneLevel(offset, RATE).x < 1e-5,
		"level/a capture chain's offset is not a voice")

	# The whole reason one measurement can serve every machine in the room.
	var half: Vector2 = Libretro.MeasureMicrophoneLevel(tone, RATE, 0.5)
	_ok(abs(half.x - lvl.x * 0.5) < 1e-4, "level/it is linear in the gain", str(half.x))


## The service measures once and hands the answer out, scaled per machine.
func _test_fanout() -> void:
	var near := FakeMachine.new()
	var far := FakeMachine.new()
	far.position = Vector3(0, 0, 4.0)
	var deaf := FakeMachine.new()
	deaf.wants_level = false

	var frames := PackedVector2Array()
	frames.resize(480)
	for i in 480:
		var v := 0.3 * sin(TAU * 800.0 * float(i) / 48000.0)
		frames[i] = Vector2(v, v)

	var svc := _service([near, far, deaf], {"frames": frames, "rate": 48000.0})
	add_child(svc)
	svc.tick()

	_ok(near.levels.size() == 1 and far.levels.size() == 1,
		"fanout/every listener got one level")
	_ok(deaf.levels.is_empty(), "fanout/a machine that wants none is not fed")
	_ok(near.lib.pushes == 1 and deaf.lib.pushes == 1,
		"fanout/and the frames still reach every machine, level or not")
	_ok(near.levels[0].x > 0.0, "fanout/the level is a real measurement", str(near.levels[0]))
	_ok(far.levels[0].x < near.levels[0].x * 0.6,
		"fanout/a machine across the room hears the player fainter",
		"%f vs %f" % [far.levels[0].x, near.levels[0].x])
	svc.queue_free()


## Which port the bit is allowed to reach.
func _test_port() -> void:
	_ok(FamicomControllerII.MIC_PORT == 1,
		"port/the microphone is player 2's, which is where the core looks")
	_ok(FamicomControllerII.drives_port(1), "port/seated there, it can set the bit")
	# This is the case that matters. The core reads joy[1] only, so a Controller
	# II in port 1 has no microphone -- and if it held the bit anyway, every noise
	# in the room would be pressing player one's START and pausing the game.
	_ok(not FamicomControllerII.drives_port(0),
		"port/seated in player one's, it holds nothing at all")
	_ok(not FamicomControllerII.drives_port(-1), "port/and unplugged, nothing")
	_ok(FamicomControllerII.MIC_BITS == 1 << ControllerBindings.JOYPAD_START,
		"port/the bit it holds is START, which this pad does not otherwise have")


## The two pads themselves.
func _test_pads() -> void:
	var one: Node3D = PAD_I.instantiate()
	var two: Node3D = PAD_II.instantiate()
	add_child(one)
	add_child(two)
	for i in range(3):
		await get_tree().process_frame

	_ok(one.systemid == "famicom" and two.systemid == "famicom",
		"pads/both belong to the Famicom")
	_ok(one is FamicomController and two is FamicomControllerII,
		"pads/and are the two different pads")

	_ok(one.get_node_or_null("Model/Face/Select") != null
			and one.get_node_or_null("Model/Face/Start") != null,
		"pads/Controller I has SELECT and START")
	_ok(two.get_node_or_null("Model/Face/Select") == null
			and two.get_node_or_null("Model/Face/Start") == null,
		"pads/Controller II has neither, as on the hardware")
	_ok(two.get_node_or_null("Model/Face/MicGrille") != null,
		"pads/it has the grille where they would be")
	_ok(two.get_node_or_null("VolumeSlider") != null, "pads/and the volume slider")
	_ok(one.small_controls().size() == 2 and two.small_controls().is_empty(),
		"pads/so only one of them binds those two bits")

	# The pad IS the microphone, unlike a Dreamcast pad with a device in a slot,
	# so it answers where it hears from directly rather than through
	# seated_microphone() -- which RetroSystem asks for first.
	two.global_position = Vector3(1.0, 1.5, -2.0)
	var grille: Node3D = two.get_node("Model/Face/MicGrille")
	_ok(two.microphone_position().is_equal_approx(grille.global_position),
		"pads/it hears from the grille, not from the pad's origin")

	_ok(two.volume() > 0.0, "pads/the slider arrives open rather than silent",
		str(two.volume()))
	two.get_node("VolumeSlider").set_value_no_signal(0.0)
	_ok(FamicomControllerII.threshold_for(two.volume()) == 0.0,
		"pads/and turned to the stop it is off")

	_ok(ScenePersistence.CONTROLLER_SCENES.has(PAD_I.resource_path)
			and ScenePersistence.CONTROLLER_SCENES.has(PAD_II.resource_path),
		"pads/a saved room knows how to build both")

	one.queue_free()
	two.queue_free()
	await get_tree().process_frame


## The platform itself: famicom used to collapse into nes everywhere.
func _test_platform() -> void:
	var info := SystemInfo.for_system("famicom")
	_ok(info != null and info.systemid == "famicom", "platform/there is a SystemInfo row")
	_ok(info != null and info.native_ports == 2, "platform/with two controller ports")
	_ok(info != null and info.media_type == SystemInfo.MediaType.CARTRIDGE,
		"platform/and a cartridge slot")

	_ok(not SystemModelRegistry.rows_for("famicom").is_empty(),
		"platform/a console model is registered")
	_ok(ResourceLoader.exists("res://Scenes/Objects/system_models/famicom_primitive.tscn"),
		"platform/and its scene exists")

	_ok(RommPlatforms.SLUG_MAP.get("famicom") == "famicom",
		"platform/RomM stops filing a Famicom library under nes",
		str(RommPlatforms.SLUG_MAP.get("famicom")))
	_ok(ScreenscraperSystems.get_systemeid("famicom") == 3,
		"platform/ScreenScraper scrapes it as the same platform",
		str(ScreenscraperSystems.get_systemeid("famicom")))
	_ok(RaConsoles.for_systemid("famicom") == 7,
		"platform/RetroAchievements counts it as the same console",
		str(RaConsoles.for_systemid("famicom")))
	_ok("famicom" in NetplayCores.CORES["fceumm"]["systems"],
		"platform/fceumm serves it for netplay")
	_ok(MediaDimensions.CART_SIZES.has("famicom"),
		"platform/its cartridge has a size of its own")
	_ok(MediaDimensions.CART_SIZES["famicom"] != MediaDimensions.CART_SIZES["nes"],
		"platform/and it is not the NES's")

	_ok(SystemIcons.has_icon("famicom"), "platform/it has console art rather than the fallback")
	_ok(SystemIcons.has_content_icon("famicom"), "platform/and its own cartridge art")

	var forced := ForcedCoreOptions.microphone_hotkey("fceumm", "famicom")
	_ok(forced.get("fceumm_famicom_microphone") == "enabled",
		"platform/fceumm is told to read the microphone")
	_ok(ForcedCoreOptions.microphone_hotkey("fceumm", "nes").is_empty(),
		"platform/an NES is not -- that machine has no microphone")
	_ok(ForcedCoreOptions.microphone_hotkey("mesen", "famicom").is_empty(),
		"platform/and neither is a core that would not understand the key")

	var spawns: Array = SpawnCatalog.items_for("famicom")
	var labels: Array = spawns.map(func(item: Dictionary) -> String: return str(item.get("spawn", "")))
	_ok("famicom_controller_i" in labels and "famicom_controller_ii" in labels,
		"platform/its card offers both pads")
	_ok(not ("composite_cable" in labels),
		"platform/and no A/V lead, because the machine has no socket for one")

	# The tile itself. A systemid reaches the browser through the core-info
	# database, so the overlay entry is what makes the platform visible at all.
	var db := CoreInfoDatabase.shared()
	_ok("famicom" in db.get_unique_systemids(),
		"platform/a core declares it, so it gets a tile")
	# And the same declaration is what gives a spawned Famicom a core at all: the
	# Cores panel walks systemids_of() and adopts a first default for every
	# platform an installed core serves, not only for its own.
	_ok("famicom" in CoreInfoDatabase.systemids_of(db.get_by_core_name("fceumm")),
		"platform/so installing fceumm adopts a default core for it")
	_ok(db.get_systemname_for_id("famicom") == "Family Computer",
		"platform/named by SystemInfo rather than by its core",
		db.get_systemname_for_id("famicom"))


func _service(consumers: Array, capture: Dictionary) -> Node:
	var svc: Node = SERVICE.new()
	svc.consumer_source = func() -> Array: return consumers
	svc.frame_source = func() -> Dictionary: return capture
	svc.device_switch = func(_on: bool) -> bool: return true
	svc.head_source = func() -> Vector3: return Vector3.ZERO
	return svc
