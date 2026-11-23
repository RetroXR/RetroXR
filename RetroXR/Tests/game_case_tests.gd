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
const BOOK_SCENE := preload("res://Scenes/Objects/media/pdf_book.tscn")
const PICKUP_SCENE := preload("res://addons/godot-xr-tools/functions/function_pickup.tscn")
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
		["pick/the menu icon is tall or square as the case is, doubled for a multi-disc case", _pick_icon],
		["sim/a shut case held upside down stays shut", _sim_latched_upside_down],
		["sim/an open lid falls open when the case stands on its spine", _sim_falls_open],
		["sim/a case standing on a shelf holds its lid where it is", _sim_upright_holds],
		["sim/a lid drifting shut rests unlatched; gravity opens it again", _sim_soft_close],
		["sim/a lid flicked shut catches the latch", _sim_flick_latch],
		["sim/a hand pushing it home catches the latch", _sim_hand_latch],
		["sim/a keep case's cover holds against gravity, moves when shaken", _sim_keep_stiff],
		["sim/inner trays never pass the lid", _sim_order],
		["sim/a caught lid holds its flip trays shut face down", _sim_latched_trays],
		["sim/a turn of the wrist swings the lid", _sim_spin],
		["sim/a lid reports how hard it hits its stops", _sim_knock],
		["sim/a keep case's cover rests ajar unlatched, eases back when let go", _sim_living_hinge],
		["sim/a keep case's flippers swing free under a cover that holds", _sim_flippers],
		["sim/a keep case's flippers turn like pages", _sim_pages],
		["sim/the same steps give the same angles", _sim_deterministic],
		["model/every variant builds with its seats and art", _model_variants],
		["case/a new case seats its discs and keeps them while shut", _case_contents],
		["case/a case saves and restores as itself", _case_save],
		["case/a disc put on a hub keeps the turn the hand held it at", _case_disc_spin],
		["case/a manual is seated shut, its reach round the booklet's middle", _case_manual_seat],
		["case/what is in the lid's way turns it, either way, and a fingertip has the whole panel", _case_lid_world],
		["case/gripped by its open lid, the lid stays in the hand and the base swings", _case_held_by_lid],
		["case/held by its lid, the base has the handle: pressed, it does not creep", _case_base_handle],
		["case/a held case's lid still gives way, and held by the lid its base does", _case_world_held],
		["case/a grip anywhere over the booklet takes the manual; at a shut case, the case", _case_manual_reach],
		["case/a seated manual turns no page and the lid's handle is quiet over it", _case_manual_quiet],
		["case/let go a little way into a tabletop, a case is lifted onto it", _case_lift_out],
		["model/a clear disc tray is drawn as a molded part", _clear_trays],
		["model/a jewel scan's wide spine strip is laid on the spine", _scan_spine_fit],
		["model/a case's three panels are joined into the layout", _panels_join],
		["case/a jewel case asks for its panels and takes them", _case_panels],
		["case/a manual put in keeps its pages unless it is a spread scan", _case_manual_spread],
		["case/a flip tray's hinge is taken from either face", _case_tray_both_faces],
		["case/a fingertip pushes a lid and never pulls it", _case_poke_no_pull],
		["case/a shut lid's inside is not a fingertip's", _case_poke_shut_inside],
		["case/a tray lying on the open lid is still the hand's", _case_tray_on_lid],
		["case/the fat case keeps its manual in the black tray", _case_manual_on_tray],
		["case/a case from an older save takes the real disc layout", _case_old_layout],
		["case/deleting what was seated does not stop the lid", _case_deleted_seated],
		["case/a seated manual's pages are on the case's own paper", _case_manual_paper],
		["case/disc 1 is nearest the front cover, and every disc reads upright", _case_disc_order],
		["case/a flipper is drawn where its handle is", _case_pages_drawn_as_held],
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
	_eq(_pick("psx", "us", 2, Vector2i(931, 680)), "jewel/fatbox4", "a two-disc game is never in the one-disc long box")
	_eq(_pick("psx", "us", 2), "jewel/fatbox4", "Metal Gear Solid (USA): the shell Final Fantasy VIII's four came in")
	_eq(_pick("psx", "jp", 2), "jewel/fatbox4", "a Japanese two-disc game is given the same shell (its manual in the black tray)")
	_eq(_pick("psx", "eu", 2), "jewel/pal_multi2", "a European one keeps the PAL case")
	_eq(_pick("segacd", "us", 2), "jewel/fatbox2", "a Sega CD two-disc game keeps the double case")


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
	# A game's disc total: what its scraped rows agree on. These are a library's own rows (2026-11-22).
	var ff7 := [{"path": "./Final Fantasy VII (USA) (Disc 1).cue", "disc_num": 1.0, "disc_total": 3.0, "region": "USA"},
		{"path": "./Final Fantasy VII (USA) (Disc 2).cue", "disc_num": 2.0, "disc_total": 3.0, "region": "USA"},
		{"path": "./Final Fantasy VII (USA) (Disc 3).cue", "disc_num": 3.0, "disc_total": 3.0, "region": "USA"},
		{"path": "./Final Fantasy VII (USA) (Disc 1).chd", "disc_num": 1, "disc_total": 9, "region": "USA"}]
	_eq(GameCase.disc_total_from(ff7, "Final Fantasy VII (USA) (Disc 1).chd"), 3, "a row that says 9 beside three that say 3: three discs")
	_eq(GameCase.disc_total_from(ff7, "Final Fantasy VII (USA) (Disc 2).cue"), 3, "and for any disc of the set")
	var mgs := [{"path": "./Metal Gear Solid (USA) (Disc 2) (Rev 1).cue", "disc_num": 2.0, "disc_total": 2.0, "region": "USA"},
		{"path": "./Metal Gear Solid (USA) (Disc 1) (Rev 1).cue", "disc_num": 1.0, "disc_total": 2.0, "region": "USA"},
		{"path": "./Metal Gear Solid (USA) (Disc 2).cue", "disc_num": 2.0, "disc_total": 5.0, "region": "USA"},
		{"path": "./Metal Gear Solid (Italy) (Disc 1).cue", "disc_num": 1.0, "disc_total": 2.0, "region": "Italy"},
		{"path": "./Metal Gear Solid (Italy) (Disc 2).cue", "disc_num": 2.0, "disc_total": 2.0, "region": "Italy"}]
	_eq(GameCase.disc_total_from(mgs, "Metal Gear Solid (USA) (Disc 2).cue"), 2, "a row that says 5 beside two that say 2: two discs")
	_eq(GameCase.disc_total_from(mgs, "Metal Gear Solid (Italy) (Disc 1).cue"), 2, "another release's rows count for their own")
	_eq(GameCase.disc_total_from([{"path": "./Lone (Disc 1).chd", "disc_num": 1, "disc_total": 9, "region": "USA"}], "Lone (Disc 1).chd"), 1,
		"a lone impossible total says nothing: its own number is all that is known")
	_eq(GameCase.disc_total_from([{"path": "./Four (Disc 1).chd", "disc_num": 1, "disc_total": 4, "region": "USA"}], "Four (Disc 1).chd"), 4,
		"a lone possible total is believed")
	_eq(GameCase.disc_total_from([{"path": "./Two (Disc 3).chd", "disc_num": 3, "disc_total": 2, "region": "USA"}], "Two (Disc 3).chd"), 3,
		"never fewer than a disc number that exists")
	_eq(GameCase.disc_total_from([], "Nothing.chd"), 0, "nothing scraped, nothing said")


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


func _pick_icon() -> void:
	for row in [["jewel", "single", false], ["jewel", "fatbox4", false], ["jewel", "longbox", true], ["jewel", "pal", false],
			["keep", "ps2", true], ["keep", "gc_jp", true], ["keep", "umd", true], ["keep", "multi5", true]]:
		_eq(GameCase.is_tall(row[0], row[1]), row[2], "%s/%s tall" % [row[0], row[1]])
	for shape in ["square", "tall", "square_multi", "tall_multi"]:
		_ok(MenuIcons.case_icon(shape) != null, "an icon for %s" % shape)
	_ok(MenuIcons.case_icon("round") == null, "none for a shape there is no picture of")
	var dir := OS.get_user_data_dir().path_join("game_case_icon_test")
	DirAccess.make_dir_recursive_absolute(dir)
	var img := Image.create(931, 680, false, Image.FORMAT_RGB8)
	img.save_png(dir.path_join("a.png"))
	img.save_jpg(dir.path_join("a.jpg"))
	_eq(GameCase.image_size(dir.path_join("a.png")), Vector2i(931, 680), "a PNG's size from its header")
	_eq(GameCase.image_size(dir.path_join("a.jpg")), Vector2i(931, 680), "a JPEG's")
	_eq(GameCase.image_size(dir.path_join("none.png")), Vector2i.ZERO, "none for a missing file")
	_eq(GameCase.icon_of("ps2", "/nowhere/Game (USA).iso"), "tall", "a PS2 game")
	GameCase._icon_cache["segacd|/nowhere/Old (USA).chd"] = "square"
	_eq(GameCase.icon_of("segacd", "/nowhere/Old (USA).chd"), "square", "kept per game")
	GameCase.forget_icon("segacd", "/nowhere/Old (USA).chd")
	_ok(not GameCase._icon_cache.has("segacd|/nowhere/Old (USA).chd"), "and forgotten when its art changes")
	_eq(GameCase.icon_of("psx", "/nowhere/Game (Japan).cue"), "square", "a Japanese PlayStation game")
	_eq(GameCase.icon_of("dreamcast", "/nowhere/Game (USA).chd"), "square", "a Dreamcast game")
	for n in [1, 2]:
		FileAccess.open(dir.path_join("Two (USA) (Disc %d).chd" % n), FileAccess.WRITE).close()
	_eq(GameCase.icon_of("psx", dir.path_join("Two (USA) (Disc 1).chd")), "square_multi", "a two-disc PlayStation game")
	_eq(GameCase.icon_of("ps2", dir.path_join("Two (USA) (Disc 1).chd")), "tall_multi", "a two-disc PS2 game")
	_eq(GameCase.icon_of("gc", dir.path_join("Two (USA) (Disc 1).chd")), "tall_multi", "a two-disc GameCube game")
	_eq(str(GameCase.pick("gc", "us", 2)["variant"]), "gc_double", "its American case: two hubs on the back panel")
	_eq(str(GameCase.pick("gc", "eu", 2)["variant"]), "gc_double_pal", "its European case: a flap over the hub")
	_eq(str(GameCase.pick("gc", "jp", 2)["variant"]), "gc_jp_double", "its Japanese case: a disc under the cover's strap")
	_eq(str(GameCase.pick("gc", "us", 1)["variant"]), "gc", "one disc: the single case")
	_eq(str(GameCase.pick("xbox360", "us", 2)["variant"]), "x360", "a two-disc Xbox 360 game keeps the single case")
	var both := GameCase.disc_slots(dir.path_join("Two (USA) (Disc 2).chd"))
	_ok(both.size() == 2 and both[0].ends_with("(Disc 1).chd") and both[1].ends_with("(Disc 2).chd"), "both discs, in order", str(both))
	FileAccess.open(dir.path_join("Lone (USA) (Disc 2).chd"), FileAccess.WRITE).close()
	var lone := GameCase.disc_slots(dir.path_join("Lone (USA) (Disc 2).chd"), 3)
	_ok(lone.size() == 3 and lone[0].is_empty() and lone[1].ends_with("(Disc 2).chd") and lone[2].is_empty(),
		"disc 2 of 3 alone: in the second seat, the others empty", str(lone))
	var one := GameCase.disc_slots("/nowhere/Game (USA).chd", 0)
	_ok(one.size() == 1 and one[0] == "/nowhere/Game (USA).chd", "a single-disc game", str(one))


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
	s.configure([0.067], 180.0, 2.5, 900.0, 15.0, 1.0)
	s.set_angle_deg(0, 60.0)
	_run_sim(s, G_SPINE_DOWN, 2.0)
	_ok(absf(s.angle_deg(0) - 60.0) < 0.5, "gravity alone does not move it", str(s.angle_deg(0)))
	_run_sim(s, G_SPINE_DOWN * 2.0, 0.2)              # the hand moving off: 1 g more
	_ok(absf(s.angle_deg(0) - 60.0) < 0.5, "nor a move of the hand", str(s.angle_deg(0)))
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


func _sim_latched_trays() -> void:
	var s := _jewel_sim(2)
	_run_sim(s, G_FACE_DOWN, 1.0)
	_ok(s.latched and s.angle_deg(2) == 0.0 and s.angle_deg(0) == 0.0, "all shut",
		"%f %f" % [s.angle_deg(0), s.angle_deg(2)])
	_ok(s.settled(G_FACE_DOWN), "settled")


func _sim_spin() -> void:
	var s := _jewel_sim()
	s.set_angle_deg(0, 60.0)
	for _i in int(0.2 / DT):
		s.step(DT, G_UPRIGHT, 80.0)                   # the case turned away from under its lid
	_ok(s.angle_deg(0) > 70.0, "the lid stays behind, opening", str(s.angle_deg(0)))
	s.set_angle_deg(0, 60.0)
	for _i in int(0.2 / DT):
		s.step(DT, G_UPRIGHT, -80.0)
	_ok(s.angle_deg(0) < 50.0, "and the other way, closing", str(s.angle_deg(0)))
	s = _jewel_sim()
	s.step(DT, G_UPRIGHT, 300.0)
	_ok(s.latched, "a caught lid rides a flick")
	_ok(not s.settled(G_UPRIGHT, 500.0), "a jolt past the latch is not rest")
	s.step(DT, G_UPRIGHT, 500.0)
	_ok(not s.latched, "and springs on a jolt past the latch")


func _sim_knock() -> void:
	var s := _jewel_sim()
	s.set_angle_deg(0, 100.0)
	var hit := 0.0
	for _i in int(1.0 / DT):
		s.step(DT, G_FACE_UP)
		hit = maxf(hit, s.knocked)
	_ok(hit > 5.0, "falling open onto its stop", str(hit))
	s.knocked = 0.0
	s.set_angle_deg(0, 30.0)
	_run_sim(s, Vector3(9.81, 0.0, 0.0), 1.0)
	_ok(s.knocked > 2.0 and not s.latched, "falling home without catching", str(s.knocked))
	s.knocked = 0.0
	s.set_held(0, true)
	for a in [120.0, 150.0, 180.0, 180.0]:
		s.set_held_angle_deg(0, a, DT)
	_ok(s.knocked > 20.0, "thrown open by a hand", str(s.knocked))
	s.knocked = 0.0
	s.set_held_angle_deg(0, 180.0, DT)
	_ok(s.knocked == 0.0, "held against the stop, no second knock")


func _keep_sim(inner := 0) -> CaseHingeSim:
	var s := CaseHingeSim.new()
	var levers: Array = []
	for i in inner + 1:
		levers.append(0.067)
	s.configure(levers, 180.0, 2.5, 900.0, 15.0, 1.0)
	for i in inner:
		s.set_hinge_friction(i, 0.12, 0.8)
	s.set_living_hinge(4.0, 4.0)
	return s


func _sim_living_hinge() -> void:
	var s := _keep_sim()
	_run_sim(s, G_FACE_UP, 1.0)
	_ok(s.latched and s.angle_deg(0) == 0.0, "clasped, it stays shut")
	s.latched = false
	_run_sim(s, G_FACE_UP, 1.0)
	_ok(s.angle_deg(0) > 1.0 and s.angle_deg(0) < 5.0 and not s.latched, "unclasped, it springs ajar", str(s.angle_deg(0)))
	_ok(s.settled(G_FACE_UP), "and rests there")
	s.set_held(0, true)
	for a in [40.0, 50.0, 60.0]:
		s.set_held_angle_deg(0, a, DT)
	s.set_held(0, false, 0.0)
	_run_sim(s, G_UPRIGHT, 1.0)
	_ok(absf(s.angle_deg(0) - 56.0) < 0.5, "opened to 60 and let go, it eases back to 56", str(s.angle_deg(0)))
	_ok(s.settled(G_UPRIGHT), "and rests")
	s.set_held(0, true)
	for a in [50.0, 40.0]:
		s.set_held_angle_deg(0, a, DT)
	s.set_held(0, false, 0.0)
	_run_sim(s, G_UPRIGHT, 1.0)
	_ok(absf(s.angle_deg(0) - 44.0) < 0.5, "pushed shut to 40, back out to 44", str(s.angle_deg(0)))
	s.set_held(0, true)
	for a in [20.0, 3.0]:
		s.set_held_angle_deg(0, a, DT)
	s.set_held(0, false, 0.0)
	_run_sim(s, G_FACE_DOWN, 1.0)
	_ok(s.latched and s.angle_deg(0) == 0.0, "pressed home it clasps and stays", str(s.angle_deg(0)))


func _sim_flippers() -> void:
	var s := _keep_sim(1)
	s.set_angle_deg(1, 120.0)
	s.set_angle_deg(0, 70.0)
	_run_sim(s, G_FACE_UP, 2.0)
	_ok(s.angle_deg(0) < 1.0, "the flipper falls shut", str(s.angle_deg(0)))
	_ok(absf(s.angle_deg(1) - 120.0) < 0.5, "the cover holds", str(s.angle_deg(1)))
	s.set_angle_deg(0, 100.0)
	_run_sim(s, G_FACE_UP, 2.0)
	_ok(absf(s.angle_deg(0) - 120.0) < 0.5, "past upright it falls onto the cover", str(s.angle_deg(0)))
	_ok(absf(s.angle_deg(1) - 120.0) < 0.5, "which still holds", str(s.angle_deg(1)))


func _page_sim() -> CaseHingeSim:
	var s := CaseHingeSim.new()
	s.configure([0.067, 0.067, 0.067], 180.0, 2.5, 900.0, 15.0, 1.0)
	for i in 2:
		s.set_hinge_friction(i, 0.12, 0.8)
	s.set_page_rule(15.0, 85.0)
	s.set_angle_deg(2, 180.0)                             # the cover lying open
	return s


func _sim_pages() -> void:
	var s := _page_sim()
	# A hand raises the lower flipper: the upper rides ahead of it, fanning out to a page's width.
	s.set_held(0, true)
	s.set_held_angle_deg(0, 8.0, DT)
	_ok(absf(s.angle_deg(0) - 8.0) < 0.01 and absf(s.angle_deg(1) - 16.0) < 0.01, "lower at 8: the upper fans to 16",
		"%f %f" % [s.angle_deg(0), s.angle_deg(1)])
	s.set_held_angle_deg(0, 40.0, DT)
	_ok(absf(s.angle_deg(0) - 40.0) < 0.01 and absf(s.angle_deg(1) - 55.0) < 0.01, "lower at 40: the upper 15 ahead, at 55",
		"%f %f" % [s.angle_deg(0), s.angle_deg(1)])
	s.set_held_angle_deg(0, 120.0, DT)
	_ok(absf(s.angle_deg(0) - 85.0) < 0.01 and absf(s.angle_deg(1) - 100.0) < 0.01, "pulled to 120 it stands at 85, the upper at 100",
		"%f %f" % [s.angle_deg(0), s.angle_deg(1)])
	s.set_held(0, false)
	# The upper one laid back down takes the lower with it, closing the fan.
	s.set_held(1, true)
	s.set_held_angle_deg(1, 50.0, DT)
	_ok(absf(s.angle_deg(0) - 35.0) < 0.01, "upper down to 50: the lower to 35", str(s.angle_deg(0)))
	s.set_held_angle_deg(1, 10.0, DT)
	_ok(absf(s.angle_deg(0) - 5.0) < 0.01, "upper at 10: the lower at 5", str(s.angle_deg(0)))
	s.set_held_angle_deg(1, 0.0, DT)
	_ok(s.angle_deg(0) == 0.0 and s.angle_deg(1) == 0.0, "both flat together")
	s.set_held(1, false)
	# Free: with the upper over on the cover, a lower one swung up stops standing at 85.
	s = _page_sim()
	s.set_angle_deg(1, 150.0)
	s.set_angle_deg(0, 40.0)
	_run_sim(s, G_SPINE_DOWN, 2.0)                        # standing on its spine: everything falls open
	_ok(absf(s.angle_deg(0) - 85.0) < 0.5 and s.angle_deg(1) > 170.0, "falling open, the lower stops at 85 and the upper goes over",
		"%f %f" % [s.angle_deg(0), s.angle_deg(1)])
	# And falling shut together they keep the rule every step.
	s = _page_sim()
	s.set_angle_deg(1, 80.0)
	s.set_angle_deg(0, 60.0)
	var worst := 0.0
	for _i in int(2.0 / DT):
		s.step(DT, G_FACE_UP)
		worst = maxf(worst, s.angles[0] - s._cap(0))
	_ok(worst < 1e-6 and s.angle_deg(1) < 1.0 and s.angle_deg(0) < 1.0, "falling shut they never cross, and lie flat",
		"%f; %f %f" % [worst, s.angle_deg(0), s.angle_deg(1)])
	# A jewel case's flip tray has no such rule.
	var j := _jewel_sim(1)
	j.set_angle_deg(1, 100.0)
	j.set_angle_deg(0, 100.0)
	_ok(j.angle_deg(0) == 100.0, "a jewel case's flip tray lies right against its lid")


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
	# The disc on a turning tray goes with it in the same frame, not a frame behind.
	c.sim.set_angle_deg(0, 120.0)
	c._apply_angles()
	_ok(c.discs()[1].global_position.distance_to(c.disc_zone(1).global_position) < 0.0005,
		"a disc on a turning flip tray keeps up with it", str(c.discs()[1].global_position.distance_to(c.disc_zone(1).global_position)))
	_ok(c.process_physics_priority < -80, "the case turns its trays before the grab drivers run")
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
func _case_disc_spin() -> void:
	var c := _new_case("jewel", "single")
	await get_tree().physics_frame
	var disc := DISC_SCENE.instantiate() as RetroDisc
	disc.systemid = "psx"
	add_child(disc)
	_spawned.append(disc)
	var seat := c.disc_zone(0).get_parent() as Node3D
	# Never in a hand (a spawn, a restore): square on the hub.
	c._seat_disc(0, disc)
	_ok(c.disc_zone(0).transform.is_equal_approx(Transform3D.IDENTITY), "a disc no hand put there sits square")
	# Let go by a hand turned 50 degrees about the hub: it stays turned, and stays so when popped.
	disc._release_basis = (seat.global_basis.orthonormalized() * Basis(Vector3.UP, deg_to_rad(50.0))).orthonormalized()
	disc._release_msec = Time.get_ticks_msec()
	c._seat_disc(0, disc)
	var turn := rad_to_deg(c.disc_zone(0).transform.basis.get_euler().y)
	_ok(absf(turn - 50.0) < 0.5, "a disc put on turned 50 degrees stays turned", str(turn))
	_ok(c.disc_zone(0).transform.origin.is_zero_approx(), "down on the hub")
	# Tilted in the hand as well: flat on the hub, the same turn.
	disc._release_basis = (seat.global_basis.orthonormalized() * Basis(Vector3.UP, deg_to_rad(-120.0))
		* Basis(Vector3.RIGHT, deg_to_rad(25.0))).orthonormalized()
	c._seat_disc(0, disc)
	var b := c.disc_zone(0).transform.basis
	_ok(b.y.is_equal_approx(Vector3.UP) and absf(rad_to_deg(b.get_euler().y) + 120.0) < 0.5, "tilted in the hand: flat, turned -120",
		str(b.get_euler()))
	c._seat_disc(0)
	_ok(c.disc_zone(0).transform.is_equal_approx(Transform3D.IDENTITY), "taken off: the seat is square again")


func _case_manual_seat() -> void:
	for fam: Array in [["jewel", "single"], ["keep", "ps2"]]:
		var c := _new_case(fam[0], fam[1])
		await get_tree().physics_frame
		c.sim.set_angle_deg(c.sim.top(), 170.0)
		c._apply_angles()
		var zone := c._manual_zone
		var ball := zone.get_node("CollisionShape3D") as CollisionShape3D
		var seat := c.model.manual_seat()
		_ok(seat.to_local(ball.global_position).length() < 0.0005, "%s: the reach is centered on the booklet" % fam[0],
			str(seat.to_local(ball.global_position)))
		_ok(absf(seat.to_local(zone.global_position).x + c.model.manual_size_m().x * 0.5) < 0.0005,
			"%s: the book still seats with its spine at the booklet's edge" % fam[0])
		var book := load("res://Scenes/Objects/media/pdf_book.tscn").instantiate() as PDFBook
		add_child(book)
		book.add_to_group("spawned")
		_spawned.append(book)
		await get_tree().physics_frame
		book._pending_page = {"state": PDFBook.BookState.OPEN, "leaf": 3}
		book._state = PDFBook.BookState.OPEN
		zone.pick_up_object(book)
		await get_tree().physics_frame
		await get_tree().physics_frame
		var shut := book._state == PDFBook.BookState.CLOSED \
			or int(book._pending_page.get("state", -1)) == PDFBook.BookState.CLOSED
		_ok(c.manual() == book and shut, "%s: an open book is shut as it is seated" % fam[0],
			"%s %s" % [book._state, str(book._pending_page)])


func _case_lid_world() -> void:
	var c := _new_case("jewel", "single")
	await get_tree().physics_frame
	c.global_transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(40.0, 1.0, 0.0))   # on its back, far off
	c.sim.set_angle_deg(c.sim.top(), 90.0)
	c._apply_angles()
	await get_tree().physics_frame
	_ok(not c._lid_blocked(90.0), "nothing near: the lid is clear")
	_ok(not c._lid_gives_way(), "and stays")
	# A block standing in the upright lid, a little to its opening side: the lid gives way toward shut.
	var block := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.02, 0.04, 0.2)
	shape.shape = box
	block.add_child(shape)
	block.collision_layer = c.collision_mask & -c.collision_mask      # one layer the case collides with
	add_child(block)
	_spawned.append(block)
	var lid_mid := c.global_transform * (c._lid_pivot + Vector3(0.0, 0.0, c._lid_box.size.x * 0.6))
	block.global_position = lid_mid + c.global_basis.x * -0.009        # behind the lid: its outside
	await get_tree().physics_frame
	_ok(c._lid_blocked(90.0), "a block in the lid where it stood")
	for _k in 4:
		await get_tree().physics_frame
	_ok(c.lid_deg() < 89.5 and c.lid_deg() > 70.0 and not c._lid_blocked(c.lid_deg()),
		"pushed from outside, it turns toward shut, just clear", str(c.lid_deg()))
	block.global_position = lid_mid + c.global_basis.x * 0.2           # away
	await get_tree().physics_frame
	c.sim.push_to_deg(c.sim.top(), 90.0)
	c._apply_angles()
	block.global_position = lid_mid + c.global_basis.x * 0.009         # inside the lid: its inside face
	for _k in 5:
		await get_tree().physics_frame
	_ok(c.lid_deg() > 90.5 and c.lid_deg() < 110.0 and not c._lid_blocked(c.lid_deg()), "pushed from inside, it turns open", str(c.lid_deg()))
	_ok(c.lid_deg() <= rad_to_deg(c.sim.open_max) + 0.01, "never past its stop")
	# A caught lid gives to nothing.
	block.global_position = lid_mid + c.global_basis.x * 0.3
	c.sim.set_angle_deg(c.sim.top(), 0.0)
	c.sim.latched = true
	_ok(not c._lid_gives_way(), "a caught lid gives to nothing")
	# The fingertip's panel: the whole lid, both faces, pushed only.
	for i in c.sim.count:
		var hinge := c.hinge(i)
		var panel := hinge.get_node_or_null("PokePanel") as CollisionShape3D
		_ok(panel != null and panel.disabled and bool(panel.get_meta(&"poke_surface", false)), "hinge %d has a fingertip panel" % i)
		_ok(hinge.poke_torque_faces == (VRHinge.FACE_Y_NEG | VRHinge.FACE_Y_POS) and hinge.poke_push_only, "both faces, pushed only")
		_ok(panel in hinge._poke_shapes() and hinge._grab_box() != panel, "the panel is what a fingertip meets; the grab box is still the grab box")
	var lid_panel := c.hinge(c.sim.top()).get_node("PokePanel") as CollisionShape3D
	_ok((lid_panel.shape as BoxShape3D).size.z > c._lid_box.size.x * 0.99, "the lid's panel is the lid's whole reach",
		str((lid_panel.shape as BoxShape3D).size))


func _case_held_by_lid() -> void:
	# The sim: the base hangs from a lid held level, front up; with gravity along the base it hangs still.
	var s := _jewel_sim()
	s.base_swings = true
	s.latched = false
	_ok(s.pull(0, G_FACE_UP) > 0.0, "under a lid held front up, the base falls away (opens)")
	_ok(absf(s.pull(0, Vector3(9.81, 0.0, 0.0))) < 1e-6, "hanging straight down, nothing turns it")
	_ok(s.pull(0, G_FACE_DOWN) < 0.0, "front down, it falls shut")
	_run_sim(s, G_FACE_UP, 0.3)
	_ok(s.angle_deg(0) > 5.0, "and it does", str(s.angle_deg(0)))
	for fam: Array in [["jewel", "single"], ["keep", "ps2"]]:
		var c := _new_case(fam[0], fam[1])
		await get_tree().physics_frame
		c.global_transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(60.0, 1.0, 0.0))
		var lid_mid := c._lid_box.get_center()
		_ok(not c._on_lid(lid_mid), "%s: shut, a grip is the case's" % fam[0])
		c.sim.set_angle_deg(c.sim.top(), 120.0)
		c._apply_angles()
		_ok(c._on_lid(c._lid_swing() * lid_mid), "%s: open, a hand on the lid has it by the lid" % fam[0])
		_ok(not c._on_lid(c._base_box.get_center() + Vector3(0.02, 0.0, 0.0)), "%s: a hand on the base has the base" % fam[0])
		# The hand's place, kept in the lid's frame: as the angle changes, the grab moves the BASE and leaves the lid.
		var hand := c.global_transform * c._lid_swing() * Transform3D(Basis(Vector3.UP, 0.4), lid_mid + Vector3(0.0, 0.01, 0.02))
		var lid_then := c.global_transform * c._lid_in_case()
		c._lid_hand = c._lid_swing().affine_inverse() * (c.global_transform.affine_inverse() * hand)
		for deg: float in [60.0, 170.0, 30.0]:
			c.sim.set_angle_deg(c.sim.top(), deg)
			c._apply_angles()
			var body := hand * (c._lid_swing() * c._lid_hand).affine_inverse()      # where the grab driver puts the case
			var lid_now := body * c._lid_in_case()
			_ok(lid_now.origin.distance_to(lid_then.origin) < 1e-4 and lid_now.basis.is_equal_approx(lid_then.basis),
				"%s: at %d degrees the lid has not moved in the hand" % [fam[0], int(deg)],
				str(lid_now.origin - lid_then.origin))
			_ok(not body.basis.is_equal_approx(c.global_transform.basis) or absf(deg - 120.0) < 0.1,
				"%s: the base has turned instead" % fam[0])


## A stand-in for a hand: what XRToolsPickable.pick_up reads of whoever takes it.
class StandInHand extends Node3D:
	var picked_up_ranged := false


func _stand_in_hand(at: Transform3D) -> StandInHand:
	var hand := StandInHand.new()
	add_child(hand)
	_spawned.append(hand)
	hand.global_transform = at
	return hand


## A block in the way: thin along world y unless `size` says otherwise, on a layer the case collides with.
func _block(c: RetroGameCase, at: Vector3, size := Vector3(0.04, 0.02, 0.2)) -> StaticBody3D:
	var block := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	block.add_child(shape)
	block.collision_layer = c.original_collision_mask & -c.original_collision_mask
	add_child(block)
	_spawned.append(block)
	block.global_position = at
	return block


## A four-page comic archive, two wide by three tall: a manual with pages to turn.
## A manual of four pages, each `w` by `h` px (a jewel booklet's are square; a spread scan's twice as wide).
func _manual_of(w: int, h: int) -> String:
	var path := OS.get_user_data_dir().path_join("__game_case_manual_%dx%d.cbz" % [w, h])
	var zip := ZIPPacker.new()
	zip.open(path)
	for i in 4:
		var img := Image.create(w, h, false, Image.FORMAT_RGB8)
		img.fill(Color(0.2 * i, 0.5, 0.5))
		zip.start_file("page_%02d.png" % i)
		zip.write_file(img.save_png_to_buffer())
		zip.close_file()
	zip.close()
	return path


## A book as it lies about the room (25 cm tall, not the booklet's height) put into a case by hand.
func _put_in(c: RetroGameCase, pdf: String) -> PDFBook:
	var book := BOOK_SCENE.instantiate() as PDFBook
	book.freeze = true
	book.pdf_path = pdf
	add_child(book)
	book.add_to_group("spawned")
	_spawned.append(book)
	for _i in 3:
		await get_tree().process_frame
	for _i in 300:
		if book._pending_renders.is_empty():
			break
		await get_tree().process_frame
	c._manual_zone.pick_up_object(book)
	# The case looks again 0.6 s after a book goes in (once it has shut).
	await get_tree().create_timer(0.9).timeout
	for _i in 4:
		await get_tree().process_frame
	return book


func _case_manual_spread() -> void:
	var jewel := Vector2(0.12, 0.12)
	var keep := Vector2(0.12, 0.18)
	_ok(not RetroGameCase.is_spread(Vector2(0.25, 0.25), jewel), "a square manual in the hand (25 cm) is no spread for a jewel booklet")
	_ok(not RetroGameCase.is_spread(Vector2(0.12, 0.12), jewel), "nor at the booklet's own size")
	_ok(RetroGameCase.is_spread(Vector2(0.5, 0.25), jewel) and RetroGameCase.is_spread(Vector2(0.24, 0.12), jewel),
		"two square pages side by side are, at either size")
	_ok(not RetroGameCase.is_spread(Vector2(0.158, 0.25), keep), "a keep case's tall manual (1023 x 1620) is no spread")
	_ok(RetroGameCase.is_spread(Vector2(0.297, 0.25), keep), "Mario Kart: Double Dash's (1248 x 1050, two pages a sheet) is")
	_ok(not RetroGameCase.is_spread(Vector2(0.25, 0.25), keep), "a square manual in a tall case is not split in two")
	_ok(not RetroGameCase.is_spread(Vector2.ZERO, jewel) and not RetroGameCase.is_spread(jewel, Vector2.ZERO), "nothing to judge by, no spread")
	# Put in by hand, at the size it lies about the room.
	var c := _new_case("jewel", "single")
	await get_tree().physics_frame
	c.global_position = Vector3(260.0, 1.0, 0.0)
	c.set_physics_process(false)
	c.sim.set_angle_deg(c.sim.top(), 120.0)
	c._apply_angles()
	var square := await _put_in(c, _manual_of(30, 30))
	_ok(square.page_size().x > c.model.manual_size_m().x * 1.4, "(the book in hand is wider than the booklet, as the old rule read it)",
		str(square.page_size()))
	_ok(c.manual() == square and not square.half_page_mode, "a single-page manual put in by hand keeps its pages whole")
	c._manual_zone.drop_object()
	for _i in 3:
		await get_tree().physics_frame
	square.global_position += Vector3(0.0, 5.0, 0.0)
	var spread := await _put_in(c, _manual_of(60, 30))
	_ok(c.manual() == spread and spread.half_page_mode, "a manual scanned two pages a sheet is read in half pages")


func _manual_fixture() -> String:
	var path := OS.get_user_data_dir().path_join("__game_case_manual.cbz")
	var zip := ZIPPacker.new()
	zip.open(path)
	for i in 4:
		var img := Image.create(20, 30, false, Image.FORMAT_RGB8)
		img.fill(Color(0.2 * i, 0.5, 0.5))
		zip.start_file("page_%02d.png" % i)
		zip.write_file(img.save_png_to_buffer())
		zip.close_file()
	zip.close()
	return path


func _seat_manual(c: RetroGameCase) -> PDFBook:
	var book := BOOK_SCENE.instantiate() as PDFBook
	book.freeze = true
	book.book_height = c.model.manual_size_m().y
	book.pdf_path = _manual_fixture()
	add_child(book)
	book.add_to_group("spawned")
	_spawned.append(book)
	for _i in 3:
		await get_tree().process_frame
	for _i in 3:
		await get_tree().physics_frame
	for _i in 300:
		if book._pending_renders.is_empty():
			break
		await get_tree().process_frame
	c._manual_zone.pick_up_object(book)
	for _i in 4:
		await get_tree().physics_frame
	for _i in 2:
		await get_tree().process_frame
	return book


## A real XRToolsFunctionPickup on a controller, its grip point at `at`.
func _grip_at(at: Vector3) -> XRToolsFunctionPickup:
	var ctrl := XRController3D.new()
	add_child(ctrl)
	_spawned.append(ctrl)
	var pickup := PICKUP_SCENE.instantiate() as XRToolsFunctionPickup
	pickup.name = "FunctionPickup"
	ctrl.add_child(pickup)
	ctrl.global_position = at
	await get_tree().physics_frame
	ctrl.global_position = at - (pickup.global_position - ctrl.global_position)
	for _i in 5:
		await get_tree().physics_frame
	pickup._update_closest_object()
	return pickup


## Take that hand away: off out of reach, and its hover with it.
func _ungrip(pickup: XRToolsFunctionPickup) -> void:
	(pickup.get_parent() as Node3D).global_position += Vector3(0.0, 5.0, 0.0)
	for _i in 4:
		await get_tree().physics_frame
	pickup._update_closest_object()


func _on_its_back(c: RetroGameCase, x: float) -> void:
	c.global_transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(x, 1.0, 0.0))


func _case_base_handle() -> void:
	var x := 80.0
	# The handles turn about one line; a keep case's cover turns on two creases, so there a still fingertip reads a
	# few degrees off over a wide swing (as its lid's own handle always has): bounded, no creep.
	for fam: Array in [["jewel", "single", 0.2], ["keep", "ps2", 6.0]]:
		x += 3.0
		var c := _new_case(fam[0], fam[1])
		await get_tree().physics_frame
		_on_its_back(c, x)
		var top := c.sim.top()
		var lid := c.hinge(top)
		var base := c._base_hinge
		_ok(base != null and base.target != null and not c._rigs.any(func(r: Array) -> bool: return r[2] == base),
			"%s: the base has a handle of its own, outside the sim's own" % fam[0])
		var on_base := Transform3D()
		for deg: float in [0.0, 40.0, 95.0, 150.0]:
			c.sim.set_angle_deg(top, deg)
			c._apply_angles()
			var rel := c.global_transform.affine_inverse() * (base.target as Node3D).global_transform
			if deg == 0.0:
				on_base = rel
			_ok(rel.origin.distance_to(on_base.origin) < 1e-4 and rel.basis.is_equal_approx(on_base.basis),
				"%s: at %d degrees the base's handle is still on the base" % [fam[0], int(deg)], str(rel.origin - on_base.origin))
			_ok(absf(base.get_rotation_deg() - deg) < 0.01, "%s: and reads the hinge's own angle" % fam[0],
				str(base.get_rotation_deg()))
		# Held by the lid, the lid is still and the base moves. A still fingertip must read still.
		c.sim.set_angle_deg(top, 100.0)
		c._apply_angles()
		var hand := c.global_transform * c._lid_swing() * Transform3D(Basis.IDENTITY, c._lid_box.get_center())
		c._lid_hand = c._lid_swing().affine_inverse() * (c.global_transform.affine_inverse() * hand)
		var tip := c.global_transform * (c._base_box.get_center() + Vector3(c._base_box.size.x * 0.2, 0.0, 0.0))
		var base_was := base._angle_at(tip, 100.0)
		var lid_was := lid._angle_at(tip, 0.0)
		c.sim.set_angle_deg(top, 130.0)
		c._apply_angles()
		c.global_transform = hand * (c._lid_swing() * c._lid_hand).affine_inverse()
		var base_now := base._angle_at(tip, base_was)
		var lid_now := lid._angle_at(tip, lid_was)
		_ok(absf(base_now - base_was) < float(fam[2]), "%s: by the base's handle a still fingertip reads still as the base turns 30" % fam[0],
			"%f -> %f" % [base_was, base_now])
		_ok(absf(absf(lid_now - lid_was) - 30.0) < float(fam[2]) + 0.2,
			"%s: by the lid's own it reads as having moved 30 degrees (the creep)" % fam[0], "%f -> %f" % [lid_was, lid_now])
		# The gates: whichever half is free to move has the live handle.
		_on_its_back(c, x)
		c.sim.set_angle_deg(top, 100.0)
		c._apply_angles()
		_ok(lid._can_engage() and not base._can_engage(), "%s: in nobody's hand the lid's handle works, the base's does not" % fam[0])
		lid._pointer_held = true
		var holder := _stand_in_hand(c.global_transform * Transform3D(Basis.IDENTITY, c._lid_swing() * c._lid_box.get_center()))
		c.pick_up(holder)
		_ok(c.held_by_lid(), "%s: gripped on its open lid" % fam[0])
		_ok(not lid._can_engage() and base._can_engage(), "%s: held by the lid, the base's handle works and the lid's does not" % fam[0])
		_ok(not lid.is_held(), "%s: a hold on the lid's handle from before the grip is dropped" % fam[0])
		base._pointer_held = true
		(base.target as Node3D).rotation.x = deg_to_rad(60.0)
		for _i in 3:
			await get_tree().physics_frame
		_ok(absf(c.lid_deg() - 60.0) < 0.2 and absf(lid.get_rotation_deg() - 60.0) < 0.2,
			"%s: the base's handle held at 60 has the hinge at 60, by both handles" % fam[0],
			"%f %f" % [c.lid_deg(), lid.get_rotation_deg()])
		base._pointer_held = false
		c.let_go(holder, Vector3.ZERO, Vector3.ZERO)
		await get_tree().physics_frame
		_ok(not c.held_by_lid() and lid._can_engage() and not base._can_engage(), "%s: let go, the lid's handle has it again" % fam[0])
		# Over a disc on the base a fingertip is reaching for the disc; at the base's back it presses the base.
		var disc_on := DISC_SCENE.instantiate() as RetroDisc
		disc_on.systemid = "psx"
		add_child(disc_on)
		_spawned.append(disc_on)
		c.disc_zone(0).pick_up_object(disc_on)
		await get_tree().physics_frame
		var hub := c.disc_zone(0).global_position
		var out_of_hub := c.disc_zone(0).global_basis.y.normalized()
		_ok(c._base_quiet(hub + out_of_hub * 0.01) and base._quiet(hub + out_of_hub * 0.01),
			"%s: over a seated disc the base's handle is quiet" % fam[0])
		_ok(not c._base_quiet(hub - out_of_hub * 0.012), "%s: behind it, at the base's back, a fingertip presses the base" % fam[0])
		c.disc_zone(0).drop_object()
		await get_tree().physics_frame
		_ok(not c._base_quiet(hub + out_of_hub * 0.01), "%s: and with the disc gone the whole base is pressed" % fam[0])
		# A save from before the base's handle has the lid's record alone; a peer may move either.
		x += 3.0
		var old := _new_case(fam[0], fam[1])
		await get_tree().physics_frame
		old.global_position = Vector3(x, 1.0, 0.0)
		old.hinge(old.sim.top()).set_rotation_deg_remote(120.0)
		for _i in 3:
			await get_tree().physics_frame
		_ok(absf(old.lid_deg() - 120.0) < 0.5 and absf(old._base_hinge.get_rotation_deg() - 120.0) < 0.5,
			"%s: restored by the lid's record alone it opens, and the base's handle follows" % fam[0],
			"%f %f" % [old.lid_deg(), old._base_hinge.get_rotation_deg()])
		old._base_hinge.set_rotation_deg_remote(45.0)
		for _i in 3:
			await get_tree().physics_frame
		_ok(absf(old.lid_deg() - 45.0) < 0.5 and absf(old.hinge(old.sim.top()).get_rotation_deg() - 45.0) < 0.5,
			"%s: a peer moving the base's handle moves the hinge" % fam[0], str(old.lid_deg()))


func _case_world_held() -> void:
	# In a hand a case's mask is 0: its lid must still find what is in its way.
	var c := _new_case("jewel", "single")
	await get_tree().physics_frame
	_on_its_back(c, 110.0)
	var top := c.sim.top()
	c.sim.set_angle_deg(top, 90.0)
	c._apply_angles()
	c.pick_up(_stand_in_hand(c.global_transform))
	await get_tree().physics_frame
	_ok(c.is_picked_up() and c.collision_mask == 0 and not c.held_by_lid(), "held by its base, its mask is 0")
	var lid_mid := c.global_transform * (c._lid_pivot + Vector3(0.0, 0.0, c._lid_box.size.x * 0.6))
	_block(c, lid_mid + c.global_basis.x * -0.009, Vector3(0.02, 0.04, 0.2))
	await get_tree().physics_frame
	_ok(c._lid_blocked(90.0), "a block in the lid of a held case is seen")
	for _i in 4:
		await get_tree().physics_frame
	_ok(c.lid_deg() < 89.5 and c.lid_deg() > 70.0 and not c._lid_blocked(c.lid_deg()), "and the lid gives way to it",
		str(c.lid_deg()))
	# Held by the lid, it is the base that gives way, and the lid stays in the hand.
	var k := _new_case("keep", "ps2")
	await get_tree().physics_frame
	_on_its_back(k, 113.0)
	var ktop := k.sim.top()
	k.sim.set_angle_deg(ktop, 100.0)
	k._apply_angles()
	k.pick_up(_stand_in_hand(k.global_transform * Transform3D(Basis.IDENTITY, k._lid_swing() * k._lid_box.get_center())))
	await get_tree().physics_frame
	_ok(k.held_by_lid(), "a keep case gripped by its cover")
	var lid_then := k.global_transform * k._lid_in_case()
	_ok(not k._lid_blocked(k.lid_deg()), "nothing in the base's way yet")
	_block(k, k.global_transform * (k._base_box.get_center()
		+ Vector3(k._base_box.size.x * 0.25, 0.0, -(k._base_box.size.z * 0.5 + 0.01 - 0.003))))
	for _i in 8:
		await get_tree().physics_frame
	_ok(absf(k.lid_deg() - 100.0) > 0.5 and not k._lid_blocked(k.lid_deg()), "a block under the base turns the base clear of it",
		str(k.lid_deg()))
	var lid_now := k.global_transform * k._lid_in_case()
	_ok(lid_now.origin.distance_to(lid_then.origin) < 0.002, "and the cover has not moved in the hand",
		str(lid_now.origin - lid_then.origin))
	# In a seat, or weightless while a save is put back, nothing gives way.
	var r := _new_case("jewel", "single")
	await get_tree().physics_frame
	_on_its_back(r, 116.0)
	r.sim.set_angle_deg(r.sim.top(), 90.0)
	r._apply_angles()
	var r_mid := r.global_transform * (r._lid_pivot + Vector3(0.0, 0.0, r._lid_box.size.x * 0.6))
	r.collision_mask = 0
	_block(r, r_mid + r.global_basis.x * -0.009, Vector3(0.02, 0.04, 0.2))
	for _i in 4:
		await get_tree().physics_frame
	_ok(absf(r.lid_deg() - 90.0) < 0.01, "a case with no mask and no holder (a save being put back) leaves its lid alone",
		str(r.lid_deg()))


func _case_manual_reach() -> void:
	var x := 130.0
	for fam: Array in [["jewel", "single"], ["keep", "ps2"]]:
		x += 3.0
		var c := _new_case(fam[0], fam[1])
		await get_tree().physics_frame
		c.global_position = Vector3(x, 1.0, 0.0)             # on its bottom edge: gravity along the hinge, the lid stays put
		var top := c.sim.top()
		c.sim.set_angle_deg(top, 110.0)
		c._apply_angles()
		var book := await _seat_manual(c)
		_ok(book._page_count == 4 and c.manual() == book, "%s: a manual with pages, seated" % fam[0], str(book._page_count))
		var zone := c._manual_zone
		var seat := c.model.manual_seat()
		var size := book.page_size()
		var inward := seat.global_basis.z.normalized() * c._manual_in
		var across := seat.global_basis.x.normalized()
		var up := seat.global_basis.y.normalized()
		var mid := seat.global_position
		_ok(absf(c.lid_deg() - 110.0) < 0.01, "%s: (the lid stands where it was put)" % fam[0], str(c.lid_deg()))
		_ok(inward.dot(c.global_transform * c._swing_at(c.lid_deg()) * c._lid_box.get_center() - mid) < 0.0,
			"%s: into the case is away from the lid's own plastic" % fam[0])
		_ok(zone.reaches(mid + inward * 0.02) >= 0.0, "%s: a grip 2 cm over the booklet's middle is for the manual" % fam[0])
		_ok(zone.reaches(mid + inward * 0.02 + across * size.x * 0.45) >= 0.0, "%s: and over its far edge" % fam[0])
		_ok(zone.reaches(mid + inward * 0.02 - across * size.x * 0.45 + up * size.y * 0.45) >= 0.0, "%s: and over a corner" % fam[0])
		_ok(zone.reaches(mid) >= 0.0, "%s: and inside the booklet itself" % fam[0])
		_ok(zone.reaches(mid + inward * 0.05) >= 0.0 and zone.reaches(mid + inward * 0.09) < 0.0,
			"%s: 5 cm above it yes, 9 cm no" % fam[0])
		_ok(zone.reaches(mid - inward * 0.012) < 0.0, "%s: not behind it: that is the lid" % fam[0])
		_ok(zone.reaches(mid + inward * 0.02 + across * (size.x * 0.5 + 0.03)) < 0.0, "%s: nor 3 cm beside it" % fam[0])
		# The reach is the space OVER the booklet: with the lid leaning over the base it stops at the base.
		c.sim.set_angle_deg(top, 40.0)
		c._apply_angles()
		var mid40 := seat.global_position
		var in40 := seat.global_basis.z.normalized() * c._manual_in
		var across40 := seat.global_basis.x.normalized()
		var out40 := signf(across40.dot(c.hinge(top).global_position - mid40))
		var under := mid40 - across40 * out40 * size.x * 0.45 + in40 * 0.05
		_ok(zone.reach_box.has_point(zone.global_transform.affine_inverse() * under),
			"%s: (a point 5 cm off the booklet's hinge side, inside the plain box)" % fam[0])
		_ok(not c._clear_of_base(under) and zone.reaches(under) < 0.0,
			"%s: with the lid at 40 degrees that point is under the base: not a reach for the manual" % fam[0],
			str(c.global_transform.affine_inverse() * under))
		_ok(zone.reaches(mid40 + in40 * 0.008) >= 0.0, "%s: just over the booklet still is" % fam[0])
		var dz := c.disc_zone(0)
		var disc_on := DISC_SCENE.instantiate() as RetroDisc
		disc_on.systemid = "psx"
		add_child(disc_on)
		_spawned.append(disc_on)
		dz.pick_up_object(disc_on)
		for _i in 3:
			await get_tree().physics_frame
		# Lid at 40: the booklet leans over the disc. Of the two, a grip takes the one it is nearer.
		var hub := dz.global_position
		var hub_out := dz.global_basis.y.normalized()
		var near_book := mid40 + in40 * 0.015
		var pickup40 := await _grip_at(near_book)
		_ok(pickup40.closest_object == zone or hub.distance_to(near_book) < 0.015,
			"%s: 1.5 cm over the booklet, a real grip ranks the manual though the hub's ball reaches there" % fam[0],
			"%s, hub %.3f away" % [pickup40.closest_object, hub.distance_to(near_book)])
		await _ungrip(pickup40)
		pickup40 = await _grip_at(hub + hub_out * 0.008)
		_ok(pickup40.closest_object == dz, "%s: at the hub it ranks the disc" % fam[0], str(pickup40.closest_object))
		await _ungrip(pickup40)
		# Nothing is reached from behind its own panel: under the base is the case's to grip.
		_ok(dz.reaches(hub + hub_out * 0.02) >= 0.0 and dz.reaches(hub - hub_out * 0.03) < 0.0,
			"%s: a hub is reached from its own side, not from under the base" % fam[0])
		pickup40 = await _grip_at(hub - hub_out * 0.03)
		_ok(pickup40.closest_object == c, "%s: a real grip 3 cm under the hub ranks the case" % fam[0], str(pickup40.closest_object))
		await _ungrip(pickup40)
		dz.drop_object()
		for _i in 2:
			await get_tree().physics_frame
		disc_on.global_position += Vector3(0.0, 9.0, 0.0)
		c.sim.set_angle_deg(top, 110.0)
		c._apply_angles()
		_ok(dz.reach_box.size == Vector3.ZERO and dz.reaches(dz.global_position + Vector3(0.03, 0.0, 0.0)) >= 0.0
			and dz.reaches(dz.global_position + Vector3(0.07, 0.0, 0.0)) < 0.0, "%s: a hub's reach is the ball it was, on its own side" % fam[0])
		# A real grip.
		var pickup := await _grip_at(mid + inward * 0.02 + across * size.x * 0.3)
		_ok(pickup.closest_object == zone, "%s: a real grip over the booklet, off its spine, ranks the manual" % fam[0],
			str(pickup.closest_object))
		_ok(c._manual_rim != null and c._manual_rim.visible, "%s: and the rim round the booklet lights" % fam[0])
		await _ungrip(pickup)
		_ok(c._manual_rim != null and not c._manual_rim.visible, "%s: and goes out as the hand leaves" % fam[0])
		pickup = await _grip_at(mid - inward * 0.03)
		_ok(pickup.closest_object == c, "%s: a grip behind the lid ranks the case" % fam[0], str(pickup.closest_object))
		await _ungrip(pickup)
		# The zones follow their seats' reach, so a grip at a shut case takes the case and lets nothing go.
		_ok(zone.enabled and dz.enabled, "%s: open, its zones are on" % fam[0])
		var disc := DISC_SCENE.instantiate() as RetroDisc
		disc.systemid = "psx"
		add_child(disc)
		_spawned.append(disc)
		dz.pick_up_object(disc)
		c.sim.set_angle_deg(top, 0.0)
		c.sim.latched = true
		c._apply_angles()
		for _i in 3:
			await get_tree().physics_frame
		_ok(not zone.enabled and not dz.enabled and c.manual() == book and dz.picked_up_object == disc,
			"%s: shut, its zones are off and still hold what they held" % fam[0])
		pickup = await _grip_at(dz.global_position + c.global_basis.z.normalized() * 0.02)
		_ok(pickup.closest_object == c, "%s: a grip at a shut case's hub ranks the case" % fam[0], str(pickup.closest_object))
		pickup._pick_up_object(pickup.closest_object)
		for _i in 3:
			await get_tree().physics_frame
		_ok(pickup.picked_up_object == c and dz.picked_up_object == disc and c.manual() == book,
			"%s: and takes the case, its disc and manual still seated" % fam[0], str(pickup.picked_up_object))
		pickup.drop_object()


func _case_manual_quiet() -> void:
	var x := 150.0
	for fam: Array in [["jewel", "single"], ["keep", "ps2"]]:
		x += 3.0
		var c := _new_case(fam[0], fam[1])
		await get_tree().physics_frame
		c.global_position = Vector3(x, 1.0, 0.0)             # on its bottom edge: gravity along the hinge, the lid stays put
		var top := c.sim.top()
		c.sim.set_angle_deg(top, 110.0)
		c._apply_angles()
		var book := await _seat_manual(c)
		var right := book.get_node("PageGrabRight") as PageGrab
		_ok(book.pages_locked() and not book.visible and not right._enabled, "%s: seated, the manual is hidden and its pages locked" % fam[0])
		book._on_page_grab_begin(1, book.global_position)
		_ok(book._grab_dir == 0, "%s: a grab at its page begins nothing" % fam[0])
		var lid := c.hinge(top)
		var seat := c.model.manual_seat()
		var size := book.page_size()
		var inward := seat.global_basis.z.normalized() * c._manual_in
		var across := seat.global_basis.x.normalized()
		var mid := seat.global_position
		var out := signf(across.dot(lid.global_position - mid))     # toward the lid's free edge
		var over := mid + inward * 0.01 + across * out * size.x * 0.3
		_ok(lid.global_position.distance_to(over) < lid.engage_radius, "%s: (a point over the booklet inside the trigger's reach)" % fam[0],
			str(lid.global_position.distance_to(over)))
		_ok(lid._quiet(over) and not lid._tip_in_activation_region(over) and not lid.accepts_pointer_at(over),
			"%s: over the booklet the lid's handle takes no trigger, shows no hand, takes no click" % fam[0])
		_ok(not lid._quiet(mid - inward * 0.012), "%s: behind the booklet, outside the lid, it is the lid's" % fam[0])
		var edge := lid.global_position - lid.global_basis.z.normalized() * 0.04 - inward * 0.005
		_ok(lid._tip_in_activation_region(edge), "%s: and at the lid's free edge the trigger still has it" % fam[0],
			"%s quiet %s" % [lid.global_position.distance_to(edge), lid._quiet(edge)])
		book.highlight_updated.emit(book, true)
		_ok(c._manual_rim != null and c._manual_rim.visible, "%s: hovered, the rim shows" % fam[0])
		book.highlight_updated.emit(book, false)
		_ok(not c._manual_rim.visible, "%s: and hides" % fam[0])
		# Under a lid leaning over the base the quiet stops at the base, and a shut case has none at all.
		c.sim.set_angle_deg(top, 40.0)
		c._apply_angles()
		var in40 := seat.global_basis.z.normalized() * c._manual_in
		var across40 := seat.global_basis.x.normalized()
		var out40 := signf(across40.dot(lid.global_position - seat.global_position))
		var under := seat.global_position - across40 * out40 * size.x * 0.45 + in40 * 0.05
		_ok(lid._quiet(seat.global_position + in40 * 0.008) and not lid._quiet(under),
			"%s: at 40 degrees the lid is quiet over the booklet and not under the base" % fam[0])
		c.sim.set_angle_deg(top, 0.0)
		c.sim.latched = true
		c._apply_angles()
		_ok(not lid._quiet(seat.global_position + seat.global_basis.z.normalized() * c._manual_in * 0.008)
			and not lid._quiet(c.global_transform * c._base_box.get_center()),
			"%s: shut, nothing about the lid is quiet: it is opened as ever" % fam[0])
		c.sim.set_angle_deg(top, 110.0)
		c._apply_angles()
		# The desktop: a click anywhere on the booklet, from inside the case, takes the manual.
		var grabber := Node3D.new()
		add_child(grabber)
		_spawned.append(grabber)
		var space := c.get_world_3d().direct_space_state
		for part: float in [0.0, 0.3, -0.3]:
			var p := mid + across * out * size.x * part
			var t := InteractionResolver.resolve_desktop(space, p + inward * 0.25, p - inward * 0.03, grabber)
			_ok(t.is_valid() and t.highlight_node == book, "%s: the desktop takes the manual at %+.1f of its width" % [fam[0], part],
				"%s %s path %s script %s action %s" % [t.kind, t.highlight_node, t.highlight_node.get_path() if t.highlight_node != null else "",
					(t.highlight_node.get_script() as Script).resource_path if t.highlight_node != null and t.highlight_node.get_script() != null else "",
					t.action_node])
		# Taken out, it is a book again and the lid is the lid's.
		book.highlight_updated.emit(book, true)
		c._manual_zone.drop_object()
		for _i in 3:
			await get_tree().physics_frame
		for _i in 2:
			await get_tree().process_frame
		_ok(not book.pages_locked() and book.visible and right._enabled, "%s: taken out, it shows and its pages turn again" % fam[0])
		_ok(not c._manual_rim.visible, "%s: the rim goes with it" % fam[0])
		_ok(not lid._quiet(over) and lid._tip_in_activation_region(over), "%s: and the whole lid is the lid's again" % fam[0])


func _case_lift_out() -> void:
	_ok(HeldObjectPhysics.lift_out(null, null, 1, 0.06) == 0.0, "nothing to lift")
	var x := 170.0
	# A table as the game's are: a heavy rigid body on the pickable layer, not the room's own geometry.
	var table := RigidBody3D.new()
	var top_shape := CollisionShape3D.new()
	var top_box := BoxShape3D.new()
	top_box.size = Vector3(1.0, 0.04, 1.0)
	top_shape.shape = top_box
	table.add_child(top_shape)
	table.mass = 15.0
	table.gravity_scale = 0.0
	table.collision_layer = 4
	table.collision_mask = 0
	add_child(table)
	_spawned.append(table)
	table.global_position = Vector3(x, 0.98, 0.0)                # its top at y = 1
	var c := _new_case("jewel", "single")
	await get_tree().physics_frame
	_ok(c.dropped.is_connected(c._on_let_go), "a case is lifted out when it is let go")
	var bottom := -c._closed_box.position.z                       # lying on its back: its back this far under its origin
	c.global_transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(x, 1.0 + bottom - 0.005, 0.0))
	for _i in 2:
		await get_tree().physics_frame
	var moved := HeldObjectPhysics.lift_out(c, c._body_shape, c.original_collision_mask, 0.06)
	_ok(moved > 0.003 and moved < 0.008 and absf(c.global_position.y - (1.0 + bottom)) < 0.0015,
		"let go 5 mm into a tabletop, it is lifted onto it", "%f, at %f" % [moved, c.global_position.y - (1.0 + bottom)])
	for _i in 2:
		await get_tree().physics_frame
	_ok(HeldObjectPhysics.lift_out(c, c._body_shape, c.original_collision_mask, 0.06) == 0.0, "and then it is clear")
	var clear := c.global_transform
	_ok(c.global_transform.is_equal_approx(clear), "a clear case is not moved")
	# Too deep: left exactly where it was.
	c.global_transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(x + 0.2, 0.975, 0.0))
	var deep := c.global_transform
	for _i in 2:
		await get_tree().physics_frame
	_ok(HeldObjectPhysics.lift_out(c, c._body_shape, c.original_collision_mask, 0.01) == 0.0
		and c.global_transform.is_equal_approx(deep), "past its limit it is left where it was")
	# The room's own floor counts as a support too.
	var floor_body := _block(c, Vector3(x + 3.0, 0.98, 0.0), Vector3(1.0, 0.04, 1.0))
	floor_body.collision_layer = 1
	c.global_transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(x + 3.0, 1.0 + bottom - 0.004, 0.0))
	for _i in 2:
		await get_tree().physics_frame
	moved = HeldObjectPhysics.lift_out(c, c._body_shape, c.original_collision_mask, 0.06)
	_ok(moved > 0.002 and moved < 0.007, "4 mm into the floor, lifted onto it", str(moved))
	# Sideways into a wall: not this rule's to move.
	var wall := _block(c, Vector3(x + 6.0, 1.0, 0.0), Vector3(0.04, 1.0, 1.0))
	wall.collision_layer = 1
	c.global_transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5),
		Vector3(x + 6.0 - 0.02 - c._closed_box.end.x + 0.004, 1.3, 0.0))
	var at_wall := c.global_transform
	for _i in 2:
		await get_tree().physics_frame
	_ok(HeldObjectPhysics.lift_out(c, c._body_shape, c.original_collision_mask, 0.06) == 0.0
		and c.global_transform.is_equal_approx(at_wall), "4 mm into a wall it is left alone (the way out is not up)")
	# A light loose thing in its way holds nothing up; nor does what it holds on its own hub.
	var loose := RigidBody3D.new()
	var loose_shape := CollisionShape3D.new()
	var loose_box := BoxShape3D.new()
	loose_box.size = Vector3(0.12, 0.004, 0.12)
	loose_shape.shape = loose_box
	loose.add_child(loose_shape)
	loose.mass = 0.016
	loose.gravity_scale = 0.0
	loose.collision_layer = 4
	loose.collision_mask = 0
	add_child(loose)
	_spawned.append(loose)
	c.global_transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(x + 9.0, 1.0, 0.0))
	loose.global_position = Vector3(x + 9.0, 1.0 - bottom + 0.001, 0.0)
	var over_loose := c.global_transform
	for _i in 2:
		await get_tree().physics_frame
	_ok(HeldObjectPhysics.lift_out(c, c._body_shape, c.original_collision_mask, 0.06) == 0.0
		and c.global_transform.is_equal_approx(over_loose), "a light loose thing under it lifts nothing")
	var disc := DISC_SCENE.instantiate() as RetroDisc
	disc.systemid = "psx"
	add_child(disc)
	_spawned.append(disc)
	c.disc_zone(0).pick_up_object(disc)
	for _i in 3:
		await get_tree().physics_frame
	_ok(HeldObjectPhysics.lift_out(c, c._body_shape, c.original_collision_mask, 0.06) == 0.0, "nor the disc on its own hub")


func _case_tray_both_faces() -> void:
	var x := 200.0
	for fam: Array in [["jewel", "fatbox2"], ["jewel", "double"], ["jewel", "pal_multi2"], ["keep", "triple"], ["keep", "multi5"]]:
		x += 3.0
		var c := _new_case(fam[0], fam[1])
		await get_tree().physics_frame
		c.global_position = Vector3(x, 1.0, 0.0)
		# Lying shut: the tray's two faces as it is drawn, and its handle laid on the middle of them.
		var pivot := c.model.pivot_m("inner1")
		var slab := c._panel_slab(("FlipTray%d" if fam[0] == "jewel" else "Leaf%d") % 1, pivot.x + 0.07)
		_ok(slab.x < slab.y and slab.y - slab.x < 0.02, "%s/%s: the tray's two faces are found" % [fam[0], fam[1]], str(slab))
		_ok(absf((c.hinge(0).position.y + pivot.z) - (slab.x + slab.y) * 0.5) < 0.0005,
			"%s/%s: its handle lies on the tray's own middle, not on its hinge line (%.1f mm off it)" % [fam[0], fam[1],
			absf(c.hinge(0).position.y) * 1000.0], "%f vs %f" % [c.hinge(0).position.y + pivot.z, (slab.x + slab.y) * 0.5])
		for i in c._zones.size():
			var d := DISC_SCENE.instantiate() as RetroDisc
			d.systemid = "psx"
			add_child(d)
			_spawned.append(d)
			c.disc_zone(i).pick_up_object(d)
		var top := c.sim.top()
		c.sim.set_angle_deg(top, 180.0)
		c.sim.set_angle_deg(0, 90.0)                       # the tray standing between the two halves
		c.set_physics_process(false)
		c._apply_angles()
		for _i in 4:
			await get_tree().physics_frame
		c._apply_angles()
		var tray := c.hinge(0)
		var box := tray.get_node("CollisionShape3D") as CollisionShape3D
		var half := (box.shape as BoxShape3D).size.y * 0.5
		var panel := tray.get_node("PokePanel") as CollisionShape3D
		var panel_half := (panel.shape as BoxShape3D).size.y * 0.5
		# The handle lies on the tray as it is drawn: every disc on it is inside the fingertip's slab, and the grab
		# box stands most of a centimetre out past the disc on each face.
		var on_tray := 0
		for i in c._zones.size():
			if c._seat_carrier[i] != 0:
				continue
			on_tray += 1
			var in_box := box.global_transform.affine_inverse() * c.disc_zone(i).global_position
			var in_panel := panel.global_transform.affine_inverse() * c.disc_zone(i).global_position
			_ok(absf(in_box.y) + 0.0006 <= half - 0.008, "%s/%s: the grab box stands out past the disc on seat %d" % [fam[0], fam[1], i + 1],
				"disc %.4f from its middle, half %.4f" % [in_box.y, half])
			_ok(absf(in_panel.y) <= panel_half + 0.0005, "%s/%s: the fingertip's slab takes in the disc on seat %d" % [fam[0], fam[1], i + 1],
				"disc %.4f from its middle, half %.4f" % [in_panel.y, panel_half])
		_ok(half >= (slab.y - slab.x) * 0.5 + 0.009 and panel_half >= (slab.y - slab.x) * 0.5 - 0.0005,
			"%s/%s: the grab box stands a centimetre out of each face of the tray (%d discs on it)" % [fam[0], fam[1], on_tray],
			"half %.4f, panel %.4f, tray %.4f" % [half, panel_half, slab.y - slab.x])
		var grabber := Node3D.new()
		add_child(grabber)
		_spawned.append(grabber)
		var space := c.get_world_3d().direct_space_state
		var mid := box.global_position
		var normal := box.global_basis.y.normalized()
		for side: float in [1.0, -1.0]:
			var t := InteractionResolver.resolve_desktop(space, mid + normal * side * 0.2, mid - normal * side * 0.05, grabber)
			# Two flippers: the second stands a page's width in front of the first, and is what a click from there meets.
			var want := c.hinge(1) if side > 0.0 and c.sim.top() > 1 else tray
			_ok(t.is_valid() and t.action_node == want, "%s/%s: from its %s face a click on its free edge takes %s" % [
				fam[0], fam[1], "upper" if side > 0.0 else "under", "the tray's hinge" if want == tray else "the flipper in front's"],
				"%s %s" % [t.kind, t.action_node])


## The five-disc keep case's two flippers turn like pages. The model drew that and the sim did not: raised by a
## hand, the lower flipper was drawn 15 degrees behind its handle, its fingertip panel and its discs' reach.
func _case_pages_drawn_as_held() -> void:
	var c := _new_case("keep", "multi5")
	await get_tree().physics_frame
	c.global_position = Vector3(230.0, 1.0, 0.0)
	c.set_physics_process(false)
	c._apply_angles()
	var top := c.sim.top()
	_ok(top == 2, "the five-disc case has two flippers under its cover", str(top))
	# A point at each flipper's free edge, as the drawn flipper carries it and as its handle's rig does.
	var leaves: Array[Node3D] = []
	var in_leaf: Array[Vector3] = []
	var out := Vector3(0.0, 0.0, -0.10)
	for i in top:
		var leaf := c.model.levels[0].find_child("Leaf%d" % (i + 1), true, false) as Node3D
		leaves.append(leaf)
		in_leaf.append(leaf.global_transform.affine_inverse() * ((c.hinge(i).get_parent() as Node3D).global_transform * out))
	c.sim.set_angle_deg(top, 180.0)
	for pose: Array in [[0, 40.0], [0, 120.0], [1, 150.0], [1, 20.0], [0, 6.0], [1, 0.0]]:
		c.sim.set_angle_deg(int(pose[0]), float(pose[1]))
		c._apply_angles()
		for i in top:
			var drawn := leaves[i].global_transform * in_leaf[i]
			var held := (c.hinge(i).get_parent() as Node3D).global_transform * out
			_ok(drawn.distance_to(held) < 0.001, "flipper %d set to %d: flipper %d is drawn where its handle is (%.1f and %.1f)" % [
				int(pose[0]) + 1, int(pose[1]), i + 1, c.sim.angle_deg(0), c.sim.angle_deg(1)],
				"%.1f mm apart" % (drawn.distance_to(held) * 1000.0))
	_ok(is_equal_approx(c.hinge(0).max_deg, GameCaseModel.LEAF_STAND) and c.hinge(1).max_deg > 170.0,
		"the lower flipper's handle stops where the flipper does", "%f %f" % [c.hinge(0).max_deg, c.hinge(1).max_deg])


## A stand-in box-texture: a back panel to `back_end` (a marked band down its last 14 px), a white spine strip to
## `spine_end` with a black block at its head, a green front. `h` tall, the widths scaled with it.
func _scan(w: int, h: int, back_end: int, spine_end: int) -> Image:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGB8)
	img.fill(Color(0.1, 0.55, 0.2))
	img.fill_rect(Rect2i(0, 0, back_end, h), Color(0.75, 0.3, 0.35))
	img.fill_rect(Rect2i(back_end - 14, 0, 14, h), Color(0.9, 0.8, 0.1))
	if spine_end > back_end:
		img.fill_rect(Rect2i(back_end, 0, spine_end - back_end, h), Color.WHITE)
		img.fill_rect(Rect2i(back_end, 0, spine_end - back_end, h / 7), Color.BLACK)
	return img


## The North American fat case's two cover trays are clear plastic. Drawn as a flat lid is (5 percent), they
## were not there at all: a disc lay on bare paper (the owner, 2026-11-22).
func _clear_trays() -> void:
	var m := GameCaseModel.new()
	add_child(m)
	_spawned.append(m)
	if not m.build("jewel", "fatbox4"):
		_ok(false, "the fat case builds")
		return
	var seen := {}
	for level in m.levels:
		for mi in GameCaseModel.meshes(level):
			for s in mi.mesh.get_surface_count():
				var base := mi.mesh.surface_get_material(s)
				var over := mi.get_surface_override_material(s) as ShaderMaterial
				if base == null or over == null or String(base.resource_name) != "Jewel_Clear":
					continue
				var rim := float(over.get_shader_parameter("rim")) if over.get_shader_parameter("rim") != null else 0.0
				var tint: Color = over.get_shader_parameter("tint")
				var key := String(mi.name)
				seen[key] = true
				if key in GameCaseModel.CLEAR_TRAY_NODES:
					_ok(rim > 0.5 and tint.a > 0.1, "%s on %s: a clear tray's walls show edge-on, its flats hazed" % [key, level.name],
						"rim %.2f, haze %.2f" % [rim, tint.a])
				else:
					_ok(rim == 0.0 and tint.a < 0.08, "%s on %s: a flat clear part is drawn as it was" % [key, level.name],
						"rim %.2f, alpha %.2f" % [rim, tint.a])
	_ok(seen.has("Tray") and seen.has("LidTray") and seen.has("Lid") and seen.has("Base"),
		"both cover trays, the lid and the base are clear plastic on this case", str(seen.keys()))
	# A single case's black tray is no clear part.
	var one := GameCaseModel.new()
	add_child(one)
	_spawned.append(one)
	if one.build("jewel", "single"):
		var tray := one.levels[0].find_child("Tray", true, false) as MeshInstance3D
		var clear := false
		for s in tray.mesh.get_surface_count():
			clear = clear or tray.get_surface_override_material(s) is ShaderMaterial
		_ok(not clear, "a single case's own tray stays the colored plastic it was")


func _scan_spine_fit() -> void:
	var white := func(c: Color) -> bool: return c.r > 0.9 and c.g > 0.9 and c.b > 0.9
	var band := func(c: Color) -> bool: return c.r > 0.75 and c.g > 0.65 and c.b < 0.3
	# Spyro the Dragon (Japan)'s shape: the back to 764, the strip to 830, of 1510 x 680.
	var wide := _scan(1510, 680, 764, 830)
	_eq(GameCaseModel.jewel_spine_start(wide), 764, "a strip 66 px wide is found by its own edge")
	_ok(GameCaseModel.fit_jewel_scan(wide), "and the scan is put right")
	_ok(wide.get_width() == 1510 and wide.get_height() == 680, "at the size it was")
	_ok(band.call(wide.get_pixel(789, 400)) and not white.call(wide.get_pixel(790, 400)), "the back runs to the layout's 792",
		str(wide.get_pixel(789, 400)))
	_ok(white.call(wide.get_pixel(795, 400)) and white.call(wide.get_pixel(825, 400)), "the strip fills the spine, 792 to 828",
		"%s %s" % [wide.get_pixel(795, 400), wide.get_pixel(825, 400)])
	_ok(wide.get_pixel(810, 40).r < 0.1, "its head still at its head", str(wide.get_pixel(810, 40)))
	_ok(wide.get_pixel(900, 400).g > 0.5 and wide.get_pixel(900, 400).r < 0.2, "the front left as it was")
	_eq(GameCaseModel.jewel_spine_start(wide), -1, "put right, it is a scan that keeps the layout")
	# The layout's own: the back to 792, the strip to 829 (Crash Bandicoot 3, Japan).
	var plain := _scan(1509, 680, 792, 829)
	var before := plain.get_data()
	_eq(GameCaseModel.jewel_spine_start(plain), -1, "a scan that keeps the layout is left alone")
	_ok(not GameCaseModel.fit_jewel_scan(plain) and plain.get_data() == before, "pixel for pixel")
	# Nothing to go by: no edge anywhere near (a back and spine of one color).
	var flat := Image.create_empty(1622, 680, false, Image.FORMAT_RGB8)
	flat.fill(Color(0.2, 0.2, 0.6))
	_eq(GameCaseModel.jewel_spine_start(flat), -1, "a scan with no edge is left alone")
	# A band in the back's own art, farther from the front than any spine is wide.
	_eq(GameCaseModel.jewel_spine_start(_scan(1510, 680, 700, 830)), -1, "a band 130 px wide is the back's own, not a spine")
	# Not a jewel case's scan: a keep case's sheet, a long box.
	_eq(GameCaseModel.jewel_spine_start(_scan(1024, 680, 764, 830)), -1, "a keep case's sheet is left alone")
	_eq(GameCaseModel.jewel_spine_start(_scan(933, 680, 764, 830)), -1, "a long box's scan is left alone")
	# Half the size: the same shape, the numbers halved.
	var half := _scan(755, 340, 382, 415)
	_eq(GameCaseModel.jewel_spine_start(half), 382, "a scan of another size is read by its height")
	_ok(GameCaseModel.fit_jewel_scan(half) and white.call(half.get_pixel(400, 200)) and not white.call(half.get_pixel(393, 200)),
		"and put right the same way", "%s %s" % [half.get_pixel(400, 200), half.get_pixel(393, 200)])
	# With mipmaps already made, they are dropped for the caller to make again.
	var mipped := _scan(1510, 680, 764, 830)
	mipped.generate_mipmaps()
	_ok(GameCaseModel.fit_jewel_scan(mipped) and not mipped.has_mipmaps(), "a scan with mipmaps loses them, to be made again")


func _flat(w: int, h: int, c: Color) -> Image:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGB8)
	img.fill(c)
	return img


func _panels_join() -> void:
	var red := func(c: Color) -> bool: return c.r > 0.6 and c.g < 0.4
	var white := func(c: Color) -> bool: return c.r > 0.9 and c.g > 0.9 and c.b > 0.9
	var green := func(c: Color) -> bool: return c.g > 0.45 and c.r < 0.25
	# Spyro the Dragon (Europe)'s shapes: a back 765 wide, a side 65, a square front.
	var side := _flat(65, 680, Color.WHITE)
	side.fill_rect(Rect2i(0, 0, 65, 97), Color.BLACK)
	var joined := GameCaseModel.join_panels(_flat(765, 680, Color(0.75, 0.3, 0.35)), side, _flat(680, 680, Color(0.1, 0.55, 0.2)))
	_ok(joined != null and joined.get_width() == 792 + 36 + 680 and joined.get_height() == 680, "back, spine and front at the layout's widths",
		str(joined.get_size()) if joined != null else "null")
	_ok(red.call(joined.get_pixel(2, 400)) and red.call(joined.get_pixel(790, 400)), "the back fills its 792")
	_ok(white.call(joined.get_pixel(793, 400)) and white.call(joined.get_pixel(826, 400)) and joined.get_pixel(810, 40).r < 0.1,
		"the side fills the spine's 36, its head at its head")
	_ok(green.call(joined.get_pixel(829, 400)) and green.call(joined.get_pixel(1507, 400)), "the front after them")
	_eq(GameCaseModel.jewel_spine_start(joined), -1, "joined, it keeps the layout")
	_ok(is_equal_approx(GameCaseModel.booklet_fraction("", 1508.0, 680.0), 680.0 / 1508.0), "its square front is the booklet's, whole")
	# A US front is the whole lid: kept at its own shape, the band's strip left of the booklet.
	var us := GameCaseModel.join_panels(_flat(794, 680, Color.RED), _flat(39, 680, Color.WHITE), _flat(792, 680, Color.GREEN))
	_ok(us.get_width() == 792 + 36 + 792, "a US scan's front keeps its 792", str(us.get_size()))
	# Panels of other sizes are brought to the back's height.
	var small := GameCaseModel.join_panels(_flat(765, 680, Color.RED), _flat(33, 340, Color.WHITE), _flat(340, 340, Color.GREEN))
	_ok(small.get_size() == Vector2i(792 + 36 + 680, 680) and white.call(small.get_pixel(810, 600)) and green.call(small.get_pixel(1400, 600)),
		"panels of another size are brought to the back's height", str(small.get_size()))
	# Sonic CD (USA)'s long box: 476, 67 and 481 of a wrap stretched to 1024; the whole front is its booklet's.
	var long_box := GameCaseModel.join_panels(_flat(476, 680, Color.RED), _flat(67, 680, Color.WHITE), _flat(481, 680, Color.GREEN), "longbox")
	_ok(long_box.get_size() == Vector2i(440 + 51 + 425, 680), "a long box's panels at its own layout", str(long_box.get_size()))
	_ok(is_equal_approx(GameCaseModel.booklet_fraction("longbox", 916.0, 680.0), 425.0 / 916.0), "its whole front on its booklet")
	_ok(not GameCase.is_normalized_scan(long_box.get_size()), "and not taken for a stretched wrap")
	_ok(GameCaseModel.join_panels(_flat(765, 680, Color.RED), null, _flat(680, 680, Color.GREEN)) == null, "a panel missing, nothing joined")
	# A keep case's sheet is its own: Gran Turismo 4's panels (483, 52, 486) on a 14 mm case and on the 22 mm one.
	var sheet := GameCaseModel.join_panels(_flat(483, 680, Color.RED), _flat(52, 680, Color.WHITE), _flat(486, 680, Color.GREEN), "ps2", "keep")
	_ok(sheet.get_size() == Vector2i(1014, 680) and red.call(sheet.get_pixel(479, 300)) and white.call(sheet.get_pixel(483, 300))
		and white.call(sheet.get_pixel(531, 300)) and green.call(sheet.get_pixel(535, 300)),
		"a keep case's panels on its sheet: 129.5, 14 and 129.5 of 273", str(sheet.get_size()))
	var thick := GameCaseModel.join_panels(_flat(483, 680, Color.RED), _flat(52, 680, Color.WHITE), _flat(486, 680, Color.GREEN), "multi5", "keep")
	_ok(thick.get_size() == Vector2i(1044, 680) and white.call(thick.get_pixel(483, 300)) and white.call(thick.get_pixel(561, 300))
		and green.call(thick.get_pixel(565, 300)), "the five-disc case's spine takes its 22 of 281", str(thick.get_size()))
	var k := GameCaseModel.new()
	add_child(k)
	_spawned.append(k)
	if k.build("keep", "ps2"):
		_eq(k.apply_box_texture(ImageTexture.create_from_image(sheet)), OK, "a keep case takes the joined sheet")
	var m := GameCaseModel.new()
	add_child(m)
	_spawned.append(m)
	if m.build("jewel", "single"):
		_eq(m.apply_box_texture(ImageTexture.create_from_image(joined)), OK, "a case takes the joined image as its box texture")


## Stands in for the spawn menu: hears a case ask for its panels.
class ArtListener extends Node:
	var asked: Array = []

	func request_case_art(rom_path: String, systemid: String) -> void:
		asked.append([rom_path, systemid])


func _case_panels() -> void:
	var rom := RomLibrary.rom_dir_for_system("psx").path_join("__case_panels_selftest.chd")
	var made: Array[String] = []
	var clean := func() -> void:
		for kind: String in RetroGameCase.PANEL_KINDS:
			var dir := RomLibrary.rom_dir_for_system("psx").path_join("media").path_join(kind)
			DirAccess.remove_absolute(dir.path_join("__case_panels_selftest.png"))
		for i in range(made.size() - 1, -1, -1):
			DirAccess.remove_absolute(made[i])               # only what this test made, and only when empty
	clean.call()
	RetroGameCase.pending_art.clear()
	RetroGameCase._asked_art.clear()
	_ok(RetroGameCase.box_panel_paths("psx", rom).is_empty(), "no panels on disk: none found")
	_eq(RetroGameCase.missing_panels("psx", rom).size(), 3, "and all three are wanted")
	var ear := ArtListener.new()
	add_child(ear)
	ear.add_to_group(RetroGameCase.PANEL_LISTENERS)
	_spawned.append(ear)
	var make := func(fam: String, variant: String) -> RetroGameCase:
		var c := CASE_SCENE.instantiate() as RetroGameCase
		c.systemid = "psx"
		c.case_family = fam
		c.case_variant = variant
		c.rom_path = rom
		c.freeze = true
		add_child(c)
		_spawned.append(c)
		return c
	var keep: RetroGameCase = make.call("keep", "ps2")
	for _i in 3:
		await get_tree().process_frame
	_ok(ear.asked.is_empty(), "a keep case asks for no panels (its wrap keeps the sheet's layout)")
	var c: RetroGameCase = make.call("jewel", "single")
	for _i in 3:
		await get_tree().process_frame
	_ok(ear.asked.size() == 1 and ear.asked[0] == [rom, "psx"], "a jewel case asks for its game's panels", str(ear.asked))
	var twin: RetroGameCase = make.call("jewel", "single")
	for _i in 3:
		await get_tree().process_frame
	_eq(ear.asked.size(), 1, "a second case of the game does not ask again")
	# The scraper lands them: two of the three are not a set.
	var sizes := {"box_back": Vector2i(765, 680), "box_side": Vector2i(65, 680), "box_front": Vector2i(680, 680)}
	for kind: String in ["box_back", "box_side"]:
		var dir := RomLibrary.rom_dir_for_system("psx").path_join("media").path_join(kind)
		_make_dirs(dir, made)
		_flat(sizes[kind].x, sizes[kind].y, Color.WHITE).save_png(dir.path_join("__case_panels_selftest.png"))
	_ok(RetroGameCase.box_panel_paths("psx", rom).is_empty() and RetroGameCase.missing_panels("psx", rom).size() == 3,
		"two of the three there: not a set, all three still wanted")
	var front_dir := RomLibrary.rom_dir_for_system("psx").path_join("media").path_join("box_front")
	_make_dirs(front_dir, made)
	_ok(_flat(680, 680, Color(0.1, 0.55, 0.2)).save_png(front_dir.path_join("__case_panels_selftest.png")) == OK,
		"(the test's own panel files are written)")
	_eq(RetroGameCase.box_panel_paths("psx", rom).size(), 3, "all three there: the set is found")
	_eq(RetroGameCase.box_size("psx", rom), Vector2i(765 + 65 + 680, 680), "with no wrap, the box's size is its panels' side by side")
	_ok(RetroGameCase.missing_panels("psx", rom).is_empty(), "and nothing more is wanted")
	var joined := await RetroGameCase.decode_panels(get_tree(), RetroGameCase.box_panel_paths("psx", rom), "single")
	_ok(joined != null and joined.get_size() == Vector2i(792 + 36 + 680, 680) and joined.has_mipmaps(),
		"decoded and joined off the main thread, with mipmaps", str(joined.get_size()) if joined != null else "null")
	# Told one has landed, the case puts its art on from them.
	c.on_panel_arrived("some/other/game.chd")
	c.on_panel_arrived(rom)
	var on_case := Vector2i.ZERO
	for _i in 120:
		await get_tree().process_frame
		on_case = _art_size(c)
		if on_case.x > 0:
			break
	_eq(on_case, Vector2i(792 + 36 + 680, 680), "told its panels have landed, the case wears them")
	_ok(_art_size(keep) == Vector2i.ZERO and _art_size(twin) == Vector2i.ZERO, "a case not told wears nothing new (this game has no wrap)")
	keep.on_panel_arrived(rom)
	on_case = Vector2i.ZERO
	for _i in 120:
		await get_tree().process_frame
		on_case = _art_size(keep)
		if on_case.x > 0:
			break
	_eq(on_case, Vector2i(1014, 680), "a keep case told the same wears them on its own sheet")
	clean.call()
	RetroGameCase.pending_art.clear()
	RetroGameCase._asked_art.clear()


## Make `dir` with whatever of its parents is missing (an empty library has no roms folder at all); `made` gets
## each folder created, parents first, for the test to take away again.
func _make_dirs(dir: String, made: Array[String]) -> void:
	var missing: Array[String] = []
	var d := dir
	while not DirAccess.dir_exists_absolute(d) and d != d.get_base_dir():
		missing.append(d)
		d = d.get_base_dir()
	DirAccess.make_dir_recursive_absolute(dir)
	for i in range(missing.size() - 1, -1, -1):
		made.append(missing[i])


## The size of the box art a case wears on its paper, or zero.
func _art_size(c: RetroGameCase) -> Vector2i:
	for mi in GameCaseModel.meshes(c.model.levels[0]):
		for s in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(s) as BaseMaterial3D
			if m != null and m.albedo_texture is ImageTexture and m.albedo_texture.get_width() > 256:
				return Vector2i(m.albedo_texture.get_width(), m.albedo_texture.get_height())
	return Vector2i.ZERO


## A manual deleted off its seat (the trash, the menu's Delete) stays in the case's collision exceptions as a null:
## the lid's check against the world called get_rid on it every tick and stopped the game.
func _case_deleted_seated() -> void:
	var c := _new_case("jewel", "single")
	await get_tree().physics_frame
	c.global_position = Vector3(390.0, 1.0, 0.0)
	c.set_physics_process(false)
	c.sim.set_angle_deg(c.sim.top(), 120.0)
	c._apply_angles()
	var book := await _seat_manual(c)
	_ok(c.manual() == book and c.get_collision_exceptions().has(book), "seated, the manual is one the case does not collide with")
	_spawned.erase(book)
	book.free()
	await get_tree().physics_frame
	_ok(c.get_collision_exceptions().any(func(b: Variant) -> bool: return not is_instance_valid(b)) or c.get_collision_exceptions().is_empty(),
		"(deleted, it is a null among the exceptions, or gone from them)", str(c.get_collision_exceptions()))
	_ok(not c._lid_blocked(120.0), "the lid's check against the world still runs, and finds nothing in the way")
	c._lid_gives_way()
	_ok(c.manual() == null, "and the case has no manual")


func _case_manual_paper() -> void:
	var x := 420.0
	for fam: Array in [["jewel", "single", "Jewel_BookletBack"], ["keep", "ps2", ""]]:
		x += 3.0
		var c := _new_case(fam[0], fam[1])
		await get_tree().physics_frame
		c.global_position = Vector3(x, 1.0, 0.0)
		c.set_physics_process(false)
		c.sim.set_angle_deg(c.sim.top(), 120.0)
		c._apply_angles()
		var book := await _seat_manual(c)
		var shown: Material = null
		for _i in 60:
			await get_tree().create_timer(0.1).timeout
			shown = null
			if fam[0] == "jewel":
				for mi in GameCaseModel.meshes(c.model.levels[0]):
					for s in mi.mesh.get_surface_count():
						var base := mi.mesh.surface_get_material(s)
						if base != null and base.resource_name == str(fam[2]):
							shown = mi.get_surface_override_material(s)
			elif c._manual_proxy != null:
				shown = (c._manual_proxy.get_node("Front") as MeshInstance3D).material_override
			if shown != null:
				break
		_ok(shown is StandardMaterial3D and (shown as StandardMaterial3D).albedo_texture != null,
			"%s: the page the case shows of its manual is on plain paper with the page's picture" % fam[0], str(shown))
		_ok(not shown is ShaderMaterial, "%s: not the book's own paper shader" % fam[0])
		var page := 0 if fam[0] == "keep" else book._page_count - 1
		_ok(shown is StandardMaterial3D and (shown as StandardMaterial3D).albedo_texture == book._texture_cache.get(page),
			"%s: and it is the %s page" % [fam[0], "first" if fam[0] == "keep" else "last"])


## A case a save puts back with its discs as an older build seated them moves them to the real layout, once;
## discs a player has arranged, and a case the menu has just filled, are left as they are.
func _case_old_layout() -> void:
	var x := 520.0
	# [family, variant, discs, seats (1-based) the save put discs 1.. on, seats they should end on, why]
	var rows := [
		["jewel", "fatbox4", 3, [4, 3, 2], [4, 2, 1], "front to back with a disc under the manual (the day's first builds)"],
		["jewel", "fatbox4", 3, [1, 2, 3], [4, 2, 1], "disc 1 on the back (every build before)"],
		["jewel", "fatbox4", 4, [1, 2, 3, 4], [4, 3, 2, 1], "four discs, disc 1 on the back"],
		["jewel", "fatbox4", 2, [4, 3], [4, 1], "two discs front to back"],
		["keep", "triple", 3, [1, 2, 3], [3, 2, 1], "a keep case filled disc 1 on the back"],
		["jewel", "fatbox4", 3, [4, 2, 1], [4, 2, 1], "the real layout already"],
		["jewel", "fatbox4", 3, [2, 4, 1], [2, 4, 1], "a player's own arrangement"],
	]
	for row: Array in rows:
		x += 3.0
		var c := CASE_SCENE.instantiate() as RetroGameCase
		c.systemid = "psx"
		c.case_family = row[0]
		c.case_variant = row[1]
		c.rom_path = "C:/nowhere/Old Save (Disc 1).chd"
		c.freeze = true
		add_child(c)
		_spawned.append(c)
		await get_tree().physics_frame
		c.global_position = Vector3(x, 1.0, 0.0)
		c.set_physics_process(false)
		var discs: Array[RetroDisc] = []
		for n in int(row[2]):
			var d := DISC_SCENE.instantiate() as RetroDisc
			d.systemid = "psx"
			d.rom_path = "C:/nowhere/Old Save (Disc %d).chd" % (n + 1)
			add_child(d)
			_spawned.append(d)
			discs.append(d)
			c.disc_zone(int((row[3] as Array)[n]) - 1).pick_up_object(d)       # as a save's restore does
		await get_tree().create_timer(RetroGameCase.OLD_LAYOUT_SETTLE + 0.5).timeout
		for _i in 3:
			await get_tree().physics_frame
		var ended: Array = []
		for d in discs:
			var at := 0
			for i in c._zones.size():
				if c._zones[i].picked_up_object == d:
					at = i + 1
			ended.append(at)
		_eq(ended, row[4], "%s/%s, %s: discs 1.. end on seats %s" % [row[0], row[1], row[5], str(row[4])])
	# A case the menu fills is right from the start and is not looked at again.
	var fresh := _new_case("jewel", "fatbox4")
	await get_tree().physics_frame
	fresh.global_position = Vector3(x + 3.0, 1.0, 0.0)
	fresh.set_physics_process(false)
	fresh.spawn_contents(PackedStringArray(["C:/nowhere/New (Disc 1).chd", "C:/nowhere/New (Disc 2).chd", "C:/nowhere/New (Disc 3).chd"]))
	await get_tree().create_timer(RetroGameCase.OLD_LAYOUT_SETTLE + 0.4).timeout
	_ok(fresh._fresh and not fresh._layout_done and fresh._zones[2].picked_up_object == null and fresh._zones[0].picked_up_object != null,
		"a case the menu has just filled has nothing under its manual, and is not looked at")


## The North American fat case (the owner's photographs, 2026-11-22): the manual lies in the black tray's front
## recess, on its disc; the lid keeps its front sheet whatever the manual does.
func _case_manual_on_tray() -> void:
	var c := _new_case("jewel", "fatbox4")
	await get_tree().physics_frame
	c.global_position = Vector3(450.0, 1.0, 0.0)
	c.set_physics_process(false)
	var top := c.sim.top()
	_ok(c._manual_loose and c._manual_on == 0 and c._manual_zone != null, "its manual's seat is on the flip tray",
		"%s %d" % [c._manual_loose, c._manual_on])
	var seat := c.model.manual_seat()
	var tray := c.model.levels[0].find_child("FlipTray1", true, false) as Node3D
	var in_case := c.global_transform.affine_inverse() * seat.global_position
	_ok(in_case.z > 0.0 and in_case.z < 0.006, "over the tray's front face, under the lid's tray", str(in_case * 1000.0))
	_ok(not c._manual_open(), "shut, the manual's place is closed")
	c.sim.set_angle_deg(top, 180.0)
	c._apply_angles()
	_ok(c._manual_open(), "the lid open flat: its place is in the open")
	# It rides the tray.
	c.sim.set_angle_deg(0, 90.0)
	c._apply_angles()
	var rode := c.global_transform.affine_inverse() * seat.global_position
	_ok(rode.distance_to(in_case) > 0.03, "the tray turned up, the manual's seat went with it", str(rode * 1000.0))
	c.sim.set_angle_deg(0, 180.0)
	c._apply_angles()
	_ok(not c._manual_open(), "the tray over on the lid: its front, and the manual's place, are covered")
	c.sim.set_angle_deg(0, 0.0)
	c._apply_angles()
	# Disc 2 on the tray's front, then the manual over it.
	var d := DISC_SCENE.instantiate() as RetroDisc
	d.systemid = "psx"
	add_child(d)
	_spawned.append(d)
	c.disc_zone(2).pick_up_object(d)
	for _i in 3:
		await get_tree().physics_frame
	_ok(c._seat_reachable(2), "with no manual on it, the disc on the tray's front is a hand's")
	var book := await _seat_manual(c)
	_ok(c.manual() == book, "the manual seats there")
	_ok(not c._seat_reachable(2), "under the manual, that disc waits for the manual to be lifted")
	_ok(c._seat_reachable(3), "the lid's own disc is not the manual's to cover")
	var over := c.global_transform.affine_inverse() * book.global_position
	_ok(over.z > (c.global_transform.affine_inverse() * d.global_position).z, "the manual lies over the disc, toward the lid",
		"%s over %s" % [over * 1000.0, (c.global_transform.affine_inverse() * d.global_position) * 1000.0])
	var booklet := c.model.levels[0].find_child("Booklet", true, false) as Node3D
	_ok(booklet != null and booklet.visible, "the lid's front sheet is there with the manual in")
	_ok(c._manual_proxy != null and c._manual_proxy.visible and c._manual_proxy.get_parent() == seat, "the manual shows as a booklet on the tray")
	# A grip is the manual's from its front, not through the tray from behind.
	var zone := c._manual_zone
	var front := zone.global_transform * Vector3(c.model.manual_size_m().x * 0.5, 0.0, 0.01)
	var behind := zone.global_transform * Vector3(c.model.manual_size_m().x * 0.5, 0.0, -0.03)
	_ok(zone.reaches(front) >= 0.0, "a hand over the manual reaches it")
	_ok(zone.reaches(behind) < 0.0, "a hand under the tray does not")
	c._manual_zone.drop_object()
	for _i in 3:
		await get_tree().physics_frame
	book.global_position += Vector3(0.0, 5.0, 0.0)
	for _i in 3:
		await get_tree().process_frame
	_ok(booklet.visible, "the manual out, the front sheet stays")
	_ok(c._manual_proxy == null or not c._manual_proxy.visible, "and the booklet on the tray is gone")
	_ok(c._seat_reachable(2), "and the disc under it is a hand's again")
	_ok(tray != null, "(the model has its flip tray)")


## A fingertip pressed on a lid that cannot turn further sinks through it; drawn back, it must not bring the lid
## out with it. The fingertip is walked along the lid's own normal as VRHinge's poke loop walks it.
func _case_poke_no_pull() -> void:
	var x := 480.0
	for fam: Array in [["jewel", "single", 0.0], ["keep", "ps2", 0.0], ["jewel", "single", 180.0]]:
		x += 3.0
		var c := _new_case(fam[0], fam[1])
		await get_tree().physics_frame
		c.global_position = Vector3(x, 1.0, 0.0)
		c.set_physics_process(false)
		var top := c.sim.top()
		var lid := c.hinge(top)
		var rest := float(fam[2])
		if rest > 90.0:
			rest = rad_to_deg(c.sim.open_max)                # open against its stop (a jewel lid: a little past flat)
		c.sim.set_angle_deg(top, rest)
		c._apply_angles()
		lid.set_process(false)
		var at_rest := lid.get_rotation_deg()
		var panel := lid.get_node("PokePanel") as CollisionShape3D
		var half := (panel.shape as BoxShape3D).size.y * 0.5
		# Shut, the finger comes at the lid's outside; open flat on its stop, at its inside.
		var face := VRHinge.FACE_Y_POS if rest < 90.0 else VRHinge.FACE_Y_NEG
		var out := panel.global_basis.y.normalized() * (1.0 if rest < 90.0 else -1.0)
		var on_face := panel.global_position + out * half
		var finger := XRController3D.new()
		add_child(finger)
		_spawned.append(finger)
		var tip := on_face + out * 0.003
		var met := lid._poke_contact_at(tip, lid.poke_face_margin, -1, -out * 0.001)
		_ok(not met.is_empty() and int(met["face"]) == face and bool(met["external"]),
			"%s/%s at %d: the finger meets the lid's face from outside it" % [fam[0], fam[1], int(rest)], str(met.get("face", 0)))
		lid._poke_ctrl = finger
		lid._poke_shape = panel
		lid._poke_face = face
		lid._poke_mode = VRHinge.POKE_TORQUE
		lid._begin_track(tip)
		var prev := tip
		# Pressed in: through the face and past the lid's middle, 1 mm a step.
		for k in int((0.003 + half * 2.0 + 0.002) / 0.001):
			tip -= out * 0.001
			lid._update_active_poke_face(tip, tip - prev)
			lid._on_poke_motion(tip, lid._poke_mode)
			prev = tip
		_ok(lid._poke_face == face, "%s/%s at %d: pressed through the lid, the push stays on the face it began on" % [fam[0], fam[1], int(rest)],
			lid._face_name(lid._poke_face))
		_ok(absf(lid.get_rotation_deg() - at_rest) < 0.5, "%s/%s at %d: a lid at its stop stays there under the finger" % [fam[0], fam[1], int(rest)],
			str(lid.get_rotation_deg()))
		# Drawn back two centimetres.
		var worst := 0.0
		for k in 20:
			tip += out * 0.001
			lid._update_active_poke_face(tip, tip - prev)
			lid._on_poke_motion(tip, lid._poke_mode)
			prev = tip
			worst = maxf(worst, absf(lid.get_rotation_deg() - at_rest))
		_ok(worst < 0.5, "%s/%s at %d: drawn back, the lid does not come out with the finger" % [fam[0], fam[1], int(rest)],
			"it turned %.1f degrees" % worst)
		# And a tip already behind a face (through the leaf) is not outside it: no push begins there.
		var behind := lid._poke_contact_at(on_face - out * 0.0006, lid.poke_face_margin, face, -out * 0.001)
		_ok(not behind.is_empty() and not bool(behind["external"]),
			"%s/%s at %d: a tip just through a face is behind it, not on it" % [fam[0], fam[1], int(rest)])
		lid._poke_ctrl = null
		lid._poke_shape = null
		lid._poke_face = 0
		lid._poke_mode = 0


## Whether a push would begin at a fingertip 2 mm off one face of a hinge's panel, coming at it (side: +1 its
## outside, -1 its inside), and the face it would be on.
func _push_at(h: CaseHinge, side: float) -> int:
	var panel := h.get_node("PokePanel") as CollisionShape3D
	var out := panel.global_basis.y.normalized() * side
	var tip := panel.global_position + out * ((panel.shape as BoxShape3D).size.y * 0.5 + 0.002)
	return int(h._poke_start_at(tip, -out * 0.001).get("face", 0))


## A hand passes through a case in VR, so a finger come up through the base is under the shut lid's inside face.
## It pushes nothing there until the lid is far enough off what is under it for a hand to be in the case.
func _case_poke_shut_inside() -> void:
	var x := 560.0
	for fam: Array in [["jewel", "single"], ["keep", "ps2"], ["jewel", "fatbox4"], ["keep", "triple"]]:
		x += 3.0
		var c := _new_case(fam[0], fam[1])
		await get_tree().physics_frame
		c.global_position = Vector3(x, 1.0, 0.0)
		c.set_physics_process(false)
		var top := c.sim.top()
		var lid := c.hinge(top)
		var tag := "%s/%s" % [fam[0], fam[1]]
		_eq(_push_at(lid, -1.0), 0, "%s shut: a fingertip under the lid's inside pushes nothing" % tag)
		_eq(_push_at(lid, 1.0), VRHinge.FACE_Y_POS, "%s shut: one on its outside still does" % tag)
		_eq(_push_at(c._base_hinge, -1.0), 0, "%s shut: nor one on the base's inside, for a case held by its lid" % tag)
		_eq(_push_at(c._base_hinge, 1.0), VRHinge.FACE_Y_POS, "%s shut: the base's outside does" % tag)
		c.sim.set_angle_deg(top, RetroGameCase.REACH_DEG - 3.0)
		c._apply_angles()
		_eq(_push_at(lid, -1.0), 0, "%s barely open (%.0f): still nothing" % [tag, c.sim.angle_deg(top)])
		_eq(_push_at(c._base_hinge, -1.0), 0, "%s barely open: nor the base's" % tag)
		c.sim.set_angle_deg(top, RetroGameCase.REACH_DEG + 3.0)
		c._apply_angles()
		_eq(_push_at(lid, -1.0), VRHinge.FACE_Y_NEG, "%s open far enough for a hand (%.0f): the lid's inside is pushed" % [tag, c.sim.angle_deg(top)])
		if top == 0:
			_eq(_push_at(c._base_hinge, -1.0), VRHinge.FACE_Y_NEG, "%s open far enough: and the base's" % tag)
			continue
		_eq(_push_at(c._base_hinge, -1.0), 0, "%s open far enough: the base's inside is still under its trays" % tag)
		# Open wide with every tray turned over onto the lid: the lid's inside is under a tray, the base's is bare.
		c.sim.set_angle_deg(top, 150.0)
		for i in top:
			c.sim.set_angle_deg(i, 150.0)
		c._apply_angles()
		var gap := c.sim.angle_deg(top) - c.sim.angle_deg(top - 1)
		_ok(gap < RetroGameCase.REACH_DEG and _push_at(lid, -1.0) == 0,
			"%s: a tray lying on the open lid, the lid's inside is the tray's to be worked from" % tag, "%.1f degrees between them" % gap)
		_eq(_push_at(c._base_hinge, -1.0), VRHinge.FACE_Y_NEG, "%s: and the base's inside is in the open" % tag)
		# The trays back on the base: the lid's inside in the open, the base's under a tray.
		for i in top:
			c.sim.set_angle_deg(i, 0.0)
		c._apply_angles()
		_eq(_push_at(lid, -1.0), VRHinge.FACE_Y_NEG, "%s: the trays back on the base, the lid's inside is pushed" % tag)
		_eq(_push_at(c._base_hinge, -1.0), 0, "%s: and the base's inside is under a tray" % tag)


func _case_tray_on_lid() -> void:
	var x := 300.0
	for fam: Array in [["jewel", "fatbox4"], ["jewel", "fatbox2"], ["keep", "triple"]]:
		x += 3.0
		var c := _new_case(fam[0], fam[1])
		await get_tree().physics_frame
		c.global_position = Vector3(x, 1.0, 0.0)
		c.set_physics_process(false)
		var top := c.sim.top()
		var tray := c.hinge(0)
		var lid := c.hinge(top)
		var panel := tray.get_node("PokePanel") as CollisionShape3D
		var half := (panel.shape as BoxShape3D).size.y * 0.5
		_ok(not c._can_take(0), "%s/%s: under a shut lid the tray is nobody's" % [fam[0], fam[1]])
		for pose: Array in [[0.0, true, false], [90.0, true, true], [180.0, false, true]]:
			c.sim.set_angle_deg(top, 180.0)
			c.sim.set_angle_deg(0, float(pose[0]))
			c._apply_angles()
			for _i in 3:
				await get_tree().physics_frame
			c._apply_angles()
			_ok(c._can_take(0) and tray._can_engage(), "%s/%s: lid open flat, the tray at %d may be taken" % [fam[0], fam[1], int(pose[0])])
			var mid := panel.global_position
			var up := panel.global_basis.y.normalized()
			var over := mid + up * (half + 0.01)             # a centimetre off its upper face, at its middle
			var under := mid - up * (half + 0.01)
			_eq(tray._tip_in_activation_region(over), bool(pose[1]), "%s/%s: tray at %d, the trigger at its upper face's middle" % [
				fam[0], fam[1], int(pose[0])])
			_eq(tray._tip_in_activation_region(under), bool(pose[2]), "%s/%s: tray at %d, the trigger at its under face's middle" % [
				fam[0], fam[1], int(pose[0])])
		# Lying on the lid: at the two free edges together, the trigger is the tray's and the lid's handle stands by.
		var edge := tray.global_position - panel.global_basis.y.normalized() * (half + 0.005)
		_ok(tray._tip_in_activation_region(edge), "%s/%s: on the open lid, a trigger at the tray's free edge takes the tray" % [fam[0], fam[1]])
		_ok(not lid._tip_in_activation_region(edge), "%s/%s: and not the lid under it" % [fam[0], fam[1]])
		_ok(lid._tip_in_activation_region(lid.global_position + panel.global_basis.y.normalized() * 0.03),
			"%s/%s: behind the lid, the trigger is the lid's still" % [fam[0], fam[1]])


func _case_disc_order() -> void:
	var x := 330.0
	for fam: Array in [["jewel", "fatbox4"], ["jewel", "fatbox2"], ["jewel", "pal_multi2"], ["keep", "double"], ["keep", "triple"],
			["keep", "multi5"], ["keep", "gc_double"]]:
		x += 3.0
		var c := _new_case(fam[0], fam[1])
		await get_tree().physics_frame
		c.global_position = Vector3(x, 1.0, 0.0)
		c.set_physics_process(false)
		var paths := PackedStringArray()
		for i in c._zones.size():
			paths.append("C:/nowhere/Game (Disc %d).chd" % (i + 1))
		c.spawn_contents(paths)
		for _i in 3:
			await get_tree().physics_frame
		# Front to back: each disc on a seat no farther forward than the one before it.
		var last := INF
		var in_order := true
		var where: Array = []
		for n in paths.size():
			for i in c._zones.size():
				var d := c._zones[i].picked_up_object as RetroDisc
				if d != null and d.rom_path == paths[n]:
					where.append(i + 1)
					if c._seat_z[i] > last + 0.0005:
						in_order = false
					last = c._seat_z[i]
		_ok(in_order and where.size() == paths.size(), "%s/%s: discs 1.. on seats %s, front to back" % [fam[0], fam[1], str(where)])
		if fam[1] == "fatbox4":
			_eq(where, [4, 3, 2, 1], "the four-disc case: disc 1 in the lid's tray, disc 4 on the back")
			_eq(c.disc_seat_order(3).map(func(i: int) -> int: return i + 1), [4, 2, 1],
				"three discs in it (Final Fantasy VII): the front cover, the back of the black tray, the rear cover")
			_eq(c.disc_seat_order(2).map(func(i: int) -> int: return i + 1), [4, 1], "two (Metal Gear Solid): the two covers")
			_eq(c.disc_seat_order(1).map(func(i: int) -> int: return i + 1), [4], "one: the front cover")
		if fam[1] == "gc_double":
			_eq(where, [1, 2], "two seats on one panel keep their order")
		# Every disc's label out of its tray and reading upright, the case standing on its bottom edge.
		var inv := c.global_basis.orthonormalized().inverse()
		for i in c._zones.size():
			var d := c._zones[i].picked_up_object as Node3D
			var seat := c._zones[i].get_parent() as Node3D
			_ok((inv * -d.global_basis.z).normalized().dot(Vector3.UP) > 0.99, "%s/%s: the disc on seat %d reads upright" % [fam[0], fam[1], i + 1],
				str((inv * -d.global_basis.z).normalized()))
			_ok(d.global_basis.y.normalized().dot(seat.global_basis.y.normalized()) > 0.99, "%s/%s: and faces out of its tray" % [fam[0], fam[1]])
		# Opened like a book (about its upright hinge), what was upright stays upright.
		c.sim.set_angle_deg(c.sim.top(), 180.0)
		c._apply_angles()
		for _i in 3:
			await get_tree().physics_frame
		for i in c._zones.size():
			var d := c._zones[i].picked_up_object as Node3D
			_ok((inv * -d.global_basis.z).normalized().dot(Vector3.UP) > 0.99, "%s/%s: opened flat, the disc on seat %d still reads upright" % [
				fam[0], fam[1], i + 1])


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
	_ok(hinges.size() == 3, "three hinge records saved (the flipper, the cover, and the cover's hinge by the base)", str(hinges))
	var back := ScenePersistence.new().call("_load_game_case", entry) as RetroGameCase
	_ok(back != null and back.case_variant == "triple" and back.case_family == "keep", "loads back")
	if back != null:
		back.free()
