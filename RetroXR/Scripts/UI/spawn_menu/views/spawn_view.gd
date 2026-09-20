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
##  * the ScreenScraper client's UI — hashing a ROM, showing what came back,
##    and the game-detail and ROM-variants panels built from it;
##  * the RomM handlers — sync, download, cache. They read as notification code
##    but every one of them ends by rebuilding a row, a list or an index here.
class_name SpawnMenuSpawnView
extends Control

signal spawn_requested(type: String)
## `options` is what the hold sub-menu forced -- "shell_preset", "body_region" --
## and empty for a plain click.
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
## Poster row thumbnails. Bounded for the same reason WHEEL_BOX is: an unbounded
## Button.icon with expand_icon draws far past its row and spills into the
## neighbours.
const POSTER_THUMB_BOX := Vector2i(96, 72)
const MAX_POSTER_THUMBS := 200
## Typing in the ROM filter rebuilds the list; this waits for a pause first.
const SEARCH_DEBOUNCE_SEC := 0.18

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
## Terminal outcomes that happened while the menu was closed, flushed on open.
var _romm_pending_notices: Array[Dictionary] = []
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
## rom_id -> percent, so a recycled row can show live progress when it scrolls
## back into view mid-download.
var _romm_progress_pct: Dictionary = {}
## rom_id -> game name, remembered from the start of the download. Only the
## started signal carries it, and looking it up again per tick would mean a
## catalog scan thousands of times over one ROM — the same reason the row index
## below is resolved once.
var _romm_dl_labels: Dictionary = {}
## rom_id -> which attempt is running, 0 for the first. Shown on the progress bar
## so a transfer that silently started over is visible as one.
var _romm_dl_attempt: Dictionary = {}
## Row index of the in-flight download, resolved once when it starts.
var _romm_dl_row_index: int = -1
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
## Poster thumbnails, memoized with misses — most entries have no thumbnail.
var _poster_thumb_cache: Dictionary = {}
var _poster_thumb_order: Array[String] = []
## systemid -> {lowercase basename: rom}. A directory listing, so it is cached
## and dropped whenever something writes to a ROM dir.
var _local_scan_cache: Dictionary = {}

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
var _books_vbox: VBoxContainer = null
var _videos_vbox: VBoxContainer = null
var _dvds_vbox: VBoxContainer = null
var _cds_vbox: VBoxContainer = null
var _tapes_vbox: VBoxContainer = null
var _records_vbox: VBoxContainer = null
var _posters_vbox: VBoxContainer = null

# ── Scraper / detail panels ───────────────────────────────────────────────────
var _scrape_popup: PanelContainer = null
## Coalesces the repopulate a batch of accepted scrapes asks for: forty
## results landing in a second must not rebuild the page forty times.
var _scrape_refresh_timer: SceneTreeTimer = null
var _game_detail_panel: PanelContainer = null
# The hold sub-menu: what to spawn an entry AS. One at a time.
var _spawn_options_panel: PanelContainer = null
var _rom_variants_panel: PanelContainer = null
## The saves-and-achievements page for one ROM, and the CartridgeOptionsPanel
## driving it — both live only as long as the page is open.
var _game_saves_panel: PanelContainer = null
var _game_saves_driver: CartridgeOptionsPanel = null
var _pack_contents_panel: PanelContainer = null
## Connected to scraper_client.media_download_completed so the tab refreshes
## when a wheel image or manual PDF finishes downloading.
var _media_dl_refresh_cb: Callable = Callable()

## Driven by the menu, which hears it from the controller — this Control is
## always visible, it is the Viewport2Din3D in the world that gets toggled.
var _menu_shown: bool = false

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
	return v


## The RomM services are the menu's, but every one of these handlers ends by
## rebuilding a row, a list or an index in this view — so the wiring lives here.
func _connect_romm() -> void:
	romm_client.auth_failed.connect(_on_romm_auth_failed)
	romm_client.reachability_changed.connect(_on_romm_reachability_changed)
	romm_cache.changed.connect(_on_romm_cache_changed)
	romm_catalog.sync_started.connect(_on_romm_sync_started)
	romm_catalog.sync_progress.connect(_on_romm_sync_progress)
	romm_catalog.sync_finished.connect(_on_romm_sync_finished)
	romm_catalog.sync_aborted.connect(_on_romm_sync_aborted)
	# The warm thread works out a platform's shown count after the grid is
	# already up, so the tile it belongs to has to be redrawn.
	romm_catalog.index_stats_ready.connect(func(_sid: String) -> void:
		_populate_cartridges_tab()
	)
	romm_downloader.download_started.connect(_on_romm_dl_started)
	romm_downloader.download_progress.connect(_on_romm_dl_progress)
	romm_downloader.download_retrying.connect(_on_romm_dl_retrying)
	romm_downloader.download_finished.connect(_on_romm_dl_finished)
	romm_downloader.download_cancelled.connect(_on_romm_dl_cancelled)
	romm_downloader.cache_evicted.connect(_on_romm_cache_evicted)
	romm_art.art_ready.connect(_on_romm_art_ready)
	if scraped_art != null:
		scraped_art.art_ready.connect(_on_scraped_art_ready)
	if scrape_queue != null:
		scrape_queue.started.connect(_on_scrape_row_changed)
		scrape_queue.completed.connect(_on_scrape_completed)
		scrape_queue.failed.connect(_on_scrape_failed)
		scrape_queue.media_downloaded.connect(_on_scrape_media_downloaded)
	# Show last run's platforms immediately; a refresh only corrects it.
	for sid: String in romm_config.cached_platforms:
		var p: Variant = romm_config.cached_platforms[sid]
		if p is Dictionary:
			_romm_platforms[sid] = p


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
	default_core_changed.connect(func(_sid: String, _cn: String): refresh_after_core_change())

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
	# Its own browser owns the scroll, so this slot stays empty — see
	# _update_spawn_active_scroll.
	_spawn_tab_scrolls.append(null)
	_populate_cartridges_tab()

	# "tv:<shell>" names a cabinet variant, the way "model:<systemid>:<model_id>"
	# names a console's. A future shell costs a row here and nothing else.
	_add_spawn_tab(tabs, "TVs", [["TV", "tv"], ["Plain Monitor", "tv:crt_plain"]])

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

	_add_spawn_tab(tabs, "Objects", [
		["Table",           "table"],
		["Storage Box",     "trash_can"],
		["VCR",             "vcr_player"],
		["DVD Player",      "dvd_player"],
		["CD Player",       "cd_player"],
		["Cassette Player", "cassette_player"],
		["Record Player",   "record_player"],
		["TV Remote",       "tv_remote"],
		["Composite Cable", "composite_cable"],
		["Mono Composite Cable", "mono_composite_cable"],
		["VGA Cable",       "vga_cable"],
		["3.5 mm Cable",   "trs_cable"],
		["Link Cable",     "link_cable"],
		["GB Link Cable",  "gb_link_cable"],
		["GC-GBA Cable",   "gc_gba_cable"],
		["PS Link Cable",  "psx_link_cable"],
		["Speakers",       "speaker_pair"],
		# A surround rig: a satellite per channel and one subwoofer, each cabled to
		# a socket on the back of the set with a speaker lead.
		["Loudspeaker",    "loudspeaker"],
		["Subwoofer",      "subwoofer"],
		# Floor stands, so a satellite is at ear height instead of on the carpet.
		# The height named is to the plate a cabinet stands on.
		["Speaker Stand 1.2m", "speaker_stand_120"],
		["Speaker Stand 1m",   "speaker_stand_100"],
		["Speaker Cable",  "speaker_cable"],
		# Not under Controllers: nobody holds it, and it is no more a controller
		# than the aerial is. It plugs into the Wii and stands on the television.
		["Sensor Bar",     "sensor_bar"],
		# The way a console reached a television before anything had a composite
		# input: phono into the deck, coax into the aerial socket.
		["RF Switch (RXR-003)", "rf_switch"],
		# Broadcast television: its lead goes in a set's aerial socket, or in the
		# ANT socket of the switch above so a console and the channels share one
		# hole. The tuner's settings are on ITS menu, not the television's.
		["Antenna", "antenna"],
	])

	# Mains leads, on their own tab rather than lost among the A/V ones. What
	# picks one is the shape of the socket on the back of the machine, not what
	# the machine is for, and a player hunting the right plug should not have to
	# read past the record player to find it.
	_add_spawn_tab(tabs, "Power", [
		["NEMA 5-15P to C13 Cable", "power_cord"],
		["NEMA 1-15P to C7 Cable", "nema_1_15_to_c7_cord"],
		["Polarized NEMA 1-15P to C7P Cable",
			"nema_1_15_polarized_to_c7_polarized_cord"],
	])

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
func refresh_after_core_change() -> void:
	_populate_systems_tab()
	_populate_cartridges_tab()


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
	# If a system detail is open, re-run it so catalog changes appear.
	_systems_browser.refresh()


## Detail page for one system: each spawnable item — the console model(s) plus
## that system's controllers/peripherals. Tap to spawn; the menu stays open so
## several items can be spawned in a row.
func _populate_systems_detail(systemid: String, vbox: VBoxContainer) -> void:
	vbox.add_child(MenuStyle.spacer(4))
	for item: Dictionary in SpawnCatalog.items_for(systemid):
		var btn := Button.new()
		btn.text = "  +  " + str(item.get("label", "Console"))
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
			btn.pressed.connect(
				_on_system_memcard_pressed.bind(systemid, card_fmt.id(), vbox))
		else:
			btn.pressed.connect(spawn_requested.emit.bind(token))
		vbox.add_child(btn)
	vbox.add_child(MenuStyle.spacer(8))


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
func _on_system_memcard_pressed(systemid: String, family: String,
		vbox: VBoxContainer) -> void:
	if not MemoryCardBrowser.has_cards(family):
		spawn_requested.emit("%s_memory_card" % family)
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
func _populate_cartridges_tab() -> void:
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
		if _romm_platforms.has(sid):
			remote = int((_romm_platforms[sid] as Dictionary).get("rom_count", 0))
		var shown := RommCatalog.shown_count(sid)
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

	# One directory scan, shared by both passes.
	var by_system := FirmwareRequirements.installed_cores_by_system()
	_mark_systems_without_a_core(systems, by_system)
	_mark_netplay_systems(systems, by_system)

	_cartridges_browser.set_systems(systems)
	# If a system detail is open, re-run it so newly-added ROMs appear. Detail
	# only: set_systems has just rebuilt the tiles, and refresh() would build all
	# 68 of them again for nothing.
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
func _mark_netplay_systems(systems: Array, by_system: Dictionary) -> void:
	for s: Dictionary in systems:
		var sid: String = str(s.get("systemid", ""))
		var best := -1
		for e: Dictionary in (by_system.get(sid, []) as Array):
			var strategy := NetplayCores.listed_strategy(str(e.get("core_name", "")))
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
	resync.pressed.connect(_on_romm_resync_pressed.bind(systemid))
	toolbar.add_child(resync)
	_romm_resync_btn = resync
	_romm_update_resync_btn()

	var scrape_all := Button.new()
	scrape_all.text = String.chr(MenuIcons.SCRAPE_ALL)
	scrape_all.add_theme_font_override("font", MenuIcons.symbols())
	scrape_all.add_theme_font_size_override("font_size", 22)
	scrape_all.custom_minimum_size = Vector2(64, 52)
	scrape_all.size_flags_horizontal = Control.SIZE_SHRINK_END
	scrape_all.tooltip_text = "Scrape every game on this page that has not been scraped yet"
	scrape_all.pressed.connect(_on_scrape_all_pressed.bind(systemid))
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
	vbox.add_child(_romm_list)

	# Start before the first rebuild, or the empty list reads "add ROMs here"
	# while a sync is in fact already running.
	if _romm_platforms.has(systemid) and not RommCatalog.has_index(systemid):
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


func _on_ereader_cards_warm(systemid: String) -> void:
	if _romm_detail_systemid != systemid:
		return
	if _romm_list == null or not is_instance_valid(_romm_list):
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
	var have_index := romm_catalog.load_index(systemid)
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
	if _romm_empty_label == null or not is_instance_valid(_romm_empty_label):
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
	# The adapter probe is a scan of the same folders and goes stale with them:
	# a reader dump copied in has to stop being a game and start being a machine
	# on the same refresh, not on the next launch.
	AdapterRoms.invalidate()


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

	if _romm_region_drop == null or not is_instance_valid(_romm_region_drop):
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
		pct.text = "%d%%" % _romm_progress_pct.get(rom_id, 0)
		state.pressed.connect(func() -> void: romm_downloader.cancel_current())
	elif source == "server":
		# The cloud glyph is visually lighter than the trash glyphs at the same
		# size — a small bump evens the weight out.
		state.add_theme_font_size_override("font_size", 44)
		if romm_client.is_reachable():
			state.text = String.chr(MenuIcons.DOWNLOAD)
			state.add_theme_color_override("font_color", MenuIcons.TINT_DOWNLOAD)
			state.tooltip_text = "Download from RomM (%s)" % MenuStyle.human_bytes(int(entry.get("fs_size_bytes", 0)))
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
			systemid, local_path, "label", Vector2i.ZERO, true)
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
		hold.held.connect(_show_n64_spawn_options.bind(label, spawn))
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
		scrape.pressed.connect(_on_scrape_pressed.bind(local_path, systemid))


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
			MenuStyle.human_bytes(freed)]], 2.5)
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
		var btn := Button.new()
		btn.text = "  +  " + item[0]
		btn.custom_minimum_size = Vector2(0, 80)
		btn.add_theme_font_size_override("font_size", 26)
		if item[1] == "speaker_cable":
			# Held for a second: choose its length and the colour of its plugs.
			var hold := HoldPress.attach(btn)
			hold.clicked.connect(spawn_requested.emit.bind(item[1]))
			hold.held.connect(_show_lead_spawn_options.bind(item[0], item[1]))
		else:
			btn.pressed.connect(spawn_requested.emit.bind(item[1]))
		vbox.add_child(btn)
	return vbox


## The virtual controllers, then a receiver per connected physical pad.
##
## A receiver is how a real gamepad reaches a console: plug one into a controller
## port and that port is driven by its pad, with nothing held. So the list has to
## follow what is actually paired right now, which is why this tab is rebuilt
## rather than authored like the others.
func _populate_controllers_tab() -> void:
	if _controllers_vbox == null or not is_instance_valid(_controllers_vbox):
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
		_controllers_vbox.add_child(_spawn_row(label, token))


func _spawn_row(label: String, token: String) -> Button:
	var btn := Button.new()
	btn.text = "  +  " + label
	btn.custom_minimum_size = Vector2(0, 80)
	btn.add_theme_font_size_override("font_size", 26)
	btn.pressed.connect(spawn_requested.emit.bind(token))
	return btn


# ── Scraper ──────────────────────────────────────────────────────────────────

func _on_scrape_pressed(rom_path: String, systemid: String) -> void:
	if scrape_queue == null:
		return
	# Review mode hands the result back for the popup; otherwise the queue
	# writes it and fetches the art, and the row repaints when it lands.
	var review := scraper_config != null and scraper_config.approve_scrapes
	if not scrape_queue.enqueue(rom_path, systemid,
			{"tag": ScrapeQueue.TAG_MANUAL, "review": review}):
		show_notice("Already in the scrape queue")
		return
	var ahead := scrape_queue.waiting_count()
	if ahead > 0:
		show_notice("Queued: %s (%d waiting)" % [rom_path.get_file().get_basename(), ahead])
	_on_scrape_row_changed(rom_path, systemid)


## Queue every game on this page not scraped yet. The filtered view is
## the page: a search or a region filter narrows what is queued, the way it
## narrows what is shown. A game already scraped is skipped -- re-scraping one
## stays a per-row action -- and so is one already waiting.
func _on_scrape_all_pressed(systemid: String) -> void:
	if scrape_queue == null:
		return
	var review := scraper_config != null and scraper_config.approve_scrapes
	var candidates: Array = []
	for model: Dictionary in _romm_rows:
		var local_path := str(model.get("path", ""))
		if local_path.is_empty():
			continue
		if systemid == "satellaview" and BsxPack.is_pack_path(local_path):
			continue
		candidates.append(local_path)
	var pick := scrape_queue.select_unscraped(systemid, candidates)
	var skipped := int(pick["skipped"])
	var queued := 0
	for local_path: String in pick["paths"]:
		if scrape_queue.enqueue(local_path, systemid,
				{"tag": ScrapeQueue.TAG_MANUAL, "review": review}):
			queued += 1
	var msg := "Queued %d game%s" % [queued, "" if queued == 1 else "s"]
	if skipped > 0:
		msg += " (%d already scraped)" % skipped
	if queued == 0 and skipped == 0:
		msg = "Nothing on this page to scrape"
	show_notice(msg, 3.0)
	if is_instance_valid(_romm_list):
		_romm_list.rebind_visible()


## A row's button reads the queue at bind time, so a change of state is a
## repaint of what is on screen and nothing more.
func _on_scrape_row_changed(_rom_path: String, _systemid: String) -> void:
	if is_instance_valid(_romm_list):
		_romm_list.rebind_visible()


func _on_scrape_completed(rom_path: String, systemid: String, result: Dictionary,
		accepted: bool) -> void:
	print("[SpawnView] Scrape completed for: %s" % rom_path.get_file())
	if not accepted:
		_show_scrape_popup(rom_path, systemid, result)
		_on_scrape_row_changed(rom_path, systemid)
		return
	# The name and metadata a row draws changed: repopulate, once per burst.
	_romm_meta_cache.erase(rom_path)
	if systemid == _romm_detail_systemid:
		_schedule_scrape_refresh()
	else:
		_on_scrape_row_changed(rom_path, systemid)


func _on_scrape_failed(rom_path: String, systemid: String, error: String) -> void:
	push_warning("[SpawnView] Scrape failed for %s: %s" % [rom_path.get_file(), error])
	_on_scrape_row_changed(rom_path, systemid)


## Same as the accept path's refresh: drop what cached a miss for this ROM
## before the art existed, then repaint the rows on screen. Wheel, label and
## manual are what a row draws; no row draws the box.
func _on_scrape_media_downloaded(rom_path: String, systemid: String, media_type: String,
		_path: String) -> void:
	if media_type != "wheel" and media_type != "label" and media_type != "manual":
		return
	if scraped_art != null:
		scraped_art.forget(systemid, rom_path)
	_romm_meta_cache.erase(rom_path)
	_on_scrape_row_changed(rom_path, systemid)


func _schedule_scrape_refresh() -> void:
	if _scrape_refresh_timer != null:
		return
	_scrape_refresh_timer = get_tree().create_timer(0.5)
	_scrape_refresh_timer.timeout.connect(func() -> void:
		_scrape_refresh_timer = null
		if is_instance_valid(_romm_list):
			_populate_cartridges_tab()
	)


func _show_scrape_popup(rom_path: String, systemid: String, result: Dictionary) -> void:
	_close_scrape_popup()

	_scrape_popup = PanelContainer.new()
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.1, 0.2, 0.98)
	for k in ["corner_radius_top_left","corner_radius_top_right",
			  "corner_radius_bottom_left","corner_radius_bottom_right"]:
		bg.set(k, 8)
	_scrape_popup.add_theme_stylebox_override("panel", bg)
	_scrape_popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	for side in ["margin_top","margin_bottom","margin_left","margin_right"]:
		margin.add_theme_constant_override(side, 14)
	_scrape_popup.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	# Title
	vbox.add_child(MenuStyle.label("SCRAPE RESULT", 24, MenuStyle.COLOR_TITLE))
	vbox.add_child(HSeparator.new())

	# Metadata
	_add_scrape_info_row(vbox, "Game", result.get("name", "Unknown"))
	_add_scrape_info_row(vbox, "Developer", result.get("developer", ""))
	_add_scrape_info_row(vbox, "Publisher", result.get("publisher", ""))
	_add_scrape_info_row(vbox, "Genre", result.get("genre", ""))
	_add_scrape_info_row(vbox, "Region", result.get("rom_region", ""))
	_add_scrape_info_row(vbox, "Release", result.get("releasedate", ""))

	vbox.add_child(HSeparator.new())

	# Media availability
	var media: Dictionary = result.get("media", {})
	vbox.add_child(MenuStyle.label("MEDIA", 18, MenuStyle.COLOR_TITLE))

	for mtype: String in ["wheel", "box", "label", "manual"]:
		var has_it: bool = not (media.get(mtype, "") as String).is_empty()
		var icon := "✅" if has_it else "❌"
		_add_scrape_info_row(vbox, mtype.capitalize(), icon)

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
	get_parent().add_child(_scrape_popup)


func _show_scrape_error_popup(error: String) -> void:
	_close_scrape_popup()

	_scrape_popup = PanelContainer.new()
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.2, 0.08, 0.08, 0.98)
	for k in ["corner_radius_top_left","corner_radius_top_right",
			  "corner_radius_bottom_left","corner_radius_bottom_right"]:
		bg.set(k, 8)
	_scrape_popup.add_theme_stylebox_override("panel", bg)
	_scrape_popup.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var margin := MarginContainer.new()
	for side in ["margin_top","margin_bottom","margin_left","margin_right"]:
		margin.add_theme_constant_override(side, 14)
	_scrape_popup.add_child(margin)

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

	get_parent().add_child(_scrape_popup)


func _close_scrape_popup() -> void:
	if _scrape_popup and is_instance_valid(_scrape_popup):
		_scrape_popup.queue_free()
	_scrape_popup = null


# ── RomM notifications ────────────────────────────────────────────────────────
# All of these land in the same bottom-of-menu toast stack the scraper uses.
# Keys are namespaced "romm:" so they cannot collide with the scraper's
# box/wheel/label/manual keys.


## Called when the menu panel becomes visible in the world.
func on_menu_shown() -> void:
	_menu_shown = true
	_flush_romm_notices()
	_romm_check_for_changes()



func on_menu_hidden() -> void:
	_menu_shown = false


## The cheapest possible "did anything change?" — /api/stats is public and ~100
## bytes. If the fingerprint matches, the library provably hasn't changed and no
## /api/roms call is made at all.
func _romm_check_for_changes() -> void:
	if romm_config == null or not romm_config.is_configured():
		return
	romm_client.stats(func(ok: bool, stats: Dictionary) -> void:
		if not ok or stats.is_empty():
			return
		var changed := not romm_config.stats_unchanged(stats)
		print("[RommSync] stats %s: was %s now %s" % [
			"changed" if changed else "unchanged",
			RommConfig.fingerprint_text(romm_config.last_stats),
			RommConfig.fingerprint_text(stats)])
		if changed:
			romm_config.last_stats = stats
			if not romm_config.save_config():
				push_warning("[RommSync] could not save %s: the fingerprint will read as changed again next launch"
					% RommConfig.config_path())
		# The cached list is already on screen; this corrects it in the
		# background and costs nothing visible.
		romm_fetch_platforms()
		if changed:
			_queue_delta_syncs()
	)


## The library moved since we last looked, so at least one synced platform is
## stale. Delta, not full: the watermark turns "one game was added" into a single
## small page instead of every page of the platform.
##
## Only platforms that already have an index are queued. One that has never been
## opened has nothing to bring up to date, and syncing it here would fetch a
## library the player has not asked to browse.
##
## Deletions are NOT reconciled by a delta — the merge only adds and updates, so
## a game removed on the server survives until a full sync. OPTIONS > Sync All
## remains the reconcile.
func _queue_delta_syncs() -> void:
	var stale: Array[String] = []
	for sid: String in _romm_platforms:
		if RommCatalog.has_index(sid):
			stale.append(sid)
	if stale.is_empty() or _menu == null:
		return
	print("[RommSync] queuing delta syncs for %d indexed platform(s): %s" % [stale.size(), ", ".join(stale)])
	_menu.queue_romm_sync(stale, false)


## Toasts can only be seen while the menu panel is open. A 4 GB download keeps
## running while the user plays, so terminal outcomes are queued and flushed
## (coalesced) the next time the menu opens, rather than vanishing unseen.
func _romm_notify_or_queue(key: String, icon: String, msg: String, dwell: float,
						   progress: float = -1.0) -> void:
	if _menu_shown:
		notify(key, icon, msg, progress, dwell)
	elif progress < 0.0:
		# Only outcomes are worth keeping for later. Queueing progress ticks
		# would bank hundreds of them and then replay a finished download.
		_romm_pending_notices.append({"ok": icon == "✅", "msg": msg})


## Called when the menu becomes visible.
func _flush_romm_notices() -> void:
	if _romm_pending_notices.is_empty():
		return
	var done := 0
	var failed := 0
	for n: Dictionary in _romm_pending_notices:
		if bool(n["ok"]):
			done += 1
		else:
			failed += 1
	_romm_pending_notices.clear()

	# One summary, not a replay of every toast.
	if done > 0 and failed == 0:
		notify("romm:flush", "✅", "%d download%s finished" % [done, "" if done == 1 else "s"],
			-1.0, MenuToasts.DWELL_INFO)
	elif done == 0 and failed > 0:
		notify("romm:flush", "❌", "%d download%s failed" % [failed, "" if failed == 1 else "s"],
			-1.0, MenuToasts.DWELL_FAIL)
	else:
		notify("romm:flush", "✅", "%d finished · %d failed" % [done, failed],
			-1.0, MenuToasts.DWELL_FAIL)


func _on_romm_auth_failed(detail: String) -> void:
	push_warning("[SpawnView] auth failed: %s" % detail)
	notify("romm:conn", "❌", "RomM sign-in expired — check OPTIONS", -1.0, MenuToasts.DWELL_FAIL)


## Fires only on a transition, so a dead server can't produce a toast stream.
##
## Repaints in BOTH directions: the cached index keeps listing server-only titles
## whether or not the server answers, so the rows have to say which of them can
## still be acted on — and say it again when it comes back.
func _on_romm_reachability_changed(reachable: bool) -> void:
	if is_instance_valid(_romm_list):
		_romm_list.rebind_visible()
	_romm_update_empty_label()
	if reachable:
		return
	notify("romm:conn", "❌", "RomM unreachable", -1.0, MenuToasts.DWELL_FAIL)


## Fires twice: once before the first request, then again with the real total
## once page one lands. The toast updates in place.
func _on_romm_sync_started(systemid: String, total: int) -> void:
	var label := _system_label(systemid)
	if total <= 0:
		notify("romm:sync:" + systemid, "⏳", "Fetching the %s list from RomM…" % label, -1.0)
	else:
		notify("romm:sync:" + systemid, "⏳",
			"Syncing %s · 0 / %s" % [label, _commas(total)], 0.0)
	# The toolbar button is this platform's stop button for as long as this runs.
	_romm_update_resync_btn()


func _on_romm_sync_progress(systemid: String, done: int, total: int) -> void:
	var frac := (float(done) / float(total)) if total > 0 else -1.0
	notify("romm:sync:" + systemid, "⏳",
		"Syncing %s · %s / %s" % [_system_label(systemid), _commas(done), _commas(total)], frac)


func _on_romm_sync_finished(systemid: String, ok: bool, added: int, removed: int, error: String) -> void:
	var key := "romm:sync:" + systemid
	var label := _system_label(systemid)
	# Back to offering a resync, whichever way this ended.
	_romm_update_resync_btn()

	if not ok:
		push_warning("[RommSync] %s failed: %s" % [systemid, error])
		notify(key, "❌", "RomM sync failed — %s" % error, -1.0, MenuToasts.DWELL_FAIL)
		# Still announced: this is what pumps the sync queue, so returning
		# quietly strands every platform behind the one that failed.
		romm_state_changed.emit()
		return

	# Record the watermark so the next open can skip the network entirely.
	var meta := RommCatalog.read_meta(systemid)
	romm_config.set_sync_state(systemid, str(meta.get("updated_after", "")), int(meta.get("total", 0)))
	print("[RommSync] %s finished: +%d -%d, watermark %s" % [systemid, added, removed,
		str(meta.get("updated_after", "")) if meta.has("updated_after") else "(none)"])
	if not romm_config.save_config():
		push_warning("[RommSync] could not save %s: %s will full-sync again next launch"
			% [RommConfig.config_path(), systemid])

	if added > 0:
		notify(key, "✅", "%s · %d new game%s" % [label, added, "" if added == 1 else "s"],
			-1.0, MenuToasts.DWELL_INFO)
	elif removed > 0:
		notify(key, "✅", "%s · %d game%s removed" % [label, removed, "" if removed == 1 else "s"],
			-1.0, MenuToasts.DWELL_INFO)
	else:
		notify(key, "✅", "%s · up to date" % label, -1.0, 1.5)

	# The open detail page is showing a stale list — rebuild it against the new index.
	if systemid == _romm_detail_systemid:
		_rebuild_romm_rows()
	romm_state_changed.emit()


## Delta by default — this is the "I just added a game" button, and a full
## re-fetch of a large platform is ~20 pages. A platform with no index yet is
## already having a full sync started for it by the open itself.
## Paint the toolbar button for what pressing it will do right now — resync this
## platform, or stop the sync that is already running on it.
func _romm_update_resync_btn() -> void:
	if _romm_resync_btn == null or not is_instance_valid(_romm_resync_btn):
		return
	var label := _system_label(_romm_detail_systemid)
	if _romm_syncing_this_platform():
		_romm_resync_btn.text = String.chr(MenuIcons.CROSS)
		_romm_resync_btn.add_theme_color_override("font_color", MenuIcons.TINT_DELETE)
		_romm_resync_btn.tooltip_text = "Stop syncing %s" % label
	else:
		_romm_resync_btn.text = String.chr(MenuIcons.RETRY)
		_romm_resync_btn.remove_theme_color_override("font_color")
		_romm_resync_btn.tooltip_text = \
			"Check RomM for changes to %s, and drop entries the server has lost" % label


func _romm_syncing_this_platform() -> bool:
	return romm_catalog != null and romm_catalog.is_syncing() \
		and romm_catalog.syncing_systemid() == _romm_detail_systemid


## Resync, or stop — whichever the button is currently offering. Everything the
## stop needs to tidy up happens in _on_romm_sync_aborted, so that a cancel from
## OPTIONS cleans up identically.
func _on_romm_resync_pressed(systemid: String) -> void:
	if _menu == null:
		return
	if romm_catalog != null and romm_catalog.is_syncing() \
			and romm_catalog.syncing_systemid() == systemid:
		romm_catalog.abort_sync()
		return
	if not RommCatalog.has_index(systemid):
		return
	_menu.queue_romm_sync([systemid], false)


## Tidy up after a cancelled sync, from wherever it was cancelled.
##
## The half-written index is not a concern — pages go to index.jsonl.part and
## swap in atomically at the end, so the previous index survives untouched.
## Emitting romm_state_changed is what advances the queue: only this platform
## was stopped, and anything queued behind it still wants to run. OPTIONS clears
## the queue before it aborts, so its Stop really does stop everything.
func _on_romm_sync_aborted(systemid: String) -> void:
	# abort_sync is also the teardown path, so this can fire while the menu is on
	# its way out. `if _menu` inside the notify wrappers is not enough — a freed
	# Object is still truthy in GDScript.
	if not is_instance_valid(_menu):
		return
	notify_clear("romm:sync:" + systemid)
	notify("romm:conn", "⏹", "Stopped syncing %s" % _system_label(systemid),
		-1.0, MenuToasts.DWELL_OK)
	_romm_update_resync_btn()
	_romm_update_empty_label()
	romm_state_changed.emit()


func _on_romm_dl_started(rom_id: int, label: String, total_bytes: int) -> void:
	_romm_dl_labels[rom_id] = label
	# A ROM tapped again after a failed run must not inherit that run's count.
	_romm_dl_attempt[rom_id] = 0
	notify_clear("romm:dl:%d:why" % rom_id)
	notify("romm:dl:%d" % rom_id, "⬇", "%s · %s" % [label, MenuStyle.human_bytes(total_bytes)], 0.0)
	# Resolved once; a scan per progress tick would be O(rows) on an 11k list.
	_romm_dl_row_index = -1
	for i in _romm_rows.size():
		if romm_catalog.rom_id_at(int(_romm_rows[i].get("index", -1))) == rom_id:
			_romm_dl_row_index = i
			break


## Progress arrives every 256 KB — ~700 times for a 178 MB ROM, ~16,000 for a
## 4 GB one. Rebinding the whole visible window each time meant thousands of
## row binds, each doing a gamelist scan and several file_exists calls on the
## main thread; with an emulator running that reads as a hard freeze. Only act
## when the displayed percentage actually changes, and touch one row.
func _on_romm_dl_progress(rom_id: int, received: int, total: int) -> void:
	# Clamped because the total is the catalog's size for the ROM, while the body
	# may be a container the server generated around it — a few hundred bytes
	# larger. "101%" reads as a bug in the bar rather than what it is.
	var frac := clampf(float(received) / float(total), 0.0, 1.0) if total > 0 else -1.0
	var pct := int(frac * 100.0) if frac >= 0.0 else 0
	if int(_romm_progress_pct.get(rom_id, -1)) == pct:
		return
	_romm_progress_pct[rom_id] = pct
	var attempt := int(_romm_dl_attempt.get(rom_id, 0))
	notify("romm:dl:%d" % rom_id, "⬇",
		"%s%s · %d%% · %s / %s" % [_romm_dl_label(rom_id),
			"" if attempt <= 0 else "  (attempt %d)" % attempt, pct,
			MenuStyle.human_bytes(received), MenuStyle.human_bytes(total)], frac)
	if is_instance_valid(_romm_list):
		_romm_list.rebind_index(_romm_dl_row_index)


## The reason gets a toast of its own, not the download's.
##
## A retry resumes within its backoff and the first progress tick lands 256 KB
## later, which on a LAN is immediate — sharing the download's key meant the only
## place the failure was ever named got overwritten before it could be read, and
## a run that failed three times looked like one that simply stopped. This one
## dwells like any other failure, beside the bar rather than on top of it.
func _on_romm_dl_retrying(rom_id: int, attempt: int, max_attempts: int, reason: String) -> void:
	_romm_dl_attempt[rom_id] = attempt
	notify("romm:dl:%d" % rom_id, "⏳",
		"%s — retry %d/%d" % [_romm_dl_label(rom_id), attempt, max_attempts], -1.0)
	notify("romm:dl:%d:why" % rom_id, "⚠",
		"%s — %s" % [_romm_dl_label(rom_id),
			reason if not reason.is_empty() else "the transfer failed"],
		-1.0, MenuToasts.DWELL_FAIL)


## What this download is fetching, for every bar after the first.
func _romm_dl_label(rom_id: int) -> String:
	var label := str(_romm_dl_labels.get(rom_id, ""))
	return label if not label.is_empty() else "Download"


func _on_romm_dl_finished(rom_id: int, ok: bool, path: String, error: String) -> void:
	var key := "romm:dl:%d" % rom_id
	if ok:
		_romm_notify_or_queue(key, "✅", "%s ready" % path.get_file().get_basename(), MenuToasts.DWELL_OK)
		# A ROM that arrived by download is one nobody browsed to, so nobody is
		# going to press Scrape on it either. Queued, not fetched now: the
		# scraper is rate-limited and a batch download would outrun it.
		if _menu != null and "auto_scraper" in _menu:
			var scraper: AutoScraper = _menu.get("auto_scraper")
			if scraper != null:
				scraper.request(path, AutoScraper.systemid_for_path(path))
	else:
		_romm_notify_or_queue(key, "❌", "%s — %s" % [_romm_dl_label(rom_id), error],
			MenuToasts.DWELL_FAIL)
		# The server answered that this row's file is gone, which is the one
		# failure that will never come good on a retry. Take the row out now
		# rather than leaving a button that can only fail again — the next sync
		# would have done it, but not before the player pressed it twice.
		if error == RommHttp.ERR_GONE and romm_catalog != null \
				and not _romm_detail_systemid.is_empty():
			romm_catalog.remove_rows(_romm_detail_systemid, [rom_id])
	_romm_dl_labels.erase(rom_id)
	_romm_dl_attempt.erase(rom_id)
	# The final message names the same failure, so leaving the retry note up
	# would say it twice.
	notify_clear("romm:dl:%d:why" % rom_id)
	_romm_dl_row_index = -1
	_romm_meta_cache.clear()
	# The download merged its game into gamelist.json through its own manager.
	if ok and gamelist_manager != null:
		gamelist_manager.invalidate(AutoScraper.systemid_for_path(path))
	_invalidate_local_scan()
	_rebuild_romm_rows()


func _on_romm_dl_cancelled(rom_id: int) -> void:
	_romm_dl_labels.erase(rom_id)
	_romm_dl_attempt.erase(rom_id)
	notify_clear("romm:dl:%d" % rom_id)
	notify_clear("romm:dl:%d:why" % rom_id)
	_rebuild_romm_rows()


## Files silently vanishing from a library reads as data loss — always say so.
func _on_romm_cache_evicted(freed_bytes: int, count: int) -> void:
	notify("romm:cache", "🗑", "Freed %s — removed %d game%s"
		% [MenuStyle.human_bytes(freed_bytes), count, "" if count == 1 else "s"], -1.0, 4.0)


## Eviction can change a server row from local to downloadable and can remove
## companion-only rows, so rebuild the model rather than merely re-binding it.
func _on_romm_cache_changed() -> void:
	_romm_meta_cache.clear()
	_invalidate_local_scan()
	_rebuild_romm_rows()




func _on_romm_art_ready(_rom_id: int, _texture: Texture2D) -> void:
	if is_instance_valid(_romm_list):
		_romm_list.rebind_visible()


## A wheel or label finished decoding. Only the visible rows are re-bound, and
## the cache's per-frame budget means at most two of these land in one frame.
func _on_scraped_art_ready(_key: String, _texture: Texture2D) -> void:
	if is_instance_valid(_romm_list):
		_romm_list.rebind_visible()


func _system_label(systemid: String) -> String:
	var sysname := core_db.get_systemname_for_id(systemid)
	return sysname if not sysname.is_empty() else systemid


static func _commas(n: int) -> String:
	var s := str(n)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out


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

	gamelist_manager.add_or_merge_rom(systemid, game_data, rom_data)
	gamelist_manager.save_gamelist(systemid)

	# Disconnect any stale media refresh callback from a previous accept
	if _media_dl_refresh_cb.is_valid() and \
			scraper_client.media_download_completed.is_connected(_media_dl_refresh_cb):
		scraper_client.media_download_completed.disconnect(_media_dl_refresh_cb)

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
	var scraped_rom := rom_path
	# LABEL is in this list because the row's thumbnail IS the label: it beats
	# the RomM cover once scraped, and leaving it out meant the one piece of art
	# a freshly scraped game always has was the one piece that never appeared
	# until the platform was closed and reopened. Box is not, since no row draws it.
	_media_dl_refresh_cb = func(mtype: String, _path: String) -> void:
		if mtype != "wheel" and mtype != "label" and mtype != "manual":
			return
		# Drop what cached a miss for this ROM before the art existed.
		if scraped_art != null:
			scraped_art.forget(systemid, scraped_rom)
		_romm_meta_cache.erase(scraped_rom)
		# ...then repaint the rows on screen, and nothing else.
		#
		# A piece of art landing changes neither the tile grid nor the row model
		# — only what an already-bound row draws. Rebuilding both cost 134 ms
		# measured, because _populate_cartridges_tab ends in browser.refresh(),
		# which re-runs the detail populator over every row of the open system:
		# 9,927 of them on this library, and then _rebuild_romm_rows did it a
		# second time. The name and metadata that DO change are handled by the
		# single _populate_cartridges_tab this accept already runs below.
		if is_instance_valid(_romm_list):
			_romm_list.rebind_visible()
	scraper_client.media_download_completed.connect(_media_dl_refresh_cb)

	# Download media files asynchronously
	var rom_basename := rom_path.get_file().get_basename()
	scraper_client.download_all_media(result, systemid, rom_basename)

	# Refresh immediately so the game name / metadata shows right away
	_populate_cartridges_tab()


## Returns the value's label, or null for an empty value, which adds no row.
func _add_scrape_info_row(parent: VBoxContainer, key: String, value: String) -> Label:
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
	_add_scrape_info_row(vbox, "Developer", game.get("developer", ""))
	_add_scrape_info_row(vbox, "Publisher", game.get("publisher", ""))
	_add_scrape_info_row(vbox, "Genre", game.get("genre", ""))
	_add_scrape_info_row(vbox, "File", local_path)
	# The FILE's region, not the game's: a game's variants differ in exactly this.
	var region := str(_rom_entry_for(game, local_path).get("region", ""))
	var flag := MenuIcons.region_flag(region)
	var region_lbl := _add_scrape_info_row(vbox, "Region",
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
	return systemid == "n64"


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
	if group != null:
		btn.toggle_mode = true
		btn.button_group = group
	return btn


## Shell and body for an N64 cartridge. Two choices, so they are picked and then
## SPAWN is pressed; `spawn` takes the options dictionary.
func _show_n64_spawn_options(label: String, spawn: Callable) -> void:
	var vbox := _open_spawn_options_panel(label)
	var chosen := {"shell_preset": "", "body_region": ""}
	var auto_color := Color(0.18, 0.18, 0.35)

	vbox.add_child(MenuStyle.header("Body"))
	var bodies := MenuStyle.hbox(10)
	vbox.add_child(bodies)
	var body_group := ButtonGroup.new()
	for body: Array in [["Auto (from the ROM)", ""],
			["USA / PAL", N64CartShell.REGION_USA], ["Japan", N64CartShell.REGION_JPN]]:
		var body_btn := _swatch_button(body[0], auto_color, body_group)
		body_btn.button_pressed = body[1] == ""
		body_btn.pressed.connect(func() -> void: chosen["body_region"] = body[1])
		bodies.add_child(body_btn)

	vbox.add_child(MenuStyle.header("Shell"))
	var shell_group := ButtonGroup.new()
	var auto_btn := _swatch_button("Auto (from the ROM)", auto_color, shell_group)
	auto_btn.button_pressed = true
	auto_btn.pressed.connect(func() -> void: chosen["shell_preset"] = "")
	vbox.add_child(auto_btn)
	var palette := CartridgeColor.get_palette()
	for section: Array in [
			["Standard", CartridgeShellPreset.Availability.STANDARD],
			["Released", CartridgeShellPreset.Availability.RELEASED],
			["Offered by Nintendo, never used", CartridgeShellPreset.Availability.OFFERED_ONLY]]:
		var presets := palette.with_availability(section[1])
		if presets.is_empty():
			continue
		vbox.add_child(MenuStyle.hint(section[0]))
		var grid := GridContainer.new()
		grid.columns = 4
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_theme_constant_override("h_separation", 10)
		grid.add_theme_constant_override("v_separation", 10)
		vbox.add_child(grid)
		for preset: CartridgeShellPreset in presets:
			# A two-tone shell is shown by its front half, the one facing the player.
			var shown := palette.find(preset.front) if preset.is_two_tone() else preset
			var swatch := _swatch_button(preset.display_name,
				(shown if shown != null else preset).color, shell_group)
			swatch.pressed.connect(func() -> void: chosen["shell_preset"] = String(preset.id))
			grid.add_child(swatch)

	vbox.add_child(MenuStyle.spacer(6))
	var go := MenuStyle.row_button("  +  SPAWN", 26, 0, 80, false)
	go.add_theme_stylebox_override("normal", MenuStyle.rounded(MenuStyle.COLOR_BTN_DL, 8))
	go.pressed.connect(func() -> void:
		var options := {}
		for key: String in chosen:
			if not str(chosen[key]).is_empty():
				options[key] = chosen[key]
		_close_spawn_options_panel()
		spawn.call(options))
	vbox.add_child(go)


## How long a lead is and what colour its plugs are. Two choices, so they are
## picked and then SPAWN is pressed -- the same shape as the cartridge panel above,
## and the reason this one no longer spawns on the first tap.
func _show_lead_spawn_options(label: String, token: String) -> void:
	var vbox := _open_spawn_options_panel(label)
	var chosen := {"color": "", "length": 0.0}
	var auto_color := Color(0.18, 0.18, 0.35)

	vbox.add_child(MenuStyle.header("Length"))
	var lengths := MenuStyle.hbox(10)
	vbox.add_child(lengths)
	var length_group := ButtonGroup.new()
	for row: Array in CompositeCable.SPAWN_LENGTHS:
		var length_btn := _swatch_button(row[1], auto_color, length_group)
		length_btn.button_pressed = row[0] == 0.0
		length_btn.pressed.connect(func() -> void: chosen["length"] = row[0])
		lengths.add_child(length_btn)

	vbox.add_child(MenuStyle.header("Plug colour"))
	var color_group := ButtonGroup.new()
	var auto_btn := _swatch_button("Default", auto_color, color_group)
	auto_btn.button_pressed = true
	auto_btn.pressed.connect(func() -> void: chosen["color"] = "")
	vbox.add_child(auto_btn)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	vbox.add_child(grid)
	for id: StringName in RcaJack.PLUG_COLORS:
		var swatch := _swatch_button(RcaJack.PLUG_COLORS[id][0], RcaJack.PLUG_COLORS[id][1],
			color_group)
		swatch.pressed.connect(func() -> void: chosen["color"] = String(id))
		grid.add_child(swatch)

	vbox.add_child(MenuStyle.spacer(6))
	var go := MenuStyle.row_button("  +  SPAWN", 26, 0, 80, false)
	go.add_theme_stylebox_override("normal", MenuStyle.rounded(MenuStyle.COLOR_BTN_DL, 8))
	go.pressed.connect(func() -> void:
		# An empty field is "the lead's own" at the other end, so a default choice
		# sends nothing rather than a value that happens to match the scene.
		var metres: float = chosen["length"]
		_close_spawn_options_panel()
		spawn_requested.emit("%s:%s:%s" % [token, chosen["color"],
			"" if metres <= 0.0 else str(metres)]))
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
		rom_hold.held.connect(_show_n64_spawn_options.bind(rom_label, rom_spawn))

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
		spawn_hold.held.connect(_show_n64_spawn_options.bind(rom_label, rom_spawn))
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
