## CoreOptions2D — 2D UI for libretro core options and controller port configuration.
## Loaded into CoreOptionsPanel's SubViewport via XRToolsViewport2DIn3D.
## Builds its entire UI programmatically (same pattern as SpawnMenu2D).
##
## Tabs:
##   Controls  — the machine's own switches: power, reset, open/eject, the RF
##               channel slide, a handheld's volume and video out, and which set
##               and input it is showing on (with any crossed cord)
##   Options   — cycle < / > through each core option value
##   Controllers — OptionButton per port to choose the active device type
##   System, BIOS, Cartridge, Saves — see their builders
##
## Emits:
##   option_changed(key, value)     — user changed a core option
##   port_device_changed(port, id)  — user changed a port's device type
##   close_requested                — user pressed ✕
class_name CoreOptions2D
extends Control

signal option_changed(key: String, value: String)
## User pressed "Reset all to defaults" at the top of the Options tab.
signal options_reset_requested
signal port_device_changed(port: int, device_id: int)
## Which physical gamepad drives this machine. Handhelds only — everything with a
## controller port takes a PadReceiver plugged into it instead.
signal pad_device_changed(guid: String, ordinal: int)
## System-tab toggle: show/hide the console's video-out cables.
signal video_out_toggled(enabled: bool)
## System-tab toggle: float in place where dropped (no gravity).
signal ignore_gravity_toggled(enabled: bool)
## System-tab toggle: a reflective-LCD handheld's screen lights itself.
signal screen_glow_toggled(enabled: bool)
## System-tab toggle (cabinets): wear the game's scraped art on the marquee and sides.
signal cabinet_art_toggled(enabled: bool)
## The cabinet's own say over the arcade attract option (ArcadeAttract.OVERRIDE_*).
signal attract_override_changed(mode: int)
## DIP tab (cabinets): open or shut the running core's own DIP screen on the game's screen.
signal dip_menu_requested
## DIP tab, Game memory (cabinets): set the game's saved memory aside, or put one set aside back (a copy's stamp).
signal memory_reset_requested
signal memory_restore_requested(stamp: String)
## System-tab slider: a handheld's volume, 0..1, the level its own wheel or slider
## sets.
signal volume_changed(value: float)
## The core picked for this machine on the System tab; "" is the system's default.
signal core_selected(core_name: String)
signal close_requested
## A Controls-tab control: "power" (bool), "reset", "eject" (null), "rf" (channel).
signal control_requested(id: String, value: Variant)

# ── Palette ────────────────────────────────────────────────────────────────────
const CoreOptionRow := preload("res://Scripts/UI/widgets/core_option_row.gd")

const COLOR_BG    := Color(0.08, 0.08, 0.16, 0.96)
const COLOR_TITLE := Color(0.9,  0.9,  1.0)
const COLOR_ROW   := Color(0.65, 0.65, 0.80)
## Matches MenuIcons.TINT_WARN so the "you can't change this" cue reads the same
## here as it does everywhere else in the menus.
const COLOR_LOCKED := Color(1.00, 0.72, 0.20)

# ── State ──────────────────────────────────────────────────────────────────────
var _options_scroll: ScrollContainer
var _options_rows: VBoxContainer
## Substring the Options tab is filtered by. A core can publish well over a
## hundred keys, and the list is alphabetical by description, so finding one by
## scrolling means knowing what its author called it.
var _options_filter: String = ""
var _options_search: LineEdit = null
var _controllers_scroll: ScrollContainer
var _controllers_rows: VBoxContainer
## Handhelds only — see _add_pad_row.
var _show_pad_picker := false
var _pad_guid := ""
var _pad_ordinal := 0
var _system_scroll: ScrollContainer
var _video_out_row: HBoxContainer = null
var _volume_box: VBoxContainer = null
var _volume_slider: HSlider = null
var _volume_value: Label = null
var _video_out_check: VRToggle = null
var _ignore_grav_check: VRToggle = null
var _screen_glow_row: Control = null
var _screen_glow_check: VRToggle = null
var _cabinet_art_row: HBoxContainer = null
var _dip_tab_idx := -1
var _dip_scroll: ScrollContainer = null
var _dip_rows: VBoxContainer = null
## What the DIP tab was last told: the core has a screen of its own, the cabinet is on, that screen is open.
var _dip_has_menu := false
var _dip_powered := false
var _dip_menu_open := false
## The Game memory section's state (RetroSystem.game_memory_state, {} for none), what the last action said, and until when a Reset is armed: it asks twice.
var _dip_memory: Dictionary = {}
var _dip_memory_note := ""
var _dip_reset_armed_until := 0
const MEMORY_CONFIRM_MS := 6000
var _cabinet_art_check: VRToggle = null
var _attract_row: HBoxContainer = null
var _attract_button: Button = null
var _attract_mode: int = 0
var _tabs: TabContainer = null
## The slotted cartridge's UI, embedded as a tab. Driven by the cartridge's own
## CartridgeOptionsPanel, which owns all the save/sync/achievement logic.
var _cart_ui: CartridgeOptions2D = null
var _cart_tab_idx: int = -1
## The backup memory a unit keeps on the machine itself, e.g. a Sega CD's.
var _saves_ui: MemoryCard2D = null
var _saves_tab_idx: int = -1
## Picks which memory the Saves tab shows when the machine has more than one.
var _saves_switch: HBoxContainer = null

## A memory on the Saves tab's switch was picked, by its index.
signal saves_source_picked(index: int)
var _system_tab_idx := -1
## The resolved core's declared firmware and whether each file is on disk.
## Hidden when the core declares none (see populate_firmware).
var _bios_scroll: ScrollContainer = null
var _bios_rows: VBoxContainer = null
var _bios_tab_idx := -1
var _active_scroll: ScrollContainer = null
var _options_tab_idx := -1
var _controllers_tab_idx := -1
# Controls tab.
var _controls_scroll: ScrollContainer = null
var _ctl_game: Label = null
var _ctl_display: Label = null
var _ctl_wiring: Label = null
var _ctl_power: VRToggle = null
var _ctl_reset: Button = null
var _ctl_eject: Button = null
var _ctl_rf: VRDropdown = null
## The channels _ctl_rf was built with, so it is rebuilt only when they change.
var _ctl_rf_options: Array = []
# Debug tab: what the core reports, as label/value rows.
var _debug_scroll: ScrollContainer = null
var _debug_rows: DebugRows = null
var _debug_tab_idx := -1
# Guard so populate_system() doesn't re-emit when it sets control values.
## The System tab's rows, and the core picker built into them by populate_cores().
var _system_rows: VBoxContainer = null
var _core_picker: Control = null
var _suppress_signal := false

var _definitions: Dictionary = {}
var _values: Dictionary = {}
## The core this machine will run, for the FRONTEND row. Empty until the first
## populate(), and empty for a system whose core cannot be resolved at all.
var _core_name: String = ""
## Shows _core_name beside the title.
var _core_lbl: Label = null
# Options the system model pins; shown locked rather than hidden, so it is clear
# why they cannot be changed instead of leaving them unexplained absences.
var _forced: Dictionary = {}
# Set when there are no options AND there is a reason worth stating.
var _unavailable: String = ""
# Array of Dictionaries: [{port, controllers: [{name, id}], current_id}]
var _controller_info: Array = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	print("[CoreOptions2D] UI built")


# ── UI construction ────────────────────────────────────────────────────────────

func _build_ui() -> void:
	# Rounded panel backdrop — same approach as SpawnMenu2D
	var margin := MenuStyle.panel_root(self, COLOR_BG, 10, 12)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 6)
	margin.add_child(root_vbox)

	# The title does not take the slack here — the core name below does, so the
	# two sit together on the left rather than at opposite ends of the row.
	var title_row := MenuStyle.title_row(root_vbox, "System Settings", 26, false)

	# Ellipsised and set to take the slack, so a long corename cannot push the
	# close button off the page.
	_core_lbl = Label.new()
	_core_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_core_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_core_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_core_lbl.add_theme_font_size_override("font_size", 20)
	_core_lbl.add_theme_color_override("font_color", COLOR_ROW)
	title_row.add_child(_core_lbl)
	_refresh_core_label()

	MenuStyle.close_button(title_row, func() -> void: close_requested.emit())

	root_vbox.add_child(HSeparator.new())

	# ── Tab container ──────────────────────────────────────────────────────────
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_font_size_override("font_size", 18)
	root_vbox.add_child(tabs)

	_build_controls_tab(tabs)

	# Options tab
	var opts_outer := VBoxContainer.new()
	opts_outer.name = "Options"
	tabs.add_child(opts_outer)
	_options_tab_idx = tabs.get_tab_count() - 1

	_options_search = LineEdit.new()
	_options_search.placeholder_text = "Search options"
	_options_search.clear_button_enabled = true
	_options_search.custom_minimum_size = Vector2(0, 44)
	_options_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_options_search.add_theme_font_size_override("font_size", 16)
	_options_search.text_changed.connect(_on_options_filter_changed)
	opts_outer.add_child(_options_search)

	_options_scroll = ScrollContainer.new()
	_options_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_options_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_options_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	MenuStyle.fat_vscroll_bar(_options_scroll)
	opts_outer.add_child(_options_scroll)

	_options_rows = VBoxContainer.new()
	_options_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_options_rows.add_theme_constant_override("separation", 2)
	_options_scroll.add_child(_options_rows)

	# Controllers tab
	var ctrl_outer := VBoxContainer.new()
	ctrl_outer.name = "Controllers"
	tabs.add_child(ctrl_outer)
	_controllers_tab_idx = tabs.get_tab_count() - 1

	_controllers_scroll = ScrollContainer.new()
	_controllers_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_controllers_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_controllers_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	MenuStyle.fat_vscroll_bar(_controllers_scroll)
	ctrl_outer.add_child(_controllers_scroll)

	_controllers_rows = VBoxContainer.new()
	_controllers_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_controllers_rows.add_theme_constant_override("separation", 4)
	_controllers_scroll.add_child(_controllers_rows)

	# System tab (device-level settings, not core options). The video-out row
	# only shows for handhelds — consoles' cables are always on.
	_tabs = tabs
	var sys_outer := VBoxContainer.new()
	sys_outer.name = "System"
	tabs.add_child(sys_outer)
	_system_tab_idx = tabs.get_tab_count() - 1

	# BIOS tab — which of the core's declared firmware files are installed.
	# Read-only; the spawn menu's Cores > BIOS page is where files are fetched.
	var bios_outer := VBoxContainer.new()
	bios_outer.name = "BIOS"
	tabs.add_child(bios_outer)
	_bios_tab_idx = tabs.get_tab_count() - 1

	_bios_scroll = ScrollContainer.new()
	_bios_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_bios_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_bios_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	MenuStyle.fat_vscroll_bar(_bios_scroll)
	bios_outer.add_child(_bios_scroll)

	_bios_rows = VBoxContainer.new()
	_bios_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bios_rows.add_theme_constant_override("separation", 4)
	_bios_scroll.add_child(_bios_rows)

	# Cartridge tab — the slotted cartridge's own saves and achievements, so they
	# are reachable without fishing the cartridge back out of the machine. The
	# whole tab is hidden when the slot is empty (see set_cartridge_tab_visible).
	#
	# An embedded CartridgeOptions2D rather than a reimplementation: the save
	# recovery, RomM sync and achievement list are already written there, and
	# CartridgeOptionsPanel drives this copy through adopt_external_ui().
	var cart_outer := VBoxContainer.new()
	cart_outer.name = "Cartridge"
	tabs.add_child(cart_outer)
	_cart_tab_idx = tabs.get_tab_count() - 1

	_cart_ui = CartridgeOptions2D.create_embedded()
	cart_outer.add_child(_cart_ui)

	# Saves tab — backup memory kept on the machine itself (a Sega CD's), listed
	# with the page a memory card shows and driven by that unit's MemoryCardPanel.
	# Hidden unless something attached keeps memory (see set_saves_tab_visible).
	var saves_outer := VBoxContainer.new()
	saves_outer.name = "Saves"
	tabs.add_child(saves_outer)
	_saves_tab_idx = tabs.get_tab_count() - 1
	tabs.set_tab_hidden(_saves_tab_idx, true)

	# Debug tab — what the running core says about itself. Last, being for a
	# player chasing a problem rather than one playing.
	var debug_outer := VBoxContainer.new()
	debug_outer.name = "Debug"
	tabs.add_child(debug_outer)
	_debug_tab_idx = tabs.get_tab_count() - 1
	_debug_scroll = ScrollContainer.new()
	_debug_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_debug_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_debug_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	MenuStyle.fat_vscroll_bar(_debug_scroll)
	debug_outer.add_child(_debug_scroll)
	_debug_rows = DebugRows.new()
	_debug_scroll.add_child(_debug_rows)
	# Which memory the page shows, when there is more than one: the unit's own and
	# a Backup RAM Cartridge in the slot.
	_saves_switch = HBoxContainer.new()
	_saves_switch.add_theme_constant_override("separation", 8)
	_saves_switch.visible = false
	saves_outer.add_child(_saves_switch)
	_saves_ui = MemoryCard2D.new()
	# The tab names the page and the menu has its own ✕.
	_saves_ui.show_name_field = false
	_saves_ui.size_flags_vertical = Control.SIZE_EXPAND_FILL
	saves_outer.add_child(_saves_ui)

	# DIP Switch tab, a cabinet's: hidden on every other machine (set_dip_tab_visible keeps the indices put).
	var dip_outer := VBoxContainer.new()
	dip_outer.name = "DIP Switch"
	tabs.add_child(dip_outer)
	_dip_tab_idx = tabs.get_tab_count() - 1
	tabs.set_tab_hidden(_dip_tab_idx, true)
	_dip_scroll = ScrollContainer.new()
	_dip_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dip_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_dip_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	MenuStyle.fat_vscroll_bar(_dip_scroll)
	dip_outer.add_child(_dip_scroll)
	_dip_rows = VBoxContainer.new()
	_dip_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dip_rows.add_theme_constant_override("separation", 4)
	_dip_scroll.add_child(_dip_rows)

	_system_scroll = ScrollContainer.new()
	_system_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_system_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_system_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	MenuStyle.fat_vscroll_bar(_system_scroll)
	sys_outer.add_child(_system_scroll)

	var sys_rows := VBoxContainer.new()
	_system_rows = sys_rows
	sys_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sys_rows.add_theme_constant_override("separation", 4)
	_system_scroll.add_child(sys_rows)

	# A handheld's Volume and Video Out moved to the Controls tab: they are the
	# machine's own switches, and that tab is where its switches are.

	var grav_row := HBoxContainer.new()
	grav_row.custom_minimum_size = Vector2(0, 56)
	grav_row.add_theme_constant_override("separation", 8)
	sys_rows.add_child(grav_row)

	var grav_lbl := Label.new()
	grav_lbl.text = "Ignore Gravity"
	grav_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grav_lbl.add_theme_font_size_override("font_size", 18)
	grav_lbl.add_theme_color_override("font_color", COLOR_ROW)
	grav_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	grav_row.add_child(grav_lbl)

	_ignore_grav_check = VRToggle.create(false, func(on: bool):
		if not _suppress_signal:
			ignore_gravity_toggled.emit(on))
	grav_row.add_child(_ignore_grav_check)

	# Only on a handheld whose real LCD had no light (populate_screen_glow): off,
	# it is lit by the room as the real one was; on, it glows like a backlight.
	var glow_row := HBoxContainer.new()
	glow_row.custom_minimum_size = Vector2(0, 56)
	glow_row.add_theme_constant_override("separation", 8)
	glow_row.visible = false
	sys_rows.add_child(glow_row)
	_screen_glow_row = glow_row

	var glow_lbl := Label.new()
	glow_lbl.text = "Self-Lit Screen"
	glow_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	glow_lbl.add_theme_font_size_override("font_size", 18)
	glow_lbl.add_theme_color_override("font_color", COLOR_ROW)
	glow_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glow_row.add_child(glow_lbl)

	_screen_glow_check = VRToggle.create(false, func(on: bool):
		if not _suppress_signal:
			screen_glow_toggled.emit(on))
	glow_row.add_child(_screen_glow_check)

	# A cabinet's art: hidden on every other machine.
	_cabinet_art_row = HBoxContainer.new()
	_cabinet_art_row.custom_minimum_size = Vector2(0, 56)
	_cabinet_art_row.add_theme_constant_override("separation", 8)
	_cabinet_art_row.visible = false
	sys_rows.add_child(_cabinet_art_row)

	var art_lbl := Label.new()
	art_lbl.text = "Cabinet Art"
	art_lbl.tooltip_text = "The game's marquee and side art on the cabinet. Off leaves it plain."
	art_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	art_lbl.add_theme_font_size_override("font_size", 18)
	art_lbl.add_theme_color_override("font_color", COLOR_ROW)
	art_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cabinet_art_row.add_child(art_lbl)

	_cabinet_art_check = VRToggle.create(true, func(on: bool):
		if not _suppress_signal:
			cabinet_art_toggled.emit(on))
	_cabinet_art_row.add_child(_cabinet_art_check)

	# A cabinet's attract mode: follow the global pref, or force it on or off for this one.
	_attract_row = HBoxContainer.new()
	_attract_row.custom_minimum_size = Vector2(0, 56)
	_attract_row.add_theme_constant_override("separation", 8)
	_attract_row.visible = false
	sys_rows.add_child(_attract_row)

	var attract_lbl := Label.new()
	attract_lbl.text = "Attract Mode"
	attract_lbl.tooltip_text = "Show the game's video while the cabinet is on, until a coin or a controller is used."
	attract_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	attract_lbl.add_theme_font_size_override("font_size", 18)
	attract_lbl.add_theme_color_override("font_color", COLOR_ROW)
	attract_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_attract_row.add_child(attract_lbl)

	_attract_button = Button.new()
	_attract_button.custom_minimum_size = Vector2(190, 44)
	_attract_button.add_theme_font_size_override("font_size", 16)
	_attract_button.pressed.connect(func():
		if _suppress_signal:
			return
		_attract_mode = (_attract_mode + 1) % 3
		_attract_button.text = _attract_text(_attract_mode)
		attract_override_changed.emit(_attract_mode))
	_attract_row.add_child(_attract_button)

	# Track which scroll container is active for stick-driven scrolling
	_active_scroll = _controls_scroll
	tabs.tab_changed.connect(func(idx: int):
		if idx == 0:
			_active_scroll = _controls_scroll
		elif idx == _options_tab_idx:
			_active_scroll = _options_scroll
		elif idx == _controllers_tab_idx:
			_active_scroll = _controllers_scroll
		elif idx == _system_tab_idx:
			_active_scroll = _system_scroll
		elif idx == _bios_tab_idx:
			_active_scroll = _bios_scroll
		elif idx == _debug_tab_idx:
			_active_scroll = _debug_scroll
		elif idx == _dip_tab_idx:
			_active_scroll = _dip_scroll
		else:
			# The Cartridge tab hosts a whole CartridgeOptions2D with ribbons of
			# its own, so it knows which of them is showing and this does not.
			# Clearing the reference is what makes scroll_active hand over.
			# Without this the stick scrolled the System tab while you were
			# looking at the cartridge page.
			_active_scroll = null
	)

	_show_options_placeholder()
	_show_controllers_placeholder()


# ── Controls: the machine's own switches ─────────────────────────────────────

## The first tab. Each row stands for a control the machine physically has, and is
## hidden where it has none (populate_controls), so a Game Boy shows no RESET and a
## cartridge console no OPEN.
func _build_controls_tab(tabs: TabContainer) -> void:
	var outer := VBoxContainer.new()
	outer.name = "Controls"
	tabs.add_child(outer)

	_controls_scroll = ScrollContainer.new()
	_controls_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_controls_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_controls_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	MenuStyle.fat_vscroll_bar(_controls_scroll)
	outer.add_child(_controls_scroll)

	var rows := MenuStyle.vbox(6)
	_controls_scroll.add_child(rows)

	# What is in it and where it is showing, read before anything is pressed.
	_ctl_game = MenuStyle.label("", 20, COLOR_TITLE)
	_ctl_game.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_ctl_game.clip_text = true
	rows.add_child(_ctl_game)
	_ctl_display = MenuStyle.label("", 18, COLOR_ROW)
	_ctl_display.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_ctl_display.clip_text = true
	rows.add_child(_ctl_display)
	# A cord in the wrong jack at the set, the same words the TV's menu uses.
	_ctl_wiring = MenuStyle.label("", 18, COLOR_LOCKED)
	_ctl_wiring.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ctl_wiring.visible = false
	rows.add_child(_ctl_wiring)
	rows.add_child(HSeparator.new())

	_ctl_power = MenuStyle.switch_row(rows, "Power", false)
	_ctl_power.toggled.connect(func(on: bool) -> void: _request_control("power", on))

	var keys := MenuStyle.hbox(8)
	rows.add_child(keys)
	_ctl_reset = _control_key("RESET", "reset")
	keys.add_child(_ctl_reset)
	_ctl_eject = _control_key("OPEN", "eject")
	keys.add_child(_ctl_eject)

	# Built on populate, from the channels the machine's own slide has.
	_ctl_rf = VRDropdown.create("RF channel", [["CH 3", 3]], 3)
	_ctl_rf.item_selected.connect(func(v: Variant) -> void: _request_control("rf", int(v)))
	_ctl_rf.visible = false
	rows.add_child(_ctl_rf)

	# A handheld's volume: a second way to its own wheel or slider, which it
	# follows while the panel is open. Hidden for a machine without one.
	_volume_box = VBoxContainer.new()
	_volume_box.add_theme_constant_override("separation", 2)
	# Hidden until populate_system says this is a handheld: a console's Controls
	# tab must not show a handheld's rows before (or without) that call.
	_volume_box.visible = false
	rows.add_child(_volume_box)
	var vol: Array = MenuStyle.slider_row(_volume_box, "Volume", 0.0, 100.0, 1.0)
	_volume_slider = vol[0]
	_volume_value = vol[1]
	(vol[2] as Label).add_theme_color_override("font_color", COLOR_ROW)
	_volume_slider.value_changed.connect(func(v: float) -> void:
		_volume_value.text = "%d%%" % roundi(v)
		if not _suppress_signal:
			volume_changed.emit(v / 100.0))

	_video_out_row = HBoxContainer.new()
	_video_out_row.custom_minimum_size = Vector2(0, 56)
	_video_out_row.add_theme_constant_override("separation", 8)
	_video_out_row.visible = false
	rows.add_child(_video_out_row)

	var vo_lbl := Label.new()
	vo_lbl.text = "Enable Video Out"
	vo_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vo_lbl.add_theme_font_size_override("font_size", 18)
	vo_lbl.add_theme_color_override("font_color", COLOR_ROW)
	vo_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_video_out_row.add_child(vo_lbl)

	_video_out_check = VRToggle.create(false, func(on: bool):
		if not _suppress_signal:
			video_out_toggled.emit(on))
	_video_out_row.add_child(_video_out_check)


func _request_control(id: String, value: Variant) -> void:
	if not _suppress_signal:
		control_requested.emit(id, value)


## A press-only key in RELEASE mode: a click in a Viewport2DIn3D arrives as two
## presses, and a press-mode RESET would reset twice (see MenuStyle.check).
func _control_key(text: String, id: String) -> Button:
	var b := MenuStyle.row_button(text, 18, 0, 52, false)
	b.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	b.focus_mode = Control.FOCUS_NONE
	var box := MenuStyle.rounded(Color(0.16, 0.16, 0.28), 6)
	for state in ["normal", "hover", "disabled"]:
		b.add_theme_stylebox_override(state, box)
	b.add_theme_stylebox_override("pressed", MenuStyle.rounded(Color(0.25, 0.45, 0.85), 6))
	b.pressed.connect(func() -> void: _request_control(id, null))
	return b


## Whether the Debug tab is the one showing — the panel only reads the core for it
## then.
func is_debug_tab_shown() -> bool:
	return _tabs != null and _tabs.current_tab == _debug_tab_idx


## Fill the Debug tab from RetroSystem.debug_state(): [[section, [[label, value]]]].
func populate_debug(sections: Array) -> void:
	if _debug_rows:
		_debug_rows.show_sections(sections)


## Sync the Controls tab to RetroSystem.controls_state() without re-emitting.
## Volume and Video Out are populate_system's and show_volume's, as before.
func populate_controls(state: Dictionary) -> void:
	if _ctl_power == null:
		return
	_suppress_signal = true
	var game := str(state.get("game", ""))
	_ctl_game.text = game if not game.is_empty() else "No game"
	var display := str(state.get("display", ""))
	_ctl_display.text = "Showing on: %s" % (display if not display.is_empty()
		else "nothing (no video lead to a set)")
	var wiring: Array = state.get("wiring", [])
	_ctl_wiring.visible = not wiring.is_empty()
	_ctl_wiring.text = "Crossed at the set: %s" % ", ".join(PackedStringArray(wiring))
	_ctl_power.button_pressed = bool(state.get("on", false))
	var has_reset := bool(state.get("has_reset", false))
	_ctl_reset.visible = has_reset
	# A reset needs a running core; the real button does nothing either.
	_ctl_reset.disabled = not bool(state.get("on", false))
	var eject := str(state.get("eject", ""))
	_ctl_eject.visible = not eject.is_empty()
	_ctl_eject.text = eject.to_upper()
	# A spring lid is shut by hand: the row says so and cannot do it.
	_ctl_eject.disabled = eject.begins_with("Close the lid")
	_ctl_reset.get_parent().visible = has_reset or not eject.is_empty()
	var rf_options: Array = state.get("rf_options", [])
	_ctl_rf.visible = not rf_options.is_empty()
	if not rf_options.is_empty():
		if rf_options != _ctl_rf_options:
			_ctl_rf_options = rf_options.duplicate()
			_ctl_rf.set_options(rf_options.map(func(ch: int) -> Array:
				return ["CH %d" % ch, ch]), int(state.get("rf_channel", rf_options[0])))
		_ctl_rf.select_id(int(state.get("rf_channel", rf_options[0])))
	_suppress_signal = false


# ── Public API ─────────────────────────────────────────────────────────────────

## Fill or refresh all tabs.
## controller_info: Array of Dicts [{port, controllers:[{name,id}], current_id}]
func populate(definitions: Dictionary, current_values: Dictionary, controller_info: Array,
		forced: Dictionary = {}, unavailable: String = "", core_name: String = "") -> void:
	_definitions = definitions
	_values = current_values
	_controller_info = controller_info
	_forced = forced
	_unavailable = unavailable
	_core_name = core_name
	_refresh_core_label()
	print("[CoreOptions2D] populate() — %d options, %d ports" % [definitions.size(), controller_info.size()])
	_refresh_options()
	_refresh_controllers()
	_refresh_dip()


## Sync the System tab to the device's current state (no signal re-emit).
## `show_video_out` false (consoles) hides just that row — their cable is
## always on; the tab stays for the other device toggles.
## The embedded cartridge UI, for CartridgeOptionsPanel.adopt_external_ui().
func cartridge_ui() -> CartridgeOptions2D:
	return _cart_ui


## Show the Cartridge tab only while something is in the slot. Hidden rather
## than removed so the index stays put and the UI never has to be rebuilt.
func set_cartridge_tab_visible(shown: bool) -> void:
	if _tabs == null or _cart_tab_idx < 0:
		return
	_tabs.set_tab_hidden(_cart_tab_idx, not shown)


## The DIP Switch tab. `shown`: this machine is a cabinet. `has_menu`: the running core has a DIP screen of
## its own, which the button opens on the game's screen; otherwise the core's DIP options are listed here.
func populate_dip(shown: bool, has_menu: bool, powered: bool, menu_open: bool, memory: Dictionary = {}) -> void:
	_dip_has_menu = has_menu
	_dip_powered = powered
	_dip_menu_open = menu_open
	_dip_memory = memory
	if _tabs != null and _dip_tab_idx >= 0:
		_tabs.set_tab_hidden(_dip_tab_idx, not shown)
	_refresh_dip()


## What the last Game memory action said, shown at the top of the section until the tab is filled again.
func show_memory_message(text: String) -> void:
	_dip_memory_note = text
	_dip_reset_armed_until = 0
	_refresh_dip()


func _refresh_dip() -> void:
	if _dip_rows == null:
		return
	for c in _dip_rows.get_children():
		c.queue_free()
	_refresh_dip_core()
	_dip_memory_rows()


## The core's own DIP screen button, or its DIP options listed.
func _refresh_dip_core() -> void:
	if _dip_has_menu:
		_dip_note("This game's DIP switches are on its own screen. Open them there, move with the stick or arrows, and press the button again to close.")
		var btn := Button.new()
		btn.text = "Close DIP Switches" if _dip_menu_open else "Open DIP Switches"
		btn.custom_minimum_size = Vector2(0, 64)
		btn.add_theme_font_size_override("font_size", 20)
		btn.pressed.connect(func() -> void: dip_menu_requested.emit())
		_dip_rows.add_child(btn)
		return
	var keys: Array = []
	for key in _definitions:
		if String(key).to_lower().contains(RetroSystem.DIP_OPTION_MARK):
			keys.append(key)
	keys.sort()
	if keys.is_empty():
		_dip_note("This core publishes no DIP switches%s." % ("" if _dip_powered else " until the game is running (turn the cabinet on)"))
		return
	for key in keys:
		var current := String(_values.get(key, ""))
		if _forced.has(key):
			current = str(_forced[key])
		CoreOptionRow.add(_dip_rows, key, _definitions[key], current, _forced.has(key),
			"(fixed by this system)", func(k: String, v: String) -> void:
				print("[CoreOptions2D] DIP '%s' -> '%s'" % [k, v])
				option_changed.emit(k, v))


## The Game memory section (ArcadeBackupMemory): what the game has saved, a Reset that asks twice, and the copies set aside to put back.
func _dip_memory_rows() -> void:
	if _dip_memory.is_empty():
		return
	var heading := Label.new()
	heading.text = "Game memory"
	heading.add_theme_font_size_override("font_size", 22)
	heading.add_theme_color_override("font_color", COLOR_TITLE)
	_dip_rows.add_child(heading)
	_dip_note("Saved: %s." % str(_dip_memory.get("summary", "nothing saved yet")))
	if not _dip_memory_note.is_empty():
		_dip_note(_dip_memory_note)
	if str(_dip_memory.get("class", "")) == "h":
		_dip_note("This game starts from a memory built by hand: the first start may say BACKUP DATA ERROR. Press TEST and follow the game's menu, then switch the cabinet off with its power switch so the game's memory is saved.")
	_dip_note("The game keeps its settings, high scores, bookkeeping and, for a gun game, its calibration here. Reset sets all of it aside (it can be put back) and the game starts as new. Saved states keep their own copy: loading one brings it back.")
	var can := bool(_dip_memory.get("can_change", false))
	var has_files := bool(_dip_memory.get("has_files", false))
	var armed := Time.get_ticks_msec() < _dip_reset_armed_until
	var reset := Button.new()
	reset.text = "Press again: set aside this game's memory" if armed else "Reset game memory"
	reset.custom_minimum_size = Vector2(0, 56)
	reset.add_theme_font_size_override("font_size", 20)
	reset.disabled = not can or not has_files
	reset.pressed.connect(func() -> void:
		if Time.get_ticks_msec() < _dip_reset_armed_until:
			_dip_reset_armed_until = 0
			memory_reset_requested.emit()
		else:
			_dip_reset_armed_until = Time.get_ticks_msec() + MEMORY_CONFIRM_MS
			_refresh_dip())
	_dip_rows.add_child(reset)
	if not can:
		_dip_note("Not now: %s." % str(_dip_memory.get("why_not", "")))
	elif not has_files:
		_dip_note("Nothing is saved yet: the game has not been switched off since it was first started.")
	var copies := _dip_memory.get("copies", []) as Array
	for i in mini(copies.size(), 5):
		var copy: Dictionary = copies[i]
		var stamp := str(copy["stamp"])
		var why := str(copy.get("reason", ""))
		var back := Button.new()
		back.text = "Put back %s%s" % [_stamp_words(stamp), (" (%s)" % why) if not why.is_empty() else ""]
		back.custom_minimum_size = Vector2(0, 44)
		back.add_theme_font_size_override("font_size", 16)
		back.clip_text = true
		back.disabled = not can
		back.pressed.connect(func() -> void: memory_restore_requested.emit(stamp))
		_dip_rows.add_child(back)


## "20261026T143005Z" as 2026-10-26 14:30 (UTC).
static func _stamp_words(stamp: String) -> String:
	if stamp.length() < 16:
		return stamp
	return "%s-%s-%s %s:%s UTC" % [stamp.substr(0, 4), stamp.substr(4, 2), stamp.substr(6, 2), stamp.substr(9, 2), stamp.substr(11, 2)]


func _dip_note(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", COLOR_ROW)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(0, 60)
	_dip_rows.add_child(lbl)


## The Saves tab's page, driven by the attached unit's MemoryCardPanel.
func saves_ui() -> MemoryCard2D:
	return _saves_ui


func set_saves_tab_visible(shown: bool) -> void:
	if _tabs == null or _saves_tab_idx < 0:
		return
	_tabs.set_tab_hidden(_saves_tab_idx, not shown)


## The memories the Saves tab can show and the one it is showing. The switch only
## appears with more than one. Deferred emit: the handler rebuilds these buttons,
## including the one being pressed.
func set_saves_sources(labels: PackedStringArray, current: int) -> void:
	if _saves_switch == null:
		return
	for c in _saves_switch.get_children():
		_saves_switch.remove_child(c)
		c.queue_free()
	_saves_switch.visible = labels.size() > 1
	for i in labels.size():
		var b := Button.new()
		b.text = labels[i]
		b.toggle_mode = true
		b.button_pressed = i == current
		b.custom_minimum_size = Vector2(0, 44)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(func() -> void: saves_source_picked.emit.call_deferred(i))
		_saves_switch.add_child(b)


## Fill the BIOS tab from FirmwareState.evaluate() rows for `core_name`. A core
## that declares no firmware gets no tab at all — an empty list would read as
## "nothing installed" when it means "nothing needed".
func populate_firmware(core_name: String, rows: Array[Dictionary]) -> void:
	if _tabs == null or _bios_tab_idx < 0:
		return
	for c in _bios_rows.get_children():
		_bios_rows.remove_child(c)
		c.queue_free()
	_tabs.set_tab_hidden(_bios_tab_idx, rows.is_empty())
	if rows.is_empty():
		return

	var summary := FirmwareState.summarise(rows)
	var badge := Label.new()
	badge.text = str(summary["badge"]).capitalize()
	badge.add_theme_font_size_override("font_size", 20)
	if int(summary["missing_required"]) > 0:
		badge.add_theme_color_override("font_color", MenuIcons.TINT_DELETE)
	elif int(summary["mismatched"]) > 0:
		badge.add_theme_color_override("font_color", MenuIcons.TINT_WARN)
	else:
		badge.add_theme_color_override("font_color", MenuIcons.TINT_OK)
	_bios_rows.add_child(badge)

	var path_lbl := Label.new()
	path_lbl.text = "Files go in:  %s" % CoreDownloadManager.default_system_dir(core_name)
	path_lbl.add_theme_font_size_override("font_size", 14)
	path_lbl.add_theme_color_override("font_color", MenuStyle.COLOR_DESC)
	path_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	path_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bios_rows.add_child(path_lbl)
	_bios_rows.add_child(HSeparator.new())

	for r: Dictionary in rows:
		var row := FirmwareRow.build(r, str(r.get("desc", "")))
		# The scrollbar is drawn over the content; keep the tag clear of it.
		var gutter := Control.new()
		gutter.custom_minimum_size = Vector2(44, 0)
		gutter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(gutter)
		_bios_rows.add_child(row)


## The core picker on the System tab: the cores installed for this machine's system, plus
## "Default", which follows the CORES panel. `choices` is [{core_name, label}], `selected` the
## machine's own pick ("" = default), `default_core` what "Default" resolves to. Built with a
## VRDropdown for the reason the port rows are (an OptionButton's popup is a Window, and the
## VR viewport's duplicated press dismisses it on the click that opens it).
func populate_cores(choices: Array, selected: String, default_core: String) -> void:
	if _system_rows == null:
		return
	if is_instance_valid(_core_picker):
		_core_picker.queue_free()
		_core_picker = null
	if choices.is_empty():
		return
	var default_label := default_core
	for c: Dictionary in choices:
		if str(c["core_name"]) == default_core:
			default_label = str(c["label"])
	var options: Array = [["Default (%s)" % default_label if not default_label.is_empty() else "Default", ""]]
	var current := ""
	for c: Dictionary in choices:
		options.append([str(c["label"]), str(c["core_name"])])
		if str(c["core_name"]) == selected:
			current = selected
	var drop := VRDropdown.create("Core", options, current, 1, Vector2(300, 48), 16)
	drop.item_selected.connect(func(value: Variant) -> void:
		core_selected.emit(str(value)))
	_core_picker = drop
	_system_rows.add_child(drop)
	_system_rows.move_child(drop, 0)


## The pad picker rides `show_video_out`: both are "this machine is a handheld".
## `volume` is the handheld's own control's level, 0..1, or -1 to hide the row.
func populate_system(video_out: bool, show_video_out: bool, ignore_grav: bool,
		pad_guid: String = "", pad_ordinal: int = 0, volume: float = -1.0,
		show_cabinet_art: bool = false, cabinet_art: bool = true,
		attract_mode: int = -1) -> void:
	show_volume(volume)
	_suppress_signal = true
	var picker_changed := _show_pad_picker != show_video_out \
		or _pad_guid != pad_guid or _pad_ordinal != pad_ordinal
	_show_pad_picker = show_video_out
	_pad_guid = pad_guid
	_pad_ordinal = pad_ordinal
	if picker_changed and _controllers_rows != null:
		_refresh_controllers()
	if _video_out_row:
		_video_out_row.visible = show_video_out
	if _video_out_check:
		_video_out_check.button_pressed = video_out
	if _ignore_grav_check:
		_ignore_grav_check.button_pressed = ignore_grav
	if _cabinet_art_row:
		_cabinet_art_row.visible = show_cabinet_art
	if _cabinet_art_check:
		_cabinet_art_check.button_pressed = cabinet_art
	if _attract_row:
		# -1 hides the row (every machine but a cabinet).
		_attract_row.visible = attract_mode >= 0
		_attract_mode = maxi(attract_mode, 0)
		_attract_button.text = _attract_text(_attract_mode)
	_suppress_signal = false


## The System tab's "Self-Lit Screen" row: `state` is RetroSystem.get_screen_glow(),
## -1 hiding the row for a machine without the switch.
func populate_screen_glow(state: int) -> void:
	if _screen_glow_row == null:
		return
	_screen_glow_row.visible = state >= 0
	_suppress_signal = true
	_screen_glow_check.button_pressed = state == 1
	_suppress_signal = false


## The attract row's button: what this cabinet does with the global option.
static func _attract_text(mode: int) -> String:
	match mode:
		ArcadeAttract.OVERRIDE_ON:
			return "Always on"
		ArcadeAttract.OVERRIDE_OFF:
			return "Always off"
	return "Follow global"


## The Volume row at `volume` (0..1) without telling anyone, or hidden at -1: the
## panel calls this as the device's own wheel turns.
func show_volume(volume: float) -> void:
	if _volume_box == null:
		return
	_volume_box.visible = volume >= 0.0
	if volume < 0.0:
		return
	_suppress_signal = true
	_volume_slider.value = volume * 100.0
	_volume_value.text = "%d%%" % roundi(volume * 100.0)
	_suppress_signal = false


## Drive the active scroll container from an external stick input (pixels > 0 = down).
func scroll_active(pixels: float) -> void:
	if _active_scroll:
		_active_scroll.scroll_vertical += int(pixels)
	elif _tabs != null and _tabs.current_tab == _saves_tab_idx and is_instance_valid(_saves_ui):
		_saves_ui.scroll_active(pixels)
	elif is_instance_valid(_cart_ui):
		# The Cartridge tab: its own ribbon strip decides which list scrolls.
		_cart_ui.scroll_active(pixels)


# ── Options tab ────────────────────────────────────────────────────────────────

## Appended, never clearing: the FRONTEND row above it is a setting in its own
## right and outlives "this core has published nothing yet".
func _show_options_placeholder() -> void:
	var lbl := Label.new()
	lbl.text = _unavailable if not _unavailable.is_empty() \
		else "No options available.\n(Start emulation first.)"
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", COLOR_ROW)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(0, 80)
	_options_rows.add_child(lbl)


## Typing filters the list, so both this and the FRONTEND/reset rows above it
## are dropped while a filter is set: they are not core options and would sit
## between the box and whatever the search actually found.
func _on_options_filter_changed(text: String) -> void:
	_options_filter = text.strip_edges()
	_refresh_options()


## Matched against the key as well as the shown description: a core's own
## documentation and its forum threads name the key, not the label.
func _matches_filter(key: String, defn: LibretroOptionDefinition) -> bool:
	if _options_filter.is_empty():
		return true
	var needle := _options_filter.to_lower()
	if key.to_lower().contains(needle):
		return true
	return _option_desc(key, defn).to_lower().contains(needle)


## The description the row shows, falling back the same way the row itself does.
func _option_desc(key: String, defn: LibretroOptionDefinition) -> String:
	return CoreOptionRow.description(key, defn)


func _refresh_options() -> void:
	for c in _options_rows.get_children():
		c.queue_free()

	var filtering := not _options_filter.is_empty()
	if not filtering:
		_add_frontend_row()

	if _definitions.is_empty():
		_show_options_placeholder()
		return

	if not filtering:
		_add_reset_row()

	var keys: Array = _definitions.keys()
	keys.sort()
	var shown := 0
	for key in keys:
		if not _matches_filter(key, _definitions[key]):
			continue
		_add_option_row(key, _definitions[key], String(_values.get(key, "")))
		shown += 1

	if shown == 0:
		var none := Label.new()
		none.text = "No option matches \"%s\"." % _options_filter
		none.add_theme_font_size_override("font_size", 16)
		none.add_theme_color_override("font_color", COLOR_ROW)
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		none.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		none.custom_minimum_size = Vector2(0, 60)
		_options_rows.add_child(none)

	print("[CoreOptions2D] %d of %d option rows built" % [shown, keys.size()])


## `corename` rather than the .info `display_name`, which is "Nintendo - SNES /
## SFC (Snes9x)" and names the platform rather than the core.
func _refresh_core_label() -> void:
	if _core_lbl == null:
		return
	if _core_name.is_empty():
		_core_lbl.text = ""
	else:
		_core_lbl.text = " - %s" % RomCompat.core_label(_core_name)


## Which API this core is told the frontend would rather render with — the same
## setting as CORES > Manager > (core) > FRONTEND in the spawn menu, reachable
## from the machine as well.
##
## Above the core's own options and outside the reset, because it is not one of
## them: every row below is a key the core publishes about itself and is written
## to that core's option file, while this is our answer to
## GET_PREFERRED_HW_RENDER, kept per core in AppPrefs. Built whether or not the
## core has published anything, since a machine that has never been switched on
## is exactly when this gets set.
func _add_frontend_row() -> void:
	if _core_name.is_empty():
		return

	var head := Label.new()
	head.text = "FRONTEND"
	head.add_theme_font_size_override("font_size", 15)
	head.add_theme_color_override("font_color", COLOR_TITLE)
	_options_rows.add_child(head)

	# "" is no override — the entry names the global, so the row says what this
	# core will actually get rather than merely that it is following something.
	var default_label := "Default"
	var options: Array = []
	for choice: Array in AppPrefs.hw_render_choices():
		if str(choice[1]) == AppPrefs.DEFAULT_HW_RENDER:
			default_label = "Default (%s)" % str(choice[0])
		options.append([str(choice[0]), str(choice[1])])
	options.push_front([default_label, ""])

	# VRDropdown, never OptionButton — every Viewport2Din3D click fires twice.
	var drop := VRDropdown.create("Preferred HW Render", options,
		AppPrefs.hw_render_override(_core_name), 1, Vector2(300, 48), 16)
	drop.item_selected.connect(func(id: Variant) -> void:
		print("[CoreOptions2D] hw render for '%s' → '%s'" % [_core_name, str(id)])
		AppPrefs.set_hw_render_override(_core_name, str(id))
	)
	_options_rows.add_child(drop)

	# One line: this page is 600x500 and the core's own options are what it is
	# for. The full explanation lives on the spawn menu's copy of this row.
	var note := Label.new()
	note.text = "Applied as the core starts."
	note.add_theme_font_size_override("font_size", 12)
	note.add_theme_color_override("font_color", COLOR_ROW)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_options_rows.add_child(note)

	_options_rows.add_child(HSeparator.new())


## Sits above the list rather than at the bottom: it acts on everything below it,
## and a list this long would otherwise bury it past the scroll.
func _add_reset_row() -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 52)
	row.add_theme_constant_override("separation", 4)
	_options_rows.add_child(row)

	var label := Label.new()
	label.text = "Restore this core's defaults"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", COLOR_TITLE)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	row.add_child(label)

	var btn := Button.new()
	btn.text = "Reset all"
	btn.custom_minimum_size = Vector2(120, 44)
	btn.add_theme_font_size_override("font_size", 14)
	btn.pressed.connect(func() -> void: options_reset_requested.emit())
	row.add_child(btn)

	_options_rows.add_child(HSeparator.new())


## Build a single option row: [description label] [<] [current value] [>]
func _add_option_row(key: String, defn: LibretroOptionDefinition, current_val: String) -> void:
	# A pinned option shows what the SYSTEM enforces, not what happens to be
	# sitting in the .opt, which can be stale.
	if _forced.has(key):
		current_val = str(_forced[key])
	CoreOptionRow.add(_options_rows, key, defn, current_val, _forced.has(key),
		"(fixed by this system)", func(k: String, v: String) -> void:
			print("[CoreOptions2D] '%s' -> '%s'" % [k, v])
			option_changed.emit(k, v))


func _value_label(value: LibretroOptionValue) -> String:
	return CoreOptionRow.value_label(value)


# ── Controllers tab ────────────────────────────────────────────────────────────

func _show_controllers_placeholder() -> void:
	for c in _controllers_rows.get_children():
		c.queue_free()
	var lbl := Label.new()
	lbl.text = "No controller info available.\n(Start emulation first.)"
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", COLOR_ROW)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(0, 80)
	_controllers_rows.add_child(lbl)


func _refresh_controllers() -> void:
	for c in _controllers_rows.get_children():
		c.queue_free()

	# Before the placeholder, not after: a handheld has no port rows at all, and
	# the pad picker is the only controller setting it has.
	if _show_pad_picker:
		_add_pad_row()

	if _controller_info.is_empty():
		if not _show_pad_picker:
			_show_controllers_placeholder()
		return

	for entry in _controller_info:
		_add_controller_row(entry)

	print("[CoreOptions2D] %d controller port rows built" % _controller_info.size())


## Build one row per port: [Port N] [inline dropdown of device types].
## Uses VRDropdown rather than OptionButton — an OptionButton's PopupMenu is a
## Window, and the VR viewport's duplicated press dismisses it on the same click
## it opens on (see vr_dropdown.gd).
func _add_controller_row(entry: Dictionary) -> void:
	var port: int = entry["port"]
	var controllers: Array = entry["controllers"]
	var current_id: int = entry["current_id"]

	if controllers.is_empty():
		return

	var options: Array = []
	for ctrl: Dictionary in controllers:
		options.append([str(ctrl["name"]), int(ctrl["id"])])

	var drop := VRDropdown.create("Port %d" % (port + 1), options, current_id,
		1, Vector2(300, 48), 16)
	drop.set_placeholder("(device %d)" % current_id)
	drop.item_selected.connect(func(device_id: Variant) -> void:
		print("[CoreOptions2D] port %d → device %d" % [port, int(device_id)])
		port_device_changed.emit(port, int(device_id))
	)

	_controllers_rows.add_child(drop)
	_controllers_rows.add_child(HSeparator.new())


## Which real gamepad drives this handheld.
##
## A handheld IS its own controller — system.gd gives it no external port zones —
## so there is nothing to plug a PadReceiver into and the pad has to be named
## here instead. Everything with a port does it the other way round, by plugging
## a receiver in, which is why this row appears on nothing else.
func _add_pad_row() -> void:
	var options: Array = [["None", ""]]
	var current := ""
	for device: int in GamepadBindings.usable_pads():
		var id := GamepadBindings.identify_device(device)
		var value := "%s:%d" % [str(id["guid"]), int(id["ordinal"])]
		options.append([str(id["name"]), value])
		if str(id["guid"]) == _pad_guid and int(id["ordinal"]) == _pad_ordinal:
			current = value

	var drop := VRDropdown.create("Physical Controller", options, current,
		1, Vector2(300, 48), 16)
	drop.item_selected.connect(func(value: Variant) -> void:
		var parts := str(value).split(":")
		var guid := parts[0] if parts.size() > 0 else ""
		var ordinal := int(parts[1]) if parts.size() > 1 else 0
		_pad_guid = guid
		_pad_ordinal = ordinal
		pad_device_changed.emit(guid, ordinal)
	)
	_controllers_rows.add_child(drop)
	_controllers_rows.add_child(HSeparator.new())
