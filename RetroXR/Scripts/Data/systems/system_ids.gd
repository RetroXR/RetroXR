## SystemIds — what a platform is called, and what it used to be called.
##
## A systemid is ES-DE's folder name for the machine (`n64`, `snes`, `gb`), so a
## ROM tree laid out for ES-DE is a ROM tree laid out for RetroXR. Until
## 2026-09-18 the ids were libretro's long ones (`nintendo_64`, `super_nes`,
## `game_boy`), and those are still on players' disks: in saved rooms, in a
## mod's manifest, in the name of a ROM folder nobody has moved. LEGACY is how
## each of those is read. Ids ES-DE has no folder for keep the name they had.
##
## Where ES-DE has several folders for one machine the primary is the US name
## for Sega and NEC (`genesis`, `segacd`, `tg16`, `tg-cd`) and the rest are
## FOLDER_ALIASES: scanned for ROMs, never written to.
##
## THREE NAMESPACES LOOK LIKE SYSTEMIDS AND ARE NOT, and none of them moved: a
## memory card's `family` (`playstation`, `gamecube` — it names
## save/memcards/<family>/), an expansion unit's id (`sega_cd`, `sufami_turbo`,
## `jaguar_cd` — it names save/carts/<host>/<expansion_id>/) and a `model_id`
## (`nes`, `nintendo_64_primitive`). All three are persisted, so canonical()
## must only ever be handed a value that IS a systemid.
##
## Tools/rename_systemids.py carries the same table for the .info files, which
## are a mirror of the libretro-super fork and have to be renamed again after
## any refresh that was not. systems_data_tests pins the two against each other.
class_name SystemIds
extends RefCounted

const LEGACY: Dictionary = {
	"3ds": "n3ds",
	"amiga_cd32": "amigacd32",
	"amiga_cdtv": "cdtv",
	"apple_ii": "apple2",
	"atari_2600": "atari2600",
	"atari_5200": "atari5200",
	"atari_7800": "atari7800",
	"atari_8bit": "atari800",
	"atari_jaguar": "atarijaguar",
	"atari_lynx": "atarilynx",
	"atari_st": "atarist",
	"channel_f": "channelf",
	"commodore_amiga": "amiga",
	"commodore_c64": "c64",
	"commodore_plus4": "plus4",
	"commodore_vic20": "vic20",
	"cpc": "amstradcpc",
	"doom_3": "doom3",
	"fb_alpha": "arcade",
	"game_boy": "gb",
	"game_boy_advance": "gba",
	"game_gear": "gamegear",
	"gamecube": "gc",
	"handheld_electronic": "gameandwatch",
	"jaguar_cd": "atarijaguarcd",
	"mac68k": "macintosh",
	"master_system": "mastersystem",
	"mega_drive": "genesis",
	"mega_duck": "megaduck",
	"neo_geo_cd": "neogeocd",
	"neo_geo_pocket": "ngp",
	"nintendo_64": "n64",
	"nintendo_64dd": "n64dd",
	"palm_os": "palm",
	"pc_88": "pc88",
	"pc_98": "pc98",
	"pc_engine": "tg16",
	"pc_engine_cd": "tg-cd",
	"pc_fx": "pcfx",
	"playstation": "psx",
	"playstation2": "ps2",
	"playstation_portable": "psp",
	"pokemon_mini": "pokemini",
	"quake_1": "quake",
	"quake_3": "quake3",
	"sam_coupe": "samcoupe",
	"sega_32x": "sega32x",
	"sega_cd": "segacd",
	"sega_saturn": "saturn",
	"sg1000": "sg-1000",
	"sharp_x1": "x1",
	"sharp_x68000": "x68000",
	"sufami_turbo": "sufami",
	"super_cassette_vision": "scv",
	"super_nes": "snes",
	"svi": "spectravideo",
	"thomson_moto": "moto",
	"virtual_boy": "virtualboy",
	"wolfenstein3d": "wolfenstein",
	"zx_spectrum": "zxspectrum",
}

## Ids that are not a system of their own any more but were never RENAMED: several
## of them became one, and nothing on disk moved. `mame`, `fbneo` and `hbmame` are
## three emulators of the one arcade machine (ES-DE gives them all `<platform>arcade`),
## and `roms/mame/` holds the player's ROMs, so their folders stay where they are and
## are read as `arcade`'s (FOLDER_ALIASES). Unlike LEGACY this is MANY-TO-ONE, which
## LEGACY's invariants forbid (systems_data_tests `ids/`), and nothing here is
## migrated: a saved room, a binding or a ledger key that says `mame` is read through
## canonical() as it loads, the way a LEGACY one is. Tools/rename_systemids.py reads
## both tables, so the .info files say `arcade`.
const MERGED: Dictionary = {
	"mame": "arcade",
	"fbneo": "arcade",
	"hbmame": "arcade",
}

## Other ES-DE folders holding the same machine's ROMs. `famicom`, `gbc`, `ngpc`
## and `wonderswancolor` are absent on purpose: each is a system of its own here. So is
## `sgb`, which fits more than one tile. `arcade` takes every ES-DE folder whose games
## are MAME or FinalBurn Neo romsets (`cps*` and `model*` included: the cabinet is the
## same, and which emulator plays a set is the core's choice, not the folder's).
## `neogeo`, `naomi*`, `atomiswave`, `daphne` and `dice` are NOT here: each has a core
## of its own or hardware of its own, so each is a system.
const FOLDER_ALIASES: Dictionary = {
	"amiga": ["amiga600", "amiga1200"],
	"amstradcpc": ["gx4000"],
	"arcade": ["mame", "fbneo", "fba", "hbmame", "mame-libretro", "mame-advmame", "mame-mame4all",
		"cps", "cps1", "cps2", "cps3", "model2", "model3", "stv"],
	"atari800": ["atarixe"],
	"cdi": ["cdimono1", "philips-cd-i"],
	"gameandwatch": ["lcdgames"],
	"genesis": ["megadrive", "megadrivejp"],
	"mastersystem": ["mark3"],
	"moto": ["to8"],
	"msx": ["msx1", "msx2", "msxturbor"],
	# RomM files them under `neogeomvs` and `neogeoaes` (its platform list names both); ES-DE keeps one
	# `neogeo` folder for the two. The cartridges differ in the plastic and the connector, the game DATA
	# is the same (the cores take one romset for either), so one system holds both.
	"neogeo": ["neogeomvs", "neogeoaes"],
	"neogeocd": ["neogeocdjp"],
	"odyssey2": ["videopac"],
	"satellaview": ["satellaview_plus"],
	"saturn": ["saturnjp"],
	"sega32x": ["sega32xjp", "sega32xna"],
	"segacd": ["megacd", "megacdjp"],
	"snes": ["sfc", "snesna"],
	"tg-cd": ["pcenginecd"],
	"tg16": ["pcengine"],
	"x68000": ["sharp-x68000"],
}

static var _legacy_of: Dictionary = {}
static var _folder_owner: Dictionary = {}


## The id a platform goes by now. Anything in neither table is already it.
static func canonical(systemid: String) -> String:
	var id: String = LEGACY.get(systemid, systemid)
	return MERGED.get(id, id)


## The id this platform went by before the rename, or "" if it never had another.
static func legacy_of(systemid: String) -> String:
	if _legacy_of.is_empty():
		for old: String in LEGACY:
			_legacy_of[LEGACY[old]] = old
	return _legacy_of.get(systemid, "")


## A systemid-keyed dictionary off the player's disk, under today's ids. Where a
## key exists under both names the new one is the one written since, and stays.
static func rekeyed(by_systemid: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: Variant in by_systemid:
		var id := canonical(str(key))
		if id == str(key) or not by_systemid.has(id):
			out[id] = by_systemid[key]
	return out


## The same for keys shaped "<systemid>/<the rest>".
static func rekeyed_paths(by_path: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: Variant in by_path:
		var path := canonical_path(str(key))
		if path == str(key) or not by_path.has(path):
			out[path] = by_path[key]
	return out


## "super_nes/Game.sfc" as "snes/Game.sfc".
static func canonical_path(path: String) -> String:
	var slash := path.find("/")
	if slash <= 0:
		return path
	return canonical(path.left(slash)) + path.substr(slash)


## Every folder name a platform's ROMs may be found under, the primary first:
## the id, then the name it had before the rename, then ES-DE's other folders.
static func folder_names(systemid: String) -> PackedStringArray:
	var names := PackedStringArray([systemid])
	var old := legacy_of(systemid)
	if old != "":
		names.append(old)
	for alias: String in FOLDER_ALIASES.get(systemid, []):
		names.append(alias)
	return names


## The platform a ROM folder of this name belongs to: the name itself unless it
## is an old id or one of ES-DE's other folders for the same machine.
static func systemid_for_folder(folder: String) -> String:
	if _folder_owner.is_empty():
		for owner: String in FOLDER_ALIASES:
			for alias: String in FOLDER_ALIASES[owner]:
				_folder_owner[alias] = owner
	return _folder_owner.get(folder, canonical(folder))
