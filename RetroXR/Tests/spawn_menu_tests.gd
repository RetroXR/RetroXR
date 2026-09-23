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
extends Node

var _passed := 0
var _failed := 0
var _only := ""
var _spawned: Array[Node] = []


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.substr("--only=".length())
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		push_error("[menu] TIMEOUT")
		get_tree().quit(1))

	await _group_filter()
	await _group_cartridges()
	_group_counts()
	_group_formats()
	_group_fit()
	await _group_hold()
	await _group_delete()
	_group_discs()
	await _group_variants()

	for n: Node in _spawned:
		if is_instance_valid(n):
			n.queue_free()
	print("[menu] %d checks, %d failed" % [_passed + _failed, _failed])
	print("[menu] RESULT=%s" % ("PASS" if _failed == 0 else "FAIL"))
	get_tree().quit(1 if _failed > 0 else 0)


# ── Harness ───────────────────────────────────────────────────────────────────

func _ok(cond: bool, what: String, detail := "") -> void:
	if not (_only.is_empty() or what.begins_with(_only)):
		return
	if cond:
		_passed += 1
		print("[menu] ok   %s" % what)
	else:
		_failed += 1
		print("[menu] FAIL %s%s" % [what, "" if detail.is_empty() else "  -- " + detail])


func _eq(got: Variant, want: Variant, what: String) -> void:
	_ok(got == want, what, "got %s, want %s" % [got, want])


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


# ── formats/ — the strings the options panel prints ───────────────────────────

func _group_formats() -> void:
	_eq(SpawnMenuSpawnView._commas(0), "0", "formats/zero needs no separator")
	_eq(SpawnMenuSpawnView._commas(999), "999", "formats/three digits need no separator")
	_eq(SpawnMenuSpawnView._commas(1000), "1,000", "formats/four digits gain one")
	_eq(SpawnMenuSpawnView._commas(1234567), "1,234,567", "formats/seven digits gain two")

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
		and not SpawnMenuSpawnView._has_spawn_options("nes"),
		"hold/only an N64 or Game Boy ROM row opens one")


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
