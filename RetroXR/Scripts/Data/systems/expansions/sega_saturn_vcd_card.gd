## Video CD Card — the Saturn's MPEG decoder (Sega's Movie Card HSS-0119, and the
## Video CD Cards Sega, Victor and Hitachi sold in Japan and Europe), in a slot of
## its own in the back of the console.
##
## One of the expansion units; see ExpansionCatalog for how a unit file is
## assembled into the catalog, and expansion_defs.gd for the MOUNT_* values.
extends RefCounted

const ID := "sega_saturn_vcd_card"

# NOT a cartridge. It plugs into the Saturn "through the door the battery is
# accessed from" (Sega Retro), a PCMCIA-like slot in the back near the battery
# (MAME's forum) -- the dedicated MPEG connector Beetle Saturn's mpeg.h describes,
# off the cartridge's A-bus -- so it has a socket of its own ("mpeg_card") and
# stays in while a cartridge goes in and out of the slot behind the lid.
#
# It slides in flat: the console turns the socket so the card's +Y runs into the
# back panel and its face looks up. `size` is width x depth in x thickness, an
# ESTIMATE (no dimensions were found); the 12 mm it stands out of the panel is a
# handle, where the real card goes in behind its door.
#
# What seating it does is ForcedCoreOptions.saturn_mpeg_card. `firmware` is the
# card's ROM, mpeg_card.bin in Beetle's system directory: without it the core's
# card answers but never authenticates (mpeg.c, MPEG_Auth), so it is not offered.
const ROW := {
	"label": "Video CD Card",
	"host": "saturn",
	"mount": ExpansionDefs.MOUNT_ABOVE,
	"socket": "mpeg_card",
	"size": Vector3(0.100, 0.070, 0.012),
	"loader": MediaDimensions.LOADER_NONE,
	"firmware": ["mpeg_card.bin"],
}


const BOOT := {
	# VERIFIED at source (beetle-saturn-libretro, mednafen/ss/mpeg.c and cdb.c,
	# upstream since 2026-08-06): Beetle is the only Saturn core here with the card.
	# YabaSanshiro has no MPEG decoder, so a Quest with the card in runs Beetle.
	# No `roms`: the disc in the console boots, as it does with every cartridge.
	"saturn|sega_saturn_vcd_card": {
		"core": "mednafen_saturn",
	},
	# The card stays in while a cartridge comes and goes, and a stack names its
	# recipe by every unit that names one -- so each ROM cartridge needs its pair
	# with the card spelled out, or seating both would fall back to the player's
	# core and lose the cartridge.
	"saturn|sega_saturn_kof95_rom|sega_saturn_vcd_card": {
		"core": "mednafen_saturn",
	},
	"saturn|sega_saturn_ultraman_rom|sega_saturn_vcd_card": {
		"core": "mednafen_saturn",
	},
}
