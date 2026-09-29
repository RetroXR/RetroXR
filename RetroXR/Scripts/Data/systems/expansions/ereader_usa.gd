## e-Reader (USA, PSAE) — the 8 MB US reader, with the link port.
##
## The only reader that will read the 1489 US strips in the library: cards are
## region-locked and a Japanese reader answers one with its own Region Error
## screen. It is the same hardware as the Card e-Reader+, which is why both need
## the + calibration blob the fork seeds by game code.
##
## See ereader.gd for the shape of the row and why the revisions are separate.
extends RefCounted

const ID := "ereader_usa"

# The shell and where its tongue and card channel are: see ereader.gd.
const _READER := preload("res://Scripts/Data/systems/expansions/ereader.gd")

# Its media is `ereader`, not its own id, so has_own_card is false and this unit
# is offered from the e-Reader card rather than from a tile of its own. Three
# tiles for one shelf of cards would be three empty libraries.
const ROW := {
	"label": "e-Reader (USA)",
	"host": "gba",
	"media": "ereader",
	"mount": ExpansionDefs.MOUNT_CARTRIDGE,
	# See ereader.gd: the battery is in the reader, and each revision keeps its
	# own flash -- they are different hardware and their cards are region-locked.
	"save_owner": ExpansionDefs.SAVE_OWNER_UNIT,
	"size": _READER.SIZE,
	"shell": _READER.SHELL,
	"shell_lods": _READER.SHELL_LODS,
	"connector": _READER.CONNECTOR,
	"seat_yaw": _READER.SEAT_YAW,
	"swipe_slit": _READER.SWIPE_SLIT,
	"loader": MediaDimensions.LOADER_SWIPE,
	# See ereader.gd: the header code is what a library dump is recognised by.
	"rom_code": "PSAE",
}


const BOOT := {
	"gba|ereader_usa": {
		"core": "mgba",
		"roms": ["expansion:ereader_usa"],
	},
}
