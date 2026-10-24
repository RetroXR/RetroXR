## Game Boy Printer self-tests — everything about the printer that needs no core.
##
##     "$godot" --headless --path RetroXR res://Tests/gb_printer_tests.tscn
##
## Exits 0 when everything passes, 1 otherwise.
##
## The printing itself is the core's, and is proved where the core is: its own
## Godot-free test (RetroXR/gbprinter-libretro, `ctest`), and the probes that run
## it against real Game Boy cores (Tools/link/gb_printer_probe, the Camera's
## gb_camera_print_probe, Tools/netplay/gb_printer_netplay_probe). What is here is
## the room's half: that the printer is offered where it should be and nowhere
## else, that it is shaped to take the Game Boy's lead, that the paper on it is as
## long as the paper the core fed, that a print is written as the paper it is, and
## that netplay and the core list know what the printer is.
extends Node

const PRINTER_SCENE := "res://Scenes/Objects/peripherals/gb_printer.tscn"
## xenu.gbprinter's two collision boxes in the printer's (Y, Z): the body to the
## deck, and the paper cover's hump standing on it.
const SHELL_BODY := Rect2(Vector2(-0.02801, -0.0686), Vector2(0.045, 0.1372))
const SHELL_HUMP := Rect2(Vector2(0.01699, -0.0686), Vector2(0.01102, 0.0468))

var _pass := 0
var _fail := 0


func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("[gb-printer] TIMEOUT")
		get_tree().quit(1))
	_test_offered_on_the_game_boy_cards_only()
	_test_spawns_and_saves_by_its_token()
	await _test_scene_shape()
	await _test_paper_is_as_long_as_the_core_fed()
	_test_print_sheet()
	_test_print_file()
	_test_rolls_are_nintendos()
	_test_a_print_keeps_its_roll()
	await _test_roll_from_the_menu_and_the_save()
	_test_menu_offers_choices()
	_test_paper_curls_back()
	_test_paper_gives_way_to_its_weight()
	_test_paper_lies_on_what_is_under_it()
	_test_paper_grows_and_tears()
	_test_paper_flops()
	_test_paper_meets_the_room()
	await _test_printer_finds_the_room()
	await _test_printouts_are_paper()
	_test_fingers_push_the_paper()
	await _test_gear_knocks_with_the_core()
	await _test_a_torn_print_keeps_its_bend()
	await _test_paper_is_outlined_round_not_over()
	_test_paper_moves_smoothly()
	await _test_netplay_surface()
	_test_netplay_row()
	_test_core_source_and_info()
	_test_bios_extras_row()
	_test_bios_extras_row_offers_updates()
	_test_poster_pictures_travel()
	print("[gb-printer] ---- %d passed, %d failed ----" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _ok(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("[gb-printer] FAIL  %s" % name)


func _eq(got: Variant, want: Variant, name: String) -> void:
	_ok(got == want, "%s (got %s, want %s)" % [name, str(got), str(want)])


## Within one step of an 8-bit channel: a print is an 8-bit image.
func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.006 and absf(a.g - b.g) < 0.006 and absf(a.b - b.b) < 0.006


func _offers(systemid: String) -> bool:
	for item: Dictionary in SpawnCatalog.items_for(systemid):
		if str(item.get("spawn", "")) == GbPrinter.SPAWN_ID:
			return true
	return false


func _test_offered_on_the_game_boy_cards_only() -> void:
	_ok(_offers("gb"), "the Game Boy card offers the printer")
	_ok(_offers("gbc"), "the Game Boy Color card offers the printer")
	# The GBA's link socket takes a different lead, and the printer is not one of
	# the things a Game Boy Advance game prints to over it.
	for sid: String in ["gba", "nes", "psx", "gamegear", "dreamcast"]:
		_ok(not _offers(sid), "%s does not offer the printer" % sid)


func _test_spawns_and_saves_by_its_token() -> void:
	_ok(ScenePersistence.PLAIN_SCENES.has(GbPrinter.SPAWN_ID),
		"the printer restores from a save by its token")
	var obj := ScenePersistence.instantiate(GbPrinter.SPAWN_ID)
	_ok(obj is GbPrinter, "and the spawn menu's fallback builds a GbPrinter from it")
	if obj != null:
		obj.free()


func _test_scene_shape() -> void:
	var printer := (load(PRINTER_SCENE) as PackedScene).instantiate() as GbPrinter
	add_child(printer)
	await get_tree().process_frame
	var ports := printer.find_children("*", "LinkPort", true, false)
	_eq(ports.size(), 1, "the printer wears one link socket, EXT.IN")
	if ports.size() == 1:
		var port := ports[0] as LinkPort
		# The SMALL socket, the Pocket's: a Pocket-era accessory. An original Game
		# Boy reaches it through the DMG-14 adapter, as the Universal Game Link
		# Cable it came with did; a DMG-04 does not go in.
		_eq(port.connector, "link_plug", "and it takes the small Game Boy lead")
		_ok(port.get_machine() == printer, "whose machine is the printer")
		# On the back, facing out of it: a plug arrives along the socket's +Z.
		var out := port.global_transform.basis.z.normalized()
		_ok(out.dot(-printer.global_transform.basis.z) > 0.99,
			"the socket faces out of the printer's back (%s)" % out)
		_ok(printer.to_local(port.global_position).z < -0.06, "and sits on the back face")
	_ok(printer.get_node("PowerSwitch") is VRButton, "POWER is a button")
	_ok(printer.get_node("FeedButton") is VRButton, "FEED is a button")
	var paper := printer.get_node("PaperPivot/Paper") as VRButton
	_ok(paper != null, "the paper can be pressed")
	if paper != null:
		_ok(paper.require_trigger, "and tearing it needs the trigger, not a brush of the hand")
	_ok(not printer.is_powered_on, "the printer starts switched off")
	_ok(printer.get_libretro_node() == null, "and has grown no core yet")
	_ok(printer.is_in_group("spawned"), "it is saved with the room")
	printer.free()


func _test_paper_is_as_long_as_the_core_fed() -> void:
	var printer := (load(PRINTER_SCENE) as PackedScene).instantiate() as GbPrinter
	add_child(printer)
	await get_tree().process_frame
	var paper := printer.get_node("PaperPivot/Paper") as Node3D
	var mesh := (printer.get_node("PaperPivot/Paper/ButtonMesh") as MeshInstance3D).mesh
	_ok(is_equal_approx(printer.paper_length(), GbPrinter.STUB_LENGTH), "switched off, only the end of the roll shows")

	var img := Image.create(GbPrinterPaper.DOTS, 208, false, Image.FORMAT_RGB8)
	img.fill(Color.WHITE)
	var tex := ImageTexture.create_from_image(img)
	printer._lay_paper(tex, 208)
	_ok(is_equal_approx(printer.paper_length(), 208 * GbPrinter.DOT_PITCH),
		"208 lines fed is 208 lines of paper (%.4f m)" % printer.paper_length())
	_ok(mesh != null and mesh.get_surface_count() == 1, "drawn as one bent sheet")
	if mesh != null and mesh.get_surface_count() == 1:
		var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
		_ok(is_equal_approx(verts[0].distance_to(verts[1]), GbPrinter.PAPER_WIDTH), "38 mm wide")
		# The first row is the slot's (the newest line, v = 1), at the pivot.
		var at_slot := paper.position + (verts[0] + verts[1]) * 0.5
		_ok(at_slot.length() < 1e-5 and is_equal_approx(uvs[0].y, 1.0),
			"coming out of the slot, its newest line at the head (%s)" % at_slot)
		var run := 0.0
		for i in range(2, verts.size(), 2):
			run += verts[i].distance_to(verts[i - 2])
		_ok(absf(run - printer.paper_length()) < 1e-5, "and as long along its bend as the paper is")
	var pivot := printer.get_node("PaperPivot") as Node3D
	_ok(pivot.rotation.x < 0.0, "the slot sends it back toward the roll cover, not over the front")
	printer._lay_paper(null, 0)
	_ok(is_equal_approx(printer.paper_length(), GbPrinter.STUB_LENGTH), "torn off, the roll's end again")
	printer.free()


func _test_rolls_are_nintendos() -> void:
	var ids: Array = GbPrinterPaper.ROLLS.map(func(r: Dictionary) -> String: return r["id"])
	_eq(ids, ["white", "yellow", "blue"], "the three rolls Nintendo sold, white first as the printer always had")
	var white := GbPrinterPaper.roll("white")
	_ok(_near(white["paper"], GbPrinterPaper.PAPER), "white is the paper the printer always drew")
	var sepia: Color = white["ink"]
	_ok(sepia.r > sepia.g and sepia.g > sepia.b and sepia.r < 0.6, "and prints sepia (%s)" % sepia)
	for id: String in ["yellow", "blue"]:
		var ink: Color = GbPrinterPaper.roll(id)["ink"]
		_ok(ink.get_luminance() < 0.1, "%s prints black" % id)
	var yellow: Color = GbPrinterPaper.roll("yellow")["paper"]
	var blue: Color = GbPrinterPaper.roll("blue")["paper"]
	_ok(yellow.b < yellow.r and yellow.b < yellow.g, "yellow paper is yellow (%s)" % yellow)
	_ok(blue.b > blue.r, "blue paper is blue (%s)" % blue)
	_eq(GbPrinterPaper.roll("pink")["id"], "white", "a roll this does not know is the first")


func _test_a_print_keeps_its_roll() -> void:
	var r := GbPrinterPaper.roll("yellow")
	var dots := Image.create(GbPrinterPaper.DOTS, 2, false, Image.FORMAT_L8)
	dots.fill(Color.WHITE)
	dots.set_pixel(0, 0, Color.BLACK)
	var left := (GbPrinterPaper.sheet_width() - GbPrinterPaper.DOTS) / 2
	var sheet := GbPrinterPaper.sheet(dots, r["paper"], r["ink"])
	_ok(_near(sheet.get_pixel(0, 0), r["paper"]), "a yellow roll's print is yellow paper")
	_ok(_near(sheet.get_pixel(left, 0), r["ink"]), "with its ink where the dots burned")
	var sepia := GbPrinterPaper.roll("white")
	var half := Image.create(GbPrinterPaper.DOTS, 1, false, Image.FORMAT_L8)
	half.fill(Color(0.5, 0.5, 0.5))
	var g := GbPrinterPaper.sheet(half, sepia["paper"], sepia["ink"]).get_pixel(left, 0)
	_ok(_near(g, (sepia["ink"] as Color).lerp(sepia["paper"], half.get_pixel(0, 0).r)),
		"a gray dot is the paper half way to the ink")
	# Written, the colors are in the file: nothing the printer does later reaches them.
	var dir := ProjectSettings.globalize_path("user://gb_printer_test_rolls")
	var path := GbPrinterPaper.save_print(dots, dir, r["paper"], r["ink"])
	var back := Image.load_from_file(path) if not path.is_empty() else null
	_ok(back != null and _near(back.get_pixel(0, 0), r["paper"])
		and _near(back.get_pixel(left, 0), r["ink"]), "and the file torn off keeps them")
	for f: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func _test_roll_from_the_menu_and_the_save() -> void:
	var printer := (load(PRINTER_SCENE) as PackedScene).instantiate() as GbPrinter
	add_child(printer)
	await get_tree().process_frame
	_eq(printer.paper_roll, "white", "a new printer has the white roll")
	_eq(printer.display_name, "Game Boy Printer", "its menu is titled for it, not its node")
	var choices: Array = printer.options_choices()
	_eq(choices.size(), 1, "its menu offers one choice")
	if choices.size() == 1:
		_eq(choices[0]["items"], ["White", "Yellow", "Blue"], "the roll, of Nintendo's three")
		_eq(choices[0]["selected"], 0, "with the loaded one down")
	printer.options_choose(0, 2)
	_eq(printer.paper_roll, "blue", "choosing one loads it")
	_eq(printer.options_choices()[0]["selected"], 2, "and the menu says so")
	var mat := (printer.get_node("PaperPivot/Paper/ButtonMesh") as MeshInstance3D).material_override as ShaderMaterial
	var blue: Color = GbPrinterPaper.roll("blue")["paper"]
	_ok(mat != null and (mat.get_shader_parameter("paper_color") as Vector3).is_equal_approx(
		Vector3(blue.r, blue.g, blue.b)), "the strip on the printer is the new roll at once")
	printer.options_choose(0, 9)
	_eq(printer.paper_roll, "blue", "a choice that is not there changes nothing")

	var store := ScenePersistence.new()
	var entry := store._serialize_node(printer, 1, {printer: 1})
	_eq(entry.get("paper"), "blue", "a save says which roll is in it")
	var back := store._deserialize_object(entry) as GbPrinter
	_ok(back != null and back.paper_roll == "blue", "and a load puts it back")
	entry.erase("paper")
	var old := store._deserialize_object(entry) as GbPrinter
	_ok(old != null and old.paper_roll == "white", "a save from before rolls loads the white one")
	for n: Node in [back, old, printer]:
		if n != null:
			n.free()


func _test_menu_offers_choices() -> void:
	var ui := ObjectOptions2D.new()
	add_child(ui)
	var got: Array = []
	ui.choice_made.connect(func(row: int, item: int) -> void: got.append([row, item]))
	ui.set_choices([{"caption": "Paper roll", "items": ["A", "B", "C"], "selected": 1, "note": "n"}])
	var buttons := ui.find_children("*", "Button", true, false).filter(
		func(b: Node) -> bool: return (b as Button).toggle_mode)
	_eq(buttons.size(), 3, "a choice is a row of buttons, one an item")
	if buttons.size() == 3:
		_ok((buttons[1] as Button).button_pressed and not (buttons[0] as Button).button_pressed,
			"the selected one down")
		(buttons[2] as Button).pressed.emit()
		_eq(got, [[0, 2]], "and a press says which row and item")
	ui.free()


## A strip settled for `seconds` under ordinary gravity, straight up out of a slot
## at the origin.
func _settled(length: float, seconds: float, gravity := Vector2(-9.8, 0.0),
		boxes: Array[Rect2] = [], planes: Array = []) -> GbPrinterStrip:
	var s := GbPrinterStrip.new()
	s.place(Vector2.ZERO, 0.0)
	s.boxes = boxes
	s.planes = planes
	s.set_length(length)
	for i in int(seconds * 60.0):
		s.step(1.0 / 60.0, gravity)
	return s


func _test_paper_curls_back() -> void:
	# Weightless, the paper takes the roll's curl: an arc of CURL_RADIUS, bending
	# toward -Z (the roll cover's side).
	var s := _settled(0.08, 3.0, Vector2.ZERO)
	var tip := s.points[s.points.size() - 1]
	var turn := 0.08 / GbPrinterStrip.CURL_RADIUS
	var want := Vector2(sin(turn), -(1.0 - cos(turn))) * GbPrinterStrip.CURL_RADIUS
	_ok(tip.distance_to(want) < 0.004, "weightless, the paper curls as the roll left it (%s, %s)" % [tip, want])
	# A short piece stands up out of the slot, curling back.
	s = _settled(0.03, 3.0)
	tip = s.points[s.points.size() - 1]
	_ok(tip.x > 0.02 and tip.y < -0.003, "a short piece stands, curling back (%s)" % tip)
	_ok(s.motion() < 0.01, "and comes to rest (%.4f)" % s.motion())


func _test_paper_gives_way_to_its_weight() -> void:
	var s := _settled(0.25, 5.0)
	var tip := s.points[s.points.size() - 1]
	_ok(tip.x < -0.05, "a long strip flops over and hangs (%s)" % tip)
	_ok(s.motion() < 0.05, "and settles (%.4f)" % s.motion())
	var weightless := _settled(0.25, 5.0, Vector2.ZERO)
	_ok(weightless.points[weightless.points.size() - 1].x > tip.x + 0.05,
		"lower than the same paper weightless")
	# Tipped forward (gravity toward the printer's +Z), the paper falls the other way.
	var forward := _settled(0.25, 5.0, Vector2(-6.9, 6.9))
	var fwd_tip := forward.points[forward.points.size() - 1]
	_ok(fwd_tip.y > tip.y + 0.05, "the printer tipped forward, it falls forward (%s against %s)" % [fwd_tip, tip])
	# A shake moves it, and no faster than paper moves through air.
	var hung := s.points[s.points.size() - 1]
	var fastest := 0.0
	var last := hung
	for i in 12:
		s.step(1.0 / 60.0, Vector2(-9.8, 30.0))
		var now := s.points[s.points.size() - 1]
		fastest = maxf(fastest, now.distance_to(last) * 60.0)
		last = now
	_ok(last.distance_to(hung) > 0.02, "shaken, it swings (%.3f m)" % last.distance_to(hung))
	_ok(fastest <= GbPrinterStrip.TERMINAL_SPEED + 0.01,
		"never faster than paper through air (%.2f m/s)" % fastest)


func _test_paper_lies_on_what_is_under_it() -> void:
	# The roll cover behind the slot, its top 1 cm above it.
	var cover := Rect2(Vector2(-0.1, -0.2), Vector2(0.11, 0.195))
	var s := _settled(0.25, 8.0, Vector2(-9.8, 0.0), [cover])
	var inside := 0
	var on_top := false
	for i in range(1, s.points.size()):
		var p := s.points[i]
		if cover.grow(-0.0005).has_point(p):
			inside += 1
		if absf(p.x - cover.end.x) < 0.003 and p.y < cover.end.y and p.y > cover.position.y:
			on_top = true
	_eq(inside, 0, "the paper does not go into the cover")
	_ok(on_top, "it lies on top of it")
	# A table 5 cm under the slot.
	s = _settled(0.4, 5.0, Vector2(-9.8, 0.0), [], [[Vector2(1.0, 0.0), -0.05]])
	var lowest := 0.0
	for p in s.points:
		lowest = minf(lowest, p.x)
	_ok(lowest > -0.0515, "nor through the table under it (%.4f)" % lowest)
	# The shell's own boxes and slot (xenu.gbprinter), on a table half a millimeter
	# under its feet: the paper drapes down the back onto the table, never into
	# the printer or under it through that gap, and comes to rest.
	s = _on_the_shell(0.25)
	for i in 900:
		s.step(1.0 / 60.0, Vector2(-9.8, 0.0))
	_eq(_in_the_printer(s), 0, "paper on the table stays out of and from under the printer")
	var on_table := false
	for p in s.points:
		on_table = on_table or p.x < -0.026
	_ok(on_table, "it reaches the table")
	_ok(s.motion() < 0.01, "and comes to rest (%.4f)" % s.motion())


## A strip out of the shell's slot (xenu.gbprinter), with its two boxes, on a
## table half a millimeter under its feet.
func _on_the_shell(length: float) -> GbPrinterStrip:
	var s := GbPrinterStrip.new()
	s.place(Vector2(0.01739, -0.0123), 0.1396)
	s.boxes = [SHELL_BODY, SHELL_HUMP]
	s.planes = [[Vector2(1.0, 0.0), -0.0285]]
	s.set_length(length)
	return s


## How many of the strip's points (past the slot's own) are in the shell's boxes
## or under them, by more than `slack` meters: where the paper turns sharply
## from the printer's back onto the table a point can sit a millimeter or two in,
## out of sight under the paper, where the bugs this guards against put it
## centimeters in.
func _in_the_printer(s: GbPrinterStrip, slack := 0.002) -> int:
	var n := 0
	for i in range(3, s.points.size()):
		var p := s.points[i]
		for box: Rect2 in [SHELL_BODY, SHELL_HUMP]:
			var r := box.grow(-slack)
			if p.y > r.position.y and p.y < r.end.y and p.x < r.end.x:
				n += 1
				break
	return n


func _test_paper_moves_smoothly() -> void:
	# The printer lifted 2 cm off the table and set down again, a long strip
	# draped down its back onto it. Each frame, how far any point's motion changed
	# (its second difference): the paper was thrown 13 cm in a frame here, flipping
	# between lying on the table and curled up the printer's back.
	var s := _on_the_shell(0.22)
	for i in 600:
		s.step(1.0 / 60.0, Vector2(-9.8, 0.0))
	var hist: Array = []
	var worst := 0.0
	var inside := 0
	for f in 240:
		var t := f / 60.0
		var off := -0.02 * (smoothstep(0.0, 1.0, t) - smoothstep(2.0, 3.0, t))
		s.planes = [[Vector2(1.0, 0.0), -0.0285 + off]]
		s.step(1.0 / 60.0, Vector2(-9.8, 0.0))
		# Set down onto the paper, the base's edge pinches it 3.6 mm in for a moment.
		inside = maxi(inside, _in_the_printer(s, 0.005))
		hist.append(s.points.duplicate())
		if hist.size() >= 3:
			var a: PackedVector2Array = hist[-3]
			var b: PackedVector2Array = hist[-2]
			var c: PackedVector2Array = hist[-1]
			for i in c.size():
				worst = maxf(worst, (c[i] - 2.0 * b[i] + a[i]).length())
	_ok(worst < 0.02, "lifted and set down, the paper never jumps (%.1f mm)" % (worst * 1000.0))
	_eq(inside, 0, "nor ends up in or under the printer")


func _test_paper_meets_the_room() -> void:
	# A table under the printer that ends 10 cm behind it, as patches the room's
	# rays would find: a long print hangs over the edge and down past it. On one
	# whole surface, as the paper had before, it could not.
	# Every ROOM_SAMPLE down the table to its last point before the edge, each
	# patch reaching PATCH_REACH: as the printer's rays would find it.
	var table: Array = []
	var z := 0.08
	while z > -0.10:
		table.append([Vector2(1.0, 0.0), -0.0285, Vector2(-0.0285, z), GbPrinter.PATCH_REACH])
		z -= GbPrinter.ROOM_SAMPLE
	var s := _on_the_shell(0.30)
	s.planes = []
	s.patches = table
	for i in 900:
		s.step(1.0 / 60.0, Vector2(-9.8, 0.0))
	var lowest := 0.0
	var past_edge := 0.0
	for p in s.points:
		lowest = minf(lowest, p.x)
		past_edge = minf(past_edge, p.y)
	_ok(past_edge < -0.10 and lowest < -0.06,
		"a long print hangs over the table's edge (lowest %.3f, back to %.3f)" % [lowest, past_edge])
	var whole := _on_the_shell(0.30)
	for i in 900:
		whole.step(1.0 / 60.0, Vector2(-9.8, 0.0))
	var whole_lowest := 0.0
	for p in whole.points:
		whole_lowest = minf(whole_lowest, p.x)
	_ok(whole_lowest > -0.031, "on one whole surface it could not (%.3f)" % whole_lowest)
	# A wall 12 cm behind the printer, facing it: the print stops against it.
	var walled := _on_the_shell(0.30)
	walled.planes = []
	walled.patches = table + [[Vector2(0.0, 1.0), -0.12, Vector2(0.0, -0.12), 0.08]]
	for i in 900:
		walled.step(1.0 / 60.0, Vector2(-9.8, 0.0))
	var through := 0
	for p in walled.points:
		if p.y < -0.123 and p.x > -0.08 and p.x < 0.08:
			through += 1
	_eq(through, 0, "nor goes through a wall behind the printer")


func _test_printer_finds_the_room() -> void:
	# A real table under a real printer: its rays find it under its feet.
	var table := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 0.02, 1.0)
	shape.shape = box
	table.add_child(shape)
	table.position = Vector3(0.0, -0.01, 0.0)
	add_child(table)
	var printer := (load(PRINTER_SCENE) as PackedScene).instantiate() as GbPrinter
	add_child(printer)
	printer.freeze = true
	printer.global_position = Vector3(0.0, 0.0285, 0.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	printer._find_obstacles()
	printer._place_room(printer.global_transform)
	var up := 0
	for piece: Array in printer._strip.patches:
		if (piece[0] as Vector2).is_equal_approx(Vector2(1.0, 0.0)):
			up += 1
	_ok(up >= 3, "a printer finds the table under its back, slot and front (%d)" % up)
	printer.free()
	table.free()


func _test_printouts_are_paper() -> void:
	var poster := (load("res://Scenes/Objects/media/poster.tscn") as PackedScene).instantiate() as Poster
	_ok(not GbPrintoutFlop.is_printout(poster), "a poster is not a print")
	poster.image_path = DataPaths.media_root(GbPrinter.PRINTS_DIR).path_join("print_x.png")
	_ok(GbPrintoutFlop.is_printout(poster), "a picture in the prints folder is (a print saved before the mark)")
	poster.image_path = ""
	poster.printout = true
	_ok(GbPrintoutFlop.is_printout(poster), "and so is one marked a print")
	var store := ScenePersistence.new()
	var entry := store._serialize_node(poster, 1, {poster: 1})
	_eq(entry.get("printout"), true, "a save says it is a print")
	var back := store._deserialize_object(entry) as Poster
	_ok(back != null and back.printout, "and a load keeps it one")
	poster.printout = false
	_ok(not store._serialize_node(poster, 1, {poster: 1}).has("printout"),
		"an ordinary poster saves as it always did")
	for n: Node in [poster, back]:
		if n != null:
			n.free()

	# Loose in the room, a print is drawn bent: the flat sheet hidden, the paper
	# its own length along its bend. An ordinary poster stays the flat sheet.
	var print_poster := (load("res://Scenes/Objects/media/poster.tscn") as PackedScene).instantiate() as Poster
	print_poster.printout = true
	print_poster.size_scale = 0.12 / Poster.BASE_LONG_EDGE
	add_child(print_poster)
	print_poster.freeze = true
	print_poster.global_position = Vector3(0, 2, 0)
	var plain := (load("res://Scenes/Objects/media/poster.tscn") as PackedScene).instantiate() as Poster
	add_child(plain)
	for i in 10:
		await get_tree().process_frame
	var flop := print_poster.get_node_or_null("Surface/FlopMesh") as MeshInstance3D
	_ok(flop != null and flop.visible, "a loose print is drawn bent")
	_ok(not (print_poster.get_node("Surface/FlatMesh") as MeshInstance3D).visible, "with the flat sheet hidden")
	if flop != null and flop.mesh != null and flop.mesh.get_surface_count() == 1:
		var verts: PackedVector3Array = flop.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var run := 0.0
		for i in range(2, verts.size(), 2):
			run += verts[i].distance_to(verts[i - 2])
		var want := print_poster.get_sheet_size().y
		_ok(absf(run - want) < 0.002, "as long along its bend as the paper (%.4f, %.4f)" % [run, want])
	_ok(not plain.has_node("PrintoutFlop"), "an ordinary poster is not given one")
	print_poster.free()
	plain.free()


func _test_fingers_push_the_paper() -> void:
	# A fingertip where the paper stands: the paper bends round it, none of it in.
	var s := _settled(0.10, 3.0)
	var mid := s.points[s.points.size() / 2]
	var finger := mid + Vector2(0.0, 0.004)
	s.fingers = [[finger, 0.009]]
	for i in 60:
		s.step(1.0 / 60.0, Vector2(-9.8, 0.0))
	var inside := 0
	for i in range(3, s.points.size()):
		if s.points[i].distance_to(finger) < 0.0085:
			inside += 1
	_eq(inside, 0, "a fingertip in the paper's way pushes it aside")
	s.fingers = []
	for i in 300:
		s.step(1.0 / 60.0, Vector2(-9.8, 0.0))
	_ok(s.points[s.points.size() / 2].distance_to(mid) < 0.003, "and taken away, the paper goes back")


func _test_gear_knocks_with_the_core() -> void:
	# The room counts the core's turns: from the motor's start at the knock,
	# TURN_S and its offsets, jolting the paper as each knocks.
	var printer := (load(PRINTER_SCENE) as PackedScene).instantiate() as GbPrinter
	add_child(printer)
	await get_tree().process_frame
	printer.set_process(false)
	var dt := 1.0 / 240.0
	var knocks: Array[float] = []
	var t := 0.0
	while t < 2.5:
		printer.motor_ran()
		var swing_before := printer._strip.sway_speed
		if printer.turn_gear(dt):
			knocks.append(t + dt)
			if knocks.size() == 1:
				_ok(printer._strip.sway_speed > swing_before, "a knock jolts the paper")
		t += dt
	_eq(knocks.size(), 2, "two knocks in two and a half seconds")
	if knocks.size() == 2:
		var first := GbPrinter.TURN_S + GbPrinter.TURN_OFFSET_S[0]
		var second := first + GbPrinter.TURN_S + GbPrinter.TURN_OFFSET_S[1]
		_ok(absf(knocks[0] - first) < 2.0 * dt and absf(knocks[1] - second) < 2.0 * dt,
			"at the turns the core makes (%.4f, %.4f against %.4f, %.4f)" % [knocks[0], knocks[1], first, second])
	var after := 0
	for i in 2000:
		if printer.turn_gear(dt):
			after += 1
	_eq(after, 0, "and none once the motor has stopped")
	printer.free()


func _test_a_torn_print_keeps_its_bend() -> void:
	var s := GbPrinterStrip.new()
	s.set_length(0.1)
	s.bend_to(12.0)
	_ok(absf(s.mean_curvature() - 12.0) < 0.01, "a strip takes a bend and says what it is (%.2f)" % s.mean_curvature())
	var poster := (load("res://Scenes/Objects/media/poster.tscn") as PackedScene).instantiate() as Poster
	poster.printout = true
	poster.size_scale = 0.12 / Poster.BASE_LONG_EDGE
	# Bent the other way from the roll's own curl, which a strip has unasked.
	poster.set_meta(GbPrintoutFlop.BEND_META, -10.0)
	add_child(poster)
	poster.freeze = true
	poster.global_position = Vector3(0, 2, 0)
	# One frame: the bend it came with is where it starts. (It relaxes to its own
	# shape within a few frames, no faster than paper moves through air.)
	await get_tree().process_frame
	var flop := poster.get_node_or_null(GbPrintoutFlop.NODE_NAME) as GbPrintoutFlop
	_ok(flop != null and not poster.has_meta(GbPrintoutFlop.BEND_META), "a torn print takes the bend it came with")
	if flop != null:
		_ok(flop._up.mean_curvature() < 0.0 and flop._down.mean_curvature() < 0.0,
			"and starts bent (%.1f, %.1f)" % [flop._up.mean_curvature(), flop._down.mean_curvature()])
	poster.free()


func _test_paper_is_outlined_round_not_over() -> void:
	# The rim goes round the paper: every point of it at or past the paper's edge,
	# and past both its ends; none over the paper.
	var centers := PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 0.05, 0), Vector3(0, 0.1, -0.01)])
	var along := PackedVector3Array([Vector3.UP, Vector3.UP, Vector3(0, 0.98, -0.2).normalized()])
	var mesh := GbPaperRim.build(centers, along, Vector3.RIGHT, 0.019, 0.0015, PackedFloat32Array([1.0, 0.5, 0.0]))
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var over := 0
	var lowest := INF
	var highest := -INF
	for v in verts:
		if absf(v.x) < 0.019 - 1e-6:
			over += 1
		lowest = minf(lowest, v.y)
		highest = maxf(highest, v.y)
	_eq(over, 0, "the rim is round the paper, none of it over it")
	_ok(lowest < -0.001 and highest > 0.1, "and past both its ends")

	# The printer's strip: the tear trigger's own (inflated) outline off, the rim
	# shown only while it is aimed at.
	var printer := (load(PRINTER_SCENE) as PackedScene).instantiate() as GbPrinter
	add_child(printer)
	await get_tree().process_frame
	var paper := printer.get_node("PaperPivot/Paper") as VRButton
	_ok(not paper.builtin_outline, "the paper's trigger draws no outline of its own")
	var rim := printer.get_node_or_null("PaperPivot/Paper/PaperRim") as MeshInstance3D
	_ok(rim != null and rim.mesh != null and rim.mesh.get_surface_count() == 1, "the paper has a rim")
	_eq(paper.outline_color().a, 0.0, "nothing aimed at it, no outline color")
	printer._show_paper_rim()
	_ok(rim != null and not rim.visible, "and no rim showing")
	printer.free()

	# A print bending as paper: its own rim, the Poster's flat one hidden.
	var poster := (load("res://Scenes/Objects/media/poster.tscn") as PackedScene).instantiate() as Poster
	poster.printout = true
	poster.size_scale = 0.12 / Poster.BASE_LONG_EDGE
	add_child(poster)
	poster.freeze = true
	poster.global_position = Vector3(0, 2, 0)
	for i in 3:
		await get_tree().process_frame
	var flop := poster.get_node_or_null(GbPrintoutFlop.NODE_NAME) as GbPrintoutFlop
	_ok(flop != null and poster.outline_drawn_by == flop, "a loose print draws its own rim")
	poster._highlight_requested = true
	poster._refresh_outline()
	var flat_rim := poster.get_node_or_null("Surface/HoverOutline") as MeshInstance3D
	var bent_rim := poster.get_node_or_null("Surface/FlopRim") as MeshInstance3D
	_ok(flat_rim != null and not flat_rim.visible, "aimed at, the flat rim behind it stays hidden")
	_ok(bent_rim != null and bent_rim.visible, "and the rim round the bent paper shows")
	poster.free()


func _test_paper_flops() -> void:
	# Pushed and let go, as BookFlop's pages are: the printer carried forward for a
	# quarter second and stopped, the paper lags, swings back past where it rests,
	# and settles. The bend alone never swung back past its rest.
	var s := _settled(0.10, 3.0)
	var rest := s.points[s.points.size() - 1]
	for i in 15:
		s.step(1.0 / 60.0, Vector2(-9.8, -6.0), 0.0, Vector2(0.0, -6.0))
	var pushed := s.points[s.points.size() - 1]
	_ok(pushed.y < rest.y - 0.005, "carried forward, the paper lags behind (%.1f mm)" % ((rest.y - pushed.y) * 1000.0))
	var past := 0.0
	for i in 240:
		s.step(1.0 / 60.0, Vector2(-9.8, 0.0))
		past = maxf(past, s.points[s.points.size() - 1].y - rest.y)
	_ok(past > 0.003, "stopped, it swings back past its rest (%.1f mm)" % (past * 1000.0))
	_ok(s.motion() < 0.01, "and settles (%.4f)" % s.motion())
	_ok(s.points[s.points.size() - 1].distance_to(rest) < 0.002, "where it was")


func _test_paper_grows_and_tears() -> void:
	var s := _settled(0.05, 2.0)
	var before := s.points[s.points.size() - 1]
	s.set_length(0.05 + GbPrinter.DOT_PITCH)
	var shape_kept := s.points[s.points.size() - 1].distance_to(before) < 0.002
	_ok(shape_kept, "a line fed pushes the paper out without throwing its shape")
	s.set_length(GbPrinter.STUB_LENGTH)
	_ok(s.motion() == 0.0 and s.angles[0] == 0.0, "torn, a fresh end of roll at rest")


func _test_print_sheet() -> void:
	# The 160 dots centred on paper as wide as the real paper, ink multiplying it.
	var dots := Image.create(GbPrinterPaper.DOTS, 4, false, Image.FORMAT_L8)
	dots.fill(Color.WHITE)
	dots.set_pixel(0, 0, Color.BLACK)
	dots.set_pixel(159, 3, Color(0.333, 0.333, 0.333))
	var sheet := GbPrinterPaper.sheet(dots)
	var w := GbPrinterPaper.sheet_width()
	_eq(sheet.get_width(), w, "a print is the paper's width in dots")
	_eq(w, int(round(0.038 / 0.0001375)), "38 mm at the head's pitch")
	_eq(sheet.get_height(), 4, "and as long as the paper")
	var left := (w - GbPrinterPaper.DOTS) / 2
	_ok(_near(sheet.get_pixel(left - 1, 0), GbPrinterPaper.PAPER), "bare paper beside the dots")
	_ok(sheet.get_pixel(left, 0).r < 0.01, "the first dot of the first line is burned")
	_ok(_near(sheet.get_pixel(left + 1, 0), GbPrinterPaper.PAPER), "its neighbour is not")
	# Asymmetric: the dark-grey dot is the LAST of the LAST line, so a mirrored or
	# flipped print shows.
	var g := sheet.get_pixel(left + 159, 3)
	_ok(absf(g.r - GbPrinterPaper.PAPER.r * 0.333) < 0.01, "and the last of the last is grey ink on paper")
	_ok(_near(sheet.get_pixel(left, 3), GbPrinterPaper.PAPER), "with nothing at its mirror")


func _test_print_file() -> void:
	var dir := ProjectSettings.globalize_path("user://gb_printer_test_prints")
	var dots := Image.create(GbPrinterPaper.DOTS, 16, false, Image.FORMAT_L8)
	dots.fill(Color.WHITE)
	var a := GbPrinterPaper.save_print(dots, dir)
	var b := GbPrinterPaper.save_print(dots, dir)
	_ok(not a.is_empty() and FileAccess.file_exists(a), "a print is written")
	_ok(not b.is_empty() and b != a, "and a second in the same second does not overwrite it")
	var back := Image.load_from_file(a)
	_ok(back != null and back.get_width() == GbPrinterPaper.sheet_width(), "as the paper, margins included")
	_eq(GbPrinterPaper.save_print(Image.create(1, 1, false, Image.FORMAT_L8), dir), "",
		"no paper out is no print")
	for f: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func _test_netplay_surface() -> void:
	var printer := (load(PRINTER_SCENE) as PackedScene).instantiate() as GbPrinter
	add_child(printer)
	await get_tree().process_frame
	_eq(printer.net_boot_spec(GbPrinter.CORE), {"mode": "no_content"},
		"a session boots the printer with no content")
	_eq(printer.resolve_core_name(), GbPrinter.CORE, "on its own core")
	_eq(printer.net_rom_md5(), "", "with no ROM to match")
	_eq(printer.port_holders(), [printer], "it is its own pad, so its port follows the hand")
	_eq(printer.net_sram_file_bytes().size(), 0, "and has no battery to ship")
	var blocked := not printer.standalone_blocker().is_empty()
	_eq(blocked, CoreDownloadManager.installed_core_lib(GbPrinter.CORE).is_empty(),
		"it refuses to start exactly when its core is missing")
	_eq(printer.net_prepare_boot({}), not blocked, "and a session can boot it exactly when it can start")
	printer.free()


func _test_netplay_row() -> void:
	var row: Dictionary = NetplayCores.CORES.get(GbPrinter.CORE, {})
	_ok(not row.is_empty(), "netplay knows the printer core")
	_eq(row.get("strategies", []), [NetplayCores.Strategy.LOCKSTEP],
		"lockstep only: a Game Boy on a cable is lockstep")
	_ok(bool(row.get("crc_from_state", false)), "its CRC is its savestate's (no SYSTEM_RAM)")
	_ok(not bool(row.get("link_rollback", false)), "and it claims no group rollback it has not shown")


func _test_core_source_and_info() -> void:
	_ok(CoreSources.has(GbPrinter.CORE), "the printer core has a source to download from")
	if CoreSources.has(GbPrinter.CORE):
		_ok(CoreSources.asset_for(GbPrinter.CORE).begins_with("gbprinter_libretro"),
			"named as its releases name it")
	var db := CoreInfoDatabase.new()
	db.load_overlay(CoreInfoDatabase.OVERLAY_DIR)
	var info: Dictionary = db.get_by_core_name(GbPrinter.CORE)
	_ok(not info.is_empty(), "its core info is in the overlay")
	_eq(str(info.get("supports_no_game", "")), "true", "it starts with no game")
	# No platform of its own: no tile on the spawn menu, no roms folder.
	var sids := CoreInfoDatabase.systemids_of(info)
	_ok(sids.is_empty() or sids == ["unknown"], "and names no platform (%s)" % str(sids))


func _test_bios_extras_row_offers_updates() -> void:
	# The printer's row on BIOS / Extras says when a newer release is out, as the
	# Cores tab does; it only ever showed the re-download glyph.
	var view: GDScript = load("res://Scripts/UI/spawn_menu/views/cores_view.gd")
	var dm := CoreDownloadManager.new()
	dm.manifest = DownloadManifest.new()
	dm.manifest.set_downloaded(GbPrinter.CORE, "retroxr-gbprinter-libretro-v3")
	dm.available_cores = [{"core_name": GbPrinter.CORE, "remote_date": "retroxr-gbprinter-libretro-v4"}]
	_ok(bool(view.call("core_update_available", dm, GbPrinter.CORE)), "v3 installed with v4 out is an update")
	dm.manifest.set_downloaded(GbPrinter.CORE, "retroxr-gbprinter-libretro-v4")
	_ok(not bool(view.call("core_update_available", dm, GbPrinter.CORE)), "v4 installed is not")
	dm.available_cores = []
	dm.manifest.set_downloaded(GbPrinter.CORE, "retroxr-gbprinter-libretro-v1")
	_ok(bool(view.call("core_update_available", dm, GbPrinter.CORE)),
		"with no listing yet, this build's own tag says what is newer")
	_ok(not bool(view.call("core_update_available", null, GbPrinter.CORE)), "and with no manager, nothing is")
	dm.free()


func _test_bios_extras_row() -> void:
	var extras: Dictionary = load("res://Scripts/UI/spawn_menu/views/cores_view.gd").get_script_constant_map().get("_BIOS_EXTRA_CORES", {})
	for sid: String in ["gb", "gbc"]:
		var rows: Array = extras.get(sid, [])
		_ok(rows.any(func(r: Dictionary) -> bool: return r.get("core") == GbPrinter.CORE),
			"the %s page of BIOS / Extras offers the printer's core" % sid)


func _test_poster_pictures_travel() -> void:
	var sync: Object = load("res://Scripts/Net/netplay/object_sync.gd").new()
	var poster := (load("res://Scenes/Objects/media/poster.tscn") as PackedScene).instantiate()
	var desc: Dictionary = sync.call("_file_desc", poster)
	_eq(desc, {"kind": "poster", "prop": "image_path"},
		"a poster's picture (a printout's among them) is a file netplay ships")
	_ok(NetFileTransfer.TRANSFER_KINDS.has("poster"), "of a kind netplay transfers")
	poster.free()
	if sync is Node:
		(sync as Node).free()
