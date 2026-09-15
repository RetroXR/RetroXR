## SaturnMemoryFormat — the 32 KB of backup memory inside a Sega Saturn.
##
## Belongs to the console rather than to a card anyone carries, so it has no shelf
## of its own; the image is kept per console and managed from its Saves tab.
class_name SaturnMemoryFormat
extends SaturnCardFormat


func id() -> String:
	return "sega_saturn_memory"


func extension() -> String:
	return "bkr"


## The Saturn's own name for it, in its memory manager.
func device_noun() -> String:
	return "System Memory"


## Nothing to fit: the memory is inside the console, and a cartridge is optional.
func save_device_note(game: String, medium: String) -> String:
	return "%s saves to the Saturn's System Memory or a Backup RAM Cartridge, not the %s.\n\nIts saves are managed from the console's Saves tab." \
		% [game, medium]
