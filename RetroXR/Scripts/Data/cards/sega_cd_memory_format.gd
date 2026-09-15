## SegaCdMemoryFormat — the 8 KB of backup memory inside a Sega CD.
##
## Belongs to the unit rather than to a card anyone carries, so it has no shelf of
## its own; the image is kept per unit and managed from the console's Saves tab.
class_name SegaCdMemoryFormat
extends SegaCdCardFormat


func id() -> String:
	return "sega_cd_memory"


func extension() -> String:
	return "brm"


func device_noun() -> String:
	return "Backup Memory"


## Nothing to fit: the memory is inside the unit, and a cartridge is optional.
func save_device_note(game: String, medium: String) -> String:
	return "%s saves to the Sega CD's backup memory or a Backup RAM Cartridge, not the %s.\n\nIts saves are managed from the console's Saves tab." \
		% [game, medium]
