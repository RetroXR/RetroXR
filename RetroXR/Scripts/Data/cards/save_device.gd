## SaveDevice — where a game keeps its saves when it is not in the game itself.
##
## A PlayStation, PlayStation 2 or GameCube disc saves to a memory card, a
## Dreamcast disc to a VMU, and many N64 cartridges to a Controller Pak alone. For
## those a save of the game's own is a file nothing reads, so the Saves menu says
## where to look instead of offering to start one.
class_name SaveDevice


## The card format this game saves to instead of a save of its own, or null when
## the game keeps its own save or the answer is not known.
static func format_for(systemid: String, rom_path: String) -> CardFormat:
	var info := SystemInfo.for_system(systemid)
	if info != null and not info.save_device.is_empty():
		return CardFormats.for_family(info.save_device)
	# The one system that decides game by game: an N64 cartridge may keep its own
	# save, a pak's, or both.
	if systemid == "nintendo_64" and N64SaveDb.pak_only_rom(rom_path):
		return CardFormats.for_family(ControllerPak.FAMILY)
	return null


## What the Saves menu shows in place of starting a save, or "".
static func note_for(systemid: String, rom_path: String, game_label: String) -> String:
	var fmt := format_for(systemid, rom_path)
	if fmt == null:
		return ""
	var info := SystemInfo.for_system(systemid)
	var medium := "cartridge" if info == null \
		or info.media_type == SystemInfo.MediaType.CARTRIDGE else "disc"
	var noun := fmt.device_noun()
	var home := "the console" if fmt.device_home() == "console" else "a controller"
	var game := game_label if not game_label.is_empty() else "This game"
	return "%s saves to a %s, not the %s.\n\nPut a %s in %s before you play. Its saves are managed from the %s itself." \
		% [game, noun, medium, noun, home, noun]
