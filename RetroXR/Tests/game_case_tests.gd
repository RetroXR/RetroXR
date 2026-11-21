## Disc games' cases: which case a game came in (GameCase), how its lid and inner trays swing and latch
## (CaseHingeSim), and the case itself (RetroGameCase over GameCaseModel): every variant builds with its seats, a
## case holds discs and gives them up only when open, and it saves and restores as itself.
##
##   godot --headless --path RetroXR res://Tests/game_case_tests.tscn
##   godot --headless --path RetroXR res://Tests/game_case_tests.tscn -- --only=sim/
##
## Exits non-zero if anything fails. How the cases LOOK is DevTools/cases/case_probe, windowed.
extends "res://Tests/test_suite.gd"

const CASE_SCENE := preload("res://Scenes/Objects/media/game_case.tscn")
const DISC_SCENE := preload("res://Scenes/Objects/media/disc.tscn")
const DT := 1.0 / 72.0
const G_FACE_UP := Vector3(0.0, 0.0, -9.81)       # lying on its back, front up
const G_FACE_DOWN := Vector3(0.0, 0.0, 9.81)
const G_SPINE_DOWN := Vector3(-9.81, 0.0, 0.0)    # standing on its spine edge
const G_UPRIGHT := Vector3(0.0, -9.81, 0.0)       # standing on its bottom edge, as on a shelf

var _case := ""
var _spawned: Array[Node] = []


func _ready() -> void:
	suite_tag = "gamecase"
	quiet_passes = true
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("[gamecase] TIMEOUT during '%s'" % _case)
		get_tree().quit(1))
	get_tree().current_scene = self
	_run()


func _run() -> void:
	var cases: Array = [
		["pick/us psx jewel scan is a jewel case", _pick_psx_us],
		["pick/us psx long scan is a long box", _pick_psx_longbox],
		["pick/us saturn and sega cd follow the scan too", _pick_saturn_segacd],
		["pick/no scan: the release date decides", _pick_by_date],
		["pick/pal psx, dreamcast, saturn", _pick_pal],
		["pick/japan gamecube is the clear small case", _pick_gc],
		["pick/multi-disc games get the case that holds them", _pick_multi],
		["pick/keep-case consoles and their colors", _pick_keep],
		["pick/a platform with no row gets a plain jewel case", _pick_default],
		["pick/a mod's case row is taken", _pick_mod],
		["discs/a game's discs are found by their numbers", _discs_of],
		["sim/a shut case held upside down stays shut", _sim_latched_upside_down],
		["sim/an open lid falls open when the case stands on its spine", _sim_falls_open],
		["sim/a case standing on a shelf holds its lid where it is", _sim_upright_holds],
		["sim/a lid drifting shut rests unlatched; gravity opens it again", _sim_soft_close],
		["sim/a lid flicked shut catches the latch", _sim_flick_latch],
		["sim/a hand pushing it home catches the latch", _sim_hand_latch],
		["sim/a keep case's cover holds against gravity, moves when shaken", _sim_keep_stiff],
		["sim/inner trays never pass the lid", _sim_order],
		["sim/the same steps give the same angles", _sim_deterministic],
		["model/every variant builds with its seats and art", _model_variants],
		["case/a new case seats its discs and keeps them while shut", _case_contents],
		["case/a case saves and restores as itself", _case_save],
		["case/dropped shut or open, a case rests on the floor", _case_drop],
		["case/the PS2 case's holder takes its memory card", _case_card_holder],
		["case/the desktop lifts a disc out of an open case", _case_desktop_grab],
		["case/a cover that carries a disc takes no manual", _case_no_manual_on_disc_cover],
		["case/a UMD case seats its UMD", _case_umd_contents],
	]
	for c in cases:
		_case = str(c[0])
		if not _wanted(_case):
			continue
		await (c[1] as Callable).call()
		_cleanup()
	_finish()


func _cleanup() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			n.queue_free()
	_spawned.clear()
	await get_tree().process_frame


func _pick(sys: String, market: String, discs := 1, size := Vector2i.ZERO, release := "") -> String:
	var p := GameCase.pick(sys, market, discs, size, release)
	return "%s/%s%s" % [p["family"], p["variant"], ("/" + str(p["color"])) if not str(p["color"]).is_empty() else ""]


# ---------------------------------------------------------------- pick
func _pick_psx_us() -> void:
	_eq(_pick("psx", "us", 1, Vector2i(1622, 680)), "jewel/single", "a US jewel scan")
	_eq(_pick("psx", "jp", 1, Vector2i(931, 680)), "jewel/single", "a long scan outside the US is not a long box")


func _pick_psx_longbox() -> void:
	_eq(_pick("psx", "us", 1, Vector2i(931, 680)), "jewel/longbox", "a long-box scan")
	_eq(_pick("psx", "us", 2, Vector2i(931, 680)), "jewel/fatbox2", "a two-disc game is never in the one-disc long box")


func _pick_saturn_segacd() -> void:
	_eq(_pick("saturn", "us", 1, Vector2i(931, 680)), "jewel/longbox", "Saturn long box")
	_eq(_pick("saturn", "us", 1, Vector2i(1509, 680)), "jewel/single", "Saturn jewel")
	_eq(_pick("segacd", "us", 1, Vector2i(931, 680)), "jewel/longbox", "Sega CD long box")


func _pick_by_date() -> void:
	_eq(_pick("psx", "us", 1, Vector2i.ZERO, "1995-09-09"), "jewel/longbox", "a launch game")
	_eq(_pick("psx", "us", 1, Vector2i.ZERO, "1998-01-01"), "jewel/single", "a later game")
	_eq(_pick("psx", "us", 1, Vector2i.ZERO, ""), "jewel/single", "no date, no scan")
	# ScreenScraper's 1024 x 680 scans (its Sega CD long boxes) say nothing by their shape: the date decides.
	_eq(_pick("segacd", "us", 1, Vector2i(1024, 680), "1993-11-19"), "jewel/longbox", "Sonic CD, a normalized scan")
	_eq(_pick("segacd", "us", 1, Vector2i(1024, 680), "1995-03-01"), "jewel/single", "a later Sega CD game")
	_eq(GameCase.market_of("segacd", "C:/roms/segacd/Sonic CD (USA).chd"), "us", "the file's region tag wins")


func _pick_pal() -> void:
	_eq(_pick("psx", "eu"), "jewel/pal", "PAL PlayStation")
	_eq(_pick("dreamcast", "eu"), "jewel/dc_pal", "PAL Dreamcast")
	_eq(_pick("saturn", "eu"), "keep/saturn_pal", "PAL Saturn")
	_eq(_pick("segacd", "eu"), "jewel/fatbox2", "Mega-CD")


func _pick_gc() -> void:
	_eq(_pick("gc", "jp"), "keep/gc_jp", "Japan")
	_eq(_pick("gc", "us"), "keep/gc", "US")


func _pick_multi() -> void:
	_eq(_pick("psx", "us", 3), "jewel/fatbox4", "FF7")
	_eq(_pick("psx", "eu", 2), "jewel/pal_multi2", "PAL 2 discs")
	_eq(_pick("psx", "eu", 4), "jewel/pal_multi4", "PAL 4 discs")
	_eq(_pick("dreamcast", "us", 2), "jewel/double", "Dreamcast 2 discs")
	_eq(_pick("ps2", "us", 2), "keep/double", "PS2 2 discs")
	_eq(_pick("wii", "us", 3), "keep/triple/white", "Wii 3 discs, white")
	_eq(_pick("ps2", "us", 5), "keep/multi5", "5 discs")
	_eq(_pick("saturn", "eu", 2), "jewel/double", "PAL Saturn multi-disc")
	_eq(GameCase.capacity("fatbox4"), 4, "capacity")


func _pick_keep() -> void:
	_eq(_pick("ps2", "jp"), "keep/ps2", "PS2")
	_eq(_pick("xbox", "us"), "keep/single/lime", "Xbox")
	_eq(_pick("xbox360", "eu"), "keep/x360", "Xbox 360")
	_eq(_pick("ps3", "us"), "keep/bluray_game/clear", "PS3")
	_eq(_pick("psp", "us"), "keep/umd", "PSP")
	_eq(_pick("3do", "us"), "keep/3do_long", "3DO US")
	_eq(_pick("3do", "jp"), "jewel/single", "3DO Japan")
	_eq(_pick("cdi", "eu"), "jewel/cdi", "CD-i")
	_eq(_pick("wiiu", "jp"), "keep/wiiu", "Wii U: its own blue case")


func _pick_default() -> void:
	_eq(_pick("neogeocd", "jp"), "jewel/single", "Neo Geo CD")
	_eq(_pick("tg-cd", "us"), "jewel/single", "TurboGrafx-CD")


func _pick_mod() -> void:
	var err := MediaDimensions.register_mod_media("testcd", {"disc_diameter": 0.12,
		"case": {"family": "keep", "variant": "x360", "color": "black"}}, "test.mod")
	_eq(err, "", "accepted")
	_eq(_pick("testcd", "us"), "keep/x360/black", "the mod's case")
	_ok(not MediaDimensions.register_mod_media("testcd2", {"case": {"family": "jewel", "variant": "nope"}},
		"test.mod").is_empty(), "an unknown variant is refused")
	MediaDimensions.drop_mod("test.mod")


func _discs_of() -> void:
	var dir := "user://game_case_tests"
	DirAccess.make_dir_recursive_absolute(dir)
	for n in ["Game (USA) (Disc 1).chd", "Game (USA) (Disc 2).chd", "Game (USA) (Disc 3).chd", "Other (USA).chd"]:
		FileAccess.open(dir.path_join(n), FileAccess.WRITE).store_string("x")
	var found := GameCase.discs_of(dir.path_join("Game (USA) (Disc 2).chd"))
	_eq(found.size(), 3, "three discs")
	_ok(found[0].ends_with("(Disc 1).chd") and found[2].ends_with("(Disc 3).chd"), "in order", str(found))
	_eq(GameCase.discs_of(dir.path_join("Other (USA).chd")).size(), 1, "a one-disc game")
	var m3u := FileAccess.open(dir.path_join("Game.m3u"), FileAccess.WRITE)
	m3u.store_string("Game (USA) (Disc 1).chd\nGame (USA) (Disc 2).chd\n")
	m3u.close()
	_eq(GameCase.discs_of(dir.path_join("Game.m3u")).size(), 2, "an m3u's list")


# ---------------------------------------------------------------- sim
func _jewel_sim(inner := 0) -> CaseHingeSim:
	var s := CaseHingeSim.new()
	var levers: Array = []
	for i in inner + 1:
		levers.append(0.0365)
	s.configure(levers, 180.0, 0.12, 400.0, 20.0)
	return s


func _run_sim(s: CaseHingeSim, g: Vector3, seconds: float) -> void:
	for _i in int(seconds / DT):
		s.step(DT, g)


func _sim_latched_upside_down() -> void:
	var s := _jewel_sim()
	_run_sim(s, G_FACE_DOWN, 2.0)
	_ok(s.latched and s.angle_deg(0) == 0.0, "still shut", str(s.angle_deg(0)))


func _sim_falls_open() -> void:
	var s := _jewel_sim()
	s.set_angle_deg(0, 30.0)
	_run_sim(s, G_SPINE_DOWN, 2.0)
	_ok(s.angle_deg(0) > 170.0, "open flat", str(s.angle_deg(0)))
	s.set_angle_deg(0, 90.0)
	_run_sim(s, G_FACE_UP, 2.0)
	_ok(absf(s.angle_deg(0) - 90.0) < 0.5, "a lid standing straight up over a case lying open is balanced",
		str(s.angle_deg(0)))


func _sim_upright_holds() -> void:
	var s := _jewel_sim()
	s.set_angle_deg(0, 60.0)
	_run_sim(s, G_UPRIGHT, 2.0)
	_ok(absf(s.angle_deg(0) - 60.0) < 0.5, "held at 60", str(s.angle_deg(0)))
	_ok(s.settled(G_UPRIGHT), "settled")


func _sim_soft_close() -> void:
	var s := _jewel_sim()
	s.set_angle_deg(0, 30.0)
	_run_sim(s, Vector3(9.81, 0.0, 0.0), 1.0)       # standing on its opening edge: the lid falls shut from 30
	_ok(s.angle_deg(0) == 0.0 and not s.latched, "resting shut, unlatched", "%f %s" % [s.angle_deg(0), s.latched])
	_run_sim(s, G_FACE_DOWN, 1.0)
	_ok(s.angle_deg(0) > 75.0, "turned over, gravity opens it to hang down", str(s.angle_deg(0)))


func _sim_flick_latch() -> void:
	var s := _jewel_sim()
	s.set_angle_deg(0, 120.0)
	s.speeds[0] = -40.0
	_run_sim(s, G_UPRIGHT, 0.5)
	_ok(s.latched, "caught")
	s.clicked = false
	s.set_angle_deg(0, 45.0)
	s.speeds[0] = -1.0
	s.latched = false
	_run_sim(s, Vector3(9.81, 0.0, 0.0), 2.0)
	_ok(not s.latched, "a gentle fall home does not catch")


func _sim_hand_latch() -> void:
	var s := _jewel_sim()
	s.set_angle_deg(0, 40.0)
	s.set_held(0, true)
	for a in [30.0, 20.0, 10.0, 4.0]:
		s.set_held_angle_deg(0, a, DT)
	_ok(s.latched and s.clicked, "caught under the hand")
	s.set_held(0, false, 0.0)
	_run_sim(s, G_FACE_DOWN, 1.0)
	_ok(s.latched, "and stays caught upside down")


func _sim_keep_stiff() -> void:
	var s := CaseHingeSim.new()
	s.configure([0.067], 180.0, 1.3, 900.0, 15.0)
	s.set_angle_deg(0, 60.0)
	_run_sim(s, G_SPINE_DOWN, 2.0)
	_ok(absf(s.angle_deg(0) - 60.0) < 0.5, "gravity alone does not move it", str(s.angle_deg(0)))
	_run_sim(s, G_SPINE_DOWN * 3.0, 0.5)              # a hard shake: 3 g along the same line
	_ok(s.angle_deg(0) > 61.0, "a shake does", str(s.angle_deg(0)))


func _sim_order() -> void:
	var s := _jewel_sim(1)
	s.set_angle_deg(1, 100.0)
	s.set_angle_deg(0, 20.0)
	_run_sim(s, Vector3(9.81, 0.0, 0.0), 1.0)       # both fall toward shut; the lid lands on the flip tray
	_ok(s.angle_deg(0) <= s.angle_deg(1) + 1e-6, "flip <= lid", "%f %f" % [s.angle_deg(0), s.angle_deg(1)])
	s.set_angle_deg(1, 0.0)
	_ok(s.angle_deg(0) == 0.0, "a shut lid shuts the flip tray under it")


func _sim_deterministic() -> void:
	var a := _jewel_sim(1)
	var b := _jewel_sim(1)
	for s in [a, b]:
		s.set_angle_deg(1, 150.0)
		s.set_angle_deg(0, 80.0)
		_run_sim(s, Vector3(-4.0, -3.0, 7.0), 1.5)
	_eq(a.angle_deg(0), b.angle_deg(0), "flip")
	_eq(a.angle_deg(1), b.angle_deg(1), "lid")


# ---------------------------------------------------------------- model / case
func _model_variants() -> void:
	var tex := ImageTexture.create_from_image(Image.create(1622, 680, false, Image.FORMAT_RGB8))
	for fam: String in GameCaseModel.FAMILIES:
		for v: String in GameCaseModel.variants_of(fam):
			var m := GameCaseModel.new()
			add_child(m)
			_spawned.append(m)
			_ok(m.build(fam, v), "%s/%s builds" % [fam, v])
			if m.levels.size() != 3:
				continue
			var seats := (m.contract().get("seats", []) as Array).size()
			_eq(m.disc_seat_count(), seats, "%s/%s disc seats" % [fam, v])
			_ok(m.manual_seat() != null, "%s/%s manual seat" % [fam, v])
			_eq(m.apply_box_texture(tex), OK, "%s/%s takes a box texture" % [fam, v])
			m.set_angles(180.0, [90.0, 90.0])
			if seats > 0:
				_ok(m.disc_seat(1).position.length() < 0.2, "%s/%s seat 1 sits in the case" % [fam, v])
	await get_tree().process_frame


func _new_case(fam: String, variant: String) -> RetroGameCase:
	var c := CASE_SCENE.instantiate() as RetroGameCase
	c.systemid = "psx"
	c.case_family = fam
	c.case_variant = variant
	add_child(c)
	c.add_to_group("spawned")
	c.freeze = true
	_spawned.append(c)
	return c


func _case_contents() -> void:
	var c := _new_case("jewel", "fatbox4")
	await get_tree().physics_frame
	_eq(c._zones.size(), 4, "four hubs")
	for i in 2:
		var d := DISC_SCENE.instantiate() as RetroDisc
		d.systemid = "psx"
		add_child(d)
		d.add_to_group("spawned")
		_spawned.append(d)
		c.disc_zone(i).pick_up_object(d)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_eq(c.discs().size(), 2, "two discs seated")
	_ok(not (c.discs()[0] as XRToolsPickable).enabled, "a disc in a shut case cannot be taken")
	c.sim.set_angle_deg(c.sim.top(), 175.0)
	c.sim.set_angle_deg(0, 5.0)
	c._apply_angles()
	_ok(not (c.discs()[0] as XRToolsPickable).enabled, "the base disc is covered by the flip tray lying on it")
	_ok(not (c.discs()[1] as XRToolsPickable).enabled, "and so is the flip tray's under side")
	_ok(c._seat_reachable(2), "the flip tray's top face is open to the hand")
	c.sim.set_angle_deg(0, 170.0)
	c._apply_angles()
	_ok((c.discs()[0] as XRToolsPickable).enabled, "the flip tray turned over: the base disc can be taken")
	_ok((c.discs()[1] as XRToolsPickable).enabled, "and the flip tray's under side, now facing up")
	# The hub's button pops a disc up, only where a finger can reach it.
	c.sim.set_angle_deg(0, 5.0)
	c._apply_angles()
	_ok(not c.pop_disc(0), "a covered hub's button cannot be pressed")
	c.sim.set_angle_deg(0, 170.0)
	c._apply_angles()
	var before := c.discs()[0].global_position
	_ok(c.pop_disc(0) and c.is_popped(0), "an open hub's button pops its disc")
	await get_tree().physics_frame
	await get_tree().physics_frame
	var lift := c.disc_zone(0).global_position.distance_to(before)
	_ok(lift > 0.003 and lift < 0.006, "it rides up about 4 mm", str(lift))
	_ok(c.discs()[0].global_position.distance_to(c.disc_zone(0).global_position) < 0.002, "the disc goes with it")
	_ok(c.discs()[0].global_position.distance_to(c.disc_zone(0).global_position) < 0.002, "a disc sits on its hub")


## Dropped shut, and dropped open, every kind of case comes to rest ON the floor: one convex hull, never two boxes
## (two in one body lost their contacts and the case sank into the table).
func _case_drop() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var fcs := CollisionShape3D.new()
	var fbox := BoxShape3D.new()
	fbox.size = Vector3(6.0, 0.02, 6.0)
	fcs.shape = fbox
	floor_body.add_child(fcs)
	add_child(floor_body)
	_spawned.append(floor_body)
	floor_body.global_position = Vector3(0.0, -50.01, 0.0)          # top at y = -50, clear of the other cases
	var drops := [["jewel", "single", 0.0], ["keep", "wiiu", 0.0], ["keep", "ps2", 0.0], ["jewel", "fatbox4", 0.0],
		["jewel", "single", 180.0], ["keep", "wiiu", 180.0]]
	var cases: Array[RetroGameCase] = []
	var x := -2.0
	for d in drops:
		var c := _new_case(str(d[0]), str(d[1]))
		c.freeze = false
		c.global_transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(x, -49.7, 0.0))
		x += 0.5
		if float(d[2]) > 0.0:
			c.sim.set_angle_deg(c.sim.top(), float(d[2]))
			c._apply_angles()
		cases.append(c)
	for _i in 200:
		await get_tree().physics_frame
	for c in cases:
		var shapes := c.get_children().filter(func(n: Node) -> bool: return n is CollisionShape3D)
		_eq(shapes.size(), 1, "%s/%s is one shape" % [c.case_family, c.case_variant])
		var low := INF
		for pt in ((shapes[0] as CollisionShape3D).shape as ConvexPolygonShape3D).points:
			low = minf(low, ((shapes[0] as CollisionShape3D).global_transform * pt).y)
		_ok(absf(low + 50.0) < 0.001, "%s/%s lid %.0f rests on the floor" % [c.case_family, c.case_variant, c.lid_deg()],
			"%.1f mm" % ((low + 50.0) * 1000.0))
		_ok(absf(c.global_basis.z.y) > 0.999, "%s/%s lies flat" % [c.case_family, c.case_variant], str(c.global_basis.z))
	_ok(cases[4].lid_deg() > 181.0, "an open jewel lid turns past flat onto the floor", str(cases[4].lid_deg()))


## The PS2 case's holder takes a PS2 memory card, label out; not a GameCube card, nor through a shut lid.
func _case_card_holder() -> void:
	var c := _new_case("keep", "ps2")
	await get_tree().physics_frame
	_ok(c.card_zone() != null, "the PS2 case has a card holder")
	var plain := _new_case("keep", "single")
	_ok(plain.card_zone() == null, "a plain keep case has none")
	_spawned.erase(plain)
	plain.free()                       # it stood where this one is: the rays below would find it
	var ps2 := (load("res://Scenes/Objects/media/ps2_memory_card.tscn") as PackedScene).instantiate() as MemoryCard
	var gc := (load("res://Scenes/Objects/media/gc_memory_card.tscn") as PackedScene).instantiate() as MemoryCard
	for card in [ps2, gc]:
		add_child(card)
		_spawned.append(card)
	var filter: Callable = c.card_zone().snap_filter
	_ok(not filter.call(ps2), "shut, the holder takes nothing")
	c.sim.set_angle_deg(c.sim.top(), 180.0)
	c._apply_angles()
	_ok(filter.call(ps2), "open, it takes a PS2 card")
	_ok(not filter.call(gc), "but not a GameCube card")
	c.card_zone().pick_up_object(ps2)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_ok(c.memory_card() == ps2, "the card is in the holder")
	_ok(ps2.global_position.distance_to(c.model.card_seat().global_position) < 0.002, "on its seat")
	_ok(ps2.global_basis.y.dot(c.model.card_seat().global_basis.z) > 0.99, "its label facing out of the panel")
	_ok(ps2.global_basis.z.dot(c.model.card_seat().global_basis.x) > 0.99,
		"lying across the landscape holder, its +Z end toward the opening edge")
	# The desktop ray reaches what is in an open case, not the case round it.
	var d := DISC_SCENE.instantiate() as RetroDisc
	d.systemid = "ps2"
	add_child(d)
	_spawned.append(d)
	c.disc_zone(0).pick_up_object(d)
	for _i in 3:
		await get_tree().physics_frame
	var front := c.model.disc_seat(1).global_basis.y
	_ok(_ray_hit(c.disc_zone(0).global_position + c.model.disc_seat(1).global_basis.x * 0.035, front, c.get_world_3d()) == d,
		"the ray over the open case's disc reaches the disc")
	_ok(_ray_hit(c.card_zone().global_position, front, c.get_world_3d()) == ps2, "and the ray over its card reaches the card")
	c.sim.set_angle_deg(c.sim.top(), 0.0)
	c._apply_angles()
	await get_tree().physics_frame
	_ok(_ray_hit(c.disc_zone(0).global_position + c.model.disc_seat(1).global_basis.x * 0.035, front, c.get_world_3d()) == c,
		"shut, the ray takes the case")


## The desktop's own resolver on an open Wii U case: off the middle, a click lifts the disc (from the zone holding
## it); on the hub, it presses the hub; once popped, the middle lifts the disc too. And the lift itself works: the
## zone lets go and a hand has it.
func _case_desktop_grab() -> void:
	var c := _new_case("keep", "wiiu")
	c.global_position = Vector3(5.0, 0.0, 0.0)
	await get_tree().physics_frame
	c.sim.set_angle_deg(c.sim.top(), 180.0)
	c._apply_angles()
	var d := DISC_SCENE.instantiate() as RetroDisc
	d.systemid = "wiiu"
	add_child(d)
	_spawned.append(d)
	c.disc_zone(0).pick_up_object(d)
	for _i in 3:
		await get_tree().physics_frame
	var grabber := Node3D.new()
	add_child(grabber)
	_spawned.append(grabber)
	var seat := c.model.disc_seat(1)
	var up := seat.global_basis.y
	var space := c.get_world_3d().direct_space_state
	var off := seat.global_position + seat.global_basis.x * 0.035
	var t := InteractionResolver.resolve_desktop(space, off + up * 0.3, off - up * 0.05, grabber)
	_ok(t.is_valid() and t.highlight_node == d, "off the middle, a click takes the disc",
		"%s %s" % [t.kind, t.highlight_node])
	var mid := seat.global_position
	t = InteractionResolver.resolve_desktop(space, mid + up * 0.3, mid - up * 0.05, grabber)
	_ok(t.is_valid() and t.kind == InteractionTarget.KIND_BUTTON, "on the hub, a click presses the hub",
		"%s %s" % [t.kind, t.action_node])
	c.pop_disc(0)
	for _i in 3:
		await get_tree().physics_frame
	t = InteractionResolver.resolve_desktop(space, mid + up * 0.3, mid - up * 0.05, grabber)
	_ok(t.is_valid() and t.highlight_node == d, "popped, the middle takes the disc too", "%s %s" % [t.kind, t.highlight_node])
	var zone := t.action_node as XRToolsSnapZone
	_ok(zone == c.disc_zone(0) and d.enabled, "through the zone that holds it, which lets it go")
	if zone != null:
		zone.drop_object()
	_ok(d.can_pick_up(grabber) and not c.discs().has(d), "and then a hand may have it")


func _case_umd_contents() -> void:
	var c := _new_case("keep", "umd")
	c.systemid = "psp"
	await get_tree().physics_frame
	c.spawn_contents(PackedStringArray(["C:/roms/psp/Game.iso"]))
	for d in c.discs():
		_spawned.append(d)
	await get_tree().physics_frame
	_eq(c.discs().size(), 1, "one UMD on its holder")
	_ok(c.discs()[0] is RetroUMD if not c.discs().is_empty() else false, "a UMD, not a disc")
	if not c.discs().is_empty():
		_ok(c.discs()[0].global_basis.y.dot(c.model.umd_seat().global_basis.z) > 0.99,
			"lying flat in its holder, label out")


func _case_no_manual_on_disc_cover() -> void:
	var c := _new_case("keep", "multi5")
	await get_tree().physics_frame
	_ok(c._manual_zone == null, "the five-disc case seats no manual (its cover carries a disc)")
	var s := _new_case("keep", "single")
	await get_tree().physics_frame
	_ok(s._manual_zone != null, "a single case does")


## The pickable the desktop ray would take first coming down `dir` onto `at`.
func _ray_hit(at: Vector3, dir: Vector3, world: World3D) -> Node:
	var q := PhysicsRayQueryParameters3D.create(at + dir * 0.2, at - dir * 0.02, 1 << 20)
	q.collide_with_areas = true
	var r: Dictionary = world.direct_space_state.intersect_ray(q)
	if r.is_empty():
		return null
	var n := r.collider as Node
	while n != null and not n is XRToolsPickable:
		n = n.get_parent()
	return n


func _case_save() -> void:
	var c := _new_case("keep", "triple")
	await get_tree().physics_frame
	c.hinge(c.sim.top()).set_rotation_deg_remote(120.0)
	await get_tree().physics_frame
	var entry := ScenePersistence.new().serialize_node(c, 1, {c: 1})
	_eq(str(entry.get("type", "")), "game_case", "type")
	_eq(str(entry.get("case_variant", "")), "triple", "variant")
	var hinges: Array = entry.get("articulated", [])
	_ok(hinges.size() == 2, "two hinges saved (the flipper and the cover)", str(hinges))
	var back := ScenePersistence.new().call("_load_game_case", entry) as RetroGameCase
	_ok(back != null and back.case_variant == "triple" and back.case_family == "keep", "loads back")
	if back != null:
		back.free()
