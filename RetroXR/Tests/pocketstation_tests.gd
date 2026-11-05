## PocketStation self-tests — the PlayStation card that is also a handheld.
##
## Where it is spawned and how it saves, the frame it seats in (a card mates along -Z,
## and this one has its button end there), the buttons a press reaches, why it will not
## run (seated, no core, no BIOS), the apps on a card it offers to play, and the run's
## progress going back to the card.
##
## No core runs here: the device on Pokket is a probe's (and a headset's) to show.
##
##     "$godot" --headless --path RetroXR res://Tests/pocketstation_tests.tscn
##     "$godot" --headless --path RetroXR res://Tests/pocketstation_tests.tscn -- --only=carry
##
## Exits 0 when everything passes, 1 otherwise.
##
## Writes one fixture card into the player's real save/memcards/playstation/ and a
## scratch under user://pocketstation_play/, and removes both at each end.
extends "res://Tests/test_suite.gd"

const SCENE := preload("res://Scenes/Objects/peripherals/pocketstation.tscn")
const FIXTURE := "__POCKETSTATION_SELFTEST"

var _only := ""


func _ready() -> void:
	suite_tag = "pocketstation"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.substr(7)
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("[pocketstation] TIMEOUT")
		_clear_fixtures()
		get_tree().quit(1))
	_clear_fixtures()
	if _wants("catalog"):
		_test_catalog()
	if _wants("frame"):
		await _test_frame()
	if _wants("saved"):
		_test_saved()
	if _wants("controls"):
		await _test_controls()
	if _wants("seat"):
		await _test_seat()
	if _wants("apps"):
		_test_apps()
	if _wants("carry"):
		await _test_carry()
	if _wants("bios"):
		_test_bios()
	_clear_fixtures()
	await _settle_warm()
	_finish()


func _wants(group: String) -> bool:
	return _only.is_empty() or _only == group


func _settle_warm() -> void:
	for i in range(1200):
		if ModelWarmer.is_warmed():
			return
		await get_tree().process_frame


func _unit(card_id := "") -> PocketStation:
	var ps := SCENE.instantiate() as PocketStation
	if not card_id.is_empty():
		ps.card_id = card_id
		ps.card_label = card_id
	add_child(ps)
	ps.freeze = true
	return ps


# ── catalog/ ──────────────────────────────────────────────────────────────────

func _test_catalog() -> void:
	var rows := SpawnCatalog.items_for("psx").filter(
		func(r: Dictionary) -> bool: return str(r.get("spawn", "")) == "pocketstation")
	_eq(rows.size(), 1, "catalog/the PlayStation's card offers one PocketStation")
	_ok(ScenePersistence.PLAIN_SCENES.has("pocketstation"), "catalog/and it is a restorable kind")
	var obj := ScenePersistence.instantiate("pocketstation")
	_ok(obj is PocketStation and obj is MemoryCard, "catalog/the token builds a PocketStation, which is a memory card")
	_eq(str(obj.get("family")) if obj != null else "", "playstation", "catalog/of the PlayStation's family")
	if obj != null:
		obj.free()
	_eq(CoreRecommendations.core_for("pocketstation"), "pokket", "catalog/its tile recommends the pokket core")


# ── frame/ ────────────────────────────────────────────────────────────────────

func _test_frame() -> void:
	var ps := _unit()
	await get_tree().process_frame
	var o := ps.global_position
	var edge := (ps.get_node("Model/CardEdge") as Node3D).global_position - o
	var hinge := (ps.get_node("Model/LidHinge") as Node3D).global_position - o
	var base := (ps.get_node("Model/BaseShell") as Node3D).global_position - o
	var screen := ps.get_node("Model/LidHinge/Screen") as Node3D
	var ir := (ps.get_node("Model/LidHinge/IrWindow") as Node3D).global_position - o
	# A slot seats a card's origin at its mouth and the card goes in along -Z.
	_ok(edge.z < -0.026 and edge.z > -0.030, "frame/the card edge leads along -Z, 28 mm in", "z %.4f" % edge.z)
	_ok(ir.z > 0.03, "frame/and the infrared end stands out of the slot", "z %.4f" % ir.z)
	_ok(hinge.z > 0.0 and hinge.z < 0.004, "frame/the lid's hinge just outside the mouth", "z %.4f" % hinge.z)
	_ok(absf(base.y) < 0.0005, "frame/the base is centred on the slot's axis", "y %.4f" % base.y)
	_ok(screen.global_position.y - o.y > 0.006 and screen.global_basis.y.dot(Vector3.UP) > 0.99,
		"frame/the screen is on top of the lid, facing up")
	var label := ps.get_node("CardLabel") as Label3D
	_ok(label.global_basis.z.dot(Vector3.DOWN) > 0.99, "frame/the name is on the back, facing down",
		str(label.global_basis.z))
	_ok(label.global_basis.y.dot(Vector3.BACK) > 0.99, "frame/reading up toward the infrared end",
		str(label.global_basis.y))
	ps.queue_free()
	await get_tree().process_frame


# ── saved/ ────────────────────────────────────────────────────────────────────

func _test_saved() -> void:
	var store := ScenePersistence.new()
	var ps := SCENE.instantiate() as PocketStation
	ps.card_id = "POCKETSTATION 7"
	ps.card_label = "POCKETSTATION 7"
	# In the tree: a save reads where the thing is.
	add_child(ps)
	var entry := store.serialize_node(ps, 1, {ps: 1})
	_eq(str(entry.get("type", "")), "pocketstation", "saved/it saves as itself, not as a plain card")
	_eq(str(entry.get("card_id", "")), "POCKETSTATION 7", "saved/with its card id")
	var back := store.deserialize_object(entry) as PocketStation
	_ok(back != null and back.card_id == "POCKETSTATION 7" and back.card_label == "POCKETSTATION 7",
		"saved/and comes back the same unit, holding the same card")
	ps.free()
	if back != null:
		back.free()


# ── controls/ ─────────────────────────────────────────────────────────────────

func _test_controls() -> void:
	_eq(PocketStation._CONTROLS.map(func(c: Array) -> int: return int(c[1])),
		[ControllerBindings.JOYPAD_UP, ControllerBindings.JOYPAD_DOWN, ControllerBindings.JOYPAD_LEFT,
		ControllerBindings.JOYPAD_RIGHT, ControllerBindings.JOYPAD_A],
		"controls/up, down, left, right and action are the pad's d-pad and A, as Pokket reads them")
	var ps := _unit()
	await get_tree().process_frame
	var action := ps.get_node("Model/ButtonAction") as Node3D
	var up := ps.get_node("Model/ButtonUp") as Node3D
	var rest_a := action.position
	var rest_u := up.position
	ps.set_input(1 << ControllerBindings.JOYPAD_A)
	for i in 20:
		await get_tree().process_frame
	_ok(action.position.y < rest_a.y - PocketStation.PRESS_DEPTH * 0.8, "controls/A sinks the action button into the base",
		"%.5f -> %.5f" % [rest_a.y, action.position.y])
	_ok(up.position.is_equal_approx(rest_u), "controls/and leaves the others where they were")
	ps.set_input(0)
	for i in 30:
		await get_tree().process_frame
	_ok(action.position.distance_to(rest_a) < 0.0001, "controls/and it comes back up when let go")
	ps.queue_free()
	await get_tree().process_frame


# ── seat/ ─────────────────────────────────────────────────────────────────────

func _test_seat() -> void:
	_eq(SystemInfo.for_system("psx").card_family, "playstation", "seat/a PlayStation takes the family it is")
	_ok(SystemInfo.for_system("gc").card_family != "playstation", "seat/and a GameCube does not")
	var ps := _unit()
	await get_tree().process_frame
	var why := ps.standalone_blocker()
	# What stops it on this machine: the core, the BIOS, or nothing.
	if CoreDownloadManager.installed_core_lib(PocketStation.STANDALONE_CORE).is_empty():
		_ok(why.contains("Pokket core"), "seat/with no core it says to get one", why)
	elif not FileAccess.file_exists(ps.bios_path()):
		_ok(why.contains(PocketStation.BIOS_FILE), "seat/with no BIOS it names the file", why)
	else:
		_eq(why, "", "seat/loose, with its core and BIOS, nothing stops it")
	_ok(not ps.power_on(ps.image_path(), "x") or why.is_empty(), "seat/a refused start returns false")
	var zone := XRToolsSnapZone.new()
	add_child(zone)
	ps.grabbed.emit(ps, zone)
	_ok(ps.is_seated() and ps.standalone_blocker().begins_with("seated"), "seat/in a slot it is a card and will not run",
		ps.standalone_blocker())
	ps.released.emit(ps, zone)
	_ok(not ps.is_seated(), "seat/and out of it a handheld again")
	zone.queue_free()
	ps.queue_free()
	await get_tree().process_frame


# ── apps/ ─────────────────────────────────────────────────────────────────────

## A one-block save: directory entry, then a title frame; `app` marks it MCX0.
static func _mcs(name: String, app: bool) -> PackedByteArray:
	var frame := PackedByteArray()
	frame.resize(PS1Card.FRAME_SIZE)
	frame.fill(0)
	frame[0] = PS1Card.STATE_FIRST
	frame.encode_u32(4, PS1Card.BLOCK_SIZE)
	frame.encode_u16(8, PS1Card.LINK_NONE)
	var ascii := name.to_ascii_buffer()
	for i in ascii.size():
		frame[10 + i] = ascii[i]
	frame[PS1Card.FRAME_SIZE - 1] = PS1Card.frame_checksum(frame, 0)
	var block := PackedByteArray()
	block.resize(PS1Card.BLOCK_SIZE)
	block.fill(0)
	block[0] = 0x53
	block[1] = 0x43
	block[2] = 0x11
	block[3] = 1
	if app:
		var mcx := "MCX0".to_ascii_buffer()
		for i in 4:
			block[0x52 + i] = mcx[i]
	return frame + block


func _test_apps() -> void:
	var card := PS1Card.insert_save(PS1Card.blank_image(), _mcs("BISLPSP00000POCKET", true))
	card = PS1Card.insert_save(card, _mcs("BISLPS000001GAME", false))
	var saves := PS1Card.list_saves(card, false)
	_eq(saves.size(), 2, "apps/a card with an app and a game save")
	var by_name := {}
	for s: Dictionary in saves:
		by_name[str(s["name"])] = s
	_ok(bool(by_name.get("BISLPSP00000POCKET", {}).get("is_game", false)),
		"apps/the MCX0 save is a PocketStation app the panel offers to play")
	_ok(not bool(by_name.get("BISLPS000001GAME", {}).get("is_game", true)),
		"apps/and the game's save is not")
	var ps := SCENE.instantiate() as PocketStation
	ps.card_id = FIXTURE
	var games := ps.library_games()
	_ok(not games.is_empty() and str(games[0].get("path", "")) == ps.image_path()
		and str(games[0].get("tag", "")) == "this card", "apps/the Games tab starts with the unit's own card")
	ps.free()


# ── carry/ ────────────────────────────────────────────────────────────────────

func _test_carry() -> void:
	var ps := _unit(FIXTURE)
	await get_tree().process_frame
	var path := SramPaths.card_save_path("playstation", FIXTURE)
	var blank := PS1Card.blank_image()
	_ok(AtomicFile.write_bytes(path, blank, "pocketstation_tests"), "carry/a fixture card on the shelf")
	var played := PS1Card.insert_save(blank, _mcs("BISLPSP00000POCKET", true))
	var scratch := PocketStation.PLAY_DIR.path_join("%s.mcr" % FIXTURE)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PocketStation.PLAY_DIR))
	AtomicFile.write_bytes(scratch, played, "pocketstation_tests")
	ps._carry_back()
	_ok(FileAccess.get_file_as_bytes(path) == played, "carry/what the device wrote goes back to the card")
	_ok(not FileAccess.file_exists(scratch), "carry/and its scratch is cleared")
	var junk := PackedByteArray()
	junk.resize(1024)
	AtomicFile.write_bytes(scratch, junk, "pocketstation_tests")
	ps._carry_back()
	_ok(FileAccess.get_file_as_bytes(path) == played and FileAccess.file_exists(scratch),
		"carry/a scratch that is not a card is left where it is, and the card untouched")
	ps.queue_free()
	await get_tree().process_frame


func _clear_fixtures() -> void:
	for p: String in [SramPaths.card_save_path("playstation", FIXTURE),
			PocketStation.PLAY_DIR.path_join("%s.mcr" % FIXTURE)]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


# ── bios/ ─────────────────────────────────────────────────────────────────────

## libretro's .info pins pocketstation.bin to one md5, and the BIOS page called
## every other dump a wrong file -- but the retail J110 circulates as at least
## three files, and Pokket boots any of them (the overlay's header says why).
func _test_bios() -> void:
	var reqs := FirmwareRequirements.for_core("pokket")
	_eq(reqs.size(), 1, "bios/pokket asks for one file")
	var row: Dictionary = reqs[0] if not reqs.is_empty() else {}
	_eq(str(row.get("path", "")), PocketStation.BIOS_FILE, "bios/the file its unit looks for")
	_eq(str(row.get("md5", "")), "", "bios/with no md5, so a J110 that is not libretro's is not a wrong file")
	_ok(bool(row.get("optional", false)), "bios/and optional, as libretro's entry has it")
