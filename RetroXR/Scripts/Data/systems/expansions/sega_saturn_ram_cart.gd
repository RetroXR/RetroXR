## Backup RAM Cartridge — more room for Sega Saturn saves, in the cartridge slot
## behind the disc lid.
##
## One of the expansion units; see ExpansionCatalog for how a unit file is
## assembled into the catalog, and expansion_defs.gd for the MOUNT_* values.
extends RefCounted

const ID := "sega_saturn_ram_cart"

## The shell every cartridge for the slot behind the lid shares: Sega's Extended
## RAM Cartridges "look virtually the same" as this one (Sega Retro, HSS-0150),
## and the slot is one slot. Named here so the other four rows take it rather
## than a copy. An estimate, not a measurement.
const SIZE := Vector3(0.113, 0.080, 0.014)

# Memory only: no BOOT key, so the disc still boots with it seated, and no media.
# MOUNT_ABOVE rather than MOUNT_CARTRIDGE because a Saturn's CartridgeSlot is its
# disc well: this grows the console a socket of its own, which the placeholder
# box moves into a slot behind the lid.
const ROW := {
	"label": "Backup RAM Cartridge",
	"host": "saturn",
	"mount": ExpansionDefs.MOUNT_ABOVE,
	"size": SIZE,
	"loader": MediaDimensions.LOADER_NONE,
	"memory": "sega_saturn_ram_cart",
	# Half of it is inside the slot, and a name at the foot of the face with it.
	"label_top": true,
}


const BOOT := {}
