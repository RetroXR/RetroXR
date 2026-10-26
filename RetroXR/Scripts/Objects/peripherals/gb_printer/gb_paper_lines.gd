## GbPaperLines — the strip out of a Game Boy Printer, kept by the room.
##
## The core sent the whole strip every time it changed, one row a line: some
## 2.6 MB a frame at 56 cm, re-uploaded whole for the two or three lines that
## were new, and as a new texture each time, since the frame grew a row at a
## time. Asked for "window" frames (OPTION) it sends a frame that never changes
## size instead: a header row saying which lines are out of the slot and which
## are in the rows below it, then those rows (gbprinter-libretro, libretro.c
## OPT_FRAMES). The newest go whenever the strip changes; once it stops, older
## windows follow back over what the core keeps, so lines a frame the room never
## saw carried are not lost.
##
## This keeps every line it is sent by the printer's own numbering, in chunks of
## CHUNK lines, one layer of a Texture2DArray each, so a frame uploads only the
## chunk it touched however long the paper is. The core keeps only its newest
## lines, so the strip can be far longer than it: MAX_LINES.
class_name GbPaperLines
extends RefCounted

## The core option that asks for window frames, and its value.
const OPTION := "gbprinter_paper_frames"
const WINDOWS := "window"
## The header's first two values: what says a frame is a window.
const MAGIC := 0x475042
const FORMAT := 1
## Lines a layer.
const CHUNK := 256
## The most lines the core lets out of the slot in window frames
## (GBP_STRIP_LONG), about 9 m: 255 chunks, so the strip never spans more than
## MAX_LAYERS layers, the most every GPU takes in one array.
const MAX_LINES := 255 * CHUNK
const MAX_LAYERS := 256
## TEAR says where the strip it captured ended as 1 + that line modulo this, in
## LY (gbp_tear_to).
const TEAR_MOD := 32767

## The strip: lines [first, end), numbered from the first the printer burned.
var first := 0
var end := 0
## Its lines as layers, chunk c at layer c % layers.
var texture: Texture2DArray = null
var layers := 0

var _chunks := {}
var _dirty := {}
var _header := PackedByteArray()


func lines() -> int:
	return end - first


## Nothing kept: a printer switched on again starts its numbering again.
func clear() -> void:
	first = 0
	end = 0
	_chunks.clear()
	_dirty.clear()
	_header = PackedByteArray()
	# Its layers hold the old strip, and a chunk not sent yet would show it.
	texture = null
	layers = 0


## Read the core's frame: -1 when it is not a window (a core that sends the
## whole strip), 0 when it is the one already read, 1 when it is new.
func take(img: Image) -> int:
	if img == null or img.is_empty() or img.get_width() != GbPrinterPaper.DOTS \
			or img.get_height() < 2:
		return -1
	var head := img.get_region(Rect2i(0, 0, 9, 1))
	if head.get_format() != Image.FORMAT_RGBA8:
		head.convert(Image.FORMAT_RGBA8)
	var h := head.get_data()
	if _value(h, 0) != MAGIC or _value(h, 1) != FORMAT:
		return -1
	if h == _header:
		return 0
	var new_first := _value(h, 2) | (_value(h, 3) << 24)
	var new_end := _value(h, 4) | (_value(h, 5) << 24)
	var from := _value(h, 6) | (_value(h, 7) << 24)
	var rows := mini(_value(h, 8), img.get_height() - 1)
	if new_end < end:
		# The strip went back: a core started again, or a state from before.
		clear()
	_header = h
	first = new_first
	end = new_end
	# Torn off.
	for c: int in _chunks.keys():
		if (c + 1) * CHUNK <= first:
			_chunks.erase(c)
			_dirty.erase(c)
	if rows <= 0:
		return 1
	var block := img.get_region(Rect2i(0, 1, GbPrinterPaper.DOTS, rows))
	block.convert(Image.FORMAT_L8)
	var k := 0
	while k < rows:
		var n := from + k
		var r := n % CHUNK
		var count := mini(rows - k, CHUNK - r)
		@warning_ignore("integer_division")
		var c := n / CHUNK
		if (c + 1) * CHUNK > first:
			_chunk(c).blit_rect(block, Rect2i(0, k, GbPrinterPaper.DOTS, count), Vector2i(0, r))
			_dirty[c] = true
		k += count
	return 1


## Bring the texture up to what has been read. True when it is a new texture,
## which the material then has to be given.
func upload() -> bool:
	@warning_ignore("integer_division")
	var lo := first / CHUNK
	@warning_ignore("integer_division")
	var hi := maxi(lo, (end - 1) / CHUNK) if end > first else lo
	var span := hi - lo + 1
	if texture != null and span <= layers:
		for c: int in _dirty:
			texture.update_layer(_chunks[c], c % layers)
		_dirty.clear()
		return false
	var want := 4
	while want < span:
		want *= 2
	layers = mini(want, MAX_LAYERS)
	var blank := _blank()
	var images: Array[Image] = []
	for i in layers:
		images.append(blank)
	for c: int in _chunks:
		if c >= lo and c <= hi:
			images[c % layers] = _chunks[c]
	texture = Texture2DArray.new()
	texture.create_from_images(images)
	_dirty.clear()
	return true


## The strip as one image, oldest line at the top, DOTS wide, grey (L8): what a
## torn print is made from. A line never sent is bare paper. Null with nothing out.
func image() -> Image:
	var n := lines()
	if n <= 0:
		return null
	var out := Image.create(GbPrinterPaper.DOTS, n, false, Image.FORMAT_L8)
	out.fill(Color.WHITE)
	var k := 0
	while k < n:
		var line := first + k
		var r := line % CHUNK
		var count := mini(n - k, CHUNK - r)
		@warning_ignore("integer_division")
		var chunk: Image = _chunks.get(line / CHUNK)
		if chunk != null:
			out.blit_rect(chunk, Rect2i(0, r, GbPrinterPaper.DOTS, count), Vector2i(0, k))
		k += count
	return out


## What TEAR's LY says to tear everything this has: 1 + end modulo TEAR_MOD.
func tear_code() -> int:
	return 1 + end % TEAR_MOD


func _chunk(c: int) -> Image:
	var img: Image = _chunks.get(c)
	if img == null:
		img = _blank()
		_chunks[c] = img
	return img


static func _blank() -> Image:
	var img := Image.create(GbPrinterPaper.DOTS, CHUNK, false, Image.FORMAT_L8)
	img.fill(Color.WHITE)
	return img


## Header value `i`: 24 bits, R high.
static func _value(h: PackedByteArray, i: int) -> int:
	return (h[i * 4] << 16) | (h[i * 4 + 1] << 8) | h[i * 4 + 2]
