## A multi-select, orderable option list: tick any number of items, then move the
## ticked ones up and down. What the ScreenScraper region and language priorities
## are edited with, in a DropdownPanel popout (or inline, with no 3D host).
##
## Ticked items come first, in priority order, each with its rank and ▲/▼;
## the rest follow in catalogue order. Ticking appends to the END of the order,
## so a new pick never jumps ahead of what was already chosen. The last ticked
## item cannot be unticked: an empty priority list means "whatever comes first",
## which is not something a player asks for by unticking.
##
## Buttons stay on ACTION_MODE_BUTTON_RELEASE and swallow a second activation in
## the same frame, as DropdownOptions2D does and for the same reason.
class_name PriorityOptions2D
extends Control

## Every user change, with the whole new order.
signal order_changed(order: Array[String])
signal close_requested

const COLOR_BG     := Color(0.16, 0.16, 0.32, 1.0)
const COLOR_TITLE  := Color(0.9, 0.9, 1.0)
const COLOR_OFF    := Color(0.60, 0.60, 0.75)
const COLOR_RANK   := Color(0.55, 0.85, 1.0)

const ROW_H := 56
const PAD := 10
const HEADER_H := 52

## Inline (no popout) there is nothing to close and no page to fill: leave out
## the header and do not stretch to a full-rect panel. Set before _ready.
var inline := false

var _list: VBoxContainer = null
var _title: Label = null
var _items: Array = []
var _order: Array[String] = []
var _font: Font = null
var _font_size := 22
var _last_activate_frame := -1


func _ready() -> void:
	var panel := PanelContainer.new()
	if not inline:
		panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	else:
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := MenuStyle.rounded(COLOR_BG, 8)
	sb.border_color = Color(0.55, 0.55, 0.90)
	for side in ["border_width_left", "border_width_right",
			"border_width_top", "border_width_bottom"]:
		sb.set(side, 3)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	var margin := MarginContainer.new()
	for side in ["margin_top", "margin_bottom", "margin_left", "margin_right"]:
		margin.add_theme_constant_override(side, PAD)
	panel.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	margin.add_child(col)

	if not inline:
		var row := MenuStyle.title_row(col, "", 24)
		row.custom_minimum_size = Vector2(0, HEADER_H - 6)
		_title = row.get_child(0) as Label
		_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var close := MenuStyle.close_button(row, _request_close, false, 46.0, 22)
		close.focus_mode = Control.FOCUS_NONE

	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 4)
	if inline:
		col.add_child(_list)
	else:
		var scroll := ScrollContainer.new()
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		MenuStyle.fat_vscroll_bar(scroll, 24, 40)
		col.add_child(scroll)
		scroll.add_child(_list)
	if inline:
		# A plain Control does not take its size from its children, so inline the
		# panel's minimum is copied up, or the row it sits in would be 0 tall.
		var fit := func() -> void: custom_minimum_size = panel.get_combined_minimum_size()
		panel.minimum_size_changed.connect(fit)
		fit.call()


## items: [[code, name, glyph], ...] — glyph is a string drawn before the name
## ("" for none). order: the ticked codes, first priority first.
func set_items(title: String, items: Array, order: Array[String], font: Font = null,
		font_size: int = 22) -> void:
	if _list == null:
		await ready
	if _title != null:
		_title.text = title
	_items = with_unknown(items, order)
	_order = order.duplicate()
	_font = MenuIcons.with_symbols(font)
	_font_size = font_size
	_rebuild()


func get_order() -> Array[String]:
	return _order.duplicate()


## Pixel size the popout should be for this many catalogue rows.
static func wanted_size(row_count: int) -> Vector2:
	return Vector2(460.0, PAD * 2 + HEADER_H + row_count * (ROW_H + 4))


## The catalogue plus any code in `order` it does not know, shown by its code —
## a priority typed by hand under the old text field is kept, not dropped.
static func with_unknown(items: Array, order: Array[String]) -> Array:
	var out := items.duplicate()
	var known := {}
	for entry: Array in items:
		known[entry[0]] = true
	for code: String in order:
		if not known.has(code):
			out.append([code, code, ""])
			known[code] = true
	return out


## Tick or untick `code`. Ticking appends; the last ticked item stays ticked.
static func toggle(order: Array[String], code: String) -> Array[String]:
	var out := order.duplicate()
	var at := out.find(code)
	if at < 0:
		out.append(code)
	elif out.size() > 1:
		out.remove_at(at)
	return out


## Move `code` by `delta` places within the order, clamped at both ends.
static func move(order: Array[String], code: String, delta: int) -> Array[String]:
	var out := order.duplicate()
	var at := out.find(code)
	if at < 0:
		return out
	var to := clampi(at + delta, 0, out.size() - 1)
	if to == at:
		return out
	out.remove_at(at)
	out.insert(to, code)
	return out


func _rebuild() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()

	var by_code := {}
	for entry: Array in _items:
		by_code[entry[0]] = entry
	for i in _order.size():
		if by_code.has(_order[i]):
			_add_row(by_code[_order[i]], i)
	for entry: Array in _items:
		if not _order.has(entry[0]):
			_add_row(entry, -1)


## rank: position in the order, or -1 for an unticked item.
func _add_row(entry: Array, rank: int) -> void:
	var code := str(entry[0])
	var glyph := str(entry[2]) if entry.size() > 2 else ""
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_list.add_child(row)

	var on := rank >= 0
	var pick := _button(
		"%s  %s%s%s" % [
			String.chr(MenuIcons.CHECKBOX_ON if on else MenuIcons.CHECKBOX_OFF),
			("%d  " % (rank + 1)) if on else "    ",
			(glyph + "  ") if not glyph.is_empty() else "",
			str(entry[1])],
		func() -> void: _apply(toggle(_order, code)))
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.alignment = HORIZONTAL_ALIGNMENT_LEFT
	pick.clip_text = true
	pick.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	pick.add_theme_color_override("font_color", COLOR_TITLE if on else COLOR_OFF)
	# The only ticked item cannot be unticked, so its box must not look live.
	pick.disabled = on and _order.size() == 1
	row.add_child(pick)

	var up := _button(String.chr(MenuIcons.MOVE_UP),
		func() -> void: _apply(move(_order, code, -1)))
	var down := _button(String.chr(MenuIcons.MOVE_DOWN),
		func() -> void: _apply(move(_order, code, 1)))
	for b: Button in [up, down]:
		b.custom_minimum_size = Vector2(ROW_H, ROW_H)
		b.add_theme_color_override("font_color", COLOR_RANK)
		# Unticked rows keep the two slots so every name starts in one column
		# and the arrows line up; they are just not there to press.
		b.modulate.a = 1.0 if on else 0.0
		b.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
		row.add_child(b)
	up.disabled = not on or rank == 0
	down.disabled = not on or rank == _order.size() - 1


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, ROW_H)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", _font)
	b.add_theme_font_size_override("font_size", _font_size)
	b.pressed.connect(func() -> void:
		if _accept_activation():
			on_press.call())
	return b


func _apply(next: Array[String]) -> void:
	if next == _order:
		return
	_order = next
	_rebuild()
	order_changed.emit(_order.duplicate())


func _request_close() -> void:
	if _accept_activation():
		close_requested.emit()


func _accept_activation() -> bool:
	var frame := Engine.get_process_frames()
	if frame == _last_activate_frame:
		return false
	_last_activate_frame = frame
	return true
