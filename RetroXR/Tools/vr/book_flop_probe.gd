## book_flop_probe — what a floppy book LOOKS like, as frames for an mp4.
##
## book_flop_tests proves the numbers and the wiring; it cannot show whether a
## drooping half reads as paper, whether the block comes through the page, or
## whether a fanned leaf is lit from the right side. This poses one book through
## the holds that matter and writes a frame per step.
##
## WINDOWED, never --headless: the dummy renderer hands back a correctly sized
## BLANK image, and every frame would "succeed".
##
##   "$godot" --path RetroXR --resolution 320x240 --position 20,20 \
##       res://Tools/vr/book_flop_probe.tscn -- --out=<dir> [--floppiness=0.7] [--pages=28] [--only=follow|flip|back|fanturn|spine|idle|table] [--nolid] [--nostack] [--nocontact] [--solid] [--hide=covers|blocks|tops|fan] [--outline|--hull]
##   python Tools/book_flop_video.py <dir>        # frames -> mp4 + contact sheet
##
## The window stays small; the book is drawn in its own 800x600 SubViewport.
##
## Nobody holds the book here, so its own tick is off. The probe moves the pose
## and steps the sim from it exactly as PDFBook._physics_process does — same
## drive_from_pose, same _push_flop — with a fixed dt, so the film is the same
## every run. Pages are drawn ASYMMETRIC (header bar, corner block, a count of
## dots) so a page that is mirrored, upside down or on the wrong leaf shows.
extends Node3D

const BOOK_SCENE := preload("res://Scenes/Objects/media/pdf_book.tscn")
const CBZ_PATH := "user://__book_flop_probe.cbz"
## --pages=N. 28 is a thin manual (a 1.4 mm block a side); 400 is a 2 cm book, whose
## surfaces sit a centimetre off the neutral plane the bend is written about.
var _pages := 28
const DT := 1.0 / 90.0
const TICKS_PER_FRAME := 3          # 30 fps film
const SIZE := Vector2i(800, 600)

# Book-local +Z is the page normal, +Y the spine. Columns are where the book's
# own X, Y, Z point in the world.
var FACE_UP := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
var FACE_DOWN := Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0))
var READING := Basis(Vector3.RIGHT, deg_to_rad(-25.0))

var _vp: SubViewport
var _cam: Camera3D
var _book: PDFBook
var _out := ""
var _frame := 0
var _caption := ""
var _captions: PackedStringArray = []
## RED: where the hand is. GREEN: the spot on the paper it gripped.
var _hand_dot: MeshInstance3D
## A family of surfaces taken out of the picture (--hide=covers|blocks|tops|fan):
## the way to find out what a patch of white actually IS.
var _hide := ""
## --outline: film with the pick-up outline up, which has to bend with the book.
## --hull: the same, with the depth-carved hull a foveated Quest session draws
## instead of the stencil pair (PickableHighlight.force_hull).
var _outline := false
var _hull := false
## Print the page-turn solver's state every frame of a flip.
var _trace := false
var _grip_dot: MeshInstance3D
## --nolid: the control for --only=fanturn — the page does not rest on the loose
## leaves and puts no lid on them, as before 2026-10-26, and goes through them.
var _nolid := false
## --nostack: the control for --only=spine — every sheet's stack_layer zeroed, as
## before 2026-10-26, so sheets a fraction of a millimetre apart by the spine draw
## in whatever order their bends happen to put them.
var _nostack := false
## --solid: every page one flat colour, each far from its neighbours' (golden-ratio
## hues, light and dark alternating), so a page drawn where another should be is
## plain at a glance and its colour says which page it is.
var _solid := false
## --only=table: the book over a real table, as PDFBook meets the room
## (_meet_room) — hung onto it, laid on it, held over its edge, lifted by a
## fingertip, and turned over onto it. --nocontact is the control: the same moves
## with nothing given to the sim, so the pages go through the table and the finger.
var _contact := true
var _finger_ball: MeshInstance3D
var _look := Vector3.ZERO
## Where the table's top is, and its left edge, in the world.
const TABLE_Y := -0.08
const TABLE_EDGE_X := -0.30


func _ready() -> void:
	get_tree().create_timer(240.0).timeout.connect(func() -> void:
		print("[probe] FAIL timed out")
		get_tree().quit(1))
	var floppiness := 0.7
	var only_follow := false
	var only_flip := false
	var only_back := false
	var only_fanturn := false
	var only_spine := false
	var only_idle := false
	var only_table := false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg.begins_with("--floppiness="):
			floppiness = float(arg.trim_prefix("--floppiness="))
		elif arg == "--only=follow":
			only_follow = true
		elif arg == "--only=flip":
			only_flip = true
		elif arg == "--only=back":
			only_back = true
		elif arg == "--only=fanturn":
			only_fanturn = true
		elif arg == "--nolid":
			_nolid = true
		elif arg == "--only=spine":
			only_spine = true
		elif arg == "--only=idle":
			only_idle = true
		elif arg == "--only=table":
			only_table = true
		elif arg == "--nocontact":
			_contact = false
		elif arg == "--nostack":
			_nostack = true
		elif arg == "--solid":
			_solid = true
		elif arg.begins_with("--pages="):
			_pages = maxi(int(arg.trim_prefix("--pages=")), 8)
		elif arg == "--outline":
			_outline = true
		elif arg == "--hull":
			_outline = true
			_hull = true
		elif arg.begins_with("--hide="):
			_hide = arg.trim_prefix("--hide=")
	if _out.is_empty():
		print("[probe] FAIL no --out=<dir>")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	# The page turns riffle; a film does not need to be heard on somebody's desk.
	AudioServer.set_bus_mute(0, true)

	_build_stage()
	_write_cbz(CBZ_PATH)
	_book = BOOK_SCENE.instantiate() as PDFBook
	_book.freeze = true
	_book.floppiness = floppiness
	_book._flop.rest_on_fan = not _nolid
	_book.pdf_path = ProjectSettings.globalize_path(CBZ_PATH)
	if _hull:
		(_book.get_node("PickableHighlight") as PickableHighlight).force_hull = true
	_vp.add_child(_book)
	for i in 6:
		await get_tree().process_frame
	# Open to the middle, so both halves have leaves to fan.
	@warning_ignore("integer_division")
	_book.set_page(PDFBook.BookState.OPEN, _pages / 4 - 1)
	for i in 900:
		if _book._pending_renders.is_empty():
			break
		await get_tree().process_frame
	for i in 10:
		await get_tree().process_frame
	_book._refresh_visible_textures()
	if _outline:
		# The held-by-ray yellow: hover white does not show against cream paper.
		var highlight := _book.get_node("PickableHighlight") as PickableHighlight
		highlight.hover_color = highlight.ray_color
		highlight.outline_width = 2.0
		highlight._sync_material_params()
		_book.highlight_updated.emit(_book, true)
	print("[probe] book %d pages, width %.3f, floppiness %.2f" % [_book._page_count, _book._book_width, floppiness])

	var above := Vector3(0.22, 0.34, 0.52)
	var below := Vector3(0.30, -0.20, 0.50)
	var front := Vector3(0.18, 0.10, 0.62)

	if only_table:
		await _table_views()
		await _finish()
		return
	await _hold("1 held level by the spine, face-up", FACE_UP, FACE_UP, above, 2.2)
	_report()
	if only_back:
		await _back_views()
		await _finish()
		return
	if only_flip:
		_trace = true
		await _flip("a page turned on the hanging book", 1, 1.8)
		await _finish()
		return
	if only_idle:
		# No page turned: held upright in front of the face, then tipped over and
		# rocked, close on the binding from either side. Whatever clips here is
		# between sheets just hanging there.
		var upright := Basis(Vector3.RIGHT, deg_to_rad(-80.0)) * FACE_UP
		await _hold("I1 held upright, close on the spine", FACE_UP, upright, Vector3(0.04, 0.05, 0.22), 3.0)
		await _hold("I2 upright, from the other side", upright, upright, Vector3(-0.06, 0.05, 0.21), 1.5)
		await _hold("I3 tipped over the top", upright, FACE_DOWN, Vector3(0.10, -0.16, 0.17), 3.0)
		await _hold("I4 rocked", FACE_DOWN, FACE_DOWN * Basis(Vector3.UP, deg_to_rad(25.0)), Vector3(0.10, -0.16, 0.17), 2.5)
		await _hold("I5 rocked back", FACE_DOWN * Basis(Vector3.UP, deg_to_rad(25.0)), FACE_DOWN * Basis(Vector3.UP, deg_to_rad(-25.0)), Vector3(-0.08, -0.16, 0.17), 3.0)
		await _hold("I6 back upright", FACE_DOWN, upright, Vector3(0.04, 0.05, 0.22), 3.0)
		await _finish()
		return
	if only_spine:
		# Close in on the binding while the book is tipped down, slowly, until its
		# leaves fan, and a page turned there: where every sheet meets the others a
		# fraction of a millimetre apart.
		var close := Vector3(0.10, -0.16, 0.17)
		await _hold("S1 close on the spine, face up", FACE_UP, FACE_UP, Vector3(0.10, 0.16, 0.17), 1.0)
		await _hold("S2 tipped down slowly, from underneath", FACE_UP, FACE_DOWN, close, 4.0)
		await _flip("S3 a page turned off the fanned side", 1, 2.4)
		await _hold("S4 and held", FACE_DOWN, FACE_DOWN, close, 1.2)
		await _key_turn("S5 E pressed", 1)
		await _hold("S6 tipped back up", FACE_DOWN, FACE_UP, Vector3(0.10, 0.16, 0.17), 3.0)
		await _finish()
		return
	if only_fanturn:
		# Turned over so both fans are up, then pages turned onto them: the page
		# must come down onto the far side's top loose leaf and rest there, never
		# through them, and land as the new top leaf with no page jumping.
		await _hold("F1 turned over: the loose leaves fan off both blocks", FACE_UP, FACE_DOWN, below, 2.6)
		await _flip("F2 a page turned by hand onto the far fan", 1, 2.4)
		await _hold("F3 the fan comes back up, the landed page on top", FACE_DOWN, FACE_DOWN, below, 1.4)
		await _key_turn("F4 E pressed: a page sprung over onto it", 1)
		await _hold("F5 and up again", FACE_DOWN, FACE_DOWN, below, 1.4)
		await _key_turn("F6 Q pressed: one turned back onto the other fan", -1)
		await _hold("F7 and up again", FACE_DOWN, FACE_DOWN, below, 1.4)
		await _finish()
		return
	if only_follow:
		# The quick loop for working on page turning: skip the other holds.
		await _follow()
		await _finish()
		return
	await _hold("2 tilted up to read: spine vertical", FACE_UP, READING, front, 2.0)
	_report()
	await _hold("3 turned over, spine on top: halves hang, pages fan", READING, FACE_DOWN, below, 3.0)
	_report()
	await _hold("4 back to level", FACE_DOWN, FACE_UP, above, 2.0)
	await _hold("5 held by the RIGHT page, 10 cm out", FACE_UP, FACE_UP, above, 2.2, Vector3(0.10, 0, 0))
	_report()
	await _hold("6 a hand on EACH end: held up, and sagging in the middle", FACE_UP, FACE_UP, above, 2.6,
		Vector3(0.15, 0, 0), 0.0, 0.0, true, Vector3(-0.15, 0, 0))
	_report()
	await _hold("6b back to one hand on the spine", FACE_UP, FACE_UP, above, 1.6)
	await _flip("6c a page turned on the hanging book", 1, 1.8)
	await _flip("6d and another", 1, 1.5)
	await _flip("6e and one turned back", -1, 1.8)
	_report()
	await _follow()
	await _hold("7 shaken up and down", FACE_UP, FACE_UP, above, 2.5, Vector3.ZERO, 0.05, 3.0)
	await _hold("8 rolled 50 degrees about the spine", FACE_UP, FACE_UP * Basis(Vector3.UP, deg_to_rad(50.0)), above, 2.2)
	_report()
	_book.hardback = true
	await _hold("9 HARDBACK, level by the spine: lies open", FACE_UP, FACE_UP, above, 2.2)
	_report()
	await _flip("9b HARDBACK: a page turned", 1, 1.8)
	await _hold("10 HARDBACK turned over: boards swing, pages fan", FACE_UP, FACE_DOWN, below, 3.0)
	_report()
	await _hold("11 HARDBACK back to level", FACE_DOWN, FACE_UP, above, 2.0)
	_book.hardback = false
	_book.set_page(PDFBook.BookState.CLOSED, 0)
	await _hold("12 soft cover again, shut, level by the spine", FACE_UP, FACE_UP, above, 2.2)
	_report()
	await _hold("13 put down: relaxes flat", FACE_UP, FACE_UP, above, 1.5, Vector3.ZERO, 0.0, 0.0, false)
	_report()

	await _finish()


func _finish() -> void:
	var f := FileAccess.open(_out.path_join("captions.txt"), FileAccess.WRITE)
	f.store_string("\n".join(_captions))
	f.close()
	print("[probe] wrote %d frames to %s" % [_frame, _out])

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


## Move from one orientation to another over the first third of the segment,
## then hold, stepping the sim from the pose the whole way.
func _hold(caption: String, from: Basis, to: Basis, cam_pos: Vector3, seconds: float,
		hand: Vector3 = Vector3.ZERO, shake_m: float = 0.0, shake_hz: float = 0.0,
		held: bool = true, second_hand: Vector3 = Vector3.INF) -> void:
	_caption = caption
	print("[probe] %s" % caption)
	var frames := int(seconds * 30.0)
	var cam_from := _cam.position
	var t := 0.0
	for i in frames:
		for k in TICKS_PER_FRAME:
			t += DT
			var blend := smoothstep(0.0, 1.0, clampf(t / (seconds * 0.35), 0.0, 1.0))
			var basis := Basis(from.get_rotation_quaternion().slerp(to.get_rotation_quaternion(), blend))
			var lift := shake_m * sin(TAU * shake_hz * t)
			_book.global_transform = Transform3D(basis, Vector3(0.0, lift, 0.0))
			_book._flop.set_support(held, hand, second_hand)
			_lid()
			_book._flop.drive_from_pose(DT, _book.global_transform, held)
			_book._push_flop(false)
			_cam.position = cam_from.lerp(cam_pos, blend)
			_cam.look_at(Vector3.ZERO, Vector3.UP)
		await _capture()


func _capture() -> void:
	if _nostack:
		for node: Node in _book.find_children("*", "MeshInstance3D", true, false):
			var mat := (node as MeshInstance3D).get_surface_override_material(0) as ShaderMaterial
			if mat and mat.shader == PDFBook.PAPER_SHADER:
				mat.set_shader_parameter("stack_layer", 0.0)
	if _hide != "":
		# Every frame: the book's layout code keeps switching these back on.
		var gone: Array = []
		match _hide:
			"covers": gone = [_book._cover_mesh, _book._back_cover_mesh]
			"blocks": gone = [_book._left_stack, _book._right_stack]
			"tops": gone = [_book._left_stack_top, _book._right_stack_top]
			"fan": gone = [_book._fan_root]
		for node: Node3D in gone:
			node.visible = false
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	img.save_jpg(_out.path_join("f_%04d.jpg" % _frame), 0.9)
	_captions.append("%04d\t%s" % [_frame, _caption])
	_frame += 1


## The COVERS. Every other segment looks at the pages, so the covers' outer faces
## are only ever seen in passing; this goes round the back. From underneath a book
## hanging face-up (covers down), while pages are turned above; from behind one
## held up to read; from above one turned over (covers up), fan out below; and a
## shut book from underneath. Anything white here that is not page paper is a bug.
func _back_views() -> void:
	var under := Vector3(0.24, -0.36, 0.40)
	var under_left := Vector3(-0.30, -0.30, 0.36)
	var behind := Vector3(0.26, 0.12, -0.60)
	var over := Vector3(0.22, 0.40, 0.46)
	await _hold("B1 from UNDERNEATH: hanging face-up, covers toward the camera", FACE_UP, FACE_UP, under, 2.4)
	await _flip("B2 from underneath: a page turned above", 1, 1.8)
	await _flip("B3 from underneath: and one turned back", -1, 1.8)
	await _hold("B4 from underneath, the other side", FACE_UP, FACE_UP, under_left, 2.0)
	await _hold("B5 a hand on each end, from underneath", FACE_UP, FACE_UP, under, 2.2,
		Vector3(0.15, 0, 0), 0.0, 0.0, true, Vector3(-0.15, 0, 0))
	await _hold("B6 held up to read, from BEHIND", FACE_UP, READING, behind, 2.4)
	await _hold("B7 turned over: covers up, seen from ABOVE", READING, FACE_DOWN, over, 3.0)
	await _hold("B8 turned over, from above on the other side", FACE_DOWN, FACE_DOWN, Vector3(-0.26, 0.40, 0.44), 2.0)
	await _hold("B9 shaken while turned over", FACE_DOWN, FACE_DOWN, over, 2.0, Vector3.ZERO, 0.05, 3.0)
	await _hold("B10 back to level, from underneath", FACE_DOWN, FACE_UP, under, 2.4)
	_book.hardback = true
	await _hold("B11 HARDBACK from underneath", FACE_UP, FACE_UP, under, 2.0)
	await _hold("B12 HARDBACK turned over, from above", FACE_UP, FACE_DOWN, over, 2.6)
	await _hold("B13 HARDBACK back to level", FACE_DOWN, FACE_UP, under, 2.0)
	_book.hardback = false
	_book.set_page(PDFBook.BookState.CLOSED, 0)
	await _hold("B14 SHUT, from underneath: the back cover", FACE_UP, FACE_UP, under, 2.2)
	await _hold("B15 shut, turned over", FACE_UP, FACE_DOWN, over, 2.4)


## The pages meet the room. A real table (a StaticBody3D on layer 1, as furniture
## is) under the book, found by the book's own rays; the fingertip is a ball
## handed to the sim the way _place_fingers hands it a controller's poke tip.
## What it must show: halves hanging ONTO the table and lying flat on it, a half
## hanging over the table's edge from a binding resting on it, a hanging half
## lifted by the finger and never passing it, the loose leaves of a book turned
## over coming down onto the table. --nocontact films the same moves going through.
func _table_views() -> void:
	var table := StaticBody3D.new()
	table.name = "Table"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 0.03, 0.4)
	shape.shape = box
	table.add_child(shape)
	var top := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = box.size
	top.mesh = mesh
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.42, 0.27, 0.16)
	wood.roughness = 0.7
	top.material_override = wood
	table.add_child(top)
	_vp.add_child(table)
	table.global_position = Vector3(TABLE_EDGE_X + 0.3, TABLE_Y - 0.015, 0.0)

	_finger_ball = MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = BookFlop.FINGER_RADIUS
	ball.height = BookFlop.FINGER_RADIUS * 2.0
	_finger_ball.mesh = ball
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.85, 0.25, 0.2)
	_finger_ball.material_override = skin
	_finger_ball.visible = false
	_vp.add_child(_finger_ball)

	var lying := TABLE_Y - _book._drawn_z_span().x + 0.0005
	var over := Transform3D(FACE_UP, Vector3.ZERO)
	var on := Transform3D(FACE_UP, Vector3(0.0, lying, 0.0))
	var at_edge := Transform3D(FACE_UP, Vector3(TABLE_EDGE_X + 0.006, lying, 0.0))
	var side := Vector3(0.34, -0.02, 0.40)
	var look := Vector3(0.0, TABLE_Y + 0.03, 0.0)
	_look = look
	_cam.position = side
	_cam.look_at(_look, Vector3.UP)
	await _carry("T1 held by the spine 8 cm over a table: the halves hang ONTO it", over, over, side, look, 2.5)
	_report()
	await _carry("T2 lowered onto it: they lie flat on it", over, on, side, look, 2.5)
	_report()
	await _carry("T3 lifted off again", on, over, side, look, 1.6)
	var edge_cam := Vector3(TABLE_EDGE_X - 0.22, TABLE_Y + 0.10, 0.36)
	var edge_look := Vector3(TABLE_EDGE_X, TABLE_Y - 0.02, 0.0)
	await _carry("T4 laid down at the table's edge: the half past it hangs over", over, at_edge, edge_cam, edge_look, 3.0)
	_report()
	await _carry("T5 lifted back over the table", at_edge, over, side, look, 2.0)
	# Edge on, along the spine: the page's profile with the finger under it.
	await _carry("T6 a fingertip rises under the right half and lifts it", over, over, Vector3(0.05, -0.01, 0.50),
		Vector3(0.05, -0.03, 0.0), 3.0,
		[Vector3(0.12, TABLE_Y + 0.004, 0.0), Vector3(0.12, 0.03, 0.0)])
	_report()
	_finger_ball.visible = false
	await _carry("T7 the finger gone: it hangs onto the table again", over, over, side, look, 1.6)
	var high := Transform3D(FACE_DOWN, Vector3(0.0, TABLE_Y + 0.13, 0.0))
	await _carry("T8 turned over 13 cm up: the loose leaves fan down onto the table", over, high,
		Vector3(0.36, TABLE_Y + 0.05, 0.36), Vector3(0.0, TABLE_Y + 0.05, 0.0), 3.0)
	_report()
	var face_down_on := Transform3D(FACE_DOWN, Vector3(0.0, TABLE_Y + _book._drawn_z_span().y + 0.0005, 0.0))
	await _carry("T9 put down on it face-down: pages flat on the table", high, face_down_on,
		Vector3(0.36, TABLE_Y + 0.08, 0.36), Vector3(0.0, TABLE_Y, 0.0), 2.6)
	_report()


## Carry the held book from one pose to another over the first 60% of the segment,
## then hold, stepping the sim as PDFBook._physics_process does — meeting the room
## first, unless --nocontact. `finger` = [from, to] moves a fingertip with it.
func _carry(caption: String, from: Transform3D, to: Transform3D, cam_pos: Vector3, look: Vector3,
		seconds: float, finger: Array = []) -> void:
	_caption = caption
	print("[probe] %s" % caption)
	var frames := int(seconds * 30.0)
	var cam_from := _cam.position
	var look_from := _look
	var t := 0.0
	# Once there, nothing should move: the worst tick-to-tick turn of either fore
	# edge while held still, which is how a page buzzing against a table shows.
	var buzz := 0.0
	var tips := Vector2(_book._flop.tip_angle(-1), _book._flop.tip_angle(1))
	for i in frames:
		for k in TICKS_PER_FRAME:
			t += DT
			var blend := smoothstep(0.0, 1.0, clampf(t / (seconds * 0.6), 0.0, 1.0))
			var basis := Basis(from.basis.get_rotation_quaternion().slerp(to.basis.get_rotation_quaternion(), blend))
			_book.global_transform = Transform3D(basis, from.origin.lerp(to.origin, blend))
			_book._flop.set_support(true, Vector3.ZERO)
			_lid()
			if _contact:
				_book._meet_room(true)
			if finger.size() == 2:
				var tip: Vector3 = (finger[0] as Vector3).lerp(finger[1], blend)
				_finger_ball.global_position = tip
				_finger_ball.visible = true
				if _contact:
					_book._flop.fingers.append([_book.to_local(tip), BookFlop.FINGER_RADIUS, 99])
			_book._flop.drive_from_pose(DT, _book.global_transform, true)
			_book._log_contact()
			_book._push_flop(false)
			_cam.position = cam_from.lerp(cam_pos, blend)
			_look = look_from.lerp(look, blend)
			_cam.look_at(_look, Vector3.UP)
			var now := Vector2(_book._flop.tip_angle(-1), _book._flop.tip_angle(1))
			if t > seconds * 0.85:
				buzz = maxf(buzz, maxf(absf(now.x - tips.x), absf(now.y - tips.y)))
			tips = now
		await _capture()
	print("[probe]   held still at the end: worst tick-to-tick turn of a fore edge %.4f deg" % rad_to_deg(buzz))


## Turn a page with a scripted hand, through the same three calls the grab zones
## make (begin / move / end) — nothing here touches the fold solver. The hand
## grips near the fore edge and is carried over the gutter in an arc; its path is
## written on the FLAT page and taken through the bend, so it follows paper that
## is hanging — through the LEAF's bend (bend_over), which is the one that is
## continuous across the gutter. The book keeps being held by the spine throughout.
func _flip(caption: String, dir: int, seconds: float) -> void:
	_caption = caption
	print("[probe] %s" % caption)
	var w := _book._book_width
	var from_leaf := _book._current_leaf
	var frames := int(seconds * 30.0)
	for i in frames:
		var u := float(i) / float(frames - 1)
		for k in TICKS_PER_FRAME:
			_book._flop.set_support(true, Vector3.ZERO)
			_lid()
			_book._flop.drive_from_pose(DT, _book.global_transform, true)
			_book._push_flop(false)
		var along := lerpf(w * 0.85, -w * 0.70, smoothstep(0.0, 1.0, u))
		var flat := Vector3(float(dir) * along, -0.04 + 0.06 * u,
			_book._page_plane_z(dir) + 0.004 + 0.10 * sin(PI * u))
		var hand := _book.to_global(_book._flop.bend_over(flat, dir))
		if i == 0:
			_book._on_page_grab_begin(dir, hand)
		else:
			_book._on_page_grab_move(hand)
		if _trace:
			var seen := _book._leaf_local(hand, _book._leaf_lift)
			var fold := _book._fold_for(seen)
			print("[probe]   f%03d flat hand (%.0f, %.0f) mm | lift %5.1f deg | in the leaf's frame: across %.0f up %.0f | radius %.0f mm, curl line %.0f mm back (limit %.0f)" % [
				_frame, flat.x * 1000.0, (flat.z - _book._page_plane_z(dir)) * 1000.0, rad_to_deg(_book._leaf_lift),
				(Vector2(seen.x, seen.y) - _book._grab_anchor).length() * 1000.0, seen.z * 1000.0,
				(float(fold[1]) if not fold.is_empty() else 0.0) * 1000.0,
				(float(fold[2]) if not fold.is_empty() else 0.0) * 1000.0,
				(float(fold[3]) if not fold.is_empty() else 0.0) * 1000.0])
		await _capture()
	_book._on_page_grab_end(dir)
	# The settle is a Tween on real time; film it until the leaf is gone.
	for i in 45:
		for k in TICKS_PER_FRAME:
			_lid()
			_book._flop.drive_from_pose(DT, _book.global_transform, true)
			_book._push_flop(false)
		await _capture()
		if _book._active_leaf == null and i > 8:
			break
	print("[probe]   leaf %d -> %d" % [from_leaf, _book._current_leaf])


## A page sprung over as E / Q does (_play_turn), filmed until it has landed.
func _key_turn(caption: String, dir: int) -> void:
	_caption = caption
	print("[probe] %s" % caption)
	var from_leaf := _book._current_leaf
	_book._play_turn(dir, {}, PDFBook.KEY_TURN_TIME * 2.0)
	# The spring is a Tween on real time, and frames here go faster than that:
	# film until it has landed, not for a count of frames.
	for i in 600:
		for k in TICKS_PER_FRAME:
			_lid()
			_book._flop.drive_from_pose(DT, _book.global_transform, true)
			_book._push_flop(false)
		await _capture()
		if _book._active_leaf == null:
			break
	print("[probe]   leaf %d -> %d" % [from_leaf, _book._current_leaf])


## PDFBook._physics_process puts the turning pages' lid on the fan before it
## steps the sim; so does every tick here, unless --nolid.
func _lid() -> void:
	if _nolid:
		_book._flop.set_fan_lid(-1, INF)
		_book._flop.set_fan_lid(1, INF)
	else:
		_book._update_fan_lids()


## Does the page follow the hand? Grip the fore edge and pull OVER the page toward
## the spine, then back OUT past the fore edge, then UP and AWAY, and let go
## without committing. The red dot is the hand, the green dot the gripped spot of
## the paper, and the gap between them is printed per phase — the fold solver's
## claim is that the gripped spot sits under the hand, and this is the check.
func _follow() -> void:
	_caption = "6f pulled OVER, UP, OUT, AWAY, then carried over the SPINE and set DOWN (red = hand, green = gripped paper)"
	print("[probe] %s" % _caption)
	var w := _book._book_width
	var plane := _book._page_plane_z(1)
	var start := Vector3(w * 0.85, -0.02, plane + 0.004)
	# Way-points on the FLAT page: [name, point, frames]
	var legs := [
		["over ", Vector3(w * 0.25, -0.02, plane + 0.07), 40],
		# Straight UP, higher than the fold alone can carry a page (9 cm), but
		# still within the paper's reach of the gutter: this one must close.
		["up   ", Vector3(w * 0.45, -0.02, plane + 0.115), 40],
		["out  ", Vector3(w * 1.25, -0.02, plane + 0.05), 40],
		["away ", Vector3(w * 0.70, 0.02, plane + 0.26), 40],
		# Held up and carried OVER THE SPINE: the page used to let go here, the
		# moment it leaned past upright, and trail the hand by 11-22 cm.
		["spine", Vector3(w * -0.55, -0.02, plane + 0.08), 50],
		# ...and set down on the far page, where it hands over to the roll.
		["down ", Vector3(w * -0.60, -0.02, plane + 0.004), 40],
		["back ", start, 30],
	]
	_hand_dot.visible = true
	_grip_dot.visible = true
	var from := start
	var begun := false
	for leg: Array in legs:
		var worst := 0.0
		var worst_plane := 0.0
		var last := 0.0
		for i in int(leg[2]):
			var u := smoothstep(0.0, 1.0, float(i + 1) / float(leg[2]))
			var flat: Vector3 = from.lerp(leg[1], u)
			for k in TICKS_PER_FRAME:
				_book._flop.set_support(true, Vector3.ZERO)
				_lid()
				_book._flop.drive_from_pose(DT, _book.global_transform, true)
				_book._push_flop(false)
			var hand := _book.to_global(_book._flop.bend_over(flat, 1))
			if not begun:
				_book._on_page_grab_begin(1, _book.to_global(_book._flop.bend_over(start, 1)))
				begun = true
			_book._on_page_grab_move(hand)
			var grip := _grip_world()
			_hand_dot.global_position = hand
			_grip_dot.global_position = grip
			last = grip.distance_to(hand)
			worst = maxf(worst, last)
			var gap := _book.to_local(grip) - _book.to_local(hand)
			worst_plane = maxf(worst_plane, Vector2(gap.x, gap.y).length())
			await _capture()
		print("[probe]   %s gap hand<->paper: end %.0f mm, worst %.0f mm (across the page %.0f mm)"
			% [leg[0], last * 1000.0, worst * 1000.0, worst_plane * 1000.0])
		# What the paper allows: a hand further from the gutter than the grip is
		# out of reach, and the best a taut page can do is point at it.
		var target: Vector3 = leg[1]
		var reach := _book._grab_anchor.x + w * 0.5 + PDFBook.SPINE_WIDTH * 0.5
		var from_gutter := Vector2(target.x, target.z - plane).length()
		print("[probe]          lift %.0f deg | hand %.0f mm from the gutter, paper reaches %.0f -> unavoidable gap %.0f mm | paper at %s, hand at %s"
			% [rad_to_deg(_book._leaf_lift), from_gutter * 1000.0, reach * 1000.0,
				maxf(from_gutter - reach, 0.0) * 1000.0,
				str((_book.to_local(_grip_dot.global_position) * 1000.0).round()),
				str((_book.to_local(_hand_dot.global_position) * 1000.0).round())])
		var seen := _book._leaf_local(_hand_dot.global_position, _book._leaf_lift)
		var fold := _book._fold_for(seen)
		print("[probe]          in the leaf's frame the hand is (%.0f, %.0f, %.0f) mm, grip anchor (%.0f, %.0f) | radius %.0f, curl line %.0f back, limit %.0f | fold strength %.0f" % [
			seen.x * 1000.0, seen.y * 1000.0, seen.z * 1000.0, _book._grab_anchor.x * 1000.0, _book._grab_anchor.y * 1000.0,
			(float(fold[1]) if not fold.is_empty() else 0.0) * 1000.0, (float(fold[2]) if not fold.is_empty() else 0.0) * 1000.0,
			(float(fold[3]) if not fold.is_empty() else 0.0) * 1000.0,
			float((_book._active_leaf.get_surface_override_material(0) as ShaderMaterial).get_shader_parameter("fold_strength"))])
		from = leg[1]
	_book._on_page_grab_end(1)
	_hand_dot.visible = false
	_grip_dot.visible = false
	for i in 30:
		for k in TICKS_PER_FRAME:
			_lid()
			_book._flop.drive_from_pose(DT, _book.global_transform, true)
			_book._push_flop(false)
		await _capture()
		if _book._active_leaf == null and i > 8:
			break


## Where the gripped spot of the turning leaf is in the world: the fold wrap of
## paper.gdshader replayed on the CPU for that one point, then the leaf's bend.
func _grip_world() -> Vector3:
	var leaf := _book._active_leaf
	if leaf == null:
		return Vector3.ZERO
	var anchor: Vector2 = _book._grab_anchor
	var mat := leaf.get_surface_override_material(0) as ShaderMaterial
	var xy := anchor
	var z := 0.0
	if float(mat.get_shader_parameter("fold_strength")) > 0.0:
		var fn: Vector2 = (mat.get_shader_parameter("fold_normal") as Vector2).normalized()
		var origin: Vector2 = mat.get_shader_parameter("fold_origin")
		var d := (anchor - origin).dot(fn)
		if d > 0.0:
			var u := clampf(0.5 + float(_book._grab_dir) * anchor.x / _book._book_width, 0.0, 1.0)
			var r := maxf(float(mat.get_shader_parameter("curl_radius"))
				* (1.0 + float(mat.get_shader_parameter("curl_taper")) * (1.0 - u)), 1e-4)
			var fold_pt := anchor - fn * d
			var arc := d / r
			if arc < PI:
				xy = fold_pt + fn * (r * sin(arc))
				z = r * (1.0 - cos(arc))
			else:
				xy = fold_pt - fn * (d - PI * r)
				z = 2.0 * r
	var book_local := leaf.position + Vector3(xy.x, xy.y, z)
	return _book.to_global(_book._flop.bend_over(book_local, _book._turn_direction, _book._leaf_lift, leaf.position.z))


func _report() -> void:
	var flop := _book._flop
	print("[probe]   tip L %.1f R %.1f deg | hinge L %.1f R %.1f | support R %.3f m | sag %.1f mm (slope %.1f deg) | fan shown L %d R %d" % [
		rad_to_deg(flop.tip_angle(-1)), rad_to_deg(flop.tip_angle(1)),
		rad_to_deg(flop.hinge(-1)), rad_to_deg(flop.hinge(1)),
		flop.support(1), flop.sag() * 1000.0, rad_to_deg(flop.sag_slope(1)),
		_book._fan_shown[0], _book._fan_shown[1]])


func _build_stage() -> void:
	_vp = SubViewport.new()
	_vp.size = SIZE
	_vp.own_world_3d = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.msaa_3d = Viewport.MSAA_4X
	add_child(_vp)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.16, 0.17, 0.20)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.78, 0.85)
	env.ambient_light_energy = 0.55
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_vp.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, 35.0, 0.0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	_vp.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(40.0, -140.0, 0.0)
	fill.light_energy = 0.35
	_vp.add_child(fill)

	_hand_dot = _make_dot(Color(1.0, 0.15, 0.1), 0.009)
	_grip_dot = _make_dot(Color(0.1, 0.95, 0.25), 0.006)

	_cam = Camera3D.new()
	_cam.fov = 40.0
	_cam.near = 0.02
	_cam.position = Vector3(0.22, 0.34, 0.52)
	_vp.add_child(_cam)
	_cam.look_at(Vector3.ZERO, Vector3.UP)


func _make_dot(color: Color, radius: float) -> MeshInstance3D:
	var dot := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = radius
	ball.height = radius * 2.0
	dot.mesh = ball
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.no_depth_test = true
	dot.material_override = mat
	dot.visible = false
	_vp.add_child(dot)
	return dot


## Pages nobody could mistake for their own mirror image: a dark header bar
## along the TOP, a solid block in the bottom-LEFT corner, and a row of dots
## counting the page number from the left.
## Page i's colour under --solid.
static func solid_page_color(i: int) -> Color:
	return Color.from_hsv(fmod(float(i) * 0.618034, 1.0), 0.9, 0.95 if i % 2 == 0 else 0.6)


func _write_cbz(path: String) -> void:
	var zip := ZIPPacker.new()
	zip.open(path)
	for i in _pages:
		var img := Image.create(200, 280, false, Image.FORMAT_RGB8)
		if _solid:
			img.fill(solid_page_color(i))
			zip.start_file("page_%02d.png" % i)
			zip.write_file(img.save_png_to_buffer())
			zip.close_file()
			continue
		var paper := Color(0.96, 0.94, 0.88) if i > 0 and i < _pages - 1 else Color.from_hsv(0.58, 0.55, 0.55)
		img.fill(paper)
		var ink := Color.from_hsv(fmod(float(i) * 0.13, 1.0), 0.75, 0.55)
		img.fill_rect(Rect2i(12, 12, 176, 26), ink)
		img.fill_rect(Rect2i(12, 214, 54, 54), ink.darkened(0.3))
		for line in 9:
			img.fill_rect(Rect2i(12, 60 + line * 15, 176 - (line % 3) * 30, 5), Color(0.3, 0.3, 0.32))
		for dot in (i % 10) + 1:
			img.fill_rect(Rect2i(78 + dot * 11, 250, 7, 7), Color(0.1, 0.1, 0.1))
		zip.start_file("page_%02d.png" % i)
		zip.write_file(img.save_png_to_buffer())
		zip.close_file()
	zip.close()
