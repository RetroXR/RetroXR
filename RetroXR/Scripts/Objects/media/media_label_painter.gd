## MediaLabelPainter — RetroXR's own labels for an album with no pictures: a cassette's side A and side B (the striped
## RETRO XR label: the album's name on the writing strip, the side in a circle and the tape in a plate either side of
## the window, the maker's line along the foot) and an LP's (a round label, warm red for side A, blue for side B).
##
## The name is fitted by `fit_name` (pure: one line, then without its trailing brackets, then more lines, then cut
## with "..."), and the label is drawn ONCE on a small off-screen canvas (a SubViewport, as VfdDisplay draws its
## display), read back into an ImageTexture with mipmaps, and the canvas freed. Labels are cached by what they show,
## so every copy of an album shares its two textures. One label is drawn at a time.
##
## A medium asks for one only for a side with no picture of its own (`MediaLabelArt.album_side` found none), so an
## album's own `cover` / `back` always wins. Nothing is written to disk and nothing goes on the wire: every peer
## draws the same label from the same name. The layout is the mock-up the player approved (2026-11-07/08).
class_name MediaLabelPainter
extends RefCounted

const FONT_PATH := "res://fonts/Michroma-Regular.ttf"
## Michroma's capital height, as a share of the font size (measured: 750 of 1000 units for "H").
const CAP_EM := 0.75
## The tallest capital the tape plate uses ("C" stands a little taller than "H").
const CAP_EM_C := 0.782

const PAPER := Color8(232, 226, 207)
const INK := Color8(34, 32, 38)
const RULE := Color8(150, 144, 130)
## Side A warm, side B cool: the 80s stripe sets.
const STRIPES := {
	"A": [Color8(255, 190, 60), Color8(250, 130, 45), Color8(232, 70, 60), Color8(196, 40, 92)],
	"B": [Color8(120, 220, 210), Color8(60, 170, 205), Color8(60, 110, 190), Color8(92, 62, 160)],
}
const LP_GROUND := {"A": Color8(196, 40, 70), "B": Color8(36, 70, 150)}

## The cassette's label is the model's LabelA / LabelB: 89.6 x 40.4 mm, its window cut out of the mesh at these
## shares of its width and height (measured from the mesh's UVs).
const CASSETTE_MM := Vector2(89.6, 40.4)
const CASSETTE_PX := 1024
const WINDOW := Rect2(0.165, 0.37, 0.67, 0.42)
const LP_PX := 512

static var _cache := {}
## Labels being drawn now: a second ask for one waits for it rather than drawing it again.
static var _drawing := {}
static var _busy := false
static var _font: Font = null


## The album's name fitted to a box: {lines: PackedStringArray, size: int}. Tried in order, each at the largest
## size that fits `max_w` wide and `max_h` tall: one line (not under 3/4 of `px`); one line without its trailing
## bracketed groups ("(Remastered 2011)", "[Deluxe Edition]"); then 2 .. `max_lines` lines split by words as evenly
## as can be (not under `min_px`), the full name before the bracket-less one. Nothing fits: `max_lines` lines at
## `min_px`, the last cut with "...".
static func fit_name(font: Font, text: String, max_w: float, max_h: float, px: int, min_px: int,
		max_lines: int) -> Dictionary:
	const LEAD := 1.15
	var cands: Array[String] = [text]
	var stripped := strip_brackets(text)
	if stripped != text:
		cands.append(stripped)
	for n in range(1, max_lines + 1):
		var floor_px := int(px * 0.75) if n == 1 else min_px
		for t in cands:
			var size := mini(px, int(max_h / (n * LEAD)))
			while size >= floor_px:
				var lines := PackedStringArray([t]) if n == 1 else split_even(font, t, size, n)
				if not lines.is_empty() and _widest(font, lines, size) <= max_w:
					return {"lines": lines, "size": size}
				size -= 2
	var words := Array(stripped.split(" ", false))
	var out := PackedStringArray()
	while not words.is_empty() and out.size() < max_lines:
		var line := ""
		while not words.is_empty() and _width(font, (line + " " + words[0]).strip_edges(), min_px) <= max_w:
			line = (line + " " + words.pop_front()).strip_edges()
		if line.is_empty():
			line = words.pop_front()       # one word wider than the box
		out.append(line)
	if not words.is_empty():
		# Cut at a word: drop whole words from the end; a single word still too wide loses letters.
		var tail := Array((out[out.size() - 1] + " " + " ".join(PackedStringArray(words))).split(" ", false))
		while tail.size() > 1 and _width(font, " ".join(PackedStringArray(tail)) + "...", min_px) > max_w:
			tail.pop_back()
		var last := " ".join(PackedStringArray(tail))
		while not last.is_empty() and _width(font, last + "...", min_px) > max_w:
			last = last.substr(0, last.length() - 1).strip_edges()
		out[out.size() - 1] = last + "..."
	return {"lines": out, "size": min_px}


## The album's name as the cassette label fits it on its writing strip (two lines at most), for a label `px` wide.
static func cassette_name_fit(title: String, px: float = CASSETTE_PX) -> Dictionary:
	var mm := px / CASSETTE_MM.x
	return fit_name(font(), title.to_upper(), px - 8.0 * mm, 9.0 * mm, int(5.2 * mm), int(2.6 * mm), 2)


## The album's name as the LP label fits it above the spindle (three lines at most), for a label `px` across.
static func lp_name_fit(title: String, px: float = LP_PX) -> Dictionary:
	var k := px / 1024.0
	return fit_name(font(), title.to_upper(), 600.0 * k, 146.0 * k * 0.9, int(64.0 * k), int(34.0 * k), 3)


## `text` without its trailing (...) / [...] groups, as file names carry them; the text itself if that leaves nothing.
static func strip_brackets(text: String) -> String:
	var re := RegEx.create_from_string("\\s*[\\(\\[][^\\)\\]]*[\\)\\]]\\s*$")
	var out := text
	while true:
		var cut := re.sub(out, "")
		if cut == out or cut.strip_edges().is_empty():
			return out
		out = cut
	return out


## `text` in `n` lines by words, the widest as narrow as it can be; empty when it has fewer than `n` words.
static func split_even(font: Font, text: String, size: int, n: int) -> PackedStringArray:
	var words := text.split(" ", false)
	if words.size() < n:
		return PackedStringArray()
	var best := PackedStringArray()
	var best_w := INF
	var cuts := []
	for i in range(n - 1):
		cuts.append(i + 1)
	while true:
		var lines := PackedStringArray()
		var start := 0
		for c: int in cuts:
			lines.append(" ".join(words.slice(start, c)))
			start = c
		lines.append(" ".join(words.slice(start)))
		var w := _widest(font, lines, size)
		if w < best_w:
			best_w = w
			best = lines
		# The next set of cut points, in order (all ways of cutting len(words) into n non-empty runs).
		var k := cuts.size() - 1
		while k >= 0 and cuts[k] == words.size() - (cuts.size() - k):
			k -= 1
		if k < 0:
			break
		cuts[k] += 1
		for j in range(k + 1, cuts.size()):
			cuts[j] = cuts[j - 1] + 1
	return best


static func font() -> Font:
	if _font == null:
		_font = load(FONT_PATH) as Font
	return _font


static func _width(f: Font, text: String, size: int) -> float:
	return f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


static func _widest(f: Font, lines: PackedStringArray, size: int) -> float:
	var w := 0.0
	for l in lines:
		w = maxf(w, _width(f, l, size))
	return w


## A cassette's label for `side` ("A" / "B") of the album named `title`, on a tape called `tape` ("C46"); drawn
## under `host` (any node in the tree) and cached. Null when nothing could be drawn (no renderer).
static func cassette(host: Node, side: String, title: String, tape: String) -> Texture2D:
	var key := "cassette|%s|%s|%s" % [side, title, tape]
	if await _wait_for_other(host, key):
		return _cache.get(key)
	_drawing[key] = true
	var w := CASSETTE_PX
	var h := roundi(CASSETTE_PX * CASSETTE_MM.y / CASSETTE_MM.x)
	# The label's top-left corner is paper: what a drawn canvas must show there.
	var tex := await _draw(host, Vector2i(w, h), false,
		func(c: Control) -> void: _paint_cassette(c, Vector2(w, h), side, title, tape), Vector2i(3, 3), PAPER)
	_drawing.erase(key)
	if tex != null:
		_cache[key] = tex
	print("[LabelPainter] cassette side %s for \"%s\" (%s): %s" % [side, title, tape,
		"%dx%d" % [w, h] if tex != null else "not drawn"])
	return tex


## An LP's round label for `side` of the album named `title`; transparent outside the circle. Cached.
static func lp(host: Node, side: String, title: String) -> Texture2D:
	var key := "lp|%s|%s" % [side, title]
	if await _wait_for_other(host, key):
		return _cache.get(key)
	_drawing[key] = true
	# Inside the rings, below and right of everything printed: the side's ground.
	var tex := await _draw(host, Vector2i(LP_PX, LP_PX), true,
		func(c: Control) -> void: _paint_lp(c, float(LP_PX), side, title), Vector2i(roundi(LP_PX * 0.77), roundi(LP_PX * 0.77)),
		LP_GROUND[side])
	_drawing.erase(key)
	if tex != null:
		_cache[key] = tex
	print("[LabelPainter] LP side %s for \"%s\": %s" % [side, title, "drawn" if tex != null else "not drawn"])
	return tex


## True when `key` is drawn already, or was being drawn and is done now (cached, or failed: then null is the answer).
static func _wait_for_other(host: Node, key: String) -> bool:
	if _cache.has(key):
		return true
	if not _drawing.has(key) or host == null or not host.is_inside_tree():
		return false
	var tree := host.get_tree()
	while _drawing.has(key):
		await tree.process_frame
	return true


## Draw on a canvas of `size` under `host`, read it back with mipmaps, free the canvas. One at a time.
## The read is CHECKED: the pixel at `probe` must be `want` (the label's own paper or ground there). A canvas read
## before it has drawn holds whatever the GPU memory it was given last held -- measured: a cassette deck's VFD, freed
## the frame before, came back as an LP's label -- so the canvas draws every frame for a few frames, and a read that
## fails the check is drawn again (twice), then logged.
## With no renderer to read back from (a headless run: a suite) the label is a plain card of the right size and
## colour, so everything that wears one is exercised all the same; how it LOOKS is a windowed probe's to show.
static func _draw(host: Node, size: Vector2i, transparent: bool, paint: Callable, probe: Vector2i,
		want: Color) -> Texture2D:
	if host == null or not host.is_inside_tree():
		push_warning("[LabelPainter] no host in the tree to draw on")
		return null
	if DisplayServer.get_name() == "headless":
		var card := Image.create(size.x, size.y, true, Image.FORMAT_RGBA8)
		card.fill(Color(0, 0, 0, 0) if transparent else PAPER)
		return ImageTexture.create_from_image(card)
	var tree := host.get_tree()
	while _busy:
		await tree.process_frame
	if not is_instance_valid(host) or not host.is_inside_tree():
		return null
	_busy = true
	var img: Image = null
	for attempt in 3:
		var vp := SubViewport.new()
		vp.name = "LabelCanvas"
		vp.size = size
		vp.disable_3d = true
		vp.transparent_bg = transparent
		vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		var canvas := Control.new()
		canvas.size = Vector2(size)
		canvas.draw.connect(func() -> void: paint.call(canvas))
		vp.add_child(canvas)
		host.add_child(vp)
		for i in 3:
			await RenderingServer.frame_post_draw
		img = vp.get_texture().get_image() if is_instance_valid(vp) else null
		if is_instance_valid(vp):
			vp.queue_free()
		if img != null and not img.is_empty() and _near(img.get_pixelv(probe), want):
			break
		push_warning("[LabelPainter] the canvas read back wrong (attempt %d: %s at %s, want %s); drawing it again"
			% [attempt + 1, img.get_pixelv(probe) if img != null and not img.is_empty() else "nothing", probe, want])
		if not is_instance_valid(host) or not host.is_inside_tree():
			img = null
			break
	_busy = false
	if img == null or img.is_empty():
		push_warning("[LabelPainter] the canvas gave no picture (size %s)" % size)
		return null
	img.convert(Image.FORMAT_RGBA8)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.06 and absf(a.g - b.g) < 0.06 and absf(a.b - b.b) < 0.06


static func _text_centred(c: Control, f: Font, text: String, cx: float, baseline: float, size: int, col: Color) -> void:
	c.draw_string(f, Vector2(cx - _width(f, text, size) / 2.0, baseline), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


## `lines` centred between `top` and `bottom` by the capitals' own height, as the mock-up laid them.
static func _block(c: Control, f: Font, lines: PackedStringArray, size: int, cx: float, top: float, bottom: float,
		col: Color) -> void:
	var cap := size * CAP_EM
	var gap := size * 0.42
	var total := lines.size() * cap + (lines.size() - 1) * gap
	var y := top + (bottom - top - total) / 2.0 + cap
	for line in lines:
		_text_centred(c, f, line, cx, y, size, col)
		y += cap + gap


static func _box(c: Control, rect: Rect2, fill: Color, radius: float, border: Color = Color.TRANSPARENT,
		width: float = 0.0) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(int(radius))
	sb.corner_detail = 16
	sb.anti_aliasing = true
	if width > 0.0:
		sb.border_color = border
		sb.set_border_width_all(int(round(width)))
	c.draw_style_box(sb, rect)


static func _paint_cassette(c: Control, px: Vector2, side: String, title: String, tape: String) -> void:
	var f := font()
	var mm := px.x / CASSETTE_MM.x
	var w := px.x
	var h := px.y
	c.draw_rect(Rect2(Vector2.ZERO, px), PAPER)
	# The writing strip above the rule, 0.6 mm kept clear at the top: the album's name, up to two lines.
	var fit := cassette_name_fit(title, w)
	_block(c, f, fit["lines"], int(fit["size"]), w / 2.0, 0.6 * mm, 11.0 * mm, INK)
	c.draw_line(Vector2(4.0 * mm, 11.6 * mm), Vector2(w - 4.0 * mm, 11.6 * mm), RULE, maxf(1.0, 0.15 * mm))
	# Everything in the window band about the window's own middle line.
	var win := Rect2(WINDOW.position.x * w, WINDOW.position.y * h, WINDOW.size.x * w, WINDOW.size.y * h)
	var yc := win.get_center().y
	var sw := 2.0 * mm
	var gap := 3.1 * mm
	var cols: Array = STRIPES[side]
	for i in cols.size():
		var y0 := yc - gap - (cols.size() - i) * sw
		c.draw_rect(Rect2(0.0, y0, w, sw - maxf(1.0, 0.1 * mm)), cols[i])
		var y1 := yc + gap + i * sw
		c.draw_rect(Rect2(0.0, y1, w, sw - maxf(1.0, 0.1 * mm)), cols[i])
	# The window is cut out of the mesh: paper here only keeps a stripe from showing at its edge.
	_box(c, win, PAPER, 8.4 * mm)
	# Two badges of one size either side of the window, each in the middle of the paper between the label's edge and
	# the window's end: the side in a circle, the tape in a plate. One outline weight for both.
	var bh := 10.0 * mm
	var line := 0.28 * mm
	var lx := win.position.x / 2.0
	var rx := w - (w - win.end.x) / 2.0
	c.draw_circle(Vector2(lx, yc), bh / 2.0, PAPER)
	c.draw_arc(Vector2(lx, yc), bh / 2.0 - line / 2.0, 0.0, TAU, 96, INK, line, true)
	var letter := int(6.0 * mm)
	_text_centred(c, f, side, lx, yc + letter * CAP_EM / 2.0, letter, INK)
	_box(c, Rect2(rx - bh / 2.0, yc - bh / 2.0, bh, bh), PAPER, 1.6 * mm, INK, line)
	var big := int(2.5 * mm)
	var small := int(1.5 * mm)
	var big_h := big * CAP_EM_C
	var small_h := small * CAP_EM
	var between := 1.1 * mm
	var top := yc - (big_h + between + small_h) / 2.0
	_text_centred(c, f, tape, rx, top + big_h, big, INK)
	_text_centred(c, f, "TYPE II", rx, top + big_h + between + small_h, small, INK)
	# The maker's line along the foot.
	c.draw_string(f, Vector2(4.0 * mm, h - 2.2 * mm), "RETRO XR", HORIZONTAL_ALIGNMENT_LEFT, -1, int(2.6 * mm), INK)
	var foot := "SIDE %s  ·  STEREO" % side
	var fs := int(1.9 * mm)
	c.draw_string(f, Vector2(w - 4.0 * mm - _width(f, foot, fs), h - 2.2 * mm), foot, HORIZONTAL_ALIGNMENT_LEFT, -1,
		fs, INK)


static func _paint_lp(c: Control, s: float, side: String, title: String) -> void:
	var f := font()
	var k := s / 1024.0                 # the mock-up was drawn 1024 across
	var o := Vector2(s, s) / 2.0
	var ground: Color = LP_GROUND[side]
	c.draw_circle(o, s / 2.0, ground)
	var cols: Array = STRIPES[side]
	for i in cols.size():
		var rr := s / 2.0 - 18.0 * k - i * 22.0 * k
		c.draw_arc(o, rr - 8.0 * k, 0.0, TAU, 128, cols[i], 16.0 * k, true)
	var inner := s / 2.0 - 18.0 * k - cols.size() * 22.0 * k
	c.draw_circle(o, inner, ground)
	var brand := int(64.0 * k)
	_text_centred(c, f, "RETRO XR", o.x, o.y - 300.0 * k + brand * CAP_EM / 2.0, brand, PAPER)
	c.draw_line(Vector2(o.x - 230.0 * k, o.y - 250.0 * k), Vector2(o.x + 230.0 * k, o.y - 250.0 * k), PAPER,
		maxf(1.0, 3.0 * k))
	# Between the rule under RETRO XR and the paper round the spindle: up to three lines.
	var top := o.y - 232.0 * k
	var bottom := o.y - 86.0 * k
	var fit := lp_name_fit(title, s)
	_block(c, f, fit["lines"], int(fit["size"]), o.x, top, bottom, PAPER)
	c.draw_arc(o, 70.0 * k, 0.0, TAU, 96, PAPER, maxf(1.0, 3.0 * k), true)
	for row: Array in [["SIDE", -240.0, 30.0, 34.0], [side, -240.0, 100.0, 110.0], ["33 1/3", 240.0, 30.0, 44.0],
			["RPM", 240.0, 90.0, 34.0], ["STEREO  ·  LONG PLAY", 0.0, 260.0, 30.0]]:
		var size := int(float(row[3]) * k)
		_text_centred(c, f, str(row[0]), o.x + float(row[1]) * k, o.y + float(row[2]) * k + size * CAP_EM / 2.0, size,
			PAPER)
