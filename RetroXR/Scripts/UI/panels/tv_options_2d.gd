## TVOptions2D — 2D UI for a TV's settings.
## Loaded into TVOptionsPanel's SubViewport via XRToolsViewport2DIn3D.
## Built programmatically, mirroring BookOptions2D.
##
## Emits:
##   scale_changed(scale)   — size slider moved (fires live while dragging)
##   scale_committed(scale) — size slider drag finished (for net replication)
##   close_requested        — user pressed ✕
##
## There is no Channels tab. The tuner's address and the channel list moved to the
## aerial that receives them — point at an Antenna and open ITS menu
## (AntennaOptions2D). A set with nothing in its coax socket has no channels, so a
## tab for them here would be a list that is empty for a reason it could not give.
class_name TVOptions2D
extends Control

signal scale_changed(scale: float)
signal scale_committed(scale: float)
## Float-in-place toggled.
signal ignore_gravity_toggled(enabled: bool)
## A CRT display-stage uniform was changed (pname, value). Applied live.
signal crt_param_changed(pname, value)
signal close_requested

# ── Palette (matches BookOptions2D / CoreOptions2D) ──────────────────────────────
const COLOR_BG    := Color(0.08, 0.08, 0.16, 0.96)
const COLOR_TITLE := Color(0.9,  0.9,  1.0)
const COLOR_ROW   := Color(0.65, 0.65, 0.80)

const MIN_SCALE := 0.2
const MAX_SCALE := 5.0

var _size_slider: HSlider = null
var _size_val: Label = null
var _float_check: VRToggle = null
var _options_scroll: ScrollContainer = null
var _crt_scroll: ScrollContainer = null
var _active_scroll: ScrollContainer = null
# CRT controls, keyed by shader uniform name → {slider, val_label, fmt}.
var _crt_sliders: Dictionary = {}
var _crt_mask_opt: VRDropdown = null
# Guard so populate() doesn't re-emit signals when it sets control values.
var _suppress_signal := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()


func _build_ui() -> void:
	var margin := MenuStyle.panel_root(self, COLOR_BG, 10, 12)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 6)
	margin.add_child(root_vbox)

	MenuStyle.close_button(MenuStyle.title_row(root_vbox, "TV Settings"),
		func() -> void: close_requested.emit())

	root_vbox.add_child(HSeparator.new())

	# ── Tab container (mirrors VCROptions2D): Options | CRT ────────────────────
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_font_size_override("font_size", 18)
	root_vbox.add_child(tabs)

	var opts_outer := VBoxContainer.new()
	opts_outer.name = "Options"
	tabs.add_child(opts_outer)

	_options_scroll = ScrollContainer.new()
	_options_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_options_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_options_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	MenuStyle.fat_vscroll_bar(_options_scroll)
	opts_outer.add_child(_options_scroll)
	_active_scroll = _options_scroll

	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 4)
	_options_scroll.add_child(rows)

	# Size slider row: [label + value] then a full-width slider under it.
	var size_header := HBoxContainer.new()
	size_header.add_theme_constant_override("separation", 8)
	rows.add_child(size_header)

	var size_lbl := Label.new()
	size_lbl.text = "TV size"
	size_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_lbl.add_theme_font_size_override("font_size", 18)
	size_lbl.add_theme_color_override("font_color", COLOR_ROW)
	size_header.add_child(size_lbl)

	_size_val = Label.new()
	_size_val.text = "1.0×"
	_size_val.add_theme_font_size_override("font_size", 18)
	_size_val.add_theme_color_override("font_color", COLOR_TITLE)
	_size_val.custom_minimum_size = Vector2(70, 0)
	_size_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	size_header.add_child(_size_val)

	_size_slider = HSlider.new()
	_size_slider.min_value = MIN_SCALE
	_size_slider.max_value = MAX_SCALE
	_size_slider.step = 0.1
	_size_slider.value = 1.0
	_size_slider.custom_minimum_size = Vector2(0, 48)
	_size_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_child(_size_slider)

	# value_changed fires continuously while dragging → live resize; the
	# commit signal on drag end is what gets replicated to other players.
	_size_slider.value_changed.connect(func(v: float):
		_size_val.text = "%.1f×" % v
		if not _suppress_signal:
			scale_changed.emit(v)
	)
	_size_slider.drag_ended.connect(func(value_changed_flag: bool):
		if not _suppress_signal and value_changed_flag:
			scale_committed.emit(_size_slider.value)
	)

	_float_check = MenuStyle.float_toggle(rows)
	_float_check.toggled.connect(func(on: bool):
		if not _suppress_signal:
			ignore_gravity_toggled.emit(on)
	)

	_build_crt_tab(tabs)

	# Stick-scroll drives whichever tab is visible.
	tabs.tab_changed.connect(_on_tab_changed)


## A named method, not a lambda: a multi-line `match` inside one does not parse.
func _on_tab_changed(idx: int) -> void:
	match idx:
		0:
			_active_scroll = _options_scroll
		_:
			_active_scroll = _crt_scroll


# ── CRT filter controls (own tab, like the VCR panel's VHS tab) ───────────────

func _build_crt_tab(tabs: TabContainer) -> void:
	var outer := VBoxContainer.new()
	outer.name = "CRT"
	tabs.add_child(outer)

	_crt_scroll = ScrollContainer.new()
	_crt_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_crt_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_crt_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	MenuStyle.fat_vscroll_bar(_crt_scroll)
	outer.add_child(_crt_scroll)

	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 4)
	_crt_scroll.add_child(rows)

	# Mask mode dropdown. VRDropdown, not OptionButton — see vr_dropdown.gd for
	# why PopupMenu can't be clicked in a VR panel.
	_crt_mask_opt = VRDropdown.create("RGB mask",
		[["Off", 0], ["Grille", 1], ["Slot", 2], ["Shadow", 3]], 1)
	_crt_mask_opt.item_selected.connect(func(id: Variant) -> void:
		if not _suppress_signal:
			crt_param_changed.emit("crt_mask_mode", int(id))
	)
	rows.add_child(_crt_mask_opt)

	# Sliders: [uniform, label, min, max, step, value-format].
	#
	# "Phosphor pitch" is in millimetres on the glass, not pixels: the mask is
	# locked to the tube, so the triad count follows from the pitch and the TV's
	# world size. Measured on a 0.35 m tube at Quest 3 density, triads start
	# resolving at ~2.5 px and are solid by ~4 px, which puts the default 2.0 mm
	# at "visible from 0.8 m, obvious by 0.5 m". 0.6 mm is a physically real
	# arcade tube and stays invisible until you are almost touching the glass.
	var specs := [
		["crt_mask_strength",     "Mask strength",    0.0, 1.0,  0.05, "%.2f"],
		["crt_mask_pitch_mm",     "Phosphor pitch",   0.4, 3.0,  0.1,  "%.1f mm"],
		["crt_scanline_strength", "Scanlines",        0.0, 1.0,  0.05, "%.2f"],
		["crt_beam_min",          "Beam (dark)",      0.05, 0.5, 0.01, "%.2f"],
		["crt_beam_max",          "Beam (bright)",    0.05, 0.8, 0.01, "%.2f"],
		["crt_gamma",             "Tube gamma",       0.8, 1.4,  0.01, "%.2f"],
		["crt_halation",          "Halation",         0.0, 0.5,  0.01, "%.2f"],
		["crt_persistence",       "Persistence",      0.0, 0.6,  0.05, "%.2f"],
		["crt_notch",             "Composite blend",  0.0, 1.0,  0.05, "%.2f"],
		["crt_curvature",         "Extra curvature",  0.0, 0.3,  0.01, "%.2f"],
		["crt_grain",             "Grain",            0.0, 1.0,  0.02, "%.2f"],
		["crt_smear",             "Smear",            0.0, 1.0,  0.05, "%.2f"],
		["crt_wiggle",            "Wiggle",           0.0, 0.2,  0.02, "%.2f"],
		["crt_vignette",          "Vignette",         0.0, 1.0,  0.05, "%.2f"],
		["crt_brightness",        "Brightness",       0.5, 2.0,  0.05, "%.2f"],
		["crt_glass_reflection",  "Glass reflection",  0.0, 1.0,  0.05, "%.2f"],
		["crt_glass_roughness",   "Glass roughness",   0.02, 0.6, 0.02, "%.2f"],
		["crt_glass_wear",        "Glass wear",        0.0, 3.0,  0.05, "%.2f×"],
		["crt_character",         "CRT character",     0.0, 1.0,  0.05, "%.2f"],
	]
	for s: Array in specs:
		_add_crt_slider(rows, s[0], s[1], s[2], s[3], s[4], s[5])


func _add_crt_slider(rows: VBoxContainer, key: String, label: String,
		minv: float, maxv: float, step: float, fmt: String) -> void:
	var built := MenuStyle.slider_row(rows, label, minv, maxv, step, 70)
	var slider := built[0] as HSlider
	var val_lbl := built[1] as Label
	slider.value_changed.connect(func(v: float):
		val_lbl.text = fmt % v
		if not _suppress_signal:
			crt_param_changed.emit(key, v)
	)
	_crt_sliders[key] = {"slider": slider, "val": val_lbl, "fmt": fmt}


# ── Public API ─────────────────────────────────────────────────────────────────

## Sync the UI to the TV's current state without re-emitting signals.
func populate(scale_factor := 1.0, ignore_gravity := false) -> void:
	_suppress_signal = true
	if _size_slider:
		_size_slider.value = scale_factor
		_size_val.text = "%.1f×" % scale_factor
	if _float_check:
		_float_check.button_pressed = ignore_gravity
	_suppress_signal = false


## Sync the CRT controls to the TV's current uniform values (no signal re-emit).
func populate_crt(params: Dictionary) -> void:
	_suppress_signal = true
	if _crt_mask_opt and params.has("crt_mask_mode"):
		_crt_mask_opt.select_id(int(params["crt_mask_mode"]))
	for key: String in _crt_sliders:
		if not params.has(key):
			continue
		var entry: Dictionary = _crt_sliders[key]
		var v := float(params[key])
		(entry["slider"] as HSlider).value = v
		(entry["val"] as Label).text = str(entry["fmt"]) % v
	_suppress_signal = false


## Drive the active scroll container from an external stick input.
func scroll_active(pixels: float) -> void:
	if _active_scroll:
		_active_scroll.scroll_vertical += int(pixels)
