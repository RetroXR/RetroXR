## MediaLabelPainter — RetroXR's own labels for an album with no pictures: a cassette's side A and side B (the striped
## RETRO XR label: the album's name on the writing strip, the side in a circle and the tape in a plate either side of
## the window, the maker's line along the foot), an LP's (a round label, warm red for side A, blue for side B) and a
## video tape's face and spine (the cassette's paper and badges, its stripes running warm into cool, as a tape has no
## sides: the speed in a circle and the tape, T-120, in a plate), and an audio CD's printed face (the name and one
## stripe band in ink on the bare silver: transparent wherever it is not printed, so the disc's own lacquer shows).
##
## The name is fitted by `fit_name` (pure: one line, then without its trailing brackets, then more lines, then cut
## with "..."), and the label is drawn ONCE on a small off-screen canvas (a SubViewport, as VfdDisplay draws its
## display), read back into an ImageTexture with mipmaps, and the canvas freed. Labels are cached by what they show,
## so every copy of an album shares its two textures. One label is drawn at a time.
##
## A medium asks for one only for a side with no picture of its own (`MediaLabelArt.album_side` found none), so an
## album's own `cover` / `back` always wins. Nothing is written to disk and nothing goes on the wire: every peer
## draws the same label from the same name. The layout is the mock-up the player approved (2026-11-07/08; the video
## tape's, concept A, and the CD's, concept B, 2026-11-17).
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
## A video tape has no sides: side A's set into side B's, run back, so the band goes yellow .. magenta .. violet .. teal.
const SWEEP := [Color8(255, 190, 60), Color8(250, 130, 45), Color8(232, 70, 60), Color8(196, 40, 92),
	Color8(92, 62, 160), Color8(60, 110, 190), Color8(60, 170, 205), Color8(120, 220, 210)]

## The cassette's label is the model's LabelA / LabelB: 89.6 x 40.4 mm, its window cut out of the mesh at these
## shares of its width and height (measured from the mesh's UVs).
const CASSETTE_MM := Vector2(89.6, 40.4)
const CASSETTE_PX := 1024
const WINDOW := Rect2(0.165, 0.37, 0.67, 0.42)
const LP_PX := 512
## A video tape's labels are drawn the shape of the paper VCRTape fits a picture in (its _ART_BOX / _SPINE_BOX), so a
## drawn one fills it as a picture of that shape would.
const VHS_FACE_MM := Vector2(78.0, 46.0)
const VHS_SPINE_MM := Vector2(148.0, 19.0)
const VHS_PX := 1024
## An audio CD's face covers the disc's bounding square, as the disc shader's label UV does: 120 mm across. The shader
## prints it only from the mirror band to the rim (AudioDisc.PRINT_FROM, r_data_end), so the face is drawn edge to
## edge and the hub and rim are the shader's to keep clear.
const CD_MM := 120.0
const CD_PX := 1024

static var _cache := {}
## A case's paper is kept as a picture (case_sheet), by the same key.
static var _sheets := {}
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


## The video's name as the tape's face fits it on its writing strip (two lines at most), for a face `px` wide.
static func vhs_face_name_fit(title: String, px: float = VHS_PX) -> Dictionary:
	var mm := px / VHS_FACE_MM.x
	return fit_name(font(), title.to_upper(), px - 8.0 * mm, 10.5 * mm, int(5.4 * mm), int(2.7 * mm), 2)


## The video's name as the spine fits it between its stripes and its plate (two lines at most), for a spine `px` long.
static func vhs_spine_name_fit(title: String, px: float = VHS_PX) -> Dictionary:
	var mm := px / VHS_SPINE_MM.x
	return fit_name(font(), title.to_upper(), 110.0 * mm, 12.0 * mm, int(6.6 * mm), int(3.2 * mm), 2)


## The album's name as the CD's face fits it above the hub (three lines at most), for a face `px` across.
static func cd_name_fit(title: String, px: float = CD_PX) -> Dictionary:
	var mm := px / CD_MM
	return fit_name(font(), title.to_upper(), 60.0 * mm, 24.0 * mm, int(6.4 * mm), int(3.0 * mm), 3)


## What a CD's face says under its name: "12 TRACKS  ·  46:20"; just the tracks while the length is not known.
static func cd_details(tracks: int, seconds: float) -> String:
	if tracks <= 0:
		return ""
	var count := "%d TRACK%s" % [tracks, "" if tracks == 1 else "S"]
	var s := roundi(seconds)
	if s <= 0:
		return count
	@warning_ignore("integer_division")
	return "%s  ·  %d:%02d" % [count, s / 60, s % 60]


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


## A video tape's face label for the video named `title`, on a tape called `tape` ("T-120"). Cached.
static func vhs_face(host: Node, title: String, tape: String) -> Texture2D:
	return await _vhs(host, "face", title, tape, VHS_FACE_MM, Vector2i(3, 3),
		func(c: Control, px: Vector2) -> void: _paint_vhs_face(c, px, title, tape))


## A video tape's spine label, the one a deck and a shelf show. Cached.
static func vhs_spine(host: Node, title: String, tape: String) -> Texture2D:
	# Probed on the paper between the stripes and the name, 14 mm in and clear of the top edge.
	return await _vhs(host, "spine", title, tape, VHS_SPINE_MM, Vector2i(roundi(14.0 * VHS_PX / VHS_SPINE_MM.x), 3),
		func(c: Control, px: Vector2) -> void: _paint_vhs_spine(c, px, title, tape))


static func _vhs(host: Node, part: String, title: String, tape: String, size_mm: Vector2, probe: Vector2i,
		paint: Callable) -> Texture2D:
	var key := "vhs|%s|%s|%s" % [part, title, tape]
	if await _wait_for_other(host, key):
		return _cache.get(key)
	_drawing[key] = true
	var px := Vector2(VHS_PX, roundi(VHS_PX * size_mm.y / size_mm.x))
	var tex := await _draw(host, Vector2i(px), false, func(c: Control) -> void: paint.call(c, px), probe, PAPER)
	_drawing.erase(key)
	if tex != null:
		_cache[key] = tex
	print("[LabelPainter] VHS %s for \"%s\" (%s): %s" % [part, title, tape,
		"%dx%d" % [px.x, px.y] if tex != null else "not drawn"])
	return tex


## An audio CD's printed face for the album named `title`, `details` under it (cd_details). Cached.
static func cd(host: Node, title: String, details: String) -> Texture2D:
	var key := "cd|%s|%s" % [title, details]
	if await _wait_for_other(host, key):
		return _cache.get(key)
	_drawing[key] = true
	# Probed on the band, 40 mm right of centre and in its fifth stripe (0.2 .. 2.2 mm below the middle line).
	var mm := CD_PX / CD_MM
	var probe := Vector2i(roundi(CD_PX / 2.0 + 40.0 * mm), roundi(CD_PX / 2.0 + 1.2 * mm))
	var tex := await _draw(host, Vector2i(CD_PX, CD_PX), true,
		func(c: Control) -> void: _paint_cd(c, float(CD_PX), title, details), probe, SWEEP[4])
	_drawing.erase(key)
	if tex != null:
		_cache[key] = tex
	print("[LabelPainter] CD face for \"%s\" (%s): %s" % [title, details, "drawn" if tex != null else "not drawn"])
	return tex


## A case's own paper for the album or DVD named `title`: the whole sheet, back | spine | front, `widths` px wide
## each and `h` tall (GameCaseModel.panel_widths), for the parts the player has no picture of (MediaCaseArt). The
## name on the front and turned down the spine, the stripe band running round all three. A picture in memory, not
## a texture: its panels are cut out and joined. Cached; do not write to it.
static func case_sheet(host: Node, kind: String, title: String, widths: Vector3i, h: int) -> Image:
	var key := "case|%s|%s|%s|%d" % [kind, title, widths, h]
	if await _wait_for_other(host, key):
		return _sheets.get(key)
	_drawing[key] = true
	var size := Vector2i(widths.x + widths.y + widths.z, h)
	# Probed on the paper, a little in from the back's top left corner.
	var img := await _draw_image(host, size, false,
		func(c: Control) -> void: _paint_case_sheet(c, kind, title, widths, float(h)), Vector2i(6, 6), PAPER)
	_drawing.erase(key)
	if img != null:
		_cache[key] = true
		_sheets[key] = img
	print("[LabelPainter] %s case paper for \"%s\": %s" % [kind, title, "%dx%d" % [size.x, size.y] if img != null else "not drawn"])
	return img


## A case sheet's name as its front fits it above the band (three lines at most), for a front `w` px wide of a
## sheet `mm` px to the millimetre.
static func case_front_name_fit(title: String, w: float, mm: float) -> Dictionary:
	return fit_name(font(), title.to_upper(), w - 16.0 * mm, 34.0 * mm, int(9.0 * mm), int(4.0 * mm), 3)


## The same down its spine (one line), for a spine `w` px wide and a run of `run` px.
static func case_spine_name_fit(title: String, w: float, run: float) -> Dictionary:
	var size := int(w * 0.46 / CAP_EM)
	return fit_name(font(), title.to_upper(), run, w, size, maxi(6, int(size * 0.6)), 1)


static func _paint_case_sheet(c: Control, kind: String, title: String, widths: Vector3i, h: float) -> void:
	var f := font()
	# A CD's sheet stands 118 mm, a DVD's 183.
	var mm := h / (118.0 if kind == "cd" else 183.0)
	var total := float(widths.x + widths.y + widths.z)
	c.draw_rect(Rect2(0.0, 0.0, total, h), PAPER)
	# The band runs round the whole sheet, two thirds of the way down.
	var stripe := (1.6 if kind == "cd" else 2.2) * mm
	var band_top := h * 0.64
	for i in SWEEP.size():
		c.draw_rect(Rect2(0.0, band_top + i * stripe, total, stripe * 0.9), SWEEP[i])
	var what := "COMPACT DISC" if kind == "cd" else "DVD"
	# The front: the name over the band, what it is and whose paper under it.
	var fx := float(widths.x + widths.y)
	var fw := float(widths.z)
	var fit := case_front_name_fit(title, fw, mm)
	_block(c, f, fit["lines"], int(fit["size"]), fx + fw / 2.0, 10.0 * mm, band_top - 6.0 * mm, INK)
	c.draw_string(f, Vector2(fx + 6.0 * mm, h - 6.0 * mm), "RETRO XR", HORIZONTAL_ALIGNMENT_LEFT, -1, int(3.4 * mm), INK)
	var what_px := int(3.4 * mm)
	c.draw_string(f, Vector2(fx + fw - 6.0 * mm - _width(f, what, what_px), h - 6.0 * mm), what,
		HORIZONTAL_ALIGNMENT_LEFT, -1, what_px, INK)
	# The back: the name again, smaller, at its head; a rule; the maker's line at its foot.
	var bw := float(widths.x)
	var back_fit := fit_name(f, title.to_upper(), bw - 16.0 * mm, 16.0 * mm, int(5.6 * mm), int(3.0 * mm), 2)
	_block(c, f, back_fit["lines"], int(back_fit["size"]), bw / 2.0, 9.0 * mm, 27.0 * mm, INK)
	c.draw_rect(Rect2(8.0 * mm, 31.0 * mm, bw - 16.0 * mm, 0.35 * mm), RULE)
	_text_centred(c, f, "RETRO XR  ·  %s" % what, bw / 2.0, h - 6.0 * mm, int(2.8 * mm), INK)
	# The spine: the name turned to read down it, clear of the band.
	var sw := float(widths.y)
	var run := band_top - 12.0 * mm
	var spine_fit := case_spine_name_fit(title, sw, run)
	var line := str((spine_fit["lines"] as PackedStringArray)[0]) if not (spine_fit["lines"] as PackedStringArray).is_empty() else ""
	var px := int(spine_fit["size"])
	c.draw_set_transform(Vector2(float(widths.x) + sw / 2.0 - px * CAP_EM / 2.0, 6.0 * mm), PI / 2.0, Vector2.ONE)
	c.draw_string(f, Vector2(maxf(0.0, (run - _width(f, line, px)) / 2.0), 0.0), line, HORIZONTAL_ALIGNMENT_LEFT, -1, px, INK)
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


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
	var img := await _draw_image(host, size, transparent, paint, probe, want)
	if img == null:
		return null
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## The same as a picture in memory (RGBA8, no mipmaps), for a caller that goes on working it: a case's paper is
## cut into panels and joined with the player's own pictures.
static func _draw_image(host: Node, size: Vector2i, transparent: bool, paint: Callable, probe: Vector2i,
		want: Color) -> Image:
	if host == null or not host.is_inside_tree():
		push_warning("[LabelPainter] no host in the tree to draw on")
		return null
	if DisplayServer.get_name() == "headless":
		var card := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		card.fill(Color(0, 0, 0, 0) if transparent else PAPER)
		return card
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
	return img


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


## The tape in its plate: its name over a smaller line, the pair centred on (`cx`, `yc`) by their capitals.
static func _plate_text(c: Control, f: Font, tape: String, under: String, cx: float, yc: float, big: int, small: int,
		between: float) -> void:
	var big_h := big * CAP_EM_C
	var small_h := small * CAP_EM
	var top := yc - (big_h + between + small_h) / 2.0
	_text_centred(c, f, tape, cx, top + big_h, big, INK)
	_text_centred(c, f, under, cx, top + big_h + between + small_h, small, INK)


static func _paint_vhs_face(c: Control, px: Vector2, title: String, tape: String) -> void:
	var f := font()
	var mm := px.x / VHS_FACE_MM.x
	var w := px.x
	var h := px.y
	c.draw_rect(Rect2(Vector2.ZERO, px), PAPER)
	# The writing strip, as the cassette's: the name in up to two lines over a rule.
	var fit := vhs_face_name_fit(title, w)
	_block(c, f, fit["lines"], int(fit["size"]), w / 2.0, 0.8 * mm, 12.6 * mm, INK)
	c.draw_line(Vector2(4.0 * mm, 13.6 * mm), Vector2(w - 4.0 * mm, 13.6 * mm), RULE, maxf(1.0, 0.15 * mm))
	# The band, warm into cool, with the badges on its middle line.
	var pitch := 2.1 * mm
	var band := 1.95 * mm
	var y0 := 17.0 * mm
	for i in SWEEP.size():
		c.draw_rect(Rect2(0.0, y0 + i * pitch, w, band), SWEEP[i])
	var yc := y0 + (SWEEP.size() * pitch - (pitch - band)) / 2.0
	var line := 0.28 * mm
	var cx := 10.5 * mm
	var r := 5.8 * mm
	c.draw_circle(Vector2(cx, yc), r, PAPER)
	c.draw_arc(Vector2(cx, yc), r - line / 2.0, 0.0, TAU, 96, INK, line, true)
	var sp := int(3.3 * mm)
	_text_centred(c, f, "SP", cx, yc + sp * CAP_EM / 2.0, sp, INK)
	_box(c, Rect2(w / 2.0 - 16.0 * mm, yc - 3.2 * mm, 32.0 * mm, 6.4 * mm), PAPER, 3.2 * mm)
	var pill := int(2.0 * mm)
	_text_centred(c, f, "VIDEO CASSETTE", w / 2.0, yc + pill * CAP_EM / 2.0, pill, INK)
	var pw := 13.6 * mm
	var ph := 11.6 * mm
	var pcx := w - 4.2 * mm - pw / 2.0
	_box(c, Rect2(pcx - pw / 2.0, yc - ph / 2.0, pw, ph), PAPER, 1.6 * mm, INK, line)
	_plate_text(c, f, tape, "HI-FI", pcx, yc, int(2.2 * mm), int(1.45 * mm), 1.0 * mm)
	# The maker's line along the foot.
	c.draw_string(f, Vector2(4.0 * mm, h - 2.4 * mm), "RETRO XR", HORIZONTAL_ALIGNMENT_LEFT, -1, int(2.5 * mm), INK)
	var foot := "STEREO  ·  NTSC"
	var fs := int(1.85 * mm)
	c.draw_string(f, Vector2(w - 4.0 * mm - _width(f, foot, fs), h - 2.4 * mm), foot, HORIZONTAL_ALIGNMENT_LEFT, -1,
		fs, INK)


static func _paint_vhs_spine(c: Control, px: Vector2, title: String, tape: String) -> void:
	var f := font()
	var mm := px.x / VHS_SPINE_MM.x
	var h := px.y
	c.draw_rect(Rect2(Vector2.ZERO, px), PAPER)
	# The stripes stand across the left end: the face's band turned on end.
	for i in SWEEP.size():
		c.draw_rect(Rect2(i * 1.6 * mm, 0.0, 1.45 * mm, h), SWEEP[i])
	# The name between the stripes (to 12.8 mm) and the plate (from 129.2 mm), centred in that run.
	var fit := vhs_spine_name_fit(title, px.x)
	_block(c, f, fit["lines"], int(fit["size"]), 71.0 * mm, 3.2 * mm, h - 3.2 * mm, INK)
	var pw := 16.6 * mm
	var ph := 11.6 * mm
	var pcx := px.x - 2.2 * mm - pw / 2.0
	_box(c, Rect2(pcx - pw / 2.0, h / 2.0 - ph / 2.0, pw, ph), PAPER, 1.6 * mm, INK, 0.28 * mm)
	_plate_text(c, f, tape, "SP  ·  HI-FI", pcx, h / 2.0, int(2.5 * mm), int(1.35 * mm), 1.0 * mm)


## `text` round the foot of a circle of radius `r` about `o`, reading left to right, the letters' tops toward the
## centre and their baseline on the circle; `spacing` added between letters.
static func _arc_text(c: Control, f: Font, text: String, o: Vector2, r: float, size: int, spacing: float,
		col: Color) -> void:
	var widths := PackedFloat32Array()
	var total := -spacing
	for i in text.length():
		var w := f.get_char_size(text.unicode_at(i), size).x + spacing
		widths.append(w)
		total += w
	var along := -total / 2.0
	for i in text.length():
		var glyph := widths[i] - spacing
		var mid := along + glyph / 2.0
		var th := PI / 2.0 - mid / r
		c.draw_set_transform(o + Vector2(cos(th), sin(th)) * r, -mid / r, Vector2.ONE)
		c.draw_char(f, Vector2(-glyph / 2.0, 0.0), text[i], size, col)
		along += widths[i]
	c.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _paint_cd(c: Control, s: float, title: String, details: String) -> void:
	var f := font()
	var mm := s / CD_MM
	var o := Vector2(s, s) / 2.0
	# Nothing but ink: the canvas stays clear, and the disc's lacquer shows wherever nothing is printed.
	# One band straight across, as the cassette's runs through its window; the hub cuts it (the shader's label_r_in).
	for i in SWEEP.size():
		c.draw_rect(Rect2(0.0, o.y + (-8.6 + i * 2.2) * mm, s, 2.0 * mm), SWEEP[i])
	# The name above the hub, its lowest line clear of the 23 mm the print starts at.
	var fit := cd_name_fit(title, s)
	_block(c, f, fit["lines"], int(fit["size"]), o.x, o.y - 50.0 * mm, o.y - 24.5 * mm, INK)
	_text_centred(c, f, "RETRO XR", o.x, o.y + 29.0 * mm, int(3.2 * mm), INK)
	if not details.is_empty():
		_text_centred(c, f, details, o.x, o.y + 35.0 * mm, int(2.2 * mm), INK)
	_arc_text(c, f, "DIGITAL AUDIO  ·  STEREO", o, 53.6 * mm, int(1.7 * mm), 0.25 * mm, INK)
