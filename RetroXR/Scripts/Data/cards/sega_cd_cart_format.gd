## SegaCdCartFormat — a Backup RAM Cartridge for the Sega CD.
##
## Made at Sega's own 128 Kbit; a larger image someone brings keeps its size, and
## the core is told which size is seated.
class_name SegaCdCartFormat
extends SegaCdCardFormat


func id() -> String:
	return "sega_cd_ram_cart"


## Kega Fusion's name for the cartridge half, which keeps it apart from the
## unit's own .brm when a family is resolved from a filename alone.
func extension() -> String:
	return "crm"


func default_size() -> int:
	return SegaCdBram.CART_SIZE


func device_noun() -> String:
	return "Backup RAM Cartridge"
