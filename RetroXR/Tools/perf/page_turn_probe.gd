extends Node3D

## What a page turn COSTS on the main thread, and where it goes.
##
## Renders happen on worker threads, so the first read through a book is smooth:
## a page that is not on disk yet returns the placeholder and lands later. The
## disk cache in `user://pdf_cache/` then SURVIVES, so every later read of that
## book takes the other branch of `_get_page_texture` — `Image.load_from_file`
## plus `ImageTexture.create_from_image`, both on the main thread, for every page
## the turn touches. Run windowed: under `--headless` the dummy renderer skips
## the VRAM upload and only the decode shows up.
##
##   "$godot" --path RetroXR --resolution 320x240 --position 20,20 \
##       res://Tools/perf/page_turn_probe.tscn

## Page pixels. A 150-DPI Letter PDF page is 1275x1650 and a comic scan is
## bigger, so this is a REAL book on the small side.
const PAGE_W := 1200
const PAGE_H := 1600
const PAGES := 24
const TURNS := 6

var _cbz := ""
var _book: PDFBook = null
var _step := 0


func _ready() -> void:
	_cbz = "user://page_turn_probe.cbz"
	print("[probe] writing %d pages of %dx%d ..." % [PAGES, PAGE_W, PAGE_H])
	_write_cbz(ProjectSettings.globalize_path(_cbz))
	_spawn_book()
	print("[probe] pass 1: filling the disk cache (this is the FIRST read of a book)")


func _spawn_book() -> void:
	_book = preload("res://Scenes/Objects/media/pdf_book.tscn").instantiate() as PDFBook
	add_child(_book)
	_book.freeze = true
	_book.pdf_path = ProjectSettings.globalize_path(_cbz)


func _process(_delta: float) -> void:
	# Wait for every page to reach the disk cache before measuring anything.
	if _step == 0:
		if _book._pending_renders.is_empty() and _book._page_count > 0:
			_step = 1
		else:
			# Walk the book so the prefetch window covers every page.
			if _book._state == PDFBook.BookState.CLOSED:
				_book.turn_page_forward()
			elif _book._current_leaf < _book._leaf_count - 2:
				_book.turn_page_forward()
		return
	if _step == 1:
		# _measure() awaits, so it quits at its own end — quitting here would fire
		# at its first await, before a single number was printed.
		_step = 2
		_measure()


func _measure() -> void:
	# A book you have read before: the disk cache is warm, the RAM cache is not.
	# This is what opening a book on a second visit actually costs.
	_book.queue_free()
	_book = null
	await get_tree().process_frame
	_spawn_book()
	while _book._page_count == 0:
		await get_tree().process_frame
	_book.set_page(PDFBook.BookState.OPEN, 2)
	await get_tree().process_frame

	print("[probe] --- a turn on a book that has been read before ---")
	var worst := 0
	var total := 0
	for i in TURNS:
		# Only the RAM cache is cleared: exactly what _trim_texture_cache() does
		# as the window moves, and what a freshly opened book starts with.
		_book._texture_cache.clear()
		var t0 := Time.get_ticks_usec()
		_book.turn_page_forward()
		var dt := Time.get_ticks_usec() - t0
		total += dt
		worst = maxi(worst, dt)
		print("[probe]   turn %d: %.1f ms on the main thread" % [i + 1, dt / 1000.0])
	print("[probe] worst %.1f ms, mean %.1f ms  (a 90 Hz frame is 11.1 ms)"
			% [worst / 1000.0, float(total) / TURNS / 1000.0])

	# Steady-state reading: the RAM cache is left alone, so only the pages that
	# entered the window since the last turn have to come off the disk — and
	# _trim_texture_cache() has just thrown away the ones behind. This is the
	# number that matches "I turned a page and it hitched".
	print("[probe] --- reading straight through, RAM cache left alone ---")
	_book.set_page(PDFBook.BookState.OPEN, 2)
	await get_tree().process_frame
	worst = 0
	total = 0
	for i in TURNS:
		var t0 := Time.get_ticks_usec()
		_book.turn_page_forward()
		var dt := Time.get_ticks_usec() - t0
		total += dt
		worst = maxi(worst, dt)
		print("[probe]   turn %d: %.1f ms on the main thread" % [i + 1, dt / 1000.0])
	print("[probe] worst %.1f ms, mean %.1f ms  = %.1f dropped frames at 90 Hz"
			% [worst / 1000.0, float(total) / TURNS / 1000.0, float(total) / TURNS / 11111.0])

	# Where does it go?
	_book._texture_cache.clear()
	_book._current_leaf += 1
	var t1 := Time.get_ticks_usec()
	_book._update_spread_textures()
	var t2 := Time.get_ticks_usec()
	_book._update_stack_thickness()
	var t3 := Time.get_ticks_usec()
	_book._prefetch_nearby_pages()
	var t4 := Time.get_ticks_usec()
	print("[probe] --- where a turn spends it ---")
	print("[probe]   _update_spread_textures  %.1f ms" % [(t2 - t1) / 1000.0])
	print("[probe]   _update_stack_thickness  %.1f ms" % [(t3 - t2) / 1000.0])
	print("[probe]   _prefetch_nearby_pages   %.1f ms   (%d pages, synchronous on a disk hit)"
			% [(t4 - t3) / 1000.0, _book.prefetch_pages * 2 + 3])

	# One page, cold RAM cache, warm disk: the unit the whole cost is built from.
	_book._texture_cache.clear()
	var t5 := Time.get_ticks_usec()
	_book._get_page_texture(8)
	var t6 := Time.get_ticks_usec()
	print("[probe]   ONE _get_page_texture    %.2f ms  (decode %dx%d PNG + upload)"
			% [(t6 - t5) / 1000.0, PAGE_W, PAGE_H])

	# Split that unit: a PNG decode can move to a worker thread, a VRAM upload
	# cannot, so which one dominates decides the fix.
	var page_png := _book._cache_dir + "page_%03d.png" % 8
	var t9 := Time.get_ticks_usec()
	var raw := Image.load_from_file(page_png)
	var t10 := Time.get_ticks_usec()
	var _tex := ImageTexture.create_from_image(raw)
	var t11 := Time.get_ticks_usec()
	print("[probe]     of which decode      %.2f ms" % [(t10 - t9) / 1000.0])
	print("[probe]     of which upload      %.2f ms" % [(t11 - t10) / 1000.0])

	# And the same page once it is already in RAM, for contrast.
	var t7 := Time.get_ticks_usec()
	_book._get_page_texture(8)
	var t8 := Time.get_ticks_usec()
	print("[probe]   ...same page cached       %.3f ms" % [(t8 - t7) / 1000.0])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_cbz))
	get_tree().quit(0)


func _write_cbz(path: String) -> void:
	var zip := ZIPPacker.new()
	zip.open(path)
	for i in PAGES:
		var img := Image.create(PAGE_W, PAGE_H, false, Image.FORMAT_RGB8)
		img.fill(Color(0.96, 0.94, 0.88))
		var ink := Color.from_hsv(fmod(float(i) * 0.13, 1.0), 0.75, 0.55)
		img.fill_rect(Rect2i(60, 60, PAGE_W - 120, 160), ink)
		for line in 24:
			img.fill_rect(Rect2i(60, 320 + line * 48, PAGE_W - 120 - (line % 3) * 180, 18),
					Color(0.3, 0.3, 0.32))
		zip.start_file("page_%02d.png" % i)
		zip.write_file(img.save_png_to_buffer())
		zip.close_file()
	zip.close()
