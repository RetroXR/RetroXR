## Starts a MAME / FBNeo romset in the arcade cabinet and prints what the core says. NEEDS a
## real core and romset (not a suite): the point is the REASON a refused game reports,
## which used to be "This core refused the game." and now carries the core's own words
## ("dl-1425.bin NOT FOUND", ...).
##
##   "$godot" --headless --path RetroXR res://Tools/cores/arcade_load_probe.tscn \
##       -- --rom=/home/me/retroxr/roms/mame/dino.zip [--system=mame]
extends Node3D

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const CART_SCENE := preload("res://Scenes/Objects/media/cartridge.tscn")


func _ready() -> void:
	var rom := ""
	var systemid := "arcade"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rom="):
			rom = a.substr(6)
		elif a.begins_with("--system="):
			systemid = a.substr(9)
	if rom.is_empty() or not FileAccess.file_exists(rom):
		print("[probe] pass --rom=<an existing romset zip>")
		get_tree().quit(1)
		return
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("[probe] TIMED OUT")
		get_tree().quit(2))
	var sys := SYSTEM_SCENE.instantiate() as RetroSystem
	sys.model_id = "arcade_cabinet_generic"
	sys.systemid = systemid
	sys.freeze = true
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
	print("[probe] power on, rom=", rom)
	sys.power_on()
	await get_tree().create_timer(60.0).timeout
	print("[probe] still running after 60 s: the game started")
	get_tree().quit(0)
