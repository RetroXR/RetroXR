## Sega CD — the disc drive the Mega Drive stands on.
##
## One of the eleven expansion units; see ExpansionCatalog for how a unit file
## is assembled into the catalog, and expansion_defs.gd for the MOUNT_* values.
extends RefCounted

const ID := "sega_cd"

# Model 1 and Model 2 both sat UNDER the Mega Drive, which is why the console
# ends up in the middle of the tower rather than at the bottom of it.
const ROW := {
	"label": "Sega CD",
	"host": "genesis",
	"media": "segacd",
	"mount": ExpansionDefs.MOUNT_BELOW,
	"size": Vector3(0.32, 0.08, 0.28),
	"loader": MediaDimensions.LOADER_TRAY,
	# The 8 KB of backup RAM inside the unit, which every Sega CD game saves to.
	"memory": "sega_cd_memory",
	# Switched on with no disc, a Sega CD runs its BIOS: the CD player and the
	# backup memory manager. genesis_plus_gx takes the BIOS file itself as the
	# content for that. Any one region serves, so the one installed is the one
	# handed over.
	"firmware": ["bios_CD_U.bin", "bios_CD_E.bin", "bios_CD_J.bin"],
	"rom_from_firmware": true,
	"firmware_first_present": true,
}


const BOOT := {
	# A loaded disc boots; with none, a cartridge in the Mega Drive; with neither,
	# the Sega CD's own BIOS. The first form never falls back, which is what lets
	# the console's cartridge come before the BIOS.
	"genesis|sega_cd": {
		"core": "genesis_plus_gx",
		"roms": ["expansion_media:sega_cd", "host", "expansion:sega_cd"],
	},
}
