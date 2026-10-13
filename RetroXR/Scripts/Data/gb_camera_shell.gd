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
class_name GbCameraShell
extends RefCounted

const BODY := "res://Scenes/Objects/media/game_boy_camera_body.tscn"
## RetroCartridge.body_region for this body, forced onto any Game Boy ROM.
const BODY_CAMERA := "camera"
const CART_TYPE_CAMERA := 0xFC
const DEFAULT_PRESET := &"blue"


static func is_body(path: String) -> bool:
	return path == BODY


static func is_camera(header: PackedByteArray) -> bool:
	return header.size() >= GbCartShell.HEADER_BYTES \
		and header[GbcCartShell.CART_TYPE_AT] == CART_TYPE_CAMERA
