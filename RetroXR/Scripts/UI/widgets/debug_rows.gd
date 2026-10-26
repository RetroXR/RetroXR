## DebugRows — a menu's Debug page: titled sections of label / value rows.
##
## Fed [[section, [[label, value], ...]], ...] — what RetroSystem.debug_state(),
## VCRPlayer.debug_state() and RetroAudioPlayer.debug_state() return. The rows are
## rebuilt only when the LABELS change; a refresh that changes values alone (every
## refresh while something plays) rewrites text, so the page does not flicker or
## lose its scroll under a pointer.
class_name DebugRows
extends VBoxContainer

const COLOR_TITLE := Color(0.9, 0.9, 1.0)
const COLOR_ROW := Color(0.65, 0.65, 0.80)

## Width of the label column, px.
const LABEL_WIDTH := 190

## One value Label per row, in order. Read by the suites.
var values: Array[Label] = []
var _sig := ""


func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 2)


func show_sections(sections: Array) -> void:
	var labels := PackedStringArray()
	for s: Array in sections:
		labels.append("#" + str(s[0]))
		for row: Array in s[1]:
			labels.append(str(row[0]))
	var sig := "|".join(labels)
	if sig != _sig:
		_sig = sig
		for c in get_children():
			remove_child(c)
			c.queue_free()
		values.clear()
		for s: Array in sections:
			add_child(MenuStyle.label(str(s[0]), 20, COLOR_TITLE))
			for row: Array in s[1]:
				var line := MenuStyle.hbox(8)
				var name_lbl := MenuStyle.label(str(row[0]), 16, COLOR_ROW)
				name_lbl.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
				line.add_child(name_lbl)
				var val := MenuStyle.label("", 16, COLOR_TITLE)
				val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				val.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				line.add_child(val)
				add_child(line)
				values.append(val)
			add_child(MenuStyle.spacer(6))
	var i := 0
	for s: Array in sections:
		for row: Array in s[1]:
			values[i].text = str(row[1])
			i += 1
