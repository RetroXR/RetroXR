## NesCartShell — which molded shell an NES cartridge spawns with.
##
## Every NES Game Pak came in the grey shell but two: The Legend of Zelda and
## Zelda II: The Adventure of Link, whose North American and European cartridges
## were vacuum-metallized gold. Later Classic Series reprints went back to grey; a
## ROM cannot tell which print it came from, so a Zelda ROM gets the gold. The
## Japanese releases were Famicom Disk System games (and, later, a grey Famicom
## cartridge), so a Japanese ROM stays grey.
##
## An iNES ROM carries no title, so the game is found by name: the scraped
## gamelist's name for the ROM, else the file name. The market is the scraped
## region, else the file name's region tag. The colors are in
## Resources/nes_cartridge_shells.tres; the player can force either at spawn.
class_name NesCartShell
extends RefCounted

const SYSTEMID := "nes"
const DEFAULT_PRESET := &"grey"
const GOLD_PRESET := &"gold"
## Words that mark a gold Game Pak, matched against the normalized name.
const GOLD_NAMES: Array[String] = ["zelda"]
## Markets whose releases were not the gold cartridge.
const NOT_GOLD_MARKETS: Array[String] = ["jp"]

static var _gamelists := GamelistManager.new()
static var _gamelist_stamps := {}


## The shell a ROM spawns in: gold for a Zelda outside Japan, else grey.
static func preset_for_rom(rom_path: String, systemid := SYSTEMID) -> StringName:
	return preset_for_name(game_name(systemid, rom_path), market(systemid, rom_path))


## The shell a game of this name shipped in, in `market_name` ("" when unknown).
static func preset_for_name(name: String, market_name := "") -> StringName:
	if NOT_GOLD_MARKETS.has(market_name):
		return DEFAULT_PRESET
	var words := normalized(name)
	for gold: String in GOLD_NAMES:
		if (" %s " % words).contains(" %s " % gold):
			return GOLD_PRESET
	return DEFAULT_PRESET


## Lower case, bracketed tags dropped, everything but letters and digits a space:
## "Legend of Zelda, The (USA) (Rev A).nes" -> "legend of zelda the nes".
static func normalized(name: String) -> String:
	var out := ""
	var depth := 0
	for c in name.to_lower():
		if c == "(" or c == "[":
			depth += 1
		elif c == ")" or c == "]":
			depth = maxi(depth - 1, 0)
		elif depth == 0:
			out += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else " "
	return " ".join(out.split(" ", false))


## The scraped name for the ROM, else its file name.
static func game_name(systemid: String, rom_path: String) -> String:
	if rom_path.is_empty():
		return ""
	var scraped := ""
	if not systemid.is_empty():
		# Reload the gamelist when a scrape has rewritten it, as SnesCartShell does.
		var path := RomLibrary.rom_dir_for_system(systemid).path_join("gamelist.json")
		var stamp := FileAccess.get_modified_time(path) if FileAccess.file_exists(path) else 0
		if _gamelist_stamps.get(systemid, -1) != stamp:
			_gamelists.invalidate(systemid)
			_gamelist_stamps[systemid] = stamp
		scraped = str(_gamelists.get_game_for_rom(systemid, rom_path).get("name", ""))
	return scraped if not scraped.is_empty() else rom_path.get_file().get_basename()


## "us", "jp", "eu", "au", or "" when neither the scraper nor the file name says.
static func market(systemid: String, rom_path: String) -> String:
	var found := N64CartShell.market_of_region(str(SnesCartShell.scraped_rom(systemid, rom_path).get("region", "")))
	return found if not found.is_empty() else SnesCartShell.filename_market(rom_path)
