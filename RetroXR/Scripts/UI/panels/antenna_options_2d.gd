## AntennaOptions2D — 2D UI for an aerial: where its channels come from, and what
## they are. Loaded into AntennaOptionsPanel's SubViewport via XRToolsViewport2DIn3D.
##
## This was the television's "Channels" tab. It moved with the thing it describes:
## the HDHomeRun is what the aerial IS in this room, so its address, its status and
## the list it reports belong on the aerial, and a set with nothing in its coax
## socket has neither channels nor anywhere to configure them.
##
## Emits:
##   channel_selected(index)            — a row in the list was clicked
##   tuner_settings_changed(auto, host) — write them to channels.json
##   channels_refresh_requested         — re-read channels.json and look again
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

# ── Palette (matches TVOptions2D / CoreOptions2D) ────────────────────────────────
const COLOR_BG    := Color(0.08, 0.08, 0.16, 0.96)
const COLOR_TITLE := Color(0.9,  0.9,  1.0)
const COLOR_ROW   := Color(0.65, 0.65, 0.80)
const COLOR_WARN  := Color(1.0,  0.80, 0.35)

var _channels_scroll: ScrollContainer = null
var _channel_list: VirtualRowList = null
var _auto_toggle: VRCheck = null
var _host_edit: LineEdit = null
var _tuner_status: Label = null
var _link_status: Label = null
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

	# --- tuner box ---
	# Caption on the left, box on the right — the shape the book and VCR panels
	# already use, and the reason VRCheck carries no text of its own.
	var auto_row := HBoxContainer.new()
	auto_row.add_theme_constant_override("separation", 8)
	auto_row.custom_minimum_size = Vector2(0, 52)
	root_vbox.add_child(auto_row)

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
	root_vbox.add_child(addr_row)

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
	root_vbox.add_child(_tuner_status)

	root_vbox.add_child(HSeparator.new())

	# --- channel list ---
	# Virtualised because a broadcast lineup runs to 80-odd rows and building that
	# many real Controls in a Viewport2DIn3D is not free.
	_channels_scroll = ScrollContainer.new()
	_channels_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_channels_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_channels_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	MenuStyle.fat_vscroll_bar(_channels_scroll)
	root_vbox.add_child(_channels_scroll)

	_channel_list = VirtualRowList.new()
	_channel_list.row_height = 46
	_channel_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_channel_list.set_row_builder(_build_channel_row)
	_channel_list.set_row_binder(_bind_channel_row)
	_channels_scroll.add_child(_channel_list)


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

## Say where the lead goes. `set_name` is empty while it reaches no television;
## `via_switch` is whether an RF switch is in the way.
func populate_link(set_name: String, via_switch: bool) -> void:
	if _link_status == null:
		return
	_can_tune = not set_name.is_empty()
	if set_name.is_empty():
		_link_status.text = "Not connected to a television — plug the lead into a " \
			+ "set's aerial socket, or an RF switch's ANT socket."
		_link_status.add_theme_color_override("font_color", COLOR_WARN)
	else:
		_link_status.text = "Feeding %s%s" % [set_name,
			" through an RF switch" if via_switch else ""]
		_link_status.add_theme_color_override("font_color", COLOR_TITLE)
	if _channel_list:
		_channel_list.rebind_visible()


## Refresh the list and which row is lit.
func populate_channels(channels: Array, current: int) -> void:
	_channels.clear()
	for c: Variant in channels:
		if c is Dictionary:
			_channels.append(c as Dictionary)
	_current_channel = current
	if _channel_list:
		_channel_list.set_row_count(_channels.size())
		_channel_list.rebind_visible()


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


## Drive the list from an external stick or wheel input.
func scroll_active(pixels: float) -> void:
	if _channels_scroll:
		_channels_scroll.scroll_vertical += int(pixels)


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


func _on_refresh() -> void:
	channels_refresh_requested.emit()
