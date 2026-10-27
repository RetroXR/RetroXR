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
##   scope/     a rifle game of ONE screen has a digital scope: the part of the picture the rifle points at, magnified, in the eyepiece
##   service/   TEST and SERVICE in the compartment opposite the power switch, there when MAME says the game reads one
##   mount/     a gun on a swivel (Silent Scope's rifle, Operation Wolf's Uzi) is fixed to its cabinet: it turns about its pivot
##   odd/       Prop Cycle's bicycle, Time Traveler's deep stage, Panic Park's two levers in one slot
##   seating/   the sit-down versions: a flight cockpit with a stick and a throttle, a cabin, a base that tilts; a bench in front of a ride's guns
##   hood/      a sit-down cabinet's monitor stands under a hood: the picture is close enough to fill the view from the seat, the hood is solid and leaves the coin doors
##              under it open; nothing of the cockpit stands in the line of sight
##   racegun/   a driving cockpit of two seats with a gun each (Lucky & Wild): both players seated, the driver's wheel and pedal, both guns on the dash, the gunner's START
##   audit/     the data MAME gets wrong or leaves out, game by game (2026-10-26): Taito F3's spare dials, Darius Gaiden's players, the modern boards' driving games, Road
##              Blasters' and Bad Lands' wheels, Wing War's pod
##   music/     the rhythm games' own controllers: beatmania's decks, pop'n's nine domes, GuitarFreaks' guitars, DrumMania's pads, a Taiko drum a player, Mambo a Go-Go's three drums
##   styles/    a controller that is not a ball on a stick: Star Wars' and Red Baron's flight yoke, Bass Fishing's rod with its reel and crank
##   rider/     a rider STANDING on a rocking board (Top Skater's skateboard, Alpine Surfer's snowboard, Alpine Racer's skis): a stand, a plate that leans, a rail to hold
##   ring/      the R-360 pod (G-LOC R360, Wing War R360): two hoops at the platform's sides and one behind the seat in place of the cabin, turning with the stick, never in the picture's way
##   rotary/    a dial AND a stick is a rotary joystick (Ikari Warriors, Top Gunner's bootleg): the stick leans and a collar on its shaft turns
##   solo/      DDR Solo's stage has six panels: up-left and up-right are MAME's buttons 3 and 4, a foot or a finger on them presses them
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
	if _want("scope"):
		await _group_scope()
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
	if _want("seating"):
		await _group_seating()
		await _clear()
	if _want("hood"):
		await _group_hood()
		await _clear()
	if _want("racegun"):
		await _group_racegun()
		await _clear()
	if _want("audit"):
		await _group_audit()
		await _clear()
	if _want("styles"):
		await _group_styles()
		await _clear()
	if _want("rider"):
		await _group_rider()
		await _clear()
	if _want("ring"):
		await _group_ring()
		await _clear()
	if _want("rotary"):
		await _group_rotary()
		await _clear()
	if _want("solo"):
		await _group_solo()
		await _clear()
	if _want("music"):
		await _group_music()
		await _clear()
	if _want("shift"):
		await _group_shift()
		await _clear()
	if _want("reach"):
		await _group_reach()
		await _clear()
	if _want("grip"):
		await _group_grip()
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
	for kind in ["stick", "twin", "ball", "dial", "buttons", "rotary", "yoke", "rod"]:
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
	for romset in ["sf2", "timecris", "pc_smb", "darius"]:
		_ok(not (_spec(romset).get("screen", {}) as Dictionary).has("scope"), "screens: %s has no scope" % romset)
	# A rifle game of ONE screen (Golgo 13, Silent Scope EX) has a DIGITAL scope: no second screen to cut, a zoom into the one it has.
	for romset in ["sscopex", "sogeki", "sscopexu", "sscopefh", "golgo13", "g13knd", "g13jnr"]:
		var scope: Dictionary = (_spec(romset).get("screen", {}) as Dictionary).get("scope", {})
		_ok(is_equal_approx(float(scope.get("zoom", 0.0)), S.SCOPE_ZOOM) and not scope.has("main") and not scope.has("lens")
				and str(_spec(romset)["form"]) == "rifle",
			"screens: %s is a rifle of one screen: a digital scope of %.1f times, nothing cut out of its frame" % [romset, S.SCOPE_ZOOM])
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
	_ok(lens != null and (lens.mesh as QuadMesh).size.is_equal_approx(Vector2(0.074, 0.0555)),
		"screens: Silent Scope: the rifle's eyepiece carries a screen 7.4 x 5.5 cm, twice the width it had (%s)" % str((lens.mesh as QuadMesh).size if lens != null else "none"))
	# ... inside the eyepiece cup it sits at the end of: the cup is wider than the picture's diagonal and ends where the picture is.
	var cup := lens.get_parent().find_child("ScopeEye", false, false) as MeshInstance3D if lens != null else null
	var cup_mesh := cup.mesh as CylinderMesh if cup != null else null
	var diagonal := (lens.mesh as QuadMesh).size.length() if lens != null else 0.0
	_ok(cup_mesh != null and cup_mesh.top_radius * 2.0 >= diagonal and cup_mesh.bottom_radius < cup_mesh.top_radius
			and absf((lens.position.z - cup.position.z) - cup_mesh.height * 0.5) < 0.002,
		"screens: and the picture is inside the cup it sits at the end of (cup %.1f cm across at the eye, picture's diagonal %.1f cm)"
			% [cup_mesh.top_radius * 200.0 if cup_mesh != null else 0.0, diagonal * 100.0])
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


## A rifle game of one screen (Golgo 13, Silent Scope EX) had a dead eyepiece: there is no second screen to show in it. Its scope is a digital one now: the
## monitor shows the whole picture and the lens the part of it the rifle points at, magnified, following the gun's own aim.
func _group_scope() -> void:
	# The window, pure: 1/zoom of the picture on each axis, centred on the aim, kept inside it.
	var mid := ArcadeScreenModule.follow_rect(2.5, Vector2i.ZERO)
	var top_left := ArcadeScreenModule.follow_rect(2.5, Vector2i(-32767, -32767))
	var bottom_right := ArcadeScreenModule.follow_rect(2.5, Vector2i(32767, 32767))
	var right_mid := ArcadeScreenModule.follow_rect(2.5, Vector2i(32767, 0))
	_ok(mid.size.is_equal_approx(Vector2(0.4, 0.4)) and mid.position.is_equal_approx(Vector2(0.3, 0.3))
			and top_left.position.is_equal_approx(Vector2.ZERO) and bottom_right.end.is_equal_approx(Vector2.ONE)
			and absf(right_mid.end.x - 1.0) < 1.0e-5 and absf(right_mid.position.y - 0.3) < 1.0e-4,
		"scope: the window is 0.4 of the picture, in the middle for an aim at the middle, never outside it at its edges (%s %s %s)" % [mid, top_left, bottom_right])
	_ok(ArcadeScreenModule.follow_rect(1.0, Vector2i(5000, -9000)).is_equal_approx(Rect2(0.0, 0.0, 1.0, 1.0))
			and ArcadeScreenModule.follow_rect(0.0, Vector2i.ZERO).is_equal_approx(Rect2(0.0, 0.0, 1.0, 1.0)),
		"scope: a zoom of 1, or of nothing, is the whole picture")
	var sys := await _machine()
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	await _board(sys, "golgo13")
	await _wait(6)
	var lens := _scope_lens(sys)
	var screen_module := model.modules_of_kind(ArcadeProfiles.KIND_SCREEN)[0] as ArcadeScreenModule
	_ok(lens != null and is_equal_approx(screen_module.scope_zoom, S.SCOPE_ZOOM) and not screen_module.scope_part.has_area(),
		"scope: Golgo 13's rifle has a lens, and the screen module a digital scope of %.1f times and no part to cut" % screen_module.scope_zoom)
	var gun := sys.captive_controllers()[0] as LightGun
	var card := Image.create(640, 480, false, Image.FORMAT_RGBA8)
	card.fill(Color(0.2, 0.3, 0.5))
	var frame_tex := ImageTexture.create_from_image(card)
	screen_module.aspect_override = 4.0 / 3.0
	var lens_mat: ShaderMaterial = null
	var rects: Array[Vector4] = []
	for aim: Vector2i in [Vector2i.ZERO, Vector2i(-32767, -32767), Vector2i(32767, 32767), Vector2i(20000, -12000)]:
		gun.last_aim = aim
		screen_module.present(frame_tex, false, false, 0.0)
		lens_mat = lens.get_surface_override_material(0) as ShaderMaterial
		rects.append(lens_mat.get_shader_parameter("view_rect") if lens_mat != null else Vector4.ZERO)
	var main_rect: Vector4 = screen_module._material.get_shader_parameter("view_rect")
	_ok(not screen_module.is_cut() and absf(main_rect.x) < 1.0e-5 and absf(main_rect.z - 1.0) < 1.0e-5 and absf(main_rect.w - 1.0) < 1.0e-5,
		"scope: the monitor shows the whole picture (%s)" % main_rect)
	_ok(lens_mat != null and absf(rects[0].x - 0.3) < 1.0e-4 and absf(rects[0].y - 0.3) < 1.0e-4 and absf(rects[0].z - 0.4) < 1.0e-4
			and absf(rects[1].x) < 1.0e-4 and absf(rects[1].y) < 1.0e-4 and absf(rects[2].x - 0.6) < 1.0e-4 and absf(rects[2].y - 0.6) < 1.0e-4
			and rects[3].x > rects[0].x + 0.1 and rects[3].y < rects[0].y - 0.05,
		"scope: and the lens shows what the rifle points at, magnified: middle, top left, bottom right, right and up (%s)" % str(rects))
	var fit: Vector2 = lens_mat.get_shader_parameter("fit_scale") if lens_mat != null else Vector2.ZERO
	_ok(absf(fit.x - 1.0) < 0.01 and absf(fit.y - 1.0) < 0.01, "scope: a 4:3 picture's 4:3 window fills the 4:3 lens (%s)" % fit)
	# The game on show (attract) or a cord from another machine is not a frame of the game: no lens.
	screen_module.present(frame_tex, false, true, 0.0)
	var dark_attract := lens.get_surface_override_material(0) != lens_mat
	screen_module.present(frame_tex, false, false, 0.0)
	screen_module.present(frame_tex, true, false, 0.0)
	var dark_external := lens.get_surface_override_material(0) != lens_mat
	_ok(dark_attract and dark_external, "scope: the lens is dark while the game is only on show, and while another machine's picture is on the glass")
	screen_module.present(frame_tex, false, false, 0.0)
	_ok(lens.get_surface_override_material(0) == lens_mat, "scope: and shows the game again when it runs")
	# Silent Scope's own scope is the other kind: a second screen cut out of the frame, no zoom.
	await _pull(sys)
	await _board(sys, "sscope")
	await _wait(6)
	var ss := model.modules_of_kind(ArcadeProfiles.KIND_SCREEN)[0] as ArcadeScreenModule
	_ok(ss.scope_zoom == 0.0 and ss.scope_part.has_area(), "scope: Silent Scope keeps its second screen cut out of the frame, with no zoom")
	# A game that is no rifle has none.
	await _pull(sys)
	await _board(sys, "sf2")
	await _wait(6)
	var plain := model.modules_of_kind(ArcadeProfiles.KIND_SCREEN)[0] as ArcadeScreenModule
	_ok(plain.scope_zoom == 0.0 and _scope_lens(sys) == null, "scope: and a street fighter has no scope at all")


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


# --- seating -------------------------------------------------------------------

func _near(a: float, b: float, tolerance: float = 1.0e-4) -> bool:
	return absf(a - b) <= tolerance


## Is `node` somewhere under a node called `ancestor`?
func _under(node: Node, ancestor: String) -> bool:
	var n: Node = node.get_parent() if node != null else null
	while n != null:
		if str(n.name) == ancestor:
			return true
		n = n.get_parent()
	return false


## The sit-down versions of the games (Tools/arcade/cockpits.py): who had a seat, a cabin round it, a base that moved and a throttle, and what the
## cabinet builds for them.
func _group_seating() -> void:
	# What the table says each game's cabinet had, form first, then the seat / cabin / motion flags, then whether it reads a throttle.
	var rows := {
		"aburner2": ["fly", "scm", true], "aburner": ["fly", "scm", false], "sharrier": ["fly", "sm", false],
		"gloc": ["fly", "scm", true], "glocr360": ["fly", "smr", false], "gforce2": ["fly", "scm", true],
		"thndrbld": ["fly", "sm", true], "thndrbld1": ["fly", "sm", true], "strkfgtr": ["fly", "scm", true],
		"sstrkfgt": ["fly", "s", false], "skytargt": ["fly", "s", false], "nightstr": ["fly", "sc", false],
		"mlanding": ["fly", "scm", false], "topland": ["fly", "sc", false], "ainferno": ["fly", "scm", false],
		"slrasslt": ["fly", "scm", false], "aircomb": ["fly", "sc", true], "airco22b": ["fly", "sc", true], "tceptor": ["fly", "s", false],
		"outrun": ["race", "sm", false], "toutrun": ["race", "sm", false], "pdrift": ["race", "sm", false], "smgp": ["race", "sm", false],
		"eca": ["race", "", false], "daytona": ["race", "", false], "polepos": ["stand", "", false],
		"rchase": ["gun", "sm", false], "rchase2": ["gunm", "sm", false], "jpark": ["gunm", "sm", false],
		"lostwsga": ["gunm", "s", false], "loffire": ["gunm", "s", false],
		"gunblade": ["gunm", "", false], "alien3": ["gunm", "", false], "timecris": ["gun", "", false],
	}
	var bad: Array[String] = []
	for romset: String in rows:
		var row: Array = rows[romset]
		var p := P.for_romset(romset)
		var flags := "%s%s%s%s" % ["s" if p.has_seat() else "", "c" if p.has_cabin() else "", "m" if p.has_motion() else "", "r" if p.has_ring() else ""]
		if p.form() != str(row[0]) or flags != str(row[1]) or p.has_throttle() != bool(row[2]):
			bad.append("%s is %s/%s/%s" % [romset, p.form(), flags, str(p.has_throttle())])
	_ok(bad.is_empty(), "seating: the table files %d games under the form, the seat, cabin, motion and throttle their cabinets had%s"
		% [rows.size(), "" if bad.is_empty() else " (wrong: " + ", ".join(bad) + ")"])
	# Nothing else carries them: a seat is only read by a form that can show one, a throttle only by a flight cockpit.
	var stray: Array[String] = []
	var seated := 0
	var seated_uprights: Array[String] = []
	for romset: String in P._index.keys():
		var p := P.for_romset(romset)
		if p.has_seat() or p.has_cabin() or p.has_motion():
			seated += 1
			if p.form() == P.FORM_UPRIGHT and p.has_seat() and not p.has_cabin() and not p.has_motion():
				# An upright you sat at: only Darius's cabinet (Darius, Darius II and their clones) and Sega's Star Wars Arcade.
				seated_uprights.append(romset)
			elif not (p.form() in [P.FORM_FLY, P.FORM_RACE, P.FORM_GUN, P.FORM_GUN_MOUNTED]) or not p.has_seat():
				stray.append(romset)
		if p.has_throttle() and p.form() != P.FORM_FLY:
			stray.append(romset + " (throttle)")
	_ok(stray.is_empty() and seated > 60, "seating: only a flight, driving or gun-ride form carries them, and always with a seat (%d games; stray: %s)"
		% [seated, ", ".join(stray)])
	seated_uprights.sort()
	_ok(seated_uprights == ["darius", "darius2", "darius2d", "darius2do", "dariuse", "dariusj", "dariuso", "dariusu", "sagaia", "swa", "swaj"],
		"seating: and the uprights you sat at are Darius's, with Darius II, and Sega's Star Wars Arcade (%s)" % ", ".join(seated_uprights))
	_ok(P.for_romset("aburner2").has_seat() and not P.for_romset("not_a_real_romset").has_seat()
			and not P.for_romset("not_a_real_romset").has_throttle() and P.for_romset("not_a_real_romset").form() == P.FORM_UPRIGHT,
		"seating: a game the table does not know has no seat and no throttle")
	# The specs.
	var ab := _spec("aburner2")
	var cp: Dictionary = ab["cockpit"]
	_ok(str(ab["form"]) == "fly" and str(ab["shape"]) == "racer" and (ab["players"] as Array).is_empty() and bool(cp["flight"])
			and bool(cp["cabin"]) and bool(cp["roof"]) and bool(cp["motion"]) and bool(cp["throttle"]) and not bool(cp["shifter"]),
		"seating: After Burner II asks for the racing body with a flight cockpit: cabin, moving base, throttle, no gear lever")
	var sharrier: Dictionary = _spec("sharrier")["cockpit"]
	var night: Dictionary = _spec("nightstr")["cockpit"]
	_ok(bool(sharrier["motion"]) and not bool(sharrier["cabin"]) and not bool(sharrier["throttle"])
			and bool(night["cabin"]) and not bool(night["motion"]) and not bool(night["throttle"]),
		"seating: Space Harrier moves in the open, Night Striker is a cabin that does not, neither has a throttle")
	_ok(bool(_spec("outrun")["cockpit"]["motion"]) and not bool(_spec("daytona")["cockpit"]["motion"])
			and not _spec("outrun")["cockpit"].has("flight"),
		"seating: Out Run's deluxe sits on a moving base, Daytona USA's cabinet does not")
	var lost := _spec("lostwsga")
	_ok(lost.has("bench") and int(lost["bench"]["seats"]) == 2 and int(lost["guns"]) == 2 and str(lost["gun_style"]) == "mounted"
			and int(_spec("rchase")["bench"]["seats"]) == 2 and str(_spec("rchase")["gun_style"]) == "holster",
		"seating: The Lost World and Rail Chase ask for a bench with a seat a gun, the guns where they hang")
	_ok(not _spec("gunblade").has("bench") and not _spec("timecris").has("bench") and not _spec("sscope").has("bench")
			and not _spec("sf2").has("bench") and not _spec("daytona").has("bench"),
		"seating: and a standing gun game, a rifle and a street fighter ask for none")
	# The pref that lets a base move: the player's choice, else on at a desk and off in a headset.
	var before := AppPrefs.arcade_motion
	AppPrefs.arcade_motion = AppPrefs.MOTION_AUTO
	var auto := AppPrefs.arcade_motion_enabled(false) and not AppPrefs.arcade_motion_enabled(true)
	AppPrefs.arcade_motion = AppPrefs.MOTION_ON
	var always := AppPrefs.arcade_motion_enabled(true) and AppPrefs.arcade_motion_enabled(false)
	AppPrefs.arcade_motion = AppPrefs.MOTION_OFF
	var never := not AppPrefs.arcade_motion_enabled(true) and not AppPrefs.arcade_motion_enabled(false)
	AppPrefs.arcade_motion = before
	_ok(auto and always and never, "seating: motion is automatic (on at a desk, off in a headset), always, or never, as the player chooses")

	# Built: After Burner II.
	var sys := await _machine()
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	model.morph_to(_spec("aburner2"))
	model.apply_game_profile(P.for_romset("aburner2"))
	await _wait(3)
	var pivot := model.find_child("MotionPivot", true, false) as Node3D
	var panel := _panels(model)[0] as ArcadeControlModule
	var seat := model.find_child("DriverSeat", true, false)
	_ok(pivot != null and seat is CockpitSeat and _under(seat, "MotionPivot") and _under(panel, "MotionPivot")
			and _under(model.find_child("Platform", true, false), "MotionPivot") and _under(model.find_child("CabinRoof", true, false), "MotionPivot"),
		"seating: After Burner II's seat, platform, cabin and controls are all on the moving base")
	_ok(panel.find_child("StickPivot", true, false) != null and panel.find_child("StickBall", true, false) != null
			and panel.find_child("ThrottlePivot", true, false) != null and panel.find_child("ThrottleKnob", true, false) != null
			and panel.find_child("WheelPivot", true, false) == null and panel.find_child("GasPivot", true, false) == null
			and panel.find_child("ShifterPivot", true, false) == null and panel.find_child("Start", true, false) != null,
		"seating: the driver's controller is a stick and a throttle, with START, and no wheel, pedals or gear lever")
	var cabin_parts := ["CabinWallL", "CabinWallR", "CabinRoof", "CabinTrimL", "CabinTrimR", "CabinLamp1", "CabinLamp5"]
	var missing: Array[String] = []
	for part: String in cabin_parts:
		if model.find_child(part, true, false) == null:
			missing.append(part)
	_ok(missing.is_empty(), "seating: and a cabin round the seat: walls, a roof running forward over the monitor and the lock-on lamps (missing: %s)" % ", ".join(missing))
	_ok(_under(panel.find_child("Btn1", true, false), "StickPivot") and _under(panel.find_child("Btn2", true, false), "StickPivot")
			and panel.cap_shown(0) and panel.cap_shown(1) and not panel.cap_shown(2) and not panel.cap_shown(5),
		"seating: its two buttons are on the stick's head, and the four it does not read are not drawn")
	# A throttle the game in the bay does not read is not drawn (a cockpit that stays when the game changes), and is when it does.
	var lever := panel.find_child("ThrottlePivot", true, false) as Node3D
	panel.apply_profile(P.for_romset("nightstr"))
	var hidden := not lever.visible
	panel.apply_profile(P.for_romset("aburner2"))
	_ok(hidden and lever.visible, "seating: a throttle lever the game does not read is not drawn, and is drawn for one that does")
	# The stick leans where it is pushed, as the grip is: right, and back toward the player.
	var ball := panel.find_child("StickBall", true, false) as Node3D
	var rest_ball := model.to_local(ball.global_position)
	panel.show_state(1 << ControllerBindings.JOYPAD_RIGHT, Vector4i.ZERO)
	for i in 20:
		panel.tick(0.05)
	var right_ball := model.to_local(ball.global_position)
	panel.show_state(1 << ControllerBindings.JOYPAD_DOWN, Vector4i.ZERO)
	for i in 20:
		panel.tick(0.05)
	var back_ball := model.to_local(ball.global_position)
	_ok(right_ball.x > rest_ball.x + 0.05 and absf(right_ball.z - rest_ball.z) < 0.01 and back_ball.z > rest_ball.z + 0.05
			and absf(back_ball.x - rest_ball.x) < 0.01,
		"seating: the flight stick leans right with RIGHT and back toward the player with DOWN (%.3f, %.3f)" % [right_ball.x - rest_ball.x, back_ball.z - rest_ball.z])
	# The throttle is the right stick's Y: up is forward, the lever's top away from the player, and it moves back when the stick does.
	panel.show_state(0, Vector4i.ZERO)
	for i in 20:
		panel.tick(0.05)
	var knob := panel.find_child("ThrottleKnob", true, false) as Node3D
	var idle_knob := model.to_local(knob.global_position)
	panel.show_state(0, Vector4i(0, 0, 0, -32767))
	for i in 20:
		panel.tick(0.05)
	var forward_knob := model.to_local(knob.global_position)
	var forward_amount := panel.throttle_amount()
	panel.show_state(0, Vector4i(0, 0, 0, 32767))
	for i in 40:
		panel.tick(0.05)
	var back_knob := model.to_local(knob.global_position)
	_ok(_near(forward_amount, 1.0, 0.01) and forward_knob.z < idle_knob.z - 0.08 and back_knob.z > idle_knob.z + 0.08,
		"seating: the right stick up pushes the throttle forward (away from the player), down pulls it back (%.3f m, %.3f m)"
			% [forward_knob.z - idle_knob.z, back_knob.z - idle_knob.z])
	panel.show_state(0, Vector4i.ZERO)
	# The moving base: the player's choice lets it move; it banks into the turn and noses up with a pull; it tilts about its centre.
	var zc := (ArcadeCabinetBuilder.COCKPIT_Z0 + ArcadeCabinetBuilder.COCKPIT_Z1) * 0.5
	var centre := Vector3(0.0, ArcadeCabinetBuilder.PLATFORM_TOP, zc)
	panel.motion_override = 0
	panel.show_state((1 << ControllerBindings.JOYPAD_RIGHT) | (1 << ControllerBindings.JOYPAD_DOWN), Vector4i.ZERO)
	for i in 60:
		panel.tick(0.05)
	_ok(pivot.transform.is_equal_approx(Transform3D.IDENTITY) and panel.motion_state() == Vector2.ZERO,
		"seating: with motion off the base stays where it is, whatever the stick does")
	panel.motion_override = 1
	for i in 80:
		panel.tick(0.05)
	var tilt := pivot.transform
	var port := tilt * Vector3(-0.3, 0.1, zc)
	var starboard := tilt * Vector3(0.3, 0.1, zc)
	var nose := tilt * Vector3(0.0, 0.1, ArcadeCabinetBuilder.COCKPIT_Z0)
	var tail := tilt * Vector3(0.0, 0.1, ArcadeCabinetBuilder.COCKPIT_Z1)
	_ok(starboard.y < port.y - 0.01 and nose.y > tail.y + 0.01,
		"seating: with motion on, the base banks right with the stick pushed right and noses up with it pulled back (%.3f m, %.3f m)"
			% [port.y - starboard.y, nose.y - tail.y])
	_ok((tilt * centre).distance_to(centre) < 1.0e-4 and panel.motion_state().is_equal_approx(Vector2(1.0, 0.8)),
		"seating: it turns about its centre, a few degrees and no more, and the extent follows the stick (%s)" % str(panel.motion_state()))
	var roll := absf(rad_to_deg(asin(clampf(tilt.basis.y.x, -1.0, 1.0))))
	_ok(roll > 2.0 and roll < 6.0, "seating: the bank at full stick is %.1f degrees: a few, because a head is carried on it" % roll)
	panel.rest()
	for i in 90:
		panel.tick(0.05)
	_ok(pivot.transform.is_equal_approx(Transform3D.IDENTITY), "seating: the run over, the base settles level")
	# The input says so when the core stops: the base settles and the throttle goes back, with nobody calling rest().
	panel.show_state(1 << ControllerBindings.JOYPAD_RIGHT, Vector4i(0, 0, 0, -32767))
	for i in 80:
		panel.tick(0.05)
	var tilted := not pivot.transform.is_equal_approx(Transform3D.IDENTITY) and panel.throttle_amount() > 0.9
	model.arcade_input()._end_run()
	for i in 90:
		panel.tick(0.05)
	_ok(tilted and pivot.transform.is_equal_approx(Transform3D.IDENTITY) and absf(panel.throttle_amount()) < 0.01,
		"seating: the end of a run (the core stopped) is what settles the base and puts the throttle back")
	panel.motion_override = -1

	# The others.
	model.morph_to(_spec("gloc"))
	model.apply_game_profile(P.for_romset("gloc"))
	await _wait(3)
	var gloc_panel := _panels(model)[0] as ArcadeControlModule
	_ok(gloc_panel.cap_shown(2) and _under(gloc_panel.find_child("Btn3", true, false), "ThrottlePivot") and not gloc_panel.cap_shown(3),
		"seating: G-LOC's third button, After Burner, is on the throttle's knob")
	model.morph_to(_spec("nightstr"))
	model.apply_game_profile(P.for_romset("nightstr"))
	await _wait(3)
	_ok(model.find_child("ThrottlePivot", true, false) == null and model.find_child("MotionPivot", true, false) == null
			and model.find_child("CabinWallL", true, false) != null and model.find_child("DriverSeat", true, false) is CockpitSeat,
		"seating: Night Striker is a cabin with a seat and a stick, no throttle lever and no moving base")
	model.morph_to(_spec("sharrier"))
	model.apply_game_profile(P.for_romset("sharrier"))
	await _wait(3)
	var sharrier_panel := _panels(model)[0] as ArcadeControlModule
	_ok(model.find_child("CabinWallL", true, false) == null and model.find_child("CabinRoof", true, false) == null
			and model.find_child("MotionPivot", true, false) != null
			and _under(sharrier_panel.find_child("Btn3", true, false), "StickPivot") and sharrier_panel.cap_shown(2),
		"seating: Space Harrier's seat is in the open on a moving base, its third button on the stick")
	model.morph_to(_spec("outrun"))
	model.apply_game_profile(P.for_romset("outrun"))
	await _wait(3)
	var out_panel := _panels(model)[0] as ArcadeControlModule
	_ok(model.find_child("MotionPivot", true, false) != null and out_panel.find_child("WheelPivot", true, false) != null
			and out_panel.find_child("StickPivot", true, false) == null and _under(out_panel, "MotionPivot"),
		"seating: Out Run is the driving cockpit (a wheel and pedals) on a moving base")
	out_panel.motion_override = 1
	out_panel.show_state(1 << ControllerBindings.JOYPAD_LEFT, Vector4i.ZERO)
	for i in 60:
		out_panel.tick(0.05)
	var out_pivot := model.find_child("MotionPivot", true, false) as Node3D
	_ok((out_pivot.transform * Vector3(-0.3, 0.1, zc)).y < (out_pivot.transform * Vector3(0.3, 0.1, zc)).y - 0.01,
		"seating: and banks into a left turn")
	model.morph_to(_spec("daytona"))
	await _wait(3)
	_ok(model.find_child("MotionPivot", true, false) == null and model.find_child("DriverSeat", true, false) is CockpitSeat,
		"seating: Daytona USA's cockpit is on no base: nothing to tilt")

	# A ride: a bench in front of the guns, a seat a gun.
	model.morph_to(_spec("lostwsga"))
	await _wait(3)
	var bench := model.find_child("Bench", false, false)
	var seat1 := model.find_child("BenchSeat1", true, false)
	var seat2 := model.find_child("BenchSeat2", true, false)
	_ok(bench != null and seat1 is CockpitSeat and seat2 is CockpitSeat and (model.get_parent().call("captive_controllers") as Array).size() == 2
			and model.find_child("MotionPivot", true, false) == null,
		"seating: The Lost World has a bench with two seats in front of its two guns, which are still hung")
	var eye1 := model.to_local((seat1 as CockpitSeat).eye_transform().origin)
	var eye2 := model.to_local((seat2 as CockpitSeat).eye_transform().origin)
	_ok(_near(eye1.y, ArcadeCabinetBuilder.BENCH_EYE_Y, 0.005) and eye1.x < -0.1 and eye2.x > 0.1 and _near(eye1.z, eye2.z, 0.001),
		"seating: the eyes are %.2f m up, a bench's and not a stool's, each player to their own side" % eye1.y)
	var up1 := model.to_local((seat1 as CockpitSeat).stand_point())
	var up2 := model.to_local((seat2 as CockpitSeat).stand_point())
	_ok(up1.x < eye1.x - 0.4 and up2.x > eye2.x + 0.4 and _near(up1.y, 0.0, 0.01) and _near(up2.y, 0.0, 0.01),
		"seating: and each gets up on the outside of their own seat, onto the floor")
	_ok(model.ground_footprint().y > 1.4, "seating: the bench is part of the cabinet's footprint on the floor (%s)" % str(model.ground_footprint()))
	var solid := false
	for box: AABB in model.get_meta(ArcadeCabinetBuilder.FORM_BOXES_META, []):
		solid = solid or (box.size.x >= 0.85 and box.size.z >= 0.7 and box.position.z <= ArcadeCabinetBuilder.BENCH_Z0 + 0.01 and box.size.y <= 0.11)
	_ok(solid, "seating: and its platform is a box the laser can aim at (the cabinet's, to take hold of it by)")
	# An upright you sat at: Darius's three screens, a bench-style seat a player a hand's reach from the panel.
	var dsp := _spec("darius")
	_ok(dsp.has("bench") and int(dsp["bench"]["seats"]) == 2 and _near(float((dsp["bench"] as Dictionary).get("seat_z", -1.0)), S.UPRIGHT_BENCH_Z) and _spec("darius2").has("bench")
			and not _spec("ninjaw").has("bench") and not _spec("dariusg").has("bench") and not _spec("sf2").has("bench") and not _spec("pacman").has("bench"),
		"seating: Darius and Darius II ask for a bench with a seat a player, Ninja Warriors, Darius Gaiden and the other uprights for none")
	# Sega's Star Wars Arcade: two seats (a pilot and a gunner), a joystick each, and the biggest picture an upright's body holds (a 50 inch class screen).
	var swa := _spec("swa")
	_ok(swa.has("bench") and int(swa["bench"]["seats"]) == 2 and _spec("swaj").has("bench") and _kinds(swa) == ["stick", "stick"] and not swa.has("cockpit")
			and str(swa["shape"]) == "tall" and int(swa["screen"]["inches"]) == 50 and not _spec("starwars").has("bench"),
		"seating: Sega's Star Wars Arcade is a bench of two seats, a pilot and a gunner, in front of a joystick each and a 50 inch class screen; Atari's Star Wars is an upright")
	model.morph_to(dsp)
	model.apply_game_profile(P.for_romset("darius"))
	await _wait(3)
	var dseat1 := model.find_child("BenchSeat1", true, false) as CockpitSeat
	var dseat2 := model.find_child("BenchSeat2", true, false) as CockpitSeat
	var dball := model.find_child("StickBall", true, false) as Node3D
	var dglass := model.find_child("CabinetScreen", true, false) as MeshInstance3D
	_ok(dseat1 != null and dseat2 != null and dball != null and dglass != null and model.find_child("Player1", true, false) != null and _panels(model).size() == 2,
		"seating: Darius is a bench of two seats in front of its two panels and its screens")
	if dseat1 != null and dball != null and dglass != null:
		var deye := dseat1.eye_transform().origin
		var reach := deye.distance_to(dball.global_position)
		var away := deye.distance_to(dglass.global_position)
		_ok(reach < 0.80 and away > 0.5 and away < 1.1 and model.to_local(dseat1.eye_transform().origin).z < 1.25,
			"seating: the seated player reaches a stick (%.2f m) and the pictures are %.2f m away" % [reach, away])
		# Nothing of the cabinet's front in the line of sight to the pictures (the sticks and the deck stand below it).
		# The platform is under the seats, with room round them to step on and off, wherever the seats stand.
		var platform := model.find_child("BenchPlatform", true, false) as MeshInstance3D
		var seat_back := model.to_local(dseat1.global_position).z
		var pz := platform.position.z
		var half := (platform.mesh as BoxMesh).size.z * 0.5
		_ok(pz - half < seat_back - 0.25 and pz + half > seat_back + 0.25, "seating: the bench's platform is under its seats, with room before and behind them (%.2f..%.2f, seats at %.2f)" % [pz - half, pz + half, seat_back])
		var blockers := _sight_blockers(model, deye, dglass, model.find_child("Deck", true, false))
		_ok(blockers.is_empty() and not _meshes(model.find_child("Deck", true, false)).is_empty(),
			"seating: and nothing on the deck stands between the eyes and the pictures (%s)" % ", ".join(blockers))
	model.morph_to(_spec("gunblade"))
	await _wait(3)
	_ok(model.find_child("Bench", false, false) == null and model.find_child("BenchSeat1", true, false) == null,
		"seating: a standing gun game has no bench, and the one morphed away leaves nothing behind")
	model.morph_to(_spec("rchase"))
	await _wait(3)
	_ok(model.find_child("Bench", false, false) != null and model.find_child("Holster1", true, false) != null,
		"seating: Rail Chase is a bench in front of two holstered guns")


## A sit-down cabinet's picture is a metre from the seated eyes and fills about 28 degrees of the view (it was 1.6 m and 16 degrees when the dash, wheel and seat
## stood where the monitor's own door swings): the monitor stands under a HOOD over the bay door's swing, the glass starting at its front lip.
func _group_hood() -> void:
	var shape: Dictionary = S.shapes()["racer"]
	var hood: Dictionary = shape["hood"]
	var glass_a: Vector2 = shape["glass_a"]
	_ok(_near(float(hood["z1"]), glass_a.x, 0.001) and _near(float(hood["y1"]), glass_a.y, 0.001),
		"hood: the glass starts where the hood ends (its lower edge is the hood's front lip)")
	_ok(float(hood["y0"]) >= 0.78 and float(hood["z1"]) >= 0.80,
		"hood: it is over the bay door's swing (above the coin face's top, as far out as the door opens), not in it")
	var sys := await _machine()
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	var plain := _count(sys, "CabinetBox")
	for romset: String in ["aburner2", "gloc", "glocr360", "sharrier", "outrun", "daytona", "scud"]:
		model.morph_to(_spec(romset))
		model.apply_game_profile(P.for_romset(romset))
		await _wait(3)
		var seat := model.find_child("DriverSeat", true, false) as CockpitSeat
		var screen := model.find_child("CabinetScreen", true, false) as MeshInstance3D
		if seat == null or screen == null:
			_ok(false, "hood: %s has a seat and a picture" % romset)
			continue
		var eye := seat.eye_transform().origin
		var quad := (screen.mesh as QuadMesh).size * Vector2(screen.global_transform.basis.get_scale().x, screen.global_transform.basis.get_scale().y)
		var dist := eye.distance_to(screen.global_position)
		var hfov := rad_to_deg(2.0 * atan(quad.x * 0.5 / dist))
		_ok(dist >= 0.80 and dist <= 1.05 and hfov >= 24.0 and hfov <= 36.0,
			"hood: %s: the picture is %.2f m from the seated eyes and fills %.1f degrees of the view (not 1.6 m and 16)" % [romset, dist, hfov])
		# Nothing of the cockpit between the eyes and the picture's middle or its upper corners (the wheel may reach the lower edge, as a real one does).
		var blocked := _sight_blockers(model, eye, screen)
		_ok(blocked.is_empty(), "hood: %s: nothing of the cockpit stands in the line of sight to the picture (%s)" % [romset, ", ".join(blocked)])
	# Solid: the hood and the wedge of glass over it are collision (a held cabinet or a pushed object does not pass through), and a morph away takes them back.
	model.morph_to(_spec("daytona"))
	await _wait(3)
	var solid: Array = model.get_meta(ArcadeCabinetBuilder.SOLID_BOXES_META, [])
	_ok(solid.size() == 1 + ArcadeCabinetBuilder.HOOD_GLASS_STEPS and _count(sys, "CabinetBox") == plain + solid.size(),
		"hood: the hood and the glass's steps are collision boxes of the cabinet (%d of them, %d in all)" % [solid.size(), _count(sys, "CabinetBox")])
	var hit := _solid_hit(sys, sys.global_transform * Vector3(0.0, 0.84, 1.20), sys.global_transform * Vector3(0.0, 0.84, 0.45))
	_ok(hit == sys, "hood: a rod pushed in under the hood's lip at the height of its slab meets the cabinet")
	var under := _solid_hit(sys, sys.global_transform * Vector3(0.0, 0.66, 1.20), sys.global_transform * Vector3(0.0, 0.66, 0.45))
	_ok(under != sys, "hood: and the same rod under it, at the coin door's height, is stopped by nothing: the door still swings")
	# The wedge of glass: a rod pushed at the picture stops within 4 cm of the glass's slope, whatever the height (the steps are cut to the slope).
	var worst := 0.0
	var stopped := 0
	for y: float in [0.92, 1.04, 1.06, 1.16, 1.20, 1.30]:
		var r := _solid_hit_at(sys, sys.global_transform * Vector3(0.0, y, 1.20), sys.global_transform * Vector3(0.0, y, 0.45))
		if r.is_empty() or r.get("collider") != sys:
			continue
		stopped += 1
		var glass_z: float = lerpf((S.shapes()["racer"]["glass_a"] as Vector2).x, (S.shapes()["racer"]["glass_b"] as Vector2).x,
			(y - (S.shapes()["racer"]["glass_a"] as Vector2).y) / ((S.shapes()["racer"]["glass_b"] as Vector2).y - (S.shapes()["racer"]["glass_a"] as Vector2).y))
		worst = maxf(worst, absf(sys.to_local(r["position"]).z - glass_z))
	_ok(stopped == 6 and worst < 0.04, "hood: a rod pushed at the glass stops within %.1f cm of its slope at every height (%d of 6 stopped)" % [worst * 100.0, stopped])
	_ok(not _is_pointer_over(sys, Vector3(0.0, 0.84, 0.70)), "hood: the hood is no pointer box: a laser from above reaches the coin doors under it")
	model.morph_to(model._base_spec)
	await _wait(3)
	_ok(not model.has_meta(ArcadeCabinetBuilder.SOLID_BOXES_META) and _count(sys, "CabinetBox") == plain,
		"hood: the cabinet's own form takes them away again (%d boxes)" % _count(sys, "CabinetBox"))


## What of a cockpit (or of `root`, a deck) stands between `eye` and the picture's middle or its upper corners (the wheel may reach the lower edge, as a real one does): the names of the
## meshes whose bounds the line to any of them goes through, the seats themselves left out.
func _sight_blockers(model: Node, eye: Vector3, screen: MeshInstance3D, root: Node = null) -> Array[String]:
	var cockpit := (root if root != null else model.find_child("Cockpit", false, false)) as Node3D
	var scale := screen.global_transform.basis.get_scale()
	var quad := (screen.mesh as QuadMesh).size * Vector2(scale.x, scale.y)
	var blocked: Array[String] = []
	for c: Vector2 in [Vector2(0.0, 0.0), Vector2(-0.5, 0.5), Vector2(0.5, 0.5), Vector2(0.0, 0.5)]:
		var target: Vector3 = screen.global_transform * Vector3(c.x * quad.x / scale.x, c.y * quad.y / scale.y, 0.0)
		for mi: MeshInstance3D in _meshes(cockpit):
			if _under(mi, "DriverSeat") or _under(mi, "GunnerSeat") or not mi.is_visible_in_tree():
				continue
			var box: AABB = mi.global_transform * mi.get_aabb()
			if box.intersects_segment(eye, target) != null:
				blocked.append(str(mi.name))
	return blocked


## Every MeshInstance3D under a node.
func _meshes(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node == null:
		return out
	for c in node.get_children():
		if c is MeshInstance3D:
			out.append(c)
		out.append_array(_meshes(c))
	return out


## The first solid thing a rod from `from` to `to` meets: what the cabinet's own body is made of, on the layers the machine sits in.
func _solid_hit(sys: RetroSystem, from: Vector3, to: Vector3) -> Object:
	var r := _solid_hit_at(sys, from, to)
	return r.get("collider") as Object if not r.is_empty() else null


## The same, with where it met it (the ray query's result).
func _solid_hit_at(sys: RetroSystem, from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = sys.collision_layer
	q.collide_with_areas = false
	q.collide_with_bodies = true
	return sys.get_world_3d().direct_space_state.intersect_ray(q)


## Is there a pointer box (anything a laser stops on) at this point of the cabinet?
func _is_pointer_over(sys: RetroSystem, local: Vector3) -> bool:
	var q := PhysicsPointQueryParameters3D.new()
	q.position = sys.global_transform * local
	q.collision_mask = POINTER_MASK
	q.collide_with_areas = true
	q.collide_with_bodies = true
	return not sys.get_world_3d().direct_space_state.intersect_point(q).is_empty()


## Lucky & Wild: a driver and a gunner in one car. It was an upright with a wheel and nothing to sit on and no gun.
func _group_racegun() -> void:
	for romset: String in ["luckywld", "luckywldj"]:
		_ok(P.for_romset(romset).form() == P.FORM_RACEGUN and P.for_romset(romset).gun_count() == 2 and P.for_romset(romset).is_driving() and P.for_romset(romset).is_gun(),
			"racegun: %s is filed as a driving cockpit with two guns" % romset)
	_ok(P.for_romset("daytona").form() == P.FORM_RACE and P.for_romset("timecris").form() == P.FORM_GUN and P.for_romset("sf2").form() == P.FORM_UPRIGHT,
		"racegun: and no other game is")
	var sp := _spec("luckywld")
	var cockpit: Dictionary = sp["cockpit"]
	_ok(str(sp["shape"]) == "racer" and float(sp["width"]) >= S.RACEGUN_WIDTH and int(cockpit["seats"]) == 2 and int(sp["guns"]) == 2 and str(sp["gun_style"]) == "dash"
			and (sp["players"] as Array).is_empty() and not bool(cockpit["shifter"]) and not bool(cockpit["roof"]),
		"racegun: the spec is the racing body %.2f m wide with two seats, two guns on the dash, no panel and no gear lever" % float(sp["width"]))
	_ok(S.gun_xs(2, 0.9, "dash") == S.RACEGUN_GUN_XS and (S.gun_xs(1, 0.9, "dash") as Array).size() == 1,
		"racegun: the guns hang in the middle of the dash, a hand's reach from either seat")
	var sys := await _machine()
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	var base_forms := _form_count(model)
	model.morph_to(sp)
	model.apply_game_profile(P.for_romset("luckywld"))
	await _wait(4)
	var driver := model.find_child("DriverSeat", true, false) as CockpitSeat
	var gunner := model.find_child("GunnerSeat", true, false) as CockpitSeat
	_ok(driver != null and gunner != null and driver != gunner and driver.find_child("SeatTrigger", false, false) is SeatTrigger and gunner.find_child("SeatTrigger", false, false) is SeatTrigger,
		"racegun: two seats, each a CockpitSeat with its own cushion to press")
	if driver == null or gunner == null:
		return
	var eye_d := model.to_local(driver.eye_transform().origin)
	var eye_g := model.to_local(gunner.eye_transform().origin)
	_ok(_near(eye_d.x, -S.RACEGUN_SEAT_X, 0.005) and _near(eye_g.x, S.RACEGUN_SEAT_X, 0.005) and _near(eye_d.y, eye_g.y, 0.001) and _near(eye_d.z, eye_g.z, 0.001),
		"racegun: the driver sits on the left and the gunner on the right, side by side (%s, %s)" % [str(eye_d), str(eye_g)])
	var stand_d := model.to_local(driver.stand_point())
	var stand_g := model.to_local(gunner.stand_point())
	_ok(stand_d.x < -float(sp["width"]) * 0.5 and stand_g.x > float(sp["width"]) * 0.5 and _near(stand_d.y, 0.0, 0.01) and _near(stand_g.y, 0.0, 0.01),
		"racegun: and each gets up on the outside of their own seat, onto the floor (%s, %s)" % [str(stand_d), str(stand_g)])
	# The driver's controls are the driver's: the wheel and the pedals on the left, in front of the first seat.
	var panels := _panels(model)
	var p1 := model.find_child("Player1", true, false) as ArcadeControlModule
	var p2 := model.find_child("Player2", true, false) as ArcadeControlModule
	_ok(panels.size() == 2 and p1 != null and p2 != null and p1.player == 0 and p2.player == 1,
		"racegun: two controllers, the driver's (player 1) and the gunner's (player 2)")
	var wheel := p1.find_child("WheelPivot", true, false) as Node3D
	var axle := model.find_child("PedalAxle", true, false) as Node3D
	_ok(wheel != null and axle != null and _near(model.to_local(wheel.global_position).x, -S.RACEGUN_SEAT_X, 0.01) and _near(model.to_local(axle.global_position).x, -S.RACEGUN_SEAT_X, 0.01)
			and p1.find_child("StickPivot", true, false) == null and p1.find_child("ShifterPivot", true, false) == null,
		"racegun: the wheel and the pedals are in front of the driver's seat, with no stick and no gear lever")
	var start1 := p1.find_child("Start", true, false) as Node3D
	var start2 := p2.find_child("Start", true, false) as Node3D
	var s1 := model.to_local(start1.global_position) if start1 != null else Vector3.ZERO
	var s2 := model.to_local(start2.global_position) if start2 != null else Vector3.ZERO
	_ok(start1 != null and start2 != null and s1.x < -0.3 and s2.x > 0.3 and _near(s1.y, s2.y, 0.01) and _near(s1.z, s2.z, 0.01) and p2.find_child("StickPivot", true, false) == null,
		"racegun: and each has a START at their end of the dash, level with the other's (%s, %s)" % [str(s1), str(s2)])
	# The guns: one each, in holsters on the dash between the seats, within a hand's reach of both, their cords going into the dash.
	var guns: Array = sys.captive_controllers()
	var sockets := model.find_child("Sockets", true, false) as ArcadeSocketModule
	_ok(guns.size() == 2 and sockets != null and sockets.holster_count() == 2 and sockets.seat_count() == 2 and sockets.pivot_node(0) == null,
		"racegun: two guns in holsters, free to be carried, with a socket each for the cord")
	var reach := 0.0
	var on_dash := true
	for i in 2:
		var holster := model.to_local(sockets.holster_transform(i).origin)
		var cord := model.to_local(sockets.cord_entry(i))
		reach = maxf(reach, maxf(eye_d.distance_to(holster), eye_g.distance_to(holster)))
		on_dash = on_dash and holster.z > ArcadeCabinetBuilder.DASH_FACE_Z and holster.z < ArcadeCabinetBuilder.DASH_FACE_Z + 0.2 and holster.y > 0.3 and holster.y < 0.7 \
			and absf(cord.z - ArcadeCabinetBuilder.DASH_FACE_Z) < 0.01 and absf(holster.x) < 0.12
	_ok(on_dash and reach < 0.9, "racegun: both holsters are on the dash's face toward the seats, the cords into it, %.2f m from the farthest eye: a reach" % reach)
	var left := model.to_local(sockets.holster_transform(0).origin).x
	var right := model.to_local(sockets.holster_transform(1).origin).x
	_ok(left < right - 0.1 and not guns.is_empty() and (guns[0] as Node).name == "ArcadeLightGun", "racegun: the first player's gun is the left one, and the guns are the cabinet's pistols")
	# What stands in front of each pair of eyes: the picture, nothing in between.
	var screen := model.find_child("CabinetScreen", true, false) as MeshInstance3D
	for seat: CockpitSeat in [driver, gunner]:
		var eye := seat.eye_transform().origin
		var dist := eye.distance_to(screen.global_position)
		var blocked := _sight_blockers(model, eye, screen)
		_ok(dist >= 0.80 and dist <= 1.10 and blocked.is_empty(), "racegun: %s sees the picture from %.2f m, nothing in the way (%s)" % [seat.name, dist, ", ".join(blocked)])
	# Two coin doors under the hood, both reachable, and the cabinet's own form again after it.
	_ok(_doors(model).size() == 2, "racegun: a coin door for each player")
	model.morph_to(model._base_spec)
	await _wait(3)
	_ok(_form_count(model) == base_forms and model.find_child("GunnerSeat", true, false) == null and sys.captive_controllers().is_empty(),
		"racegun: the cabinet's own form again leaves no seat, no gun and no holster behind (%d form parts)" % _form_count(model))


## The games a player asked about, each with the hardware it had (K8): the data MAME gets wrong or leaves out.
func _group_audit() -> void:
	# Taito F3: the board's two spare paddle dials are declared for every one of its 35 games, and only Arkanoid Returns reads them. With them each was drawn with a spinner where
	# its joystick was (Puzzle Bobble 2, Elevator Action Returns, Darius Gaiden...).
	var f3 := ["arabianm", "bubblem", "bublbob2", "cleopatr", "commandw", "cupfinal", "dankuga", "dariusg", "dariusgx", "elvactr", "gekiridn", "gseeker", "gunlock", "intcup94",
			"kaiserkn", "kirameki", "landmakr", "lightbr", "pbobble2", "pbobble3", "pbobble4", "popnpop", "puchicar", "pwrgoal", "qtheater", "quizhuhu", "recalh", "ridingf",
			"ringrage", "scfinals", "spcinv95", "tcobra2", "trstar", "twinqix"]
	var f3_bad: Array = []
	for romset: String in f3:
		var gp := P.for_romset(romset)
		if not gp.known or gp.has_kind(P.KIND_DIAL) or not gp.has_kind(P.KIND_JOY) or S.panel_kind(gp) != "stick":
			f3_bad.append(romset)
	_ok(f3_bad.is_empty(), "audit: none of Taito F3's games has a dial, each has its joystick (%s)" % str(f3_bad))
	_ok(P.for_romset("arkretrn").has_kind(P.KIND_DIAL) and S.panel_kind(P.for_romset("arkretrn")) == "dial",
		"audit: Arkanoid Returns, which does read a paddle, keeps its dial")
	_ok(not P.for_romset("arkretrn").has_kind(P.KIND_JOY) and P.for_romset("arkretrn").buttons == 4,
		"audit: and no joystick beside it (the F3 board's is for its menus), the four buttons the joystick carried kept")
	# Darius Gaiden is a two-player upright, whatever four players the F3 board takes.
	var dg := P.for_romset("dariusg")
	var dsp := _spec("dariusg")
	_ok(dg.players == 2 and dg.coins == 2 and P.for_romset("dariusgx").players == 2 and (dsp["players"] as Array).size() == 2 and (dsp["coins"] as Array).size() == 2
			and _kinds(dsp) == ["stick", "stick"],
		"audit: Darius Gaiden has two panels of a stick and two coin doors, the Extra Version too (%s)" % str(_kinds(dsp)))
	# World Combat / Warzaid (Konami Viper, 2002): one optical gun a player. MAME's 4P sets leave the gun axes undefined and list two buttons; only the 2P set was a gun game.
	var wc_bad: Array = []
	for romset: String in ["wcombat", "wcombatj", "wcombatk", "wcombatu"]:
		var gp := P.for_romset(romset)
		var sp := _spec(romset)
		if gp.form() != P.FORM_GUN or int(sp["guns"]) != 2 or str(sp["gun_style"]) != "holster" or _kinds(sp) != ["start", "start"] or sp.has("gun_pedals"):
			wc_bad.append("%s (%s)" % [romset, gp.form()])
	_ok(wc_bad.is_empty() and not P.for_romset("kickgoal").is_gun(),
		"audit: all four World Combat sets are gun cabinets, two guns in holsters and no pedal, as the 2P set was (%s)" % str(wc_bad))
	# The modern boards give a driving game a joystick panel, or no controls at all: each was a sit-down cockpit.
	var race_bad: Array = []
	for romset: String in ["outr2", "outr2st", "crtaxihr", "wangmid", "wangmid2", "initd", "initdexp", "initdv3j", "inidv3cy", "clubkrt", "clubk2k3", "f355", "f355twin", "sgdrvsim",
			"sgnascar", "wgp", "wgp2", "tx1", "outr2sdx", "initiad4", "segartv", "hummerxt", "fzeroax", "mkartagp", "wanganmd", "wanganmr", "acedriv3", "rrvac", "batlgr3"]:
		var gp := P.for_romset(romset)
		var sp := _spec(romset)
		if not gp.known or gp.form() != P.FORM_RACE or not gp.is_driving() or str(sp.get("shape", "")) != "racer" or not sp.has("cockpit") or not (sp["players"] as Array).is_empty():
			race_bad.append("%s (%s)" % [romset, gp.form()])
	_ok(race_bad.is_empty(), "audit: OutRun 2, the Wangan Midnights, Initial D, Club Kart, F355, NASCAR, F-Zero AX and their kind are sit-down cockpits (%s)" % str(race_bad))
	_ok(int(_spec("tx1")["screen"]["screens"]) == 3 and float(_spec("tx1")["width"]) > 1.0, "audit: TX-1's three screens are in a seated cockpit's wide body (%.2f m)" % float(_spec("tx1")["width"]))
	_ok(P.for_romset("motogp").form() == P.FORM_BIKE and not _spec("motogp").has("cockpit"), "audit: Namco's MotoGP, which declares no controls, is a ride-on motorbike")
	# Road Blasters and Night Driver: the wheel on an upright's panel, the pedal at its foot.
	for romset: String in ["roadblst", "nitedrvr"]:
		var sp := _spec(romset)
		var ps: Array = sp["players"]
		_ok(P.for_romset(romset).form() == P.FORM_STAND and ps.size() == 1 and str(ps[0]["kind"]) == "wheel" and str(sp["shape"]) in ["upright", "tate"],
			"audit: %s is a stand-up driving cabinet, the wheel on its panel" % romset)
	# Bad Lands: a steering wheel for each of two players, with no pedals (the gas is a button); its bootleg, a joystick, keeps its stick.
	var bl := _spec("badlands")
	var bp: Array = bl["players"]
	_ok(bp.size() == 2 and _kinds(bl) == ["wheel", "wheel"] and not bool(bp[0].get("pedals", true)) and not bool(bp[1].get("pedals", true)) and not bool(bp[0].get("shifter", true))
			and float(bp[1]["wheel_x"]) - float(bp[0]["wheel_x"]) >= 0.40 and (bp[0]["buttons"] as Array).size() == 2,
		"audit: Bad Lands has a wheel a player, 0.4 m or more apart, two buttons each, no pedals (%s)" % str(_kinds(bl)))
	_ok(_kinds(_spec("badlandsb")) == ["stick", "stick"], "audit: and its bootleg, a joystick game, is a joystick cabinet")
	var sys := await _machine()
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	model.morph_to(bl)
	model.apply_game_profile(P.for_romset("badlands"))
	await _wait(4)
	var wheels := model.find_children("WheelPivot", "Node3D", true, false)
	_ok(wheels.size() == 2 and model.find_child("GasPivot", true, false) == null and model.find_child("PedalAxle", true, false) == null and _panels(model).size() == 2,
		"audit: built, Bad Lands has two wheels and no pedal (%d wheels)" % wheels.size())
	var wx: Array = []
	for w in wheels:
		wx.append(model.to_local((w as Node3D).global_position).x)
	wx.sort()
	_ok(wx.size() == 2 and float(wx[1]) - float(wx[0]) >= 0.40, "audit: the wheels stand 0.4 m or more apart (%s)" % str(wx))
	# Wing War R360 shares G-LOC R360's pod: a seat in rings, on a base that moves (the plain Wing War has its cabin).
	for romset: String in ["wingwar360", "wingwar", "glocr360"]:
		var gp := P.for_romset(romset)
		var ringed := romset != "wingwar"
		_ok(gp.form() == P.FORM_FLY and gp.has_seat() and gp.has_cabin() == not ringed and gp.has_ring() == ringed and gp.has_motion(),
			"audit: %s is a flight cockpit with a seat, %s and a moving base" % [romset, "rings" if ringed else "a cabin"])


## DDR Solo (K8): a stage of six panels, the four arrows and the two corners on the screen's side, which MAME reads as buttons 3 and 4.
func _group_solo() -> void:
	var bad: Array = []
	for romset: String in ["ddr4ms", "ddr4msj", "ddr4mps", "ddrs2k", "ddrs2kj", "ddrsbm"]:
		var sp := _spec(romset)
		if P.for_romset(romset).stage_arrows() != 6 or int(sp["stage"]["arrows"]) != 6 or _kinds(sp) != ["pad"] or (sp["stage"]["xs"] as Array).size() != 1:
			bad.append(romset)
	_ok(bad.is_empty(), "solo: the four Solo games and their clones are one stage of six arrows (%s)" % str(bad))
	_ok(P.for_romset("ddr4m").stage_arrows() == 4 and P.for_romset("ddrusa").stage_arrows() == 4 and P.for_romset("ddrkara").stage_arrows() == 4
			and P.for_romset("ddrkids").stage_arrows() == 4 and P.for_romset("pumpipx2").stage_arrows() == 5 and P.for_romset("sf2").stage_arrows() == 4,
		"solo: two-player DDR, Karaoke Mix and Kids keep four arrows, Pump It Up five")
	# The panels of the 3 x 3 square: the top row, the two sides' middles and the bottom's middle; the centre and the bottom corners stay bare.
	var cells: Array = []
	for row in 3:
		for col in 3:
			if ArcadeCabinetBuilder._is_arrow(6, row, col):
				cells.append(Vector2i(col, row))
	_ok(cells.size() == 6 and cells.has(Vector2i(0, 0)) and cells.has(Vector2i(1, 0)) and cells.has(Vector2i(2, 0)) and cells.has(Vector2i(0, 1)) and cells.has(Vector2i(2, 1))
			and cells.has(Vector2i(1, 2)) and not ArcadeCabinetBuilder._is_arrow(6, 1, 1) and not ArcadeCabinetBuilder._is_arrow(6, 2, 0) and not ArcadeCabinetBuilder._is_arrow(6, 2, 2),
		"solo: the six are up-left, up, up-right, left, right and down (%s)" % str(cells))
	var sys := await _machine()
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	model.morph_to(_spec("ddrsbm"))
	model.apply_game_profile(P.for_romset("ddrsbm"))
	await _wait(4)
	var panel := _panels(model)[0] as ArcadeControlModule
	var pads := {}
	for n: String in ["PadUp", "PadDown", "PadLeft", "PadRight", "PadUpLeft", "PadUpRight"]:
		var node := panel.find_child(n, true, false) as Node3D
		pads[n] = model.to_local(node.global_position) if node != null else Vector3(INF, INF, INF)
	var placed := true
	for n: String in pads:
		placed = placed and not (pads[n] as Vector3).is_equal_approx(Vector3(INF, INF, INF))
	_ok(placed, "solo: the stage has all six panels, named for the directions and the corners")
	if not placed:
		return
	var ul: Vector3 = pads["PadUpLeft"]
	var up: Vector3 = pads["PadUp"]
	var ur: Vector3 = pads["PadUpRight"]
	_ok(ul.x < up.x - 0.2 and up.x < ur.x - 0.2 and _near(ul.z, up.z, 0.01) and _near(ur.z, up.z, 0.01) and _near((pads["PadLeft"] as Vector3).x, ul.x, 0.01)
			and _near((pads["PadRight"] as Vector3).x, ur.x, 0.01) and (pads["PadDown"] as Vector3).z > up.z + 0.4 and _near((pads["PadDown"] as Vector3).x, up.x, 0.01),
		"solo: the corners are on the screen's side, over the left and right panels, the down panel at the player's end of the square")
	var tiles := 0
	for c in model.find_children("StageTile*", "MeshInstance3D", true, false):
		tiles += 1
	_ok(tiles == 3, "solo: and the three squares that are no arrow are bare tiles (%d)" % tiles)
	# The corners are MAME's buttons 3 and 4 ("P1 Up-Left", "P1 Up-Right"): they sink with them and nothing else does.
	var ulp := panel.find_child("PadUpLeft", true, false) as Node3D
	var urp := panel.find_child("PadUpRight", true, false) as Node3D
	var upp := panel.find_child("PadUp", true, false) as Node3D
	var ul_rest := ulp.position
	var ur_rest := urp.position
	var up_rest := upp.position
	panel.show_state(1 << ArcadeProfiles.button_bit(3))
	_ok(not ulp.position.is_equal_approx(ul_rest) and urp.position.is_equal_approx(ur_rest) and upp.position.is_equal_approx(up_rest),
		"solo: button 3 sinks the up-left panel and no other")
	panel.show_state(1 << ArcadeProfiles.button_bit(4))
	_ok(ulp.position.is_equal_approx(ul_rest) and not urp.position.is_equal_approx(ur_rest) and upp.position.is_equal_approx(up_rest),
		"solo: button 4 sinks the up-right panel, and the up-left comes back")
	panel.show_state(1 << ControllerBindings.JOYPAD_UP)
	_ok(ulp.position.is_equal_approx(ul_rest) and not upp.position.is_equal_approx(up_rest), "solo: UP sinks the up panel alone")
	panel.show_state(0)
	# A finger on a corner presses the game's button for it.
	var hands := ArcadePanelHands.new(panel)
	var bits: Array = []
	for poke: ArcadePanelHands.Poke in hands.pokes():
		bits.append(poke.bit)
	_ok(bits.has(ArcadeProfiles.button_bit(3)) and bits.has(ArcadeProfiles.button_bit(4)) and bits.has(ControllerBindings.JOYPAD_UP) and bits.size() >= 6,
		"solo: a fingertip can press each of the six (%d zones)" % bits.size())
	# The two-player stage keeps its four.
	model.morph_to(_spec("ddr4m"))
	model.apply_game_profile(P.for_romset("ddr4m"))
	await _wait(4)
	var plain := true
	for p: ArcadeControlModule in _panels(model):
		plain = plain and p.find_child("PadUpLeft", true, false) == null and p.find_child("PadUpRight", true, false) == null and p.find_child("PadUp", true, false) != null
	_ok(plain and _panels(model).size() == 2, "solo: DDR 4th Mix keeps four arrows a dancer, no corner panel")


## The rhythm games' own controllers (K8): which instrument each game has, where each of MAME's buttons is on it, and that the parts are where the input and a finger find them.
func _group_music() -> void:
	var want := {
		"deck": ["bm1stmix", "bm2ndmix", "bm2ndmixa", "bm3rdmix", "bm4thmix", "bm5thmix", "bm6thmix", "bm7thmix", "bmcompmx", "bmcompm2", "bmfinal", "bmdct"],
		"popn": ["popn1", "popn1j", "popn2", "popn3", "popn4", "popn5", "popn6", "popn7", "popn8", "popnanm", "popnanm2", "popnmt"],
		"guitar": ["gtrfrks", "gtrfrksja", "gtrfrk2m", "gtrfrk5m", "gtrfrk9m", "gtfrk11m", "gtrfrkva", "gtrfrkv3a"],
		"drums": ["drmn", "drmn5m", "drmn10m", "drmnv3a", "pcnfrk", "pcnfrk5m", "pcnfrk10m"],
		"taiko": ["taiko2", "taiko3", "taiko6", "taikort", "taiko7", "taiko8", "taiko9", "taiko10", "taiko11"],
		"conga": ["mamboagg", "mamboagga"],
	}
	var bad: Array = []
	for instrument: String in want:
		for romset: String in want[instrument]:
			var gp := P.for_romset(romset)
			if not gp.known or gp.form() != P.FORM_MUSIC or gp.instrument() != instrument:
				bad.append("%s (%s)" % [romset, gp.instrument()])
	_ok(bad.is_empty(), "music: every beatmania, pop'n music, GuitarFreaks, DrumMania, Taiko and Mambo a Go-Go set has its instrument (%s)" % str(bad))
	_ok(P.for_romset("bmiidx").instrument().is_empty() and P.for_romset("kbm").instrument().is_empty() and P.for_romset("bm3").instrument().is_empty() and P.for_romset("sf2").instrument().is_empty()
			and P.for_romset("ppp").form() == P.FORM_ODD,
		"music: IIDX, Keyboardmania and beatmania III have none yet, and an upright has none")
	# What each instrument asks of the cabinet: panels, a deck as deep as it needs.
	var shapes := {"deck": [2, 0.0], "popn": [1, 0.0], "guitar": [2, 0.0], "drums": [1, 0.20], "taiko": [2, 0.25], "conga": [1, 0.12]}
	var shapes_bad: Array = []
	for instrument: String in shapes:
		var sp := _spec(str(want[instrument][0]))
		var ps: Array = sp["players"]
		var all_music := true
		for k: String in _kinds(sp):
			all_music = all_music and k == "music"
		if ps.size() != int(shapes[instrument][0]) or not all_music or not is_equal_approx(float(sp.get("deck_extra", 0.0)), float(shapes[instrument][1])):
			shapes_bad.append("%s (%d panels, deck +%.2f)" % [instrument, ps.size(), float(sp.get("deck_extra", 0.0))])
	_ok(shapes_bad.is_empty(), "music: a deck a player (beatmania, GuitarFreaks, Taiko), one panel for the rest, the deeper deck where the drums are (%s)" % str(shapes_bad))
	var iidx := _spec("bmiidx")
	var iidx_generic := (iidx["players"] as Array).size() >= 1
	for k: String in _kinds(iidx):
		iidx_generic = iidx_generic and k != "music"
	_ok(iidx_generic, "music: a rhythm game with no controller of its own yet (IIDX) keeps the generic panels")
	# Which of MAME's buttons each part is (konami/ksys573.cpp, namco/namcos10.cpp): a pad is not its neighbour.
	var maps := {
		"drums": {"HiHat": 3, "Snare": 4, "HighTom": 1, "LowTom": 2, "Cymbal": 5},
		"guitar": {"Fret1": 1, "Fret2": 2, "Fret3": 3, "Pick": 6, "Wail": 7},
		"taiko": {"FaceLeft": 3, "FaceRight": 2, "RimLeft": 4, "RimRight": 1},
	}
	var map_bad: Array = []
	for instrument: String in maps:
		var layout_btn := {}
		for item: Dictionary in ArcadeInstruments.panel(instrument, 0, 0.0, false)["parts"]:
			if item.has("btn"):
				layout_btn[str(item["name"])] = int(item["btn"])
		var table: Dictionary = maps[instrument]
		if layout_btn.size() != table.size():
			map_bad.append("%s has %d buttons" % [instrument, layout_btn.size()])
		for part_name: String in table:
			if int(layout_btn.get(part_name, -1)) != int(table[part_name]):
				map_bad.append("%s/%s" % [instrument, part_name])
	var bass: Dictionary = ArcadeInstruments.panel("drums", 0, 0.0, false)["pedal"]
	_ok(map_bad.is_empty() and int(bass["btn"]) == 6, "music: DrumMania's pads, GuitarFreaks' buttons and Taiko's zones are MAME's own buttons (%s)" % str(map_bad))
	# beatmania's keys: the first, third and fifth white in the front row, the second and fourth black and behind.
	var key_rows_ok := true
	for item: Dictionary in ArcadeInstruments.panel("deck", 0, 0.0, false)["parts"]:
		var white_key: bool = int(item["btn"]) % 2 == 1
		var tint: Color = item["color"]
		key_rows_ok = key_rows_ok and (tint.v > 0.5) == white_key and ((item["pos"] as Vector2).y < 0.0) == white_key
	_ok(key_rows_ok, "music: beatmania's keys 1, 3 and 5 are white and in the front row, 2 and 4 black and behind them")
	# A second GuitarFreaks guitar is the first seen in a mirror (neck on the outside); a part in a mirror turns round, a sector's angles with it.
	var guitars := ArcadeInstruments.panels("guitar", 2)
	var neck_x := func(panel: Dictionary, part_name: String) -> float:
		for item: Dictionary in panel["parts"]:
			if str(item["name"]) == part_name:
				return float((item["pos"] as Vector2).x)
		return INF
	_ok(float(neck_x.call(guitars[0], "GuitarNeck")) < float(neck_x.call(guitars[0], "GuitarBodyLower"))
			and float(neck_x.call(guitars[1], "GuitarNeck")) > float(neck_x.call(guitars[1], "GuitarBodyLower")),
		"music: GuitarFreaks' second guitar is the first in a mirror, its neck on the outside")
	var mirrored_drum := {}
	for item: Dictionary in ArcadeInstruments.panel("taiko", 0, 0.0, true)["parts"]:
		mirrored_drum[str(item["name"])] = item
	_ok(is_equal_approx(float(mirrored_drum["FaceLeft"]["a0"]), -88.0) and is_equal_approx(float(mirrored_drum["FaceLeft"]["a1"]), 88.0)
			and is_equal_approx(float(mirrored_drum["FaceRight"]["a0"]), 92.0) and is_equal_approx(float(mirrored_drum["FaceRight"]["a1"]), 268.0),
		"music: a part seen in a mirror turns round: a sector's angles become 180 minus the old ones, the ends swapped")
	# The panels stand side by side, not through each other (a mirrored beatmania pair keep their STARTs together in the middle, a few millimetres of flange between), and a game has no more
	# of them than its instrument has.
	var overlap: Array = []
	for instrument: String in ArcadeInstruments.IDS:
		var pair := ArcadeInstruments.panels(instrument, 2)
		if pair.size() == 2 and float(pair[1]["x0"]) < float(pair[0]["x1"]) - 0.005:
			overlap.append(instrument)
	_ok(overlap.is_empty() and ArcadeInstruments.panels("popn", 5).size() == 1 and ArcadeInstruments.panels("taiko", 9).size() == 2 and ArcadeInstruments.panels("deck", 0).size() == 1
			and ArcadeInstruments.panels("guitar", 2).size() == 2,
		"music: two players' panels stand side by side (%s overlap), a game has as many as its instrument has and at least one" % str(overlap))
	# Every part, START and the turntable stand inside their panel's reach, and the body is as wide as the panels need.
	var fit_bad: Array = []
	var narrow: Array = []
	for instrument: String in ArcadeInstruments.IDS:
		var group := ArcadeInstruments.panels(instrument, ArcadeInstruments.max_players(instrument))
		var left_most := 0.0
		var right_most := 0.0
		for fp: Dictionary in group:
			left_most = minf(left_most, float(fp["x0"]))
			right_most = maxf(right_most, float(fp["x1"]))
			var stands: Array = []
			for item: Dictionary in fp["parts"]:
				var half := Vector2.ZERO
				var round_part := true
				match str(item["shape"]):
					"box":
						half = (item["size"] as Vector2) * 0.5
						round_part = false
					"dome", "disc":
						half = Vector2.ONE * float(item["radius"])
					"sector":
						half = Vector2.ONE * float(item["r1"])
				stands.append([str(item["name"]), item["pos"], half, round_part])
			# START is a cap of 11 mm with a flange of 13.4: part of the reach too. A turntable or a knob stands on its plinth.
			stands.append(["START", Vector2(float(fp["start_x"]), float(fp["start_y"])), Vector2.ONE * 0.0134, true])
			if fp.has("dial"):
				stands.append(["dial", fp["dial"]["pos"], Vector2.ONE * float(fp["dial"]["plinth"]), true])
			for entry: Array in stands:
				var at: Vector2 = entry[1]
				var reach_by: Vector2 = entry[2]
				if at.x - reach_by.x < float(fp["x0"]) - 0.0001 or at.x + reach_by.x > float(fp["x1"]) + 0.0001 \
						or at.y - reach_by.y < float(fp["y0"]) - 0.0001 or at.y + reach_by.y > float(fp["y1"]) + 0.0001:
					fit_bad.append("%s/%s" % [instrument, entry[0]])
				# START is clear of everything else on the panel, the turntable too (a drum's shell is 5 cm tall: a START on it would be buried).
				if entry[0] != "START":
					var start_at := Vector2(float(fp["start_x"]), float(fp["start_y"]))
					var gap := 0.0
					if bool(entry[3]):
						gap = maxf((start_at - at).length() - reach_by.x, 0.0)
					else:
						gap = Vector2(maxf(absf(start_at.x - at.x) - reach_by.x, 0.0), maxf(absf(start_at.y - at.y) - reach_by.y, 0.0)).length()
					if gap < 0.0134 - 0.0005:
						fit_bad.append("%s/START on %s" % [instrument, entry[0]])
		var body_wide := float(_spec(str(want[instrument][0]))["width"])
		if body_wide < 2.0 * maxf(-left_most, right_most) - 0.001:
			narrow.append("%s %.2f" % [instrument, body_wide])
	_ok(fit_bad.is_empty() and narrow.is_empty(), "music: every part stands inside its panel's reach, START and the turntable too, and the body is as wide as they need (%s, too narrow: %s)" % [str(fit_bad), str(narrow)])
	# The face of a drum, as a mesh: seen from above, its walls leaning out, whichever way round its angles are given.
	var mesh_bad: Array = []
	for arc: Array in [[0.05, 0.12, 20.0, 160.0], [0.0, 0.12, -88.0, 88.0], [0.128, 0.172, 92.0, 268.0], [0.05, 0.12, 160.0, 20.0]]:
		var arrays := ArcadeInstruments.sector_mesh(float(arc[0]), float(arc[1]), float(arc[2]), float(arc[3]), 0.01).surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		if verts.is_empty() or verts.size() % 3 != 0:
			mesh_bad.append("%s is empty" % str(arc))
			continue
		var mid_angle := deg_to_rad((float(arc[2]) + float(arc[3])) * 0.5)
		var wound := true
		var walls_ok := true
		for t in range(0, verts.size(), 3):
			# Godot's front face is the clockwise one: a visible triangle's right-handed cross product points AWAY from its normal.
			wound = wound and (verts[t + 1] - verts[t]).cross(verts[t + 2] - verts[t]).dot(norms[t]) < 0.0
			var centre := (verts[t] + verts[t + 1] + verts[t + 2]) / 3.0
			if absf(norms[t].y) > 0.5:
				# The top: its normal up, and it is the face that lies above the middle.
				walls_ok = walls_ok and norms[t].y > 0.0 and centre.y > 0.0
				continue
			var from_axis := Vector2(centre.x, -centre.z)
			var leans := Vector2(norms[t].x, -norms[t].z)
			var distance := from_axis.length()
			if distance > float(arc[1]) - 0.002:
				walls_ok = walls_ok and leans.dot(from_axis) > 0.0
			elif float(arc[0]) > 0.0 and distance < float(arc[0]) + 0.002:
				walls_ok = walls_ok and leans.dot(from_axis) < 0.0
			else:
				# A straight end: its normal points away from the sector's middle.
				var toward_mid := Vector2(-from_axis.y, from_axis.x).normalized() * (1.0 if wrapf(from_axis.angle() - mid_angle, -PI, PI) < 0.0 else -1.0)
				walls_ok = walls_ok and leans.dot(toward_mid) < 0.0
		if not wound or not walls_ok:
			mesh_bad.append("%s (wound %s, walls %s)" % [str(arc), str(wound), str(walls_ok)])
	_ok(mesh_bad.is_empty(), "music: a sector of a drum is drawn facing out, its top and its walls, whichever way round its angles are given (%s)" % str(mesh_bad))
	# The panels' own numbers: beatmania's second deck is the first seen in a mirror, its keys numbered from the left.
	var deck := S.for_game(S.variant("generic"), P.for_romset("bm2ndmix"))
	var d1: Dictionary = deck["players"][0]
	var d2: Dictionary = deck["players"][1]
	var key_x := func(panel: Dictionary, button: int) -> float:
		for part: Dictionary in panel["parts"]:
			if int(part.get("btn", 0)) == button:
				return float((part["pos"] as Vector2).x)
		return INF
	var ordered := true
	for k in range(1, 5):
		ordered = ordered and float(key_x.call(d1, k)) < float(key_x.call(d1, k + 1)) and float(key_x.call(d2, k)) < float(key_x.call(d2, k + 1))
	_ok(ordered and float((d1["dial"]["pos"] as Vector2).x) < float(key_x.call(d1, 1)) and float((d2["dial"]["pos"] as Vector2).x) > float(key_x.call(d2, 5)),
		"music: both decks have keys 1 to 5 from the left, the first player's turntable on the left of them and the second's on the right")
	_ok(absf(float(d2["start_x"]) - float(d1["start_x"])) < 0.05 and float(d1["start_x"]) < 0.0 and float(d2["start_x"]) > 0.0,
		"music: and the two STARTs stand together in the middle")
	# The cabinet built: the parts by the names the control module finds.
	var sys := await _machine()
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	var names := {
		"bm2ndmix": ["Btn1", "Btn2", "Btn3", "Btn4", "Btn5", "DialPivot", "TurntableBase"],
		"popn1": ["Btn1", "Btn2", "Btn3", "Btn4", "Btn5", "Btn6", "Btn7", "Btn8", "Btn9"],
		"gtrfrks": ["Btn1", "Btn2", "Btn3", "Btn6", "Btn7", "DialPivot", "GuitarNeck", "GuitarBodyLower"],
		"drmn": ["Btn1", "Btn2", "Btn3", "Btn4", "Btn5", "Btn6", "BassPedalPlate"],
		"taiko6": ["Btn1", "Btn2", "Btn3", "Btn4", "DrumShell"],
		"mamboagg": ["Btn1", "Btn2", "Btn3", "Btn4", "Btn5", "Btn6", "Btn7", "Btn8", "Btn9", "Drum1", "Drum3"],
	}
	for romset: String in names:
		model.morph_to(_spec(romset))
		model.apply_game_profile(P.for_romset(romset))
		await _wait(4)
		var missing: Array = []
		for panel: ArcadeControlModule in _panels(model):
			for n: String in names[romset]:
				if panel.find_child(n, true, false) == null:
					missing.append("%s/%s" % [panel.name, n])
		var players := _panels(model).size()
		# A deck a player has its parts on each panel; a game of one panel's, once.
		_ok(missing.is_empty() and players == (2 if romset in ["bm2ndmix", "gtrfrks", "taiko6"] else 1),
			"music: %s is built with its parts (%d panels, missing %s)" % [romset, players, str(missing)])
		# Each cap the instrument has is shown: none is left out for the table's count of buttons.
		var hidden := 0
		for panel: ArcadeControlModule in _panels(model):
			for i in ArcadeProfiles.BUTTON_COUNT:
				var cap := panel.find_child("Btn%d" % (i + 1), true, false) as Node3D
				if cap != null and not cap.visible:
					hidden += 1
		_ok(hidden == 0, "music: %s shows every cap it has (%d hidden)" % [romset, hidden])
		# The panel is ONE pointable thing: its grip covers every part that stands on the deck, START and the turntable too (the bass drum's pedal is on the floor and has no place in it).
		var outside: Array = []
		var tilted: Array = []
		var spec_players: Array = _spec(romset)["players"]
		var starts_ok := true
		for pi in _panels(model).size():
			var panel := _panels(model)[pi] as ArcadeControlModule
			var grip := panel.find_child("PanelGrip", true, false) as Node3D
			var box := ((grip.find_child("CollisionShape3D", true, false) as CollisionShape3D).shape as BoxShape3D).size
			for child in panel.get_children():
				var stands := child as Node3D
				if stands == null or not (stands.name == &"Start" or stands.name == &"DialPivot" or str(stands.name).begins_with("Btn")) or stands.position.length() > 0.6:
					continue
				if absf(stands.position.x - grip.position.x) > box.x * 0.5 or absf(stands.position.y - grip.position.y) > box.y * 0.5:
					outside.append("%s/%s" % [panel.name, stands.name])
				# Every flat part lies with its local Y out of the deck, as a cap does: a finger's zone and the press are the same for all of them.
				if stands is MeshInstance3D and not (stands.basis * Vector3.UP).is_equal_approx(Vector3.BACK):
					tilted.append("%s/%s" % [panel.name, stands.name])
			# START stands where the layout puts it, not at the generic panel's -0.07.
			var start_cap := panel.find_child("Start", true, false) as Node3D
			starts_ok = starts_ok and start_cap != null and absf(start_cap.position.x - float(spec_players[pi]["start_x"])) < 0.001 \
					and absf(start_cap.position.y - float((spec_players[pi] as Dictionary).get("start_y", -0.07))) < 0.001
		_ok(outside.is_empty(), "music: %s's grip covers all of its panel (%s outside it)" % [romset, str(outside)])
		_ok(tilted.is_empty(), "music: %s's keys, domes and zones lie flat on the deck (%s tilted)" % [romset, str(tilted)])
		_ok(starts_ok, "music: %s's START stands where its layout puts it" % romset)
	# pop'n music: nine domes from the left, the first and the last white, the middle red, two rows.
	model.morph_to(_spec("popn1"))
	await _wait(3)
	var popn := _panels(model)[0] as ArcadeControlModule
	var xs: Array = []
	var ys: Array = []
	for i in 9:
		var cap := popn.find_child("Btn%d" % (i + 1), true, false) as Node3D
		xs.append(model.to_local(cap.global_position).x)
		ys.append(model.to_local(cap.global_position).y)
	var increasing := true
	for i in 8:
		increasing = increasing and float(xs[i]) < float(xs[i + 1])
	var rows := {}
	for i in 9:
		rows[snappedf(float(ys[i]), 0.002)] = true
	_ok(increasing and rows.size() == 2, "music: pop'n music's nine domes run left to right in two rows (%d heights)" % rows.size())
	var tints: Array = []
	for i in 9:
		tints.append(_hue_name(((popn.find_child("Btn%d" % (i + 1), true, false) as MeshInstance3D).get_active_material(0) as StandardMaterial3D).albedo_color))
	_ok(tints == ["white", "yellow", "green", "blue", "red", "blue", "green", "yellow", "white"],
		"music: and they are white, yellow, green, blue, red, blue, green, yellow, white (%s)" % str(tints))
	# Taiko: a drum is two face halves and two rim halves, MAME's Fuchi and Men.
	model.morph_to(_spec("taiko6"))
	await _wait(3)
	var taiko := _panels(model)[0] as ArcadeControlModule
	var sec_of := func(n: String) -> Dictionary:
		return (taiko.find_child(n, true, false) as Node3D).get_meta(&"sector", {}) as Dictionary
	var left_face: Dictionary = sec_of.call("Btn3")
	var left_rim: Dictionary = sec_of.call("Btn4")
	var right_face: Dictionary = sec_of.call("Btn2")
	var right_rim: Dictionary = sec_of.call("Btn1")
	_ok(left_face.size() == 4 and left_rim.size() == 4 and right_face.size() == 4 and right_rim.size() == 4
			and float(left_face["a0"]) > PI * 0.4 and float(left_rim["a0"]) > PI * 0.4 and float(right_face["a1"]) < PI * 0.6 and float(right_rim["a1"]) < PI * 0.6
			and float(left_rim["r0"]) > float(left_face["r1"]),
		"music: a Taiko drum's four zones are sectors: the left face and the left rim face the left, the right ones the right, the rim outside the face")
	# A finger: a point in each zone reads as pressed in that zone and no other of the drum (the sectors share one square).
	var zones := {
		"Btn3": [Vector2(-0.06, 0.0), 0.122], "Btn2": [Vector2(0.06, 0.0), 0.122],
		"Btn4": [Vector2(-0.150, 0.0), 0.172], "Btn1": [Vector2(0.150, 0.0), 0.172],
	}
	var reads_ok := true
	var reads := ""
	for n: String in zones:
		var cap := taiko.find_child(n, true, false) as MeshInstance3D
		for m: String in zones:
			var other := taiko.find_child(m, true, false) as MeshInstance3D
			var tip := Vector2(zones[n][0])
			var local := Vector3(tip.x, 0.0, -tip.y)
			var sec: Dictionary = other.get_meta(&"sector", {})
			var reading := ArcadePanelHands.sector_reading(local, other.mesh.get_aabb(), sec)
			var inside := reading <= 1.0
			reads += "%s/%s=%.2f " % [n, m, reading]
			if inside != (n == m):
				reads_ok = false
	_ok(reads_ok, "music: a fingertip in one of Taiko's zones is in that zone and not in the other three (%s)" % reads)
	# The same through the hands themselves: each zone's Poke carries its sector, so a tip in the left face does not press the left rim.
	var taiko_hands := ArcadePanelHands.new(taiko)
	var taiko_pokes := {}
	for poke: ArcadePanelHands.Poke in taiko_hands.pokes():
		taiko_pokes[poke.bit] = poke
	var poke_ok := taiko_pokes.size() >= 4
	var poke_reads := ""
	for n: String in zones:
		var own_poke := taiko_pokes.get(ArcadeProfiles.button_bit(int(n.trim_prefix("Btn")))) as ArcadePanelHands.Poke
		if own_poke == null:
			poke_ok = false
			continue
		var tip_at := Vector2(zones[n][0])
		var tip_world := own_poke.frame() * Vector3(tip_at.x, 0.0, -tip_at.y)
		for m: String in zones:
			var other_poke := taiko_pokes.get(ArcadeProfiles.button_bit(int(m.trim_prefix("Btn")))) as ArcadePanelHands.Poke
			if other_poke == null:
				continue
			var near := other_poke.reading(tip_world, 1.0)
			poke_reads += "%s/%s=%.2f " % [n, m, near]
			if (near <= 1.0) != (n == m):
				poke_ok = false
	_ok(poke_ok, "music: and a fingertip's reading through the hands' own pokes says the same (%s)" % poke_reads)
	# A zone is a thin slab: a tip a hand above it, or a hand through the drum, does not press it.
	var face_poke: ArcadePanelHands.Poke = taiko_pokes.get(ArcadeProfiles.button_bit(3)) as ArcadePanelHands.Poke
	var face_at := Vector3(-0.06, 0.0, 0.0)
	var face_sector: Dictionary = (taiko.find_child("Btn3", true, false) as Node3D).get_meta(&"sector", {})
	var face_box := (taiko.find_child("Btn3", true, false) as MeshInstance3D).mesh.get_aabb()
	_ok(face_poke != null and ArcadePanelHands.sector_reading(face_at, face_box, face_sector) <= 1.0
			and ArcadePanelHands.sector_reading(face_at + Vector3(0.0, 0.004, 0.0), face_box, face_sector) <= 1.0
			and ArcadePanelHands.sector_reading(face_at + Vector3(0.0, 0.10, 0.0), face_box, face_sector) > 1.0
			and ArcadePanelHands.sector_reading(face_at + Vector3(0.0, -0.10, 0.0), face_box, face_sector) > 1.0,
		"music: a fingertip on a Taiko zone presses it, one a hand above it or a hand through the drum does not")
	# A zone of the drum stands ON its shell, not in it.
	var shell := taiko.find_child("DrumShell", true, false) as MeshInstance3D
	var shell_top := shell.position.z + (shell.mesh as CylinderMesh).height * 0.5
	var on_shell := true
	for n in ["Btn1", "Btn2", "Btn3", "Btn4"]:
		var zone_node := taiko.find_child(n, true, false) as MeshInstance3D
		on_shell = on_shell and absf(zone_node.position.z - zone_node.mesh.get_aabb().size.y * 0.5 - shell_top) < 0.001
	_ok(on_shell, "music: Taiko's four zones stand on the drum's shell (its top at %.3f m)" % shell_top)
	# A guitar's frets stand ON its neck, its pick and wail button on its body: a part's bottom is where what it stands on ends.
	model.morph_to(_spec("gtrfrks"))
	await _wait(3)
	var guitar_panel := _panels(model)[0] as ArcadeControlModule
	var neck := guitar_panel.find_child("GuitarNeck", true, false) as MeshInstance3D
	var body := guitar_panel.find_child("GuitarBodyLower", true, false) as MeshInstance3D
	var neck_top := neck.position.z + neck.mesh.get_aabb().size.y * 0.5
	var body_top := body.position.z + body.mesh.get_aabb().size.y * 0.5
	var stacked := true
	var stack_log := ""
	for n in [1, 2, 3, 6, 7]:
		var on_part := guitar_panel.find_child("Btn%d" % n, true, false) as MeshInstance3D
		var underside := on_part.position.z - on_part.mesh.get_aabb().size.y * 0.5
		var floor_z := neck_top if n <= 3 else body_top
		stack_log += "Btn%d %.4f/%.4f " % [n, underside, floor_z]
		stacked = stacked and absf(underside - floor_z) < 0.001
	_ok(stacked, "music: GuitarFreaks' frets stand on the neck and its pick and wail button on the body (%s)" % stack_log)
	# Each player's guitar is the colour of their own panel.
	var guitar_two := _panels(model)[1] as ArcadeControlModule
	var colour_of := func(panel: ArcadeControlModule) -> Color:
		return ((panel.find_child("GuitarBodyLower", true, false) as MeshInstance3D).get_active_material(0) as StandardMaterial3D).albedo_color
	_ok(not (colour_of.call(guitar_panel) as Color).is_equal_approx(colour_of.call(guitar_two) as Color), "music: and the two players' guitars are not the same colour")
	var knob_base := guitar_panel.find_child("DialBase", true, false) as MeshInstance3D
	_ok(knob_base != null and absf(knob_base.position.z - knob_base.mesh.get_aabb().size.y * 0.5 - body_top) < 0.001,
		"music: and its effect knob on the body too (its underside at %.4f, the body's top at %.4f)" % [knob_base.position.z - knob_base.mesh.get_aabb().size.y * 0.5 if knob_base != null else -1.0, body_top])
	# Mambo a Go-Go: nine pads, MAME's numbering: the drums left, centre, right are columns 1, 2, 3; pad 1 on top, pad 2 bottom left, pad 3 bottom right.
	model.morph_to(_spec("mamboagg"))
	await _wait(3)
	var conga := _panels(model)[0] as ArcadeControlModule
	var pos := {}
	for i in 9:
		# The three pads of a drum share the drum's middle for an origin: where each is, is where its mesh is.
		var cap := conga.find_child("Btn%d" % (i + 1), true, false) as MeshInstance3D
		pos[i + 1] = model.to_local(cap.global_transform * cap.mesh.get_aabb().get_center())
	var cols_ok := true
	for row in 3:
		cols_ok = cols_ok and (pos[row * 3 + 1] as Vector3).x < (pos[row * 3 + 2] as Vector3).x and (pos[row * 3 + 2] as Vector3).x < (pos[row * 3 + 3] as Vector3).x
	for col in 3:
		var top: Vector3 = pos[col + 1]
		var bl: Vector3 = pos[col + 4]
		var br: Vector3 = pos[col + 7]
		# Pad 1 is on the monitor's side of pads 2 and 3 (further from the player), pad 2 left of pad 3, the three in one drum.
		cols_ok = cols_ok and top.z < bl.z - 0.02 and top.z < br.z - 0.02 and bl.x < br.x and absf(top.x - (bl.x + br.x) * 0.5) < 0.03
	_ok(cols_ok, "music: Mambo a Go-Go's buttons 1 to 9 are three drums of three pads, the left drum's pads 1, 4 and 7")
	# The input: a button's bit sinks its own part and no other; the four buttons past six are the pad's L2, R2, L3 and R3.
	model.morph_to(_spec("popn1"))
	await _wait(3)
	var pp := _panels(model)[0] as ArcadeControlModule
	var rest := {}
	for i in 9:
		rest[i] = (pp.find_child("Btn%d" % (i + 1), true, false) as Node3D).position
	var all_ok := true
	for i in 9:
		pp.show_state(1 << ArcadeProfiles.BUTTON_BITS[i])
		for j in 9:
			var moved := not ((pp.find_child("Btn%d" % (j + 1), true, false) as Node3D).position).is_equal_approx(rest[j])
			all_ok = all_ok and moved == (i == j)
	pp.show_state(0)
	_ok(all_ok, "music: each of pop'n music's nine buttons sinks its own dome and no other (the last three on the pad's L2, R2 and L3)")
	# The turntable turns with LEFT and RIGHT, as every dial does; a hand takes it anywhere on the platter.
	model.morph_to(_spec("bm2ndmix"))
	await _wait(3)
	var dj := _panels(model)[0] as ArcadeControlModule
	var platter := dj.find_child("DialPivot", true, false) as Node3D
	var before := platter.basis
	dj.show_state(1 << ControllerBindings.JOYPAD_RIGHT)
	for i in 20:
		dj.tick(1.0 / 60.0)
	_ok(not platter.basis.is_equal_approx(before) and float(platter.get_meta(&"reach", 0.0)) >= 0.08,
		"music: beatmania's turntable turns with RIGHT and is taken anywhere on its platter (reach %.3f m)" % float(platter.get_meta(&"reach", 0.0)))
	dj.show_state(0)
	# A hand takes it seven centimetres from its spindle (a knob is taken within 4.5 cm).
	var dj_hands := ArcadePanelHands.new(dj)
	var dial_grab: ArcadePanelHands.ControlGrab = null
	for g: ArcadePanelHands.ControlGrab in dj_hands.grabs():
		if g.kind == &"dial":
			dial_grab = g
	var rim_tip: Vector3 = platter.global_transform * Vector3(0.07, 0.0, 0.012)
	_ok(dial_grab != null and dial_grab.reach() >= 0.08 and dial_grab.can_grab(rim_tip, 1.0),
		"music: and a hand can take the turntable at its platter's edge (reach %.3f m)" % (dial_grab.reach() if dial_grab != null else -1.0))
	# The bass drum's pedal goes DOWN, on the floor, and a hand (or a pad's R) presses it.
	model.morph_to(_spec("drmn"))
	await _wait(3)
	var kit := _panels(model)[0] as ArcadeControlModule
	var pedal := kit.find_child("Btn6", true, false) as Node3D
	var pedal_rest := model.to_local(pedal.global_position)
	_ok(pedal_rest.y < 0.08 and pedal_rest.z > 0.6, "music: the bass drum's pedal is on the floor in front of the cabinet (%s)" % str(pedal_rest))
	kit.show_state(1 << ArcadeProfiles.button_bit(6))
	var pedal_moved := model.to_local(pedal.global_position) - pedal_rest
	_ok(pedal_moved.y < -0.008 and absf(pedal_moved.x) < 0.001 and absf(pedal_moved.z) < 0.001, "music: and it goes straight down under a press (%s)" % str(pedal_moved))
	kit.show_state(0)
	var hands := ArcadePanelHands.new(kit)
	var bits: Array = []
	for poke: ArcadePanelHands.Poke in hands.pokes():
		bits.append(poke.bit)
	var every := true
	for b in range(1, 7):
		every = every and bits.has(ArcadeProfiles.button_bit(b))
	_ok(every, "music: a fingertip can press each of DrumMania's six (%d zones)" % bits.size())


## A controller that is not a ball on a stick (the table's `y`): Atari's flight yoke (Star Wars, The Empire Strikes Back, Red Baron) and Sega's fishing rod with its reel (Bass Fishing). The part a hand
## takes is `StickBall` either way and the panel still leans, so the input and the hands need nothing of their own; the rod's reel has a crank that turns (`DialPivot`).
func _group_styles() -> void:
	var yokes := ["starwars", "starwars1", "esb", "redbaron", "redbarona"]
	var rods := ["bassdx", "getbass", "getbassdx", "getbassur"]
	var bad: Array = []
	for romset: String in yokes:
		if P.for_romset(romset).control_style() != "yoke" or S.panel_kind(P.for_romset(romset)) != "yoke":
			bad.append(romset)
	for romset: String in rods:
		if P.for_romset(romset).control_style() != "rod" or S.panel_kind(P.for_romset(romset)) != "rod":
			bad.append(romset)
	for romset: String in ["bzone", "sf2", "outrun", "asteroid", "tempest", "not_a_real_romset"]:
		if P.for_romset(romset).control_style() != "":
			bad.append("%s has a style" % romset)
	_ok(bad.is_empty(), "styles: the Atari yoke games and every Bass Fishing set have their own controller, no other game does (%s)" % str(bad))
	# They are uprights (the fishing game's paddle and pedal would have made it a driving cabinet), one panel, a yoke's wider than a stick's.
	var forms_ok := true
	for romset: String in yokes + rods:
		forms_ok = forms_ok and P.for_romset(romset).form() == P.FORM_UPRIGHT and not _spec(romset).has("cockpit") and _kinds(_spec(romset)).size() == 1
	_ok(forms_ok, "styles: and they are uprights with one panel, not driving cabinets")
	var yoke := S.panel("yoke", 4, 0.0, 0)
	var stick := S.panel("stick", 4, 0.0, 0)
	_ok(S.panel_width("yoke", 4) > S.panel_width("stick", 4) + 0.08 and S.panel_extent(yoke).y - S.panel_extent(yoke).x >= S.panel_width("yoke", 4) - 0.035
			and float(yoke["stick_x"]) - S.panel_extent(yoke).x >= S.YOKE_REACH - 0.001 and str(yoke["kind"]) == "yoke" and str(S.panel("rod", 2, 0.0, 0)["kind"]) == "rod"
			and float((yoke["buttons"] as Array)[0]["pos"].x) - float(yoke["stick_x"]) >= S.YOKE_FIRST_COLUMN - 0.001 and not stick.has("YokeX"),
		"styles: a yoke's panel is wider than a stick's, its handgrips inside it and the caps clear of them")
	var sys := await _machine()
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	model.morph_to(_spec("starwars"))
	model.apply_game_profile(P.for_romset("starwars"))
	await _wait(4)
	var panel := _panels(model)[0] as ArcadeControlModule
	var pivot := panel.find_child("StickPivot", true, false) as Node3D
	_ok(pivot != null, "styles: Star Wars has a stick pivot")
	if pivot == null:
		return
	var hub := pivot.find_child("StickBall", false, false) as MeshInstance3D
	var grip_l := pivot.find_child("YokeGripL", false, false) as Node3D
	var grip_r := pivot.find_child("YokeGripR", false, false) as Node3D
	_ok(hub != null and hub.mesh is BoxMesh and grip_l != null and grip_r != null and pivot.find_child("YokeBar", false, false) != null
			and pivot.find_child("YokeTriggerL", false, false) != null and pivot.find_child("YokeTriggerR", false, false) != null and pivot.find_child("StickShaft", false, false) != null,
		"styles: Star Wars has a column, a hub, a bar, a handgrip each end with a trigger on its front")
	if grip_l == null or grip_r == null or hub == null:
		return
	_ok(grip_r.position.x - grip_l.position.x > 0.20 and grip_r.position.x - grip_l.position.x < 0.28 and _near(grip_l.position.x, -grip_r.position.x, 0.001)
			and grip_l.position.z > hub.position.z and (grip_l as MeshInstance3D).mesh is CylinderMesh,
		"styles: the grips stand a quarter of a metre apart either side of the hub and above it (%.3f m)" % (grip_r.position.x - grip_l.position.x))
	# The caps clear of the handgrips (seen from above, in the panel's frame).
	var clear := true
	for i in 4:
		var cap := panel.find_child("Btn%d" % (i + 1), true, false) as Node3D
		clear = clear and cap != null and cap.position.x - (pivot.position.x + grip_r.position.x) > 0.04
	_ok(clear, "styles: and the buttons stand clear of them")
	# It leans like any stick, and a hand takes it by the hub.
	var rest := pivot.basis
	panel.show_state(1 << ControllerBindings.JOYPAD_RIGHT)
	for i in 20:
		panel.tick(1.0 / 60.0)
	var leaned := not pivot.basis.is_equal_approx(rest)
	panel.show_state(0)
	var hands := ArcadePanelHands.new(panel)
	var grab: ArcadePanelHands.ControlGrab = null
	for g: ArcadePanelHands.ControlGrab in hands.grabs():
		if g.kind == &"stick":
			grab = g
	_ok(leaned and grab != null and grab.handle().distance_to(hub.global_position) < 0.005 and panel.find_child("DialPivot", true, false) == null,
		"styles: the yoke leans with the input and a hand takes it at its hub; it has no collar")
	# The rod.
	model.morph_to(_spec("bassdx"))
	model.apply_game_profile(P.for_romset("bassdx"))
	await _wait(4)
	var angler := _panels(model)[0] as ArcadeControlModule
	var rod_pivot := angler.find_child("StickPivot", true, false) as Node3D
	_ok(rod_pivot != null, "styles: Bass Fishing has a stick pivot")
	if rod_pivot == null:
		return
	var grip := rod_pivot.find_child("StickBall", false, false) as MeshInstance3D
	var blank := rod_pivot.find_child("StickShaft", false, false) as MeshInstance3D
	var mount := rod_pivot.find_child("CrankMount", false, false) as Node3D
	var crank := rod_pivot.find_child("DialPivot", true, false) as Node3D
	_ok(grip != null and grip.mesh is CylinderMesh and blank != null and mount != null and crank != null and crank.get_parent() == mount and rod_pivot.find_child("RodReel", false, false) != null
			and (blank.mesh as CylinderMesh).height >= 0.45,
		"styles: Bass Fishing has a grip, a rod of half a metre or more, a reel and a crank on a mount of its own")
	if blank == null or mount == null or crank == null or grip == null:
		return
	# The rod rises and leans toward the angler (the pivot's -Y is toward the player); the crank turns about the reel's axle, the pivot's X.
	var axis := blank.basis.y
	_ok(axis.z > 0.85 and axis.y < -0.25 and absf(axis.x) < 0.01 and mount.basis.z.is_equal_approx(Vector3.RIGHT) and crank.basis.is_equal_approx(Basis.IDENTITY),
		"styles: the rod rises toward the angler and the crank turns about the reel's axle (%s)" % str(axis))
	var rod_rest := rod_pivot.basis
	angler.show_state(1 << ControllerBindings.JOYPAD_RIGHT)
	for i in 20:
		angler.tick(1.0 / 60.0)
	_ok(not rod_pivot.basis.is_equal_approx(rod_rest) and not crank.basis.is_equal_approx(Basis.IDENTITY) and crank.basis.z.is_equal_approx(Vector3.BACK),
		"styles: RIGHT swings the rod and winds the reel, about its own axle")
	angler.show_state(0)
	var angler_hands := ArcadePanelHands.new(angler)
	var rod_grab: ArcadePanelHands.ControlGrab = null
	var crank_grab: ArcadePanelHands.ControlGrab = null
	for g: ArcadePanelHands.ControlGrab in angler_hands.grabs():
		if g.kind == &"stick":
			rod_grab = g
		elif g.kind == &"dial":
			crank_grab = g
	_ok(rod_grab != null and crank_grab != null and rod_grab.handle().distance_to(crank_grab.handle()) > 0.05 and rod_grab.handle().distance_to(crank_grab.handle()) < 0.20,
		"styles: a hand takes the rod by its grip and the crank on the reel, a few centimetres apart")
	# A plain stick keeps its ball and no collar.
	model.morph_to(_spec("sf2"))
	model.apply_game_profile(P.for_romset("sf2"))
	await _wait(3)
	var plain := _panels(model)[0] as ArcadeControlModule
	_ok(plain.find_child("YokeBar", true, false) == null and plain.find_child("RodReel", true, false) == null and plain.find_child("DialPivot", true, false) == null
			and (plain.find_child("StickBall", true, false) as MeshInstance3D).mesh is SphereMesh,
		"styles: a street fighter's stick is a ball on a stick")


## A rider STANDING on a rocking board (Top Skater's skateboard, Alpine Surfer's snowboard, Alpine Racer's skis): the table, the spec, the rig built on a real cabinet, where its parts
## stand, the lean, the sight over the rail and the pointer box. Every size is an estimate (docs/dev/arcade-cabinets.md): what is tested is that the rig is one a person can step
## up to, hold and see over, with the plate clear of its stand at full lock, not that it is the real machine's size.
func _group_rider() -> void:
	var want := {
		"skate": ["topskatr", "topskatrj", "topskatru", "topskatruo"],
		"snow": ["alpines"],
		"ski": ["alpinerd", "alpinerc", "alpinerjc", "alpinr2b", "alpinr2a", "skisuprg"],
	}
	var bad: Array = []
	for vehicle: String in want:
		for romset: String in want[vehicle]:
			var gp := P.for_romset(romset)
			if not gp.known or gp.form() != vehicle or not gp.is_board() or gp.players != 1 or gp.has_seat():
				bad.append("%s (%s, %d players)" % [romset, gp.form(), gp.players])
	_ok(bad.is_empty(), "rider: Top Skater (a skateboard), Alpine Surfer (a snowboard), both Alpine Racers and Ski Super G (skis) are a rider standing on a board, one rider a machine (%s)" % str(bad))
	var other: Array = []
	for romset: String in ["skichamp", "segawski", "surfplnt", "alpine", "hangon", "propcycl", "ddrmax", "sf2", "outrun", "not_a_real_romset"]:
		if P.for_romset(romset).is_board():
			other.append(romset)
	_ok(other.is_empty(), "rider: no other game is a board: the ski and surf games nothing is known of, a bike, a bicycle, a dance stage, an upright (%s)" % str(other))
	var spec_bad: Array = []
	for vehicle: String in want:
		var sp := _spec(str(want[vehicle][0]))
		var rig: Dictionary = sp.get("board", {})
		if str(rig.get("vehicle", "")) != vehicle or str(sp["shape"]) != "wide" or not (sp["players"] as Array).is_empty() or int(sp["guns"]) != 0 or (sp["coins"] as Array).size() != 1 \
				or sp.has("cockpit") or sp.has("bike") or sp.has("cycle") or sp.has("bench") or sp.has("stage") or sp.has("screen"):
			spec_bad.append("%s (%s)" % [vehicle, str(rig)])
	_ok(spec_bad.is_empty(), "rider: each asks for the wide body's own big screen, no panel, no seat, one coin door and the rig of its own vehicle (%s)" % str(spec_bad))
	_ok(not _spec("sf2").has("board") and not _spec("hangon").has("board") and S._same_form(_spec("topskatr"), _spec("topskatrj")) and not S._same_form(_spec("topskatr"), _spec("alpines"))
			and not S._same_form(_spec("alpines"), _spec("alpinerd")),
		"rider: an upright asks for no rig, a clone asks for what its parent does, and a skateboard, a snowboard and skis are three rigs")
	var parts := {
		"skate": ["SkateDeck", "SkateNose", "SkateTail", "SkateTruck1", "SkateTruck2", "SkateWheel1", "SkateWheel2", "SkateWheel3", "SkateWheel4"],
		"snow": ["SnowBoard", "SnowNose", "SnowTail", "SnowBinding1", "SnowBinding2", "SnowStrap1", "SnowStrap2"],
		"ski": ["Ski1", "Ski2", "SkiTip1", "SkiTip2", "SkiBinding1", "SkiBinding2"],
	}
	var common := ["Board", "BoardStand", "BoardStandTrim", "BoardAxle", "Player1", "LeanPivot", "BoardPlate", "BoardPlateTrim", "Handlebars", "BarCross", "BarGripL", "BarGripR",
			"BoardPostLF", "BoardPostLB", "BoardPostRF", "BoardPostRB", "BoardRailL", "BoardRailR", "BarClamp", "Start", "PanelGrip"]
	var sys := await _machine()
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	var to_cab := model.global_transform.affine_inverse()
	for vehicle: String in want:
		var romset := str(want[vehicle][0])
		model.morph_to(_spec(romset))
		model.apply_game_profile(P.for_romset(romset))
		await _wait(4)
		var missing: Array = []
		for n: String in common + (parts[vehicle] as Array):
			if model.find_child(n, true, false) == null:
				missing.append(n)
		var stray: Array = []
		for other_vehicle: String in parts:
			if other_vehicle != vehicle:
				for n: String in parts[other_vehicle]:
					if model.find_child(n, true, false) != null:
						stray.append(n)
		_ok(missing.is_empty() and stray.is_empty() and _panels(model).size() == 1 and _doors(model).size() == 1,
			"rider: %s has a stand, an axle, a plate, its own parts, a rail with two grips and START, one controller and one coin door, and nothing of the other vehicles (missing %s, stray %s)"
				% [romset, str(missing), str(stray)])
		if not missing.is_empty():
			continue
		var panel := _panels(model)[0] as ArcadeControlModule
		var lean := model.find_child("LeanPivot", true, false) as Node3D
		var gl := to_cab * (model.find_child("BarGripL", true, false) as Node3D).global_position
		var gr := to_cab * (model.find_child("BarGripR", true, false) as Node3D).global_position
		var cross := to_cab * (model.find_child("BarCross", true, false) as Node3D).global_position
		var start := to_cab * (model.find_child("Start", true, false) as Node3D).global_position
		# The rail is held at the hip: a standing person's waist, the same each side, symmetric about the middle, and the crossbar is in FRONT of the grips (toward the screen).
		_ok(gl.y > 0.95 and gl.y < 1.15 and _near(gl.y, gr.y, 0.001) and _near(gl.x, -gr.x, 0.001) and _near(gl.z, gr.z, 0.001) and gr.x - gl.x > 0.60 and gr.x - gl.x < 0.80,
			"rider: %s's rail is held at the waist (%.2f m up), a grip each side of the middle %.2f m apart" % [vehicle, gl.y, gr.x - gl.x])
		_ok(cross.z < gl.z - 0.25 and _near(cross.y, gl.y, 0.001) and _near(start.x, 0.0, 0.001) and _near(start.z, cross.z, 0.001) and start.y > cross.y + 0.01 and start.y < cross.y + 0.05,
			"rider: %s's crossbar is in front of the grips with START in the middle of it, on top (%.2f m in front)" % [vehicle, gl.z - cross.z])
		# The bars' own middle (what a hand's let-go distance is measured from) is the middle of the two grips, not the crossbar's: a full throw of a hand 15 cm out stays within reach of it.
		var bars_at := to_cab * (model.find_child("Handlebars", true, false) as Node3D).global_position
		_ok(_near(bars_at.x, 0.0, 0.001) and _near(bars_at.z, gl.z, 0.001) and _near(bars_at.y, gl.y, 0.001),
			"rider: %s's bars are taken from the middle of the two grips, %.2f m from either" % [vehicle, bars_at.distance_to(gl)])
		# Everything stands on the stand: no part of the rig, rail and leaning plate aside, past its edges, and the stand is clear of the bay door's swing.
		var stand := to_cab * (model.find_child("BoardStand", true, false) as MeshInstance3D).global_position
		var over: Array = []
		for mi: MeshInstance3D in _meshes(model.find_child("Board", true, false)):
			var box: AABB = to_cab * (mi.global_transform * mi.get_aabb())
			if box.position.z < ArcadeCabinetBuilder.BOARD_Z0 - 0.005 or box.end.z > ArcadeCabinetBuilder.BOARD_Z1 + 0.005 or box.position.x < -0.50 or box.end.x > 0.50:
				over.append(str(mi.name))
		_ok(over.is_empty() and _near(stand.z, (ArcadeCabinetBuilder.BOARD_Z0 + ArcadeCabinetBuilder.BOARD_Z1) * 0.5, 0.001),
			"rider: %s stands wholly on its stand, 0.84 m from the cabinet's front at the nearest (over: %s)" % [vehicle, str(over)])
		# The stand is clear of the bay door's swing (no nearer than 0.84 m to the cabinet's front) and big enough to stand in front of the screen on.
		var stand_mi := model.find_child("BoardStand", true, false) as MeshInstance3D
		var stand_box: AABB = to_cab * (stand_mi.global_transform * stand_mi.get_aabb())
		_ok(stand_box.position.z >= 0.839 and stand_box.size.z >= 1.2 and stand_box.size.x >= 0.8 and stand_box.size.x <= 0.95,
			"rider: %s's stand starts %.2f m out, clear of the bay door, and is %.2f m deep and %.2f m wide" % [vehicle, stand_box.position.z, stand_box.size.z, stand_box.size.x])
		# What the vehicle is: seen from the plate, the nose (and a snowboard's or skateboard's tail) turned up past the body, the skis a shoulder's width apart, the wheels on the plate.
		var in_lean := lean.global_transform.affine_inverse()
		var box_of := func(n: String) -> AABB:
			var mi := model.find_child(n, true, false) as MeshInstance3D
			return in_lean * (mi.global_transform * mi.get_aabb())
		var turned: Array = []
		match vehicle:
			"skate":
				turned = [["SkateDeck", "SkateNose", true], ["SkateDeck", "SkateTail", false]]
			"snow":
				turned = [["SnowBoard", "SnowNose", true], ["SnowBoard", "SnowTail", false]]
			_:
				turned = [["Ski1", "SkiTip1", true], ["Ski2", "SkiTip2", true]]
		var flat: Array = []
		for t: Array in turned:
			var body: AABB = box_of.call(str(t[0]))
			var tip: AABB = box_of.call(str(t[1]))
			var beyond := tip.position.z < body.position.z if bool(t[2]) else tip.end.z > body.end.z
			# Its far end up past its near end by its own slope (a box tipped the other way has the same extent round its middle).
			var piece := model.find_child(str(t[1]), true, false) as MeshInstance3D
			var half_z := piece.get_aabb().size.z * 0.5
			var far_end: Vector3 = in_lean * (piece.global_transform * Vector3(0.0, 0.0, -half_z if bool(t[2]) else half_z))
			var near_end: Vector3 = in_lean * (piece.global_transform * Vector3(0.0, 0.0, half_z if bool(t[2]) else -half_z))
			if not beyond or tip.end.y < body.end.y + 0.015 or far_end.y < near_end.y + 0.02:
				flat.append(str(t[1]))
		_ok(flat.is_empty(), "rider: %s's ends are turned up, the nose toward the screen (%s are not)" % [vehicle, str(flat)])
		match vehicle:
			"skate":
				var wheels_ok := true
				var deck: AABB = box_of.call("SkateDeck")
				for w in range(1, 5):
					var wb: AABB = box_of.call("SkateWheel%d" % w)
					wheels_ok = wheels_ok and wb.position.y >= 0.012 and wb.position.y <= 0.02 and wb.end.y <= deck.position.y + 0.002 and absf(wb.get_center().x) > 0.08 and absf(wb.get_center().z) > 0.2
				_ok(wheels_ok, "rider: the skateboard's four wheels stand on the plate at the corners, under the deck")
			"snow":
				var b1: AABB = box_of.call("SnowBinding1")
				var b2: AABB = box_of.call("SnowBinding2")
				var board: AABB = box_of.call("SnowBoard")
				_ok(_near(b1.get_center().z, -b2.get_center().z, 0.001) and absf(b1.get_center().z - b2.get_center().z) > 0.35 and absf(b1.get_center().z - b2.get_center().z) < 0.5
						and b1.position.y >= board.end.y - 0.005 and b2.position.y >= board.end.y - 0.005,
					"rider: the snowboard has a binding for each foot, a shoulder's width apart, on its top")
			_:
				var k1: AABB = box_of.call("Ski1")
				var k2: AABB = box_of.call("Ski2")
				_ok(absf(k1.get_center().x + k2.get_center().x) < 0.001 and absf(k1.get_center().x - k2.get_center().x) > 0.2 and absf(k1.get_center().x - k2.get_center().x) < 0.35
						and k1.size.z > 0.85 and k1.end.x <= k2.position.x and k2.size.z > 0.85,
					"rider: the two skis lie side by side, apart, each most of a metre long")
		# Leaned all the way either way: the plate's low edge clears the stand, the rail leans with it, the plate leans into the turn.
		var rest_top := to_cab * (model.find_child("Handlebars", true, false) as Node3D).global_position
		var rest_rail := to_cab * (model.find_child("BoardRailL", true, false) as Node3D).global_position
		var lows: Array = []
		var shifts: Array = []
		var rails: Array = []
		for bit: int in [ControllerBindings.JOYPAD_RIGHT, ControllerBindings.JOYPAD_LEFT]:
			panel.show_state(1 << bit)
			for i in 90:
				panel.tick(0.05)
			var plate := model.find_child("BoardPlate", true, false) as MeshInstance3D
			var low := 10.0
			var half := plate.get_aabb().size * 0.5
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					low = minf(low, (to_cab * (plate.global_transform * Vector3(sx * half.x, -half.y, sz * half.z))).y)
			lows.append(snappedf(low, 0.001))
			shifts.append(snappedf((to_cab * (model.find_child("Handlebars", true, false) as Node3D).global_position).x - rest_top.x, 0.001))
			shifts.append(snappedf(lean.global_basis.y.x, 0.001))
			rails.append(snappedf((to_cab * (model.find_child("BoardRailL", true, false) as Node3D).global_position).x - rest_rail.x, 0.001))
		panel.show_state(0)
		for i in 90:
			panel.tick(0.05)
		_ok(float(lows[0]) > ArcadeCabinetBuilder.BOARD_STAND_H + 0.004 and float(lows[1]) > ArcadeCabinetBuilder.BOARD_STAND_H + 0.004,
			"rider: %s's plate keeps clear of its stand at full lock either way (low edge %s m, the stand's top %.2f)" % [vehicle, str(lows), ArcadeCabinetBuilder.BOARD_STAND_H])
		_ok(float(shifts[0]) > 0.15 and float(shifts[2]) < -0.15 and float(shifts[1]) > 0.2 and float(shifts[3]) < -0.2,
			"rider: %s leans into a turn, the rail with it (%s, a side rail %s)" % [vehicle, str(shifts), str(rails)])
		_ok(float(rails[0]) > 0.15 and float(rails[1]) < -0.15, "rider: and the side rails go with it, the whole rail one piece with the plate")
		_ok(lean.global_basis.y.distance_to(Vector3.UP) < 0.001, "rider: and it comes upright again with the stick")
		# A standing rider sees the whole picture over the rail: from where their eyes are at the plate to the middle and the corners of the glass.
		var eye := model.to_global(Vector3(0.0, 1.75, ArcadeCabinetBuilder.BOARD_Z0 + (ArcadeCabinetBuilder.BOARD_Z1 - ArcadeCabinetBuilder.BOARD_Z0) * 0.5 + 0.05))
		var blockers := _sight_blockers(model, eye, model.get_builtin_screen(), model.find_child("Board", true, false))
		_ok(blockers.is_empty(), "rider: %s: nothing of the rig stands between a standing rider's eyes and the picture (%s)" % [vehicle, str(blockers)])
	# A pointer box over the stand and the plate, below the rail: a laser aimed at the grips and START is not hidden by it, and the rig is part of the cabinet's footprint.
	var boxes: Array = model.get_meta(ArcadeCabinetBuilder.FORM_BOXES_META, [])
	var low_boxes := boxes.size() == 1
	for box: AABB in boxes:
		low_boxes = low_boxes and box.end.y > ArcadeCabinetBuilder.BOARD_AXIS_Y and box.end.y < 0.5 and _near(box.position.z, ArcadeCabinetBuilder.BOARD_Z0, 0.001) \
				and _near(box.end.z, ArcadeCabinetBuilder.BOARD_Z1, 0.001)
	_ok(low_boxes and model.ground_footprint().y > 2.4,
		"rider: the stand and its plate can be aimed at to take hold of the cabinet, the rail cannot be hidden by them, and the floor rectangle reaches the end of the stand (%s)" % str(model.ground_footprint()))
	# No collision: a person steps up to it. Its one controller can be aimed at to take hold of.
	var solid := 0
	for body in model.find_child("Board", true, false).find_children("*", "CollisionObject3D", true, false):
		if body is StaticBody3D or body is RigidBody3D or body is CharacterBody3D:
			solid += 1
	var p1 := _panels(model)[0] as ArcadeControlModule
	_ok(solid == 0 and p1.grip() != null and (p1.grip().collision_layer & (1 << 20)) != 0,
		"rider: nothing of the rig is solid, and its rail can be aimed at to take hold of the controller")
	# Pulling the game back is the cabinet's own again.
	model.morph_to(_spec("sf2"))
	await _wait(3)
	_ok(model.find_child("Board", true, false) == null and model.find_child("LeanPivot", true, false) == null and _panels(model).size() == 2 and model.ground_footprint().y < 1.0,
		"rider: a game with no board gives the upright back, the rig gone and the footprint the cabinet's own")


## The R-360 pod (G-LOC R360, Wing War R360): Sega's sphere cockpit hung in rings that turn. The table says so with `r` where a cockpit's cabin would be; the cockpit has two hoops at the
## platform's sides on an axle through the seat and one behind it, turning with the stick, and nothing of them stands in the way of the picture.
func _group_ring() -> void:
	var rings := ["glocr360", "glocr360j", "wingwar360"]
	var plain := ["gloc", "glocu", "wingwar", "wingwaru", "aburner2", "gforce2", "thndrbld", "aircomb"]
	var bad: Array = []
	for romset: String in rings:
		var gp := P.for_romset(romset)
		if not gp.has_ring() or gp.has_cabin() or not gp.has_seat() or not gp.has_motion() or gp.form() != P.FORM_FLY:
			bad.append(romset)
	for romset: String in plain:
		if P.for_romset(romset).has_ring():
			bad.append("%s has a ring" % romset)
	_ok(bad.is_empty(), "ring: the three R-360 sets have a seat, a moving base and rings where the cabin was; no other flight cockpit has rings (%s)" % str(bad))
	var pod: Dictionary = _spec("glocr360")["cockpit"]
	var gloc: Dictionary = _spec("gloc")["cockpit"]
	_ok(bool(pod["ring"]) and not bool(pod["cabin"]) and bool(pod["motion"]) and bool(gloc["cabin"]) and not bool(gloc["ring"]),
		"ring: the spec has the rings in place of the cabin for the pod and the cabin and no rings for G-LOC's own")
	var sys := await _machine()
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	model.morph_to(_spec("glocr360"))
	model.apply_game_profile(P.for_romset("glocr360"))
	await _wait(3)
	var outer := model.find_child("RingOuter", true, false) as Node3D
	var rear := model.find_child("RingInner", true, false) as Node3D
	var seat := model.find_child("DriverSeat", true, false) as CockpitSeat
	var base := model.find_child("MotionPivot", true, false) as Node3D
	_ok(outer != null and rear != null and seat != null and base != null and base.is_ancestor_of(outer) and base.is_ancestor_of(rear)
			and model.find_child("CabinWallL", true, false) == null and model.find_child("CabinRoof", true, false) == null,
		"ring: built: an outer ring and a rear one on the moving base, no cabin walls or roof")
	if outer == null or rear == null or seat == null:
		return
	# Round the pod: an axle through the seat's own middle, a hoop each side of the platform (wider than it), one behind the seat.
	var centre := model.to_local(outer.global_position)
	var seat_at := model.to_local(seat.global_position)
	var hoop_l := outer.find_child("RingHoopL", false, false) as Node3D
	var hoop_r := outer.find_child("RingHoopR", false, false) as Node3D
	var hoop_back := rear.find_child("RingHoopRear", false, false) as Node3D
	_ok(hoop_l != null and hoop_r != null and hoop_back != null and _near(centre.x, 0.0, 0.01) and _near(centre.z, seat_at.z, 0.01) and centre.y > 0.9 and centre.y < 1.2
			and model.to_local(hoop_l.global_position).x < -model.cabinet_width * 0.5 and model.to_local(hoop_r.global_position).x > model.cabinet_width * 0.5
			and model.to_local(hoop_back.global_position).z > seat_at.z + 0.4,
		"ring: the axle runs through the seat's middle at the level of the chest, a hoop stands outside each side of the platform and one behind the seat (%s)" % str(centre))
	# Each hoop lies in the plane it should: the side hoops are in the lateral axle's normal plane (their axis is X), the rear one faces forward (its axis is Z).
	var axis_of := func(hoop: Node3D) -> Vector3:
		return (hoop.global_transform.basis * Vector3.UP).normalized()
	var ax_l: Vector3 = axis_of.call(hoop_l)
	var ax_b: Vector3 = axis_of.call(hoop_back)
	_ok(absf(ax_l.dot(model.global_transform.basis.x.normalized())) > 0.99 and absf(ax_b.dot(model.global_transform.basis.z.normalized())) > 0.99,
		"ring: the side hoops stand in planes across the axle and the rear one faces the screen")
	# The axle is there each side, and four brackets stand on each hoop, a quarter of the way round from one another, so that a turn shows.
	var brackets_ok := outer.find_child("RingAxleL", false, false) != null and outer.find_child("RingAxleR", false, false) != null
	for entry: Array in [["RingBracketL*", outer, 1.0, Vector3.AXIS_X], ["RingBracketR*", outer, 1.0, Vector3.AXIS_X], ["RingBracketRear*", rear, 0.8, Vector3.AXIS_Z]]:
		var holder: Node3D = entry[1]
		var found := holder.find_children(str(entry[0]), "MeshInstance3D", false, false)
		var round_ok := found.size() == 4
		var angles := {}
		for b: Node in found:
			var at: Vector3 = (b as Node3D).position
			# In the hoop's own plane: the two axes that are not its axle's.
			var flat := Vector2(at.y, at.z) if int(entry[3]) == Vector3.AXIS_X else Vector2(at.x, at.y)
			round_ok = round_ok and _near(flat.length(), float(entry[2]), 0.01)
			angles[snappedf(rad_to_deg(flat.angle()), 5.0)] = true
		brackets_ok = brackets_ok and round_ok and angles.size() == 4
	_ok(brackets_ok, "ring: an axle each side and four brackets a quarter apart on each hoop, on its circle")
	# Open frames: no collision under them.
	var solid := 0
	solid += outer.find_children("*", "CollisionShape3D", true, false).size() + rear.find_children("*", "CollisionShape3D", true, false).size()
	_ok(solid == 0, "ring: no collision or pointer box on them: a player walks through (%d shapes)" % solid)
	# The input: a pull turns the outer ring over the top and leaves the rear one, a push to the side turns the rear one about the view's axis, and a level stick puts both back; the
	# seat's eyes stay put (the base tips a few degrees: the rings turn through a hundred).
	var panel := model.find_child("Player1", true, false) as ArcadeControlModule
	panel.motion_override = 1
	var eye_rest := seat.eye_transform().basis
	panel.show_state(1 << ControllerBindings.JOYPAD_DOWN)
	panel.tick(1.0 / 60.0)
	var first_tick := absf(outer.basis.y.z)
	for i in 119:
		panel.tick(1.0 / 60.0)
	var pitched := outer.basis
	_ok(pitched.x.is_equal_approx(Vector3.RIGHT) and absf(pitched.y.z) > 0.9 and rear.basis.is_equal_approx(Basis.IDENTITY),
		"ring: a pull turns the outer ring about the axle over the top and leaves the rear one (%s)" % str(pitched.y))
	_ok(first_tick > 0.0 and first_tick < 0.3, "ring: eased, with the base: a sixtieth of a second in it has turned a few degrees (%.2f), not all the way" % first_tick)
	var eye_turned := rad_to_deg(acos(clampf(seat.eye_transform().basis.z.dot(eye_rest.z), -1.0, 1.0)))
	_ok(eye_turned < 6.0, "ring: while the seat's eyes turn only with the base's few degrees (%.1f)" % eye_turned)
	panel.show_state(1 << ControllerBindings.JOYPAD_RIGHT)
	for i in 120:
		panel.tick(1.0 / 60.0)
	var rolled := rear.basis
	_ok(rolled.z.is_equal_approx(Vector3.BACK) and absf(rolled.x.y) > 0.8 and outer.basis.is_equal_approx(Basis.IDENTITY),
		"ring: a push to the side turns the rear ring about the view's axis and brings the outer one back (%s)" % str(rolled.x))
	panel.show_state(0)
	for i in 120:
		panel.tick(1.0 / 60.0)
	_ok(outer.basis.is_equal_approx(Basis.IDENTITY) and rear.basis.is_equal_approx(Basis.IDENTITY), "ring: and a level stick puts both back")
	# Motion off (a headset's default): the rings stay where they are.
	panel.motion_override = 0
	panel.show_state(1 << ControllerBindings.JOYPAD_DOWN)
	for i in 120:
		panel.tick(1.0 / 60.0)
	_ok(outer.basis.is_equal_approx(Basis.IDENTITY), "ring: with Cabinet Motion off they stay level")
	panel.show_state(0)
	# G-LOC's own cockpit has none of it.
	model.morph_to(_spec("gloc"))
	await _wait(3)
	_ok(model.find_child("RingOuter", true, false) == null and model.find_child("CabinWallL", true, false) != null,
		"ring: G-LOC's own cockpit keeps its cabin and has no ring")


## A rotary joystick (Ikari Warriors, Victory Road, Heavy Barrel, Top Gunner's bootleg, Tron...): MAME says a stick AND a dial. The panel has both: the stick leans and a collar on its
## shaft turns (`DialPivot` on the `StickPivot`).
func _group_rotary() -> void:
	var want := {
		"rotary": ["topgunbl", "ikari", "victroad", "hbarrel", "tron", "bermudat", "gondo", "ghox", "ikari3", "720"],
		"dial": ["arkanoid", "tempest", "kick", "wrally", "gtmr"],
		"stick": ["sf2", "pacman"],
		"wheel": ["badlands", "changela"],
		"ball": ["dotron", "centiped"],
	}
	var bad: Array = []
	for kind: String in want:
		for romset: String in want[kind]:
			var got := S.panel_kind(P.for_romset(romset))
			if got != kind:
				bad.append("%s is %s, not %s" % [romset, got, kind])
	_ok(bad.is_empty(), "rotary: a dial with a stick is a rotary joystick; a dial alone, a dial with a paddle (a driving game's wheel), a trackball and a pedal keep theirs (%s)" % str(bad))
	# The panel: a stick's, laid out and as wide as a stick's, with its kind kept.
	var two := _spec("topgunbl")
	var p0: Dictionary = two["players"][0]
	var plain := S.panel("stick", int(P.for_romset("topgunbl").buttons), float(p0["start_x"]) - 0.0, 0)
	_ok(_kinds(two) == ["rotary", "rotary"] and p0.has("stick_x") and not p0.has("dial_x"),
		"rotary: Top Gunner's bootleg is two rotary panels with a stick and no separate dial")
	var rot := S.panel("rotary", 2, 0.0, 0)
	var stk := S.panel("stick", 2, 0.0, 0)
	_ok(str(rot["kind"]) == "rotary" and _near(float(rot["stick_x"]), float(stk["stick_x"])) and _near(float(rot["start_x"]), float(stk["start_x"]))
			and S.panel_extent(rot).is_equal_approx(S.panel_extent(stk)) and _near(S.panel_width("rotary", 2), S.panel_width("stick", 2)),
		"rotary: and it stands, reaches and is as wide as a stick's panel (the body and the grip are made for it)")
	var sys := await _machine()
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	model.morph_to(_spec("topgunbl"))
	model.apply_game_profile(P.for_romset("topgunbl"))
	await _wait(4)
	var panels := _panels(model)
	_ok(panels.size() == 2, "rotary: built, one panel a player (%d)" % panels.size())
	var built := true
	var bad_parts: Array = []
	for panel: ArcadeControlModule in panels:
		var pivot := panel.find_child("StickPivot", true, false) as Node3D
		var collar := panel.find_child("DialPivot", true, false) as Node3D
		if pivot == null or collar == null or collar.get_parent() != pivot:
			built = false
			bad_parts.append("%s has no collar on its stick" % panel.name)
			continue
		var ball := pivot.find_child("StickBall", false, false) as Node3D
		# On the shaft, below the ball, with its knob and the mark that shows the turn.
		var on_shaft := absf(collar.position.x) < 0.0005 and absf(collar.position.y) < 0.0005 and collar.position.z > 0.01 and collar.position.z < ball.position.z - 0.03
		if not on_shaft or collar.find_child("DialKnob", false, false) == null or collar.find_child("DialMark", false, false) == null:
			built = false
			bad_parts.append("%s's collar is off the shaft (%s)" % [panel.name, str(collar.position)])
	_ok(built, "rotary: each stick has a collar on its shaft below the ball, with a knob and a mark (%s)" % str(bad_parts))
	# The input: RIGHT leans the stick and turns the collar clockwise seen by the player, LEFT the other way; the collar turns about the shaft and nothing else.
	var one := panels[0] as ArcadeControlModule
	var stick := one.find_child("StickPivot", true, false) as Node3D
	var collar_one := one.find_child("DialPivot", true, false) as Node3D
	var stick_rest := stick.basis
	var collar_rest := collar_one.basis
	one.show_state(1 << ControllerBindings.JOYPAD_RIGHT)
	for i in 20:
		one.tick(1.0 / 60.0)
	var right_basis := collar_one.basis
	# The turn as an angle, clockwise seen by the player positive (the collar is turned by -angle about the shaft's +Z).
	var turned := func(b: Basis) -> float:
		return atan2(-b.x.y, b.x.x)
	var turned_right: float = turned.call(right_basis)
	_ok(not stick.basis.is_equal_approx(stick_rest) and not right_basis.is_equal_approx(collar_rest) and right_basis.z.is_equal_approx(Vector3.BACK) and turned_right > 0.05,
		"rotary: RIGHT leans the stick and turns its collar clockwise, about the shaft (%.2f rad)" % turned_right)
	one.show_state(1 << ControllerBindings.JOYPAD_LEFT)
	for i in 4:
		one.tick(1.0 / 60.0)
	var turned_back: float = wrapf(float(turned.call(collar_one.basis)) - turned_right, -PI, PI)
	_ok(turned_back < -0.02, "rotary: and LEFT turns it back (%.2f rad)" % turned_back)
	one.show_state(0)
	# The hands: the stick by its ball, the collar apart from it; a drag round the collar turns it by the angle swept, in the stick's own (leaned) frame.
	var hands := ArcadePanelHands.new(one)
	var stick_grab: ArcadePanelHands.ControlGrab = null
	var dial_grab: ArcadePanelHands.ControlGrab = null
	for g: ArcadePanelHands.ControlGrab in hands.grabs():
		if g.kind == &"stick":
			stick_grab = g
		elif g.kind == &"dial":
			dial_grab = g
	_ok(stick_grab != null and dial_grab != null and dial_grab.handle().distance_to(stick_grab.handle()) > 0.03 and dial_grab.handle().distance_to(stick_grab.handle()) < 0.08,
		"rotary: a hand can take the stick by its ball and the collar below it, a few centimetres apart")
	if dial_grab != null:
		one.show_state(1 << ControllerBindings.JOYPAD_DOWN)
		for i in 30:
			one.tick(1.0 / 60.0)
		var dg := dial_grab as ArcadePanelHands.DialGrab
		var from_tip: Vector3 = collar_one.global_transform * Vector3(0.02, 0.0, 0.012)
		var to_tip: Vector3 = collar_one.global_transform * Vector3(0.0, -0.02, 0.012)
		dg.begin(from_tip)
		var before := dg.angle
		dg.drag(to_tip, 0.016)
		_ok(absf(absf(wrapf(dg.angle - before, -PI, PI)) - PI * 0.5) < 0.08,
			"rotary: a quarter turn of the hand round the collar turns it a quarter turn, with the stick leaned (%.2f rad)" % wrapf(dg.angle - before, -PI, PI))
		dg.end()
		one.show_state(0)
	# Nothing else grows a collar: a stick alone, a spinner alone.
	for romset: String in ["sf2", "arkanoid"]:
		model.morph_to(_spec(romset))
		model.apply_game_profile(P.for_romset(romset))
		await _wait(3)
		var panel := _panels(model)[0] as ArcadeControlModule
		var dial := panel.find_child("DialPivot", true, false) as Node3D
		var has_stick := panel.find_child("StickPivot", true, false) != null
		if romset == "sf2":
			_ok(dial == null and has_stick, "rotary: a plain stick game has no collar")
		else:
			_ok(dial != null and not has_stick and dial.get_parent() == panel, "rotary: a spinner game is the spinner alone, on the panel")


## The name of a button's colour, for what a test says in words (white, yellow, red, blue, green; "?" for anything else).
func _hue_name(c: Color) -> String:
	if c.r > 0.85 and c.g > 0.85 and c.b > 0.85:
		return "white"
	if c.r > 0.85 and c.g > 0.75 and c.b < 0.3:
		return "yellow"
	if c.r > 0.8 and c.g < 0.3 and c.b < 0.3:
		return "red"
	if c.b > 0.8 and c.r < 0.3:
		return "blue"
	if c.g > 0.6 and c.r < 0.3 and c.b < 0.4:
		return "green"
	return "?"


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
			and ArcadeProfiles.button_bit(0) == -1 and ArcadeProfiles.button_bit(7) == ControllerBindings.JOYPAD_L2 and ArcadeProfiles.button_bit(10) == ControllerBindings.JOYPAD_R3
			and ArcadeProfiles.button_bit(11) == -1,
		"shift: MAME's button n is the pad's B A Y X L R in order, and a seventh is nothing")
	# The spec: a lever only for a game that has one.
	_ok(bool(_spec("pdrift")["cockpit"]["shifter"]) and bool(_spec("hotchase")["cockpit"]["shifter"]),
		"shift: Power Drift's and Hot Chase's sit-down cockpits carry their lever")
	_ok(not bool(_spec("daytona")["cockpit"]["shifter"]) and bool(_spec("outrun")["cockpit"]["shifter"]) and bool(_spec("polepos")["players"][0]["shifter"])
			and not bool(_spec("scud")["cockpit"]["shifter"]),
		"shift: no lever is built for Daytona USA or Scud Race; Out Run's sit-down cockpit and Pole Position's stand-up panel have one")
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
	# Nothing overflows the case: pushed to the far ends each handle's dome is inside the walls, START stands ABOVE its lever (toward the screen, clear of the
	# dome), all of it is on a deck that is deeper than an upright's with the apron out as far, and the rail runs under the carriages' whole travel.
	a.show_state(1 << ControllerBindings.JOYPAD_LEFT)
	b.show_state(1 << ControllerBindings.JOYPAD_RIGHT)
	for i in 40:
		a.tick(1.0 / 60.0)
		b.tick(1.0 / 60.0)
	var inner := float(_spec("panicprk")["width"]) - 0.04
	var dome := ball_mesh.radius
	var out_a := model.to_local(la.global_position).x
	var out_b := model.to_local(lb.global_position).x
	_ok(out_a < -0.25 and out_b > 0.25 and absf(out_a) + dome <= inner * 0.5 and absf(out_b) + dome <= inner * 0.5,
		"slot: at the ends of the slot each handle is inside the walls (%.3f and %.3f m of %.3f, dome %.3f)" % [out_a, out_b, inner * 0.5, dome])
	var rail := model.find_child("SlotRail", true, false) as MeshInstance3D
	_ok(rail != null and (rail.mesh as BoxMesh).size.x >= 2.0 * (S.SLOT_TRAVEL * 2.0 + dome) and (rail.mesh as BoxMesh).size.x <= inner,
		"slot: the rail runs under both carriages' whole travel and stops inside the case (%.2f m)" % ((rail.mesh as BoxMesh).size.x if rail != null else 0.0))
	var plate := model.find_child("DeckPlate", true, false) as MeshInstance3D
	var half_deck := (plate.mesh as BoxMesh).size.y * 0.5
	var start_b := b.find_child("Start", true, false) as MeshInstance3D
	var rim := (start_a.mesh as CylinderMesh).bottom_radius * 1.22
	var clear := 1.0e9
	var on_deck := true
	for pair: Array in [[la, start_a], [lb, start_b]]:
		var lever_y := (pair[0] as Node3D).position.y
		var start_y := (pair[1] as Node3D).position.y
		clear = minf(clear, start_y - rim - (lever_y + dome))
		on_deck = on_deck and start_y + rim <= half_deck and lever_y - dome >= -half_deck + 0.03
	_ok(clear >= 0.0 and on_deck,
		"slot: START stands above each lever with %.1f cm to spare over the dome, and lever and START are both on the deck (half of it %.3f m)" % [clear * 100.0, half_deck])
	var apron := model.find_child("Apron", true, false) as Node3D
	var overhang := false
	for box: AABB in model.get_meta(ArcadeCabinetBuilder.SOLID_BOXES_META, []):
		overhang = overhang or (box.end.z >= 0.54 - 0.001 and box.position.z <= 0.47 + 0.001 and box.position.y >= 0.77)
	_ok(half_deck * 2.0 >= 0.24 and apron != null and apron.position.z >= 0.52 and overhang,
		"slot: the deck is deeper than the upright's 0.19 m (%.2f), the apron out with it (%.2f) and the overhang is solid" % [half_deck * 2.0, apron.position.z if apron != null else 0.0])
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
		"propcycl", "timetrv", "panicprk", "luckywld", "bm2ndmix", "popn1", "gtrfrks", "drmn", "taiko6", "mamboagg", "ddrsbm"]
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


## A control's pointer shape is the CONTROL, not the console round it. After Burner's stick had a box 0.32 m across (and a green plate that big) at its head, which stood between a laser
## aimed from the seat or from behind it and the coin doors, 0.8 m in front: nobody could put a coin in. From the middle behind the controls, at chest height, every coin slot and
## RETURN of a flight cockpit is the first thing the laser meets; a wheel's grip is its rim, hub and spokes, so a laser goes through the hole; a rider's bars are a bar deep.
func _group_grip() -> void:
	var sys := await _machine()
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	for romset: String in ["aburner2", "gloc"]:
		model.morph_to(_spec(romset))
		await _wait(3)
		var from := sys.global_transform * Vector3(0.0, 1.10, 1.70)
		var buttons := 0
		var reached := 0
		var blocker := ""
		for door: ArcadeCoinModule in _doors(model):
			if not door.door_enabled():
				continue
			for button_name in ["CoinReturn", "CoinSlot"]:
				var button := door.find_child(button_name, true, false) as VRButton
				if button == null:
					continue
				buttons += 1
				var centre := button.global_transform * Vector3(0, 0, 0.008)
				var hit := _first_hit(sys, from, centre)
				reached += 1 if hit == button else 0
				if hit != button and hit is Node:
					blocker = "%s/%s" % [(hit as Node).get_parent().name, (hit as Node).name]
		_ok(buttons >= 2 and reached == buttons,
			"grip: %s: from behind the controls every coin slot and RETURN is the first thing a laser meets (%d of %d; %s in the way)" % [romset, reached, buttons, blocker])
		var stick := _panels(model)[0].grip() as Area3D
		var box := _grip_box(stick)
		_ok(box.x <= 0.14 and box.y <= 0.30 and box.z <= 0.14 and stick.panel_size.x <= 0.14 and stick.panel_size.y <= 0.30,
			"grip: %s: the stick's box and its lit plate are the stick's size (%s, %s)" % [romset, str(box), str(stick.panel_size)])
	# A wheel: the rim, the hub and the spokes take a laser, the openings between them do not.
	for romset: String in ["daytona", "scud", "luckywld"]:
		model.morph_to(_spec(romset))
		await _wait(3)
		var grip := _panels(model)[0].grip() as ArcadePanelGrip
		var gt := grip.global_transform
		var axis := gt.basis.z.normalized()
		var rim := ArcadeCabinetBuilder.WHEEL_RIM_R
		var probes := {
			"hole": [Vector3(0.0, 0.08, 0.0), false], "rim": [Vector3(rim, 0.0, 0.0), true], "rim's top": [Vector3(0.0, rim, 0.0), true],
			"hub": [Vector3.ZERO, true], "spoke": [Vector3(cos(deg_to_rad(30.0)), sin(deg_to_rad(30.0)), 0.0) * 0.08, true],
			"outside the rim": [Vector3(rim + 0.09, 0.0, 0.0), false]}
		var wrong: Array = []
		for name: String in probes:
			var p := gt * (probes[name][0] as Vector3)
			var hit := _first_hit(sys, p + axis * 0.4, p - axis * 0.1)
			if (hit == grip) != bool(probes[name][1]):
				wrong.append(name)
		_ok(wrong.is_empty() and grip.ring_radius > 0.0,
			"grip: %s: the wheel's grip is its rim, hub and spokes, with the hole open to a laser (wrong: %s)" % [romset, str(wrong)])
	# A rider's bars: a bar deep, not a hand's width.
	for romset: String in ["hangon", "propcycl", "topskatr", "alpinr2b"]:
		model.morph_to(_spec(romset))
		await _wait(3)
		var bars := _panels(model)[0].grip() as ArcadePanelGrip
		var bars_box := _grip_box(bars)
		_ok(bars != null and bars_box.x > 0.5 and bars_box.y <= 0.12 and bars_box.z <= 0.12 and bars.panel_size.y <= 0.12,
			"grip: %s: the bars' box and plate are as deep as the bars (%s, %s)" % [romset, str(bars_box), str(bars.panel_size)])


## The size of a grip's first box shape.
func _grip_box(grip: Node) -> Vector3:
	var col := grip.find_child("CollisionShape3D", true, false) as CollisionShape3D
	return (col.shape as BoxShape3D).size if col != null and col.shape is BoxShape3D else Vector3(INF, INF, INF)


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
