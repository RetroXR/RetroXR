## game_search_tests — the Games tab's searches that look past one system.
##
## System aliases (a tile answers to "gba" as well as "Game Boy Advance") and the
## global game search, which reads every system's ROM folder and RomM index
## sidecars without loading any of them into the catalog. The index here is
## written by the test in the on-disk layout RommCatalog syncs, so a change to
## that layout fails this suite rather than the search quietly finding nothing.
##
##   "$godot" --headless --path RetroXR res://Tests/game_search_tests.tscn
extends "res://Tests/test_suite.gd"

## Cases in this file, NOT counting the guard below -- a case that never RAN is
## not a case that passed.
const EXPECTED_CASES := 106

var _root := ""


func _ready() -> void:
	suite_tag = "gsearch"
	get_tree().create_timer(30.0).timeout.connect(func() -> void:
		push_error("[gsearch] TIMEOUT")
		get_tree().quit(1))

	_root = ProjectSettings.globalize_path("user://game_search_tests_tmp")
	_wipe(_root)
	DirAccess.make_dir_recursive_absolute(_root)

	_group_aliases()
	_group_regional_names()
	_group_cart_fallback()
	_group_options_pages()
	_group_region_objects()
	_group_cart_on_the_wire()
	_group_index()
	_group_search_all()

	_wipe(_root)
	_eq(_case_count(), EXPECTED_CASES, "suite/every case ran")
	_finish()


# ── aliases ──────────────────────────────────────────────────────────────────

func _group_aliases() -> void:
	var gba := GameSearch.system_aliases("gba")
	_ok(gba.has("gba"), "aliases/systemid is an alias")
	_ok(GameSearch.system_matches("gba", "game boy advance", gba),
		"aliases/gba finds Game Boy Advance")
	_ok(GameSearch.system_matches("advance", "game boy advance", PackedStringArray()),
		"aliases/the proper name still matches")
	_ok(not GameSearch.system_matches("zzzz", "game boy advance", gba),
		"aliases/an unrelated needle matches nothing")
	_ok(GameSearch.system_matches("", "anything", PackedStringArray()),
		"aliases/an empty needle shows every tile")

	# Every RomM slug the project maps must find the system it maps to.
	var bad: Array[String] = []
	for slug: String in RommPlatforms.SLUG_MAP:
		var sid := str(RommPlatforms.SLUG_MAP[slug])
		if not GameSearch.system_aliases(sid).has(slug.to_lower()):
			bad.append(slug)
	_ok(bad.is_empty(), "aliases/every SLUG_MAP slug is an alias of its system", str(bad))

	var sn := GameSearch.system_aliases("snes", {"slug": "Super-Nintendo-Odd", "fs_slug": "sfc"})
	_ok(sn.has("super-nintendo-odd"), "aliases/the server platform's slug is folded in")
	_ok(sn.has("sfc"), "aliases/the server platform's fs_slug is folded in")
	var folders := SystemIds.folder_names("snes")
	var all_folders := true
	for f: String in folders:
		all_folders = all_folders and sn.has(f.to_lower())
	_ok(all_folders, "aliases/every RetroXR folder name is an alias")
	var seen := {}
	var dup := false
	for a: String in sn:
		dup = dup or seen.has(a)
		seen[a] = true
	_ok(not dup, "aliases/no alias is listed twice")


# ── regional names ───────────────────────────────────────────────────────────

func _group_regional_names() -> void:
	_eq(RegionalNames.name_for("genesis", "", "Sega Genesis (core)"), "Sega Genesis (core)",
		"regional/Default leaves the core's own name")
	_eq(RegionalNames.name_for("genesis", "us", "x"), "Sega Genesis", "regional/USA Genesis")
	_eq(RegionalNames.name_for("genesis", "eu", "x"), "Sega Mega Drive", "regional/Europe Mega Drive")
	_eq(RegionalNames.name_for("tg16", "jp", "x"), "PC Engine", "regional/Japan PC Engine")
	_eq(RegionalNames.name_for("tg16", "us", "x"), "TurboGrafx-16", "regional/USA TurboGrafx-16")
	_eq(RegionalNames.name_for("snes", "jp", "x"), "Super Famicom", "regional/Japan Super Famicom")
	_eq(RegionalNames.name_for("odyssey2", "jp", "x"), "Magnavox Odyssey²",
		"regional/a region a row omits falls back to the US name")
	_eq(RegionalNames.name_for("nes", "eu", "NES"), "NES", "regional/a system not in the table keeps its name")

	# Every regional name finds its tile in a search, whatever region is showing.
	var gen := GameSearch.system_aliases("genesis")
	_ok(GameSearch.system_matches("mega drive", "sega genesis", gen), "regional/'mega drive' finds the Genesis tile")
	var tg := GameSearch.system_aliases("tg16")
	_ok(GameSearch.system_matches("pc engine", "turbografx-16", tg), "regional/'pc engine' finds TurboGrafx-16")
	_ok(GameSearch.system_matches("sgx", "x", GameSearch.system_aliases("supergrafx")),
		"regional/'sgx' finds SuperGrafx")
	_ok(GameSearch.system_matches("mark iii", "x", GameSearch.system_aliases("mastersystem")),
		"regional/'mark iii' finds Master System")
	_ok(RegionalNames.is_region("jp") and RegionalNames.is_region("") and not RegionalNames.is_region("xx"),
		"regional/only known regions are accepted")


# ── a ROM with no known market takes the player's region ─────────────────────

func _group_cart_fallback() -> void:
	var unknown := "/nonexistent/Some Game.sfc"
	var was := RegionalNames.test_region
	RegionalNames.test_region = "jp"
	_eq(SnesCartShell.market("snes", unknown), "jp", "fallback/an unknown SNES market is Japan for a Japanese player")
	_eq(SnesCartShell.body_model_for_rom("", "snes", unknown), SnesCartShell.BODY_SFC,
		"fallback/...so the cartridge is the Super Famicom body")
	RegionalNames.test_region = "us"
	_ok(SnesCartShell.body_model_for_rom("", "snes", unknown) in [SnesCartShell.BODY_TYPE_A, SnesCartShell.BODY_TYPE_B],
		"fallback/a US player gets the North American body")
	RegionalNames.test_region = ""
	_eq(SnesCartShell.market("snes", unknown), "", "fallback/pinned to no region, an unknown market stays unknown")
	_eq(N64CartShell.market("n64", "/nonexistent/x.z64"), "", "fallback/N64 likewise")
	RegionalNames.test_region = "jp"
	_eq(N64CartShell.market("n64", "/nonexistent/x.z64"), "jp", "fallback/an unknown N64 market is the player's")

	# The ROM's own market wins whatever the player's region is.
	RegionalNames.test_region = "jp"
	_eq(SnesCartShell.market("snes", "/nonexistent/Game (USA).sfc"), "us",
		"fallback/a file tagged USA stays US for a Japanese player")
	RegionalNames.test_region = was

	_eq(RegionalNames.region_of_mains("na"), "us", "fallback/North American outlet is the USA")
	_eq(RegionalNames.region_of_mains("jp"), "jp", "fallback/Japanese outlet is Japan")
	_eq(RegionalNames.region_of_mains("uk"), "eu", "fallback/any other outlet is Europe")
	_eq(RegionalNames.effective_region(), "", "fallback/a suite resolves to Original unless it pins a region")

	# The names pick and the cartridge fallback are two answers from one dropdown,
	# and Original is about names only. cart_market_for("original", ...) once
	# returned "" -- every unknown SNES ROM back to the procedural box for a player
	# who only wanted the cores' names.
	_eq(RegionalNames.cart_market_for("original", "jp"), "jp",
		"split/Original names still give an unknown ROM the player's own cartridge")
	_eq(RegionalNames.cart_market_for("", "na"), "us", "split/unpicked on a US outlet is a US cartridge")
	_eq(RegionalNames.cart_market_for("", "au"), "au", "split/unpicked on an Australian outlet keeps au")
	_eq(RegionalNames.cart_market_for("eu", "jp"), "eu", "split/a picked region beats the outlet")
	_eq(RegionalNames.names_region_for("original", "jp"), "", "split/Original keeps the cores' names")
	_eq(RegionalNames.names_region_for("", "jp"), "jp", "split/unpicked names follow the outlet")
	_eq(RegionalNames.names_region_for("us", "jp"), "us", "split/a picked region names the tiles")

	# The dropdown flies a flag per region and a globe on Auto, all drawn by the
	# bundled flag font (Windows' emoji font has no flags). A glyph it lacks is a
	# tofu box in the headset, which no other check here would see.
	var font := MenuIcons.flags_font()
	var missing: Array[String] = []
	for code: String in ["us", "eu", "jp", "world"]:
		var flag := MenuIcons.region_flag(code)
		if flag.is_empty():
			missing.append(code + "(no flag)")
			continue
		for i in flag.length():
			if font == null or not font.has_char(flag.unicode_at(i)):
				missing.append("%s U+%X" % [code, flag.unicode_at(i)])
	_ok(font != null, "flags/the flag font loads")

	# A VRDropdown row is [label, id]; REGIONS rows are [id, label]. Passed through
	# unswapped, every pick sent a label the pref refuses and the dropdown did
	# nothing. Built by the Options view's own function, so this is the real list.
	var view := SpawnMenuOptionsView.new()
	var items: Array = view._region_names_items()
	view.free()
	var bad: Array[String] = []
	for it: Array in items:
		if not RegionalNames.is_region(str(it[1])):
			bad.append(str(it[1]))
	_eq(items.size(), RegionalNames.REGIONS.size(), "rows/one Console Names row per region")
	# No "Auto" row: not picked yet shows the outlet's region selected instead, and
	# USA heads the list.
	_eq(str(items[0][1]), "us", "rows/USA is the first row")
	_ok(not items.any(func(it: Array) -> bool: return str(it[1]).is_empty()),
		"rows/there is no row for an unpicked setting")
	_ok(bad.is_empty(), "rows/every row's id is a value the pref accepts", str(bad))
	_ok(missing.is_empty(), "flags/every Console Names glyph is in the flag font", str(missing))


# ── the Options pages ────────────────────────────────────────────────────────

## Every `_page("Title")` call makes a whole new tab, so a second call with the same
## title does not add to the page, it adds a duplicate that Godot renames
## "@ScrollContainer@NNNN" (a builder for the Systems page did exactly that).
##
## Read from the source on purpose: building the real pages means building the
## spawn menu's widgets, whose Viewport2Din3D hangs a headless run, so the calls
## that make the tabs are the only handle a suite has on them.
func _group_options_pages() -> void:
	var src := FileAccess.get_file_as_string("res://Scripts/UI/spawn_menu/views/options_view.gd")
	var seen := {}
	var dup: Array[String] = []
	var re := RegEx.create_from_string("_page\\(\"([^\"]+)\"")
	for m: RegExMatch in re.search_all(src):
		var title := m.get_string(1)
		if seen.has(title):
			dup.append(title)
		seen[title] = true
	_ok(seen.size() > 5 and dup.is_empty(), "options/every page title is built once", str(dup))


# ── what the region reaches past names ───────────────────────────────────────

func _group_region_objects() -> void:
	var was := RegionalNames.test_region
	var unknown := "/nonexistent/Some Game.sfc"

	# Variants: the mods spell regions their own way.
	_eq(RegionalNames.region_of_variant({"id": "us_gray"}), "us", "variant/us_gray is North America")
	_eq(RegionalNames.region_of_variant({"id": "eur"}), "eu", "variant/eur is Europe")
	_eq(RegionalNames.region_of_variant({"id": "pal"}), "eu", "variant/pal is Europe")
	_eq(RegionalNames.region_of_variant({"id": "jpn"}), "jp", "variant/jpn is Japan")
	_eq(RegionalNames.region_of_variant({"id": "red"}), "", "variant/a colour is no region")
	_eq(RegionalNames.region_of_variant({"id": "mk80000a", "region": "jp"}), "jp",
		"variant/a variant saying its region outright is believed")

	# xenu.saturn's and xenu.sgb's own lists.
	var saturn := [{"id": "us"}, {"id": "jp"}, {"id": "pal"}]
	var sgb := [{"id": "usa"}, {"id": "jpn"}, {"id": "ukv"}, {"id": "noe"}]
	RegionalNames.test_region = "jp"
	_eq(RegionalNames.variant_for_region(saturn), "jp", "variant/a Japanese player's Saturn is the Japanese one")
	RegionalNames.test_region = "us"
	_eq(RegionalNames.variant_for_region(saturn), "", "variant/a US player's is the row as it comes")
	RegionalNames.test_region = "eu"
	_eq(RegionalNames.variant_for_region(saturn), "pal", "variant/a European player's is PAL")
	_eq(RegionalNames.variant_for_region(sgb), "ukv", "variant/...and the first PAL Super Game Boy listed")
	_eq(RegionalNames.variant_for_region([{"id": "red"}, {"id": "blue"}]), "",
		"variant/a row of colours is left as it comes")

	# The row's own default beats the region -- the FIRST variant too, which the
	# panel now keeps by its id (erased, it read as never chosen).
	var tok := "__gsearch_test|row"
	var had: Variant = AppPrefs.spawn_defaults.get(tok)
	RegionalNames.test_region = "jp"
	AppPrefs.spawn_defaults.erase(tok)
	_eq(SpawnMenuSpawnView._row_default(tok, saturn), "jp", "variant/no default of its own: the region's")
	# Through what MAKE DEFAULT stores for the first variant, not a hand-set value.
	var kept := SpawnMenuSpawnView._kept_default("", saturn)
	_eq(kept, "us", "variant/MAKE DEFAULT keeps the first variant by its id")
	AppPrefs.spawn_defaults[tok] = kept
	_eq(SpawnMenuSpawnView._row_default(tok, saturn), "", "variant/a picked first variant beats the region")
	if had == null:
		AppPrefs.spawn_defaults.erase(tok)
	else:
		AppPrefs.spawn_defaults[tok] = had

	# Brazil: Europe's names, North America's cartridges.
	_eq(RegionalNames.region_of_mains("br"), "eu", "brazil/Brazil reads Europe's names")
	_eq(RegionalNames.cart_market_for("", "br"), "us", "brazil/...and takes North America's cartridges")

	# The PAL sticker an unknown ROM's fallback SFC shell wears.
	RegionalNames.test_region = "eu"
	_eq(SnesCartShell.rear_sticker("snes", unknown), "eur", "sticker/Europe's fallback cartridge has Europe's sticker")
	RegionalNames.test_region = "au"
	_eq(SnesCartShell.rear_sticker("snes", unknown), "ukv", "sticker/Australia's has the UK one")
	RegionalNames.test_region = "jp"
	_eq(SnesCartShell.rear_sticker("snes", unknown), "", "sticker/Japan's has none")
	RegionalNames.test_region = "eu"
	_eq(SnesCartShell.rear_sticker("snes", "/nonexistent/Game (USA).sfc"), "",
		"sticker/a ROM tagged USA has none, whatever the player's region")

	# A pinned market beats the player's region, so a saved cartridge keeps its body.
	RegionalNames.test_region = "us"
	_eq(SnesCartShell.market("snes", unknown, "jp"), "jp", "pin/a pinned market beats the player's region")
	_eq(RetroCartridge.body_model_for("snes", unknown, "", &"", "jp"), SnesCartShell.BODY_SFC,
		"pin/...and so the body follows the pin")
	_ok(RetroCartridge.uses_fallback_market("snes", unknown), "pin/a ROM naming no region uses the fallback")
	_ok(not RetroCartridge.uses_fallback_market("snes", "/nonexistent/Game (USA).sfc"),
		"pin/a ROM naming its region never does")
	var cart := RetroCartridge.new()
	cart.systemid = "snes"
	cart.rom_path = unknown
	RegionalNames.test_region = "jp"
	cart._pin_fallback_market()
	_eq(cart.fallback_market, "jp", "pin/a cartridge pins the player's market the first time")
	RegionalNames.test_region = "us"
	cart._pin_fallback_market()
	_eq(cart.fallback_market, "jp", "pin/...and keeps it when the region changes")
	cart.free()
	_ok("fallback_market" in ScenePersistence._STRING_FIELDS, "pin/the pin is a saved field")

	# Add-on names: shown regionally, the fixed label kept for the card id.
	RegionalNames.test_region = "eu"
	_eq(ExpansionCatalog.display_label_of("sega_cd"), "Mega-CD", "addon/Europe's Sega CD is the Mega-CD")
	_eq(ExpansionCatalog.label_of("sega_cd"), "Sega CD",
		"addon/...but its fixed label, which a memory card id is minted from, does not move")
	RegionalNames.test_region = "jp"
	var stack := ExpansionCatalog.stack_label("Sega Mega Drive", ["sega_cd", "sega_32x"])
	_ok(stack.contains("Mega-CD") and stack.contains("Super 32X") and not stack.contains("Sega CD"),
		"addon/a Japanese stack's nameplate uses Japan's add-on names", stack)
	RegionalNames.test_region = ""
	_eq(ExpansionCatalog.display_label_of("sega_32x"), "32X", "addon/Original keeps the label")
	_eq(SegaCdCardFormat.new().label(), "Sega CD", "addon/...and the card's name")
	RegionalNames.test_region = was


# ── a session agrees on an unknown-region cartridge ───────────────────────────

## A netplay spawn and a late joiner's snapshot are ScenePersistence entries, the
## same ones a room save writes, so the pin travels in the entry: the peer that
## spawned the cartridge decides its body, and every other peer -- whatever its
## own region -- builds that body. Before the pin each peer fell back to its own
## region, so one saw a Super Famicom shell and another a Type A, different sizes.
func _group_cart_on_the_wire() -> void:
	var was := RegionalNames.test_region
	var sp := ScenePersistence.new("arcade")
	var unknown := "/nonexistent/Some Game.sfc"

	# The spawning peer is Japanese: its cartridge pins "jp" as it enters the tree,
	# before object_sync's local_spawn serializes it.
	RegionalNames.test_region = "jp"
	var cart := ScenePersistence.CART_SCENE.instantiate() as RetroCartridge
	cart.systemid = "snes"
	cart.rom_path = unknown
	cart.freeze = true
	add_child(cart)
	var entry := sp._serialize_node(cart, 0, {})
	_eq(str(entry.get("fallback_market", "")), "jp", "wire/the spawn entry carries the spawner's pin")
	remove_child(cart)
	cart.free()

	# The receiving peer is American.
	RegionalNames.test_region = "us"
	var got := sp.instantiate_objects(self, [entry])
	var peer: RetroCartridge = null
	for id: Variant in got:
		peer = got[id] as RetroCartridge
	_ok(peer != null, "wire/the receiving peer builds the cartridge")
	if peer != null:
		_eq(peer.fallback_market, "jp", "wire/...keeping the spawner's pin, not its own region")
		_eq(peer._body_model(), SnesCartShell.BODY_SFC, "wire/...and so the spawner's body")
		remove_child(peer)
		peer.free()

	# Control: the same entry without the field is what every peer did before --
	# fall back to its own region, which here is a different body.
	var bare := entry.duplicate(true)
	bare.erase("fallback_market")
	got = sp.instantiate_objects(self, [bare])
	var own: RetroCartridge = null
	for id: Variant in got:
		own = got[id] as RetroCartridge
	_eq(own._body_model() if own != null else "", SnesCartShell.BODY_TYPE_A,
		"wire/without the pin the peer used its own region (the old mismatch)")
	if own != null:
		remove_child(own)
		own.free()
	RegionalNames.test_region = was


# ── one index, straight off disk ─────────────────────────────────────────────

## Write a RomM index in RommCatalog's sidecar layout. rows: [name, fs_name, id].
func _write_index(dir: String, rows: Array) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var names := ""
	var fsn := ""
	var exts := ""
	var regs := ""
	var ids := PackedInt32Array()
	var offs := PackedInt64Array()
	var jsonl := ""
	for r: Array in rows:
		offs.append(jsonl.to_utf8_buffer().size())
		ids.append(int(r[2]))
		names += str(r[0]) + "\n"
		fsn += str(r[1]).get_basename().to_lower() + "\n"
		exts += str(r[1]).get_extension().to_lower() + "\n"
		regs += "\n"
		jsonl += JSON.stringify({"id": r[2], "name": r[0], "fs_name": r[1]}) + "\n"
	_put(dir.path_join("index.jsonl"), jsonl.to_utf8_buffer())
	_put(dir.path_join("index.names"), names.to_utf8_buffer())
	_put(dir.path_join("index.fsnames"), fsn.to_utf8_buffer())
	_put(dir.path_join("index.exts"), exts.to_utf8_buffer())
	_put(dir.path_join("index.regions"), regs.to_utf8_buffer())
	_put(dir.path_join("index.ids"), ids.to_byte_array())
	_put(dir.path_join("index.off"), offs.to_byte_array())


func _put(path: String, bytes: PackedByteArray) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()


func _group_index() -> void:
	var dir := _root.path_join("idx")
	_write_index(dir, [
		["Pokémon Emerald", "Pokemon Emerald.gba", 11],
		["Pokémon Emerald", "Pokemon Emerald.sav", 12],
		["Metroid Fusion", "Metroid Fusion.gba", 13],
		["Pokemon Ruby", "Pokemon Ruby.gba", 14],
	])
	var hits := RommCatalog.search_dir(dir, SearchFold.fold("pokemon"), 10)
	_eq(hits.size(), 2, "index/accent-folded query finds both Pokémon games")
	var labels: Array[String] = []
	for h: Dictionary in hits:
		labels.append(str(h["label"]))
	_ok("Pokémon Emerald" in labels and "Pokemon Ruby" in labels, "index/hits carry the display name")
	_ok(not (hits.any(func(h: Dictionary) -> bool: return int(h["rom_id"]) == 12)),
		"index/a save kept beside its game is not a result")
	_eq(int((hits[0]["entry"] as Dictionary).get("id", 0)), int(hits[0]["rom_id"]),
		"index/the hit's entry is its own row")
	_eq(RommCatalog.search_dir(dir, "pokemon", 1).size(), 1, "index/the limit caps the hits")
	_eq(RommCatalog.search_dir(dir, "nonesuch", 10).size(), 0, "index/no match is empty")
	_eq(RommCatalog.search_dir(_root.path_join("missing"), "pokemon", 10).size(), 0,
		"index/an unsynced platform is empty, not an error")
	# A half-swapped index must be refused, not seeked into.
	_put(dir.path_join("index.ids"), PackedInt32Array([1, 2]).to_byte_array())
	_eq(RommCatalog.search_dir(dir, "pokemon", 10).size(), 0,
		"index/an inconsistent index finds nothing")


# ── the whole search ─────────────────────────────────────────────────────────

func _group_search_all() -> void:
	var gba_dir := _root.path_join("gba")
	var psx_dir := _root.path_join("psx")
	DirAccess.make_dir_recursive_absolute(gba_dir)
	DirAccess.make_dir_recursive_absolute(psx_dir)
	_put(gba_dir.path_join("Pokemon Emerald.gba"), PackedByteArray([1]))
	_put(gba_dir.path_join("Zelda Minish Cap.gba"), PackedByteArray([1]))
	_put(gba_dir.path_join("Pokemon Emerald.sav"), PackedByteArray([1]))
	_put(psx_dir.path_join("Final Fantasy VII.cue"), PackedByteArray([1]))
	_put(psx_dir.path_join("Final Fantasy VII.bin"), PackedByteArray([1]))
	_put(psx_dir.path_join("Spyro Pokemon Crossover.cue"), PackedByteArray([1]))

	var idx := _root.path_join("idx_gba")
	_write_index(idx, [
		["Pokemon Emerald", "Pokemon Emerald.gba", 21],
		["Pokemon Ruby", "Pokemon Ruby.gba", 22],
	])
	var jobs: Array = [
		{"systemid": "gba", "name": "Game Boy Advance", "index_dir": idx,
			"local_dirs": PackedStringArray([gba_dir]), "exts": ["gba", "zip"],
			"folders": false, "cached": {}},
		{"systemid": "psx", "name": "PlayStation", "index_dir": "",
			"local_dirs": PackedStringArray([psx_dir]), "exts": ["cue", "bin", "chd"],
			"folders": false, "cached": {}},
	]

	var res := GameSearch.search_all(jobs, "pokemon")
	var rows: Array = res["rows"]
	var by_label: Dictionary = {}
	for r: Dictionary in rows:
		by_label[str(r["label"])] = r
	_eq(rows.size(), 3, "search/Emerald (both), Ruby (server) and the PlayStation crossover")
	_eq(str((by_label["Pokemon Emerald"] as Dictionary)["source"]), "both",
		"search/a game on disk and in the index is ONE row, downloaded")
	_eq(str((by_label["Pokemon Ruby"] as Dictionary)["source"]), "server",
		"search/an index-only game is a server row")
	_eq(str((by_label["Spyro Pokemon Crossover"] as Dictionary)["system_name"]), "PlayStation",
		"search/a result names its own system, whichever system the query came from")
	_ok(str((by_label["Pokemon Emerald"] as Dictionary)["path"]).ends_with("Pokemon Emerald.gba"),
		"search/a merged row launches the local file")

	# Order: titles that START with the query come first.
	_eq(str(rows[0]["label"]).begins_with("Pokemon"), true, "search/a title starting with the query leads")
	_eq(str(rows[rows.size() - 1]["label"]), "Spyro Pokemon Crossover",
		"search/a title merely containing the query comes after")

	var ff := GameSearch.search_all(jobs, "final fantasy")
	_eq((ff["rows"] as Array).size(), 1, "search/a .cue and its .bin are one game")
	_eq(str(((ff["rows"] as Array)[0] as Dictionary)["path"]).get_extension(), "cue",
		"search/the descriptor is the file a row launches")

	# The RomM cache decides the path of a row whose file is not named like the index.
	jobs[0]["cached"] = {22: gba_dir.path_join("renamed.gba")}
	var cached := GameSearch.search_all(jobs, "ruby")
	_eq(str(((cached["rows"] as Array)[0] as Dictionary)["source"]), "both",
		"search/a cached download makes its server row a downloaded one")

	_eq((GameSearch.search_all(jobs, "p")["rows"] as Array).size(), 0,
		"search/a one-letter query searches nothing")
	var capped := GameSearch.search_all(jobs, "pokemon", 2)
	_eq((capped["rows"] as Array).size(), 2, "search/the row limit caps the page")
	_eq(bool(capped["truncated"]), true, "search/a capped page says so")


func _wipe(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		var full := path.path_join(f)
		if dir.current_is_dir():
			_wipe(full)
		DirAccess.remove_absolute(full)
		f = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)
