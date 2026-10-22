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
	await _test_netplay_surface()
	_test_netplay_row()
	_test_core_source_and_info()
	_test_bios_extras_row()
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
	var mesh := (printer.get_node("PaperPivot/Paper/ButtonMesh") as MeshInstance3D).mesh as QuadMesh
	_ok(is_equal_approx(mesh.size.y, GbPrinter.STUB_LENGTH), "switched off, only the end of the roll shows")

	var img := Image.create(GbPrinterPaper.DOTS, 208, false, Image.FORMAT_RGB8)
	img.fill(Color.WHITE)
	var tex := ImageTexture.create_from_image(img)
	printer._lay_paper(tex, 208)
	_ok(is_equal_approx(mesh.size.y, 208 * GbPrinter.DOT_PITCH),
		"208 lines fed is 208 lines of paper (%.4f m)" % mesh.size.y)
	_ok(is_equal_approx(mesh.size.x, GbPrinter.PAPER_WIDTH), "38 mm wide")
	_ok(is_equal_approx(paper.position.y, mesh.size.y * 0.5),
		"standing up out of the slot, its newest line at the head")
	var pivot := printer.get_node("PaperPivot") as Node3D
	_ok(pivot.rotation.x < 0.0, "leaning back toward the roll cover, not over the front")
	printer._lay_paper(null, 0)
	_ok(is_equal_approx(mesh.size.y, GbPrinter.STUB_LENGTH), "torn off, the roll's end again")
	printer.free()


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
