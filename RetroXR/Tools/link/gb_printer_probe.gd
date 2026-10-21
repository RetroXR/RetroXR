## A real Game Boy core printing to the Game Boy Printer core over the link bus.
##
##     "$godot" --path RetroXR res://Tools/link/gb_printer_probe.tscn --resolution 320x240 --position 20,20 -- --core=gambatte
##     ... -- --core=mgba
##     ... -- --core=gambatte --nocable      (the control: nothing on the wire)
##
## ONE Game Boy core per process: starting a core wrongly can take the process
## down, and a leg that dies must not take the other's result with it.
##
## A probe rather than a test: it needs gambatte or mGBA built with the link
## driver and gbprinter_libretro installed, so it cannot gate a commit. What it
## shows is what no suite can: that a Game Boy core and the printer core, each
## knowing nothing of the other, print a picture through the frontend's bus.
##
## The ROM is ours (Tools/gen_gblink_rom.py, build_printer). It finds the printer
## as the games do, sends INIT, nine DATA packets of a known picture (the odd
## ones RLE-compressed), the closing empty DATA and PRINT, checks every reply,
## and polls until the print is done: the screen turns WHITE when all of that
## held, GREY when any of it did not, and stays black until a printer answers.
## The paper is then compared dot for dot with printer_expected.png, which the
## same script writes -- so the oracle is the paper itself, not a summary of it.
##
## Then the two buttons, through the same input the room pushes: TEAR with a
## count tears that many lines off the OLD end, FEED feeds blank paper.
##
## Windowed, never --headless: the dummy renderer hands back blank frames, and a
## blank frame the size of the paper would make the size checks pass on nothing.
extends Node

const CORE_OPTIONS := {
	"gambatte": [["gambatte_gb_link_mode", "Link Cable"], ["gambatte_gb_bootloader", "disabled"]],
	"mgba": [["mgba_link_cable", "ON"], ["mgba_use_bios", "OFF"]],
}

const PRINTER_CORE := "gbprinter"
const ROM := "res://Tools/gblink/printer.gb"
const EXPECTED := "res://Tools/gblink/printer_expected.png"

## Libretro joypad ids, as bits of SetJoypadState's mask.
const BTN_B := 1 << 0   # TEAR
const BTN_A := 1 << 8   # FEED

## Finding the printer, ~6000 bytes at a byte a transfer, and ~210 lines at the
## printer's ~35 a second come to about fifteen seconds. Twice that, and then
## some, before calling it.
const PRINT_TIMEOUT_S := 45.0
const NOCABLE_WAIT_S := 15.0

var _core := "gambatte"
var _nocable := false
var _pass := 0
var _fail := 0
var _opt_path := ""
var _opt_backup := ""
var _had_opt := false
var _restored := false


func _ready() -> void:
	get_tree().create_timer(150.0).timeout.connect(func() -> void:
		print("[gb-print] TIMEOUT")
		_restore()
		get_tree().quit(1))
	await _run()


func _ok(name: String, cond: bool, detail := "") -> void:
	if cond:
		_pass += 1
		print("[gb-print] PASS  %s" % name)
	else:
		_fail += 1
		print("[gb-print] FAIL  %s%s" % [name, "  — " + detail if not detail.is_empty() else ""])


func _eq(name: String, got: Variant, want: Variant) -> void:
	_ok(name, got == want, "got %s, want %s" % [str(got), str(want)])


func _finish() -> void:
	_restore()
	print("[gb-print] ---- %s%s: %d passed, %d failed ----" % [
		_core, " (no cable)" if _nocable else "", _pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--core="):
			_core = arg.substr(7)
		elif arg == "--nocable":
			_nocable = true
	if not CORE_OPTIONS.has(_core):
		print("[gb-print] SKIP  no link options known for %s" % _core)
		get_tree().quit(0)
		return

	var root := CoreDownloadManager.default_core_root()
	for core in [_core, PRINTER_CORE]:
		if CoreDownloadManager.installed_core_lib(core).is_empty():
			print("[gb-print] SKIP  no %s core installed under %s" % [core, root])
			get_tree().quit(0)
			return
	var rom := ProjectSettings.globalize_path(ROM)
	if not FileAccess.file_exists(rom) or not FileAccess.file_exists(EXPECTED):
		print("[gb-print] SKIP  run Tools/gen_gblink_rom.py first")
		get_tree().quit(0)
		return
	if not _write_options(root):
		print("[gb-print] SKIP  could not write the core options file")
		get_tree().quit(0)
		return
	print("[gb-print] core %s%s" % [_core, ", NO CABLE" if _nocable else ""])

	var printer := Libretro.new()
	var gb := Libretro.new()
	add_child(printer)
	add_child(gb)

	# The printer takes no content: it said SET_SUPPORT_NO_GAME and ignores the
	# game info either way.
	printer.StartContent(root, PRINTER_CORE, "")
	gb.StartContent(root, _core, rom)
	await _frames(120)

	_eq("the printer starts with no paper out", _size(printer.GetVideoImage()), Vector2i(1, 1))
	var shade_waiting := _lum(gb.GetVideoImage())
	print("[gb-print] Game Boy before the cable: luminance %.2f" % shade_waiting)

	if not _nocable:
		_ok("cabling the Game Boy to the printer succeeds", gb.LinkConnect(printer, 0, 0))
		await _frames(2)
		_eq("the Game Boy sees two machines", gb.LinkPeerCount(0), 2)
		_eq("so does the printer", printer.LinkPeerCount(0), 2)

	# Wait for the ROM's verdict: a flat screen that is no longer black.
	var started := Time.get_ticks_msec()
	var limit := (NOCABLE_WAIT_S if _nocable else PRINT_TIMEOUT_S) * 1000.0
	var shade := shade_waiting
	while Time.get_ticks_msec() - started < limit:
		await _frames(30)
		shade = _lum(gb.GetVideoImage())
		if shade > shade_waiting + 0.15:
			# The first frame to show it can be caught half repainted, the old
			# shade above the line the palette changed on and the new one below.
			await _frames(30)
			shade = _lum(gb.GetVideoImage())
			break
	var took := (Time.get_ticks_msec() - started) / 1000.0
	var gb_img := gb.GetVideoImage()
	var paper := printer.GetVideoImage()
	_save(gb_img, "screen")
	_save(paper, "paper")
	print("[gb-print] after %.1f s: Game Boy luminance %.2f, paper %s" % [took, shade, _size(paper)])

	if _nocable:
		_ok("with no cable the Game Boy never finds a printer", shade <= shade_waiting + 0.05,
				"luminance %.2f" % shade)
		_eq("and nothing is printed", _size(paper), Vector2i(1, 1))
		await _stop(gb, printer)
		_finish()
		return

	# The ROM's own verdict. WHITE is colour 0 painted everywhere: the lightest
	# shade the core draws. GREY would be well below it.
	_ok("the Game Boy read every reply right and saw the print finish", shade > 0.85,
			"luminance %.2f (white is about 1, the ROM's grey about 0.4)" % shade)

	# The paper itself.
	var expected := Image.load_from_file(ProjectSettings.globalize_path(EXPECTED))
	expected.convert(Image.FORMAT_L8)
	_eq("the paper is the picture's size, margins included", _size(paper), _size(expected))
	var diff := _first_difference(paper, expected, 0)
	_ok("the paper matches the picture dot for dot", diff.is_empty(), diff)

	# TEAR: B with LX as the count, through the same input the room uses. The
	# OLD end goes, so what is left is the tail of the same picture.
	var before_h := paper.get_height()
	gb.SetJoypadState(0, 0, 0, 0, 0, 0)
	printer.SetJoypadState(0, BTN_B, 100, 0, 0, 0)
	await _frames(6)
	printer.SetJoypadState(0, 0, 0, 0, 0, 0)
	await _frames(6)
	var torn := printer.GetVideoImage()
	_eq("tearing 100 lines leaves the rest", _size(torn), Vector2i(160, before_h - 100))
	var tail := expected.get_region(Rect2i(0, 100, 160, before_h - 100))
	var tdiff := _first_difference(torn, tail, 0)
	_ok("and what is left is the end of the same print", tdiff.is_empty(), tdiff)

	# B with no count tears the lot.
	printer.SetJoypadState(0, BTN_B, 0, 0, 0, 0)
	await _frames(6)
	printer.SetJoypadState(0, 0, 0, 0, 0, 0)
	await _frames(6)
	_eq("tearing with no count takes everything", _size(printer.GetVideoImage()), Vector2i(1, 1))

	# FEED for a second feeds about 35 blank lines. Timed by the clock, not by
	# frames: the window draws at the monitor's rate, the core at the Game Boy's.
	printer.SetJoypadState(0, BTN_A, 0, 0, 0, 0)
	var feed_from := Time.get_ticks_msec()
	while Time.get_ticks_msec() - feed_from < 1000:
		await get_tree().process_frame
	printer.SetJoypadState(0, 0, 0, 0, 0, 0)
	await _frames(6)
	var fed := printer.GetVideoImage()
	print("[gb-print] FEED for a second gave %s" % _size(fed))
	_ok("FEED feeds about 35 lines a second", fed.get_width() == 160
			and fed.get_height() >= 28 and fed.get_height() <= 42, "got %s" % _size(fed))
	_ok("and it is blank", _is_blank(fed))

	await _stop(gb, printer)
	_finish()


func _stop(gb: Libretro, printer: Libretro) -> void:
	# Either order has to leave the other alone; the Game Boy goes first because
	# it is the one a player switches off.
	gb.StopContent()
	await _frames(60)
	printer.StopContent()
	await _frames(60)
	gb.queue_free()
	printer.queue_free()
	await _frames(2)


func _size(img: Image) -> Vector2i:
	if img == null or img.is_empty():
		return Vector2i.ZERO
	return Vector2i(img.get_width(), img.get_height())


## Mean luminance over a coarse grid, 0..1. Only the ROM's three flat shades are
## ever compared, so a grid is plenty.
func _lum(img: Image) -> float:
	if img == null or img.is_empty():
		return 0.0
	var total := 0.0
	var n := 0
	for y in range(0, img.get_height(), 8):
		for x in range(0, img.get_width(), 8):
			total += img.get_pixel(x, y).get_luminance()
			n += 1
	return total / max(n, 1)


## Every pixel, not a sample: a fault in one tile column is one tile wide.
func _first_difference(got: Image, want: Image, tolerance: int) -> String:
	if _size(got) != _size(want):
		return "sizes differ: %s vs %s" % [_size(got), _size(want)]
	var g := got.duplicate() as Image
	g.convert(Image.FORMAT_L8)
	var a := g.get_data()
	var b := want.get_data()
	for i in range(a.size()):
		if absi(int(a[i]) - int(b[i])) > tolerance:
			return "first at (%d,%d): %d, want %d" % [i % 160, i / 160, a[i], b[i]]
	return ""


func _is_blank(img: Image) -> bool:
	var g := img.duplicate() as Image
	g.convert(Image.FORMAT_L8)
	for v in g.get_data():
		if v != 255:
			return false
	return true


func _save(img: Image, name: String) -> void:
	if img == null or img.is_empty():
		return
	var dir := "res://probe_out"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var path := "%s/gb_printer_%s_%s%s.png" % [dir, _core, name, "_nocable" if _nocable else ""]
	img.save_png(path)
	print("[gb-print] wrote %s" % path)


## Turn the cable on and the boot ROM off, keeping a copy of whatever was there.
func _write_options(root: String) -> bool:
	_opt_path = "%s/core_options/%s.opt" % [root, _core]
	var existing := ""
	_had_opt = FileAccess.file_exists(_opt_path)
	if _had_opt:
		var reader := FileAccess.open(_opt_path, FileAccess.READ)
		if reader != null:
			existing = reader.get_as_text()
			reader.close()
	_opt_backup = existing

	var wanted: Array = CORE_OPTIONS[_core]
	var lines: PackedStringArray = []
	for line in existing.split("\n", false):
		var keep := true
		for pair: Array in wanted:
			if line.begins_with(str(pair[0])):
				keep = false
		if keep:
			lines.append(line)
	for pair: Array in wanted:
		lines.append('%s = "%s"' % [pair[0], pair[1]])

	DirAccess.make_dir_recursive_absolute(_opt_path.get_base_dir())
	var writer := FileAccess.open(_opt_path, FileAccess.WRITE)
	if writer == null:
		return false
	writer.store_string("\n".join(lines) + "\n")
	writer.close()
	return true


func _restore() -> void:
	if _restored or _opt_path.is_empty():
		return
	_restored = true
	if not _had_opt:
		DirAccess.remove_absolute(_opt_path)
		return
	var writer := FileAccess.open(_opt_path, FileAccess.WRITE)
	if writer != null:
		writer.store_string(_opt_backup)
		writer.close()
		print("[gb-print] restored %s" % _opt_path)
