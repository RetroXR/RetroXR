## Ultraman: Hikari no Kyojin Densetsu ROM Cartridge — the second of the two
## Saturn games that came with a cartridge of their own data, in the slot behind
## the disc lid.
##
## One of the expansion units; see ExpansionCatalog for how a unit file is
## assembled into the catalog, and expansion_defs.gd for the MOUNT_* values.
extends RefCounted

const ID := "sega_saturn_ultraman_rom"

const _BACKUP := preload("res://Scripts/Data/systems/expansions/sega_saturn_ram_cart.gd")

# The KOF '95 cartridge's row with the other dump: see sega_saturn_kof95_rom.gd.
# The file is ss.cart.ultraman_path in Beetle Saturn's mednafen/settings.c.
const ROW := {
	"label": "Ultraman ROM Cartridge",
	"host": "saturn",
	"mount": ExpansionDefs.MOUNT_ABOVE,
	"size": _BACKUP.SIZE,
	"loader": MediaDimensions.LOADER_NONE,
	"label_top": true,
	"firmware": ["mpr-19367-mx.ic1"],
}


const BOOT := {
	# VERIFIED at source, as the KOF '95 row is: Beetle's "Ultraman: Hikari no
	# Kyojin Densetsu" cart, and no YabaSanshiro equivalent.
	"saturn|sega_saturn_ultraman_rom": {
		"core": "mednafen_saturn",
	},
}
