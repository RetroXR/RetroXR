## XboxHddSaves — one game's saves, lifted out of an Xbox hard disk image.
##
## Every Xbox game saves to the console's hard disk, so under xemu every game's
## saves are inside ONE file, <save>/xemu/xemu/xbox_hdd.qcow2. That file cannot
## be what RomM backs up: a record holds one rom_id and the games would fight
## over it, exactly as they would over a memory card (RommSaveSync.push_card_save
## says the same), and it is ~300 MB once a game has built its cache. What a game
## owns on that disk is two folders on the data partition, E:, named for its
## title id:
##
##     E:\UDATA\<title id>\    the saves a player sees, one folder each, with
##                             TitleMeta.xbx and the save's own SaveMeta.xbx
##     E:\TDATA\<title id>\    what the game keeps for itself: profiles, settings
##
## Those two trees are lifted into one archive, "UDATA/<title id>/…" and
## "TDATA/<title id>/…" inside it, which is a few hundred KB and belongs to
## exactly one game. The title id is IN the paths — the layout Xbox save archives
## already use — so the archive says whose it is, and a Memory Unit can take its
## UDATA half as it stands (XboxMemoryUnit.saves_in_download).
##
## UPLOAD-ONLY, like a card save. Putting one back means writing FATX — cluster
## allocation, directory growth — into an image a parked core may still hold.
## Until that is built and proven the server is a backup and never a source.
##
## The E: partition's place is fixed by the Xbox kernel, not read from a table:
## the retail disk has no partition table at all.
class_name XboxHddSaves
extends RefCounted

const DATA_PARTITION_OFFSET := 0xABE80000
const DATA_PARTITION_SIZE := 0x131F00000
const SAVE_ROOTS: PackedStringArray = ["UDATA", "TDATA"]
const ARCHIVE_EXT := "zip"

## Past these a lift is refused, not truncated. Saves run from a few KB to a few
## MB; the ceiling is for a disk that is not what it claims to be.
const MAX_FILES := 4096
const MAX_BYTES := 128 * 1024 * 1024

## What the core names the disk, inside the folder it makes in its save dir.
const CORE := "xemu"
const HDD_FILE := "xbox_hdd.qcow2"


## Where the running core keeps the disk it writes to: a copy it makes, on first
## use, of the one in its system folder.
static func hdd_path() -> String:
	return SramPaths.core_save_dir(CORE).path_join(CORE).path_join(HDD_FILE)


## The files a title keeps on the disk at `hdd`.
##
## {ok, error, files} — `files` is "UDATA/<title id>/<save>/<name>" -> bytes, and empty with
## ok TRUE for a game that has saved nothing yet. ok is false only when the disk
## could not be read or did not check out, which is the case that must not be
## mistaken for "no saves" and uploaded over a good backup.
static func lift(hdd: String, title_id: String) -> Dictionary:
	if not title_id.is_valid_hex_number() or title_id.length() != 8:
		return _failed("'%s' is not a title id" % title_id)
	var why: Array = []
	var image := Qcow2Image.open(hdd, why)
	if image == null:
		return _failed(str(why[0]))
	var volume := FatxVolume.open(image, DATA_PARTITION_OFFSET, DATA_PARTITION_SIZE, why)
	if volume == null:
		image.close()
		return _failed(str(why[0]))

	var files: Dictionary = {}
	var budget := {"files": MAX_FILES, "bytes": MAX_BYTES}
	for root: String in SAVE_ROOTS:
		var root_entry := volume.find(FatxVolume.ROOT_CLUSTER, root)
		if not volume.error.is_empty():
			image.close()
			return _failed(volume.error)
		if root_entry.is_empty() or not bool(root_entry["dir"]):
			continue
		var title := volume.find(int(root_entry["cluster"]), title_id)
		if not volume.error.is_empty():
			image.close()
			return _failed(volume.error)
		if title.is_empty() or not bool(title["dir"]):
			continue
		if not volume.read_tree(int(title["cluster"]), "%s/%s/" % [root, title_id.to_lower()],
				files, budget):
			image.close()
			return _failed(volume.error)
	image.close()
	return {"ok": true, "error": "", "files": files}


static func _failed(error: String) -> Dictionary:
	return {"ok": false, "error": error, "files": {}}


## Total size of what lift() returned.
static func byte_count(files: Dictionary) -> int:
	var n := 0
	for path: String in files:
		n += (files[path] as PackedByteArray).size()
	return n


# --- The archive --------------------------------------------------------------

## `files` as a .zip whose bytes depend on nothing but `files`.
##
## Written here rather than with ZIPPacker, which stamps every entry with the
## time it was packed: the md5 would move on every power-off, and RommSaveSync
## decides whether to upload by that md5 — a game that saved nothing would be
## re-sent each time. So: paths sorted, entries STORED (saves are small, and a
## deflate stream is one more thing that may differ between two builds), and one
## fixed timestamp, 1980-01-01, the earliest a zip can say.
static func pack(files: Dictionary) -> PackedByteArray:
	var paths: Array = files.keys()
	paths.sort()
	var out := PackedByteArray()
	var central := PackedByteArray()
	for path: String in paths:
		var data: PackedByteArray = files[path]
		var name := path.to_utf8_buffer()
		var crc := _crc32(data)
		var local_at := out.size()

		var local := PackedByteArray()
		local.resize(30)
		local.encode_u32(0, 0x04034b50)
		local.encode_u16(4, 20)          # version needed
		local.encode_u16(6, 0x0800)      # names are UTF-8
		local.encode_u16(8, 0)           # stored
		local.encode_u16(10, 0)          # time
		local.encode_u16(12, 0x0021)     # date: 1980-01-01
		local.encode_u32(14, crc)
		local.encode_u32(18, data.size())
		local.encode_u32(22, data.size())
		local.encode_u16(26, name.size())
		local.encode_u16(28, 0)
		out.append_array(local)
		out.append_array(name)
		out.append_array(data)

		var entry := PackedByteArray()
		entry.resize(46)
		entry.encode_u32(0, 0x02014b50)
		entry.encode_u16(4, 20)          # version made by
		entry.encode_u16(6, 20)
		entry.encode_u16(8, 0x0800)
		entry.encode_u16(10, 0)
		entry.encode_u16(12, 0)
		entry.encode_u16(14, 0x0021)
		entry.encode_u32(16, crc)
		entry.encode_u32(20, data.size())
		entry.encode_u32(24, data.size())
		entry.encode_u16(28, name.size())
		entry.encode_u32(42, local_at)
		central.append_array(entry)
		central.append_array(name)

	var end := PackedByteArray()
	end.resize(22)
	end.encode_u32(0, 0x06054b50)
	end.encode_u16(8, paths.size())
	end.encode_u16(10, paths.size())
	end.encode_u32(12, central.size())
	end.encode_u32(16, out.size())
	out.append_array(central)
	out.append_array(end)
	return out


## The files in an archive, as {path -> bytes}, or {} when it is not one.
##
## Through ZIPReader and a scratch file, because what comes back from a server
## need not be an archive pack() made: anyone's Xbox save zip is deflated, and
## the engine reads those only from a path.
static func unpack(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 22 or bytes.decode_u32(0) != 0x04034b50:
		return {}
	var scratch := OS.get_user_data_dir().path_join("__xbox_unpack_%d_%d.zip"
		% [OS.get_process_id(), Time.get_ticks_usec()])
	var f := FileAccess.open(scratch, FileAccess.WRITE)
	if f == null:
		return {}
	f.store_buffer(bytes)
	f.close()
	var out: Dictionary = {}
	var reader := ZIPReader.new()
	if reader.open(scratch) == OK:
		for path: String in reader.get_files():
			if not path.ends_with("/"):
				out[path.replace("\\", "/")] = reader.read_file(path)
		reader.close()
	DirAccess.remove_absolute(scratch)
	return out


## CRC-32 of `data`, taken from the trailer of its gzip stream: the engine has
## no CRC-32 of its own to call, a gzip member ends with exactly that, and a
## byte loop in GDScript over a few MB of save is seconds on a Quest.
static func _crc32(data: PackedByteArray) -> int:
	if data.is_empty():
		return 0
	var gz := data.compress(FileAccess.COMPRESSION_GZIP)
	if gz.size() < 8:
		return 0
	return gz.decode_u32(gz.size() - 8)
