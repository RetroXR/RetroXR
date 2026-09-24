## VRPriorityDropdown — a label + toggle that pops out a PriorityOptions2D card:
## tick any number of items and order them with ▲/▼. The ScreenScraper region
## and language priorities are edited with it.
##
## The row half of VRDropdown, with the same rules: the list is its own
## DropdownPanel quad in front of the menu (inline under the row where there is
## no Viewport2Din3D to pop out of), buttons stay on ACTION_MODE_BUTTON_RELEASE,
## and a second activation in one frame is dropped. It shares VRDropdown's
## one-open-at-a-time slot, so opening either kind closes the other.
##
## Unlike a VRDropdown the card stays open while it is edited — moving a region
## three places is three presses — and goes on the toggle, its ✕, or another
## dropdown opening.
##
## Usage:
##   var d := VRPriorityDropdown.create("Region Priority", items, ["us", "eu"])
##   d.order_changed.connect(func(order: Array[String]) -> void: ...)
class_name VRPriorityDropdown
extends VBoxContainer

## Emitted only on a user edit, with the whole new order.
signal order_changed(order: Array[String])

const COLOR_TITLE := Color(0.9, 0.9, 1.0)
const PRIORITY_2D := preload("res://Scenes/UI/priority_options_2d.tscn")
## How many picks the toggle spells out before it trails off.
const SUMMARY_MAX := 4

var popout_3d := true

var _label: Label
var _toggle: Button
var _title := ""
var _items: Array = []
var _order: Array[String] = []
var _font_size := 18
var _is_open := false
var _popout: DropdownPanel = null
var _inline: PriorityOptions2D = null
var _last_activate_frame := -1


## items: [[code, name, glyph], ...] — glyph is a string ("" for none) drawn in
## MenuIcons.symbols(), so a region flag or an ICON_* codepoint both work.
static func create(
		label_text: String,
		items: Array,
		order: Array[String],
		toggle_min_size: Vector2 = Vector2(260, 52),
		font_size: int = 18) -> VRPriorityDropdown:
	var d := VRPriorityDropdown.new()
	d._title = label_text
	d._items = items
	d._order = order.duplicate()
	d._font_size = font_size
	d._build(toggle_min_size)
	return d


func _build(toggle_min_size: Vector2) -> void:
	add_theme_constant_override("separation", 4)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.custom_minimum_size = Vector2(0, 56)
	add_child(row)

	_label = Label.new()
	_label.text = _title
	_label.add_theme_font_size_override("font_size", _font_size)
	_label.add_theme_color_override("font_color", COLOR_TITLE)
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_label)

	_toggle = Button.new()
	_toggle.add_theme_font_override("font", MenuIcons.symbols())
	_toggle.custom_minimum_size = toggle_min_size
	_toggle.add_theme_font_size_override("font_size", _font_size)
	_toggle.focus_mode = Control.FOCUS_NONE
	_toggle.clip_text = true
	_toggle.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_toggle.pressed.connect(_on_toggle_pressed)
	row.add_child(_toggle)
	_refresh_toggle()


func get_order() -> Array[String]:
	return _order.duplicate()


func is_open() -> bool:
	return _is_open


func close() -> void:
	_is_open = false
	if is_instance_valid(_popout):
		_popout.hide_panel()
	if is_instance_valid(_inline):
		_inline.visible = false
	if VRDropdown._open_dropdown == self:
		VRDropdown._open_dropdown = null
	_refresh_toggle()


## Build the popout ahead of the first tap, as VRDropdown.prewarm() does.
func prewarm() -> void:
	if _ensure_popout() != null:
		_popout.prewarm()


## The picks in order, as their glyphs (or names, for one with none), then the
## chevron: "🇺🇸 › 🇪🇺 › 🌐 › 🇯🇵 …  ▾".
func summary() -> String:
	var by_code := {}
	for entry: Array in PriorityOptions2D.with_unknown(_items, _order):
		by_code[entry[0]] = entry
	var parts := PackedStringArray()
	for i in mini(_order.size(), SUMMARY_MAX):
		var entry: Array = by_code[_order[i]]
		var glyph := str(entry[2]) if entry.size() > 2 else ""
		parts.append(glyph if not glyph.is_empty() else str(entry[1]))
	var text := " › ".join(parts)
	if _order.size() > SUMMARY_MAX:
		text += " …"
	return text


func _refresh_toggle() -> void:
	var arrow := String.chr(MenuIcons.COLLAPSE if _is_open else MenuIcons.EXPAND)
	_toggle.text = summary() + "  " + arrow


func _accept_activation() -> bool:
	var frame := Engine.get_process_frames()
	if frame == _last_activate_frame:
		return false
	_last_activate_frame = frame
	return true


func _on_toggle_pressed() -> void:
	if not _accept_activation():
		return
	if _is_open:
		close()
		return
	var other: Control = VRDropdown._open_dropdown
	if other != null and other != self and is_instance_valid(other):
		other.call("close")
	VRDropdown._open_dropdown = self
	_is_open = true
	if not (popout_3d and _open_popout()):
		_open_inline()
	_refresh_toggle()


func _ensure_popout() -> DropdownPanel:
	var host := _host_viewport()
	if host == null:
		return null
	if _popout == null or not is_instance_valid(_popout):
		_popout = DropdownPanel.new()
		_popout.name = "PriorityPopout"
		_popout.options_scene = PRIORITY_2D
		host.add_child(_popout)
		_popout.order_changed.connect(_on_edited)
		_popout.close_requested.connect(close)
	return _popout


func _open_popout() -> bool:
	var host := _host_viewport()
	if _ensure_popout() == null:
		return false
	var rect := Rect2(_toggle.global_position, _toggle.size)
	_popout.show_priority_for(host, rect, _title, _items, _order,
		_label.get_theme_font("font"))
	return true


## No 3D host: the same card, under the row. It has no ✕ there; the toggle
## closes it.
func _open_inline() -> void:
	if _inline == null or not is_instance_valid(_inline):
		_inline = PRIORITY_2D.instantiate() as PriorityOptions2D
		_inline.inline = true
		_inline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		add_child(_inline)
		_inline.order_changed.connect(_on_edited)
	_inline.visible = true
	_inline.set_items(_title, _items, _order, _label.get_theme_font("font"), _font_size)


func _on_edited(order: Array[String]) -> void:
	_order = order.duplicate()
	_refresh_toggle()
	order_changed.emit(_order.duplicate())


## The Viewport2Din3D this control renders inside, if any (see VRDropdown).
func _host_viewport() -> XRToolsViewport2DIn3D:
	var vp := get_viewport()
	if vp == null:
		return null
	return vp.get_parent() as XRToolsViewport2DIn3D


## The popout hangs off the host panel, not this control, so it would outlive
## an options page that is torn down with the card still showing.
func _exit_tree() -> void:
	if VRDropdown._open_dropdown == self:
		VRDropdown._open_dropdown = null
	_is_open = false
	if is_instance_valid(_popout):
		_popout.queue_free()
	_popout = null
