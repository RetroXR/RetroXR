## GbCartShell — which moulded shell a Game Boy cartridge spawns with.
##
## Read from the ROM header, 0x150 bytes, never by hashing the file:
##   - Pokemon Gold and Silver: gold and silver, in every market.
##   - Pokemon Red, Blue and Yellow: red, blue and yellow outside Japan. The
##     Japanese Red, Blue and Pikachu came in the standard grey; the destination
##     byte tells them apart. Pocket Monsters Green, which only Japan had, was
##     grey too.
##   - Any other game that also runs in colour on a Game Boy Color (CGB flag
##     0x80): black.
##   - Everything else, GBC-only games (0xC0) included: grey.
## Only Nintendo-published ROMs match a Pokemon title. The colours are in
## Resources/gb_cartridge_shells.tres.
class_name GbCartShell
extends RefCounted

const BODY := "res://imported-assets/carts/game_boy/gb_cart.glb"
## The palette's systemid. A Game Boy Color cartridge is the same shell and
## takes the same palette; is_shell() is the check for "spawns as this model".
const SYSTEMID := "gb"
const SYSTEMIDS: Array[String] = ["gb", "gbc"]
const DEFAULT_PRESET := &"grey"
const BLACK_PRESET := &"black"

const HEADER_BYTES := 0x150
const TITLE_AT := 0x134
const TITLE_BYTES := 15
const CGB_AT := 0x143
const NEW_LICENSEE_AT := 0x144
const DESTINATION_AT := 0x14A
const OLD_LICENSEE_AT := 0x14B
const CGB_DUAL := 0x80
const DESTINATION_JAPAN := 0x00
const OLD_LICENSEE_NINTENDO := 0x01
const OLD_LICENSEE_USE_NEW := 0x33

## Title prefix -> preset, in every market.
const TITLE_SHELLS := {
	"POKEMON_GLD": &"gold",
	"POKEMON_SLV": &"silver",
}
## Title prefix -> preset, outside Japan only.
const OVERSEAS_TITLE_SHELLS := {
	"POKEMON RED": &"red",
	"POKEMON BLUE": &"blue",
	"POKEMON YEL": &"yellow",
}


## Whether a cartridge of this systemid spawns as the Game Boy shell.
static func is_shell(systemid: String) -> bool:
	return SYSTEMIDS.has(systemid)


static func preset_for_rom(rom_path: String) -> StringName:
	return preset_for_header(read_header(rom_path))


static func preset_for_header(header: PackedByteArray) -> StringName:
	if header.size() < HEADER_BYTES:
		return DEFAULT_PRESET
	var title := header_title(header)
	if is_nintendo(header):
		for prefix: String in TITLE_SHELLS:
			if title.begins_with(prefix):
				return TITLE_SHELLS[prefix]
		if header[DESTINATION_AT] != DESTINATION_JAPAN:
			for prefix: String in OVERSEAS_TITLE_SHELLS:
				if title.begins_with(prefix):
					return OVERSEAS_TITLE_SHELLS[prefix]
	if header[CGB_AT] == CGB_DUAL:
		return BLACK_PRESET
	return DEFAULT_PRESET


## The title field up to its first NUL; the flag byte after it is never included.
static func header_title(header: PackedByteArray) -> String:
	if header.size() < TITLE_AT + TITLE_BYTES:
		return ""
	var out := ""
	for i in TITLE_BYTES:
		var b := header[TITLE_AT + i]
		if b == 0:
			break
		out += char(b)
	return out


static func is_nintendo(header: PackedByteArray) -> bool:
	if header.size() < HEADER_BYTES:
		return false
	var old := header[OLD_LICENSEE_AT]
	if old == OLD_LICENSEE_NINTENDO:
		return true
	return old == OLD_LICENSEE_USE_NEW and header[NEW_LICENSEE_AT] == 0x30 \
		and header[NEW_LICENSEE_AT + 1] == 0x31


static func read_header(rom_path: String) -> PackedByteArray:
	if rom_path.is_empty():
		return PackedByteArray()
	var f := FileAccess.open(rom_path, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	var bytes := f.get_buffer(HEADER_BYTES)
	f.close()
	return bytes
