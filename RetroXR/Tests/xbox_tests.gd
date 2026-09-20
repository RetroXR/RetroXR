## xbox_tests — the Xbox: that it is registered as a machine, and that a game's
## saves can be lifted off the hard disk xemu keeps them in.
##
## No core, no disc and no disk image: every fixture is built here. A qcow2 of
## an 8 GB disk whose only allocated clusters are a FATX header, one page of FAT
## and a handful of data clusters 2.9 GB in — which is also what makes it a test
## of the reader rather than of a copy: most of what it reads was never written
## and has to come back as zeros. File chains are FRAGMENTED on purpose (a gap
## after every cluster), so a reader that walks memory instead of the FAT reads
## the gap. The XISO's directory tree is rooted so that default.xbe is a LEFT
## turn away; a reader that scans entries in order never finds it.
##
## The torn/ group is the point of the validation in FatxVolume. The image is
## read while a parked core may still hold it, and what is read gets uploaded as
## a backup: each corruption here must make the WHOLE lift fail, never return the
## files it managed to read before the bad one.
##
##   "$godot" --headless --path RetroXR res://Tests/xbox_tests.tscn
extends Node

## Cases in this file, NOT counting the guard below -- it is checked before it
## has recorded itself. Bump when adding.
const EXPECTED_CASES := 167

const TITLE := "4d530004"
const OTHER_TITLE := "4d530051"
const CLUSTER := 0x4000            # FATX cluster: 32 sectors, what the kernel formats
const QCLUSTER := 0x10000          # qcow2 cluster
const BASE := XboxHddSaves.DATA_PARTITION_OFFSET
## Where cluster 1 starts: header, then a u32 FAT for the partition's 313,280
## clusters rounded up to 4 KB. Computed the way the volume computes it; the
## reader is checked against the FILES coming back, not against this number.
const DATA := BASE + 0x1000 + 0x132000

var _passed := 0
var _failed := 0
var _dir := ""

## The FATX fixture under construction: guest offset -> bytes, the FAT as
## cluster -> next, and the next free cluster.
var _extents: Dictionary = {}
var _fat: Dictionary = {}
var _free := 2
## Where things landed, for the torn/ cases to break: path -> {cluster, at, dir}.
var _placed: Dictionary = {}


func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		push_error("[xbox] TIMEOUT")
		get_tree().quit(1))
	_dir = OS.get_user_data_dir().path_join("__xbox_selftest")
	DirAccess.make_dir_recursive_absolute(_dir)

	_group_system()
	_group_sources()
	_group_qcow2()
	_group_fatx()
	_group_torn()
	_group_disc()
	_group_archive()
	_group_unit()
	await _group_slots()
	await _group_one_at_a_time()

	_eq(_passed + _failed, EXPECTED_CASES, "suite/every case ran")
	_cleanup()
	print("[xbox] %d checks, %d failed" % [_passed + _failed, _failed])
	print("[xbox] RESULT=%s" % ("PASS" if _failed == 0 else "FAIL"))
	get_tree().quit(1 if _failed > 0 else 0)


func _cleanup() -> void:
	for n: String in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute(_dir.path_join(n))
	DirAccess.remove_absolute(_dir)


func _ok(cond: bool, what: String, detail := "") -> void:
	if cond:
		_passed += 1
		print("[xbox] ok   %s" % what)
	else:
		_failed += 1
		print("[xbox] FAIL %s%s" % [what, "" if detail.is_empty() else "  -- " + detail])


func _eq(got: Variant, want: Variant, what: String) -> void:
	_ok(got == want, what, "got %s, want %s" % [got, want])


# ── system/ ───────────────────────────────────────────────────────────────────

## Everything that makes `xbox` a machine in the room. Each of these is a table
## a new system can be silently absent from: it would still appear, as a
## cartridge console with no box art whose BIOS tab says its files are missing.
func _group_system() -> void:
	var info := SystemInfo.for_system("xbox")
	_ok(info != null, "system/there is a descriptor")
	if info != null:
		_eq(info.native_ports, 4, "system/with the console's four ports")
		_eq(int(info.media_type), int(SystemInfo.MediaType.DISC_TRAY), "system/and a disc tray")
	else:
		_ok(false, "system/with the console's four ports")
		_ok(false, "system/and a disc tray")
	_ok(MediaDimensions.is_disc_system("xbox"), "system/it takes discs, not cartridges")
	_ok(MediaDimensions.has_front_tray("xbox"), "system/out of a tray in the front")
	_eq(MediaDimensions.disc_loader("xbox"), MediaDimensions.LOADER_TRAY,
		"system/which is still a tray to the loader")
	_eq(float(MediaDimensions.disc_finish("xbox")["pitch"]), MediaDimensions.PITCH_DVD,
		"system/and the discs are DVDs")

	_eq(ScreenscraperSystems.get_systemeid("xbox"), 32, "system/ScreenScraper knows it as 32")
	_ok(SystemIcons.has_icon("xbox"), "system/the Systematic console art is here")
	_ok(SystemIcons.has_content_icon("xbox"), "system/and its disc")
	_eq(CoreRecommendations.core_for("xbox"), "xemu", "system/xemu is the recommended core")
	_ok(not RaConsoles.is_supported("xbox"), "system/RetroAchievements has no Xbox")
	_ok(RaConsoles.UNSUPPORTED.has("xbox"), "system/and that was considered, not forgotten")

	# The overlay REPLACES the vendored entry, which describes an older port.
	var db := CoreInfoDatabase.shared()
	var entry: Dictionary = db.get_by_core_name("xemu")
	_eq(str(entry.get("systemid", "")), "xbox", "system/the core's .info files it under xbox")
	_ok(str(entry.get("display_name", "")).contains("retroXR"),
		"system/and it is OUR .info, not the vendored one", str(entry.get("display_name", "")))
	_ok(db.extensions_for_systemid("xbox").has("iso"), "system/so an .iso is an Xbox game")

	# The trap the overlay exists for. The core is handed system/xemu/ and looks
	# for its files directly in it; the fork's own .info says "xemu/<file>", for a
	# frontend with one shared system directory. Resolved here that would be
	# system/xemu/xemu/, where the core never looks.
	var firmware := FirmwareRequirements.for_core("xemu")
	_eq(firmware.size(), 4, "system/four firmware files")
	var nested := PackedStringArray()
	var required := PackedStringArray()
	for fw: Dictionary in firmware:
		if str(fw["path"]).contains("/"):
			nested.append(str(fw["path"]))
		if not bool(fw["optional"]):
			required.append(str(fw["path"]))
	_ok(nested.is_empty(), "system/none of them in a folder the core does not search",
		", ".join(nested))
	_ok(FirmwareRequirements.destination("xemu", "mcpx_1.0.bin").simplify_path()
		.ends_with("system/xemu/mcpx_1.0.bin"), "system/so the boot ROM lands beside the core's own",
		FirmwareRequirements.destination("xemu", "mcpx_1.0.bin"))
	_ok(not required.has("xbox_eeprom.bin") and required.has("xbox_hdd.qcow2"),
		"system/the disk is required and the EEPROM, which the core makes, is not",
		", ".join(required))

	_ok(XboxStorage.is_xbox_core("xemu"), "system/xemu is the core the one-at-a-time rule is about")
	_ok(not XboxStorage.is_xbox_core("pcsx2"), "system/and no other")

	# Switched on with an EMPTY tray. Every other console's BIOS screen is in the
	# firmware; an Xbox's is the dashboard on its hard disk, and with the stock
	# image that is a placeholder drawing one line of text — which is the machine
	# working. Without this row an empty Xbox refused to start at all, and a disc
	# sitting in an open tray got "close the tray" instead of the dashboard.
	var boot := BiosBoot.entry("xemu", "xbox")
	_ok(not boot.is_empty(), "empty/an Xbox knows how to start with nothing in it")
	_ok(BiosBoot.boots_with_no_content("xemu", "xbox"),
		"empty/by being handed no content at all, not a blank disc")
	_eq(BiosBoot.empty_media_extension("xemu", "xbox"), "",
		"empty/there being no such thing as a blank Xbox disc")
	_ok((boot.get("boot_rom", []) as Array).has("Complex_4627v1.03.bin"),
		"empty/and only once its flash BIOS is installed", str(boot.get("boot_rom", [])))

	# The verdict the power button reaches, called directly as its other cases
	# are: it is a table of decisions and reads no disk.
	var none: Array[Dictionary] = []
	var empty := RetroSystem._power_on_verdict("xemu", "xbox", "", none, "", true, true, "")
	_ok(bool(empty["start"]) and str(empty["rom"]).is_empty(),
		"empty/so it switches on with an empty tray, handed nothing")
	# The case the user met: a disc in a tray still open. Starting beats the
	# refusal, because that is what the hardware does — an open tray is a disc
	# the drive cannot read, which is the dashboard.
	var tray := RetroSystem._power_on_verdict("xemu", "xbox", "", none, "", true, true, "tray")
	_ok(bool(tray["start"]), "empty/and with the tray still open over a disc")
	# With no BIOS the row cannot help: can_boot_empty says no, so empty_ok is
	# false, and the machine asks for a game rather than starting into black.
	var no_bios := RetroSystem._power_on_verdict("xemu", "xbox", "", none, "", false, true, "")
	_eq(str(no_bios["title"]), "No game inserted",
		"empty/but with no BIOS it asks for a disc, as it always did")


# ── sources/ ──────────────────────────────────────────────────────────────────

## A core only we build: the buildbot lists no xemu, so there is no row for ours
## to replace and the download manager has to list it itself — and must never
## list one it knows no release of, which could only 404.
func _group_sources() -> void:
	_eq(CoreSources.branch_of("xemu"), "retroxr", "sources/xemu is built from a branch")
	_ok(CoreSources.is_released("xemu"), "sources/which has a release")
	_eq(CoreSources.source_url("xemu"), "https://github.com/RetroXR/xemu/tree/" + CoreSources.version_of("xemu"),
		"sources/so its source is the tag, not the branch")
	_ok(CoreSources.version_of("xemu").begins_with("retroxr-xemu-libretro-v"),
		"sources/named the way every fork's tag is", CoreSources.version_of("xemu"))
	_ok(not CoreSources.is_released("no_such_core"), "sources/a core this app knows no release of has none")
	_ok(CoreSources.is_released("dolphin") and CoreSources.branch_of("dolphin").is_empty(),
		"sources/where a released core is pinned by its tag")
	_ok(CoreSources.source_url("dolphin").ends_with("/tree/" + CoreSources.version_of("dolphin")),
		"sources/and its source is that tag")
	_eq(CoreSources.source_url("nestopia"), "", "sources/a buildbot core has no source of ours")

	# The buildbot lists no xemu, and ours is listed all the same, from the tag
	# this app knows, with our asset and our source.
	var mgr := CoreDownloadManager.new()
	var listing: Array[Dictionary] = [
		{"core_name": "wasm4", "filename": "wasm4_libretro.dll.zip", "remote_date": "2026-01-01 00:00"},
		{"core_name": "yabause", "filename": "yabause_libretro.dll.zip", "remote_date": "2026-01-01 00:00"},
	]
	var applied := mgr._apply_own_sources(listing)
	var names := PackedStringArray()
	var xemu_row: Dictionary = {}
	for e: Dictionary in applied:
		names.append(str(e["core_name"]))
		if str(e["core_name"]) == "xemu":
			xemu_row = e
	if CoreSources.has("xemu"):
		_ok(str(xemu_row.get("filename", "")) == CoreSources.asset_for("xemu")
			and str(xemu_row.get("remote_date", "")) == CoreSources.version_of("xemu")
			and str(xemu_row.get("source", "")) == "retroxr",
			"sources/a core the buildbot never built is listed from our release", str(xemu_row))
	else:
		# A platform we publish no xemu for has no asset to offer, and no row.
		_ok(xemu_row.is_empty(), "sources/a core the buildbot never built is listed from our release")
	var sorted_names := Array(names)
	sorted_names.sort()
	_ok(Array(names) == sorted_names, "sources/in its place in the list", ", ".join(names))
	# The version probe's answer goes through the same door, and adds no second row.
	var before := applied.size()
	CoreDownloadManager._list_own_core(applied, "xemu", "retroxr-xemu-libretro-v2")
	_eq(applied.size(), before, "sources/once")
	# What a core with NO known release gets, which is how this one began: a row
	# only when GitHub names a release, never before.
	# Its own list, not a copy of `listing`: _apply_own_sources returns the array it
	# was handed, so by now that one already holds xemu.
	var unreleased: Array[Dictionary] = [
		{"core_name": "wasm4", "filename": "wasm4_libretro.dll.zip", "remote_date": "2026-01-01 00:00"},
		{"core_name": "yabause", "filename": "yabause_libretro.dll.zip", "remote_date": "2026-01-01 00:00"},
	]
	CoreDownloadManager._list_own_core(unreleased, "xemu", "retroxr-xemu-libretro-v1")
	_eq(unreleased.size(), 3, "sources/the probe's answer is what lists a core nobody knew a release of")
	mgr.free()


# ── unit/ ─────────────────────────────────────────────────────────────────────

func _utf16(text: String) -> PackedByteArray:
	var out := PackedByteArray([0xff, 0xfe])
	out.append_array(text.to_utf16_buffer())
	return out


## One save as the archive a Memory Unit takes: the game's files and one folder.
func _save_archive(title_id: String, game: String, save_id: String, label: String,
		extra: Dictionary = {}) -> PackedByteArray:
	var files := {
		"UDATA/%s/TitleMeta.xbx" % title_id: _utf16("TitleName=%s
" % game),
		"UDATA/%s/%s/SaveMeta.xbx" % [title_id, save_id]: _utf16("Name=%s
" % label),
		"UDATA/%s/%s/game.sav" % [title_id, save_id]: _pattern(5000, 11),
	}
	for path: String in extra:
		files["UDATA/%s/%s/%s" % [title_id, save_id, path]] = extra[path]
	return XboxHddSaves.pack(files)


## The Memory Unit: an 8 MB FATX card RetroXR both reads AND writes, which the
## hard disk never is. The round trip is the oracle — a save put in must come
## back out as the same bytes — and the FatxVolume reader, already checked
## against a real disk, reads everything the writer wrote.
func _group_unit() -> void:
	var fmt := CardFormats.for_family("xbox_mu")
	_ok(fmt != null and fmt.device_home() == "controller", "unit/there is a Memory Unit family, and it lives in a controller")
	_eq(fmt.romm_systemid() if fmt != null else "", "xbox", "unit/whose saves are filed under the Xbox")
	_ok(CardFormats.for_path("save/memcards/xbox_mu/A.xmu") == fmt, "unit/and whose images are told by their extension")
	_eq(SystemInfo.for_system("xbox").card_slots, 0, "unit/the console itself has no slot for one")

	# What xemu's create_fatx_image writes, field for field; its volume id is
	# rand(), so the bytes cannot be pinned, only the structure.
	var blank := XboxMemoryUnit.blank_image(0x1234)
	_eq(blank.size(), 8 * 1024 * 1024, "unit/a new unit is 8 MB")
	_ok(blank.decode_u32(0) == 0x58544146 and blank.decode_u32(8) == 4 and blank.decode_u32(12) == 1
		and blank.decode_u16(16) == 0 and blank[18] == 0xff and blank[0xfff] == 0xff,
		"unit/with the superblock the core formats one with")
	_ok(blank.decode_u32(0x1000) == 0xfffffff8 and blank.slice(0x1004, 0x3000).count(0) == 0x1ffc,
		"unit/and its FAT: the root's one cluster, and nothing else")
	_ok(fmt.is_card_image(blank) and fmt.list_saves(blank).is_empty(), "unit/it is a card, and empty")
	_ok(not fmt.is_card_image(_pattern(8 * 1024 * 1024, 3)), "unit/8 MB of something else is not")
	var room := fmt.free_blocks(blank)
	_ok(room > 480 and room <= 512, "unit/with most of its 512 blocks free", str(room))

	var halo := _save_archive(TITLE, "Halo", "0A1B2C3D4E5F", "Silent Cartographer")
	_ok(fmt.is_save_file(halo), "unit/one save's archive is a save file")
	_eq(fmt.save_name(halo), "4d530004/0A1B2C3D4E5F", "unit/named for its game and its folder")
	var one := fmt.insert_save(blank, halo)
	_eq(one.size(), blank.size(), "unit/a save goes in")
	var saves := fmt.list_saves(one)
	_eq(saves.size(), 1, "unit/and is listed")
	if saves.size() == 1:
		_eq(str(saves[0]["title"]), "Silent Cartographer", "unit/by the name in its SaveMeta, UTF-16 and BOM and all")
		_eq(str(saves[0]["serial"]), TITLE, "unit/under its game's title id")
		_ok(fmt.extract_save(one, int(saves[0]["block"])) == halo, "unit/and comes back out byte for byte")
	else:
		for skipped: String in ["by the name in its SaveMeta, UTF-16 and BOM and all",
				"under its game's title id", "and comes back out byte for byte"]:
			_ok(false, "unit/" + skipped)
	_ok(fmt.free_blocks(one) < room, "unit/it takes room")
	_ok(fmt.insert_save(one, halo).is_empty(), "unit/the same save does not go in twice")

	# A second save of the SAME game finds the title's files already there.
	var second := _save_archive(TITLE, "Halo", "111111111111", "The Maw")
	var two := fmt.insert_save(one, second)
	_eq(fmt.list_saves(two).size(), 2, "unit/a second save of the game shares its title files")
	_ok(fmt.extract_save(two, fmt.block_of(two, "4d530004/111111111111")) == second,
		"unit/and is itself on the way out")
	# Counted in the directory itself: read back into a Dictionary, a TitleMeta
	# written twice is one key and looks exactly like one written once.
	var two_volume := FatxVolume.open(XboxRawImage.of(two), 0, two.size())
	var two_udata := two_volume.find(FatxVolume.ROOT_CLUSTER, "UDATA")
	var metas := 0
	for e: Dictionary in two_volume.list_dir(int(two_volume.find(int(two_udata["cluster"]), TITLE)["cluster"])):
		if str(e["name"]) == "TitleMeta.xbx":
			metas += 1
	_eq(metas, 1, "unit/with the game's title file on the unit once, not once a save")
	# Attributes as the console's kernel writes them, measured off a disk Conker
	# saved to: its save API's .xbx metadata is SYSTEM (0x04), a game's own file
	# is plain, a folder is 0x10. An archive carries none, so the writer restores
	# them by rule.
	var attrs: Dictionary = {}
	var title_dir := int(two_volume.find(int(two_udata["cluster"]), TITLE)["cluster"])
	for e: Dictionary in two_volume.list_dir(title_dir):
		attrs[str(e["name"])] = int(e["attr"])
	for e: Dictionary in two_volume.list_dir(int(two_volume.find(title_dir, "0A1B2C3D4E5F")["cluster"])):
		attrs[str(e["name"])] = int(e["attr"])
	_ok(attrs.get("TitleMeta.xbx") == 0x04 and attrs.get("SaveMeta.xbx") == 0x04
		and attrs.get("game.sav") == 0x00 and attrs.get("0A1B2C3D4E5F") == 0x10,
		"unit/files carry the attributes the console's own kernel gives them", str(attrs))

	# 2 KB clusters hold 32 entries, so a save of 40 files has to GROW its folder.
	var many: Dictionary = {}
	for i: int in 40:
		many["chunk%02d.bin" % i] = _pattern(100 + i, i)
	var wide := _save_archive(OTHER_TITLE, "Conker", "ABCDEF012345", "Chapter 3", many)
	var three := fmt.insert_save(two, wide)
	_eq(fmt.list_saves(three).size(), 3, "unit/a save with more files than a cluster of entries fits")
	_ok(fmt.extract_save(three, fmt.block_of(three, "4d530051/ABCDEF012345")) == wide,
		"unit/and every one of them comes back")

	# Deleting frees the room, and the game's folder goes with its last save.
	var gone := fmt.delete_save(three, fmt.block_of(three, "4d530051/ABCDEF012345"))
	_eq(fmt.list_saves(gone).size(), 2, "unit/a save is deleted")
	_eq(fmt.free_blocks(gone), fmt.free_blocks(two), "unit/and all of its room comes back")
	var volume := FatxVolume.open(XboxRawImage.of(gone), 0, gone.size())
	var udata := volume.find(FatxVolume.ROOT_CLUSTER, "UDATA")
	_ok(volume.find(int(udata["cluster"]), OTHER_TITLE).is_empty()
		and not volume.find(int(udata["cluster"]), TITLE).is_empty(),
		"unit/its game's folder goes with the last save, and the other game's stays")
	_ok(fmt.insert_save(gone, wide).size() == gone.size(), "unit/and the freed room takes a save again")

	# A lift off the hard disk is every save of one game, plus TDATA a unit has
	# no place for: it is split per save, and that is the way back to the console.
	_fatx(_halo_tree())
	var lifted := XboxStorage.archive_for(_xiso("unit.iso", 0, 0x4d530004, "Halo"), _qcow2("unit.qcow2"))
	var parts := fmt.saves_in_download(lifted["bytes"])
	_eq(parts.size(), 1, "unit/a hard disk backup holds the saves a unit can take")
	var restored := fmt.insert_save(blank, parts[0]) if parts.size() == 1 else PackedByteArray()
	_eq(fmt.list_saves(restored).size(), 1, "unit/and one goes into a Memory Unit, which is the way home")

	# Not everything with a zip's magic is a save, and a path must stay a path.
	_ok(not fmt.is_save_file(XboxHddSaves.pack({"readme.txt": _pattern(10, 1)})), "unit/another archive is not a save")
	_ok(not fmt.is_save_file(XboxHddSaves.pack({"UDATA/4d530004/../../x/y": _pattern(10, 1)})),
		"unit/nor is one that climbs out of its folder")
	_ok(not fmt.is_save_file(_pattern(4000, 9)), "unit/nor are bytes that are no archive at all")

	# Full is a refusal, never a half-written card.
	var big := _save_archive(TITLE, "Halo", "BBBBBBBBBBBB", "Too big", {"huge.bin": _pattern(8 * 1024 * 1024 - 4096, 5)})
	_ok(fmt.insert_save(blank, big).is_empty(), "unit/a save that does not fit is refused whole")


# ── slots/ ────────────────────────────────────────────────────────────────────

const PAD_SCENE := preload("res://Scenes/Objects/controllers/retro_controller.tscn")
const UNIT_SCENE := preload("res://Scenes/Objects/controllers/xbox/xbox_mu.tscn")
const UNIT_IDS: PackedStringArray = ["__xbox_selftest_unit_a", "__xbox_selftest_unit_b"]


## What a pad is to VmuPort: something with a systemid.
class FakePad extends Node3D:
	var systemid := ""


func _unit(card_id: String) -> XboxMuCard:
	var unit := UNIT_SCENE.instantiate() as XboxMuCard
	# Identity before the tree, as a restore sets it: _ready mints one otherwise.
	unit.card_id = card_id
	unit.card_label = card_id
	add_child(unit)
	return unit


## The Memory Unit in the room: which sockets take it, both of a pad's slots,
## and the files the core reads them from. These cases write two unit images
## into the player's REAL save/memcards/xbox_mu/ (the path cannot be redirected)
## under names no player would choose, and remove exactly those.
func _group_slots() -> void:
	for id: String in UNIT_IDS:
		DirAccess.remove_absolute(SramPaths.card_save_path("xbox_mu", id))
		SramPaths.ensure_card("xbox_mu", id)
	var unit_a := _unit(UNIT_IDS[0])
	var unit_b := _unit(UNIT_IDS[1])
	var pad := PAD_SCENE.instantiate() as Node3D
	add_child(pad)
	for i: int in 3:
		await get_tree().process_frame

	_ok(unit_a.is_in_group("controller_plug") and unit_a.is_in_group(VmuPort.XBOX_SLOT_GROUP)
		and unit_a.is_in_group("memory_card"), "slots/a unit is seatable, in a pad's slot, and counts as a card")
	_ok(not unit_a.minted and unit_a.card_id == UNIT_IDS[0], "slots/one given its identity before the tree keeps it")
	_eq(unit_a.seated_slot(), -1, "slots/loose, it is in no slot")

	# Which pads take it. The primitive pad stands in for every console's, and a
	# pad made for one console takes that console's things.
	var any_pad := VmuPort.new()
	var any_owner := FakePad.new()
	add_child(any_owner)
	any_pad.attach(any_owner)
	var dc_owner := FakePad.new()
	dc_owner.systemid = "dreamcast"
	add_child(dc_owner)
	var dc_pad := VmuPort.new()
	dc_pad.attach(dc_owner)
	var xbox_owner := FakePad.new()
	xbox_owner.systemid = "xbox"
	add_child(xbox_owner)
	var xbox_pad := VmuPort.new()
	xbox_pad.attach(xbox_owner)
	var pack := preload("res://Scenes/Objects/controllers/dreamcast/jump_pack.tscn").instantiate() as Node3D
	add_child(pack)
	await get_tree().process_frame
	_ok(any_pad._accepts(unit_a) and any_pad._accepts(pack), "slots/the primitive pad takes a unit, and still a Jump Pack")
	_ok(not dc_pad._accepts(unit_a) and dc_pad._accepts(pack), "slots/a Dreamcast's own pad takes no Xbox unit")
	_ok(xbox_pad._accepts(unit_a) and not xbox_pad._accepts(pack), "slots/an Xbox's own pad takes one, and no Jump Pack")
	_eq(xbox_pad.slot_count(), 2, "slots/and has the two slots an Xbox pad has")
	_ok(not any_pad._accepts(pad), "slots/nothing else goes in")

	# BOTH slots of one pad: the console's 1A and 1B.
	_eq(int(pad.call("vmu_slot_count")), 2, "slots/a pad has two")
	pad.call("restore_vmu", unit_a, 0)
	pad.call("restore_vmu", unit_b, 1)
	await get_tree().process_frame
	_ok(pad.call("get_vmu_device", 0) == unit_a and pad.call("get_vmu_device", 1) == unit_b,
		"slots/and holds a unit in each")
	_ok(unit_a.seated_slot() == 0 and unit_b.seated_slot() == 1, "slots/each knowing which it is in")
	# A Dreamcast on the end of this pad is told these slots hold nothing it can
	# use, and VmuStorage, which asks for CARDS, is handed none to stage.
	_ok(str(pad.call("vmu_slot_option_value", 0)) == "None" and str(pad.call("vmu_slot_option_value", 1)) == "None",
		"slots/a Dreamcast is told both are empty")
	_ok(pad.call("get_vmu", 0) == null and pad.call("get_vmu", 1) == null, "slots/and is handed no VMU to stage")

	# On an Xbox, in port 1.
	var console := await _console("xbox", "xemu")
	console._port_controllers[0] = pad
	var storage: XboxStorage = console.get_node("XboxStorage")
	var seated := storage.seated_units()
	_eq(seated.size(), 2, "slots/the console finds both units in its pad")
	_eq(XboxStorage.unit_name(0, 0) + " " + XboxStorage.unit_name(0, 1) + " " + XboxStorage.unit_name(3, 1),
		"1A 1B 4B", "slots/by the names the console itself gives them")

	var root := _dir.path_join("root")
	storage.stage_units_before_start(root, "xemu")
	var file_a := XboxStorage.unit_path(root, 0, 0)
	var file_b := XboxStorage.unit_path(root, 0, 1)
	_ok(file_a.ends_with("save/xemu/xemu/memory_unit_port1.img") and file_b.ends_with("save/xemu/xemu/memory_unit_port1b.img"),
		"slots/each is staged where the core reads that slot from", file_a + " | " + file_b)
	_ok(FileAccess.get_file_as_bytes(file_a) == FileAccess.get_file_as_bytes(SramPaths.card_save_path("xbox_mu", UNIT_IDS[0]))
		and XboxMemoryUnit.is_card_image(FileAccess.get_file_as_bytes(file_b)), "slots/as the unit's own image")
	var opts := CoreOptionsStore.load_values(root, "xemu")
	_ok(str(opts.get("xemu_memory_unit_port1")) == "enabled" and str(opts.get("xemu_memory_unit_port1b")) == "enabled",
		"slots/with both of the pad's slots switched on", str(opts))
	# Every OTHER slot off: the options persist in the core's .opt, and one left
	# on is a unit the console still sees after it left the room.
	var left_on := PackedStringArray()
	for port: int in range(1, 4):
		for slot: int in 2:
			if str(opts.get(XboxStorage.unit_key(port, slot))) != "disabled":
				left_on.append(XboxStorage.unit_key(port, slot))
	_ok(left_on.is_empty(), "slots/and every slot with nothing in it switched off", ", ".join(left_on))

	# The console saves to the unit in 1B. The drain takes it home — to B, not A.
	var halo := _save_archive(TITLE, "Halo", "0A1B2C3D4E5F", "Silent Cartographer")
	var written := XboxMemoryUnit.insert_save(FileAccess.get_file_as_bytes(file_b), halo)
	var wf := FileAccess.open(file_b, FileAccess.WRITE)
	wf.store_buffer(written)
	wf.close()
	storage.drain_units()
	var fmt := CardFormats.for_family("xbox_mu")
	_eq(fmt.list_saves(FileAccess.get_file_as_bytes(SramPaths.card_save_path("xbox_mu", UNIT_IDS[1]))).size(), 1,
		"slots/what the console wrote to 1B goes back to the unit that was in 1B")
	_eq(fmt.list_saves(FileAccess.get_file_as_bytes(SramPaths.card_save_path("xbox_mu", UNIT_IDS[0]))).size(), 0,
		"slots/and not to the one in 1A")

	# A file caught half written must not replace a good image. Cut off inside
	# the save's own data, the root still lists and only the whole walk notices.
	var torn := written.duplicate()
	var volume := FatxVolume.open(XboxRawImage.of(written), 0, written.size())
	torn.encode_u16(volume.fat_offset() + fmt.block_of(written, "4d530004/0A1B2C3D4E5F") * 2, 0)
	wf = FileAccess.open(file_b, FileAccess.WRITE)
	wf.store_buffer(torn)
	wf.close()
	_ok(XboxMemoryUnit.is_card_image(torn) and not XboxMemoryUnit.is_consistent(torn),
		"slots/a torn unit still looks like a unit from its root")
	storage.drain_units()
	_eq(fmt.list_saves(FileAccess.get_file_as_bytes(SramPaths.card_save_path("xbox_mu", UNIT_IDS[1]))).size(), 1,
		"slots/and is not copied over the good image")

	# Draining runs on a timer, and stops once the power-off window closes.
	storage.start_draining_units()
	var timer := storage.get_node_or_null("XboxUnitDrainTimer") as Timer
	_ok(timer != null and not timer.is_stopped(), "slots/units are written back while the console runs")
	storage.stop_draining_units_soon()
	storage.set("_unit_drain_until", Time.get_unix_time_from_system() - 1.0)
	storage.call("_on_unit_tick")
	_ok(timer != null and timer.is_stopped(), "slots/and for a while after it stops, then no longer")

	# Another console's core is none of this.
	var other_root := _dir.path_join("other")
	storage.stage_units_before_start(other_root, "pcsx2")
	_ok(not FileAccess.file_exists(XboxStorage.unit_path(other_root, 0, 0)) and storage.get("_units").is_empty(),
		"slots/nothing is staged for a core that is not xemu")

	# The spawn menu and a saved room both know the unit.
	var tokens := PackedStringArray()
	for item: Dictionary in SpawnCatalog.items_for("xbox"):
		tokens.append(str(item.get("spawn", "")))
	_ok(tokens.has("xbox_mu"), "slots/an Xbox's card offers a Memory Unit", ", ".join(tokens))
	var made := ScenePersistence.instantiate("xbox_mu")
	_ok(made is XboxMuCard, "slots/and a saved room can bring one back")
	if made != null:
		made.free()
	_ok(MemoryCardBrowser.card_count("xbox_mu") >= 2, "slots/units with an image are on the card shelf")

	for n: Node in [console, pad, unit_a, unit_b, pack, any_owner, dc_owner, xbox_owner]:
		n.queue_free()
	for i: int in 10:
		await get_tree().physics_frame
	for id: String in UNIT_IDS:
		DirAccess.remove_absolute(SramPaths.card_save_path("xbox_mu", id))
	for sub: String in ["root/save/xemu/xemu/memory_unit_port1.img", "root/save/xemu/xemu/memory_unit_port1b.img",
			"root/core_options/xemu.opt"]:
		DirAccess.remove_absolute(_dir.path_join(sub))
	for sub: String in ["root/save/xemu/xemu", "root/save/xemu", "root/save", "root/core_options", "root", "other/core_options", "other"]:
		DirAccess.remove_absolute(_dir.path_join(sub))


# ── one/ ──────────────────────────────────────────────────────────────────────

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")


func _console(systemid: String, core: String) -> RetroSystem:
	var sys := SYSTEM_SCENE.instantiate() as RetroSystem
	sys.systemid = systemid
	# Pinned, so the case does not read this machine's core defaults.
	sys.core_name = core
	sys.freeze = true
	add_child(sys)
	for i: int in 30:
		await get_tree().physics_frame
	return sys


## xemu is one machine per process, and every console writes the same hard disk
## image: a second Xbox is refused by the ROOM, before the core has to.
func _group_one_at_a_time() -> void:
	var first := await _console("xbox", "xemu")
	var second := await _console("xbox", "xemu")
	var ps2 := await _console("ps2", "pcsx2")
	var storage: XboxStorage = second.get_node("XboxStorage")
	_eq(storage.busy_elsewhere("xemu"), "", "one/two Xboxes may stand in a room, both off")
	first.is_powered_on = true
	_ok(not storage.busy_elsewhere("xemu").is_empty(), "one/but the second cannot start while the first runs")
	_eq((first.get_node("XboxStorage") as XboxStorage).busy_elsewhere("xemu"), "",
		"one/and the one running is not in its own way")
	_eq((ps2.get_node("XboxStorage") as XboxStorage).busy_elsewhere("pcsx2"), "",
		"one/nor in any other machine's")
	first.is_powered_on = false
	ps2.is_powered_on = true
	_eq(storage.busy_elsewhere("xemu"), "", "one/and a running PlayStation 2 holds no Xbox back")
	ps2.is_powered_on = false
	for sys: RetroSystem in [first, second, ps2]:
		sys.queue_free()
	for i: int in 10:
		await get_tree().physics_frame


# ── Fixtures ──────────────────────────────────────────────────────────────────

func _u32(v: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(4)
	b.encode_u32(0, v)
	return b


func _be64(v: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(8)
	for i: int in 8:
		b[i] = (v >> (56 - 8 * i)) & 0xff
	return b


func _pattern(size: int, seed_byte: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(size)
	for i: int in size:
		b[i] = (seed_byte + i * 7) & 0xff
	return b


## A fresh FATX volume holding `tree` ({name: bytes | {…}}) at BASE.
func _fatx(tree: Dictionary) -> void:
	_extents.clear()
	_fat.clear()
	_placed.clear()
	_free = 2
	var head := PackedByteArray()
	head.resize(16)
	head.encode_u32(0, 0x58544146)   # "FATX"
	head.encode_u32(4, 0xda6d205b)
	head.encode_u32(8, 32)
	head.encode_u16(12, 1)
	_extents[BASE] = head
	_fat[1] = 0xffffffff
	_dir_into(tree, 1, "")


func _take_cluster() -> int:
	var c := _free
	_free += 2   # the gap: no chain in this fixture is contiguous
	return c


func _dir_into(tree: Dictionary, cluster: int, prefix: String) -> void:
	var data := PackedByteArray()
	data.resize(CLUSTER)
	data.fill(0xff)
	var at := 0
	for name: String in tree:
		var item: Variant = tree[name]
		var is_dir := item is Dictionary
		var size := 0 if is_dir else (item as PackedByteArray).size()
		var first := 0
		if is_dir:
			first = _take_cluster()
			_fat[first] = 0xffffffff
			_dir_into(item, first, prefix + name + "/")
		elif size > 0:
			var bytes: PackedByteArray = item
			var prev := 0
			for off: int in range(0, size, CLUSTER):
				var c := _take_cluster()
				if prev == 0:
					first = c
				else:
					_fat[prev] = c
				_fat[c] = 0xffffffff
				_extents[DATA + (c - 1) * CLUSTER] = bytes.slice(off, mini(off + CLUSTER, size))
				prev = c
		var raw := name.to_ascii_buffer()
		data[at] = raw.size()
		data[at + 1] = 0x10 if is_dir else 0x00
		for i: int in FatxVolume.NAME_MAX:
			data[at + 2 + i] = raw[i] if i < raw.size() else 0xff
		data.encode_u32(at + 0x2c, first)
		data.encode_u32(at + 0x30, size)
		_placed[prefix + name] = {"cluster": first, "at": at, "dir": cluster}
		at += FatxVolume.ENTRY_SIZE
	_extents[DATA + (cluster - 1) * CLUSTER] = data


## The fixture as a qcow2 file. `opts` break the header or one cluster's entry.
func _qcow2(name: String, opts: Dictionary = {}) -> String:
	# The FAT goes in as one extent per touched 4 KB, so its untouched middle —
	# over a megabyte — stays unallocated in the image, as it is in a real one.
	var extents := _extents.duplicate()
	var fat_pages: Dictionary = {}
	for c: int in _fat:
		var page := (c * 4) & ~0xfff
		# Out, changed, back in: a packed array read from a Dictionary is a COPY,
		# and poking the copy left every FAT entry zero the first time round.
		var bytes: PackedByteArray = fat_pages.get(page, PackedByteArray())
		if bytes.is_empty():
			bytes.resize(0x1000)
		bytes.encode_u32(c * 4 - page, int(_fat[c]))
		fat_pages[page] = bytes
	for page: int in fat_pages:
		extents[BASE + 0x1000 + page] = fat_pages[page]

	# Guest clusters that hold anything.
	var guest: Dictionary = {}
	for off: int in extents:
		var bytes: PackedByteArray = extents[off]
		var done := 0
		while done < bytes.size():
			var ci := (off + done) >> 16
			var within := (off + done) & 0xffff
			var take := mini(bytes.size() - done, QCLUSTER - within)
			if not guest.has(ci):
				var blank := PackedByteArray()
				blank.resize(QCLUSTER)
				guest[ci] = blank
			var cluster: PackedByteArray = guest[ci]
			for i: int in take:
				cluster[within + i] = bytes[done + i]
			guest[ci] = cluster
			done += take

	const PER_L2 := QCLUSTER >> 3
	var l1_used: Dictionary = {}
	for ci: int in guest:
		@warning_ignore("integer_division")
		l1_used[ci / PER_L2] = true
	# Host layout: header, L1, one L2 per used L1 slot, then the data.
	var next_host := 2 * QCLUSTER
	var l2_at: Dictionary = {}
	for i: int in l1_used:
		l2_at[i] = next_host
		next_host += QCLUSTER
	var l2_tables: Dictionary = {}
	for i: int in l1_used:
		var t := PackedByteArray()
		t.resize(QCLUSTER)
		l2_tables[i] = t
	var ordered: Array = guest.keys()
	ordered.sort()
	var data_at: Dictionary = {}
	var nth := 0
	for ci: int in ordered:
		data_at[ci] = next_host
		# COPIED (bit 63) set, as QEMU sets it: the reader has to mask it off.
		var entry := next_host | (1 << 63)
		if int(opts.get("compress_nth", -1)) == nth:
			entry |= 1 << 62
		if int(opts.get("zero_nth", -1)) == nth:
			entry |= 1
		@warning_ignore("integer_division")
		var table: PackedByteArray = l2_tables[ci / PER_L2]
		var e := _be64(entry)
		for k: int in 8:
			table[(ci % PER_L2) * 8 + k] = e[k]
		@warning_ignore("integer_division")
		l2_tables[ci / PER_L2] = table
		next_host += QCLUSTER
		nth += 1

	var head := PackedByteArray()
	head.resize(104)
	var magic: int = opts.get("magic", Qcow2Image.MAGIC)
	for k: int in 4:
		head[k] = (magic >> (24 - 8 * k)) & 0xff
	head[7] = int(opts.get("version", 3))
	var backing := _be64(int(opts.get("backing", 0)))
	var size := _be64(0x200000000)
	var l1_off := _be64(QCLUSTER)
	var incompat := _be64(int(opts.get("incompat", 0)))
	for k: int in 8:
		head[8 + k] = backing[k]
		head[24 + k] = size[k]
		head[40 + k] = l1_off[k]
		head[72 + k] = incompat[k]
	head[23] = 16                     # cluster bits
	head[35] = int(opts.get("crypt", 0))
	head[39] = 16                     # L1 entries: 16 x 512 MB = the 8 GB disk

	var path := _dir.path_join(name)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(head)
	f.seek(QCLUSTER)
	for i: int in 16:
		f.store_buffer(_be64((int(l2_at[i]) | (1 << 63)) if l2_at.has(i) else 0))
	for i: int in l2_at:
		f.seek(int(l2_at[i]))
		f.store_buffer(l2_tables[i])
	for ci: int in ordered:
		f.seek(int(data_at[ci]))
		f.store_buffer(guest[ci])
	f.close()
	return path


func _halo_tree() -> Dictionary:
	return {
		"TDATA": {
			TITLE: {"profile.bin": _pattern(40000, 3)},   # three clusters, fragmented
			OTHER_TITLE: {"conker.cfg": _pattern(64, 9)},
		},
		"UDATA": {
			TITLE: {
				"TitleMeta.xbx": _pattern(34, 1),
				"0123456789AB": {
					"SaveMeta.xbx": _pattern(72, 5),
					"slot.sav": _pattern(CLUSTER, 7),       # exactly one cluster
					"empty.flag": PackedByteArray(),
				},
			},
		},
	}


# ── qcow2/ ────────────────────────────────────────────────────────────────────

func _group_qcow2() -> void:
	_fatx(_halo_tree())
	var why: Array = []
	var image := Qcow2Image.open(_qcow2("plain.qcow2"), why)
	_ok(image != null, "qcow2/a plain image opens", str(why))
	if image != null:
		_eq(image.virtual_size(), 0x200000000, "qcow2/as the 8 GB disk it is")
		_eq(image.read(BASE, 4).get_string_from_ascii(), "FATX",
			"qcow2/a written cluster reads back, 2.9 GB in")
		# Inside the FAT, between the two touched pages: never written.
		var hole := image.read(BASE + 0x80000, 64)
		_ok(hole.size() == 64 and hole.count(0) == 64, "qcow2/a cluster never written reads as zeros")
		# A cluster with no L2 table at all, at the start of the disk.
		var far := image.read(0x1000, 16)
		_ok(far.size() == 16 and far.count(0) == 16, "qcow2/and so does one with no table behind it")
		# Across a qcow2 cluster boundary: header cluster into the next.
		var span := image.read(BASE + QCLUSTER - 8, 16)
		_eq(span.size(), 16, "qcow2/a read may cross clusters")
		_ok(image.read(0x200000000 - 4, 8).is_empty(), "qcow2/but not the end of the disk")
		image.close()
	else:
		for skipped: String in ["as the 8 GB disk it is", "a written cluster reads back, 2.9 GB in",
				"a cluster never written reads as zeros", "and so does one with no table behind it",
				"a read may cross clusters", "but not the end of the disk"]:
			_ok(false, "qcow2/" + skipped)

	# qcow2 v3's "reads as zeros" flag, on a cluster that still has an offset and
	# stale bytes behind it — which is how QEMU leaves one it has discarded.
	var zeroed := Qcow2Image.open(_qcow2("zeroed.qcow2", {"zero_nth": 0}))
	var stale := zeroed.read(BASE, 4) if zeroed != null else PackedByteArray()
	_ok(stale.size() == 4 and stale.count(0) == 4,
		"qcow2/a cluster flagged zero reads as zeros, whatever is behind it")
	if zeroed != null:
		zeroed.close()

	# Each of these would make read() return bytes that are not the guest's.
	for bad: Array in [
		["not a qcow2", {"magic": 0x46415458}],
		["version 4", {"version": 4}],
		["a backing file", {"backing": 0x100}],
		["encryption", {"crypt": 1}],
		["an external data file", {"incompat": 4}],
		["extended L2 entries", {"incompat": 16}],
	]:
		_ok(Qcow2Image.open(_qcow2("bad.qcow2", bad[1])) == null, "qcow2/%s is refused" % bad[0])
	# The dirty bit says the REFCOUNTS may be stale. Nothing here reads one.
	_ok(Qcow2Image.open(_qcow2("dirty.qcow2", {"incompat": 1})) != null,
		"qcow2/a dirty image is still readable")
	var lifted := XboxHddSaves.lift(_qcow2("packed.qcow2", {"compress_nth": 0}), TITLE)
	_ok(not bool(lifted["ok"]) and str(lifted["error"]).contains("compressed"),
		"qcow2/a compressed cluster fails the read rather than reading as data", str(lifted["error"]))


# ── fatx/ ─────────────────────────────────────────────────────────────────────

func _group_fatx() -> void:
	_fatx(_halo_tree())
	var lifted := XboxHddSaves.lift(_qcow2("halo.qcow2"), TITLE)
	_ok(bool(lifted["ok"]), "fatx/a title's saves lift", str(lifted["error"]))
	var files: Dictionary = lifted["files"]
	var paths: Array = files.keys()
	paths.sort()
	_eq(", ".join(PackedStringArray(paths)),
		"TDATA/4d530004/profile.bin, UDATA/4d530004/0123456789AB/SaveMeta.xbx, "
		+ "UDATA/4d530004/0123456789AB/empty.flag, UDATA/4d530004/0123456789AB/slot.sav, "
		+ "UDATA/4d530004/TitleMeta.xbx",
		"fatx/both trees, nested, and nobody else's")
	_ok(files.get("TDATA/4d530004/profile.bin") == _pattern(40000, 3),
		"fatx/a fragmented three-cluster file comes back whole")
	_ok(files.get("UDATA/4d530004/0123456789AB/slot.sav") == _pattern(CLUSTER, 7),
		"fatx/a file of exactly one cluster does not read a second")
	_ok(files.get("UDATA/4d530004/TitleMeta.xbx") == _pattern(34, 1), "fatx/a short file is cut to its size")
	_ok(files.has("UDATA/4d530004/0123456789AB/empty.flag")
		and (files["UDATA/4d530004/0123456789AB/empty.flag"] as PackedByteArray).is_empty(),
		"fatx/an empty file is a file")
	_eq(XboxHddSaves.byte_count(files), 40000 + CLUSTER + 34 + 72, "fatx/and the sizes add up")

	var cased := XboxHddSaves.lift(_qcow2("halo.qcow2"), TITLE.to_upper())
	_eq((cased["files"] as Dictionary).size(), 5, "fatx/the folder is found whatever its case")
	var none := XboxHddSaves.lift(_qcow2("halo.qcow2"), "4d530099")
	_ok(bool(none["ok"]) and (none["files"] as Dictionary).is_empty(),
		"fatx/a game that never saved is no files, and not a failure")
	_ok(not bool(XboxHddSaves.lift(_qcow2("halo.qcow2"), "../UDATA")["ok"]),
		"fatx/a title id is eight hex digits or nothing")

	_fatx({})
	var blank := XboxHddSaves.lift(_qcow2("blank.qcow2"), TITLE)
	_ok(bool(blank["ok"]) and (blank["files"] as Dictionary).is_empty(),
		"fatx/a freshly formatted disk has no saves")
	_extents.clear()
	_fat.clear()
	var unformatted := XboxHddSaves.lift(_qcow2("raw.qcow2"), TITLE)
	_ok(not bool(unformatted["ok"]), "fatx/an unformatted one is a failure, not an empty backup",
		str(unformatted["error"]))


# ── torn/ ─────────────────────────────────────────────────────────────────────

## `what` breaks the fixture; the lift must then fail outright.
func _torn(label: String, what: Callable) -> void:
	_fatx(_halo_tree())
	what.call()
	var lifted := XboxHddSaves.lift(_qcow2("torn.qcow2"), TITLE)
	_ok(not bool(lifted["ok"]) and (lifted["files"] as Dictionary).is_empty(),
		"torn/%s fails the whole lift" % label,
		"ok=%s files=%d error=%s" % [lifted["ok"], (lifted["files"] as Dictionary).size(), lifted["error"]])


## Overwrite part of `path`'s 64-byte directory entry, `field` bytes into it.
## Out, changed, back in, for the reason _qcow2 gives.
func _poke_entry(path: String, field: int, value: int, width: int) -> void:
	var key := DATA + (int(_placed[path]["dir"]) - 1) * CLUSTER
	var data: PackedByteArray = _extents[key]
	var at := int(_placed[path]["at"]) + field
	if width == 4:
		data.encode_u32(at, value)
	else:
		data[at] = value
	_extents[key] = data


func _group_torn() -> void:
	var profile := "TDATA/%s/profile.bin" % TITLE
	_torn("a chain that loops", func() -> void:
		var first := int(_placed[profile]["cluster"])
		_fat[first + 4] = first)
	_torn("a chain through a free cluster", func() -> void:
		_fat[int(_placed[profile]["cluster"]) + 2] = 0)
	# A directory has no size to check its chain against, so this is the one case
	# only the FAT can catch: without it the listing just ends early, and the
	# backup is quietly missing whatever came after.
	_torn("a directory chain through a free cluster", func() -> void:
		_fat[int(_placed["UDATA/%s" % TITLE]["cluster"])] = 0)
	_torn("a chain shorter than its file", func() -> void:
		_fat[int(_placed[profile]["cluster"])] = 0xffffffff)
	_torn("a chain longer than its file", func() -> void:
		var last := int(_placed[profile]["cluster"]) + 4
		_fat[last] = last + 1
		_fat[last + 1] = 0xffffffff)
	_torn("a file starting past the volume", func() -> void:
		_poke_entry(profile, 0x2c, 0x7fffffff, 4))
	_torn("a name that is not a name", func() -> void:
		_poke_entry(profile, 4, 0x01, 1))
	_torn("a name longer than FATX allows", func() -> void:
		_poke_entry(profile, 0, 0x60, 1))
	_torn("a directory that contains itself", func() -> void:
		var save := "UDATA/%s/0123456789AB" % TITLE
		_poke_entry(save + "/SaveMeta.xbx", 0x2c, int(_placed[save]["cluster"]), 4)
		_poke_entry(save + "/SaveMeta.xbx", 1, 0x10, 1))
	# The control: untouched, the same fixture lifts. Without it every case above
	# would pass against a fixture that never lifted at all.
	_fatx(_halo_tree())
	_ok(bool(XboxHddSaves.lift(_qcow2("torn.qcow2"), TITLE)["ok"]),
		"torn/and the same disk, unbroken, lifts")


# ── disc/ ─────────────────────────────────────────────────────────────────────

func _dir_entry(left: int, right: int, sector: int, size: int, name: String) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(14)
	b.encode_u16(0, left)
	b.encode_u16(2, right)
	b.encode_u32(4, sector)
	b.encode_u32(8, size)
	b[12] = 0x20
	b[13] = name.length()
	b.append_array(name.to_ascii_buffer())
	while b.size() % 4 != 0:
		b.append(0xff)
	return b


## An XISO of one game, its partition starting `base` bytes into the file.
func _xiso(name: String, base: int, title_id: int, title: String, boot := "default.xbe") -> String:
	# Rooted at "media" so the boot file is a LEFT turn and "zeta.bin" a right.
	var root := _dir_entry(0, 0, 50, 0, "media")
	var left_at := root.size()
	var left := _dir_entry(0, 0, 40, 0x400, boot)
	var right_at := left_at + left.size()
	var right := _dir_entry(0, 0, 60, 16, "zeta.bin")
	@warning_ignore("integer_division")
	root.encode_u16(0, left_at / 4)
	@warning_ignore("integer_division")
	root.encode_u16(2, right_at / 4)
	var directory := root + left + right

	var volume := XboxDisc.VOLUME_MAGIC.to_ascii_buffer()
	volume.append_array(_u32(33))
	volume.append_array(_u32(directory.size()))

	var xbe := PackedByteArray()
	xbe.resize(0x400)
	xbe.encode_u32(0, 0x48454258)            # "XBEH"
	xbe.encode_u32(0x104, 0x10000)           # base address
	xbe.encode_u32(0x118, 0x10000 + 0x180)   # certificate ADDRESS
	xbe.encode_u32(0x180 + 0x08, title_id)
	var wide := title.to_utf16_buffer()
	for i: int in wide.size():
		xbe[0x180 + 0x0c + i] = wide[i]

	var path := _dir.path_join(name)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.seek(base + 32 * 2048)
	f.store_buffer(volume)
	f.seek(base + 33 * 2048)
	f.store_buffer(directory)
	f.seek(base + 40 * 2048)
	f.store_buffer(xbe)
	f.close()
	return path


func _group_disc() -> void:
	var halo := XboxDisc.title_of(_xiso("halo.iso", 0, 0x4d530004, "Halo"))
	_eq(str(halo.get("title_id", "")), TITLE, "disc/the title id comes off default.xbe")
	_eq(str(halo.get("name", "")), "Halo", "disc/with the game's own name")
	var upper := XboxDisc.title_of(_xiso("upper.iso", 0, 0x4d530051, "Conker: Live and Reloaded", "DEFAULT.XBE"))
	_eq(str(upper.get("title_id", "")), OTHER_TITLE, "disc/whatever case the disc spells the file in")

	# A game partition that does not start the file, as on a redump image. Tried
	# at a small offset: the real one is 406 MB in, and what is under test is that
	# EVERY seek honours the base, which a base of zero cannot show.
	var f := FileAccess.open(_xiso("offset.iso", 0x20000, 0x4d530004, "Halo"), FileAccess.READ)
	_eq(str(XboxDisc._title_in(f, 0x20000).get("title_id", "")), TITLE,
		"disc/a partition further into the file is read from where it starts")
	_ok(XboxDisc._title_in(f, 0).is_empty(), "disc/and is not found where it is not")
	f.close()
	_ok(XboxDisc.PARTITION_OFFSETS.has(0x18300000), "disc/a redump image's partition is one of the places tried")

	_ok(XboxDisc.title_of(_xiso("noboot.iso", 0, 0x4d530004, "Halo", "game.xbe")).is_empty(),
		"disc/a disc with no default.xbe names no game")
	var junk := _dir.path_join("junk.iso")
	var jf := FileAccess.open(junk, FileAccess.WRITE)
	jf.store_buffer(_pattern(0x12000, 1))
	jf.close()
	_ok(XboxDisc.title_of(junk).is_empty(), "disc/nor does a file that is not a disc")
	_ok(XboxDisc.title_of(_dir.path_join("absent.iso")).is_empty(), "disc/or one that is not there")


# ── archive/ ──────────────────────────────────────────────────────────────────

func _group_archive() -> void:
	# CRC-32's published check value. The CRC is lifted out of a gzip trailer
	# rather than computed, which is the kind of trick that needs an oracle.
	_eq(XboxHddSaves._crc32("123456789".to_ascii_buffer()), 0xcbf43926, "archive/the CRC is CRC-32")

	var files := {"UDATA/b.sav": _pattern(5000, 2), "UDATA/a.sav": _pattern(10, 4), "TDATA/none": PackedByteArray()}
	var zip := XboxHddSaves.pack(files)
	# Insertion order must not reach the bytes: RommSaveSync uploads when the md5
	# moves, and a Dictionary built in another order is the same saves.
	var shuffled := {"TDATA/none": PackedByteArray(), "UDATA/a.sav": _pattern(10, 4), "UDATA/b.sav": _pattern(5000, 2)}
	_ok(zip == XboxHddSaves.pack(shuffled), "archive/the same saves pack to the same bytes")
	_ok(zip != XboxHddSaves.pack({"UDATA/b.sav": _pattern(5000, 3), "UDATA/a.sav": _pattern(10, 4),
		"TDATA/none": PackedByteArray()}), "archive/and changed saves to different ones")

	# Read back by the engine's own reader, which checks each entry's CRC.
	var path := _dir.path_join("saves.zip")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(zip)
	f.close()
	var reader := ZIPReader.new()
	_eq(reader.open(path), OK, "archive/it is a zip")
	_eq(", ".join(reader.get_files()), "TDATA/none, UDATA/a.sav, UDATA/b.sav", "archive/listing its files in order")
	_ok(reader.read_file("UDATA/b.sav") == _pattern(5000, 2), "archive/and giving them back")
	reader.close()

	# End to end, as XboxStorage runs it: disc -> title id -> that title's folder.
	_fatx(_halo_tree())
	var hdd := _qcow2("e2e.qcow2")
	var got := XboxStorage.archive_for(_xiso("e2e.iso", 0, 0x4d530051, "Conker"), hdd)
	_ok(bool(got["ok"]) and str(got["title_id"]) == OTHER_TITLE, "archive/a disc finds its own game's saves",
		str(got["error"]))
	f = FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(got["bytes"])
	f.close()
	reader = ZIPReader.new()
	reader.open(path)
	_eq(", ".join(reader.get_files()), "TDATA/4d530051/conker.cfg", "archive/and not the other game's")
	reader.close()
	var never := XboxStorage.archive_for(_xiso("never.iso", 0, 0x4d530099, "Unplayed"), hdd)
	_ok(bool(never["ok"]) and (never["bytes"] as PackedByteArray).is_empty(),
		"archive/a game with no saves is nothing to upload, not an empty archive")
	var broken := XboxStorage.archive_for(_xiso("e2e.iso", 0, 0x4d530051, "Conker"), _dir.path_join("absent.qcow2"))
	_ok(not bool(broken["ok"]) and (broken["bytes"] as PackedByteArray).is_empty(),
		"archive/and a disk that cannot be read uploads nothing")
