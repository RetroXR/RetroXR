## seventh_gen_tests — the PlayStation 3 (rpcs3) and the Xbox 360 (xenia_edge):
## that each is registered as a machine, and that a library of PS3 FOLDER dumps
## is one row a game.
##
## No core and no game. Both cores are the buildbot's own builds, so nothing here
## is about where they come from: the download manager lists every
## `*_libretro*.zip` the buildbot serves. What a new system can be silently
## absent from is the tables, and each of those is asserted.
##
## folders/ is the one bug this addition had to fix rather than fill in: every
## PS3 disc dump is a folder holding a file called `PS3_DISC.SFB`, so keyed by
## the file's stem (as every other library is) a shelf of forty PS3 games was ONE
## row, and every scrape wrote its art over the last one's.
##
##   "$godot" --headless --path RetroXR res://Tests/seventh_gen_tests.tscn
extends "res://Tests/test_suite.gd"

## Cases in this file, NOT counting the guard below -- it is checked before it
## has recorded itself. Bump when adding.
const EXPECTED_CASES := 66

var _dir := ""


func _ready() -> void:
	suite_tag = "seventh_gen"
	get_tree().create_timer(30.0).timeout.connect(func() -> void:
		push_error("[seventh_gen] TIMEOUT")
		get_tree().quit(1))
	_dir = OS.get_user_data_dir().path_join("__seventh_gen_selftest")
	_remove_tree(_dir)
	DirAccess.make_dir_recursive_absolute(_dir)

	_group_ps3()
	_group_xbox360()
	_group_folders()

	_eq(_case_count(), EXPECTED_CASES, "suite/every case ran")
	_remove_tree(_dir)
	_finish()


# ── ps3/ ──────────────────────────────────────────────────────────────────────

func _group_ps3() -> void:
	var info := SystemInfo.for_system("ps3")
	_ok(info != null, "ps3/there is a descriptor")
	_eq(info.systemid if info != null else "", "ps3", "ps3/named for ES-DE's folder")
	_eq(info.native_ports if info != null else -1, 7, "ps3/seven pads, as the console paired")
	_eq(int(info.media_type) if info != null else -1, int(SystemInfo.MediaType.DISC_INSERT),
		"ps3/a disc drawn in through a slot")
	_ok(info != null and info.folder_content, "ps3/and a game can be a FOLDER")

	_ok(MediaDimensions.is_disc_system("ps3"), "ps3/it takes discs, not cartridges")
	_eq(MediaDimensions.disc_loader("ps3"), MediaDimensions.LOADER_SLOT,
		"ps3/through the slot loader, as the descriptor says")
	_ok(not MediaDimensions.has_front_tray("ps3"), "ps3/with no tray")
	_eq(float(MediaDimensions.disc_finish("ps3")["pitch"]), MediaDimensions.PITCH_BD,
		"ps3/and the discs are Blu-rays")

	_eq(ScreenscraperSystems.get_systemeid("ps3"), 59, "ps3/ScreenScraper knows it as 59")
	_ok(SystemIcons.has_icon("ps3"), "ps3/the Systematic console art is here")
	_ok(SystemIcons.has_content_icon("ps3"), "ps3/and its disc")
	_eq(CoreRecommendations.core_for("ps3"), "rpcs3", "ps3/rpcs3 is the recommended core")
	_ok(not RaConsoles.is_supported("ps3"), "ps3/RetroAchievements has no PS3")
	_ok(RaConsoles.UNSUPPORTED.has("ps3"), "ps3/and that was considered, not forgotten")
	_eq(RommPlatforms.systemid_for({"slug": "ps3", "fs_slug": "ps3"}), "ps3",
		"ps3/RomM's ps3 is the PS3")

	# The vendored .info says libretro's `playstation3`; SystemIds renames it.
	_eq(SystemIds.canonical("playstation3"), "ps3", "ps3/libretro's id reads as ours")
	var db := CoreInfoDatabase.shared()
	var entry: Dictionary = db.get_by_core_name("rpcs3")
	_eq(str(entry.get("systemid", "")), "ps3", "ps3/the core's .info files it under ps3")
	var exts := db.extensions_for_systemid("ps3")
	_ok(exts.has("iso") and exts.has("pkg") and exts.has("sfb") and exts.has("sfo"),
		"ps3/an image, a package, a disc dump and an installed game all load", ", ".join(exts))

	# The core is handed system/rpcs3/ and looks for the PUP directly in it (or in
	# a nested rpcs3/, which it would be handed as system/rpcs3/rpcs3/). A path
	# with a folder in it would resolve somewhere the core never looks.
	var firmware := FirmwareRequirements.for_core("rpcs3")
	_eq(firmware.size(), 1, "ps3/one firmware row: the system software")
	var pup: Dictionary = firmware[0] if not firmware.is_empty() else {}
	_eq(str(pup.get("path", "")), "PS3UPDAT.PUP", "ps3/PS3UPDAT.PUP, in no folder")
	_ok(not bool(pup.get("optional", true)), "ps3/and required: the core boots nothing without it")
	_ok(FirmwareRequirements.destination("rpcs3", "PS3UPDAT.PUP").simplify_path()
		.ends_with("system/rpcs3/PS3UPDAT.PUP"), "ps3/so it lands where the core looks",
		FirmwareRequirements.destination("rpcs3", "PS3UPDAT.PUP"))
	# No row is a claim nobody has measured: the XMB is not known to come up with
	# nothing in the slot. A row goes in with the probe that shows it.
	_ok(BiosBoot.entry("rpcs3", "ps3").is_empty(), "ps3/and it is not switched on empty")
	_ok(CoreSources.is_hidden_on("rpcs3", "Android"), "ps3/desktop only: no row on a Quest")
	_ok(not CoreSources.is_hidden_on("rpcs3", "Windows") and not CoreSources.is_hidden_on("rpcs3", "Linux"),
		"ps3/and offered on the desktops")
	_ok(not CoreSources.has("rpcs3"), "ps3/the buildbot's build, not one of ours")


# ── xbox360/ ──────────────────────────────────────────────────────────────────

func _group_xbox360() -> void:
	var info := SystemInfo.for_system("xbox360")
	_ok(info != null, "xbox360/there is a descriptor")
	_eq(info.native_ports if info != null else -1, 4, "xbox360/four pads")
	_eq(int(info.media_type) if info != null else -1, int(SystemInfo.MediaType.DISC_TRAY),
		"xbox360/out of a disc tray")
	_ok(info != null and not info.folder_content, "xbox360/one game, one file")

	_ok(MediaDimensions.is_disc_system("xbox360"), "xbox360/it takes discs")
	_ok(MediaDimensions.has_front_tray("xbox360"), "xbox360/out of a tray in the front")
	_eq(MediaDimensions.disc_loader("xbox360"), MediaDimensions.LOADER_TRAY,
		"xbox360/which is still a tray to the loader")
	_eq(float(MediaDimensions.disc_finish("xbox360")["pitch"]), MediaDimensions.PITCH_DVD,
		"xbox360/and the discs are DVDs")

	_eq(ScreenscraperSystems.get_systemeid("xbox360"), 33, "xbox360/ScreenScraper knows it as 33")
	_ok(SystemIcons.has_icon("xbox360"), "xbox360/the Systematic console art is here")
	_ok(SystemIcons.has_content_icon("xbox360"), "xbox360/and its disc")
	_eq(CoreRecommendations.core_for("xbox360"), "xenia_edge",
		"xbox360/xenia_edge is the recommended core")
	_ok(RaConsoles.UNSUPPORTED.has("xbox360") and not RaConsoles.is_supported("xbox360"),
		"xbox360/RetroAchievements has none, and that was considered")
	_eq(RommPlatforms.systemid_for({"slug": "xbox360", "fs_slug": "xbox-360"}), "xbox360",
		"xbox360/RomM's 360 is the 360")
	_eq(RommPlatforms.systemid_for({"slug": "xbox", "fs_slug": "xbox"}), "xbox",
		"xbox360/and the original Xbox is still the original")

	_eq(SystemIds.canonical("xbox_360"), "xbox360", "xbox360/libretro's id reads as ours")
	var db := CoreInfoDatabase.shared()
	_eq(str(db.get_by_core_name("xenia_edge").get("systemid", "")), "xbox360",
		"xbox360/the core's .info files it under xbox360")
	var exts := db.extensions_for_systemid("xbox360")
	_ok(exts.has("iso") and exts.has("xex"), "xbox360/an image and an executable load",
		", ".join(exts))
	# xemu's .iso must not become a 360 game, nor the reverse: each system's
	# extensions are its own cores'.
	_ok(not db.extensions_for_systemid("xbox").has("xex"), "xbox360/and no .xex is offered to xemu")
	_ok(FirmwareRequirements.for_core("xenia_edge").is_empty(), "xbox360/no firmware to install")
	_ok(CoreSources.is_hidden_on("xenia_edge", "Android")
		and not CoreSources.is_hidden_on("xenia_edge", "Windows"), "xbox360/desktop only")
	_ok(not CoreSources.active_core_names().has("xenia_edge"),
		"xbox360/and never probed as a release of ours")
	# The core's default ends the process on the first unimplemented instruction;
	# here that process is the room. Asked through all(), the run's real entry.
	var none: Array[bool] = []
	var pins := ForcedCoreOptions.all("xenia_edge", "xbox360", "game.iso", [], "", none, "")
	_eq(str(pins.get("xenia_break_on_unimplemented_instructions", "")), "disabled",
		"xbox360/a missing instruction never ends the app")
	_ok(not ForcedCoreOptions.all("rpcs3", "ps3", "game.iso", [], "", none, "")
		.has("xenia_break_on_unimplemented_instructions"), "xbox360/and only Xenia is told")


# ── folders/ ──────────────────────────────────────────────────────────────────

func _group_folders() -> void:
	_eq(RomLibrary.content_stem("Uncharted (USA)/PS3_DISC.SFB"), "Uncharted (USA)",
		"folders/a disc dump is named for its folder")
	_eq(RomLibrary.content_stem("C:/roms/ps3/BLUS30001/PARAM.SFO"), "BLUS30001",
		"folders/so is an installed game")
	_eq(RomLibrary.content_stem("/r/ps3/Demon's Souls/PS3_GAME/USRDIR/EBOOT.BIN"),
		"Demon's Souls", "folders/climbing out of PS3_GAME/USRDIR to the game's own")
	_eq(RomLibrary.content_stem("/r/ps3/Game (USA).iso"), "Game (USA)",
		"folders/an image keeps its own stem")
	_eq(RomLibrary.content_stem("/r/scummvm/Monkey Island/monkey1.scummvm"), "monkey1",
		"folders/and so does a marker named for its game")
	_eq(RomLibrary.content_stem("PS3_DISC.SFB"), "PS3_DISC",
		"folders/a bare marker with no folder keeps its stem")

	# A shelf of two disc dumps, an installed game and an image beside them.
	_make_file("Uncharted (USA)/PS3_DISC.SFB")
	_make_dir("Uncharted (USA)/PS3_GAME")
	# An update package sitting in the dump: a marker the core declares, and the
	# wrong one to hand it. Named to sort AHEAD of PS3_DISC.SFB and written first,
	# so a scan that takes the first match takes it on an alphabetical directory
	# order (NTFS) and on one that follows creation.
	_make_file("Motorstorm (USA)/0_update.pkg")
	_make_file("Motorstorm (USA)/PS3_DISC.SFB")
	_make_file("BLUS30001/PARAM.SFO")
	_make_file("Resistance (USA).iso")

	var exts := CoreInfoDatabase.shared().extensions_for_systemid("ps3")
	var subdirs: Array[String] = []
	subdirs.assign(DirAccess.get_directories_at(_dir))
	var found := RomLibrary._scan_content_folders(_dir, subdirs, exts, [] as Array[String])
	var by_label: Dictionary = {}
	for row: Dictionary in found:
		by_label[str(row["label"])] = str(row["path"])
	_eq(found.size(), 3, "folders/each game folder is one row")
	_ok(str(by_label.get("Motorstorm (USA)", "")).ends_with("PS3_DISC.SFB"),
		"folders/and the disc's own marker beats an update package beside it",
		str(by_label.get("Motorstorm (USA)", "")))
	_ok(str(by_label.get("BLUS30001", "")).ends_with("PARAM.SFO"),
		"folders/an installed game is found by its PARAM.SFO")

	var rows: Array[Dictionary] = []
	rows.assign(found)
	rows.append({"path": _dir.path_join("Resistance (USA).iso"), "label": "Resistance (USA)"})
	var keyed := RomLibrary.index_by_basename(rows, exts)
	_eq(keyed.size(), 4, "folders/four games are four library rows, not two")
	_ok(keyed.has("uncharted (usa)") and keyed.has("motorstorm (usa)"),
		"folders/each keyed by its folder, which is what a RomM fs_name says",
		", ".join(PackedStringArray(keyed.keys())))
	_ok(not keyed.has("ps3_disc"), "folders/and none by the marker every dump shares")

	# ScreenScraper finds a folder dump by NAME: the marker's hash is every dump's.
	_eq(ScreenscraperClient.romnom_for(_dir.path_join("Uncharted (USA)/PS3_DISC.SFB")),
		"Uncharted (USA)", "folders/a dump is scraped under its folder's name")
	_eq(ScreenscraperClient.romnom_for(_dir.path_join("Resistance (USA).iso")),
		"Resistance (USA).iso", "folders/and an image under its file name, as before")

	# The scraped art follows the same name, so two games stop sharing one box.
	_eq(RomLibrary.scraped_manual_path("ps3", "Uncharted (USA)/PS3_DISC.SFB").get_file(),
		"Uncharted (USA).pdf", "folders/a manual is looked for under the game's name")


func _make_dir(rel: String) -> void:
	DirAccess.make_dir_recursive_absolute(_dir.path_join(rel))


func _make_file(rel: String) -> void:
	var path := _dir.path_join(rel)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[seventh_gen] could not write %s" % path)
		return
	f.store_string("x")
	f.close()


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for d: String in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(d))
	for n: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(n))
	DirAccess.remove_absolute(path)
