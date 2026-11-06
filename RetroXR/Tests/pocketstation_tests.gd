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
const _DUP := "__PS_SELFTEST_DUP"
const _ORPHAN := "__PS_SELFTEST_ORPHAN"

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
	if _wants("core"):
		_test_core()
	if _wants("merge"):
		await _test_merge()
	if _wants("dock"):
		await _test_dock()
	if _wants("ids"):
		await _test_ids()
	if _wants("slot"):
		await _test_slot()
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
	var paths: Array[String] = [SramPaths.card_save_path("playstation", FIXTURE),
			PocketStation.PLAY_DIR.path_join("%s.mcr" % FIXTURE),
			PocketStation.PLAY_DIR.path_join("%s.base.mcr" % FIXTURE),
			PocketStation.PLAY_DIR.path_join("%s.mcr" % _ORPHAN)]
	paths.append_array(_kept_files())
	for p: String in paths:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	# The conflict case makes kept/; leave no empty folder of the suite's behind.
	var kept := ProjectSettings.globalize_path(PocketStation.PLAY_DIR.path_join("kept"))
	if DirAccess.dir_exists_absolute(kept) and DirAccess.get_files_at(kept).is_empty() 			and DirAccess.get_directories_at(kept).is_empty():
		DirAccess.remove_absolute(kept)


# ── core/ ─────────────────────────────────────────────────────────────────────

## libretro's .info pins pocketstation.bin to one md5, and the BIOS page called
## every other dump a wrong file -- but the retail J110 circulates as at least
## three files, and Pokket boots any of them (the overlay's header says why).
func _test_core() -> void:
	var reqs := FirmwareRequirements.for_core("pokket")
	_eq(reqs.size(), 1, "core/pokket asks for one file")
	var row: Dictionary = reqs[0] if not reqs.is_empty() else {}
	_eq(str(row.get("path", "")), PocketStation.BIOS_FILE, "core/the file its unit looks for")
	_eq(str(row.get("md5", "")), "", "core/with no md5, so a J110 that is not libretro's is not a wrong file")
	_ok(bool(row.get("optional", false)), "core/and optional, as libretro's entry has it")
	# Pokket's only options are its IR link's, which a single unit never loads.
	var defs := {"pokket_link_layout": 1, "pokket_link_audio": 2, "pokket_link_unit_b_id": 3, "pokket_other": 4}
	_eq(PocketStation.single_unit_options(defs).keys(), ["pokket_other"],
		"core/the panel offers none of the IR link's options, and keeps any other")


# ── merge/ ────────────────────────────────────────────────────────────────────

const _APP := "BISLPSP00000POCKET"
const _GAME := "BISLPS000001GAME"
const _OTHER := "BISLPS000002OTHER"


## A copy of `img` with one byte of a save's data changed: an edit its owner made.
static func _edited(img: PackedByteArray, save_name: String, value: int) -> PackedByteArray:
	var out := img.duplicate()
	var at := PS1Card.block_of(out, save_name)
	if at >= 0:
		out[at * PS1Card.BLOCK_SIZE + 0x200] = value
	return out


static func _body(img: PackedByteArray, save_name: String) -> PackedByteArray:
	return PocketStation._save_bytes(img, save_name)


## The card as a run started, an app and a game's save on it.
static func _base_card() -> PackedByteArray:
	return PS1Card.insert_save(PS1Card.insert_save(PS1Card.blank_image(), _mcs(_APP, true)),
		_mcs(_GAME, false))


func _test_merge() -> void:
	var base := _base_card()
	# The run edits its app; meanwhile a console saves the game and adds a save.
	var played := _edited(base, _APP, 0x11)
	var now := PS1Card.insert_save(_edited(base, _GAME, 0x22), _mcs(_OTHER, false))
	var m := PocketStation.merge_card(base, played, now)
	var out: PackedByteArray = m["image"]
	_ok(PS1Card.is_card_image(out), "merge/the merge is a card")
	_ok(_body(out, _APP) == _body(played, _APP), "merge/the run's edit to its app goes back")
	_ok(_body(out, _GAME) == _body(now, _GAME), "merge/the save a console made while it ran stays")
	_ok(PS1Card.block_of(out, _OTHER) >= 0, "merge/and so does one it added")
	_eq((m["conflicts"] as Array).size(), 0, "merge/with nothing both changed")
	var both := PocketStation.merge_card(base, _edited(base, _GAME, 0x33), now)
	_eq(both["conflicts"], [_GAME], "merge/a save both changed is a conflict")
	_ok(_body(both["image"], _GAME) == _body(now, _GAME), "merge/and the card keeps its copy")
	var no_game := PS1Card.delete_save(base, PS1Card.block_of(base, _GAME))
	_eq(PS1Card.block_of(PocketStation.merge_card(base, no_game, base)["image"], _GAME), -1,
		"merge/a save the run deleted goes")
	_eq(PS1Card.block_of(PocketStation.merge_card(base, base, no_game)["image"], _GAME), -1,
		"merge/and one deleted from the card while the run left it alone does not come back")

	# Through the unit: the starting card beside the scratch, the card written meanwhile.
	var ps := _unit(FIXTURE)
	await get_tree().process_frame
	var path := SramPaths.card_save_path("playstation", FIXTURE)
	var scratch := PocketStation.PLAY_DIR.path_join("%s.mcr" % FIXTURE)
	var base_path := PocketStation.PLAY_DIR.path_join("%s.base.mcr" % FIXTURE)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PocketStation.PLAY_DIR))
	AtomicFile.write_bytes(path, now, "pocketstation_tests")
	AtomicFile.write_bytes(base_path, base, "pocketstation_tests")
	AtomicFile.write_bytes(scratch, played, "pocketstation_tests")
	ps._carry_back()
	var card := FileAccess.get_file_as_bytes(path)
	_ok(_body(card, _APP) == _body(played, _APP), "merge/carried back, the run's progress is on the card")
	_ok(_body(card, _GAME) == _body(now, _GAME) and PS1Card.block_of(card, _OTHER) >= 0,
		"merge/and the saves written to the card while it ran survive it")
	_ok(not FileAccess.file_exists(scratch) and not FileAccess.file_exists(base_path),
		"merge/the scratch and its starting card are cleared")
	# Both changed the game's save: the card keeps its copy, the run's is set aside.
	AtomicFile.write_bytes(path, now, "pocketstation_tests")
	AtomicFile.write_bytes(base_path, base, "pocketstation_tests")
	AtomicFile.write_bytes(scratch, _edited(played, _GAME, 0x33), "pocketstation_tests")
	ps._carry_back()
	_ok(_body(FileAccess.get_file_as_bytes(path), _GAME) == _body(now, _GAME),
		"merge/a save both changed keeps the card's copy")
	_ok(not _kept_files().is_empty() and not FileAccess.file_exists(scratch),
		"merge/and the run's is kept aside, not lost, nor left to block the next start", str(_kept_files()))
	# A run still waiting to go back is never written over, nor renamed out from under.
	AtomicFile.write_bytes(scratch, played, "pocketstation_tests")
	_ok(not ps._boot_card("t"), "merge/the next start refuses to write over a run still waiting")
	_ok(not ps.rename_blocker().is_empty(), "merge/and the card cannot be renamed under it", ps.rename_blocker())
	DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch))
	_eq(ps.rename_blocker(), "", "merge/with nothing waiting it can")
	ps.queue_free()
	await get_tree().process_frame


func _kept_files() -> Array[String]:
	var out: Array[String] = []
	var dir := PocketStation.PLAY_DIR.path_join("kept")
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir)):
		return out
	for f: String in DirAccess.get_files_at(ProjectSettings.globalize_path(dir)):
		if f.begins_with(FIXTURE):
			out.append(dir.path_join(f))
	return out


# ── dock/ ─────────────────────────────────────────────────────────────────────

## The unit seated in a PlayStation. The console is marked powered with no core, so
## its card controller hot-swaps and reports the card in use exactly as a running one.
func _test_dock() -> void:
	var sys := (load("res://Scenes/Objects/system.tscn") as PackedScene).instantiate() as RetroSystem
	sys.systemid = "psx"
	add_child(sys)
	sys.freeze = true
	for i in 10:
		await get_tree().physics_frame
	var slot: XRToolsSnapZone = sys.memcard_slots()[0]
	var ps := _unit(FIXTURE)
	ps.global_position = slot.global_position + Vector3(0, 0.3, 0.3)
	await get_tree().process_frame
	var path := SramPaths.card_save_path("playstation", FIXTURE)
	var scratch := PocketStation.PLAY_DIR.path_join("%s.mcr" % FIXTURE)
	var base_path := PocketStation.PLAY_DIR.path_join("%s.base.mcr" % FIXTURE)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PocketStation.PLAY_DIR))
	var base := _base_card()
	var played := _edited(base, _APP, 0x11)

	# Progress waiting from an earlier run: on the card BEFORE the console is handed it.
	AtomicFile.write_bytes(path, base, "pocketstation_tests")
	AtomicFile.write_bytes(base_path, base, "pocketstation_tests")
	AtomicFile.write_bytes(scratch, played, "pocketstation_tests")
	sys.is_powered_on = true
	var handed: Array = []
	var look := func(_what: Node3D) -> void: handed.append(FileAccess.get_file_as_bytes(path))
	slot.has_picked_up.connect(look)
	slot.pick_up_object(ps)
	slot.has_picked_up.disconnect(look)
	_ok(ps.is_seated(), "dock/it seats in the slot")
	_ok(handed.size() == 1 and _body(handed[0], _APP) == _body(played, _APP),
		"dock/the console is handed the card with the waiting progress already on it")

	# Pulled with the console on, after the game saved into the card meanwhile: the
	# progress that waited goes back, and the game's save stays.
	var now := _edited(base, _GAME, 0x22)
	AtomicFile.write_bytes(path, now, "pocketstation_tests")
	AtomicFile.write_bytes(base_path, base, "pocketstation_tests")
	AtomicFile.write_bytes(scratch, played, "pocketstation_tests")
	ps._carry_back()
	_ok(FileAccess.file_exists(scratch), "dock/seated in a running console, progress waits")
	slot.drop_object()
	await get_tree().process_frame
	await get_tree().process_frame
	var card := FileAccess.get_file_as_bytes(path)
	_ok(not FileAccess.file_exists(scratch) and _body(card, _APP) == _body(played, _APP),
		"dock/pulled out with the console on, the waiting progress goes back")
	_ok(_body(card, _GAME) == _body(now, _GAME), "dock/and the game's save made while it was in stays")

	# Switched off by being seated (the core still unloading): the carry-back may write
	# under the powered console once, at once, while the card is still the one it read.
	ps.global_position = slot.global_position + Vector3(0, 0.3, 0.3)
	await get_tree().physics_frame
	AtomicFile.write_bytes(path, base, "pocketstation_tests")
	AtomicFile.write_bytes(base_path, base, "pocketstation_tests")
	AtomicFile.write_bytes(scratch, played, "pocketstation_tests")
	ps._carry_pending = true
	slot.pick_up_object(ps)
	ps._carry_pending = false
	_ok(_body(FileAccess.get_file_as_bytes(path), _APP) == _body(base, _APP),
		"dock/seated while switching off, the console first reads the card as it was")
	var was := ps._seated_at_msec
	ps._seated_at_msec = Time.get_ticks_msec() - 10000
	ps._carry_back(true)
	_ok(FileAccess.file_exists(scratch), "dock/long after the seat it waits, as the game may have saved")
	ps._seated_at_msec = was
	AtomicFile.write_bytes(path, now, "pocketstation_tests")
	ps._carry_back(true)
	_ok(FileAccess.file_exists(scratch), "dock/and so it does when the card already changed")
	AtomicFile.write_bytes(path, base, "pocketstation_tests")
	ps._carry_back(true)
	_ok(not FileAccess.file_exists(scratch)
		and _body(FileAccess.get_file_as_bytes(path), _APP) == _body(played, _APP),
		"dock/moments after, with the card untouched, the progress goes on under the console")
	slot.drop_object()
	sys.is_powered_on = false
	await get_tree().process_frame
	ps.queue_free()
	sys.queue_free()
	await get_tree().process_frame


# ── ids/ ──────────────────────────────────────────────────────────────────────

## A new card never takes a name a card in the room already answers to, nor one a
## PocketStation's waiting run is filed under.
func _test_ids() -> void:
	var cards: Array[Node] = []
	for i in 2:
		var c := (load("res://Scenes/Objects/media/memory_card.tscn") as PackedScene).instantiate()
		c.set("card_label", _DUP)
		add_child(c)
		cards.append(c)
	await get_tree().process_frame
	_ok(str(cards[0].get("card_id")) != str(cards[1].get("card_id")),
		"ids/two new cards in the room never share a name, image or not",
		"%s / %s" % [cards[0].get("card_id"), cards[1].get("card_id")])
	for c in cards:
		c.queue_free()
	var scratch := PocketStation.PLAY_DIR.path_join("%s.mcr" % _ORPHAN)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PocketStation.PLAY_DIR))
	AtomicFile.write_bytes(scratch, PS1Card.blank_image(), "pocketstation_tests")
	var ps := SCENE.instantiate() as PocketStation
	ps.card_label = _ORPHAN
	add_child(ps)
	ps.freeze = true
	_ok(ps.card_id != _ORPHAN, "ids/a new unit does not take the id of a run left waiting by one gone",
		ps.card_id)
	ps.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(scratch))
	await get_tree().process_frame


# ── slot/ ─────────────────────────────────────────────────────────────────────

## A seated PocketStation is the core's to answer as one (pcsx_rearmed's per-slot
## device option); a plain card, an empty slot or another core is a card.
func _test_slot() -> void:
	_eq(ForcedCoreOptions.pocketstation_slots("pcsx_rearmed", "psx", [true, false]),
		{"pcsx_rearmed_memcard1_device": "pocketstation", "pcsx_rearmed_memcard2_device": "card"},
		"slot/a PocketStation in slot 1 is pinned as one, slot 2 a card")
	_eq(ForcedCoreOptions.pocketstation_slots("pcsx_rearmed", "psx", [false, false]),
		{"pcsx_rearmed_memcard1_device": "card", "pcsx_rearmed_memcard2_device": "card"},
		"slot/and pinned back to a card when it is pulled")
	_eq(ForcedCoreOptions.pocketstation_slots("mednafen_psx_hw", "psx", [true, true]), {},
		"slot/no other core is told anything")
	_eq(ForcedCoreOptions.pocketstation_slots("pcsx_rearmed", "ps2", [true]), {},
		"slot/nor another console")
	var sys := (load("res://Scenes/Objects/system.tscn") as PackedScene).instantiate() as RetroSystem
	sys.systemid = "psx"
	add_child(sys)
	sys.freeze = true
	for i in 6:
		await get_tree().physics_frame
	var ps := _unit(FIXTURE)
	ps.global_position = sys.memcard_slots()[0].global_position + Vector3(0, 0.3, 0.3)
	await get_tree().physics_frame
	sys.memcard_slots()[0].pick_up_object(ps)
	_eq(str(sys.all_forced_options("pcsx_rearmed").get("pcsx_rearmed_memcard1_device", "")), "pocketstation",
		"slot/seated in a PlayStation, its run pins slot 1 a PocketStation")
	sys.memcard_slots()[0].drop_object()
	await get_tree().process_frame
	_eq(str(sys.all_forced_options("pcsx_rearmed").get("pcsx_rearmed_memcard1_device", "")), "card",
		"slot/and pulled, a card again")
	ps.queue_free()
	sys.queue_free()
	await get_tree().process_frame
