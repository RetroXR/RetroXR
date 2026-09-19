## book_flop_bench — what a floppy book costs the main thread, per physics tick.
##
##   "$godot" --path RetroXR --resolution 320x240 --position 20,20 \
##       res://Tools/perf/book_flop_bench.tscn
##
## Windowed, so set_shader_parameter goes to a real RenderingServer and not the
## dummy one. Times the two halves of PDFBook._physics_process separately —
## the sim (set_support + drive_from_pose) and handing its numbers to the
## shaders (_push_flop) — with get_ticks_usec around each call, the way
## rope_bench does: elapsed wall time per tick is paced by the main loop and
## makes every version look free.
##
## The pose MOVES every tick (a slow roll plus a shake), otherwise _push_flop's
## epsilon gate would skip the writes and the bench would time the cheap path.
## Each scenario is the cost of ONE held book. A book nobody holds has its tick
## switched off, so its cost is not small, it is zero — printed as a reminder,
## not measured.
##
## The GPU side is not here: it is a sin/cos pair per vertex on ~600 vertices
## (Quest) and cannot be timed from a script.
extends Node3D

const BOOK_SCENE := preload("res://Scenes/Objects/media/pdf_book.tscn")
const CBZ_PATH := "user://__book_flop_bench.cbz"
const PAGES := 28
const DT := 1.0 / 90.0
const WARMUP := 200
const TICKS := 3000

var FACE_UP := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
var FACE_DOWN := Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0))

var _book: PDFBook


func _ready() -> void:
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("[bench] FAIL timed out")
		get_tree().quit(1))
	_write_cbz(CBZ_PATH)
	_book = BOOK_SCENE.instantiate() as PDFBook
	_book.freeze = true
	_book.pdf_path = ProjectSettings.globalize_path(CBZ_PATH)
	add_child(_book)
	for i in 6:
		await get_tree().process_frame
	_book.set_page(PDFBook.BookState.OPEN, 6)
	for i in 900:
		if _book._pending_renders.is_empty():
			break
		await get_tree().process_frame

	print("[bench] one held book, %d ticks at 90 Hz, after %d warm-up. desktop=%s" % [
		TICKS, WARMUP, QualityManager.is_desktop()])
	print("[bench] %-46s %9s %9s %9s %8s" % ["scenario", "sim us", "push us", "total us", "% core"])
	_run("one hand on the spine, face-up", FACE_UP, Vector3.ZERO, Vector3.INF)
	_run("turned over: 6 loose leaves fanned", FACE_DOWN, Vector3.ZERO, Vector3.INF)
	_run("two hands, sagging", FACE_UP, Vector3(0.15, 0, 0), Vector3(-0.15, 0, 0))
	_book.hardback = true
	_run("hardback, one hand", FACE_UP, Vector3.ZERO, Vector3.INF)
	_book.hardback = false
	_book.set_page(PDFBook.BookState.CLOSED, 0)
	_run("shut, one hand", FACE_UP, Vector3.ZERO, Vector3.INF)
	print("[bench] not held: tick is OFF (is_physics_processing=%s) -> 0 us" % _book.is_physics_processing())

	var cache_dir: String = _book._cache_dir
	_book.queue_free()
	for i in 4:
		await get_tree().process_frame
	var dir := DirAccess.open(cache_dir)
	if dir:
		for file: String in dir.get_files():
			dir.remove(file)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(cache_dir))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CBZ_PATH))
	get_tree().quit(0)


func _run(label: String, basis: Basis, hand: Vector3, second: Vector3) -> void:
	_book._flop.reset()
	var sim_us := 0
	var push_us := 0
	var t := 0.0
	for i in WARMUP + TICKS:
		t += DT
		var roll := Basis(Vector3.UP, 0.35 * sin(t * 1.7))
		_book.global_transform = Transform3D(basis * roll, Vector3(0.0, 0.04 * sin(t * 9.0), 0.0))
		var a := Time.get_ticks_usec()
		_book._flop.set_support(true, hand, second)
		_book._flop.drive_from_pose(DT, _book.global_transform, true)
		var b := Time.get_ticks_usec()
		_book._push_flop(false)
		var c := Time.get_ticks_usec()
		if i >= WARMUP:
			sim_us += b - a
			push_us += c - b
	var sim := float(sim_us) / TICKS
	var push := float(push_us) / TICKS
	# Share of one core: microseconds per tick, 90 ticks a second.
	print("[bench] %-46s %9.1f %9.1f %9.1f %7.2f%%" % [label, sim, push, sim + push, (sim + push) * 90.0 / 10000.0])


func _write_cbz(path: String) -> void:
	var zip := ZIPPacker.new()
	zip.open(path)
	for i in PAGES:
		var img := Image.create(20, 28, false, Image.FORMAT_RGB8)
		img.fill(Color.from_hsv(float(i) / PAGES, 0.6, 0.8))
		zip.start_file("page_%02d.png" % i)
		zip.write_file(img.save_png_to_buffer())
		zip.close_file()
	zip.close()
