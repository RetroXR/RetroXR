## Extended RAM Cartridge 4MB (HSS-0167) — 4 MB more work RAM for a Sega Saturn,
## the cartridge Capcom's later fighters ask for, in the slot behind the disc lid.
##
## One of the expansion units; see ExpansionCatalog for how a unit file is
## assembled into the catalog, and expansion_defs.gd for the MOUNT_* values.
extends RefCounted

const ID := "sega_saturn_extram_4m"

const _BACKUP := preload("res://Scripts/Data/systems/expansions/sega_saturn_ram_cart.gd")

# The 1 MB cartridge's row, with four times the RAM: see sega_saturn_extram_1m.gd.
# Beetle Saturn's database wants it for X-Men vs. Street Fighter, Marvel Super
# Heroes vs. Street Fighter, Vampire Savior, Street Fighter Zero 3, Pocket
# Fighter, Final Fight Revenge and the Dungeons & Dragons Collection.
const ROW := {
	"label": "Extended RAM Cartridge 4MB",
	"host": "saturn",
	"mount": ExpansionDefs.MOUNT_ABOVE,
	"size": _BACKUP.SIZE,
	"loader": MediaDimensions.LOADER_NONE,
	"label_top": true,
}


const BOOT := {}
