## SaturnCartFormat — a Backup RAM Cartridge for the Sega Saturn, 512 KB.
class_name SaturnCartFormat
extends SaturnCardFormat


func id() -> String:
	return "sega_saturn_ram_cart"


## Beetle Saturn's name for the cartridge image.
func extension() -> String:
	return "bcr"


func default_size() -> int:
	return SaturnBram.CART_SIZE


func device_noun() -> String:
	return "Backup RAM Cartridge"
