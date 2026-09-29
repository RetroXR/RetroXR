## GbaCartShell — which moulded shell a Game Boy Advance cartridge spawns with.
##
## Read from the ROM header, 0xC0 bytes, never by hashing the file. The
## third-generation Pokemon games shipped in dyed translucent plastic, in every
## market; everything else is the standard grey, the model's own plastic:
##   - Ruby (game code AXV_): clear red.
##   - Sapphire (AXP_): clear blue.
##   - Emerald (BPE_): clear green.
##   - FireRed (BPR_): clear orange-red.
##   - LeafGreen (BPG_): clear leaf green.
## The first three letters of the game code at 0xAC name the game; the fourth is
## its language, so every market matches.
##
## The Classic NES Series (and Europe's NES Classics) came in NES grey: every
## one has a game code beginning "F" (FZLE, FSME, FADP...), whoever made the
## original game. Japan's Famicom Mini carts share the "F" but end in "J", and
## keep the standard grey.
##
## Only a Nintendo-published ROM (maker code "01" at 0xB0) matches either. The
## colours, and how clear each shell is, are in Resources/gba_cartridge_shells.tres.
class_name GbaCartShell
extends RefCounted

const BODY := "res://imported-assets/carts/game_boy_advance/gba_cart.glb"
const SYSTEMID := "gba"
const DEFAULT_PRESET := &"grey"

const HEADER_BYTES := 0xC0
const TITLE_AT := 0xA0
const TITLE_BYTES := 12
const GAME_CODE_AT := 0xAC
const GAME_CODE_BYTES := 4
const MAKER_CODE_AT := 0xB0
const MAKER_NINTENDO := "01"

## Game code without its language letter -> preset.
const GAME_SHELLS := {
	"AXV": &"ruby",
	"AXP": &"sapphire",
	"BPE": &"emerald",
	"BPR": &"fire_red",
	"BPG": &"leaf_green",
}

## The NES reissues: game code "F" + two letters + market. Famicom Mini is "J".
const NES_SERIES_PREFIX := "F"
const NES_SERIES_PRESET := &"nes_grey"
const MARKET_JAPAN := "J"


static func preset_for_rom(rom_path: String) -> StringName:
	return preset_for_header(read_header(rom_path))


static func preset_for_header(header: PackedByteArray) -> StringName:
	if not is_nintendo(header):
		return DEFAULT_PRESET
	var code := game_code(header)
	if GAME_SHELLS.has(code.left(3)):
		return GAME_SHELLS[code.left(3)]
	if code.length() == GAME_CODE_BYTES and code.begins_with(NES_SERIES_PREFIX) \
			and code.right(1) != MARKET_JAPAN:
		return NES_SERIES_PRESET
	return DEFAULT_PRESET


## The four-letter game code, e.g. "AXVE" for the American Ruby.
static func game_code(header: PackedByteArray) -> String:
	return _ascii(header, GAME_CODE_AT, GAME_CODE_BYTES)


static func is_nintendo(header: PackedByteArray) -> bool:
	return header.size() >= HEADER_BYTES and _ascii(header, MAKER_CODE_AT, 2) == MAKER_NINTENDO


static func read_header(rom_path: String) -> PackedByteArray:
	if rom_path.is_empty():
		return PackedByteArray()
	var f := FileAccess.open(rom_path, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	var bytes := f.get_buffer(HEADER_BYTES)
	f.close()
	return bytes


## `count` bytes from `at`, up to the first NUL.
static func _ascii(header: PackedByteArray, at: int, count: int) -> String:
	if header.size() < at + count:
		return ""
	var out := ""
	for i in count:
		var b := header[at + i]
		if b == 0:
			break
		out += char(b)
	return out
