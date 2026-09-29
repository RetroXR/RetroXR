## GbcCartShell — the clear cartridge the Game Boy Color-only games came in.
##
## Read from the ROM header, 0x150 bytes, never by hashing the file. A game that
## runs only on a Game Boy Color (CGB flag 0xC0 at 0x143) came in the clear
## CGB-002 shell rather than the Game Boy's: smoke, except Pokemon Crystal (title
## PM_CRYSTAL, Nintendo, every market), which is clear blue with glitter. A game
## that also runs on the original Game Boy (0x80) came in the Game Boy's shape in
## black, and every other one in grey: those are GbCartShell's.
##
## Two boards show through the shell. A game that saves (a battery in the
## cartridge type at 0x147) gets the large DMG-KGDU-10 board with its coin cell,
## the one Crystal's cartridge has; the rest the small DMG-A09-10, the MBC5-only
## board. Real saving boards vary (only the MBC3 ones carry a clock crystal),
## so this is the nearer of the two, not the game's own board.
##
## The player can force either body (RetroCartridge.body_region), and a forced
## preset brings the body whose palette holds it: a Crystal shell makes any ROM
## a Game Boy Color cartridge, a Game Boy one a Game Boy cartridge. The colours
## are in Resources/gbc_cartridge_shells.tres.
class_name GbcCartShell
extends RefCounted

const BODY_LARGE := "res://imported-assets/carts/game_boy_color/gbc_cart_large.glb"
const BODY_SMALL := "res://imported-assets/carts/game_boy_color/gbc_cart_small.glb"
## This body's palette id in CartridgeColor; the Game Boy body's is GbCartShell.SYSTEMID.
const PALETTE := "gbc"
const DEFAULT_PRESET := &"smoke"
## RetroCartridge.body_region for a Game Boy or Game Boy Color ROM: the Game Boy's
## shape or this one. Empty is the ROM's own.
const BODY_GB := "gb"
const BODY_GBC := "gbc"

const CGB_ONLY := 0xC0
const CART_TYPE_AT := 0x147
## Cartridge types with a battery-backed save (Pan Docs, "0147 - Cartridge Type").
const BATTERY_TYPES: Array[int] = [0x03, 0x06, 0x09, 0x0D, 0x0F, 0x10, 0x13, 0x1B, 0x1E, 0x22, 0xFF]
## Title prefix -> preset, Nintendo only, every market.
const TITLE_SHELLS := {
	"PM_CRYSTAL": &"crystal",
}


## Whether `path` is one of this shell's bodies.
static func is_body(path: String) -> bool:
	return path == BODY_LARGE or path == BODY_SMALL


static func is_cgb_only(header: PackedByteArray) -> bool:
	return header.size() >= GbCartShell.HEADER_BYTES and header[GbCartShell.CGB_AT] == CGB_ONLY


static func has_battery(header: PackedByteArray) -> bool:
	return header.size() >= GbCartShell.HEADER_BYTES and BATTERY_TYPES.has(header[CART_TYPE_AT])


## This shell on the board the header's cartridge type suggests.
static func board_body(header: PackedByteArray) -> String:
	return BODY_LARGE if has_battery(header) else BODY_SMALL


## The model a Game Boy or Game Boy Color cartridge spawns as: one of this shell's
## bodies, or GbCartShell.BODY. A forced body wins, then the body of a forced
## preset's palette, then the header: GBC-only, unless GbCartShell gives the title a
## shell of its own (the Korean Gold and Silver are GBC-only and stay gold and
## silver).
static func body_model_for(body_region: String, shell_preset: StringName, header: PackedByteArray) -> String:
	var clear := is_cgb_only(header) and GbCartShell.preset_for_header(header) == GbCartShell.DEFAULT_PRESET
	if body_region == BODY_GBC:
		clear = true
	elif body_region == BODY_GB:
		clear = false
	elif _palette_holds(PALETTE, shell_preset):
		clear = true
	elif _palette_holds(GbCartShell.SYSTEMID, shell_preset):
		clear = false
	return board_body(header) if clear else GbCartShell.BODY


static func body_model_for_rom(body_region: String, shell_preset: StringName, rom_path: String) -> String:
	return body_model_for(body_region, shell_preset, GbCartShell.read_header(rom_path))


static func preset_for_rom(rom_path: String) -> StringName:
	return preset_for_header(GbCartShell.read_header(rom_path))


static func preset_for_header(header: PackedByteArray) -> StringName:
	if GbCartShell.is_nintendo(header):
		var title := GbCartShell.header_title(header)
		for prefix: String in TITLE_SHELLS:
			if title.begins_with(prefix):
				return TITLE_SHELLS[prefix]
	return DEFAULT_PRESET


static func _palette_holds(palette_id: String, preset: StringName) -> bool:
	if preset == &"":
		return false
	var palette := CartridgeColor.get_palette(palette_id)
	return palette != null and palette.find(preset) != null
