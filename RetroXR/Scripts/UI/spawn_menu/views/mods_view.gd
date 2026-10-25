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
## A mod switched on loads without a restart: Installed's Apply now rebuilds the
## room with it mounted. Switching off, updating or removing one that is RUNNING
## waits for a restart, because a mounted pack cannot be unmounted -- the same
## button then reads Restart now and the app does it itself. The page says which
## is which wherever it matters rather than pretending otherwise.
class_name SpawnMenuModsView
extends VBoxContainer

## The sub-tab changed, so the thumbstick should drive a different scroll.
signal scroll_changed(scroll: ScrollContainer)
## The player pressed the Installed page's button: apply what is waiting, by
## restarting the app (`restart`) or by loading the new mods into this room.
signal apply_requested(restart: bool)

## A tile is one size whatever the menu's width: the grids are HFlowContainers,
## so a wider menu fits more tiles on a row instead of stretching three.
const TILE_W := 326
const TILE_H := 300
const ART_H := 176
const TILE_BTN_H := 40
const TILE_BTN_W := 150
const UPDATE_ALL_KEY := "mods:updateall"
## The toast of a refused netplay join's Get (fetch_for_session).
const SESSION_KEY := "mods:session"
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
var _grid: HFlowContainer = null
var _update_all_btn: Button = null
var _install_all_btn: Button = null
## True while Update all is asking mod.io about each installed mod.
var _checking_updates := false
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

## A download that brought others with it because it needs them, by its job key:
## {deps: job key -> mod, done, staged, adopted: job keys, skip: [{name, why}],
## have: [mods here already]}. Its review answers for all of them; `adopted` are
## ones that were already on their way on their own, which a Discard leaves be.
var _with_needs: Dictionary = {}
## A download asked for because another needs it: its job key -> that one's.
var _needed_for: Dictionary = {}
## Dependency downloads cancelled because the mod that needed them went: their
## cancel is not news (one toast for the mod, not one per thing it brought).
var _quiet_cancel: Dictionary = {}
## Bumped when consent is withdrawn. A mod.io answer that set off before that
## (a press's get_mod, what a mod needs, Update all) is dropped when it lands.
var _consent_serial := 0
## Mods installed from the browser this session that landed switched off: the
## apply bar offers to switch them on and load them (switched_off_new).
var _just_installed: Array[String] = []
var _browse_banner: VBoxContainer = null
## Tests: whether the room counts as ready to apply into (null = ask SceneManager).
## A suite has no room, so without it "applied" and "blocked" look the same.
var room_ready_override: Variant = null
## Tests: whether a download installs and switches on by itself (null = ask
## AppPrefs.mods_auto_install). A suite must not read or write the player's.
var auto_install_override: Variant = null
## The "Install and enable downloads" switches, one per page, kept in step.
var _auto_switches: Array[VRToggle] = []
var _packs_banner: VBoxContainer = null

# Installed
## What is waiting and the button that applies it, above the list AND above one
## mod's page -- the page is where the switch is, so where a change is made.
var _installed_banner: VBoxContainer = null
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
			_rescan_installed()
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
	# The button waits on a settled room, so it is redrawn when one settles.
	SceneManager.scene_content_ready.connect(func(_id: String) -> void: _fill_banner())


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
	_rescan_installed()
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
			var waiting := reviews.keys().size()
			var busy := downloader != null and downloader.is_busy()
			_withdraw()
			if waiting > 0 or busy:
				var lost := PackedStringArray()
				if waiting > 0:
					lost.append("%d downloaded mod%s waiting for review %s discarded" % [
						waiting, "" if waiting == 1 else "s", "was" if waiting == 1 else "were"])
				if busy:
					lost.append("the download in progress was stopped")
				notify("mods:terms", "❌", "mod.io's terms have changed, so %s. Agree to them again under Browse."
					% " and ".join(lost), -1.0, MenuToasts.DWELL_FAIL))


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
	_consent_serial += 1
	if downloader != null:
		downloader.cancel_all()
	reviews.discard_all()
	_with_needs.clear()
	_needed_for.clear()
	_quiet_cancel.clear()
	_checking_updates = false
	_sync_update_all_btn()
	_sync_install_all_btn()
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
	_packs_banner = MenuStyle.vbox(8)
	_packs_banner.visible = false
	vbox.add_child(_packs_banner)
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
	# The same apply bar as Installed's: a mod installed here can be loaded here.
	_browse_banner = MenuStyle.vbox(8)
	_browse_banner.visible = false
	vbox.add_child(_browse_banner)
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

	# Update all sits on the status line, not in the toolbar, where it squeezed the
	# search box on a narrow menu.
	var status_row := MenuStyle.hbox(10)
	_browse_list.add_child(status_row)
	_status_lbl = MenuStyle.label("", 16, MenuStyle.COLOR_DESC)
	_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status_row.add_child(_status_lbl)
	_update_all_btn = MenuStyle.row_button("", 18, 170, 48, false)
	_update_all_btn.name = "UpdateAllButton"
	_update_all_btn.add_theme_font_override("font", MenuIcons.symbols())
	_update_all_btn.pressed.connect(update_all)
	status_row.add_child(_update_all_btn)
	_sync_update_all_btn()
	_install_all_btn = MenuStyle.row_button("", 18, 200, 48, false)
	_install_all_btn.name = "InstallAllButton"
	_install_all_btn.add_theme_font_override("font", MenuIcons.symbols())
	_install_all_btn.add_theme_stylebox_override("normal", MenuStyle.rounded(MenuStyle.COLOR_BTN_DL, 6))
	_install_all_btn.pressed.connect(install_all)
	status_row.add_child(_install_all_btn)
	_sync_install_all_btn()

	_grid = HFlowContainer.new()
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
	add_auto_install_switch(_browse_list)
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


## `keep_scroll`: redrawn for a change made while the player was looking (an
## install, a switch) rather than a new page of results, so it stays where it was.
func _rebuild_grid(keep_scroll: bool = false) -> void:
	var scroll := _pages[0]
	var was := scroll.scroll_vertical
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
	if keep_scroll:
		# The new tiles have no size until the next layout pass.
		scroll.set_deferred("scroll_vertical", was)
	else:
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
	var key := _job_key(int(mod["id"]))
	var busy := downloader != null and downloader.is_queued(key)
	var state := browse_state(mod, busy, has_review(key), _manager())
	var tile := _make_tile(str(mod["name"]), sub, state_text(state), _state_color(state),
		_tile_action(mod, state))
	_bind_art(tile, str(mod["logo_small"]))
	tile.pressed.connect(func() -> void: _open_browse_detail(mod))
	return tile


## The button on a Browse tile, so a mod can be fetched without opening its page:
## Download or Update, Cancel while it comes down, Review once it waits. Null for
## any other state. The same calls as the mod's own page.
func _tile_action(mod: Dictionary, state: String) -> Button:
	var key := _job_key(int(mod["id"]))
	var glyph := 0
	var caption := ""
	var on_press := Callable()
	match state:
		"", "update":
			glyph = MenuIcons.UPDATE if state == "update" else MenuIcons.DOWNLOAD
			caption = "Update" if state == "update" else "Download"
			on_press = func() -> void: _download(mod)
		"busy":
			glyph = MenuIcons.CLOSE
			caption = "Cancel"
			on_press = func() -> void: downloader.cancel(key)
		"review":
			glyph = MenuIcons.CHECK
			caption = "Review"
			on_press = func() -> void: _review_from_tile(key, mod)
		_:
			return null
	var btn := MenuStyle.row_button("%s  %s" % [String.chr(glyph), caption], 16, TILE_BTN_W,
		TILE_BTN_H, false)
	btn.name = "TileAction"
	btn.add_theme_font_override("font", MenuIcons.symbols())
	if state in ["", "update", "review"]:
		btn.add_theme_stylebox_override("normal", MenuStyle.rounded(MenuStyle.COLOR_BTN_DL, 6))
	btn.pressed.connect(on_press)
	return btn


## Redraw the one Browse tile a download belongs to, in place: rebuilding the grid
## would throw the page back to its top.
func _refresh_tile(key: String) -> void:
	if _grid == null:
		return
	for i in _mods.size():
		if _job_key(int(_mods[i]["id"])) != key:
			continue
		if i >= _grid.get_child_count():
			return
		var old := _grid.get_child(i)
		var tile := _browse_tile(_mods[i])
		_grid.add_child(tile)
		_grid.move_child(tile, i)
		_grid.remove_child(old)
		old.queue_free()
		return


## Open the question a parked download is answered in. A pack's member is
## answered by the pack's review and what a mod needs by that mod's: answering
## either on its own pulled it out from under them (the pack's install then read
## a review that was gone, mid-install, with the loader's changes held).
func _review_from_tile(key: String, mod: Dictionary = {}) -> void:
	if _packs_page.owns(key):
		_tabs.current_tab = PACKS_TAB
		_packs_page.show_review_of(key)
		return
	var owner_coming := false
	for owner: Variant in (_needed_for.get(key, []) as Array):
		if has_review(str(owner)):
			_open_single_review(str(owner))
			return
		owner_coming = owner_coming or downloader.is_queued(str(owner))
	if owner_coming:
		notify(_toast_key(key), "⏳", "It installs with the mod that needs it, once that has downloaded",
			-1.0, MenuToasts.DWELL_INFO)
		return
	# Nobody left to answer for it: it is asked about on its own, never stranded.
	if not mod.is_empty():
		_open_mod = mod
	_open_single_review(key)


## Where the downloads waiting for an answer are asked about, for the menu's
## "a restart would lose this" line.
func review_place() -> String:
	var browse := false
	var packs := false
	for key: String in reviews.keys():
		if _packs_page.owns(key):
			packs = true
		else:
			browse = true
	if browse and packs:
		return "Browse and Packs"
	return "Packs" if packs else "Browse"


## The loader the page reads: the Mods autoload, or a suite's scratch one.
func _manager() -> Node:
	if reviews != null and reviews.manager != null:
		return reviews.manager
	return Mods


## Where one mod.io mod stands on this device:
##   ""          not here
##   "nofile"    its page has no file to download yet
##   "installed" here, and the file mod.io offers is the one installed
##   "update"    here, and mod.io offers a different file
##   "staged"    an update is fetched and waits for the next launch
##   "busy"      being downloaded now
##   "review"    downloaded, and waiting for the player's answer
##   "unscanned" mod.io's scan of the file it offers has not finished clean
## `manager` is the loader to ask, the Mods autoload when null.
static func browse_state(mod: Dictionary, busy: bool = false, review: bool = false,
		manager: Node = null) -> String:
	if busy:
		return "busy"
	if review:
		return "review"
	var m: Node = manager if manager != null else Mods
	var rec := m.find_by_source("modio_id", int(mod.get("id", 0))) as ModRecord
	if rec != null and rec.removal_staged:
		# On its way out at the next restart: as far as this page goes it is gone.
		rec = null
	if rec == null:
		if int(mod.get("file_id", 0)) <= 0:
			return "nofile"
		return "unscanned" if not ModioClient.scan_problem(mod).is_empty() else ""
	if not rec.update_staged.is_empty():
		return "staged"
	if int(mod.get("file_id", 0)) > 0 \
			and int((m.source(rec.id) as Dictionary).get("file_id", 0)) != int(mod["file_id"]):
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
	if bool(mod.get("dependencies", false)):
		facts.add_child(MenuStyle.label("Needs other mods, which are downloaded with it.",
			16, MenuStyle.COLOR_DESC))

	var busy := downloader != null and downloader.is_queued(_job_key(mod_id))
	var state := browse_state(mod, busy, has_review(_job_key(mod_id)), _manager())
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
		review_btn.pressed.connect(func() -> void: _review_from_tile(_job_key(mod_id)))
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
	var serial := _consent_serial
	# Asked again rather than taken from the listing: mod.io signs a download
	# address and lets it expire, and the page may have been open for a while.
	client.get_mod(mod_id, func(ok: bool, fresh: Dictionary, error: String) -> void:
		if serial != _consent_serial:
			notify_clear(_toast_key(key))
			return
		if not ok:
			notify(_toast_key(key), "❌", error, -1.0, MenuToasts.DWELL_FAIL)
			return
		_download_fresh(key, fresh))


## Install the download parked under `key` as the review's Install does: what it
## needs first, switched as the player says with it (ModManager.set_enabled takes
## them along), then the mod itself. Returns ModManager.install's answer plus
## `also_failed`, the needs that would not go in.
func _install_reviewed(key: String, enable: bool) -> Dictionary:
	var m := _manager()
	var parked: Dictionary = review(key)
	var manifest: ModManifest = parked["manifest"]
	var source: Dictionary = parked["source"]
	m.hold_changes()
	var also_failed := PackedStringArray()
	var entry: Dictionary = _with_needs.get(key, {})
	for dkey: String in (entry.get("staged", []) as Array):
		if not has_review(dkey):
			continue
		var dep: Dictionary = (entry["deps"] as Dictionary)[dkey]
		var dm: ModManifest = review(dkey)["manifest"]
		var dout := finish_review(dkey, _source_for(dm.id, int(dep["id"]), int(dep["file_id"]),
			str(dep["profile_url"])), false)
		if not bool(dout.get("ok", false)):
			also_failed.append("%s (%s)" % [dm.name, str(dout.get("error", ""))])
	_drop_needs(key, false)
	var out := finish_review(key, _source_for(manifest.id, int(source.get("modio_id", 0)),
		int(source.get("file_id", 0)), str(source.get("profile_url", ""))), enable)
	m.release_changes()
	out["also_failed"] = also_failed
	return out


## Where a single install records the mod came from: a mod here already takes an
## update (who wanted it stays as it was), a new one is wanted on its own.
func _source_for(id: String, modio_id: int, file_id: int, profile_url: String) -> Dictionary:
	var m := _manager()
	if m.mod(id) != null:
		return ModCollectionPlan.source_after_update(m.source(id), modio_id, file_id, profile_url)
	return ModCollectionPlan.source_after_single(m.source(id), modio_id, file_id, profile_url)


# ── Install and enable as soon as it lands ────────────────────────────────────

## Whether a finished download skips its review: installed straight away, and
## switched on when it is new (an update keeps whatever the player chose for it).
func auto_installs() -> bool:
	if auto_install_override != null:
		return bool(auto_install_override)
	return AppPrefs.mods_auto_install


## Install the download parked under `key` as the review's Install would, with
## Enable on for a new mod, and say how it went.
func _auto_install(key: String) -> void:
	var id := (review(key)["manifest"] as ModManifest).id
	_report_install(key, _install_reviewed(key, _manager().mod(id) == null))
	if _open_review == key:
		_close_single_review()
	else:
		_refresh_open_mod(key)


## The toast after one mod's install, by review or by itself.
func _report_install(key: String, out: Dictionary) -> void:
	var also_failed: PackedStringArray = out.get("also_failed", PackedStringArray())
	if not bool(out.get("ok", false)):
		notify(_toast_key(key), "❌", "Not installed: %s" % str(out.get("error", "")),
			-1.0, MenuToasts.DWELL_FAIL)
	elif not also_failed.is_empty():
		notify(_toast_key(key), "❌", "Installed, but not what it needs: %s" % ", ".join(also_failed),
			-1.0, MenuToasts.DWELL_FAIL)
	else:
		var step := next_step()
		notify(_toast_key(key), "✅", "Installed" + ("" if step.is_empty() else " — " + step),
			-1.0, MenuToasts.DWELL_FAIL)


## The switch for AppPrefs.mods_auto_install, under `parent`. Every page that
## has one shows the same answer.
func add_auto_install_switch(parent: Container) -> VRToggle:
	var sw := MenuStyle.switch_row(parent, "Install and enable downloads", auto_installs(), 18, 56,
		"On: a mod installs and switches on as soon as it downloads. Off: each one waits "
		+ "for you to review what it replaces and what it needs, and lands switched off.")
	sw.name = "AutoInstallSwitch"
	_auto_switches.append(sw)
	sw.toggled.connect(func(on: bool) -> void:
		if auto_install_override != null:
			auto_install_override = on
		else:
			AppPrefs.mods_auto_install = on
			AppPrefs.save_prefs()
		for other: VRToggle in _auto_switches:
			if other != sw and is_instance_valid(other):
				other.set_pressed_no_signal(on))
	return sw


# ── Install all ───────────────────────────────────────────────────────────────

## The downloads Install all would install: each one parked for its review, ready
## (nothing it needs still coming down), and answered for by no one else -- a
## pack's members by the pack's question, a mod's needs by that mod's.
func installable_reviews() -> Array[String]:
	var out: Array[String] = []
	for key: String in reviews.keys():
		if (_packs_page != null and _packs_page.owns(key)) or _needed_for.has(key) \
				or _needs_waiting(key) > 0:
			continue
		out.append(key)
	out.sort()
	return out


## Install every download that waits for its review, each as its own Install
## would. They land switched OFF unless the mod was already on -- so the Enable
## switch under Installed is still the player's say -- except that with
## auto_installs a new one goes in on, as it would have had it not waited.
func install_all() -> void:
	var keys := installable_reviews()
	if keys.is_empty():
		return
	var m := _manager()
	m.hold_changes()
	var done := 0
	var failed := PackedStringArray()
	for key: String in keys:
		var manifest: ModManifest = review(key)["manifest"]
		var label := manifest.name
		var out := _install_reviewed(key, auto_installs() and m.mod(manifest.id) == null)
		notify_clear(_toast_key(key))
		if not bool(out.get("ok", false)):
			failed.append("%s (%s)" % [label, str(out.get("error", ""))])
			continue
		done += 1
		for need: String in (out.get("also_failed", PackedStringArray()) as PackedStringArray):
			failed.append("%s, needed by %s" % [need, label])
	m.release_changes()
	if _browse_review.visible and not reviews.has(_open_review):
		_close_single_review()
	_sync_install_all_btn()
	if not failed.is_empty():
		notify("mods:installall", "❌", "Installed %d; not installed: %s" % [done, ", ".join(failed)],
			-1.0, MenuToasts.DWELL_FAIL)
	else:
		var step := next_step(done != 1)
		notify("mods:installall", "✅", "Installed %d mod%s%s" % [done,
			"" if done == 1 else "s", "" if step.is_empty() else " — " + step],
			-1.0, MenuToasts.DWELL_FAIL)


func _sync_install_all_btn() -> void:
	if _install_all_btn == null:
		return
	var n := installable_reviews().size()
	_install_all_btn.visible = n > 0
	_install_all_btn.text = "%s  Install all (%d)" % [String.chr(MenuIcons.CHECK), n]


## The rest of a download, once mod.io has just answered for the mod (`fresh`):
## the checks, what it needs, and the queue. Update all comes in here too, with
## the answer it asked for itself.
func _download_fresh(key: String, fresh: Dictionary) -> void:
	var mod_id := int(fresh["id"])
	if downloader.is_queued(key):
		return
	if has_review(key):
		# Fetched already and waiting for its answer (it may have landed while
		# Update all was asking mod.io): a second copy would only replace it.
		notify(_toast_key(key), "✅", "%s is downloaded already — review it to install" % str(fresh["name"]),
			-1.0, MenuToasts.DWELL_INFO)
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
	if not bool(fresh.get("dependencies", false)):
		_enqueue(key, fresh)
		_refresh_tile(key)
		if int(_open_mod.get("id", 0)) == mod_id:
			_fill_browse_detail()
		return
	# It needs other mods: they come down with it, or it would arrive unable
	# to run (ModManager.dependency_problem).
	notify(_toast_key(key), "⏳", "Asking mod.io what %s needs…" % str(fresh["name"]))
	fetch_needs([fresh], func(nok: bool, needs: Array[Dictionary], nerror: String) -> void:
		if not nok:
			notify(_toast_key(key), "❌", "%s: mod.io did not say what it needs (%s)" % [
				str(fresh["name"]), nerror], -1.0, MenuToasts.DWELL_FAIL)
			return
		if downloader.is_queued(key):
			return
		_fetch_with_needs(key, fresh, needs)
		_refresh_tile(key))


# ── A refused netplay join ────────────────────────────────────────────────────
# The NET view's panel (ModSessionPlan) asks here: the versions mod.io holds, and
# Get. Both go through the client, so the terms gate holds; a download is the
# tile's Download -- asked fresh, scanned, its needs with it, parked for review.

## What mod.io holds of these mods now, in ONE request:
## on_done(ok, versions: modio_id -> its file's version, error). Nothing is sent
## before the player has agreed to mod.io's terms; ok is false then.
func session_versions(ids: Array[int], on_done: Callable) -> void:
	if client == null or not has_consent():
		on_done.call(false, {}, "mod.io's terms are not agreed yet")
		return
	var serial := _consent_serial
	client.get_mods(ids, func(ok: bool, mods: Array[Dictionary], error: String) -> void:
		if serial != _consent_serial:
			on_done.call(false, {}, "mod.io consent was withdrawn")
			return
		var out := {}
		if ok:
			for m: Dictionary in mods:
				out[int(m["id"])] = str(m["file_version"])
		print("[ModsView] a refused join asked mod.io for %d mods: %d answered%s" % [
			ids.size(), out.size(), "" if ok else " (%s)" % error])
		on_done.call(ok, out, error))


## Get what a refused join is missing. `wanted` is modio_id -> the HOST'S version;
## a mod whose file on mod.io is another version is left alone (the panel already
## says the host must update), one stating no version is fetched and the review
## shows what came. Each lands as any download does: waiting for its review,
## then OFF until switched on.
func fetch_for_session(wanted: Dictionary) -> void:
	if client == null or downloader == null or not has_consent() or wanted.is_empty():
		return
	var ids: Array[int] = []
	for id: Variant in wanted:
		ids.append(int(id))
	notify(SESSION_KEY, "⏳", "Asking mod.io for the host's %d mod%s…" % [
		ids.size(), "" if ids.size() == 1 else "s"])
	var serial := _consent_serial
	client.get_mods(ids, func(ok: bool, mods: Array[Dictionary], error: String) -> void:
		if serial != _consent_serial:
			notify_clear(SESSION_KEY)
			return
		if not ok:
			notify(SESSION_KEY, "❌", "Could not ask mod.io for the host's mods: %s" % error,
				-1.0, MenuToasts.DWELL_FAIL)
			return
		var started := 0
		for fresh: Dictionary in mods:
			var have := str(fresh["file_version"])
			var want := str(wanted.get(int(fresh["id"]), ""))
			if not have.is_empty() and have != want:
				print("[ModsView] host's %s is %s, mod.io has %s: not fetched" % [
					str(fresh["name"]), want, have])
				continue
			_download_fresh(_job_key(int(fresh["id"])), fresh)
			started += 1
		notify(SESSION_KEY, "⏳" if started > 0 else "❌",
			"Getting %d of the host's mods — review them here to install" % started
			if started > 0 else "None of the host's versions are on mod.io",
			-1.0, MenuToasts.DWELL_INFO if started > 0 else MenuToasts.DWELL_FAIL))


# ── Update all ────────────────────────────────────────────────────────────────

## Every installed mod that came from mod.io, asked about in ONE request
## (ModioClient.get_mods), and each whose file mod.io has changed downloaded at
## once, as its tile's Update would. Each still waits for its own review. Mods
## with an update already staged, coming down or waiting are left out. It asked
## get_mod for each mod in turn once, which took a request's round trip per mod
## before the first download began.
func update_all() -> void:
	if client == null or downloader == null or _checking_updates:
		return
	var ids := modio_installed()
	if ids.is_empty():
		notify(UPDATE_ALL_KEY, "✅", "No mods from mod.io to update", -1.0, MenuToasts.DWELL_INFO)
		return
	_checking_updates = true
	_sync_update_all_btn()
	notify(UPDATE_ALL_KEY, "⏳", "Checking %d mod%s for updates…" % [
		ids.size(), "" if ids.size() == 1 else "s"])
	var serial := _consent_serial
	client.get_mods(ids, func(ok: bool, mods: Array[Dictionary], error: String) -> void:
		if serial != _consent_serial:
			notify_clear(UPDATE_ALL_KEY)
			return
		_checking_updates = false
		_sync_update_all_btn()
		if not ok:
			notify(UPDATE_ALL_KEY, "❌", "Could not ask mod.io for updates: %s" % error,
				-1.0, MenuToasts.DWELL_FAIL)
			return
		var found: Array[Dictionary] = []
		for fresh: Dictionary in mods:
			if browse_state(fresh, false, false, _manager()) == "update":
				found.append(fresh)
		_finish_update_all(found, ids.size() - mods.size()))


## The mod.io id of each installed mod an update could be fetched for now.
func modio_installed() -> Array[int]:
	var out: Array[int] = []
	var m := _manager()
	for rec: ModRecord in m.all_mods():
		var mid := int((m.source(rec.id) as Dictionary).get("modio_id", 0))
		# Being removed: updating it would install it again and undo the removal.
		if mid <= 0 or not rec.update_staged.is_empty() or rec.removal_staged:
			continue
		var key := _job_key(mid)
		if (downloader != null and downloader.is_queued(key)) or has_review(key):
			continue
		out.append(mid)
	return out


## `missing`: how many mod.io did not return (removed, or hidden from the game).
func _finish_update_all(found: Array[Dictionary], missing: int) -> void:
	for fresh: Dictionary in found:
		_download_fresh(_job_key(int(fresh["id"])), fresh)
	var tail := "" if missing == 0 else " (%d no longer on mod.io)" % missing
	if found.is_empty():
		notify(UPDATE_ALL_KEY, "✅" if missing == 0 else "❌",
			"Every mod from mod.io is up to date%s" % tail, -1.0,
			MenuToasts.DWELL_INFO if missing == 0 else MenuToasts.DWELL_FAIL)
	else:
		notify(UPDATE_ALL_KEY, "⏳", "Updating %d mod%s%s" % [found.size(),
			"" if found.size() == 1 else "s", tail], -1.0, MenuToasts.DWELL_INFO)


func _sync_update_all_btn() -> void:
	if _update_all_btn == null:
		return
	_update_all_btn.disabled = _checking_updates
	_update_all_btn.text = "%s  %s" % [String.chr(MenuIcons.UPDATE),
		"Checking…" if _checking_updates else "Update all"]


func _enqueue(key: String, mod: Dictionary) -> void:
	if client != null and not has_consent():
		return
	downloader.enqueue(key, str(mod["name"]), str(mod["download_url"]),
		int(mod["file_size"]), str(mod["file_md5"]),
		{"modio_id": int(mod["id"]), "file_id": int(mod["file_id"]),
			"profile_url": str(mod["profile_url"])})


## Everything `mods` need, all the way down, asked of mod.io one mod at a time
## and gathered without repeats (ModCollectionPlan.with_needs). Only a mod mod.io
## says has dependencies is asked about. Used by a single download and a pack.
## callback(ok: bool, needs: Array[Dictionary], error: String)
func fetch_needs(mods: Array, callback: Callable) -> void:
	var asking := mods.filter(func(m: Dictionary) -> bool: return bool(m.get("dependencies", false)))
	var none: Array[Dictionary] = []
	var serial := _consent_serial
	_fetch_needs_from(asking, 0, none,
		func(ok: bool, needs: Array[Dictionary], error: String) -> void:
			# Withdrawn while mod.io was answering: whatever this was for is gone.
			if serial == _consent_serial:
				callback.call(ok, needs, error))


func _fetch_needs_from(mods: Array, i: int, so_far: Array[Dictionary], callback: Callable) -> void:
	if i >= mods.size():
		callback.call(true, so_far, "")
		return
	client.list_dependencies(int((mods[i] as Dictionary)["id"]),
		func(ok: bool, deps: Array[Dictionary], error: String) -> void:
			if not ok:
				callback.call(false, so_far, error)
				return
			_fetch_needs_from(mods, i + 1, ModCollectionPlan.with_needs(so_far, deps), callback))


## Download `mod` and every one of `needs` that is not here at mod.io's file.
## Those it brings in are answered for in its review rather than one by one.
func _fetch_with_needs(key: String, mod: Dictionary, needs: Array) -> void:
	var plan := ModCollectionPlan.plan_install(needs, SpawnMenuModsPacksPage.installed_files())
	var entry := {"deps": {}, "done": [], "staged": [], "adopted": [],
		"skip": (plan["skip"] as Array).duplicate(true),
		"have": (plan["have"] as Array).duplicate(true)}
	for dep: Dictionary in (plan["fetch"] as Array):
		var dkey := _job_key(int(dep["id"]))
		if dkey == key:
			continue
		if _packs_page.owns(dkey):
			# On its way in a pack, which answers for it.
			(entry["skip"] as Array).append({"name": str(dep["name"]),
				"why": "it is being installed with a pack; install that too"})
			continue
		(entry["deps"] as Dictionary)[dkey] = dep
		var needers: Array = _needed_for.get(dkey, [])
		if not needers.has(key):
			needers.append(key)
		_needed_for[dkey] = needers
		if has_review(dkey):
			# Fetched already, on its own, and waiting: this review answers for it.
			(entry["done"] as Array).append(dkey)
			(entry["staged"] as Array).append(dkey)
			(entry["adopted"] as Array).append(dkey)
		elif downloader.is_queued(dkey):
			(entry["adopted"] as Array).append(dkey)
		else:
			_enqueue(dkey, dep)
	_with_needs[key] = entry
	_enqueue(key, mod)
	if int(_open_mod.get("id", 0)) == int(mod["id"]):
		_fill_browse_detail()


## One of the downloads mods brought with them ended; `staged` when it was fetched
## and vetted and now waits in their reviews. EVERY mod that needs it is told: it
## used to be recorded against the last one only, and the first then waited on it
## for ever ("Downloading what it needs…").
func _need_done(dkey: String, staged: bool, error: String) -> void:
	# A copy: installing an owner here drops it from this very list.
	for owner: Variant in (_needed_for.get(dkey, []) as Array).duplicate():
		var key := str(owner)
		var entry: Dictionary = _with_needs.get(key, {})
		if entry.is_empty() or (entry["done"] as Array).has(dkey):
			continue
		(entry["done"] as Array).append(dkey)
		if staged:
			(entry["staged"] as Array).append(dkey)
		else:
			(entry["skip"] as Array).append({"name": str(((entry["deps"] as Dictionary)[dkey] as Dictionary)["name"]),
				"why": error if not error.is_empty() else "the download was cancelled"})
		if auto_installs() and has_review(key) and _needs_waiting(key) == 0 \
				and not _packs_page.owns(key) and not _needed_for.has(key):
			_auto_install(key)
		elif _open_review == key:
			_fill_single_review()
	_sync_install_all_btn()


## How many of what `key` brought with it are still coming down.
func _needs_waiting(key: String) -> int:
	var entry: Dictionary = _with_needs.get(key, {})
	if entry.is_empty():
		return 0
	return (entry["deps"] as Dictionary).size() - (entry["done"] as Array).size()


## Forget what `key` brought with it. What is still coming down is cancelled, and
## with `discard` what came down and waits is thrown away -- all but what was
## already on its way on its own, and what another mod still needs.
func _drop_needs(key: String, discard: bool) -> void:
	var entry: Dictionary = _with_needs.get(key, {})
	_with_needs.erase(key)
	for dkey: String in (entry.get("deps", {}) as Dictionary):
		var needers: Array = _needed_for.get(dkey, [])
		needers.erase(key)
		if not needers.is_empty():
			continue
		_needed_for.erase(dkey)
		if (entry["adopted"] as Array).has(dkey):
			continue
		if not (entry["done"] as Array).has(dkey):
			if downloader.is_queued(dkey):
				_quiet_cancel[dkey] = true
				downloader.cancel(dkey)
		elif discard and (entry["staged"] as Array).has(dkey):
			discard_review(dkey)


func _on_job_started(key: String, label: String, _total: int) -> void:
	# A new run of it: whatever quiet cancel was meant for the last one is spent.
	_quiet_cancel.erase(key)
	_refresh_tile(key)
	_last_pct.erase(key)
	notify(_toast_key(key), "⏳", "Downloading %s" % label, 0.0)
	_refresh_open_mod(key)
	_packs_page.on_job_started(key)


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
	_refresh_tile(key)
	if _quiet_cancel.has(key):
		_quiet_cancel.erase(key)
		notify_clear(_toast_key(key))
		return
	if _packs_page.owns(key):
		notify_clear(_toast_key(key))
		_packs_page.on_job_done(key, false, "")
		return
	if _needed_for.has(key):
		notify_clear(_toast_key(key))
		_need_done(key, false, "")
		# A dependency can need mods of its own: they go with it, or they are left
		# parked under an owner that is gone, unanswerable, holding off a restart.
		_drop_needs(key, true)
		_packs_page.drop_tags_for(key)
		return
	# What it was bringing with it goes with it.
	_drop_needs(key, true)
	notify(_toast_key(key), "❌", "Download cancelled", -1.0, MenuToasts.DWELL_INFO)
	_refresh_open_mod(key)


func _on_job_finished(key: String, ok: bool, error: String, result: Dictionary) -> void:
	if client != null and not has_consent():
		# It finished after consent was withdrawn: nothing of it is kept, or it
		# would wait for an answer behind the terms gate and hold off a restart.
		if has_review(key):
			reviews.discard(key)
		notify_clear(_toast_key(key))
		_refresh_tile(key)
		return
	if _quiet_cancel.has(key):
		# Cancelled because nothing needs it any more, but the transfer had already
		# ended (cancel only stops one still running): what landed is not wanted.
		_quiet_cancel.erase(key)
		if has_review(key):
			reviews.discard(key)
		notify_clear(_toast_key(key))
		_refresh_tile(key)
		return
	_refresh_tile(key)
	_sync_install_all_btn.call_deferred()
	var waiting := ok and bool(result.get("review", false))
	# A pack's members are answered for together, by the pack, and what a mod
	# needs by that mod's review.
	if _packs_page.owns(key):
		notify_clear(_toast_key(key))
		_packs_page.on_job_done(key, waiting, error)
		return
	if _needed_for.has(key):
		notify_clear(_toast_key(key))
		_need_done(key, waiting, error)
		if not waiting:
			_drop_needs(key, true)
			_packs_page.drop_tags_for(key)
		return
	if not waiting:
		_drop_needs(key, true)
		_packs_page.drop_tags_for(key)
	if not ok:
		# The loader's own sentence when it refused the pack, the transfer's
		# otherwise. Either way the player learns why nothing was installed.
		notify(_toast_key(key), "❌", "Not installed: %s" % error, -1.0, MenuToasts.DWELL_FAIL)
	elif waiting and auto_installs():
		if _needs_waiting(key) == 0:
			_auto_install(key)
			return
		# _need_done installs it when the last of what it needs lands.
		notify(_toast_key(key), "⏳", "Downloaded — installing once what it needs is here",
			-1.0, MenuToasts.DWELL_INFO)
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
	var parked := reviews.parked(key)
	var id := (parked["manifest"] as ModManifest).id if not parked.is_empty() else ""
	var new := not id.is_empty() and _manager().mod(id) == null
	var out := reviews.finish(key, source, enable)
	if bool(out.get("ok", false)) and not id.is_empty():
		# A NEW mod that landed off is offered to the apply bar; an update keeps
		# whatever the player chose for it.
		if new and not _manager().is_enabled(id) and not _just_installed.has(id):
			_just_installed.append(id)
		_packs_page.tag_pending()
	_sync_install_all_btn()
	_fill_banner()
	return out


func discard_review(key: String) -> void:
	reviews.discard(key)
	_packs_page.drop_tags_for(key)
	_refresh_tile(key)
	_sync_install_all_btn()


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
	var old: ModRecord = _manager().mod(manifest.id)

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

	# What it needs, and what becomes of each: installed with it, here already,
	# still coming down, or not to be had -- in which case it will not run.
	var needs: Dictionary = _with_needs.get(key, {})
	if not needs.is_empty():
		_browse_review.add_child(MenuStyle.label("It needs:", 18, MenuStyle.COLOR_LICENSE))
		for dkey: String in (needs["deps"] as Dictionary):
			var dep: Dictionary = (needs["deps"] as Dictionary)[dkey]
			if (needs["staged"] as Array).has(dkey) and has_review(dkey):
				var dm: ModManifest = review(dkey)["manifest"]
				claims[dm.name] = Array(dm.shadowing_claims())
				_browse_review.add_child(MenuStyle.label("    %s %s, installed with it" % [dm.name, dm.version],
					16, MenuStyle.COLOR_LICENSE))
				for path: String in dm.shadowing_claims():
					_browse_review.add_child(MenuStyle.label("        Replaces " + path, 15, MenuStyle.COLOR_BTN_UPD))
			elif not (needs["done"] as Array).has(dkey):
				_browse_review.add_child(MenuStyle.hint("    %s, downloading…" % str(dep["name"])))
		for dep: Dictionary in (needs["have"] as Array):
			_browse_review.add_child(MenuStyle.hint("    %s, installed already" % str(dep["name"])))
		for entry: Dictionary in (needs["skip"] as Array):
			_browse_review.add_child(MenuStyle.label("    %s cannot be installed: %s. It will not run without it." % [
				str(entry["name"]), str(entry["why"])], 15, MenuStyle.COLOR_BTN_UPD))
	for line: String in ModCollectionPlan.conflicts(claims):
		_browse_review.add_child(MenuStyle.label("! " + line, 16, MenuStyle.COLOR_BTN_UPD))

	_browse_review.add_child(HSeparator.new())
	# An update keeps whatever the player already chose for this mod.
	var enable: VRToggle = null
	if not _manager().is_enabled(manifest.id):
		enable = MenuStyle.switch_row(_browse_review, "Enable", false)
	var actions := MenuStyle.hbox(10)
	_browse_review.add_child(actions)
	var waiting := _needs_waiting(key)
	var install := MenuStyle.row_button("Install" if waiting == 0
		else "Downloading what it needs…", 20, 220 if waiting == 0 else 360, 56, false)
	install.disabled = waiting > 0
	install.add_theme_stylebox_override("normal", MenuStyle.rounded(MenuStyle.COLOR_BTN_DL, 6))
	install.pressed.connect(func() -> void:
		_report_install(key, _install_reviewed(key, enable != null and enable.button_pressed))
		_close_single_review())
	actions.add_child(install)
	var discard := MenuStyle.row_button("Discard", 20, 200, 56, false)
	discard.pressed.connect(func() -> void:
		_drop_needs(key, true)
		discard_review(key)
		notify(_toast_key(key), "❌", "Download discarded", -1.0, MenuToasts.DWELL_INFO)
		_close_single_review())
	actions.add_child(discard)


func _refresh_open_mod(key: String) -> void:
	if not _open_mod.is_empty() and _job_key(int(_open_mod["id"])) == key:
		_fill_browse_detail()


# ── Installed ─────────────────────────────────────────────────────────────────

func _build_installed(vbox: VBoxContainer) -> void:
	_installed_banner = MenuStyle.vbox(8)
	_installed_banner.visible = false
	vbox.add_child(_installed_banner)
	_installed_list = MenuStyle.vbox(10)
	vbox.add_child(_installed_list)
	_installed_detail = MenuStyle.vbox(8)
	_installed_detail.visible = false
	vbox.add_child(_installed_detail)


func _on_mods_changed() -> void:
	refresh_installed()
	_sync_install_all_btn()
	if _browse_detail.visible and not _open_mod.is_empty():
		_fill_browse_detail()
	elif _fetched and _browse_list.visible:
		_rebuild_grid(true)
	_packs_page.on_mods_changed()


## A pack dropped into the folder since boot shows up when the page does. The
## rescan announces what it found (mods_changed), which repaints the page; when
## it finds nothing the page is repainted here.
func _rescan_installed() -> void:
	if Mods.rescan() == 0:
		refresh_installed()


func refresh_installed() -> void:
	if _installed_list == null:
		return
	_fill_banner()
	if not _open_installed.is_empty() and Mods.mod(_open_installed) == null:
		_open_installed = ""
	_installed_list.visible = _open_installed.is_empty()
	_installed_detail.visible = not _open_installed.is_empty()
	if not _open_installed.is_empty():
		_fill_installed_detail()
		return

	_clear(_installed_list)
	var mods: Array = Mods.all_mods()
	var unreadable: Array = Mods.unreadable()
	if mods.is_empty() and unreadable.is_empty():
		_installed_list.add_child(MenuStyle.hint(
			"No mods installed. Get one from the Browse tab, or drop a .zip or "
			+ ".pck in the folder below."))
	else:
		# Every mod that is off and could run, switched on at once. The banner
		# then offers to apply them, as it does after one switch.
		var off := Mods.switchable_off()
		if not off.is_empty():
			var enable_all := MenuStyle.row_button("Enable all (%d)" % off.size(), 20, 260, 56, false)
			enable_all.name = "EnableAllButton"
			enable_all.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			enable_all.pressed.connect(func() -> void:
				Mods.enable_all()
				refresh_installed())
			_installed_list.add_child(enable_all)
		var grid := HFlowContainer.new()
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


## The changes that have not taken effect, and ONE button for all of them.
##
## New mods that can be mounted now (ModManager.apply_plan's `live`) are loaded
## into this room, which is rebuilt behind the loading curtain with everything in
## it carried across. Anything a running pack stands in the way of -- switching
## one off, updating or removing it, or a mod that replaces a shipped file --
## takes a restart, which the app does itself; that button applies the lot.
func _fill_banner() -> void:
	for box: VBoxContainer in [_installed_banner, _browse_banner, _packs_banner]:
		_fill_banner_into(box)


## Mods installed from the browser this session that are still off and could be
## switched on. One the player has switched on since is dropped for good.
func switched_off_new() -> Array[String]:
	var m := _manager()
	var off: Array = m.switchable_off()
	var keep: Array[String] = []
	var out: Array[String] = []
	for id: String in _just_installed:
		if m.mod(id) == null or m.is_enabled(id):
			continue
		keep.append(id)
		if off.has(id):
			out.append(id)
	_just_installed = keep
	return out


## What the apply bar says to do next, for the toast after an install: "" when
## nothing waits. Read off the same plan the bar is drawn from, so the two agree.
func next_step(many: bool = false) -> String:
	var it := "them" if many else "it"
	if not switched_off_new().is_empty():
		return "enable and apply %s from the bar above" % it
	var plan: Dictionary = _manager().apply_plan()
	if not str(plan["blocked"]).is_empty():
		return "see the bar above"
	if bool(plan["restart"]):
		return "restart to finish from the bar above"
	if _plan_is_live(plan):
		return "apply %s from the bar above" % it
	return ""


func _fill_banner_into(box: VBoxContainer) -> void:
	if box == null:
		return
	_clear(box)
	var m := _manager()
	var off := switched_off_new()
	var plan: Dictionary = m.apply_plan()
	var live: Array = plan["live"]
	var restart := bool(plan["restart"])
	box.visible = not off.is_empty() or restart or _plan_is_live(plan)
	if not box.visible:
		return
	if not off.is_empty():
		# A download lands OFF, and an off mod is not in the plan: without this the
		# player had to find each one under Installed and switch it on before
		# there was anything to apply.
		var names := off.map(func(id: String) -> String: return str(m.mod(id).manifest.name))
		var head := MenuStyle.label("%s %s installed and switched off. Enable %s to load %s into this room." % [
			", ".join(names), "is" if off.size() == 1 else "are", "it" if off.size() == 1 else "them",
			"it" if off.size() == 1 else "them"], 18, MenuStyle.COLOR_RECOMMENDED)
		head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(head)
		var row := MenuStyle.hbox(10)
		box.add_child(row)
		var go := MenuStyle.row_button("Enable and apply now", 20, 300, 56, false)
		go.name = "EnableApplyButton"
		go.add_theme_stylebox_override("normal", MenuStyle.rounded(MenuStyle.COLOR_BTN_DL, 6))
		go.pressed.connect(func() -> void: _enable_and_apply(off))
		row.add_child(go)
		var later := MenuStyle.row_button("Leave off", 20, 200, 56, false)
		later.pressed.connect(func() -> void:
			_just_installed.clear()
			_fill_banner())
		row.add_child(later)
		box.add_child(HSeparator.new())
		return
	var text := "Some of your changes need RetroXR to restart."
	if not restart:
		text = "%s. Applying reloads this room, and everything in it comes back where it was." \
			% live_summary(plan)
	var head2 := MenuStyle.label(text, 18, MenuStyle.COLOR_RECOMMENDED)
	head2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(head2)
	var blocked := str(plan["blocked"])
	if not blocked.is_empty():
		box.add_child(MenuStyle.hint(blocked))
		box.add_child(HSeparator.new())
		return
	var why := _apply_blocker(restart)
	var button := _narrow(MenuStyle.row_button(
		"Restart now" if restart else "Apply now", 20, 260, 56, false))
	button.name = "ApplyButton"
	button.add_theme_stylebox_override("normal", MenuStyle.rounded(MenuStyle.COLOR_BTN_DL, 6))
	button.disabled = not why.is_empty()
	button.pressed.connect(_on_apply_pressed)
	box.add_child(button)
	if not why.is_empty():
		box.add_child(MenuStyle.hint(why))
	box.add_child(HSeparator.new())


## True when applying would change something in this room without a restart.
static func _plan_is_live(plan: Dictionary) -> bool:
	return not (plan["live"] as Array).is_empty() or not (plan.get("unload", []) as Array).is_empty() \
		or not (plan.get("update", []) as Array).is_empty()


## What Apply now will do, for the bar: "Load A; update B to 2.0; switch off C".
static func live_summary(plan: Dictionary) -> String:
	var parts := PackedStringArray()
	var names := func(recs: Array) -> String:
		return ", ".join(recs.map(func(r: ModRecord) -> String: return r.manifest.name))
	if not (plan["live"] as Array).is_empty():
		parts.append("load " + names.call(plan["live"]))
	for r: ModRecord in (plan.get("update", []) as Array):
		parts.append("update %s to %s" % [r.manifest.name, r.update_staged])
	var off: Array = (plan.get("unload", []) as Array).filter(func(r: ModRecord) -> bool:
		return not r.removal_staged)
	var gone: Array = (plan.get("unload", []) as Array).filter(func(r: ModRecord) -> bool:
		return r.removal_staged)
	if not off.is_empty():
		parts.append("switch off " + names.call(off))
	if not gone.is_empty():
		parts.append("remove " + names.call(gone))
	var text := "; ".join(parts)
	return text.substr(0, 1).to_upper() + text.substr(1)


## Switch on what was just installed, then apply as the bar's Apply does.
func _enable_and_apply(ids: Array[String]) -> void:
	var m := _manager()
	m.hold_changes()
	for id: String in ids:
		m.set_enabled(id, true)
	m.release_changes()
	_just_installed.clear()
	_fill_banner()
	var plan: Dictionary = m.apply_plan()
	# Switched on but unable to run (a mod it needs is missing): there is nothing
	# to load, and the bar would just vanish. Say why instead.
	var cannot := PackedStringArray()
	for id: String in ids:
		var rec: ModRecord = m.mod(id)
		var why: String = m.dependency_problem(rec) if rec != null else ""
		if not why.is_empty():
			cannot.append("%s: %s" % [rec.manifest.name, why])
	if not cannot.is_empty():
		notify("mods:apply", "❌", "Switched on, but cannot load — %s" % "; ".join(cannot),
			-1.0, MenuToasts.DWELL_FAIL)
		if not bool(plan["restart"]) and not _plan_is_live(plan):
			return
	if bool(plan["restart"]):
		# The bar said "load it into this room"; a restart is a different promise
		# (it replaces a shipped file, or another change is waiting). It is now
		# the bar's own Restart now, for the player to press.
		notify("mods:apply", "⏳", "Switched on — it needs RetroXR to restart: press Restart now",
			-1.0, MenuToasts.DWELL_FAIL)
		return
	_on_apply_pressed()


## Asked again at the press: the banner was drawn a while ago, and a download may
## have started or the room begun to change since.
func _on_apply_pressed() -> void:
	var plan: Dictionary = _manager().apply_plan()
	var restart := bool(plan["restart"])
	if not restart and not _plan_is_live(plan):
		_fill_banner()
		return
	var why := str(plan["blocked"])
	if why.is_empty():
		why = _apply_blocker(restart)
	if not why.is_empty():
		notify("mods:apply", "❌", why, -1.0, MenuToasts.DWELL_FAIL)
		_fill_banner()
		return
	apply_requested.emit(restart)


## Why the button may not be pressed now, "" when it may. Either way the room is
## rebuilt or carried, so it has to have finished arriving; a restart also loses
## whatever is downloading, and the downloads parked for review (the next launch
## sweeps those away).
func _apply_blocker(restart: bool) -> String:
	var ready: bool = bool(room_ready_override) if room_ready_override != null \
		else SceneManager.is_scene_content_ready(SceneManager.current_scene_id)
	if not ready:
		return "Wait for the room to finish loading."
	if restart and _menu != null and _menu.has_method("busy_reason"):
		return str(_menu.busy_reason())
	return ""


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
		# Unloaded live: nothing of it runs now, only its file is left to delete.
		return "Removed — its file goes at the next launch" if not rec.loaded \
			else "Removed at next restart"
	if not rec.update_staged.is_empty():
		# The same version number again is a new copy, not an update to it: a
		# re-download, or an author who re-uploaded without bumping the number.
		if rec.update_staged == rec.manifest.version:
			return "A new copy of %s installs at next restart" % rec.update_staged
		return "Updates to %s at next restart" % rec.update_staged
	if rec.blocked_by_dependency:
		return "Needs another mod"
	return Mods.status_text(rec.status)


## One line per mod `rec` needs, {text, ok}: which, at least which version, and
## what that mod is doing now -- the first thing to read when it did not load.
## `ok` is false where that mod stands in its way: missing, too old, going, or
## unable to run itself. Switched off is not that, since switching `rec` on
## switches it on too.
static func dependency_lines(rec: ModRecord) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for dep: Dictionary in rec.manifest.dependencies:
		var dep_id := str(dep["id"])
		var other := Mods.mod(dep_id)
		var named := dep_id if other == null else other.manifest.name
		if not str(dep["min"]).is_empty():
			named += " %s or newer" % str(dep["min"])
		var state := "not installed"
		var ok := false
		if other != null:
			if other.removal_staged:
				state = "being removed"
			elif not ModManifest.version_at_least(other.manifest.version, str(dep["min"])):
				state = "%s is installed" % other.manifest.version
			elif other.loaded:
				state = "running"
				ok = true
			elif Mods.is_enabled(dep_id):
				state = installed_status_text(other).to_lower()
				ok = other.status != Mods.Status.FAILED and other.status != Mods.Status.REFUSED
			else:
				state = "switched off"
				ok = other.status != Mods.Status.REFUSED
		out.append({"text": "Needs %s — %s" % [named, state], "ok": ok})
	return out


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
		var adds := api.summary()
		# A part other mods use registers nothing, and "nothing" reads as broken.
		if adds == "nothing" and not Mods.needed_by(rec.id).is_empty():
			adds = "nothing to the room by itself; the mods that need it use what it carries"
		vbox.add_child(MenuStyle.label("Adds: " + adds, 16, MenuStyle.COLOR_LICENSE))
		var contributions: Dictionary = api.contributions()
		for kind: String in ModApi.KINDS:
			for label: String in (contributions.get(kind, []) as Array):
				vbox.add_child(MenuStyle.hint("    • " + label))
		for problem: String in api.problems():
			vbox.add_child(MenuStyle.label("    ! " + problem, 15, MenuStyle.COLOR_BTN_UPD))

	# A mod a dependency stops says so on that dependency's own line, below.
	if not rec.reason.is_empty() and not rec.blocked_by_dependency:
		var reason := MenuStyle.label(rec.reason, 16,
			MenuStyle.COLOR_BTN_UPD if status == Mods.Status.REFUSED
			or status == Mods.Status.FAILED else MenuStyle.COLOR_DESC)
		reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(reason)

	# What it needs and what needs it: the mods that go on and off with this one.
	for line: Dictionary in dependency_lines(rec):
		var dep_label := MenuStyle.label(str(line["text"]), 16,
			MenuStyle.COLOR_LICENSE if bool(line["ok"]) else MenuStyle.COLOR_BTN_UPD)
		dep_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(dep_label)
	var users: Array[String] = Mods.needed_by(rec.id)
	if not users.is_empty():
		vbox.add_child(MenuStyle.hint("Needed by " + ", ".join(PackedStringArray(
			users.map(func(other: String) -> String: return Mods.mod(other).manifest.name)))))

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
		# Said before it happens: the switch takes these with it.
		var with_it: Array[String] = Mods.switched_off_with(id) if Mods.is_enabled(id) \
			else Mods.switched_on_with(id)
		if not with_it.is_empty():
			var way := "off" if Mods.is_enabled(id) else "on"
			vbox.add_child(MenuStyle.hint("Switching it %s also switches %s %s." % [way, way,
				", ".join(PackedStringArray(with_it.map(
					func(other: String) -> String: return Mods.mod(other).manifest.name)))]))

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
func _make_tile(title: String, subtitle: String, badge: String, badge_color: Color,
		action: Button = null) -> Button:
	var tile := Button.new()
	# Fixed: a wider menu fits more tiles on a row, it does not stretch them.
	tile.custom_minimum_size = Vector2(TILE_W, TILE_H)
	tile.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
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
	var row := MenuStyle.hbox(6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.custom_minimum_size = Vector2(0, TILE_BTN_H)
	box.add_child(row)
	var badge_lbl := MenuStyle.label(badge, 15, badge_color)
	badge_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	badge_lbl.clip_text = true
	badge_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	badge_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(badge_lbl)
	# Its own press, not the tile's: a Button inside the tile takes the click first.
	if action != null:
		row.add_child(action)
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
