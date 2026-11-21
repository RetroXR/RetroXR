## TouchMenuRows — the Touch Screen section of a machine's System tab: how close to
## the glass a fingertip touches, how far off it lifts, and the touch haptic
## (TouchFeel). Only on a machine with a touch screen: a DS, a 3DS, a Wii U (its
## GamePad). Placed after the Power section, built the same way (PowerMenuRows).
##
## Lift-off is never closer than touch: raising touch past lift-off carries lift-off
## up with it, lowering lift-off under touch carries touch down, and both sliders
## show it at once.
class_name TouchMenuRows
extends VBoxContainer

var _sys: Node = null
var _touch: HSlider = null
var _touch_val: Label = null
var _lift: HSlider = null
var _lift_val: Label = null
var _haptic: HSlider = null
var _haptic_val: Label = null
## While the sliders are being set from the machine, so their signals change nothing.
var _syncing := false


## The section for `sys` in `ui`'s System tab, made the first time and refreshed
## after; removed for a machine with no touch screen. Returns it, or null.
static func ensure_in(ui: Control, sys: Node) -> TouchMenuRows:
	if ui == null:
		return null
	var existing := ui.find_child("TouchRows", true, false) as TouchMenuRows
	if existing != null and existing._sys == sys and is_instance_valid(sys):
		existing.refresh()
		return existing
	if existing != null:
		existing.get_parent().remove_child(existing)
		existing.queue_free()
	if not TouchFeel.has_touch_screen(sys):
		return null
	var parent: Container = null
	var power := ui.find_child("PowerRows", true, false)
	if power != null:
		parent = power.get_parent() as Container
	if parent == null:
		parent = PowerMenuRows._system_rows_of(ui)
	var rows := TouchMenuRows.new()
	rows.name = "TouchRows"
	rows.add_theme_constant_override("separation", 4)
	rows._sys = sys
	parent.add_child(rows)
	rows._build()
	return rows


func _build() -> void:
	add_child(MenuStyle.spacer(8))
	add_child(MenuStyle.header("Touch Screen"))
	var desc := MenuStyle.label(
		"How close to the glass a fingertip touches, and how far off it lifts again. "
		+ "Lift-off is never closer than touch.", 17, MenuStyle.COLOR_DESC)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(desc)
	var row: Array = MenuStyle.slider_row(self, "Touch distance", TouchFeel.TOUCH_MIN_MM,
		TouchFeel.TOUCH_MAX_MM, 0.1)
	_touch = row[0]
	_touch_val = row[1]
	_touch.name = "TouchDistance"
	row = MenuStyle.slider_row(self, "Lift-off distance", TouchFeel.TOUCH_MIN_MM,
		TouchFeel.LIFT_MAX_MM, 0.1)
	_lift = row[0]
	_lift_val = row[1]
	_lift.name = "LiftOffDistance"
	row = MenuStyle.slider_row(self, "Touch haptic", 0.0, 100.0, 5.0)
	_haptic = row[0]
	_haptic_val = row[1]
	_haptic.name = "TouchHaptic"
	var reset := MenuStyle.row_button("Screen's own feel", 18)
	reset.name = "TouchDefaults"
	reset.pressed.connect(_on_reset)
	add_child(reset)
	_touch.value_changed.connect(func(_v: float) -> void: _on_changed(true))
	_lift.value_changed.connect(func(_v: float) -> void: _on_changed(false))
	_haptic.value_changed.connect(func(_v: float) -> void: _on_changed(true))
	refresh()


## Show the machine's feel: what it set, or its screen's own distances.
func refresh() -> void:
	if _touch == null or not is_instance_valid(_sys):
		return
	var d := TouchFeel.distances_m(_sys, TouchFeel.defaults_mm(_sys)) * 1000.0
	_syncing = true
	_touch.value = d.x
	_lift.value = d.y
	_haptic.value = roundf(TouchFeel.haptic(_sys) * 100.0)
	_syncing = false
	_label()


func _on_changed(moved_touch: bool) -> void:
	if _syncing or not is_instance_valid(_sys):
		return
	var pair := TouchFeel.apply(_sys, _touch.value, _lift.value, _haptic.value / 100.0, moved_touch)
	_syncing = true
	_touch.value = pair.x
	_lift.value = pair.y
	_syncing = false
	_label()


func _on_reset() -> void:
	if not is_instance_valid(_sys):
		return
	TouchFeel.reset(_sys)
	refresh()


func _label() -> void:
	_touch_val.text = "%.1f mm" % _touch.value
	_lift_val.text = "%.1f mm" % _lift.value
	_haptic_val.text = "Off" if _haptic.value <= 0.0 else "%d%%" % roundi(_haptic.value)
