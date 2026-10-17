## ObjectOptions2D — 2D UI for the generic object menu.
##
## Deliberately almost empty: a title, a ✕, whatever facts the object has about
## itself (set_info — a tape's place and file), and whatever FloatingObjectPanel3D
## adds. It exists so that a table, a trash can or any other plain pickable has
## a menu to put the "lock in place" row into, rather than that row being the
## privilege of the ten objects that happened to grow a settings panel.
##
## Emits:
##   close_requested — user pressed ✕
class_name ObjectOptions2D
extends Control

signal close_requested

const COLOR_BG := Color(0.08, 0.08, 0.16, 0.96)
const COLOR_TITLE := Color(0.9, 0.9, 1.0)
const COLOR_CAPTION := Color(0.55, 0.55, 0.68)
const COLOR_INFO := Color(0.82, 0.82, 0.92)

var _title: Label = null
var _panel: Control = null
## The object's facts, under the title.
var _info: VBoxContainer = null


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()


func _build_ui() -> void:
	var margin := MenuStyle.panel_root(self, COLOR_BG, 10, 12)
	_panel = margin.get_parent() as Control
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	var title_row := MenuStyle.title_row(vbox, "Object", 22)
	_title = title_row.get_child(0) as Label
	# Wrapped: an unwrapped title as long as a film's name widened the whole box
	# past the 340 px page, pushing the ✕ off it and clipping every row below.
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	MenuStyle.close_button(title_row, func() -> void: close_requested.emit(),
		22, 36.0)

	# Built now, empty, so it sits under the title whatever comes later: the lock
	# row is appended to this same box once the panel finds it, and goes below.
	_info = VBoxContainer.new()
	_info.add_theme_constant_override("separation", 6)
	_info.visible = false
	vbox.add_child(_info)


func populate(title: String) -> void:
	if _title != null:
		_title.text = title


## Show `rows`, each a [caption, text] pair, under the title. The text wraps
## anywhere rather than at spaces: the longest of these is a path, and its file
## name, at the end, is the part worth reading. The labels are kept and
## rewritten, because some of this moves while the menu is up (a tape's place).
func set_info(rows: Array) -> void:
	if _info == null:
		return
	while _info.get_child_count() > rows.size():
		var gone := _info.get_child(_info.get_child_count() - 1)
		_info.remove_child(gone)
		gone.queue_free()
	while _info.get_child_count() < rows.size():
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		row.add_child(MenuStyle.label("", 13, COLOR_CAPTION))
		var text := MenuStyle.label("", 15, COLOR_INFO)
		text.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		row.add_child(text)
		_info.add_child(row)
	for i in rows.size():
		var pair: Array = rows[i]
		var row := _info.get_child(i)
		(row.get_child(0) as Label).text = str(pair[0])
		(row.get_child(1) as Label).text = str(pair[1])
	_info.visible = not rows.is_empty()


## How tall the page has to be to show all of it, in pixels. Only right once the
## layout has run: a wrapped label measures itself at the width it was last given.
func content_height() -> float:
	return _panel.get_combined_minimum_size().y if _panel != null else 0.0
