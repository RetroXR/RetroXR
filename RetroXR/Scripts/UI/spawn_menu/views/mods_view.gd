## SpawnMenuModsView — the menu's MODS tab: what is on mod.io, and what is here.
##
## Three sub-tabs. BROWSE is this game's catalogue on mod.io as a grid of tiles,
## each with the preview image its author uploaded; PACKS is its collections
## (SpawnMenuModsPacksPage); INSTALLED is what is in the mods folder, with the
## switch that lets one run. The last used to be a page of the OPTIONS tab and
## moved here whole, so there is one place for mods.
##
## Browsing needs no account, but it does need the player's agreement to mod.io's
## terms: BROWSE and PACKS show those, and nothing else, until they are accepted.
## INSTALLED never asks -- it is the player's own folder.
##
## A download is fetched only once mod.io's scan of it has finished clean,
## checked against mod.io's checksum, and vetted by the loader as a boot would
## vet it plus the no-games rule (ModManager.vet). It then WAITS for one answer:
## a review that shows what the mod replaces. Installed, it is DISABLED unless
## the player said otherwise there. Fetching a mod is not consent to run it.
##
## What mod.io's terms ask of a game showing its catalogue is on the page too:
## its name beside the catalogue, and a way to report anything shown (the
## Report button on every mod).
##
## Enabling, updating and removing a mod that is running all wait for the next
## launch, because a mounted pack cannot be unmounted; the page says so wherever
## that is the case rather than pretending otherwise.
class_name SpawnMenuModsView
extends VBoxContainer

## The sub-tab changed, so the thumbstick should drive a different scroll.
signal scroll_changed(scroll: ScrollContainer)

const COLUMNS := 3
const TILE_H := 286
const ART_H := 176
const SEARCH_DEBOUNCE := 0.6
const FETCH_KEY := "mods:fetch"

const BROWSE_TAB := 0
const PACKS_TAB := 1
const INSTALLED_TAB := 2

## Said wherever the player is about to let a mod in.
const TRUST_WARNING := "A mod is made by its author, not by RetroXR, and runs with " \
	+ "the app's full access to your ROMs, saves and network. Nothing here runs " \
	+ "until it is enabled."

var _menu: Node = null
var client: ModioClient = null
var downloader: ModDownloader = null
var art: ModArtCache = null

var _tabs: TabContainer = null
var _pages: Array[ScrollContainer] = []

# Browse
var _browse_list: VBoxContainer = null      ## toolbar + grid + pager
var _browse_detail: VBoxContainer = null    ## one mod, in place of the list
var _search_edit: LineEdit = null
var _search_timer: Timer = null
var _sort := str(ModioClient.SORTS[0][1])
var _status_lbl: Label = null
var _grid: GridContainer = null
var _prev_btn: Button = null
var _next_btn: Button = null
var _page_lbl: Label = null
var _mods: Array[Dictionary] = []
var _total := 0
var _offset := 0
var _fetched := false
var _fetching := false
## Bumped per request, so a slow reply to a search the player has since changed
## is dropped instead of painted over the newer one.
var _request_serial := 0
var _open_mod: Dictionary = {}
var _tag := ""
var _tag_slot: HBoxContainer = null
var _tags_asked := false
var _browse_review: VBoxContainer = null    ## the question before a mod is installed
var _open_review := ""

# Consent. The gate stands in for the page until mod.io's terms are accepted.
var _browse_gate: VBoxContainer = null
var _packs_gate: VBoxContainer = null
var _packs_body: VBoxContainer = null
var _packs_page: SpawnMenuModsPacksPage = null
var _terms: Dictionary = {}
var _terms_error := ""
var _terms_asking := false
var _declined := false
var _terms_rechecked := false

## Downloads that are fetched and vetted and wait for the player. The Modio
## autoload's, so one that finishes while the menu is away is still here.
var reviews: ModReviews = null

# Installed
var _installed_list: VBoxContainer = null
var _installed_detail: VBoxContainer = null
var _open_installed := ""

## image address -> the TextureRects waiting on it.
var _art_waiters: Dictionary = {}
## The same placeholder behind every tile with no picture.
var _placeholder: StyleBoxFlat = null
## Whole percent last shown per download, so a toast is not re-measured per chunk.
var _last_pct: Dictionary = {}


## `menu` is the SpawnMenu2D. Optional: the tab builds standalone in a probe.
static func create(menu: Node = null) -> SpawnMenuModsView:
	var v := SpawnMenuModsView.new()
	v._menu = menu
	v.client = _service(menu, "modio_client") as ModioClient
	v.downloader = _service(menu, "mod_downloader") as ModDownloader
	v.art = _service(menu, "mod_art") as ModArtCache
	v.reviews = _service(menu, "mod_reviews") as ModReviews
	if v.reviews == null:
		# Standalone, in a probe: the view brings its own, and wires it in. In
		# the game the autoload has already done both.
		v.reviews = ModReviews.new()
		if v.downloader != null:
			v.downloader.install_hook = v.reviews.stage
	v._build()
	return v


static func _service(menu: Node, service_name: String) -> Variant:
	if menu == null or not (service_name in menu):
		return null
	return menu.get(service_name)


func notify(key: String, icon: String, msg: String,
			progress: float = -1.0, seconds: float = 0.0) -> void:
	if _menu:
		_menu.notify(key, icon, msg, progress, seconds)


func _build() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_placeholder = MenuStyle.rounded(MenuStyle.COLOR_NAV_INACTIVE, 6)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_browse(_page("Browse"))
	_build_packs(_page("Packs"))
	_build_installed(_page("Installed"))
	_tabs.tab_changed.connect(func(_i: int) -> void:
		scroll_changed.emit(active_scroll())
		if _tabs.current_tab == INSTALLED_TAB:
			refresh_installed()
		elif _tabs.current_tab == PACKS_TAB and has_consent():
			_packs_page.ensure_fetched())
	add_child(TabStrip.wrap(_tabs))

	if art != null:
		art.art_ready.connect(_on_art_ready)
	if downloader != null:
		downloader.job_started.connect(_on_job_started)
		downloader.job_progress.connect(_on_job_progress)
		downloader.job_retrying.connect(_on_job_retrying)
		downloader.job_cancelled.connect(_on_job_cancelled)
		downloader.job_finished.connect(_on_job_finished)
	Mods.mods_changed.connect(_on_mods_changed)


func _page(title: String) -> VBoxContainer:
	var page := MenuStyle.vscroll()
	page.name = title
	var vbox := MenuStyle.vbox(10)
	page.add_child(vbox)
	_tabs.add_child(page)
	_pages.append(page)
	return vbox


func active_scroll() -> ScrollContainer:
	if _tabs == null or _pages.is_empty():
		return null
	return _pages[clampi(_tabs.current_tab, 0, _pages.size() - 1)]


## Called when the tab is shown. Nothing reaches mod.io until the player opens
## this tab for the first time, and then only its terms until they agree to them.
func ensure_fetched() -> void:
	refresh_installed()
	_apply_consent()
	if not has_consent():
		if _terms.is_empty() and not _declined:
			_ask_terms()
		return
	_recheck_terms()
	_ask_tags()
	if not _fetched and not _fetching:
		_fetch(0)
	if _tabs.current_tab == PACKS_TAB:
		_packs_page.ensure_fetched()


# ── Consent ───────────────────────────────────────────────────────────────────

func has_consent() -> bool:
	return client != null and client.consent.granted()


## Show the gate or the pages behind it, whichever the player's answer allows.
func _apply_consent() -> void:
	var open := has_consent() or client == null
	_browse_gate.visible = not open
	_packs_gate.visible = not open
	_packs_body.visible = open
	if open:
		_show_browse(_browse_review if not _open_review.is_empty()
			else (_browse_detail if not _open_mod.is_empty() else _browse_list))
	else:
		for panel: Control in [_browse_list, _browse_detail, _browse_review]:
			panel.visible = false
		_fill_gate(_browse_gate)
		_fill_gate(_packs_gate)


func _ask_terms() -> void:
	if client == null or _terms_asking:
		return
	_terms_asking = true
	_terms_error = ""
	_apply_consent()
	client.get_terms(func(ok: bool, terms: Dictionary, error: String) -> void:
		_terms_asking = false
		if ok:
			_terms = terms
		else:
			_terms_error = error
		_apply_consent())


## Once a session, for a player who has agreed: has mod.io changed the text they
## agreed to? If so they are asked again rather than held to words they never saw.
func _recheck_terms() -> void:
	if _terms_rechecked or client == null:
		return
	_terms_rechecked = true
	client.get_terms(func(ok: bool, terms: Dictionary, _error: String) -> void:
		if ok and client.consent.terms_changed(str(terms["text"])):
			_terms = terms
			_withdraw())


func _fill_gate(gate: VBoxContainer) -> void:
	_clear(gate)
	gate.add_child(MenuStyle.label("Mods are hosted by mod.io", 24, MenuStyle.COLOR_TITLE))
	if _declined:
		var off := MenuStyle.label(
			"mod.io is off. Browsing and downloading mods needs your agreement to "
			+ "mod.io's terms; the mods you already have are under Installed.",
			18, MenuStyle.COLOR_LICENSE)
		off.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		gate.add_child(off)
		var again := _narrow(MenuStyle.row_button("Show mod.io's terms", 18, 280, 52, false))
		again.pressed.connect(func() -> void:
			_declined = false
			if _terms.is_empty():
				_ask_terms()
			else:
				_apply_consent())
		gate.add_child(again)
		return
	if _terms.is_empty():
		if _terms_error.is_empty():
			gate.add_child(MenuStyle.hint("Asking mod.io for its terms…"))
			return
		gate.add_child(MenuStyle.label(_terms_error, 18, MenuStyle.COLOR_BTN_UPD))
		var retry := _narrow(MenuStyle.row_button("Try again", 18, 200, 52, false))
		retry.pressed.connect(_ask_terms)
		gate.add_child(retry)
		return

	# mod.io's own words, buttons and links, as its terms endpoint gave them.
	var text := MenuStyle.label(str(_terms["text"]), 18, MenuStyle.COLOR_LICENSE)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gate.add_child(text)
	gate.add_child(MenuStyle.hint(
		"RetroXR does not sign you in to mod.io: browsing and downloading are "
		+ "anonymous. Nothing is asked of mod.io until you agree."))
	# A flow, not a row: mod.io sends six links, and six buttons in a row are
	# wider than the menu. A row that wide stretched the whole gate with it, so
	# the terms above wrapped at the row's width and ran off the right edge.
	var links := HFlowContainer.new()
	links.add_theme_constant_override("h_separation", 10)
	links.add_theme_constant_override("v_separation", 10)
	gate.add_child(links)
	for link: Dictionary in (_terms["links"] as Array):
		var url := str(link["url"])
		var btn := MenuStyle.row_button(str(link["text"]), 16, 220, 48, false)
		btn.pressed.connect(func() -> void: _open_link(url))
		links.add_child(btn)
	gate.add_child(HSeparator.new())
	var answers := MenuStyle.hbox(10)
	gate.add_child(answers)
	var agree := MenuStyle.row_button(str(_terms["agree"]), 20, 220, 56, false)
	agree.add_theme_stylebox_override("normal", MenuStyle.rounded(MenuStyle.COLOR_BTN_DL, 6))
	agree.pressed.connect(func() -> void:
		client.consent.grant(str(_terms["text"]))
		_terms_rechecked = true
		ensure_fetched())
	answers.add_child(agree)
	var decline := MenuStyle.row_button(str(_terms["disagree"]), 20, 220, 56, false)
	decline.pressed.connect(func() -> void:
		_declined = true
		_apply_consent())
	answers.add_child(decline)


## Take the agreement back. What was fetched under it goes too: the catalogue
## pages, the pack list, and every download in flight or waiting for an answer.
func _withdraw() -> void:
	if client == null:
		return
	client.consent.withdraw()
	if downloader != null:
		downloader.cancel_all()
	reviews.discard_all()
	_request_serial += 1
	_fetching = false
	_fetched = false
	_mods.clear()
	_total = 0
	_offset = 0
	_open_mod = {}
	_open_review = ""
	_clear(_grid)
	_packs_page.forget()
	_declined = true
	_apply_consent()


# ── Browse ────────────────────────────────────────────────────────────────────

func _build_packs(vbox: VBoxContainer) -> void:
	_packs_gate = MenuStyle.vbox(12)
	_packs_gate.visible = false
	vbox.add_child(_packs_gate)
	_packs_body = MenuStyle.vbox(10)
	vbox.add_child(_packs_body)
	_packs_page = SpawnMenuModsPacksPage.new(self, _packs_body, _pages[PACKS_TAB])


## One of the Browse page's three faces: the grid, one mod, or the review.
func _show_browse(which: Control) -> void:
	for panel: Control in [_browse_list, _browse_detail, _browse_review]:
		panel.visible = panel == which


func _build_browse(vbox: VBoxContainer) -> void:
	_browse_gate = MenuStyle.vbox(12)
	_browse_gate.visible = false
	vbox.add_child(_browse_gate)
	_browse_list = MenuStyle.vbox(10)
	vbox.add_child(_browse_list)
	_browse_detail = MenuStyle.vbox(10)
	_browse_detail.visible = false
	vbox.add_child(_browse_detail)
	_browse_review = MenuStyle.vbox(8)
	_browse_review.visible = false
	vbox.add_child(_browse_review)

	var bar := MenuStyle.hbox(10)
	bar.custom_minimum_size = Vector2(0, 56)
	_browse_list.add_child(bar)

	_search_edit = LineEdit.new()
	_search_edit.placeholder_text = "Search mods"
	_search_edit.clear_button_enabled = true
	_search_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_edit.custom_minimum_size = Vector2(0, 52)
	_search_edit.add_theme_font_size_override("font_size", 20)
	# Every keystroke restarts the wait, so a word is one request, not one per letter.
	_search_edit.text_changed.connect(func(_t: String) -> void: _search_timer.start(SEARCH_DEBOUNCE))
	_search_edit.text_submitted.connect(func(_t: String) -> void:
		_search_timer.stop()
		_fetch(0))
	bar.add_child(_search_edit)

	_search_timer = Timer.new()
	_search_timer.one_shot = true
	_search_timer.timeout.connect(func() -> void: _fetch(0))
	add_child(_search_timer)

	# VRDropdown, never OptionButton — its popup is a Window the panel cannot hold.
	var sort_drop := VRDropdown.create("Sort", ModioClient.SORTS, _sort, 1, Vector2(240, 52), 18)
	sort_drop.item_selected.connect(func(id: Variant) -> void:
		_sort = str(id)
		_fetch(0))
	bar.add_child(sort_drop)

	# Filled once mod.io has said which tags this game has.
	_tag_slot = MenuStyle.hbox(0)
	bar.add_child(_tag_slot)

	var refresh_btn := MenuStyle.row_button("Refresh", 18, 130, 52, false)
	refresh_btn.pressed.connect(func() -> void: _fetch(_offset))
	bar.add_child(refresh_btn)

	_status_lbl = MenuStyle.label("", 16, MenuStyle.COLOR_DESC)
	_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_browse_list.add_child(_status_lbl)

	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	_browse_list.add_child(_grid)

	var pager := MenuStyle.hbox(10)
	pager.alignment = BoxContainer.ALIGNMENT_CENTER
	_browse_list.add_child(pager)
	_prev_btn = MenuStyle.row_button("Previous", 18, 160, 52, false)
	_prev_btn.pressed.connect(func() -> void: _fetch(maxi(0, _offset - ModioClient.PAGE_SIZE)))
	pager.add_child(_prev_btn)
	_page_lbl = MenuStyle.label("", 18, MenuStyle.COLOR_LICENSE)
	_page_lbl.custom_minimum_size = Vector2(200, 0)
	_page_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pager.add_child(_page_lbl)
	_next_btn = MenuStyle.row_button("Next", 18, 160, 52, false)
	_next_btn.pressed.connect(func() -> void: _fetch(_offset + ModioClient.PAGE_SIZE))
	pager.add_child(_next_btn)

	_browse_list.add_child(HSeparator.new())
	_browse_list.add_child(MenuStyle.hint("Mods are hosted by mod.io. " + TRUST_WARNING))
	var withdraw := _narrow(MenuStyle.row_button("Withdraw mod.io consent", 16, 300, 48, false))
	withdraw.pressed.connect(func() -> void:
		if withdraw.text != "Really withdraw?":
			withdraw.text = "Really withdraw?"
			return
		withdraw.text = "Withdraw mod.io consent"
		_withdraw())
	_browse_list.add_child(withdraw)
	_update_pager()


## The tag filter, built when mod.io answers. One request a session.
func _ask_tags() -> void:
	if _tags_asked or client == null:
		return
	_tags_asked = true
	client.list_tags(func(ok: bool, tags: PackedStringArray, _error: String) -> void:
		if not ok or tags.is_empty():
			_tags_asked = ok
			return
		var options: Array = [["All tags", ""]]
		for tag: String in tags:
			options.append([tag, tag])
		_clear(_tag_slot)
		var drop := VRDropdown.create("Tag", options, _tag, 1, Vector2(220, 52), 18)
		drop.item_selected.connect(func(id: Variant) -> void:
			_tag = str(id)
			_fetch(0))
		_tag_slot.add_child(drop))


func _fetch(offset: int) -> void:
	if client == null:
		_status_lbl.text = "The mod browser is unavailable in this build."
		return
	_fetching = true
	_request_serial += 1
	var serial := _request_serial
	_status_lbl.text = "Asking mod.io…"
	client.list_mods(_search_edit.text, _sort, offset,
		func(ok: bool, mods: Array[Dictionary], total: int, error: String) -> void:
			if serial != _request_serial:
				return
			_fetching = false
			if not ok:
				# The tiles already on screen stay: a failed refresh is not a
				# reason to take away a page the player was reading.
				_status_lbl.text = error
				return
			_fetched = true
			_mods = mods
			_total = total
			_offset = offset
			_rebuild_grid(), _tag)


func _rebuild_grid() -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_art_waiters.clear()
	var wanted := PackedStringArray()
	for mod: Dictionary in _mods:
		wanted.append(str(mod["logo_small"]))
		_grid.add_child(_browse_tile(mod))
	if art != null:
		art.cancel_outside(wanted)

	if _mods.is_empty():
		_status_lbl.text = "Nothing on mod.io matches that." \
			if not _search_edit.text.strip_edges().is_empty() or not _tag.is_empty() \
			else "No mods have been published yet."
	else:
		_status_lbl.text = "%d mod%s on mod.io" % [_total, "" if _total == 1 else "s"]
	_update_pager()
	var scroll := _pages[0]
	scroll.scroll_vertical = 0


func _update_pager() -> void:
	var pages := maxi(1, ceili(float(_total) / float(ModioClient.PAGE_SIZE)))
	var page := _offset / ModioClient.PAGE_SIZE + 1
	_page_lbl.text = "Page %d of %d" % [page, pages]
	_prev_btn.disabled = _offset <= 0
	_next_btn.disabled = _offset + ModioClient.PAGE_SIZE >= _total
	var paged := pages > 1
	_prev_btn.visible = paged
	_next_btn.visible = paged
	_page_lbl.visible = paged


func _browse_tile(mod: Dictionary) -> Button:
	var sub := str(mod["author"])
	if int(mod["file_size"]) > 0:
		sub += ("  ·  " if not sub.is_empty() else "") + MenuStyle.human_bytes(int(mod["file_size"]))
	var state := browse_state(mod, false, has_review(_job_key(int(mod["id"]))))
	var tile := _make_tile(str(mod["name"]), sub, state_text(state), _state_color(state))
	_bind_art(tile, str(mod["logo_small"]))
	tile.pressed.connect(func() -> void: _open_browse_detail(mod))
	return tile


## Where one mod.io mod stands on this device:
##   ""          not here
##   "nofile"    its page has no file to download yet
##   "installed" here, and the file mod.io offers is the one installed
##   "update"    here, and mod.io offers a different file
##   "staged"    an update is fetched and waits for the next launch
##   "busy"      being downloaded now
##   "review"    downloaded, and waiting for the player's answer
##   "unscanned" mod.io's scan of the file it offers has not finished clean
static func browse_state(mod: Dictionary, busy: bool = false, review: bool = false) -> String:
	if busy:
		return "busy"
	if review:
		return "review"
	var rec := Mods.find_by_source("modio_id", int(mod.get("id", 0)))
	if rec == null:
		if int(mod.get("file_id", 0)) <= 0:
			return "nofile"
		return "unscanned" if not ModioClient.scan_problem(mod).is_empty() else ""
	if not rec.update_staged.is_empty():
		return "staged"
	if int(mod.get("file_id", 0)) > 0 \
			and int(Mods.source(rec.id).get("file_id", 0)) != int(mod["file_id"]):
		# A newer file that is not scanned yet is not an update to offer.
		return "update" if ModioClient.scan_problem(mod).is_empty() else "installed"
	return "installed"


static func state_text(state: String) -> String:
	match state:
		"nofile":    return "No file yet"
		"installed": return "Installed"
		"update":    return "Update available"
		"staged":    return "Restart to update"
		"busy":      return "Downloading…"
		"review":    return "Downloaded — review to install"
		"unscanned": return "Being scanned by mod.io"
	return ""


static func _state_color(state: String) -> Color:
	match state:
		"installed": return MenuStyle.COLOR_RECOMMENDED
		"update", "staged", "busy", "review": return Color(0.95, 0.75, 0.35)
	return MenuStyle.COLOR_DESC


func _open_browse_detail(mod: Dictionary) -> void:
	_open_mod = mod
	_fill_browse_detail()
	_show_browse(_browse_detail)
	_pages[BROWSE_TAB].scroll_vertical = 0


## A mod named somewhere else in the tab -- a pack's member -- on its own page.
func open_mod(mod: Dictionary) -> void:
	_tabs.current_tab = BROWSE_TAB
	_open_browse_detail(mod)


func _close_browse_detail() -> void:
	_open_mod = {}
	_show_browse(_browse_list)
	# The tiles' badges are painted when built, and a download may have finished.
	if _fetched:
		_rebuild_grid()


func _fill_browse_detail() -> void:
	_clear(_browse_detail)
	if _open_mod.is_empty():
		return
	var mod := _open_mod
	var mod_id := int(mod["id"])
	var back := _narrow(MenuStyle.row_button("←  All mods", 20, 220, 52, false))
	back.pressed.connect(_close_browse_detail)
	_browse_detail.add_child(back)

	var head := MenuStyle.hbox(16)
	_browse_detail.add_child(head)
	var picture := _art_panel(Vector2(480, 270))
	head.add_child(picture)
	_bind_art(picture, str(mod["logo_large"]))

	var facts := MenuStyle.vbox(6)
	facts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(facts)
	var title := MenuStyle.label(str(mod["name"]), 26, MenuStyle.COLOR_TITLE)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	facts.add_child(title)
	if not str(mod["author"]).is_empty():
		facts.add_child(MenuStyle.label("by " + str(mod["author"]), 18, MenuStyle.COLOR_LICENSE))
	var lines := PackedStringArray()
	if not str(mod["file_version"]).is_empty():
		lines.append("Version " + str(mod["file_version"]))
	if int(mod["file_size"]) > 0:
		lines.append(MenuStyle.human_bytes(int(mod["file_size"])))
	if int(mod["downloads"]) > 0:
		lines.append("%d downloads" % int(mod["downloads"]))
	if not str(mod["rating"]).is_empty() and str(mod["rating"]) != "Unrated":
		lines.append(str(mod["rating"]))
	if not lines.is_empty():
		facts.add_child(MenuStyle.label("  ·  ".join(lines), 16, MenuStyle.COLOR_DESC))
	if not (mod["tags"] as PackedStringArray).is_empty():
		facts.add_child(MenuStyle.label(", ".join(mod["tags"]), 16, MenuStyle.COLOR_DESC))

	var busy := downloader != null and downloader.is_queued(_job_key(mod_id))
	var state := browse_state(mod, busy, has_review(_job_key(mod_id)))
	var state_lbl := MenuStyle.label(state_text(state), 18, _state_color(state))
	state_lbl.visible = not state_lbl.text.is_empty()
	facts.add_child(state_lbl)

	var actions := MenuStyle.hbox(10)
	facts.add_child(actions)
	if state == "busy":
		var cancel := MenuStyle.row_button("Cancel", 20, 200, 56, false)
		cancel.pressed.connect(func() -> void: downloader.cancel(_job_key(mod_id)))
		actions.add_child(cancel)
	elif state == "review":
		var review_btn := MenuStyle.row_button("Review and install", 20, 280, 56, false)
		review_btn.add_theme_stylebox_override("normal", MenuStyle.rounded(MenuStyle.COLOR_BTN_DL, 6))
		review_btn.pressed.connect(func() -> void: _open_single_review(_job_key(mod_id)))
		actions.add_child(review_btn)
	elif state == "" or state == "update":
		var get_btn := MenuStyle.row_button(
			"Update" if state == "update" else "Download", 20, 200, 56, false)
		get_btn.add_theme_stylebox_override("normal", MenuStyle.rounded(MenuStyle.COLOR_BTN_DL, 6))
		get_btn.pressed.connect(func() -> void: _download(mod))
		actions.add_child(get_btn)
	elif state == "installed" or state == "staged":
		var manage := MenuStyle.row_button("Manage", 20, 200, 56, false)
		manage.pressed.connect(func() -> void:
			var rec := Mods.find_by_source("modio_id", mod_id)
			if rec != null:
				_tabs.current_tab = INSTALLED_TAB
				_open_installed_detail(rec.id))
		actions.add_child(manage)

	if not str(mod["summary"]).is_empty():
		var summary := MenuStyle.label(str(mod["summary"]), 18, MenuStyle.COLOR_LICENSE)
		summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_browse_detail.add_child(summary)

	_browse_detail.add_child(HSeparator.new())
	var links := MenuStyle.hbox(10)
	_browse_detail.add_child(links)
	if not str(mod["profile_url"]).is_empty():
		var page_btn := MenuStyle.row_button("Open on mod.io", 18, 240, 52, false)
		page_btn.pressed.connect(func() -> void: _open_link(str(mod["profile_url"])))
		links.add_child(page_btn)
	# mod.io's terms: everything a game shows must be reportable.
	var report := MenuStyle.row_button("Report this mod", 18, 240, 52, false)
	report.pressed.connect(func() -> void: _open_link(ModioClient.report_url(mod_id)))
	links.add_child(report)
	_browse_detail.add_child(MenuStyle.hint(
		"Hosted by mod.io. Reporting opens mod.io's own form in a browser."))


## A browser on a desktop, the headset's own on a Quest. The address goes in a
## toast as well, because a browser that opens BEHIND a headset's app is easy to
## miss and the player may want to type it somewhere else.
func _open_link(url: String) -> void:
	OS.shell_open(url)
	notify("mods:link", "✅", url, -1.0, MenuToasts.DWELL_FAIL)


static func _job_key(mod_id: int) -> String:
	return ModReviews.job_key(mod_id)


static func _toast_key(job_key: String) -> String:
	return "mods:dl:" + job_key


func _download(mod: Dictionary) -> void:
	var mod_id := int(mod["id"])
	var key := _job_key(mod_id)
	# is_queued is the double-press guard: one press must be one download.
	if client == null or downloader == null or downloader.is_queued(key):
		return
	notify(_toast_key(key), "⏳", "Asking mod.io for %s…" % str(mod["name"]))
	# Asked again rather than taken from the listing: mod.io signs a download
	# address and lets it expire, and the page may have been open for a while.
	client.get_mod(mod_id, func(ok: bool, fresh: Dictionary, error: String) -> void:
		if not ok:
			notify(_toast_key(key), "❌", error, -1.0, MenuToasts.DWELL_FAIL)
			return
		if int(fresh["file_id"]) <= 0 or str(fresh["download_url"]).is_empty():
			notify(_toast_key(key), "❌", "%s has no file to download yet" % str(fresh["name"]),
				-1.0, MenuToasts.DWELL_FAIL)
			return
		# Asked of the FRESH reply: a file can be flagged after the page was listed.
		var scan := ModioClient.scan_problem(fresh)
		if not scan.is_empty():
			notify(_toast_key(key), "❌", "%s: %s" % [str(fresh["name"]), scan],
				-1.0, MenuToasts.DWELL_FAIL)
			return
		downloader.enqueue(key, str(fresh["name"]), str(fresh["download_url"]),
			int(fresh["file_size"]), str(fresh["file_md5"]),
			{"modio_id": mod_id, "file_id": int(fresh["file_id"]),
				"profile_url": str(fresh["profile_url"])})
		if int(_open_mod.get("id", 0)) == mod_id:
			_fill_browse_detail())


func _on_job_started(key: String, label: String, _total: int) -> void:
	_last_pct.erase(key)
	notify(_toast_key(key), "⏳", "Downloading %s" % label, 0.0)
	_refresh_open_mod(key)


func _on_job_progress(key: String, received: int, total: int) -> void:
	if total <= 0:
		return
	var pct := clampi(int(100.0 * float(received) / float(total)), 0, 100)
	if int(_last_pct.get(key, -1)) == pct:
		return
	_last_pct[key] = pct
	notify(_toast_key(key), "⏳", "Downloading — %s of %s" % [
		MenuStyle.human_bytes(received), MenuStyle.human_bytes(total)], float(pct) / 100.0)


func _on_job_retrying(key: String, attempt: int, max_attempts: int, reason: String) -> void:
	notify(_toast_key(key), "⏳", "%s — retrying (%d of %d)" % [reason, attempt, max_attempts])


func _on_job_cancelled(key: String) -> void:
	if _packs_page.owns(key):
		notify_clear(_toast_key(key))
		_packs_page.on_job_done(key, false, "")
		return
	notify(_toast_key(key), "❌", "Download cancelled", -1.0, MenuToasts.DWELL_INFO)
	_refresh_open_mod(key)


func _on_job_finished(key: String, ok: bool, error: String, result: Dictionary) -> void:
	var waiting := ok and bool(result.get("review", false))
	# A pack's members are answered for together, by the pack.
	if _packs_page.owns(key):
		notify_clear(_toast_key(key))
		_packs_page.on_job_done(key, waiting, error)
		return
	if not ok:
		# The loader's own sentence when it refused the pack, the transfer's
		# otherwise. Either way the player learns why nothing was installed.
		notify(_toast_key(key), "❌", "Not installed: %s" % error, -1.0, MenuToasts.DWELL_FAIL)
	elif waiting:
		notify(_toast_key(key), "✅", "Downloaded — review it to install",
			-1.0, MenuToasts.DWELL_FAIL)
		# Straight to the question when the player is looking at this very mod.
		if not _open_mod.is_empty() and _job_key(int(_open_mod["id"])) == key \
				and _browse_detail.visible:
			_open_single_review(key)
			return
	_refresh_open_mod(key)


func notify_clear(key: String) -> void:
	if _menu != null and _menu.has_method("notify_clear"):
		_menu.notify_clear(key)


# ── Review: the one question before a download is installed ───────────────────

# The parking itself is ModReviews.stage, the downloader's install hook.

func has_review(key: String) -> bool:
	return reviews.has(key)


func review(key: String) -> Dictionary:
	return reviews.parked(key)


func finish_review(key: String, source: Dictionary, enable: bool) -> Dictionary:
	return reviews.finish(key, source, enable)


func discard_review(key: String) -> void:
	reviews.discard(key)


## name -> the shipped paths each installed mod replaces, for spotting two mods
## that want the same file.
static func installed_claims() -> Dictionary:
	var out := {}
	for rec: ModRecord in Mods.all_mods():
		if rec.status != Mods.Status.REFUSED and not rec.removal_staged:
			var claims := Array(rec.manifest.shadowing_claims())
			if not claims.is_empty():
				out[rec.manifest.name] = claims
	return out


func _open_single_review(key: String) -> void:
	if not reviews.has(key):
		return
	_open_review = key
	_fill_single_review()
	_show_browse(_browse_review)
	_pages[BROWSE_TAB].scroll_vertical = 0


func _close_single_review() -> void:
	_open_review = ""
	if _open_mod.is_empty():
		_show_browse(_browse_list)
		if _fetched:
			_rebuild_grid()
	else:
		_fill_browse_detail()
		_show_browse(_browse_detail)


func _fill_single_review() -> void:
	_clear(_browse_review)
	var key := _open_review
	if not reviews.has(key):
		return
	var parked: Dictionary = reviews.parked(key)
	var manifest: ModManifest = parked["manifest"]
	var source: Dictionary = parked["source"]
	var old := Mods.mod(manifest.id)

	var back := _narrow(MenuStyle.row_button("←  Decide later", 20, 240, 52, false))
	back.pressed.connect(_close_single_review)
	_browse_review.add_child(back)
	var title := MenuStyle.label("Install %s %s?" % [manifest.name, manifest.version],
		26, MenuStyle.COLOR_TITLE)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_browse_review.add_child(title)
	var by := manifest.author if not manifest.author.is_empty() else "unknown author"
	_browse_review.add_child(MenuStyle.label("%s — %s" % [manifest.id, by], 15, MenuStyle.COLOR_DESC))
	_browse_review.add_child(MenuStyle.hint(TRUST_WARNING))
	if old != null:
		_browse_review.add_child(MenuStyle.label(
			"Replaces the %s you have." % old.manifest.version
			+ (" It is running, so the new one takes over at the next restart." if old.mounted else ""),
			16, MenuStyle.COLOR_LICENSE))

	# What it writes outside its own folder. The shadowing list is the one that
	# matters: those replace files the game ships.
	for path: String in manifest.shadowing_claims():
		_browse_review.add_child(MenuStyle.label("    Replaces " + path, 15, MenuStyle.COLOR_BTN_UPD))
	for path: String in manifest.adding_claims():
		_browse_review.add_child(MenuStyle.hint("    Adds file " + path))
	var claims := installed_claims()
	claims[manifest.name] = Array(manifest.shadowing_claims())
	for line: String in ModCollectionPlan.conflicts(claims):
		_browse_review.add_child(MenuStyle.label("! " + line, 16, MenuStyle.COLOR_BTN_UPD))

	_browse_review.add_child(HSeparator.new())
	# An update keeps whatever the player already chose for this mod.
	var enable: VRToggle = null
	if not Mods.is_enabled(manifest.id):
		enable = MenuStyle.switch_row(_browse_review, "Enable on next launch", false)
	var actions := MenuStyle.hbox(10)
	_browse_review.add_child(actions)
	var install := MenuStyle.row_button("Install", 20, 220, 56, false)
	install.add_theme_stylebox_override("normal", MenuStyle.rounded(MenuStyle.COLOR_BTN_DL, 6))
	install.pressed.connect(func() -> void:
		var out := finish_review(key, ModCollectionPlan.source_after_single(
			Mods.source(manifest.id), int(source.get("modio_id", 0)),
			int(source.get("file_id", 0)), str(source.get("profile_url", ""))),
			enable != null and enable.button_pressed)
		if not bool(out.get("ok", false)):
			notify(_toast_key(key), "❌", "Not installed: %s" % str(out.get("error", "")),
				-1.0, MenuToasts.DWELL_FAIL)
		elif bool(out.get("restart", false)):
			notify(_toast_key(key), "✅", "Installed — restart RetroXR to apply it",
				-1.0, MenuToasts.DWELL_FAIL)
		else:
			notify(_toast_key(key), "✅", "Installed — enable it under Installed",
				-1.0, MenuToasts.DWELL_FAIL)
		_close_single_review())
	actions.add_child(install)
	var discard := MenuStyle.row_button("Discard", 20, 200, 56, false)
	discard.pressed.connect(func() -> void:
		discard_review(key)
		notify(_toast_key(key), "❌", "Download discarded", -1.0, MenuToasts.DWELL_INFO)
		_close_single_review())
	actions.add_child(discard)


func _refresh_open_mod(key: String) -> void:
	if not _open_mod.is_empty() and _job_key(int(_open_mod["id"])) == key:
		_fill_browse_detail()


# ── Installed ─────────────────────────────────────────────────────────────────

func _build_installed(vbox: VBoxContainer) -> void:
	_installed_list = MenuStyle.vbox(10)
	vbox.add_child(_installed_list)
	_installed_detail = MenuStyle.vbox(8)
	_installed_detail.visible = false
	vbox.add_child(_installed_detail)


func _on_mods_changed() -> void:
	refresh_installed()
	if _browse_detail.visible and not _open_mod.is_empty():
		_fill_browse_detail()
	elif _fetched and _browse_list.visible:
		_rebuild_grid()
	_packs_page.on_mods_changed()


func refresh_installed() -> void:
	if _installed_list == null:
		return
	if not _open_installed.is_empty() and Mods.mod(_open_installed) == null:
		_open_installed = ""
	_installed_list.visible = _open_installed.is_empty()
	_installed_detail.visible = not _open_installed.is_empty()
	if not _open_installed.is_empty():
		_fill_installed_detail()
		return

	_clear(_installed_list)
	if Mods.restart_pending():
		var pending := MenuStyle.label(
			"Restart RetroXR to apply your changes.", 18, MenuStyle.COLOR_RECOMMENDED)
		pending.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_installed_list.add_child(pending)

	var mods: Array = Mods.all_mods()
	var unreadable: Array = Mods.unreadable()
	if mods.is_empty() and unreadable.is_empty():
		_installed_list.add_child(MenuStyle.hint(
			"No mods installed. Get one from the Browse tab, or drop a .zip or "
			+ ".pck in the folder below and restart."))
	else:
		var grid := GridContainer.new()
		grid.columns = COLUMNS
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 12)
		_installed_list.add_child(grid)
		for rec: ModRecord in mods:
			grid.add_child(_installed_tile(rec))
		for u: Dictionary in unreadable:
			_build_unreadable_card(_installed_list, u)

	_installed_list.add_child(HSeparator.new())
	_installed_list.add_child(MenuStyle.hint(
		"A mod runs with the app's full access to your ROMs, saves and network, "
		+ "so nothing loads until you enable it. Mods from mod.io have been "
		+ "through its scan; a file you copy in yourself has been through nothing."))
	_installed_list.add_child(MenuStyle.hint("Folder: " + RomLibrary.default_mods_root()))


func _installed_tile(rec: ModRecord) -> Button:
	var tile := _make_tile("%s  %s" % [rec.manifest.name, rec.manifest.version],
		rec.manifest.author if not rec.manifest.author.is_empty() else rec.id,
		installed_status_text(rec), _status_color(rec.status))
	if picture_of(rec) != null:
		_set_art(tile, picture_of(rec))
	var id := rec.id
	tile.pressed.connect(func() -> void: _open_installed_detail(id))
	return tile


## The one line under an installed mod's name. What is WAITING comes before what
## is: a mod on its way out reads as that, not as "Loaded".
static func installed_status_text(rec: ModRecord) -> String:
	if rec.removal_staged:
		return "Removed at next restart"
	if not rec.update_staged.is_empty():
		# The same version number again is a new copy, not an update to it: a
		# re-download, or an author who re-uploaded without bumping the number.
		if rec.update_staged == rec.manifest.version:
			return "A new copy of %s installs at next restart" % rec.update_staged
		return "Updates to %s at next restart" % rec.update_staged
	return Mods.status_text(rec.status)


## The picture for an installed mod: the pack that is waiting to take over when
## there is one and it has a picture, else the pack that is here.
static func picture_of(rec: ModRecord) -> Texture2D:
	if not rec.update_staged.is_empty() and rec.update_thumbnail != null:
		return rec.update_thumbnail
	return rec.thumbnail


func _open_installed_detail(id: String) -> void:
	_open_installed = id
	refresh_installed()
	_pages[INSTALLED_TAB].scroll_vertical = 0


## What one installed mod is and does, so that enabling it is an informed choice
## -- and, when it did not load, why. The second matters more: a mod that
## silently does nothing is the worst outcome of this system.
##
## What a mod "adds" is OBSERVED, not declared: ModApi records each registration
## as it happens, so this reports what the mod actually did rather than what its
## manifest claimed.
func _fill_installed_detail() -> void:
	_clear(_installed_detail)
	var rec := Mods.mod(_open_installed)
	if rec == null:
		return
	var vbox := _installed_detail
	var manifest := rec.manifest
	var status := rec.status

	var back := _narrow(MenuStyle.row_button("←  Installed mods", 20, 260, 52, false))
	back.pressed.connect(func() -> void:
		_open_installed = ""
		refresh_installed())
	vbox.add_child(back)

	var head := MenuStyle.hbox(16)
	vbox.add_child(head)
	var picture := _art_panel(Vector2(320, 180))
	head.add_child(picture)
	if picture_of(rec) != null:
		_set_art(picture, picture_of(rec))
	var titles := MenuStyle.vbox(4)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	var title := MenuStyle.label("%s  %s" % [manifest.name, manifest.version],
		24, MenuStyle.COLOR_TITLE)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	titles.add_child(title)
	var by := manifest.author if not manifest.author.is_empty() else "unknown author"
	titles.add_child(MenuStyle.label("%s — %s" % [manifest.id, by], 15, MenuStyle.COLOR_DESC))
	titles.add_child(MenuStyle.label(installed_status_text(rec), 16, _status_color(status)))
	titles.add_child(MenuStyle.hint("%s%s  ·  %s  ·  %d files" % [
		"Running now: " if not rec.update_staged.is_empty() else "",
		rec.path.get_file(), MenuStyle.human_bytes(rec.size), rec.files]))
	if not rec.update_staged.is_empty() and rec.update_size > 0:
		titles.add_child(MenuStyle.hint("Waiting: %s  ·  %s  ·  %d files" % [
			rec.update_staged, MenuStyle.human_bytes(rec.update_size), rec.update_files]))
	if not Mods.source(rec.id).is_empty():
		var packs := ModCollectionPlan.collections_of(Mods.source(rec.id)).size()
		titles.add_child(MenuStyle.hint("From mod.io" if packs == 0
			else "From mod.io, with %d pack%s" % [packs, "" if packs == 1 else "s"]))

	if not manifest.description.is_empty():
		var desc := MenuStyle.label(manifest.description, 16, MenuStyle.COLOR_LICENSE)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(desc)

	# What it actually registered, taken from ModApi rather than the manifest.
	var api := rec.api
	if api != null:
		vbox.add_child(MenuStyle.label("Adds: " + api.summary(), 16, MenuStyle.COLOR_LICENSE))
		var contributions: Dictionary = api.contributions()
		for kind: String in ModApi.KINDS:
			for label: String in (contributions.get(kind, []) as Array):
				vbox.add_child(MenuStyle.hint("    • " + label))
		for problem: String in api.problems():
			vbox.add_child(MenuStyle.label("    ! " + problem, 15, MenuStyle.COLOR_BTN_UPD))

	if not rec.reason.is_empty():
		var reason := MenuStyle.label(rec.reason, 16,
			MenuStyle.COLOR_BTN_UPD if status == Mods.Status.REFUSED
			or status == Mods.Status.FAILED else MenuStyle.COLOR_DESC)
		reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(reason)

	# Paths outside its own folder. The shadowing list is the one that matters:
	# those replace files the game ships.
	for path: String in manifest.shadowing_claims():
		vbox.add_child(MenuStyle.label("    Replaces " + path, 15, MenuStyle.COLOR_BTN_UPD))
	for path: String in manifest.adding_claims():
		vbox.add_child(MenuStyle.hint("    Adds file " + path))

	vbox.add_child(HSeparator.new())
	var id := rec.id
	# A refused mod gets no switch: enabling it would change nothing, and a
	# toggle that does nothing is worse than none. Nor does one being removed.
	if status != Mods.Status.REFUSED and not rec.removal_staged:
		var sw := MenuStyle.switch_row(vbox, "Enabled", Mods.is_enabled(id))
		sw.toggled.connect(func(on: bool) -> void:
			Mods.set_enabled(id, on)
			refresh_installed())

	if not rec.removal_staged:
		# Two presses, the second on a button that says what it will do: this
		# deletes a file, and one stray trigger pull should not.
		var remove := _narrow(MenuStyle.row_button("Remove this mod", 18, 260, 52, false))
		remove.pressed.connect(func() -> void:
			if remove.text != "Really remove?":
				remove.text = "Really remove?"
				remove.add_theme_stylebox_override("normal",
					MenuStyle.rounded(MenuStyle.COLOR_BTN_CLEAR, 6))
				return
			var out: Dictionary = Mods.remove(id)
			if not bool(out["ok"]):
				notify("mods:remove", "❌", str(out["error"]), -1.0, MenuToasts.DWELL_FAIL)
			elif bool(out["restart"]):
				notify("mods:remove", "✅", "Removed at the next restart", -1.0, MenuToasts.DWELL_OK)
			else:
				notify("mods:remove", "✅", "Mod removed", -1.0, MenuToasts.DWELL_OK))
		vbox.add_child(remove)


func _build_unreadable_card(vbox: VBoxContainer, u: Dictionary) -> void:
	vbox.add_child(MenuStyle.spacer(8))
	vbox.add_child(MenuStyle.label(str(u["path"]).get_file(), 20, MenuStyle.COLOR_TITLE))
	vbox.add_child(MenuStyle.label("Not loadable", 15, MenuStyle.COLOR_BTN_UPD))
	var why := MenuStyle.label(str(u["reason"]), 16, MenuStyle.COLOR_DESC)
	why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(why)
	var path := str(u["path"])
	var delete := _narrow(MenuStyle.row_button("Delete this file", 18, 260, 52, false))
	delete.pressed.connect(func() -> void:
		if not Mods.remove_unreadable(path):
			notify("mods:remove", "❌", "Cannot delete %s" % path.get_file(),
				-1.0, MenuToasts.DWELL_FAIL))
	vbox.add_child(delete)


static func _status_color(status: int) -> Color:
	match status:
		Mods.Status.LOADED:  return MenuStyle.COLOR_RECOMMENDED
		Mods.Status.PENDING: return MenuStyle.COLOR_BTN_UPD
		Mods.Status.REFUSED: return MenuStyle.COLOR_BTN_UPD
		Mods.Status.FAILED:  return MenuStyle.COLOR_BTN_UPD
	return MenuStyle.COLOR_DESC


# ── Tiles ─────────────────────────────────────────────────────────────────────

## One tile: a 16:9 picture over a name, a line of small print and a badge. A
## Button, so the whole tile is the target -- everything inside ignores the
## pointer and lets it through.
func _make_tile(title: String, subtitle: String, badge: String, badge_color: Color) -> Button:
	var tile := Button.new()
	tile.custom_minimum_size = Vector2(0, TILE_H)
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.clip_contents = true

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["margin_top", "margin_bottom", "margin_left", "margin_right"]:
		margin.add_theme_constant_override(side, 6)
	tile.add_child(margin)

	var box := MenuStyle.vbox(3)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)

	var picture := _art_panel(Vector2(0, ART_H))
	box.add_child(picture)
	tile.set_meta("art", picture.get_meta("art"))

	var name_lbl := MenuStyle.label(title, 18, MenuStyle.COLOR_TITLE)
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lbl.clip_text = true
	box.add_child(name_lbl)
	var sub_lbl := MenuStyle.label(subtitle, 15, MenuStyle.COLOR_DESC)
	sub_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sub_lbl.clip_text = true
	box.add_child(sub_lbl)
	var badge_lbl := MenuStyle.label(badge, 15, badge_color)
	badge_lbl.clip_text = true
	box.add_child(badge_lbl)
	return tile


## The picture frame: a dark plate that shows until the image arrives, and
## stays for a mod that has none. The TextureRect is its meta "art".
func _art_panel(min_size: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = min_size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.clip_contents = true
	panel.add_theme_stylebox_override("panel", _placeholder)

	var none := MenuStyle.label("No preview", 15, MenuStyle.COLOR_DESC)
	none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	none.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(none)

	var rect := TextureRect.new()
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(rect)
	panel.set_meta("art", rect)
	panel.set_meta("none", none)
	return panel


## Show the image at `url` in a tile or picture frame, now if it is in memory
## and when it arrives otherwise.
func _bind_art(holder: Control, url: String) -> void:
	if art == null or url.is_empty():
		return
	var tex := art.get_or_request(url)
	if tex != null:
		_set_art(holder, tex)
		return
	if not _art_waiters.has(url):
		_art_waiters[url] = []
	(_art_waiters[url] as Array).append(holder)


func _set_art(holder: Control, tex: Texture2D) -> void:
	var rect := holder.get_meta("art") as TextureRect
	if rect != null:
		rect.texture = tex


func _on_art_ready(url: String, tex: Texture2D) -> void:
	if not _art_waiters.has(url):
		return
	for holder: Variant in (_art_waiters[url] as Array):
		if is_instance_valid(holder):
			_set_art(holder as Control, tex)
	_art_waiters.erase(url)


## A fixed-width button in a column keeps its width. A VBoxContainer stretches
## its children across by default, which turns a 220 px Back button into a bar.
static func _narrow(btn: Button) -> Button:
	btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	return btn


static func _clear(box: Node) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
