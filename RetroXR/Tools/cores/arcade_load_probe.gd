## Starts a MAME / FBNeo romset in the arcade cabinet and prints what the core says. NEEDS a
## real core and romset (not a suite): the point is the REASON a refused game reports,
## which used to be "This core refused the game." and now carries the core's own words
## ("dl-1425.bin NOT FOUND", ...).
##
##   "$godot" --headless --path RetroXR res://Tools/cores/arcade_load_probe.tscn \
##       -- --rom=/home/me/retroxr/roms/mame/dino.zip [--system=arcade] [--core=fbneo]
##
## --audio samples the loudest peak on any audio bus (and the sink's fill) for 40 s once the
## game runs, so "no sound" is a number: a game that has started and is silent prints a peak
## near -80 dB. Run a control with sound at once (Bubble Bobble) beside the game in question.
##
## --play adds, with --audio, a coin and START at 8 s (the cabinet's own coin door, then the
## player's panel attached and the START key held), because many games are silent on their
## attract screen and a silent number would then prove nothing.
##
## --model=<registry id> wears another cabinet (arcade_cabinet_lightgun...), whose guns are built with it.
##
## --controllers prints the devices the core lists for each port (its own ids for a gun, a pad...).
##
## --core= pins the core (`mame`, `fbneo`, ...); without it the system's own pick is used,
## which for `arcade` is current MAME. The probe prints the core it really ran.
extends Node3D

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const CART_SCENE := preload("res://Scenes/Objects/media/cartridge.tscn")


func _ready() -> void:
	var rom := ""
	var systemid := "arcade"
	var core := ""
	var model_id := "arcade_cabinet_generic"
	var audio := false
	var controllers := false
	var play := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rom="):
			rom = a.substr(6)
		elif a.begins_with("--system="):
			systemid = a.substr(9)
		elif a.begins_with("--core="):
			core = a.substr(7)
		elif a.begins_with("--model="):
			model_id = a.substr(8)
		elif a == "--audio":
			audio = true
		elif a == "--play":
			play = true
		elif a == "--controllers":
			controllers = true
	if rom.is_empty() or not FileAccess.file_exists(rom):
		print("[probe] pass --rom=<an existing romset zip>")
		get_tree().quit(1)
		return
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("[probe] TIMED OUT")
		get_tree().quit(2))
	var sys := SYSTEM_SCENE.instantiate() as RetroSystem
	sys.model_id = model_id
	sys.systemid = systemid
	sys.freeze = true
	if not core.is_empty():
		sys.core_name = core
	add_child(sys)
	for i in 6:
		await get_tree().process_frame
	(sys.get_model() as RetroSystemModelArcadeCabinet).set_lid_angle_deg(90.0)
	var cart := CART_SCENE.instantiate() as Node3D
	cart.systemid = systemid
	cart.rom_path = rom
	cart.freeze = true
	cart.position = Vector3(0, 3, 0)
	add_child(cart)
	for i in 8:
		await get_tree().process_frame
	(sys.get_node("CartridgeSlot") as XRToolsSnapZone).pick_up_object(cart)
	for i in 6:
		await get_tree().process_frame
	var lib: Node = sys.get_libretro_node()
	lib.connect("content_load_failed", func(reason: String) -> void:
		print("[probe] content_load_failed: ", reason.replace("\n", " | "))
		get_tree().quit(0))
	print("[probe] power on, rom=", rom, " core=", sys.core_name)
	sys.power_on()
	if audio:
		# A 3D voice is only heard by a listener: with no camera in the tree the mixer has
		# nobody to place it for, and every bus reads silence whatever the core plays.
		var cam := Camera3D.new()
		add_child(cam)
		cam.current = true
		cam.position = Vector3(0, 1.2, 1.6)
		await get_tree().create_timer(8.0).timeout
		var loudest := -200.0
		var fill_max := 0
		var fill_min := 100
		for i in 80:
			await get_tree().create_timer(0.5).timeout
			if play and i == 0:
				var cab := sys.get_model() as RetroSystemModelArcadeCabinet
				for m in cab.modules_of_kind(ArcadeProfiles.KIND_COIN):
					if (m as ArcadeCoinModule).player == 0:
						(m as ArcadeCoinModule).insert_coin()
			if play and i == 2:
				var cab2 := sys.get_model() as RetroSystemModelArcadeCabinet
				for m in cab2.modules_of_kind(ArcadeProfiles.KIND_STICK_BUTTONS):
					if (m as ArcadeControlModule).player == 0:
						var grip := (m as ArcadeControlModule).grip()
						grip.pointer_event(XRToolsPointerEvent.new(XRToolsPointerEvent.Type.PRESSED, null, grip, Vector3.ZERO, Vector3.ZERO))
				Input.action_press("RETRO_JOYPAD_START")
			if play and i == 4:
				Input.action_release("RETRO_JOYPAD_START")
			if play and i > 8 and i % 6 == 0:
				Input.action_press("RETRO_JOYPAD_B")
			if play and i > 8 and i % 6 == 1:
				Input.action_release("RETRO_JOYPAD_B")
			for b in AudioServer.bus_count:
				loudest = maxf(loudest, maxf(AudioServer.get_bus_peak_volume_left_db(b, 0),
					AudioServer.get_bus_peak_volume_right_db(b, 0)))
			var f := int(lib.GetAudioBufferOccupancy()) if lib.has_method("GetAudioBufferOccupancy") else -1
			fill_max = maxi(fill_max, f)
			fill_min = mini(fill_min, f)
		print("[probe] audio: loudest bus peak %.1f dB over 40 s, sink fill %d..%d%%, ready=%s"
			% [loudest, fill_min, fill_max, str(lib.IsAudioReady()) if lib.has_method("IsAudioReady") else "?"])
		get_tree().quit(0)
		return
	if controllers:
		await get_tree().create_timer(6.0).timeout
		for entry: Dictionary in sys._controller_info:
			print("[probe] controllers port %s: %s" % [entry.get("port"), JSON.stringify(entry.get("controllers", []))])
		get_tree().quit(0)
		return
	await get_tree().create_timer(60.0).timeout
	print("[probe] still running after 60 s: the game started")
	get_tree().quit(0)
