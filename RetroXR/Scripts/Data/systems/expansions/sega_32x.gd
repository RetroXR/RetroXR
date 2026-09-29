## 32X — the mushroom in the cartridge slot, and the Tower of Power.
##
## One of the eleven expansion units; see ExpansionCatalog for how a unit file
## is assembled into the catalog, and expansion_defs.gd for the MOUNT_* values.
extends RefCounted

const ID := "sega_32x"

# Into the cartridge slot, on top, with its own cartridge slot on top of that.
# The only expansion here that a game cartridge goes INTO rather than past.
#
# The shell is the laser-scanned unit, debranded (see the LICENSE beside it and
# Tools/glb/prepare_sega32x.py): real size, facing +Z, y = 0 on the plane it rests
# on, with the plug that goes into the Mega Drive hanging 35.7 mm below that. It
# wears Sega's Model 2 spacer under it -- on a Model 2 the plug bottoms out with
# the unit standing ~22 mm clear of the console, and the spacer fills that gap.
# `size` is its true bounds, plug included, so the per-axis fit is 1:1 and the
# scan is never stretched; the box it replaces is centred on those bounds. Its
# CartFloor marker places the unit's own cartridge well, and its Flap_Front /
# Flap_Back swing open while a cartridge is in (RetroExpansion).
const ROW := {
	"label": "32X",
	"host": "genesis",
	"media": "sega32x",
	"mount": ExpansionDefs.MOUNT_CARTRIDGE,
	"size": Vector3(0.20781, 0.09906, 0.11225),
	"loader": MediaDimensions.LOADER_NONE,
	"shell": SHELL,
	# The plug seats the way a cartridge does: the bottom edge of its board goes
	# where a cartridge's bottom edge goes, so this is the middle of a Genesis
	# cartridge (70 mm tall) standing on the shell's PlugSeat marker -- (0, -34.6,
	# +11.1) mm in the GLB, (0, -48.5, +11.1) mm once centred on the bounds.
	"connector": Vector3(0.0, -0.0135, 0.0111),
}

const SHELL := "res://imported-assets/consoles/sega_32x/sega32x.glb"


const BOOT := {
	# UNVERIFIED. A 32X cartridge is the game and picodrive is the core that is
	# both halves at once.
	"genesis|sega_32x": {
		"core": "picodrive",
		"roms": ["expansion:sega_32x"],
	},
	# UNVERIFIED. The full tower, where the disc is still what boots. The disc
	# alone: the plain form would fall back to genesis_plus_gx's BIOS file.
	"genesis|sega_cd|sega_32x": {
		"core": "picodrive",
		"roms": ["expansion_media:sega_cd"],
	},
}
