## mods_view_probe — how the MODS tab LOOKS, which no suite can say: the menu
## cannot be driven headless, and the dummy renderer draws nothing anyway.
##
##   godot --path RetroXR --resolution 1100x840 --position 20,20 res://Tools/mods/mods_view_probe.tscn
##
## WINDOWED. Builds the real view over a canned catalogue -- no network, mod.io
## is never asked -- with each logo seeded straight into ModArtCache's disk
## cache, and writes PNGs to user://mods_view_probe/: consent (mod.io's terms,
## before anything else is shown), declined, browse, detail, review (the question
## before a download is installed), packs, pack, pack_review, installed and
## installed_detail. The Installed pages are the machine's real mods. The
## player's own answer to mod.io's terms is not read or written: the probe keeps
## its own in its output folder.
##
## With `-- --live` it photographs the REAL catalogue instead: the real client,
## mod.io's own terms, tiles and logos, written as live_consent / live_browse /
## live_detail. It needs the network and still keeps its own answer to the terms.
##
## Every seeded logo has a hard-edged block in one corner, so a picture that is
## stretched, mirrored or cropped off-centre shows as that and not as "a
## gradient, fine".
extends Node

const OUT := "user://mods_view_probe"

## Logos written into the art cache for this run, removed again at the end.
var _seeded := PackedStringArray()


class StubClient extends ModioClient:
	var mods: Array[Dictionary] = []
	var packs: Array[Dictionary] = []

	func list_mods(_search: String, _sort: String, _offset: int, callback: Callable,
			_tag: String = "") -> void:
		if not consent.granted():
			callback.call_deferred(false, mods.slice(0, 0), 0, NEEDS_CONSENT)
			return
		callback.call_deferred(true, mods, 57, "")

	func get_terms(callback: Callable) -> void:
		callback.call_deferred(true, {
			"text": "This game uses mod.io to support user-generated content. By selecting "
				+ "\"I Agree\" you agree to the mod.io Terms of Use and a mod.io account will be "
				+ "created for you (using your display name, avatar and ID). Please see the "
				+ "mod.io Privacy Policy on how mod.io processes your personal data.",
			"agree": "I Agree", "disagree": "No, Thanks",
			"links": [{"text": "Terms of Use", "url": "https://mod.io/terms"},
				{"text": "Privacy Policy", "url": "https://mod.io/privacy"},
				# Six, as the real endpoint sends: enough to overflow a single row.
				{"text": "mod.io", "url": "https://mod.io"},
				{"text": "Refund Policy", "url": "https://mod.io/refund"},
				{"text": "Monetization Policy", "url": "https://mod.io/monetization"},
				{"text": "Manage Account", "url": "https://mod.io/me/account"}]}, "")

	func list_tags(callback: Callable) -> void:
		callback.call_deferred(true, PackedStringArray(
			["Cartridge", "Furniture", "Console", "Controller", "Knick Knack"]), "")

	func list_collections(_search: String, _sort: String, _offset: int, callback: Callable) -> void:
		callback.call_deferred(true, packs, packs.size(), "")

	func list_collection_mods(_id: int, callback: Callable) -> void:
		callback.call_deferred(true, mods.slice(0, 5), 5, "")


class StubMenu extends Node:
	var modio_client: ModioClient = null
	var mod_downloader: ModDownloader = null
	var mod_art: ModArtCache = null

	func notify(_k: String, _i: String, msg: String, _p: float = -1.0, _s: float = 0.0) -> void:
		print("[probe] toast: ", msg)


func _ready() -> void:
	get_tree().create_timer(25.0).timeout.connect(func() -> void:
		print("[probe] TIMEOUT"); get_tree().quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))

	var bg := ColorRect.new()
	bg.color = MenuStyle.COLOR_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var menu := StubMenu.new()
	add_child(menu)
	if OS.get_cmdline_user_args().has("--live"):
		await _live(menu)
		return
	var client := StubClient.new()
	client.consent.state_path = OUT.path_join("consent.json")
	client.consent.withdraw()
	menu.add_child(client)
	menu.modio_client = client
	menu.mod_art = ModArtCache.new()
	menu.add_child(menu.mod_art)
	menu.mod_downloader = ModDownloader.new()
	menu.add_child(menu.mod_downloader)

	var names := ["PlayStation 2", "Super Nintendo", "Arcade Cabinet", "Bedroom, 1998",
		"Sega Saturn", "CRT Shelf Pack", "Neo Geo Pocket"]
	var hues := [0.62, 0.08, 0.95, 0.35, 0.55, 0.15, 0.78]
	for i in range(names.size()):
		var url := "https://probe.invalid/logo_%d.png" % i
		if i != 5:      # one mod with no picture at all
			_seed_logo(url, hues[i], names[i])
		client.mods.append({
			"id": 100 + i, "name": names[i], "summary": "A %s for the room, with its pad and leads. " % names[i]
				+ "This is the text an author writes on the mod's mod.io page.",
			"author": "xenu", "profile_url": "https://mod.io/g/retroxr/m/x%d" % i,
			"logo_small": url if i != 5 else "", "logo_large": url if i != 5 else "",
			"tags": PackedStringArray(["Console"]), "downloads": 1200 - i * 150,
			"rating": "Very Positive", "date_updated": 0,
			"file_id": 0 if i == 6 else 500 + i, "file_name": "pack.zip",
			"file_size": (34 - i * 4) * 1048576, "file_md5": "", "file_version": "1.%d.0" % i,
			"download_url": "https://probe.invalid/dl/%d" % i,
			# One mod.io has not finished scanning: no download is offered for it.
			"virus_status": 0 if i == 4 else 1, "virus_positive": 0,
		})
	for i in range(3):
		client.packs.append({"id": 30 + i, "name": ["Sony shelf", "A 1998 bedroom", "Handhelds"][i],
			"summary": "Every console on one shelf, with the pads and leads each one needs.",
			"author": "xenu", "profile_url": "https://mod.io/g/retroxr/c/p%d" % i,
			"logo_small": "https://probe.invalid/logo_%d.png" % i,
			"logo_large": "https://probe.invalid/logo_%d.png" % i,
			"file_size": (90 - i * 20) * 1048576, "downloads": 400 - i * 90,
			"date_updated": 0, "incomplete": i == 2})

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_top", "margin_bottom", "margin_left", "margin_right"]:
		margin.add_theme_constant_override(side, 14)
	add_child(margin)
	var view := SpawnMenuModsView.create(menu)
	margin.add_child(view)
	view.ensure_fetched()

	# Before the player has answered: mod.io's terms and nothing else.
	await get_tree().create_timer(1.0).timeout
	print("[probe] before consent: tiles=", view._grid.get_child_count(),
		" gate=", view._browse_gate.visible, " list=", view._browse_list.visible)
	await _shot("consent")
	view._declined = true
	view._apply_consent()
	await get_tree().create_timer(0.4).timeout
	await _shot("declined")
	view._declined = false
	client.consent.grant(str(view._terms["text"]))
	view.ensure_fetched()

	await get_tree().create_timer(2.0).timeout
	print("[probe] tiles=", view._grid.get_child_count(), " first tile size=",
		(view._grid.get_child(0) as Control).size)
	await _shot("browse")
	view._open_browse_detail(client.mods[0])
	await get_tree().create_timer(0.6).timeout
	await _shot("detail")

	# The question before a download is installed, over a pack that claims a
	# shipped file. Parked by hand: no file is fetched and none is installed.
	var manifest := ModManifest.parse({"id": "xenu.ps2", "name": "PlayStation 2 (SCPH-30001 R)",
		"version": "0.2.0", "author": "xenu", "api_version": 1,
		"entry": "res://mods/xenu.ps2/mod_main.gd",
		"claims": ["res://Scripts/Mods/retro_mod.gd", "res://Textures/SystemIcons/ps2_gold.svg"]})
	var key := SpawnMenuModsView._job_key(100)
	view.reviews._parked[key] = {"staged": OUT.path_join("none.zip"), "manifest": manifest, "thumbnail": null,
		"source": {"modio_id": 100, "file_id": 500, "profile_url": ""}}
	view._open_single_review(key)
	await get_tree().create_timer(0.6).timeout
	await _shot("review")
	view.reviews._parked.erase(key)
	view._close_single_review()

	view._tabs.current_tab = SpawnMenuModsView.PACKS_TAB
	await get_tree().create_timer(1.0).timeout
	await _shot("packs")
	var page := view._packs_page
	page._open(client.packs[0])
	await get_tree().create_timer(1.0).timeout
	await _shot("pack")
	# The one question for a whole pack: two members after the same file, and
	# one that could not be fetched.
	var second := ModManifest.parse({"id": "xenu.psx", "name": "PlayStation", "version": "1.1.0",
		"author": "xenu", "api_version": 1, "entry": "res://mods/xenu.psx/mod_main.gd",
		"claims": ["res://Scripts/Mods/retro_mod.gd"]})
	var key2 := SpawnMenuModsView._job_key(101)
	view.reviews._parked[key] = {"staged": "", "manifest": manifest, "thumbnail": null, "source": {}}
	view.reviews._parked[key2] = {"staged": "", "manifest": second, "thumbnail": null, "source": {}}
	page._batch = {"id": 30, "name": "Sony shelf", "keys": {key: client.mods[0], key2: client.mods[1]},
		"done": [key, key2], "staged": [key, key2], "have": [client.mods[2]],
		"skip": [{"name": "Sega Saturn", "why": "mod.io has not finished scanning this file"}]}
	page._fill_review()
	page._show(page._review)
	await get_tree().create_timer(0.6).timeout
	await _shot("pack_review")
	page._batch = {}
	view.reviews._parked.clear()

	view._tabs.current_tab = SpawnMenuModsView.INSTALLED_TAB
	await get_tree().create_timer(0.6).timeout
	await _shot("installed")
	var first: Array = Mods.all_mods()
	if not first.is_empty():
		view._open_installed_detail((first[0] as ModRecord).id)
		await get_tree().create_timer(0.6).timeout
		await _shot("installed_detail")
	for path: String in _seeded:
		DirAccess.remove_absolute(path)
	client.consent.withdraw()
	get_tree().quit(0)


## The real mod.io, through the real client and art cache.
func _live(menu: StubMenu) -> void:
	var client := ModioClient.new()
	client.consent.state_path = OUT.path_join("consent.json")
	client.consent.withdraw()
	menu.add_child(client)
	menu.modio_client = client
	menu.mod_art = ModArtCache.new()
	menu.add_child(menu.mod_art)
	menu.mod_downloader = ModDownloader.new()
	menu.add_child(menu.mod_downloader)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_top", "margin_bottom", "margin_left", "margin_right"]:
		margin.add_theme_constant_override(side, 14)
	add_child(margin)
	var view := SpawnMenuModsView.create(menu)
	margin.add_child(view)
	view.ensure_fetched()
	await get_tree().create_timer(4.0).timeout
	print("[probe] live terms fetched=", not view._terms.is_empty(), " error='", view._terms_error, "'")
	await _shot("live_consent")
	if view._terms.is_empty():
		get_tree().quit(1)
		return
	client.consent.grant(str(view._terms["text"]))
	view.ensure_fetched()
	await get_tree().create_timer(6.0).timeout
	print("[probe] live tiles=", view._grid.get_child_count(), " status='", view._status_lbl.text, "'")
	await _shot("live_browse")
	if not view._mods.is_empty():
		view._open_browse_detail(view._mods[0])
		await get_tree().create_timer(4.0).timeout
		var large := str(view._mods[0]["logo_large"])
		print("[probe] live large logo: in memory=", menu.mod_art._textures.has(large),
			" dead=", menu.mod_art._dead.has(large), " waiting=", view._art_waiters.has(large))
		await _shot("live_detail")
	client.consent.withdraw()
	get_tree().quit(0)


func _seed_logo(url: String, hue: float, text: String) -> void:
	var img := Image.create(640, 360, false, Image.FORMAT_RGB8)
	for y in range(360):
		for x in range(640):
			var v := 0.35 + 0.4 * float(x + y) / 1000.0
			img.set_pixel(x, y, Color.from_hsv(hue, 0.55, v))
	# A hard-edged block, so a stretched or mis-cropped picture is visible.
	img.fill_rect(Rect2i(40, 40, 120 + text.length() * 6, 120), Color.from_hsv(hue, 0.25, 0.95))
	var path := ProjectSettings.globalize_path(ModArtCache.disk_path(url))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	_seeded.append(path)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path(OUT.path_join(name + ".png"))
	img.save_png(path)
	print("[probe] wrote ", path, " ", img.get_size())
