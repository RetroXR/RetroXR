## Arcade attract self-tests -- a switched-on cabinet that shows its game instead of running it.
## Headless: no core, no ROM, no VLC, no headset.
##
##     "$godot" --headless --path RetroXR res://Tests/arcade_attract_tests.tscn
##     "$godot" --headless --path RetroXR res://Tests/arcade_attract_tests.tscn -- --only=use
##
## Exits 0 when everything passes, 1 otherwise.
##
## What a headless run cannot show is the picture and the sound, so none of this proves them:
## Tools/models/arcade_attract_probe (windowed) is the picture, and a headset the cost.
##
## Groups:
##   rules/    the pure half: when a cabinet attracts, what is in view, who gets a video, how far is heard
##   media/    the video -> title -> wheel -> cover chain, read from a scratch ROM folder
##   state/    a built cabinet: switched on it shows the game and runs no core; off it behaves as always
##   screen/   the glass takes the attract picture at the picture's own shape
##   use/      a coin, a panel, a gun or pad in hand each start the game, once; the coin counts in it
##   idle/     nobody at the cabinet puts the core away; somebody there, or a coin, keeps it
##   leave/    the board pulled, the power button and the cabinet's own override end the attract
##   media_ask/ a cabinet with a game and no video asks the scraper (through its group) for that game only
##   keep/     the cabinet's override is saved when set and left out when it follows the global option
##   panel/    the System tab's row, shown for a cabinet only
extends Node

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const CART_SCENE := preload("res://Scenes/Objects/media/cartridge.tscn")
const MODEL_ID := "arcade_cabinet_generic"
const TEST_SYSTEM := "__attract_selftest"
const ROM := "/tmp/attract_test_board.zip"

var _checks := 0
var _failed := 0
var _only := ""
var _spawned: Array[Node] = []
var _pref_before := false


## A pad or gun for the idle and grab cases: it says whether a hand has it, and where its holster is.
class StubPad extends Node3D:
	var held := false
	var captive_well: Object = null

	func is_picked_up() -> bool:
		return held


## A holster that holds whatever it is told to.
class StubWell extends RefCounted:
	var picked_up_object: Object = null


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7)
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("[attract] TIMED OUT")
		get_tree().quit(1))
	_pref_before = AppPrefs.arcade_attract_mode
	await _run()
	AppPrefs.arcade_attract_mode = _pref_before
	ArcadeAttract.test_still.clear()
	_remove_tree(RomLibrary.rom_dir_for_system(TEST_SYSTEM))
	print("[attract] %d checks, %d failed" % [_checks, _failed])
	print("[attract] RESULT=%s" % ("PASS" if _failed == 0 else "FAIL"))
	get_tree().quit(1 if _failed > 0 else 0)


func _ok(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
	print("[attract] %s  %s" % ["PASS" if ok else "FAIL", what])


func _want(group: String) -> bool:
	return _only.is_empty() or _only == group


func _wait(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _run() -> void:
	if _want("rules"):
		_group_rules()
	if _want("media"):
		_group_media()
	if _want("state"):
		await _group_state()
	if _want("screen"):
		await _group_screen()
	if _want("use"):
		await _group_use()
	if _want("idle"):
		await _group_idle()
	if _want("leave"):
		await _group_leave()
	if _want("media_ask"):
		await _group_media_ask()
	if _want("keep"):
		await _group_keep()
	if _want("panel"):
		await _group_panel()


# ── fixtures ────────────────────────────────────────────────────────────────

func _remove_tree(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while not name.is_empty():
		var full := path.path_join(name)
		if d.current_is_dir():
			_remove_tree(full)
		else:
			DirAccess.remove_absolute(full)
		name = d.get_next()
	d.list_dir_end()
	DirAccess.remove_absolute(path)


func _touch(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("x")
	f.close()


func _png(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var img := Image.create(8, 6, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 0, 0))
	img.save_png(path)


func _cabinet(wake: bool = true) -> RetroSystem:
	var sys := SYSTEM_SCENE.instantiate() as RetroSystem
	sys.model_id = MODEL_ID
	sys.systemid = "arcade"
	sys.position = Vector3(_spawned.size() * 2.0, 0, 0)
	sys.freeze = true
	add_child(sys)
	sys.add_to_group("spawned")
	_spawned.append(sys)
	await _wait(6)
	return sys


## A cabinet with a board in its bay, the way the room has one.
func _cabinet_with_board(rom: String = ROM) -> RetroSystem:
	var sys := await _cabinet()
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	model.set_lid_angle_deg(90.0)
	var cart := CART_SCENE.instantiate() as Node3D
	cart.systemid = "arcade"
	cart.rom_path = rom
	cart.position = Vector3(0, 3, 0)
	cart.freeze = true
	add_child(cart)
	_spawned.append(cart)
	await _wait(8)
	_slot_of(sys).pick_up_object(cart)
	await _wait(6)
	return sys


func _slot_of(sys: RetroSystem) -> XRToolsSnapZone:
	var bay := sys.get_bay()
	return bay.slot if bay != null else sys.get_node("CartridgeSlot") as XRToolsSnapZone


func _clear() -> void:
	for n in _spawned:
		if is_instance_valid(n):
			n.queue_free()
	for bay in get_tree().get_nodes_in_group(ArcadeBayUnit.GROUP):
		bay.queue_free()
	_spawned.clear()
	await _wait(6)


## Switch the option on (without saving it) and a cabinet on: it should now be attracting.
func _attracting_cabinet() -> RetroSystem:
	AppPrefs.arcade_attract_mode = true
	var sys := await _cabinet_with_board()
	# A made-up ROM makes the core refuse it a moment after the start, and the refusal powers the machine
	# off: that is the machine's business, and not what these cases are about.
	sys._libretro.content_load_failed.disconnect(sys._on_content_load_failed)
	sys.power_on()
	return sys


# ── rules ───────────────────────────────────────────────────────────────────

func _group_rules() -> void:
	var F := ArcadeAttract.OVERRIDE_FOLLOW
	var ON := ArcadeAttract.OVERRIDE_ON
	var OFF := ArcadeAttract.OVERRIDE_OFF
	_ok(ArcadeAttract.effective_pref(false, F) == false and ArcadeAttract.effective_pref(true, F) == true,
		"rules: a cabinet that follows the global option does as it says")
	_ok(ArcadeAttract.effective_pref(false, ON) and not ArcadeAttract.effective_pref(true, OFF),
		"rules: its own override beats the global option, either way")
	# wanted(pref, override, has_game, external, netplay)
	_ok(not ArcadeAttract.wanted(false, F, true, false, false), "rules: off by default, a cabinet runs its game as ever")
	_ok(ArcadeAttract.wanted(true, F, true, false, false), "rules: on, with a game in it, it attracts")
	_ok(not ArcadeAttract.wanted(true, F, false, false, false), "rules: with no game or bay there is nothing to show")
	_ok(not ArcadeAttract.wanted(true, F, true, true, false), "rules: a console cabled to the A/V input owns the screen")
	_ok(not ArcadeAttract.wanted(true, F, true, false, true), "rules: a netplay session runs the real core")
	_ok(ArcadeAttract.wanted(false, ON, true, false, false), "rules: forced on, it attracts with the global option off")
	_ok(not ArcadeAttract.wanted(true, OFF, true, false, false), "rules: forced off, it does not")
	_ok(not ArcadeAttract.wanted(false, ON, false, false, false), "rules: and forced on still needs a game")

	# In view: a camera at the origin looking down -Z, a screen 2 m ahead facing it (+Z toward the camera).
	var cam := Transform3D.IDENTITY
	var screen := Transform3D(Basis.IDENTITY, Vector3(0, 0, -2))
	var size := Vector2(0.38, 0.285)
	_ok(ArcadeAttract.screen_visible(cam, 70.0, 1.0, screen, size), "rules: a screen straight ahead is in view")
	_ok(not ArcadeAttract.screen_visible(cam, 70.0, 1.0, Transform3D(Basis.IDENTITY, Vector3(0, 0, 2)), size),
		"rules: one behind the head is not")
	_ok(not ArcadeAttract.screen_visible(cam, 70.0, 1.0, Transform3D(Basis.IDENTITY, Vector3(6, 0, -2)), size),
		"rules: one far off to the side is not")
	_ok(not ArcadeAttract.screen_visible(cam, 70.0, 1.0, Transform3D(Basis.IDENTITY, Vector3(0, 6, -2)), size),
		"rules: nor one far above")
	_ok(ArcadeAttract.screen_visible(cam, 70.0, 1.0, Transform3D(Basis.IDENTITY, Vector3(1.2, 0, -2)), size),
		"rules: a screen inside the edge of the view is in view")
	# Turned its back to us (+Z away from the camera): the cabinet's rear is no glass.
	var turned := Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, -2))
	_ok(not ArcadeAttract.screen_visible(cam, 70.0, 1.0, turned, size),
		"rules: a screen facing away is not in view, however centred")
	_ok(ArcadeAttract.screen_visible(cam, 70.0, 1.0, Transform3D(Basis.IDENTITY, Vector3(0.0, 0, -0.1)), size),
		"rules: and one right at the face still is")

	# Who gets a video: the nearest, ties to the lower index.
	var picked := ArcadeAttract.pick_budget(PackedFloat32Array([5.0, 1.0, 9.0, 2.0]), 2)
	_ok(picked.size() == 2 and picked.has(1) and picked.has(3), "rules: the two nearest cabinets get the video (%s)" % str(picked))
	_ok(ArcadeAttract.pick_budget(PackedFloat32Array([3.0, 3.0, 3.0]), 1) == PackedInt32Array([0]),
		"rules: a tie goes to the lower index, so it does not flicker")
	_ok(ArcadeAttract.pick_budget(PackedFloat32Array([1.0]), 4).size() == 1 and ArcadeAttract.pick_budget(PackedFloat32Array(), 4).is_empty(),
		"rules: a budget larger than the room hands out what there is")
	_ok(ArcadeAttract.pick_budget(PackedFloat32Array([1.0, 2.0]), 0).is_empty(), "rules: a budget of none hands out none")
	_ok(ArcadeAttract.video_budget() >= 1, "rules: there is always at least one video")

	_ok(ArcadeAttract.audio_tier(1.0) == ArcadeAttract.Tier.NEAR and ArcadeAttract.audio_tier(ArcadeAttract.NEAR_AUDIO) == ArcadeAttract.Tier.NEAR,
		"rules: near the sound is served in full")
	_ok(ArcadeAttract.audio_tier(ArcadeAttract.NEAR_AUDIO + 0.5) == ArcadeAttract.Tier.FAR
		and ArcadeAttract.audio_tier(ArcadeAttract.MAX_AUDIO - 0.5) == ArcadeAttract.Tier.FAR,
		"rules: far it is approximated")
	_ok(ArcadeAttract.audio_tier(ArcadeAttract.MAX_AUDIO) == ArcadeAttract.Tier.SILENT and ArcadeAttract.audio_tier(100.0) == ArcadeAttract.Tier.SILENT,
		"rules: past hearing it is not served at all")

	# Who is at the cabinet: a pad in a hand, not in its holster.
	var pad := StubPad.new()
	_ok(not ArcadeInput.held_by_hand(pad), "rules: a pad nobody holds is nobody's")
	pad.held = true
	_ok(ArcadeInput.held_by_hand(pad), "rules: a pad in a hand is somebody's")
	var well := StubWell.new()
	pad.captive_well = well
	well.picked_up_object = pad
	_ok(not ArcadeInput.held_by_hand(pad), "rules: a gun lying in its holster is picked up by the zone, not by a hand")
	well.picked_up_object = null
	_ok(ArcadeInput.held_by_hand(pad), "rules: and out of it, in a hand, it is")
	pad.free()


# ── media ───────────────────────────────────────────────────────────────────

func _group_media() -> void:
	var dir := RomLibrary.rom_dir_for_system(TEST_SYSTEM)
	_remove_tree(dir)
	var rom := dir.path_join("sf2.zip")
	var media := dir.path_join("media")
	_ok(ArcadeAttract.resolve_media(TEST_SYSTEM, rom)["kind"] == "", "media: a game with nothing scraped has nothing to show")
	_png(media.path_join("box/sf2.png"))
	var r: Dictionary = ArcadeAttract.resolve_media(TEST_SYSTEM, rom)
	_ok(r["kind"] == "image" and r["folder"] == "box", "media: the cover when it is all there is")
	_png(media.path_join("wheel/sf2.png"))
	r = ArcadeAttract.resolve_media(TEST_SYSTEM, rom)
	_ok(r["kind"] == "image" and r["folder"] == "wheel", "media: the wheel before the cover")
	_png(media.path_join("title/sf2.png"))
	r = ArcadeAttract.resolve_media(TEST_SYSTEM, rom)
	_ok(r["kind"] == "image" and r["folder"] == "title", "media: the title screen before the wheel")
	_touch(media.path_join("video/sf2.mp4"))
	r = ArcadeAttract.resolve_media(TEST_SYSTEM, rom)
	_ok(r["kind"] == "video" and str(r["path"]).ends_with("video/sf2.mp4"), "media: and the video before them all")
	_ok(ArcadeAttract.has_video(TEST_SYSTEM, rom), "media: the cabinet can tell a game has its video")
	_ok(not ArcadeAttract.has_video(TEST_SYSTEM, dir.path_join("other.zip")), "media: and that another has not")
	DirAccess.remove_absolute(media.path_join("video/sf2.mp4"))
	_touch(media.path_join("video/sf2.mkv"))
	_ok(ArcadeAttract.resolve_media(TEST_SYSTEM, rom)["kind"] == "video", "media: a video in another container counts")
	_ok(ArcadeAttract.load_still(TEST_SYSTEM, rom) != null, "media: the still that holds the place of the video is the title")
	DirAccess.remove_absolute(media.path_join("title/sf2.png"))
	_ok(ArcadeAttract.load_still(TEST_SYSTEM, rom) != null, "media: with no title the wheel stands in")
	DirAccess.remove_absolute(media.path_join("wheel/sf2.png"))
	_ok(ArcadeAttract.load_still(TEST_SYSTEM, rom) != null, "media: with no wheel the cover")
	DirAccess.remove_absolute(media.path_join("box/sf2.png"))
	_ok(ArcadeAttract.load_still(TEST_SYSTEM, rom) == null, "media: and with none, nothing")
	_remove_tree(dir)


# ── state ───────────────────────────────────────────────────────────────────

func _group_state() -> void:
	AppPrefs.arcade_attract_mode = false
	var sys := await _cabinet_with_board()
	_ok(sys.rom_path == ROM, "state: the board is the cabinet's game")
	_ok(not sys.attract_applies(), "state: with the option off, a cabinet does not attract")
	AppPrefs.arcade_attract_mode = true
	_ok(sys.attract_applies(), "state: on, with a game in it, it does")
	sys.attract_override = ArcadeAttract.OVERRIDE_OFF
	_ok(not sys.attract_applies(), "state: the cabinet's own 'off' beats the global 'on'")
	sys.attract_override = ArcadeAttract.OVERRIDE_FOLLOW
	_ok(not sys.attracting and not sys.is_powered_on, "state: nothing is attracting before it is switched on")
	sys.power_on()
	_ok(sys.attracting, "state: switched on, it attracts")
	_ok(not sys.is_powered_on, "state: and no core runs")
	_ok(not sys.attract_session, "state: (no core is the attract's to put away)")
	_ok(sys.get_node_or_null("ArcadeAttract") != null, "state: the attract is a node of the cabinet")
	var lbl := sys.get_node_or_null("PowerButton/ButtonLabel") as Label3D
	_ok(lbl == null or lbl.text == "STOP", "state: the power button reads STOP, as the machine is on")
	sys.power_on()
	_ok(sys.attracting and not sys.is_powered_on, "state: switching on again changes nothing")
	sys.toggle_power()
	_ok(not sys.attracting, "state: the power button, pressed, switches it off")
	_ok(not sys.is_powered_on, "state: and it is off")
	sys.toggle_power()
	_ok(sys.attracting, "state: and on again, it attracts again")
	await _clear()

	# No game in it: nothing to show, so it is no different from before.
	AppPrefs.arcade_attract_mode = true
	var empty := await _cabinet()
	_ok(not empty.attract_applies(), "state: a cabinet with no board does not attract")
	_ok(not empty.attracting, "state: and is not attracting")
	await _clear()

	# A machine that is not a cabinet never attracts.
	var console := SYSTEM_SCENE.instantiate() as RetroSystem
	console.systemid = "snes"
	console.freeze = true
	add_child(console)
	_spawned.append(console)
	await _wait(6)
	_ok(not console.attract_applies(), "state: a console never attracts, whatever the option")
	await _clear()


# ── screen ──────────────────────────────────────────────────────────────────

func _group_screen() -> void:
	AppPrefs.arcade_attract_mode = true
	var rom := ROM
	var tex := ImageTexture.create_from_image(Image.create(16, 9, false, Image.FORMAT_RGBA8))
	ArcadeAttract.test_still[rom] = tex
	var sys := await _cabinet_with_board(rom)
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	_ok(model.host_picture() == null and not model.attract_picture_active(),
		"screen: before it is switched on the glass shows no attract picture")
	sys.power_on()
	await _wait(3)
	_ok(sys.attracting and model.attract_picture_active(), "screen: attracting, the glass shows the attract's picture")
	_ok(model.host_picture() == tex, "screen: and it is the game's still")
	var screen := model.modules_of_kind(ArcadeProfiles.KIND_SCREEN)[0] as ArcadeScreenModule
	_ok(absf(screen.current_aspect() - 16.0 / 9.0) < 0.01, "screen: at the picture's own shape (%f)" % screen.current_aspect())
	_ok(screen.get_screen().get_surface_override_material(0) != null, "screen: the tube is lit with it")
	sys.power_off()
	await _wait(3)
	_ok(not model.attract_picture_active() and model.host_picture() == null, "screen: switched off, the glass is dark again")
	ArcadeAttract.test_still.erase(rom)
	# A game with nothing to show leaves the tube dark rather than lit with nothing.
	sys.power_on()
	await _wait(3)
	_ok(sys.attracting and not model.attract_picture_active(), "screen: a game with nothing scraped attracts to a dark tube")
	await _clear()


# ── use ─────────────────────────────────────────────────────────────────────

## What the cabinet looked like the moment ArcadeInput said somebody used it, after RetroSystem had
## answered: it had left the attract and asked for the real game (attract_session is set by that power-on;
## a core that cannot load a made-up ROM takes it away again a moment later, so it is read here).
func _log_uses(sys: RetroSystem) -> Array[Dictionary]:
	var log: Array[Dictionary] = []
	var input := (sys.get_model() as RetroSystemModelArcadeCabinet).arcade_input()
	input.first_use.connect(func(k: StringName) -> void:
		log.append({"kind": k, "attracting": sys.attracting, "session": sys.attract_session,
			"released": sys._attract_released}))
	return log


func _started(log: Array[Dictionary], kind: StringName) -> bool:
	for e in log:
		if e["kind"] == kind and not e["attracting"] and e["session"] and not e["released"]:
			return true
	return false


func _group_use() -> void:
	var sys := await _attracting_cabinet()
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	var input := model.arcade_input()
	var log := _log_uses(sys)
	_ok(sys.attracting, "use: the cabinet is attracting")
	await _wait(10)
	_ok(sys.attracting and log.is_empty(), "use: left alone it stays so")

	# A coin.
	var door := model.modules_of_kind(ArcadeProfiles.KIND_COIN)[0] as ArcadeCoinModule
	door.insert_coin()
	_ok(sys.attracting, "use: a coin in the air has not started the game yet")
	await get_tree().create_timer(ArcadeCoinModule.FLIGHT_SECONDS + 0.2).timeout
	_ok(_started(log, &"coin"), "use: a coin that lands starts the real game")
	_ok(log.size() == 1, "use: once (%d)" % log.size())
	# A made-up ROM cannot load, so no core is running; stand in for one so the coin can count.
	sys.is_powered_on = true
	var seen_at := -1.0
	var waited := 0.0
	while waited < ArcadeAttract.COIN_BOOT_DELAY + 2.0 and seen_at < 0.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if input.last_sent.has(0) and (int(input.last_sent[0]) & (1 << ArcadeProfiles.COIN_BIT)) != 0:
			seen_at = waited
	_ok(seen_at >= ArcadeAttract.COIN_BOOT_DELAY - 0.2 and seen_at <= ArcadeAttract.COIN_BOOT_DELAY + 0.8,
		"use: the coin that started it counts in the game once the core has had its moment (after %.2f s)" % seen_at)
	sys.is_powered_on = false
	await _clear()

	# A panel pressed.
	sys = await _attracting_cabinet()
	model = sys.get_model() as RetroSystemModelArcadeCabinet
	log = _log_uses(sys)
	var panel := model.modules_of_kind(ArcadeProfiles.KIND_STICK_BUTTONS)[0] as ArcadeControlModule
	panel.set_attached(true)
	await _wait(2)
	_ok(_started(log, &"panel"), "use: attaching to a panel starts the game")
	_ok(panel.is_attached(), "use: and the panel stays attached (the player is still on it)")
	await _clear()

	# A gun or pad taken in hand.
	sys = await _attracting_cabinet()
	log = _log_uses(sys)
	var pad := StubPad.new()
	add_child(pad)
	sys._port_controllers[0] = pad
	await _wait(4)
	_ok(sys.attracting, "use: a pad plugged in and left alone is nobody at the cabinet")
	var well := StubWell.new()
	pad.captive_well = well
	well.picked_up_object = pad
	pad.held = true
	await _wait(4)
	_ok(sys.attracting, "use: nor a gun in its holster")
	well.picked_up_object = null
	await _wait(4)
	_ok(_started(log, &"grab"), "use: taken in hand, it starts the game")
	sys._port_controllers[0] = null
	pad.queue_free()
	await _clear()

	# More than one use at a time starts the game once.
	sys = await _attracting_cabinet()
	log = _log_uses(sys)
	sys.attract_first_use(&"coin")
	_ok(not sys.attracting and sys.attract_session, "use: the first use leaves the attract")
	sys.attract_first_use(&"panel")
	_ok(not sys.attracting and not sys._attract_released, "use: a second, late one does nothing and leaves nothing set")
	await _clear()


# ── idle ────────────────────────────────────────────────────────────────────

func _group_idle() -> void:
	var sys := await _attracting_cabinet()
	var attract := sys.get_node("ArcadeAttract") as ArcadeAttract
	_ok(is_equal_approx(ArcadeAttract.IDLE_SECONDS, 120.0), "idle: two minutes of nobody put the core away")
	# The core runs on behalf of an attract start.
	sys.attract_first_use(&"coin")
	sys.is_powered_on = true
	sys.attract_session = true
	_ok(sys.attract_session and not sys.attracting, "idle: the game is running, started by the attract")
	attract._watch_idle(30.0)
	_ok(is_equal_approx(attract.idle_seconds(), 30.0), "idle: nobody there, the clock runs")
	attract.touch()
	_ok(attract.idle_seconds() == 0.0, "idle: a coin or a press starts it over")
	attract._watch_idle(30.0)
	# Somebody picks a pad up.
	var pad := StubPad.new()
	add_child(pad)
	sys._port_controllers[0] = pad
	pad.held = true
	attract._watch_idle(30.0)
	_ok(attract.idle_seconds() == 0.0, "idle: somebody holding a pad keeps it from running")
	pad.held = false
	sys._port_controllers[0] = null
	pad.queue_free()
	var panel := (sys.get_model() as RetroSystemModelArcadeCabinet).modules_of_kind(ArcadeProfiles.KIND_STICK_BUTTONS)[0] as ArcadeControlModule
	panel.set_attached(true)
	attract._watch_idle(30.0)
	_ok(attract.idle_seconds() == 0.0, "idle: so does a panel attached")
	panel.set_attached(false)
	attract._watch_idle(ArcadeAttract.IDLE_SECONDS - 1.0)
	_ok(sys.is_powered_on and sys.attract_session, "idle: just short of the time the game is still there")
	attract._watch_idle(2.0)
	_ok(not sys.is_powered_on, "idle: at the time the core is put away")
	_ok(sys.attracting, "idle: and the cabinet shows its game again")
	_ok(not sys.attract_session, "idle: with no core to put away")
	await _clear()

	# A game the player started the ordinary way is never put away: nobody asked for an attract.
	AppPrefs.arcade_attract_mode = false
	var plain := await _cabinet_with_board()
	var pa := ArcadeAttract.new()
	plain.add_child(pa)
	pa._host = plain
	plain.is_powered_on = true
	plain.attract_session = false
	pa._watch_idle(ArcadeAttract.IDLE_SECONDS * 3.0)
	_ok(plain.is_powered_on and pa.idle_seconds() == 0.0, "idle: a game not started by the attract is left alone")
	plain.is_powered_on = false
	await _clear()


# ── leave ───────────────────────────────────────────────────────────────────

func _group_leave() -> void:
	var sys := await _attracting_cabinet()
	_ok(sys.attracting, "leave: attracting")
	_slot_of(sys).drop_object()
	await _wait(6)
	_ok(not sys.attracting and sys.rom_path.is_empty(), "leave: pulling the board ends it, the game gone")
	await _clear()

	sys = await _attracting_cabinet()
	sys.power_off()
	_ok(not sys.attracting and not sys.is_powered_on, "leave: power off ends it")
	await _clear()

	sys = await _attracting_cabinet()
	sys.attract_override = ArcadeAttract.OVERRIDE_OFF
	sys.set_attract_override(ArcadeAttract.OVERRIDE_OFF)
	_ok(not sys.attracting, "leave: forcing the cabinet's attract off ends it")
	await _clear()

	# A cabinet with a console on its A/V input: attract gives way.
	sys = await _attracting_cabinet()
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	_ok(not model.external_picture_active(), "leave: nothing is cabled to the cabinet")
	_ok(not ArcadeAttract.wanted(true, ArcadeAttract.OVERRIDE_FOLLOW, true, true, false),
		"leave: a console cabled to its input means no attract")
	await _clear()


# ── media_ask ───────────────────────────────────────────────────────────────

## A stand-in for the spawn menu: the node in the `attract_media_listener` group that the cabinet calls.
class StubListener extends Node:
	var asked: Array[Array] = []

	func request_attract_media(rom_path: String, systemid: String) -> void:
		asked.append([rom_path, systemid])


func _group_media_ask() -> void:
	var listener := StubListener.new()
	listener.add_to_group(&"attract_media_listener")
	add_child(listener)
	var dir := RomLibrary.rom_dir_for_system(TEST_SYSTEM)
	_remove_tree(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	var rom := dir.path_join("ask.zip")

	# Option off: nothing is asked, whatever is in the bay.
	AppPrefs.arcade_attract_mode = false
	var sys := await _cabinet_with_board(rom)
	_ok(listener.asked.is_empty(), "media_ask: with the option off a board put in the bay asks for nothing")
	AppPrefs.arcade_attract_mode = true
	sys.power_on()
	_ok(sys.attracting and listener.asked.size() == 1 and listener.asked[0][0] == rom,
		"media_ask: switched on to attract, the cabinet asks for its game's video (%s)" % str(listener.asked))
	_ok(listener.asked[0][1] == "arcade", "media_ask: naming the board's system (%s)" % str(listener.asked[0][1]))
	sys.power_off()
	await _clear()

	# A board put in with the option on asks as it lands.
	listener.asked.clear()
	AppPrefs.arcade_attract_mode = true
	sys = await _cabinet_with_board(rom)
	_ok(listener.asked.size() == 1 and listener.asked[0][0] == rom, "media_ask: a board put in with it on asks at once")
	await _clear()

	# A game that has its video is not asked for again. The board's system is `arcade`, so its media is
	# looked for under the arcade folder; a name nothing else uses keeps the player's files out of it.
	listener.asked.clear()
	var real_rom := RomLibrary.rom_dir_for_system("arcade").path_join("__attract_selftest_ask.zip")
	var real_video := RomLibrary.rom_dir_for_system("arcade").path_join("media/video/__attract_selftest_ask.mp4")
	var had_video_dir := DirAccess.dir_exists_absolute(real_video.get_base_dir())
	_touch(real_video)
	sys = await _cabinet_with_board(real_rom)
	_ok(listener.asked.is_empty(), "media_ask: a game with its video asks for nothing")
	await _clear()
	DirAccess.remove_absolute(real_video)
	if not had_video_dir:
		DirAccess.remove_absolute(real_video.get_base_dir())

	# With nobody to ask yet (the menu that holds the scraper is not up), the want is kept for it.
	listener.remove_from_group(&"attract_media_listener")
	ArcadeAttract.pending_media.clear()
	listener.asked.clear()
	sys = await _cabinet_with_board(rom)
	_ok(listener.asked.is_empty() and ArcadeAttract.pending_media.get(rom, "") == "arcade",
		"media_ask: with no scraper up yet the want is kept (%s)" % str(ArcadeAttract.pending_media))
	await _clear()
	ArcadeAttract.pending_media.clear()
	listener.add_to_group(&"attract_media_listener")

	# The cabinet's own 'off' stops the ask even with the global option on.
	listener.asked.clear()
	_remove_tree(dir.path_join("media"))
	sys = await _cabinet()
	sys.attract_override = ArcadeAttract.OVERRIDE_OFF
	var cart := CART_SCENE.instantiate() as Node3D
	cart.systemid = "arcade"
	cart.rom_path = rom
	cart.position = Vector3(0, 3, 0)
	cart.freeze = true
	add_child(cart)
	_spawned.append(cart)
	await _wait(8)
	(sys.get_model() as RetroSystemModelArcadeCabinet).set_lid_angle_deg(90.0)
	_slot_of(sys).pick_up_object(cart)
	await _wait(6)
	_ok(listener.asked.is_empty(), "media_ask: a cabinet told 'always off' asks for nothing")
	await _clear()
	listener.queue_free()
	_remove_tree(dir)


# ── keep ────────────────────────────────────────────────────────────────────

func _group_keep() -> void:
	AppPrefs.arcade_attract_mode = false
	var sys := await _cabinet()
	var sp := ScenePersistence.new("arcade_attract_tests")
	var entry := _saved(sp)
	_ok(not entry.has("attract"), "keep: a cabinet that follows the global option adds nothing to the room file")
	sys.attract_override = ArcadeAttract.OVERRIDE_ON
	entry = _saved(sp)
	_ok(int(entry.get("attract", -1)) == ArcadeAttract.OVERRIDE_ON, "keep: one forced on is saved as such")
	sys.attract_override = ArcadeAttract.OVERRIDE_OFF
	entry = _saved(sp)
	_ok(int(entry.get("attract", -1)) == ArcadeAttract.OVERRIDE_OFF, "keep: and one forced off")
	var keep: Array[Dictionary] = []
	for o in sp._collect_objects(self):
		if o.get("type") == "system" or str(o.get("type", "")).begins_with("arcade_bay_"):
			keep.append(o)
	await _clear()
	var made := sp.instantiate_objects(self, keep)
	var back: RetroSystem = null
	for k in made:
		if made[k] is RetroSystem:
			back = made[k]
			_spawned.append(back)
	await _wait(6)
	_ok(back != null and back.attract_override == ArcadeAttract.OVERRIDE_OFF, "keep: and it comes back as it was left")
	await _clear()


func _saved(sp: ScenePersistence) -> Dictionary:
	for o in sp._collect_objects(self):
		if o.get("type") == "system":
			return o
	return {}


# ── panel ───────────────────────────────────────────────────────────────────

func _group_panel() -> void:
	var opts := preload("res://Scenes/UI/core_options_2d.tscn").instantiate() as CoreOptions2D
	add_child(opts)
	await get_tree().process_frame
	opts.populate_system(false, false, false, "", 0, -1.0, true, true, ArcadeAttract.OVERRIDE_ON)
	_ok(opts._attract_row.visible, "panel: the System tab shows the Attract Mode row for a cabinet")
	_ok(opts._attract_button.text == "Always on", "panel: reading what the cabinet has (%s)" % opts._attract_button.text)
	opts.populate_system(false, false, false, "", 0, -1.0, true, true, ArcadeAttract.OVERRIDE_FOLLOW)
	_ok(opts._attract_button.text == "Follow global", "panel: or that it follows the global option")
	var asked: Array[int] = []
	opts.attract_override_changed.connect(func(m: int) -> void: asked.append(m))
	opts._attract_button.pressed.emit()
	opts._attract_button.pressed.emit()
	opts._attract_button.pressed.emit()
	_ok(asked == [ArcadeAttract.OVERRIDE_ON, ArcadeAttract.OVERRIDE_OFF, ArcadeAttract.OVERRIDE_FOLLOW],
		"panel: pressing steps follow, on, off, follow (%s)" % str(asked))
	opts.populate_system(false, false, false)
	_ok(not opts._attract_row.visible, "panel: a machine that is not a cabinet has no such row")
	opts.queue_free()
	# The panel's signal reaches the machine.
	var sys := await _cabinet()
	sys.set_attract_override(ArcadeAttract.OVERRIDE_ON)
	_ok(sys.attract_override == ArcadeAttract.OVERRIDE_ON, "panel: the machine takes the override")
	sys.set_attract_override(99)
	_ok(sys.attract_override == ArcadeAttract.OVERRIDE_OFF, "panel: and keeps it to a value it knows")
	await _clear()
