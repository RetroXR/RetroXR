## Backup RAM Cartridge — more room for Sega CD saves, in the Mega Drive's own
## cartridge slot while the Sega CD underneath plays the disc.
##
## One of the expansion units; see ExpansionCatalog for how a unit file is
## assembled into the catalog, and expansion_defs.gd for the MOUNT_* values.
extends RefCounted

const ID := "sega_cd_ram_cart"

# A cartridge that runs nothing: it is memory, so no BOOT key names it and a Mega
# Drive standing on a Sega CD still boots the disc with it seated. Filed on the
# Sega CD's card, where a player looking for more save room is standing, and
# sized as a Mega Drive cartridge.
const ROW := {
	"label": "Backup RAM Cartridge",
	"host": "mega_drive",
	"mount": ExpansionDefs.MOUNT_CARTRIDGE,
	"size": Vector3(0.110, 0.070, 0.017),
	"loader": MediaDimensions.LOADER_NONE,
	"card": "sega_cd",
	"memory": "sega_cd_ram_cart",
}


const BOOT := {}
