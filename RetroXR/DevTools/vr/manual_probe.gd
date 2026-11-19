extends Node3D

## Why a scraped manual can come up as a navy slab with no pages.
##
## A book whose file fails to open keeps every authored default in
## pdf_book.tscn: navy StandardMaterial3D covers, both page stacks invisible,
## and a collision box centred on the spine rather than the one visible cover.
## _load_pdf_internal() has three early returns and they log three distinct
## lines, but the Quest's logcat ring buffer rotates in well under a minute, so
## the evidence is gone by the time anyone looks. This runs the same calls on
## device and prints each step.
##
## TWO legs, because a probe that only tests the broken thing cannot tell a bad
## PDF from a bad book pipeline:
##   control   a CBZ written here, through a real PDFBook  -- must load
##   subject   every scraped .pdf on the device            -- report each step
##
## Probe-only export (own package, never replaces the app) -- quest-device.md:
##   "$godot" --headless --path RetroXR --export-debug "Quest manual probe" m.apk

const BOOK_SCENE := preload("res://Scenes/Objects/media/pdf_book.tscn")
const CBZ_PATH := "user://__manual_probe.cbz"


func _ready() -> void:
	# Nothing on a headset would close a wedged probe.
	get_tree().create_timer(600.0).timeout.connect(func() -> void:
		print("[probe] GAVE UP")
		get_tree().quit(1))
	print("[probe] on %s, media root %s" % [OS.get_name(), DataPaths.media_root()])
	await _control_leg()
	await _subject_leg()
	print("[probe] done")
	get_tree().quit(0)


## The pipeline itself, on a file this probe wrote. If THIS comes back navy the
## problem is not the manual.
func _control_leg() -> void:
	print("[probe] === control: a CBZ written here ===")
	_write_cbz(ProjectSettings.globalize_path(CBZ_PATH))
	await _book_on(ProjectSettings.globalize_path(CBZ_PATH), "control CBZ")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CBZ_PATH))


func _subject_leg() -> void:
	var manuals := _find_manuals()
	# --file=<abs path>: test one file instead of scanning. Used to reproduce a
	# half-downloaded manual on desktop, where the device is not needed.
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--file="):
			manuals = PackedStringArray([arg.substr(7)])
			print("[probe] --file given, scanning skipped")
	print("[probe] === subject: %d scraped PDF(s) on this device ===" % manuals.size())
	var tested := 0
	for path: String in manuals:
		if tested >= 3:
			print("[probe]   (%d more not tested)" % (manuals.size() - tested))
			break
		tested += 1
		_raw_pdf(path)
		await _book_on(path, "book")


## Every step _load_pdf_internal takes, reported one at a time.
func _raw_pdf(path: String) -> void:
	print("[probe] --- %s" % path.get_file())
	print("[probe]   %d bytes on disk" % _size_of(path))
	var renderer: Object = ClassDB.instantiate("PDFRenderer")
	if renderer == null:
		print("[probe]   FAIL: PDFRenderer class not available (GDExtension not loaded)")
		return
	print("[probe]   PDFRenderer instantiated")
	if not renderer.open(path):
		print("[probe]   FAIL: open() false  <-- this is '[PDFBook] Failed to open PDF'")
		return
	print("[probe]   open() ok")
	var pages: int = renderer.get_page_count()
	print("[probe]   page_count = %d" % pages)
	if pages == 0:
		print("[probe]   FAIL: 0 pages  <-- this is '[PDFBook] PDF has 0 pages'")
		renderer.close()
		return
	var size: Vector2 = renderer.get_page_size(0)
	print("[probe]   page_size = %.1f x %.1f" % [size.x, size.y])
	var img: Image = renderer.render_page(0, 150)
	if img == null:
		print("[probe]   FAIL: render_page(0, 150) returned null")
	else:
		print("[probe]   rendered page 0 at %d x %d" % [img.get_width(), img.get_height()])
	renderer.close()


## The same path through a real PDFBook. The oracle is the COVER MATERIAL: a
## book that loaded wears paper.gdshader, one that failed still wears the
## scene's navy StandardMaterial3D -- which is exactly what "purple/blackish
## cover" looks like in the headset.
func _book_on(path: String, label: String) -> void:
	var book := BOOK_SCENE.instantiate() as PDFBook
	book.freeze = true
	book.pdf_path = path
	add_child(book)
	for i in 600:
		await get_tree().process_frame
		if book._page_count > 0:
			break
	var mat: Material = book._cover_mesh.get_active_material(0)
	var cached := not book._cache_dir.is_empty() and DirAccess.dir_exists_absolute(
		ProjectSettings.globalize_path(book._cache_dir))
	print("[probe]   %s: pages=%d leaves=%d cover=%s cache_dir=%s"
			% [label, book._page_count, book._leaf_count, mat.get_class(),
			"present" if cached else "MISSING"])
	print("[probe]   %s: stacks visible L=%s R=%s -> %s"
			% [label, book._left_stack.visible, book._right_stack.visible,
			"LOADED" if mat is ShaderMaterial else "NAVY SLAB (the reported bug)"])
	book.queue_free()
	await get_tree().process_frame


func _find_manuals() -> PackedStringArray:
	var found: PackedStringArray = []
	# Android gives each package its own /sdcard/Android/data/<pkg>, and this
	# probe is its OWN package, so the real app's roms tree is unreadable here
	# (that is scoped storage, not a permission we forgot). Anything pushed into
	# this probe's private dir is fair game, though:
	#   adb shell "cat <manual> | run-as com.xenu.retroxr.mprobe sh -c 'cat > files/x.pdf'"
	var own := DirAccess.open("user://")
	if own != null:
		for file: String in own.get_files():
			if file.get_extension().to_lower() == "pdf":
				found.append(ProjectSettings.globalize_path("user://".path_join(file)))
	var roms := DataPaths.media_root("roms")
	var dir := DirAccess.open(roms)
	if dir == null:
		print("[probe] cannot read %s (scoped storage: another package's dir)" % roms)
		return found
	for system: String in dir.get_directories():
		var manual_dir := roms.path_join(system).path_join("media/manual")
		var sub := DirAccess.open(manual_dir)
		if sub == null:
			continue
		for file: String in sub.get_files():
			if file.get_extension().to_lower() == "pdf":
				found.append(manual_dir.path_join(file))
	return found


func _size_of(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	return 0 if f == null else f.get_length()


func _write_cbz(path: String) -> void:
	var zip := ZIPPacker.new()
	zip.open(path)
	for i in 6:
		var img := Image.create(200, 280, false, Image.FORMAT_RGB8)
		img.fill(Color.from_hsv(float(i) / 6.0, 0.6, 0.85))
		zip.start_file("page_%02d.png" % i)
		zip.write_file(img.save_png_to_buffer())
		zip.close_file()
	zip.close()
