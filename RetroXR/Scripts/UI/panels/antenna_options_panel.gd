## AntennaOptionsPanel — floating 3D panel for an Antenna: the HDHomeRun's address,
## its status, and the channels it reports.
##
## Created on demand and kept as a child of the aerial's body, the way
## ObjectOptionsPanel is, so it dies with it and a second press finds the same
## instance rather than stacking a new one. On demand matters twice over here: the
## panel owns a SubViewport, and opening it is one of the two things that make an
## aerial go and look for its tuner (the other is being plugged into a set).
##
## The subject is the BODY, not the Antenna root. The root is a CompositeCable that
## never moves — the player carries the body, which is what the panel has to float
## over, and what FloatingObjectPanel3D's lock row has to lock.
class_name AntennaOptionsPanel
extends FloatingObjectPanel3D

const PANEL_SCENE := preload("res://Scenes/UI/antenna_options_panel.tscn")
const NODE_NAME := "AntennaOptionsPanel"

## Clear of the rods: they stand 0.39 m over the body's origin, and the panel is
## half a metre tall and hangs from its centre.
const FLOAT_HEIGHT := 0.74

var _antenna: Antenna = null
var _body: Node3D = null

@onready var _viewport_node: XRToolsViewport2DIn3D = $AntennaOptionsViewport


## Open or close the panel for `antenna`, floating over `body`.
static func toggle_for(antenna: Antenna, body: Node3D, camera: Node3D) -> void:
	if antenna == null or body == null or not is_instance_valid(body):
		return
	var panel := body.get_node_or_null(NODE_NAME) as AntennaOptionsPanel
	if panel == null:
		panel = PANEL_SCENE.instantiate() as AntennaOptionsPanel
		panel.name = NODE_NAME
		body.add_child(panel)
	if panel.visible:
		panel.hide_panel()
	else:
		panel.show_for(antenna, body, camera)


func show_for(antenna: Antenna, body: Node3D, camera: Node3D) -> void:
	_antenna = antenna
	_body = body
	_camera = camera
	global_position = _anchor()
	visible = true
	_ensure_ui_connected()
	_populate()


# ── Internal helpers ───────────────────────────────────────────────────────────

func _get_ui() -> AntennaOptions2D:
	var vp := _viewport_node.get_node_or_null("Viewport") as SubViewport
	if not vp or vp.get_child_count() == 0:
		return null
	return vp.get_child(0) as AntennaOptions2D


func _ensure_ui_connected() -> void:
	if _ui_connected:
		return
	var ui := _get_ui()
	if not ui:
		call_deferred("_ensure_ui_connected")
		return
	ui.close_requested.connect(hide_panel)
	ui.channel_selected.connect(_on_channel_selected)
	ui.tuner_settings_changed.connect(_on_tuner_settings_changed)
	ui.channels_refresh_requested.connect(_on_channels_refresh)
	_ui_connected = true


func _populate() -> void:
	if not is_instance_valid(_antenna):
		return
	var ui := _get_ui()
	if not ui:
		call_deferred("_populate")
		return
	# Asking to see the channels is a legitimate reason to go and find them, even
	# with the lead lying on the floor — it is how you find out the aerial works.
	var lineup := _antenna.lineup()
	if not lineup.channels_changed.is_connected(_refresh):
		lineup.channels_changed.connect(_refresh)
	if not _antenna.topology_changed.is_connected(_refresh):
		_antenna.topology_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	var ui := _get_ui()
	if not ui or not is_instance_valid(_antenna):
		return
	var lineup := _antenna.lineup()
	var tv := _antenna.reached_set()
	ui.populate_link(_set_name(tv), _antenna.via_switch())
	ui.populate_channels(lineup.channels, tv.rf_air_index if tv != null else -1)
	ui.populate_tuner(lineup.tuner_auto(), lineup.tuner_host(),
		lineup.discovered_host(), lineup.tuner_status_line())


func _set_name(tv: RetroTV) -> String:
	if tv == null:
		return ""
	var label: Variant = tv.get("display_name")
	if label is String and not (label as String).is_empty():
		return label
	var n := str(tv.name)
	var at := n.find("@")
	return n.substr(0, at) if at > 0 else n


func _on_channel_selected(index: int) -> void:
	if not is_instance_valid(_antenna):
		return
	var tv := _antenna.reached_set()
	if tv == null:
		return
	# Picking a channel implies wanting to watch it, and the TV owns replication
	# of the resulting source + dial state.
	tv.set_channel_index(index)
	_refresh()


func _on_tuner_settings_changed(auto: bool, host: String) -> void:
	if is_instance_valid(_antenna):
		_antenna.lineup().set_tuner_config(auto, host)


func _on_channels_refresh() -> void:
	if is_instance_valid(_antenna):
		_antenna.lineup().reload_channels()


# ── Placement, for FloatingObjectPanel3D ─────────────────────────────────────

func _target_node() -> Node3D:
	return _body


func _float_height() -> float:
	return FLOAT_HEIGHT
