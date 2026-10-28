## SpawnMenuSpawnView — the menu's SPAWN tab, and everything that feeds it.
##
## Ten sub-tabs of things the player can pull into the room: systems, cartridges,
## TVs, books, videos, DVDs, CDs, tapes, objects, controllers. Each one asks for
## a spawn by signal and the menu relays it out to the controller.
##
## Three subsystems live here rather than beside it, because all three exist to
## keep this list right:
##
##  * the virtualized ROM row list — a few recycled rows over a list of
##    thousands, so scrolling a big platform does not allocate;
##  * the ScreenScraper client's UI — asking the queue, showing what came back
##    (SpawnScrapeUi), and the game-detail and ROM-variants panels built from it;
##  * the RomM handlers — sync, download, cache (RommSpawnSync). They read as
##    notification code but every one of them ends by rebuilding a row, a list or
##    an index here, so they answer to this view.
class_name SpawnMenuSpawnView
extends Control

signal spawn_requested(type: String)
## `options` is what the hold sub-menu forced -- "shell_preset" or "shell_color",
## "body_region" -- and empty for a plain click.
signal spawn_cartridge_requested(rom_path: String, game_label: String, systemid: String,
		options: Dictionary)
signal spawn_manual_requested(pdf_path: String)
signal spawn_poster_requested(image_path: String)
signal spawn_video_requested(video_path: String)
signal spawn_dvd_requested(dvd_path: String)
signal spawn_cd_requested(album_path: String)
signal spawn_cassette_requested(album_path: String)
signal spawn_record_requested(album_path: String)
signal default_core_changed(systemid: String, core_name: String)
## Which scroll the thumbstick should drive — the sub-tabs each own one, and the
## two grid browsers own one per page.
signal scroll_changed(scroll: ScrollContainer)
## A RomM sync or download changed something the OPTIONS readout shows.
signal romm_state_changed

const WHEEL_BOX := Vector2i(300, 76)
## A row's scraped label, which the Cover slot draws at 72x96. Four times that
## leaves the mips room for a menu resized up and read at an angle, and keeps a
## 1000-px scan from being uploaded whole — two of those land in a frame, and a
## texture upload is the costly part of a Quest frame (books.md).
const LABEL_BOX := Vector2i(288, 384)
## Poster row thumbnails. Bounded for the same reason WHEEL_BOX is: an unbounded
## Button.icon with expand_icon draws far past its row and spills into the
## neighbours.
const POSTER_THUMB_BOX := Vector2i(96, 72)
const MAX_POSTER_THUMBS := 200
## Typing in the ROM filter rebuilds the list; this waits for a pause first.
const SEARCH_DEBOUNCE_SEC := 0.18
## The colour the cartridge panel's Custom sliders open on: a mid blue, so hue,
## saturation and brightness each visibly change it from the first drag, where a
## grey would leave the hue slider doing nothing.
const CUSTOM_SHELL_START := Color(0.26, 0.44, 0.65)
## The Custom colour wheel's diameter: about the height of the three sliders and
## the flake switch beside it.
const CUSTOM_SHELL_WHEEL := 340.0

## Applied to a whole row rather than its label: a server-only title with the
## server down has no working control on it, and dimming only the icon reads as
## decoration rather than as "none of this does anything".
const UNREACHABLE_DIM := Color(1.0, 1.0, 1.0, 0.45)

## Library systems with no Cartridges tile: their games are picked on an object's
## own panel, a VMU's on the card's Games tab.
const NOT_CARTRIDGE_SYSTEMS: Array[String] = [VmuCard.LIBRARY_SYSTEMID]

var core_db: CoreInfoDatabase = null
var core_defaults: CoreDefaults = null
var gamelist_manager: GamelistManager = null
var scraper_client: ScreenscraperClient = null
var scraper_config: ScraperConfig = null
## Every scrape goes through the menu's queue; this view only asks and listens.
var scrape_queue: ScrapeQueue = null
var romm_config: RommConfig = null
var romm_client: RommClient = null
var romm_catalog: RommCatalog = null
var romm_downloader: RommDownloader = null
var romm_cache: RommCacheManifest = null
var romm_art: RommArtCache = null
## The same treatment for ScreenScraper art. Built here rather than injected:
## it needs no config, unlike romm_art which needs the server URL.
var scraped_art: ScrapedArtCache = null

## The menu, for raising notices. Typed Node so the classes do not name each
## other — same reason as SpawnMenuOptionsView.
var _menu: Node = null

## Mirrors _active_scroll on the menu; assigning it emits scroll_changed, so the
## many places below that just set it keep reading the way they did.
var _active_scroll: ScrollContainer = null:
	set(value):
		_active_scroll = value
		scroll_changed.emit(value)

# ── RomM state ────────────────────────────────────────────────────────────────
## systemid -> platform dict from /api/platforms (with "systemid" added).
var _romm_platforms: Dictionary = {}
var _romm_unmapped: Array = []
## Slug signature of the last unmapped set announced, so it is reported once.
var _romm_unmapped_announced: String = ""
## Merged local+server row model for the open Cartridges detail page.
## Each entry: {source: "local"|"server"|"both", entry: Dictionary, path, label}
var _romm_rows: Array[Dictionary] = []
var _romm_detail_systemid: String = ""
var _romm_detail_exts: Array[String] = []
var _romm_filter: String = ""
## "all" | "downloaded" | "on_disk" | "server" | "local", and a region name or "" for any.
var _romm_source_filter: String = "all"
var _romm_region_filter: String = ""
var _romm_region_drop: VRDropdown = null
var _romm_region_options: Array[String] = []
var _romm_list: VirtualRowList = null
var _romm_empty_label: Label = null
## The toolbar's RETRY button, which doubles as this platform's stop button
## while it is the one syncing.
var _romm_resync_btn: Button = null
## local_path -> {game, manual_path, has_manual}; binding hits the disk otherwise.
var _romm_meta_cache: Dictionary = {}
## Row index whose delete button is armed for its second confirming tap.
var _romm_delete_armed: int = -1
## Path of the poster / video / DVD / album whose delete button is armed. A path,
## not a row index: these tabs are rebuilt from a fresh scan, and the three music
## tabs list the same albums.
var _media_delete_armed: String = ""
var _media_delete_armed_btn: Button = null
## Bumped on every arm and every commit, so a stale 3 s timer can tell it is stale.
var _media_delete_serial: int = 0
## Typing is bursty; one rebuild after the keys stop instead of one per key.
var _romm_search_timer: Timer = null
## Global game search (GameSearch): the query, the systems it covers, the worker
## running it and the page it fills. Results are re-checked against `_gs_query`
## when they land, so a slow search for an old query never overwrites a new one.
var _gs_query: String = ""
var _gs_systems: Array[Dictionary] = []
var _gs_task: int = -1
var _gs_dirty: bool = false
var _gs_timer: Timer = null
var _gs_local: Dictionary = {}
var _gs_server_rows: Array[Dictionary] = []
var _gs_server_term: String = ""
var _gs_searching: bool = false
var _gs_home_edit: LineEdit = null
var _gs_status: Label = null
var _gs_list: VBoxContainer = null
## Poster thumbnails, memoized with misses — most entries have no thumbnail.
var _poster_thumb_cache: Dictionary = {}
var _poster_thumb_order: Array[String] = []
## systemid -> {lowercase basename: rom}. A directory listing, so it is cached
## and dropped whenever something writes to a ROM dir.
var _local_scan_cache: Dictionary = {}
## systemid -> games in its ROM folders, for the corner of a tile the RomM badge
## does not cover. Counted on a worker (_request_local_counts) and kept until
## something writes to that folder.
var _local_counts: Dictionary = {}
## The WorkerThreadPool task counting now, or -1.
var _local_count_task: int = -1
## Systemids asked for while a count was running; counted once it lands.
var _local_count_pending: Dictionary = {}

# ── Tabs ──────────────────────────────────────────────────────────────────────
## Per-tab ScrollContainers, indexed by tab index. Systems and Cartridges own
## their own scroll inside a SystemGridBrowser, so their slot is null.
var _spawn_tab_scrolls: Array[ScrollContainer] = []
var _spawn_tabs: TabContainer = null
var _systems_browser: SystemGridBrowser = null
var _cartridges_browser: SystemGridBrowser = null
## Held because its tail is one row per connected gamepad, rebuilt whenever a pad
## is paired or unpaired.
var _controllers_vbox: VBoxContainer = null
var _power_vbox: VBoxContainer
var _books_vbox: VBoxContainer = null
## The TVs tab's rows. Kept so a mod applied mid-session can add its cabinets.
var _tvs_vbox: VBoxContainer = null
var _videos_vbox: VBoxContainer = null
var _dvds_vbox: VBoxContainer = null
var _cds_vbox: VBoxContainer = null
var _tapes_vbox: VBoxContainer = null
var _records_vbox: VBoxContainer = null
var _posters_vbox: VBoxContainer = null

# ── Scraper / detail panels ───────────────────────────────────────────────────
## The scrape queue's outcomes and the review popup, and the RomM handlers. Built
## with the view (not in create) so a view made with new() has them too.
var _scrape_ui := SpawnScrapeUi.new(self)
var _romm_sync := RommSpawnSync.new(self)
var _game_detail_panel: PanelContainer = null
# The hold sub-menu: what to spawn an entry AS. One at a time.
var _spawn_options_panel: PanelContainer = null
var _rom_variants_panel: PanelContainer = null
## The saves-and-achievements page for one ROM, and the CartridgeOptionsPanel
## driving it — both live only as long as the page is open.
var _game_saves_panel: PanelContainer = null
var _game_saves_driver: CartridgeOptionsPanel = null
var _pack_contents_panel: PanelContainer = null

## Driven by the menu, which hears it from the controller — this Control is
## always visible, it is the Viewport2Din3D in the world that gets toggled.
var _menu_shown: bool = false

## Rebuilds owed to the menu, run once at the end of the frame that asked for
## them, and only while the menu is out; put away, they wait for on_menu_shown.
##
## A finished download reached _rebuild_romm_rows twice in one frame (the cache
## manifest's `changed`, then the downloader's `finished`). A core serving six
## systems reported each of them, and every report rebuilt both grids and the
## open page: 560 ms of one frame on a Quest 3. And all of it ran with the menu
## put away too, because _romm_detail_systemid outlives the page it names.
var _owe_systems := false
var _owe_cartridges := false
var _owe_romm_rows := false
var _owed_flush_queued := false
## Whether the owed Cartridges refresh must also re-run the open system's page:
## for a scrape that changed what its rows show, or a core change for THAT system.
## Re-running it rebuilds the whole ROM list -- 117 ms of a Quest 3 frame for a
## 3k-row platform -- and a core for some other system changes nothing on it.
var _owe_detail := false
var _owe_core_sids: Dictionary = {}

## Art that landed this frame, applied once at its end: RomM rom ids, and the
## file stems scraped art is named after. See _flush_landed_art.
var _art_landed_ids: Dictionary = {}
var _art_landed_stems: Dictionary = {}
var _art_flush_queued := false
var _cover_prune_timer: SceneTreeTimer = null

static func create(menu: Node) -> SpawnMenuSpawnView:
	var v := SpawnMenuSpawnView.new()
	v._menu = menu
	v.core_db          = menu.core_db
	v.core_defaults    = menu.core_defaults
	v.gamelist_manager = menu.gamelist_manager
	v.scraper_client   = menu.scraper_client
	v.scraper_config   = menu.scraper_config
	v.scrape_queue     = menu.scrape_queue
	v.romm_config      = menu.romm_config
	v.romm_client      = menu.romm_client
	v.romm_catalog     = menu.romm_catalog
	v.romm_downloader  = menu.romm_downloader
	v.romm_cache       = menu.romm_cache
	v.romm_art         = menu.romm_art
	v.scraped_art      = menu.scraped_art
	v._connect_romm()
	v._build()
	v.visibility_changed.connect(v._on_visibility_changed)
	return v


## The RomM services are the menu's, but every one of these handlers ends by
## rebuilding a row, a list or an index in this view — so the wiring lives here,
## and the handlers in RommSpawnSync and SpawnScrapeUi, which answer to it.
func _connect_romm() -> void:
	_romm_sync.connect_services()
	# The warm thread works out a platform's shown count after the grid is
	# already up, so the tile it belongs to has to be redrawn. Once however many
	# platforms it finishes in a frame.
	romm_catalog.index_stats_ready.connect(func(_sid: String) -> void:
		_owe(false, true, false)
	)
	romm_art.art_ready.connect(_on_romm_art_ready)
	if scraped_art != null:
		scraped_art.art_ready.connect(_on_scraped_art_ready)
	if scrape_queue != null:
		scrape_queue.started.connect(_on_scrape_row_changed)
		_scrape_ui.connect_queue(scrape_queue)
	# Show last run's platforms immediately; a refresh only corrects it.
	for sid: String in romm_config.cached_platforms:
		var p: Variant = romm_config.cached_platforms[sid]
		if p is Dictionary:
			_romm_platforms[sid] = p


## Whether the RomM library is switched on at all. Everything the grid, a system's
## page and the search draw from the server -- the cached platform list and the
## synced indexes on disk -- outlives the switch, so each of those asks this first:
## turned off, a library that WAS enabled kept its isotipo and counts on every tile.
## Not is_configured(): a basic-auth library is enabled with no password after a
## restart, and its last run's platforms are meant to show.
func _romm_shown() -> bool:
	return romm_config != null and romm_config.enabled and not romm_config.base_url.is_empty()


## The switch in OPTIONS moved. On, the platforms are fetched (which repaints the
## grid if they changed); either way the grid and an open page are owed a
## repaint, paid when this tab is next on screen.
func romm_enabled_changed() -> void:
	print("[RommSync] library %s" % ("enabled" if _romm_shown() else "disabled; hiding server tiles and rows"))
	if _romm_shown():
		romm_fetch_platforms()
	_owe(false, true, true)


## Read by the OPTIONS tab, which shows what the server holds.
func romm_platforms() -> Dictionary:
	return _romm_platforms


func romm_unmapped() -> Array:
	return _romm_unmapped


## The scroll the visible sub-tab owns, re-reported after a tab switch.
func refresh_active_scroll() -> void:
	_update_spawn_active_scroll(_spawn_tabs.current_tab if _spawn_tabs else 0)


func notify(key: String, icon: String, msg: String,
			progress: float = -1.0, seconds: float = 0.0) -> void:
	if _menu:
		_menu.notify(key, icon, msg, progress, seconds)


func notify_clear(key: String) -> void:
	if _menu:
		_menu.notify_clear(key)


func show_notice(msg: String, seconds := 2.5) -> void:
	if _menu:
		_menu.show_notice(msg, seconds)


func _show_scrape_status(msg: String) -> void:
	if _menu:
		_menu.show_scrape_status(msg)


func _hide_scrape_status() -> void:
	if _menu:
		_menu.hide_scrape_status()

## Systems and Cartridges are SystemGridBrowsers that own their own scroll, and
## their slot in _spawn_tab_scrolls is null; every other tab is a plain
## ScrollContainer at the matching index. Keyed on title rather than position for
## the same reason the populate dispatch is.
func _update_spawn_active_scroll(tab_idx: int) -> void:
	var title := _spawn_tabs.get_tab_title(tab_idx) if _spawn_tabs != null \
		and tab_idx >= 0 and tab_idx < _spawn_tabs.get_tab_count() else ""
	if title == "Systems":
		_update_systems_inner_scroll()
	elif title == "Games":
		_update_cartridges_inner_scroll()
	elif tab_idx >= 0 and tab_idx < _spawn_tab_scrolls.size():
		_active_scroll = _spawn_tab_scrolls[tab_idx]
	else:
		_active_scroll = null


func _update_systems_inner_scroll() -> void:
	if _systems_browser:
		_active_scroll = _systems_browser.get_active_scroll()
	else:
		_active_scroll = null


func _update_cartridges_inner_scroll() -> void:
	if _cartridges_browser:
		_active_scroll = _cartridges_browser.get_active_scroll()
	else:
		_active_scroll = null



func _build() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_spawn_tabs = tabs
	_spawn_tab_scrolls.clear()

	# Systems tab — drill-down browser, one title card per system (like Cores).
	# Opening a system lists its spawnable items (console model(s) + peripherals).
	_systems_browser = SystemGridBrowser.new()
	_systems_browser.name = "Systems"
	_systems_browser.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_systems_browser.empty_text = "No default cores set.\nGo to Cores ▸ Manager to configure systems."
	_systems_browser.allow_hiding = true
	_systems_browser.allow_compact = true
	_systems_browser.set_detail_populator(_populate_systems_detail)
	# The hidden list and the compact switch both serve BOTH grids, so either one
	# changing has to repaint the other or the two disagree until you switch tabs
	# twice.
	_systems_browser.grid_prefs_changed.connect(func() -> void:
		if _cartridges_browser:
			_cartridges_browser.refresh()
	)
	_systems_browser.active_scroll_changed.connect(func(_s: ScrollContainer):
		_update_systems_inner_scroll()
	)
	tabs.add_child(_systems_browser)
	_spawn_tab_scrolls.append(null)  # index 0 handled via _update_systems_inner_scroll
	_populate_systems_tab()

	# Rebuild systems/cartridges lists whenever the user sets/changes a default
	default_core_changed.connect(func(sid: String, _cn: String): refresh_after_core_change(sid))

	# Cartridges tab — drill-down browser, one tile per system
	_cartridges_browser = SystemGridBrowser.new()
	_cartridges_browser.name = "Games"
	_cartridges_browser.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# These tiles stand for the media, not the machine, so show the cartridge.
	_cartridges_browser.use_content_art = true
	_cartridges_browser.empty_text = "No default cores set.\nGo to Cores ▸ Manager to configure systems."
	_cartridges_browser.allow_hiding = true
	_cartridges_browser.allow_compact = true
	_cartridges_browser.set_detail_populator(_populate_cartridges_detail)
	_cartridges_browser.grid_prefs_changed.connect(func() -> void:
		if _systems_browser:
			_systems_browser.refresh()
	)
	_cartridges_browser.active_scroll_changed.connect(func(_s: ScrollContainer):
		_update_cartridges_inner_scroll()
	)
	tabs.add_child(_cartridges_browser)
	_build_global_search_bar()
	# Its own browser owns the scroll, so this slot stays empty — see
	# _update_spawn_active_scroll.
	_spawn_tab_scrolls.append(null)
	_populate_cartridges_tab()

	_add_tv_spawn_tab(tabs)
	Mods.mods_applied.connect(_on_mods_applied)

	# Books tab — lists PDFs from the books root directory
	var books_scroll := ScrollContainer.new()
	books_scroll.name = "Books"
	tabs.add_child(books_scroll)
	_spawn_tab_scrolls.append(books_scroll)
	MenuStyle.fat_vscroll_bar(books_scroll)
	_books_vbox = VBoxContainer.new()
	_books_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_books_vbox.add_theme_constant_override("separation", 10)
	books_scroll.add_child(_books_vbox)
	_populate_books_tab()

	# Videos tab — lists video files from the videos root directory
	var videos_scroll := ScrollContainer.new()
	videos_scroll.name = "Videos"
	tabs.add_child(videos_scroll)
	_spawn_tab_scrolls.append(videos_scroll)
	MenuStyle.fat_vscroll_bar(videos_scroll)
	_videos_vbox = VBoxContainer.new()
	_videos_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_videos_vbox.add_theme_constant_override("separation", 10)
	videos_scroll.add_child(_videos_vbox)
	_populate_videos_tab()

	# DVDs tab — lists DVD images (VIDEO_TS folders / .iso / .img) from the dvd root
	var dvds_scroll := ScrollContainer.new()
	dvds_scroll.name = "DVDs"
	tabs.add_child(dvds_scroll)
	_spawn_tab_scrolls.append(dvds_scroll)
	MenuStyle.fat_vscroll_bar(dvds_scroll)
	_dvds_vbox = VBoxContainer.new()
	_dvds_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dvds_vbox.add_theme_constant_override("separation", 10)
	dvds_scroll.add_child(_dvds_vbox)
	_populate_dvds_tab()

	# CDs tab — lists music albums (folders of audio files / loose files) from the
	# music root; each spawns an AudioDisc for the CD player.
	var cds_scroll := ScrollContainer.new()
	cds_scroll.name = "CDs"
	tabs.add_child(cds_scroll)
	_spawn_tab_scrolls.append(cds_scroll)
	MenuStyle.fat_vscroll_bar(cds_scroll)
	_cds_vbox = VBoxContainer.new()
	_cds_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cds_vbox.add_theme_constant_override("separation", 10)
	cds_scroll.add_child(_cds_vbox)
	_populate_cds_tab()

	# Tapes tab — same music library, each spawns an AudioCassette for the deck.
	var tapes_scroll := ScrollContainer.new()
	tapes_scroll.name = "Tapes"
	tabs.add_child(tapes_scroll)
	_spawn_tab_scrolls.append(tapes_scroll)
	MenuStyle.fat_vscroll_bar(tapes_scroll)
	_tapes_vbox = VBoxContainer.new()
	_tapes_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tapes_vbox.add_theme_constant_override("separation", 10)
	tapes_scroll.add_child(_tapes_vbox)
	_populate_tapes_tab()

	# Records tab — the same music library again, each row spawning a VinylRecord
	# for the turntable.
	var records_scroll := ScrollContainer.new()
	records_scroll.name = "Records"
	tabs.add_child(records_scroll)
	_spawn_tab_scrolls.append(records_scroll)
	MenuStyle.fat_vscroll_bar(records_scroll)
	_records_vbox = VBoxContainer.new()
	_records_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_records_vbox.add_theme_constant_override("separation", 10)
	records_scroll.add_child(_records_vbox)
	_populate_records_tab()

	# Posters tab — lists images from the posters root directory
	var posters_scroll := ScrollContainer.new()
	posters_scroll.name = "Posters"
	tabs.add_child(posters_scroll)
	_spawn_tab_scrolls.append(posters_scroll)
	MenuStyle.fat_vscroll_bar(posters_scroll)
	_posters_vbox = VBoxContainer.new()
	_posters_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_posters_vbox.add_theme_constant_override("separation", 10)
	posters_scroll.add_child(_posters_vbox)
	_populate_posters_tab()

	# The shipped objects, then every prop a mod registered with a menu label: both
	# SpawnCatalog's, as a console card's rows are (items_for).
	_add_spawn_tab(tabs, "Objects", SpawnCatalog.objects())

	# Mains leads, on their own tab rather than lost among the A/V ones. What
	# picks one is the shape of the socket on the back of the machine, not what
	# the machine is for, and a player hunting the right plug should not have to
	# read past the record player to find it.
	_power_vbox = _add_spawn_tab(tabs, "Power", _power_items())

	# Rebuilt at runtime, unlike the other const tabs: its tail is one row per
	# physical gamepad currently connected, which nothing knows at build time.
	_controllers_vbox = _add_spawn_tab(tabs, "Controllers", [])
	_populate_controllers_tab()
	# A pad plugged in or unplugged changes the list while the menu is open.
	Input.joy_connection_changed.connect(
		func(_device: int, _connected: bool) -> void: _populate_controllers_tab())

	# Refresh on tab switch — picks up files added to disk since last open
	# Also update _active_scroll to the current tab's ScrollContainer
	# Dispatched on the tab's title, not its index. These were index compares, and
	# reordering two tabs then meant finding every hardcoded position — four of
	# them, spread over three functions — with nothing to catch a miss but the
	# wrong list quietly refreshing.
	tabs.tab_changed.connect(func(idx: int):
		match tabs.get_tab_title(idx):
			"Systems": _populate_systems_tab()
			"Games": _populate_cartridges_tab()
			"Books": _populate_books_tab()
			"Videos": _populate_videos_tab()
			"DVDs": _populate_dvds_tab()
			"CDs": _populate_cds_tab()
			"Tapes": _populate_tapes_tab()
			"Records": _populate_records_tab()
			"Posters": _populate_posters_tab()
		_update_spawn_active_scroll(idx)
	)

	# The strip and the TabContainer come back in one VBox; it fills this view,
	# which is anchored over the whole content area.
	var wrapped := TabStrip.wrap(tabs)
	wrapped.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(wrapped)


func _clear_vbox(vbox: VBoxContainer) -> void:
	for child in vbox.get_children():
		child.queue_free()
	vbox.add_child(MenuStyle.spacer(10))


## A system gained (or changed) its default core, so both grids keyed off
## CoreDefaults have a tile to add or relabel. The one entry point for that,
## called from this view's own default_core_changed AND by SpawnMenu when the
## Cores view reports a download — the two grids must never refresh
## independently again, which is how Cartridges came to update while Systems
## silently did not.
##
## Owed rather than run: a core that serves several systems reports each one in
## the same frame, and the grids need rebuilding once.
func refresh_after_core_change(systemid: String = "") -> void:
	if systemid.is_empty():
		_owe_detail = true
	else:
		_owe_core_sids[systemid] = true
	_owe(true, true, false)


func _owe(systems: bool, cartridges: bool, romm_rows: bool) -> void:
	_owe_systems = _owe_systems or systems
	_owe_cartridges = _owe_cartridges or cartridges
	_owe_romm_rows = _owe_romm_rows or romm_rows
	if _can_pay() and not _owed_flush_queued:
		_owed_flush_queued = true
		_flush_owed.call_deferred()


## Out in the world AND the tab on screen. A core finishes installing while the
## player is on the CORES tab, and this view's two grids and open page are ~90 ms
## of a desktop frame that nobody could see.
func _can_pay() -> bool:
	return _menu_shown and is_visible_in_tree()


## Switching back to this tab settles what it owes before it is drawn.
func _on_visibility_changed() -> void:
	if _can_pay():
		_flush_owed()


func _flush_owed() -> void:
	_owed_flush_queued = false
	if not _can_pay():
		return
	var systems := _owe_systems
	var cartridges := _owe_cartridges
	var rows := _owe_romm_rows
	var shown_sid := _cartridges_browser.current_systemid() if _cartridges_browser != null else ""
	var detail := _owe_detail or _owe_core_sids.has(shown_sid)
	_owe_systems = false
	_owe_cartridges = false
	_owe_romm_rows = false
	_owe_detail = false
	_owe_core_sids.clear()
	if systems:
		_populate_systems_tab()
	if cartridges:
		_populate_cartridges_tab(detail)
	# Only for a page that is open: opening one builds its rows from scratch, so
	# a list nobody is looking at has nothing to catch up on. And a Cartridges
	# refresh that re-ran the open page has rebuilt its rows already.
	var open := _cartridges_browser != null and shown_sid == _romm_detail_systemid
	if rows and open and not (cartridges and detail):
		_rebuild_romm_rows()


## Rebuild the Systems home grid: one tile per system that has a default core.
## Spawnable items are listed lazily, only when a system tile is opened.
## Systemids that earn a tile from something other than a persisted default core.
##
## A tile normally exists because the Cores panel wrote a default for it, which
## for the e-Reader happens the moment mGBA is installed — it is one of mGBA's
## secondary_systemids. This is the safeguard for the case where it did not: a
## reader dump on the shelf is a machine the player owns, and it should have its
## shelf whether or not core_defaults happens to name it.
##
## Reads AdapterRoms' cached probe, so it is one directory scan per session at
## worst and nothing at all on a machine with no dump.
func _extra_systemids(seen: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for id: String in ["ereader"]:
		if seen.has(id):
			continue
		if not ExpansionCatalog.firmware_rom_path(id).is_empty():
			out.append(id)
			seen[id] = true
	# And every platform an INSTALLED core serves, for exactly the same reason.
	#
	# On a settled install this adds nothing: the Cores panel adopts a default the
	# first time it lists a core, so all_defaults() already names everything. What
	# it catches is a platform that appeared since that page was last opened —
	# `famicom` was one. fceumm had been installed here for months and only began
	# declaring famicom when the Famicom shipped, so the machine existed, its core
	# was present, and it had no tile at all until the player happened to visit
	# Cores. A platform you can play should not be waiting on a page visit.
	for core_name: String in _installed_core_names():
		var info: Dictionary = core_db.get_by_core_name(core_name) if core_db != null else {}
		if info.is_empty():
			continue
		for id: String in CoreInfoDatabase.systemids_of(info):
			# "unknown" is what a core with no systemid at all is filed under; it
			# names no machine and would open on an empty shelf.
			if id.is_empty() or id == "unknown" or seen.has(id):
				continue
			out.append(id)
			seen[id] = true
	return out


## The core_name of every library in the cores directory — the same sweep the
## Cores panel makes to build its own list, and the same cost.
func _installed_core_names() -> Array[String]:
	var names: Array[String] = []
	var dir := DirAccess.open(CoreDownloadManager.default_cores_dir())
	if dir == null:
		return names
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		var cn := "" if dir.current_is_dir() \
			else CoreDownloadManager.core_name_from_lib_filename(fname)
		if not cn.is_empty() and not (cn in names):
			names.append(cn)
		fname = dir.get_next()
	dir.list_dir_end()
	return names


func _populate_systems_tab() -> void:
	if not _systems_browser:
		return
	var systems: Array = []
	var seen: Dictionary = {}
	var ids: Array[String] = []
	for systemid: String in core_defaults.all_defaults():
		ids.append(systemid)
		seen[systemid] = true
	ids.append_array(_extra_systemids(seen))
	for systemid: String in ids:
		var sysname: String = core_db.get_systemname_for_id(systemid)
		var entry := {"systemid": systemid, "name": sysname}
		var n := SpawnCatalog.items_for(systemid).size()
		if n > 1:
			entry["badge"] = "%d items" % n
		systems.append(entry)
	_systems_browser.set_systems(systems)
	# If a system detail is open, re-run it so catalog changes appear. Detail
	# only: set_systems has just built the tiles, and refresh() built them again.
	_systems_browser.refresh_detail()


## Detail page for one system: each spawnable item — the console model(s) plus
## that system's controllers/peripherals. Tap to spawn; the menu stays open so
## several items can be spawned in a row.
func _populate_systems_detail(systemid: String, vbox: VBoxContainer) -> void:
	vbox.add_child(MenuStyle.spacer(4))
	for item: Dictionary in SpawnCatalog.items_for(systemid):
		var btn := Button.new()
		btn.text = "  +  " + str(item.get("label", "Console"))
		# Only set where a card has more than one console to choose between.
		if bool(item.get("default", false)):
			btn.text += "      default"
		btn.custom_minimum_size = Vector2(0, 80)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 26)
		var token := SpawnCatalog.spawn_token(systemid, item)
		# A shelf is only offered for a console that actually takes cards — one
		# with no card_family gets the plain row, because browsing another
		# console's cards from it would be a lie about what it can hold.
		var card_fmt := CardFormats.for_system(systemid)
		# The N64's Controller Pak gets the same shelf. for_system cannot find it:
		# it plugs into a CONTROLLER, so nintendo_64 declares no card_family on
		# purpose — that field drives the console's own slots and would divert the
		# cartridge save. Resolved by family instead.
		if token == "controller_pak":
			card_fmt = CardFormats.for_family(ControllerPak.FAMILY)
		# And the Dreamcast's VMU, for exactly the same reason.
		elif token == "vmu":
			card_fmt = CardFormats.for_family(VmuCard.FAMILY)
		# And the Xbox's Memory Unit, which goes in a controller as well.
		elif token == "xbox_mu":
			card_fmt = CardFormats.for_family(XboxMuCard.FAMILY)
		# And a cartridge that is memory -- the Sega CD's Backup RAM Cartridge --
		# resolved from the unit its row names.
		var cart_memory := memory_cart_family(token)
		if not cart_memory.is_empty():
			card_fmt = CardFormats.for_family(cart_memory)
		if (token.ends_with("memory_card") or token == "controller_pak"
				or token == "vmu" or token == "xbox_mu"
				or not cart_memory.is_empty()) and card_fmt != null:
			# This row does one of two different things, so it says which. With
			# cards saved it opens the shelf and drops the +, because every other
			# + on this page puts something in the room on the first press.
			var cards := MemoryCardBrowser.card_count(card_fmt.id())
			if cards > 0:
				btn.text = "     %s      %d card%s" \
					% [str(item.get("label", "Memory Card")), cards, "" if cards == 1 else "s"]
			var card_colors: Array = item.get("variants", [])
			if card_colors.is_empty():
				btn.pressed.connect(
					_on_system_memcard_pressed.bind(systemid, card_fmt.id(), vbox))
			else:
				# A card that comes in colors (a mod offered them on this card's row).
				# Pressed, it does what a card row does, a new card in the row's
				# default color; held, it asks which color for a new card.
				var family := card_fmt.id()
				var card_hold := HoldPress.attach(btn)
				card_hold.clicked.connect(func() -> void:
					_on_system_memcard_pressed(systemid, family, vbox,
						_row_default(_default_key(systemid, token), card_colors)))
				card_hold.held.connect(
					_show_model_spawn_options.bind(systemid, item, "%s_memory_card" % family))
				_mark_holdable(btn, _default_key(systemid, token), card_colors)
		elif not (item.get("variants", []) as Array).is_empty():
			# A console that comes in several colors. Pressed, it spawns as its
			# row has it; held for a second, it asks which, as a ROM's row asks
			# for a cartridge's shell.
			# Pressed, it spawns the color its held panel made its default.
			var colors: Array = item.get("variants", [])
			var hold := HoldPress.attach(btn)
			hold.clicked.connect(func() -> void:
				spawn_requested.emit(SpawnCatalog.spawn_token(systemid, item,
					_row_default(_default_key(systemid, token), colors))))
			hold.held.connect(_show_model_spawn_options.bind(systemid, item))
			_mark_holdable(btn, _default_key(systemid, token), colors)
		else:
			btn.pressed.connect(spawn_requested.emit.bind(token))
		# A unit whose firmware is not installed still spawns; the row says what
		# power-on will ask for, small and red under its name.
		var missing := str(item.get("missing", ""))
		if not missing.is_empty():
			btn.custom_minimum_size.y = 100
			# A second, empty line lifts the name clear of the note.
			btn.text += "\n"
			var note := Label.new()
			note.text = missing
			note.add_theme_font_size_override("font_size", 17)
			note.add_theme_color_override("font_color", MenuIcons.TINT_DELETE)
			note.mouse_filter = Control.MOUSE_FILTER_IGNORE
			note.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			note.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
			note.offset_left = 62
			note.offset_right = -16
			note.offset_top = -34
			note.offset_bottom = -8
			btn.add_child(note)
		vbox.add_child(btn)
	vbox.add_child(MenuStyle.spacer(8))


## What a plain press of a row with colors spawns: the color its held panel made
## the default, while the row still lists it; otherwise the variant sold in the
## player's region (a Japanese player's Saturn, 32X or pad is the Japanese one);
## otherwise the row as it comes. The first color listed IS as it comes, so it
## reads as "". The answer is a concrete variant, and that is what the spawned
## object saves, so a region change later never re-dresses it.
static func _row_default(row_token: String, variants: Array) -> String:
	var id := AppPrefs.spawn_default(row_token)
	if not id.is_empty():
		for i in variants.size():
			if str((variants[i] as Dictionary).get("id", "")) == id:
				return "" if i == 0 else id
	return RegionalNames.variant_for_region(variants)


## What MAKE DEFAULT stores for the variant a spawn asks for (`""` for the first,
## the row as it comes): the first is kept by its id, not as "" -- erased, it read
## as "never chosen", and the player's region then won over their own pick.
static func _kept_default(variant: String, variants: Array) -> String:
	if variant.is_empty() and not variants.is_empty():
		return str((variants[0] as Dictionary).get("id", ""))
	return variant


## Where a row's default is kept: by card and row, since rows on different cards
## can share a token and still come in different colors (each console's
## "Memory Card" row spawns its own family's card).
static func _default_key(systemid: String, row_token: String) -> String:
	return "%s|%s" % [systemid, row_token]


## A token asking for `token`'s thing in `variant`, or `token` as it is.
static func _in_color(token: String, variant: String) -> String:
	return token if variant.is_empty() else "%s%s:%s" % [SpawnCatalog.AS, variant, token]


## The mark of a row that can be held: at its right end, a swatch of the color a
## plain press spawns, so a row with colors says so before it is held and says
## which one it will give.
func _mark_holdable(btn: Button, row_token: String, variants: Array) -> void:
	var id := _row_default(row_token, variants)
	var shown: Dictionary = variants[0]
	for variant: Dictionary in variants:
		if str(variant.get("id", "")) == id:
			shown = variant
	btn.icon = _hold_icon(SystemModelRegistry.variant_color(shown))
	btn.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	btn.tooltip_text = "%s. Hold to choose another." % str(shown.get("label", ""))


## Swatches drawn so far, by color: a page of rows asks for the same few.
static var _hold_icons: Dictionary = {}


## A round swatch of `color` in a light ring, 34 px across, its edge eased.
static func _hold_icon(color: Color) -> Texture2D:
	var key := color.to_html()
	if _hold_icons.has(key):
		return _hold_icons[key]
	const SIZE := 34
	var img := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	var mid := (SIZE - 1) * 0.5
	var ring := Color(0.92, 0.94, 1.0)
	for y in SIZE:
		for x in SIZE:
			var d := Vector2(x - mid, y - mid).length()
			var fill := ring if d > mid - 4.0 else Color(color, 1.0)
			fill.a = clampf(mid + 0.5 - d, 0.0, 1.0)
			img.set_pixel(x, y, fill)
	var tex := ImageTexture.create_from_image(img)
	_hold_icons[key] = tex
	return tex


## The card family of a spawn token naming a unit that is only memory -- a Backup
## RAM Cartridge, with no bay of its own -- or "".
static func memory_cart_family(token: String) -> String:
	if not token.begins_with("expansion:"):
		return ""
	var id := token.substr("expansion:".length())
	if not ExpansionCatalog.has(id) or not ExpansionCatalog.media_of(id).is_empty():
		return ""
	return ExpansionCatalog.memory_of(id)


## A console's card shelf, opened from its own page. It takes that page over, so
## Back returns to the console you came from.
##
## Nothing saved yet means there is nothing to choose between, so the row keeps
## its plain behaviour and spawns a blank card.
##
## `variant` is the color a new blank card is spawned in (its row's default),
## "" for as it comes.
func _on_system_memcard_pressed(systemid: String, family: String,
		vbox: VBoxContainer, variant: String = "") -> void:
	if not MemoryCardBrowser.has_cards(family):
		spawn_requested.emit(_in_color("%s_memory_card" % family, variant))
		return
	_clear_children(vbox)
	var b := MemoryCardBrowser.new()
	b.family = family
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_constant_override("separation", 10)
	# Deferred: both handlers tear down the browser that is emitting them.
	b.spawn_requested.connect(func(t: String) -> void:
		spawn_requested.emit(t)
		_restore_system_detail.call_deferred(systemid, vbox))
	b.closed.connect(func() -> void:
		_restore_system_detail.call_deferred(systemid, vbox))
	b.notice.connect(show_notice)
	# One Back button for the whole trail: the shelf's pages announce themselves
	# to the console page's header rather than stacking a second one under it.
	b.page_changed.connect(func(title: String, on_back: Callable) -> void:
		if _systems_browser != null:
			_systems_browser.push_subpage(title, on_back))
	vbox.add_child(b)
	b.open()


func _restore_system_detail(systemid: String, vbox: VBoxContainer) -> void:
	if _systems_browser != null:
		_systems_browser.clear_subpage()
	_clear_children(vbox)
	_populate_systems_detail(systemid, vbox)


func _clear_children(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


## Rebuild the Cartridges home grid: one tile per system that has a default core
## OR a mapped RomM platform. ROMs are scanned/synced lazily, only when a system
## tile is opened — a full library sync at launch would be minutes of transfer
## before the user could do anything.
func _populate_cartridges_tab(rerun_detail: bool = true) -> void:
	if not _cartridges_browser:
		return

	var seen: Dictionary = {}
	for systemid: String in NOT_CARTRIDGE_SYSTEMS:
		seen[systemid] = true
	var systems: Array = []
	for systemid: String in core_defaults.all_defaults():
		if seen.has(systemid):
			continue
		seen[systemid] = true
		systems.append({"systemid": systemid, "name": core_db.get_systemname_for_id(systemid)})

	for systemid: String in _extra_systemids(seen):
		systems.append({"systemid": systemid, "name": _system_label(systemid)})

	var romm_on := _romm_shown()
	if romm_on:
		for systemid: String in _romm_platforms:
			if not seen.has(systemid):
				systems.append({"systemid": systemid, "name": _system_label(systemid)})

	# Mark tiles backed by the server with the RomM isotipo and its ROM count.
	#
	# The server's own rom_count counts every row it holds, saves kept beside
	# their games included. Once a platform is synced its index knows what the
	# list will show, so that wins; the server count is the fallback for a
	# platform never synced, where a number that is too big still beats no
	# number at all.
	var mark: Texture2D = MenuIcons.romm_mark()
	for s: Dictionary in systems:
		var sid: String = s["systemid"]
		var remote := 0
		if romm_on and _romm_platforms.has(sid):
			remote = int((_romm_platforms[sid] as Dictionary).get("rom_count", 0))
		var shown := RommCatalog.shown_count(sid) if romm_on else -1
		if shown >= 0:
			remote = shown
		if remote > 0 and mark != null:
			s["badge_icon"] = mark
			s["badge_count"] = remote
			# What is already on this device, shown as the left half of the pair.
			#
			# From the cache manifest rather than the ROM folder: it is an
			# in-memory walk with no disk I/O, and this runs once per platform on
			# every repopulate — _local_by_name() would mean a synchronous
			# directory scan per tile, and it counts gamelist.json and other
			# sidecars that the detail list filters out again later.
			#
			# So the number means "downloaded from this server", not "files in the
			# folder": a ROM copied in by hand is not counted. That is the reading
			# the RomM mark above it promises.
			if romm_cache != null:
				s["badge_here"] = romm_cache.rom_ids_for_system(sid).size()
		elif int(_local_counts.get(sid, 0)) > 0:
			# No server count to pair with — RomM not set up, or this platform is
			# not on it — so the corner says what is on this device on its own.
			s["badge_local"] = int(_local_counts[sid])

	# Systems not counted yet are counted off the frame; the tiles redraw when
	# the numbers land.
	var uncounted: Array[String] = []
	for s: Dictionary in systems:
		if not _local_counts.has(str(s["systemid"])):
			uncounted.append(str(s["systemid"]))
	_request_local_counts(uncounted)

	# One directory scan, shared by both passes.
	var by_system := FirmwareRequirements.installed_cores_by_system()
	_mark_systems_without_a_core(systems, by_system)
	_mark_netplay_systems(systems, by_system)

	# Each tile also answers to its folder names and RomM slugs ("gba"), and the
	# global search covers the same list.
	_gs_systems.clear()
	for s: Dictionary in systems:
		var sid: String = s["systemid"]
		s["aliases"] = GameSearch.system_aliases(sid, _romm_platforms.get(sid, {}))
		_gs_systems.append({"systemid": sid, "name": str(s["name"])})

	_cartridges_browser.set_systems(systems)
	# If a system detail is open, re-run it so newly-added ROMs appear. Detail
	# only: set_systems has just rebuilt the tiles, and refresh() would build all
	# 68 of them again for nothing. Not when the caller knows the page is
	# unaffected (_flush_owed).
	if rerun_detail:
		_cartridges_browser.refresh_detail()

	# Pull the largest synced platforms' sidecars into the file cache while the
	# user is still looking at the grid. Opening one is disk-bound the first
	# time — 25-37 ms on desktop, considerably worse on Quest storage — and this
	# spends that on a worker thread before the tap rather than during it.
	_prewarm_top_platforms(systems)


## Purple a platform you cannot actually play yet, the same plate the Cores tab's
## Download grid uses for a system with nothing installed. The two grids answer
## the same question from opposite ends — one lists what you could install, the
## other what you could load — so a platform that is purple in one and plain in
## the other would be reading the same library two different ways.
##
## A platform counts as covered when any installed core is filed under it, or when
## the core it would actually boot is installed. Both, because a core often serves
## a platform it is not filed under: the default is what a cartridge here launches.
func _mark_systems_without_a_core(systems: Array, by_system: Dictionary) -> void:
	var installed_names: Dictionary = {}
	for sid: String in by_system:
		for e: Dictionary in (by_system[sid] as Array):
			installed_names[str(e.get("core_name", ""))] = true

	for s: Dictionary in systems:
		var sid: String = str(s.get("systemid", ""))
		var covered: bool = by_system.has(sid) and not (by_system[sid] as Array).is_empty()
		if not covered and core_defaults != null:
			var dflt := core_defaults.get_default_core(sid)
			covered = not dflt.is_empty() and installed_names.has(dflt)
		s["alt_tile"] = not covered


## The netplay mark, in the tile's top-right corner: an installed core for this
## system is vetted for online play, tinted by the strongest strategy any of them
## offers. Takes the installed map rather than fetching it, so the directory scan
## behind it runs once for the whole grid instead of once per tile.
##
## Installed, not merely known: the mark says what this device can do now, which
## is the question a cartridge tile is answering.
##
## by_system files a core under its primary systemid only, so the platforms it
## serves through `secondary_systemids` are walked here too -- the Sufami Turbo
## runs on snes9x, filed under `snes`, and would otherwise never show the mark.
func _mark_netplay_systems(systems: Array, by_system: Dictionary) -> void:
	var db := CoreInfoDatabase.shared()
	var cores_by_sid: Dictionary = {}
	for key: String in by_system:
		for e: Dictionary in (by_system[key] as Array):
			var cn := str(e.get("core_name", ""))
			var sids: Array[String] = CoreInfoDatabase.systemids_of(db.get_by_core_name(cn))
			if key not in sids:
				sids.append(key)
			for sid: String in sids:
				if not cores_by_sid.has(sid):
					cores_by_sid[sid] = []
				(cores_by_sid[sid] as Array).append(cn)
	for s: Dictionary in systems:
		var sid: String = str(s.get("systemid", ""))
		var best := -1
		for cn: String in (cores_by_sid.get(sid, []) as Array):
			var strategy := NetplayCores.listed_strategy(cn)
			if strategy < 0:
				continue
			if best < 0 or NetplayCores.STRATEGY_ORDER.find(strategy) \
					< NetplayCores.STRATEGY_ORDER.find(best):
				best = strategy
		if best < 0:
			continue
		s["corner_glyph"] = String.chr(MenuIcons.NETPLAY)
		s["corner_glyph_color"] = MenuIcons.netplay_tint(best)
		s["corner_glyph_tip"] = "Online play: %s" % NetplaySession.strategy_str(best).capitalize()



## One /api/platforms call, cached. Local systems are already on screen by the
## time this returns — server platforms just merge in.
func romm_fetch_platforms() -> void:
	if romm_config == null or not romm_config.is_configured():
		return
	romm_client.platforms(func(ok: bool, platforms: Array) -> void:
		if not ok:
			return
		var part := RommPlatforms.partition(platforms, romm_config.platform_overrides)
		var collapsed := RommPlatforms.collapse_by_systemid(part["mapped"])
		_romm_platforms = collapsed["platforms"]
		# Shadowed platforms ride the unmapped channel: both are platforms with
		# ROMs that the grid will not show, and both are fixed by the same
		# platform_overrides entry.
		_romm_unmapped = part["unmapped"]
		_romm_unmapped.append_array(collapsed["shadowed"])

		# Only announce when the set actually changes. Most unmapped platforms
		# stay unmapped forever (no systemid or 3D model exists for them), so
		# re-reporting the same list on every menu open is pure noise.
		# Worded "not shown" from here down: the list also carries platforms that
		# mapped fine and then lost their systemid to a bigger library, and
		# calling those unmapped sends you hunting for a mapping that exists.
		var signature := ""
		for p: Dictionary in _romm_unmapped:
			signature += str(p.get("slug", "")) + ","
		if not _romm_unmapped.is_empty() and signature != _romm_unmapped_announced:
			notify("romm:map", "⚠", "%d RomM platform%s not shown — see OPTIONS"
				% [_romm_unmapped.size(), "" if _romm_unmapped.size() == 1 else "s"],
				-1.0, 4.0)
		_romm_unmapped_announced = signature

		# Rebuilding the tab means re-deriving every tile. The platform set
		# almost never changes between launches — it is already persisted and
		# used to draw the grid at startup — so only rebuild when it actually
		# moved. This ran on the same frame as a 70 KB JSON parse, which is
		# what made opening the menu hitch.
		var changed := _romm_platforms.size() != romm_config.cached_platforms.size()
		if not changed:
			for sid: String in _romm_platforms:
				if not romm_config.cached_platforms.has(sid):
					changed = true
					break
				var was: Dictionary = romm_config.cached_platforms[sid]
				if int(was.get("rom_count", -1)) != int((_romm_platforms[sid] as Dictionary).get("rom_count", -2)):
					changed = true
					break

		if changed:
			romm_config.cached_platforms = _romm_platforms.duplicate()
			romm_config.save_config()
			_populate_cartridges_tab()
		romm_state_changed.emit()
	)


## Detail page for one system: local ROMs and the RomM library, merged.
##
## Local files render immediately; the server list appears when its index is
## ready (syncing that platform in the background if it has never been synced).
## The rows go into a VirtualRowList, so a 100k-entry platform costs the same as
## a 12-entry one.
func _populate_cartridges_detail(systemid: String, vbox: VBoxContainer) -> void:
	if systemid == GameSearch.PAGE_ID:
		_populate_global_search(vbox)
		return
	RomLibrary.ensure_rom_dir(systemid)
	# A rebuild of the page you are already on is not a fresh open: clearing the
	# search here is what threw you back to row one of the whole library after
	# accepting a scrape, because the 12 rows you were looking at were a filtered
	# view and the restored scroll offset then indexed into all 2744.
	var keep_filters := _cartridges_browser.is_refreshing() and systemid == _romm_detail_systemid
	_romm_detail_systemid = systemid
	_romm_rows.clear()
	if not keep_filters:
		_romm_filter = ""
	# Opening a platform must see the disk as it is now, not as it was.
	_invalidate_local_scan(systemid)

	# Collect all supported extensions for this system across all its cores.
	#
	# Through CoreInfoDatabase rather than by walking get_by_systemid here: a
	# SECONDARY platform is indexed under its parent core's entry, whose own
	# extension list is the parent's. Walking it gave the e-Reader mGBA's
	# gba|gbc|gb, none of which a dotcode strip is, so every one of the 3217
	# cards on disk was filtered out of its own page and the platform looked
	# empty. extensions_for_systemid adds the secondary extensions the .info
	# declared, which is where "raw" lives.
	_romm_detail_exts = CoreInfoDatabase.extensions_for_systemid(systemid)

	# Search and filters live in the browser's pinned toolbar, not in the scroll
	# area — they must stay reachable however far down the list you are.
	var toolbar := _cartridges_browser.detail_toolbar()
	toolbar.visible = true

	# Local filter over the cached names: instant at 100k rows, works offline.
	var search := LineEdit.new()
	search.placeholder_text = "Search %s…" % _system_label(systemid)
	search.clear_button_enabled = true
	search.custom_minimum_size = Vector2(0, 52)
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.add_theme_font_size_override("font_size", 20)
	# Assigning text does not emit text_changed, so this cannot re-arm the
	# debounce timer — the rows below are already built from _romm_filter.
	search.text = _romm_filter
	search.text_changed.connect(_on_romm_search_changed)
	toolbar.add_child(search)

	var sep := VSeparator.new()
	sep.add_theme_constant_override("separation", 16)
	toolbar.add_child(sep)

	if not keep_filters:
		_romm_source_filter = "all"
		_romm_region_filter = ""
	# The options cache belongs to the widget, and this is a new one — a stale
	# cache matches, returns early, and leaves the fresh dropdown holding nothing
	# but "All regions".
	_romm_region_options = []

	var source_drop := VRDropdown.create("", [
		["All", "all"],
		["Downloaded", "downloaded"],
		["Downloaded + local", "on_disk"],
		["Not downloaded", "server"],
		["Local only", "local"],
	], _romm_source_filter, 1, Vector2(210, 52), 18)
	source_drop.size_flags_horizontal = Control.SIZE_SHRINK_END
	source_drop.float_panel = true
	source_drop.set_toggle_glyph(MenuIcons.FILTER, MenuIcons.symbols())
	source_drop.item_selected.connect(func(id: Variant) -> void:
		_romm_source_filter = str(id)
		_rebuild_romm_rows()
	)
	toolbar.add_child(source_drop)

	_romm_region_drop = VRDropdown.create("", [["All regions", ""]], _romm_region_filter,
		1, Vector2(210, 52), 18)
	_romm_region_drop.size_flags_horizontal = Control.SIZE_SHRINK_END
	_romm_region_drop.float_panel = true
	_romm_region_drop.set_toggle_glyph(MenuIcons.REGION, MenuIcons.symbols())
	_romm_region_drop.item_selected.connect(func(id: Variant) -> void:
		_romm_region_filter = str(id)
		_rebuild_romm_rows()
	)
	toolbar.add_child(_romm_region_drop)

	# A platform syncs on its first open and never again on its own, so without
	# this there is no way to pick up a game added to the server since.
	var resync := Button.new()
	resync.text = String.chr(MenuIcons.RETRY)
	resync.add_theme_font_override("font", MenuIcons.symbols())
	resync.add_theme_font_size_override("font_size", 22)
	resync.custom_minimum_size = Vector2(64, 52)
	resync.size_flags_horizontal = Control.SIZE_SHRINK_END
	resync.pressed.connect(_romm_sync.on_resync_pressed.bind(systemid))
	toolbar.add_child(resync)
	_romm_resync_btn = resync
	_romm_sync.update_resync_btn()

	var scrape_all := Button.new()
	scrape_all.text = String.chr(MenuIcons.SCRAPE_ALL)
	scrape_all.add_theme_font_override("font", MenuIcons.symbols())
	scrape_all.add_theme_font_size_override("font_size", 22)
	scrape_all.custom_minimum_size = Vector2(64, 52)
	scrape_all.size_flags_horizontal = Control.SIZE_SHRINK_END
	scrape_all.tooltip_text = "Scrape every game on this page that has not been scraped yet"
	scrape_all.pressed.connect(_scrape_ui.on_scrape_all_pressed.bind(systemid))
	toolbar.add_child(scrape_all)

	# A blank 8M Memory Pack is a thing you BUY, not a thing that exists: the
	# Satellaview downloads onto a pack and there is nowhere to put a programme
	# without one. Every other platform's media arrives as a dump, so this is the
	# one shelf that has to be able to mint a new medium — the way the memory-card
	# shelf does.
	if systemid == "satellaview":
		var new_pack := Button.new()
		new_pack.text = "  +  %s  New Memory Pack  " % String.chr(MenuIcons.BSX_MEMORY_PACK)
		# symbols() is the theme font with the glyph table BEHIND it, so the Latin
		# half of this label still renders; the Nerd Font on its own has no letters.
		new_pack.add_theme_font_override("font", MenuIcons.symbols())
		new_pack.add_theme_font_size_override("font_size", 18)
		new_pack.custom_minimum_size = Vector2(0, 52)
		new_pack.size_flags_horizontal = Control.SIZE_SHRINK_END
		new_pack.pressed.connect(_on_new_pack_pressed.bind(systemid))
		toolbar.add_child(new_pack)

	_romm_empty_label = Label.new()
	_romm_empty_label.add_theme_font_size_override("font_size", 18)
	_romm_empty_label.add_theme_color_override("font_color", MenuStyle.COLOR_DESC)
	_romm_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_romm_empty_label.visible = false
	vbox.add_child(_romm_empty_label)

	_romm_list = VirtualRowList.new()
	_romm_list.row_height = 100
	_romm_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_romm_list.set_row_builder(_build_blank_rom_row)
	_romm_list.set_row_binder(_bind_rom_row)
	_romm_list.window_moved.connect(_schedule_cover_prune)
	vbox.add_child(_romm_list)

	# Start before the first rebuild, or the empty list reads "add ROMs here"
	# while a sync is in fact already running.
	if _romm_shown() and _romm_platforms.has(systemid) and not RommCatalog.has_index(systemid):
		var pid := int((_romm_platforms[systemid] as Dictionary).get("id", 0))
		print("[RommSync] %s opened with no index at %s (platform id %d)"
			% [systemid, RommCatalog.index_path(systemid), pid])
		if pid > 0:
			romm_catalog.sync_platform(systemid, pid, true)

	# Grouping the dotcode cards opens every strip file to learn its length —
	# 4000 opens on a full set, seconds on the main thread. Scan off it and
	# fill the page when the result lands; until then the list says so.
	if systemid == EReaderCards.SYSTEMID and not EReaderCards.is_warm():
		EReaderCards.warm_async("", _on_ereader_cards_warm.bind(systemid))

	_rebuild_romm_rows()


# ── Global game search ───────────────────────────────────────────────────────
# One query across every system: local ROM folders and synced RomM indexes on a
# worker (GameSearch.search_all), plus the server's own search for platforms this
# device never synced. The results are a short plain list, not the system page's
# VirtualRowList — they are capped, and a row here only launches or downloads.

## The search box on the Games home page. Searching on Enter or the button, not
## per key: the results are a page of their own, and swapping pages under a
## focused field would drop the keyboard mid-word.
func _build_global_search_bar() -> void:
	var bar := _cartridges_browser.home_toolbar()
	bar.add_theme_constant_override("separation", 8)
	_gs_home_edit = LineEdit.new()
	_gs_home_edit.placeholder_text = "Search games in every system…"
	_gs_home_edit.clear_button_enabled = true
	_gs_home_edit.custom_minimum_size = Vector2(0, 52)
	_gs_home_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_gs_home_edit.add_theme_font_size_override("font_size", 20)
	_gs_home_edit.text_submitted.connect(_open_global_search)
	bar.add_child(_gs_home_edit)
	var go := Button.new()
	go.text = "Search"
	go.add_theme_font_size_override("font_size", 20)
	go.custom_minimum_size = Vector2(120, 52)
	go.pressed.connect(func() -> void: _open_global_search(_gs_home_edit.text))
	bar.add_child(go)


func _open_global_search(query: String) -> void:
	_gs_query = query.strip_edges()
	_gs_local = {}
	_gs_server_rows.clear()
	_gs_server_term = ""
	print("[GameSearch] opened with query '%s' over %d systems" % [_gs_query, _gs_systems.size()])
	_cartridges_browser.open_system(GameSearch.PAGE_ID)
	_run_global_search()


func _populate_global_search(vbox: VBoxContainer) -> void:
	_romm_list = null
	var toolbar := _cartridges_browser.detail_toolbar()
	toolbar.visible = true
	var search := LineEdit.new()
	search.placeholder_text = "Search games in every system…"
	search.clear_button_enabled = true
	search.custom_minimum_size = Vector2(0, 52)
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.add_theme_font_size_override("font_size", 20)
	search.text = _gs_query
	search.text_changed.connect(_on_global_search_changed)
	toolbar.add_child(search)

	_gs_status = Label.new()
	_gs_status.add_theme_font_size_override("font_size", 18)
	_gs_status.add_theme_color_override("font_color", MenuStyle.COLOR_DESC)
	_gs_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_gs_status)
	_gs_list = VBoxContainer.new()
	_gs_list.add_theme_constant_override("separation", 6)
	_gs_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_gs_list)

	_cartridges_browser.push_subpage("Search all games",
		func() -> void: _cartridges_browser.show_home())
	_render_global_results()


func _on_global_search_changed(text: String) -> void:
	_gs_query = text.strip_edges()
	if _gs_timer == null:
		_gs_timer = Timer.new()
		_gs_timer.one_shot = true
		_gs_timer.timeout.connect(_run_global_search)
		add_child(_gs_timer)
	_gs_timer.start(SEARCH_DEBOUNCE_SEC)


func _run_global_search() -> void:
	var term := _gs_query
	if SearchFold.fold(term).length() < GameSearch.MIN_QUERY:
		_gs_local = {}
		_gs_server_rows.clear()
		_gs_searching = false
		_render_global_results()
		return
	_gs_searching = true
	_render_global_results()
	_global_search_local(term)
	_global_search_server(term)


## The folders and indexes are resolved HERE, on the main thread: RomLibrary's
## folder cache and the core database are not the worker's to touch.
func _global_search_local(term: String) -> void:
	if _gs_task >= 0:
		_gs_dirty = true
		return
	var jobs: Array = []
	for sys: Dictionary in _gs_systems:
		var sid: String = sys["systemid"]
		# Not a ternary: its `[]` branch is an untyped Array, which an
		# Array[String] refuses at run time.
		var exts: Array[String] = []
		if sid != EReaderCards.SYSTEMID:
			exts = CoreInfoDatabase.extensions_for_systemid(sid)
		var info := SystemInfo.for_system(sid)
		jobs.append({
			"systemid": sid,
			"name": sys["name"],
			"index_dir": RommCatalog.index_dir(sid) if _romm_shown() and RommCatalog.has_index(sid) else "",
			"local_dirs": RomLibrary.rom_dirs_for_system(sid),
			"exts": exts,
			"folders": info != null and info.folder_content,
			"cached": romm_cache.cached_paths_for_system(sid) if romm_cache != null else {},
		})
	_gs_task = WorkerThreadPool.add_task(func() -> void:
		var found := GameSearch.search_all(jobs, term)
		_on_global_search_local_done.call_deferred(term, found)
	, false, "Global game search")


func _on_global_search_local_done(term: String, found: Dictionary) -> void:
	_finish_global_search()
	if _gs_dirty:
		_gs_dirty = false
		_global_search_local(_gs_query)
		return
	if term != _gs_query:
		return
	_gs_local = found
	_gs_searching = false
	print("[GameSearch] '%s': %d local/index rows%s" % [term,
		(found["rows"] as Array).size(), " (truncated)" if found["truncated"] else ""])
	_render_global_results()


## RomM's own search, for platforms this device never synced. Only when RomM is
## set up; a failure just leaves the local half on its own.
func _global_search_server(term: String) -> void:
	if romm_config == null or not romm_config.is_configured() or romm_client == null:
		return
	romm_client.search_roms(term, GameSearch.RESULT_LIMIT, func(ok: bool, rows: Array) -> void:
		if not is_instance_valid(self) or term != _gs_query:
			return
		if not ok:
			print("[GameSearch] RomM search for '%s' failed; local results only" % term)
			return
		_gs_server_term = term
		_gs_server_rows.assign(rows)
		print("[GameSearch] RomM answered '%s' with %d rows" % [term, rows.size()])
		_render_global_results()
	)


func _finish_global_search() -> void:
	if _gs_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_gs_task)
		_gs_task = -1


## The worker's rows plus whatever the server found that they do not already
## hold, as one list. A server row is matched to its system through the platform
## id the sync recorded; one on a platform with no systemid here is dropped.
func _global_result_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var have: Dictionary = {}
	for r: Dictionary in (_gs_local.get("rows", []) as Array):
		rows.append(r)
		if int(r["rom_id"]) > 0:
			have[int(r["rom_id"])] = true
	if _gs_server_term == _gs_query:
		var by_platform: Dictionary = {}
		for sid: String in _romm_platforms:
			by_platform[int((_romm_platforms[sid] as Dictionary).get("id", 0))] = sid
		for e: Dictionary in _gs_server_rows:
			var rid := int(e.get("id", 0))
			var sid := str(by_platform.get(int(e.get("platform_id", 0)), ""))
			if rid == 0 or sid.is_empty() or have.has(rid) \
					or RommCatalog._is_save_ext(str(e.get("fs_extension", "")).to_lower()):
				continue
			have[rid] = true
			var path := ""
			if romm_cache != null:
				path = str(romm_cache.cached_paths_for_system(sid).get(rid, ""))
			rows.append({
				"systemid": sid, "system_name": _system_label(sid),
				"label": str(e.get("name", "")), "path": path,
				"source": "both" if not path.is_empty() else "server",
				"rom_id": rid, "entry": e, "regions": PackedStringArray(),
			})
		GameSearch.sort_rows(rows, _gs_query)
	return rows


func _render_global_results() -> void:
	if not is_instance_valid(_gs_list):
		return
	for c in _gs_list.get_children():
		c.queue_free()
	if SearchFold.fold(_gs_query).length() < GameSearch.MIN_QUERY:
		_gs_status.text = "Type at least %d letters to search every system." % GameSearch.MIN_QUERY
		return
	var rows := _global_result_rows()
	var shown := mini(rows.size(), GameSearch.RESULT_LIMIT)
	if rows.is_empty():
		_gs_status.text = "Searching…" if _gs_searching \
			else "No games match \"%s\"." % _gs_query
		return
	_gs_status.text = ("%d games" % shown) if rows.size() <= GameSearch.RESULT_LIMIT \
		and not bool(_gs_local.get("truncated", false)) \
		else "First %d games — narrow the search to see more." % shown
	for i in shown:
		_gs_list.add_child(_make_global_row(rows[i]))


func _make_global_row(hit: Dictionary) -> Control:
	var sid: String = hit["systemid"]
	var path: String = hit["path"]
	var label: String = hit["label"]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var main := Button.new()
	main.text = "  " + label
	main.alignment = HORIZONTAL_ALIGNMENT_LEFT
	main.clip_text = true
	main.custom_minimum_size = Vector2(0, 68)
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.add_theme_font_size_override("font_size", 20)
	if not path.is_empty():
		main.tooltip_text = "Spawn this game"
		main.pressed.connect(func() -> void:
			if romm_cache != null:
				romm_cache.touch(sid, RommCacheManifest.relative_path(sid, path))
			spawn_cartridge_requested.emit(path, label, sid, {}))
	elif romm_client != null and romm_client.is_reachable():
		main.tooltip_text = "Download from RomM (%s)" % ByteSize.human(
			int((hit["entry"] as Dictionary).get("fs_size_bytes", 0)))
		main.pressed.connect(func() -> void:
			romm_downloader.enqueue(hit["entry"], sid)
			show_notice("Downloading %s" % label))
	else:
		main.disabled = true
		main.tooltip_text = "RomM is unreachable — this title is on the server only"
	row.add_child(main)

	var state := Label.new()
	state.add_theme_font_size_override("font_size", 16)
	state.add_theme_color_override("font_color", MenuStyle.COLOR_DESC)
	state.text = {"both": "Downloaded", "local": "On device", "server": "RomM"}.get(hit["source"], "")
	state.custom_minimum_size = Vector2(110, 0)
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	state.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(state)

	# The system's proper name, and one press to its own page.
	var sys_btn := Button.new()
	sys_btn.text = str(hit["system_name"])
	sys_btn.clip_text = true
	sys_btn.custom_minimum_size = Vector2(230, 68)
	sys_btn.add_theme_font_size_override("font_size", 18)
	sys_btn.tooltip_text = "Open %s" % hit["system_name"]
	sys_btn.pressed.connect(func() -> void: _cartridges_browser.open_system(sid))
	row.add_child(sys_btn)
	return row


func _on_ereader_cards_warm(systemid: String) -> void:
	if _romm_detail_systemid != systemid:
		return
	if not is_instance_valid(_romm_list):
		return
	_invalidate_local_scan(systemid)
	_rebuild_romm_rows()


## Build the merged row model: every local file, plus every server entry, with
## entries that are both collapsed into one row.
##
## Dedupe is by filename first — cheap and correct for the overwhelmingly common
## case. Hashing 361 GiB to build a list is not an option, so MD5 is only
## consulted when a local hash happens to be cached already.
func _rebuild_romm_rows() -> void:
	var systemid := _romm_detail_systemid
	if systemid.is_empty():
		return

	_romm_rows.clear()
	var regions_seen: Dictionary = {}

	# 1. Local files, keyed by lowercase basename.
	#
	# Scanned WITHOUT the extension filter: RomM stores ROMs as .zip, which is
	# not in any core's supported_extensions, so a filtered scan cannot see a
	# freshly downloaded file and every row stays stuck on "download me".
	# Keying on the basename also survives the archive being unpacked, where
	# X.zip becomes X.3ds.
	# Cached: this is a directory listing, and a rebuild happens on every filter
	# change. Invalidated whenever something writes to the ROM dir — see
	# _invalidate_local_scan.
	var local_by_name: Dictionary = _local_by_name(systemid)

	# 2. Server entries. Everything here comes from sidecars already in RAM —
	# no seek and no JSON parse per row, or opening a 3k-ROM platform stalls the
	# frame for a second building rows nobody is looking at yet. The row's real
	# data is read on demand in _bind_rom_row, for the dozen rows on screen.
	# Switched off, a synced index on disk still lists the server's games; only the
	# local files are this page's then.
	var have_index := _romm_shown() and romm_catalog.load_index(systemid)
	var matched: Dictionary = {}
	# rom_id -> local path for everything this system has downloaded, resolved
	# once. Asking the manifest per row formats a key and probes two dictionaries
	# 49,000 times to find the thirteen entries that exist — 60 ms of the rebuild.
	var cached_by_rom: Dictionary = romm_cache.cached_paths_for_system(systemid) \
		if romm_cache != null else {}
	if have_index:
		var fast := romm_catalog.has_fast_sidecars()
		var indices := PackedInt32Array()
		if _romm_filter.is_empty():
			indices.resize(romm_catalog.count())
			for i in romm_catalog.count():
				indices[i] = i
		else:
			indices = romm_catalog.search(_romm_filter)

		for i: int in indices:
			# Not a game, so never in the list: a save or savestate kept beside
			# its game, which would otherwise claim that game's local file as a
			# row of its own.
			if romm_catalog.is_hidden_at(i):
				continue
			var key := ""
			var label := ""
			var regions := PackedStringArray()
			if fast:
				key = romm_catalog.fs_basename_at(i)
				label = romm_catalog.name_at(i)
				regions = romm_catalog.regions_at(i)
			else:
				# Index predates the sidecars; fall back to the slow path so an
				# un-resynced platform still works.
				var entry := romm_catalog.row(i)
				if entry.is_empty():
					continue
				key = str(entry.get("fs_name", "")).get_basename().to_lower()
				label = str(entry.get("name", key))
				var rl: Array = entry.get("regions", []) if entry.get("regions") is Array else []
				for r: Variant in rl:
					regions.append(str(r))

			# A multi-file server ROM is keyed by its deleted source archive in the
			# cache but launches an m3u/cue below it. Resolve by stable RomM id before
			# falling back to basename matching.
			var cached_path := str(cached_by_rom.get(romm_catalog.rom_id_at(i), ""))
			var local: Dictionary = {"path": cached_path, "label": label} \
				if not cached_path.is_empty() else local_by_name.get(key, {})
			if not local.is_empty():
				matched[key] = true
				matched[str(local.get("path", "")).get_file().get_basename().to_lower()] = true

			for r: String in regions:
				regions_seen[r] = true

			var src := "both" if not local.is_empty() else "server"
			if not _romm_row_passes(src, regions):
				continue
			_romm_rows.append({
				"source": src,
				"index": i,
				"path": str(local.get("path", "")),
				"label": label,
			})

	# 3. Local-only files the server doesn't know about. The extension filter
	# skipped in step 1 applies here, or gamelist.json lists itself as a ROM.
	var needle := SearchFold.fold(_romm_filter)
	for key: String in local_by_name:
		if matched.has(key):
			continue
		var rom: Dictionary = local_by_name[key]
		# Skipping a cache-owned file is only safe when there was an index to
		# match it against — step 2 is where it earns its row back. With no
		# index the row never comes, and a game sitting on disk is listed
		# nowhere at all.
		if have_index and romm_cache != null and romm_cache.owns_file(systemid,
				RommCacheManifest.relative_path(systemid, str(rom["path"]))):
			continue
		var ext := str(rom["path"]).get_extension().to_lower()
		if not _romm_detail_exts.is_empty() and ext not in _romm_detail_exts:
			continue
		var label := str(rom["label"])
		if not needle.is_empty() and not SearchFold.fold(label).contains(needle):
			continue
		# A local-only file has no server metadata, so it has no region to match.
		if not _romm_row_passes("local", PackedStringArray()):
			continue
		_romm_rows.append({
			"source": "local",
			"index": -1,
			"path": str(rom["path"]),
			"label": label,
		})

	# 4. A downloaded game's variants are one row, the starred copy's. A disc not
	# downloaded yet is in no gamelist, so it keeps a row of its own.
	if gamelist_manager != null:
		_romm_rows.assign(GamelistManager.collapse_variant_rows(
			systemid, _romm_rows, gamelist_manager.games_with_variants(systemid)))

	_romm_refresh_region_options(regions_seen)

	if is_instance_valid(_romm_list):
		_romm_list.set_row_count(_romm_rows.size())

	_romm_update_empty_label()


## Split out of the rebuild so a reachability transition can correct the wording
## without rebuilding every row.
func _romm_update_empty_label() -> void:
	if not is_instance_valid(_romm_empty_label):
		return
	_romm_empty_label.visible = _romm_rows.is_empty()
	if not _romm_rows.is_empty():
		return
	if _romm_detail_systemid == EReaderCards.SYSTEMID and not EReaderCards.is_warm():
		var p := EReaderCards.scan_progress()
		_romm_empty_label.text = "Scanning cards…" if p.y == 0 			else "Scanning cards… %d / %d" % [p.x, p.y]
		# Tick the count until the scan lands; the rebuild it triggers stops this.
		get_tree().create_timer(0.25).timeout.connect(_romm_update_empty_label)
	elif not _romm_filter.is_empty():
		_romm_empty_label.text = "No games match “%s”." % _romm_filter
	elif not romm_client.is_reachable():
		# Ahead of the sync check: a sync that is still "running" against a dead
		# server is not news the player can use.
		_romm_empty_label.text = "RomM is unreachable — only local files are listed."
	elif romm_catalog.is_syncing():
		_romm_empty_label.text = "Syncing from RomM…"
	else:
		_romm_empty_label.text = "Add ROMs to %s/ to see them here." \
			% RomLibrary.rom_dir_for_system(_romm_detail_systemid)


## Warm the sidecars for the platforms most likely to be opened next.
##
## Biggest first, because cost scales with row count and those are the ones that
## stutter. Capped: the warm worker handles one platform at a time and a long
## queue would still be running when the user taps.
func _prewarm_top_platforms(systems: Array) -> void:
	if romm_catalog == null:
		return
	var sized: Array = []
	for s: Dictionary in systems:
		var sid: String = s["systemid"]
		if int(s.get("badge_count", 0)) > 0:
			sized.append([int(s["badge_count"]), sid])
	sized.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) > int(b[0]))
	# Every synced platform, not just the first few: the worker also backfills
	# missing sidecars, which is a one-time repair worth doing for all of them
	# rather than only the ones that happen to be biggest.
	for e: Array in sized:
		romm_catalog.prewarm_index(str(e[1]))


## Local ROM files for one system, keyed by lowercase basename.
##
## Scanned WITHOUT the extension filter: RomM stores ROMs as .zip, which is not
## in any core's supported_extensions, so a filtered scan cannot see a freshly
## downloaded file and every row stays stuck on "download me". Keying on the
## basename also survives the archive being unpacked, where X.zip becomes X.3ds.
func _local_by_name(systemid: String) -> Dictionary:
	if _local_scan_cache.has(systemid):
		return _local_scan_cache[systemid]
	# A card scan still running is not waited for here: the page shows nothing
	# yet and is rebuilt when it lands (_on_ereader_cards_warm). Not cached, so
	# the next rebuild asks again.
	if systemid == EReaderCards.SYSTEMID and not EReaderCards.is_warm():
		return {}
	# Same-stem collisions are resolved by RomLibrary: a manifest beats its tracks,
	# and a real game beats a save or savestate that happens to sit beside it.
	var by_name := RomLibrary.index_by_basename(
		RomLibrary.scan_roms(systemid, [] as Array[String]),
		CoreInfoDatabase.extensions_for_systemid(systemid))
	_local_scan_cache[systemid] = by_name
	return by_name


## Mint a blank pack into the broadcast folder and show it straight away.
##
## It lands beside the channel packets on purpose: snes9x reads its broadcast
## directory from the loaded ROM's own folder, so a pack kept anywhere else boots
## perfectly and receives nothing.
func _on_new_pack_pressed(systemid: String) -> void:
	var path := BsxPack.create_blank(RomLibrary.rom_dir_for_system(systemid))
	if path.is_empty():
		push_warning("[SpawnView] could not create a memory pack in %s" % systemid)
		return
	print("[SpawnView] new memory pack: %s" % path)
	_invalidate_local_scan(systemid)
	if _cartridges_browser:
		_cartridges_browser.refresh_detail()


## Drop the cached listing after anything that writes to a ROM directory —
## a download landing, an eviction, a scrape, a manual refresh.
func _invalidate_local_scan(systemid: String = "") -> void:
	if systemid.is_empty():
		_local_scan_cache.clear()
	else:
		_local_scan_cache.erase(systemid)
	# The tile counts go stale with the listing. Recounted rather than dropped, so
	# a tile keeps its old number until the new one lands instead of blinking.
	if systemid.is_empty():
		var all: Array[String] = []
		all.assign(_local_counts.keys())
		_request_local_counts(all)
	elif _local_counts.has(systemid):
		_request_local_counts([systemid] as Array[String])
	# The adapter probe is a scan of the same folders and goes stale with them:
	# a reader dump copied in has to stop being a game and start being a machine
	# on the same refresh, not on the next launch.
	AdapterRoms.invalidate()


## Count these systems' local games on a worker, then redraw the tiles that
## changed. A listing per system is too slow for the frame on Quest storage, and
## the grid is rebuilt often — so this runs once per system per session, and again
## only for a folder something wrote to.
##
## Everything the worker needs is resolved here first: RomLibrary's folder cache
## and the core database are not the worker's to touch.
func _request_local_counts(systemids: Array[String]) -> void:
	for sid: String in systemids:
		_local_count_pending[sid] = true
	if _local_count_task >= 0 or _local_count_pending.is_empty():
		return
	var jobs: Array[Dictionary] = []
	for sid: String in _local_count_pending:
		# The e-Reader's shelf is cards, grouped by name off a scan of its own —
		# not a folder of games to count.
		if sid == EReaderCards.SYSTEMID:
			continue
		var exts := CoreInfoDatabase.extensions_for_systemid(sid)
		if exts.is_empty():
			_local_counts[sid] = 0
			continue
		var info := SystemInfo.for_system(sid)
		jobs.append({
			"systemid": sid,
			"dirs": RomLibrary.rom_dirs_for_system(sid),
			"exts": exts,
			"folders": info != null and info.folder_content,
		})
	_local_count_pending.clear()
	if jobs.is_empty():
		return
	_local_count_task = WorkerThreadPool.add_task(func() -> void:
		var counts: Dictionary = {}
		for job: Dictionary in jobs:
			counts[job["systemid"]] = _count_local_games(
				job["dirs"], job["exts"], job["folders"])
		_on_local_counts_ready.call_deferred(counts)
	, false, "Local ROM counts")


func _on_local_counts_ready(counts: Dictionary) -> void:
	if _local_count_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_local_count_task)
		_local_count_task = -1
	var changed := false
	for sid: String in counts:
		if int(_local_counts.get(sid, -1)) != int(counts[sid]):
			_local_counts[sid] = int(counts[sid])
			changed = true
	if changed:
		_owe(false, true, false)
	# Whatever was asked for while this one ran.
	_request_local_counts([] as Array[String])


## Games in a system's ROM folders, counted the way its page lists them: one per
## file stem with an extension a core loads, so a .cue and its .bin are one game
## and the gamelist and scraped media beside them are none. A folder-content
## system (ScummVM) also counts each subfolder holding a file it loads.
##
## Pure DirAccess and nothing shared, so it is safe on a worker. It does not ask
## AdapterRoms, so a reader's own dump on the Game Boy Advance shelf is counted
## as a game here; one too many is the price of keeping that probe off the thread.
static func _count_local_games(dirs: PackedStringArray, exts: Array[String],
		folders: bool) -> int:
	var stems: Dictionary = {}
	var games := 0
	for dir_path: String in dirs:
		var dir := DirAccess.open(dir_path)
		if not dir:
			continue
		dir.list_dir_begin()
		var f := dir.get_next()
		while f != "":
			if f.begins_with("."):
				pass
			elif dir.current_is_dir():
				if folders and _folder_has_game(dir_path.path_join(f), exts):
					games += 1
			elif f.get_extension().to_lower() in exts:
				stems[f.get_basename().to_lower()] = true
			f = dir.get_next()
		dir.list_dir_end()
	return games + stems.size()


static func _folder_has_game(path: String, exts: Array[String]) -> bool:
	var dir := DirAccess.open(path)
	if not dir:
		return false
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir() and not f.begins_with(".") \
				and f.get_extension().to_lower() in exts:
			dir.list_dir_end()
			return true
		f = dir.get_next()
	dir.list_dir_end()
	return false


func _exit_tree() -> void:
	_finish_local_count()
	_finish_global_search()


## A view freed without ever entering the tree (spawn_menu_tests builds one
## bare) gets no _exit_tree, and the count's worker then calls back into a
## freed object: a segfault at quit.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_finish_local_count()
		_finish_global_search()


func _finish_local_count() -> void:
	if _local_count_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_local_count_task)
		_local_count_task = -1


func _romm_row_passes(source: String, regions: PackedStringArray) -> bool:
	match _romm_source_filter:
		"downloaded":
			if source != "both":
				return false
		"on_disk":
			if source == "server":
				return false
		"server":
			if source != "server":
				return false
		"local":
			if source != "local":
				return false

	# Local-only rows are exempt. The dropdown's options are built from server
	# rows alone (_romm_refresh_region_options), and a local file carries no
	# region at all — so it can never match any option, and picking a region
	# silently emptied the list of the files the player actually owns.
	if source != "local" and not _romm_region_filter.is_empty():
		if _romm_region_filter not in regions:
			return false
	return true


## Rebuild the region list from what the platform actually contains, keeping the
## current selection if it survives.
func _romm_refresh_region_options(seen: Dictionary) -> void:
	var names: Array[String] = []
	for r: String in seen:
		if not r.is_empty():
			names.append(r)
	names.sort()
	if names == _romm_region_options:
		return
	_romm_region_options = names

	# A selection that no longer exists on this platform would silently empty
	# the list.
	if not _romm_region_filter.is_empty() and _romm_region_filter not in names:
		_romm_region_filter = ""

	if not is_instance_valid(_romm_region_drop):
		return
	var opts: Array = [["All regions", ""]]
	for r: String in names:
		var flag := MenuIcons.region_flag(r)
		opts.append([r if flag.is_empty() else "%s %s" % [flag, r], r])
	_romm_region_drop.set_options(opts, _romm_region_filter)


## Debounced: a rebuild scans the ROM dir, runs the filter over every server
## row and rebuilds the model, which is tens of milliseconds on a 3k platform
## on Quest. Doing that per keystroke made typing stutter; typing is bursty, so
## coalescing to one rebuild once the keys stop costs nothing in responsiveness.
func _on_romm_search_changed(text: String) -> void:
	_romm_filter = text.strip_edges().to_lower()
	if _romm_search_timer == null:
		_romm_search_timer = Timer.new()
		_romm_search_timer.one_shot = true
		_romm_search_timer.wait_time = SEARCH_DEBOUNCE_SEC
		_romm_search_timer.timeout.connect(_rebuild_romm_rows)
		add_child(_romm_search_timer)
	_romm_search_timer.start(SEARCH_DEBOUNCE_SEC)


# ── Virtualized ROM rows ──────────────────────────────────────────────────────
# Glyph codepoints verified present in RetroXR/fonts/SymbolsNerdFont-Regular.ttf.
# Two different delete glyphs is deliberate: the pictogram encodes whether the
# file can be got back. (At row size the two trash cans look near-identical, so
# the confirm text carries the real distinction — the glyph is a support cue.)


## Allocate one blank recyclable row. Called ~12 times total, not once per ROM.
func _build_blank_rom_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var state := Button.new()
	state.name = "State"
	state.custom_minimum_size = Vector2(76, 100)
	state.add_theme_font_override("font", MenuIcons.symbols())
	state.add_theme_font_size_override("font_size", 40)
	row.add_child(state)

	var pct := Label.new()
	pct.name = "Pct"
	pct.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pct.add_theme_font_size_override("font_size", 15)
	pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pct.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	pct.offset_top = -32
	pct.offset_bottom = -14
	pct.visible = false
	state.add_child(pct)

	var cover := TextureRect.new()
	cover.name = "Cover"
	cover.custom_minimum_size = Vector2(72, 96)
	# IGNORE_SIZE: FIT_HEIGHT_PROPORTIONAL reports a minimum height of
	# width * aspect, which pushes a portrait cover's row past row_height.
	cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(cover)

	# A pack this room minted, marked before the title. Its own Label rather than
	# a prefix on the title: MarqueeButton draws through an internal label and
	# clips to its own width, so a glyph put in the text scrolls away with it.
	var pack_mark := Label.new()
	pack_mark.name = "PackMark"
	pack_mark.add_theme_font_override("font", MenuIcons.symbols())
	pack_mark.add_theme_font_size_override("font_size", 26)
	pack_mark.add_theme_color_override("font_color", MenuIcons.TINT_OK)
	pack_mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pack_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pack_mark.text = String.chr(MenuIcons.BSX_MEMORY_PACK)
	pack_mark.visible = false
	row.add_child(pack_mark)

	var main := MarqueeButton.create("", 22)
	main.name = "Main"
	HoldPress.attach(main)
	main.custom_minimum_size = Vector2(0, 100)
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(main)

	# What a dotcode card's strips are — "L", "S", "L+S", "L+L" — under the title
	# it belongs to, in the description grey so it reads as an annotation rather
	# than part of the name. A child of the title button for the same reason Pct
	# is a child of State: a Control's children draw over it, where a prefix put
	# in the text would scroll away with the marquee.
	var strips := Label.new()
	strips.name = "Strips"
	strips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strips.add_theme_font_size_override("font_size", 15)
	strips.add_theme_color_override("font_color", MenuStyle.COLOR_DESC)
	strips.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	strips.offset_left = 10
	strips.offset_top = -30
	strips.offset_bottom = -10
	strips.visible = false
	main.add_child(strips)

	# The disc's numeral and the region's flag, in the title's bottom-right corner
	# for the same reason. One box for the pair: a row can carry several flags, so
	# only a container knows where "left of the flag" is, and a hidden badge
	# takes no room in one.
	var badges := HBoxContainer.new()
	badges.name = "Badges"
	badges.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badges.add_theme_constant_override("separation", 8)
	badges.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	badges.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	badges.grow_vertical = Control.GROW_DIRECTION_BEGIN
	badges.offset_left = -12
	badges.offset_right = -12
	badges.offset_top = -8
	badges.offset_bottom = -8
	main.add_child(badges)

	var disc := Label.new()
	disc.name = "Disc"
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	disc.add_theme_font_override("font", MenuIcons.symbols())
	disc.add_theme_font_size_override("font_size", 30)
	disc.add_theme_color_override("font_color", MenuStyle.COLOR_TITLE)
	disc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	disc.visible = false
	badges.add_child(disc)

	var region_flag := Label.new()
	region_flag.name = "RegionFlag"
	region_flag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	region_flag.add_theme_font_override("font", MenuIcons.flags_font())
	region_flag.add_theme_font_size_override("font_size", 30)
	region_flag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	region_flag.visible = false
	badges.add_child(region_flag)

	# How many variants a folded row stands for, top-right.
	var variants := Label.new()
	variants.name = "Variants"
	variants.mouse_filter = Control.MOUSE_FILTER_IGNORE
	variants.add_theme_font_size_override("font_size", 17)
	variants.add_theme_color_override("font_color", MenuStyle.COLOR_DESC)
	variants.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	variants.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	variants.offset_left = -12
	variants.offset_right = -12
	variants.offset_top = 8
	variants.offset_bottom = 8
	variants.visible = false
	main.add_child(variants)

	# "Pack" is last and shows only for a .bs: what is written on a Satellaview
	# memory pack, which the row itself can only summarise.
	for n: String in ["Detail", "Saves", "Manual", "Scrape", "Pack"]:
		var b := Button.new()
		b.name = n
		b.custom_minimum_size = Vector2(66, 100)
		b.add_theme_font_override("font", MenuIcons.symbols())
		b.add_theme_font_size_override("font_size", 26)
		b.add_theme_color_override("font_color", Color(0.72, 0.72, 0.86))
		row.add_child(b)

	return row


## Fill a recycled row for `index`. Runs on every scroll, so it must be cheap
## and must disconnect anything it connected last time.
func _bind_rom_row(row: Control, index: int) -> void:
	if index < 0 or index >= _romm_rows.size():
		return
	var model: Dictionary = _romm_rows[index]
	# Read on demand: this is the only place a row's JSON is parsed.
	var cat_index := int(model.get("index", -1))
	var entry: Dictionary = romm_catalog.row(cat_index) if cat_index >= 0 else {}
	var systemid := _romm_detail_systemid
	var source := str(model["source"])
	var label := str(model["label"])
	var rom_id := int(entry.get("id", 0))
	var local_path := str(model["path"])

	var state := row.get_node("State") as Button
	var pct := state.get_node("Pct") as Label
	var cover := row.get_node("Cover") as TextureRect
	var main := row.get_node("Main") as MarqueeButton
	var detail := row.get_node("Detail") as Button
	var saves := row.get_node("Saves") as Button
	var manual := row.get_node("Manual") as Button
	var scrape := row.get_node("Scrape") as Button
	var pack := row.get_node("Pack") as Button

	_disconnect_all(state.pressed)
	_disconnect_all(main.pressed)
	# The pool's sweep above took HoldPress's own listener with it.
	var hold := main.get_node("HoldPress") as HoldPress
	hold.reset()
	hold.ensure_connected()
	hold.hold_enabled = false
	_disconnect_all(hold.clicked)
	_disconnect_all(hold.held)
	_disconnect_all(detail.pressed)
	_disconnect_all(saves.pressed)
	_disconnect_all(manual.pressed)
	_disconnect_all(scrape.pressed)
	_disconnect_all(pack.pressed)

	# Rows are pooled, so anything a branch below only sets conditionally has to
	# be cleared here — otherwise one dead-server row leaves every title it later
	# recycles into greyed out and unpressable.
	row.modulate = Color(1.0, 1.0, 1.0, 1.0)
	state.disabled = false
	main.disabled = false

	# Rows are pooled, so this is set on EVERY bind and not only when true --
	# otherwise one pack leaves its mark on every title it later recycles into.
	var pack_mark := row.get_node("PackMark") as Label
	pack_mark.visible = BsxPack.is_own_pack_path(local_path)
	pack_mark.tooltip_text = "A memory pack made here — the Satellaview writes downloads to this one"

	# Set on every bind for the same reason, and off any platform but the cards.
	var strips := main.get_node("Strips") as Label
	strips.text = ""
	if systemid == EReaderCards.SYSTEMID and not local_path.is_empty():
		strips.text = EReaderCards.strip_summary(EReaderCards.card_for_path(local_path))
	strips.visible = not strips.text.is_empty()

	var region_flag := main.get_node("Badges/RegionFlag") as Label
	region_flag.text = MenuIcons.region_flags(_row_regions(cat_index, systemid, local_path))
	region_flag.visible = not region_flag.text.is_empty()

	# The file's own name where there is a file, else the name the server holds
	# it under. A folded row shows its starred copy's, the disc a tap spawns.
	var disc := main.get_node("Badges/Disc") as Label
	disc.text = MenuIcons.disc_badge(MenuIcons.disc_number(_row_filename(local_path, entry)))
	disc.visible = not disc.text.is_empty()

	var variants := main.get_node("Variants") as Label
	var variant_count := int(model.get("variants", 0))
	variants.text = "%d variants" % variant_count
	variants.visible = variant_count > 1

	# A scraped wheel logo replaces the title text entirely; otherwise the title
	# scrolls. MarqueeButton extends Button, so it carries the icon itself.
	var wheel: Texture2D = null
	if not local_path.is_empty():
		wheel = scraped_art.get_or_request(systemid, local_path.get_file(), "wheel", WHEEL_BOX)
	if wheel != null:
		main.icon = wheel
		main.expand_icon = false
		main.add_theme_constant_override("icon_max_width", WHEEL_BOX.x)
		main.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		main.set_marquee_text("")
	else:
		main.icon = null
		main.expand_icon = false
		# MarqueeButton keeps its own `text` empty and draws via an internal
		# label — setting `text` directly would fight its width clipping.
		main.set_marquee_text("  " + label)

	# ── Leading state icon ──────────────────────────────────────────────────
	var downloading := rom_id > 0 and romm_downloader.current_rom_id() == rom_id
	pct.visible = false

	if downloading:
		state.text = String.chr(MenuIcons.BUSY)
		state.add_theme_color_override("font_color", MenuIcons.TINT_BUSY)
		state.tooltip_text = "Cancel download"
		pct.visible = true
		pct.add_theme_color_override("font_color", MenuIcons.TINT_BUSY)
		pct.text = "%d%%" % _romm_sync.progress_pct(rom_id)
		state.pressed.connect(func() -> void: romm_downloader.cancel_current())
	elif source == "server":
		# The cloud glyph is visually lighter than the trash glyphs at the same
		# size — a small bump evens the weight out.
		state.add_theme_font_size_override("font_size", 44)
		if romm_client.is_reachable():
			state.text = String.chr(MenuIcons.DOWNLOAD)
			state.add_theme_color_override("font_color", MenuIcons.TINT_DOWNLOAD)
			state.tooltip_text = "Download from RomM (%s)" % ByteSize.human(int(entry.get("fs_size_bytes", 0)))
			state.pressed.connect(func() -> void: romm_downloader.enqueue(entry, systemid))
		else:
			# The index is on disk, so these keep listing with the server down.
			# The row is the only place that can say so: the unreachable toast is
			# long gone by the time you have scrolled to the one you wanted.
			state.text = String.chr(MenuIcons.SYNC_OFF)
			state.add_theme_color_override("font_color", MenuIcons.TINT_MUTED)
			state.tooltip_text = "RomM is unreachable — this title is on the server only"
			state.disabled = true
			row.modulate = UNREACHABLE_DIM
	else:
		state.add_theme_font_size_override("font_size", 40)
		var forever := source == "local"
		state.text = String.chr(MenuIcons.DELETE_FOREVER if forever else MenuIcons.DELETE)
		state.add_theme_color_override("font_color", MenuIcons.TINT_DELETE)
		state.tooltip_text = "Delete permanently" if forever else "Delete local copy"
		state.pressed.connect(_on_rom_delete_pressed.bind(index, state))

	# ── Cover ───────────────────────────────────────────────────────────────
	# A scraped label beats RomM's cover, which is a screenshot on most servers;
	# the cover fills in until the label is scraped or while it is decoding.
	cover.texture = null
	if not local_path.is_empty():
		# Mipmapped: these are photographic scans read at a glancing angle in VR.
		# Was MediaDimensions.load_label_texture, which decoded and generated mips
		# inline with no cache at all — 4.1 ms per row on every scroll step.
		cover.texture = scraped_art.get_or_request(
			systemid, local_path, "label", LABEL_BOX, true)
	if cover.texture == null and rom_id > 0:
		cover.texture = romm_art.get_or_request(rom_id, str(entry.get("cover_small", "")), systemid)
	cover.visible = cover.texture != null

	# ── Launch ──────────────────────────────────────────────────────────────
	if not local_path.is_empty():
		var spawn := func(options: Dictionary) -> void:
			if romm_cache != null:
				romm_cache.touch(systemid,
					RommCacheManifest.relative_path(systemid, local_path))
			spawn_cartridge_requested.emit(local_path, label, systemid, options)
		hold.clicked.connect(spawn.bind({}))
		# Held for a second: choose the shell and the body before it spawns.
		hold.hold_enabled = _has_spawn_options(systemid)
		hold.held.connect(_show_cart_spawn_options.bind(systemid, label, spawn, local_path))
	elif romm_client.is_reachable():
		# Not downloaded yet — tapping the title fetches it, same as the icon.
		main.pressed.connect(func() -> void: romm_downloader.enqueue(entry, systemid))
	else:
		main.disabled = true

	# ── Trailing cluster ────────────────────────────────────────────────────
	# A Satellaview memory pack is a MEDIUM, not a game, and half this cluster is
	# about games. Worked out before the buttons rather than beside each one,
	# because more than one of them asks.
	var is_pack: bool = systemid == "satellaview" and not local_path.is_empty() \
			and BsxPack.is_pack_path(local_path)

	var meta := _romm_row_meta(systemid, local_path)
	var game: Dictionary = meta["game"]
	detail.text = String.chr(MenuIcons.GAMEPAD)
	# Not for a pack: there is no game to describe. A pack whose filename happens
	# to match a catalog entry would otherwise offer that game's page, which is a
	# different thing than the medium in front of you.
	detail.visible = not game.is_empty() and not is_pack
	if detail.visible:
		detail.pressed.connect(_show_game_detail_panel.bind(game, systemid, local_path))

	# The game's saves and achievements, the same page the cartridge's own menu
	# shows — reachable here so you can look before you spawn anything. Needs a
	# local ROM: a save is keyed by the file's path, and a title that is still only
	# on the server has none on this device.
	saves.text = String.chr(MenuIcons.CARD_SAVES)
	saves.visible = not local_path.is_empty()
	saves.tooltip_text = "Saves and achievements"
	if not local_path.is_empty():
		saves.pressed.connect(
			_show_game_saves_panel.bind(systemid, local_path, label))

	# ── Memory packs ────────────────────────────────────────────────────────
	# A pack is called by what is WRITTEN ON IT, read out of its own header, not
	# by its filename. The two are unrelated: a pack downloaded from the server
	# arrives named for the broadcast that filled it, and one minted here is named
	# whatever kept it unique on disk. An unused pack says so rather than showing
	# the placeholder title a blank carries.
	# A pack is named by EVERY programme written on it, not by the first: several
	# live on one medium, and naming it after block 0 leaves the rest invisible.
	if is_pack:
		main.set_marquee_text("  " + BsxPack.display_name(local_path))
	# Set on every bind, not only when true: rows are pooled, and a pack's button
	# left visible would offer a pack's contents for whatever title recycles here.
	pack.text = String.chr(MenuIcons.BSX_PACK_CONTENTS)
	pack.visible = is_pack
	pack.tooltip_text = "What is written on this pack"
	if is_pack:
		pack.pressed.connect(_show_pack_contents_panel.bind(local_path))

	var has_manual: bool = meta["has_manual"]
	var manual_path: String = meta["manual_path"]
	manual.text = String.chr(MenuIcons.BOOK)
	manual.visible = has_manual
	if has_manual:
		manual.pressed.connect(spawn_manual_requested.emit.bind(manual_path))

	# Scraping hashes the local file, so it needs one on disk. Not for a pack:
	# ScreenScraper has no entry for a medium, and a pack's hash changes every
	# time the player downloads onto it, so there is nothing stable to match.
	# disabled is reset here or a mid-scrape scroll leaves it stuck on whichever
	# row later reuses this pooled button.
	scrape.visible = not local_path.is_empty() and not is_pack
	var queued := scrape.visible and scrape_queue != null and scrape_queue.is_queued(local_path)
	if queued:
		scrape.text = "⏳"
		scrape.tooltip_text = "Waiting in the scrape queue"
	elif ScrapeQueue.is_scraped(meta["game"]):
		scrape.text = String.chr(MenuIcons.RESCRAPE)
		scrape.tooltip_text = "Scraped already. Scrape again from ScreenScraper"
	else:
		scrape.text = String.chr(MenuIcons.SCRAPE)
		scrape.tooltip_text = "Scrape artwork and details from ScreenScraper"
	scrape.disabled = queued
	if scrape.visible and not queued:
		scrape.pressed.connect(_scrape_ui.on_scrape_pressed.bind(local_path, systemid))


## Two-stage delete: the first press arms it, the second within 3 s commits.
## A single mis-tap must never delete a 4 GB download, and every
## Viewport2Din3D click already fires twice.
func _on_rom_delete_pressed(index: int, state: Button) -> void:
	if index < 0 or index >= _romm_rows.size():
		return
	var model: Dictionary = _romm_rows[index]
	var local_path := str(model["path"])
	if local_path.is_empty():
		return

	if _romm_delete_armed != index:
		_romm_delete_armed = index
		state.text = String.chr(MenuIcons.ERROR)
		var forever := str(model["source"]) == "local"
		show_notice("Tap again to %s" % ("delete permanently" if forever else "delete local copy"), 3.0)
		get_tree().create_timer(3.0).timeout.connect(func() -> void:
			if _romm_delete_armed == index:
				_romm_delete_armed = -1
				if is_instance_valid(_romm_list):
					_romm_list.rebind_visible()
		)
		return

	_romm_delete_armed = -1
	var systemid := _romm_detail_systemid
	var fname := local_path.get_file()
	var relative := RommCacheManifest.relative_path(systemid, local_path)

	# Read BEFORE the ROM goes, because the artwork lookup keys on the ROM's own
	# basename and the RomM cover on the server id. A hand-copied ROM has no
	# catalog row and yields 0, which matches no cover — correct, it has none.
	var catalog_index := int(model.get("index", -1))
	var rom_id := romm_catalog.rom_id_at(catalog_index) if \
		romm_catalog != null and catalog_index >= 0 else 0
	var metadata := StorageCleanup.metadata_for_rom(systemid, relative, rom_id)

	var removed_group := romm_cache != null \
		and romm_cache.remove_for_file(systemid, relative) >= 0
	if not removed_group and FileAccess.file_exists(local_path):
		DirAccess.remove_absolute(local_path)

	# Library row and artwork go with it. Saves deliberately do not: a game can be
	# fetched again and a save cannot, so orphaned saves are surfaced by the
	# Clean up sweep as their own explicitly-confirmed category instead.
	var freed := StorageCleanup.purge_rom_metadata(systemid, relative, rom_id)
	# The purge edited gamelist.json through its own manager, so this view's
	# cached copy is now a frame behind the disk.
	if gamelist_manager != null:
		gamelist_manager.invalidate(systemid)

	show_notice("Deleted %s%s" % [fname,
		"" if metadata.is_empty() else " and %d metadata file%s (%s)" % [
			metadata.size(), "" if metadata.size() == 1 else "s",
			ByteSize.human(freed)]], 2.5)
	_romm_meta_cache.clear()
	_invalidate_local_scan(systemid)
	_rebuild_romm_rows()


## Gamelist entry and manual path for a row. Memoized because the raw form is a
## linear scan of gamelist.json plus two file_exists calls, run per row on every
## bind — which is every scroll step and, previously, every download progress tick.
func _romm_row_meta(systemid: String, local_path: String) -> Dictionary:
	if local_path.is_empty():
		return {"game": {}, "manual_path": "", "has_manual": false}
	if _romm_meta_cache.has(local_path):
		return _romm_meta_cache[local_path]

	var manual_path := RomLibrary.scraped_manual_path(systemid, local_path.get_file())
	var meta := {
		"game": gamelist_manager.get_game_for_rom(systemid, local_path),
		"manual_path": manual_path,
		"has_manual": FileAccess.file_exists(manual_path),
	}
	_romm_meta_cache[local_path] = meta
	return meta


## A row's regions: RomM's for a server row, else the region the gamelist holds
## for that file — the only source a local-only file has.
func _row_regions(cat_index: int, systemid: String, local_path: String) -> PackedStringArray:
	var regions: PackedStringArray = romm_catalog.regions_at(cat_index) \
		if cat_index >= 0 else PackedStringArray()
	if not regions.is_empty() or local_path.is_empty():
		return regions
	var game: Dictionary = _romm_row_meta(systemid, local_path)["game"]
	var region := str(_rom_entry_for(game, local_path).get("region", ""))
	if not region.is_empty():
		regions.append(region)
	return regions


## The name a row's disc number is read off: the local file's where there is one,
## with its folder, since a disc nested as "Game (Disc 1)/Game.cue" is numbered
## there and not on the leaf; else the name RomM holds the ROM under.
static func _row_filename(local_path: String, entry: Dictionary) -> String:
	if local_path.is_empty():
		return str(entry.get("fs_name", ""))
	return local_path.get_base_dir().get_file().path_join(local_path.get_file())


## The entry in a game's "roms" for one file, or {} when the game does not list it.
static func _rom_entry_for(game: Dictionary, local_path: String) -> Dictionary:
	for rom: Dictionary in game.get("roms", []):
		if str(rom.get("path", "")).get_file() == local_path.get_file():
			return rom
	return {}


## Rows are recycled, so every connection from the previous bind must go.
static func _disconnect_all(sig: Signal) -> void:
	for c: Dictionary in sig.get_connections():
		sig.disconnect(c["callable"])


func _populate_books_tab() -> void:
	if not _books_vbox:
		return
	_clear_vbox(_books_vbox)
	var books := RomLibrary.scan_books()
	if books.is_empty():
		var hint := Label.new()
		hint.text = "No PDFs found in books folder."
		hint.add_theme_color_override("font_color", MenuStyle.COLOR_DESC)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_books_vbox.add_child(hint)
		return
	for book: Dictionary in books:
		var btn := Button.new()
		btn.text = "  📖  " + book["label"]
		btn.custom_minimum_size = Vector2(0, 72)
		btn.add_theme_font_size_override("font_size", 24)
		btn.pressed.connect(spawn_manual_requested.emit.bind(book["path"]))
		_books_vbox.add_child(btn)
	_books_vbox.add_child(MenuStyle.spacer(8))


func _populate_videos_tab() -> void:
	if not _videos_vbox:
		return
	_clear_vbox(_videos_vbox)
	var videos := RomLibrary.scan_videos()
	if videos.is_empty():
		var hint := Label.new()
		hint.text = "No videos found in videos folder."
		hint.add_theme_color_override("font_color", MenuStyle.COLOR_DESC)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_videos_vbox.add_child(hint)
		return
	for video: Dictionary in videos:
		var btn := Button.new()
		btn.text = "  📼  " + video["label"]
		btn.custom_minimum_size = Vector2(0, 72)
		btn.add_theme_font_size_override("font_size", 24)
		btn.pressed.connect(spawn_video_requested.emit.bind(video["path"]))
		_add_media_row(_videos_vbox, btn, video["path"], RomLibrary.default_videos_root())
	_videos_vbox.add_child(MenuStyle.spacer(8))


func _populate_dvds_tab() -> void:
	if not _dvds_vbox:
		return
	_clear_vbox(_dvds_vbox)
	var dvds := RomLibrary.scan_dvds()
	if dvds.is_empty():
		var hint := Label.new()
		hint.text = "No DVD images found in dvd folder."
		hint.add_theme_color_override("font_color", MenuStyle.COLOR_DESC)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_dvds_vbox.add_child(hint)
		return
	for dvd: Dictionary in dvds:
		var btn := Button.new()
		btn.text = "  💿  " + dvd["label"]
		btn.custom_minimum_size = Vector2(0, 72)
		btn.add_theme_font_size_override("font_size", 24)
		btn.pressed.connect(spawn_dvd_requested.emit.bind(dvd["path"]))
		_add_media_row(_dvds_vbox, btn, dvd["path"], RomLibrary.default_dvd_root())
	_dvds_vbox.add_child(MenuStyle.spacer(8))


func _populate_cds_tab() -> void:
	_populate_music_vbox(_cds_vbox, "💿", spawn_cd_requested)


func _populate_tapes_tab() -> void:
	_populate_music_vbox(_tapes_vbox, "🎵", spawn_cassette_requested)


func _populate_records_tab() -> void:
	_populate_music_vbox(_records_vbox, "🎶", spawn_record_requested)


## Shared list builder for the CDs / Tapes / Records tabs — all three list the same
## music albums, differing only in the icon and which spawn signal a row fires.
func _populate_music_vbox(vbox: VBoxContainer, icon: String, sig: Signal) -> void:
	if not vbox:
		return
	_clear_vbox(vbox)
	var albums := RomLibrary.scan_music()
	if albums.is_empty():
		var hint := Label.new()
		hint.text = "No music found in music folder."
		hint.add_theme_color_override("font_color", MenuStyle.COLOR_DESC)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(hint)
		return
	for album: Dictionary in albums:
		var btn := Button.new()
		btn.text = "  %s  %s" % [icon, album["label"]]
		btn.custom_minimum_size = Vector2(0, 72)
		btn.add_theme_font_size_override("font_size", 24)
		btn.pressed.connect(sig.emit.bind(album["path"]))
		_add_media_row(vbox, btn, album["path"], RomLibrary.default_music_root())
	vbox.add_child(MenuStyle.spacer(8))


## One library row: the delete button leading, where a ROM row keeps its own, then
## the spawn button taking the rest of the width.
func _add_media_row(vbox: VBoxContainer, spawn_btn: Button, path: String, root: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var del := Button.new()
	del.name = "Delete"
	del.custom_minimum_size = Vector2(76, spawn_btn.custom_minimum_size.y)
	del.add_theme_font_override("font", MenuIcons.symbols())
	del.add_theme_font_size_override("font_size", 40)
	del.add_theme_color_override("font_color", MenuIcons.TINT_DELETE)
	# A rebuild inside the arm window (the CDs tab, armed, then over to Records)
	# must not quietly hand back an innocent-looking trash can — and the new
	# button is the one the timer has to stand down.
	del.text = String.chr(MenuIcons.DELETE_FOREVER)
	if _media_delete_armed == path:
		del.text = String.chr(MenuIcons.ERROR)
		_media_delete_armed_btn = del
	del.tooltip_text = "Delete permanently"
	del.pressed.connect(_on_media_delete_pressed.bind(path, root, del))
	row.add_child(del)

	spawn_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spawn_btn.clip_text = true
	row.add_child(spawn_btn)
	vbox.add_child(row)


## Same two-stage confirm as _on_rom_delete_pressed. Nothing here can be fetched
## again — there is no server copy of a poster or an album — so it is always the
## "permanently" wording and always the DELETE_FOREVER glyph.
##
## Objects already in the room are left alone, as a deleted ROM leaves its
## cartridge: a poster keeps the texture it has loaded, and a tape whose file is
## gone simply will not play. The StorageBox is the verb for removing those.
func _on_media_delete_pressed(path: String, root: String, del: Button) -> void:
	if path.is_empty():
		return

	if _media_delete_armed != path:
		# Arming a second row stands the first one down at once, so there is never
		# more than one warning glyph on screen claiming to be one tap from gone.
		if is_instance_valid(_media_delete_armed_btn):
			_media_delete_armed_btn.text = String.chr(MenuIcons.DELETE_FOREVER)
		_media_delete_armed = path
		_media_delete_armed_btn = del
		_media_delete_serial += 1
		var serial := _media_delete_serial
		del.text = String.chr(MenuIcons.ERROR)
		show_notice("Tap again to delete permanently", 3.0)
		# The serial, not the path: A armed, B armed, A armed again must not have
		# A's FIRST timer cut its second arm short.
		get_tree().create_timer(3.0).timeout.connect(func() -> void:
			if _media_delete_serial == serial:
				_disarm_media_delete()
		)
		return

	_media_delete_armed = ""
	_media_delete_armed_btn = null
	_media_delete_serial += 1
	var fname := path.get_file()
	if RomLibrary.delete_library_entry(path, root):
		show_notice("Deleted %s" % fname, 2.5)
	else:
		# A file the player has open elsewhere, or a read-only folder on the card.
		show_notice("Could not delete %s" % fname, 3.0)

	if _poster_thumb_cache.erase(path):
		_poster_thumb_order.erase(path)
	_refresh_media_tabs(root)


func _disarm_media_delete() -> void:
	if is_instance_valid(_media_delete_armed_btn):
		_media_delete_armed_btn.text = String.chr(MenuIcons.DELETE_FOREVER)
	_media_delete_armed = ""
	_media_delete_armed_btn = null


## Rebuild whichever tabs list `root`. Music is three tabs over one folder, so an
## album deleted from CDs has to leave Tapes and Records too.
func _refresh_media_tabs(root: String) -> void:
	if root == RomLibrary.default_videos_root():
		_populate_videos_tab()
	elif root == RomLibrary.default_dvd_root():
		_populate_dvds_tab()
	elif root == RomLibrary.default_posters_root():
		_populate_posters_tab()
	elif root == RomLibrary.default_music_root():
		_populate_cds_tab()
		_populate_tapes_tab()
		_populate_records_tab()


## Returns the vbox, so a tab whose contents change at runtime can keep hold of
## it and repopulate. The const tabs ignore the return.
func _add_spawn_tab(tabs: TabContainer, tab_title: String, items: Array) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = tab_title
	tabs.add_child(scroll)
	_spawn_tab_scrolls.append(scroll)
	MenuStyle.fat_vscroll_bar(scroll)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 14)
	scroll.add_child(vbox)
	vbox.add_child(MenuStyle.spacer(10))
	for item: Array in items:
		vbox.add_child(_spawn_tab_button(item))
	return vbox


## Every mains lead the game ships, the player's region's first: the ones whose
## wall plug fits the room's outlets, then the rest, which still spawn -- an
## import's cord is a real thing to own -- but go into nothing on this wall.
func _power_items() -> Array:
	var all := []
	for token: String in MainsRegions.CORDS:
		all.append([str((MainsRegions.CORDS[token] as Dictionary)["label"]), token])
	# More sockets on a 3 ft cord, the strip sold where the room is --
	# including, if you like, for its own plug.
	all.append(["%d-Outlet Power Strip" % MainsRegions.strip_outlets(AppPrefs.mains_region),
		"power_strip"])
	# And any wall plug into this room's wall: the region's prongs, a universal
	# socket.
	all.append(["Universal Travel Adapter", "travel_adapter"])
	var own: Array = MainsRegions.of(AppPrefs.mains_region).get("cords", []) \
		+ ["travel_adapter"]
	var first := []
	var rest := []
	for item: Array in all:
		(first if own.has(item[1]) else rest).append(item)
	# And the cells a handheld, a printer, a Wii Remote or a Rumble Pak runs on,
	# whatever the region: they go in a battery bay (CellSlots). Each comes in
	# BatteryCell's labels, picked by holding its row.
	return first + rest + [["AA Battery", "battery_aa", BatteryCell.VARIANTS],
		["AAA Battery", "battery_aaa", BatteryCell.VARIANTS]]


## Re-sort the Power tab after the region changed.
func refresh_power_tab() -> void:
	if not is_instance_valid(_power_vbox):
		return
	_clear_vbox(_power_vbox)
	for item: Array in _power_items():
		_power_vbox.add_child(_spawn_tab_button(item))


## The Power tab's own name for the defaults its rows keep (_default_key), as a
## console card's are kept under its systemid.
const POWER_CARD := "power"


## One `[label, token]` row of a plain spawn tab, or `[label, token, variants]`
## for a thing that comes in several looks.
func _spawn_tab_button(item: Array) -> Button:
	var btn := Button.new()
	btn.text = "  +  " + item[0]
	btn.custom_minimum_size = Vector2(0, 80)
	btn.add_theme_font_size_override("font_size", 26)
	if item[1] == "speaker_cable":
		# Held for a second: choose its length and the colour of its plugs.
		var hold := HoldPress.attach(btn)
		hold.clicked.connect(spawn_requested.emit.bind(item[1]))
		hold.held.connect(_show_lead_spawn_options.bind(item[0], item[1]))
	elif item.size() > 2 and not (item[2] as Array).is_empty():
		# A thing that comes in several looks (a battery's labels), as a console
		# card's row does: pressed, the look its held panel made the default; held,
		# it asks which. Kept on the "power" card's key.
		var row := {"kind": "peripheral", "label": item[0], "spawn": item[1], "variants": item[2]}
		var looks: Array = item[2]
		var key := _default_key(POWER_CARD, item[1])
		var hold := HoldPress.attach(btn)
		hold.clicked.connect(func() -> void:
			spawn_requested.emit(SpawnCatalog.spawn_token(POWER_CARD, row, _row_default(key, looks))))
		hold.held.connect(_show_model_spawn_options.bind(POWER_CARD, row))
		_mark_holdable(btn, key, looks)
	else:
		btn.pressed.connect(spawn_requested.emit.bind(item[1]))
	return btn


## Keep the stock TVs, then offer every registered cabinet using the same
## "tv:<shell>" token as the plain monitor. The mods mounted at boot have
## registered by the time the menu is built; one mounted later is added by
## _populate_tvs_tab.
func _add_tv_spawn_tab(tabs: TabContainer) -> VBoxContainer:
	_tvs_vbox = _add_spawn_tab(tabs, "TVs", _tv_items())
	return _tvs_vbox


func _tv_items() -> Array:
	var items: Array = [["TV", "tv"], ["Plain Monitor", "tv:crt_plain"]]
	for shell: Dictionary in RetroTV.mod_shells():
		items.append([str(shell["label"]), "tv:" + str(shell["id"])])
	return items


func _populate_tvs_tab() -> void:
	if not is_instance_valid(_tvs_vbox):
		return
	_clear_vbox(_tvs_vbox)
	for item: Array in _tv_items():
		_tvs_vbox.add_child(_spawn_tab_button(item))


## Mods were mounted after the menu was built (ModManager.apply_live). The TVs
## tab was built once; the two grids and an open card are owed a rebuild, which
## pays when the tab is next on screen; and a mod's SystemInfo can change what a
## ROM folder scan finds.
func _on_mods_applied() -> void:
	_populate_tvs_tab()
	_invalidate_local_scan()
	refresh_after_core_change("")


## The virtual controllers, then a receiver per connected physical pad.
##
## A receiver is how a real gamepad reaches a console: plug one into a controller
## port and that port is driven by its pad, with nothing held. So the list has to
## follow what is actually paired right now, which is why this tab is rebuilt
## rather than authored like the others.
func _populate_controllers_tab() -> void:
	if not is_instance_valid(_controllers_vbox):
		return
	_clear_vbox(_controllers_vbox)
	_controllers_vbox.add_child(MenuStyle.spacer(10))
	for item: Array in [
			["Primitive Controller", "retro_controller"],
			["Light Gun",          "light_gun"],
			["Mouse",              "retro_mouse"],
			["Keyboard",           "retro_keyboard"],
			["Wiimote",            "wiimote"],
			["Nunchuk",            "nunchuk"],
			["Wii MotionPlus",     "motion_plus"]]:
		_controllers_vbox.add_child(_spawn_row(str(item[0]), str(item[1])))

	# The keyboard and mouse dongles, VR only. On desktop the real keyboard and
	# mouse ARE the player — WASD walks and mouse-look drags the virtual mouse —
	# so a dongle quietly forwarding them to a core would fight the controls you
	# are standing on, and there is nothing to gain: the point of a receiver is to
	# free the Quest controllers, and a desktop player has none.
	if MenuStyle.is_vr_mode():
		_controllers_vbox.add_child(_spawn_row("Keyboard Receiver", "keyboard_receiver"))
		_controllers_vbox.add_child(_spawn_row("Mouse Receiver", "mouse_receiver"))

	_controllers_vbox.add_child(HSeparator.new())
	_controllers_vbox.add_child(MenuStyle.header("DETECTED PADS", 20))
	var pads := GamepadBindings.usable_pads()
	if pads.is_empty():
		_controllers_vbox.add_child(MenuStyle.hint(
			"No gamepad connected. Pair one and it appears here."))
		return
	for device: int in pads:
		var id := GamepadBindings.identify_device(device)
		var label := "%s Receiver" % str(id["name"])
		var token := "pad_receiver:%s:%d" % [str(id["guid"]), int(id["ordinal"])]
		_controllers_vbox.add_child(_pad_receiver_row(label, token,
			str(id["guid"]), int(id["ordinal"])))


## The row for a pad's receiver. On a desktop the first pad is the PLAYER's (DesktopPad): a
## receiver for it makes it an external controller, so the first press asks before it spawns.
func _pad_receiver_row(label: String, token: String, guid: String, ordinal: int) -> Control:
	var box := VBoxContainer.new()
	var btn := _spawn_row(label, token)
	box.add_child(btn)
	var warn := VBoxContainer.new()
	warn.visible = false
	warn.add_child(MenuStyle.hint(
		"This is the controller you play with. A receiver for it treats it as an EXTERNAL "
		+ "controller: it stops moving you and working your hand until the receiver is put "
		+ "away. The keyboard does that meanwhile."))
	var buttons := HBoxContainer.new()
	var go := Button.new()
	go.text = "  Continue  "
	go.custom_minimum_size = Vector2(0, 64)
	go.add_theme_font_size_override("font_size", 24)
	var cancel := Button.new()
	cancel.text = "  Cancel  "
	cancel.custom_minimum_size = Vector2(0, 64)
	cancel.add_theme_font_size_override("font_size", 24)
	buttons.add_child(go)
	buttons.add_child(cancel)
	warn.add_child(buttons)
	box.add_child(warn)
	# Replaces the plain row's own press: it spawns at once only when nothing is at stake.
	for c in btn.pressed.get_connections():
		btn.pressed.disconnect(c["callable"])
	btn.pressed.connect(func() -> void:
		if DesktopPad.would_go_external(guid, ordinal):
			btn.visible = false
			warn.visible = true
		else:
			spawn_requested.emit(token))
	go.pressed.connect(func() -> void:
		warn.visible = false
		btn.visible = true
		spawn_requested.emit(token))
	cancel.pressed.connect(func() -> void:
		warn.visible = false
		btn.visible = true)
	return box


func _spawn_row(label: String, token: String) -> Button:
	var btn := Button.new()
	btn.text = "  +  " + label
	btn.custom_minimum_size = Vector2(0, 80)
	btn.add_theme_font_size_override("font_size", 26)
	btn.pressed.connect(spawn_requested.emit.bind(token))
	return btn


# ── Scraper ──────────────────────────────────────────────────────────────────
# The queue's outcomes and the review popup are SpawnScrapeUi's.

## A row's button reads the queue at bind time, so a change of state is a
## repaint of what is on screen and nothing more.
## One ROM's row, at the end of the frame, with any art that landed in it.
func _on_scrape_row_changed(rom_path: String, _systemid: String) -> void:
	_art_landed_stems[rom_path.get_file().get_basename()] = true
	_queue_art_flush()


# ── RomM notifications ────────────────────────────────────────────────────────
# The handlers are RommSpawnSync's; what is left here is when the menu is out,
# and the art that lands in the rows.

## Called when the menu panel becomes visible in the world.
func on_menu_shown() -> void:
	_menu_shown = true
	# Whatever changed while the menu was away, settled NOW rather than at the
	# end of the frame: a sync that finished meanwhile rewrote the index, and no
	# row may be bound against the old one's offsets first.
	_flush_owed()
	_romm_sync.on_menu_shown()



func on_menu_hidden() -> void:
	_menu_shown = false


func _on_romm_art_ready(rom_id: int, _texture: Texture2D) -> void:
	_art_landed_ids[rom_id] = true
	_queue_art_flush()


## A wheel or label finished decoding. The key is the art's own file,
## <rom dir>/media/<kind>/<rom stem>.<ext>, and the stem is what finds its row.
func _on_scraped_art_ready(key: String, _texture: Texture2D) -> void:
	_art_landed_stems[key.get_file().get_basename()] = true
	_queue_art_flush()


## Once the list has stopped moving, drop the cover fetches queued for rows that
## scrolled past. A fling through a platform binds every row it crosses, each
## bind queues its cover, and they would otherwise keep arriving — and keep being
## applied — long after the rows they were for were gone.
func _schedule_cover_prune() -> void:
	if _cover_prune_timer != null or not is_inside_tree():
		return
	_cover_prune_timer = get_tree().create_timer(0.3)
	_cover_prune_timer.timeout.connect(func() -> void:
		_cover_prune_timer = null
		if not is_instance_valid(_romm_list) or romm_art == null or romm_catalog == null:
			return
		var keep := PackedInt32Array()
		for i: int in _romm_list.visible_indices():
			if i < _romm_rows.size():
				var cat_index := int((_romm_rows[i] as Dictionary).get("index", -1))
				if cat_index >= 0:
					keep.append(romm_catalog.rom_id_at(cat_index))
		romm_art.cancel_outside(keep)
	)


func _queue_art_flush() -> void:
	if _art_flush_queued:
		return
	_art_flush_queued = true
	_flush_landed_art.call_deferred()


## Re-bind the rows on screen whose art landed this frame, and only those.
##
## The caches promote up to six textures a frame, and each one used to re-bind
## the whole window: ~100 row binds in one frame, each parsing its row's JSON
## and probing the disk for scraped art. 19 ms of a Quest 3 frame.
func _flush_landed_art() -> void:
	_art_flush_queued = false
	var ids := _art_landed_ids
	var stems := _art_landed_stems
	_art_landed_ids = {}
	_art_landed_stems = {}
	if not is_instance_valid(_romm_list) or romm_catalog == null:
		return
	for i: int in _romm_list.visible_indices():
		if i >= _romm_rows.size():
			continue
		var model: Dictionary = _romm_rows[i]
		# What _bind_rom_row asks the caches for: scraped art by the local
		# file's name, RomM covers by the row's rom id.
		var local_path := str(model.get("path", ""))
		var hit := not stems.is_empty() and not local_path.is_empty() \
			and stems.has(local_path.get_file().get_basename())
		if not hit and not ids.is_empty():
			var cat_index := int(model.get("index", -1))
			hit = cat_index >= 0 and ids.has(romm_catalog.rom_id_at(cat_index))
		if hit:
			_romm_list.rebind_index(i)


func _system_label(systemid: String) -> String:
	var sysname := core_db.get_systemname_for_id(systemid)
	return sysname if not sysname.is_empty() else systemid


func _show_game_detail_panel(game: Dictionary, systemid: String, local_path: String) -> void:
	_close_game_detail_panel()

	_game_detail_panel = PanelContainer.new()
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.1, 0.2, 0.98)
	for k in ["corner_radius_top_left","corner_radius_top_right",
			  "corner_radius_bottom_left","corner_radius_bottom_right"]:
		bg.set(k, 8)
	_game_detail_panel.add_theme_stylebox_override("panel", bg)
	_game_detail_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	for side in ["margin_top","margin_bottom","margin_left","margin_right"]:
		margin.add_theme_constant_override(side, 14)
	_game_detail_panel.add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	MenuStyle.fat_vscroll_bar(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = game.get("name", "Unknown")
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", MenuStyle.COLOR_TITLE)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	# Metadata
	SpawnScrapeUi.info_row(vbox, "Developer", game.get("developer", ""))
	SpawnScrapeUi.info_row(vbox, "Publisher", game.get("publisher", ""))
	SpawnScrapeUi.info_row(vbox, "Genre", game.get("genre", ""))
	SpawnScrapeUi.info_row(vbox, "File", local_path)
	# The FILE's region, not the game's: a game's variants differ in exactly this.
	var region := str(_rom_entry_for(game, local_path).get("region", ""))
	var flag := MenuIcons.region_flag(region)
	var region_lbl := SpawnScrapeUi.info_row(vbox, "Region",
		region if flag.is_empty() else "%s  %s" % [flag, region])
	if region_lbl != null:
		region_lbl.add_theme_font_override("font", MenuIcons.symbols())

	vbox.add_child(HSeparator.new())

	# Description
	var desc: String = game.get("desc", "")
	if not desc.is_empty():
		var desc_lbl := Label.new()
		desc_lbl.text = desc
		desc_lbl.add_theme_font_size_override("font_size", 16)
		desc_lbl.add_theme_color_override("font_color", MenuStyle.COLOR_LICENSE)
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(desc_lbl)
		vbox.add_child(HSeparator.new())

	# ROM variants button (if game has more than 1 ROM)
	var roms: Array = game.get("roms", [])
	if roms.size() > 1:
		var variants_btn := Button.new()
		variants_btn.text = "  ROM Variants (%d)  " % roms.size()
		variants_btn.custom_minimum_size = Vector2(0, 56)
		variants_btn.add_theme_font_size_override("font_size", 20)
		variants_btn.pressed.connect(_show_rom_variants_panel.bind(game, systemid))
		vbox.add_child(variants_btn)

	# Close button
	var close_btn := Button.new()
	close_btn.text = "  CLOSE  "
	close_btn.custom_minimum_size = Vector2(0, 56)
	close_btn.add_theme_font_size_override("font_size", 20)
	close_btn.pressed.connect(_close_game_detail_panel)
	vbox.add_child(close_btn)

	get_parent().add_child(_game_detail_panel)


func _close_game_detail_panel() -> void:
	_close_rom_variants_panel()
	if _game_detail_panel and is_instance_valid(_game_detail_panel):
		_game_detail_panel.queue_free()
	_game_detail_panel = null


# ── Hold sub-menu: what to spawn an entry AS ─────────────────────────────────
#
# A press held for a second (HoldPress) opens one of these instead of
# spawning. A full-rect overlay like the panels above and for the same reason:
# a PopupMenu is an embedded Window, and the second VR press dismisses it.


## Whether this platform's ROM rows open a sub-menu when held.
static func _has_spawn_options(systemid: String) -> bool:
	# A mod's shells: only when there is something to choose between.
	if ModCartShells.has(systemid):
		return ModCartShells.bodies(systemid).size() > 1 or ModCartShells.tintable(systemid)
	if systemid in ["n64", GbaCartShell.SYSTEMID, SnesCartShell.SYSTEMID, NesCartShell.SYSTEMID]:
		return true
	return GbCartShell.is_shell(systemid)


## The overlay's shell: a title with a close button, and the column to fill.
func _open_spawn_options_panel(title: String) -> VBoxContainer:
	_close_spawn_options_panel()
	_spawn_options_panel = PanelContainer.new()
	var bg := MenuStyle.rounded(Color(0.1, 0.1, 0.2, 1.0), 8)
	_spawn_options_panel.add_theme_stylebox_override("panel", bg)
	_spawn_options_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	for side in ["margin_top", "margin_bottom", "margin_left", "margin_right"]:
		margin.add_theme_constant_override(side, 14)
	_spawn_options_panel.add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	MenuStyle.fat_vscroll_bar(scroll)

	var vbox := MenuStyle.vbox(10)
	scroll.add_child(vbox)
	var row := MenuStyle.title_row(vbox, title, 24)
	MenuStyle.close_button(row, _close_spawn_options_panel)
	vbox.add_child(HSeparator.new())

	get_parent().add_child(_spawn_options_panel)
	return vbox


func _close_spawn_options_panel() -> void:
	if _spawn_options_panel and is_instance_valid(_spawn_options_panel):
		_spawn_options_panel.queue_free()
	_spawn_options_panel = null


## A button painted in the colour it stands for. `group` makes it one of a set
## of which the chosen one wears a bright border.
static func _swatch_button(text: String, color: Color, group: ButtonGroup = null) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 72)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 20)
	btn.clip_text = true
	_paint_swatch(btn, color)
	if group != null:
		btn.toggle_mode = true
		btn.button_group = group
	return btn


## A swatch's fill, chosen border and ink, which is black or white by how light
## the fill is. Split out so a swatch can follow a colour being mixed.
static func _paint_swatch(btn: Button, color: Color) -> void:
	var ink := Color.BLACK if color.get_luminance() > 0.45 else Color.WHITE
	for state in ["font_color", "font_hover_color", "font_pressed_color",
			"font_hover_pressed_color", "font_focus_color"]:
		btn.add_theme_color_override(state, ink)
	var chosen := MenuStyle.rounded(color, 8)
	chosen.set_border_width_all(5)
	chosen.border_color = Color(0.55, 0.75, 1.0)
	for state in ["normal", "hover", "focus"]:
		btn.add_theme_stylebox_override(state, MenuStyle.rounded(color, 8))
	for state in ["pressed", "hover_pressed"]:
		btn.add_theme_stylebox_override(state, chosen)


## Shell, and for an N64, Super NES or Game Boy the body, of a cartridge (an NES
## cartridge has one body, so only its shell: grey, or the Zelda gold). Picked
## and then SPAWN is pressed; `spawn` takes the options dictionary. The swatches are
## the colors of what `rom_path` will spawn as (_shell_palettes) -- the system's own
## CartridgeColor palette, a Game Boy or Game Boy Color cartridge both shells', the
## Game Boy Camera only its own -- then a colour the player mixes.
func _show_cart_spawn_options(systemid: String, label: String, spawn: Callable, rom_path := "") -> void:
	var vbox := _open_spawn_options_panel(label)
	var chosen := {"shell_preset": "", "shell_color": "", "shell_flake": false, "body_region": ""}
	var auto_color := Color(0.18, 0.18, 0.35)

	# A mod's shells are only offered colours when it said what they go on. Made
	# before the Body row, whose choice can turn a cartridge into a camera and so
	# refill the swatches.
	var shell_group := ButtonGroup.new()
	var auto_shell: Button = null
	var swatches: VBoxContainer = null
	if not ModCartShells.has(systemid) or ModCartShells.tintable(systemid):
		auto_shell = _swatch_button("Auto (from the ROM)", auto_color, shell_group)
		auto_shell.button_pressed = true
		auto_shell.pressed.connect(_pick_shell.bind(chosen, "", "", false))
		swatches = MenuStyle.vbox(10)

	# The first body is the default, and leaves body_region empty.
	var body_options: Array = []
	if ModCartShells.has(systemid):
		var mod_bodies := ModCartShells.bodies(systemid)
		if mod_bodies.size() > 1:
			body_options = [["Auto (from the ROM)", ""]]
			for mod_body: Dictionary in mod_bodies:
				body_options.append([str(mod_body["label"]), str(mod_body["id"])])
	elif systemid == "n64":
		body_options = [["Auto (from the ROM)", ""],
				["USA / PAL", N64CartShell.REGION_USA], ["Japan", N64CartShell.REGION_JPN]]
	elif systemid == SnesCartShell.SYSTEMID:
		body_options = [["Auto (from the ROM)", ""],
				["Type A (groove)", SnesCartShell.TYPE_A], ["Type B (recess)", SnesCartShell.TYPE_B],
				["Super Famicom / PAL", SnesCartShell.SFC]]
	elif GbCartShell.is_shell(systemid):
		body_options = [["Auto (from the ROM)", ""], ["Game Boy", GbcCartShell.BODY_GB],
				["Game Boy Color (clear)", GbcCartShell.BODY_GBC],
				["Game Boy Camera", GbCameraShell.BODY_CAMERA]]
	if not body_options.is_empty():
		vbox.add_child(MenuStyle.header("Body"))
		var bodies := MenuStyle.hbox(10)
		vbox.add_child(bodies)
		var body_group := ButtonGroup.new()
		for body: Array in body_options:
			var body_btn := _swatch_button(body[0], auto_color, body_group)
			body_btn.button_pressed = body[1] == ""
			body_btn.pressed.connect(func() -> void:
				chosen["body_region"] = body[1]
				if swatches != null:
					_fill_shell_swatches(swatches, systemid, rom_path, chosen, auto_shell))
			bodies.add_child(body_btn)

	if swatches != null:
		vbox.add_child(MenuStyle.header("Shell"))
		vbox.add_child(auto_shell)
		vbox.add_child(swatches)
		_fill_shell_swatches(swatches, systemid, rom_path, chosen, auto_shell)
		_add_custom_shell(vbox, shell_group, chosen)

	vbox.add_child(MenuStyle.spacer(6))
	var go := MenuStyle.row_button("  +  SPAWN", 26, 0, 80, false)
	go.add_theme_stylebox_override("normal", MenuStyle.rounded(MenuStyle.COLOR_BTN_DL, 8))
	go.pressed.connect(func() -> void:
		var options := {}
		for key: String in chosen:
			var value: Variant = chosen[key]
			if (value is bool and value) or (value is String and not value.is_empty()):
				options[key] = value
		_close_spawn_options_panel()
		spawn.call(options))
	vbox.add_child(go)


## The palettes a hold menu offers, [title, palette] each: the Game Boy Camera's
## own colors on a camera, and on a cartridge the system's, which for the game's
## Game Boy shells are both shells' (a swatch brings its shell's body). Never the
## camera's on a cartridge or a cartridge's on the camera.
static func _shell_palettes(systemid: String, camera: bool) -> Array:
	if camera:
		return [["Game Boy Camera", CartridgeColor.get_palette(GbCameraShell.PALETTE)]]
	if GbCartShell.is_shell(systemid) and not ModCartShells.has(systemid):
		return [["Game Boy", CartridgeColor.get_palette(GbCartShell.SYSTEMID)],
				["Game Boy Color", CartridgeColor.get_palette(GbcCartShell.PALETTE)]]
	# Null for a mod's shells that came with no colours of their own.
	var own := CartridgeColor.get_palette(systemid)
	return [["", own]] if own != null else []


## Whether a Game Boy ROM's hold menu spawns the camera with `body_region` forced:
## the camera's ROM left on Auto, or the camera's body chosen, the game's or a mod's.
static func _spawns_camera(systemid: String, rom_path: String, body_region: String) -> bool:
	if not GbCartShell.is_shell(systemid):
		return false
	var model := RetroCartridge.body_model_for(systemid, rom_path, body_region, &"")
	return model == GbCameraShell.BODY or model == RetroCartridge.camera_body_for(systemid)


## A hold menu's shell swatches, into `box`, for what `chosen` spawns. Asked again
## on every Body pick, and refilled only when it turns a cartridge into the camera
## or back; a swatch that goes with the old ones gives the choice back to Auto.
static func _fill_shell_swatches(box: VBoxContainer, systemid: String, rom_path: String,
		chosen: Dictionary, auto_shell: Button) -> void:
	var camera := _spawns_camera(systemid, rom_path, str(chosen["body_region"]))
	if box.has_meta(&"camera") and bool(box.get_meta(&"camera")) == camera:
		return
	box.set_meta(&"camera", camera)
	if not str(chosen["shell_preset"]).is_empty():
		auto_shell.button_pressed = true
		_pick_shell(chosen, "", "", false)
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	for entry: Array in _shell_palettes(systemid, camera):
		var palette: CartridgeShellPalette = entry[1]
		for section: Array in [
				["Standard", CartridgeShellPreset.Availability.STANDARD],
				["Released", CartridgeShellPreset.Availability.RELEASED],
				# Offered by Nintendo and never used: listed after the released ones,
				# untitled.
				["", CartridgeShellPreset.Availability.OFFERED_ONLY]]:
			var presets := palette.with_availability(section[1])
			if presets.is_empty():
				continue
			var title: String = section[0]
			if not entry[0].is_empty() and not title.is_empty():
				title = "%s, %s" % [entry[0], title.to_lower()]
			if not title.is_empty():
				box.add_child(MenuStyle.hint(title))
			var grid := GridContainer.new()
			grid.columns = 4
			grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			grid.add_theme_constant_override("h_separation", 10)
			grid.add_theme_constant_override("v_separation", 10)
			box.add_child(grid)
			for preset: CartridgeShellPreset in presets:
				# A two-tone shell is shown by its front half, the one facing the player.
				var shown := palette.find(preset.front) if preset.is_two_tone() else preset
				var swatch := _swatch_button(preset.display_name,
					(shown if shown != null else preset).color, auto_shell.button_group)
				swatch.pressed.connect(_pick_shell.bind(chosen, String(preset.id), "", false))
				grid.add_child(swatch)


## One shell choice replaces the last: a preset id, or a mixed "#rrggbb" and
## whether it is metal flake. Empty preset and colour is Auto.
static func _pick_shell(chosen: Dictionary, preset: String, color: String, flake: bool) -> void:
	chosen["shell_preset"] = preset
	chosen["shell_color"] = color
	chosen["shell_flake"] = flake


## A colour of the player's own: a swatch in the shell group wearing it, and
## below it a colour wheel with the hue, saturation and brightness sliders and a
## Metal flakes switch beside it. The wheel shows hue and saturation at a glance
## and picks both in one drag; the sliders set each exactly, and the two follow
## each other. Not Godot's ColorPicker, whose wheel and fields are sized for a
## mouse, whose hex field wants a keyboard, and whose eyedropper cannot see out of
## a headset. Touching any of them picks the swatch; so does pressing it.
func _add_custom_shell(vbox: VBoxContainer, shell_group: ButtonGroup, chosen: Dictionary) -> void:
	vbox.add_child(MenuStyle.hint("Custom"))
	var swatch := _swatch_button("", CUSTOM_SHELL_START, shell_group)
	swatch.name = "ShellCustom"
	vbox.add_child(swatch)
	var mixer := MenuStyle.hbox(28)
	vbox.add_child(mixer)
	var wheel := HsvWheel.create(CUSTOM_SHELL_WHEEL)
	wheel.name = "ShellWheel"
	mixer.add_child(wheel)
	var controls := MenuStyle.vbox(10)
	mixer.add_child(controls)
	var sliders: Array[HSlider] = []
	var readouts: Array[Label] = []
	for row: Array in [["Hue", "ShellHue", 359.0, CUSTOM_SHELL_START.h * 360.0],
			["Saturation", "ShellSaturation", 100.0, CUSTOM_SHELL_START.s * 100.0],
			["Brightness", "ShellBrightness", 100.0, CUSTOM_SHELL_START.v * 100.0]]:
		var parts := MenuStyle.menu_slider_row(controls, row[0], 0.0, row[2], 1.0)
		var slider: HSlider = parts[0]
		slider.name = row[1]
		slider.value = row[3]
		sliders.append(slider)
		readouts.append(parts[1])
	var flake := MenuStyle.switch_row(controls, "Metal flakes", false, 22, 56)
	flake.name = "ShellFlake"

	var refresh := func(pick: bool) -> void:
		var c := Color.from_hsv(sliders[0].value / 360.0, sliders[1].value / 100.0,
			sliders[2].value / 100.0)
		var hex := "#" + c.to_html(false)
		_paint_swatch(swatch, c)
		swatch.text = "Custom  %s%s" % [hex, "  metal flakes" if flake.button_pressed else ""]
		wheel.set_hsv(sliders[0].value / 360.0, sliders[1].value / 100.0, sliders[2].value / 100.0)
		readouts[0].text = "%d°" % int(sliders[0].value)
		readouts[1].text = "%d%%" % int(sliders[1].value)
		readouts[2].text = "%d%%" % int(sliders[2].value)
		if pick:
			# Setting button_pressed moves the group's choice without emitting
			# `pressed`, so the choice is recorded here too.
			swatch.button_pressed = true
			_pick_shell(chosen, "", hex, flake.button_pressed)
	refresh.call(false)
	for slider in sliders:
		slider.value_changed.connect(func(_v: float) -> void: refresh.call(true))
	flake.toggled.connect(func(_on: bool) -> void: refresh.call(true))
	swatch.pressed.connect(func() -> void: refresh.call(true))
	# The wheel sets the two sliders it covers. A pick that leaves both where they
	# were changes neither, so it picks the swatch itself.
	wheel.picked.connect(func(h: float, s: float) -> void:
		sliders[0].value = h * 360.0
		sliders[1].value = s * 100.0
		refresh.call(true))


## Which of its colors to spawn a console in: one swatch for each of the
## `variants` its row lists (SystemModelRegistry), painted in that variant's own
## color. It opens on the first, which is the console as a plain press spawns
## it, and picking that one asks for nothing: the token then names no color, so
## the save records none.
##
## It opens on the row's default, and MAKE DEFAULT makes the color picked what a
## plain press of the row spawns from then on. `base` is the token a color is
## asked of when it is not the row's own: a card row's is "memory_card", and a
## new card is its console's family's, "<family>_memory_card".
func _show_model_spawn_options(systemid: String, item: Dictionary, base: String = "") -> void:
	var vbox := _open_spawn_options_panel(str(item.get("label", "Console")))
	var variants: Array = item.get("variants", [])
	var row_token := _default_key(systemid, SpawnCatalog.spawn_token(systemid, item))
	var chosen := {"variant": _row_default(row_token, variants)}

	vbox.add_child(MenuStyle.header("Color"))
	var group := ButtonGroup.new()
	var grid := GridContainer.new()
	grid.name = "Variants"
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	vbox.add_child(grid)
	for i in variants.size():
		var variant: Dictionary = variants[i]
		var id := str(variant.get("id", ""))
		var swatch := _swatch_button(str(variant.get("label", id)),
			SystemModelRegistry.variant_color(variant), group)
		var asked := "" if i == 0 else id
		swatch.button_pressed = asked == chosen["variant"]
		grid.add_child(swatch)

	vbox.add_child(MenuStyle.spacer(6))
	var make_default := MenuStyle.row_button("  MAKE DEFAULT", 22, 0, 64, false)
	make_default.name = "MakeDefault"
	var show_default := func() -> void:
		var is_default: bool = chosen["variant"] == _row_default(row_token, variants)
		make_default.disabled = is_default
		make_default.text = "  DEFAULT FOR THIS ROW" if is_default else "  MAKE DEFAULT"
	show_default.call()
	for i in grid.get_child_count():
		var asked := "" if i == 0 else str((variants[i] as Dictionary).get("id", ""))
		(grid.get_child(i) as Button).pressed.connect(func() -> void:
			chosen["variant"] = asked
			show_default.call())
	make_default.pressed.connect(func() -> void:
		AppPrefs.set_spawn_default(row_token, _kept_default(chosen["variant"], variants))
		show_default.call()
		# The row behind the panel shows the new default's swatch.
		if _systems_browser != null:
			_systems_browser.refresh_detail())
	vbox.add_child(make_default)
	var go := MenuStyle.row_button("  +  SPAWN", 26, 0, 80, false)
	go.name = "SpawnVariant"
	go.add_theme_stylebox_override("normal", MenuStyle.rounded(MenuStyle.COLOR_BTN_DL, 8))
	go.pressed.connect(func() -> void:
		var variant: String = chosen["variant"]
		_close_spawn_options_panel()
		spawn_requested.emit(_in_color(base, variant) if not base.is_empty()
			else SpawnCatalog.spawn_token(systemid, item, variant)))
	vbox.add_child(go)


## How long a lead is and what colour its plugs are. Two choices, so they are
## picked and then SPAWN is pressed -- the same shape as the cartridge panel above,
## and the reason this one no longer spawns on the first tap.
##
## Both groups OPEN ON WHAT THE LEAD ALREADY IS (3 m, grey plugs) and picking
## those forces nothing. There is no "Default" button in either group: it would be
## a second button for an outcome already on screen, differing only in whether the
## save records a field, which a player cannot see and should not be asked about.
func _show_lead_spawn_options(label: String, token: String) -> void:
	var vbox := _open_spawn_options_panel(label)
	var chosen := {"color": String(CompositeCable.SHIPPED_PLUG_COLOR),
		"length": CompositeCable.SHIPPED_LENGTH}
	var plain := Color(0.18, 0.18, 0.35)

	vbox.add_child(MenuStyle.header("Length"))
	var lengths := MenuStyle.hbox(10)
	vbox.add_child(lengths)
	var length_group := ButtonGroup.new()
	for row: Array in CompositeCable.SPAWN_LENGTHS:
		var length_btn := _swatch_button(row[1], plain, length_group)
		length_btn.button_pressed = row[0] == CompositeCable.SHIPPED_LENGTH
		length_btn.pressed.connect(func() -> void: chosen["length"] = row[0])
		lengths.add_child(length_btn)

	vbox.add_child(MenuStyle.header("Plug color"))
	var color_group := ButtonGroup.new()
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	vbox.add_child(grid)
	for id: StringName in RcaJack.PLUG_COLORS:
		var swatch := _swatch_button(RcaJack.PLUG_COLORS[id][0], RcaJack.PLUG_COLORS[id][1],
			color_group)
		swatch.button_pressed = id == CompositeCable.SHIPPED_PLUG_COLOR
		swatch.pressed.connect(func() -> void: chosen["color"] = String(id))
		grid.add_child(swatch)

	vbox.add_child(MenuStyle.spacer(6))
	var go := MenuStyle.row_button("  +  SPAWN", 26, 0, 80, false)
	go.add_theme_stylebox_override("normal", MenuStyle.rounded(MenuStyle.COLOR_BTN_DL, 8))
	go.pressed.connect(func() -> void:
		# An empty field is "the lead's own" at the other end, so the two choices the
		# menu opened on send nothing rather than pinning a value that merely happens
		# to match the scene -- a player who only changed the colour does not also
		# fix the length.
		var metres: float = chosen["length"]
		var colour: String = chosen["color"]
		_close_spawn_options_panel()
		spawn_requested.emit("%s:%s:%s" % [token,
			"" if colour == CompositeCable.SHIPPED_PLUG_COLOR else colour,
			"" if is_equal_approx(metres, CompositeCable.SHIPPED_LENGTH) else str(metres)]))
	vbox.add_child(go)


## A game's saves and achievements, without going and finding the cartridge.
##
## The page IS the cartridge menu's — an embedded CartridgeOptions2D driven by a
## CartridgeOptionsPanel — so save recovery, RomM sync and the achievement list
## behave here exactly as they do there, and are written once.
##
## What it is pointed at depends on the room: the actual cartridge when one for
## this ROM has been spawned, so choosing a save binds it the way it always did;
## otherwise a CartridgeSaveTarget standing in for the ROM, which reads and syncs
## but has nothing to bind to.
func _show_game_saves_panel(systemid: String, rom_path: String, label: String) -> void:
	_close_game_saves_panel()

	_game_saves_panel = PanelContainer.new()
	var bg := StyleBoxFlat.new()
	# Opaque: a list of save timestamps with the library's rows showing through it
	# is unreadable, and this page covers the whole content area.
	bg.bg_color = Color(0.1, 0.1, 0.2)
	for k in ["corner_radius_top_left", "corner_radius_top_right",
			  "corner_radius_bottom_left", "corner_radius_bottom_right"]:
		bg.set(k, 8)
	_game_saves_panel.add_theme_stylebox_override("panel", bg)
	_game_saves_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	for side in ["margin_top", "margin_bottom", "margin_left", "margin_right"]:
		margin.add_theme_constant_override(side, 14)
	_game_saves_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var ui := CartridgeOptions2D.create_embedded()
	vbox.add_child(ui)

	var close_btn := Button.new()
	close_btn.text = "  CLOSE  "
	close_btn.custom_minimum_size = Vector2(0, 56)
	close_btn.add_theme_font_size_override("font_size", 20)
	close_btn.pressed.connect(_close_game_saves_panel)
	vbox.add_child(close_btn)

	get_parent().add_child(_game_saves_panel)

	# The driver goes in the page, so closing the page takes it with it. It is a
	# bare CartridgeOptionsPanel — no quad of its own, external UI only.
	_game_saves_driver = CartridgeOptionsPanel.new()
	_game_saves_panel.add_child(_game_saves_driver)
	var target: Object = _spawned_cartridge_for(rom_path)
	if target == null:
		target = CartridgeSaveTarget.create(systemid, rom_path, label)
	_game_saves_driver.adopt_external_ui(ui, target)


## The cartridge in the room holding this ROM, or null.
func _spawned_cartridge_for(rom_path: String) -> RetroCartridge:
	if rom_path.is_empty():
		return null
	for n: Node in get_tree().get_nodes_in_group("cartridge"):
		var cart := n as RetroCartridge
		if cart != null and cart.rom_path == rom_path:
			return cart
	return null


func _close_game_saves_panel() -> void:
	if _game_saves_panel and is_instance_valid(_game_saves_panel):
		_game_saves_panel.queue_free()
	_game_saves_panel = null
	_game_saves_driver = null


## What is written on a memory pack, without spawning it first.
##
## The same BsxPackContents2D the in-world panel floats beside the pack, embedded
## here — one list, two ways of reaching it. No driver object: unlike the saves
## page, which needs a CartridgeOptionsPanel to act on a real cartridge, a pack
## listing is read straight out of the file and acts on nothing.
func _show_pack_contents_panel(pack_path: String) -> void:
	_close_pack_contents_panel()

	_pack_contents_panel = PanelContainer.new()
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.1, 0.2)
	_pack_contents_panel.add_theme_stylebox_override("panel", bg)
	_pack_contents_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	_pack_contents_panel.add_child(margin)

	var col := MenuStyle.vbox(10)
	margin.add_child(col)

	var ui := BsxPackContents2D.create_embedded()
	ui.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(ui)

	var close := MenuStyle.row_button("  CLOSE  ", 22, 0, 56, false)
	close.pressed.connect(_close_pack_contents_panel)
	col.add_child(close)

	get_parent().add_child(_pack_contents_panel)

	# After the tree add: populate() walks the node it built in _ready().
	var data := FileAccess.get_file_as_bytes(pack_path)
	ui.populate(pack_path.get_file().get_basename(),
		BsxPack.programmes_of(data),
		BsxPack.free_blocks(data),
		BsxPack.BLOCK_COUNT)


func _close_pack_contents_panel() -> void:
	if _pack_contents_panel and is_instance_valid(_pack_contents_panel):
		_pack_contents_panel.queue_free()
	_pack_contents_panel = null


func _show_rom_variants_panel(game: Dictionary, systemid: String) -> void:
	_close_rom_variants_panel()

	_rom_variants_panel = PanelContainer.new()
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.12, 0.12, 0.22, 0.98)
	for k in ["corner_radius_top_left","corner_radius_top_right",
			  "corner_radius_bottom_left","corner_radius_bottom_right"]:
		bg.set(k, 8)
	_rom_variants_panel.add_theme_stylebox_override("panel", bg)
	_rom_variants_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	for side in ["margin_top","margin_bottom","margin_left","margin_right"]:
		margin.add_theme_constant_override(side, 14)
	_rom_variants_panel.add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	MenuStyle.fat_vscroll_bar(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(vbox)

	vbox.add_child(MenuStyle.label("ROM VARIANTS", 22, MenuStyle.COLOR_TITLE))
	vbox.add_child(HSeparator.new())

	var game_id: String = game.get("game_id", "")
	var roms: Array = game.get("roms", [])

	for rom: Dictionary in roms:
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.custom_minimum_size = Vector2(0, 64)

		# Star (preferred) button
		var is_preferred: bool = rom.get("preferred", false)
		var star_btn := Button.new()
		star_btn.text = "⭐" if is_preferred else "☆"
		star_btn.custom_minimum_size = Vector2(56, 56)
		star_btn.add_theme_font_size_override("font_size", 22)
		var rom_path_rel: String = rom.get("path", "")
		star_btn.pressed.connect(func():
			gamelist_manager.set_preferred_rom(systemid, game_id, rom_path_rel)
			gamelist_manager.save_gamelist(systemid)
			gamelist_manager.invalidate(systemid)
			var updated_game := _find_game_by_id(systemid, game_id)
			if not updated_game.is_empty():
				# The info page underneath describes the starred FILE, so it is
				# rebuilt too, and first: showing it closes this panel, and the
				# later child is the one drawn on top.
				if _game_detail_panel != null:
					_show_game_detail_panel(updated_game, systemid,
						GamelistManager.to_absolute_path(systemid, rom_path_rel))
				_show_rom_variants_panel(updated_game, systemid)
			_populate_cartridges_tab()
		)
		row.add_child(star_btn)

		# ROM name / wheel
		var rom_btn := Button.new()
		rom_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rom_btn.custom_minimum_size = Vector2(0, 56)
		rom_btn.add_theme_font_size_override("font_size", 18)

		var romname: String = rom.get("romname", "")
		var wheel_tex := _load_wheel_texture(systemid, romname)
		if wheel_tex:
			rom_btn.icon = wheel_tex
			rom_btn.text = ""
			rom_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
			rom_btn.expand_icon = true
		else:
			rom_btn.text = romname.get_basename()

		var abs_path := GamelistManager.to_absolute_path(systemid, rom.get("path", ""))
		var rom_label := romname.get_basename()
		var rom_spawn := func(options: Dictionary) -> void:
			spawn_cartridge_requested.emit(abs_path, rom_label, systemid, options)
		var rom_hold := HoldPress.attach(rom_btn)
		rom_hold.hold_enabled = _has_spawn_options(systemid)
		rom_hold.clicked.connect(rom_spawn.bind({}))
		rom_hold.held.connect(_show_cart_spawn_options.bind(systemid, rom_label, rom_spawn, abs_path))

		# Which disc this file is, in the title's bottom-right corner: a game's
		# discs share one wheel, so the rows are otherwise identical.
		var disc_text := MenuIcons.disc_badge(MenuIcons.disc_number(romname))
		if not disc_text.is_empty():
			var disc_lbl := Label.new()
			disc_lbl.name = "Disc"
			disc_lbl.text = disc_text
			disc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			disc_lbl.add_theme_font_override("font", MenuIcons.symbols())
			disc_lbl.add_theme_font_size_override("font_size", 28)
			disc_lbl.add_theme_color_override("font_color", MenuStyle.COLOR_TITLE)
			disc_lbl.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
			disc_lbl.grow_horizontal = Control.GROW_DIRECTION_BEGIN
			disc_lbl.grow_vertical = Control.GROW_DIRECTION_BEGIN
			disc_lbl.offset_left = -10
			disc_lbl.offset_right = -10
			disc_lbl.offset_top = -4
			disc_lbl.offset_bottom = -4
			rom_btn.add_child(disc_lbl)

		row.add_child(rom_btn)

		# Region: its flag, or the word for a region that has none
		var region_str: String = rom.get("region", "")
		if not region_str.is_empty():
			var region_lbl := Label.new()
			var flag := MenuIcons.region_flag(region_str)
			if flag.is_empty():
				region_lbl.text = region_str
				region_lbl.add_theme_font_size_override("font_size", 14)
				region_lbl.add_theme_color_override("font_color", MenuStyle.COLOR_LICENSE)
			else:
				region_lbl.text = flag
				region_lbl.add_theme_font_override("font", MenuIcons.flags_font())
				region_lbl.add_theme_font_size_override("font_size", 30)
			region_lbl.custom_minimum_size = Vector2(50, 0)
			region_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			region_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			row.add_child(region_lbl)

		# Manual button
		if _has_scraped_manual(systemid, romname):
			var manual_btn := Button.new()
			manual_btn.text = "📖"
			manual_btn.custom_minimum_size = Vector2(56, 56)
			manual_btn.add_theme_font_size_override("font_size", 22)
			var pdf_path := RomLibrary.scraped_manual_path(systemid, romname)
			manual_btn.pressed.connect(spawn_manual_requested.emit.bind(pdf_path))
			row.add_child(manual_btn)

		# Spawn, last so it lines up down the right edge whatever a row lacks.
		# The title spawns too, but nothing about a logo says so.
		var spawn_btn := Button.new()
		spawn_btn.name = "Spawn"
		spawn_btn.text = " SPAWN "
		spawn_btn.custom_minimum_size = Vector2(110, 56)
		spawn_btn.add_theme_font_size_override("font_size", 18)
		var spawn_hold := HoldPress.attach(spawn_btn)
		spawn_hold.hold_enabled = _has_spawn_options(systemid)
		spawn_hold.clicked.connect(rom_spawn.bind({}))
		spawn_hold.held.connect(_show_cart_spawn_options.bind(systemid, rom_label, rom_spawn, abs_path))
		row.add_child(spawn_btn)

		vbox.add_child(row)

	vbox.add_child(HSeparator.new())

	var close_btn := Button.new()
	close_btn.text = "  CLOSE  "
	close_btn.custom_minimum_size = Vector2(0, 56)
	close_btn.add_theme_font_size_override("font_size", 20)
	close_btn.pressed.connect(_close_rom_variants_panel)
	vbox.add_child(close_btn)

	get_parent().add_child(_rom_variants_panel)


func _close_rom_variants_panel() -> void:
	if _rom_variants_panel and is_instance_valid(_rom_variants_panel):
		_rom_variants_panel.queue_free()
	_rom_variants_panel = null


func _load_wheel_texture(systemid: String, romname: String) -> Texture2D:
	if romname.is_empty():
		return null
	var base := romname.get_basename()
	var media_dir := RomLibrary.rom_dir_for_system(systemid).path_join("media/wheel")
	# Try common image extensions
	for ext in [".png", ".jpg", ".jpeg", ".webp"]:
		var path := media_dir.path_join(base + ext)
		if FileAccess.file_exists(path):
			var img := Image.load_from_file(path)
			if img:
				_fit_within(img, WHEEL_BOX)
				return ImageTexture.create_from_image(img)
	return null


## Scale an image down to fit a box, preserving aspect.
##
## Wheel logos are full-res (600x300 is typical) and were drawn via expand_icon,
## which scales them to a button far wider than it is tall — so the logo rendered
## much larger than its 100 px row and spilled across the boundary into the rows
## either side. Bounding the texture keeps it inside the row whatever its aspect;
## icon_max_width alone caps width only, which cannot bound a square-ish logo.
## (Measured: expand_icon does NOT inflate the button's minimum height, so this
## was a drawing-size problem, not a layout one.)
static func _fit_within(img: Image, box: Vector2i) -> void:
	var w := img.get_width()
	var h := img.get_height()
	if w <= 0 or h <= 0 or (w <= box.x and h <= box.y):
		return
	var factor: float = minf(float(box.x) / float(w), float(box.y) / float(h))
	img.resize(maxi(1, int(round(w * factor))), maxi(1, int(round(h * factor))),
		Image.INTERPOLATE_LANCZOS)


func _populate_posters_tab() -> void:
	if not _posters_vbox:
		return
	_clear_vbox(_posters_vbox)
	var posters := RomLibrary.scan_posters()
	if posters.is_empty():
		var hint := Label.new()
		hint.text = "No images found in posters folder."
		hint.add_theme_color_override("font_color", MenuStyle.COLOR_DESC)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_posters_vbox.add_child(hint)
		return
	for poster: Dictionary in posters:
		var btn := Button.new()
		btn.text = "  " + str(poster["label"])
		btn.custom_minimum_size = Vector2(0, 84)
		btn.add_theme_font_size_override("font_size", 24)
		var thumb := _cached_poster_thumb(str(poster["path"]))
		if thumb != null:
			btn.icon = thumb
			btn.add_theme_constant_override("icon_max_width", POSTER_THUMB_BOX.x)
		else:
			btn.text = "  🖼  " + str(poster["label"])
		btn.pressed.connect(spawn_poster_requested.emit.bind(poster["path"]))
		_add_media_row(_posters_vbox, btn, poster["path"], RomLibrary.default_posters_root())
	_posters_vbox.add_child(MenuStyle.spacer(8))


## Memoized, misses included — a folder of large images would otherwise be decoded
## again on every tab entry.
func _cached_poster_thumb(path: String) -> Texture2D:
	if _poster_thumb_cache.has(path):
		return _poster_thumb_cache[path]
	var tex := _load_poster_thumb(path)
	_poster_thumb_cache[path] = tex
	_poster_thumb_order.append(path)
	while _poster_thumb_order.size() > MAX_POSTER_THUMBS:
		_poster_thumb_cache.erase(_poster_thumb_order.pop_front())
	return tex


## No mipmaps: this is a 2D icon drawn at one size, not print art on a wall.
func _load_poster_thumb(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(path)
	if img == null:
		return null
	_fit_within(img, POSTER_THUMB_BOX)
	return ImageTexture.create_from_image(img)


func _has_scraped_manual(systemid: String, romname: String) -> bool:
	if romname.is_empty():
		return false
	return FileAccess.file_exists(RomLibrary.scraped_manual_path(systemid, romname))


func _find_game_by_id(systemid: String, game_id: String) -> Dictionary:
	var gamelist := gamelist_manager.load_gamelist(systemid)
	for g: Dictionary in gamelist.get("games", []):
		if g.get("game_id", "") == game_id:
			return g
	return {}
