## AvSwitchOptions2D — the AV selector's menu (AvSwitch), in AvSwitchOptionsPanel's SubViewport. Built in code as
## VCROptions2D is.
##
## Tabs:
##   Options — INPUT 1-4: the slide, from the menu (the one pressed is where it stands), each with what is on it
##   Debug   — AvSwitch.debug_state(): every jack, every source, the labels, TO TV, power, the chain and netplay
##   System  — the power rows (PowerMenuRows adds it)
class_name AvSwitchOptions2D
extends Control

## The player picked input `index` (0-3).
signal input_selected(index: int)
signal close_requested

const COLOR_BG := Color(0.08, 0.08, 0.16, 0.96)
const COLOR_ROW := Color(0.65, 0.65, 0.80)
const COLOR_ON := Color(1.0, 0.78, 0.45)

var _tabs: TabContainer = null
var _options_scroll: ScrollContainer = null
var _debug_scroll: ScrollContainer = null
var _debug_outer: Control = null
var _debug_rows: DebugRows = null
var _active_scroll: ScrollContainer = null
var _buttons: Array[Button] = []
var _notes: Array[Label] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	print("[AvSwitchOptions2D] UI built")


func _build_ui() -> void:
	var margin := MenuStyle.panel_root(self, COLOR_BG, 10, 12)
	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 6)
	margin.add_child(root_vbox)
	MenuStyle.close_button(MenuStyle.title_row(root_vbox, "AV Selector"),
		func() -> void: close_requested.emit())
	root_vbox.add_child(HSeparator.new())

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_font_size_override("font_size", 18)
	root_vbox.add_child(_tabs)

	var opts := VBoxContainer.new()
	opts.name = "Options"
	_tabs.add_child(opts)
	_options_scroll = MenuStyle.vscroll()
	opts.add_child(_options_scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 4)
	_options_scroll.add_child(rows)
	rows.add_child(MenuStyle.label("Slide: TO TV carries the selected input", 16, COLOR_ROW))
	for i in AvSwitch.INPUTS:
		var line := MenuStyle.hbox(10)
		rows.add_child(line)
		var b := MenuStyle.row_button("INPUT %d" % (i + 1), 22, 150, 56, false)
		b.toggle_mode = true
		var idx := i
		b.pressed.connect(func() -> void:
			print("[AvSwitchOptions2D] INPUT %d picked" % (idx + 1))
			input_selected.emit(idx))
		line.add_child(b)
		_buttons.append(b)
		var note := MenuStyle.label("nothing", 16, COLOR_ROW)
		note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		note.clip_text = true
		line.add_child(note)
		_notes.append(note)
	_active_scroll = _options_scroll

	_debug_outer = VBoxContainer.new()
	_debug_outer.name = "Debug"
	_tabs.add_child(_debug_outer)
	_debug_scroll = MenuStyle.vscroll()
	_debug_outer.add_child(_debug_scroll)
	_debug_rows = DebugRows.new()
	_debug_scroll.add_child(_debug_rows)

	_tabs.tab_changed.connect(_on_tab_changed)


func _on_tab_changed(_idx: int) -> void:
	var shown := _tabs.get_current_tab_control()
	if shown == _debug_outer:
		_active_scroll = _debug_scroll
		return
	var scrolls := shown.find_children("*", "ScrollContainer", true, false) if shown != null else []
	_active_scroll = scrolls[0] as ScrollContainer if not scrolls.is_empty() else _options_scroll


## The slide's input and, per input, a line on what is there and its label ("dark" / "lit" / "selected").
func populate(selected: int, sources: Array, labels: Array) -> void:
	for i in _buttons.size():
		_buttons[i].set_pressed_no_signal(i == selected)
		var what: String = sources[i] if i < sources.size() else "nothing"
		var lit: String = labels[i] if i < labels.size() else "dark"
		_notes[i].text = "%s, %s" % [what, lit]
		_notes[i].add_theme_color_override("font_color", COLOR_ON if lit != "dark" else COLOR_ROW)


## Whether the Debug tab is the one showing — the panel only reads the switch then.
func is_debug_tab_shown() -> bool:
	return _tabs != null and _tabs.get_current_tab_control() == _debug_outer


## Show the Debug tab (a probe's screenshot, a test).
func show_debug_tab() -> void:
	if _tabs != null and _debug_outer != null:
		_tabs.current_tab = _debug_outer.get_index()


## Fill the Debug tab from AvSwitch.debug_state().
func populate_debug(sections: Array) -> void:
	if _debug_rows:
		_debug_rows.show_sections(sections)


## Drive the active scroll container from an external stick input (pixels > 0 = down).
func scroll_active(pixels: float) -> void:
	if _active_scroll:
		_active_scroll.scroll_vertical += int(pixels)
