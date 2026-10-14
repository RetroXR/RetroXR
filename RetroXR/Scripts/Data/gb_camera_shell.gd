## GbCameraShell — the Game Boy Camera, which is a cartridge with a camera on its
## head rather than a game in a shell.
##
## Read from the ROM header, 0x150 bytes, never by hashing the file: the cartridge
## type at 0x147 is 0xFC (POCKET CAMERA, Pan Docs "0147 - Cartridge Type"), which
## no game has. Measured on Game Boy Camera (USA, Europe): title GAMEBOYCAMERA,
## type 0xFC, Nintendo.
##
## The body is a stand-in made of primitives. Its lower 65 mm is a Game Boy
## cartridge, and that is all MediaDimensions and every slot in the room know of
## it, so it seats wherever a Game Boy cartridge does and exactly as one does.
## The head is the body's "Overhang" (RetroCartridge.OVERHANG_NODE): it stands
## outside whatever the cartridge is seated in, with boxes of its own to be taken
## by. The ball stands on top of it and swivels about its upright axle on a
## VRKnob, the lens swinging round sideways from the label side to the back.
##
## One ROM served every colour the camera was sold in, so the header cannot say
## which this one is. It is blue; the Game Boy palette's other shells repaint it,
## as they do a cartridge.
##
## It is a camera: the lens is a GbCameraEye, and what it sees goes to the core
## through libretro's camera interface. That is a fact about ONE core. mGBA asks
## for the interface and photographs what it is handed; Gambatte refuses the
## cartridge type and the load fails (libgambatte cartridge.cpp, "Pocket Camera
## ROM not supported"); SameBoy runs the cartridge but its libretro port asks for
## no picture. So the ROM names its core (boot_for), the way a Slot-2 cartridge
## names melonDS DS, and a machine holding it runs mGBA whatever it runs a game on.
class_name GbCameraShell
extends RefCounted

const BODY := "res://Scenes/Objects/media/game_boy_camera_body.tscn"
## RetroCartridge.body_region for this body, forced onto any Game Boy ROM.
const BODY_CAMERA := "camera"
const CART_TYPE_CAMERA := 0xFC
const DEFAULT_PRESET := &"blue"
## The core a machine runs while this ROM is in its slot.
const CORE := "mgba"
## The machines whose own slot takes a Game Boy cartridge (RetroSystem._MEDIA_COMPAT).
const HOSTS := ["gb", "gbc", "gba"]

## rom path -> whether its header is the camera's. Asked every time a machine
## resolves its core, and each fresh answer opens the file.
static var _camera_roms: Dictionary = {}


static func is_body(path: String) -> bool:
	return path == BODY


static func is_camera(header: PackedByteArray) -> bool:
	return header.size() >= GbCartShell.HEADER_BYTES \
		and header[GbcCartShell.CART_TYPE_AT] == CART_TYPE_CAMERA


## Whether the file at `rom_path` is the camera's ROM. Keyed on the header and not
## on the body it was spawned in: a camera ROM forced into a game's shell is still
## a ROM Gambatte cannot load.
##
## A header that could not be read is not remembered, so a ROM still downloading
## is asked again once it is there. An archive answers false, as it does for the
## body: the header read sees the zip.
static func is_camera_rom(rom_path: String) -> bool:
	if rom_path.is_empty():
		return false
	if _camera_roms.has(rom_path):
		return bool(_camera_roms[rom_path])
	var header := GbCartShell.read_header(rom_path)
	if header.size() < GbCartShell.HEADER_BYTES:
		return false
	var camera := is_camera(header)
	_camera_roms[rom_path] = camera
	return camera


## The launch recipe a machine of `systemid` takes on with `rom_path` in its own
## slot, or {} -- which is every ROM but one. Only a core: it loads as any Game
## Boy cartridge does.
static func boot_for(systemid: String, rom_path: String) -> Dictionary:
	if not HOSTS.has(systemid) or not is_camera_rom(rom_path):
		return {}
	return {"core": CORE}
