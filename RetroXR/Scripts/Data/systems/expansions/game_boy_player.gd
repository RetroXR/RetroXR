## Game Boy Player (DOL-017) — the box the GameCube stands on, with a Game Boy
## Advance cartridge slot in its front.
##
## One of the expansion units; see ExpansionCatalog for how a unit file is
## assembled into the catalog, and expansion_defs.gd for the MOUNT_* values.
extends RefCounted

const ID := "game_boy_player"

# It bolts to the GameCube's underside: its tower goes up into the Hi-Speed Port
# bay behind the cover in the console's floor, the console's feet sit in the
# pockets on its top face, and two coin-turned screws from underneath hold the
# pair together. The Game Pak goes into the slot in its front, label down; EJECT,
# a lever in its right side, pushes it back out. The console then boots the
# Start-Up Disc and runs the cartridge on the television.
#
# `size` is the shell's bounds, 150.04 x 57.55 x 155.25 mm (RetroXR-models'
# nintendo/gamecube/game-boy-player, from wesk's laser scan): the tray and top
# plate, and the tower and its plug collar standing 24 mm over the plate at the
# right rear. The console does not stand on the top of that box but on the
# pockets' floors, 31.2 mm over the floor: DECK_Y.
#
# `media` is gba, an existing system, so the Game Boy Advance library already
# fills the slot: a cartridge a player owns is the same object either way.
const ROW := {
	"label": "Game Boy Player",
	"host": "gc",
	"media": "gba",
	"mount": ExpansionDefs.MOUNT_BELOW,
	"size": Vector3(0.15004, 0.05755, 0.15525),
	"seat_y": DECK_Y,
	"loader": MediaDimensions.LOADER_SLOT,
	# Offered on the GameCube's card: its media would file it on the Game Boy
	# Advance's, where nobody looks for a box a GameCube stands on.
	"card": "gc",
	"cover_socket": COVER_SOCKET,
	# Label down, contacts first: a quarter turn forward about X takes the
	# cartridge's top (+Y) out toward the player and its label (+Z) to the floor.
	"slot_basis": Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0)),
	"slot_marker_depth": true,
	# The lever slides toward the front, up to 12 mm.
	"eject_axis": Vector3(0, 0, 1),
	"eject_travel": 0.012,
	# The beam hits the shell, not a box round it.
	"pointer_mesh": true,
}

## The pockets' floors, where the GameCube's front feet rest (its rear skids sit
## in the rear slots, 0.2 mm lower): 31.2 mm over the floor, 2.425 mm above the
## middle of the box. A console seated on the top of the box hung on the tower.
const DECK_Y := 0.002425

## The opening in the GameCube's floor the player's tower goes up into. It has a
## cover of its own, and the console only stands on the player once it is off.
const COVER_SOCKET := "hi_speed_port"


# VERIFIED by running it (2026-10-29, the Dolphin libretro core, the Start-Up
# Disc and a Game Boy Advance cartridge): the core publishes a "GBP" subsystem
# (id 257) whose content is the GBA ROM FIRST and the GameCube disc second, and
# the cartridge's title screen comes up inside the player's frame. No GBA BIOS:
# mGBA's built-in substitute is used. The retroXR fork of the core attaches the
# player for a subsystem load (and detaches it for any other), so a stock
# Dolphin.ini does not have to have it set. An empty slot falls back to the plain
# load of the disc, which boots the Start-Up Disc to its "not connected" screen.
const BOOT := {
	"gc|game_boy_player": {
		"core": "dolphin",
		"roms": ["host", "expansion:game_boy_player"],
		"subsystem": {"ident": "GBP",
			"roms": ["expansion_media:game_boy_player", "host"]},
	},
}
