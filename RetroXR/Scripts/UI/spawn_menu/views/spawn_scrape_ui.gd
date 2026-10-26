## SpawnScrapeUi — the SPAWN tab's half of the ScreenScraper client: asking the
## scrape queue for a game or a page of them, hearing what came back, and the
## review popup that accepts a result into the gamelist.
##
## The queue does the scraping; this decides what each outcome does to the view
## that owns it -- a row repainted, the open page repopulated once per burst, or
## the popup over the menu. The game-detail and ROM-variants panels stay with the
## view: they belong to a row, scraped or not, and only borrow info_row from here.
class_name SpawnScrapeUi
extends RefCounted

var _view: SpawnMenuSpawnView = null

var _popup: PanelContainer = null
## Coalesces the repopulate a batch of accepted scrapes asks for: forty
## results landing in a second must not rebuild the page forty times.
var _refresh_timer: SceneTreeTimer = null
## Connected to scraper_client.media_download_completed so the tab refreshes
## when a wheel image or manual PDF finishes downloading.
var _media_dl_refresh_cb: Callable = Callable()


func _init(view: SpawnMenuSpawnView) -> void:
	_view = view


## Method callables, never lambdas: a lambda would keep this object alive through
## the connection after its view is gone. `started` is the view's own: it only
## repaints a row.
func connect_queue(queue: ScrapeQueue) -> void:
	queue.completed.connect(_on_scrape_completed)
	queue.failed.connect(_on_scrape_failed)
	queue.media_downloaded.connect(_on_scrape_media_downloaded)


func on_scrape_pressed(rom_path: String, systemid: String) -> void:
	var queue := _view.scrape_queue
	if queue == null:
		return
	# Review mode hands the result back for the popup; otherwise the queue
	# writes it and fetches the art, and the row repaints when it lands.
	var review := _view.scraper_config != null and _view.scraper_config.approve_scrapes
	if not queue.enqueue(rom_path, systemid,
			{"tag": ScrapeQueue.TAG_MANUAL, "review": review}):
		_view.show_notice("Already in the scrape queue")
		return
	var ahead := queue.waiting_count()
	if ahead > 0:
		_view.show_notice("Queued: %s (%d waiting)" % [rom_path.get_file().get_basename(), ahead])
	_view._on_scrape_row_changed(rom_path, systemid)


## Queue every game on this page not scraped yet. The filtered view is
## the page: a search or a region filter narrows what is queued, the way it
## narrows what is shown. A game already scraped is skipped -- re-scraping one
## stays a per-row action -- and so is one already waiting.
func on_scrape_all_pressed(systemid: String) -> void:
	var queue := _view.scrape_queue
	if queue == null:
		return
	var review := _view.scraper_config != null and _view.scraper_config.approve_scrapes
	var candidates: Array = []
	for model: Dictionary in _view._romm_rows:
		var local_path := str(model.get("path", ""))
		if local_path.is_empty():
			continue
		if systemid == "satellaview" and BsxPack.is_pack_path(local_path):
			continue
		candidates.append(local_path)
	var pick := queue.select_unscraped(systemid, candidates)
	var skipped := int(pick["skipped"])
	var queued := 0
	for local_path: String in pick["paths"]:
		if queue.enqueue(local_path, systemid,
				{"tag": ScrapeQueue.TAG_MANUAL, "review": review}):
			queued += 1
	var msg := "Queued %d game%s" % [queued, "" if queued == 1 else "s"]
	if skipped > 0:
		msg += " (%d already scraped)" % skipped
	if queued == 0 and skipped == 0:
		msg = "Nothing on this page to scrape"
	_view.show_notice(msg, 3.0)
	if is_instance_valid(_view._romm_list):
		_view._romm_list.rebind_visible()


func _on_scrape_completed(rom_path: String, systemid: String, result: Dictionary,
		accepted: bool) -> void:
	print("[SpawnView] Scrape completed for: %s" % rom_path.get_file())
	if not accepted:
		_show_scrape_popup(rom_path, systemid, result)
		_view._on_scrape_row_changed(rom_path, systemid)
		return
	# The name and metadata a row draws changed: repopulate, once per burst.
	_view._romm_meta_cache.erase(rom_path)
	if systemid == _view._romm_detail_systemid:
		_schedule_scrape_refresh()
	else:
		_view._on_scrape_row_changed(rom_path, systemid)


func _on_scrape_failed(rom_path: String, systemid: String, error: String) -> void:
	push_warning("[SpawnView] Scrape failed for %s: %s" % [rom_path.get_file(), error])
	_view._on_scrape_row_changed(rom_path, systemid)


## Same as the accept path's refresh: drop what cached a miss for this ROM
## before the art existed, then repaint the rows on screen. Wheel, label and
## manual are what a row draws; no row draws the box.
func _on_scrape_media_downloaded(rom_path: String, systemid: String, media_type: String,
		_path: String) -> void:
	if media_type != "wheel" and media_type != "label" and media_type != "manual":
		return
	if _view.scraped_art != null:
		_view.scraped_art.forget(systemid, rom_path)
	_view._romm_meta_cache.erase(rom_path)
	_view._on_scrape_row_changed(rom_path, systemid)


func _schedule_scrape_refresh() -> void:
	if _refresh_timer != null:
		return
	_refresh_timer = _view.get_tree().create_timer(0.5)
	_refresh_timer.timeout.connect(func() -> void:
		_refresh_timer = null
		if not is_instance_valid(_view):
			print("[SpawnView] scrape refresh due after the view closed; nothing to repaint")
			return
		if is_instance_valid(_view._romm_list):
			# Names and metadata the rows draw changed: the open page too.
			_view._owe_detail = true
			_view._owe(false, true, false)
	)


func _show_scrape_popup(rom_path: String, systemid: String, result: Dictionary) -> void:
	_close_scrape_popup()

	_popup = PanelContainer.new()
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.1, 0.2, 0.98)
	for k in ["corner_radius_top_left","corner_radius_top_right",
			  "corner_radius_bottom_left","corner_radius_bottom_right"]:
		bg.set(k, 8)
	_popup.add_theme_stylebox_override("panel", bg)
	_popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	for side in ["margin_top","margin_bottom","margin_left","margin_right"]:
		margin.add_theme_constant_override(side, 14)
	_popup.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# Title
	vbox.add_child(MenuStyle.label("SCRAPE RESULT", 24, MenuStyle.COLOR_TITLE))
	vbox.add_child(HSeparator.new())

	# Metadata
	info_row(vbox, "Game", result.get("name", "Unknown"))
	info_row(vbox, "Developer", result.get("developer", ""))
	info_row(vbox, "Publisher", result.get("publisher", ""))
	info_row(vbox, "Genre", result.get("genre", ""))
	info_row(vbox, "Region", result.get("rom_region", ""))
	info_row(vbox, "Release", result.get("releasedate", ""))

	vbox.add_child(HSeparator.new())

	# Media availability
	var media: Dictionary = result.get("media", {})
	vbox.add_child(MenuStyle.label("MEDIA", 18, MenuStyle.COLOR_TITLE))

	for mtype: String in ["wheel", "box", "label", "manual"]:
		var has_it: bool = not (media.get(mtype, "") as String).is_empty()
		var icon := "✅" if has_it else "❌"
		info_row(vbox, mtype.capitalize(), icon)

	vbox.add_child(HSeparator.new())

	# Buttons
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	vbox.add_child(btn_row)

	var accept_btn := Button.new()
	accept_btn.text = "  ACCEPT  "
	accept_btn.custom_minimum_size = Vector2(0, 56)
	accept_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	accept_btn.add_theme_font_size_override("font_size", 20)
	var accept_style := StyleBoxFlat.new()
	accept_style.bg_color = MenuStyle.COLOR_BTN_DL
	for k2 in ["corner_radius_top_left","corner_radius_top_right",
			   "corner_radius_bottom_left","corner_radius_bottom_right"]:
		accept_style.set(k2, 5)
	for state in ["normal", "hover", "pressed"]:
		accept_btn.add_theme_stylebox_override(state, accept_style)
	accept_btn.pressed.connect(_on_scrape_accepted.bind(rom_path, systemid, result))
	btn_row.add_child(accept_btn)

	var close_btn := Button.new()
	close_btn.text = "  CLOSE  "
	close_btn.custom_minimum_size = Vector2(0, 56)
	close_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close_btn.add_theme_font_size_override("font_size", 20)
	close_btn.pressed.connect(_close_scrape_popup)
	btn_row.add_child(close_btn)

	# Add popup as sibling of the spawn view content
	_view.get_parent().add_child(_popup)


func _show_scrape_error_popup(error: String) -> void:
	_close_scrape_popup()

	_popup = PanelContainer.new()
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.2, 0.08, 0.08, 0.98)
	for k in ["corner_radius_top_left","corner_radius_top_right",
			  "corner_radius_bottom_left","corner_radius_bottom_right"]:
		bg.set(k, 8)
	_popup.add_theme_stylebox_override("panel", bg)
	_popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	for side in ["margin_top","margin_bottom","margin_left","margin_right"]:
		margin.add_theme_constant_override(side, 14)
	_popup.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "SCRAPE FAILED"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
	vbox.add_child(title)

	var err_lbl := Label.new()
	err_lbl.text = error
	err_lbl.add_theme_font_size_override("font_size", 18)
	err_lbl.add_theme_color_override("font_color", MenuStyle.COLOR_LICENSE)
	err_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(err_lbl)

	var close_btn := Button.new()
	close_btn.text = "  CLOSE  "
	close_btn.custom_minimum_size = Vector2(0, 56)
	close_btn.add_theme_font_size_override("font_size", 20)
	close_btn.pressed.connect(_close_scrape_popup)
	vbox.add_child(close_btn)

	_view.get_parent().add_child(_popup)


func _close_scrape_popup() -> void:
	if _popup and is_instance_valid(_popup):
		_popup.queue_free()
	_popup = null


func _on_scrape_accepted(rom_path: String, systemid: String, result: Dictionary) -> void:
	_close_scrape_popup()

	var game_data := {
		"game_id": result.get("game_id", ""),
		"name": result.get("name", ""),
		"desc": result.get("desc", ""),
		"developer": result.get("developer", ""),
		"publisher": result.get("publisher", ""),
		"genre": result.get("genre", ""),
		"scraped": true,
	}
	var rom_data := {
		"path": "./" + rom_path.get_file(),
		"romname": rom_path.get_file(),
		"releasedate": result.get("releasedate", ""),
		"region": result.get("rom_region", ""),
	}

	_view.gamelist_manager.add_or_merge_rom(systemid, game_data, rom_data)
	_view.gamelist_manager.save_gamelist(systemid)

	var client := _view.scraper_client
	# Disconnect any stale media refresh callback from a previous accept
	if _media_dl_refresh_cb.is_valid() and \
			client.media_download_completed.is_connected(_media_dl_refresh_cb):
		client.media_download_completed.disconnect(_media_dl_refresh_cb)

	# Re-populate when a piece of art a row DRAWS finishes downloading, so the
	# list updates without requiring a manual tab switch.
	# Scoped to the ROM that was just scraped, and coalesced.
	#
	# This used to clear the whole art memo and rebuild both the tile grid and
	# the row model on EVERY file. download_all_media fetches up to four per
	# game and two of them landed here, so one accept ran that cycle twice and a
	# batch ran it dozens of times — each pass throwing away every other row's
	# decoded art and forcing it all to be read again. Measured before this:
	# 2.4 ms per wheel and 4.1 ms per label to re-decode, times every visible row.
	#
	# A bound method rather than a lambda, so the connection does not keep this
	# object alive past its view.
	_media_dl_refresh_cb = _on_accepted_media_downloaded.bind(systemid, rom_path)
	client.media_download_completed.connect(_media_dl_refresh_cb)

	# Download media files asynchronously
	var rom_basename := rom_path.get_file().get_basename()
	client.download_all_media(result, systemid, rom_basename)

	# Refresh immediately so the game name / metadata shows right away
	_view._populate_cartridges_tab()


## LABEL is in this list because the row's thumbnail IS the label: it beats
## the RomM cover once scraped, and leaving it out meant the one piece of art
## a freshly scraped game always has was the one piece that never appeared
## until the platform was closed and reopened. Box is not, since no row draws it.
func _on_accepted_media_downloaded(mtype: String, _path: String, systemid: String,
		scraped_rom: String) -> void:
	if mtype != "wheel" and mtype != "label" and mtype != "manual":
		return
	# Drop what cached a miss for this ROM before the art existed.
	if _view.scraped_art != null:
		_view.scraped_art.forget(systemid, scraped_rom)
	_view._romm_meta_cache.erase(scraped_rom)
	# ...then repaint the rows on screen, and nothing else.
	#
	# A piece of art landing changes neither the tile grid nor the row model
	# — only what an already-bound row draws. Rebuilding both cost 134 ms
	# measured, because _populate_cartridges_tab ends in browser.refresh(),
	# which re-runs the detail populator over every row of the open system:
	# 9,927 of them on this library, and then _rebuild_romm_rows did it a
	# second time. The name and metadata that DO change are handled by the
	# single _populate_cartridges_tab the accept already runs.
	if is_instance_valid(_view._romm_list):
		_view._romm_list.rebind_visible()


## A "Key: value" line of a scrape result or a game's details. Returns the
## value's label, or null for an empty value, which adds no row.
static func info_row(parent: VBoxContainer, key: String, value: String) -> Label:
	if value.is_empty():
		return null
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)

	var k_lbl := Label.new()
	k_lbl.text = key + ":"
	k_lbl.add_theme_font_size_override("font_size", 17)
	k_lbl.add_theme_color_override("font_color", MenuStyle.COLOR_LICENSE)
	k_lbl.custom_minimum_size = Vector2(110, 0)
	row.add_child(k_lbl)

	var v_lbl := Label.new()
	v_lbl.text = value
	v_lbl.add_theme_font_size_override("font_size", 17)
	v_lbl.add_theme_color_override("font_color", MenuStyle.COLOR_TITLE)
	v_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(v_lbl)
	return v_lbl
