## CoreOptionRow — one libretro core option as a row: its description, and < / >
## stepping through its values. Shared by the system options page and the card menu,
## which preload it by path.
extends RefCounted

const COLOR_TITLE := Color(0.9, 0.9, 1.0)
const COLOR_ROW := Color(0.65, 0.65, 0.80)
const COLOR_LOCKED := Color(1.00, 0.72, 0.20)


## Add a row for `key` to `parent`. `defn` is a LibretroOptionDefinition, kept
## untyped so GetValues and GetLabel use dynamic dispatch. A `locked` row shows its
## value and `locked_note`, with its arrows disabled. `on_changed` receives
## (key, value) whenever the player steps the value. `stacked` puts the
## description on its own line above the controls, for a narrow panel.
static func add(parent: Control, key: String, defn, current_val: String, locked: bool,
		locked_note: String, on_changed: Callable, stacked := false) -> void:
	var label := Label.new()
	label.text = description(key, defn)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", COLOR_ROW)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 52)
	row.add_theme_constant_override("separation", 4)
	if stacked:
		var block := VBoxContainer.new()
		block.add_theme_constant_override("separation", 0)
		parent.add_child(block)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		block.add_child(label)
		block.add_child(row)
	else:
		label.clip_text = true
		parent.add_child(row)
		row.add_child(label)

	var values_arr: Array = defn.GetValues()
	if values_arr.is_empty():
		return

	var cur_idx := 0
	for i in range(values_arr.size()):
		if values_arr[i].GetValue() == current_val:
			cur_idx = i
			break

	# Its own Label, so the note can carry its own colour.
	if locked:
		var note := Label.new()
		note.text = locked_note
		if stacked:
			note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		note.add_theme_font_size_override("font_size", 13)
		note.add_theme_color_override("font_color", COLOR_LOCKED)
		note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(note)

	var prev_btn := Button.new()
	prev_btn.text = " < "
	prev_btn.custom_minimum_size = Vector2(48, 48)
	prev_btn.disabled = locked
	row.add_child(prev_btn)

	var val_lbl := Label.new()
	val_lbl.custom_minimum_size = Vector2(140, 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	val_lbl.add_theme_font_size_override("font_size", 13)
	val_lbl.add_theme_color_override("font_color", COLOR_TITLE)
	val_lbl.clip_text = true
	val_lbl.text = value_label(values_arr[cur_idx])
	row.add_child(val_lbl)

	var next_btn := Button.new()
	next_btn.text = " > "
	next_btn.custom_minimum_size = Vector2(48, 48)
	next_btn.disabled = locked
	row.add_child(next_btn)

	var idx_ref := [cur_idx]
	var step := func(delta: int) -> void:
		idx_ref[0] = (idx_ref[0] + delta + values_arr.size()) % values_arr.size()
		var v = values_arr[idx_ref[0]]
		val_lbl.text = value_label(v)
		on_changed.call(key, String(v.GetValue()))
	prev_btn.pressed.connect(step.bind(-1))
	next_btn.pressed.connect(step.bind(1))


## The text a row shows for an option, falling back to its key.
static func description(key: String, defn) -> String:
	var desc: String = defn.GetDescriptionCategorized()
	if desc.is_empty():
		desc = defn.GetDescription()
	if desc.is_empty():
		desc = key
	return desc


## A LibretroOptionValue's display label, falling back to the raw value.
static func value_label(v) -> String:
	var lbl: String = v.GetLabel()
	return lbl if not lbl.is_empty() else v.GetValue()
