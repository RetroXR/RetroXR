## XboxMemoryUnit — the 8 MB card that goes in the top of an Xbox controller.
##
## The image is a bare FATX volume, no partition table: superblock at 0, one FAT,
## then 2 KB clusters with the root directory in cluster 1 (FatxVolume has the
## layout). 4,096 clusters, so the FAT is 16-bit. Saves are filed as they are on
## the console's hard disk, without the hard disk's TDATA:
##
##     UDATA\<title id>\TitleMeta.xbx, TitleImage.xbx, SaveImage.xbx   the GAME's
##     UDATA\<title id>\<save id>\SaveMeta.xbx, <the save's files>      one SAVE
##
## so one save is one <save id> FOLDER, and the three title files beside it are
## shared by every save of that game. `name` is "<title id>/<save id>".
##
## ONE SAVE AS A FILE is an archive of exactly that tree, title files included —
## "UDATA/<title id>/…", the layout every Xbox save archive already uses, and the
## one XboxHddSaves lifts off the hard disk in. That is deliberate: a backup
## lifted from the hard disk goes INTO a Memory Unit here (saves_in_download
## splits it per save), and the console copies it home from there. Nothing in
## RetroXR writes the hard disk image.
##
## What xemu formats a new unit with is not byte-pinnable — its volume id is
## rand() — so a blank is pinned by structure: the same superblock fields, the
## same first FAT word, zeros to 8 MB.
##
## Sizes are counted in the console's own BLOCKS of 16 KB, the unit its Memory
## screen shows, not in the volume's 2 KB clusters.
class_name XboxMemoryUnit
extends RefCounted

const SIZE := 8 * 1024 * 1024
const SECTORS_PER_CLUSTER := 4
const BLOCK_BYTES := 16 * 1024
const SAVE_ROOT := "UDATA"
const TITLE_FILES: PackedStringArray = ["TitleMeta.xbx", "TitleImage.xbx", "SaveImage.xbx"]
const SAVE_META := "SaveMeta.xbx"
const TITLE_META := "TitleMeta.xbx"

## 2026-01-01 00:00:00 in FATX's packed form: year since 2000 (7 bits), month
## (4), day (5), hour (5), minute (6), seconds/2 (5). Fixed, so inserting the
## same save twice gives the same image.
const _STAMP := (26 << 25) | (1 << 21) | (1 << 16)

const _END16 := 0xffff
const _END32 := 0xffffffff


# --- Reading ------------------------------------------------------------------

static func _volume(data: PackedByteArray) -> FatxVolume:
	if data.size() != SIZE:
		return null
	return FatxVolume.open(XboxRawImage.of(data), 0, SIZE)


static func blank_image(volume_id: int = 0) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(SIZE)
	for i: int in FatxVolume.HEADER_SIZE:
		out[i] = 0xff
	out.encode_u32(0, 0x58544146)            # "FATX"
	out.encode_u32(4, volume_id if volume_id != 0 else randi())
	out.encode_u32(8, SECTORS_PER_CLUSTER)
	out.encode_u32(12, FatxVolume.ROOT_CLUSTER)
	out.encode_u16(16, 0)
	# Media descriptor, and the root directory's one cluster: end of chain.
	out.encode_u32(FatxVolume.HEADER_SIZE, 0xfffffff8)
	return out


static func is_card_image(data: PackedByteArray) -> bool:
	var volume := _volume(data)
	if volume == null:
		return false
	volume.list_dir(FatxVolume.ROOT_CLUSTER)
	return volume.error.is_empty()


## Does the WHOLE tree walk — every directory, every chain, every file's length?
## is_card_image asks only about the root, which is enough to tell a unit from
## some other file and not enough to accept one read out from under a console
## that may be half way through writing a save.
static func is_consistent(data: PackedByteArray) -> bool:
	var volume := _volume(data)
	if volume == null:
		return false
	var files: Dictionary = {}
	return volume.read_tree(FatxVolume.ROOT_CLUSTER, "", files, {"files": 8192, "bytes": SIZE})


## Every save, as CardFormat.list_saves describes them. `block` is the first
## cluster of the save's folder.
static func list_saves(data: PackedByteArray) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var volume := _volume(data)
	if volume == null:
		return out
	var root := volume.find(FatxVolume.ROOT_CLUSTER, SAVE_ROOT)
	if root.is_empty() or not bool(root["dir"]):
		return out
	for title: Dictionary in volume.list_dir(int(root["cluster"])):
		if not bool(title["dir"]):
			continue
		var title_id := str(title["name"]).to_lower()
		var entries := volume.list_dir(int(title["cluster"]))
		var game := ""
		for e: Dictionary in entries:
			if not bool(e["dir"]) and str(e["name"]).nocasecmp_to(TITLE_META) == 0:
				game = meta_value(volume.read_file(e), "TitleName")
		for e: Dictionary in entries:
			if not bool(e["dir"]):
				continue
			var files: Dictionary = {}
			var budget := {"files": 1024, "bytes": SIZE}
			if not volume.read_tree(int(e["cluster"]), "", files, budget):
				continue
			var label := ""
			for path: String in files:
				if path.nocasecmp_to(SAVE_META) == 0:
					label = meta_value(files[path], "Name")
			var bytes := 0
			for path: String in files:
				bytes += (files[path] as PackedByteArray).size()
			out.append({
				"name": "%s/%s" % [title_id, str(e["name"])],
				"serial": title_id,
				"title": label if not label.is_empty() else game,
				"game": game,
				"blocks": blocks_for_size(bytes),
				"block": int(e["cluster"]),
				"icons": [],
			})
	return out


## "Key=Value" out of a TitleMeta.xbx or SaveMeta.xbx: UTF-16, one pair a line,
## with a BOM on some and not on others.
static func meta_value(meta: PackedByteArray, key: String) -> String:
	if meta.size() < 2:
		return ""
	var text := meta.get_string_from_utf16()
	for line: String in text.split("\n"):
		var clean := line.strip_edges().trim_prefix("﻿")
		if clean.begins_with(key + "="):
			return clean.substr(key.length() + 1).strip_edges()
	return ""


static func blocks_for_size(byte_size: int) -> int:
	@warning_ignore("integer_division")
	return maxi(1, (byte_size + BLOCK_BYTES - 1) / BLOCK_BYTES)


static func total_blocks(data: PackedByteArray) -> int:
	var volume := _volume(data)
	if volume == null:
		@warning_ignore("integer_division")
		return SIZE / BLOCK_BYTES
	@warning_ignore("integer_division")
	return (SIZE - volume.data_offset()) / BLOCK_BYTES


static func free_blocks(data: PackedByteArray) -> int:
	var volume := _volume(data)
	if volume == null:
		return 0
	@warning_ignore("integer_division")
	return _free_clusters(data, volume).size() * volume.cluster_size() / BLOCK_BYTES


static func block_of(data: PackedByteArray, name: String) -> int:
	for s: Dictionary in list_saves(data):
		if str(s["name"]).nocasecmp_to(name) == 0:
			return int(s["block"])
	return -1


# --- One save as a file -------------------------------------------------------

## The save whose folder starts at `first_cluster`, as an archive of
## "UDATA/<title id>/…": the title's own files and that one save folder.
static func extract_save(data: PackedByteArray, first_cluster: int) -> PackedByteArray:
	var volume := _volume(data)
	if volume == null:
		return PackedByteArray()
	var root := volume.find(FatxVolume.ROOT_CLUSTER, SAVE_ROOT)
	if root.is_empty():
		return PackedByteArray()
	for title: Dictionary in volume.list_dir(int(root["cluster"])):
		if not bool(title["dir"]):
			continue
		var prefix := "%s/%s/" % [SAVE_ROOT, str(title["name"]).to_lower()]
		var entries := volume.list_dir(int(title["cluster"]))
		for e: Dictionary in entries:
			if not bool(e["dir"]) or int(e["cluster"]) != first_cluster:
				continue
			var files: Dictionary = {}
			for t: Dictionary in entries:
				if not bool(t["dir"]):
					files[prefix + str(t["name"])] = volume.read_file(t)
			var budget := {"files": 1024, "bytes": SIZE}
			if not volume.read_tree(first_cluster, prefix + str(e["name"]) + "/", files, budget):
				return PackedByteArray()
			return XboxHddSaves.pack(files)
	return PackedByteArray()


## {path -> bytes} of an archive made of "UDATA/<8 hex>/…" entries and nothing
## else, or {} — which is what any other zip, and anything that is not a zip, is.
static func read_archive(bytes: PackedByteArray) -> Dictionary:
	var files := XboxHddSaves.unpack(bytes)
	if files.is_empty():
		return {}
	var saves: Dictionary = {}
	for path: String in files:
		var parts := path.split("/")
		if parts.size() < 3:
			return {}
		# TDATA rides along in a hard disk lift; a Memory Unit has nowhere for it.
		if parts[0] == "TDATA":
			continue
		if parts[0] != SAVE_ROOT or parts[1].length() != 8 or not parts[1].is_valid_hex_number():
			return {}
		for piece: String in parts:
			if piece.is_empty() or piece == "." or piece == ".." or piece.length() > FatxVolume.NAME_MAX:
				return {}
		saves[path] = files[path]
	return saves


static func is_save_file(bytes: PackedByteArray) -> bool:
	return save_names(read_archive(bytes)).size() == 1


## "<title id>/<save id>" of every save folder in an archive's files.
static func save_names(files: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for path: String in files:
		var parts := path.split("/")
		if parts.size() >= 4:
			var name := "%s/%s" % [parts[1].to_lower(), parts[2]]
			if not out.has(name):
				out.append(name)
	return out


static func save_name(save: PackedByteArray) -> String:
	var names := save_names(read_archive(save))
	return names[0] if names.size() == 1 else ""


## An archive of several saves — a hard disk lift — as one archive per save,
## each carrying its title's files.
static func saves_in_download(bytes: PackedByteArray) -> Array[PackedByteArray]:
	var out: Array[PackedByteArray] = []
	var files := read_archive(bytes)
	for name: String in save_names(files):
		var title_id := name.get_slice("/", 0)
		var save_prefix := "%s/%s/%s/" % [SAVE_ROOT, title_id, name.get_slice("/", 1)]
		var one: Dictionary = {}
		for path: String in files:
			var parts := path.split("/")
			if parts[1].to_lower() != title_id:
				continue
			if parts.size() == 3 or path.to_lower().begins_with(save_prefix.to_lower()):
				one["%s/%s/%s" % [SAVE_ROOT, title_id, "/".join(parts.slice(2))]] = files[path]
		out.append(XboxHddSaves.pack(one))
	return out


# --- Writing ------------------------------------------------------------------

## `data` with one save archive written into it. Empty when the archive is not
## one save, a save of that name is already there, or it does not fit.
static func insert_save(data: PackedByteArray, save: PackedByteArray) -> PackedByteArray:
	var files := read_archive(save)
	var names := save_names(files)
	if names.size() != 1 or block_of(data, names[0]) >= 0:
		return PackedByteArray()
	var out := data.duplicate()
	var paths: Array = files.keys()
	paths.sort()
	for path: String in paths:
		var parts := path.split("/")
		var dir := FatxVolume.ROOT_CLUSTER
		for i: int in parts.size() - 1:
			dir = _ensure_dir(out, dir, parts[i])
			if dir < 0:
				return PackedByteArray()
		# The title's own files are shared: the first save of a game brings
		# them, and a later one must not be refused for finding them there.
		var volume := _volume(out)
		if not volume.find(dir, parts[parts.size() - 1]).is_empty():
			continue
		if not _write_file(out, dir, parts[parts.size() - 1], files[path]):
			return PackedByteArray()
	return out


## `data` without the save whose folder starts at `first_cluster`, and without
## its game's folder once that was the last save in it — as the console's own
## Memory screen leaves it.
static func delete_save(data: PackedByteArray, first_cluster: int) -> PackedByteArray:
	var volume := _volume(data)
	if volume == null:
		return PackedByteArray()
	var root := volume.find(FatxVolume.ROOT_CLUSTER, SAVE_ROOT)
	if root.is_empty():
		return PackedByteArray()
	for title: Dictionary in volume.list_dir(int(root["cluster"])):
		if not bool(title["dir"]):
			continue
		var entries := volume.list_dir(int(title["cluster"]))
		for e: Dictionary in entries:
			if not bool(e["dir"]) or int(e["cluster"]) != first_cluster:
				continue
			var out := data.duplicate()
			if not _remove(out, e):
				return PackedByteArray()
			var saves_left := 0
			for other: Dictionary in entries:
				if bool(other["dir"]) and int(other["cluster"]) != first_cluster:
					saves_left += 1
			if saves_left == 0 and not _remove(out, title):
				return PackedByteArray()
			return out
	return PackedByteArray()


## Free everything under an entry, then the entry itself.
static func _remove(data: PackedByteArray, entry: Dictionary) -> bool:
	var volume := _volume(data)
	if bool(entry["dir"]):
		for child: Dictionary in volume.list_dir(int(entry["cluster"])):
			if not _remove(data, child):
				return false
		volume = _volume(data)
	if int(entry["cluster"]) >= FatxVolume.ROOT_CLUSTER:
		var chain := volume.chain_of(int(entry["cluster"]))
		if not volume.error.is_empty():
			return false
		for c: int in chain:
			_set_fat(data, volume, c, 0)
	var at := volume.data_offset() + (int(entry["at_cluster"]) - 1) * volume.cluster_size() \
		+ int(entry["at"])
	data[at] = 0xe5
	return true


static func _free_clusters(data: PackedByteArray, volume: FatxVolume) -> PackedInt64Array:
	var out := PackedInt64Array()
	# The clusters that exist are the ones the image has room for past the FAT,
	# which is fewer than the FAT has entries for.
	@warning_ignore("integer_division")
	var last := (data.size() - volume.data_offset()) / volume.cluster_size()
	for c: int in range(FatxVolume.ROOT_CLUSTER + 1, last + 1):
		if _get_fat(data, volume, c) == 0:
			out.append(c)
	return out


static func _get_fat(data: PackedByteArray, volume: FatxVolume, c: int) -> int:
	if volume.is_wide():
		return data.decode_u32(volume.fat_offset() + c * 4)
	return data.decode_u16(volume.fat_offset() + c * 2)


static func _set_fat(data: PackedByteArray, volume: FatxVolume, c: int, value: int) -> void:
	if volume.is_wide():
		data.encode_u32(volume.fat_offset() + c * 4, value & _END32)
	else:
		data.encode_u16(volume.fat_offset() + c * 2, value & _END16)


## A chain of `count` free clusters, linked and ended, or empty when there are
## not that many.
static func _allocate(data: PackedByteArray, volume: FatxVolume, count: int) -> PackedInt64Array:
	var free := _free_clusters(data, volume)
	if count <= 0 or free.size() < count:
		return PackedInt64Array()
	var chain := free.slice(0, count)
	for i: int in chain.size():
		_set_fat(data, volume, chain[i],
			chain[i + 1] if i + 1 < chain.size() else (_END32 if volume.is_wide() else _END16))
	return chain


## The directory named `name` inside the directory at `parent`, made if absent.
## Its first cluster, or -1.
static func _ensure_dir(data: PackedByteArray, parent: int, name: String) -> int:
	var volume := _volume(data)
	var found := volume.find(parent, name)
	if not found.is_empty():
		return int(found["cluster"]) if bool(found["dir"]) else -1
	var chain := _allocate(data, volume, 1)
	if chain.is_empty():
		return -1
	var at := volume.data_offset() + (chain[0] - 1) * volume.cluster_size()
	for i: int in volume.cluster_size():
		data[at + i] = 0xff
	if not _add_entry(data, parent, name, true, chain[0], 0):
		return -1
	return chain[0]


static func _write_file(data: PackedByteArray, dir: int, name: String, bytes: PackedByteArray) -> bool:
	var volume := _volume(data)
	var first := 0
	if not bytes.is_empty():
		@warning_ignore("integer_division")
		var chain := _allocate(data, volume, (bytes.size() + volume.cluster_size() - 1) / volume.cluster_size())
		if chain.is_empty():
			return false
		first = chain[0]
		for i: int in chain.size():
			var at := volume.data_offset() + (chain[i] - 1) * volume.cluster_size()
			var piece := bytes.slice(i * volume.cluster_size(), mini((i + 1) * volume.cluster_size(), bytes.size()))
			for k: int in volume.cluster_size():
				data[at + k] = piece[k] if k < piece.size() else 0
	return _add_entry(data, dir, name, false, first, bytes.size())


## Write a 64-byte entry into the first free place of a directory: a deleted
## entry, or the end marker — moving the marker along, and growing the directory
## by a cluster when the marker was its last entry.
static func _add_entry(data: PackedByteArray, dir: int, name: String, is_dir: bool,
		first: int, size: int) -> bool:
	var raw := name.to_ascii_buffer()
	if raw.is_empty() or raw.size() > FatxVolume.NAME_MAX:
		return false
	var volume := _volume(data)
	var chain := volume.chain_of(dir)
	if chain.is_empty():
		return false
	var per := volume.cluster_size()
	for c: int in chain:
		var base := volume.data_offset() + (c - 1) * per
		for at: int in range(0, per, FatxVolume.ENTRY_SIZE):
			var marker := data[base + at]
			if marker != 0x00 and marker != 0xff and marker != 0xe5:
				continue
			var was_end := marker != 0xe5
			_put_entry(data, base + at, raw, is_dir, first, size)
			if not was_end:
				return true
			# The end moved one entry along. Past the cluster, the directory
			# grows, and a new cluster of 0xFF is nothing but end markers.
			if at + FatxVolume.ENTRY_SIZE < per:
				data[base + at + FatxVolume.ENTRY_SIZE] = 0xff
				return true
			if c != chain[chain.size() - 1]:
				return true
			var more := _allocate(data, volume, 1)
			if more.is_empty():
				return true   # full to the last entry, which is still a valid directory
			_set_fat(data, volume, c, more[0])
			var fresh := volume.data_offset() + (more[0] - 1) * per
			for i: int in per:
				data[fresh + i] = 0xff
			return true
	return false


## Attributes as the console's kernel leaves them. Measured on a disk Conker had
## saved to: a folder is 0x10, a game's own file 0x00, and the four metadata
## files its save API writes — TitleMeta, TitleImage, SaveImage, SaveMeta, all
## ".xbx" — are SYSTEM, 0x04. An archive carries no attributes, so they are put
## back by that rule rather than lost.
static func _attr_for(name: String, is_dir: bool) -> int:
	if is_dir:
		return FatxVolume.ATTR_DIRECTORY
	return FatxVolume.ATTR_SYSTEM if name.to_lower().ends_with(".xbx") else 0


static func _put_entry(data: PackedByteArray, at: int, raw: PackedByteArray, is_dir: bool,
		first: int, size: int) -> void:
	data[at] = raw.size()
	data[at + 1] = _attr_for(raw.get_string_from_ascii(), is_dir)
	for i: int in FatxVolume.NAME_MAX:
		data[at + 2 + i] = raw[i] if i < raw.size() else 0xff
	data.encode_u32(at + 0x2c, first)
	data.encode_u32(at + 0x30, size)
	data.encode_u32(at + 0x34, _STAMP)
	data.encode_u32(at + 0x38, _STAMP)
	data.encode_u32(at + 0x3c, _STAMP)
