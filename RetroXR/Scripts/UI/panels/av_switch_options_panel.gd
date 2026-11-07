## AvSwitchOptionsPanel — the floating menu over an AvSwitch (VCROptionsPanel's arrangement): the slide's input from
## the menu, the power rows, and a Debug tab read from AvSwitch.debug_state() while it is the tab showing.
class_name AvSwitchOptionsPanel
extends FloatingObjectPanel3D

const FLOAT_HEIGHT := 0.30
## How often the Debug tab re-reads the switch while it shows; a change the switch sees refreshes it at once too.
const DEBUG_POLL_S := 1.0

var _switch: AvSwitch = null
var _debug_poll := 0.0

@onready var _viewport_node: XRToolsViewport2DIn3D = $AvSwitchOptionsViewport


func show_for(switch: AvSwitch, camera: Node3D) -> void:
	_switch = switch
	_camera = camera
	if _switch:
		global_position = _switch.global_position + Vector3(0, FLOAT_HEIGHT, 0)
	visible = true
	_ensure_ui_connected()
	refresh()


## Re-read the switch into every tab (the switch calls it when its wiring, slide or labels change).
func refresh() -> void:
	var ui := ui_2d()
	if ui == null:
		call_deferred("refresh")
		return
	if not is_instance_valid(_switch):
		return
	var sources: Array = []
	var labels: Array = []
	for i in AvSwitch.INPUTS:
		var dev := _switch.source_device(i)
		sources.append("nothing" if dev == null else String(dev.name))
		labels.append(AvSwitch.LABEL_WORDS[_switch.label_state(i)])
	ui.populate(_switch.selected, sources, labels)
	ui.populate_debug(_switch.debug_state())
	PowerMenuRows.ensure_in(ui, _switch.power_input())


func _ensure_ui_connected() -> void:
	if _ui_connected:
		return
	var ui := ui_2d()
	if ui == null:
		call_deferred("_ensure_ui_connected")
		return
	ui.input_selected.connect(_on_input_selected)
	ui.close_requested.connect(hide_panel)
	_ui_connected = true


func _on_input_selected(index: int) -> void:
	if is_instance_valid(_switch):
		_switch.select(index)


func ui_2d() -> AvSwitchOptions2D:
	if _viewport_node == null:
		return null
	var vp := _viewport_node.get_node_or_null("Viewport") as SubViewport
	return vp.get_child(0) as AvSwitchOptions2D if vp and vp.get_child_count() > 0 else null


func _target_node() -> Node3D:
	return _switch


func _float_height() -> float:
	return FLOAT_HEIGHT


func _while_shown(delta: float) -> void:
	_debug_poll += delta
	if _debug_poll < DEBUG_POLL_S:
		return
	_debug_poll = 0.0
	var ui := ui_2d()
	if ui != null and ui.is_debug_tab_shown() and is_instance_valid(_switch):
		ui.populate_debug(_switch.debug_state())
