## The King of Fighters '95 ROM Cartridge — the graphics half of SNK's Saturn
## port, which came in the box with the disc, in the slot behind the disc lid.
##
## One of the expansion units; see ExpansionCatalog for how a unit file is
## assembled into the catalog, and expansion_defs.gd for the MOUNT_* values.
extends RefCounted

const ID := "sega_saturn_kof95_rom"

const _BACKUP := preload("res://Scripts/Data/systems/expansions/sega_saturn_ram_cart.gd")

# Half of a game, so a Saturn with it seated starts only where its dump is
# installed: `firmware` is the file Beetle Saturn opens for its CART_KOF95
# (mednafen/settings.c, ss.cart.kof95_path), in the core's system directory.
# Without it the core would run with the slot empty (cart.c falls through to no
# cartridge), so power-on refuses with "BIOS required" instead, naming the dump.
# The shell is the Backup RAM Cartridge's; the slot is the same one.
const ROW := {
	"label": "KOF '95 ROM Cartridge",
	"host": "saturn",
	"mount": ExpansionDefs.MOUNT_ABOVE,
	"size": _BACKUP.SIZE,
	"loader": MediaDimensions.LOADER_NONE,
	"label_top": true,
	"firmware": ["mpr-18811-mx.ic1"],
}


const BOOT := {
	# VERIFIED against beetle-saturn-libretro (mednafen/ss/cart.c, libretro.c):
	# Beetle maps this cartridge from "The King of Fighters '95" in
	# beetle_saturn_cart; YabaSanshiro's yabasanshiro_addon_cart offers RAM
	# cartridges and nothing else, so a Quest with this seated has to run Beetle
	# or run the game without its graphics. No `roms`: the disc in the console is
	# what boots, and the cartridge is the forced option.
	"saturn|sega_saturn_kof95_rom": {
		"core": "mednafen_saturn",
	},
}
