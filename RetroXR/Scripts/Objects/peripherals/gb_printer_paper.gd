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
## (gb_printer_paper.gdshader), so a print does not change colour when torn.
const PAPER := Color(0.96, 0.955, 0.93)


## The paper's width in dots: 38 mm of it at the head's pitch.
static func sheet_width() -> int:
	return int(round(GbPrinter.PAPER_WIDTH / GbPrinter.DOT_PITCH))


## `dots` (DOTS wide, any height, the core's greys) centred on a sheet of paper.
## Ink multiplies the paper, as the strip's shader does.
static func sheet(dots: Image) -> Image:
	var src := dots.duplicate() as Image
	src.convert(Image.FORMAT_L8)
	var w := sheet_width()
	var h := src.get_height()
	var left := (w - DOTS) / 2
	var out := Image.create(w, h, false, Image.FORMAT_RGB8)
	out.fill(PAPER)
	for y in range(h):
		for x in range(DOTS):
			var ink := src.get_pixel(x, y).r
			out.set_pixel(left + x, y, Color(PAPER.r * ink, PAPER.g * ink, PAPER.b * ink))
	return out


## Write the print into `dir` and return its path, or "" if it could not be
## written. Named for when it came out, so prints sort in the order they were made
## and two in one second do not overwrite each other.
static func save_print(dots: Image, dir: String) -> String:
	if dots == null or dots.is_empty() or dots.get_width() != DOTS:
		return ""
	DirAccess.make_dir_recursive_absolute(dir)
	var stamp := Time.get_datetime_string_from_system(false, false).replace(":", "").replace("T", "_")
	var path := dir.path_join("print_%s.png" % stamp)
	var n := 2
	while FileAccess.file_exists(path):
		path = dir.path_join("print_%s_%d.png" % [stamp, n])
		n += 1
	if sheet(dots).save_png(path) != OK:
		return ""
	return path
