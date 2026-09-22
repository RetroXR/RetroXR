## Slot2Catalog — a console's SECOND native cartridge slot, and how the pair boots.
##
## The Nintendo DS has two slots moulded into the shell: Slot-1 on the back edge
## for a DS Game Card and Slot-2 on the front edge for a Game Boy Advance
## cartridge, which a DS game may read (the Pokémon dual-slot transfer, Mega Man
## ZX, Portrait of Ruin, the Boktai solar sensor). There is no box to bolt on,
## so it is not an expansion unit — but the launch is the same shape as one, a
## `roms` list and a `subsystem` pairing, so ExpansionLaunch reads it as one.
##
## VERIFIED against JesseTG/melonds-ds, src/libretro/info.cpp:
##
##   slot_1_2_roms[] = { {"Nintendo DS (Slot 1)", "nds",     need_fullpath=false, required=true},
##                       {"GBA (Slot 2)",         "gba",     need_fullpath=false, required=true},
##                       {"GBA Save Data",        "srm|sav", need_fullpath=true,  required=false} }
##   subsystems[]    = { {"Slot 1 & 2 Boot",                    "gba",      3 roms},
##                       {"Slot 1 & 2 Boot (No GBA Save Data)", "gbanosav", 2 roms} }
##
## and core/core.cpp assigns game[0] to the DS card, game[1] to the GBA ROM
## (asserting its data was read into memory, which the bridge does for every
## need_fullpath=false entry) and game[2] to the GBA save PATH.
##
## The GBA save never goes through retro_get_memory_data: the core reads that
## path itself (LoadGbaSram) and writes it back itself (FlushGbaSram, on a timer
## and at unload). Two consequences decide the row below. LoadGbaSram THROWS on
## a path that does not exist — "Failed to open GBA save file" and the load
## fails — and tolerates an empty file, so the launch creates one before the
## call (see ExpansionLaunch's slot2_save token). And `gbanosav` never writes a
## save at all, so it is not a fallback: a player's progress would be lost every
## time the machine was switched off.
##
## The core is pinned because DeSmuME publishes no such subsystem. The recipe
## exists only while a GBA cartridge is seated, so an empty Slot-2 leaves the
## player's own core choice alone.
##
## Netplay starts every machine through the single-ROM path, so a DS with a GBA
## cartridge in it boots its DS card alone in a session. Not extended here.
class_name Slot2Catalog
extends RefCounted

const ROWS: Dictionary = {
	"nds": {
		"media": "gba",
		"core": "melondsds",
		"roms": ["host"],
		"subsystem": {"ident": "gba", "roms": ["host", "slot2", "slot2_save"]},
	},
}


## The systemid of the media a console's second slot takes, or "" for every
## console that has one slot.
static func media_of(host: String) -> String:
	return str((ROWS.get(host, {}) as Dictionary).get("media", ""))


## The launch recipe for a console with its second slot FILLED, or {}.
static func boot_for(host: String) -> Dictionary:
	var row: Dictionary = ROWS.get(host, {})
	if row.is_empty():
		return {}
	var out := row.duplicate(true)
	out.erase("media")
	return out


## The save-type strings a GBA cartridge carries in its ROM (Nintendo's SDK links
## them in with the save library), longest first so FLASH1M_V is not read as
## FLASH_V, and the bytes of save memory each one means.
const _GBA_SAVE_TYPES: Array = [
	["FLASH1M_V", 131072],
	["FLASH512_V", 65536],
	["FLASH_V", 65536],
	["SRAM_F_V", 32768],
	["SRAM_V", 32768],
	["EEPROM_V", 8192],
]
## A cartridge that names none of them has no save to keep; the core still needs
## a file, and battery SRAM is the size that asks nothing of the game.
const _GBA_SAVE_FALLBACK := 32768


## A blank GBA save for the cartridge at `rom_path`: erased (0xFF) memory of the
## size its own save-type string declares.
##
## MEASURED 2026-09-21 on melondsds: the core refuses an EMPTY save file ("Failed
## to open GBA save file", the load fails) exactly as it refuses a missing one --
## it sizes the cartridge's save memory from the file's length. The first run of
## every GBA cartridge in a DS used to die on that. EEPROM is either 512 bytes or
## 8 KB and the ROM cannot say which; 8 KB is the one the Classic NES Series (and
## most EEPROM games of any size) use.
static func blank_gba_save(rom_path: String) -> PackedByteArray:
	var size := _GBA_SAVE_FALLBACK
	var rom := FileAccess.get_file_as_bytes(rom_path)
	if not rom.is_empty():
		for row: Array in _GBA_SAVE_TYPES:
			if _contains(rom, str(row[0]).to_ascii_buffer()):
				size = int(row[1])
				break
	var out := PackedByteArray()
	out.resize(size)
	out.fill(0xFF)
	return out


static func _contains(hay: PackedByteArray, needle: PackedByteArray) -> bool:
	var first := needle[0]
	var at := hay.find(first)
	while at >= 0 and at + needle.size() <= hay.size():
		if hay.slice(at, at + needle.size()) == needle:
			return true
		at = hay.find(first, at + 1)
	return false
