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
	_ok(str(sc["gun_style"]) == "rifle" and int(sc["guns"]) == 1 and int(sc["screen"]["screens"]) == 2,
		"specs: Silent Scope: one rifle, two screens")
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
		"polepos", "daytona", "scud", "hangon", "ddrusa", "pumpipx2", "robotron", "centiped", "pong"]
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
