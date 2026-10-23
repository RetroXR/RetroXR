## What a core says its inputs are (SET_INPUT_DESCRIPTORS). NEEDS a real core and romset (not a suite).
## Starts the romset in the arcade cabinet, waits, and prints every descriptor the core published
## through Libretro.GetInputDescriptors(). ONE core per process.
##
##   "$godot" --headless --path RetroXR res://Tools/cores/arcade_descriptors_probe.tscn \
##       -- --rom=/home/me/retroxr/roms/mame/sf2.zip --core=fbneo
##
## --wait=<seconds> is how long the game runs before asking (default 10). It also prints how the cabinet dressed itself.
extends Node3D

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const CART_SCENE := preload("res://Scenes/Objects/media/cartridge.tscn")


func _ready() -> void:
	var rom := ""
	var core := ""
	var wait := 10.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rom="):
			rom = a.substr(6)
		elif a.begins_with("--core="):
			core = a.substr(7)
		elif a.begins_with("--wait="):
			wait = float(a.substr(7))
	if rom.is_empty() or not FileAccess.file_exists(rom):
		print("[probe] pass --rom=<an existing romset zip>")
		get_tree().quit(1)
		return
	get_tree().create_timer(wait + 60.0).timeout.connect(func() -> void:
		print("[probe] TIMED OUT")
		get_tree().quit(2))
	var sys := SYSTEM_SCENE.instantiate() as RetroSystem
	sys.model_id = "arcade_cabinet_generic"
	sys.systemid = "arcade"
	sys.freeze = true
	if not core.is_empty():
		sys.core_name = core
	add_child(sys)
	for i in 6:
		await get_tree().process_frame
	(sys.get_model() as RetroSystemModelArcadeCabinet).set_lid_angle_deg(90.0)
	var cart := CART_SCENE.instantiate() as Node3D
	cart.systemid = "arcade"
	cart.rom_path = rom
	cart.freeze = true
	cart.position = Vector3(0, 3, 0)
	add_child(cart)
	for i in 8:
		await get_tree().process_frame
	var bay: ArcadeBayUnit = sys.get_bay()
	var slot: XRToolsSnapZone = bay.slot if bay != null else sys.get_node("CartridgeSlot") as XRToolsSnapZone
	slot.pick_up_object(cart)
	for i in 6:
		await get_tree().process_frame
	var lib: Libretro = sys.get_libretro_node()
	lib.connect("content_load_failed", func(reason: String) -> void:
		print("[probe] content_load_failed: ", reason.replace("\n", " | "))
		get_tree().quit(1))
	sys.power_on()
	print("[probe] core=", sys._resolve_core(), " rom=", rom)
	await get_tree().create_timer(wait).timeout
	var descs: Array = lib.GetInputDescriptors()
	print("[probe] descriptors=", descs.size())
	for d: Dictionary in descs:
		print("[probe] port=%d device=%d index=%d id=%d  %s" % [d["port"], d["device"], d["index"], d["id"], d["description"]])
	# And what the cabinet made of it (RetroSystemModelArcadeCabinet polls the core by itself).
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	var game := model.game_profile()
	print("[probe] profile: ", "none" if game == null else game.summary())
	for panel: ArcadeControlModule in model.modules_of_kind(ArcadeProfiles.KIND_STICK_BUTTONS):
		var line := "P%d visible=%s stick=%s caps=" % [panel.player + 1, panel.visible, panel.stick_shown()]
		for i in ArcadeProfiles.BUTTON_COUNT:
			line += ("%d" % i if panel.cap_shown(i) else "-") + ("(%s)" % panel.cap_label(i).replace("\n", "/") if not panel.cap_label(i).is_empty() else "") + " "
		print("[probe] ", line)
	for door: ArcadeCoinModule in model.modules_of_kind(ArcadeProfiles.KIND_COIN):
		print("[probe] coin door P%d enabled=%s" % [door.player + 1, door.door_enabled()])
	get_tree().quit(0)
