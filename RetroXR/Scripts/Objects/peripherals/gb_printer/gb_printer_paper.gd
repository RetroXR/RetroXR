## GbPrinterPaper — what a torn-off Game Boy Printer print looks like as a file.
##
## The printer core hands over the dots it burned, 160 a line. The paper is wider
## than the head, so a print kept as only those dots would be a picture of the ink
## rather than of the paper: this puts them in the middle of a sheet the paper's
## real width, in the paper's own colour, which is what a Poster then shows at the
## paper's real size. Pure and static, so a suite can check it without a core.
class_name GbPrinterPaper
extends RefCounted

## Dots across the head, and so the width of every frame the core sends.
const DOTS := 160

## Bare thermal paper, which is not quite white. The same tone as the strip
## (gb_printer_paper.gdshader), so a print does not change color when torn.
const PAPER := Color(0.96, 0.955, 0.93)

## The rolls Nintendo sold, each its own paper and its own ink: yellow paper
## printing black (the roll in the printer's box), blue printing black, and white
## printing sepia (Japanese Wikipedia, "ポケットプリンタ": 黄色・黒印刷、青色・黒印刷、
## 白色・セピア印刷). The tones are judged from photographs of the rolls, not
## measured. The first is what a printer starts with.
const ROLLS: Array[Dictionary] = [
	{"id": "white", "name": "White", "paper": PAPER, "ink": Color(0.36, 0.2, 0.11)},
	{"id": "yellow", "name": "Yellow", "paper": Color(0.98, 0.89, 0.43), "ink": Color(0.06, 0.06, 0.07)},
	{"id": "blue", "name": "Blue", "paper": Color(0.62, 0.8, 0.94), "ink": Color(0.06, 0.06, 0.07)},
]


## The roll called `id`, or the first when there is none by that name (a save
## from before rolls, or from a newer game with one this does not know).
static func roll(id: String) -> Dictionary:
	for r: Dictionary in ROLLS:
		if r["id"] == id:
			return r
	return ROLLS[0]


## The paper's width in dots: 38 mm of it at the head's pitch.
static func sheet_width() -> int:
	return int(round(GbPrinter.PAPER_WIDTH / GbPrinter.DOT_PITCH))


## `dots` (DOTS wide, any height, the core's grays) centered on a sheet of
## `paper`. A dot is the paper as far toward `ink` as it is dark, as the strip's
## shader draws it; with black ink that is ink multiplying the paper.
static func sheet(dots: Image, paper := PAPER, ink := Color.BLACK) -> Image:
	var src := dots.duplicate() as Image
	src.convert(Image.FORMAT_L8)
	var w := sheet_width()
	var h := src.get_height()
	@warning_ignore("integer_division")
	var left := (w - DOTS) / 2
	var out := Image.create(w, h, false, Image.FORMAT_RGB8)
	out.fill(paper)
	for y in range(h):
		for x in range(DOTS):
			out.set_pixel(left + x, y, ink.lerp(paper, src.get_pixel(x, y).r))
	return out


## Write the print into `dir` and return its path, or "" if it could not be
## written. Named for when it came out, so prints sort in the order they were made
## and two in one second do not overwrite each other. The colors are baked in: a
## print keeps the roll it was printed on whatever the printer is loaded with later.
static func save_print(dots: Image, dir: String, paper := PAPER, ink := Color.BLACK) -> String:
	if dots == null or dots.is_empty() or dots.get_width() != DOTS:
		return ""
	DirAccess.make_dir_recursive_absolute(dir)
	var stamp := Time.get_datetime_string_from_system(false, false).replace(":", "").replace("T", "_")
	var path := dir.path_join("print_%s.png" % stamp)
	var n := 2
	while FileAccess.file_exists(path):
		path = dir.path_join("print_%s_%d.png" % [stamp, n])
		n += 1
	if sheet(dots, paper, ink).save_png(path) != OK:
		return ""
	return path
