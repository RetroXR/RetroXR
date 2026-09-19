## SegaCdCardFormat — what the Sega CD's internal memory and its Backup RAM
## Cartridge share: one layout (SegaCdBram), one single-save file, one RomM
## platform. The two families differ in size, extension and what they are called.
##
## Forwards to SegaCdBram. Nothing but the forwards belongs here.
class_name SegaCdCardFormat
extends CardFormat


## The image size a new one is made at.
func default_size() -> int:
	return SegaCdBram.INTERNAL_SIZE


func label() -> String:
	return "Sega CD"


func save_extension() -> String:
	return "scds"


func romm_systemid() -> String:
	return "segacd"


## Other frontends upload the whole image rather than one save.
func romm_save_extensions() -> PackedStringArray:
	return PackedStringArray([save_extension(), "brm"])


## Read from the image: a cartridge's size is a property of the cartridge.
func total_blocks(data: PackedByteArray) -> int:
	var size := data.size() if SegaCdBram.size_is_valid(data.size()) else default_size()
	@warning_ignore("integer_division")
	return size / SegaCdBram.BLOCK_SIZE - 3


## Whether a save is raw or protected is only known from its header, so this
## counts raw blocks: never more than it will take, so a row is not refused for
## room it does not need.
func blocks_for_size(byte_size: int) -> int:
	var data_bytes := maxi(0, byte_size - SegaCdBram.SCDS_HEADER)
	@warning_ignore("integer_division")
	return maxi(1, (data_bytes + SegaCdBram.RAW_BLOCK_DATA - 1) / SegaCdBram.RAW_BLOCK_DATA)


func blank_image() -> PackedByteArray:
	return SegaCdBram.blank_image(default_size())


func is_card_image(data: PackedByteArray) -> bool:
	return SegaCdBram.is_card_image(data)


## The block handle is the save's directory index. A save's name is the whole of
## what a Sega CD shows, so the title is that name with its padding turned back
## into spaces.
func list_saves(data: PackedByteArray, _with_icons := true) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var files := SegaCdBram.list_files(data)
	for k in files.size():
		var e := files[k]
		var name := str(e["name"])
		out.append({"name": name, "serial": "", "title": name.replace("_", " ").strip_edges(),
			"blocks": int(e["size"]), "block": k, "icons": []})
	return out


func block_of(data: PackedByteArray, name: String) -> int:
	return SegaCdBram.index_of(data, name)


func extract_save(data: PackedByteArray, first_block: int) -> PackedByteArray:
	var files := SegaCdBram.list_files(data)
	if first_block < 0 or first_block >= files.size():
		return PackedByteArray()
	var payload := SegaCdBram.read_file(data, first_block)
	if payload.is_empty():
		return PackedByteArray()
	var e := files[first_block]
	return SegaCdBram.make_save(str(e["name"]), int(e["mode"]), payload)


func is_save_file(bytes: PackedByteArray) -> bool:
	return SegaCdBram.is_save(bytes)


## One save, or every save on a whole image someone uploaded instead.
func saves_in_download(bytes: PackedByteArray) -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	if SegaCdBram.is_save(bytes):
		out.append(bytes)
	elif SegaCdBram.is_card_image(bytes):
		for k in SegaCdBram.list_files(bytes).size():
			var save := extract_save(bytes, k)
			if not save.is_empty():
				out.append(save)
	return out


func save_name(save: PackedByteArray) -> String:
	var parsed := SegaCdBram.parse_save(save)
	return (parsed["name"] as PackedByteArray).get_string_from_ascii() if not parsed.is_empty() else ""


func insert_save(data: PackedByteArray, save: PackedByteArray) -> PackedByteArray:
	var parsed := SegaCdBram.parse_save(save)
	if parsed.is_empty():
		return PackedByteArray()
	return SegaCdBram.write_file(data, parsed["name"], int(parsed["mode"]), parsed["payload"])


func delete_save(data: PackedByteArray, first_block: int) -> PackedByteArray:
	return SegaCdBram.delete_file(data, first_block)


func free_blocks(data: PackedByteArray) -> int:
	return SegaCdBram.free_blocks(data)
