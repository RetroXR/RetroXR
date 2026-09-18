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
		{"systemid": "super_nes", "name": "Super Nintendo", "badge": "2 cores"},
		{"systemid": "game_boy", "name": "Game Boy", "badge": "4 cores"},
		{"systemid": "mega_drive", "name": "Mega Drive", "badge": "1 core"},
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


# ── hold/ — a press held for two seconds opens a sub-menu instead ─────────────

## HoldPress is driven through the button's own signals and its public advance(),
## so two seconds cost nothing. Every case counts BOTH signals: a hold that also
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
	hold.advance(1.9)
	_eq(seen["held"], 0, "hold/nothing opens before two seconds")
	hold.advance(0.2)
	_eq(seen["held"], 1, "hold/two seconds opens the sub-menu, pointer still down")
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
	hold.advance(1.5)
	btn.mouse_exited.emit()
	hold.advance(1.5)
	_eq(seen["held"], 0, "hold/leaving the button gives the hold up")

	hold.hold_enabled = false
	btn.button_down.emit()
	hold.advance(3.0)
	btn.pressed.emit()
	btn.button_up.emit()
	_eq([seen["clicked"], seen["held"]], [1, 0], "hold/switched off, a long press is a click")

	# A pooled row: every listener swept off `pressed`, then rebound mid-hold.
	hold.hold_enabled = true
	btn.button_down.emit()
	hold.advance(2.5)
	for c: Dictionary in btn.pressed.get_connections():
		btn.pressed.disconnect(c["callable"])
	hold.reset()
	hold.ensure_connected()
	seen["clicked"] = 0
	btn.pressed.emit()
	_eq(seen["clicked"], 1, "hold/a rebound row forgets the last entry's hold")

	_ok(SpawnMenuSpawnView._has_spawn_options("nintendo_64")
		and not SpawnMenuSpawnView._has_spawn_options("nes"),
		"hold/only an N64 ROM row opens one")
