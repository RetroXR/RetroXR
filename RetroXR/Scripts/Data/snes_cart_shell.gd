## SnesCartShell — which body and moulded shell a Super NES cartridge spawns with.
##
## The two bodies are the North American (NTSC-U) shell, alike but for the front
## latch: Type A, the deep locking notch (Super Mario World's), and Type B, the
## sloped recess (Bubsy II's) that replaced it partway through 1993. Games printed
## after the change, reprints of older ones included, came in Type B.
##
## Auto (RetroCartridge.body_region empty) gives a North American ROM the body of
## its first print by release date: Type B from TYPE_B_FROM on, else Type A, which
## is also the answer when no date is known. A ROM from any other market keeps the
## procedural box: the Super Famicom and PAL cartridges are a different shape. The
## player can force either body on any ROM at spawn.
##
## The market is the scraper's region for the ROM, else the destination byte of
## the internal header. The shell colour is read from that header's title, never
## by hashing the file: Killer Instinct shipped in black plastic, everything else
## in the standard grey, the model's own. The colours are in
## Resources/snes_cartridge_shells.tres.
class_name SnesCartShell
extends RefCounted

const SYSTEMID := "snes"
const BODY_TYPE_A := "res://imported-assets/carts/snes/snes_cart_type_a.glb"
const BODY_TYPE_B := "res://imported-assets/carts/snes/snes_cart_type_b.glb"
## RetroCartridge.body_region values the player can force. Empty is Auto.
const TYPE_A := "type_a"
const TYPE_B := "type_b"
const DEFAULT_PRESET := &"grey"

## First release date, YYYYMMDD, from which Auto picks Type B. Collectors date the
## sloped front to "some point in 1993"; a 1993 game's first print could be
## either, so Auto keeps the whole of 1993 on Type A.
const TYPE_B_FROM := "19940101"

## Where the internal header sits: LoROM, then HiROM.
const HEADER_AT: Array[int] = [0x7FC0, 0xFFC0]
const HEADER_BYTES := 0x20
const TITLE_BYTES := 21
const DESTINATION_AT := 0x19
const CHECKSUM_COMPLEMENT_AT := 0x1C
const CHECKSUM_AT := 0x1E
## A dump from a copier carries 512 bytes of its own in front of the ROM.
const COPIER_BYTES := 0x200
const READ_BYTES := 0xFFC0 + HEADER_BYTES + COPIER_BYTES

## Header destination code -> market. Canada took the US cartridge.
const DESTINATION_MARKETS := {
	0x00: "jp", 0x01: "us", 0x0F: "us",
	0x02: "eu", 0x03: "eu", 0x04: "eu", 0x05: "eu", 0x06: "eu", 0x07: "eu",
	0x08: "eu", 0x09: "eu", 0x0A: "eu", 0x11: "au",
}

## Internal title, trailing spaces trimmed -> preset.
const TITLE_SHELLS := {
	"KILLER INSTINCT": &"black",
}

static var _gamelists := GamelistManager.new()
static var _gamelist_stamps := {}


## The body model for a ROM, or "" to keep the procedural box.
static func body_model_for_rom(body_region: String, systemid: String, rom_path: String) -> String:
	var scraped := scraped_rom(systemid, rom_path)
	var market_name := N64CartShell.market_of_region(str(scraped.get("region", "")))
	if market_name.is_empty():
		market_name = header_market(read_header(rom_path))
	return body_model(body_region, market_name, date_digits(str(scraped.get("releasedate", ""))))


## A forced body on any ROM; otherwise a North American ROM's first print by
## `released` (YYYYMMDD, or "" when unknown), and "" for any other market.
static func body_model(body_region: String, market_name: String, released := "") -> String:
	match body_region:
		TYPE_A:
			return BODY_TYPE_A
		TYPE_B:
			return BODY_TYPE_B
	if market_name != "us":
		return ""
	return BODY_TYPE_B if released.length() == 8 and released >= TYPE_B_FROM else BODY_TYPE_A


static func preset_for_rom(rom_path: String) -> StringName:
	return preset_for_title(title_of(read_header(rom_path)))


static func preset_for_title(title: String) -> StringName:
	return TITLE_SHELLS.get(title, DEFAULT_PRESET)


## "us", "jp", "eu", "au", or "" when the header does not say.
static func header_market(header: PackedByteArray) -> String:
	if header.size() < HEADER_BYTES:
		return ""
	return str(DESTINATION_MARKETS.get(header[DESTINATION_AT], ""))


## The internal header's title, trailing spaces trimmed, or "".
static func title_of(header: PackedByteArray) -> String:
	if header.size() < HEADER_BYTES:
		return ""
	var title := ""
	for i in TITLE_BYTES:
		var b := header[i]
		if b < 0x20 or b > 0x7E:
			break
		title += char(b)
	return title.strip_edges(false, true)


## The ROM's 32-byte internal header, or empty when none checks out (a zipped
## ROM, a missing file, or a checksum and complement that do not pair).
static func read_header(rom_path: String) -> PackedByteArray:
	if rom_path.is_empty():
		return PackedByteArray()
	var f := FileAccess.open(rom_path, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	var skip := COPIER_BYTES if f.get_length() % 0x400 == COPIER_BYTES else 0
	var bytes := f.get_buffer(READ_BYTES)
	f.close()
	return header_in(bytes, skip)


## The first header in `bytes` (from offset `skip`) whose checksum and complement
## sum to 0xFFFF, as every licensed cartridge's do, or empty.
static func header_in(bytes: PackedByteArray, skip := 0) -> PackedByteArray:
	for at: int in HEADER_AT:
		var h := skip + at
		if bytes.size() < h + HEADER_BYTES:
			continue
		if bytes.decode_u16(h + CHECKSUM_COMPLEMENT_AT) + bytes.decode_u16(h + CHECKSUM_AT) == 0xFFFF:
			return bytes.slice(h, h + HEADER_BYTES)
	return PackedByteArray()


## "YYYYMMDD" from a scraped date ("1994-11-01", "19941101T000000"), or "".
static func date_digits(date: String) -> String:
	var digits := ""
	for c in date:
		if c >= "0" and c <= "9":
			digits += c
		elif c == "T":
			break
	return digits.left(8) if digits.length() >= 8 else ""


## This ROM's entry in the system's scraped gamelist ({region, releasedate, ...}),
## or {}.
static func scraped_rom(systemid: String, rom_path: String) -> Dictionary:
	if systemid.is_empty() or rom_path.is_empty():
		return {}
	var path := RomLibrary.rom_dir_for_system(systemid).path_join("gamelist.json")
	var stamp := FileAccess.get_modified_time(path) if FileAccess.file_exists(path) else 0
	if _gamelist_stamps.get(systemid, -1) != stamp:
		_gamelists.invalidate(systemid)
		_gamelist_stamps[systemid] = stamp
	var game := _gamelists.get_game_for_rom(systemid, rom_path)
	for rom: Dictionary in game.get("roms", []):
		if str(rom.get("path", "")).get_file() == rom_path.get_file():
			return rom
	return {}
