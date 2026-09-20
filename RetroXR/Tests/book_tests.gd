## book_tests — a book's page-grab zones must never be in the way of a click.
##
## Every case here is the 2026-09-18 bug: a saved book whose manual had moved
## with its ROM folder failed to open, never laid out its grab zones, and sat
## inside two 1 m default cubes on the pointer layer — nothing near it could be
## clicked, its own options panel included. The oracle is a real physics ray on
## that layer, not the `disabled` flag alone: the flag is what the fix sets, the
## ray is what the player's reticle does.
##
## Needs no PDF and no godot-pdfium: the loaded book is a CBZ built here.
extends Node3D

const BOOK_SCENE := preload("res://Scenes/Objects/media/pdf_book.tscn")
const POINTABLE_LAYER := 1 << 20
const CBZ_PATH := "user://__book_tests.cbz"
const MANUAL_NAME := "__book_tests_manual.cbz"

var _failed := 0
var _ran := 0


func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("[test] FAIL suite/timed out")
		get_tree().quit(1))

	await _test_unloadable_book()
	await _test_loaded_book()
	await _test_a_cached_page_never_decodes_on_the_main_thread()
	_test_saved_manual_follows_its_folder()

	print("[test] %d cases, %s" % [_ran,
		"PASS" if _failed == 0 else "%d FAILURE(S)" % _failed])
	get_tree().quit(0 if _failed == 0 else 1)


## The file is gone: the book stays a blank closed cover, and must be no bigger
## to the pointer than it looks.
func _test_unloadable_book() -> void:
	var book := _spawn_book("user://__book_tests_missing.pdf")
	await _settle()

	for zone: PageGrab in _zones(book):
		_ok(not zone.is_enabled(), "unloadable/%s is off" % zone.name)
		_ok(_shape_of(zone).disabled, "unloadable/%s shape is out of the world" % zone.name)
	# 0.3 m to the side: outside the book's own PointerArea (half-width 0.2),
	# well inside a default 1 m BoxShape3D.
	_ok(_ray_at(0.3) == null, "unloadable/a ray beside the book reaches what is behind it")
	_ok(not (_ray_at(0.0) is PageGrab), "unloadable/a ray at the book finds the book")

	book.queue_free()
	await _settle()


func _test_loaded_book() -> void:
	_write_cbz(CBZ_PATH)
	var cbz := ProjectSettings.globalize_path(CBZ_PATH)
	var book := _spawn_book(cbz)
	await _settle()
	await _drain_renders(book)

	var right := book.get_node("PageGrabRight") as PageGrab
	var left := book.get_node("PageGrabLeft") as PageGrab
	var zone_x := right.position.x
	_ok(book.net_get_page()["state"] == 0 and zone_x > 0.05, "closed/book loaded and laid out")
	_ok(right.is_enabled() and not _shape_of(right).disabled, "closed/the cover can be opened")
	var size := (_shape_of(right).shape as BoxShape3D).size
	_ok(size.x < 0.2 and size.y < 0.3, "closed/zone is page-sized (%.3f x %.3f)" % [size.x, size.y])
	_ok(_ray_at(zone_x) == right, "closed/a ray at the fore edge finds the page")
	# Closed, there is no left page: that zone is off and lies over empty floor.
	_ok(not left.is_enabled() and _shape_of(left).disabled, "closed/no page on the left to grab")
	_ok(not (_ray_at(-zone_x) is PageGrab), "closed/a ray left of the spine is not stopped by a dead zone")

	# The pointer target is the book's outline in THIS state. Authored as an open
	# spread centred on the spine, it once answered from a page-width of empty
	# air beside a closed book.
	var pointer_area := book.get_node("PointerArea")
	_ok(_ray_at(-zone_x) == null, "closed/nothing answers the pointer left of the spine")
	_ok(_ray_at(0.03) == pointer_area, "closed/the cover's inner strip is the book itself")
	var fresh := BOOK_SCENE.instantiate()
	_ok((fresh.get_node("PointerArea/CollisionShape3D") as CollisionShape3D).shape
		!= (pointer_area.get_child(0) as CollisionShape3D).shape,
		"closed/pointer shape is this book's own, not the scene's shared one")
	fresh.free()

	book.set_page(PDFBook.BookState.OPEN, 0)
	await _settle()
	_ok(_ray_at(-zone_x) == left and _ray_at(zone_x) == right, "open/both pages answer")
	_ok(_ray_at(-0.03) == pointer_area, "open/the left page's inner strip is the book itself")

	book.set_page(PDFBook.BookState.LAST_PAGE, 1)
	await _settle()
	_ok(_ray_at(zone_x) == null, "last page/nothing answers the pointer right of the spine")
	_ok(_ray_at(-zone_x) == left, "last page/the back cover can be turned back")

	book.set_page(PDFBook.BookState.CLOSED, 0)
	await _settle()
	await _drain_renders(book)

	# A reload that fails has to take the live zone away again.
	book.load_pdf("user://__book_tests_missing.cbz")
	await _settle()
	_ok(not right.is_enabled() and _shape_of(right).disabled, "reload/failed load switches the zone off")
	_ok(not (_ray_at(zone_x) is PageGrab), "reload/and takes it out of the ray's way")

	book.queue_free()
	await _settle()
	_remove_tree("user://pdf_cache/" + cbz.md5_text())
	DirAccess.remove_absolute(cbz)


## A page rendered on some earlier run is sitting in the cache dir, and reading
## it back is a ~11 ms decode plus a ~3 ms upload — against an 11 ms frame at
## 90 Hz. _get_page_texture used to do exactly that, inline, because no render
## was needed: a turn pulls in two pages and prefetches fifteen, so every turn
## of a book that had ever been read cost 28-34 ms and reopening one cost
## 150-220, while the FIRST read of the same book (nothing on disk yet, so it
## had to go to the pool) was smooth. Both paths go to the pool now.
## Numbers: Tools/perf/page_turn_probe.gd.
func _test_a_cached_page_never_decodes_on_the_main_thread() -> void:
	_write_cbz(CBZ_PATH)
	var cbz := ProjectSettings.globalize_path(CBZ_PATH)
	var book := _spawn_book(cbz)
	await _settle()
	await _drain_renders(book)
	book.set_page(PDFBook.BookState.OPEN, 0)
	await _settle()
	await _drain_renders(book)
	_ok(FileAccess.file_exists(book._cache_dir + "page_002.png"),
		"cache/the pages really are on disk")

	# Where a reopened book, and any page the trim has moved past, starts from.
	book._texture_cache.clear()
	var got := book._get_page_texture(2)
	_ok(got == book._loading_texture and not book._texture_cache.has(2),
		"cache/asking for a page that is on disk hands back the placeholder, not a decode")
	_ok(book._pending_renders.has(2), "cache/...and queues it for the worker pool")
	await _drain_renders(book)
	_ok(book._texture_cache.has(2) and book._get_page_texture(2) == book._texture_cache[2],
		"cache/...which arrives a frame or two later")

	# The uploads themselves are capped: a whole finished prefetch window is
	# fifteen pages, and an ImageTexture each would land as one hitch.
	book._texture_cache.clear()
	book._upload_queue.clear()
	var img := Image.create(8, 8, false, Image.FORMAT_RGB8)
	# Queued furthest-from-the-spread FIRST on purpose: drained in arrival order
	# this passes whatever the queue does, and the reader would be left looking
	# at the placeholder while pages they cannot see went up ahead of it.
	for page in [3, 2, 1, 0]:
		book._upload_queue.append([page, img])
	book._drain_uploads()
	_ok(book._texture_cache.size() == PDFBook.UPLOADS_PER_FRAME,
		"cache/at most %d pages are uploaded in a frame" % PDFBook.UPLOADS_PER_FRAME)
	# Nearest the open spread first, or a turn would show the placeholder while
	# pages nobody is looking at went up the queue ahead of it.
	_ok(book._texture_cache.has(1), "cache/...the pages being read go first")

	book.queue_free()
	await _settle()
	_remove_tree("user://pdf_cache/" + cbz.md5_text())
	DirAccess.remove_absolute(cbz)


## A scraped manual lives under roms/<systemid>/media/, so a room saved before a
## folder was renamed has to find it the way it finds the ROM. Writes one file
## under the player's REAL roms root (the path cannot be redirected) and removes
## exactly what it created.
func _test_saved_manual_follows_its_folder() -> void:
	var root := RomLibrary.default_roms_root()
	var created: Array[String] = []
	var dir := root
	for part: String in ["n64", "media", "manual"]:
		dir = dir.path_join(part)
		if not DirAccess.dir_exists_absolute(dir):
			created.append(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	RomLibrary.forget_rom_dirs()
	var now := dir.path_join(MANUAL_NAME)
	_write_cbz(now)

	var saved := root.path_join("nintendo_64/media/manual").path_join(MANUAL_NAME)
	var sp := ScenePersistence.new()
	var back := sp._deserialize_object({"type": "book", "pdf_path": saved}) as PDFBook
	_ok(back != null and back.pdf_path.simplify_path() == now.simplify_path(),
		"restore/a manual saved under the old folder name is found under the new one")
	if back != null:
		back.free()

	DirAccess.remove_absolute(now)
	created.reverse()
	for made: String in created:
		DirAccess.remove_absolute(made)
	RomLibrary.forget_rom_dirs()


# ── helpers ───────────────────────────────────────────────────────────────────

func _spawn_book(path: String) -> PDFBook:
	var book := BOOK_SCENE.instantiate() as PDFBook
	book.freeze = true
	book.pdf_path = path
	add_child(book)
	return book


## _ready awaits a frame before loading, set_enabled defers the shape, and the
## physics server has to step before a ray sees either.
func _settle() -> void:
	for i in 3:
		await get_tree().process_frame
	for i in 3:
		await get_tree().physics_frame


## Page decodes run on the worker pool and write into the cache dir — let them
## finish before it is deleted.
func _drain_renders(book: PDFBook) -> void:
	for i in 300:
		if book._pending_renders.is_empty():
			return
		await get_tree().process_frame


func _zones(book: PDFBook) -> Array[PageGrab]:
	return [book.get_node("PageGrabRight") as PageGrab, book.get_node("PageGrabLeft") as PageGrab]


func _shape_of(zone: PageGrab) -> CollisionShape3D:
	return zone.get_child(0) as CollisionShape3D


## What the reticle would land on, looking square at the book's front, x metres
## along it. Same layer and area/body flags as the pointer.
func _ray_at(x: float) -> Object:
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(x, 0.0, 2.0), Vector3(x, 0.0, -2.0), POINTABLE_LAYER)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit.get("collider") as Object


func _write_cbz(path: String) -> void:
	var zip := ZIPPacker.new()
	zip.open(path)
	for i in 4:
		var img := Image.create(20, 28, false, Image.FORMAT_RGB8)
		img.fill(Color(0.2 * i, 0.5, 0.5))
		zip.start_file("page_%02d.png" % i)
		zip.write_file(img.save_png_to_buffer())
		zip.close_file()
	zip.close()


func _remove_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for file: String in dir.get_files():
		dir.remove(file)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _ok(ok: bool, label: String) -> void:
	_ran += 1
	if ok:
		print("[test] ok   %s" % label)
	else:
		_failed += 1
		print("[test] FAIL %s" % label)
