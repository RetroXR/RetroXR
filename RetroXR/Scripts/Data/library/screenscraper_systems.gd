## ScreenscraperSystems — maps project systemid strings to screenscraper.fr numeric systemeid values.
class_name ScreenscraperSystems
extends RefCounted


## Mapping from project systemid → screenscraper systemeid.
## Source: https://www.screenscraper.fr/webapi2.php (system list)
const SYSTEM_MAP := {
	"3do": 29,
	"n3ds": 17,
	"amigacd32": 130,
	"cdtv": 129,
	"apple2": 86,
	"arcadia": 94,
	"arduboy": 263,
	"atari2600": 26,
	"atari5200": 40,
	"atari7800": 41,
	"atari800": 43,
	"atarijaguar": 27,
	"atarilynx": 28,
	"atarist": 42,
	"bbcmicro": 37,
	"cdi": 133,
	"channelf": 80,
	"colecovision": 48,
	"amiga": 64,
	"commodore_c128": 66,
	"c64": 66,
	"commodore_c64_supercpu": 66,
	"commodore_c64dtv": 66,
	"commodore_pet": 240,
	"plus4": 99,
	"vic20": 73,
	"amstradcpc": 65,
	"daphne": 49,
	"doom": 290,
	"dos": 135,
	"dreamcast": 23,
	"epochcv": 300,
	# "Nintendo GBA e-Reader", an accessory system of its own there the same way
	# the Famicom Disk System and the Satellaview are.
	"ereader": 119,
	"fbneo": 75,
	"fds": 106,
	"gb": 9,
	"gba": 12,
	"gamegear": 21,
	"gc": 13,
	# Screenscraper has no generic handheld-electronic platform, only Nintendo's
	# Game & Watch. A Tiger or Acclaim title reaches it as a name search and
	# usually misses, which costs it art rather than giving it the wrong art.
	"gameandwatch": 52,
	"hbmame": 75,
	"intellivision": 115,
	"j2me": 302,
	"atarijaguarcd": 171,
	"jollycv": 48,
	"lowresnx": 244,
	"macintosh": 146,
	"mame": 75,
	"mastersystem": 2,
	"genesis": 1,
	"megaduck": 90,
	"model3": 55,
	"msx": 113,
	"nds": 15,
	"neogeocd": 70,
	"ngp": 25,
	"neogeo": 142,
	"nes": 3,
	# ScreenScraper does not split the two: one platform, both regions.
	"famicom": 3,
	"n64": 14,
	"n64dd": 122,
	"odyssey2": 104,
	"p2000t": 287,
	"palm": 219,
	"pc88": 221,
	"pc98": 208,
	"tg16": 31,
	"tg-cd": 114,
	"pcfx": 72,
	"pcxt": 135,
	"pico8": 234,
	"psx": 57,
	"ps2": 58,
	"psp": 61,
	"pokemini": 211,
	"samcoupe": 213,
	"satellaview": 107,
	"scummvm": 123,
	"sega32x": 19,
	"segacd": 20,
	"sega_pico": 250,
	"saturn": 22,
	"sg-1000": 109,
	"x1": 220,
	"x68000": 79,
	"sufami": 108,
	"scv": 67,
	"snes": 4,
	"supergrafx": 105,
	"supervision": 207,
	"spectravideo": 218,
	"tamagotchi": 293,
	"moto": 141,
	"ti_83": 205,
	"tic80": 222,
	"uzebox": 216,
	"vectrex": 102,
	"vircon32": 272,
	"virtualboy": 11,
	"wasm4": 262,
	"wii": 16,
	"wiiu": 18,
	"wonderswan": 45,
	"xbox": 32,
	"zmachine": 215,
	"zx81": 77,
	"zxspectrum": 76,
}


## Returns the screenscraper systemeid for a project systemid, or -1 if unmapped.
static func get_systemeid(systemid: String) -> int:
	if _mod_map.has(systemid):
		return int(_mod_map[systemid])
	return SYSTEM_MAP.get(systemid, -1)


## Mappings contributed by mods.
##
## A platform absent from SYSTEM_MAP can never be scraped, so a mod platform
## without one gets no box art, no wheel and no cart label -- ever. That failure
## is invisible: the carts simply stay blank, and nothing anywhere says why.
static var _mod_map: Dictionary = {}
## systemid -> the mod that contributed it, so it can be taken back again.
static var _mod_owners: Dictionary = {}


## "" on success, else why the mapping was refused — the failure this table
## describes above is invisible at runtime, so refusing one quietly is the worst
## of the options available.
static func register_mod_system(systemid: String, systemeid: int,
		owner_id: String = "") -> String:
	if systemid.is_empty():
		return "systemid is empty"
	if systemeid <= 0:
		return "screenscraper system id must be positive, got %d" % systemeid
	_mod_map[systemid] = systemeid
	_mod_owners[systemid] = owner_id
	return ""


## Take back one mod's mappings. A mapping left standing after its mod is gone
## points a platform that no longer exists at a scraper system that does.
static func drop_mod(owner_id: String) -> void:
	for systemid: String in _mod_owners.keys():
		if _mod_owners[systemid] != owner_id:
			continue
		_mod_map.erase(systemid)
		_mod_owners.erase(systemid)
