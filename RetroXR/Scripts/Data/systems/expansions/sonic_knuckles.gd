## Sonic & Knuckles — the lock-on cartridge, with a Genesis slot under its lid.
##
## One of the expansion units; see ExpansionCatalog for how a unit file is
## assembled into the catalog, and expansion_defs.gd for the MOUNT_* values.
extends RefCounted

const ID := "sonic_knuckles"

# A Genesis cartridge that goes into the console's slot and carries a slot of its
# own under a hinged lid on top: Sega's "Lock-On Technology". Seat Sonic 3 in it
# and the console plays Sonic 3 & Knuckles, Sonic 2 makes Knuckles in Sonic 2,
# and anything else the S&K program does not recognise gives Blue Sphere.
#
# genesis_plus_gx does all of it already (core/cart_hw/md_cart.c, TYPE_SK): the
# core is handed the TOP cartridge as its content, and with the option
# genesis_plus_gx_lock_on = "sonic & knuckles" (ForcedCoreOptions.sonic_knuckles
# _lock_on, read at load) it maps system/sk.bin over $000000 and the Sonic 2
# "UPMEM" chip, system/sk2chip.bin, at $300000.
#
# BOTH files are needed, and `firmware_all` says so. The core reads sk2chip.bin
# inside the sk.bin branch and only locks on when that ALSO loads -- without it
# the console silently plays the top cartridge alone, Sonic 3 with no Knuckles,
# for every game and not only Sonic 2. Refusing at power-on naming the missing
# file is better than a machine that quietly does less than it says.
#
# The adapter's own program is the firmware (the Super Game Boy's arrangement,
# `rom_from_firmware`): spawned from the Genesis card, and with its slot empty it
# boots sk.bin on its own, which is plain Sonic & Knuckles -- as the real one does.
#
# `size` is an ESTIMATE: no measured dimensions were found. The real cartridge
# is a Genesis cartridge's width or a little more, noticeably taller, and thick
# enough to hold a cartridge standing in its roof; one retail listing gives
# 130 x 115 x 28 mm, which may be the packaging. No hinged lid is modelled yet.
const ROW := {
	"label": "Sonic & Knuckles",
	"host": "genesis",
	"media": "genesis",
	"mount": ExpansionDefs.MOUNT_CARTRIDGE,
	"size": Vector3(0.115, 0.105, 0.028),
	"loader": MediaDimensions.LOADER_NONE,
	"firmware": ["sk.bin", "sk2chip.bin"],
	"firmware_all": true,
	"rom_from_firmware": true,
	"label_front": true,
}


const BOOT := {
	# VERIFIED against our genesis_plus_gx fork (md_cart.c TYPE_SK): the content
	# is the cartridge in the TOP slot, and the S&K half comes from the system
	# directory. The plain token is bay-then-rom, so an empty slot boots the
	# adapter's own sk.bin, and the lock-on option is pinned off for that run
	# (S&K locked onto itself would map the same ROM twice).
	#
	# The core is pinned: picodrive has no lock-on at all.
	"genesis|sonic_knuckles": {
		"core": "genesis_plus_gx",
		"roms": ["expansion:sonic_knuckles"],
	},
}
