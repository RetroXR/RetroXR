## Which key opens a core's own DIP switch / service menu. NEEDS a real core and romset (not a suite).
## Starts the romset in the arcade cabinet, saves the core's picture, taps the keys named in --keys
## (libretro key names: tab, f2, f3, return, up, down, left, right, escape...) and saves the picture
## again, so the menu is seen or it is not. ONE core per process.
##
##   "$godot" --headless --path RetroXR res://Tools/cores/arcade_dip_probe.tscn \
##       -- --rom=/home/me/retroxr/roms/mame/dino.zip --core=mame --keys=tab --out=/some/dir
##
## --keys takes a list ("tab,down,down,return"), each tapped for 0.12 s with 0.25 s between, as RetroSystem.press_dip_switch does;
## --wait=<seconds> is how long the game runs before the first picture (default 15).
extends Node3D

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const CART_SCENE := preload("res://Scenes/Objects/media/cartridge.tscn")

## libretro.h RETROK_*
const KEYS := {
	"tab": 9, "return": 13, "escape": 27, "space": 32, "up": 273, "down": 274, "right": 275, "left": 276,
	"f1": 282, "f2": 283, "f3": 284, "f4": 285, "f5": 286, "f6": 287, "f7": 288, "f8": 289, "f9": 290,
	"f10": 291, "f11": 292, "f12": 293, "pause": 19, "p": 112, "l": 108,
}


func _ready() -> void:
	var rom := ""
	var core := ""
	var out := "/tmp"
	var keys: Array[String] = []
	var wait := 15.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--rom="):
			rom = a.substr(6)
		elif a.begins_with("--core="):
			core = a.substr(7)
		elif a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--wait="):
			wait = float(a.substr(7))
		elif a.begins_with("--keys="):
			for k in a.substr(7).split(","):
				keys.append(k)
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
	_shot(lib, out + "/before.png")
	for k in keys:
		var code: int = KEYS.get(k, 0)
		if code == 0:
			print("[probe] unknown key ", k)
			continue
		lib.SetKeyState(0, code, true, code if code >= 32 and code <= 126 else 0)
		await get_tree().create_timer(0.12).timeout
		lib.SetKeyState(0, code, false, 0)
		await get_tree().create_timer(0.25).timeout
	await get_tree().create_timer(1.0).timeout
	_shot(lib, out + "/after.png")
	get_tree().quit(0)


func _shot(lib: Libretro, path: String) -> void:
	var img: Image = lib.GetVideoImage()
	if img == null or img.is_empty():
		print("[probe] no picture for ", path)
		return
	print("[probe] saved ", path, " ", img.get_size(), " err=", img.save_png(path))
