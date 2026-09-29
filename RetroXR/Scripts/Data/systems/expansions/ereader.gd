## Card e-Reader (Japan, PEAJ) — the original 4 MB reader.
##
## One of three revisions, one unit each, because a reader IS its dump and the
## dumps are not interchangeable: cards are region-locked and the reader answers
## a foreign card with its own Region Error screen. See ereader_plus.gd and
## ereader_usa.gd, which differ from this file only in their label and their game
## code.
##
## See ExpansionCatalog for how a unit file is assembled into the catalog, and
## expansion_defs.gd for the MOUNT_* values.
extends RefCounted

const ID := "ereader"

# A Game Boy Advance cartridge with a slit across its front that a printed card
# is SLID through, dotcode edge first, lying flat with its dotcode up to the
# scanner. LOADER_SWIPE, so it builds a swipe groove and no bay at all -- the card
# is never seated, and a snap zone would capture it mid-swipe.
#
# The unit id IS the media systemid, so has_own_card is true and the e-Reader
# tile carries the reader and its cards and nothing else. An id that differed
# from the media put the tile back on the generic console path, which offered a
# Primitive System, a Primitive Controller and a composite lead for a cartridge.
# The other two revisions have no card of their own and are therefore carded
# HERE, which is where a player picking a reader is already standing.
#
# Its program is the e-Reader cartridge dump, and it comes out of the LIBRARY --
# AdapterRoms finds it by the header code below, on the Game Boy Advance shelf or
# beside the cards in the e-Reader one. It is not firmware: it is an ordinary GBA
# ROM, and asking a player to install a second copy of it into the core's system
# directory, under a name of ours, was the room inventing a BIOS the hardware
# does not have. The Super Game Boy still works the older way -- see
# ExpansionCatalog.firmware_rom_path for why the two differ.
#
# The shell is the US e-Reader (AGB-014), modelled from photographs and calipers
# of a real unit and debranded (imported-assets/consoles/ereader/). The two
# Japanese revisions wear it too: the Card e-Reader+ is the same hardware, and
# the original PEAJ differs mainly in having no link sockets.
#
# SIZE is the shell's own bounds, tongue included, so it is fitted 1:1. The
# CONNECTOR and SWIPE_SLIT below are read off the model in that frame (the
# centre of those bounds; +Y up, the card-slit face on +Z, which is the face a
# console's cartridge slot turns away, the way it turns a cartridge's label).
const SIZE := Vector3(0.094, 0.11197, 0.04257)
const SHELL := "res://imported-assets/consoles/ereader/ereader.glb"
# 3,938, 2,349 and 1,468 triangles; see the LICENSE file beside them.
const SHELL_LODS := [
	["res://imported-assets/consoles/ereader/ereader_lod1.glb", 0.8],
	["res://imported-assets/consoles/ereader/ereader_lod2.glb", 2.0],
]
# The reader's tongue is a GBA cartridge's lower half: it goes INTO the slot
# while the housing stands over the console. So the seat takes the point where
# a GBA cartridge's middle would be -- 17.5 mm (half of MediaDimensions' 35 mm
# GBA cart) up from the tongue's bottom edge, at the tongue's depth, which is
# 15.6 mm behind the centre of the model. Follow that entry if it changes: the
# tongue's bottom edge then reaches as deep into the slot as a cartridge's.
const CONNECTOR := Vector3(0.0, -0.03849, -0.01559)
# The card channel: 1 mm tall at 79.9 mm above the tongue's bottom edge,
# running the full width and 22 mm in from the front face to a rear wall. The
# groove line is 0.3 mm in front of that wall, where a card's coded edge stops.
# Groove frame (CardSwipeSlit): travel along the width, the card standing out of
# the front (+Z), its printed face up (+Y) to the scanner above the channel.
const SWIPE_SLIT := Transform3D(
	Basis(Vector3(-1.0, 0.0, 0.0), Vector3(0.0, 0.0, 1.0), Vector3(0.0, 1.0, 0.0)),
	Vector3(0.0, 0.04139, -0.00379))
const ROW := {
	"label": "Card e-Reader",
	"host": "gba",
	"media": "ereader",
	"mount": ExpansionDefs.MOUNT_CARTRIDGE,
	# The battery is in the READER, not in anything it reads. Its 128 KiB of
	# flash holds the scanner calibration and the cards it has already taken --
	# the "Access saved data" row on its menu is that flash -- and a card is a
	# sheet of printed paper with no memory in it at all. Without this the unit
	# owns no save: it is not a cartridge with a save_id and it has no bay, so
	# every other route in _compose_sram_path answers "", the core is handed an
	# empty SRAM path, and each launch starts from blank flash.
	"save_owner": ExpansionDefs.SAVE_OWNER_UNIT,
	"size": SIZE,
	"shell": SHELL,
	"shell_lods": SHELL_LODS,
	"connector": CONNECTOR,
	"swipe_slit": SWIPE_SLIT,
	"loader": MediaDimensions.LOADER_SWIPE,
	# The game code in the dump's own header, which is what mGBA's override table
	# matches to switch the reader hardware on, and what AdapterRoms matches to
	# find the program. It does three jobs from one fact: a dump in the library
	# spawns the reader rather than a cartridge, the revision follows the file
	# rather than a filename, and the dump stops being offered as a game.
	"rom_code": "PEAJ",
}


const BOOT := {
	# The e-Reader boots as an ordinary GBA cartridge -- its dump is the program,
	# and mGBA switches the reader hardware on from the game code in the header
	# (PEAJ/PSAJ/PSAE in the core's own override table), not from anything named
	# here. The cards are not content: they arrive at runtime through disk
	# control, one image per strip.
	#
	# No `subsystem`. mGBA's retro_load_game_special is a stub that returns false
	# and its .info says load_subsystem = "false", so there is no ident to name and
	# inventing one would be worse than leaving it blank.
	"gba|ereader": {
		"core": "mgba",
		"roms": ["expansion:ereader"],
	},
}
