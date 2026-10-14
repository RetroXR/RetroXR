## ThreeDoMemoryFormat — the 32 KB of NVRAM inside a 3DO.
##
## Belongs to the console rather than to a card anyone carries, so it has no shelf
## of its own; the image is kept per console and managed from its Saves tab, as a
## Saturn's System Memory is.
##
## NVRAM's block is a byte, so the unit here is a byte: a save is the bytes its
## file occupies, and free is what the OS reports -- every free block less the
## 64-byte header a file made there would need. Forwards to ThreeDoNvram.
class_name ThreeDoMemoryFormat
extends CardFormat


func id() -> String:
	return "3do_nvram"


func label() -> String:
	return "3DO"


func extension() -> String:
	return "nvram"


func save_extension() -> String:
	return "3dosav"


func romm_systemid() -> String:
	return "3do"


## Other frontends upload the whole image rather than one save: Opera's own files
## are <game>.<n>.srm and nvram.<n>.srm, and before that 3DO.nvram.
func romm_save_extensions() -> PackedStringArray:
	return PackedStringArray([save_extension(), "srm", "nvram"])


func unit_noun() -> String:
	return "byte"


## The OS's own name for it, and Opera's.
func device_noun() -> String:
	return "NVRAM"


## Nothing to fit: the memory is inside the console.
func save_device_note(game: String, medium: String) -> String:
	return "%s saves to the 3DO's NVRAM, not the %s.\n\nIts saves are managed from the console's Saves tab." \
		% [game, medium]


func total_blocks(data: PackedByteArray) -> int:
	return ThreeDoNvram.capacity(data)


func blocks_for_size(byte_size: int) -> int:
	return maxi(1, byte_size - ThreeDoNvram.SAVE_HEADER)


func blank_image() -> PackedByteArray:
	return ThreeDoNvram.blank_image()


func is_card_image(data: PackedByteArray) -> bool:
	return ThreeDoNvram.is_card_image(data)


## The block handle is where the file starts. A 3DO file has a name and nothing
## else to show, so the name is the title.
func list_saves(data: PackedByteArray, _with_icons := true) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in ThreeDoNvram.list_files(data):
		out.append({"name": str(e["name"]), "serial": "", "title": str(e["name"]),
			"blocks": int(e["blocks"]), "block": int(e["at"]), "icons": []})
	return out


func block_of(data: PackedByteArray, name: String) -> int:
	return ThreeDoNvram.index_of(data, name)


func extract_save(data: PackedByteArray, first_block: int) -> PackedByteArray:
	for e: Dictionary in ThreeDoNvram.list_files(data):
		if int(e["at"]) != first_block:
			continue
		var contents := ThreeDoNvram.read_file(data, first_block)
		if contents.size() != int(e["blocks"]) or int(e["bytes"]) > contents.size():
			return PackedByteArray()
		return ThreeDoNvram.make_save(str(e["name"]), int(e["type"]), int(e["unique"]),
			int(e["bytes"]), contents)
	return PackedByteArray()


func is_save_file(bytes: PackedByteArray) -> bool:
	return ThreeDoNvram.is_save(bytes)


## One save, or every save on a whole image someone uploaded instead.
func saves_in_download(bytes: PackedByteArray) -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	if ThreeDoNvram.is_save(bytes):
		out.append(bytes)
	elif ThreeDoNvram.is_card_image(bytes):
		for e: Dictionary in ThreeDoNvram.list_files(bytes):
			var save := extract_save(bytes, int(e["at"]))
			if not save.is_empty():
				out.append(save)
	return out


func save_name(save: PackedByteArray) -> String:
	var parsed := ThreeDoNvram.parse_save(save)
	return str(parsed["name"]) if not parsed.is_empty() else ""


func insert_save(data: PackedByteArray, save: PackedByteArray) -> PackedByteArray:
	var parsed := ThreeDoNvram.parse_save(save)
	if parsed.is_empty():
		return PackedByteArray()
	return ThreeDoNvram.write_file(data, str(parsed["name"]), int(parsed["type"]),
		int(parsed["unique"]), int(parsed["bytes"]), parsed["contents"])


func delete_save(data: PackedByteArray, first_block: int) -> PackedByteArray:
	return ThreeDoNvram.delete_file(data, first_block)


func free_blocks(data: PackedByteArray) -> int:
	return ThreeDoNvram.free_bytes(data)
