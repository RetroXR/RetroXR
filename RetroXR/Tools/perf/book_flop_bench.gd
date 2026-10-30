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
##
## "room" is PDFBook._meet_room: one row of rays a tick, the patches placed in the
## book's frame, the fingertips (none here). It runs only for a held book, and the
## sim's contact work lands in "sim". The table scenarios hang the book over a
## real StaticBody3D, and lay it on one, so that work is actually done.
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
	print("[bench] %-46s %9s %9s %9s %9s %8s" % ["scenario", "room us", "sim us", "push us", "total us", "% core"])
	_run("one hand on the spine, face-up", FACE_UP, Vector3.ZERO, Vector3.INF)
	_run("held up in the air, nothing near", FACE_UP, Vector3.ZERO, Vector3.INF, Vector3(0.0, 2.0, 0.0))
	var table := _table()
	# A body is in the physics space's broadphase only after a step: queried
	# the frame it was added, the rays went straight through it.
	for i in 3:
		await get_tree().physics_frame
	_run("hanging onto a table 8 cm below", FACE_UP, Vector3.ZERO, Vector3.INF, Vector3(0.0, 0.08, 0.0))
	_run("lying on a table", FACE_UP, Vector3.ZERO, Vector3.INF, Vector3(0.0, 0.0015, 0.0))
	_run("turned over 13 cm above a table", FACE_DOWN, Vector3.ZERO, Vector3.INF, Vector3(0.0, 0.13, 0.0))
	table.queue_free()
	for i in 2:
		await get_tree().physics_frame
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


## `over` = where the book is held above the table's top (world), or INF with no
## table: the shake is smaller then, so it stays over or on it.
func _run(label: String, basis: Basis, hand: Vector3, second: Vector3, over: Vector3 = Vector3.INF) -> void:
	_book._flop.reset()
	_book._meet_room(false)
	var room_us := 0
	var sim_us := 0
	var push_us := 0
	var contacts := 0
	var t := 0.0
	for i in WARMUP + TICKS:
		t += DT
		if over.is_finite():
			var roll := Basis(Vector3.UP, 0.08 * sin(t * 1.7))
			_book.global_transform = Transform3D(basis * roll, Vector3(0.0, TABLE_TOP, 0.0) + over
				+ Vector3(0.01 * sin(t * 2.3), 0.002 * sin(t * 9.0), 0.0))
		else:
			var roll := Basis(Vector3.UP, 0.35 * sin(t * 1.7))
			_book.global_transform = Transform3D(basis * roll, Vector3(0.0, 0.04 * sin(t * 9.0), 0.0))
		var a := Time.get_ticks_usec()
		_book._flop.set_support(true, hand, second)
		_book._meet_room(over.is_finite())
		var b := Time.get_ticks_usec()
		_book._flop.drive_from_pose(DT, _book.global_transform, true)
		var c := Time.get_ticks_usec()
		_book._push_flop(false)
		var d := Time.get_ticks_usec()
		if i >= WARMUP:
			room_us += b - a
			sim_us += c - b
			push_us += d - c
			contacts += _book._flop.contacts[0] + _book._flop.contacts[1]
	var room := float(room_us) / TICKS
	var sim := float(sim_us) / TICKS
	var push := float(push_us) / TICKS
	var total := room + sim + push
	# Share of one core: microseconds per tick, 90 ticks a second.
	print("[bench] %-46s %9.1f %9.1f %9.1f %9.1f %7.2f%%   (%.1f points pushed a tick)" % [label, room, sim, push, total,
		total * 90.0 / 10000.0, float(contacts) / TICKS])


const TABLE_TOP := -0.5


func _table() -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, 0.04, 1.0)
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	body.global_position = Vector3(0.0, TABLE_TOP - 0.02, 0.0)
	return body


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
