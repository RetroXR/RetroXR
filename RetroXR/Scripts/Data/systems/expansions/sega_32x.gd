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
# on, with the plug that goes into the Mega Drive hanging 35.7 mm below that. On a
# Model 2 the plug bottoms out with the unit standing ~13 mm clear of the console;
# Sega's Model 2 spacer fills that gap, and here it is its own accessory
# (Sega32xSpacer, spawned from this card) that clips into the unit's
# AccessoryMount and rides it into the slot.
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
	# cartridge standing on the shell's PlugSeat marker (PLUG_EDGE_Y). Derived
	# from that cartridge's own height, because the console seats a cartridge by
	# its MIDDLE: a fixed number here sinks the unit, and its spacer, into the
	# console whenever the Genesis cartridge's row changes.
	"connector": Vector3(0.0, PLUG_EDGE_Y + MediaDimensions.CART_SIZES["genesis"].y * 0.5, 0.0111),
	# Sega32xSpacer.GROUP. Its model shares the shell's frame, so the mount at the
	# shell's origin seats it exactly under the unit.
	"accessory_group": "sega32x_spacer",
}

const SHELL := "res://imported-assets/consoles/sega_32x/sega32x.glb"

## The plug board's bottom edge -- the shell's PlugSeat marker -- in the unit
## frame: (0, -34.6, +11.1) mm in the GLB, (0, -48.5, +11.1) mm once centred on
## the bounds.
const PLUG_EDGE_Y := -0.0485


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
