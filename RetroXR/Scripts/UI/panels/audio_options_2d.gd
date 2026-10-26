## AudioOptions2D — 2D UI for a CD or cassette player's settings.
## Loaded into AudioOptionsPanel's SubViewport via XRToolsViewport2DIn3D.
## Built programmatically, mirroring MouseOptions2D.
##
## The decks had no panel at all until float-in-place needed somewhere to live.
## Kept deliberately thin: the transport is on the unit's own face and on the
## remote, so this is for the properties of the OBJECT, not of the playback.
##
## Two tabs: Options (float in place) and Debug (RetroAudioPlayer.debug_state:
## the record, tape or disc, the player, the audio it decodes, the deck).
##
## Emits:
##   ignore_gravity_toggled(enabled) — float-in-place toggled
##   close_requested                 — user pressed ✕
class_name AudioOptions2D
extends Control

signal ignore_gravity_toggled(enabled: bool)
signal close_requested

const COLOR_BG    := Color(0.08, 0.08, 0.16, 0.96)
const COLOR_TITLE := Color(0.9,  0.9,  1.0)

var _title_lbl: Label = null
var _float_check: VRToggle = null
var _tabs: TabContainer = null
var _debug_scroll: ScrollContainer = null
var _debug_rows: DebugRows = null
## Guard so populate() doesn't re-emit while it sets the control.
var _suppress := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()


func _build_ui() -> void:
	var margin := MenuStyle.panel_root(self, COLOR_BG, 10, 12)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var title_row := MenuStyle.title_row(root, "Player")
	_title_lbl = title_row.get_child(0) as Label
	MenuStyle.close_button(title_row, func() -> void: close_requested.emit())

	root.add_child(HSeparator.new())

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_font_size_override("font_size", 18)
	root.add_child(_tabs)
	var opts := MenuStyle.vbox(10)
	opts.name = "Options"
	_tabs.add_child(opts)

	var dbg := VBoxContainer.new()
	dbg.name = "Debug"
	_tabs.add_child(dbg)
	_debug_scroll = MenuStyle.vscroll()
	dbg.add_child(_debug_scroll)
	_debug_rows = DebugRows.new()
	_debug_scroll.add_child(_debug_rows)

	_float_check = MenuStyle.float_toggle(opts)
	_float_check.toggled.connect(func(on: bool):
		if not _suppress:
			ignore_gravity_toggled.emit(on)
	)


## Whether the Debug tab is the one showing — the panel only reads the deck then.
func is_debug_tab_shown() -> bool:
	return _tabs != null and _tabs.current_tab == 1


## Fill the Debug tab from RetroAudioPlayer.debug_state().
func populate_debug(sections: Array) -> void:
	if _debug_rows:
		_debug_rows.show_sections(sections)


## Drive the Debug tab's scroll from an external stick input.
func scroll_active(pixels: float) -> void:
	if _debug_scroll and is_debug_tab_shown():
		_debug_scroll.scroll_vertical += int(pixels)


## Sync to the player's current state without re-emitting signals.
func populate(title: String, ignore_gravity: bool) -> void:
	_suppress = true
	if _title_lbl and not title.is_empty():
		_title_lbl.text = title
	if _float_check:
		_float_check.button_pressed = ignore_gravity
	_suppress = false
