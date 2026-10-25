## RegionalNames — what a platform is called in the USA, Europe and Japan.
##
## The Mega Drive is the Genesis in the USA, the PC Engine is the TurboGrafx-16.
## One tile, one folder (SystemIds.FOLDER_ALIASES already merges `megadrive` into
## `genesis`); this only chooses the NAME the tile wears, from Options > Systems.
## Until the player picks one ("" stored), the region is the OUTLET region's
## (Options > Outlet Region, itself seeded from the system locale), and follows it
## if that moves; a pick then sticks. "original" keeps the names the cores' own
## info files give.
##
## A region a row does not list falls back to its US name, so nothing is ever
## blank, and a system not in the table (a mod's, say) keeps its name.
##
## Every name here is also a SEARCH alias for its tile whatever the dropdown
## says: with "Mega Drive" showing, "genesis" must still find it.
class_name RegionalNames
extends RefCounted

## [pref value, label], in the dropdown's order: USA first. There is no row for
## "" -- not picked yet -- because the dropdown shows the region the outlet gives
## instead (outlet_region()); "original" is the cores' own names.
const ORIGINAL := "original"
const REGIONS := [["us", "USA"], ["eu", "Europe"], ["jp", "Japan"], [ORIGINAL, "Original"]]
## The three regions a pick can name, and what the dropdown calls each.
const LABELS := {"us": "USA", "eu": "Europe", "jp": "Japan"}

## A suite pins the region here; unset, a run under res://Tests/ resolves to "" so
## a name or a cartridge never depends on the machine's locale.
static var test_region: String = "<unset>"
## Whether this process is a suite: read once, since a name lookup asks it for
## every tile of every grid rebuild.
static var _test_run: int = -1

const NAMES := {
	"genesis": {"us": "Sega Genesis", "eu": "Sega Mega Drive", "jp": "Sega Mega Drive"},
	"segacd": {"us": "Sega CD", "eu": "Sega Mega-CD", "jp": "Sega Mega-CD"},
	"sega32x": {"us": "Sega 32X", "eu": "Sega Mega Drive 32X", "jp": "Sega Super 32X"},
	"mastersystem": {"us": "Sega Master System", "eu": "Sega Master System", "jp": "Sega Mark III"},
	"tg16": {"us": "TurboGrafx-16", "eu": "PC Engine", "jp": "PC Engine"},
	"tg-cd": {"us": "TurboGrafx-CD", "eu": "PC Engine CD-ROM²", "jp": "PC Engine CD-ROM²"},
	"supergrafx": {"us": "PC Engine SuperGrafx", "eu": "PC Engine SuperGrafx", "jp": "PC Engine SuperGrafx"},
	"odyssey2": {"us": "Magnavox Odyssey²", "eu": "Philips Videopac G7000"},
	"snes": {"us": "Super Nintendo", "eu": "Super Nintendo", "jp": "Super Famicom"},
}

## An add-on's name per region, by ExpansionCatalog id. Short, because it is
## printed after its host's on a stacked console's nameplate ("Sega Mega Drive +
## Mega-CD + 32X"); a region a row omits keeps the row's own label. DISPLAY ONLY:
## ExpansionCatalog.label_of stays the fixed name, because a unit's memory card id
## is minted from it and persisted.
const ADDON_NAMES := {
	"sega_cd": {"us": "Sega CD", "eu": "Mega-CD", "jp": "Mega-CD"},
	"sega_32x": {"us": "32X", "eu": "32X", "jp": "Super 32X"},
}

## Spellings people type that are not any region's full name.
const EXTRA_ALIASES := {
	"genesis": ["mega drive", "megadrive"],
	"segacd": ["mega cd", "megacd"],
	"sega32x": ["super 32x", "mega drive 32x"],
	"mastersystem": ["mark iii", "mark 3", "mark3"],
	"tg16": ["pc engine", "pcengine", "pce"],
	"tg-cd": ["pc engine cd", "pcengine cd", "pce cd", "pcecd"],
	"supergrafx": ["pc engine supergrafx", "sgx"],
	"odyssey2": ["videopac", "g7000", "g7400"],
	"snes": ["super famicom", "sfc"],
}


## "us" / "eu" / "jp" for a mains region: North America and China are the USA,
## Japan is Japan, every other outlet -- Brazil's included, where Tectoy sold the
## Mega Drive and the Master System under those names -- is Europe's names.
static func region_of_mains(mains: String) -> String:
	match mains:
		"na", "cn":
			return "us"
		"jp":
			return "jp"
	return "eu"


## The region the outlet gives: what an unpicked setting means, and what the
## dropdown shows selected until the player picks.
static func outlet_region() -> String:
	return region_of_mains(_player_mains())


## The region whose names tiles wear, for a pick and an outlet region: the pick,
## the outlet region's answer when nothing is picked, or "" for Original.
static func names_region_for(pick: String, mains: String) -> String:
	if pick == ORIGINAL:
		return ""
	return pick if LABELS.has(pick) else region_of_mains(mains)


## The market a cartridge takes when its ROM names none (no scraped region, no
## file tag, no header code), for a pick and an outlet region. The ROM's market
## always wins; this is only asked when it is unknown.
##
## The picked region if there is one, else the outlet region's -- and the
## outlet's for Original too: Original is a choice about LABELS, and says nothing about
## which cartridge a game came in. Tying the two together meant a player who
## wanted the cores' names got the procedural box back for every unknown SNES ROM.
## An Australian outlet keeps "au", whose cartridges differ from Europe's.
##
## Brazil reads Europe's NAMES but took North America's CARTRIDGES (the Super NES
## and N64 shells sold there were the US ones), so its market here is "us".
static func cart_market_for(pick: String, mains: String) -> String:
	if LABELS.has(pick):
		return pick
	match mains:
		"au":
			return "au"
		"br":
			return "us"
	return region_of_mains(mains)


## The market for an unknown-region cartridge: `pinned` when the cartridge has
## one (the market it was given when it first appeared, saved with it), else the
## running player's. The pin is what keeps a saved cartridge's body -- the Super
## NES and Super Famicom shells are different sizes -- from changing when the
## player changes region.
static func cart_market_or(pinned: String) -> String:
	return pinned if not pinned.is_empty() else cart_market()


## names_region_for() for the running player ("" in a suite that pins nothing).
static func effective_region() -> String:
	if test_region != "<unset>":
		return test_region
	if _is_test_run():
		return ""
	return names_region_for(AppPrefs.region_names, _player_mains())


## cart_market_for() for the running player ("" in a suite that pins nothing,
## so a cartridge suite never depends on the machine's locale).
static func cart_market() -> String:
	if test_region != "<unset>":
		return test_region
	if _is_test_run():
		return ""
	return cart_market_for(AppPrefs.region_names, _player_mains())


static func _player_mains() -> String:
	var mains := AppPrefs.mains_region
	return mains if not mains.is_empty() else MainsRegions.for_locale(OS.get_locale())


static func _is_test_run() -> bool:
	if _test_run < 0:
		_test_run = 0
		for arg: String in OS.get_cmdline_args():
			if arg.begins_with("res://Tests/"):
				_test_run = 1
				break
	return _test_run == 1


## The tile name for a region in force (see effective_region), or `base` (the
## cores' own name) when it is "" or the system is not in the table.
static func name_for(systemid: String, region: String, base: String) -> String:
	if region.is_empty() or region == ORIGINAL or not NAMES.has(systemid):
		return base
	var row: Dictionary = NAMES[systemid]
	return str(row.get(region, row.get("us", base)))


## The first word of a variant id, lowercased, to the region it was sold in.
## Mods spell regions their own way -- `us` / `usa` / `us_gray`, `eu` / `eur` /
## `pal` / `ukv` / `noe` / `eu_blue`, `jp` / `jpn` / `jp_black` -- so a variant is
## read by the word its id starts with. A variant may say `"region"` outright.
const VARIANT_REGIONS := {
	"us": "us", "usa": "us", "na": "us",
	"eu": "eu", "eur": "eu", "pal": "eu", "uk": "eu", "ukv": "eu", "noe": "eu",
	"esp": "eu", "ita": "eu", "fah": "eu", "fr": "eu", "de": "eu", "au": "eu",
	"jp": "jp", "jpn": "jp", "japan": "jp",
}


## The region a row's variant was sold in ("us" / "eu" / "jp"), or "" when it is a
## colour rather than a region (most memory cards' variants are).
static func region_of_variant(variant: Dictionary) -> String:
	var said := str(variant.get("region", "")).strip_edges().to_lower()
	if not said.is_empty():
		return str(VARIANT_REGIONS.get(said, said if LABELS.has(said) else ""))
	var id := str(variant.get("id", "")).strip_edges().to_lower()
	return str(VARIANT_REGIONS.get(id.get_slice("_", 0), ""))


## The region a spawned OBJECT with regional variants takes when the player set
## no default for its row: the cartridge's answer, Australia reading Europe's
## (the variants sold there were Europe's PAL ones). "" in a suite.
static func object_region() -> String:
	var market := cart_market()
	return "eu" if market == "au" else market


## The variant of `variants` a row spawns for the player's region, as a spawn
## asks for it: "" when that is the first (the row as it comes), when no variant
## is that region's, or in a suite.
static func variant_for_region(variants: Array) -> String:
	var region := object_region()
	if region.is_empty():
		return ""
	for i in variants.size():
		if variants[i] is Dictionary and region_of_variant(variants[i]) == region:
			return "" if i == 0 else str((variants[i] as Dictionary).get("id", ""))
	return ""


## An add-on's name in the region in force, or `base` (its fixed label) for
## Original, a suite, or an add-on the table does not list.
static func addon_name(expansion_id: String, base: String) -> String:
	var region := effective_region()
	if region.is_empty():
		return base
	return str((ADDON_NAMES.get(expansion_id, {}) as Dictionary).get(region, base))


## Every name this system answers to in a search, lowercase, in every region.
static func search_aliases(systemid: String) -> PackedStringArray:
	var out := PackedStringArray()
	var row: Dictionary = NAMES.get(systemid, {})
	for region: String in row:
		var n := str(row[region]).to_lower()
		if not out.has(n):
			out.append(n)
	for extra: String in EXTRA_ALIASES.get(systemid, []):
		if not out.has(extra):
			out.append(extra)
	return out


## Whether `region` may be stored: a row's id, or "" for not picked yet.
static func is_region(region: String) -> bool:
	if region.is_empty():
		return true
	for r: Array in REGIONS:
		if r[0] == region:
			return true
	return false
