extends Node3D

## Q / E pressed faster than a page turns: several sheets in the air at once
## (PDFBook._launch_flight). Windowed — a recording is the proof:
##
##   "$godot" --path RetroXR --resolution 640x400 --position 20,20 \
##       res://Tools/vr/book_riffle_probe.tscn [-- --single] [-- --back]
##
## Writes frames to user://book_riffle_probe/ and asserts, once every sheet has
## landed, that the book stepped one page per sheet and both blocks show the
## spread again. `--single` launches one sheet (the control: one in the air);
## `--back` riffles backwards.

const PAGES := 24
const SHEETS := 4
const GAP := 0.06
const START_LEAF := 5

var _book: PDFBook = null
var _frames := 0
var _recording := false
var _dir := 1
var _sheets := SHEETS


func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("[probe] GAVE UP")
		get_tree().quit(1))
	var args := OS.get_cmdline_user_args()
	if "--single" in args:
		_sheets = 1
	if "--back" in args:
		_dir = -1
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.22, 0.24, 0.28)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.7)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 20, 0)
	add_child(sun)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(0.0, -0.2, 0.3)
	cam.look_at(Vector3(0.0, -0.02, 0.0))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://book_riffle_probe"))

	var cbz := ProjectSettings.globalize_path("user://book_riffle_probe.cbz")
	_write_cbz(cbz)
	_book = preload("res://Scenes/Objects/media/pdf_book.tscn").instantiate() as PDFBook
	add_child(_book)
	_book.freeze = true
	_book.pdf_path = cbz
	# The book loads again from its own _ready, landing on page one: open it after.
	while _book._page_count == 0:
		await get_tree().process_frame
	for _i in 30:
		await get_tree().process_frame
	_book.set_page(PDFBook.BookState.OPEN, START_LEAF)
	# Every page this riffle can show, in memory before the first sheet lifts.
	for _i in 600:
		await get_tree().process_frame
		var lo := (START_LEAF - SHEETS) * 2 - 2
		var hi := (START_LEAF + SHEETS + 2) * 2
		var ready := true
		for p in range(maxi(lo, 0), mini(hi, PAGES)):
			if not _book._texture_cache.has(p):
				_book._get_page_texture(p)
				ready = false
		if ready:
			break
	for _i in 10:
		await get_tree().process_frame

	# The boot curtain covers a windowed run; nothing here is a room arriving.
	if has_node("/root/LoadingOverlay"):
		for owner: StringName in [&"boot_warm", &"boot_restore"]:
			LoadingOverlay.end(owner)
	for _i in 90:
		await get_tree().process_frame

	var leaf0 := _book._current_leaf
	print("[probe] riffling %d sheet(s) %s from leaf %d" % [_sheets, "forward" if _dir > 0 else "back", leaf0])
	_recording = true
	var launched := 0
	var most_in_air := 0
	for k in _sheets:
		if _book._launch_flight(_dir):
			launched += 1
		most_in_air = maxi(most_in_air, _book._flights.size())
		await get_tree().create_timer(GAP).timeout
		most_in_air = maxi(most_in_air, _book._flights.size())
	while not _book._flights.is_empty():
		await get_tree().process_frame
	for _i in 20:
		await get_tree().process_frame
	_recording = false

	var ok := true
	ok = _check(launched == _sheets, "every press launched a sheet (%d/%d)" % [launched, _sheets]) and ok
	ok = _check(most_in_air == _sheets, "%d sheet(s) in the air at once (wanted %d)" % [most_in_air, _sheets]) and ok
	ok = _check(_book._current_leaf == leaf0 + _dir * _sheets,
		"stepped one page per sheet (leaf %d -> %d)" % [leaf0, _book._current_leaf]) and ok
	ok = _check(_book._flight_shown == [-1, -1], "both blocks show the spread again") and ok
	var left := _book._get_page_texture(_book._current_leaf * 2 + 1)
	var shown: Variant = (_book._left_stack_top.get_active_material(0) as ShaderMaterial).get_shader_parameter("front_texture")
	ok = _check(shown == left, "the left block wears the spread's left page") and ok
	print("[probe] %d frames in user://book_riffle_probe/" % _frames)
	print("[probe] %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit(0 if ok else 1)


func _check(cond: bool, what: String) -> bool:
	print("[probe] %s %s" % ["ok  " if cond else "FAIL", what])
	return cond


func _process(_delta: float) -> void:
	if not _recording:
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://book_riffle_probe/f%04d.png" % _frames)
	_frames += 1


## Every page its own colour, with a dark band whose height is its number, so a
## frame says which page is where.
func _write_cbz(path: String) -> void:
	var zip := ZIPPacker.new()
	zip.open(path)
	for i in PAGES:
		var img := Image.create(300, 400, false, Image.FORMAT_RGB8)
		img.fill(Color.from_hsv(float(i) / PAGES, 0.45, 0.95))
		var band := 20 + i * 14
		img.fill_rect(Rect2i(20, band, 260, 12), Color(0.1, 0.1, 0.1))
		zip.start_file("%03d.png" % i)
		zip.write_file(img.save_png_to_buffer())
		zip.close_file()
	zip.close()
