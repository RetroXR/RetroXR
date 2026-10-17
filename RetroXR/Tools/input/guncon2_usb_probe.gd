## A GunCon 2 in a PlayStation 2's USB socket, with a real game -- the half no
## headless suite can reach.
##
##     "$godot" --path RetroXR --resolution 320x240 --position 20,20 \
##         res://Tools/input/guncon2_usb_probe.tscn -- \
##         "--ps2-rom=$HOME/retroxr/roms/ps2/Time Crisis II (USA).chd" --usb=1 --shots=<dir>
##
## --usb=1 or 2 seats a gun in that USB socket; --usb=0 seats none, the control.
## No pad goes in any controller port, so whatever the game does with a press, it
## did because of the gun.
##
## The gun is the game's own light gun, given what makes it a GunCon 2: a USB-A
## plug and the core's device name. The console tells the core the gun is on the
## port of the socket's number, and the core plugs it into its own USB port of
## that number. The probe then aims at the middle of the picture and alternates
## the calibration shot (START + SELECT held together, the core's convention) and
## the TRIGGER, and writes the picture every few seconds:
## a title that answers the gun (and does not with --usb=0) is the evidence.
## The core's own "(GunCon2) Attached to USB port" line is logged at INFO, which
## the extension does not forward, so the pictures are what there is.
##
## --then=trigger|offscreen|reload calibrates twice (at 30 s, once the calibration
## screen is up: it comes at about 24 s, and a chord before it is lost) and then
## presses only that. `trigger` fires at the middle; `offscreen` fires aimed off
## the glass, which is what an off-screen shot looks like to the game; `reload`
## sends RELOAD aimed at the middle, which the core turns into an off-screen shot.
## Each is HELD from then on. Time Crisis II's "Is the gun sight aligned
## correctly?" screen draws the gun's live cursor: centred for the trigger leg,
## gone for the offscreen leg. A RELOAD that reaches the core reports the gun at
## (0, 0) while it is held, so its cursor goes as the offscreen leg's does; one
## that does not leaves it centred, as the trigger leg's is.
##
## Run WINDOWED: headless hands back a correctly sized frame with nothing in it.
extends Node

const RUN_SECONDS := 150.0
const SHOT_EVERY := 5.0

var _rom := ""
var _usb := 1
var _shots := ""
var _then := ""


func _ready() -> void:
	get_tree().create_timer(RUN_SECONDS + 150.0).timeout.connect(func() -> void:
		print("[probe] TIMEOUT")
		get_tree().quit(1))
	for a in OS.get_cmdline_user_args():
		var s := str(a)
		if s.begins_with("--ps2-rom="):
			_rom = s.substr("--ps2-rom=".length())
		elif s.begins_with("--usb="):
			_usb = int(s.substr("--usb=".length()))
		elif s.begins_with("--then="):
			_then = s.substr("--then=".length())
		elif s.begins_with("--shots="):
			_shots = s.substr("--shots=".length())
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_shots))
	if _rom.is_empty() or not FileAccess.file_exists(_rom):
		print("[probe] need --ps2-rom=<path to a PS2 disc image>")
		get_tree().quit(1)
		return
	await _run()
	get_tree().quit(0)


func _run() -> void:
	var sys := preload("res://Scenes/Objects/system.tscn").instantiate() as Node3D
	sys.set("systemid", "ps2")
	sys.set("rom_path", _rom)
	add_child(sys)
	await get_tree().process_frame
	var zones: Array = sys.get("_usb_zones")
	print("[probe] the console has %d USB sockets" % zones.size())

	var k := _usb - 1
	var gun: Node3D = null
	if _usb > 0:
		gun = (load("res://Scenes/Objects/peripherals/light_gun.tscn") as PackedScene).instantiate() as Node3D
		gun.set("systemid", "ps2")
		gun.set("connector", Connectors.USB_A)
		gun.set("device_names", PackedStringArray(["guncon 2", "guncon2", "g-con 2"]))
		add_child(gun)
		gun.position = Vector3(0.0, 0.3, 0.8)
		for i in 5:
			await get_tree().process_frame
		var plug := gun.get("_cable_plug") as Node3D
		sys.call("restore_controller_plug", RetroSystem.USB_SLOT_BASE + k, plug)
		await get_tree().process_frame
		var held: Array = sys.get("_usb_plugs")
		print("[probe] gun seated in USB socket %d: %s, it drives core port %d"
			% [_usb, held[k] == plug, int(gun.get("_port_index"))])
		# The probe presses the buttons, not the gun's own hand-reading loop.
		gun.set_process(false)

	sys.call("toggle_power")
	var lib: Object = sys.call("get_libretro_node")
	var up := false
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 120000:
		await get_tree().process_frame
		if not (lib.call("GetCoreIdentity") as Dictionary).is_empty():
			up = true
			break
	print("[probe] core up: %s after %d ms" % [up, Time.get_ticks_msec() - t0])
	if not up:
		return
	for entry: Dictionary in sys.get("_controller_info"):
		print("[probe] core port %d: told %d" % [int(entry.get("port", -1)), int(entry.get("current_id", -1))])

	var t1 := Time.get_ticks_msec()
	var next_shot := 0.0
	var next_press := 20.0 if _then.is_empty() else 30.0
	var press := 0
	while Time.get_ticks_msec() - t1 < RUN_SECONDS * 1000.0:
		await get_tree().process_frame
		var at := (Time.get_ticks_msec() - t1) / 1000.0
		if _usb > 0:
			# Aimed at the middle of the picture, on screen -- or, for the offscreen
			# leg once it is calibrated, off the glass.
			lib.call("SetLightgunPosition", k, 0, 0)
			lib.call("SetLightgunIsOffscreen", k, _then == "offscreen" and press >= 4)
			if at >= next_press:
				# The calibration shot (START + SELECT held together, which is how the
				# core takes a GunCon 2's calibration), then the TRIGGER, alternately,
				# each held a moment.
				var calibrate := press % 4 < 2 if _then.is_empty() else press < 4
				var down := press % 2 == 0 or not (calibrate or _then.is_empty())
				var button := ControllerBindings.LIGHTGUN_RELOAD if _then == "reload" \
					else ControllerBindings.LIGHTGUN_TRIGGER
				if calibrate:
					lib.call("SetLightgunButton", k, ControllerBindings.LIGHTGUN_START, down)
					lib.call("SetLightgunButton", k, ControllerBindings.LIGHTGUN_SELECT, down)
				else:
					lib.call("SetLightgunButton", k, button, down)
				if down:
					print("[probe] t=%5.1f  %s" % [at, "calibration shot (START+SELECT)" if calibrate
						else ControllerBindings.LIGHTGUN_NAMES.get(button, str(button)).to_upper()])
				press += 1
				next_press = at + (0.4 if down else 3.0)
				if not calibrate and not _then.is_empty():
					next_press = INF   # held to the end
					print("[probe]          held from here on")
		if _shots.is_empty() or at < next_shot:
			continue
		next_shot = at + SHOT_EVERY
		var img: Image = lib.call("GetVideoImage")
		if img == null or img.is_empty():
			continue
		var flat := Image.create_from_data(img.get_width(), img.get_height(), false,
			Image.FORMAT_RGB8, _rgb_bytes(img))
		flat.save_png("%s/usb%d%s_%05.1f.png" % [_shots, _usb,
			"" if _then.is_empty() else "_" + _then, at])
	sys.call("toggle_power")
	var t2 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t2 < 5000:
		await get_tree().process_frame


func _rgb_bytes(img: Image) -> PackedByteArray:
	var src := img.get_data()
	var out := PackedByteArray()
	out.resize(img.get_width() * img.get_height() * 3)
	var i := 0
	var o := 0
	while o < out.size():
		out[o] = src[i]
		out[o + 1] = src[i + 1]
		out[o + 2] = src[i + 2]
		o += 3
		i += 4
	return out
