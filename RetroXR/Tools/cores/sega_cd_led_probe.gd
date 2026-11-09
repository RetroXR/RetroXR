## Sega CD ACCESS lamp probe: does the drive's lamp follow genesis_plus_gx's LED?
##
## genesis_plus_gx publishes libretro's LED interface: LED 0 is the Z80 running, LED 1
## the sub-CPU's LEDR bit (the red ACCESS lamp the BIOS drives). libretro-godot re-emits
## each change as the Libretro node's `led_state(led, on)`, and the drive's AccessLed
## follows the LED its row names (`access_led`, 1 for the Sega CD).
##
## Driven through the ROOM: a Genesis bolted on the Sega CD unit, power_on, the core
## genesis_plus_gx with a Sega CD BIOS in its system folder. ONE LEG PER PROCESS:
##   --leg=bios   no disc: the BIOS's own control panel ("No Disc"), whose lamp the
##                manual says FLASHES (Model 2 manual p.14)
##   --leg=disc   --disc=<a Sega CD .chd/.cue> in the drive: the lamp is lit while the
##                disc is read
## Prints every change of both LEDs with the frame it landed on, how many each made,
## and whether the drive's lamp was lit exactly while LED 1 was.
##
##   godot --headless --path RetroXR res://Tools/cores/sega_cd_led_probe.tscn -- \
##       --leg=bios [--seconds=20]
extends Node3D

const SYS_SCENE := "res://Scenes/Objects/system.tscn"
const UNIT_SCENE := "res://Scenes/Objects/expansion.tscn"
const DISC_SCENE := "res://Scenes/Objects/media/disc.tscn"
const CORE := "genesis_plus_gx"

var _leg := "bios"
var _disc := ""
var _seconds := 20.0
var _pass := 0
var _fail := 0
var _lib: Libretro = null
var _unit: RetroExpansion = null
var _changes := {0: 0, 1: 0}
var _lit_frames := {0: 0, 1: 0}
var _state := {0: false, 1: false}
var _lamp_mismatch := 0


func _ready() -> void:
	get_tree().create_timer(_seconds + 120.0).timeout.connect(func() -> void:
		print("[scd-led] TIMEOUT")
		get_tree().quit(1))
	await _run()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--leg="):
			_leg = arg.substr(6)
		elif arg.begins_with("--disc="):
			_disc = arg.substr(7)
		elif arg.begins_with("--seconds="):
			_seconds = arg.substr(10).to_float()
	if CoreDownloadManager.installed_core_lib(CORE).is_empty():
		print("[scd-led] SKIP  no %s core" % CORE)
		get_tree().quit(0)
		return
	if not ExpansionCatalog.firmware_present("sega_cd"):
		print("[scd-led] SKIP  no Sega CD BIOS for %s" % CORE)
		get_tree().quit(0)
		return
	if _leg == "disc" and (_disc.is_empty() or not FileAccess.file_exists(_disc)):
		print("[scd-led] SKIP  pass --disc=<a Sega CD disc> for the disc leg")
		get_tree().quit(0)
		return
	print("[scd-led] leg=%s disc=%s access_led=%d" % [_leg, _disc.get_file(), ExpansionCatalog.access_led_of("sega_cd")])

	var sys := (load(SYS_SCENE) as PackedScene).instantiate() as RetroSystem
	sys.systemid = "genesis"
	sys.core_name = CORE
	add_child(sys)
	sys.freeze = true
	sys.gravity_scale = 0.0
	sys.global_position = Vector3(0, 1.5, 0)
	_unit = (load(UNIT_SCENE) as PackedScene).instantiate() as RetroExpansion
	_unit.expansion_id = "sega_cd"
	add_child(_unit)
	_unit.freeze = true
	_unit.global_position = Vector3(0, 0.5, 0)
	await _room_frames(30)
	_unit.get_socket().pick_up_object(sys)
	await _room_frames(10)
	_ok("the Genesis stands on the Sega CD", sys.expansion_ids().has("sega_cd"))
	if _leg == "disc":
		var disc := (load(DISC_SCENE) as PackedScene).instantiate() as Node3D
		disc.set("systemid", "segacd")
		disc.set("rom_path", _disc)
		add_child(disc)
		disc.global_position = Vector3(0, 0.8, 0)
		await _room_frames(10)
		_unit.restore_media_in_slot(disc)
		await _room_frames(10)
		_ok("the disc is in the drive", _unit.get_loaded_media_path() == _disc, _unit.get_loaded_media_path())

	_lib = sys.get_libretro_node()
	_lib.led_state.connect(_on_led)
	sys.power_on()
	_ok("it switches on", sys.is_powered_on)
	if not sys.is_powered_on:
		return _finish()
	var deadline := Time.get_ticks_msec() + int(_seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
		for led: int in [0, 1]:
			if _state[led]:
				_lit_frames[led] += 1
		if _unit.get("_led_on") != _state[1]:
			_lamp_mismatch += 1
	var frames: int = _lib.GetFrameCount()
	print("[scd-led] %d emulated frames: LED 0 changed %d times (lit %d room frames), LED 1 changed %d times (lit %d)"
		% [frames, _changes[0], _lit_frames[0], _changes[1], _lit_frames[1]])
	_ok("the core reports the ACCESS lamp (LED 1)", _changes[1] > 0)
	if _leg == "bios":
		_ok("with no disc it flashes (LED 1 turned on and off several times)", _changes[1] >= 4)
	_ok("the drive's lamp follows LED 1 (frames it disagreed: %d)" % _lamp_mismatch, _lamp_mismatch <= 2)
	sys.power_off()
	await _room_frames(10)
	_finish()


func _on_led(led: int, on: bool) -> void:
	if not _changes.has(led):
		_changes[led] = 0
	_changes[led] += 1
	_state[led] = on
	if _changes[led] <= 12:
		print("[scd-led] LED %d %s at frame %d" % [led, "on" if on else "off", _lib.GetFrameCount()])


func _room_frames(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame


func _ok(check: String, cond: bool, detail := "") -> void:
	if cond:
		_pass += 1
		print("[scd-led] PASS  %s" % check)
	else:
		_fail += 1
		print("[scd-led] FAIL  %s %s" % [check, detail])


func _finish() -> void:
	print("[scd-led] RESULT %d passed, %d failed" % [_pass, _fail])
	get_tree().quit(0 if _fail == 0 else 1)
