## N64SaveDb — which N64 games save to a Controller Pak, from the core's own ROM
## database (see N64SaveDbTable and Tools/gen_n64_save_db.py).
##
## Only a yes is an answer. The database marks no game as never using a pak, so
## a game this does not know is unknown, not pak-less.
class_name N64SaveDb

## Big-endian ROM magic, and the two byte orders dumps also come in.
const MAGIC_Z64 := [0x80, 0x37, 0x12, 0x40]
const MAGIC_V64 := [0x37, 0x80, 0x40, 0x12]
const MAGIC_N64 := [0x40, 0x12, 0x37, 0x80]
## The header's CRC pair sits here, and is all of the header the lookup needs.
const HEADER_BYTES := 0x18


## By MD5, which is what RomM reports. The database hashes the ROM in .z64 byte
## order, so a .v64 or .n64 upload does not match.
static func uses_pak_md5(md5: String) -> bool:
	return N64SaveDbTable.USES_PAK_MD5.has(md5.to_lower())


static func pak_only_md5(md5: String) -> bool:
	return N64SaveDbTable.PAK_ONLY_MD5.has(md5.to_lower())


## By a ROM on disk, read by its header rather than hashed whole: 24 bytes in any
## of the three byte orders, where an MD5 would read up to 64 MB.
static func uses_pak_rom(rom_path: String) -> bool:
	return N64SaveDbTable.USES_PAK_CRC.has(header_crc_key(_read_header(rom_path)))


static func pak_only_rom(rom_path: String) -> bool:
	return N64SaveDbTable.PAK_ONLY_CRC.has(header_crc_key(_read_header(rom_path)))


## "CRC1-CRC2" in upper-case hex from a ROM's first bytes, or "" when they are
## not an N64 header in any byte order.
static func header_crc_key(header: PackedByteArray) -> String:
	if header.size() < HEADER_BYTES:
		return ""
	var head := [header[0], header[1], header[2], header[3]]
	# The byte of the big-endian word each position is read from.
	var order: Array
	if head == MAGIC_Z64:
		order = [0, 1, 2, 3]
	elif head == MAGIC_V64:
		order = [1, 0, 3, 2]
	elif head == MAGIC_N64:
		order = [3, 2, 1, 0]
	else:
		return ""
	return "%08X-%08X" % [_word(header, 0x10, order), _word(header, 0x14, order)]


static func _word(header: PackedByteArray, at: int, order: Array) -> int:
	return (header[at + order[0]] << 24) | (header[at + order[1]] << 16) \
		| (header[at + order[2]] << 8) | header[at + order[3]]


static func _read_header(rom_path: String) -> PackedByteArray:
	if rom_path.is_empty():
		return PackedByteArray()
	var f := FileAccess.open(rom_path, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	var bytes := f.get_buffer(HEADER_BYTES)
	f.close()
	return bytes
