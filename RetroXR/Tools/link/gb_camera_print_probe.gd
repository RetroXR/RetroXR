## The Game Boy Camera printing one of its saved photos to the Game Boy Printer.
##
##     "$godot" --path RetroXR res://Tools/link/gb_camera_print_probe.tscn --resolution 320x240 --position 20,20 -- --sav=<camera .srm> --steps=<steps>
##
## A real game, where gb_printer_probe is our own ROM: the protocol a game
## actually speaks, its timing, and its picture. mGBA alone (gambatte refuses the
## Camera's cartridge type, 0xFC), with the model pinned as the room pins it.
##
## The save is COPIED to a scratch file before the core sees it: the player's
## photos are never the core's to write. With no --sav the camera starts blank.
##
## --steps is a comma list, run in order, timed in the Game Boy's own frames so
## the same list replays the same way however fast the window draws:
##
##     w<N>         wait N frames
##     A B START SELECT UP DOWN LEFT RIGHT   press (6 frames) and release (6),
##                  with an optional xN to repeat: DOWNx3
##     shot:<name>  screenshot the Game Boy to probe_out/gb_camera_<name>.png
##     printed      wait until the paper stops growing, then save it
##
## With no --steps it prints the album's first photo. The way there, found by
## screenshot (US cartridge): title A, main menu RIGHT to VIEW, A, the ALBUM/SHOW
## screen A, the album grid A on the first photo, then SELECT -- which is what
## opens the photo's radial menu (print up, delete down, paint, frame, comment,
## stamp) -- UP for print, A, and A again on "A PRINT / B CANCEL". The picture
## takes about seven seconds to cross the cable before any paper moves.
##
## Prints `[cam-print] paper WxH`, and PASS when the paper came out at all and
## ends with a picture rather than blank paper. Whether the picture is the photo
## is for the eye: the screenshots and the paper go side by side.
##
## Measured 2026-10-21 on a player's own save: photo A01 came out as 208 lines,
## its 144 plus the Camera's 0x13 margins, 144 of them inked, matching the screen.
extends Node

const PRINT_FIRST_PHOTO := "w300,A,w60,RIGHT,w30,A,w150,A,w150,A,w150,shot:photo," \
		+ "SELECT,w60,UP,w60,A,w90,A,w45,shot:printing,printed,shot:after"

const CORE := "mgba"
const PRINTER_CORE := "gbprinter"
const ROM_NAME := "Game Boy Camera (USA, Europe) (SGB Enhanced).gb"
const OPTIONS := [
	["mgba_link_cable", "ON"], ["mgba_use_bios", "OFF"],
	["mgba_gb_model", "Game Boy"], ["mgba_sgb_borders", "OFF"],
]
const KEYS := {
	"B": 0, "SELECT": 2, "START": 3, "UP": 4, "DOWN": 5, "LEFT": 6, "RIGHT": 7, "A": 8,
}
const SCRATCH := "user://probe_camera_print.srm"

var _gb: Libretro
var _printer: Libretro
var _opt_path := ""
var _opt_backup := ""
var _had_opt := false
var _restored := false
var _fail := 0


func _ready() -> void:
	get_tree().create_timer(600.0).timeout.connect(func() -> void:
		print("[cam-print] TIMEOUT")
		_restore()
		get_tree().quit(1))
	await _run()


func _run() -> void:
	var sav := ""
	var steps := PRINT_FIRST_PHOTO
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--sav="):
			sav = arg.substr(6)
		elif arg.begins_with("--steps="):
			steps = arg.substr(8)
	var root := CoreDownloadManager.default_core_root()
	for core in [CORE, PRINTER_CORE]:
		if CoreDownloadManager.installed_core_lib(core).is_empty():
			print("[cam-print] SKIP  %s is not installed" % core)
			get_tree().quit(0)
			return
	var rom := RomLibrary.rom_dir_for_system("gb").path_join(ROM_NAME)
	if not FileAccess.file_exists(rom):
		print("[cam-print] SKIP  no %s" % rom)
		get_tree().quit(0)
		return
	_write_options(root)

	var scratch := ProjectSettings.globalize_path(SCRATCH)
	if FileAccess.file_exists(scratch):
		DirAccess.remove_absolute(scratch)
	if not sav.is_empty():
		var bytes := FileAccess.get_file_as_bytes(sav)
		if bytes.is_empty():
			print("[cam-print] FAIL  could not read %s" % sav)
			_finish()
			return
		var f := FileAccess.open(scratch, FileAccess.WRITE)
		f.store_buffer(bytes)
		f.close()
		print("[cam-print] using a copy of %s" % sav)

	_printer = Libretro.new()
	_gb = Libretro.new()
	add_child(_printer)
	add_child(_gb)
	_printer.StartContent(root, PRINTER_CORE, "")
	_gb.SetSramPath(scratch)
	_gb.StartContent(root, CORE, rom)
	await _frames_real(60)
	print("[cam-print] cable: %s" % _gb.LinkConnect(_printer, 0, 0))

	for raw in steps.split(",", false):
		var step := raw.strip_edges()
		if step.begins_with("w"):
			await _wait(int(step.substr(1)))
		elif step.begins_with("shot:"):
			_save(_gb.GetVideoImage(), step.substr(5))
		elif step == "printed":
			await _wait_printed()
		else:
			var times := 1
			var key := step
			var x := step.find("x")
			if x > 0 and step.substr(x + 1).is_valid_int():
				key = step.substr(0, x)
				times = int(step.substr(x + 1))
			if not KEYS.has(key):
				print("[cam-print] unknown step %s" % step)
				continue
			for i in range(times):
				_gb.SetJoypadState(0, 1 << int(KEYS[key]), 0, 0, 0, 0)
				await _wait(6)
				_gb.SetJoypadState(0, 0, 0, 0, 0, 0)
				await _wait(10)

	var paper := _printer.GetVideoImage()
	_save(paper, "paper")
	print("[cam-print] paper %dx%d" % [paper.get_width(), paper.get_height()])
	if paper.get_width() != 160:
		print("[cam-print] FAIL  nothing was printed")
		_fail += 1
	else:
		var inked := _inked_lines(paper)
		print("[cam-print] %d of %d lines carry ink" % [inked, paper.get_height()])
		if inked < 32:
			print("[cam-print] FAIL  the paper is blank")
			_fail += 1
		else:
			print("[cam-print] PASS  a picture came out of the printer")
	_finish()


func _finish() -> void:
	if _gb != null:
		_gb.StopContent()
	await _frames_real(60)
	if _printer != null:
		_printer.StopContent()
	await _frames_real(60)
	_restore()
	get_tree().quit(1 if _fail > 0 else 0)


func _frames_real(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


## N of the Game Boy's own frames.
func _wait(n: int) -> void:
	var until := _gb.GetFrameCount() + n
	var guard := Time.get_ticks_msec() + 60000 + n * 50
	while _gb.GetFrameCount() < until and Time.get_ticks_msec() < guard:
		await get_tree().process_frame


## Until paper has come out and then not grown for three seconds of game time.
## Nothing comes out until the whole picture has crossed the cable, which the
## Camera spends a good few seconds on, so the first line is waited for apart.
func _wait_printed() -> void:
	var first_by := Time.get_ticks_msec() + 60000
	while Time.get_ticks_msec() < first_by:
		await _wait(10)
		var img0 := _printer.GetVideoImage()
		if img0 != null and img0.get_width() == 160:
			print("[cam-print] paper started after %.1f s" % ((Time.get_ticks_msec() - first_by + 60000) / 1000.0))
			break
	var last := -1
	var still := 0
	var guard := Time.get_ticks_msec() + 120000
	while still < 180 and Time.get_ticks_msec() < guard:
		await _wait(10)
		var img := _printer.GetVideoImage()
		var h := img.get_height() if img != null and img.get_width() == 160 else 0
		if h == last:
			still += 10
		else:
			still = 0
			last = h
	print("[cam-print] paper settled at %d lines" % max(last, 0))


func _inked_lines(img: Image) -> int:
	var g := img.duplicate() as Image
	g.convert(Image.FORMAT_L8)
	var data := g.get_data()
	var n := 0
	for y in range(g.get_height()):
		for x in range(160):
			if data[y * 160 + x] < 200:
				n += 1
				break
	return n


func _save(img: Image, name: String) -> void:
	if img == null or img.is_empty():
		print("[cam-print] (no picture for %s)" % name)
		return
	var dir := "res://probe_out"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var path := "%s/gb_camera_%s.png" % [dir, name]
	img.save_png(path)
	print("[cam-print] wrote %s" % path)


func _write_options(root: String) -> void:
	_opt_path = "%s/core_options/%s.opt" % [root, CORE]
	_had_opt = FileAccess.file_exists(_opt_path)
	_opt_backup = FileAccess.get_file_as_string(_opt_path) if _had_opt else ""
	var lines: PackedStringArray = []
	for line in _opt_backup.split("\n", false):
		var keep := true
		for pair: Array in OPTIONS:
			if line.begins_with(str(pair[0])):
				keep = false
		if keep:
			lines.append(line)
	for pair: Array in OPTIONS:
		lines.append('%s = "%s"' % [pair[0], pair[1]])
	DirAccess.make_dir_recursive_absolute(_opt_path.get_base_dir())
	var w := FileAccess.open(_opt_path, FileAccess.WRITE)
	w.store_string("\n".join(lines) + "\n")
	w.close()


func _restore() -> void:
	if _restored or _opt_path.is_empty():
		return
	_restored = true
	if not _had_opt:
		DirAccess.remove_absolute(_opt_path)
		return
	var w := FileAccess.open(_opt_path, FileAccess.WRITE)
	if w != null:
		w.store_string(_opt_backup)
		w.close()
