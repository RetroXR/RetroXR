## XboxDisc — which game an Xbox disc image is, read off the disc.
##
## An Xbox save is filed on the hard disk under its game's TITLE ID, eight hex
## digits (Halo is 4d530004: "MS", game 4). The id is in the certificate of the
## disc's default.xbe, so finding a game's saves starts here:
##
##     XDVDFS volume descriptor, at sector 32 (0x10000) of the game partition:
##         "MICROSOFT*XBOX*MEDIA", root directory sector u32, root size u32
##     a directory is a BINARY TREE of entries, ordered by name without case:
##         left u16, right u16   offsets into the directory, in 4-byte units
##         sector u32, size u32, attributes u8, name length u8, name
##     default.xbe:
##         "XBEH", base address u32 at +0x104, certificate ADDRESS u32 at +0x118
##         certificate: title id u32 at +0x08, title name at +0x0C (40 UTF-16)
##
## The game partition starts the file in an XISO (what extract-xiso writes, and
## what the xemu core wants) and 0x18300000 in on a full redump image, behind the
## DVD-Video partition a player showed to anything that was not an Xbox. Both are
## tried: this is about naming a game, not about whether the core will run it.
class_name XboxDisc
extends RefCounted

const VOLUME_MAGIC := "MICROSOFT*XBOX*MEDIA"
const SECTOR := 2048
const VOLUME_SECTOR := 32
## Where the game partition starts: an XISO, then a redump image.
const PARTITION_OFFSETS: Array[int] = [0, 0x18300000]
const BOOT_FILE := "default.xbe"

## A directory tree deeper than this is a loop, not a directory.
const _MAX_TREE_STEPS := 4096


## {title_id, name} of the game on `path`, or {} when it is not an Xbox disc.
## `title_id` is eight lowercase hex digits, as the hard disk spells the folder.
static func title_of(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	for base: int in PARTITION_OFFSETS:
		var found := _title_in(f, base)
		if not found.is_empty():
			f.close()
			return found
	f.close()
	return {}


static func _title_in(f: FileAccess, base: int) -> Dictionary:
	var at := base + VOLUME_SECTOR * SECTOR
	if at + 28 > f.get_length():
		return {}
	f.seek(at)
	var volume := f.get_buffer(28)
	if volume.slice(0, 20).get_string_from_ascii() != VOLUME_MAGIC:
		return {}
	var boot := _find(f, base, volume.decode_u32(20), volume.decode_u32(24), BOOT_FILE)
	if boot.is_empty():
		return {}

	var xbe_at := base + int(boot["sector"]) * SECTOR
	f.seek(xbe_at)
	var head := f.get_buffer(0x11c)
	if head.size() < 0x11c or head.slice(0, 4).get_string_from_ascii() != "XBEH":
		return {}
	# An ADDRESS in the loaded image, not a file offset: the headers are mapped
	# at the base address, so the difference is where it sits in the file.
	var cert := head.decode_u32(0x118) - head.decode_u32(0x104)
	if cert < 0 or cert + 0x5c > int(boot["size"]):
		return {}
	f.seek(xbe_at + cert)
	var certificate := f.get_buffer(0x5c)
	if certificate.size() < 0x5c:
		return {}
	var name := certificate.slice(0x0c, 0x5c).get_string_from_utf16()
	return {
		"title_id": "%08x" % certificate.decode_u32(0x08),
		"name": name.strip_edges(),
	}


## {sector, size} of `want` in the directory at `sector`, or {}.
static func _find(f: FileAccess, base: int, sector: int, size: int, want: String) -> Dictionary:
	if size <= 0 or size > (1 << 24):
		return {}
	f.seek(base + sector * SECTOR)
	var dir := f.get_buffer(size)
	if dir.size() != size:
		return {}
	var at := 0
	for _step: int in _MAX_TREE_STEPS:
		if at + 14 > dir.size():
			return {}
		var left := dir.decode_u16(at)
		if left == 0xffff:
			return {}
		var name_len := dir[at + 13]
		if at + 14 + name_len > dir.size():
			return {}
		var name := dir.slice(at + 14, at + 14 + name_len).get_string_from_ascii()
		var order := want.nocasecmp_to(name)
		if order == 0:
			return {"sector": dir.decode_u32(at + 4), "size": dir.decode_u32(at + 8)}
		var next := left if order < 0 else dir.decode_u16(at + 2)
		if next == 0:
			return {}
		at = next * 4
	return {}
