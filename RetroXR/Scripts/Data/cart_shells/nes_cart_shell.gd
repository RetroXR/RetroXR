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


## The shell a ROM spawns in: gold for a Zelda outside Japan, else grey.
static func preset_for_rom(rom_path: String, systemid := SYSTEMID, pinned := "") -> StringName:
	return preset_for_name(game_name(systemid, rom_path), market(systemid, rom_path, pinned))


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
	var scraped := str(CartRomInfo.scraped_game(systemid, rom_path).get("name", ""))
	return scraped if not scraped.is_empty() else rom_path.get_file().get_basename()


## "us", "jp", "eu", "au", or "" when neither the scraper nor the file name says.
## Nothing in the ROM saying, the cartridge's pinned market, else the player's.
static func market(systemid: String, rom_path: String, pinned := "") -> String:
	return CartRomInfo.market_or_pinned(rom_market(systemid, rom_path), pinned)


## The market the ROM itself names, or "" -- market() without the fallback.
static func rom_market(systemid: String, rom_path: String) -> String:
	var found := N64CartShell.market_of_region(str(CartRomInfo.scraped_rom(systemid, rom_path).get("region", "")))
	return found if not found.is_empty() else SnesCartShell.filename_market(rom_path)


# --- The cart-shell protocol (ModCartShells' table of the game's own shells) ---
# The body is the one NES Game Pak (RetroCartridge's model table); only its colour
# is the ROM's.

## {palette, preset}: the NES palette and this ROM's shell in it.
static func cart_finish(systemid: String, rom_path: String, _model_path: String,
		pinned: String) -> Dictionary:
	return {"palette": SYSTEMID, "preset": preset_for_rom(rom_path, systemid, pinned)}
