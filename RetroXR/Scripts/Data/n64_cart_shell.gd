## N64CartShell — which body and which moulded shell an N64 cartridge spawns with.
##
## The body follows the market the game was sold in: Japanese cartridges have
## their own rear key notches and latches, North American and PAL ones share a
## shape. The market is what the scraper recorded for the ROM, else the ROM
## header's country byte.
##
## The shell is looked up by the ROM's identity in N64CartColorsTable (see
## Tools/gen_n64_cart_colors.py): by MD5 when one is known, else by the header's
## CRC pair and country, which reads 64 bytes instead of hashing the file. A game
## the table does not list shipped in grey. A PAL release whose Australian run was
## moulded differently only takes that colour when the market is Australia.
class_name N64CartShell
extends RefCounted

const BODY_USA := "res://imported-assets/carts/nintendo_64/n64_cartridge_usa.glb"
const BODY_JPN := "res://imported-assets/carts/nintendo_64/n64_cartridge_jpn.glb"
const DEFAULT_PRESET := &"grey"

## RetroCartridge.body_region values. North America and PAL share a body.
const REGION_USA := "usa"
const REGION_JPN := "jpn"

const HEADER_BYTES := 0x40
const COUNTRY_AT := 0x3E

## Header country code -> market.
const COUNTRY_MARKETS := {
	"E": "us", "N": "us", "J": "jp", "U": "au",
	"P": "eu", "X": "eu", "Y": "eu", "D": "eu", "F": "eu", "S": "eu",
	"I": "eu", "H": "eu", "W": "eu", "L": "eu",
}

## Scraped region name or code, lower-cased -> market.
const REGION_MARKETS := {
	"usa": "us", "us": "us", "canada": "us", "ca": "us",
	"japan": "jp", "jp": "jp",
	"australia": "au", "au": "au", "new zealand": "au", "nz": "au",
	"europe": "eu", "eu": "eu", "uk": "eu", "united kingdom": "eu",
	"germany": "eu", "de": "eu", "france": "eu", "fr": "eu", "italy": "eu", "it": "eu",
	"spain": "eu", "sp": "eu", "es": "eu", "netherlands": "eu", "nl": "eu",
	"sweden": "eu", "se": "eu", "scandinavia": "eu",
}

const SYSTEMID := "n64"


## "us", "eu", "au", "jp", or "" when neither the scraper nor the header says.
## Nothing in the ROM saying, the cartridge's pinned market, else the player's.
static func market(systemid: String, rom_path: String, pinned := "") -> String:
	return CartRomInfo.market_or_pinned(rom_market(systemid, rom_path), pinned)


## The market the ROM itself names, or "" -- market() without the fallback.
static func rom_market(systemid: String, rom_path: String) -> String:
	var scraped := market_of_region(scraped_region(systemid, rom_path))
	return scraped if not scraped.is_empty() else header_market(read_header(rom_path))


static func body_model(market_name: String) -> String:
	return BODY_JPN if market_name == "jp" else BODY_USA


## The body for a region the player forced, else the market's own.
static func body_model_for_region(region: String, market_name: String) -> String:
	match region:
		REGION_USA:
			return BODY_USA
		REGION_JPN:
			return BODY_JPN
	return body_model(market_name)


## The shell a ROM spawns in, in the market() it was sold in -- the same
## (rom_path, systemid, pinned) contract SnesCartShell and NesCartShell keep. One
## with a market in hand already asks preset_for_header.
static func preset_for_rom(rom_path: String, systemid := SYSTEMID, pinned := "") -> StringName:
	return preset_for_header(read_header(rom_path), market(systemid, rom_path, pinned))


# --- The cart-shell protocol (ModCartShells' table of the game's own shells) ---

## The body a cartridge wears: a forced region's, else its market's.
static func cart_body(systemid: String, rom_path: String, body_region: String,
		_shell_preset: StringName, pinned: String) -> String:
	return body_model_for_region(body_region, market(systemid, rom_path, pinned))


## {palette, preset}: the N64 palette and this ROM's shell in it.
static func cart_finish(systemid: String, rom_path: String, _model_path: String,
		pinned: String) -> Dictionary:
	return {"palette": SYSTEMID, "preset": preset_for_rom(rom_path, systemid, pinned)}


static func preset_for_header(header: PackedByteArray, market_name: String = "") -> StringName:
	var key := header_key(header)
	if key.is_empty():
		return DEFAULT_PRESET
	if market_name == "au" and N64CartColorsTable.AUSTRALIA_CRC.has(key):
		return StringName(N64CartColorsTable.AUSTRALIA_CRC[key])
	return StringName(N64CartColorsTable.SHELL_CRC.get(key, DEFAULT_PRESET))


static func preset_for_md5(md5: String, market_name: String = "") -> StringName:
	var key := md5.to_lower()
	if market_name == "au" and N64CartColorsTable.AUSTRALIA_MD5.has(key):
		return StringName(N64CartColorsTable.AUSTRALIA_MD5[key])
	return StringName(N64CartColorsTable.SHELL_MD5.get(key, DEFAULT_PRESET))


static func market_of_region(region: String) -> String:
	return str(REGION_MARKETS.get(region.strip_edges().to_lower(), ""))


## "CRC1-CRC2:market" for the table, with Australia keyed under PAL, or "".
static func header_key(header: PackedByteArray) -> String:
	var crc := N64SaveDb.header_crc_key(header)
	var m := header_market(header)
	if crc.is_empty() or m.is_empty():
		return ""
	return "%s:%s" % [crc, "eu" if m == "au" else m]


static func header_market(header: PackedByteArray) -> String:
	var at := _country_offset(header)
	if at < 0:
		return ""
	return str(COUNTRY_MARKETS.get(char(header[at]), ""))


## The region the scraper wrote for this ROM in the system's gamelist, or "".
static func scraped_region(systemid: String, rom_path: String) -> String:
	return str(CartRomInfo.scraped_rom(systemid, rom_path).get("region", ""))


static func read_header(rom_path: String) -> PackedByteArray:
	return CartRomInfo.read_bytes(rom_path, HEADER_BYTES)


## Where the big-endian country byte lies in this dump's byte order, or -1.
static func _country_offset(header: PackedByteArray) -> int:
	if header.size() < HEADER_BYTES:
		return -1
	var head := [header[0], header[1], header[2], header[3]]
	if head == N64SaveDb.MAGIC_Z64:
		return COUNTRY_AT
	if head == N64SaveDb.MAGIC_V64:
		return COUNTRY_AT + 1
	if head == N64SaveDb.MAGIC_N64:
		return COUNTRY_AT - 1
	return -1
