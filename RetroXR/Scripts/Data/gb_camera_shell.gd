## GbCameraShell — the Game Boy Camera, which is a cartridge with a camera on its
## head rather than a game in a shell.
##
## Read from the ROM header, 0x150 bytes, never by hashing the file: the cartridge
## type at 0x147 is 0xFC (POCKET CAMERA, Pan Docs "0147 - Cartridge Type"), which
## no game has. Measured on Game Boy Camera (USA, Europe): title GAMEBOYCAMERA,
## type 0xFC, Nintendo. In Japan it was the Pocket Camera, with a ROM of its own:
## Pocket Camera (Japan) (Rev 1), title POCKETCAMERA, type 0xFC, destination 0x00
## (Japan; the gold edition's is 0x01, overseas). Its units wear their own labels
## (a mod's model prints them: dress_region()).
##
## The body is a stand-in made of primitives. Its lower 65 mm is a Game Boy
## cartridge, and that is all MediaDimensions and every slot in the room know of
## it, so it seats wherever a Game Boy cartridge does and exactly as one does.
## The head is the body's "Overhang" (RetroCartridge.OVERHANG_NODE): it stands
## outside whatever the cartridge is seated in, with boxes of its own to be taken
## by. The ball stands on top of it and swivels about its upright axle on a
## VRKnob, the lens swinging round sideways from the label side to the back.
##
## Its colors are its own (PALETTE, Resources/gb_camera_shells.tres): the back half
## and the "Nintendo" half of the ball in the color, the front half and the eye
## half charcoal, as on every retail unit (RetroCartridge.paint_camera). One ROM
## served every color but
## one, so the header cannot say which; that one is blue. The gold Legend of Zelda
## edition shipped with a ROM of its own, titled GAMEBOYCAMERA G, and is gold. The
## Pocket Camera came in red, yellow, green and clear purple, and its ROM is red.
## A Game Boy palette color or a mixed one can be asked of it too.
##
## GbcCartShell names this class, and it is compiled early, at boot: it names no
## class of the cartridge, its colors or its lens (which name RetroCartridge and
## RetroSystem), or that early load would take in the cartridge and the controllers
## and their cords with it. What needs those classes is RetroCartridge's.
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
## CartridgeColor's palette id for the camera's colors. Their ids are the camera's
## own ("camera_red"), so a swatch from it says which body it means.
const PALETTE := "gb_camera"
const DEFAULT_PRESET := &"camera_blue"
const GOLD_PRESET := &"camera_gold"
const PRESET_PREFIX := "camera_"
## The lens's class_name (gb_camera_eye.gd).
const EYE_CLASS := &"GbCameraEye"
## The gold edition's ROM's title (the plain one's is GAMEBOYCAMERA).
const GOLD_TITLE := "GAMEBOYCAMERA G"
## The Pocket Camera's color: its ROM, Japan's, is the same for its four (red,
## yellow, green, clear purple), and red is the first of them.
const JAPAN_PRESET := &"camera_red"
## Every retail camera's front half, the label side and the eye half of the ball.
const FRONT := Color(0.2627, 0.2588, 0.2902)
## A real camera's two halves, by the names its model gives their plastic. The
## stand-in has one plastic for both, which takes the color whole.
const FRONT_PLASTIC := &"Tintable_Front_Plastic"
const BACK_PLASTIC := &"Tintable_Rear_Plastic"
## The ball's halves, in plastics of their own: the front's charcoal and the back's
## color on every edition but the clear one, whose ball is opaque (CLEAR_BALL).
const BALL_FRONT_PLASTIC := &"GBCAM_BallFront"
const BALL_BACK_PLASTIC := &"GBCAM_BallBack"
## A clear edition's ball, [eye half, back half]: the Pocket Camera's clear purple
## has an opaque violet front half and a light gray back (photographs of it; the
## model's colors.json). A clear color with none keeps a charcoal eye half and the
## color, opaque, behind.
const CLEAR_BALL := {
	&"camera_clear_purple": [Color8(88, 66, 158), Color8(190, 190, 200)],
}
## A mod model's main board, inside the cartridge: shown only through a clear shell.
const BOARD_NODE := "Board"
## A real camera's front label: its ground is the back's color, which a mod's model
## gives as printed art (label_art(), or dress_region(japan), which also puts on a
## Japanese unit's back: its own FCC label, a serial sticker, no barcode).
const LABEL_MESH := "CameraLabel"
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


## The color a camera ROM came in: gold for the gold edition's, red for the Pocket
## Camera's, blue for the rest.
static func preset_for_header(header: PackedByteArray) -> StringName:
	if GbCartShell.header_title(header) == GOLD_TITLE:
		return GOLD_PRESET
	return JAPAN_PRESET if is_japanese(header) else DEFAULT_PRESET


## Whether a camera ROM is the Pocket Camera's: its header's destination code is
## Japan's.
static func is_japanese(header: PackedByteArray) -> bool:
	return header.size() >= GbCartShell.HEADER_BYTES \
		and header[GbCartShell.DESTINATION_AT] == GbCartShell.DESTINATION_JAPAN


static func is_japanese_rom(rom_path: String) -> bool:
	return is_japanese(GbCartShell.read_header(rom_path))


static func preset_for_rom(rom_path: String) -> StringName:
	return preset_for_header(GbCartShell.read_header(rom_path))


## Whether `id` is one of the camera's own colors: their ids are "camera_" and the
## color (Resources/gb_camera_shells.tres), apart from every other palette's.
static func is_preset(id: StringName) -> bool:
	return String(id).begins_with(PRESET_PREFIX) and String(id).length() > PRESET_PREFIX.length()


## Whether a cartridge body is a camera: it has the lens (a node whose script is
## GbCameraEye's). The game's stand-in is one, and so is a mod's camera body. The
## lens's class is asked by name, not named (see above).
static func is_camera_model(model: Node) -> bool:
	if model == null:
		return false
	for n in model.find_children("*", "Node3D", true, false):
		var script := n.get_script() as Script
		if script != null and script.get_global_name() == EYE_CLASS:
			return true
	return false
