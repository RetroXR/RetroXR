## FatxVolume — reads one FATX partition of an Xbox hard disk. Read-only.
##
## FATX is FAT with the history taken out: a 4 KB header, ONE allocation table,
## then clusters, with the root directory in cluster 1.
##
##     +0x0000  "FATX", volume id u32, sectors per cluster u32, FAT copies u16
##     +0x1000  the FAT: u16 entries, or u32 once the partition has 0xFFF0 or
##              more clusters, rounded up to 4 KB
##     then     cluster 1, cluster 2, ...  (cluster N at data + (N - 1) * size)
##
## A directory is a chain of clusters of 64-byte entries: name length u8 (0x00 or
## 0xFF ends the directory, 0xE5 is a deleted entry), attributes u8 (0x10 is a
## directory), 42 bytes of name, first cluster u32, size u32, then timestamps.
## There are no "." entries and no long names. Everything is little-endian.
##
## Measured against a disk xemu had run Halo on: E: has 313,280 16 KB clusters
## and so a u32 FAT; C:, X:, Y: and Z: are small enough for u16.
##
## EVERYTHING READ IS CHECKED, because the image may be open in a running core
## whose tables have not all reached the file (see Qcow2Image). A name with a
## control character in it, a cluster past the end, a chain that loops or whose
## length disagrees with the file's size: each is an error for the whole read,
## never a file quietly cut short — what this returns gets uploaded as a backup.
class_name FatxVolume
extends RefCounted

const MAGIC := "FATX"
const HEADER_SIZE := 0x1000
const ENTRY_SIZE := 64
const NAME_MAX := 42
const ATTR_DIRECTORY := 0x10
## What the console's own save API marks a save's metadata with.
const ATTR_SYSTEM := 0x04
const ROOT_CLUSTER := 1

## FAT pages are read through the image this many bytes at a time.
const _FAT_PAGE := 0x4000

var error := ""

## Qcow2Image or XboxRawImage: anything with read(offset, length) and `error`.
var _image: RefCounted = null
var _base := 0
var _cluster_size := 0
var _clusters := 0
var _wide := false
var _fat_offset := 0
var _data_offset := 0
var _fat_pages: Dictionary = {}


## The FATX volume `size` bytes long at `base` of `image`, or null — `why`
## receives the reason. An unformatted partition is the usual one.
static func open(image: RefCounted, base: int, size: int, why: Array = []) -> FatxVolume:
	var volume := FatxVolume.new()
	if volume._open(image, base, size):
		return volume
	why.append(volume.error)
	return null


func _open(image: RefCounted, base: int, size: int) -> bool:
	_image = image
	_base = base
	var head: PackedByteArray = image.call("read", base, 16)
	if head.size() != 16:
		error = str(image.get("error"))
		return false
	if head.slice(0, 4).get_string_from_ascii() != MAGIC:
		error = "no FATX volume at 0x%x" % base
		return false
	var sectors := head.decode_u32(8)
	# A power of two, 1..128 sectors: what the Xbox kernel formats with.
	if sectors <= 0 or sectors > 128 or (sectors & (sectors - 1)) != 0:
		error = "implausible cluster size (%d sectors)" % sectors
		return false
	_cluster_size = sectors * 512
	@warning_ignore("integer_division")
	_clusters = size / _cluster_size
	_wide = _clusters >= 0xfff0
	var fat_bytes := _clusters * (4 if _wide else 2)
	fat_bytes = (fat_bytes + HEADER_SIZE - 1) & ~(HEADER_SIZE - 1)
	_fat_offset = base + HEADER_SIZE
	_data_offset = _fat_offset + fat_bytes
	return true


# --- Geometry, for a writer (XboxMemoryUnit) ----------------------------------

func cluster_size() -> int:
	return _cluster_size


func cluster_count() -> int:
	return _clusters


func is_wide() -> bool:
	return _wide


## Offset of the FAT, and of cluster 1, from the start of the IMAGE.
func fat_offset() -> int:
	return _fat_offset


func data_offset() -> int:
	return _data_offset


## The clusters of the chain starting at `first`, or empty with `error` set.
func chain_of(first: int) -> PackedInt64Array:
	error = ""
	return _chain(first, -1)


## The entries of the directory starting at `cluster`, as {name, dir, cluster,
## size}. Empty with `error` set on a fault; an empty directory sets none.
func list_dir(cluster: int) -> Array[Dictionary]:
	error = ""
	var out: Array[Dictionary] = []
	for c: int in _chain(cluster, -1):
		var data := _cluster(c)
		if data.is_empty():
			return []
		for at: int in range(0, data.size(), ENTRY_SIZE):
			var name_len := data[at]
			if name_len == 0x00 or name_len == 0xff:
				return out
			if name_len == 0xe5:
				continue
			if name_len > NAME_MAX:
				error = "a directory entry has a %d-byte name" % name_len
				return []
			var name_bytes := data.slice(at + 2, at + 2 + name_len)
			for ch: int in name_bytes:
				if ch < 0x20 or ch == 0x7f or ch == 0x2f or ch == 0x5c:
					error = "a directory entry's name is not a name"
					return []
			var first := data.decode_u32(at + 0x2c)
			var is_dir := (data[at + 1] & ATTR_DIRECTORY) != 0
			var size := data.decode_u32(at + 0x30)
			# An empty file has no cluster. Anything else must name a real one.
			if (is_dir or size > 0) and (first < ROOT_CLUSTER or first > _clusters):
				error = "%s starts at cluster %d, which is not on the volume" \
					% [name_bytes.get_string_from_ascii(), first]
				return []
			out.append({
				"name": name_bytes.get_string_from_ascii(),
				"dir": is_dir, "cluster": first, "size": size,
				"attr": data[at + 1],
				# Where the entry itself is, for a writer: its directory
				# cluster, and its offset in that cluster.
				"at_cluster": c, "at": at,
			})
	if not error.is_empty():
		return []
	return out


## The entry named `name` (case does not matter, as on the console) in the
## directory at `cluster`, or {}.
func find(cluster: int, name: String) -> Dictionary:
	for e: Dictionary in list_dir(cluster):
		if str(e["name"]).nocasecmp_to(name) == 0:
			return e
	return {}


## A file's bytes. Empty with `error` set on a fault; a zero-length file is
## empty with none.
func read_file(entry: Dictionary) -> PackedByteArray:
	error = ""
	var size := int(entry.get("size", 0))
	if size == 0:
		return PackedByteArray()
	@warning_ignore("integer_division")
	var want := (size + _cluster_size - 1) / _cluster_size
	var chain := _chain(int(entry.get("cluster", 0)), want)
	if chain.size() != want:
		if error.is_empty():
			error = "%s is %d bytes but its chain is %d clusters" \
				% [str(entry.get("name", "")), size, chain.size()]
		return PackedByteArray()
	var out := PackedByteArray()
	for c: int in chain:
		var data := _cluster(c)
		if data.is_empty():
			return PackedByteArray()
		out.append_array(data)
	return out.slice(0, size)


## Every file under the directory at `cluster`, as "sub/dir/name" -> bytes.
##
## `budget` is {files, bytes} and is counted DOWN: past either the walk stops
## with an error rather than returning part of a save. Returns false on a fault.
func read_tree(cluster: int, prefix: String, into: Dictionary, budget: Dictionary,
		depth: int = 0) -> bool:
	if depth > 16:
		error = "directories nest deeper than a save's do"
		return false
	var entries := list_dir(cluster)
	if not error.is_empty():
		return false
	for e: Dictionary in entries:
		var path := prefix + str(e["name"])
		if bool(e["dir"]):
			if not read_tree(int(e["cluster"]), path + "/", into, budget, depth + 1):
				return false
			continue
		budget["files"] = int(budget["files"]) - 1
		budget["bytes"] = int(budget["bytes"]) - int(e["size"])
		if int(budget["files"]) < 0 or int(budget["bytes"]) < 0:
			error = "more save data than a backup carries"
			return false
		var bytes := read_file(e)
		if not error.is_empty():
			return false
		into[path] = bytes
	return true


# --- Clusters -----------------------------------------------------------------

## The clusters of a chain. `expect` is how many there should be (-1 when only
## the FAT knows, as for a directory); one past that is a fault, and so is a
## loop, which is a chain longer than the volume has clusters.
func _chain(first: int, expect: int) -> PackedInt64Array:
	var out := PackedInt64Array()
	var limit := expect if expect >= 0 else _clusters
	var c := first
	while c >= ROOT_CLUSTER:
		if c > _clusters or out.size() >= limit:
			error = "a cluster chain runs off the volume or past its file"
			return PackedInt64Array()
		out.append(c)
		c = _next(c)
		if c == -2:
			return PackedInt64Array()
	return out


## The cluster after `c`: -1 at the end of a chain, -2 with `error` on a fault.
func _next(c: int) -> int:
	var width := 4 if _wide else 2
	var at := c * width
	@warning_ignore("integer_division")
	var page_index := at / _FAT_PAGE
	var page: PackedByteArray = _fat_pages.get(page_index, PackedByteArray())
	if page.is_empty():
		page = _image.call("read", _fat_offset + page_index * _FAT_PAGE, _FAT_PAGE)
		if page.size() != _FAT_PAGE:
			error = str(_image.get("error"))
			return -2
		_fat_pages[page_index] = page
	var within := at - page_index * _FAT_PAGE
	var value := page.decode_u32(within) if _wide else page.decode_u16(within)
	# Free (0) in the middle of a chain is a torn table, not an end.
	if value == 0:
		error = "a cluster chain leads to a free cluster"
		return -2
	if value >= (0xfffffff0 if _wide else 0xfff0):
		return -1
	return value


func _cluster(c: int) -> PackedByteArray:
	var data: PackedByteArray = _image.call("read", _data_offset + (c - 1) * _cluster_size, _cluster_size)
	if data.size() != _cluster_size:
		error = str(_image.get("error"))
		return PackedByteArray()
	return data
