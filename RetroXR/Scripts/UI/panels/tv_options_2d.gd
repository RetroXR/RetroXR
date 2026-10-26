## TVOptions2D — 2D UI for a TV's settings.
## Loaded into TVOptionsPanel's SubViewport via XRToolsViewport2DIn3D.
## Built programmatically, mirroring BookOptions2D.
##
## Emits:
##   scale_changed(scale)   — size slider moved (fires live while dragging)
##   scale_committed(scale) — size slider drag finished (for net replication)
##   close_requested        — user pressed ✕
##   control_requested(id, value) — one of the set's own buttons, pressed here
##
## The Controls tab is the set's bezel caps and the remote's TV keys as menu
## controls: power, input (with what is on each one), volume, channel, picture
## shape, 3D (only while a 3D source is in), speaker switch, audio output and CRT.
## It is fed RetroTV.menu_state() and asks for changes by id; TVOptionsPanel makes
## them through the same calls the caps make, so the OSD, the caps and netplay all
## follow without anything here knowing about them.
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
## A Controls-tab button: `id` is the remote's key name ("power", "source",
## "vol_up", "aspect", ...) and `value` what it was set to, or null for a press.
signal control_requested(id: String, value: Variant)

# ── Palette (matches BookOptions2D / CoreOptions2D) ──────────────────────────────
const COLOR_BG    := Color(0.08, 0.08, 0.16, 0.96)
const COLOR_TITLE := Color(0.9,  0.9,  1.0)
const COLOR_ROW   := Color(0.65, 0.65, 0.80)
## The input the set is showing, in the input list, against the others.
const COLOR_SELECTED := Color(0.25, 0.45, 0.85)
const COLOR_IDLE     := Color(0.16, 0.16, 0.28)
const COLOR_EMPTY    := Color(0.5, 0.5, 0.6)
## An input with a cord in the wrong jack.
const COLOR_WARN     := Color(1.0, 0.7, 0.25)
## Every AUDIO OUTPUT position, indexed by RetroTV.AudioOut. A set offers the ones
## its cabinet has (menu_state's audio_out_options).
const AUDIO_OUT_CHOICES := [["TV speakers", 0], ["Stereo out", 1], ["Surround", 2]]

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

# Controls tab.
var _controls_scroll: ScrollContainer = null
var _power_sw: VRToggle = null
var _inputs_box: VBoxContainer = null
# The input list as last built, so a re-populate that changes nothing about it
# (the usual case: only the volume moved) does not rebuild the buttons under a
# pointer that is pressing one.
var _inputs_sig := ""
# source -> Button, for moving the highlight without a rebuild.
var _input_buttons: Dictionary = {}
var _volume_val: Label = null
var _mute_btn: Button = null
var _ch_down_btn: Button = null
var _ch_up_btn: Button = null
var _channel_val: Label = null
var _aspect_opt: VRDropdown = null
var _stereo_opt: VRDropdown = null
var _audio_mode_opt: VRDropdown = null
var _audio_out_opt: VRDropdown = null
## The positions _audio_out_opt was last built with.
var _audio_out_shown: Array = [0, 1, 2]
var _crt_sw: VRToggle = null


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

	# ── Tab container (mirrors VCROptions2D): Controls | Options | CRT ─────────
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_font_size_override("font_size", 18)
	root_vbox.add_child(tabs)

	_build_controls_tab(tabs)

	var opts_outer := VBoxContainer.new()
	opts_outer.name = "Options"
	tabs.add_child(opts_outer)

	_options_scroll = ScrollContainer.new()
	_options_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_options_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_options_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	MenuStyle.fat_vscroll_bar(_options_scroll)
	opts_outer.add_child(_options_scroll)

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
			_active_scroll = _controls_scroll
		1:
			_active_scroll = _options_scroll
		_:
			_active_scroll = _crt_scroll


# ── Controls: the set's own buttons ───────────────────────────────────────────

func _build_controls_tab(tabs: TabContainer) -> void:
	var outer := VBoxContainer.new()
	outer.name = "Controls"
	tabs.add_child(outer)

	_controls_scroll = ScrollContainer.new()
	_controls_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_controls_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_controls_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	MenuStyle.fat_vscroll_bar(_controls_scroll)
	outer.add_child(_controls_scroll)
	_active_scroll = _controls_scroll

	var rows := MenuStyle.vbox(6)
	_controls_scroll.add_child(rows)

	_power_sw = MenuStyle.switch_row(rows, "Power", true)
	_power_sw.toggled.connect(func(on: bool) -> void: _request("power", on))

	# Every input the cabinet has, each with what is plugged into it. A press
	# selects it: SOURCE without stepping through the others to get there.
	rows.add_child(_section("Input"))
	_inputs_box = MenuStyle.vbox(4)
	rows.add_child(_inputs_box)

	rows.add_child(_section("Volume"))
	var vol := MenuStyle.hbox(8)
	rows.add_child(vol)
	vol.add_child(_key("VOL −", "vol_down"))
	_mute_btn = _key("MUTE", "mute")
	vol.add_child(_mute_btn)
	vol.add_child(_key("VOL +", "vol_up"))
	_volume_val = _value_label()
	vol.add_child(_volume_val)

	# Live only on the aerial input, as the remote's keys are. The bezel's CH keys
	# select RF first because they are moulded in; here the input list is right
	# above, so these grey out instead and say why.
	rows.add_child(_section("Channel"))
	var ch := MenuStyle.hbox(8)
	rows.add_child(ch)
	_ch_down_btn = _key("CH −", "ch_down")
	ch.add_child(_ch_down_btn)
	_ch_up_btn = _key("CH +", "ch_up")
	ch.add_child(_ch_up_btn)
	_channel_val = _value_label()
	_channel_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_channel_val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ch.add_child(_channel_val)

	rows.add_child(HSeparator.new())
	_aspect_opt = _choice(rows, "Picture shape", [["4:3", 0], ["16:9", 1]], "aspect")
	# Hidden until a 3D source is in, the way the bezel's 3D cap is.
	_stereo_opt = _choice(rows, "3D mode",
		[["Stereo (both eyes)", 0], ["Left eye", 1], ["Right eye", 2]], "stereo3d")
	_stereo_opt.visible = false
	_audio_mode_opt = _choice(rows, "Speaker switch",
		[["Stereo", 0], ["Mono left", 1], ["Mono right", 2]], "audio_mode")
	_audio_out_opt = _choice(rows, "Audio output", AUDIO_OUT_CHOICES, "audio_out")

	_crt_sw = MenuStyle.switch_row(rows, "CRT filter", true)
	_crt_sw.toggled.connect(func(on: bool) -> void: _request("crt", on))


func _request(id: String, value: Variant) -> void:
	if not _suppress_signal:
		control_requested.emit(id, value)


func _section(text: String) -> Label:
	return MenuStyle.label(text, 18, COLOR_ROW)


func _value_label() -> Label:
	var l := MenuStyle.label("", 18, COLOR_TITLE)
	l.custom_minimum_size = Vector2(90, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


## A press-only key. RELEASE mode, never PRESS: a click in a Viewport2DIn3D arrives
## as two presses, so a press-mode VOL+ would step twice (see MenuStyle.check).
func _key(text: String, id: String) -> Button:
	var b := MenuStyle.row_button(text, 18, 110, 48, false)
	b.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	b.focus_mode = Control.FOCUS_NONE
	# The input rows' tile, so a key reads as a key and not as a caption.
	var box := MenuStyle.rounded(COLOR_IDLE, 6)
	for state in ["normal", "hover", "disabled"]:
		b.add_theme_stylebox_override(state, box)
	b.add_theme_stylebox_override("pressed", MenuStyle.rounded(COLOR_SELECTED, 6))
	b.pressed.connect(func() -> void: _request(id, null))
	return b


func _choice(rows: VBoxContainer, label: String, options: Array, id: String) -> VRDropdown:
	var d := VRDropdown.create(label, options, options[0][1])
	d.item_selected.connect(func(v: Variant) -> void: _request(id, int(v)))
	rows.add_child(d)
	return d


## Rebuild the input list, only when what it lists changed; move the highlight always.
func _populate_inputs(inputs: Array, selected: int) -> void:
	var sig := var_to_str(inputs)
	if sig != _inputs_sig:
		_inputs_sig = sig
		for c in _inputs_box.get_children():
			_inputs_box.remove_child(c)
			c.queue_free()
		_input_buttons.clear()
		for row: Dictionary in inputs:
			var source := int(row["source"])
			var device := str(row["device"])
			var text := "%s   —   %s" % [row["name"],
				device if not device.is_empty() else "nothing connected"]
			# A cord in the wrong jack, on a line of its own: the input still works,
			# it just swaps the speakers or loses the picture, which is the thing
			# nothing else in the room explains.
			var wiring: Array = row.get("wiring", [])
			if not wiring.is_empty():
				text += "\nCrossed: %s" % ", ".join(PackedStringArray(wiring))
			var b := MenuStyle.row_button(text, 18, 0, 48)
			b.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
			b.focus_mode = Control.FOCUS_NONE
			b.clip_text = true
			b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			if not wiring.is_empty():
				b.add_theme_color_override("font_color", COLOR_WARN)
				b.add_theme_color_override("font_hover_color", COLOR_WARN)
			elif device.is_empty():
				b.add_theme_color_override("font_color", COLOR_EMPTY)
			b.pressed.connect(func() -> void: _request("source", source))
			_inputs_box.add_child(b)
			_input_buttons[source] = b
	for source: int in _input_buttons:
		var b := _input_buttons[source] as Button
		var box := MenuStyle.rounded(COLOR_SELECTED if source == selected else COLOR_IDLE, 6)
		b.add_theme_stylebox_override("normal", box)
		b.add_theme_stylebox_override("hover", box)


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


## Sync the Controls tab to RetroTV.menu_state() without re-emitting signals.
func populate_controls(state: Dictionary) -> void:
	if _power_sw == null:
		return
	_suppress_signal = true
	_power_sw.button_pressed = bool(state.get("on", true))
	_populate_inputs(state.get("inputs", []), int(state.get("source", 0)))
	var muted := bool(state.get("muted", false))
	_volume_val.text = "MUTED" if muted \
		else "%d%%" % roundi(float(state.get("volume", 0.0)) * 100.0)
	_mute_btn.text = "UNMUTE" if muted else "MUTE"
	var can_ch := bool(state.get("can_change_channel", false))
	_ch_down_btn.disabled = not can_ch
	_ch_up_btn.disabled = not can_ch
	_channel_val.text = str(state.get("channel_text", "")) if can_ch else "RF input only"
	_aspect_opt.select_id(1 if bool(state.get("widescreen", false)) else 0)
	_stereo_opt.visible = bool(state.get("has_stereo", false))
	_stereo_opt.select_id(int(state.get("stereo_mode", 0)))
	_audio_mode_opt.select_id(int(state.get("audio_mode", 0)))
	# Only the positions this cabinet has: a set with an L/R pair and no more has
	# no SURROUND to offer (the Panasonic CT-20D10B).
	var outs: Array = state.get("audio_out_options", [0, 1, 2])
	if outs != _audio_out_shown:
		_audio_out_shown = outs.duplicate()
		_audio_out_opt.set_options(AUDIO_OUT_CHOICES.filter(func(c: Array) -> bool:
			return outs.has(c[1])), int(state.get("audio_out", 0)))
	_audio_out_opt.select_id(int(state.get("audio_out", 0)))
	_crt_sw.button_pressed = bool(state.get("crt", true))
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
