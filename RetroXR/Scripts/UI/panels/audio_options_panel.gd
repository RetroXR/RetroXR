## AudioOptionsPanel — floating 3D panel for a CD or cassette player.
##
## Parented to the player but top_level, so it inherits no transform; floats
## above the unit facing the camera. Mirrors MouseOptionsPanel.
class_name AudioOptionsPanel
extends FloatingObjectPanel3D

## Height above the player's origin at which the panel floats.
const FLOAT_HEIGHT := 0.3

var _player: RetroAudioPlayer = null

@onready var _viewport_node: XRToolsViewport2DIn3D = $AudioOptionsViewport


func show_for(player: RetroAudioPlayer, camera: Node3D) -> void:
	_player = player
	_camera = camera
	if _player:
		global_position = _player.global_position + Vector3(0, FLOAT_HEIGHT, 0)
	visible = true
	_ensure_ui_connected()
	_populate()


func _get_ui() -> AudioOptions2D:
	var vp := _viewport_node.get_node_or_null("Viewport") as SubViewport
	if not vp or vp.get_child_count() == 0:
		return null
	return vp.get_child(0) as AudioOptions2D


func _ensure_ui_connected() -> void:
	if _ui_connected:
		return
	var ui := _get_ui()
	if not ui:
		call_deferred("_ensure_ui_connected")
		return
	ui.ignore_gravity_toggled.connect(_on_ignore_gravity_toggled)
	ui.close_requested.connect(hide_panel)
	_ui_connected = true


func _populate() -> void:
	if not _player:
		return
	var ui := _get_ui()
	if not ui:
		call_deferred("_populate")
		return
	ui.populate(_player.player_label, _player.get_ignore_gravity())
	ui.populate_debug(_player.debug_state())
	PowerMenuRows.ensure_in(ui, _player.power_input())


func _on_ignore_gravity_toggled(enabled: bool) -> void:
	if _player and is_instance_valid(_player):
		_player.set_ignore_gravity(enabled)


# ── Placement, for FloatingObjectPanel3D ─────────────────────────────────────

func _target_node() -> Node3D:
	return _player


func _float_height() -> float:
	return FLOAT_HEIGHT


# ── Debug tab ────────────────────────────────────────────────────────────────

## How often the Debug tab re-reads the deck, while it is the tab showing.
const DEBUG_POLL_S := 1.0
var _debug_poll := 0.0


func _while_shown(delta: float) -> void:
	_debug_poll += delta
	if _debug_poll < DEBUG_POLL_S:
		return
	_debug_poll = 0.0
	var ui := _get_ui()
	if ui != null and ui.is_debug_tab_shown() and is_instance_valid(_player):
		ui.populate_debug(_player.debug_state())
