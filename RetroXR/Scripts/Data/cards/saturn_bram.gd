## SaturnBram — the Sega Saturn's backup RAM, laid out the way its BIOS lays it out.
##
## One layout serves both places a Saturn saves: the 32 KB inside the console and
## the 512 KB Backup RAM Cartridge. Read from Yabause's HLE implementation of the
## BIOS backup calls (src/bios.c: BiosBUPWrite, BiosBUPRead, BiosBUPDirectory),
## which reads the memory a byte at a time on odd addresses; every offset here is
## that address halved, which is how Beetle Saturn keeps it in .srm and .bcr.
##
## An image is fixed-size blocks, 64 bytes inside the console and 512 on the
## cartridge. Block 0 is "BackUpRam Format" repeated and block 1 is reserved. A
## save starts in a block whose first byte has bit 7 set: name, language, comment,
## date and size, then the numbers of the further blocks it owns ending in 0, then
## its data. Every further block starts with 4 bytes that are skipped.
class_name SaturnBram

const INTERNAL_SIZE := 0x8000
const CART_SIZE := 0x80000
const INTERNAL_BLOCK := 0x40
const CART_BLOCK := 0x200
const RESERVED_BLOCKS := 2
const BLOCK_HEADER := 4
const START_FLAG := 0x80

const NAME_LEN := 11
const COMMENT_LEN := 10
const OFF_NAME := 4
const OFF_LANGUAGE := 15
const OFF_COMMENT := 16
const OFF_DATE := 26
const OFF_SIZE := 30
const OFF_TABLE := 34

const FORMAT_MAGIC := "BackUpRam Format"

## A single save lifted off an image. Nothing standard carries a save's name,
## comment and date with its data, so this is RetroXR's own: magic, name,
## language, comment, date (u32 big-endian), size (u32 big-endian), then the data.
const SAVE_MAGIC := [0x53, 0x41, 0x54, 0x53, 0x41, 0x56, 0x45, 0x00]  # "SATSAVE\0"
const SAVE_HEADER := 38


# --- Image --------------------------------------------------------------------

## The block size an image of this many bytes uses, or 0 for a size no Saturn
## memory has.
static func block_size(size: int) -> int:
	match size:
		INTERNAL_SIZE:
			return INTERNAL_BLOCK
		CART_SIZE:
			return CART_BLOCK
	return 0


static func size_is_valid(size: int) -> bool:
	return block_size(size) > 0


## A freshly formatted image: the format stamp across block 0 and nothing else,
## the pattern Beetle Saturn writes into memory it has no file for.
static func blank_image(size: int = INTERNAL_SIZE) -> PackedByteArray:
	var bs := block_size(size)
	if bs == 0:
		return PackedByteArray()
	var data := PackedByteArray()
	data.resize(size)
	data.fill(0)
	var magic := FORMAT_MAGIC.to_ascii_buffer()
	for i in bs:
		data[i] = magic[i % magic.size()]
	return data


static func is_card_image(data: PackedByteArray) -> bool:
	if not size_is_valid(data.size()):
		return false
	var magic := FORMAT_MAGIC.to_ascii_buffer()
	for i in magic.size():
		if data[i] != magic[i]:
			return false
	return true


## Blocks an image holds, reserved ones included.
static func block_count(data: PackedByteArray) -> int:
	var bs := block_size(data.size())
	@warning_ignore("integer_division")
	return data.size() / bs if bs > 0 else 0


## How many blocks a save of `size` data bytes takes. The first block gives up 34
## bytes to its header and every block 2 to its entry in the table, and the table
## ends in a 2-byte zero: BiosBUPWrite's own arithmetic.
static func blocks_for_data(size: int, bs: int) -> int:
	@warning_ignore("integer_division")
	return 1 + (size + 0x1D) / (bs - 6)


# --- Directory ----------------------------------------------------------------

## Every save, in block order: {block, name, language, comment, date, size, blocks}.
## `blocks` counts the first block too. A block whose first byte has bit 7 set
## but which belongs to another save's chain is that save's data, not a save.
static func list_files(data: PackedByteArray) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not is_card_image(data):
		return out
	var bs := block_size(data.size())
	var starts: Array[Dictionary] = []
	var owned := {}
	for b in range(RESERVED_BLOCKS, block_count(data)):
		if data[b * bs] & START_FLAG == 0:
			continue
		var chain := _chain(data, b)
		if chain.is_empty():
			continue
		starts.append({"block": b, "chain": chain})
		for c: int in (chain["blocks"] as PackedInt32Array):
			owned[c] = true
	for s: Dictionary in starts:
		var b := int(s["block"])
		if owned.has(b):
			continue
		var at := b * bs
		out.append({
			"block": b,
			"name": _text(data, at + OFF_NAME, NAME_LEN),
			"language": data[at + OFF_LANGUAGE],
			"comment": _text(data, at + OFF_COMMENT, COMMENT_LEN),
			"date": _u32(data, at + OFF_DATE),
			"size": _u32(data, at + OFF_SIZE),
			"blocks": (s["chain"]["blocks"] as PackedInt32Array).size() + 1,
		})
	return out


## The first block of the save with this name, or -1.
static func index_of(data: PackedByteArray, name: String) -> int:
	for e: Dictionary in list_files(data):
		if str(e["name"]) == name.strip_edges():
			return int(e["block"])
	return -1


static func free_blocks(data: PackedByteArray) -> int:
	if not is_card_image(data):
		return 0
	var used := 0
	for e: Dictionary in list_files(data):
		used += int(e["blocks"])
	return block_count(data) - RESERVED_BLOCKS - used


## A save's data, or empty when there is no save starting at `first` or its chain
## is broken.
static func read_file(data: PackedByteArray, first: int) -> PackedByteArray:
	var e := _entry(data, first)
	if e.is_empty():
		return PackedByteArray()
	var bs := block_size(data.size())
	var chain := _chain(data, first)
	var blocks: PackedInt32Array = chain["blocks"]
	var hops := int(chain["hops"])
	var pos := int(chain["data_at"])
	var size := int(e["size"])
	var out := PackedByteArray()
	out.resize(size)
	for i in size:
		if pos % bs == 0:
			if hops >= blocks.size():
				return PackedByteArray()
			pos = blocks[hops] * bs + BLOCK_HEADER
			hops += 1
		out[i] = data[pos]
		pos += 1
	return out


## Write a save, returning a NEW image. Empty when a save of that name is there,
## it will not fit, or the image is not formatted. Takes the lowest free blocks,
## as BiosBUPWrite does.
static func write_file(data: PackedByteArray, name: PackedByteArray, language: int,
		comment: PackedByteArray, date: int, payload: PackedByteArray) -> PackedByteArray:
	if not is_card_image(data):
		return PackedByteArray()
	if index_of(data, name.get_string_from_ascii()) >= 0:
		return PackedByteArray()
	var bs := block_size(data.size())
	var need := blocks_for_data(payload.size(), bs)
	var used := {}
	for e: Dictionary in list_files(data):
		used[int(e["block"])] = true
		for c: int in (_chain(data, int(e["block"]))["blocks"] as PackedInt32Array):
			used[c] = true
	var picked: Array[int] = []
	for b in range(RESERVED_BLOCKS, block_count(data)):
		if not used.has(b):
			picked.append(b)
			if picked.size() == need:
				break
	if picked.size() < need:
		return PackedByteArray()

	var out := data.duplicate()
	for b: int in picked:
		for i in bs:
			out[b * bs + i] = 0
	var at := picked[0] * bs
	out[at] = START_FLAG
	_put(out, at + OFF_NAME, name, NAME_LEN)
	out[at + OFF_LANGUAGE] = language & 0xFF
	_put(out, at + OFF_COMMENT, comment, COMMENT_LEN)
	_put_u32(out, at + OFF_DATE, date)
	_put_u32(out, at + OFF_SIZE, payload.size())

	var rest := picked.slice(1)
	var pos := at + OFF_TABLE
	var hops := 0
	for b: int in rest:
		out[pos] = (b >> 8) & 0xFF
		out[pos + 1] = b & 0xFF
		pos += 2
		if pos % bs == 0:
			pos = rest[hops] * bs + BLOCK_HEADER
			hops += 1
	out[pos] = 0
	out[pos + 1] = 0
	pos += 2
	for i in payload.size():
		if pos % bs == 0:
			if hops >= rest.size():
				return PackedByteArray()
			pos = rest[hops] * bs + BLOCK_HEADER
			hops += 1
		out[pos] = payload[i]
		pos += 1
	return out


## `into` with every save of `from` it has no save of that name for and room for,
## returning a NEW image. A save that does not fit is left out.
static func merge(into: PackedByteArray, from: PackedByteArray) -> PackedByteArray:
	var out := into
	for e: Dictionary in list_files(from):
		if index_of(out, str(e["name"])) >= 0:
			continue
		var payload := read_file(from, int(e["block"]))
		if payload.size() != int(e["size"]):
			continue
		var next := write_file(out, str(e["name"]).to_ascii_buffer(), int(e["language"]),
			str(e["comment"]).to_ascii_buffer(), int(e["date"]), payload)
		if not next.is_empty():
			out = next
	return out


## Free a save's blocks, returning a NEW image: its start flag is cleared, as
## BiosBUPDelete does, and nothing else is touched.
static func delete_file(data: PackedByteArray, first: int) -> PackedByteArray:
	if _entry(data, first).is_empty():
		return PackedByteArray()
	var out := data.duplicate()
	out[first * block_size(data.size())] = 0
	return out


# --- Single saves ---------------------------------------------------------------

static func make_save(name: String, language: int, comment: String, date: int,
		payload: PackedByteArray) -> PackedByteArray:
	var out := PackedByteArray(SAVE_MAGIC)
	out.resize(SAVE_HEADER)
	_put(out, 8, name.to_ascii_buffer(), NAME_LEN)
	out[19] = language & 0xFF
	_put(out, 20, comment.to_ascii_buffer(), COMMENT_LEN)
	_put_u32(out, 30, date)
	_put_u32(out, 34, payload.size())
	out.append_array(payload)
	return out


static func is_save(bytes: PackedByteArray) -> bool:
	if bytes.size() < SAVE_HEADER:
		return false
	for i in SAVE_MAGIC.size():
		if bytes[i] != SAVE_MAGIC[i]:
			return false
	return _u32(bytes, 34) == bytes.size() - SAVE_HEADER


## {name, language, comment, date, payload}, or {} when this is not a save.
static func parse_save(bytes: PackedByteArray) -> Dictionary:
	if not is_save(bytes):
		return {}
	return {
		"name": bytes.slice(8, 8 + NAME_LEN),
		"language": bytes[19],
		"comment": bytes.slice(20, 20 + COMMENT_LEN),
		"date": _u32(bytes, 30),
		"payload": bytes.slice(SAVE_HEADER),
	}


# --- Internals ------------------------------------------------------------------

## The save starting at `first`, as list_files reports it, or {}.
static func _entry(data: PackedByteArray, first: int) -> Dictionary:
	for e: Dictionary in list_files(data):
		if int(e["block"]) == first:
			return e
	return {}


## A save's further blocks and where its data starts: {blocks, data_at, hops}, or
## {} when the table runs off the image, into a reserved block or round a loop.
## `hops` is how many of `blocks` the table itself has already crossed into.
static func _chain(data: PackedByteArray, first: int) -> Dictionary:
	var bs := block_size(data.size())
	var count := block_count(data)
	var blocks := PackedInt32Array()
	var seen := {first: true}
	var pos := first * bs + OFF_TABLE
	var hops := 0
	while true:
		if pos % bs == 0:
			if hops >= blocks.size():
				return {}
			pos = blocks[hops] * bs + BLOCK_HEADER
			hops += 1
		var entry := (data[pos] << 8) | data[pos + 1]
		pos += 2
		if entry == 0:
			break
		if entry < RESERVED_BLOCKS or entry >= count or seen.has(entry):
			return {}
		seen[entry] = true
		blocks.append(entry)
	return {"blocks": blocks, "data_at": pos, "hops": hops}


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
