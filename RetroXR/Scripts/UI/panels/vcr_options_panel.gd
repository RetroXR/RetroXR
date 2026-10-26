## VCROptionsPanel — floating 3D panel that displays settings for a VCRPlayer.
##
## Parented to a VCRPlayer node but uses top_level=true so it inherits no transform.
## Each frame it repositions itself above the owning VCR and faces the camera.
## Opened/closed via show_for()/hide_panel(); also has an in-UI ✕ close button.
## Mirrors CoreOptionsPanel.
class_name VCROptionsPanel
extends FloatingObjectPanel3D

## Height above the VCR's origin at which the panel floats.
const FLOAT_HEIGHT := 0.42

var _vcr: VCRPlayer = null

@onready var _viewport_node: XRToolsViewport2DIn3D = $VCROptionsViewport


# ── Public API ─────────────────────────────────────────────────────────────────

## Show the panel for the given VCR, looking toward the given camera.
func show_for(vcr: VCRPlayer, camera: Node3D) -> void:
	_vcr = vcr
	_camera = camera
	if _vcr:
		global_position = _vcr.global_position + Vector3(0, FLOAT_HEIGHT, 0)
	visible = true
	_ensure_ui_connected()
	_populate()


# ── Internal helpers ───────────────────────────────────────────────────────────

func _ensure_ui_connected() -> void:
	if _ui_connected:
		return
	var vp := _viewport_node.get_node_or_null("Viewport") as SubViewport
	if not vp or vp.get_child_count() == 0:
		call_deferred("_ensure_ui_connected")
		return
	var ui := vp.get_child(0) as VCROptions2D
	if not ui:
		push_warning("[VCROptionsPanel] SubViewport child is not VCROptions2D")
		return
	ui.effect_toggled.connect(_on_effect_toggled)
	ui.scan_speed_changed.connect(_on_scan_speed_changed)
	ui.vcr_param_changed.connect(_on_vcr_param_changed)
	ui.close_requested.connect(hide_panel)
	ui.ignore_gravity_toggled.connect(_on_ignore_gravity_toggled)
	_ui_connected = true


func _populate() -> void:
	if not _vcr:
		return
	var vp := _viewport_node.get_node_or_null("Viewport") as SubViewport
	if not vp or vp.get_child_count() == 0:
		call_deferred("_populate")
		return
	var ui := vp.get_child(0) as VCROptions2D
	if not ui:
		return
	ui.populate(_vcr.vcr_effect_enabled, _vcr.scan_speed, _vcr.get_ignore_gravity())
	ui.populate_vcr(_vcr.get_vcr_params())
	ui.populate_debug(_vcr.debug_state())


func _on_ignore_gravity_toggled(enabled: bool) -> void:
	if _vcr and is_instance_valid(_vcr):
		_vcr.set_ignore_gravity(enabled)


func _on_effect_toggled(enabled: bool) -> void:
	if _vcr and is_instance_valid(_vcr):
		_vcr.set_vcr_effect_enabled(enabled)


func _on_scan_speed_changed(value: float) -> void:
	if _vcr and is_instance_valid(_vcr):
		_vcr.scan_speed = value


func _on_vcr_param_changed(pname, value) -> void:
	if _vcr and is_instance_valid(_vcr):
		_vcr.set_vcr_param(pname, value)


# ── Placement, for FloatingObjectPanel3D ─────────────────────────────────────

func _target_node() -> Node3D:
	return _vcr


func _float_height() -> float:
	return FLOAT_HEIGHT


# ── Debug tab ────────────────────────────────────────────────────────────────

## How often the Debug tab re-reads the deck, while it is the tab showing.
const DEBUG_POLL_S := 0.5
var _debug_poll := 0.0


func _while_shown(delta: float) -> void:
	_debug_poll += delta
	if _debug_poll < DEBUG_POLL_S:
		return
	_debug_poll = 0.0
	var ui := _vcr_ui()
	if ui != null and ui.is_debug_tab_shown() and is_instance_valid(_vcr):
		ui.populate_debug(_vcr.debug_state())


func _vcr_ui() -> VCROptions2D:
	var vp := _viewport_node.get_node_or_null("Viewport") as SubViewport
	return vp.get_child(0) as VCROptions2D if vp and vp.get_child_count() > 0 else null
