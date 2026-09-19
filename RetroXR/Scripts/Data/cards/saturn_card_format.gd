## SaturnCardFormat — what the Saturn's System Memory and its Backup RAM
## Cartridge share: one layout (SaturnBram), one single-save file, one RomM
## platform. The two families differ in size, extension and what they are called.
##
## Forwards to SaturnBram. Nothing but the forwards belongs here.
class_name SaturnCardFormat
extends CardFormat


## The image size a new one is made at.
func default_size() -> int:
	return SaturnBram.INTERNAL_SIZE


func label() -> String:
	return "Sega Saturn"


func save_extension() -> String:
	return "ssav"


func romm_systemid() -> String:
	return "saturn"


## Other frontends upload the whole image rather than one save.
func romm_save_extensions() -> PackedStringArray:
	return PackedStringArray([save_extension(), "srm", "bkr", "bcr"])


## Read from the image, falling back to the family's size for one not made yet.
func total_blocks(data: PackedByteArray) -> int:
	var size := data.size() if SaturnBram.size_is_valid(data.size()) else default_size()
	@warning_ignore("integer_division")
	return size / SaturnBram.block_size(size) - SaturnBram.RESERVED_BLOCKS


func blocks_for_size(byte_size: int) -> int:
	return SaturnBram.blocks_for_data(maxi(0, byte_size - SaturnBram.SAVE_HEADER),
		SaturnBram.block_size(default_size()))


func blank_image() -> PackedByteArray:
	return SaturnBram.blank_image(default_size())


func is_card_image(data: PackedByteArray) -> bool:
	return SaturnBram.is_card_image(data)


## The block handle is the save's first block. The comment is what the Saturn's
## own memory manager shows, so it is the title when there is one.
func list_saves(data: PackedByteArray, _with_icons := true) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in SaturnBram.list_files(data):
		var name := str(e["name"])
		var comment := str(e["comment"])
		out.append({"name": name, "serial": "",
			"title": comment if not comment.is_empty() else name,
			"blocks": int(e["blocks"]), "block": int(e["block"]), "icons": []})
	return out


func block_of(data: PackedByteArray, name: String) -> int:
	return SaturnBram.index_of(data, name)


func extract_save(data: PackedByteArray, first_block: int) -> PackedByteArray:
	for e: Dictionary in SaturnBram.list_files(data):
		if int(e["block"]) != first_block:
			continue
		var payload := SaturnBram.read_file(data, first_block)
		if payload.size() != int(e["size"]):
			return PackedByteArray()
		return SaturnBram.make_save(str(e["name"]), int(e["language"]),
			str(e["comment"]), int(e["date"]), payload)
	return PackedByteArray()


func is_save_file(bytes: PackedByteArray) -> bool:
	return SaturnBram.is_save(bytes)


## One save, or every save on a whole image someone uploaded instead.
func saves_in_download(bytes: PackedByteArray) -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	if SaturnBram.is_save(bytes):
		out.append(bytes)
	elif SaturnBram.is_card_image(bytes):
		for e: Dictionary in SaturnBram.list_files(bytes):
			var save := extract_save(bytes, int(e["block"]))
			if not save.is_empty():
				out.append(save)
	return out


func save_name(save: PackedByteArray) -> String:
	var parsed := SaturnBram.parse_save(save)
	return (parsed["name"] as PackedByteArray).get_string_from_ascii().strip_edges() \
		if not parsed.is_empty() else ""


func insert_save(data: PackedByteArray, save: PackedByteArray) -> PackedByteArray:
	var parsed := SaturnBram.parse_save(save)
	if parsed.is_empty():
		return PackedByteArray()
	return SaturnBram.write_file(data, parsed["name"], int(parsed["language"]),
		parsed["comment"], int(parsed["date"]), parsed["payload"])


func delete_save(data: PackedByteArray, first_block: int) -> PackedByteArray:
	return SaturnBram.delete_file(data, first_block)


func free_blocks(data: PackedByteArray) -> int:
	return SaturnBram.free_blocks(data)
