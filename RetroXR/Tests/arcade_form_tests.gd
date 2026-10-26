## Arcade form self-tests — the cabinet takes the shape of the game in its bay (ArcadeCabinetSpecs.for_game,
## RetroSystemModelArcadeCabinet.morph_to). Headless, no core, no ROM, no headset.
##
##     "$godot" --headless --path RetroXR res://Tests/arcade_form_tests.tscn
##     "$godot" --headless --path RetroXR res://Tests/arcade_form_tests.tscn -- --only=guns
##
## Exits 0 when everything passes, 1 otherwise.
##
## What a headless run can say: which form each kind of game asks for (pure data), that building it puts
## the parts where the modules find them, that what hangs on the parts (the guns and their ports, the input,
## the collision and pointer boxes, the rectangle on the floor) follows a morph, and that pulling the board
## gives the cabinet back its own form. How each form LOOKS is the probe's
## (Tools/models/arcade_cabinet_probe -- --forms, windowed).
##
## Groups:
##   specs/     the spec each kind of game asks for: panels, doors, guns, screen, cockpit, stage
##   layout/    panels across the deck: the generic two where they always were, more make the BODY wider
##   build/     each form built on a real cabinet: its modules, parts and screen
##   board/     the real path: a board in the bay changes the form, pulling it gives the cabinet's own back
##   tate/      a monitor on its side gets the tall body and a window cut to the picture; every body is one silhouette
##   wide/      three to six players: the BODY is as wide as the deck they need, doors and sockets under their panels
##   picture/   the picture takes a share of a wide body, never a postage stamp in it; a big-screen cabinet has its body's own tube
##   screens/   a game of several screens: the tube takes the frame's shape, the body follows; Silent Scope's second screen is in its scope
##   pedals/    a gun game's pedal and a driver's two are built as real ones are: a hinged ribbed tread on a base, an axle
##   service/   TEST and SERVICE in the compartment opposite the power switch, there when MAME says the game reads one
##   mount/     a gun on a swivel (Silent Scope's rifle, Operation Wolf's Uzi) is fixed to its cabinet: it turns about its pivot
##   odd/       Prop Cycle's bicycle, Time Traveler's deep stage, Panic Park's two levers in one slot
##   shift/     a driving game's gear lever is the game's: its button, a toggle or held, a sequential box, none where MAME has none
##   reach/     every panel, wheel and coin button a morph builds can be aimed at: pointable, and first under a laser
##   guns/      a gun game's guns are built, plugged in and hung, its pedal wired; another game frees them and their ports
##   ports/     a pad in a socket the new form does not have (or a gun takes) comes out
##   input/     the input drives the new panels, and a third or fourth coin door reaches its port
##   animate/   a wheel turns, pedals tip, a bike leans, a second stick leans, a dancer's arrows sink
##   running/   a form asked for while a core runs is built when it stops
##   boxes/     collision and pointer boxes are laid again, not added to; a cockpit has pointer boxes only
##   footprint/ the rectangle on the floor covers a cockpit or a stage
##   bezel/     the game's own bezel from the player's MAME artwork (its parent's for a clone), never a filler
extends Node

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const CART_SCENE := preload("res://Scenes/Objects/media/cartridge.tscn")
const PAD_SCENE := "res://Scenes/Objects/controllers/retro_controller.tscn"
var P := ArcadeGameProfile
var S := ArcadeCabinetSpecs

var _checks := 0
var _failed := 0
var _cases_failed := 0
var _only := ""
var _spawned: Array[Node] = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7)
	get_tree().create_timer(300.0).timeout.connect(func() -> void:
		print("[form] TIMED OUT")
		get_tree().quit(1))
	await _run()
	print("[form] %d checks, %d case(s) failed" % [_checks, _cases_failed])
	print("[form] RESULT=%s" % ("PASS" if _failed == 0 else "FAIL"))
	get_tree().quit(1 if _failed > 0 else 0)


func _ok(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		_cases_failed += 1
	print("[form] %s  %s" % ["PASS" if ok else "FAIL", what])


func _wait(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _want(group: String) -> bool:
	return _only.is_empty() or _only == group


func _run() -> void:
	if _want("specs"):
		_group_specs()
	if _want("layout"):
		_group_layout()
	if _want("build"):
		await _group_build()
		await _clear()
	if _want("board"):
		await _group_board()
		await _clear()
	if _want("tate"):
		await _group_tate()
		await _clear()
	if _want("wide"):
		await _group_wide()
		await _clear()
	if _want("picture"):
		await _group_picture()
		await _clear()
	if _want("screens"):
		await _group_screens()
		await _clear()
	if _want("pedals"):
		await _group_pedals()
		await _clear()
	if _want("service"):
		await _group_service()
		await _clear()
	if _want("mount"):
		await _group_mount()
		await _clear()
	if _want("odd"):
		await _group_odd()
		await _clear()
	if _want("shift"):
		await _group_shift()
		await _clear()
	if _want("reach"):
		await _group_reach()
		await _clear()
	if _want("guns"):
		await _group_guns()
		await _clear()
	if _want("ports"):
		await _group_ports()
		await _clear()
	if _want("input"):
		await _group_input()
		await _clear()
	if _want("animate"):
		await _group_animate()
		await _clear()
	if _want("running"):
		await _group_running()
		await _clear()
	if _want("boxes"):
		await _group_boxes()
		await _clear()
	if _want("footprint"):
		await _group_footprint()
		await _clear()
	if _want("bezel"):
		await _group_bezel()
		await _clear()


# --- helpers -------------------------------------------------------------------

func _machine(model_id: String = ArcadeProfiles.CABINET_MODEL_ID, systemid: String = "arcade", frames: int = 10) -> RetroSystem:
	var sys := SYSTEM_SCENE.instantiate() as RetroSystem
	sys.model_id = model_id
	sys.systemid = systemid
	sys.position = Vector3(_spawned.size() * 4.0, 0, 0)
	sys.freeze = true
	add_child(sys)
	sys.add_to_group("spawned")
	_spawned.append(sys)
	await _wait(frames)
	return sys


func _clear() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			n.queue_free()
	for bay in get_tree().get_nodes_in_group(ArcadeBayUnit.GROUP):
		bay.queue_free()
	_spawned.clear()
	await _wait(6)


func _slot_of(sys: RetroSystem) -> XRToolsSnapZone:
	var bay := sys.get_bay()
	return bay.slot if bay != null else sys.get_node("CartridgeSlot") as XRToolsSnapZone


## A board for `romset` seated in the cabinet's bay (the path every drop, restore and re-dock takes).
func _board(sys: RetroSystem, romset: String) -> Node3D:
	(sys.get_model() as RetroSystemModelArcadeCabinet).set_lid_angle_deg(90.0)
	var cart := CART_SCENE.instantiate() as Node3D
	cart.systemid = "arcade"
	cart.rom_path = "/tmp/%s.zip" % romset
	cart.position = sys.global_position + Vector3(0, 3, 0)
	cart.freeze = true
	add_child(cart)
	_spawned.append(cart)
	await _wait(6)
	_slot_of(sys).pick_up_object(cart)
	await _wait(8)
	return cart


func _pull(sys: RetroSystem) -> void:
	_slot_of(sys).drop_object()
	await _wait(8)


func _spec(romset: String, base_name: String = "generic") -> Dictionary:
	var base := S.variant(base_name)
	base["variant"] = base_name
	return S.for_game(base, P.for_romset(romset))


func _panels(model: Node) -> Array:
	return (model as RetroSystemModelArcadeCabinet).modules_of_kind(ArcadeProfiles.KIND_STICK_BUTTONS)


func _doors(model: Node) -> Array:
	return (model as RetroSystemModelArcadeCabinet).modules_of_kind(ArcadeProfiles.KIND_COIN)


func _kinds(spec: Dictionary) -> Array:
	var out: Array = []
	for p: Dictionary in spec.get("players", []):
		out.append(str(p["kind"]))
	return out


# --- specs ---------------------------------------------------------------------

func _group_specs() -> void:
	var base := S.variant("generic")
	base["variant"] = "generic"
	# A game that wants exactly what the cabinet is: the cabinet's own row, so nothing is rebuilt.
	var sf2 := _spec("sf2")
	_ok(S._same_form(sf2, base) and not sf2.has("form"),
		"specs: Street Fighter II asks for exactly the generic cabinet (two panels, six caps, two doors)")
	_ok(S._same_form(S.for_game(base, null), base) and S._same_form(S.for_game(base, P.for_romset("zzz_homebrew")), base),
		"specs: no game, or one the table does not know, is the cabinet's own form")
	# An alternating game: ONE panel in the middle, and a second START beside it for player 2.
	var kk := _spec("kurikint")
	var kp: Array = kk["players"]
	_ok(kp.size() == 2 and str(kp[0]["kind"]) == "stick" and str(kp[1]["kind"]) == "start" and int(kp[1]["player"]) == 1
			and str(kp[0].get("label", "")) == "1P" and str(kp[1].get("label", "")) == "2P",
		"specs: Kuri Kinton (alternating) has one panel, 1P, and a START 2P beside it (%s)" % str(_kinds(kk)))
	var ext: Vector2 = S.panel_extent(kp[0])
	_ok(absf((ext.x + ext.y) * 0.5) < 0.01 and float(kp[1]["start_x"]) > ext.y,
		"specs: the shared panel is in the middle of the deck, the 2P START outside it")
	_ok((kk["coins"] as Array).size() == 1, "specs: and one coin door")
	var pac := _spec("pacman")
	_ok(bool(pac["screen"]["vertical"]) and int(pac["screen"]["inches"]) == 19 and (pac["players"] as Array).size() == 2,
		"specs: Pac-Man's monitor stands on its side, 19 inches, one shared panel (%s)" % str(pac.get("screen")))
	_ok((pac["players"][0]["buttons"] as Array).is_empty(), "specs: and Pac-Man's panel has a stick and no buttons")
	var dk := _spec("dkong")
	_ok((dk["players"][0]["buttons"] as Array).size() == 1, "specs: Donkey Kong's has its one jump button")
	var tmnt := _spec("tmnt")
	_ok((tmnt["players"] as Array).size() == 4 and (tmnt["coins"] as Array).size() == 4,
		"specs: TMNT has four panels and four coin doors")
	_ok(S.panels_span(tmnt["players"]) > 0.62 + 0.01 and float(tmnt["width"]) - 0.04 >= S.panels_span(tmnt["players"]) + 0.03,
		"specs: four panels are wider than the generic deck, so the BODY is wider (%.2f m), with a hand's width to spare each side"
			% float(tmnt["width"]))
	var door_xs: Array = tmnt["coins"]
	var centres := S.panel_centres(tmnt["players"])
	var under := door_xs.size() == centres.size()
	for i in mini(door_xs.size(), centres.size()):
		under = under and absf(float(door_xs[i]) - float(centres[i])) < 0.001
	_ok(under, "specs: and each coin door stands under its player's panel (%s)" % str(door_xs))
	_ok(is_equal_approx(float(tmnt["door_width"]), 0.60) and is_equal_approx(float(_spec("sf2").get("width", 0.66)), 0.66),
		"specs: the bay door keeps the 0.60 m it was baked with; a two-player game keeps the generic body")
	var two_buttons := true
	for p: Dictionary in tmnt["players"]:
		two_buttons = two_buttons and (p["buttons"] as Array).size() == 2
	_ok(two_buttons, "specs: each TMNT panel has its two buttons")
	_ok(int(tmnt.get("socket_count", 2)) == 4 and int(_spec("dino").get("socket_count", 2)) == 3
			and not _spec("kurikint").has("socket_count") and not sf2.has("socket_count"),
		"specs: a socket on the front for each player's pad, up to four (two for two players or one shared panel)")
	var x6 := _spec("xmen6p")
	_ok((x6["players"] as Array).size() == 6 and int(x6["screen"]["screens"]) == 2,
		"specs: X-Men 6P has six panels and two screens")
	var robo := _spec("robotron")
	_ok(_kinds(robo) == ["twin"] and (robo["coins"] as Array).size() == 1,
		"specs: Robotron is one panel with two sticks, one coin door (%s)" % str(_kinds(robo)))
	var cent := _spec("centiped")
	_ok(_kinds(cent) == ["ball"] and bool(cent["screen"]["vertical"]), "specs: Centipede has a trackball and a tate monitor")
	_ok(_kinds(_spec("pong")).has("dial"), "specs: Pong has paddle dials")
	# Gun games: the wide body, the guns, their style and their pedals.
	var tc := _spec("timecris")
	_ok(str(tc["shape"]) == "wide" and int(tc["guns"]) == 1 and str(tc["gun_style"]) == "holster"
			and (tc.get("gun_pedals", []) as Array).size() == 1 and not bool(tc["sockets"]),
		"specs: Time Crisis: the gun body, one gun in a holster, one pedal, no sockets")
	var pb := _spec("ptblank")
	_ok(int(pb["guns"]) == 2 and not pb.has("gun_pedals"), "specs: Point Blank: two guns, no pedal")
	_ok(str(_spec("opwolf")["gun_style"]) == "mounted" and int(_spec("opwolf")["guns"]) == 1,
		"specs: Operation Wolf: one gun on a mount")
	var bb := _spec("bbusters")
	_ok(int(bb["guns"]) == 3 and str(bb["gun_style"]) == "mounted" and (bb["coins"] as Array).size() == 2
			and absf(float(bb["coins"][0]) + 0.13) < 0.001,
		"specs: Beast Busters: three mounted guns, two coin doors either side of the middle one")
	var sc := _spec("sscope")
	_ok(str(sc["gun_style"]) == "rifle" and int(sc["guns"]) == 1 and int(sc["screen"]["screens"]) == 1 and sc["screen"].has("scope"),
		"specs: Silent Scope: one rifle, the monitor's own screen and the scope's")
	# The shooters MAME files as a joystick panel, analog sticks or nothing at all (the curated list): each is a gun cabinet with its guns,
	# a pedal for each gun only where the game had them.
	var shooters_bad: Array = []
	for row: Array in [["timecrs3", "holster", 2, true], ["timecrs4", "holster", 2, true], ["timecrs4j", "holster", 2, true],
			["vnight", "holster", 2, false], ["hotd3", "holster", 2, false], ["hotd4", "holster", 2, false],
			["ghostsev", "holster", 2, false], ["ghostsqu", "holster", 2, false], ["vcop3", "holster", 2, false],
			["ninjaslt", "holster", 2, false], ["gunsur2", "holster", 1, false], ["letsgoju", "holster", 2, false],
			["alien3", "mounted", 2, false], ["jpark", "mounted", 2, false], ["gunblade", "mounted", 2, false],
			["rchase2", "mounted", 2, false], ["oceanhun", "mounted", 2, false],
			["timecris", "holster", 1, true], ["timecrs2", "holster", 1, true], ["crszone", "holster", 1, true]]:
		var sp := _spec(str(row[0]))
		var pedals_n := (sp.get("gun_pedals", []) as Array).size()
		if not (str(sp.get("form", "")) in ["gun", "gunm"] and str(sp.get("shape", "")) == "wide" and str(sp.get("gun_style", "")) == str(row[1])
				and int(sp.get("guns", 0)) == int(row[2]) and not bool(sp.get("sockets", true))
				and pedals_n == (int(row[2]) if bool(row[3]) else 0) and (sp["players"] as Array).size() == int(row[2])):
			shooters_bad.append("%s (%s)" % [row[0], str(sp.get("form", "own"))])
	_ok(shooters_bad.is_empty(), "specs: every shooter is a wide gun cabinet with its guns (cords or mounts), no sockets, a START for each gun, a pedal under each only for Time Crisis and Crisis Zone (%s)" % str(shooters_bad))
	# A two-gun game's panels are START alone for each gun, and a door under each.
	_ok(_kinds(pb) == ["start", "start"] and (pb["coins"] as Array).size() == 2 and not bool(pb["sockets"]),
		"specs: Point Blank: a START for each gun and a coin door under each")
	# Driving: a cockpit (and its roof), a stand-up panel, a bike.
	var dt := _spec("daytona")
	_ok(str(dt["shape"]) == "racer" and dt.has("cockpit") and not bool(dt["cockpit"]["roof"]) and (dt["players"] as Array).is_empty(),
		"specs: Daytona USA is a sit-down cockpit with no roof")
	_ok(bool(_spec("scud")["cockpit"]["roof"]), "specs: Scud Race's cockpit has a roof")
	var pp := _spec("polepos")
	_ok(_kinds(pp) == ["wheel"] and str(pp["shape"]) == "upright" and bool(pp["screen"]["vertical"]) == false,
		"specs: Pole Position is a stand-up wheel panel")
	_ok(_spec("hangon").has("bike") and str(_spec("hangon")["shape"]) == "racer", "specs: Hang-On is a ride-on bike")
	# Dancing: a stage, four arrows (DDR) or five (Pump It Up), a square per dancer.
	var ddr := _spec("ddrusa")
	_ok(ddr.has("stage") and int(ddr["stage"]["arrows"]) == 4 and (ddr["stage"]["xs"] as Array).size() == 2
			and _kinds(ddr) == ["pad", "pad"], "specs: DDR is a stage with two squares of four arrows")
	_ok(int(_spec("pumpipx2")["stage"]["arrows"]) == 5, "specs: Pump It Up's squares have five panels")
	# The unusual cabinets are uprights until they have a module of their own.
	_ok(not _spec("timetrv").has("cockpit") and str(_spec("timetrv")["shape"]) == "upright",
		"specs: Time Traveler is drawn as an upright for now")


func _same(a: Variant, b: Variant) -> bool:
	return S._same_value(a, b)


# --- layout --------------------------------------------------------------------

func _group_layout() -> void:
	# The generic cabinet's panels ARE the layout of two players with six buttons.
	var two := S.layout_panels("stick", 2, 6)
	_ok(_same(two, S.variant("generic")["players"]),
		"layout: two players with six buttons stand exactly where the generic cabinet's always did")
	for n in [1, 2, 3, 4, 6]:
		var panels := S.layout_panels("stick", n, 3)
		var apart := true
		for i in range(1, panels.size()):
			apart = apart and S.panel_extent(panels[i]).x >= S.panel_extent(panels[i - 1]).y - 0.0001
		var reach := S.panels_span(panels) * 0.5
		var mid := (S.panel_extent(panels[0]).x + S.panel_extent(panels[-1]).y) * 0.5
		_ok(panels.size() == n and apart and absf(mid) < 0.01,
			"layout: %d panel(s) side by side without overlapping, centred on the deck (reach %.2f)" % [n, reach])
	for kind in ["stick", "twin", "ball", "dial", "buttons"]:
		for b in [0, 1, 2, 3, 4, 5, 6]:
			var p := S.panel(kind, b, 0.0, 0)
			var e := S.panel_extent(p)
			_ok(absf((e.x + e.y) * 0.5) < 0.02 and absf((e.y - e.x) - S.panel_width(kind, b)) < 0.035
					and (p.get("buttons", []) as Array).size() == clampi(b, 0, 6),
				"layout: a %s panel with %d button(s) is as wide as its parts and centred (%.3f..%.3f)" % [kind, b, e.x, e.y])


# --- build ---------------------------------------------------------------------

func _group_build() -> void:
	var sys := await _machine()
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	_ok(not model.form_spec().is_empty() and str(model.form_spec().get("variant", "")) == "generic",
		"build: the generic cabinet knows the row it was baked from")
	var base_screen := model.get_builtin_screen().mesh as QuadMesh
	var base_size := base_screen.size
	var base_forms := _form_count(model)
	# A tate game: the tube stands on its side, the picture is fitted to it.
	model.morph_to(_spec("pacman"))
	await _wait(2)
	var tube := (model.get_builtin_screen().mesh as QuadMesh).size
	var screen := model.modules_of_kind(ArcadeProfiles.KIND_SCREEN)[0] as ArcadeScreenModule
	_ok(tube.y > tube.x and screen.glass_size.is_equal_approx(tube),
		"build: Pac-Man's tube stands on its side (%.3f x %.3f), and the picture is fitted to it" % [tube.x, tube.y])
	_ok(tube.y < base_size.x, "build: a 19-inch tube is smaller than the cabinet's own 25-inch one")
	_ok(_panels(model).size() == 2 and (_panels(model)[1] as ArcadeControlModule).grip().momentary
			and model.find_child("StartLabel", true, false) != null,
		"build: one shared panel and a momentary 2P START, each START labelled")
	_ok(_doors(model).size() == 1, "build: one coin door")
	# Four players: four panels on a body as wide as they need, no wings.
	model.morph_to(_spec("tmnt"))
	await _wait(2)
	_ok(_panels(model).size() == 4 and model.find_child("DeckWingL", true, false) == null and _doors(model).size() == 4
			and is_equal_approx(model.cabinet_width, float(_spec("tmnt")["width"])),
		"build: TMNT builds four panels and four coin doors on a body %.2f m wide, with no wings on the deck" % model.cabinet_width)
	var players_ok := true
	for i in 4:
		players_ok = players_ok and (_panels(model)[i] as ArcadeControlModule).player == i
	_ok(players_ok, "build: each panel plays its own port, in order")
	var sockets := model.modules_of_kind(ArcadeProfiles.KIND_SOCKETS)[0] as ArcadeSocketModule
	var zones_on := 0
	for z: Node in sys._port_zones:
		zones_on += 1 if (z as XRToolsSnapZone).enabled else 0
	_ok(sockets.seat_count() == 4 and zones_on == 4, "build: and four front sockets, each a live port (%d)" % zones_on)
	# Every form builds: guns, cockpit, bike, stage, a stand-up wheel, a trackball, twin sticks.
	for romset in ["timecris", "opwolf", "sscope", "bbusters", "daytona", "scud", "polepos", "hangon", "ddrusa",
			"pumpipx2", "robotron", "centiped", "xmen6p", "pong"]:
		model.morph_to(_spec(romset))
		await _wait(2)
		var spec := model.form_spec()
		_ok(str(spec.get("form", "")) == P.for_romset(romset).form() and _panels(model).size() >= 1,
			"build: %s builds its form (%s, %d panel(s))" % [romset, str(spec.get("form", "")), _panels(model).size()])
	model.morph_to(_spec("daytona"))
	await _wait(2)
	var cockpit := model.find_child("Cockpit", false, false)
	var p1 := _panels(model)[0] as ArcadeControlModule
	_ok(cockpit != null and p1.find_child("WheelPivot", true, false) != null and p1.find_child("GasPivot", true, false) != null
			and p1.find_child("BrakePivot", true, false) != null and cockpit.find_child("SeatBack", true, false) != null,
		"build: the cockpit has a seat, and the driver's controller is the wheel and the two pedals")
	_ok(model.find_child("Roof", true, false) == null, "build: Daytona's cockpit has no roof")
	var back := cockpit.find_child("SeatBack", true, false) as Node3D
	_ok(back.basis.y.z > 0.1, "build: the seat's back leans back, away from the screen (%s)" % str(back.basis.y))
	model.morph_to(_spec("scud"))
	await _wait(2)
	_ok(model.find_child("Roof", true, false) != null and model.find_child("RoofSign", true, false) != null,
		"build: Scud Race's has a roof with its sign")
	model.morph_to(_spec("ddrusa"))
	await _wait(2)
	var arrows := 0
	for panel: ArcadeControlModule in _panels(model):
		for n in ["PadUp", "PadDown", "PadLeft", "PadRight"]:
			arrows += 1 if panel.find_child(n, true, false) != null else 0
	_ok(model.find_child("Stage", false, false) != null and arrows == 8, "build: DDR's stage has four arrows for each dancer")
	model.morph_to(_spec("robotron"))
	await _wait(2)
	_ok(_panels(model)[0].find_child("StickPivot2", true, false) != null, "build: Robotron's panel has its second stick")
	# Back to the cabinet's own: the same parts it was baked with.
	model.morph_to(model._base_spec)
	await _wait(2)
	_ok(_panels(model).size() == 2 and _doors(model).size() == 2
			and (model.get_builtin_screen().mesh as QuadMesh).size.is_equal_approx(base_size)
			and model.find_child("Stage", false, false) == null and model.find_child("Cockpit", false, false) == null,
		"build: and back to its own two panels, two doors and its tube")
	_ok(_form_count(model) == base_forms, "build: no form part is left over from the forms before (%d)" % base_forms)


func _form_count(model: Node) -> int:
	var forms := 0
	for c in model.get_children():
		forms += 1 if c.has_meta(ArcadeCabinetBuilder.FORM_META) else 0
	return forms


# --- board ---------------------------------------------------------------------

func _group_board() -> void:
	var sys := await _machine()
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	await _board(sys, "tmnt")
	_ok(_panels(model).size() == 4 and model.game_profile() != null and model.game_profile().romset == "tmnt",
		"board: a TMNT board makes the cabinet a four-player one")
	await _pull(sys)
	_ok(_panels(model).size() == 2 and model.game_profile() == null and str(model.form_spec().get("form", "")) == "",
		"board: pulling it gives the cabinet its own form back")
	await _board(sys, "sf2")
	var before: Array = _panels(model)
	await _board(sys, "sf2")
	_ok(_panels(model) == before, "board: a game that wants the cabinet as it is rebuilds nothing")
	await _pull(sys)
	await _board(sys, "dino")
	var dino_ok := _panels(model).size() == 3
	for panel: ArcadeControlModule in _panels(model):
		dino_ok = dino_ok and panel.cap_shown(0) and panel.cap_shown(1) and not panel.cap_shown(2)
	_ok(dino_ok, "board: Cadillacs and Dinosaurs: three panels, two caps each")
	# The art hangs in the new form's slots.
	var wheel := ImageTexture.create_from_image(Image.create(60, 20, false, Image.FORMAT_RGBA8))
	ArcadeCabinetArt.test_art["/tmp/kurikint.zip"] = {"wheel": wheel, "cover": null}
	await _board(sys, "kurikint")
	ArcadeCabinetArt.test_art.erase("/tmp/kurikint.zip")
	var mq := model.find_child("MarqueeArt", true, false) as MeshInstance3D
	_ok(_panels(model).size() == 2 and mq != null and mq.visible
			and (mq.material_override as StandardMaterial3D).albedo_texture == wheel,
		"board: the game's art hangs in the slots of its new form")


# --- tate ----------------------------------------------------------------------

## The window the monitor module shows the picture through and the tube behind it, metres.
func _window(model: Node) -> Dictionary:
	var glass := model.find_child("Glass", true, false) as MeshInstance3D
	return {"glass": (glass.mesh as QuadMesh).size, "tube": ((model as RetroSystemModelArcadeCabinet).get_builtin_screen().mesh as QuadMesh).size}


func _group_tate() -> void:
	# Every body is ONE silhouette: the glass edge and the marquee's underside meet at its corner, the highest
	# point is the body's height, and the marquee stands between them.
	for shape_name: String in S.shapes():
		var sh: Dictionary = S.shapes()[shape_name]
		var outline: Array = sh["profile"]
		var a: Vector2 = sh["glass_a"]
		var b: Vector2 = sh["glass_b"]
		var top := 0.0
		for p: Vector2 in outline:
			top = maxf(top, p.y)
		var mq: Dictionary = sh["marquee"]
		var lo := float(mq["y"]) - float(mq["h"]) * 0.5
		var hi := float(mq["y"]) + float(mq["h"]) * 0.5
		_ok(outline.has(a) and outline.has(b) and is_equal_approx(top, float(sh["h"]))
				and is_equal_approx(float(sh["marquee_bottom"]), b.y) and lo >= b.y - 0.001 and hi <= top + 0.001,
			"tate: the %s body is one silhouette (glass %s to %s, marquee %.2f..%.2f, top %.2f)" % [shape_name, a, b, lo, hi, top])
	# The tall body is the upright's with a longer glass up the same slant.
	var up: Dictionary = S.shapes()["upright"]
	var ta: Dictionary = S.shapes()["tate"]
	var up_edge: Vector2 = (up["glass_b"] as Vector2) - (up["glass_a"] as Vector2)
	var ta_edge: Vector2 = (ta["glass_b"] as Vector2) - (ta["glass_a"] as Vector2)
	var lower := true
	for i in 8:
		lower = lower and (up["profile"][i] as Vector2) == (ta["profile"][i] as Vector2)
	_ok(lower and up_edge.normalized().is_equal_approx(ta_edge.normalized()) and ta["glass_a"] == up["glass_a"]
			and is_equal_approx(float(ta["w"]), float(up["w"])) and ta_edge.length() > up_edge.length() + 0.1,
		"tate: the upright's lower body, deck and lean, the glass %.2f m longer (%.2f against %.2f)"
			% [ta_edge.length() - up_edge.length(), ta_edge.length(), up_edge.length()])
	# Which games get it: a monitor on its side, and nobody else.
	for romset in ["batsugun", "1943", "galaga", "pacman", "dkong", "centiped"]:
		var spec := _spec(romset)
		_ok(str(spec["shape"]) == "tate" and bool(spec["screen"]["vertical"]),
			"tate: %s, a monitor on its side, gets the tall body" % romset)
	for romset in ["sf2", "polepos", "timecris", "daytona", "hangon", "ddrusa"]:
		_ok(str(_spec(romset).get("shape", "upright")) != "tate", "tate: %s, a monitor the right way up, does not" % romset)
	# On a cabinet: the baked one cuts its window to its tube, and a vertical game's board changes both.
	var sys := await _machine()
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	var own := _window(model)
	var own_tube: Vector2 = own["tube"]
	var own_glass: Vector2 = own["glass"]
	_ok(is_equal_approx(own_glass.x, own_tube.x + 0.06) and is_equal_approx(own_glass.y, own_tube.y + 0.06),
		"tate: the cabinet's own window is its tube and 3 cm round it (%s in %s)" % [own_tube, own_glass])
	await _board(sys, "batsugun")
	var w := _window(model)
	var tube: Vector2 = w["tube"]
	var glass: Vector2 = w["glass"]
	_ok(tube.y > tube.x and glass.y > glass.x and absf(tube.x / tube.y - 0.75) < 0.01,
		"tate: Batsugun's picture is 3:4 and the window it is seen through is taller than wide (%s in %s)" % [tube, glass])
	_ok(tube.y > 0.45 and tube.x > 0.34,
		"tate: and as big as a 25 inch tube stood up (%.2f x %.2f), not the 0.30 x 0.40 the upright's window left" % [tube.x, tube.y])
	var margin_x := (glass.x - tube.x) * 0.5
	var margin_y := (glass.y - tube.y) * 0.5
	_ok(absf(margin_x - 0.03) < 0.002 and absf(margin_y - 0.03) < 0.003,
		"tate: the picture has 3 cm of black round it, side and top alike (%.3f, %.3f)" % [margin_x, margin_y])
	_ok(is_equal_approx(model.cabinet_height, float(ta["h"])) and is_equal_approx(model.marquee_bottom, float(ta["marquee_bottom"]))
			and is_equal_approx(model.glass_back_z, float(ta["glass_back_z"])),
		"tate: the model's height and marquee follow the body (%.2f, glass back %.2f)" % [model.cabinet_height, model.glass_back_z])
	var side := model.find_child("FrameSideL", true, false) as MeshInstance3D
	var body: Color = S.variant("generic")["body"]
	_ok(side != null and (side.get_active_material(0) as StandardMaterial3D).albedo_color.is_equal_approx(body)
			and is_equal_approx((side.mesh as BoxMesh).size.x, (0.62 - glass.x) * 0.5),
		"tate: the front beside the window is the cabinet's own board, as wide as the window leaves it")
	# The marquee stands over the glass and the glass on the deck: nothing of the window is hidden by either.
	var pane := model.find_child("Glass", true, false) as Node3D
	var half := pane.global_basis.y * glass.y * 0.5
	var edge_lo := model.to_local(pane.global_position - half).y
	var edge_hi := model.to_local(pane.global_position + half).y
	_ok(edge_lo >= (ta["glass_a"] as Vector2).y and edge_hi <= float(ta["marquee_bottom"]),
		"tate: the window sits between the deck and the marquee (%.2f..%.2f of %.2f..%.2f)" % [edge_lo, edge_hi,
			(ta["glass_a"] as Vector2).y, float(ta["marquee_bottom"])])
	await _pull(sys)
	var back := _window(model)
	_ok(is_equal_approx(model.cabinet_height, float(up["h"])) and (back["tube"] as Vector2).is_equal_approx(own_tube)
			and (back["glass"] as Vector2).is_equal_approx(own_glass),
		"tate: pulling the board gives the upright, its tube and its window back")
	await _board(sys, "sf2")
	_ok(is_equal_approx(model.cabinet_height, float(up["h"])) and (_window(model)["tube"] as Vector2).is_equal_approx(own_tube),
		"tate: a game the right way up keeps the upright (1.80 m)")
	await _pull(sys)
	await _board(sys, "pacman")
	var pac := _window(model)
	_ok(is_equal_approx(model.cabinet_height, float(ta["h"])) and (pac["tube"] as Vector2).y < tube.y
			and (pac["tube"] as Vector2).y > (pac["tube"] as Vector2).x
			and is_equal_approx((pac["glass"] as Vector2).y, (pac["tube"] as Vector2).y + 0.06),
		"tate: Pac-Man's 19 inch tube is smaller than Batsugun's in a window cut to it (%s in %s)" % [pac["tube"], pac["glass"]])


# --- wide ----------------------------------------------------------------------

func _group_wide() -> void:
	# The body is the shape's while the panels fit its deck, else as wide as they need.
	_ok(is_equal_approx(S.body_width(0.66, S.variant("generic")["players"]), 0.66),
		"wide: the generic two panels fit the generic body")
	var last := 0.0
	for romset in ["dino", "tmnt", "xmen6p"]:
		var spec := _spec(romset)
		var w := float(spec["width"])
		var span := S.panels_span(spec["players"])
		_ok(is_equal_approx(w, span + 0.08) and w > last,
			"wide: %s's body is %.2f m, its panels' span and 8 cm (%.2f), wider than the one before" % [romset, w, span])
		last = w
	# A player has a third of a metre of the deck at least (a real four-player cabinet was 1.2 m: twelve inches a head).
	var pitch_ok := true
	for romset in ["dino", "tmnt", "xmen6p"]:
		var cs := S.panel_centres(_spec(romset)["players"])
		for i in range(1, cs.size()):
			pitch_ok = pitch_ok and float(cs[i]) - float(cs[i - 1]) >= 0.299
	_ok(pitch_ok, "wide: three, four and six players each have at least 30 cm of the deck")
	# Four players and two coin slots (Cotton 2): the two doors are spread over its body, not left bunched in the
	# middle where the generic cabinet's two stand.
	var cot := _spec("cotton2")
	_ok((cot["players"] as Array).size() == 4 and (cot["coins"] as Array).size() == 2 and absf(float(cot["coins"][0])) > 0.2,
		"wide: Cotton 2 has four panels and two coin slots, the doors spread over its body (%s)" % str(cot["coins"]))
	_ok(is_equal_approx(float(_spec("timecris", "daphne_gun")["door_width"]), 0.84)
			and is_equal_approx(float(_spec("tmnt")["door_width"]), 0.60),
		"wide: the bay's door keeps the width its cabinet was baked with (a wide base's is its own)")
	# Built on a real cabinet.
	var sys := await _machine()
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	for romset in ["dino", "tmnt", "xmen6p"]:
		var spec := _spec(romset)
		model.morph_to(spec)
		await _wait(2)
		var in_w := float(spec["width"]) - 0.04
		var plate := model.find_child("DeckPlate", true, false) as MeshInstance3D
		var starts_in := true
		var lowest := 9.0
		for panel: ArcadeControlModule in _panels(model):
			var x := model.to_local((panel.find_child("Start", true, false) as Node3D).global_position).x
			starts_in = starts_in and absf(x) <= in_w * 0.5 - 0.01
			lowest = minf(lowest, x)
		_ok(is_equal_approx((plate.mesh as BoxMesh).size.x, in_w) and starts_in and is_equal_approx(model.cabinet_width, float(spec["width"]))
				and model.find_child("DeckWingL", true, false) == null and model.ground_footprint().x < float(spec["width"]) + 0.01,
			"wide: %s's deck runs side to side of a %.2f m body, every START on it, no wings (footprint %s)"
				% [romset, float(spec["width"]), str(model.ground_footprint())])
		var centres := S.panel_centres(spec["players"])
		var doors := _doors(model)
		var under := true
		var door_lo := 9.0
		var door_hi := -9.0
		for i in doors.size():
			var dx := (doors[i] as Node3D).position.x
			door_lo = minf(door_lo, dx)
			door_hi = maxf(door_hi, dx)
			# A door for every panel stands under it; fewer doors (X-Men 6P has four slots) are spread, centred.
			if doors.size() == centres.size():
				under = under and absf(dx - float(centres[i])) < 0.002
		under = under and absf(door_lo + door_hi) < 0.01 and door_hi < in_w * 0.5 and door_hi > 0.1
		_ok(under, "wide: %s: %d coin door(s), centred on the body and each under its panel when there is one for each (%.2f..%.2f)"
			% [romset, doors.size(), door_lo, door_hi])
		var seats := model.modules_of_kind(ArcadeProfiles.KIND_SOCKETS)[0] as ArcadeSocketModule
		var seat_ok := seats.seat_count() == int(spec.get("socket_count", 2))
		var seat_lo := 9.0
		var seat_hi := -9.0
		for i in seats.seat_count():
			var sx := model.to_local((seats.find_child("PortSeat%d" % (i + 1), true, false) as Node3D).global_position).x
			seat_ok = seat_ok and absf(sx) < in_w * 0.5
			seat_lo = minf(seat_lo, sx)
			seat_hi = maxf(seat_hi, sx)
		var seat_under := seats.seat_count() != centres.size()
		if not seat_under:
			seat_under = true
			for i in seats.seat_count():
				var seat_x := model.to_local((seats.find_child("PortSeat%d" % (i + 1), true, false) as Node3D).global_position).x
				seat_under = seat_under and absf(seat_x - float(centres[i])) < 0.002
		seat_ok = seat_ok and seat_under and seat_lo < -in_w * 0.25
		_ok(seat_ok and seat_hi > in_w * 0.25 and absf(seat_lo + seat_hi) < 0.01,
			"wide: %s: the pad sockets are spread over the apron, centred (%.2f..%.2f)" % [romset, seat_lo, seat_hi])
		var face := model.find_child("LowerFaceL", true, false) as MeshInstance3D
		_ok(face != null and is_equal_approx((face.mesh as BoxMesh).size.x, (in_w - 0.60) * 0.5)
				and is_equal_approx(model.to_local(face.global_position).x, -(0.30 + (in_w - 0.60) * 0.25)),
			"wide: %s: the front beside the bay's 0.60 m door is closed" % romset)
	# The generic body (no lower face to close), and a wide gun body built on it (a lower face to close).
	model.morph_to(model._base_spec)
	await _wait(2)
	_ok(model.find_child("LowerFaceL", true, false) == null, "wide: the generic body has nothing beside the door to close")
	model.morph_to(_spec("timecris"))
	await _wait(2)
	_ok(model.find_child("LowerFaceL", true, false) != null, "wide: a gun cabinet's 0.90 m body is closed beside the door too")



# --- picture -------------------------------------------------------------------

## The picture a spec's cabinet is drawn with: the real builder's tube_of, on the spec's own body.
func _tube(spec: Dictionary) -> Vector2:
	return ArcadeCabinetBuilder.tube_of(spec)


func _group_picture() -> void:
	var up: Dictionary = S.shapes()["upright"]
	var tall: Dictionary = S.shapes()["tall"]
	var up_tube: Vector2 = up["tube"]
	var tall_edge: Vector2 = (tall["glass_b"] as Vector2) - (tall["glass_a"] as Vector2)
	# The widest picture the tall glass holds with its black round it: its edge less the frame, as a 4:3 tube is wide.
	var cap := (tall_edge.length() - S.GLASS_FRAME) / 0.75
	# A body the panels fit keeps the upright's own tube: nothing a two-player game saw changes.
	_ok(S.wide_picture(0.66).is_empty() and S.wide_picture(0.74).is_empty(),
		"picture: a body of the generic width, and one a hand wider, keep the upright's own tube")
	for row: Array in [["sf2", "upright"], ["kurikint", "upright"], ["pacman", "tate"], ["daytona", "racer"]]:
		var sp := _spec(str(row[0]))
		_ok(str(sp.get("shape", "upright")) == str(row[1]) and is_equal_approx(float(sp.get("width", 0.66)), 0.66),
			"picture: %s keeps the generic %s body (%s, %.2f m)" % [row[0], row[1], sp.get("shape", "upright"), float(sp.get("width", 0.66))])
	_ok(_tube(_spec("sf2")).is_equal_approx(up_tube) and _tube(_spec("kurikint")).is_equal_approx(up_tube),
		"picture: and the upright's 0.44 x 0.33 tube (Street Fighter II, Kuri Kinton)")
	# Past it the picture is a share of the body and grows with it: the upright's glass while it holds the tube, then the tall one's.
	var last := 0.0
	var seen_tall := false
	var shares_ok := true
	var order_ok := true
	var given_ok := true
	var asked_wide := true
	for w in [0.80, 0.85, 0.90, 0.95, 1.0, 1.1, 1.2, 1.3, 1.5, 2.0]:
		var pic := S.wide_picture(w)
		if pic.is_empty():
			asked_wide = false
			continue
		var shape_name := str(pic["shape"])
		var spec := {"shape": shape_name, "width": w, "screen": {"vertical": false, "screens": 1, "inches": int(pic["inches"])}}
		var t := _tube(spec)
		# The tube it asks for is the tube it gets: the glass had room, nothing was squeezed to fit it.
		var native: Vector2 = S.shapes()[shape_name]["tube"]
		var asked := native * (float(pic["inches"]) / float(S.shapes()[shape_name]["inches"]))
		given_ok = given_ok and absf(t.x - asked.x) < 0.012 and absf(t.y - asked.y) < 0.012 and t.x >= last - 0.001
		shares_ok = shares_ok and (t.x / w >= S.PICTURE_SHARE - 0.02 or t.x >= cap - 0.01)
		order_ok = order_ok and (shape_name == "tall" or not seen_tall)
		seen_tall = seen_tall or shape_name == "tall"
		last = t.x
	_ok(asked_wide, "picture: every body from 0.80 m up asks for a bigger picture than the upright's")
	_ok(given_ok, "picture: a wider body gets a bigger picture, and the one it asks for is the one it is given (not squeezed)")
	_ok(shares_ok, "picture: it takes %d%% of the body's width, or all the tall glass holds (%.2f m)" % [roundi(S.PICTURE_SHARE * 100.0), cap])
	_ok(order_ok and seen_tall, "picture: the upright's glass is used while it holds the tube, then the tall body, and never back")
	# A picture asked for that the glass cannot hold is fitted to it whole, never squashed: the same aspect, inside the edge and the sides.
	var huge := _tube({"shape": "tall", "width": 1.2, "screen": {"vertical": false, "screens": 1, "inches": 99}})
	_ok(absf(huge.y / huge.x - 0.75) < 0.001 and huge.y <= tall_edge.length() - S.GLASS_FRAME + 0.001 and huge.x <= 1.2 - 0.04 - S.GLASS_SIDES + 0.001,
		"picture: and one the glass cannot hold is fitted to it whole, 4:3 still (%.2f x %.2f)" % [huge.x, huge.y])
	var twin := _tube({"shape": "tall", "width": 1.0, "screen": {"vertical": false, "screens": 2, "inches": 36}})
	_ok(twin.x <= 1.0 - 0.04 - S.GLASS_SIDES + 0.001 and twin.x > 0.8, "picture: two screens side by side fill the body between its sides and no more (%.2f m)" % twin.x)
	var big := S.wide_picture(2.0)
	var biggest := _tube({"shape": "tall", "width": 2.0, "screen": {"vertical": false, "screens": 1, "inches": int(big.get("inches", 25))}})
	_ok(int(big.get("inches", 0)) == 40 and biggest.x <= cap + 0.012 and biggest.y + 0.06 <= tall_edge.length() - 0.11 + 0.001,
		"picture: the biggest picture the tall glass holds is %.2f x %.2f, a 40 inch class, with its 3 cm of black round it" % [biggest.x, biggest.y])
	# The tall body is the tate body with the glass longer up the same slant: nothing below the glass moves, the rest rises with it.
	var ta: Dictionary = S.shapes()["tate"]
	var ta_edge: Vector2 = (ta["glass_b"] as Vector2) - (ta["glass_a"] as Vector2)
	var below := true
	for i in 8:
		below = below and (tall["profile"][i] as Vector2) == (ta["profile"][i] as Vector2)
	_ok(below and tall["glass_a"] == ta["glass_a"] and tall_edge.normalized().is_equal_approx(ta_edge.normalized())
			and absf(tall_edge.length() - ta_edge.length() - S.TALL_EXTRA) < 0.001
			and absf(float(tall["h"]) - float(ta["h"]) - S.TALL_EXTRA * ta_edge.normalized().y) < 0.001
			and is_equal_approx(float(tall["w"]), float(ta["w"])),
		"picture: the tall body is the tate body's with the glass %.2f m longer (%.2f against %.2f), %.2f m of cabinet"
			% [S.TALL_EXTRA, tall_edge.length(), ta_edge.length(), float(tall["h"])])
	# The games the player noticed: three players, four, six.
	for row: Array in [["dino", 0.50], ["avsp", 0.55], ["tmnt", 0.65], ["tmnt2", 0.65], ["simpsons", 0.65], ["captcomm", 0.65],
			["gauntleg", 0.65]]:
		var sp := _spec(str(row[0]))
		var t := _tube(sp)
		var width := float(sp["width"])
		_ok(str(sp["shape"]) == "tall" and t.x >= float(row[1]) and t.x / width >= 0.50 and not bool(sp["screen"]["vertical"]),
			"picture: %s (%d players, a %.2f m body) shows a %.2f x %.2f picture, %d%% of the body, in the %s body"
				% [row[0], (sp["players"] as Array).size(), width, t.x, t.y, roundi(t.x / width * 100.0), sp["shape"]])
	# A monitor on its side stays on the tate body however wide the panels make it: a tall narrow picture, not a landscape one.
	for romset in ["asylum", "ddp2"]:
		var sp := _spec(romset)
		_ok(str(sp["shape"]) == "tate" and bool(sp["screen"]["vertical"]) and float(sp["width"]) > 0.85
				and _tube(sp).y > _tube(sp).x,
			"picture: %s (%d players, a %.2f m body) keeps the tate body and its picture stood on its side" % [romset, (sp["players"] as Array).size(), float(sp["width"])])
	var xm := _spec("xmen6p")
	_ok(_tube(xm).x >= 1.2 and int(xm["screen"]["screens"]) == 2 and _tube(xm).x / float(xm["width"]) >= 0.6,
		"picture: X-Men's two screens are one wide picture across the six-player body (%.2f of %.2f m)" % [_tube(xm).x, float(xm["width"])])
	# The whole table: no single-screen picture is lost in its body, and no big-screen cabinet has a small one.
	var worst := 1.0
	var worst_name := ""
	var lost: Array = []
	var small: Array = []
	var measured := 0
	var big_forms := [P.FORM_GUN, P.FORM_GUN_MOUNTED, P.FORM_RIFLE, P.FORM_DANCE, P.FORM_PUMP, P.FORM_CYCLE]
	var base := S.variant("generic")
	base["variant"] = "generic"
	for line in ArcadeGameTable.TABLE.split("\n", false):
		var parts := line.split(" ", false)
		if parts.size() < 2:
			continue
		var romset := str(parts[1]).split("=")[0].split("<")[0]
		var gp := P.from_key(romset, parts[0])
		if not gp.known:
			continue
		var sp := S.for_game(base, gp)
		var shape_name := str(sp.get("shape", "upright"))
		var t := _tube(sp)
		var width := float(sp.get("width", S.shapes()[shape_name]["w"]))
		measured += 1
		if shape_name in ["upright", "tall"] and not gp.is_vertical() and gp.screens() == 1 and width > 0.76 and t.x < cap - 0.01:
			var share := t.x / width
			if share < worst:
				worst = share
				worst_name = romset
			if share < S.PICTURE_SHARE - 0.03:
				lost.append(romset)
		if gp.form() in big_forms and not gp.is_vertical() and gp.screens() == 1 and t.x < 0.71:
			small.append(romset)
	_ok(lost.is_empty(), "picture: no single-screen upright game's picture is under %d%% of its body (%s)"
		% [roundi((S.PICTURE_SHARE - 0.03) * 100.0), str(lost.slice(0, 6))])
	_ok(small.is_empty(), "picture: every gun, rifle, dance, pump and cycle cabinet has its body's own 0.72 m tube (%s)" % str(small.slice(0, 6)))
	_ok(measured > 1500 and worst > 0.5, "picture: %d profiles measured, the smallest share %.2f (%s)" % [measured, worst, worst_name])
	# On a real cabinet: the body, the window and the model's height follow, and the board's removal gives the upright back.
	var sys := await _machine()
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	var own := _window(model)
	await _board(sys, "tmnt2")
	var w4 := _window(model)
	var tube4: Vector2 = w4["tube"]
	var glass4: Vector2 = w4["glass"]
	_ok(tube4.is_equal_approx(_tube(_spec("tmnt2"))) and is_equal_approx(glass4.x, tube4.x + 0.06) and is_equal_approx(glass4.y, tube4.y + 0.06)
			and tube4.x > (own["tube"] as Vector2).x * 1.4,
		"picture: Turtles in Time on a cabinet: a %.2f x %.2f picture in a window cut to it, %.0f%% bigger than the upright's"
			% [tube4.x, tube4.y, (tube4.x / (own["tube"] as Vector2).x - 1.0) * 100.0])
	_ok(is_equal_approx(model.cabinet_height, float(tall["h"])) and is_equal_approx(model.cabinet_width, float(_spec("tmnt2")["width"])),
		"picture: and the body follows (%.2f m tall, %.2f m wide)" % [model.cabinet_height, model.cabinet_width])
	var pane := model.find_child("Glass", true, false) as Node3D
	var half := pane.global_basis.y * glass4.y * 0.5
	var lo := model.to_local(pane.global_position - half).y
	var hi := model.to_local(pane.global_position + half).y
	_ok(lo >= (tall["glass_a"] as Vector2).y and hi <= float(tall["marquee_bottom"]),
		"picture: the window sits between the deck and the marquee of the tall body (%.2f..%.2f of %.2f..%.2f)"
			% [lo, hi, (tall["glass_a"] as Vector2).y, float(tall["marquee_bottom"])])
	await _pull(sys)
	var back := _window(model)
	_ok(is_equal_approx(model.cabinet_height, float(up["h"])) and (back["tube"] as Vector2).is_equal_approx(up_tube),
		"picture: pulling the board gives the upright and its 0.44 m tube back")
	await _board(sys, "opwolf")
	_ok((_window(model)["tube"] as Vector2).is_equal_approx(S.shapes()["wide"]["tube"]),
		"picture: Operation Wolf's cabinet has the wide body's whole tube (0.72 x 0.54), not a 25 inch one in a 40 inch frame")


# --- screens -------------------------------------------------------------------

## The scope screen of the rifle a machine wears, or null.
func _scope_lens(sys: RetroSystem) -> MeshInstance3D:
	for gun: Variant in sys.captive_controllers():
		if is_instance_valid(gun):
			var found := (gun as Node).find_child("ScopeScreen", true, false) as MeshInstance3D
			if found != null:
				return found
	return null


func _group_screens() -> void:
	var tall: Dictionary = S.shapes()["tall"]
	var tall_edge: Vector2 = (tall["glass_b"] as Vector2) - (tall["glass_a"] as Vector2)
	# The frame MAME draws and the shape of a tube: the same, whatever the glass has to scale it down to.
	var frame_ok := true
	var aspect_name := ""
	# Silent Scope: the monitor shows the first screen, the scope the second, cut out of the one frame (Dual Side-by-Side, 8.03 x 3).
	for romset in ["sscope", "sscope2", "sscopeaa", "sscope2jvd1", "sscopeacvd2"]:
		var sp := _spec(romset)
		var scope: Dictionary = sp["screen"].get("scope", {})
		var main_part: Array = scope.get("main", [])
		var lens_part: Array = scope.get("lens", [])
		_ok(not scope.is_empty() and int(scope["index"]) == 1 and str(sp["shape"]) == "wide"
				and _tube(sp).is_equal_approx(S.shapes()["wide"]["tube"])
				and absf(float(main_part[0])) < 0.0001 and absf(float(main_part[2]) - 4.0 / 8.03) < 0.0005 and float(main_part[3]) == 1.0
				and absf(float(lens_part[0]) - 4.03 / 8.03) < 0.0005 and absf(float(lens_part[2]) - 4.0 / 8.03) < 0.0005
				and absf(float(scope["aspect"]) - 8.03 / 3.0) < 0.002,
			"screens: %s: the monitor has the left half of the frame on the wide body's whole tube, the scope the right (%s | %s)" % [romset, main_part, lens_part])
	for romset in ["sscopex", "golgo13", "sf2", "timecris", "pc_smb", "darius"]:
		_ok(not (_spec(romset).get("screen", {}) as Dictionary).has("scope"), "screens: %s has no scope" % romset)
	# Two screens over one another (a PlayChoice-10, a Mega-Tech, Punch-Out!!): a portrait pair in the tall body, the usual width.
	for row: Array in [["pc_smb", 1], ["pc_1942", 1], ["mt_aftrb", 1], ["punchout", 0], ["hangplt", 0], ["armwrest", 0]]:
		var sp := _spec(str(row[0]))
		var t := _tube(sp)
		var frame := P.for_romset(str(row[0])).frame_aspect()
		_ok(str(sp["shape"]) == "tall" and t.y > t.x and absf(t.x / t.y - frame) / frame < 0.02 and float(sp["width"]) < 0.80
				and t.y + 0.06 <= tall_edge.length() - 0.11 + 0.001,
			"screens: %s: two screens over one another are a portrait %.2f x %.2f m picture (%.2f) in the tall body, %.2f m wide" % [row[0], t.x, t.y, frame, float(sp["width"])])
	# ... and which is on top is MAME's: a PlayChoice-10 has screen 1 over screen 0, Punch-Out!! screen 0 over screen 1.
	_ok(P.for_romset("pc_smb").screen_part(1).position.y < P.for_romset("pc_smb").screen_part(0).position.y
			and P.for_romset("mt_aftrb").screen_part(1).position.y < P.for_romset("mt_aftrb").screen_part(0).position.y
			and P.for_romset("punchout").screen_part(0).position.y < P.for_romset("punchout").screen_part(1).position.y,
		"screens: a PlayChoice-10 and a Mega-Tech have their second screen on top, Punch-Out!! its first")
	# Two side by side: a wide pair, and a body to hold it.
	for romset in ["nss_actr", "warriorb", "cyberbal", "wrally2", "vsbball", "backfire"]:
		var sp := _spec(romset)
		var t := _tube(sp)
		var inner := float(sp.get("width", 0.66)) - 0.04
		_ok(t.x > 0.85 and absf(t.x / t.y - 8.03 / 3.0) / (8.03 / 3.0) < 0.02 and t.x <= inner - S.GLASS_SIDES + 0.001,
			"screens: %s: two screens side by side are a %.2f x %.2f m picture, on a %.2f m body that holds it" % [romset, t.x, t.y, float(sp.get("width", 0.66))])
	# Three and four across, and a pair on a racing cabinet's monitor housing, which widens.
	for row: Array in [["darius", 4.0, "upright"], ["buggyboy", 4.0, "upright"], ["orunners", 8.03 / 3.0, "racer"], ["racedrivpan", 4.02, "racer"]]:
		var sp := _spec(str(row[0]))
		var t := _tube(sp)
		_ok(str(sp["shape"]) == str(row[2]) and absf(t.x / t.y - float(row[1])) / float(row[1]) < 0.02 and float(sp["width"]) >= t.x + 0.12 - 0.011 and float(sp["width"]) > 0.9,
			"screens: %s: the frame is %.2f:1, the %s body widens to %.2f m for a %.2f x %.2f m picture" % [row[0], float(row[1]), row[2], float(sp["width"]), t.x, t.y])
	# A wide body takes the pictures to 80% of it as far as the tall glass reaches (X-Men's six players, Run and Gun's four).
	var xm := _spec("xmen6p")
	var rg := _spec("rungun2")
	_ok(str(xm["shape"]) == "tall" and _tube(xm).x / float(xm["width"]) >= 0.75 and float(xm["width"]) < 2.0
			and _tube(rg).x / float(rg["width"]) >= 0.75 and float(rg["width"]) < 1.4,
		"screens: X-Men's pair takes %d%% of its %.2f m body, Run and Gun's %d%% of %.2f m" % [roundi(_tube(xm).x / float(xm["width"]) * 100.0), float(xm["width"]),
			roundi(_tube(rg).x / float(rg["width"]) * 100.0), float(rg["width"])])
	# The whole table: every game of several screens has a tube the shape of its frame that its glass and its body hold.
	var measured := 0
	var bad: Array = []
	var wide_bodies: Array = []
	var base := S.variant("generic")
	base["variant"] = "generic"
	for line in ArcadeGameTable.TABLE.split("\n", false):
		var parts := line.split(" ", false)
		if parts.size() < 2:
			continue
		var romset := str(parts[1]).split("=")[0].split("<")[0]
		var gp := P.from_key(romset, parts[0])
		if not gp.known or gp.screens() < 2 or gp.scope_screen() >= 0:
			continue
		measured += 1
		var sp := S.for_game(base, gp)
		var shape_name := str(sp.get("shape", "upright"))
		var sh: Dictionary = S.shapes()[shape_name]
		var t := _tube(sp)
		var width := float(sp.get("width", sh["w"]))
		var edge: Vector2 = (sh["glass_b"] as Vector2) - (sh["glass_a"] as Vector2)
		var shaped := absf(t.x / t.y - gp.frame_aspect()) / gp.frame_aspect() < 0.03
		var holds := t.x <= width - 0.04 - S.GLASS_SIDES + 0.001 and t.y <= edge.length() - S.GLASS_FRAME + 0.001
		if not (shaped and holds):
			bad.append("%s %s" % [romset, shape_name])
		if width > S.MAX_SCREENS_BODY + 0.011 and S.panels_span(sp["players"]) + 0.08 < width - 0.011:
			wide_bodies.append(romset)
	frame_ok = bad.is_empty()
	_ok(measured > 55 and frame_ok, "screens: %d games of several screens: each has a tube the shape of its frame, held by its glass and its body (%s)" % [measured, str(bad.slice(0, 6))])
	_ok(wide_bodies.is_empty(), "screens: and no body is wider than %.1f m for its screens alone (%s)" % [S.MAX_SCREENS_BODY, str(wide_bodies.slice(0, 4))])
	# However many screens, the body is no wider than the screens alone make it: eight across would be 10 m.
	var many := S.screens_body({"vertical": false, "screens": 8, "aspect": 10.7}, "upright", 0.66)
	var panels := S.screens_body({"vertical": false, "screens": 2, "aspect": 8.03 / 3.0}, "tall", 2.8)
	_ok(is_equal_approx(float(many["width"]), S.MAX_SCREENS_BODY) and float(panels["width"]) >= 2.8,
		"screens: eight screens across make a %.1f m body at most, but panels that need more than that are not narrowed (%.1f m)" % [float(many["width"]), float(panels["width"])])
	# A game of one screen is untouched by any of it.
	for romset in ["sf2", "pacman", "1943", "dino", "timecris"]:
		_ok(not (_spec(romset).get("screen", {}) as Dictionary).has("aspect"), "screens: %s, one screen, has no frame to follow" % romset)
	# On a real cabinet: a PlayChoice-10's portrait pair, then Silent Scope's rifle with its screen in the eyepiece and the cut that feeds it.
	var sys := await _machine()
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	await _board(sys, "pc_smb")
	var w := _window(model)
	var tube: Vector2 = w["tube"]
	_ok(tube.y > tube.x and is_equal_approx(model.cabinet_height, float(tall["h"])) and _scope_lens(sys) == null,
		"screens: PlayChoice-10 on a cabinet: a portrait %.2f x %.2f m picture in the %.2f m tall body, no scope" % [tube.x, tube.y, model.cabinet_height])
	await _pull(sys)
	await _board(sys, "sscope")
	await _wait(6)
	var lens := _scope_lens(sys)
	_ok(lens != null and (lens.mesh as QuadMesh).size.is_equal_approx(Vector2(0.037, 0.0278)),
		"screens: Silent Scope: the rifle's eyepiece carries a small screen (%s)" % str((lens.mesh as QuadMesh).size if lens != null else "none"))
	_ok(lens != null and (sys.global_basis.inverse() * lens.global_basis.z).dot(Vector3.BACK) > 0.9,
		"screens: and it faces the player, at rest")
	var screen_module := model.modules_of_kind(ArcadeProfiles.KIND_SCREEN)[0] as ArcadeScreenModule
	_ok(screen_module.main_part.is_equal_approx(Rect2(0.0, 0.0, 0.4981, 1.0)) and screen_module.scope_part.is_equal_approx(Rect2(0.5019, 0.0, 0.4981, 1.0))
			and absf(screen_module.scope_frame_aspect - 2.677) < 0.002,
		"screens: and the screen module has the cut: monitor left, scope right (%s | %s)" % [screen_module.main_part, screen_module.scope_part])
	# Feed it a frame of 8.03:3 as the core would: the monitor cuts its half, the lens its own.
	var card := Image.create(804, 300, false, Image.FORMAT_RGBA8)
	card.fill(Color(0.2, 0.3, 0.5))
	var frame_tex := ImageTexture.create_from_image(card)
	screen_module.aspect_override = 8.03 / 3.0
	screen_module.present(frame_tex, false, false, 0.0)
	var cut: Vector4 = screen_module._material.get_shader_parameter("view_rect")
	var lens_mat := lens.get_surface_override_material(0) as ShaderMaterial if lens != null else null
	var lens_rect: Vector4 = lens_mat.get_shader_parameter("view_rect") if lens_mat != null else Vector4.ZERO
	var lens_fit: Vector2 = lens_mat.get_shader_parameter("fit_scale") if lens_mat != null else Vector2.ZERO
	_ok(screen_module.is_cut() and absf(cut.x) < 0.0001 and absf(cut.z - 0.4981) < 0.0001
			and absf(screen_module.current_fit().x - 1.0) < 0.001 and absf(screen_module.current_fit().y - 1.0) < 0.001
			and absf(screen_module.current_aspect() - 4.0 / 3.0) < 0.002,
		"screens: a frame of the shape the table expects: the monitor shows the left 4:3 half whole (%s, fit %s)" % [cut, screen_module.current_fit()])
	_ok(lens_mat != null and absf(lens_rect.x - 0.5019) < 0.0001 and absf(lens_rect.z - 0.4981) < 0.0001 and absf(lens_fit.x - 1.0) < 0.01 and absf(lens_fit.y - 1.0) < 0.01,
		"screens: and the lens shows the right half (%s, fit %s)" % [lens_rect, lens_fit])
	# A frame of another shape (the player's own artwork, a view the table did not foresee): the whole frame on the monitor, a dark lens.
	screen_module.aspect_override = 4.0 / 3.0
	screen_module.present(frame_tex, false, false, 0.0)
	var whole: Vector4 = screen_module._material.get_shader_parameter("view_rect")
	_ok(not screen_module.is_cut() and absf(whole.z - 1.0) < 0.0001 and absf(whole.w - 1.0) < 0.0001
			and lens.get_surface_override_material(0) != lens_mat,
		"screens: a frame of another shape is shown whole on the monitor and the lens goes dark (%s)" % whole)
	# The game on show (attract) is its own picture: no cut either.
	screen_module.aspect_override = 8.03 / 3.0
	screen_module.present(frame_tex, false, true, 0.0)
	_ok(not screen_module.is_cut() and lens.get_surface_override_material(0) != lens_mat, "screens: and a game that is only on show has no cut, and a dark lens")
	_ok(not ArcadeScreenModule.crop_applies(1.333, 2.677) and ArcadeScreenModule.crop_applies(2.60, 2.677) and ArcadeScreenModule.crop_applies(2.677, 2.677)
			and not ArcadeScreenModule.crop_applies(0.0, 2.677) and not ArcadeScreenModule.crop_applies(2.677, 0.0),
		"screens: the cut is made within 4% of the shape expected, never for a shape unknown")
	await _pull(sys)
	await _wait(6)
	_ok(_scope_lens(sys) == null, "screens: pulling the board takes the rifle, and its lens, away")


# --- pedals --------------------------------------------------------------------

## How many of `node`'s descendants have a name that begins with `prefix`.
func _named(node: Node, prefix: String) -> int:
	var n := 0
	for c in node.find_children("%s*" % prefix, "", true, false):
		n += 1
	return n


func _group_pedals() -> void:
	var sys := await _machine()
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	# A gun game's pedal: a base on the floor, a cheek each side of the hinge, the pin, a tread hinged at its heel
	# with ribs, a toe lip and a rubber face, and its lead.
	model.morph_to(_spec("timecris"))
	await _wait(2)
	var pedal := model.find_child("Pedal1", true, false) as ArcadePedalModule
	var plate := pedal.get_node("PedalPlate") as Node3D
	var hinge := pedal.get_node("PedalHinge") as Node3D
	_ok(pedal.find_child("PedalBase", false, false) != null and pedal.find_child("PedalCheekL", false, false) != null
			and pedal.find_child("PedalCheekR", false, false) != null and _named(plate, "PedalRib") >= 5
			and plate.find_child("PedalToeLip", false, false) != null and plate.find_child("PedalPad", false, false) != null
			and pedal.find_child("PedalBoot", false, false) != null and pedal.find_child("PedalCable", false, false) != null,
		"pedals: a gun pedal has a base, two cheeks, a tread with ribs, a toe lip and a rubber face, a boot and a cord (%d ribs)" % _named(plate, "PedalRib"))
	_ok(plate.position.is_equal_approx(hinge.position), "pedals: the tread turns on its pin: its origin is the hinge's")
	var rest_deg := rad_to_deg(asin(clampf(-plate.basis.z.y, -1.0, 1.0)))
	_ok(rest_deg > 15.0 and rest_deg < 30.0, "pedals: and rests toe up on its spring (%.0f degrees)" % rest_deg)
	var pad := plate.find_child("PedalPad", false, false) as MeshInstance3D
	var mat := (pad.mesh as BoxMesh).material as StandardMaterial3D
	_ok(mat.albedo_color.v < 0.15 and mat.roughness > 0.8 and mat.metallic < 0.1, "pedals: the face is matt black rubber, not a coloured plate")
	var toe_z := pedal.to_local(plate.to_global(Vector3(0, 0, -0.25))).z
	_ok(model.to_local(pedal.global_position).z + toe_z > 0.76 and (pedal.get_node("PedalBase") as MeshInstance3D).position.y < 0.01,
		"pedals: the toe is clear of the bay door lying open (0.80 m out of the cabinet's front)")
	# A driver's two: organ pedals on one axle over a footplate with a heel mat, brake wider than gas.
	model.morph_to(_spec("daytona"))
	await _wait(2)
	var gas := model.find_child("GasPivot", true, false) as Node3D
	var brake := model.find_child("BrakePivot", true, false) as Node3D
	var axle := model.find_child("PedalAxle", true, false) as Node3D
	_ok(gas != null and brake != null and axle != null and model.find_child("FootMat", true, false) != null
			and model.find_child("Footplate", true, false) != null,
		"pedals: a driver's two pedals hang on an axle over a footplate with a heel mat")
	_ok(absf(gas.global_position.y - axle.global_position.y) < 0.001 and absf(brake.global_position.y - axle.global_position.y) < 0.001
			and absf(gas.global_position.z - axle.global_position.z) < 0.001,
		"pedals: both pivot on the axle")
	var gas_w := ((gas.find_child("GasDeck", false, false) as MeshInstance3D).mesh as BoxMesh).size.x
	var brake_w := ((brake.find_child("BrakeDeck", false, false) as MeshInstance3D).mesh as BoxMesh).size.x
	_ok(brake_w > gas_w + 0.01 and brake.position.x < gas.position.x, "pedals: the brake is the wider pad, on the left (%.3f against %.3f m)" % [brake_w, gas_w])
	var tilt := rad_to_deg(asin(clampf(-gas.basis.z.y, -1.0, 1.0)))
	_ok(tilt > 25.0 and tilt < 45.0 and _named(gas, "GasRib") >= 4 and gas.find_child("GasToeLip", false, false) != null,
		"pedals: the pads rise toward the screen like a car's, ribbed, with a lip at the toe (%.0f degrees, %d ribs)" % [tilt, _named(gas, "GasRib")])
	# They still move: the control module tips them with the pedals' axes.
	var p1 := _panels(model)[0] as ArcadeControlModule
	var gas_rest := gas.basis
	var brake_rest := brake.basis
	p1.show_state(1 << ControllerBindings.JOYPAD_R2)
	for i in 8:
		p1.tick(0.05)
	_ok(not gas.basis.is_equal_approx(gas_rest) and brake.basis.is_equal_approx(brake_rest),
		"pedals: and the gas tips when R2 is pressed, the brake not")


# --- service -------------------------------------------------------------------

func _desc(device: int, id: int, words: String, port: int = 0) -> Dictionary:
	return {"port": port, "device": device, "index": 0, "id": id, "description": words}


func _group_service() -> void:
	# What MAME says, in the table: the flag is `<input service="yes">`.
	_ok(P.for_romset("sscope").has_service() and P.for_romset("sf2").has_service() and P.for_romset("sscope2").has_service(),
		"service: Silent Scope and Street Fighter II read a service switch (MAME's `service`)")
	_ok(not P.for_romset("timecris").has_service() and not P.for_romset("pacman").has_service() and not P.for_romset("zzz_homebrew").has_service(),
		"service: Time Crisis and Pac-Man read none, and a game the table does not know is not said to")
	# What the core calls it.
	var K := ArcadeServiceKeys
	var fbneo := [_desc(1, 2, "Coin"), _desc(1, 3, "Start"), _desc(1, 14, "Service"), _desc(1, 15, "Diagnostic"), _desc(1, 0, "Weak Kick")]
	_ok(int(K.lookup(fbneo, K.SERVICE).get("id", -1)) == 14 and int(K.lookup(fbneo, K.TEST).get("id", -1)) == 15,
		"service: a core that says \"Service\" and \"Diagnostic\" on pad ids is believed: SERVICE is 14, TEST 15")
	var mameish := [_desc(1, 12, "Service Mode"), _desc(1, 13, "Service 1"), _desc(3, 283, "Test")]
	_ok(int(K.lookup(mameish, K.TEST).get("id", -1)) in [12, 283] and int(K.lookup(mameish, K.SERVICE).get("id", -1)) == 13,
		"service: \"Service Mode\" is the test switch and \"Service 1\" the credit, never the same input")
	_ok(K.lookup([_desc(1, 2, "Coin"), _desc(4, 0, "Service"), _desc(2, 1, "Test")], K.TEST).is_empty()
			and K.lookup([_desc(1, 2, "Coin")], K.SERVICE).is_empty(),
		"service: a light gun's or a mouse's ids are not a switch, and a core that names none gives {} (the fallback keys)")
	_ok(int(K.lookup([_desc(1, 9, "Service", 1), _desc(1, 14, "Service", 0)], K.SERVICE).get("id", -1)) == 14,
		"service: player 1's port is believed first")
	_ok(K.default_key(K.TEST) == 283 and K.default_key(K.SERVICE) == 57, "service: MAME's own keys are F2 and 9 (libretro.h's RETROK codes)")
	# Built on a real cabinet.
	var sys := await _machine()
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	var services := model.modules_of_kind(ArcadeProfiles.KIND_SERVICE)
	_ok(services.size() == 1 and (services[0] as ArcadeServiceModule).button(K.TEST) != null
			and (services[0] as ArcadeServiceModule).button(K.SERVICE) != null,
		"service: the cabinet has one service module with a TEST and a SERVICE button")
	var service := services[0] as ArcadeServiceModule
	var power := model.get_node("Bay").find_child("PowerSwitch", true, false) as Node3D
	var test_at := model.to_local(service.button(K.TEST).global_position)
	var credit_at := model.to_local(service.button(K.SERVICE).global_position)
	_ok(test_at.x < -0.1 and credit_at.x < -0.05 and power.position.x > 0.1,
		"service: they stand on the OTHER side of the compartment from the power switch (%.2f, %.2f against %.2f)" % [test_at.x, credit_at.x, power.position.x])
	_ok(absf(test_at.y - power.position.y) < 0.02 and absf(credit_at.y - power.position.y) < 0.02 and test_at.z > 0.1 and test_at.z < 0.38,
		"service: in the compartment, on its floor at the power switch's height, in reach of the door (z %.2f)" % test_at.z)
	# The words on the bracket are white, outlined in black: black on the grey bracket could not be read.
	var legible := true
	for label_name in ["TestLabel", "ServiceLabel", "LeftLabel", "DownLabel", "UpLabel", "RightLabel", "EnterLabel"]:
		var tag := service.find_child(label_name, true, false) as Label3D
		legible = legible and tag != null and tag.modulate.is_equal_approx(Color.WHITE) and tag.outline_size > 0 and tag.outline_modulate.v < 0.2
	_ok(legible, "service: every word on the bracket is white with a black outline")
	# The operator's selector beside them: five buttons in the compartment, clear of the walls, the door and one another.
	var selector_ok := true
	var spots: Array[Vector3] = []
	for which: StringName in K.SELECTOR:
		var b := service.button(which)
		selector_ok = selector_ok and b != null
		if b != null:
			var at := model.to_local(b.global_position)
			spots.append(at)
			selector_ok = selector_ok and at.x > -0.29 and at.x < 0.0 and at.z > 0.1 and at.z < 0.36 and absf(at.y - power.position.y) < 0.02
	for i in spots.size():
		for j in range(i + 1, spots.size()):
			selector_ok = selector_ok and spots[i].distance_to(spots[j]) > 0.04
	for which: StringName in [K.TEST, K.SERVICE]:
		for at: Vector3 in spots:
			selector_ok = selector_ok and model.to_local(service.button(which).global_position).distance_to(at) > 0.06
	_ok(selector_ok and spots.size() == 5, "service: the selector (left, down, up, right, enter) stands on the compartment's floor, apart from the walls, the door and each other")
	# A game dresses them: there for Silent Scope, gone for Time Crisis, back for another.
	await _board(sys, "sscope")
	_ok(service.is_enabled() and service.button(K.TEST).collision_layer != 0, "service: with Silent Scope in the bay they are there and can be aimed at")
	await _pull(sys)
	await _board(sys, "timecris")
	_ok(not service.is_enabled() and service.button(K.TEST).collision_layer == 0 and service.button(K.SERVICE).collision_layer == 0
			and service.button(K.UP).collision_layer == 0 and service.button(K.ENTER).collision_layer == 0,
		"service: with Time Crisis in the bay (MAME reads none) they are gone, the selector with them, and cannot be aimed at")
	await _pull(sys)
	await _board(sys, "sf2")
	_ok(service.is_enabled(), "service: and back for the next game that reads one")
	# A press goes to the machine and into the core: the keys, with nothing named.
	var keys: Array = []
	sys.core_key_sink = func(code: int, down: bool) -> void: keys.append([code, down])
	_ok(not sys.press_core_service(K.TEST) and keys.is_empty(), "service: with no core running nothing is pressed")
	sys.is_powered_on = true
	sys.core_descriptors_override = []
	service.press(K.TEST)
	await get_tree().create_timer(0.5).timeout
	_ok(keys == [[283, true], [283, false]], "service: TEST taps F2, the way MAME reads Service Mode (%s)" % str(keys))
	keys.clear()
	service.button(K.SERVICE).button_pressed.emit()
	await get_tree().create_timer(0.5).timeout
	_ok(keys == [[57, true], [57, false]], "service: the SERVICE button taps 9, MAME's Service 1 (%s)" % str(keys))
	# A core that names it on a pad id gets that id held on its port a moment: through the cabinet's input.
	keys.clear()
	sys.core_descriptors_override = [_desc(1, 14, "Service")]
	var input := model.arcade_input()
	input.frame_override = input.wait_frames()
	service.press(K.SERVICE)
	input._process(0.01)
	_ok(keys.is_empty() and (int(input.last_sent.get(0, 0)) & (1 << 14)) != 0,
		"service: a core that names it on pad id 14 hears it there, not on a key")
	input._process(0.5)
	input._process(0.01)
	_ok((int(input.last_sent.get(0, 0)) & (1 << 14)) == 0, "service: and only for a moment")
	sys.core_descriptors_override = [_desc(3, 296, "Diagnostic")]
	service.press(K.TEST)
	await get_tree().create_timer(0.5).timeout
	_ok(keys == [[296, true], [296, false]], "service: and a core that names it on a key gets that key (%s)" % str(keys))
	# The selector is the first player's stick and button 1, one tap each on port 0 (a wheel's cabinet has neither): a pad id held a moment.
	keys.clear()
	var selector_works := true
	for pair: Array in [[K.UP, ControllerBindings.JOYPAD_UP], [K.DOWN, ControllerBindings.JOYPAD_DOWN], [K.LEFT, ControllerBindings.JOYPAD_LEFT],
			[K.RIGHT, ControllerBindings.JOYPAD_RIGHT], [K.ENTER, ArcadeProfiles.button_bit(1)]]:
		input._process(0.5)
		input._process(0.01)
		service.press(pair[0])
		input._process(0.01)
		var down := (int(input.last_sent.get(0, 0)) & (1 << int(pair[1]))) != 0
		input._process(0.5)
		input._process(0.01)
		var up := (int(input.last_sent.get(0, 0)) & (1 << int(pair[1]))) == 0
		selector_works = selector_works and down and up
		if not (down and up):
			print("[form] selector %s down=%s up=%s" % [str(pair[0]), str(down), str(up)])
	_ok(selector_works and keys.is_empty(), "service: UP, DOWN, LEFT, RIGHT and ENTER each hold the first player's direction or button 1 a moment, and press no key")
	sys.is_powered_on = false
	input.last_sent.clear()
	service.press(K.UP)
	input._process(0.01)
	_ok(not sys.press_core_service(K.ENTER) and not input.last_sent.has(0), "service: with no core running the selector presses nothing")


# --- mount ---------------------------------------------------------------------

func _group_mount() -> void:
	var sys := await _machine()
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	await _board(sys, "sscope")
	await _wait(10)
	var rifle := sys.captive_controllers()[0] as LightGun
	_ok(rifle.is_mounted() and rifle.captive_well == null and rifle.freeze
			and rifle.release_mode == XRToolsPickable.ReleaseMode.FROZEN
			and rifle.ranged_grab_method == XRToolsPickable.RangedMethod.NONE and rifle.mount_lever,
		"mount: Silent Scope's rifle is FIXED to its post: no well to be taken out of, never let fall, never called from afar, turned by its lever")
	_ok(model.captive_gun_mounts().size() == 1 and (model.captive_gun_mounts()[0]["local"] as Vector3).z < -0.2
			and (model.captive_gun_mounts()[0]["local"] as Vector3).z > -0.3,
		"mount: its pivot is under the forestock, a quarter of a metre ahead of the grip (%s)" % str(model.captive_gun_mounts()[0]["local"]))
	var home := model.global_transform.affine_inverse() * rifle.global_transform
	_ok(home.is_equal_approx(model.gun_origins()[0]) and rifle.mount_turn() == Vector2.ZERO,
		"mount: at rest it is on its post, level, aimed at the screen")
	# The pivot stays where it is, whatever a hand wants (a hold a metre off, above, behind).
	var pivot := rifle.mount.global_position
	var stays := true
	var worst := 0.0
	for want: Vector3 in [Vector3(0, 0, -1), Vector3(1, 0.2, -1), Vector3(-1, -0.5, -0.3), Vector3(0, 1, 0), Vector3(0, -1, 0.2), Vector3(0.3, 0, 1)]:
		var held := Transform3D(Basis.looking_at(want.normalized(), Vector3.UP), pivot + Vector3(0.7, 0.5, 0.9))
		var posed := rifle.constrain_grab(held)
		var off := (posed * rifle.mount_pivot).distance_to(pivot)
		worst = maxf(worst, off)
		stays = stays and off < 1e-4
	_ok(stays, "mount: whatever a hand wants, the pivot stays on the post (off by %.6f m at worst)" % worst)
	# It turns the way the hand aims it, within its travel, and never rolls.
	var turned := rifle.constrain_grab(Transform3D(Basis.looking_at(Vector3(-1, 0.3, -2).normalized(), Vector3.UP), Vector3.ZERO))
	var ahead := -turned.basis.z
	_ok(ahead.dot(Vector3(-1, 0.3, -2).normalized()) > 0.999 and absf(turned.basis.x.y) < 1e-4,
		"mount: it turns the way the hand points it (yaw %.1f, pitch %.1f degrees) and never rolls" % [rad_to_deg(rifle.mount_turn().x), rad_to_deg(rifle.mount_turn().y)])
	rifle.constrain_grab(Transform3D(Basis.looking_at(Vector3(-5, 0, -0.5).normalized(), Vector3.UP), Vector3.ZERO))
	_ok(is_equal_approx(rifle.mount_turn().x, LightGun.MOUNT_YAW_LIMIT), "mount: it turns no further than its housing lets it (yaw %.1f degrees)" % rad_to_deg(rifle.mount_turn().x))
	rifle.constrain_grab(Transform3D(Basis.looking_at(Vector3(0, 5, -1).normalized(), Vector3.UP), Vector3.ZERO))
	_ok(is_equal_approx(rifle.mount_turn().y, LightGun.MOUNT_PITCH_LIMIT.y), "mount: ... nor lifts further than its stop (pitch %.1f degrees)" % rad_to_deg(rifle.mount_turn().y))
	rifle.constrain_grab(Transform3D(Basis.looking_at(Vector3(0, -5, -1).normalized(), Vector3.UP), Vector3.ZERO))
	_ok(is_equal_approx(rifle.mount_turn().y, LightGun.MOUNT_PITCH_LIMIT.x), "mount: ... nor drops further than its stop (pitch %.1f degrees)" % rad_to_deg(rifle.mount_turn().y))
	# A rifle's long stock is a lever: with the hand behind and to the right of the pivot the barrel swings left.
	var hand := Node3D.new()
	add_child(hand)
	hand.global_position = pivot + Vector3(0.1, 0.0, 0.3)
	var by_lever := rifle.constrain_grab(Transform3D(Basis.IDENTITY, Vector3.ZERO), hand)
	var lever_dir := (pivot - hand.global_position).normalized()
	_ok((-by_lever.basis.z).dot(lever_dir) > 0.999 and rifle.mount_turn().x > deg_to_rad(10.0) and rifle.mount_turn().x < deg_to_rad(25.0),
		"mount: a rifle follows its lever: the barrel runs from the hand through the pivot (yaw %.1f degrees)" % rad_to_deg(rifle.mount_turn().x))
	hand.global_position = pivot + Vector3(0.05, 0.0, 0.05)
	rifle.constrain_grab(Transform3D(Basis.looking_at(Vector3(0, 0, -1), Vector3.UP), Vector3.ZERO), hand)
	_ok(is_zero_approx(rifle.mount_turn().x), "mount: a hand too near the pivot to tell by does not swing it: it goes by the way the hand points")
	hand.free()
	# The real grab driver (patched): what holds it on the post is the hook, not the hand.
	var by := Node3D.new()
	add_child(by)
	by.global_transform = rifle.global_transform
	var grab := Grab.new(Grabber.new(by), rifle, null, true)
	var driver := XRToolsGrabDriver.create_snap(rifle, grab)
	# As the pickable's own pick_up leaves it: held, so the gun's own pin to its post stands aside for the driver.
	rifle._grab_driver = driver
	await _wait(2)
	# The hand carries it off.
	by.global_position = pivot + Vector3(2.0, 1.0, 2.0)
	await _wait(3)
	_ok((rifle.global_transform * rifle.mount_pivot).distance_to(pivot) < 1e-3 and rifle.global_position.distance_to(by.global_position) > 1.0,
		"mount: held by a hand two metres off, the gun is still on its post (the driver's hook)")
	rifle._grab_driver = null
	driver.discard()
	by.free()
	# Let go it stays, and it goes where its cabinet goes.
	await _wait(3)
	var before := rifle.global_position
	sys.global_position += Vector3(0.0, 0.0, 1.5)
	await _wait(4)
	_ok(rifle.global_position.distance_to(before + Vector3(0.0, 0.0, 1.5)) < 0.02 and rifle.freeze,
		"mount: the cabinet moved, the rifle went with it, frozen on its post")
	# Beast Busters' Uzis and Operation Wolf's are fixed too; a holstered gun is not.
	await _pull(sys)
	await _board(sys, "bbusters")
	await _wait(10)
	var all_fixed := sys.captive_controllers().size() == 3
	for g: Variant in sys.captive_controllers():
		all_fixed = all_fixed and (g as LightGun).is_mounted() and not (g as LightGun).mount_lever and (g as LightGun).captive_well == null
	_ok(all_fixed, "mount: Beast Busters' three guns are fixed to their swivels, turned by the way a hand points them")
	await _pull(sys)
	await _board(sys, "timecris")
	await _wait(10)
	var holstered := sys.captive_controllers()[0] as LightGun
	_ok(not holstered.is_mounted() and holstered.captive_well != null and holstered.mount_turn() == Vector2.ZERO,
		"mount: a gun in a holster (Time Crisis) is not fixed: it is taken out and carried")


# --- guns ----------------------------------------------------------------------

func _group_guns() -> void:
	var sys := await _machine()
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	_ok(sys.captive_controllers().is_empty(), "guns: the generic cabinet carries no guns")
	await _board(sys, "ptblank")
	await _wait(10)
	var guns: Array = sys.captive_controllers()
	_ok(guns.size() == 2, "guns: Point Blank's board gives the cabinet two guns (%d)" % guns.size())
	var plugged := true
	for i in guns.size():
		plugged = plugged and sys.get_port_controllers()[i] == guns[i]
	_ok(plugged, "guns: each in its own port")
	var hung := true
	var origins := model.gun_origins()
	for i in guns.size():
		hung = hung and (model.global_transform.affine_inverse() * (guns[i] as Node3D).global_transform).origin.distance_to(origins[i].origin) < 0.03
	_ok(hung, "guns: and hanging in its holster")
	await _pull(sys)
	await _wait(4)
	var freed := true
	for g: Variant in guns:
		freed = freed and not is_instance_valid(g)
	_ok(freed and sys.captive_controllers().is_empty(), "guns: pulling the board takes the guns away")
	var ports_free := true
	for i in 2:
		ports_free = ports_free and sys.get_port_controllers()[i] == null
	_ok(ports_free, "guns: and their ports are free again")
	_ok(model._sockets != null and model._sockets.seat_count() == 2 and model._sockets.holster_count() == 0,
		"guns: the front sockets are back")
	var zones_free := true
	for i in 2:
		var zone := sys._port_zones[i] as XRToolsSnapZone
		zones_free = zones_free and zone.monitoring and not zone.has_snapped_object()
	_ok(zones_free, "guns: the sockets the guns were in take a plug again")
	await _board(sys, "opwolf")
	await _wait(10)
	_ok(sys.captive_controllers().size() == 1 and absf(model.gun_origins()[0].origin.x) < 0.01,
		"guns: Operation Wolf's one gun stands on its post in the middle")
	await _pull(sys)
	await _board(sys, "sscope")
	await _wait(10)
	guns = sys.captive_controllers()
	_ok(guns.size() == 1 and str((guns[0] as Node).scene_file_path).ends_with("arcade_light_rifle.tscn"),
		"guns: Silent Scope's is one rifle")
	var rest := model.gun_origins()[0]
	_ok(rest.basis.z.dot(Vector3.BACK) > 0.99 and rest.origin.y > 1.0,
		"guns: resting level on its post, aimed at the screen")
	await _pull(sys)
	await _board(sys, "bbusters")
	await _wait(10)
	_ok(sys.captive_controllers().size() == 3 and model.find_child("MountPost3", true, false) != null,
		"guns: Beast Busters' three guns on their posts")
	await _pull(sys)
	await _board(sys, "timecris")
	await _wait(10)
	var pedals := model.modules_of_kind(ArcadeProfiles.KIND_PEDAL)
	_ok(sys.captive_controllers().size() == 1 and pedals.size() == 1 and (pedals[0] as ArcadePedalModule).active
		and (pedals[0] as ArcadePedalModule).port() == 0,
		"guns: Time Crisis: one gun and its pedal, player 1's button 2")
	_ok(model.gun_origins()[0].origin.x > 0.2 and absf((pedals[0] as Node3D).position.x) < 0.01,
		"guns: its one gun hangs on the right, the pedal in the middle where its player stands")
	if pedals.size() == 1:
		# Built at run time, it finds its own plate and hinge as the baked one does, and the input has it.
		var tc_pedal := pedals[0] as ArcadePedalModule
		_ok(model.arcade_input()._pedals.has(tc_pedal), "guns: the input is wired to the pedal the morph built")
		var tc_plate := tc_pedal.get_node("PedalPlate") as Node3D
		var tc_rest := tc_plate.transform
		tc_pedal.show_pressed(true)
		for i in 6:
			tc_pedal.tick(0.02)
		_ok(tc_pedal.plate_down() == 1.0
			and (tc_plate.transform * Vector3(0, 0, -0.09)).y < (tc_rest * Vector3(0, 0, -0.09)).y - 0.02,
			"guns: and its plate goes down when it is pressed")
		tc_pedal.show_pressed(false)
		for i in 6:
			tc_pedal.tick(0.02)
		_ok(tc_plate.transform.is_equal_approx(tc_rest), "guns: and back up")
	# A game that reads its gun as an analog stick (MAME's AD_STICK: libretro-mame binds it to the LEFT stick, a light gun to the
	# light-gun device alone) hears the aim as the left stick too; a light-gun game does not.
	var input := model.arcade_input()
	await _pull(sys)
	await _board(sys, "term2")
	await _wait(10)
	var t2_gun := sys.captive_controllers()[0] as LightGun
	t2_gun.last_aim = Vector2i(1234, -4321)
	var axes := input._gun_axes(t2_gun)
	_ok(int(axes["alx"]) == 1234 and int(axes["aly"]) == -4321 and int(axes["arx"]) == 0 and int(axes["ary"]) == 0,
		"guns: Terminator 2's gun aim goes out as the left stick, in the light gun's own coordinates (%s)" % str(axes))
	# ... and it is what the running cabinet sends on the gun's port, every frame.
	sys.is_powered_on = true
	input.frame_override = input.wait_frames()
	input._process(0.01)
	_ok(input._heard_axes.get(0, Vector4i.ZERO) == Vector4i(1234, -4321, 0, 0),
		"guns: the running cabinet sends it on the gun's port (%s)" % str(input._heard_axes.get(0, "nothing")))
	sys.is_powered_on = false
	input.frame_override = -1
	await _pull(sys)
	await _board(sys, "sscope")
	await _wait(10)
	var rifle_gun := sys.captive_controllers()[0] as LightGun
	rifle_gun.last_aim = Vector2i(-777, 555)
	axes = input._gun_axes(rifle_gun)
	_ok(int(axes["alx"]) == -777 and int(axes["aly"]) == 555, "guns: and so does Silent Scope's rifle (yaw and pitch are two AD sticks)")
	await _pull(sys)
	await _board(sys, "timecris")
	await _wait(10)
	var tc_gun := sys.captive_controllers()[0] as LightGun
	tc_gun.last_aim = Vector2i(1234, -4321)
	axes = input._gun_axes(tc_gun)
	_ok(int(axes["alx"]) == 0 and int(axes["aly"]) == 0, "guns: a light-gun game (Time Crisis) hears nothing on the stick")
	sys.is_powered_on = true
	input.frame_override = input.wait_frames()
	input._process(0.01)
	_ok(input._heard_axes.get(0, Vector4i.ZERO) == Vector4i.ZERO, "guns: and the running cabinet sends it none")
	sys.is_powered_on = false
	input.frame_override = -1
	await _pull(sys)
	_ok(input._gun_axes(null)["alx"] == 0, "guns: and no gun is no aim")


# --- shift ---------------------------------------------------------------------

## The cockpit or the stand-up wheel panel of a driving game, with the game's profile applied the way a board in the bay does.
func _driver_panel(model: RetroSystemModelArcadeCabinet, romset: String) -> ArcadeControlModule:
	model.morph_to(_spec(romset))
	model.apply_game_profile(P.for_romset(romset))
	return _panels(model)[0] as ArcadeControlModule


## The panel shown `mask` for a frame and then `frames` frames of nothing new, the lever left to settle.
func _show(panel: ArcadeControlModule, mask: int, frames: int = 30) -> void:
	panel.show_state(mask)
	for i in frames:
		panel.tick(1.0 / 60.0)


func _group_shift() -> void:
	# The table: which games have a lever and what it says (read from the driver sources by Tools/arcade/shifters.py).
	_ok(P.for_romset("outrun").shifter() == {"button": 3, "toggle": true} and P.for_romset("chasehq").shifter() == {"button": 4, "toggle": true}
			and P.for_romset("finallap").shifter() == {"button": 1, "toggle": true} and P.for_romset("polepos").shifter() == {"button": 3, "toggle": false}
			and P.for_romset("smgp").shifter() == {"up": 2, "down": 1},
		"shift: Out Run's gear shift is button 3 and a toggle, Chase HQ's 4, Final Lap's 1; Pole Position's is button 3 held; Super Monaco GP's is up on 2 and down on 1")
	_ok(P.for_romset("outrun").shifter() == P.for_romset("outrunb").shifter() and P.for_romset("toutrun1").shifter() == {"button": 3, "toggle": true}
			and P.for_romset("pdrift").shifter() == {"button": 3, "toggle": true} and P.for_romset("toutrun").shifter() == {"button": 3, "toggle": true},
		"shift: a clone has its parent's lever; Power Drift and Turbo Out Run say button 3, a toggle")
	_ok(P.for_romset("shangon").shifter().is_empty(), "shift: Super Hang-On is a ride-on bike, and a bike has no lever to draw")
	_ok(P.for_romset("daytona").shifter().is_empty() and P.for_romset("sf2").shifter().is_empty() and P.for_romset("hangon").shifter().is_empty()
			and P.for_romset("not_a_real_romset").shifter().is_empty() and not P.for_romset("daytona").has_shifter(),
		"shift: an H pattern (Daytona USA), a game that is not a driver, a bike and a romset the table lacks have no two-position lever")
	_ok(ArcadeGameProfile.from_key("t", "p1c1b1w0:paddle+pedal;trace;x3t").shifter() == {"button": 3, "toggle": true}
			and ArcadeGameProfile.from_key("t", "p1c1b1w0:paddle+pedal;trace;x6h").shifter() == {"button": 6, "toggle": false}
			and ArcadeGameProfile.from_key("t", "p1c1b1w0:paddle+pedal;trace;xs12").shifter() == {"up": 1, "down": 2}
			and ArcadeGameProfile.from_key("t", "p1c1b1w0:paddle+pedal;trace;x").shifter().is_empty()
			and ArcadeGameProfile.from_key("t", "p1c1b1w0:paddle+pedal;trace;x3q").shifter().is_empty()
			and ArcadeGameProfile.from_key("t", "p1c1b1w0:paddle+pedal;trace").shifter().is_empty(),
		"shift: the table's x is read: a button and t or h, or s and two buttons; anything else is no lever")
	_ok(ArcadeProfiles.button_bit(1) == ControllerBindings.JOYPAD_B and ArcadeProfiles.button_bit(2) == ControllerBindings.JOYPAD_A
			and ArcadeProfiles.button_bit(3) == ControllerBindings.JOYPAD_Y and ArcadeProfiles.button_bit(6) == ControllerBindings.JOYPAD_R
			and ArcadeProfiles.button_bit(0) == -1 and ArcadeProfiles.button_bit(7) == -1,
		"shift: MAME's button n is the pad's B A Y X L R in order, and a seventh is nothing")
	# The spec: a lever only for a game that has one.
	_ok(bool(_spec("pdrift")["cockpit"]["shifter"]) and bool(_spec("hotchase")["cockpit"]["shifter"]),
		"shift: Power Drift's and Hot Chase's sit-down cockpits carry their lever")
	_ok(not bool(_spec("daytona")["cockpit"]["shifter"]) and bool(_spec("outrun")["players"][0]["shifter"]) and bool(_spec("polepos")["players"][0]["shifter"])
			and not bool(_spec("scud")["cockpit"]["shifter"]),
		"shift: no lever is built for Daytona USA or Scud Race; Out Run's and Pole Position's stand-up panels have one")
	_ok(P.for_romset("crusnusa").buttons >= 1 and P.for_romset("buggyboy").buttons >= 1
			and not bool(_spec("crusnusa")["players"][0]["shifter"]) and not bool(_spec("buggyboy")["players"][0]["shifter"]),
		"shift: a stand-up game with buttons but no lever of its own (Cruis'n USA's H pattern, Buggy Boy) is not given one for its buttons")
	# The cabinet: the lever follows the game's own button, not button 1.
	var sys := await _machine()
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	var panel := _driver_panel(model, "daytona")
	_ok(panel.find_child("ShifterPivot", true, false) == null, "shift: Daytona USA's cockpit has no lever")
	panel = _driver_panel(model, "polepos")
	await _wait(2)
	var lever := panel.find_child("ShifterPivot", true, false) as Node3D
	_ok(lever != null and panel.shift_config() == {"button": 3, "toggle": false}, "shift: Pole Position's panel has one, on button 3, held")
	var y_bit := ArcadeProfiles.button_bit(3)
	var b_bit := ArcadeProfiles.button_bit(1)
	_show(panel, 1 << b_bit)
	_ok(not panel.shift_high() and panel.shift_amount() < 0.05, "shift: button 1, the old lever's, does nothing to it")
	_show(panel, 1 << y_bit)
	_ok(panel.shift_high() and panel.shift_amount() > 0.95, "shift: button 3 held throws it high")
	_show(panel, 0)
	_ok(not panel.shift_high() and panel.shift_amount() < 0.05, "shift: and it falls back when the button is let go")
	# A toggle: one press per change, on the edge, whoever presses.
	panel = _driver_panel(model, "outrun")
	await _wait(2)
	_ok(panel.shift_config() == {"button": 3, "toggle": true} and not panel.shift_high(), "shift: Out Run's is a toggle, low")
	_show(panel, 1 << y_bit, 5)
	_show(panel, 1 << y_bit, 5)
	_ok(panel.shift_high(), "shift: a press flips it, and holding the button flips it once")
	# Something else changing while the button stays down is no new press.
	_show(panel, (1 << y_bit) | (1 << ControllerBindings.JOYPAD_START), 5)
	_ok(panel.shift_high(), "shift: another button going down meanwhile is not a press of this one")
	_show(panel, (1 << y_bit) | (1 << ControllerBindings.JOYPAD_START) | (1 << ControllerBindings.JOYPAD_UP), 5)
	_ok(panel.shift_high(), "shift: nor is a second")
	_show(panel, 0)
	_ok(panel.shift_high() and panel.shift_amount() > 0.95, "shift: let go it stays high")
	_show(panel, 1 << y_bit, 5)
	_show(panel, 0)
	_ok(not panel.shift_high() and panel.shift_amount() < 0.05, "shift: the next press flips it back")
	_show(panel, 1 << y_bit, 5)
	_show(panel, 0, 5)
	panel.reset_shift()
	_ok(not panel.shift_high(), "shift: a new run starts in the first gear (reset_shift)")
	_show(panel, 1 << y_bit, 5)
	_show(panel, 0, 5)
	_ok(panel.shift_high(), "shift: thrown again")
	model.arcade_input()._process(0.016)
	_ok(not panel.shift_high(), "shift: the cabinet's input with no core running puts the lever back (a run is over)")
	_show(panel, 1 << y_bit, 5)
	var other := _driver_panel(model, "finallap")
	_ok(not other.shift_high() and other.shift_config() == {"button": 1, "toggle": true}, "shift: another game's lever starts low (a profile that changes it resets it)")
	# A sequential box: up goes high, down goes low, and neither a toggle nor held.
	panel = _driver_panel(model, "smgp")
	await _wait(2)
	var up_bit := ArcadeProfiles.button_bit(2)
	var down_bit := ArcadeProfiles.button_bit(1)
	_show(panel, 1 << up_bit, 5)
	_show(panel, 0)
	_ok(panel.shift_high(), "shift: Super Monaco GP's up button throws the lever high, and it stays")
	_show(panel, 1 << up_bit, 5)
	_show(panel, 0)
	_ok(panel.shift_high(), "shift: up again changes nothing")
	_show(panel, 1 << down_bit, 5)
	_show(panel, 0)
	_ok(not panel.shift_high(), "shift: the down button sends it low")
	# A game with no profile (a pad in the room, no board): the lever has nothing to say.
	model.apply_game_profile(null)
	_show(panel, 1 << up_bit, 5)
	_ok(panel.shift_config().is_empty() and not panel.shift_high(), "shift: with no game in the bay a lever follows nothing")


# --- odd -----------------------------------------------------------------------

func _group_odd() -> void:
	_ok(P.for_romset("propcycl").form() == P.FORM_CYCLE and P.for_romset("propcyclj").form() == P.FORM_CYCLE
			and P.for_romset("timetrv").form() == P.FORM_HOLO and P.for_romset("timetrv2").form() == P.FORM_HOLO
			and P.for_romset("panicprk").form() == P.FORM_SLOT and P.for_romset("panicprkj").form() == P.FORM_SLOT,
		"odd: the table files Prop Cycle, Time Traveler and Panic Park, and their clones, under forms of their own")
	var cycle := _spec("propcycl")
	_ok(cycle.has("cycle") and str(cycle["shape"]) == "wide" and (cycle["players"] as Array).is_empty()
			and (cycle["coins"] as Array).size() == 1 and not cycle.has("screen"),
		"odd: Prop Cycle asks for the wide body (and its own 40 inch tube) with a bicycle in front, no deck panel of its own, one coin door")
	var holo := _spec("timetrv")
	_ok(holo.has("holo") and is_equal_approx(float(holo["holo"]["depth"]), S.HOLO_DEPTH) and str(holo["shape"]) == "upright"
			and _kinds(holo) == ["stick"],
		"odd: Time Traveler asks for the upright with a deep stage, its stick and its two buttons")
	var slot := _spec("panicprk")
	var slot_xs: Array = []
	for pl: Dictionary in slot["players"]:
		slot_xs.append(float(pl["slot_x"]))
	_ok(_kinds(slot) == ["slot", "slot"] and is_equal_approx(float(slot_xs[0]), -S.SLOT_TRAVEL)
			and is_equal_approx(float(slot_xs[1]), S.SLOT_TRAVEL),
		"odd: Panic Park asks for two levers, one in each half of one slot (%s)" % str(slot_xs))
	_ok(float(slot["width"]) * 0.5 >= S.SLOT_TRAVEL * 2.0 + 0.03 and S.panels_span(slot["players"]) >= S.SLOT_TRAVEL * 4.0 + 0.05,
		"odd: and the body, and the span the panels ask for, take both levers' whole travel (%.2f m, %.2f m)"
			% [float(slot["width"]), S.panels_span(slot["players"])])
	_ok(not _spec("sf2").has("cycle") and not _spec("sf2").has("holo") and _kinds(_spec("pacman")) != ["slot"],
		"odd: no other game gets any of them")
	# Panic Park's own cabinets had a 33 or a 50 inch screen (System 23): the smaller, in the tall body that holds it with its black round it.
	_ok(P.for_romset("panicprk").monitor_inches() == 33 and str(slot["shape"]) == "tall" and int(slot["screen"]["inches"]) == 33
			and _tube(slot).x > 0.62 and float(slot["width"]) >= _tube(slot).x + 0.12 - 0.011 and float(slot["width"]) < 0.80,
		"odd: Panic Park's picture is a 33 inch class (%.2f x %.2f m) in the tall body, on a body (%.2f m) that holds it" % [_tube(slot).x, _tube(slot).y, float(slot["width"])])
	# A form asked of a spec that already wore another leaves nothing of it behind, and a spec that differs only by its
	# stage or its bicycle is a different form, so the morph is built.
	_ok(not S.for_game(cycle, P.for_romset("pacman")).has("cycle") and not S.for_game(holo, P.for_romset("pacman")).has("holo"),
		"odd: a plain game asked of a bicycle's spec or a stage's has neither")
	for key: String in ["cycle", "holo"]:
		var with_it: Dictionary = cycle if key == "cycle" else holo
		var without := with_it.duplicate(true)
		without.erase(key)
		_ok(not S._same_form(without, with_it), "odd: a spec without its %s is another form (the morph is built)" % key)
	var sys := await _machine()
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	var base_forms := _form_count(model)
	var base_depth := -model.get_builtin_screen().position.z
	# A bicycle.
	model.morph_to(_spec("propcycl"))
	await _wait(2)
	_ok(_panels(model).size() == 1, "odd: the bicycle's one panel is built")
	if _panels(model).is_empty():
		return
	var p1 := _panels(model)[0] as ArcadeControlModule
	var parts_ok := _panels(model).size() == 1
	for part in ["BarsPivot", "BarGripL", "BarGripR", "CrankPivot", "CrankPedalL", "CrankPedalR", "Saddle", "Start", "SeatTube"]:
		parts_ok = parts_ok and p1.find_child(part, true, false) != null
	_ok(parts_ok, "odd: the bicycle has bars with two grips, a crank with its two pedals, a saddle and START")
	var bike_boxes: Array = model.get_meta(ArcadeCabinetBuilder.FORM_BOXES_META, [])
	_ok(bike_boxes.size() >= 1 and model.ground_footprint().y > 2.2,
		"odd: its stand can be aimed at to carry the cabinet, and the rectangle on the floor reaches the end of it (%s)" % str(model.ground_footprint()))
	_ok(model.find_child("Cycle", false, false) != null and (p1.grip().collision_layer & (1 << 20)) != 0 and _doors(model).size() == 1,
		"odd: it stands on its own stand, its bars can be aimed at to take hold of, and the cabinet has one coin door")
	var bars := p1.find_child("BarsPivot", true, false) as Node3D
	var rest_bars := bars.basis
	p1.show_state(1 << ControllerBindings.JOYPAD_RIGHT)
	for i in 30:
		p1.tick(1.0 / 60.0)
	var gl := (p1.find_child("BarGripL", true, false) as Node3D).global_position
	var gr := (p1.find_child("BarGripR", true, false) as Node3D).global_position
	_ok(not bars.basis.is_equal_approx(rest_bars) and gr.z > gl.z + 0.2,
		"odd: a right turn takes the right grip back toward the rider and the left one forward (%.2f m apart)" % (gr.z - gl.z))
	p1.show_state(1 << ControllerBindings.JOYPAD_UP)
	for i in 40:
		p1.tick(1.0 / 60.0)
	var pushed := bars.basis.y.z
	p1.show_state(1 << ControllerBindings.JOYPAD_DOWN)
	for i in 40:
		p1.tick(1.0 / 60.0)
	_ok(pushed < -0.1 and bars.basis.y.z > 0.1,
		"odd: UP pushes the grips forward over the stem and DOWN pulls them back (%.2f, %.2f)" % [pushed, bars.basis.y.z])
	p1.show_state(0)
	for i in 40:
		p1.tick(1.0 / 60.0)
	var crank := p1.find_child("CrankPivot", true, false) as Node3D
	var pedal := p1.find_child("CrankPedalR", true, false) as Node3D
	var axle_z := crank.global_position.z
	var top_z := pedal.global_position.z
	p1.show_state(0, Vector4i(0, 0, 0, -32767))
	for i in 10:
		p1.tick(1.0 / 60.0)
	_ok(pedal.global_position.z < axle_z - 0.12 and is_equal_approx(top_z, axle_z),
		"odd: the right stick up pedals forward: the pedal that was on top has gone away from the rider (%.2f -> %.2f)"
			% [top_z - axle_z, pedal.global_position.z - axle_z])
	p1.show_state(0, Vector4i(0, 0, 0, 32767))
	for i in 20:
		p1.tick(1.0 / 60.0)
	_ok(pedal.global_position.z > axle_z + 0.05, "odd: and down pedals backward")
	p1.show_state(0)
	# A hologram.
	model.morph_to(_spec("timetrv"))
	await _wait(2)
	var depth := -model.get_builtin_screen().position.z
	_ok(is_equal_approx(depth - base_depth, S.HOLO_DEPTH) and model.find_child("HoloPlinth", true, false) != null
			and model.find_child("HoloSideL", true, false) != null and model.find_child("HoloRoof", true, false) != null
			and model.find_child("HoloFloor", true, false) != null and model.find_child("Cycle", false, false) == null,
		"odd: Time Traveler's picture stands %.0f cm deeper than the generic cabinet's, in a black tunnel with a plinth, and the bicycle is gone"
			% (S.HOLO_DEPTH * 100.0))
	_ok((model.get_builtin_screen().mesh as QuadMesh).size.is_equal_approx(Vector2(0.44, 0.33)),
		"odd: and the picture is the tube's size still, only further back")
	# Two levers in one slot.
	model.morph_to(_spec("panicprk"))
	await _wait(2)
	_ok(_panels(model).size() == 2, "odd: Panic Park's two panels are built")
	if _panels(model).size() < 2:
		return
	var a := _panels(model)[0] as ArcadeControlModule
	var b := _panels(model)[1] as ArcadeControlModule
	var la := a.find_child("SlidePivot", true, false) as Node3D
	var lb := b.find_child("SlidePivot", true, false) as Node3D
	_ok(_panels(model).size() == 2 and la != null and lb != null and model.find_child("SlotRail", true, false) != null
			and model.find_child("HoloPlinth", true, false) == null,
		"odd: Panic Park has two levers on one rail, one panel each, and the deep stage is gone")
	var ca := ((la.find_child("LeverBall", true, false) as MeshInstance3D).material_override as StandardMaterial3D).albedo_color
	var cb := ((lb.find_child("LeverBall", true, false) as MeshInstance3D).material_override as StandardMaterial3D).albedo_color
	_ok(ca.r > ca.b + 0.4 and cb.b > cb.r + 0.4, "odd: player 1's lever ball is red and player 2's blue")
	# What a player slides is a big flat dome, and START is a big round button in the same colour (no other panel's START is more than 2.5 cm).
	var ball_mesh := (la.find_child("LeverBall", true, false) as MeshInstance3D).mesh as SphereMesh
	var start_a := a.find_child("Start", true, false) as MeshInstance3D
	var start_color := (start_a.get_active_material(0) as StandardMaterial3D).albedo_color
	_ok(ball_mesh.radius >= 0.04 and ball_mesh.height < ball_mesh.radius * 2.0 and (start_a.mesh as CylinderMesh).bottom_radius >= 0.025
			and start_color.is_equal_approx(ca),
		"odd: each handle is a flat dome %.0f cm across and each START a %.0f cm round button in its player's colour"
			% [ball_mesh.radius * 200.0, (start_a.mesh as CylinderMesh).bottom_radius * 200.0])
	var xa := la.global_position.x
	var xb := lb.global_position.x
	a.show_state(1 << ControllerBindings.JOYPAD_RIGHT)
	b.show_state(1 << ControllerBindings.JOYPAD_LEFT)
	for i in 40:
		a.tick(1.0 / 60.0)
		b.tick(1.0 / 60.0)
	_ok(xa < xb and absf((la.global_position.x - xa) - S.SLOT_TRAVEL) < 0.005 and absf((xb - lb.global_position.x) - S.SLOT_TRAVEL) < 0.005
			and absf(la.global_position.x - lb.global_position.x) < 0.01,
		"odd: each lever slides its half of the slot, and pushed to the ends they meet in the middle")
	# Back to the cabinet's own form: nothing left over.
	model.morph_to(model._base_spec)
	await _wait(2)
	_ok(_form_count(model) == base_forms and model.find_child("SlotRail", true, false) == null
			and is_equal_approx(-model.get_builtin_screen().position.z, base_depth),
		"odd: the cabinet's own form again leaves none of it behind (%d form parts)" % _form_count(model))


# --- reach ---------------------------------------------------------------------

## What a VR laser hits (XRToolsFunctionPointer.DEFAULT_MASK): the pointable layer and the one that blocks it.
const POINTER_MASK := 0b0000_0000_0101_0000_0000_0000_0000_0000


## The first thing a laser aimed from `from` at `to` meets, or null.
func _first_hit(sys: RetroSystem, from: Vector3, to: Vector3) -> Object:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = POINTER_MASK
	q.collide_with_areas = true
	q.collide_with_bodies = true
	var r := sys.get_world_3d().direct_space_state.intersect_ray(q)
	return r.get("collider") as Object if not r.is_empty() else null


## Where a hand aims from at something on a cabinet: in front of it, a little above, as a player stands.
func _hand_for(sys: RetroSystem, target: Vector3) -> Vector3:
	return target + sys.global_transform.basis * Vector3(0.0, 0.30, 0.55)


## A panel a morph built was once dead: its nodes were scripted AFTER they entered the tree, so the grip's _ready
## (which makes it pointable) never ran, and neither did the coin buttons'. Only the baked panels could be taken
## hold of; Cotton's, a wheel, a bike's bars and every panel of a four-player game could not. Every form, every
## panel, every coin button: pointable, and the first thing under a laser aimed from where a player stands.
func _group_reach() -> void:
	var sys := await _machine()
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	var games: Array = ["sf2", "cotton", "1943", "pacman", "tmnt", "xmen6p", "timecris", "ptblank", "opwolf", "sscope",
		"polepos", "daytona", "scud", "hangon", "ddrusa", "pumpipx2", "robotron", "centiped", "pong",
		"propcycl", "timetrv", "panicprk"]
	for romset: String in games:
		model.morph_to(_spec(romset))
		await _wait(3)
		var panels := _panels(model)
		var live := 0
		var aimable := 0
		var lit := 0
		var grips := 0
		for panel: ArcadeControlModule in panels:
			var grip := panel.grip()
			grips += 1 if grip != null else 0
			if grip == null or not panel.is_visible_in_tree():
				continue
			live += 1
			lit += 1 if (grip.collision_layer & ArcadePanelGrip.POINTABLE_LAYER) != 0 and grip.find_child("PanelHighlight", false, false) != null else 0
			aimable += 1 if _first_hit(sys, _hand_for(sys, grip.global_position), grip.global_position) == grip else 0
		_ok(grips == panels.size() and live >= 1 and lit == live,
			"reach: %s: every panel's grip is live (pointable, with its glow: %d of %d)" % [romset, lit, live])
		_ok(aimable == live, "reach: %s: a laser aimed at each panel from where a player stands meets its grip first (%d of %d)" % [romset, aimable, live])
		var buttons := 0
		var reached := 0
		for door: ArcadeCoinModule in _doors(model):
			if not door.door_enabled():
				continue
			for button_name in ["CoinReturn", "CoinSlot"]:
				var button := door.find_child(button_name, true, false) as VRButton
				if button == null:
					continue
				buttons += 1
				var centre := button.global_transform * Vector3(0, 0, 0.008)
				reached += 1 if _first_hit(sys, _hand_for(sys, centre), centre) == button else 0
		_ok(buttons >= 2 and reached == buttons,
			"reach: %s: every coin door's slot and RETURN can be aimed at (%d of %d)" % [romset, reached, buttons])


# --- ports ---------------------------------------------------------------------

func _group_ports() -> void:
	var sys := await _machine()
	var pad_scene := load(PAD_SCENE) as PackedScene
	_ok(pad_scene != null, "ports: a pad to plug in")
	if pad_scene == null:
		return
	var pad := pad_scene.instantiate() as Node3D
	add_child(pad)
	_spawned.append(pad)
	pad.global_position = sys.global_position + Vector3(0, 1.2, 1.2)
	await _wait(10)
	if pad.has_method("restore_port_connection"):
		pad.call("restore_port_connection", sys, 1)
	await _wait(10)
	_ok(sys.get_port_controllers()[1] == pad, "ports: a pad in the second front socket")
	# A one-gun game: socket 2 is not there any more, and the pad comes out.
	await _board(sys, "timecris")
	await _wait(10)
	_ok(sys.get_port_controllers()[1] == null, "ports: a game with one gun takes the second socket away, and the pad comes out")
	await _pull(sys)
	await _wait(6)
	if pad.has_method("restore_port_connection"):
		pad.call("restore_port_connection", sys, 0)
	await _wait(10)
	_ok(sys.get_port_controllers()[0] == pad, "ports: the pad in the first socket")
	await _board(sys, "ptblank")
	await _wait(10)
	var guns: Array = sys.captive_controllers()
	_ok(guns.size() == 2 and sys.get_port_controllers()[0] == guns[0], "ports: a gun takes the first socket's port, the pad comes out")


# --- input ---------------------------------------------------------------------

func _group_input() -> void:
	var sys := await _machine()
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	var input := model.arcade_input()
	(_panels(model)[0] as ArcadeControlModule).set_attached(true)
	_ok(input.playing, "input: attached to a panel")
	await _board(sys, "tmnt")
	_ok(not input.playing and input.attached.is_empty(), "input: a new form lets go of the panel that is gone")
	var panels := _panels(model)
	(panels[3] as ArcadeControlModule).set_attached(true)
	_ok(input.playing and input.attached.has(3), "input: player 4's new panel can be attached to")
	(panels[3] as ArcadeControlModule).set_attached(false)
	# A cabinet with more coin doors than panels (two panels, four doors; a mod's could be one): the fourth door's
	# coin still reaches port 4 (the input's loop used to stop at the last panel). The game is up (its boot run in
	# its own frames), so the coin goes straight in.
	var spec := model._base_spec.duplicate(true)
	spec["coins"] = [-0.21, -0.07, 0.07, 0.21]
	model.morph_to(spec)
	await _wait(2)
	_ok(_panels(model).size() == 2 and _doors(model).size() == 4, "input: two panels, four coin doors")
	sys.is_powered_on = true
	input.frame_override = 0
	await get_tree().process_frame
	await get_tree().process_frame
	input.frame_override = 100000
	var door4 := _doors(model)[3] as ArcadeCoinModule
	door4.coin_inserted.emit(door4.player)
	var seen := false
	for i in 12:
		await get_tree().process_frame
		seen = seen or (int(input.last_sent.get(3, 0)) & (1 << ArcadeProfiles.COIN_BIT)) != 0
	_ok(seen, "input: the fourth coin door's coin reaches port 4")
	sys.is_powered_on = false
	input.frame_override = -1


# --- animate -------------------------------------------------------------------

func _group_animate() -> void:
	var sys := await _machine()
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	model.morph_to(_spec("daytona"))
	await _wait(2)
	var p1 := _panels(model)[0] as ArcadeControlModule
	var wheel := p1.find_child("WheelPivot", true, false) as Node3D
	var gas := p1.find_child("GasPivot", true, false) as Node3D
	var rest_wheel := wheel.basis
	var rest_gas := gas.basis
	p1.show_state(1 << ControllerBindings.JOYPAD_R2, Vector4i(32767, 0, 0, 0))
	for i in 30:
		p1.tick(1.0 / 60.0)
	_ok(p1.steering() > 0.95 and not wheel.basis.is_equal_approx(rest_wheel), "animate: full right lock turns the wheel")
	_ok(p1.pedal_down("gas") > 0.95 and not gas.basis.is_equal_approx(rest_gas) and p1.pedal_down("brake") == 0.0,
		"animate: R2 presses the gas pedal and not the brake")
	# Clockwise seen by the driver: the wheel's top moves to the driver's right (+X).
	var top := wheel.global_transform * Vector3(0, 0, -0.15)
	var rest_top := (wheel.get_parent() as Node3D).global_transform * (rest_wheel * Vector3(0, 0, -0.15))
	_ok(top.x > rest_top.x + 0.05, "animate: a right turn takes the top of the wheel to the right")
	p1.show_state(1 << ControllerBindings.JOYPAD_LEFT)
	for i in 40:
		p1.tick(1.0 / 60.0)
	_ok(p1.steering() < -0.95 and p1.pedal_down("gas") < 0.05, "animate: LEFT turns it the other way, the gas comes back up")
	model.morph_to(_spec("hangon"))
	await _wait(2)
	var bike := _panels(model)[0] as ArcadeControlModule
	var lean := bike.find_child("LeanPivot", true, false) as Node3D
	var rest_lean := lean.basis
	bike.show_state(1 << ControllerBindings.JOYPAD_RIGHT)
	for i in 30:
		bike.tick(1.0 / 60.0)
	_ok(not lean.basis.is_equal_approx(rest_lean) and (lean.global_basis.y.x > 0.1), "animate: the bike leans into a right turn")
	model.morph_to(_spec("ddrusa"))
	await _wait(2)
	var dancer := _panels(model)[1] as ArcadeControlModule
	var up := dancer.find_child("PadUp", true, false) as Node3D
	var left := dancer.find_child("PadLeft", true, false) as Node3D
	var up_rest := up.position
	dancer.show_state(1 << ControllerBindings.JOYPAD_UP)
	_ok(not up.position.is_equal_approx(up_rest) and left.position.is_equal_approx(left.position),
		"animate: UP sinks player 2's up arrow")
	dancer.show_state(0)
	_ok(up.position.is_equal_approx(up_rest), "animate: and it comes back up")
	model.morph_to(_spec("robotron"))
	await _wait(2)
	var robo := _panels(model)[0] as ArcadeControlModule
	var s2 := robo.find_child("StickPivot2", true, false) as Node3D
	robo.show_state(1 << ControllerBindings.JOYPAD_A)
	for i in 20:
		robo.tick(1.0 / 60.0)
	_ok(not s2.basis.is_equal_approx(Basis.IDENTITY), "animate: the face buttons lean Robotron's fire stick")


# --- running -------------------------------------------------------------------

func _group_running() -> void:
	var sys := await _machine()
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	sys.is_powered_on = true
	model.on_media_inserted(null)
	model._request_form(_spec("tmnt"))
	# Frames go by with the core running: the build asked for is never done under it.
	await _wait(3)
	_ok(_panels(model).size() == 2, "running: a form asked for under a running core is not built")
	sys.is_powered_on = false
	model.on_power_off()
	await _wait(2)
	_ok(_panels(model).size() == 4, "running: it is built once the core stops")


# --- boxes ---------------------------------------------------------------------

func _count(node: Node, prefix: String) -> int:
	var n := 0
	for c in node.get_children():
		n += 1 if str(c.name).begins_with(prefix) else 0
	return n


## Every collision shape under a node, whatever it is called (Godot renames a duplicate name).
func _shapes(node: Node) -> int:
	var n := 0
	for c in node.get_children():
		n += 1 if c is CollisionShape3D and not c.is_queued_for_deletion() else 0
	return n


func _group_boxes() -> void:
	var sys := await _machine()
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	var area := sys.get_node("PointerArea")
	var cab := _count(sys, "CabinetBox")
	var ptr := _count(area, "PointerBox")
	var shapes := _shapes(sys)
	var area_shapes := _shapes(area)
	model.morph_to(_spec("tmnt"))
	await _wait(2)
	model.morph_to(model._base_spec)
	await _wait(2)
	_ok(_count(sys, "CabinetBox") == cab and _count(area, "PointerBox") == ptr and _count(area, "PointerDoor") == 1
			and _shapes(sys) == shapes and _shapes(area) == area_shapes,
		"boxes: two morphs later the cabinet has the same boxes, not twice as many (%d, %d)" % [_shapes(sys), _shapes(area)])
	model.morph_to(_spec("daytona"))
	await _wait(2)
	var forms: Array = model.get_meta(ArcadeCabinetBuilder.FORM_BOXES_META, [])
	_ok(forms.size() >= 3 and _count(area, "FormBox") == forms.size(), "boxes: the cockpit's seat, dash and platform can be aimed at")
	var reaches_cockpit := false
	for c in sys.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
			var box := (c as CollisionShape3D)
			reaches_cockpit = reaches_cockpit or box.position.z + (box.shape as BoxShape3D).size.z * 0.5 > 0.9
	_ok(not reaches_cockpit, "boxes: and none of it collides (a player walks into the cockpit and sits on their chair)")
	model.morph_to(_spec("timecris"))
	await _wait(2)
	_ok(_count(sys, "CabinetBox") > cab, "boxes: the gun body's straight screen adds its coin-face box")


# --- footprint -----------------------------------------------------------------

func _group_footprint() -> void:
	var sys := await _machine()
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	await _wait(2)
	_ok(model.ground_footprint().is_equal_approx(Vector2(0.66, 0.80)) and model.ground_footprint_center().is_zero_approx(),
		"footprint: the cabinet's own base, centred on it")
	model.morph_to(_spec("daytona"))
	await _wait(2)
	var size := model.ground_footprint()
	var center := model.ground_footprint_center()
	_ok(size.y > 2.3 and center.y > 0.7, "footprint: the cockpit's base reaches 2 m forward (%s about %s)" % [str(size), str(center)])
	var placer := sys.get_node_or_null("GroundPlacement") as GroundPlacement
	_ok(placer != null and placer.footprint.is_equal_approx(size) and placer.footprint_center.is_equal_approx(center),
		"footprint: and the rectangle on the floor follows it")
	model.morph_to(_spec("ddrusa"))
	await _wait(2)
	_ok(model.ground_footprint().x > 1.8, "footprint: two dancers' squares are wider than the cabinet (%s)" % str(model.ground_footprint()))
	model.morph_to(model._base_spec)
	await _wait(2)
	_ok(model.ground_footprint().is_equal_approx(Vector2(0.66, 0.80)) and placer.footprint_center.is_zero_approx(),
		"footprint: back to the cabinet's own")


# --- bezel ---------------------------------------------------------------------

## A MAME layout as Mr. Do's packs write them: an element per picture, a view with the bezel round the screen,
## and the credits in a comment.
const LAY_SCANNED := """<?xml version="1.0"?>
<mamelayout version="2">
	<element name="bezel"><image file="bezel.png"/></element>
	<element name="backdrop"><image file="backdrop.png"/></element>
	<view name="Upright_Artwork">
		<element ref="backdrop"><bounds x="0" y="0" width="400" height="300"/></element>
		<screen index="0"><bounds x="100" y="50" width="200" height="150"/></screen>
		<element ref="bezel"><bounds x="0" y="0" width="400" height="300"/></element>
	</view>
	<view name="Widescreen_Artwork">
		<screen index="0"><bounds x="440" y="0" width="1040" height="1080"/></screen>
		<bezel element="bezel"><bounds left="0" top="0" right="1920" bottom="1080"/></bezel>
	</view>
</mamelayout>
<!-- Artwork type: Bezel. Scanned bezel provided by Mr. Do -->
"""


func _group_bezel() -> void:
	var picked := ArcadeBezel.pick_bezel(ArcadeBezel.parse_layout(LAY_SCANNED))
	_ok(str(picked.get("file", "")) == "bezel.png" and str(picked.get("view", "")) == "Upright_Artwork"
			and (picked["hole"] as Rect2).is_equal_approx(Rect2(0.25, 1.0 / 6.0, 0.5, 0.5)),
		"bezel: the layout's bezel round its screen, the hole where the screen is (%s)" % str(picked.get("hole")))
	var wide := LAY_SCANNED.replace('name="Upright_Artwork"', 'name="Upright_Widescreen"')
	_ok(ArcadeBezel.pick_bezel(ArcadeBezel.parse_layout(wide)).is_empty(),
		"bezel: a widescreen view, and a 16:9 canvas, are television filler: none taken")
	var canvas := """<mamelayout version="2"><element name="bezel"><image file="b.png"/></element>
		<view name="Upright"><screen index="0"><bounds x="440" y="0" width="1040" height="1080"/></screen>
		<element ref="bezel"><bounds x="0" y="0" width="1920" height="1080"/></element></view></mamelayout>"""
	_ok(ArcadeBezel.pick_bezel(ArcadeBezel.parse_layout(canvas)).is_empty(), "bezel: a 16:9 canvas is a television's, whatever its view is called")
	var fan := LAY_SCANNED.replace("Scanned bezel provided by Mr. Do", "Realistic bezel by Someone")
	_ok(ArcadeBezel.pick_bezel(ArcadeBezel.parse_layout(fan)).is_empty(), "bezel: a bezel the credits call drawn is not taken")
	var legacy := """<mamelayout version="2"><element name="b"><image file="b.png"/></element>
		<view name="Bezel"><bezel element="b"><bounds xc="0.5" yc="0.5" width="2" height="1.5"/></bezel>
		<screen index="0"><bounds left="0" top="0" right="1" bottom="1"/></screen></view></mamelayout>"""
	var lp := ArcadeBezel.pick_bezel(ArcadeBezel.parse_layout(legacy))
	_ok(str(lp.get("file", "")) == "b.png" and (lp["hole"] as Rect2).is_equal_approx(Rect2(0.25, 1.0 / 6.0, 0.5, 2.0 / 3.0)),
		"bezel: the old <bezel> item and centred bounds are read too (%s)" % str(lp.get("hole")))
	var backdrop_only := LAY_SCANNED.replace('<element ref="bezel"><bounds x="0" y="0" width="400" height="300"/></element>', "")
	_ok(ArcadeBezel.pick_bezel(ArcadeBezel.parse_layout(backdrop_only.replace("Widescreen_Artwork", "x").replace(
			'<bezel element="bezel"><bounds left="0" top="0" right="1920" bottom="1080"/></bezel>', ""))).is_empty(),
		"bezel: a picture drawn UNDER the screen is a backdrop, not a bezel")
	# Where it hangs: the hole holds the tube, centred on it.
	var r := ArcadeScreenModule.bezel_rect(Vector2(400, 300), Rect2(0.25, 1.0 / 6.0, 0.5, 0.5), Vector2(0.40, 0.30), Vector2(0, 0.005))
	# The hole is in the picture's upper half, so the picture reaches further below the tube than above it.
	_ok(r.size.is_equal_approx(Vector2(0.80, 0.60)) and r.get_center().is_equal_approx(Vector2(0, 0.005 - 0.05)),
		"bezel: the picture is scaled so its hole is the tube, and stands where the hole puts it (%s)" % str(r))

	# The player's artwork: a clone (pacman) finds its parent's (puckman), as MAME looks.
	var dir := OS.get_temp_dir().path_join("retroxr_bezel_test")
	DirAccess.make_dir_recursive_absolute(dir)
	var img := Image.create(400, 300, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.9, 0.2, 0.1, 1.0))
	img.fill_rect(Rect2i(100, 50, 200, 150), Color(0, 0, 0, 0))
	var zip := ZIPPacker.new()
	zip.open(dir.path_join("puckman.zip"))
	zip.start_file("default.lay")
	zip.write_file(LAY_SCANNED.to_utf8_buffer())
	zip.close_file()
	zip.start_file("bezel.png")
	zip.write_file(img.save_png_to_buffer())
	zip.close_file()
	zip.close()
	ArcadeBezel.test_root = dir
	var found := ArcadeBezel.load_for_rom("/roms/arcade/pacman.zip")
	_ok(str(found.get("set", "")) == "puckman" and found.get("image") is Image and (found["image"] as Image).get_size() == Vector2i(400, 300),
		"bezel: Pac-Man (a clone) takes the bezel of its parent's artwork, puckman.zip")
	_ok(ArcadeBezel.load_for_rom("/roms/arcade/sf2.zip").is_empty(), "bezel: a game with no artwork has none")
	var sys := await _machine()
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	await _board(sys, "pacman")
	var screen := model.modules_of_kind(ArcadeProfiles.KIND_SCREEN)[0] as ArcadeScreenModule
	for i in 60:
		if screen.bezel() != null:
			break
		await get_tree().process_frame
	var hung := screen.bezel()
	var frame := screen.find_child("FrameSideL", false, false) as Node3D
	_ok(hung != null and model.bezel_texture() != null and frame != null and not frame.visible,
		"bezel: a Pac-Man board hangs it round the tube, and the black frame makes way")
	if hung != null:
		var tube := model.get_builtin_screen()
		var opening := screen.opening()
		var q := hung.mesh as QuadMesh
		_ok(q.size.x <= opening.size.x + 0.001 and q.size.y <= opening.size.y + 0.001,
			"bezel: cut to the monitor's opening (%s in %s)" % [str(q.size), str(opening.size)])
		# The hole's middle is the tube's middle: the part of the picture at the tube's centre is the hole's.
		var m := hung.material_override as StandardMaterial3D
		var at := Vector2(tube.position.x, tube.position.y) - (Vector2(hung.position.x, hung.position.y) - q.size * 0.5)
		var uv := Vector2(m.uv1_offset.x + m.uv1_scale.x * at.x / q.size.x, m.uv1_offset.y + m.uv1_scale.y * (1.0 - at.y / q.size.y))
		_ok(uv.is_equal_approx(Vector2(0.5, 0.25 + 1.0 / 6.0)) or uv.distance_to(Vector2(0.5, 1.0 / 6.0 + 0.25)) < 0.01,
			"bezel: the hole is centred on the tube (uv %s)" % str(uv))
	model.set_morph_enabled(false)
	await _wait(2)
	screen = model.modules_of_kind(ArcadeProfiles.KIND_SCREEN)[0] as ArcadeScreenModule
	frame = screen.find_child("FrameSideL", false, false) as Node3D
	_ok(screen.bezel() != null and not frame.visible, "bezel: a new form (the cabinet's own form again) hangs it on its new tube")
	sys.set_cabinet_art_enabled(false)
	_ok(screen.bezel() == null and frame.visible, "bezel: Cabinet Art off takes it down")
	sys.set_cabinet_art_enabled(true)
	_ok(screen.bezel() != null, "bezel: and on puts it back")
	await _pull(sys)
	screen = model.modules_of_kind(ArcadeProfiles.KIND_SCREEN)[0] as ArcadeScreenModule
	_ok(screen.bezel() == null and model.bezel_texture() == null, "bezel: pulling the board takes it away")
	ArcadeBezel.test_root = ""
	DirAccess.remove_absolute(dir.path_join("puckman.zip"))
	DirAccess.remove_absolute(dir)
