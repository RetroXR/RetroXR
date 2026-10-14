## ThreeDoNvram — the 3DO's 32 KB of NVRAM, laid out the way Portfolio OS lays it
## out: a "linked memory" file system, flat, one byte to a block.
##
## Read from the OS itself (trapexit/portfolio_os: src/filesystem/
## LinkedMemFileSystem.c, includes/filesystem.h, discdata.h) and from Opera, which
## keeps the memory as a plain byte array and formats a blank one the way the
## OS's own `format` does (libopera/opera_nvram.c). Every field is big-endian.
##
## An image is a 132-byte disc label (record type 1, "ZZZZZ", structure version 2,
## the root's first avatar the offset of the list) and then one circular,
## doubly-linked list of blocks, starting at an anchor. Every block begins
## fingerprint, forward link, back link, block count (the header included) and
## header block count. A file's header is 64 bytes: that, then its byte count,
## unique id, type and a 32-byte name, and its data follows. A free block's
## header is the first 20. The list runs in address order and wraps to the anchor,
## which is how the OS finds the last block (a forward link lower than itself).
##
## Offsets are in blocks, and NVRAM's block is a byte, so they are byte offsets.
class_name ThreeDoNvram

const IMAGE_SIZE := 0x8000
const LABEL_SIZE := 132
const BLOCK_HEADER := 20
const ENTRY_SIZE := 64
## LINKED_MEM_SLACK: a free block is split only when what is left would hold a
## file header and this much more. Otherwise the file takes all of it.
const SLACK := 32

const FINGERPRINT_FILE := 0xBE4F32A6
const FINGERPRINT_FREE := 0x7AA565BD
const FINGERPRINT_ANCHOR := 0x855A02B6

const LABEL_RECORD_TYPE := 1
const SYNC_BYTE := 0x5A  # 'Z'
const SYNC_LEN := 5
const STRUCTURE_LINKED_MEM := 2
const OFF_STRUCTURE := 6
const OFF_COMMENTARY := 8
const OFF_IDENTIFIER := 40
const OFF_VOLUME_ID := 72
const OFF_BLOCK_SIZE := 76
const OFF_BLOCK_COUNT := 80
const OFF_ROOT_ID := 84
const OFF_ROOT_BLOCK_SIZE := 92
const OFF_ROOT_AVATAR := 100

const OFF_FLINK := 4
const OFF_BLINK := 8
const OFF_COUNT := 12
const OFF_HEADER := 16
const OFF_BYTES := 20
const OFF_UNIQUE := 24
const OFF_TYPE := 28
const OFF_NAME := 32
const NAME_LEN := 32
## What FILECMD_ADDENTRY stamps a new file's type with: four spaces.
const BLANK_TYPE := 0x20202020

## The OS walks at most this many blocks before calling the list broken.
const MAX_BLOCKS := 1000

## A single save lifted off an image. Nothing standard carries a 3DO file's name,
## type and byte count with its data, so this is RetroXR's own: magic, name, type,
## unique id and byte count (u32 big-endian), then every byte the file occupies.
const SAVE_MAGIC := [0x33, 0x44, 0x4F, 0x53, 0x41, 0x56, 0x45, 0x00]  # "3DOSAVE\0"
const SAVE_HEADER := 52


# --- Image --------------------------------------------------------------------

## A freshly formatted image, byte for byte the one Opera makes for memory it has
## no file for: the label, the anchor, and one free block over all the rest.
static func blank_image() -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(IMAGE_SIZE)
	data.fill(0)
	data[0] = LABEL_RECORD_TYPE
	for i in SYNC_LEN:
		data[1 + i] = SYNC_BYTE
	data[OFF_STRUCTURE] = STRUCTURE_LINKED_MEM
	_put(data, OFF_COMMENTARY, "opera formatted".to_ascii_buffer(), 32)
	_put(data, OFF_IDENTIFIER, "nvram".to_ascii_buffer(), 32)
	_put_u32(data, OFF_VOLUME_ID, 0xFFFFFFFF)  # NVRAM_VOLUME_UNIQUE_ID, -1
	_put_u32(data, OFF_BLOCK_SIZE, 1)
	_put_u32(data, OFF_BLOCK_COUNT, IMAGE_SIZE)
	_put_u32(data, OFF_ROOT_ID, 0xFFFFFFFE)  # NVRAM_ROOT_UNIQUE_ID, -2
	_put_u32(data, OFF_ROOT_BLOCK_SIZE, 1)
	_put_u32(data, OFF_ROOT_AVATAR, LABEL_SIZE)
	var anchor := LABEL_SIZE
	var free := anchor + BLOCK_HEADER
	_put_block(data, anchor, FINGERPRINT_ANCHOR, free, free, BLOCK_HEADER, BLOCK_HEADER)
	_put_block(data, free, FINGERPRINT_FREE, anchor, anchor, IMAGE_SIZE - free, BLOCK_HEADER)
	return data


## A 3DO NVRAM image this can read: the label Opera checks for, a one-byte block,
## and an anchor where the label says the list starts.
static func is_card_image(data: PackedByteArray) -> bool:
	if data.size() != IMAGE_SIZE or data[0] != LABEL_RECORD_TYPE:
		return false
	for i in SYNC_LEN:
		if data[1 + i] != SYNC_BYTE:
			return false
	if data[OFF_STRUCTURE] != STRUCTURE_LINKED_MEM or _u32(data, OFF_BLOCK_SIZE) != 1:
		return false
	var anchor := _u32(data, OFF_ROOT_AVATAR)
	return anchor >= LABEL_SIZE and anchor + BLOCK_HEADER <= data.size() \
		and _u32(data, anchor) == FINGERPRINT_ANCHOR


## Every block, in list order from the one after the anchor:
## {at, fingerprint, flink, blink, count, header}. Empty when the image is not
## one, or when the list is broken: a block off the image or overlapping the next,
## a back link that does not point at the block before, an unknown fingerprint,
## or no way back to the anchor.
static func blocks(data: PackedByteArray) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not is_card_image(data):
		return out
	var anchor := _u32(data, OFF_ROOT_AVATAR)
	var prev := anchor
	var at := _u32(data, anchor + OFF_FLINK)
	while at != anchor:
		if out.size() >= MAX_BLOCKS or at < anchor + BLOCK_HEADER \
				or at + BLOCK_HEADER > data.size():
			out.clear()
			return out
		var fp := _u32(data, at)
		var count := _u32(data, at + OFF_COUNT)
		var header := _u32(data, at + OFF_HEADER)
		var flink := _u32(data, at + OFF_FLINK)
		if (fp != FINGERPRINT_FILE and fp != FINGERPRINT_FREE) \
				or _u32(data, at + OFF_BLINK) != prev \
				or header < BLOCK_HEADER or count < header or at + count > data.size() \
				or (fp == FINGERPRINT_FILE and header < ENTRY_SIZE):
			out.clear()
			return out
		if flink != anchor and (flink <= at or at + count > flink):
			out.clear()
			return out
		out.append({"at": at, "fingerprint": fp, "flink": flink, "blink": prev,
			"count": count, "header": header})
		prev = at
		at = flink
	if _u32(data, anchor + OFF_BLINK) != prev:
		out.clear()
	return out


# --- Directory ----------------------------------------------------------------

## Every file, in list order: {at, name, type, unique, bytes, blocks}. `blocks` is
## what the file occupies past its header, which is what the OS reports as its
## size on the device; `bytes` is its end of file.
static func list_files(data: PackedByteArray) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for b: Dictionary in blocks(data):
		if int(b["fingerprint"]) != FINGERPRINT_FILE:
			continue
		var at := int(b["at"])
		out.append({
			"at": at,
			"name": _text(data, at + OFF_NAME, NAME_LEN),
			"type": _u32(data, at + OFF_TYPE),
			"unique": _u32(data, at + OFF_UNIQUE),
			"bytes": _u32(data, at + OFF_BYTES),
			"blocks": int(b["count"]) - int(b["header"]),
		})
	return out


## Where the file of this name starts, or -1. Names compare without case, as the
## OS's own lookups do.
static func index_of(data: PackedByteArray, name: String) -> int:
	var want := name.strip_edges().to_lower()
	for e: Dictionary in list_files(data):
		if str(e["name"]).to_lower() == want:
			return int(e["at"])
	return -1


## What the OS reports as free: every free block less the header a file made in it
## would need.
static func free_bytes(data: PackedByteArray) -> int:
	var free := 0
	for b: Dictionary in blocks(data):
		if int(b["fingerprint"]) == FINGERPRINT_FREE:
			free += maxi(0, int(b["count"]) - ENTRY_SIZE)
	return free


## The most a formatted image of this layout holds: everything past the anchor,
## less one file's header.
static func capacity(data: PackedByteArray) -> int:
	if not is_card_image(data):
		data = blank_image()
	var anchor := _u32(data, OFF_ROOT_AVATAR)
	return data.size() - anchor - _u32(data, anchor + OFF_COUNT) - ENTRY_SIZE


## Every byte a file occupies past its header, or empty when there is no file
## starting at `at`.
static func read_file(data: PackedByteArray, at: int) -> PackedByteArray:
	for b: Dictionary in blocks(data):
		if int(b["at"]) == at and int(b["fingerprint"]) == FINGERPRINT_FILE:
			return data.slice(at + int(b["header"]), at + int(b["count"]))
	return PackedByteArray()


## Write a file, returning a NEW image. Empty when one of that name is there, the
## name will not fit with its terminator, nothing is free that holds it, or the
## list is broken. As the OS makes and sizes a file: the first free block from
## the anchor that holds header and data, split when enough is left over.
static func write_file(data: PackedByteArray, name: String, type: int, unique: int,
		byte_count: int, contents: PackedByteArray) -> PackedByteArray:
	var name_bytes := name.strip_edges().to_ascii_buffer()
	if name_bytes.is_empty() or name_bytes.size() >= NAME_LEN \
			or byte_count > contents.size() or index_of(data, name) >= 0:
		return PackedByteArray()
	var want := ENTRY_SIZE + contents.size()
	var hole := {}
	for b: Dictionary in blocks(data):
		if int(b["fingerprint"]) == FINGERPRINT_FREE and int(b["count"]) >= want:
			hole = b
			break
	if hole.is_empty():
		return PackedByteArray()

	var out := data.duplicate()
	var at := int(hole["at"])
	var count := int(hole["count"])
	var flink := int(hole["flink"])
	if count - want >= ENTRY_SIZE + SLACK:
		var rest := at + want
		_put_block(out, rest, FINGERPRINT_FREE, flink, at, count - want, BLOCK_HEADER)
		# The OS makes a file and then sizes it, and the free block split off the
		# second time carries the rest of the entry the first wrote: no bytes, type
		# four spaces, the name. Kept, so an image written here is the image a 3DO
		# writes (measured against Gex's own file, three_do_nvram_probe).
		_put_u32(out, rest + OFF_BYTES, 0)
		_put_u32(out, rest + OFF_UNIQUE, 0)
		_put_u32(out, rest + OFF_TYPE, BLANK_TYPE)
		_put(out, rest + OFF_NAME, name_bytes, NAME_LEN)
		_put_u32(out, flink + OFF_BLINK, rest)
		flink = rest
		count = want
	_put_block(out, at, FINGERPRINT_FILE, flink, int(hole["blink"]), count, ENTRY_SIZE)
	_put_u32(out, at + OFF_BYTES, byte_count)
	_put_u32(out, at + OFF_UNIQUE, unique)
	_put_u32(out, at + OFF_TYPE, type)
	_put(out, at + OFF_NAME, name_bytes, NAME_LEN)
	for i in count - ENTRY_SIZE:
		out[at + ENTRY_SIZE + i] = contents[i] if i < contents.size() else 0
	return out


## Free a file, returning a NEW image: it becomes a free block and joins every
## free block either side of it, as FILECMD_DELETEENTRY does. Its old header past
## the first 20 bytes is left where it was, as the OS leaves it.
static func delete_file(data: PackedByteArray, at: int) -> PackedByteArray:
	var list := blocks(data)
	var index := -1
	for i in list.size():
		if int(list[i]["at"]) == at and int(list[i]["fingerprint"]) == FINGERPRINT_FILE:
			index = i
	if index < 0:
		return PackedByteArray()
	var first := index
	while first > 0 and int(list[first - 1]["fingerprint"]) == FINGERPRINT_FREE:
		first -= 1
	var last := index
	while last + 1 < list.size() and int(list[last + 1]["fingerprint"]) == FINGERPRINT_FREE:
		last += 1
	var out := data.duplicate()
	var start := int(list[first]["at"])
	var count := 0
	for i in range(first, last + 1):
		count += int(list[i]["count"])
	var flink := int(list[last]["flink"])
	_put_block(out, start, FINGERPRINT_FREE, flink, int(list[first]["blink"]), count, BLOCK_HEADER)
	_put_u32(out, flink + OFF_BLINK, start)
	return out


## `into` with every file of `from` it has none of that name for and room for,
## returning a NEW image. A file that does not fit is left out.
static func merge(into: PackedByteArray, from: PackedByteArray) -> PackedByteArray:
	var out := into
	for e: Dictionary in list_files(from):
		if index_of(out, str(e["name"])) >= 0:
			continue
		var next := write_file(out, str(e["name"]), int(e["type"]), int(e["unique"]),
			mini(int(e["bytes"]), int(e["blocks"])), read_file(from, int(e["at"])))
		if not next.is_empty():
			out = next
	return out


# --- Single saves ---------------------------------------------------------------

static func make_save(name: String, type: int, unique: int, byte_count: int,
		contents: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray(SAVE_MAGIC)
	out.resize(SAVE_HEADER)
	_put(out, 8, name.to_ascii_buffer(), NAME_LEN)
	_put_u32(out, 40, type)
	_put_u32(out, 44, unique)
	_put_u32(out, 48, byte_count)
	out.append_array(contents)
	return out


static func is_save(bytes: PackedByteArray) -> bool:
	if bytes.size() < SAVE_HEADER:
		return false
	for i in SAVE_MAGIC.size():
		if bytes[i] != SAVE_MAGIC[i]:
			return false
	return bytes[8] != 0 and _u32(bytes, 48) <= bytes.size() - SAVE_HEADER


## {name, type, unique, bytes, contents}, or {} when this is not a save.
static func parse_save(bytes: PackedByteArray) -> Dictionary:
	if not is_save(bytes):
		return {}
	return {
		"name": _text(bytes, 8, NAME_LEN),
		"type": _u32(bytes, 40),
		"unique": _u32(bytes, 44),
		"bytes": _u32(bytes, 48),
		"contents": bytes.slice(SAVE_HEADER),
	}


# --- Internals ------------------------------------------------------------------

static func _put_block(data: PackedByteArray, at: int, fingerprint: int, flink: int,
		blink: int, count: int, header: int) -> void:
	_put_u32(data, at, fingerprint)
	_put_u32(data, at + OFF_FLINK, flink)
	_put_u32(data, at + OFF_BLINK, blink)
	_put_u32(data, at + OFF_COUNT, count)
	_put_u32(data, at + OFF_HEADER, header)


static func _text(data: PackedByteArray, at: int, n: int) -> String:
	var bytes := PackedByteArray()
	for i in n:
		var c := data[at + i]
		if c == 0:
			break
		bytes.append(c)
	return bytes.get_string_from_ascii().strip_edges()


static func _put(data: PackedByteArray, at: int, src: PackedByteArray, n: int) -> void:
	for i in n:
		data[at + i] = src[i] if i < src.size() else 0


static func _u32(data: PackedByteArray, at: int) -> int:
	return (data[at] << 24) | (data[at + 1] << 16) | (data[at + 2] << 8) | data[at + 3]


static func _put_u32(data: PackedByteArray, at: int, v: int) -> void:
	data[at] = (v >> 24) & 0xFF
	data[at + 1] = (v >> 16) & 0xFF
	data[at + 2] = (v >> 8) & 0xFF
	data[at + 3] = v & 0xFF
