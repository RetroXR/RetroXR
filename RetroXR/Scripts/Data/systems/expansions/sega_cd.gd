## Sega CD — the disc drive the Mega Drive stands on.
##
## One of the eleven expansion units; see ExpansionCatalog for how a unit file
## is assembled into the catalog, and expansion_defs.gd for the MOUNT_* values.
extends RefCounted

const ID := "sega_cd"

# The Model 2 (MK-4102, 1993), the top-loader: a long low base whose platform the
# Genesis stands on, and on its right the drive's housing, its lid hinged at the back.
# The console is slid on from the left until its expansion edge (the slot in its RIGHT
# side, behind the panel that comes off) is in the receptacle on the drive's left wall
# (Sega's manual, "Slide the Genesis sideways, from left to right"). So the console
# stands BESIDE the drive, not square on top of the unit: `seat` is that wall at the
# platform's level and the console's foot is its right side (RetroSystemModel.
# expansion_foot), which is what lets a Genesis Model 2 (220 wide) and a Model 1 (280)
# both seat against it. A Model 1 overhangs the platform's left end; Sega packed an
# extension spacer that clips on there for it (SegaCd2Spacer, on this unit's card).
#
# Worn as a primitive stand-in (SegaCd2Primitive) built from RetroXR-models'
# sega/sega-cd/console-2 (Sega's design patent at the published depth), in that model's
# frame and with its markers' names, so the model can replace it as this shell.
# 396 x 84.3 x 220 mm: Sega's published width, chosen over the patent drawing's 381
# (2026-11-08), every x read off the patent stretched by 396 / 381 as the model's are.
#
# The Model 1 (MK-4100, the front-loading drawer the console stands right on top of)
# is not built yet: this unit was a box with a drawer until 2026-11-08.
const ROW := {
	"label": "Sega CD",
	"host": "genesis",
	"media": "segacd",
	"mount": ExpansionDefs.MOUNT_BELOW,
	# The shell's true bounds, so the per-axis fit is 1:1: the base's 220 deep plus the
	# AC ADAPTOR mouth drawn 0.6 proud of its back.
	"size": Vector3(0.396, 0.0843, 0.2206),
	"shell": SHELL,
	"loader": MediaDimensions.LOADER_TRAY,
	"lid": true,
	# The lid opens about 85 degrees about its rear edge (photographs: 80 to 90).
	"lid_open_deg": -85.0,
	# The drive's left wall at x 23.39 mm (the patent's 22.5 x 396 / 381), on the
	# platform's deck (43 mm): a Model 2's origin lands at x -86.61 and a Model 1's at
	# -116.61, the models' own ConsoleSeats.
	# (A Model 2's feet sit in the rails 2 mm lower on the real unit; the stand-in's
	# rails are drawn, not cut, so it stands on the deck.)
	"seat": Vector3(0.0225 * SX, 0.043, 0.0),
	# The base the whole length, the drive above it on the right back to where its front
	# falls to the nose (z 90), and the nose's foot under the OPEN knob and the ACCESS
	# lamp: a box over the whole nose stood in front of the knob, and every beam aimed
	# at it took the drive instead.
	"boxes": [
		AABB(Vector3(-0.198, 0.0, -0.110), Vector3(0.396, 0.045, 0.220)),
		AABB(Vector3(0.0225 * SX, 0.045, -0.106), Vector3(0.164 * SX, 0.0378, 0.196)),
		AABB(Vector3(0.0225 * SX, 0.045, 0.090), Vector3(0.164 * SX, 0.006, 0.016)),
	],
	# The OPEN plate lies in the drive's gray nose and presses square into it, 2 mm: the
	# nose's inward normal (it falls 22 mm over 16 from z 90 to the front edge, 54
	# degrees; SegaCd2Primitive.NOSE_TOP / NOSE_FOOT).
	"eject_axis": Vector3(0.0, -0.58817, -0.80874),
	"eject_travel": 0.002,
	# The Model 1 Genesis's extension spacer (SegaCd2Spacer.GROUP).
	"accessory_group": "sega_cd2_spacer",
	# Its mount at the spacer bar's middle (x -224.3, 24 up), where its body is: at the
	# shell's origin, 22 cm from the bar, the zone never had the bar in its sphere.
	"accessory_at": Vector3(-0.2243, 0.024, 0.0),
	# The ACCESS lamp (the shell's AccessLed) is genesis_plus_gx's LED 1: the sub-CPU's
	# LEDR bit in its LED register at $FF8000, which the BIOS drives (lit while a disc
	# plays or is read, flashing with no disc or the door open). Its LED 0 is the Z80.
	"access_led": 1,
	# LINE OUT LEFT / RIGHT and MIXING on the back (ExpansionAudio).
	"line_out": true,
	"mixing": true,
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

const SHELL := "res://Scenes/Objects/expansions/sega_cd2_primitive.tscn"
## The patent's x to Sega's published width (SegaCd2Primitive.SX).
const SX := 396.0 / 381.0


const BOOT := {
	# A loaded disc boots; with none, a cartridge in the Mega Drive; with neither,
	# the Sega CD's own BIOS. The first form never falls back, which is what lets
	# the console's cartridge come before the BIOS.
	"genesis|sega_cd": {
		"core": "genesis_plus_gx",
		"roms": ["expansion_media:sega_cd", "host", "expansion:sega_cd"],
	},
}
