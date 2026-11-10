## AntennaOptions2D — 2D UI for an aerial: where its channels come from, and what
## they are. Loaded into AntennaOptionsPanel's SubViewport via XRToolsViewport2DIn3D.
##
## This was the television's "Channels" tab. It moved with the thing it describes:
## the HDHomeRun is what the aerial IS in this room, so its address, its status and
## the list it reports belong on the aerial, and a set with nothing in its coax
## socket has neither channels nor anywhere to configure them.
##
## Two ribbons, one per source: HDHomeRun (the tuner's box and the broadcast rows it
## reports) and IPTV (the M3U playlist box and the rows it lists). Each ribbon's
## list holds only its own source's channels; the "where the lead goes" line sits
## above both because it governs either.
##
## Emits:
##   channel_selected(index)            — a row in the list was clicked
##   tuner_settings_changed(auto, host) — write them to channels.json
##   channels_refresh_requested         — re-read channels.json and look again
##   playlist_settings_changed(on, url) — the M3U playlist box was edited
##   close_requested                    — user pressed ✕
class_name AntennaOptions2D
extends Control

signal close_requested
## A row in the channel list was clicked.
signal channel_selected(index: int)
## The tuner's auto/address settings were edited; write them to channels.json.
signal tuner_settings_changed(auto: bool, host: String)
## Refresh pressed — re-read channels.json and go looking for the tuner again.
signal channels_refresh_requested
## The IPTV playlist box was edited; write it to channels.json and fetch again.
signal playlist_settings_changed(enabled: bool, url: String)

# ── Palette (matches TVOptions2D / CoreOptions2D) ────────────────────────────────
const COLOR_BG    := Color(0.08, 0.08, 0.16, 0.96)
const COLOR_TITLE := Color(0.9,  0.9,  1.0)
const COLOR_ROW   := Color(0.65, 0.65, 0.80)
const COLOR_WARN  := Color(1.0,  0.80, 0.35)

var _tabs: TabContainer = null
## Per ribbon: its scroll and its list, in tab order (HDHomeRun, IPTV).
var _scrolls: Array[ScrollContainer] = []
var _lists: Array[VirtualRowList] = []
## Per ribbon: indices into _channels of the rows that ribbon lists.
var _tab_rows: Array = [[], []]
var _auto_toggle: VRCheck = null
var _host_edit: LineEdit = null
var _tuner_status: Label = null
var _link_status: Label = null
var _playlist_toggle: VRCheck = null
var _playlist_edit: LineEdit = null
var _playlist_status: Label = null
var _channels: Array[Dictionary] = []
var _current_channel := -1
# Whether a row can be clicked: only while the lead actually reaches a set.
var _can_tune := false
# The address discovered by the tuner, shown greyed while auto is on so the box
# always says where it is even when nobody typed it.
var _discovered_host := ""
# Guard so populate_*() doesn't re-emit signals when it sets control values.
var _suppress_signal := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()


func _build_ui() -> void:
	var margin := MenuStyle.panel_root(self, COLOR_BG, 10, 12)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 6)
	margin.add_child(root_vbox)

	MenuStyle.close_button(MenuStyle.title_row(root_vbox, "Antenna"),
		func() -> void: close_requested.emit())

	root_vbox.add_child(HSeparator.new())

	# Where the lead goes. First, because it answers the question every other row
	# raises: a full channel list that nothing is showing is a lead lying on the floor.
	_link_status = Label.new()
	_link_status.text = "—"
	_link_status.add_theme_font_size_override("font_size", 16)
	_link_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root_vbox.add_child(_link_status)

	# One ribbon per source. Each holds its source's box and only its own rows.
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_font_size_override("font_size", 18)
	root_vbox.add_child(_tabs)

	var hd_page := _tab_page("HDHomeRun")
	_build_tuner_box(hd_page)
	hd_page.add_child(HSeparator.new())
	_add_channel_list(hd_page, 0)

	var pl_page := _tab_page("IPTV (M3U)")
	_build_playlist_box(pl_page)
	pl_page.add_child(HSeparator.new())
	_add_channel_list(pl_page, 1)


func _tab_page(title: String) -> VBoxContainer:
	var page := VBoxContainer.new()
	page.name = title
	page.add_theme_constant_override("separation", 6)
	_tabs.add_child(page)
	return page


func _build_tuner_box(parent: VBoxContainer) -> void:
	# Caption on the left, box on the right — the shape the book and VCR panels
	# already use, and the reason VRCheck carries no text of its own.
	var auto_row := HBoxContainer.new()
	auto_row.add_theme_constant_override("separation", 8)
	auto_row.custom_minimum_size = Vector2(0, 52)
	parent.add_child(auto_row)

	var auto_lbl := Label.new()
	auto_lbl.text = "Find tuner automatically"
	auto_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	auto_lbl.add_theme_font_size_override("font_size", 18)
	auto_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	auto_row.add_child(auto_lbl)

	_auto_toggle = VRCheck.create(true, _on_auto_toggled)
	auto_row.add_child(_auto_toggle)

	var addr_row := HBoxContainer.new()
	addr_row.add_theme_constant_override("separation", 8)
	parent.add_child(addr_row)

	var addr_lbl := Label.new()
	addr_lbl.text = "Address"
	addr_lbl.add_theme_font_size_override("font_size", 18)
	addr_lbl.add_theme_color_override("font_color", COLOR_ROW)
	addr_lbl.custom_minimum_size = Vector2(90, 0)
	addr_row.add_child(addr_lbl)

	_host_edit = LineEdit.new()
	_host_edit.placeholder_text = "192.168.0.100"
	_host_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_host_edit.custom_minimum_size = Vector2(0, 38)
	_host_edit.add_theme_font_size_override("font_size", 18)
	_host_edit.text_submitted.connect(func(_t: String) -> void: _commit_tuner())
	_host_edit.focus_exited.connect(_commit_tuner)
	addr_row.add_child(_host_edit)

	var refresh_btn := Button.new()
	refresh_btn.text = "Refresh"
	refresh_btn.add_theme_font_size_override("font_size", 18)
	refresh_btn.custom_minimum_size = Vector2(105, 38)
	refresh_btn.focus_mode = Control.FOCUS_NONE
	refresh_btn.pressed.connect(_on_refresh)
	addr_row.add_child(refresh_btn)

	_tuner_status = Label.new()
	_tuner_status.text = "—"
	_tuner_status.add_theme_font_size_override("font_size", 15)
	_tuner_status.add_theme_color_override("font_color", COLOR_ROW)
	_tuner_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(_tuner_status)


func _build_playlist_box(parent: VBoxContainer) -> void:
	# Same caption-then-box shape as the tuner's. The URL is one m3u source in
	# channels.json; .m3u files dropped in the tv folder need nothing typed here,
	# and the status line names that folder so a player can find it.
	var pl_row := HBoxContainer.new()
	pl_row.add_theme_constant_override("separation", 8)
	pl_row.custom_minimum_size = Vector2(0, 52)
	parent.add_child(pl_row)

	var pl_lbl := Label.new()
	pl_lbl.text = "Use playlist URL"
	pl_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pl_lbl.add_theme_font_size_override("font_size", 18)
	pl_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pl_row.add_child(pl_lbl)

	_playlist_toggle = VRCheck.create(true, func(_on: bool) -> void: _commit_playlist())
	pl_row.add_child(_playlist_toggle)

	_playlist_edit = LineEdit.new()
	_playlist_edit.placeholder_text = "https://example.com/playlist.m3u"
	_playlist_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_playlist_edit.custom_minimum_size = Vector2(0, 38)
	_playlist_edit.add_theme_font_size_override("font_size", 16)
	_playlist_edit.text_submitted.connect(func(_t: String) -> void: _commit_playlist())
	_playlist_edit.focus_exited.connect(_commit_playlist)
	parent.add_child(_playlist_edit)

	_playlist_status = Label.new()
	_playlist_status.text = "—"
	_playlist_status.add_theme_font_size_override("font_size", 15)
	_playlist_status.add_theme_color_override("font_color", COLOR_ROW)
	_playlist_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(_playlist_status)


## A ribbon's channel list. Virtualized because a broadcast lineup runs to 80-odd
## rows and building that many real Controls in a Viewport2DIn3D is not free.
func _add_channel_list(parent: VBoxContainer, tab: int) -> void:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	MenuStyle.fat_vscroll_bar(scroll)
	parent.add_child(scroll)

	var list := VirtualRowList.new()
	list.row_height = 46
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.set_row_builder(_build_channel_row)
	list.set_row_binder(func(row: Control, i: int) -> void:
		var rows: Array = _tab_rows[tab]
		_bind_channel_row(row, int(rows[i]) if i >= 0 and i < rows.size() else -1))
	scroll.add_child(list)
	_scrolls.append(scroll)
	_lists.append(list)


func _build_channel_row() -> Control:
	var btn := Button.new()
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_font_size_override("font_size", 18)
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, 44)
	return btn


func _bind_channel_row(row: Control, index: int) -> void:
	var btn := row as Button
	if index < 0 or index >= _channels.size():
		btn.text = ""
		btn.disabled = true
		return
	var ch: Dictionary = _channels[index]
	var number := str(ch.get("number", ""))
	var label := str(ch.get("name", ""))
	var hd := "  HD" if bool(ch.get("hd", false)) else ""
	var group := str(ch.get("group", ""))
	if not group.is_empty():
		label += "  · %s" % group
	# The list is worth reading with the lead loose — it is how you find out the
	# aerial works at all — but there is no set to tune, so the rows do nothing.
	btn.disabled = not _can_tune
	btn.text = "  %s  %s%s" % [number.rpad(6), label, hd]
	btn.add_theme_color_override("font_color",
		COLOR_TITLE if index == _current_channel else COLOR_ROW)
	# Rebound on every scroll, so the old row's connection has to go first or the
	# button ends up tuning several different channels at once.
	for c in btn.pressed.get_connections():
		btn.pressed.disconnect(c["callable"])
	btn.pressed.connect(func() -> void: channel_selected.emit(index))


# ── Public API: driven by AntennaOptionsPanel from the aerial's lineup ─────────

## Say where the lead goes. `tv_name` is empty while it reaches no television;
## `via_switch` is whether an RF switch is in the way.
func populate_link(tv_name: String, via_switch: bool) -> void:
	if _link_status == null:
		return
	_can_tune = not tv_name.is_empty()
	if tv_name.is_empty():
		_link_status.text = "Not connected to a television — plug the lead into a " \
			+ "set's aerial socket, or an RF switch's ANT socket."
		_link_status.add_theme_color_override("font_color", COLOR_WARN)
	else:
		_link_status.text = "Feeding %s%s" % [tv_name,
			" through an RF switch" if via_switch else ""]
		_link_status.add_theme_color_override("font_color", COLOR_TITLE)
	_rebind_lists()


## Refresh the list and which row is lit.
func populate_channels(channels: Array, current: int) -> void:
	_channels.clear()
	for c: Variant in channels:
		if c is Dictionary:
			_channels.append(c as Dictionary)
	_current_channel = current
	# Split by source: playlist rows to the IPTV ribbon, everything else (the
	# tuner's rows) to HDHomeRun. Indices stay into _channels, so a click still
	# emits the index the lineup knows.
	_tab_rows = [[], []]
	for i in _channels.size():
		var tab := 1 if str(_channels[i].get("source", "")) == "m3u" else 0
		(_tab_rows[tab] as Array).append(i)
	for t in _lists.size():
		_lists[t].set_row_count((_tab_rows[t] as Array).size())
	_rebind_lists()


func _rebind_lists() -> void:
	for list in _lists:
		list.rebind_visible()


## Sync the tuner controls. `status` is already-worded text for the status line.
func populate_tuner(auto: bool, host: String, discovered: String, status: String) -> void:
	_suppress_signal = true
	_discovered_host = discovered
	if _auto_toggle:
		_auto_toggle.button_pressed = auto
	if _host_edit:
		# While auto is on the field shows what discovery found, greyed: the
		# address stays visible even when nobody typed it, and switching to manual
		# starts from something that works rather than an empty box.
		_host_edit.editable = not auto
		_host_edit.text = discovered if auto else host
		_host_edit.modulate = Color(1, 1, 1, 0.55 if auto else 1.0)
	if _tuner_status:
		_tuner_status.text = status
	_suppress_signal = false


## Sync the playlist box. `status` is already-worded text for its status line.
func populate_playlist(enabled: bool, url: String, status: String) -> void:
	_suppress_signal = true
	if _playlist_toggle:
		_playlist_toggle.button_pressed = enabled
	# Never overwrite what the player is typing.
	if _playlist_edit and not _playlist_edit.has_focus():
		_playlist_edit.text = url
	if _playlist_status:
		_playlist_status.text = status
	_suppress_signal = false


## Drive the list from an external stick or wheel input.
func scroll_active(pixels: float) -> void:
	if _tabs == null:
		return
	var t := _tabs.current_tab
	if t >= 0 and t < _scrolls.size():
		_scrolls[t].scroll_vertical += int(pixels)


func _on_auto_toggled(pressed: bool) -> void:
	if _suppress_signal:
		return
	if _host_edit:
		_host_edit.editable = not pressed
		_host_edit.modulate = Color(1, 1, 1, 0.55 if pressed else 1.0)
		if pressed and not _discovered_host.is_empty():
			_host_edit.text = _discovered_host
	_commit_tuner()


func _commit_tuner() -> void:
	if _suppress_signal or _auto_toggle == null or _host_edit == null:
		return
	tuner_settings_changed.emit(_auto_toggle.button_pressed, _host_edit.text.strip_edges())


func _commit_playlist() -> void:
	if _suppress_signal or _playlist_toggle == null or _playlist_edit == null:
		return
	playlist_settings_changed.emit(_playlist_toggle.button_pressed,
		_playlist_edit.text.strip_edges())


func _on_refresh() -> void:
	channels_refresh_requested.emit()
