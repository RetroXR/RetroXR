extends RefCounted
## Pure line-based pagination for text (epub) pages in the 3D reader (src/ui/reader.gd).
## A RichTextLabel lays a chapter out once at page width; this takes the resulting line
## offsets and cuts them into runs of whole lines that fit a page height, so no line is
## ever sliced in half at a page break. No Node, no I/O - unit tested directly.

const EPSILON := 0.01


## `line_offsets[i]` is the y of the top of line i (ascending), `content_height` the
## bottom of the last line. Returns the first line index of every page; empty when there
## are no lines (the caller then shows one blank page). A single line taller than a page
## still gets a page of its own rather than being dropped.
static func page_starts(line_offsets: PackedFloat32Array, content_height: float, page_height: float) -> PackedInt32Array:
	var starts := PackedInt32Array()
	var count: int = line_offsets.size()
	if count == 0:
		return starts
	starts.append(0)
	if page_height <= 0.0:
		return starts
	var page_top: float = line_offsets[0]
	for i in range(1, count):
		var line_bottom: float = line_offsets[i + 1] if i + 1 < count else content_height
		if line_bottom - page_top > page_height + EPSILON:
			starts.append(i)
			page_top = line_offsets[i]
	return starts


## [first_line, end_line) of page `page` given page_starts() output and the line count.
static func page_range(starts: PackedInt32Array, page: int, line_count: int) -> Vector2i:
	if starts.is_empty() or page < 0 or page >= starts.size():
		return Vector2i(0, 0)
	var first: int = starts[page]
	var end: int = starts[page + 1] if page + 1 < starts.size() else line_count
	return Vector2i(first, maxi(end, first))
