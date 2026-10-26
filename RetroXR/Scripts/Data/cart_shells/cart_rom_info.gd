## CartRomInfo — what the cartridge shells (N64CartShell, SnesCartShell, NesCartShell,
## GbCartShell, GbaCartShell ...) read about a ROM: the bytes of its header, and
## what the scraper wrote for it.
##
## One gamelist cache for all of them, reloaded for a system when a scrape has
## rewritten its gamelist.json, and the one "nothing in the ROM saying" rule for
## a shell that picks by market.
class_name CartRomInfo
extends RefCounted

static var _gamelists := GamelistManager.new()
static var _gamelist_stamps := {}


## The first `count` bytes of the ROM file, or empty when there is no file.
static func read_bytes(rom_path: String, count: int) -> PackedByteArray:
	if rom_path.is_empty():
		return PackedByteArray()
	var f := FileAccess.open(rom_path, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	var bytes := f.get_buffer(count)
	f.close()
	return bytes


## The game the system's scraped gamelist lists this ROM under ({name, roms, ...}),
## or {}.
static func scraped_game(systemid: String, rom_path: String) -> Dictionary:
	if systemid.is_empty() or rom_path.is_empty():
		return {}
	var path := RomLibrary.rom_dir_for_system(systemid).path_join("gamelist.json")
	var stamp := FileAccess.get_modified_time(path) if FileAccess.file_exists(path) else 0
	if _gamelist_stamps.get(systemid, -1) != stamp:
		_gamelists.invalidate(systemid)
		_gamelist_stamps[systemid] = stamp
	return _gamelists.get_game_for_rom(systemid, rom_path)


## This ROM's own entry under its scraped game ({region, releasedate, ...}), or {}.
static func scraped_rom(systemid: String, rom_path: String) -> Dictionary:
	var game := scraped_game(systemid, rom_path)
	for rom: Dictionary in game.get("roms", []):
		if str(rom.get("path", "")).get_file() == rom_path.get_file():
			return rom
	return {}


## The market the ROM named, else -- nothing in the ROM saying -- the cartridge's
## pinned market, else the player's (RegionalNames.cart_market_or).
static func market_or_pinned(found: String, pinned := "") -> String:
	return found if not found.is_empty() else RegionalNames.cart_market_or(pinned)
