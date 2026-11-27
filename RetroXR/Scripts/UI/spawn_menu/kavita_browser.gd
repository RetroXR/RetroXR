## Kavita on the Books tab, laid out as the Games tab's RomM pages are: the
## libraries as tiles, then a library's series and a series' books as rows of
## cover and title, with RomM's download glyph and a percentage while a book
## comes down. The connection (server and Auth Key) is OPTIONS > Kavita's.
##
## A comic or PDF opens straight off the server when its title is pressed
## (KavitaPages, nothing downloaded); the download button keeps a copy on the
## device, under OPTIONS > Kavita's budget (KavitaCache). Which way a book reads
## is Kavita's: its reading profile for the series or library, else a Manga
## library reads right to left. A search over the whole server sits on the home
## page.
##
## The node is kept across Books tab rebuilds (SpawnView re-parents it), so a
## download carries on while the tab is repopulated. Hidden while Kavita is not
## set up.
class_name KavitaBrowser
extends VBoxContainer

## right_to_left: Kavita reads this book right to left (its reading profile, or a
## Manga library). `path` is a downloaded file or a kavita://chapter/<id> stream.
signal book_selected(path: String, right_to_left: bool)

const ROW_HEIGHT := 100
const SERIES_PAGE := 100
## What Kavita can hand over as one file the reader opens.
const FILE_FORMATS := ["epub", "pdf", "cbz"]
## Comic archives saved as CBZ from Kavita's page images (no RAR or 7z here).
const COMIC_ARCHIVES := ["cbr", "cb7", "cbt", "rar", "7z", "zip"]
const TILE_MIN_WIDTH := 250.0
## Kavita's LibraryType for Manga (its LibraryDto "type"; Comic is 1, Book 2).
const LIBRARY_MANGA := 0
## Kavita's ReadingDirection (a reading profile's "readingDirection").
const PROFILE_RIGHT_TO_LEFT := 1

## (key, icon, msg, progress, seconds): the menu's toasts, set by SpawnView.
var notifier: Callable = Callable()

var _config := KavitaConfig.new()
var _identity := ""
var _art: KavitaArtCache
var _back: Button
var _title: Label
var _reload: Button
var _filter: LineEdit
var _search_row: HBoxContainer
var _search: LineEdit
var _status: Label
var _tiles: GridContainer
var _list: VirtualRowList

var _page := "home"   ## home | series | search | books
var _libraries: Array = []
var _library := {}
var _series_all: Array = []
var _series := {}
var _books_all: Array = []
## Kavita's reading profiles (/api/reading-profile/all); empty on a server without them.
var _profiles: Array = []
## The search a series was opened from, so Back returns to its results.
var _last_query := ""
var _books_from_search := false
## The rows on screen: the current page's series or books, filtered.
var _rows: Array = []
## Bumped on every page change, so a reply for a page already left is dropped.
var _load_token := 0

var _queue: Array[Dictionary] = []
var _active_id := 0
var _active_pct := 0
var _delete_armed := 0


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_art = KavitaArtCache.new()
	add_child(_art)
	_art.art_ready.connect(func(_kind: String, _id: int, _tex: Texture2D) -> void:
		if is_instance_valid(_list):
			_list.rebind_visible())

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	add_child(header)
	_back = Button.new()
	_back.add_theme_font_override("font", MenuIcons.symbols())
	_back.text = "%s  Back" % String.chr(MenuIcons.BACK)
	_back.custom_minimum_size = Vector2(150, 52)
	_back.add_theme_font_size_override("font_size", 20)
	_back.pressed.connect(_go_back)
	header.add_child(_back)
	# Kavita's mark beside the title, as RomM's marks what comes from RomM.
	var mark := TextureRect.new()
	mark.texture = MenuIcons.kavita_mark()
	mark.custom_minimum_size = Vector2(40, 40)
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.visible = mark.texture != null
	header.add_child(mark)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 24)
	_title.add_theme_color_override("font_color", MenuStyle.COLOR_TITLE)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.clip_text = true
	header.add_child(_title)
	_reload = Button.new()
	_reload.text = String.chr(MenuIcons.RETRY)
	_reload.add_theme_font_override("font", MenuIcons.symbols())
	_reload.add_theme_font_size_override("font_size", 22)
	_reload.custom_minimum_size = Vector2(64, 52)
	_reload.tooltip_text = "Reload from Kavita"
	_reload.pressed.connect(_reload_page)
	header.add_child(_reload)
	add_child(HSeparator.new())

	_filter = LineEdit.new()
	_filter.clear_button_enabled = true
	_filter.custom_minimum_size = Vector2(0, 52)
	_filter.add_theme_font_size_override("font_size", 20)
	_filter.text_changed.connect(func(_t: String) -> void: _apply_filter())
	add_child(_filter)

	# A search over every library, on the home page: the Games tab's search bar.
	_search_row = HBoxContainer.new()
	_search_row.add_theme_constant_override("separation", 8)
	add_child(_search_row)
	_search = LineEdit.new()
	_search.placeholder_text = "Search Kavita…"
	_search.clear_button_enabled = true
	_search.custom_minimum_size = Vector2(0, 52)
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.add_theme_font_size_override("font_size", 20)
	_search.text_submitted.connect(_show_search)
	_search_row.add_child(_search)
	var go := Button.new()
	go.text = "Search"
	go.add_theme_font_size_override("font_size", 20)
	go.custom_minimum_size = Vector2(120, 52)
	go.pressed.connect(func() -> void: _show_search(_search.text))
	_search_row.add_child(go)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 18)
	_status.add_theme_color_override("font_color", MenuStyle.COLOR_DESC)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)

	_tiles = GridContainer.new()
	_tiles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tiles.add_theme_constant_override("h_separation", 10)
	_tiles.add_theme_constant_override("v_separation", 10)
	add_child(_tiles)
	resized.connect(func() -> void:
		_tiles.columns = maxi(1, int(size.x / TILE_MIN_WIDTH)))
	refresh()


## Read the settings again. Called by SpawnView each time the Books tab is built,
## so a server or key changed under OPTIONS shows here without a restart.
func refresh() -> void:
	_config.load_config()
	visible = _config.is_configured()
	if not visible:
		return
	var identity := _config.base_url + "\n" + _config.auth_key
	if identity != _identity:
		_identity = identity
		_art.setup(_config)
		_libraries.clear()
		print("[Kavita] browsing %s" % _config.base_url)
		_show_home()
	elif _page == "home" and _libraries.is_empty():
		_show_home()


func _notify(key: String, icon: String, msg: String, progress: float = -1.0, seconds: float = 0.0) -> void:
	if notifier.is_valid():
		notifier.call(key, icon, msg, progress, seconds)


# ── Pages ────────────────────────────────────────────────────────────────────

func _set_page(page: String, title: String) -> void:
	_page = page
	_load_token += 1
	_title.text = title
	_back.visible = page != "home"
	_filter.visible = page == "series" or page == "books"
	_filter.text = ""
	_filter.placeholder_text = "Filter series…" if page == "series" else "Filter books…"
	_search_row.visible = page == "home"
	_tiles.visible = page == "home"
	for child in _tiles.get_children():
		child.queue_free()
	if is_instance_valid(_list):
		_list.queue_free()
	_list = null
	_rows.clear()
	_status.text = ""


func _go_back() -> void:
	if _page == "books" and _books_from_search:
		_show_search(_last_query)
	elif _page == "books":
		_open_library(_library)
	else:
		_show_home()


func _reload_page() -> void:
	match _page:
		"home":
			_libraries.clear()
			_show_home()
		"series":
			_open_library(_library)
		"search":
			_show_search(_last_query)
		"books":
			_open_series(_series)


func _show_home() -> void:
	_set_page("home", "Kavita")
	if not _libraries.is_empty():
		_build_tiles()
		return
	var token := _load_token
	_status.text = "Loading libraries…"
	var res: Dictionary = await KavitaClient.request_json(self, _config, "/api/Library/libraries")
	if token != _load_token:
		return
	if not res.ok or not (res.data is Array):
		_status.text = "Could not load libraries: %s." % KavitaClient.describe_error(res)
		return
	_libraries = res.data
	print("[Kavita] %d librar%s" % [_libraries.size(), "y" if _libraries.size() == 1 else "ies"])
	_build_tiles()
	# Reading profiles say which way a series or a library reads. A server
	# without them (before Kavita 0.8.7) answers 404 and Manga libraries decide.
	var profiles: Dictionary = await KavitaClient.request_json(self, _config, "/api/reading-profile/all")
	_profiles = profiles.data if profiles.ok and profiles.data is Array else []
	print("[Kavita] %d reading profile(s)" % _profiles.size())


func _build_tiles() -> void:
	_status.text = "" if not _libraries.is_empty() else "This Auth Key can see no libraries."
	_tiles.columns = maxi(1, int(size.x / TILE_MIN_WIDTH))
	for library: Dictionary in _libraries:
		var btn := Button.new()
		btn.add_theme_font_override("font", MenuIcons.symbols())
		var kavita := MenuIcons.kavita_mark()
		if kavita != null:
			btn.icon = kavita
			btn.add_theme_constant_override("icon_max_width", 48)
			btn.text = "  " + str(library.get("name", "Library"))
		else:
			btn.text = "%s  %s" % [String.chr(MenuIcons.BOOK), str(library.get("name", "Library"))]
		btn.add_theme_font_size_override("font_size", 22)
		btn.custom_minimum_size = Vector2(0, 96)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.clip_text = true
		SystemGridBrowser.style_tile(btn)
		btn.pressed.connect(_open_library.bind(library))
		_tiles.add_child(btn)


## Every series whose name matches, across the libraries this key can see.
func _show_search(query: String) -> void:
	var q := query.strip_edges()
	if q.is_empty():
		return
	_last_query = q
	_set_page("search", "Search: %s" % q)
	_make_list(_build_series_row, _bind_series_row)
	_series_all.clear()
	var token := _load_token
	_status.text = "Searching…"
	var res: Dictionary = await KavitaClient.request_json(self, _config,
		"/api/Search/search?queryString=%s&includeChapterAndFiles=false" % q.uri_encode())
	if token != _load_token:
		return
	if not res.ok or not (res.data is Dictionary):
		_status.text = "Search failed: %s." % KavitaClient.describe_error(res)
		return
	# A search result names its series as seriesId; the series page reads id.
	for hit: Dictionary in (res.data as Dictionary).get("series", []):
		_series_all.append({"id": int(hit.get("seriesId", 0)), "name": str(hit.get("name", "")),
			"libraryId": int(hit.get("libraryId", 0)), "libraryName": str(hit.get("libraryName", ""))})
	print("[Kavita] search '%s': %d series" % [q, _series_all.size()])
	_apply_filter()
	_status.text = "" if not _series_all.is_empty() else "Nothing on Kavita matches."


func _library_by_id(id: int) -> Dictionary:
	for library: Dictionary in _libraries:
		if int(library.get("id", 0)) == id:
			return library
	return {}


## Whether Kavita reads a series right to left: a reading profile bound to the
## series, else one bound to its library, else the default profile when it says
## right to left, else whether the library is of the Manga type.
func _right_to_left_for(series_id: int, library: Dictionary) -> bool:
	var library_id := int(library.get("id", 0))
	for key: String in ["seriesIds", "libraryIds"]:
		var want := series_id if key == "seriesIds" else library_id
		if want <= 0:
			continue
		for profile: Dictionary in _profiles:
			var ids: Array = profile.get(key, [])
			# JSON numbers arrive as floats.
			if ids.has(want) or ids.has(float(want)):
				return int(profile.get("readingDirection", 0)) == PROFILE_RIGHT_TO_LEFT
	for profile: Dictionary in _profiles:
		if int(profile.get("kind", -1)) == 0 and int(profile.get("readingDirection", 0)) == PROFILE_RIGHT_TO_LEFT:
			return true
	return int(library.get("type", -1)) == LIBRARY_MANGA


func _open_library(library: Dictionary) -> void:
	_library = library
	_set_page("series", str(library.get("name", "Library")))
	_make_list(_build_series_row, _bind_series_row)
	_series_all.clear()
	var token := _load_token
	_status.text = "Loading series…"
	# Pages of a hundred, the list filling as each lands: a large library is
	# thousands of series.
	var page := 1
	var filter := {"statements": [{"field": 19, "comparison": 0, "value": str(int(library.get("id", 0)))}],
		"combination": 0}
	while true:
		var res: Dictionary = await KavitaClient.request_json(self, _config,
			"/api/Series/all-v2?pageNumber=%d&pageSize=%d" % [page, SERIES_PAGE], HTTPClient.METHOD_POST, filter)
		if token != _load_token:
			return
		if not res.ok or not (res.data is Array):
			_status.text = "Could not load series: %s." % KavitaClient.describe_error(res)
			return
		_series_all.append_array(res.data)
		_apply_filter()
		if (res.data as Array).size() < SERIES_PAGE:
			break
		page += 1
	print("[Kavita] %s: %d series (library type %s%s)" % [_title.text, _series_all.size(),
		str(library.get("type", "?")), ", manga: right to left" if int(library.get("type", -1)) == LIBRARY_MANGA else ""])
	_status.text = "" if not _series_all.is_empty() else "No series in this library."


func _open_series(series: Dictionary) -> void:
	_books_from_search = _page == "search"
	if series.has("libraryId"):
		var library := _library_by_id(int(series["libraryId"]))
		if not library.is_empty():
			_library = library
	_series = series
	_set_page("books", str(series.get("name", "Series")))
	_make_list(_build_book_row, _bind_book_row)
	_books_all.clear()
	var token := _load_token
	_status.text = "Loading books…"
	var res: Dictionary = await KavitaClient.request_json(self, _config,
		"/api/Series/volumes?seriesId=%d" % int(series.get("id", 0)))
	if token != _load_token:
		return
	if not res.ok or not (res.data is Array):
		_status.text = "Could not load books: %s." % KavitaClient.describe_error(res)
		return
	var skipped := 0
	for volume: Dictionary in res.data:
		for chapter: Dictionary in volume.get("chapters", []):
			var book := _book_of(volume, chapter)
			if book.is_empty():
				skipped += 1
			else:
				_books_all.append(book)
	print("[Kavita] %s: %d books, %d in a format the reader cannot open" % [_title.text, _books_all.size(), skipped])
	_apply_filter()
	if _books_all.is_empty():
		_status.text = "No books here that RetroXR can open."


## One row's worth of a chapter, or {} for a format the reader cannot open.
func _book_of(volume: Dictionary, chapter: Dictionary) -> Dictionary:
	var files: Array = chapter.get("files", [])
	if files.is_empty() or not (files[0] is Dictionary):
		return {}
	var ext := str((files[0] as Dictionary).get("extension", "")).trim_prefix(".").to_lower()
	var comic := ext in COMIC_ARCHIVES or (ext == "cbz" and files.size() > 1)
	if not comic and (ext not in FILE_FORMATS or files.size() != 1):
		return {}
	var bytes := 0
	for f: Variant in files:
		if f is Dictionary:
			bytes += int((f as Dictionary).get("bytes", 0))
	var id := int(chapter.get("id", 0))
	var revision := "%d:%s" % [bytes, str(chapter.get("lastModifiedUtc", ""))]
	var saved_ext := "cbz" if comic else ext
	return {
		"id": id,
		"name": _book_name(volume, chapter),
		"comic": comic,
		"source_ext": ext,
		"bytes": bytes,
		"pages": int(chapter.get("pages", 0)),
		"revision": revision,
		"right_to_left": _right_to_left_for(int(_series.get("id", 0)), _library),
		# Kavita serves a comic's or a PDF's pages as images: those read without downloading.
		"streams": comic or ext == "cbz" or ext == "pdf",
		"path": _cache_dir().path_join("%d-%s.%s" % [id, revision.md5_text(), saved_ext]),
	}


func _book_name(volume: Dictionary, chapter: Dictionary) -> String:
	for key: String in ["titleName", "title"]:
		var t := str(chapter.get(key, "")).strip_edges()
		# A book that is a whole volume (a comic's trade) gets Kavita's stand-in
		# chapter, whose title is its number, -100000: that says nothing.
		if _says_something(t):
			return t
	var parts: PackedStringArray = []
	var vol := str(volume.get("name", "")).strip_edges()
	if _says_something(vol):
		parts.append("Volume " + vol)
	var number := str(chapter.get("range", chapter.get("number", ""))).strip_edges()
	if _says_something(number):
		parts.append("Chapter " + number)
	return " · ".join(parts) if not parts.is_empty() else str(_series.get("name", "Book"))


## False for an empty name or one of Kavita's stand-in numbers: -100000 for a
## loose chapter or volume, 100000 for its specials, and 0.
static func _says_something(text: String) -> bool:
	if text.is_empty():
		return false
	if text.is_valid_float():
		var n := absf(text.to_float())
		return n > 0.0 and n < 100000.0
	return true


func _cache_dir() -> String:
	return "user://kavita_cache/" + _identity.md5_text()


func _apply_filter() -> void:
	var needle := _filter.text.strip_edges().to_lower()
	var source := _series_all if _page == "series" or _page == "search" else _books_all
	_rows.clear()
	for item: Dictionary in source:
		if needle.is_empty() or str(item.get("name", "")).to_lower().contains(needle):
			_rows.append(item)
	if is_instance_valid(_list):
		_list.set_row_count(_rows.size())
		_list.rebind_visible()


# ── Rows, the RomM list's shape ──────────────────────────────────────────────

func _make_list(builder: Callable, binder: Callable) -> void:
	_list = VirtualRowList.new()
	_list.row_height = ROW_HEIGHT
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.set_row_builder(builder)
	_list.set_row_binder(binder)
	add_child(_list)


func _cover_rect() -> TextureRect:
	var cover := TextureRect.new()
	cover.name = "Cover"
	cover.custom_minimum_size = Vector2(72, 96)
	cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return cover


func _title_button() -> MarqueeButton:
	var main := MarqueeButton.create("", 22)
	main.name = "Main"
	main.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return main


func _build_series_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_cover_rect())
	row.add_child(_title_button())
	return row


func _bind_series_row(row: Control, index: int) -> void:
	if index < 0 or index >= _rows.size():
		return
	var series: Dictionary = _rows[index]
	var main := row.get_node("Main") as MarqueeButton
	_disconnect_all(main.pressed)
	main.set_marquee_text("  " + str(series.get("name", "Untitled")))
	main.pressed.connect(_open_series.bind(series))
	var cover := row.get_node("Cover") as TextureRect
	cover.texture = _art.get_or_request("series", int(series.get("id", 0)),
		str(series.get("lastChapterAddedUtc", series.get("lastChapterAdded", ""))))


func _build_book_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var state := Button.new()
	state.name = "State"
	state.custom_minimum_size = Vector2(76, ROW_HEIGHT)
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
	row.add_child(_cover_rect())
	row.add_child(_title_button())
	return row


func _bind_book_row(row: Control, index: int) -> void:
	if index < 0 or index >= _rows.size():
		return
	var book: Dictionary = _rows[index]
	var id := int(book.id)
	var path := str(book.path)
	var state := row.get_node("State") as Button
	var pct := state.get_node("Pct") as Label
	var main := row.get_node("Main") as MarqueeButton
	_disconnect_all(state.pressed)
	_disconnect_all(main.pressed)
	main.set_marquee_text("  " + str(book.name))
	(row.get_node("Cover") as TextureRect).texture = _art.get_or_request("chapter", id, str(book.revision))

	pct.visible = false
	var queued := _queue.any(func(j: Dictionary) -> bool: return int(j.id) == id)
	if id == _active_id or queued:
		state.add_theme_font_size_override("font_size", 40)
		state.text = String.chr(MenuIcons.BUSY)
		state.add_theme_color_override("font_color", MenuIcons.TINT_BUSY)
		state.tooltip_text = "Downloading" if id == _active_id else "Waiting to download"
		pct.visible = true
		pct.add_theme_color_override("font_color", MenuIcons.TINT_BUSY)
		pct.text = "%d%%" % _active_pct if id == _active_id else "…"
	elif FileAccess.file_exists(path):
		state.add_theme_font_size_override("font_size", 40)
		state.text = String.chr(MenuIcons.DELETE)
		var armed := _delete_armed == id
		state.add_theme_color_override("font_color", Color(1, 0.7, 0.7) if armed else MenuIcons.TINT_DELETE)
		state.tooltip_text = "Press again to delete" if armed else "Delete the copy on this device"
		state.pressed.connect(_on_delete_pressed.bind(book))
		main.tooltip_text = "Open the copy on this device"
		main.pressed.connect(_open_book.bind(book, path))
	else:
		state.add_theme_font_size_override("font_size", 44)
		state.text = String.chr(MenuIcons.DOWNLOAD)
		state.add_theme_color_override("font_color", MenuIcons.TINT_DOWNLOAD)
		state.tooltip_text = "Download from Kavita (%s)" % ByteSize.human(int(book.bytes))
		state.pressed.connect(_enqueue.bind(book))
		if bool(book.get("streams", false)):
			# Read straight off the server; the download button keeps a copy.
			main.tooltip_text = "Read from Kavita without downloading"
			main.pressed.connect(_open_book.bind(book, KavitaPages.path_for(id)))
		else:
			main.tooltip_text = "Download from Kavita (%s)" % ByteSize.human(int(book.bytes))
			main.pressed.connect(_enqueue.bind(book))


## Spawn a book: a downloaded copy (marked as just used, so it is the last the
## budget removes) or a kavita:// stream.
func _open_book(book: Dictionary, path: String) -> void:
	if not KavitaPages.is_remote(path):
		KavitaCache.touch(path)
	print("[Kavita] opening chapter %d %s%s" % [int(book.id),
		"streamed" if KavitaPages.is_remote(path) else "from the device",
		", right to left" if bool(book.right_to_left) else ""])
	book_selected.emit(path, bool(book.right_to_left))


## Every book file open in the room right now, which the budget never removes.
static func open_book_paths(any: Node) -> PackedStringArray:
	var out := PackedStringArray()
	if any == null or not any.is_inside_tree():
		return out
	for n: Node in any.get_tree().root.find_children("*", "RigidBody3D", true, false):
		if n is PDFBook:
			out.append(str((n as PDFBook).pdf_path))
	return out


static func _disconnect_all(sig: Signal) -> void:
	for c: Dictionary in sig.get_connections():
		sig.disconnect(c["callable"])


func _on_delete_pressed(book: Dictionary) -> void:
	var id := int(book.id)
	if _delete_armed != id:
		# Two presses, as a row's trash glyph is a reach away from its title.
		_delete_armed = id
		_list.rebind_visible()
		get_tree().create_timer(3.0).timeout.connect(func() -> void:
			if _delete_armed == id:
				_delete_armed = 0
				if is_instance_valid(_list):
					_list.rebind_visible())
		return
	_delete_armed = 0
	var err := DirAccess.remove_absolute(str(book.path))
	print("[Kavita] deleted chapter %d's copy (%s): %s" % [id, book.path, error_string(err)])
	if is_instance_valid(_list):
		_list.rebind_visible()


# ── Downloads, one at a time ─────────────────────────────────────────────────

func _enqueue(book: Dictionary) -> void:
	var id := int(book.id)
	if id <= 0 or id == _active_id or _queue.any(func(j: Dictionary) -> bool: return int(j.id) == id):
		return
	_queue.append(book)
	print("[Kavita] queued chapter %d (%s, %s)" % [id, book.source_ext, ByteSize.human(int(book.bytes))])
	if is_instance_valid(_list):
		_list.rebind_visible()
	_pump()


func _pump() -> void:
	if _active_id != 0 or _queue.is_empty():
		return
	var book: Dictionary = _queue.pop_front()
	_active_id = int(book.id)
	_active_pct = 0
	var key := "kavita:dl:%d" % _active_id
	_notify(key, "⬇", "%s · %s" % [book.name, ByteSize.human(int(book.bytes))], 0.0)
	DirAccess.make_dir_recursive_absolute(str(book.path).get_base_dir())
	var res: Dictionary
	if bool(book.comic):
		res = await KavitaClient.fetch_comic_as_cbz(self, _config, _active_id, int(book.pages),
			str(book.path), _on_progress.bind(book, true))
	else:
		res = await KavitaClient.download(self, _config, "/api/Download/chapter?chapterId=%d" % _active_id,
			str(book.path), _on_progress.bind(book, false))
	_active_id = 0
	if res.ok:
		print("[Kavita] chapter %d downloaded to %s" % [int(book.id), book.path])
		_notify(key, "✅", "%s downloaded" % book.name, -1.0, MenuToasts.DWELL_OK)
		KavitaCache.touch(str(book.path))
		var keep := open_book_paths(self)
		keep.append(str(book.path))
		KavitaCache.evict(_cache_dir(), _config.cache_budget_bytes(), keep)
	else:
		var code := int(res.get("code", 0))
		var why := ("the account may not have download permission" if code == 401 or code == 403
			else KavitaClient.describe_error(res))
		print("[Kavita] chapter %d failed: %s" % [int(book.id), why])
		_notify(key, "❌", "%s did not download: %s" % [book.name, why], -1.0, MenuToasts.DWELL_FAIL)
	if is_instance_valid(_list):
		_list.rebind_visible()
	_pump()


## Bytes for a file, pages for a comic. Acts only when the whole percentage
## moves: progress arrives every frame.
func _on_progress(done: int, total: int, book: Dictionary, comic: bool) -> void:
	if total <= 0 and not comic:
		total = int(book.bytes)
	var frac := clampf(float(done) / float(total), 0.0, 1.0) if total > 0 else 0.0
	var pct := int(frac * 100.0)
	if pct == _active_pct and done < total:
		return
	_active_pct = pct
	var amount := ("page %d of %d" % [done, total]) if comic \
		else "%s / %s" % [ByteSize.human(done), ByteSize.human(total)]
	_notify("kavita:dl:%d" % int(book.id), "⬇", "%s · %d%% · %s" % [book.name, pct, amount], frac)
	if is_instance_valid(_list):
		_list.rebind_visible()
