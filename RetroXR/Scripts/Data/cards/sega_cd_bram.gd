## SegaCdBram — the Sega CD's backup RAM, laid out the way its BIOS lays it out.
##
## One layout serves both places a Sega CD saves: the 8 KB inside the unit and a
## Backup RAM Cartridge. Measured against the BIOS disassembly
## (DarkMorford/scd-bios-disassembly) and cross-checked byte for byte against
## buram, whose error-correction code is transliterated here:
##
##   buram — Mega CD backup RAM management tool
##   Copyright (c) 2022 Ian Karlsson. MIT licence.
##   https://github.com/superctr/buram
##
## An image is 64-byte blocks. Block 0 is reserved; the last block is the plain
## format block (volume, the free and file counts four times each, and
## "SEGA_CD_ROM" / "RAM_CARTRIDGE___"). Directory entries grow down from just under
## it, two to a block and always error-corrected; save data grows up from block 1.
## A save is either raw (64 data bytes a block) or protected (32 data bytes a
## block, error-corrected the same way the directory is).
class_name SegaCdBram

const BLOCK_SIZE := 0x40
## The 8 KB inside the Sega CD, and Sega's own Backup RAM Cartridge (128 Kbit).
const INTERNAL_SIZE := 0x2000
const CART_SIZE := 0x4000
## The largest cartridge Genesis Plus GX maps (4 Mbit).
const MAX_SIZE := 0x80000

const NAME_LEN := 11
const ENTRY_SIZE := 16
const MODE_RAW := 0x00
const MODE_PROTECTED := 0xFF
const RAW_BLOCK_DATA := 64
const PROTECTED_BLOCK_DATA := 32
## The BIOS computes a delete's shift in 16 bits, so a larger file cannot be
## deleted on the console.
const MAX_FILE_BLOCKS := 255

## A single save lifted off an image. Nothing standard carries a save's name and
## mode with its data, so this is RetroXR's own: magic, 11-byte name, mode, block
## count (u16 big-endian), then the save's data as the game sees it.
const SCDS_MAGIC := [0x53, 0x43, 0x44, 0x53, 0x41, 0x56, 0x45, 0x00]  # "SCDSAVE\0"
const SCDS_HEADER := 22

const _VOLUME := "___________"
const _FORMAT_ID := [0x00, 0x00, 0x00, 0x00, 0x40]
const _FORMAT_TAIL := "SEGA_CD_ROM"
const _MEDIA_TAIL := "RAM_CARTRIDGE___"
const _LAST_RS6_BYTE := [0x2d, 0x2e, 0x2f, 0x08, 0x11, 0x1a, 0x23, 0x2c]
const _RS8_GEN := [87, 166, 113, 75, 198, 25, 167, 114, 76, 199, 26, 1]
const _RS6_GEN := [20, 58, 56, 18, 26, 6, 59, 57, 19, 27, 7, 1]

static var _rs8: Dictionary = {}
static var _rs6: Dictionary = {}
static var _crc_tab := PackedInt32Array()


# --- Image --------------------------------------------------------------------

## A freshly formatted image of this size, exactly as the BIOS formats one.
static func blank_image(size: int = INTERNAL_SIZE) -> PackedByteArray:
	if not size_is_valid(size):
		return PackedByteArray()
	var data := PackedByteArray()
	data.resize(size)
	var top := size - BLOCK_SIZE
	for i in NAME_LEN:
		data[top + i] = _VOLUME.unicode_at(i)
	for i in _FORMAT_ID.size():
		data[top + 0x0B + i] = _FORMAT_ID[i]
	var tail := _format_tail()
	for i in tail.size():
		data[top + 0x20 + i] = tail[i]
	_write_counts(data, _block_count(size) - 3, 0)
	return data


## A power-of-two size from the unit's 8 KB up to a 4 Mbit cartridge.
static func size_is_valid(size: int) -> bool:
	return size >= INTERNAL_SIZE and size <= MAX_SIZE and (size & (size - 1)) == 0


## Formatted, and its counts readable. Genesis Plus GX compares the last 0x20 bytes
## exactly and reformats anything else, so that is the check here too.
static func is_card_image(data: PackedByteArray) -> bool:
	if not size_is_valid(data.size()):
		return false
	var tail := _format_tail()
	var at := data.size() - tail.size()
	for i in tail.size():
		if data[at + i] != tail[i]:
			return false
	var files := file_count(data)
	return files >= 0 and files <= _block_count(data.size()) * 2


## How many saves the directory holds, or -1 when the stored count is unreadable.
static func file_count(data: PackedByteArray) -> int:
	return _read_repeat(data, data.size() - BLOCK_SIZE + 0x18)


## Blocks free for a new save, worked out from the directory rather than trusted
## from the stored count, which tools that resize an image leave stale. One block
## stays back whenever the next entry would start a new directory block.
static func free_blocks(data: PackedByteArray) -> int:
	var files := list_files(data)
	var used := 0
	for e: Dictionary in files:
		used += int(e["size"])
	@warning_ignore("integer_division")
	var dir_blocks := (files.size() + 1) / 2
	var reserve := 1 if files.size() % 2 == 0 else 0
	return maxi(0, _block_count(data.size()) - 2 - used - dir_blocks - reserve)


## Every directory entry, in directory order: {name, mode, start, size, damaged}.
## `name` is the raw 11 bytes as a String; `damaged` marks an entry whose block
## could not be corrected.
static func list_files(data: PackedByteArray) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not is_card_image(data):
		return out
	var count := file_count(data)
	var blocks := _block_count(data.size())
	for k in count:
		var e := _read_entry(data, k)
		var start := int(e["start"])
		var size := int(e["size"])
		if start < 1 or size < 1 or start + size > blocks:
			e["damaged"] = true
		out.append(e)
	return out


## The directory index of the save with this 11-character name, or -1.
static func index_of(data: PackedByteArray, name: String) -> int:
	var files := list_files(data)
	for k in files.size():
		if str(files[k]["name"]) == name:
			return k
	return -1


## One save's data as the game wrote it: 64 bytes a block raw, 32 protected.
## Empty when the entry is damaged or a protected block cannot be corrected.
static func read_file(data: PackedByteArray, index: int) -> PackedByteArray:
	var files := list_files(data)
	if index < 0 or index >= files.size() or bool(files[index]["damaged"]):
		return PackedByteArray()
	var e := files[index]
	var start := int(e["start"])
	var size := int(e["size"])
	if int(e["mode"]) == MODE_RAW:
		return data.slice(start * BLOCK_SIZE, (start + size) * BLOCK_SIZE)
	var out := PackedByteArray()
	for b in size:
		var decoded := _decode_block(data, (start + b) * BLOCK_SIZE)
		if int(decoded["flags"]) & 12:
			return PackedByteArray()
		out.append_array((decoded["buf"] as PackedByteArray).slice(2, 34))
	return out


## Append a save, as the BIOS's write does, returning a NEW image. Empty when the
## name is already there, it does not fit, or the data is not whole blocks.
static func write_file(data: PackedByteArray, name: PackedByteArray, mode: int,
		payload: PackedByteArray) -> PackedByteArray:
	if not is_card_image(data) or name.size() != NAME_LEN:
		return PackedByteArray()
	var per_block := RAW_BLOCK_DATA if mode == MODE_RAW else PROTECTED_BLOCK_DATA
	if payload.is_empty() or payload.size() % per_block != 0:
		return PackedByteArray()
	@warning_ignore("integer_division")
	var size: int = payload.size() / per_block
	if size > MAX_FILE_BLOCKS or size > free_blocks(data):
		return PackedByteArray()
	if index_of(data, name.get_string_from_ascii()) >= 0:
		return PackedByteArray()

	var out := data.duplicate()
	var files := list_files(out)
	var start := 1
	if not files.is_empty():
		start = int(files[-1]["start"]) + int(files[-1]["size"])
	var entry := _entry_bytes(name, mode, start, size)
	_write_entry(out, files.size(), entry)
	if mode == MODE_RAW:
		for i in payload.size():
			out[start * BLOCK_SIZE + i] = payload[i]
	else:
		for b in size:
			var buf := PackedByteArray()
			buf.resize(36)
			for i in PROTECTED_BLOCK_DATA:
				buf[2 + i] = payload[b * PROTECTED_BLOCK_DATA + i]
			_encode_block(out, (start + b) * BLOCK_SIZE, buf)
	_refresh_counts(out, files.size() + 1)
	return out


## Remove a save and close the gap, as the BIOS's delete does: every later save
## moves down and its entry moves up one slot. The vacated last slot is left as
## it was, which is what the BIOS leaves. Returns a NEW image, or empty.
static func delete_file(data: PackedByteArray, index: int) -> PackedByteArray:
	var files := list_files(data)
	if index < 0 or index >= files.size():
		return PackedByteArray()
	var out := data.duplicate()
	var shift := int(files[index]["size"])
	for j in range(index, files.size() - 1):
		var later: Dictionary = files[j + 1]
		var start := int(later["start"]) - shift
		var size := int(later["size"])
		_write_entry(out, j, _entry_bytes(later["name_bytes"], int(later["mode"]), start, size))
		var moved := out.slice((start + shift) * BLOCK_SIZE, (start + shift + size) * BLOCK_SIZE)
		for i in moved.size():
			out[start * BLOCK_SIZE + i] = moved[i]
	_refresh_counts(out, files.size() - 1)
	return out


# --- One save on its own ------------------------------------------------------

static func make_save(name: String, mode: int, payload: PackedByteArray) -> PackedByteArray:
	var per_block := RAW_BLOCK_DATA if mode == MODE_RAW else PROTECTED_BLOCK_DATA
	var out := PackedByteArray(SCDS_MAGIC)
	var raw_name := name.to_ascii_buffer()
	raw_name.resize(NAME_LEN)
	out.append_array(raw_name)
	out.append(mode & 0xFF)
	@warning_ignore("integer_division")
	var blocks: int = payload.size() / per_block
	out.append((blocks >> 8) & 0xFF)
	out.append(blocks & 0xFF)
	out.append_array(payload)
	return out


## {name: PackedByteArray, mode, blocks, payload}, or {} when this is not one.
static func parse_save(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() <= SCDS_HEADER or bytes.slice(0, SCDS_MAGIC.size()) != PackedByteArray(SCDS_MAGIC):
		return {}
	var mode := bytes[19]
	if mode != MODE_RAW and mode != MODE_PROTECTED:
		return {}
	var blocks := (bytes[20] << 8) | bytes[21]
	var per_block := RAW_BLOCK_DATA if mode == MODE_RAW else PROTECTED_BLOCK_DATA
	if blocks < 1 or bytes.size() != SCDS_HEADER + blocks * per_block:
		return {}
	return {"name": bytes.slice(8, 19), "mode": mode, "blocks": blocks,
		"payload": bytes.slice(SCDS_HEADER)}


static func is_save(bytes: PackedByteArray) -> bool:
	return not parse_save(bytes).is_empty()


# --- Directory ----------------------------------------------------------------

static func _block_count(size: int) -> int:
	@warning_ignore("integer_division")
	return size / BLOCK_SIZE


## Entry k sits in the half-block at size - 0x60 - k*0x20: even entries in a
## block's upper half, odd ones in its lower half.
static func _entry_address(size: int, k: int) -> int:
	return size - 0x60 - k * 0x20


static func _read_entry(data: PackedByteArray, k: int) -> Dictionary:
	var addr := _entry_address(data.size(), k)
	var block := addr & ~(BLOCK_SIZE - 1)
	var decoded := _decode_block(data, block)
	var buf: PackedByteArray = decoded["buf"]
	var off := 2 + ((addr - block) >> 1)
	var name := ""
	for i in NAME_LEN:
		name += String.chr(buf[off + i])
	return {"name": name, "name_bytes": buf.slice(off, off + NAME_LEN), "mode": buf[off + 11],
		"start": (buf[off + 12] << 8) | buf[off + 13],
		"size": (buf[off + 14] << 8) | buf[off + 15],
		"damaged": bool(int(decoded["flags"]) & 12)}


## Write entry k, keeping the other half of its block as it decodes now.
static func _write_entry(data: PackedByteArray, k: int, entry: PackedByteArray) -> void:
	var addr := _entry_address(data.size(), k)
	var block := addr & ~(BLOCK_SIZE - 1)
	var buf: PackedByteArray = _decode_block(data, block)["buf"]
	var off := 2 + ((addr - block) >> 1)
	for i in ENTRY_SIZE:
		buf[off + i] = entry[i]
	_encode_block(data, block, buf)


static func _entry_bytes(name: PackedByteArray, mode: int, start: int, size: int) -> PackedByteArray:
	var e := name.slice(0, NAME_LEN)
	e.resize(NAME_LEN)
	e.append(mode & 0xFF)
	e.append((start >> 8) & 0xFF)
	e.append(start & 0xFF)
	e.append((size >> 8) & 0xFF)
	e.append(size & 0xFF)
	return e


static func _format_tail() -> PackedByteArray:
	var t := _FORMAT_TAIL.to_ascii_buffer()
	t.append_array(PackedByteArray([0x00, 0x01, 0x00, 0x00, 0x00]))
	t.append_array(_MEDIA_TAIL.to_ascii_buffer())
	return t


static func _refresh_counts(data: PackedByteArray, files: int) -> void:
	_write_counts(data, 0, files)
	_write_counts(data, free_blocks(data), files)


static func _write_counts(data: PackedByteArray, free: int, files: int) -> void:
	var top := data.size() - BLOCK_SIZE
	for i in 4:
		data[top + 0x10 + i * 2] = (free >> 8) & 0xFF
		data[top + 0x11 + i * 2] = free & 0xFF
		data[top + 0x18 + i * 2] = (files >> 8) & 0xFF
		data[top + 0x19 + i * 2] = files & 0xFF


## A count stored four times: the value at least three copies agree on, which is
## what the BIOS accepts, or -1.
static func _read_repeat(data: PackedByteArray, at: int) -> int:
	if at < 0 or at + 8 > data.size():
		return -1
	var values: Array[int] = []
	for i in 4:
		values.append((data[at + i * 2] << 8) | data[at + i * 2 + 1])
	for v in values:
		if values.count(v) >= 3:
			return v
	return -1


# --- Error correction (transliterated from buram) -----------------------------

static func _ensure_tables() -> void:
	if not _crc_tab.is_empty():
		return
	_rs8 = _rs_init(0x1D, 8, _RS8_GEN)
	_rs6 = _rs_init(0x03, 6, _RS6_GEN)
	_crc_tab.resize(256)
	for i in 256:
		var d := i << 8
		for j in 8:
			d = ((d << 1) ^ (0x1021 if d & 0x8000 else 0)) & 0xFFFF
		_crc_tab[i] = d


static func _rs_init(poly: int, symsize: int, gen: Array) -> Dictionary:
	var nn := (1 << symsize) - 1
	var index_of := PackedInt32Array()
	var alpha_to := PackedInt32Array()
	index_of.resize(256)
	alpha_to.resize(256)
	var sr := 1
	for i in range(1, nn + 1):
		index_of[sr] = i
		alpha_to[i] = sr
		sr <<= 1
		if sr & (1 << symsize):
			sr ^= poly
		sr &= nn
	return {"nn": nn, "index_of": index_of, "alpha_to": alpha_to, "gen": gen}


static func _rs_add_mod(rs: Dictionary, i: int, d: int) -> int:
	var nn: int = rs["nn"]
	d += int(rs["gen"][i])
	while d >= nn:
		d -= nn
	return (rs["alpha_to"] as PackedInt32Array)[d + 1]


static func _rs_encode(rs: Dictionary, blk: PackedInt32Array) -> void:
	var index_of: PackedInt32Array = rs["index_of"]
	var p1 := 0
	var p2 := 0
	for i in 6:
		var d := blk[i]
		if d:
			d = index_of[d] - 1
			p1 ^= _rs_add_mod(rs, i, d)
			p2 ^= _rs_add_mod(rs, i + 6, d)
	blk[6] = p1
	blk[7] = p2


static func _rs_decode(rs: Dictionary, blk: PackedInt32Array) -> int:
	var nn: int = rs["nn"]
	var index_of: PackedInt32Array = rs["index_of"]
	var alpha_to: PackedInt32Array = rs["alpha_to"]
	var error_mask := 0
	var error_loc := 0
	for i in 8:
		var d := blk[i]
		error_mask ^= d
		if d:
			d = index_of[d] + 6 - i
			while d >= nn:
				d -= nn
			error_loc ^= alpha_to[d + 1]
	if error_mask:
		var d := nn + index_of[error_loc] - index_of[error_mask]
		while d >= nn:
			d -= nn
		if d < 8:
			blk[7 - d] ^= error_mask
			return 1 << 1
		return 1 << 2
	return 0


static func _crc(buf: PackedByteArray, at: int) -> int:
	var d := 0
	for i in 32:
		d = ((d << 8) ^ _crc_tab[buf[at + i] ^ (d >> 8)]) & 0xFFFF
	return d


static func _interleave_data(inb: PackedByteArray, out: PackedByteArray) -> void:
	var p := 0
	var o := 0
	for i in 12:
		var sr := inb[p]
		p += 1
		out[o] = sr & 0xFF
		sr = ((sr << 8) | inb[p]) & 0xFFFF
		p += 1
		out[o + 1] = (sr >> 2) & 0xFF
		sr = ((sr << 8) | inb[p]) & 0xFFFF
		p += 1
		out[o + 2] = (sr >> 4) & 0xFF
		out[o + 3] = (sr << 2) & 0xFF
		o += 4


static func _deinterleave_data(inb: PackedByteArray, out: PackedByteArray) -> void:
	var p := 0
	var o := 0
	for i in 12:
		var sr := inb[p]
		p += 1
		sr = (sr << 6) & 0xFFFF
		sr = (sr & 0xFF00) | inb[p]
		p += 1
		out[o] = (sr >> 6) & 0xFF
		sr = (sr << 6) & 0xFFFF
		sr = (sr & 0xFF00) | inb[p]
		p += 1
		out[o + 1] = (sr >> 4) & 0xFF
		sr = (sr << 6) & 0xFFFF
		sr = (sr & 0xFF00) | inb[p]
		p += 1
		out[o + 2] = (sr >> 2) & 0xFF
		o += 3


static func _interleave_rs6(block: int, blk: PackedInt32Array, out: PackedByteArray) -> void:
	for i in 5:
		out[block + i * 9] = (blk[i] << 2) & 0xFF
	out[_LAST_RS6_BYTE[block]] = (blk[5] << 2) & 0xFF
	out[0x30 + block] = (blk[6] << 2) & 0xFF
	out[0x38 + block] = (blk[7] << 2) & 0xFF


static func _deinterleave_rs6(block: int, inb: PackedByteArray, blk: PackedInt32Array) -> void:
	for i in 5:
		blk[i] = inb[block + i * 9] >> 2
	blk[5] = inb[_LAST_RS6_BYTE[block]] >> 2
	blk[6] = inb[0x30 + block] >> 2
	blk[7] = inb[0x38 + block] >> 2


static func _interleave_rs8(block: int, blk: PackedInt32Array, out: PackedByteArray) -> void:
	for i in 8:
		var tmp := blk[i]
		for j in 8:
			out[block + j * 8] = ((out[block + j * 8] << 1) | (tmp >> 7)) & 0xFF
			tmp = (tmp << 1) & 0xFF


static func _deinterleave_rs8(block: int, inb: PackedByteArray, blk: PackedInt32Array) -> void:
	for i in 8:
		blk[i] = 0
	for i in 8:
		var tmp := inb[block + i * 8]
		for j in 8:
			blk[j] = ((blk[j] << 1) | (tmp >> 7)) & 0xFF
			tmp = (tmp << 1) & 0xFF


## Encode 36 bytes (32 of data at 2..33; the CRC is filled in) into the 64-byte
## block at `at`.
static func _encode_block(data: PackedByteArray, at: int, buf: PackedByteArray) -> void:
	_ensure_tables()
	var crc := _crc(buf, 2)
	buf[0] = crc >> 8
	buf[1] = crc & 0xFF
	buf[34] = ~buf[0] & 0xFF
	buf[35] = ~buf[1] & 0xFF
	var out := PackedByteArray()
	out.resize(BLOCK_SIZE)
	_interleave_data(buf, out)
	var blk := PackedInt32Array()
	blk.resize(8)
	for block in 8:
		_deinterleave_rs6(block, out, blk)
		_rs_encode(_rs6, blk)
		_interleave_rs6(block, blk, out)
	for block in 8:
		_deinterleave_rs8(block, out, blk)
		_rs_encode(_rs8, blk)
		_interleave_rs8(block, blk, out)
	for i in BLOCK_SIZE:
		data[at + i] = out[i]


## Decode the 64-byte block at `at`: {buf: 36 bytes, flags}. Flags 2 = corrected,
## 4 = found but not corrected, 8 = both CRC copies disagree.
static func _decode_block(data: PackedByteArray, at: int) -> Dictionary:
	_ensure_tables()
	var inb := data.slice(at, at + BLOCK_SIZE)
	var blk := PackedInt32Array()
	blk.resize(8)
	var flags := 0
	for block in 8:
		_deinterleave_rs8(block, inb, blk)
		flags |= _rs_decode(_rs8, blk)
		_interleave_rs8(block, blk, inb)
	for block in 8:
		_deinterleave_rs6(block, inb, blk)
		flags |= _rs_decode(_rs6, blk)
		_interleave_rs6(block, blk, inb)
	var buf := PackedByteArray()
	buf.resize(36)
	_deinterleave_data(inb, buf)
	var crc := _crc(buf, 2)
	var check1 := (buf[0] << 8) | buf[1]
	var check2 := ~((buf[34] << 8) | buf[35]) & 0xFFFF
	if crc != check1 and crc != check2:
		flags |= 8
	return {"buf": buf, "flags": flags}
