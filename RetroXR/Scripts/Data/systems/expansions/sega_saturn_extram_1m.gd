## Extended RAM Cartridge (HSS-0150) — 1 MB more work RAM for a Sega Saturn, in
## the cartridge slot behind the disc lid.
##
## One of the expansion units; see ExpansionCatalog for how a unit file is
## assembled into the catalog, and expansion_defs.gd for the MOUNT_* values.
extends RefCounted

const ID := "sega_saturn_extram_1m"

const _BACKUP := preload("res://Scripts/Data/systems/expansions/sega_saturn_ram_cart.gd")

# RAM only: no memory family (it is volatile), no media, no BOOT key -- the disc
# still boots, and the whole of what seating it does is a pinned core option
# (ForcedCoreOptions.saturn_cart), as an Expansion Pak's is. It stands in the
# Backup RAM Cartridge's slot in the Backup RAM Cartridge's shell, so the two
# cannot both be in, which is the hardware: a game that wants the RAM saves to
# the console's System Memory.
#
# The SNK fighters and a few others want this one and NOT the 4 MB cartridge:
# Beetle Saturn's own game database (mednafen/ss/db.c) marks Real Bout Garou
# Densetsu and Samurai Spirits: Amakusa Kourin incompatible with 4 MB.
const ROW := {
	"label": "Extended RAM Cartridge 1MB",
	"host": "saturn",
	"mount": ExpansionDefs.MOUNT_ABOVE,
	"size": _BACKUP.SIZE,
	"loader": MediaDimensions.LOADER_NONE,
	"label_top": true,
}


const BOOT := {}
