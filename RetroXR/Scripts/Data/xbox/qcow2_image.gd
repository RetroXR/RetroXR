## Qcow2Image — reads a QEMU qcow2 disk image. Read-only, and only what an Xbox
## hard disk needs.
##
## xemu keeps the console's hard disk as a qcow2, and every Xbox save is a file
## inside it, so backing a save up means reading through the image rather than
## copying it: a disk that has run Halo is ~300 MB of cache partitions around a
## few hundred KB of save.
##
## A qcow2 maps the guest's disk in two levels. The header names an L1 table of
## big-endian u64 offsets to L2 tables; an L2 table is one cluster of u64 entries,
## each the host offset of a guest cluster. An entry of zero — at either level —
## is a cluster that was never written, which reads as zeros. So:
##
##     guest offset -> cluster index -> L1[i / per_l2] -> L2[i % per_l2] -> host
##
## REFUSED rather than guessed at: encryption, a backing file, compressed
## clusters, an external data file and extended L2 entries. None of them is what
## qemu-img or xemu makes for this disk, and each would make read() return bytes
## that are not the guest's. The dirty bit is accepted: it says the REFCOUNTS may
## be stale, and nothing here reads a refcount.
##
## The image may be open in the running core — xemu parks its machine rather than
## destroying it. Reading is safe, but the L2 tables are cached by QEMU and reach
## the file when it flushes, so a caller must treat what it parses as possibly
## torn and validate it (FatxVolume does).
class_name Qcow2Image
extends RefCounted

const MAGIC := 0x514649fb   # "QFI\xfb"

## Bits of an L1 or L2 entry that are the host offset; the rest are flags.
const _OFFSET_MASK := 0x00fffffffffffe00
const _L2_COMPRESSED := 1 << 62
## qcow2 v3: the cluster reads as zeros whatever the offset says.
const _L2_ZERO := 1

## Incompatible-feature bits. Only `dirty` may be set.
const _INCOMPAT_DIRTY := 1

## Why open() failed, in words for a log.
var error := ""

var _file: FileAccess = null
var _cluster_bits := 0
var _cluster_size := 0
var _virtual_size := 0
var _per_l2 := 0
var _l1: PackedInt64Array = PackedInt64Array()
## L2 table host offset -> PackedInt64Array of its entries, flags included.
var _l2_cache: Dictionary = {}


## The image at `path`, or null — `why` (an Array) receives the reason.
static func open(path: String, why: Array = []) -> Qcow2Image:
	var image := Qcow2Image.new()
	if image._open(path):
		return image
	why.append(image.error)
	return null


func virtual_size() -> int:
	return _virtual_size


func close() -> void:
	if _file != null:
		_file.close()
		_file = null
	_l2_cache.clear()


func _open(path: String) -> bool:
	_file = FileAccess.open(path, FileAccess.READ)
	if _file == null:
		error = "cannot open %s (err %d)" % [path, FileAccess.get_open_error()]
		return false
	var head := _file.get_buffer(104)
	if head.size() < 72 or _be32(head, 0) != MAGIC:
		error = "not a qcow2 image"
		return false
	var version := _be32(head, 4)
	if version != 2 and version != 3:
		error = "qcow2 version %d is not supported" % version
		return false
	if _be64(head, 8) != 0:
		error = "the image has a backing file"
		return false
	_cluster_bits = _be32(head, 20)
	if _cluster_bits < 9 or _cluster_bits > 21:
		error = "cluster size 2^%d is out of range" % _cluster_bits
		return false
	_cluster_size = 1 << _cluster_bits
	_per_l2 = _cluster_size >> 3
	_virtual_size = _be64(head, 24)
	if _be32(head, 32) != 0:
		error = "the image is encrypted"
		return false
	if version == 3 and head.size() >= 80 and (_be64(head, 72) & ~_INCOMPAT_DIRTY) != 0:
		error = "the image uses a qcow2 feature this reader does not have (0x%x)" \
			% _be64(head, 72)
		return false

	var l1_size := _be32(head, 36)
	var l1_offset := _be64(head, 40)
	# Enough L1 entries to map the disk, and no more than a sane image has: the
	# table is read whole, so a corrupt count must not become a huge allocation.
	if l1_size <= 0 or l1_size > (1 << 20) or l1_offset <= 0:
		error = "the L1 table is missing or implausible (%d entries)" % l1_size
		return false
	_file.seek(l1_offset)
	var raw := _file.get_buffer(l1_size * 8)
	if raw.size() != l1_size * 8:
		error = "the L1 table is cut short"
		return false
	_l1.resize(l1_size)
	for i: int in l1_size:
		_l1[i] = _be64(raw, i * 8)
	return true


## `length` bytes of the GUEST disk at `offset`. Empty on any failure — a
## compressed cluster, a read past the file — and `error` says which.
func read(offset: int, length: int) -> PackedByteArray:
	var out := PackedByteArray()
	if _file == null or offset < 0 or length < 0 or offset + length > _virtual_size:
		error = "read outside the disk (%d + %d)" % [offset, length]
		return out
	while length > 0:
		var within := offset & (_cluster_size - 1)
		var take := mini(length, _cluster_size - within)
		var host := _host_cluster(offset >> _cluster_bits)
		if host < 0:
			return PackedByteArray()
		if host == 0:
			var zeros := PackedByteArray()
			zeros.resize(take)
			out.append_array(zeros)
		else:
			_file.seek(host + within)
			var got := _file.get_buffer(take)
			if got.size() != take:
				error = "the image file is cut short at 0x%x" % (host + within)
				return PackedByteArray()
			out.append_array(got)
		offset += take
		length -= take
	return out


## Host offset of a guest cluster, 0 when it was never written, -1 on failure.
func _host_cluster(index: int) -> int:
	@warning_ignore("integer_division")
	var l1_index := index / _per_l2
	if l1_index >= _l1.size():
		return 0
	var l2_offset := _l1[l1_index] & _OFFSET_MASK
	if l2_offset == 0:
		return 0
	var table: PackedInt64Array = _l2_cache.get(l2_offset, PackedInt64Array())
	if table.is_empty():
		_file.seek(l2_offset)
		var raw := _file.get_buffer(_cluster_size)
		if raw.size() != _cluster_size:
			error = "an L2 table is cut short at 0x%x" % l2_offset
			return -1
		table.resize(_per_l2)
		for i: int in _per_l2:
			table[i] = _be64(raw, i * 8)
		_l2_cache[l2_offset] = table
	var entry := table[index % _per_l2]
	if entry & _L2_COMPRESSED:
		error = "the image has compressed clusters"
		return -1
	if entry & _L2_ZERO:
		return 0
	return entry & _OFFSET_MASK


static func _be32(b: PackedByteArray, at: int) -> int:
	return (b[at] << 24) | (b[at + 1] << 16) | (b[at + 2] << 8) | b[at + 3]


static func _be64(b: PackedByteArray, at: int) -> int:
	return (_be32(b, at) << 32) | _be32(b, at + 4)
