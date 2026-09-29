## SnesCartShell — which body and moulded shell a Super NES cartridge spawns with.
##
## Three bodies. Two are the North American (NTSC-U) shell, alike but for the
## front latch: Type A, the deep locking notch (Super Mario World's), and Type B,
## the sloped recess (Bubsy II's) that replaced it partway through 1993. Games
## printed after the change, reprints of older ones included, came in Type B. The
## third is the Super Famicom shell, which Japan, Europe and Australia shared:
## rounded top, ribbed back, 128 x 87.5 x 20 mm (Super Mario RPG's).
##
## Auto (RetroCartridge.body_region empty) gives a North American ROM the body of
## its first print by release date: Type B from TYPE_B_FROM on, else Type A, which
## is also the answer when no date is known. A Japanese, European or Australian
## ROM gets the Super Famicom body; a ROM of no known market keeps the procedural
## box. The player can force any body on any ROM at spawn.
##
## The market is the scraper's region for the ROM, else the file name's region
## tag, else the destination byte of the internal header. The shell colour is read
## from that header's title, never by hashing the file: Killer Instinct shipped in
## black plastic, and the North American Doom and Maximum Carnage in red;
## everything else in the standard grey, the model's own. The colours are in
## Resources/snes_cartridge_shells.tres.
class_name SnesCartShell
extends RefCounted

const SYSTEMID := "snes"
const BODY_TYPE_A := "res://imported-assets/carts/snes/snes_cart_type_a.glb"
const BODY_TYPE_B := "res://imported-assets/carts/snes/snes_cart_type_b.glb"
const BODY_SFC := "res://imported-assets/carts/sfc/sfc_cart.glb"
## RetroCartridge.body_region values the player can force. Empty is Auto.
const TYPE_A := "type_a"
const TYPE_B := "type_b"
const SFC := "sfc"
## Markets whose cartridges are the Super Famicom shell.
const SFC_MARKETS: Array[String] = ["jp", "eu", "au"]
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

## Internal title, trailing spaces trimmed -> [preset, the markets it shipped in, or
## [] for every one]. Measured on a No-Intro set: these titles belong to no other
## game. Doom's and Maximum Carnage's ROMs share their titles across markets, but
## only the North American cartridges were red; Europe's and Japan's were grey.
## Killer Instinct had no Japanese release.
const TITLE_SHELLS := {
	"KILLER INSTINCT": [&"black", []],
	"DOOM": [&"red", ["us"]],
	"MAXIMUM CARNAGE": [&"red", ["us"]],
}

## GoodTools' one-letter region codes, as in "Doom (U) [!].smc".
const GOODTOOLS_MARKETS := {"U": "us", "J": "jp", "E": "eu", "F": "eu", "G": "eu", "A": "au"}

static var _gamelists := GamelistManager.new()
static var _gamelist_stamps := {}


## The body model for a ROM, or "" to keep the procedural box.
static func body_model_for_rom(body_region: String, systemid: String, rom_path: String) -> String:
	var released := date_digits(str(scraped_rom(systemid, rom_path).get("releasedate", "")))
	return body_model(body_region, market(systemid, rom_path), released)


## "us", "jp", "eu", "au", or "" — from the scraper's region for the ROM, else the
## file name's region tag, else the header's destination byte. The tag outranks
## the header: 12 of 3,057 retail No-Intro ROMs carry a wrong destination
## (Pinocchio and Flashback USA say Japan, An American Tail 0xFF, FIFA 98 Europe
## says USA), and none a wrong tag.
static func market(systemid: String, rom_path: String) -> String:
	var found := N64CartShell.market_of_region(str(scraped_rom(systemid, rom_path).get("region", "")))
	if found.is_empty():
		found = filename_market(rom_path)
	if found.is_empty():
		found = header_market(read_header(rom_path))
	return found


## The market of the first bracketed region tag in the file name: No-Intro's
## "(USA)", "(Europe)", "(Japan, USA)", or GoodTools' "(U)", "(JU)". A tag naming
## North America among others is "us": that cartridge was sold there.
static func filename_market(rom_path: String) -> String:
	var name := rom_path.get_file()
	var at := name.find("(")
	while at >= 0:
		var close := name.find(")", at)
		if close < 0:
			break
		var tag := name.substr(at + 1, close - at - 1).strip_edges()
		var found: Array[String] = []
		for part in tag.split(","):
			var m := N64CartShell.market_of_region(part)
			if not m.is_empty():
				found.append(m)
		if found.is_empty() and _is_goodtools_code(tag):
			for c in tag:
				found.append(GOODTOOLS_MARKETS[c])
		if not found.is_empty():
			return "us" if found.has("us") else found[0]
		at = name.find("(", close)
	return ""


## A forced body on any ROM; otherwise a North American ROM's first print by
## `released` (YYYYMMDD, or "" when unknown), the Super Famicom body for the
## markets that shared it, and "" when the market is unknown.
static func body_model(body_region: String, market_name: String, released := "") -> String:
	match body_region:
		TYPE_A:
			return BODY_TYPE_A
		TYPE_B:
			return BODY_TYPE_B
		SFC:
			return BODY_SFC
	if market_name in SFC_MARKETS:
		return BODY_SFC
	if market_name != "us":
		return ""
	return BODY_TYPE_B if released.length() == 8 and released >= TYPE_B_FROM else BODY_TYPE_A


## "U", "JU", "E": every letter a GoodTools region code ("PAL" is not one).
static func _is_goodtools_code(tag: String) -> bool:
	if tag.is_empty() or tag.length() > 3:
		return false
	for c in tag:
		if not GOODTOOLS_MARKETS.has(c):
			return false
	return true


static func preset_for_rom(rom_path: String, systemid := SYSTEMID) -> StringName:
	return preset_for_title(title_of(read_header(rom_path)), market(systemid, rom_path))


## The shell a title shipped in, in `market_name`: grey unless TITLE_SHELLS lists
## the title for that market (or for every market).
static func preset_for_title(title: String, market_name := "") -> StringName:
	var entry: Array = TITLE_SHELLS.get(title, [])
	if entry.is_empty():
		return DEFAULT_PRESET
	var markets: Array = entry[1]
	return entry[0] if markets.is_empty() or markets.has(market_name) else DEFAULT_PRESET


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
