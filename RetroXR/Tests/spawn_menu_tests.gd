## spawn_menu_tests — the spawn menu's logic, without its rendering.
##
## spawn_view.gd and options_view.gd are the two largest files in the project
## (2,875 and 2,130 lines) and had no coverage. Most of that is widget assembly
## that only means anything on a GPU, and this suite deliberately does not touch
## it: the menu lives in a Viewport2Din3D, and driving that headless hangs
## rather than fails — the same trap scene_tests avoids by never running a real
## transition.
##
## What IS covered is the part that decides what the player is shown: the
## drill-down browser's filter, which systems get a Cartridges tile, and the four
## formatters whose output is read off a panel and whose boundaries are easy to
## get wrong by one.
##
##   "$godot" --headless --path RetroXR res://Tests/spawn_menu_tests.tscn
##   "$godot" --headless --path RetroXR res://Tests/spawn_menu_tests.tscn -- --only=filter
extends "res://Tests/test_suite.gd"

var _only := ""
var _spawned: Array[Node] = []


func _ready() -> void:
	suite_tag = "menu"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.substr("--only=".length())
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		push_error("[menu] TIMEOUT")
		get_tree().quit(1))

	await _group_filter()
	await _group_cartridges()
	_group_counts()
	_group_tokens()
	_group_parse_token()
	await _group_colors()
	_group_formats()
	_group_fit()
	_group_tvs()
	await _group_hold()
	await _group_delete()
	_group_discs()
	await _group_variants()
	await _group_toasts()
	await _group_owed()
	await _group_art()
	await _group_scroll()
	_group_art_lookup()
	await _group_idle()
	await _group_tiles()
	await _group_local_counts()
	_group_frame_cap()
	await _group_trash()
	await _group_item_delete()
	await _group_objects()
	await _group_locate()

	for n: Node in _spawned:
		if is_instance_valid(n):
			n.queue_free()
	_finish()


# ── Harness ───────────────────────────────────────────────────────────────────

## Group filter on the check's own name. TestSuite._ok asks it, so a check
## outside the --only group is neither run nor counted.
func _wanted(what: String) -> bool:
	return _only.is_empty() or what.begins_with(_only)

# ── local_counts/ — a tile with no RomM badge still says what is on the device ─

const LOCAL_COUNT_ROOT := "user://__spawn_menu_local_count_selftest"


## With no server to pair a number with, the Cartridges tile shows the games in
## its own ROM folders. Counted the way the page lists them: one per stem a core
## loads, so a save beside its game, a .bin beside its .cue and the gamelist are
## not games.
func _group_local_counts() -> void:
	var root := ProjectSettings.globalize_path(LOCAL_COUNT_ROOT)
	var one := root.path_join("snes")
	var two := root.path_join("sfc")
	DirAccess.make_dir_recursive_absolute(one.path_join("Folder Game"))
	DirAccess.make_dir_recursive_absolute(two)
	for path: String in [
			one.path_join("Alpha.sfc"), one.path_join("Alpha.srm"),
			one.path_join("Beta.cue"), one.path_join("Beta.bin"),
			one.path_join("gamelist.json"), one.path_join(".hidden.sfc"),
			one.path_join("Folder Game/inner.sfc"),
			two.path_join("Gamma.SFC"), two.path_join("alpha.sfc")]:
		FileAccess.open(path, FileAccess.WRITE).close()
	var exts: Array[String] = ["sfc", "cue", "bin"]
	var dirs := PackedStringArray([one, two])
	_eq(SpawnMenuSpawnView._count_local_games(dirs, exts, false), 3,
		"local_counts/one per game stem across both folders")
	_eq(SpawnMenuSpawnView._count_local_games(dirs, exts, true), 4,
		"local_counts/a folder-content system also counts a folder holding a game")
	_eq(SpawnMenuSpawnView._count_local_games(PackedStringArray([root.path_join("none")]),
		exts, false), 0, "local_counts/a missing folder is no games")
	_remove_local_count_tree(root)

	# The count runs on a worker and comes back on the main thread. Read-only on
	# the real roms root: the number is the player's, its arrival is the check.
	var view := SpawnMenuSpawnView.new()
	add_child(view)
	_spawned.append(view)
	view._request_local_counts(["nes"] as Array[String])
	_ok(view._local_count_task >= 0, "local_counts/a count is handed to a worker")
	for i in 120:
		if view._local_counts.has("nes"):
			break
		await get_tree().process_frame
	_ok(view._local_counts.has("nes") and view._local_count_task == -1,
		"local_counts/and its number lands back on the view")

	var browser := SystemGridBrowser.new()
	add_child(browser)
	_spawned.append(browser)
	await get_tree().process_frame
	var mark := PlaceholderTexture2D.new()
	browser.set_systems([
		{"systemid": "nes", "name": "NES", "badge_local": 7},
		{"systemid": "snes", "name": "SNES", "badge_local": 5,
			"badge_icon": mark, "badge_count": 40, "badge_here": 2},
		{"systemid": "gb", "name": "Game Boy", "badge_local": 0},
	])
	# Sorted by name: Game Boy, NES, SNES.
	_eq(_badge_texts(browser._tile_nodes[1]), ["7"],
		"local_counts/no RomM badge: the corner shows the local count")
	_eq(_badge_texts(browser._tile_nodes[2]), ["2", " / ", "40"],
		"local_counts/a RomM badge keeps its pair and the local count stays out")
	_eq(_badge_texts(browser._tile_nodes[0]), [],
		"local_counts/nothing on the device: no corner number")


## The corner badge's numbers on one tile, in drawing order.
func _badge_texts(tile: Control) -> Array:
	var out: Array = []
	for node: Node in tile.find_children("*", "Label", true, false):
		var lbl := node as Label
		if lbl.has_theme_font_size_override("font_size") \
				and lbl.get_theme_font_size("font_size") == 14:
			out.append(lbl.text)
	return out


func _remove_local_count_tree(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub: String in dir.get_directories():
		_remove_local_count_tree(path.path_join(sub))
	for f: String in dir.get_files():
		DirAccess.remove_absolute(path.path_join(f))
	DirAccess.remove_absolute(path)


## The GRAPHICS tab's desktop frame cap: offered on the desktop and nowhere else,
## and picking it caps the engine and survives a launch. graphics_prefs.json is
## the player's own, so it is put back byte for byte.
func _group_frame_cap() -> void:
	var prefs := ProjectSettings.globalize_path(QualityManager.PREFS_PATH)
	var had := FileAccess.file_exists(prefs)
	var before := FileAccess.get_file_as_bytes(prefs) if had else PackedByteArray()
	var was_cap := QualityManager.frame_cap
	var was_max := Engine.max_fps

	var desk := SpawnMenuGraphicsView.create(false)
	var cap := _dropdown(desk, "Frame Rate Cap")
	_ok(cap != null, "frame_cap/the desktop GRAPHICS tab offers a frame cap")
	if cap != null:
		_eq(cap.get_selected_id(), QualityManager.frame_cap, "frame_cap/it opens on the saved cap")
		cap.item_selected.emit(60)
		_eq(Engine.max_fps, 60, "frame_cap/picking 60 caps the engine at 60")
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(prefs))
		_eq(int((saved as Dictionary).get("frame_cap", -1)) if saved is Dictionary else -1, 60,
			"frame_cap/and it is saved with the other graphics settings")
		cap.item_selected.emit(0)
		_eq(Engine.max_fps, 0, "frame_cap/Off takes the cap away")
	desk.free()

	var vr := SpawnMenuGraphicsView.create(true)
	_ok(_dropdown(vr, "Frame Rate Cap") == null, "frame_cap/a headset's GRAPHICS tab has no frame cap")
	vr.free()

	QualityManager.frame_cap = was_cap
	Engine.max_fps = was_max
	if had:
		var f := FileAccess.open(prefs, FileAccess.WRITE)
		f.store_buffer(before)
		f.close()
	elif FileAccess.file_exists(prefs):
		DirAccess.remove_absolute(prefs)


func _dropdown(root: Node, title: String) -> VRDropdown:
	for node: Node in root.find_children("*", "VRDropdown", true, false):
		var dd := node as VRDropdown
		if dd._label != null and dd._label.text == title:
			return dd
	return null


## Build only the actual TVs tab, without the menu's rendered viewport.
func _group_tvs() -> void:
	const OWNER := "menu.tv_fixture"
	const SHELL := "menu.tv_fixture:panasonic"
	var view := SpawnMenuSpawnView.new()
	var tabs := TabContainer.new()
	view.add_child(tabs)
	var baseline := RetroTV.mod_shells().size()
	_eq(RetroTV.register_mod_shell(SHELL, "res://Scenes/Objects/tv.tscn",
		"Panasonic fixture", OWNER), "", "tvs/register a cabinet")
	var rows := view._add_tv_spawn_tab(tabs)
	var buttons: Array[Button] = []
	for child: Node in rows.get_children():
		if child is Button:
			buttons.append(child as Button)
	_eq(tabs.get_tab_title(0), "TVs", "tvs/tab title")
	_eq(buttons.size(), baseline + 3, "tvs/stock TVs plus every registered cabinet")
	_eq(buttons[0].text.strip_edges(), "+  TV", "tvs/stock TV remains")
	_eq(buttons[1].text.strip_edges(), "+  Plain Monitor", "tvs/stock monitor remains")
	var emitted: Array[String] = []
	view.spawn_requested.connect(func(token: String) -> void: emitted.append(token))
	buttons[-1].pressed.emit()
	_eq(buttons[-1].text.strip_edges(), "+  Panasonic fixture", "tvs/registration label shown")
	_eq(emitted, ["tv:" + SHELL], "tvs/press emits the namespaced cabinet token")
	RetroTV.drop_mod_shells(OWNER)
	var rebuilt := view._add_tv_spawn_tab(tabs)
	var count := 0
	for child: Node in rebuilt.get_children():
		if child is Button:
			count += 1
	_eq(count, baseline + 2, "tvs/removed cabinet absent from a rebuilt menu")

	# A mod applied mid-session (ModManager.apply_live) registers AFTER the tab
	# was built, and the menu is built once a session. The tab is rebuilt in place
	# when the loader says mods were applied.
	_eq(RetroTV.register_mod_shell(SHELL, "res://Scenes/Objects/tv.tscn",
		"Late fixture", OWNER), "", "tvs/register a cabinet after the build")
	view._on_mods_applied()
	var labels: Array[String] = []
	for child: Node in rebuilt.get_children():
		if child is Button and not child.is_queued_for_deletion():
			labels.append((child as Button).text.strip_edges())
	_ok(labels.has("+  Late fixture"), "tvs/a cabinet applied after the build is offered",
		str(labels))
	_eq(labels.size(), baseline + 3, "tvs/and the rows are replaced, not doubled")
	RetroTV.drop_mod_shells(OWNER)
	view.free()


# ── filter/ — the drill-down browser's search box ─────────────────────────────

## SystemGridBrowser is a plain VBoxContainer with a documented `.new()` usage
## and no viewport of its own, so the real widget can be built and driven here.
## The filter is what a player types to find one machine among sixty; it hides
## tiles rather than rebuilding the grid, so a tile left visible is a wrong hit
## and a tile hidden is a machine the player cannot reach.
func _group_filter() -> void:
	var browser := SystemGridBrowser.new()
	add_child(browser)
	_spawned.append(browser)
	await get_tree().process_frame
	browser.set_systems([
		{"systemid": "nes", "name": "Nintendo (NES)", "badge": "3 cores"},
		{"systemid": "snes", "name": "Super Nintendo", "badge": "2 cores"},
		{"systemid": "gb", "name": "Game Boy", "badge": "4 cores"},
		{"systemid": "genesis", "name": "Mega Drive", "badge": "1 core"},
	])
	await get_tree().process_frame

	_eq(_visible_names(browser).size(), 4, "filter/every system shows with no filter")

	browser._on_filter_changed("nintendo")
	var nintendo := _visible_names(browser)
	_eq(nintendo.size(), 2, "filter/a word matches both Nintendo machines")

	# Case is the player's business, not the grid's.
	browser._on_filter_changed("NINTENDO")
	_eq(_visible_names(browser).size(), 2, "filter/matching ignores case")

	# A substring anywhere, not just a prefix — "boy" has to find the Game Boy.
	browser._on_filter_changed("boy")
	_eq(_visible_names(browser).size(), 1, "filter/matches inside the name, not only its start")

	browser._on_filter_changed("   nes   ")
	_ok(_visible_names(browser).size() >= 1,
		"filter/surrounding whitespace is trimmed rather than searched for")

	browser._on_filter_changed("zzzz no such machine")
	_eq(_visible_names(browser).size(), 0, "filter/a miss hides everything")

	# Clearing has to bring them ALL back: this is the state the player is left
	# in after backspacing, and a grid that stays filtered looks like a library
	# that lost half its systems.
	browser._on_filter_changed("")
	_eq(_visible_names(browser).size(), 4, "filter/clearing restores every tile")


## The tiles the grid is currently showing.
func _visible_names(browser: SystemGridBrowser) -> Array:
	var out: Array = []
	for tile: Node in browser._tiles_grid.get_children():
		if tile is Button and (tile as Button).visible:
			out.append(str(tile.get_meta("filter_name", "")))
	return out


# ── cartridges/ — which systems the Cartridges grid has a tile for ────────────

## The view's own populator over a view that is never added to the tree, so none
## of its widget assembly runs. A tile comes from a default core or a RomM
## platform, and the VMU has both.
func _group_cartridges() -> void:
	var browser := SystemGridBrowser.new()
	add_child(browser)
	_spawned.append(browser)
	await get_tree().process_frame

	var view := SpawnMenuSpawnView.new()
	view._cartridges_browser = browser
	view.core_db = CoreInfoDatabase.new()
	view.core_defaults = CoreDefaults.new()
	view.core_defaults.set_default_core("dreamcast", "flycast")
	view.core_defaults.set_default_core("vmu", "vemulator")
	# RomM switched off hides its tiles, so the platform tiles need it on.
	view.romm_config = RommConfig.new()
	view.romm_config.enabled = true
	view.romm_config.base_url = "http://romm.test"
	view._romm_platforms = {
		"nes": {"id": 1, "rom_count": 3, "systemid": "nes"},
		"vmu": {"id": 2, "rom_count": 3, "systemid": "vmu"},
	}
	view._populate_cartridges_tab()
	var ids: Array = []
	for s: Dictionary in browser._systems:
		ids.append(str(s["systemid"]))

	_ok(ids.has("dreamcast"), "cartridges/a system with a default core has a tile", str(ids))
	_ok(ids.has("nes"), "cartridges/a RomM platform has a tile", str(ids))
	_ok(not ids.has("vmu"),
		"cartridges/the VMU has no tile from its default core or its RomM platform", str(ids))
	# The card's Games tab finds the platform to sync through this dictionary.
	_ok(view._romm_platforms.has("vmu"),
		"cartridges/the VMU's RomM platform is still known to the menu")
	view.free()


# ── counts/ — the badge on a tile ─────────────────────────────────────────────

## Both of these are read off a panel at arm's length, and both change shape at
## a power of ten, which is exactly where an off-by-one hides.
func _group_counts() -> void:
	_eq(SystemGridBrowser._compact_count(0), "0", "counts/zero is plain")
	_eq(SystemGridBrowser._compact_count(999), "999", "counts/under a thousand is plain")
	_eq(SystemGridBrowser._compact_count(1000), "1.0k", "counts/a thousand gains one decimal")
	_eq(SystemGridBrowser._compact_count(9999), "10.0k", "counts/just under ten thousand")
	_eq(SystemGridBrowser._compact_count(10000), "10k",
		"counts/ten thousand drops the decimal")
	_eq(SystemGridBrowser._compact_count(999999), "1000k",
		"counts/just under a million is still thousands")
	_eq(SystemGridBrowser._compact_count(1000000), "1.0M",
		"counts/a million becomes millions")


# ── tokens/ — what a console row asks SpawnMenuController for ─────────────────

## A row's token is written by SpawnCatalog.spawn_token and read back by
## model_of_token, and the two have to agree for EVERY id a row can carry. A
## mod's model id has a colon in it. Read with a split at every colon it lost
## everything after that colon, the game knew no such model, and the platform's
## first row was spawned whichever one was picked: the Super Famicom beside the
## Super NES, a PS one beside the PlayStation.
func _group_tokens() -> void:
	for row: Array in [
			["nes", "nes", "tokens/a shipped console"],
			["snes", "xenu.sfc:shvc001", "tokens/a mod's console keeps the whole of its id"],
			["psx", "xenu.psone:scph101", "tokens/a mod's console beside the game's own"],
			["x68000", "", "tokens/a row with no model still says its system"],
	]:
		var token := SpawnCatalog.spawn_token(str(row[0]), {"model_id": str(row[1])})
		var asked := SpawnCatalog.model_of_token(token)
		_eq(asked.size(), 2, "%s: two answers" % row[2])
		_eq(asked[0], str(row[0]), "%s: the system" % row[2])
		_eq(asked[1], str(row[1]), "%s: the model" % row[2])
	var short := SpawnCatalog.model_of_token("model:")
	_ok(short.size() == 2 and short[0].is_empty() and short[1].is_empty(),
		"tokens/a token cut short answers with nothing, and does not throw")

	# Asked for in one of its colors, the color is a field of its own in front
	# and the rest reads back as it did.
	var item := {"model_id": "xenu.n64:nus001"}
	var plain := SpawnCatalog.spawn_token("n64", item)
	var green := SpawnCatalog.spawn_token("n64", item, "jungle_green")
	_eq(plain, "model:n64:xenu.n64:nus001", "tokens/a console as it comes is asked for as before")
	_eq(green, "model_as:jungle_green:n64:xenu.n64:nus001", "tokens/a color goes in front, under a prefix of its own")
	_eq([SpawnCatalog.variant_of_token(plain), SpawnCatalog.variant_of_token(green)], ["", "jungle_green"],
		"tokens/and reads back: nothing for the plain one")
	var back := SpawnCatalog.model_of_token(green)
	_eq([back[0], back[1]], ["n64", "xenu.n64:nus001"], "tokens/with the system and the whole of the model id behind it")
	_ok(SpawnCatalog.is_model_token(plain) and SpawnCatalog.is_model_token(green)
		and not SpawnCatalog.is_model_token("speaker_cable:red:"),
		"tokens/both are a console's token, and a lead's is not")
	# Any other row asked for in a color keeps its own token whole, colons and
	# all, behind the color.
	var pad_row := {"kind": "peripheral", "spawn": "mod:xenu.pads:six"}
	var pad_plain := SpawnCatalog.spawn_token("genesis", pad_row)
	var pad_red := SpawnCatalog.spawn_token("genesis", pad_row, "red")
	_eq([pad_plain, pad_red], ["mod:xenu.pads:six", "as:red:mod:xenu.pads:six"],
		"tokens/a peripheral's token is its own, with the color in front when one is asked for")
	_eq([SpawnCatalog.variant_of_token(pad_plain), SpawnCatalog.variant_of_token(pad_red)], ["", "red"],
		"tokens/and its color reads back")
	_eq([SpawnCatalog.plain_token(pad_plain), SpawnCatalog.plain_token(pad_red), SpawnCatalog.plain_token("as:")],
		["mod:xenu.pads:six", "mod:xenu.pads:six", ""],
		"tokens/and what is left is the token to spawn")
	_ok(not SpawnCatalog.is_model_token(pad_red), "tokens/a peripheral in a color is not a console's token")
	var cut := SpawnCatalog.model_of_token("model_as:")
	_ok(cut.size() == 2 and cut[0].is_empty() and cut[1].is_empty() and SpawnCatalog.variant_of_token("model_as:").is_empty(),
		"tokens/a colored token cut short answers with nothing too")


## SpawnCatalog.parse_token is the one reader of every prefixed token the
## controller is sent. Each prefix has to be caught BEFORE the token is compared
## whole: one that fell through spawned a console with the token as its systemid.
func _group_parse_token() -> void:
	var model := SpawnCatalog.parse_token("model_as:jungle_green:n64:xenu.n64:nus001")
	_eq([model["kind"], model["systemid"], model["model_id"], model["model_variant"], model["variant"]],
		[SpawnCatalog.TokenKind.MODEL, "n64", "xenu.n64:nus001", "jungle_green", ""],
		"parse/a console in a color: system, whole model id, and its color")
	var red_pad := SpawnCatalog.parse_token("as:red:mod:xenu.pads:six")
	_eq([red_pad["kind"], red_pad["mod_type"], red_pad["variant"], red_pad["token"]],
		[SpawnCatalog.TokenKind.MOD, "xenu.pads:six", "red", "mod:xenu.pads:six"],
		"parse/a peripheral in a color: the color off the front, the rest read as its own token")
	var lead := SpawnCatalog.parse_token("speaker_cable:red:2.5")
	_eq([lead["kind"], lead["color"], lead["has_length"], lead["length"]], [SpawnCatalog.TokenKind.SPEAKER_CABLE, "red", true, 2.5],
		"parse/a lead's color and length")
	var old_lead := SpawnCatalog.parse_token("speaker_cable:")
	_eq([old_lead["color"], old_lead["has_length"]], ["", false],
		"parse/a lead token from before lengths says it has none")
	var card := SpawnCatalog.parse_token("memcard:ps2:My Card")
	_eq([card["kind"], card["family"], card["card_id"]], [SpawnCatalog.TokenKind.MEMCARD, "ps2", "My Card"],
		"parse/an existing card: family, then the id after the FIRST colon")
	var bare_card := SpawnCatalog.parse_token("memcard:Old Card")
	_eq([bare_card["family"], bare_card["card_id"]], ["playstation", "Old Card"],
		"parse/a card token with no family is a PlayStation card")
	var blank := SpawnCatalog.parse_token("n64_memory_card")
	_eq([blank["kind"], blank["family"]], [SpawnCatalog.TokenKind.BLANK_MEMCARD, "n64"], "parse/a blank card of a family")
	var rx := SpawnCatalog.parse_token("pad_receiver:abc123:2")
	_eq([rx["kind"], rx["guid"], rx["ordinal"]], [SpawnCatalog.TokenKind.PAD_RECEIVER, "abc123", 2], "parse/a pad receiver's pad")
	_eq([SpawnCatalog.parse_token("expansion:sega32x")["expansion_id"],
		SpawnCatalog.parse_token("tv:pvm")["shell"]], ["sega32x", "pvm"],
		"parse/an expansion's id and a set's shell")
	for literal: String in ["tv", "cartridge", "snes", "light_gun"]:
		var plain := SpawnCatalog.parse_token(literal)
		_eq([plain["kind"], plain["token"]], [SpawnCatalog.TokenKind.PLAIN, literal], "parse/'%s' is read whole" % literal)


# ── colors/ — a console that comes in several ───────────────────────────────

## A model row may list the colors its shell comes in. The card's row for it is
## then held to pick one, as a ROM's row is held to pick a cartridge's shell, and
## pressed to spawn the first, which is the row as it comes.
func _group_colors() -> void:
	const OWNER := "menu.colors"
	const MODEL := "menu.colors:box"
	const SYS := "zz_colors"
	const SCRIPT := "res://Tests/variant_model_fixture.gd"
	var row := {"platform": SYS, "label": "Box", "script": SCRIPT,
		"variants": [{"id": "gray", "label": "Gray", "color": Color(0.2, 0.2, 0.2)},
			{"id": "green", "label": "Jungle", "color": "#1e8e3e"}]}
	_eq(SystemModelRegistry.register_mod_row(MODEL, row, OWNER), "", "colors/a row that lists its colors registers")
	_eq(SystemModelRegistry.variants_of(MODEL).size(), 2, "colors/and says which they are")
	_eq(SystemModelRegistry.variants_of("nes").size(), 0, "colors/a model with one color lists none")
	_eq(SystemModelRegistry.variant_color({"color": "#1e8e3e"}).to_html(false), "1e8e3e",
		"colors/a swatch is given as '#rrggbb'")
	_eq(SystemModelRegistry.variant_color({"color": Color(0.2, 0.2, 0.2)}), Color(0.2, 0.2, 0.2),
		"colors/or as a Color")
	for bad: Array in [
			["not a list", "gray"],
			["an entry that is not a dictionary", ["gray"]],
			["no id", [{"label": "Gray"}]],
			["a colon in an id", [{"id": "a:b"}]],
			["the same id twice", [{"id": "gray"}, {"id": "gray"}]],
			["a color that is not one", [{"id": "gray", "color": "grayish"}]],
	]:
		var broken := {"platform": SYS, "label": "X", "script": SCRIPT, "variants": bad[1]}
		_ok(not SystemModelRegistry.register_mod_row("menu.colors:bad", broken, OWNER).is_empty(),
			"colors/refused: %s" % bad[0])

	var found := {}
	var plain_rows := 0
	for item: Dictionary in SpawnCatalog.items_for(SYS):
		if str(item.get("model_id", "")) == MODEL:
			found = item
		elif not item.has("variants"):
			plain_rows += 1
	_eq((found.get("variants", []) as Array).size(), 2, "colors/the card's item for that console carries them")
	# A row kept only so that rooms saved naming it still load.
	_eq(SystemModelRegistry.register_mod_row("menu.colors:old", {"platform": SYS, "label": "Box (Green)", "script": SCRIPT,
		"unlisted": true}, OWNER), "", "colors/a row may be kept off the card")
	var offered: Array = []
	for item: Dictionary in SpawnCatalog.items_for(SYS):
		offered.append(str(item.get("model_id", "")))
	_ok(not offered.has("menu.colors:old") and offered.has(MODEL)
		and str(SystemModelRegistry.resolve("menu.colors:old", SYS).get("id", "")) == "menu.colors:old",
		"colors/the card does not offer it, and a save that names it still resolves to it")
	_ok(plain_rows > 0, "colors/and the card's other rows carry none")

	# The card itself. Its page is a plain column, built with no menu round it.
	var holder := Control.new()
	add_child(holder)
	_spawned.append(holder)
	var view := SpawnMenuSpawnView.new()
	holder.add_child(view)
	var page := VBoxContainer.new()
	holder.add_child(page)
	var sent: Array[String] = []
	view.spawn_requested.connect(func(token: String) -> void: sent.append(token))
	view._populate_systems_detail(SYS, page)
	await get_tree().process_frame
	var console: Button = null
	var others_hold := 0
	for child in page.get_children():
		var btn := child as Button
		if btn == null:
			continue
		if btn.text.contains("Box"):
			console = btn
		elif btn.has_node("HoldPress"):
			others_hold += 1
	var hold := console.get_node_or_null("HoldPress") as HoldPress if console != null else null
	_ok(hold != null, "colors/the console's row can be held")
	_eq(others_hold, 0, "colors/and no other row on the card can")
	if hold == null:
		SystemModelRegistry.drop_mod(OWNER)
		return
	var plain := "model:%s:%s" % [SYS, MODEL]

	console.button_down.emit()
	hold.advance(0.3)
	console.pressed.emit()
	console.button_up.emit()
	_eq(sent, [plain] as Array[String], "colors/pressed, it spawns the console as it comes")
	_ok(view._spawn_options_panel == null, "colors/and opens nothing")

	sent.clear()
	console.button_down.emit()
	hold.advance(HoldPress.HOLD_SECONDS + 0.1)
	console.pressed.emit()
	console.button_up.emit()
	var panel := view._spawn_options_panel
	_ok(panel != null and sent.is_empty(), "colors/held for a second, it opens the panel and spawns nothing")
	var grid := panel.find_child("Variants", true, false) as GridContainer if panel != null else null
	var swatches: Array = grid.get_children() if grid != null else []
	_eq(swatches.size(), 2, "colors/with a swatch for each color")
	if swatches.size() == 2:
		var first := swatches[0] as Button
		var second := swatches[1] as Button
		_eq([first.text, second.text], ["Gray", "Jungle"], "colors/each under its own name")
		_ok(first.button_pressed and not second.button_pressed, "colors/open on the first, which is the row's own")
		var fill := second.get_theme_stylebox("normal") as StyleBoxFlat
		_ok(fill != null and fill.bg_color.is_equal_approx(Color.html("#1e8e3e")), "colors/each painted its color")
		(panel.find_child("SpawnVariant", true, false) as Button).pressed.emit()
		_eq(sent, [plain] as Array[String], "colors/SPAWN on the first asks for no color at all")
		_ok(view._spawn_options_panel == null, "colors/and closes the panel")

		sent.clear()
		console.button_down.emit()
		hold.advance(HoldPress.HOLD_SECONDS + 0.1)
		console.pressed.emit()
		console.button_up.emit()
		panel = view._spawn_options_panel
		grid = panel.find_child("Variants", true, false) as GridContainer if panel != null else null
		if grid != null and grid.get_child_count() == 2:
			(grid.get_child(1) as Button).pressed.emit()
			(panel.find_child("SpawnVariant", true, false) as Button).pressed.emit()
		_eq(sent, ["model_as:green:%s:%s" % [SYS, MODEL]] as Array[String],
			"colors/a swatch picked, SPAWN asks for the console in that color")
	await get_tree().process_frame

	# A row that is not a console's. One a mod adds lists its colors on the item;
	# one of the game's own is offered them by its token.
	var pad_colors := [{"id": "gray", "label": "Gray", "color": "#888888"}, {"id": "red", "label": "Red", "color": "#cc2222"}]
	_eq(SpawnCatalog.register_mod_peripherals(SYS, [{"label": "Mod Pad", "spawn": "mod:menu.colors:pad", "variants": pad_colors}], OWNER),
		"", "colors/a mod's own row may list colors")
	_ok(not SpawnCatalog.register_mod_peripherals(SYS, [{"label": "Bad Pad", "spawn": "x", "variants": [{"id": "a:b"}]}], OWNER).is_empty(),
		"colors/and is refused when they are malformed")
	_eq(SpawnCatalog.register_mod_row_variants("light_gun", pad_colors, OWNER), "", "colors/a row of the game's own can be offered colors by its token")
	_ok(not SpawnCatalog.register_mod_row_variants("light_gun", pad_colors, "menu.other").is_empty(),
		"colors/by one mod at a time")
	_ok(not SpawnCatalog.register_mod_row_variants("light_gun2", [{"id": ""}], OWNER).is_empty(),
		"colors/and not malformed ones")
	var mod_pad := {}
	for item: Dictionary in SpawnCatalog.items_for(SYS):
		if str(item.get("spawn", "")) == "mod:menu.colors:pad":
			mod_pad = item
	_eq((mod_pad.get("variants", []) as Array).size(), 2, "colors/the card's item for the mod's row carries them")
	var gun := {}
	for item: Dictionary in SpawnCatalog.items_for("nes"):
		if str(item.get("spawn", "")) == "light_gun":
			gun = item
	_eq((gun.get("variants", []) as Array).size(), 2, "colors/and so does the game's own row, wherever it is carded")
	# A token several cards share, each row spawning its own console's thing: offered
	# on one card, the others' rows are left as they were.
	_eq(SpawnCatalog.register_mod_row_variants("memory_card", pad_colors, OWNER, "ps2"), "",
		"colors/a shared token can be offered colors on one card")
	var card_colors := {}
	for card_sys: String in ["ps2", "psx", "gc"]:
		for item: Dictionary in SpawnCatalog.items_for(card_sys):
			if str(item.get("spawn", "")) == "memory_card":
				card_colors[card_sys] = (item.get("variants", []) as Array).size()
	_eq(card_colors, {"ps2": 2, "psx": 0, "gc": 0}, "colors/and only that card's row carries them")
	var pad_page := VBoxContainer.new()
	holder.add_child(pad_page)
	view._populate_systems_detail(SYS, pad_page)
	await get_tree().process_frame
	var pad_btn: Button = null
	for child in pad_page.get_children():
		if child is Button and (child as Button).text.contains("Mod Pad"):
			pad_btn = child as Button
	var pad_hold := pad_btn.get_node_or_null("HoldPress") as HoldPress if pad_btn != null else null
	_ok(pad_hold != null, "colors/a peripheral's row with colors can be held too")
	if pad_hold != null:
		sent.clear()
		pad_btn.button_down.emit()
		pad_hold.advance(0.3)
		pad_btn.pressed.emit()
		pad_btn.button_up.emit()
		_eq(sent, ["mod:menu.colors:pad"] as Array[String], "colors/pressed, it spawns as it comes")
		sent.clear()
		pad_btn.button_down.emit()
		pad_hold.advance(HoldPress.HOLD_SECONDS + 0.1)
		pad_btn.pressed.emit()
		pad_btn.button_up.emit()
		var pad_panel := view._spawn_options_panel
		var pad_grid := pad_panel.find_child("Variants", true, false) as GridContainer if pad_panel != null else null
		if pad_grid != null and pad_grid.get_child_count() == 2:
			(pad_grid.get_child(1) as Button).pressed.emit()
			(pad_panel.find_child("SpawnVariant", true, false) as Button).pressed.emit()
		_eq(sent, ["as:red:mod:menu.colors:pad"] as Array[String], "colors/held and picked, it asks for itself in that color")
		# The row says it can be held, and with what a press gives; held, a color
		# can be made that press's color, and is kept.
		_ok(pad_btn.icon != null, "colors/a row that can be held wears a swatch")
		var pad_key := "%s|%s" % [SYS, "mod:menu.colors:pad"]
		var pad_was := AppPrefs.spawn_default(pad_key)
		AppPrefs.set_spawn_default(pad_key, "")
		pad_btn.button_down.emit()
		pad_hold.advance(HoldPress.HOLD_SECONDS + 0.1)
		pad_btn.pressed.emit()
		pad_btn.button_up.emit()
		pad_panel = view._spawn_options_panel
		pad_grid = pad_panel.find_child("Variants", true, false) as GridContainer if pad_panel != null else null
		var make := pad_panel.find_child("MakeDefault", true, false) as Button if pad_panel != null else null
		_ok(make != null and make.disabled, "colors/held, the panel opens on the row's default, as it comes")
		if pad_grid != null and make != null:
			(pad_grid.get_child(1) as Button).pressed.emit()
			_ok(not make.disabled, "colors/another color picked can be made the default")
			make.pressed.emit()
			_eq(AppPrefs.spawn_default(pad_key), "red", "colors/and is kept for this row")
			_ok(make.disabled, "colors/and the button then says it is the default")
		view._close_spawn_options_panel()
		sent.clear()
		pad_btn.button_down.emit()
		pad_hold.advance(0.3)
		pad_btn.pressed.emit()
		pad_btn.button_up.emit()
		_eq(sent, ["as:red:mod:menu.colors:pad"] as Array[String], "colors/pressed now, the row spawns its default")
		pad_btn.button_down.emit()
		pad_hold.advance(HoldPress.HOLD_SECONDS + 0.1)
		pad_btn.pressed.emit()
		pad_btn.button_up.emit()
		pad_panel = view._spawn_options_panel
		pad_grid = pad_panel.find_child("Variants", true, false) as GridContainer if pad_panel != null else null
		_ok(pad_grid != null and (pad_grid.get_child(1) as Button).button_pressed
			and not (pad_grid.get_child(0) as Button).button_pressed,
			"colors/and held again, the panel opens on it")
		view._close_spawn_options_panel()
		_eq(SpawnMenuSpawnView._row_default(pad_key, pad_colors), "red", "colors/a kept default the row still lists is read back")
		_eq(SpawnMenuSpawnView._row_default(pad_key, [pad_colors[0]]), "", "colors/one the row no longer lists is ignored")
		AppPrefs.set_spawn_default(pad_key, pad_was)
	await get_tree().process_frame

	SystemModelRegistry.drop_mod(OWNER)
	SpawnCatalog.drop_mod(OWNER)
	_eq(SystemModelRegistry.variants_of(MODEL).size(), 0, "colors/with the row gone there is nothing to pick")
	var gun_after := {}
	for item: Dictionary in SpawnCatalog.items_for("nes"):
		if str(item.get("spawn", "")) == "light_gun":
			gun_after = item
	_ok(not gun_after.is_empty() and not gun_after.has("variants"), "colors/and the game's own row is as it was once the mod is gone")


# ── formats/ — the strings the options panel prints ───────────────────────────

func _group_formats() -> void:
	_eq(RommSpawnSync._commas(0), "0", "formats/zero needs no separator")
	_eq(RommSpawnSync._commas(999), "999", "formats/three digits need no separator")
	_eq(RommSpawnSync._commas(1000), "1,000", "formats/four digits gain one")
	_eq(RommSpawnSync._commas(1234567), "1,234,567", "formats/seven digits gain two")

	# The mixer rate, printed beside a switch. 48000 must not read "48.0".
	_eq(SpawnMenuOptionsView._khz(48000.0), "48", "formats/a whole rate drops its decimal")
	_eq(SpawnMenuOptionsView._khz(44100.0), "44.1", "formats/a fractional rate keeps one")


# ── fit/ — cover art scaled into its box ──────────────────────────────────────

## _fit_within is the one piece of image handling here that is pure arithmetic,
## and it runs on every piece of downloaded art. Two rules matter: it never
## enlarges (an upscaled thumbnail is worse than a small one), and it preserves
## aspect, since a stretched box render is the visible symptom.
func _group_fit() -> void:
	var small := Image.create(40, 30, false, Image.FORMAT_RGB8)
	SpawnMenuSpawnView._fit_within(small, Vector2i(200, 200))
	_eq(Vector2i(small.get_width(), small.get_height()), Vector2i(40, 30),
		"fit/an image already inside the box is left alone")

	var wide := Image.create(400, 100, false, Image.FORMAT_RGB8)
	SpawnMenuSpawnView._fit_within(wide, Vector2i(200, 200))
	_eq(Vector2i(wide.get_width(), wide.get_height()), Vector2i(200, 50),
		"fit/a wide image is bounded by its width")

	var tall := Image.create(100, 400, false, Image.FORMAT_RGB8)
	SpawnMenuSpawnView._fit_within(tall, Vector2i(200, 200))
	_eq(Vector2i(tall.get_width(), tall.get_height()), Vector2i(50, 200),
		"fit/a tall image is bounded by its height")

	# A sliver must not round to zero: a 0-pixel image is not a valid texture.
	var sliver := Image.create(4000, 3, false, Image.FORMAT_RGB8)
	SpawnMenuSpawnView._fit_within(sliver, Vector2i(200, 200))
	_ok(sliver.get_width() >= 1 and sliver.get_height() >= 1,
		"fit/an extreme aspect never rounds a side to zero",
		"%dx%d" % [sliver.get_width(), sliver.get_height()])


# ── hold/ — a press held for a second opens a sub-menu instead ─────────────

## HoldPress is driven through the button's own signals and its public advance(),
## so the wait costs nothing. Every case counts BOTH signals: a hold that also
## clicks spawns the thing the player was trying to choose a colour for.
func _group_hold() -> void:
	var btn := Button.new()
	add_child(btn)
	_spawned.append(btn)
	var hold := HoldPress.attach(btn)
	var seen := {"clicked": 0, "held": 0}
	hold.clicked.connect(func() -> void: seen["clicked"] += 1)
	hold.held.connect(func() -> void: seen["held"] += 1)
	await get_tree().process_frame

	btn.button_down.emit()
	hold.advance(0.3)
	btn.pressed.emit()
	btn.button_up.emit()
	_eq([seen["clicked"], seen["held"]], [1, 0], "hold/a short press clicks and opens nothing")

	seen["clicked"] = 0
	btn.button_down.emit()
	hold.advance(HoldPress.HOLD_SECONDS - 0.1)
	_eq(seen["held"], 0, "hold/nothing opens before the hold time")
	hold.advance(0.2)
	_eq(seen["held"], 1, "hold/the hold time opens the sub-menu, pointer still down")
	hold.advance(5.0)
	_eq(seen["held"], 1, "hold/and only once however long it stays down")
	btn.pressed.emit()
	btn.button_up.emit()
	_eq(seen["clicked"], 0, "hold/the release after a hold does not click")

	btn.button_down.emit()
	btn.pressed.emit()
	btn.button_up.emit()
	_eq(seen["clicked"], 1, "hold/the next press clicks again")

	seen["clicked"] = 0
	seen["held"] = 0
	btn.button_down.emit()
	hold.advance(HoldPress.HOLD_SECONDS * 0.6)
	btn.mouse_exited.emit()
	hold.advance(HoldPress.HOLD_SECONDS * 0.6)
	_eq(seen["held"], 0, "hold/leaving the button gives the hold up")

	hold.hold_enabled = false
	btn.button_down.emit()
	hold.advance(HoldPress.HOLD_SECONDS * 2.0)
	btn.pressed.emit()
	btn.button_up.emit()
	_eq([seen["clicked"], seen["held"]], [1, 0], "hold/switched off, a long press is a click")

	# A pooled row: every listener swept off `pressed`, then rebound mid-hold.
	hold.hold_enabled = true
	btn.button_down.emit()
	hold.advance(HoldPress.HOLD_SECONDS + 0.5)
	for c: Dictionary in btn.pressed.get_connections():
		btn.pressed.disconnect(c["callable"])
	hold.reset()
	hold.ensure_connected()
	seen["clicked"] = 0
	btn.pressed.emit()
	_eq(seen["clicked"], 1, "hold/a rebound row forgets the last entry's hold")

	_ok(SpawnMenuSpawnView._has_spawn_options("n64")
		and SpawnMenuSpawnView._has_spawn_options("gb")
		and SpawnMenuSpawnView._has_spawn_options("nes")
		and not SpawnMenuSpawnView._has_spawn_options("genesis"),
		"hold/an N64, Game Boy or NES ROM row opens one, a Genesis row does not")

	# The sub-menu itself: what SPAWN hands on for the palette, and for a colour
	# mixed on the Custom sliders. It opens beside the view, so the view has a parent.
	var holder := Control.new()
	add_child(holder)
	_spawned.append(holder)
	var view := SpawnMenuSpawnView.new()
	holder.add_child(view)
	var sent := {"options": null}
	var spawn := func(options: Dictionary) -> void: sent["options"] = options
	var panel_part := func(part: String) -> Control:
		return view._spawn_options_panel.find_child(part, true, false) as Control
	var press_text := func(text: String) -> void:
		for b: Node in view._spawn_options_panel.find_children("*", "Button", true, false):
			if (b as Button).text.strip_edges() == text:
				(b as Button).pressed.emit()
				return
		_ok(false, "hold/no button reads %s" % text)

	view._show_cart_spawn_options("n64", "Selftest", spawn)
	var custom := panel_part.call("ShellCustom") as Button
	var hue := panel_part.call("ShellHue") as HSlider
	_ok(custom != null and hue != null and panel_part.call("ShellSaturation") != null
		and panel_part.call("ShellBrightness") != null and panel_part.call("ShellFlake") != null,
		"hold/the shell list ends in a Custom swatch, its three sliders and a flake switch")
	_ok(custom != null and not custom.button_pressed, "hold/Custom is not chosen until it is touched")
	press_text.call("+  SPAWN")
	_eq(sent["options"], {}, "hold/untouched, SPAWN forces nothing")

	view._show_cart_spawn_options("n64", "Selftest", spawn)
	custom = panel_part.call("ShellCustom") as Button
	hue = panel_part.call("ShellHue") as HSlider
	hue.value = 10.0
	var want := "#" + Color.from_hsv(10.0 / 360.0, SpawnMenuSpawnView.CUSTOM_SHELL_START.s,
		SpawnMenuSpawnView.CUSTOM_SHELL_START.v).to_html(false)
	_ok(custom.button_pressed and custom.text.contains(want),
		"hold/moving a slider picks Custom and shows its colour", custom.text)
	press_text.call("+  SPAWN")
	_eq(sent["options"], {"shell_color": want}, "hold/SPAWN hands on the mixed colour alone")

	view._show_cart_spawn_options("n64", "Selftest", spawn)
	(panel_part.call("ShellFlake") as BaseButton).button_pressed = true
	custom = panel_part.call("ShellCustom") as Button
	_ok(custom.button_pressed and custom.text.contains("metal flakes"),
		"hold/the flake switch picks Custom too", custom.text)
	press_text.call("+  SPAWN")
	var flaked: Dictionary = sent["options"]
	_ok(flaked.get("shell_flake", false) == true and str(flaked.get("shell_color", "")).begins_with("#")
		and not flaked.has("shell_preset"), "hold/and SPAWN hands on the flake with the colour", str(flaked))

	view._show_cart_spawn_options("n64", "Selftest", spawn)
	(panel_part.call("ShellFlake") as BaseButton).button_pressed = true
	press_text.call("Blue")
	press_text.call("+  SPAWN")
	_eq(sent["options"], {"shell_preset": "blue"}, "hold/a palette swatch after mixing drops the mix")

	# The colour wheel beside the sliders: each follows the other.
	view._show_cart_spawn_options("n64", "Selftest", spawn)
	await get_tree().process_frame
	var wheel := panel_part.call("ShellWheel") as HsvWheel
	hue = panel_part.call("ShellHue") as HSlider
	var sat := panel_part.call("ShellSaturation") as HSlider
	var bright := panel_part.call("ShellBrightness") as HSlider
	custom = panel_part.call("ShellCustom") as Button
	_ok(wheel != null and wheel.size.x > 0.0, "hold/a colour wheel sits beside the sliders")
	hue.value = 200.0
	_ok(is_equal_approx(wheel.hue, 200.0 / 360.0), "hold/the hue slider turns the wheel's marker")
	# The top of the disc is a quarter turn round from red: 90 degrees, full saturation.
	wheel.pick_at(Vector2(wheel.size.x * 0.5, HsvWheel.MARKER_RADIUS))
	_ok(is_equal_approx(hue.value, 90.0) and is_equal_approx(sat.value, 100.0) and custom.button_pressed,
		"hold/a pick on the wheel sets hue and saturation and picks Custom", "%s %s" % [hue.value, sat.value])
	var hover := InputEventMouseMotion.new()
	hover.position = Vector2(wheel.size.x - HsvWheel.MARKER_RADIUS, wheel.size.y * 0.5)
	wheel._gui_input(hover)
	_ok(is_equal_approx(hue.value, 90.0), "hold/the pointer passing over the wheel picks nothing")
	var drag := hover.duplicate() as InputEventMouseMotion
	drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	wheel._gui_input(drag)
	_ok(is_equal_approx(hue.value, 0.0) and is_equal_approx(sat.value, 100.0),
		"hold/dragging with the trigger held picks: the right-hand rim is red", str(hue.value))
	wheel.pick_at(wheel.size * 0.5)
	_ok(is_equal_approx(sat.value, 0.0), "hold/the centre of the wheel is unsaturated")
	press_text.call("Blue")
	wheel.pick_at(wheel.size * 0.5)
	press_text.call("+  SPAWN")
	_eq(sent["options"], {"shell_color": "#" + Color.from_hsv(0.0, 0.0, bright.value / 100.0).to_html(false)},
		"hold/a wheel pick that moves no slider still picks Custom over a swatch")

	view._show_cart_spawn_options("gb", "Selftest", spawn)
	_ok(panel_part.call("ShellCustom") != null, "hold/a Game Boy cartridge can be mixed too")
	view._close_spawn_options_panel()


# ── delete/ — the trash can on a poster, video, DVD or album row ────────────

const DELETE_ROOT := "user://__spawn_menu_delete_selftest"


## The delete takes its root as an argument, so this whole group runs against a
## scratch folder and never goes near the player's posters or music. The view has
## no _ready and tolerates a null menu, so the REAL row builder and the REAL press
## handler are what gets driven — only the toast goes nowhere.
func _group_delete() -> void:
	var root := ProjectSettings.globalize_path(DELETE_ROOT)
	RomLibrary._remove_tree(root)
	DirAccess.make_dir_recursive_absolute(root)

	# What the scans hand over: a loose file, and a folder with things inside it
	# that no scan lists (cover art, a nested VIDEO_TS).
	var song := root.path_join("song.mp3")
	var other := root.path_join("other.mp3")
	var album := root.path_join("Album")
	_touch(song)
	_touch(other)
	_touch(album.path_join("01.flac"))
	_touch(album.path_join("cover.jpg"))
	_touch(album.path_join("VIDEO_TS").path_join("VTS_01_1.VOB"))
	# And a neighbour OUTSIDE the root, which nothing may ever reach.
	var outside_dir := root + "_outside"
	var outside := outside_dir.path_join("keep.mp3")
	_touch(outside)

	_ok(RomLibrary.is_library_entry(song, root), "delete/a file in the root is an entry")
	_ok(RomLibrary.is_library_entry(album, root), "delete/so is an album folder")
	_ok(not RomLibrary.is_library_entry(root, root), "delete/the root itself is not")
	_ok(not RomLibrary.is_library_entry(root + "/", root), "delete/nor with a trailing slash")
	_ok(not RomLibrary.is_library_entry(album.path_join("01.flac"), root),
		"delete/nor is a track inside an album")
	_ok(not RomLibrary.is_library_entry(root.path_join("../" + outside_dir.get_file() + "/keep.mp3"), root),
		"delete/nor a path that climbs out with ..")
	_ok(not RomLibrary.is_library_entry("", root) and not RomLibrary.is_library_entry(song, ""),
		"delete/nor anything empty")

	_ok(not RomLibrary.delete_library_entry(outside, root), "delete/a path outside the root is refused")
	_ok(not RomLibrary.delete_library_entry(root, root), "delete/and so is the root")
	_ok(FileAccess.file_exists(outside) and FileAccess.file_exists(song),
		"delete/a refusal removes nothing")

	# The real row, the real handler.
	var view := SpawnMenuSpawnView.new()
	add_child(view)
	_spawned.append(view)
	var vbox := VBoxContainer.new()
	view.add_child(vbox)
	var dels := {}
	for path: String in [song, other, album]:
		var spawn_btn := Button.new()
		spawn_btn.custom_minimum_size = Vector2(0, 72)
		view._add_media_row(vbox, spawn_btn, path, root)
		dels[path] = spawn_btn.get_parent().get_node("Delete")
	await get_tree().process_frame
	var trash := String.chr(MenuIcons.DELETE_FOREVER)
	var warn := String.chr(MenuIcons.ERROR)
	_eq((dels[song] as Button).text, trash, "delete/a row starts as a trash can")

	(dels[song] as Button).pressed.emit()
	_ok(FileAccess.file_exists(song), "delete/one tap deletes nothing")
	_eq((dels[song] as Button).text, warn, "delete/it arms, and says so")

	(dels[other] as Button).pressed.emit()
	_ok(FileAccess.file_exists(song) and FileAccess.file_exists(other),
		"delete/a tap on a second row is that row's FIRST tap")
	_eq([(dels[song] as Button).text, (dels[other] as Button).text], [trash, warn],
		"delete/and stands the first row down")

	(dels[song] as Button).pressed.emit()
	_ok(FileAccess.file_exists(song), "delete/so the first row needs two taps again")
	(dels[song] as Button).pressed.emit()
	_ok(not FileAccess.file_exists(song), "delete/the second tap deletes the file")
	_ok(FileAccess.file_exists(other), "delete/and only that file")

	# A rebuild inside the arm window: the new button inherits the warning.
	(dels[other] as Button).pressed.emit()
	var rebuilt_spawn := Button.new()
	view._add_media_row(vbox, rebuilt_spawn, other, root)
	var rebuilt: Button = rebuilt_spawn.get_parent().get_node("Delete")
	_eq(rebuilt.text, warn, "delete/a row rebuilt while armed is still armed")
	view._disarm_media_delete()
	_eq(rebuilt.text, trash, "delete/and it is the rebuilt button the timeout stands down")
	rebuilt.pressed.emit()
	_ok(FileAccess.file_exists(other), "delete/after the timeout a tap only arms again")

	(dels[album] as Button).pressed.emit()
	(dels[album] as Button).pressed.emit()
	_ok(not DirAccess.dir_exists_absolute(album), "delete/an album folder goes with everything in it")
	_ok(FileAccess.file_exists(outside), "delete/the folder next door is untouched")

	# The poster thumbnail is memoized by path, misses included.
	view._poster_thumb_cache[other] = null
	view._poster_thumb_order.append(other)
	rebuilt.pressed.emit()
	rebuilt.pressed.emit()
	_ok(not FileAccess.file_exists(other), "delete/(the poster stand-in was deleted)")
	_ok(not view._poster_thumb_cache.has(other) and not view._poster_thumb_order.has(other),
		"delete/a deleted poster leaves the thumbnail cache")

	RomLibrary._remove_tree(root)
	RomLibrary._remove_tree(outside_dir)
	_ok(not DirAccess.dir_exists_absolute(root) and not DirAccess.dir_exists_absolute(outside_dir),
		"delete/the scratch folders are gone afterwards")


func _touch(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("x")
	f.close()


# ── discs/ — which disc a file is, and the glyph that says so ─────────────────

## The numerals are a TABLE because the font's run is not regular: the filled 5
## sits one codepoint past where the stride of three puts it, and what IS at the
## stride is the outlined 5 — a glyph that renders, so has_char cannot tell the
## two apart and the codepoints are pinned here instead.
func _group_discs() -> void:
	_eq(MenuIcons.disc_number("Final Fantasy VII (USA) (Disc 2).cue"), 2,
		"discs/Redump's (Disc N) is read")
	_eq(MenuIcons.disc_number("Riven (USA) (Disk 5 of 5).chd"), 5,
		"discs/so is (Disk N of M), and it is N")
	_eq(MenuIcons.disc_number("Some Game [CD3].bin"), 3, "discs/and a bracketed [CDN]")
	_eq(MenuIcons.disc_number("Some Game (Disc 12).chd"), 12, "discs/two digits are one number")
	_eq(MenuIcons.disc_number("Disc Station 98 (Japan).chd"), 0,
		"discs/the word in a TITLE names no disc")
	_eq(MenuIcons.disc_number("Final Fantasy VII (USA).m3u"), 0,
		"discs/a playlist of every disc is no one disc")

	_eq(MenuIcons.disc_badge(1), String.chr(0xF03A4), "discs/disc 1 is md-numeric_1_box")
	_eq(MenuIcons.disc_badge(2), String.chr(0xF03A7), "discs/disc 2 is md-numeric_2_box")
	_eq(MenuIcons.disc_badge(5), String.chr(0xF03B1),
		"discs/disc 5 is the FILLED box, one past the stride")
	_eq(MenuIcons.disc_badge(0), "", "discs/no disc draws nothing")
	_eq(MenuIcons.disc_badge(12), "12", "discs/past the font's last box it is the plain number")

	# The main list reads a row's disc off one of two names.
	_eq(MenuIcons.disc_number(SpawnMenuSpawnView._row_filename(
		"C:/roms/psx/Game (USA) (Disc 2).cue", {"fs_name": "Game (USA) (Disc 1).chd"})), 2,
		"discs/a downloaded row is numbered by its own file, not the server's")
	_eq(MenuIcons.disc_number(SpawnMenuSpawnView._row_filename(
		"", {"fs_name": "Game (USA) (Disc 3).chd"})), 3,
		"discs/a row still on the server is numbered by the name RomM holds")
	_eq(MenuIcons.disc_number(SpawnMenuSpawnView._row_filename(
		"C:/roms/psx/Game (USA) (Disc 4)/Game.cue", {})), 4,
		"discs/a disc nested in a folder is numbered by the folder")
	_eq(MenuIcons.disc_number(SpawnMenuSpawnView._row_filename(
		"C:/roms (Disc 9)/psx/Game.cue", {})), 0,
		"discs/but nothing above that folder is read")

	var font: Font = load(MenuIcons.FONT_PATH)
	var missing: Array = []
	for disc: int in MenuIcons.DISC_BOXES:
		if not font.has_char(MenuIcons.DISC_BOXES[disc]):
			missing.append(disc)
	_ok(missing.is_empty(), "discs/the shipped font holds every box in the table", str(missing))


# ── variants/ — the game info page and the ROM Variants panel over it ─────────

## The star handler saves and then reloads the list, which would be the player's
## real gamelist.json. Held in memory instead: the panels are what is under test.
class _MemoryGamelists extends GamelistManager:
	func save_gamelist(_systemid: String) -> void:
		pass

	func invalidate(_systemid: String) -> void:
		pass


## Both panels are plain Controls parented to the view's PARENT, so the real ones
## can be built under a holder with no viewport anywhere. The view itself has no
## _ready, which is why it can stand in the tree here without assembling a menu.
func _group_variants() -> void:
	const SYS := "zz_variants"
	var holder := Control.new()
	add_child(holder)
	_spawned.append(holder)
	var browser := SystemGridBrowser.new()
	holder.add_child(browser)
	var view := SpawnMenuSpawnView.new()
	holder.add_child(view)
	view._cartridges_browser = browser
	view.core_db = CoreInfoDatabase.new()
	view.core_defaults = CoreDefaults.new()
	view.gamelist_manager = _MemoryGamelists.new()

	var disc1 := "Two Discs (USA) (Disc 1).cue"
	var disc2 := "Two Discs (Japan) (Disc 2).cue"
	var game := {"game_id": "1", "name": "Two Discs", "roms": [
		{"path": "./" + disc1, "romname": disc1, "region": "USA", "preferred": true},
		{"path": "./" + disc2, "romname": disc2, "region": "Japan"},
	]}
	view.gamelist_manager._gamelists[SYS] = {"games": [game]}
	var abs1 := GamelistManager.to_absolute_path(SYS, "./" + disc1)
	var abs2 := GamelistManager.to_absolute_path(SYS, "./" + disc2)
	var usa := "%s  USA" % MenuIcons.region_flag("USA")
	var japan := "%s  Japan" % MenuIcons.region_flag("Japan")

	view._show_game_detail_panel(game, SYS, abs1)
	var texts := _label_texts(view._game_detail_panel)
	_ok(texts.has(abs1) and texts.has(usa),
		"variants/the info page names the file's region beside the file", str(texts))

	view._show_rom_variants_panel(game, SYS)
	await get_tree().process_frame
	var discs: Array = []
	for n: Node in view._rom_variants_panel.find_children("Disc", "Label", true, false):
		discs.append((n as Label).text)
	_eq(discs, [MenuIcons.disc_badge(1), MenuIcons.disc_badge(2)],
		"variants/each row carries its own disc's numeral")

	var spawned: Array = []
	view.spawn_cartridge_requested.connect(
		func(path: String, _label: String, _systemid: String, _options: Dictionary) -> void:
			spawned.append(path))
	var spawn_btns := view._rom_variants_panel.find_children("Spawn", "Button", true, false)
	_eq(spawn_btns.size(), 2, "variants/every row has a spawn button")
	if spawn_btns.size() == 2:
		(spawn_btns[1] as Button).pressed.emit()
	_eq(spawned, [abs2], "variants/and it spawns THAT row's file, once")

	# Star the other disc. The page underneath described disc 1.
	for n: Node in view._rom_variants_panel.find_children("*", "Button", true, false):
		if (n as Button).text == "☆":
			(n as Button).pressed.emit()
			break
	texts = _label_texts(view._game_detail_panel)
	_ok(texts.has(abs2) and texts.has(japan) and not texts.has(abs1),
		"variants/starring a file rewrites the info page under the panel", str(texts))
	_ok(view._rom_variants_panel != null and view._rom_variants_panel.is_inside_tree()
		and view._rom_variants_panel.get_index() > view._game_detail_panel.get_index(),
		"variants/and the variants panel is still open, on top of it")


func _label_texts(root: Node) -> Array:
	var out: Array = []
	for n: Node in root.find_children("*", "Label", true, false):
		out.append((n as Label).text)
	return out


# ── toasts/ — the bar stack's pop-out quad, under a download's updates ────────
#
# The real quad is a Viewport2Din3D, which hangs a headless run, so these count
# instead of drawing: a panel that counts refreshes, a curve that counts builds.

class _CountingToastPanel extends ToastPanel:
	var refreshes := 0

	func refresh() -> void:
		refreshes += 1


## A pickable whose grip the test holds: is_picked_up() is what a hand or desktop
## grab answers, without a grab driver behind it.
class _HeldPickable extends XRToolsPickable:
	var held := false

	func is_picked_up() -> bool:
		return held


## A laser that claims one object. Every lifecycle hook is stubbed — the real
## pickup wants a controller above it.
class _RayStub extends XRToolsFunctionPickup:
	var target: XRToolsPickable = null

	func _ready() -> void:
		pass

	func _enter_tree() -> void:
		pass

	func _process(_delta: float) -> void:
		pass

	func _physics_process(_delta: float) -> void:
		pass

	func is_ray_grabbing_target(t: XRToolsPickable) -> bool:
		return t != null and t == target


func _trash_body(at: Vector3, spawned: bool) -> _HeldPickable:
	var body := _HeldPickable.new()
	body.freeze = true
	body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	body.collision_layer = 4
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.05, 0.05, 0.05)
	shape.shape = box
	body.add_child(shape)
	if spawned:
		body.add_to_group("spawned")
	add_child(body)
	_spawned.append(body)
	body.global_position = at
	return body


func _trash_settle() -> void:
	for i in 4:
		await get_tree().physics_frame
		await get_tree().process_frame


## The bin at the menu's corner: an object carried into it turns red, one carried
## out again is left alone, and one let go inside it is deleted — whether it came
## in by hand or on the laser. Things not spawned pass through, and a hidden menu
## takes no bin with it.
func _group_trash() -> void:
	var holder := Node3D.new()
	add_child(holder)
	_spawned.append(holder)
	var bin := MenuTrashBin.new()
	holder.add_child(bin)
	holder.global_position = Vector3(0, 50, 0)
	await _trash_settle()
	var at := bin.global_position
	var away := at + Vector3(1, 0, 0)

	_ok(bin.lid_openness() < 0.01, "trash/the lid rests shut")
	var hand := _trash_body(at, true)
	hand.held = true
	await _trash_settle()
	_ok(bin.is_armed(), "trash/a held object over the bin arms it")
	await _wait_until(func() -> bool: return bin.lid_openness() > 0.95, 3.0)
	_ok(bin.lid_openness() > 0.95, "trash/and the lid swings open", str(bin.lid_openness()))
	hand.global_position = away
	await _trash_settle()
	_ok(not bin.is_armed(), "trash/carried out again it disarms")
	await _wait_until(func() -> bool: return bin.lid_openness() < 0.05, 3.0)
	_ok(bin.lid_openness() < 0.05, "trash/and the lid shuts", str(bin.lid_openness()))
	hand.held = false
	await _trash_settle()
	_ok(is_instance_valid(hand) and not Vanish.is_vanishing(hand),
		"trash/and letting go outside deletes nothing")
	hand.held = true
	hand.global_position = at
	await _trash_settle()
	await get_tree().create_timer(0.5).timeout
	hand.held = false
	await _trash_settle()
	_ok(not is_instance_valid(hand) or Vanish.is_vanishing(hand),
		"trash/let go over the bin, it is deleted")
	_ok(bin.lid_openness() > 0.5, "trash/the lid stays open while it shrinks away",
		str(bin.lid_openness()))
	var mouth := bin.get_node("Mouth") as Node3D
	await get_tree().create_timer(0.26).timeout
	_ok(is_instance_valid(hand) and hand.global_position.distance_to(mouth.global_position) < 0.02
			and hand.scale.x < 0.6,
		"trash/it shrinks into the can's mouth rather than falling",
		str(hand.global_position - mouth.global_position) if is_instance_valid(hand) else "freed")
	_eq(Vanish._exit, Vanish.Exit.FALL, "trash/and other deletes fall as before")
	await _wait_until(func() -> bool: return bin.lid_openness() < 0.05, 5.0)
	_ok(bin.lid_openness() < 0.05, "trash/then shuts", str(bin.lid_openness()))

	var laser := _RayStub.new()
	laser.add_to_group(XRToolsFunctionPickup.PICKUP_GROUP)
	add_child(laser)
	_spawned.append(laser)
	var rayed := _trash_body(at, true)
	laser.target = rayed
	await _trash_settle()
	_ok(bin.is_armed(), "trash/a laser-carried object arms it too")
	laser.target = null
	await _trash_settle()
	_ok(not is_instance_valid(rayed) or Vanish.is_vanishing(rayed),
		"trash/and is deleted when the laser lets go")

	var fixture := _trash_body(at, false)
	fixture.held = true
	await _trash_settle()
	_ok(not bin.is_armed(), "trash/an object nobody spawned is not taken")
	fixture.held = false

	bin.visible = false
	await _trash_settle()
	_ok(not bin.get_node("TrashArea").monitoring, "trash/hidden, the bin stops watching")


## An item menu over whatever it belongs to, with the 2D page swapped for a bare
## box: the rows are built into whatever _lock_box hands back, and a real
## Viewport2Din3D hangs headless.
class _ItemPanel extends FloatingObjectPanel3D:
	var subject: Node3D = null
	var box: VBoxContainer = null

	func _target_node() -> Node3D:
		return subject

	func _lock_box() -> BoxContainer:
		return box


func _item_panel(subject: Node3D) -> _ItemPanel:
	var panel := _ItemPanel.new()
	panel.subject = subject
	panel.box = VBoxContainer.new()
	add_child(panel)
	panel.add_child(panel.box)
	_spawned.append(panel)
	panel._ensure_lock_row()
	return panel


func _row_names(box: BoxContainer) -> Array:
	var names: Array = []
	for c in box.get_children():
		names.append(str(c.name))
	return names


## Every item menu whose object a bin could take has Delete, just above Lock in
## place. One press only asks; a second within a few seconds deletes and closes
## the menu.
func _group_item_delete() -> void:
	var thing := _trash_body(Vector3(3, 50, 0), true)
	var panel := _item_panel(thing)
	_eq(_row_names(panel.box), ["DeleteRow", "LockRow"],
		"item_delete/a spawned object's menu has Delete just above the lock")
	panel.visible = true
	var btn: Button = panel._delete_btn
	_ok(btn.text.ends_with("Delete"), "item_delete/the row reads Delete", btn.text)
	btn.pressed.emit()
	_ok(is_instance_valid(thing) and not Vanish.is_vanishing(thing),
		"item_delete/one press deletes nothing")
	_ok(btn.text.ends_with("Tap again to delete"), "item_delete/it asks again", btn.text)
	panel._tick_delete_prompt(DELETE_WAIT)
	_ok(btn.text.ends_with("Delete") and panel._delete_confirm == 0.0,
		"item_delete/left alone, the question lapses", btn.text)
	btn.pressed.emit()
	btn.pressed.emit()
	_ok(not is_instance_valid(thing) or Vanish.is_vanishing(thing),
		"item_delete/two presses delete it")
	_ok(not panel.visible, "item_delete/and close its menu")
	var stood := Vector3(3, 50, 0)
	await get_tree().create_timer(0.26).timeout
	_ok(is_instance_valid(thing) and thing.global_position.distance_to(stood) < 0.001
			and thing.scale.x < 0.6,
		"item_delete/it shrinks where it stands rather than falling",
		str(thing.global_position - stood) if is_instance_valid(thing) else "freed")
	_eq(Vanish._exit, Vanish.Exit.FALL, "item_delete/and other deletes fall as before")

	var fixture := _trash_body(Vector3(4, 50, 0), false)
	var fixed_panel := _item_panel(fixture)
	_eq(_row_names(fixed_panel.box), ["LockRow"],
		"item_delete/the room's own furniture can be locked but not deleted")


const DELETE_WAIT := FloatingObjectPanel3D.DELETE_CONFIRM_SECONDS + 0.1


## The rows of `page` for `picks` only, in row order, as [pick, distance text].
## Other groups leave spawned bodies about, so a case reads only its own.
func _object_rows(page: SceneObjectsPage, picks: Array) -> Array:
	var out := []
	for id: int in page._ids:
		var r: Dictionary = page._rows[id]
		if r["pick"] in picks:
			out.append([r["pick"], (r["dist"] as Label).text])
	return out


func _object_row(page: SceneObjectsPage, pick: Node) -> Dictionary:
	for id: int in page._ids:
		if page._rows[id]["pick"] == pick:
			return page._rows[id]
	return {}


## SCENE > Objects: every deletable spawned object, nearest first, its distance
## to two places, and the item menu's two-tap Delete.
func _group_objects() -> void:
	var eye := Node3D.new()
	add_child(eye)
	_spawned.append(eye)
	eye.global_position = Vector3(20, 50, 0)
	var far := _trash_body(Vector3(22.5, 50, 0), true)
	var near := _trash_body(Vector3(21, 50, 0), true)
	var fixture := _trash_body(Vector3(20.5, 50, 0), false)
	# A lead: the node in "spawned" is not a pickable, the plug under it is.
	var lead := Node3D.new()
	lead.name = "CompositeCable"
	lead.add_to_group("spawned")
	add_child(lead)
	_spawned.append(lead)
	var plug := _HeldPickable.new()
	plug.freeze = true
	lead.add_child(plug)
	plug.global_position = Vector3(23, 50, 0)

	var page := SceneObjectsPage.create()
	page.camera_override = eye
	add_child(page)
	_spawned.append(page)
	page.refresh()
	var rows := _object_rows(page, [near, far, fixture, plug])
	_eq(rows.map(func(r: Array) -> Node: return r[0]), [near, far, plug],
		"objects/spawned objects listed nearest first, the furniture not at all")
	_eq(rows.map(func(r: Array) -> String: return r[1]), ["1.00 m", "2.50 m", "3.00 m"],
		"objects/distance in metres to two places")
	_eq(_object_row(page, plug).get("name", ""), "Composite Cable",
		"objects/a lead is one row, named for the lead and not its plug")
	# A device's captive cable: in "spawned" at the scene root, its end a CablePlug.
	# Deleting that would orphan the device's rope, so it is no row at all.
	var captive_cable := Node3D.new()
	captive_cable.add_to_group("spawned")
	add_child(captive_cable)
	_spawned.append(captive_cable)
	var captive := _StubCablePlug.new()
	captive.freeze = true
	captive_cable.add_child(captive)
	captive.global_position = Vector3(21.5, 50, 0)
	page.refresh()
	_ok(not SceneObjectsPage.collect(get_tree()).has(captive_cable.get_instance_id()),
		"objects/a device's captive cable is not listed")

	var far_row: Control = _object_row(page, far)["row"]
	far.global_position = Vector3(20.2, 50, 0)
	page.refresh()
	rows = _object_rows(page, [near, far, plug])
	_eq(rows.map(func(r: Array) -> Node: return r[0]), [far, near, plug],
		"objects/walking about re-sorts the list")
	_eq(rows[0][1], "0.20 m", "objects/and re-reads the distance")
	_ok(_object_row(page, far)["row"] == far_row,
		"objects/moving only re-orders rows, it does not rebuild them")

	var del: Button = _object_row(page, near)["delete"]
	del.pressed.emit()
	_ok(is_instance_valid(near) and not Vanish.is_vanishing(near),
		"objects/one press of Delete deletes nothing")
	_eq(del.text, "Tap again", "objects/it asks again")
	page._process(SceneObjectsPage.DELETE_CONFIRM_SECONDS + 0.1)
	del = _object_row(page, near)["delete"]
	_eq(del.text, "Delete", "objects/left alone, the question lapses")
	del.pressed.emit()
	del.pressed.emit()
	_ok(not is_instance_valid(near) or Vanish.is_vanishing(near),
		"objects/two presses delete it")
	_ok(_object_row(page, near).is_empty(), "objects/and its row goes")
	_ok(not _object_row(page, far).is_empty(), "objects/and nothing else's")

	_eq(SceneObjectsPage.name_of(_named_node("SuperThing")), "Super Thing",
		"objects/an unnamed kind of object reads as its node name")
	var labelled := _GameLabelled.new()
	labelled.game_label = "Super Mario World"
	_eq(SceneObjectsPage.name_of(labelled), "Super Mario World",
		"objects/a cartridge reads as its game")
	labelled.free()


func _named_node(n: String) -> Node:
	var node := Node.new()
	node.name = n
	add_child(node)
	_spawned.append(node)
	return node


## A CablePlug without its _ready, which wants a host to take a colour from.
class _StubCablePlug extends CablePlug:
	func _ready() -> void:
		pass


class _GameLabelled extends Node:
	var game_label := ""


## Locate's arrow: hidden while the object is in view, at the edge pointing the
## way to turn otherwise, always left or right when it is behind, and gone with
## the object.
func _group_locate() -> void:
	_eq(LocateArrow.place(Vector3(0, 0, -1))["shown"], false,
		"locate/straight ahead, no arrow")
	_eq(LocateArrow.place(Vector3(0.3, 0, -1))["shown"], false,
		"locate/inside the found cone, no arrow")
	var right := LocateArrow.place(Vector3(1, 0, -0.2))
	_ok(right["shown"] and absf(right["bearing"] - PI / 2.0) < 0.01,
		"locate/to the right, it points right", str(right))
	var up := LocateArrow.place(Vector3(0, 1, -0.3))
	_ok(up["shown"] and absf(up["bearing"]) < 0.01, "locate/above, it points up", str(up))
	var behind_left := LocateArrow.place(Vector3(-0.2, 0.5, 1))
	_ok(behind_left["shown"] and absf(behind_left["bearing"] + PI / 2.0) < 0.01,
		"locate/behind and to the left, it points left -- never up", str(behind_left))
	var behind := LocateArrow.place(Vector3(0, 0, 1))
	_ok(behind["shown"] and absf(absf(behind["bearing"]) - PI / 2.0) < 0.01,
		"locate/dead behind, it still says which way to turn", str(behind))

	var eye := Node3D.new()
	add_child(eye)
	_spawned.append(eye)
	eye.global_position = Vector3(30, 50, 0)
	var thing := _trash_body(Vector3(32, 50, 0), true)
	var arrow := LocateArrow.on(eye)
	_ok(LocateArrow.on(eye) == arrow, "locate/one arrow per camera")
	arrow.locate(thing, "thing")
	await get_tree().process_frame
	await get_tree().process_frame
	_ok(arrow.visible and arrow.position.x > 0.0,
		"locate/the arrow is up, on the side the object is", str(arrow.position))
	thing.global_position = Vector3(30, 50, -2)
	await get_tree().process_frame
	_ok(not arrow.visible and arrow.is_locating(),
		"locate/turned to face it, the arrow hides but keeps tracking")
	thing.global_position = Vector3(30, 50, 2)
	await get_tree().process_frame
	thing.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	_ok(not arrow.is_locating() and not arrow.visible,
		"locate/a deleted object ends the locate")


class _CountingCurve extends CurvedPanel:
	var builds := 0
	var radius := 1.4

	func set_curved(_on: bool, _animate := true) -> void:
		builds += 1

	func axis_radius() -> float:
		return radius

	func surface_pose(_flat_x: float, _y: float, _out: float) -> Transform3D:
		return Transform3D.IDENTITY


## A core download updates its bar every frame and a firmware fetch two or three
## times in one; each update used to queue a refresh of its own, and each
## refresh rebuilt the quad's arc mesh and collision whether anything moved.
func _group_toasts() -> void:
	var toasts := MenuToasts.create()
	add_child(toasts)
	_spawned.append(toasts)
	var counting := _CountingToastPanel.new()
	toasts._panel = counting
	for i in 5:
		toasts.notify("t:%d" % (i % 2), "", "bar %d" % i, i / 5.0)
	await get_tree().process_frame
	_eq(counting.refreshes, 1, "toasts/five updates in one frame refresh the quad once")
	toasts.notify("t:0", "", "again", 0.9)
	await get_tree().process_frame
	_eq(counting.refreshes, 2, "toasts/and the next frame's update refreshes it again")
	toasts._panel = null
	counting.free()

	var panel := ToastPanel.new()
	var host := XRToolsViewport2DIn3D.new()
	var quad := XRToolsViewport2DIn3D.new()
	var host_curve := _CountingCurve.new()
	var arc := _CountingCurve.new()
	panel._host = host
	panel._viewport = quad
	panel._host_curve = host_curve
	panel._curve = arc
	panel.visible = true
	for i in 5:
		panel._place()
	_eq(arc.builds, 1, "toasts/placing an unchanged quad five times builds its arc once")
	host_curve.radius = 2.0
	panel._place()
	_eq(arc.builds, 2, "toasts/a new host radius builds it again")
	host_curve.radius = 0.0
	panel._place()
	panel._place()
	_eq(arc.builds, 3, "toasts/flattening the host builds it once more")

	# The menu put away, the way the controller puts it away: nothing is
	# measured, and the refresh is owed for when it comes back. The stack has a
	# bar in it, so a refresh that ran would hand it a wrap width.
	var stack := MenuToasts.create()
	add_child(stack)
	stack._add("t", "", "a bar", -1.0)
	panel._stack = stack
	host.visible = false
	panel.refresh()
	_ok(panel._stale and is_zero_approx(stack._wrap_width),
		"toasts/a hidden host's quad is not measured, and a refresh is owed",
		"stale=%s wrap=%s" % [panel._stale, stack._wrap_width])
	host.visible = true
	panel._on_host_visibility_changed()
	_ok(not panel._stale and stack._wrap_width > 0.0,
		"toasts/and it is paid when the host is shown again",
		"stale=%s wrap=%s" % [panel._stale, stack._wrap_width])
	stack._panel = null
	for n: Node in [panel, host, quad, host_curve, arc, stack]:
		n.free()


# ── owed/ — rebuilds the spawn tab owes, and when it pays them ────────────────

class _CountingSpawnView extends SpawnMenuSpawnView:
	var systems := 0
	var cartridges := 0
	var detail_reruns := 0
	var rows := 0

	func _populate_systems_tab() -> void:
		systems += 1

	func _populate_cartridges_tab(rerun_detail: bool = true) -> void:
		cartridges += 1
		if rerun_detail:
			detail_reruns += 1

	func _rebuild_romm_rows() -> void:
		rows += 1


## A core serving six systems reported each in one frame, and every report
## rebuilt both grids; a finished download rebuilt its list twice; and all of it
## ran with the menu put away, because the list's systemid outlives its page.
func _group_owed() -> void:
	var view := _CountingSpawnView.new()
	add_child(view)
	_spawned.append(view)
	var browser := SystemGridBrowser.new()
	view._cartridges_browser = browser
	view._menu_shown = true

	for i in 6:
		view.refresh_after_core_change()
	await get_tree().process_frame
	_eq([view.systems, view.cartridges], [1, 1],
		"owed/a core serving six systems rebuilds each grid once")

	view.on_menu_hidden()
	view.refresh_after_core_change()
	view.refresh_after_core_change()
	await get_tree().process_frame
	_eq([view.systems, view.cartridges], [1, 1],
		"owed/nothing is rebuilt while the menu is put away")
	view.on_menu_shown()
	_eq([view.systems, view.cartridges], [2, 2],
		"owed/and it is rebuilt once, as the menu comes back, not a frame later")

	view._romm_detail_systemid = "gba"
	browser._current_systemid = "gba"
	view._romm_sync._on_romm_cache_changed()
	view._romm_sync._on_romm_dl_finished(1, false, "", "probe")
	await get_tree().process_frame
	_eq(view.rows, 1, "owed/a finished download rebuilds the open list once, not twice")

	browser._current_systemid = ""
	view._romm_sync._on_romm_cache_changed()
	await get_tree().process_frame
	_eq(view.rows, 1, "owed/a list whose page has been closed is not rebuilt")

	# Another tab on screen: the CORES tab a core was just installed from.
	view.visible = false
	view.refresh_after_core_change()
	await get_tree().process_frame
	_eq([view.systems, view.cartridges], [2, 2],
		"owed/nothing is rebuilt while another tab is on screen")
	view.visibility_changed.connect(view._on_visibility_changed)
	view.visible = true
	_eq([view.systems, view.cartridges], [3, 3],
		"owed/and it is rebuilt once as its own tab comes back")

	# The open page is gba. A core for other systems redraws the tiles and leaves
	# the page; one for gba, or a scrape, re-runs it.
	browser._current_systemid = "gba"
	var reruns := view.detail_reruns
	view.refresh_after_core_change("genesis")
	view.refresh_after_core_change("segacd")
	await get_tree().process_frame
	_eq([view.cartridges, view.detail_reruns - reruns], [4, 0],
		"owed/a core for another system redraws the tiles, not the open page")
	view.refresh_after_core_change("genesis")
	view.refresh_after_core_change("gba")
	await get_tree().process_frame
	_eq(view.detail_reruns - reruns, 1, "owed/a core for the open system re-runs its page")
	view._owe_detail = true
	view._owe(false, true, false)
	await get_tree().process_frame
	_eq(view.detail_reruns - reruns, 2, "owed/and so does a scrape's refresh")
	browser.free()


# ── art/ — which rows a landed cover or scraped image re-binds ────────────────

class _StubCatalog extends RommCatalog:
	func rom_id_at(i: int) -> int:
		return 100 + i


## Up to six textures land in a frame, and each used to re-bind every row on
## screen. Now only the rows they belong to are, once each, at the frame's end.
func _group_art() -> void:
	var scroll := ScrollContainer.new()
	scroll.size = Vector2(400, 300)
	add_child(scroll)
	_spawned.append(scroll)
	var list := VirtualRowList.new()
	list.row_height = 100
	var bound: Array = []
	list.set_row_builder(func() -> Control: return Control.new())
	list.set_row_binder(func(_row: Control, i: int) -> void: bound.append(i))
	scroll.add_child(list)
	list.set_row_count(5)
	await get_tree().process_frame

	var view := SpawnMenuSpawnView.new()
	add_child(view)
	_spawned.append(view)
	var catalog := _StubCatalog.new()
	view.romm_catalog = catalog
	view._romm_list = list
	view._romm_rows = [
		{"path": "C:/roms/gba/Alpha (USA).gba", "index": -1},
		{"path": "", "index": 1},
		{"path": "", "index": 2},
		{"path": "C:/roms/gba/Beta (Europe).gba", "index": 3},
		{"path": "", "index": 4},
	]
	_eq(list.visible_indices().size(), 5, "art/all five rows are on screen")

	bound.clear()
	var tex := ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))
	view._on_romm_art_ready(102, tex)
	view._on_scraped_art_ready("C:/roms/gba/media/wheel/Beta (Europe).png", tex)
	view._on_romm_art_ready(102, tex)
	_eq(bound, [], "art/nothing is re-bound until the frame ends")
	await get_tree().process_frame
	bound.sort()
	_eq(bound, [2, 3], "art/only the rows whose art landed are re-bound, once each")

	bound.clear()
	view._on_scrape_row_changed("C:/roms/gba/Alpha (USA).gba", "gba")
	await get_tree().process_frame
	_eq(bound, [0], "art/a scrape changing one ROM re-binds that ROM's row")

	bound.clear()
	view._on_romm_art_ready(999, tex)
	await get_tree().process_frame
	_eq(bound, [], "art/art for a row that is not on screen re-binds nothing")
	catalog.free()


# ── scroll/ — what one step of the ROM list costs ─────────────────────────────

## Every pooled row was re-bound whenever the first row on screen changed, so a
## one-row scroll bound fourteen rows on a headset, each parsing its JSON and
## asking the art caches. A row keeps its slot now, and only the rows that come
## into view are bound.
func _group_scroll() -> void:
	var scroll := ScrollContainer.new()
	scroll.size = Vector2(400, 300)
	add_child(scroll)
	_spawned.append(scroll)
	var list := VirtualRowList.new()
	list.row_height = 100
	var bound: Array = []
	list.set_row_builder(func() -> Control: return Control.new())
	list.set_row_binder(func(_row: Control, i: int) -> void: bound.append(i))
	scroll.add_child(list)
	list.set_row_count(50)
	await get_tree().process_frame
	await get_tree().process_frame
	_eq(list.visible_indices(), PackedInt32Array(range(0, 9)), "scroll/the window starts at row 0")

	# Three rows of overscan: the window starts moving at row 4.
	bound.clear()
	scroll.scroll_vertical = 400
	await get_tree().process_frame
	_eq(bound, [9], "scroll/a one-row step binds only the row that came into view")
	_eq(list.visible_indices(), PackedInt32Array(range(1, 10)), "scroll/and the window is rows 1 to 9")

	bound.clear()
	scroll.scroll_vertical = 1000
	await get_tree().process_frame
	bound.sort()
	_eq(bound, [10, 11, 12, 13, 14, 15], "scroll/a six-row jump binds six")

	bound.clear()
	list.rebind_visible()
	_eq(bound.size(), 9, "scroll/a re-bind still binds every row")
	bound.clear()
	list.rebind_index(12)
	list.rebind_index(40)
	_eq(bound, [12], "scroll/one row re-binds on its own, and one off screen not at all")


# ── art lookup/ — scraped art is not looked for on disk at every bind ─────────

const ART_SYSTEM := "__art_selftest"

## resolve() is up to four file_exists calls a kind and a row asks for two, on
## every bind. Where the art is -- or that there is none -- is kept a while, and
## forget(), which a scrape calls when it writes, drops it at once.
func _group_art_lookup() -> void:
	var root := RomLibrary.rom_dir_for_system(ART_SYSTEM)
	RomLibrary._remove_tree(root)
	var wheel_dir := root.path_join("media").path_join("wheel")
	DirAccess.make_dir_recursive_absolute(wheel_dir)
	var rom := root.path_join("Probe (USA).gba")
	var cache := ScrapedArtCache.new()
	add_child(cache)

	_eq(cache.get_or_request(ART_SYSTEM, rom, "wheel"), null, "art lookup/no art, no texture")
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.save_png(wheel_dir.path_join("Probe (USA).png"))
	cache.get_or_request(ART_SYSTEM, rom, "wheel")
	_ok(cache._decoding.is_empty(), "art lookup/a miss is remembered, not looked for again at once")
	cache.forget(ART_SYSTEM, rom)
	cache.get_or_request(ART_SYSTEM, rom, "wheel")
	_eq(cache._decoding.size(), 1, "art lookup/forget() -- what a scrape calls -- finds it")

	for task: int in cache._decoding.values():
		WorkerThreadPool.wait_for_task_completion(task)
	cache._decoding.clear()
	cache.free()
	RomLibrary._remove_tree(root)


# ── idle/ — menu widgets that cost frames while nobody uses them ──────────────

## Three things that kept working after they stopped being seen: a dropdown's
## popout outliving the dropdown, a panel's lock button rewritten every frame,
## and PS2 save icons rendering inside a panel that had been put away.
func _group_idle() -> void:
	var dd := VRDropdown.new()
	add_child(dd)
	var popout := DropdownPanel.new()
	dd._popout = popout
	remove_child(dd)
	await get_tree().process_frame
	_ok(not is_instance_valid(popout), "idle/a dropdown's popout goes when the dropdown does")
	dd.free()

	var panel := FloatingObjectPanel3D.new()
	panel._lock_btn = Button.new()
	panel._refresh_lock_row()
	panel._lock_btn.text = "left alone"
	panel._refresh_lock_row()
	_eq(panel._lock_btn.text, "left alone", "idle/an unchanged lock is not written to the button again")
	panel._lock_btn.free()
	panel.free()

	var host := Node3D.new()
	var vp := SubViewport.new()
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	host.add_child(vp)
	add_child(host)
	var icon := PS2IconView.new()
	vp.add_child(icon)
	icon.show_model({"shapes": [PackedVector3Array([Vector3.ZERO, Vector3.ONE, Vector3.UP])],
		"frames": []})
	host.visible = false
	icon._process(0.5)
	_eq(icon._time, 0.0, "idle/a PS2 icon in a panel that is put away does not move")
	_eq(icon._viewport.render_target_update_mode, SubViewport.UPDATE_DISABLED,
		"idle/nor render")
	host.visible = true
	icon._process(0.5)
	_eq(icon._time, 0.5, "idle/and turns again when the panel is back")
	host.free()


# ── tiles/ — a grid handed the same systems keeps the tiles that did not change ─

## A core finishing an install sends every grid in the menu through set_systems,
## and it rebuilt every tile of each: 126 ms for the CORES tab's Download grid
## and 75 ms for its Manager grid on a Quest 3, for one core. Unchanged tiles stay.
func _group_tiles() -> void:
	var browser := SystemGridBrowser.new()
	add_child(browser)
	_spawned.append(browser)
	await get_tree().process_frame
	var three := [
		{"systemid": "nes", "name": "NES", "badge": "2 cores"},
		{"systemid": "snes", "name": "SNES", "badge": "3 cores", "alt_tile": true},
		{"systemid": "gba", "name": "Game Boy Advance", "badge": "1 core"},
	]
	browser.set_systems(three)
	var before := browser._tile_nodes.duplicate()
	var changed := three.duplicate(true)
	(changed[2] as Dictionary)["alt_tile"] = false
	browser.set_systems(changed)
	var after := browser._tile_nodes.duplicate()
	# Sorted by name: Game Boy Advance, NES, SNES -- the changed one is first.
	_eq([after[0] == before[0], after[1] == before[1], after[2] == before[2]], [false, true, true],
		"tiles/one system changed: only its tile is rebuilt")
	_eq(browser._tiles_grid.get_children().size(), 3, "tiles/and the grid still holds three")
	_eq(_visible_names(browser), ["game boy advance", "nes", "snes"],
		"tiles/in the same order")
	# A tile still queued for deletion is a child until the frame ends, so the
	# grid has to be looked at a frame later: kept tiles must still be there.
	await get_tree().process_frame
	var alive := 0
	for n: Variant in browser._tile_nodes:
		if is_instance_valid(n) and (n as Node).get_parent() == browser._tiles_grid:
			alive += 1
	_eq([alive, browser._tiles_grid.get_children().size()], [3, 3],
		"tiles/and a frame later all three are alive and on the grid")

	var four := changed.duplicate(true)
	four.append({"systemid": "n64", "name": "Nintendo 64"})
	browser.set_systems(four)
	_ok(not browser._tile_nodes.has(after[0]), "tiles/a system added rebuilds the grid")

	var kept := browser._tile_nodes.duplicate()
	browser.allow_compact = true
	var was := AppPrefs.compact_tiles
	AppPrefs.compact_tiles = not was
	browser._rebuild_tiles()
	AppPrefs.compact_tiles = was
	_ok(not browser._tile_nodes.has(kept[0]), "tiles/and so does switching to compact")
