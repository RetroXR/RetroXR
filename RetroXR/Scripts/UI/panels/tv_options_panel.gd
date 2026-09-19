## TVOptionsPanel — floating 3D panel that displays settings for a RetroTV.
##
## Parented to a RetroTV node but uses top_level=true so it inherits no transform.
## Each frame it repositions itself above the owning TV and faces the camera.
## Opened/closed via show_for()/hide_panel(); also has an in-UI ✕ close button.
## Mirrors BookOptionsPanel / VCROptionsPanel.
class_name TVOptionsPanel
extends FloatingObjectPanel3D

## Gap between the top of the set and the bottom edge of the panel.
const CLEARANCE := 0.10

## Fallback height above the TV's origin, for a set that reports no geometry.
const FLOAT_HEIGHT := 0.55

## Built on first open, not with the panel — see CoreOptionsPanel.UI_SCENE.
const UI_SCENE := preload("res://Scenes/UI/tv_options_2d.tscn")

var _tv: RetroTV = null
## Top of the owning set above its origin, in the set's own metres at scale 1.
## Measured once per open and multiplied by the live display scale every frame,
## so dragging the size slider carries the panel with it without re-sweeping the
## cabinet's meshes each tick.
var _tv_top := 0.0

@onready var _viewport_node: XRToolsViewport2DIn3D = $TVOptionsViewport


# ── Public API ─────────────────────────────────────────────────────────────────

## Show the panel for the given TV, looking toward the given camera.
func show_for(tv: RetroTV, camera: Node3D) -> void:
	_tv = tv
	_camera = camera
	# Before `visible`, not after: our own viewport quad is a child of the set, so
	# a sweep taken with the panel already up measures the last panel and walks
	# further from the cabinet on every open.
	_measure_tv()
	if _tv:
		global_position = _anchor()
	visible = true
	if _viewport_node.scene == null:
		_viewport_node.scene = UI_SCENE
	_ensure_ui_connected()
	_populate()


# ── Placement ─────────────────────────────────────────────────────────────────

## Where the panel floats: clear of the top of the set, whatever size it is.
##
## The panel keeps its own world size — top_level means it never inherits the
## set's scale — so the whole panel, not just its centre, has to be lifted past
## the cabinet: half its height plus the gap.
func _anchor() -> Vector3:
	if _tv_top <= 0.0:
		return _tv.global_position + Vector3.UP * FLOAT_HEIGHT
	return _tv.global_position + Vector3.UP * (
		_tv_top * _tv.get_scale_factor() + CLEARANCE + _half_height())


func _half_height() -> float:
	return _viewport_node.screen_size.y * 0.5 if _viewport_node else 0.0


## Measure the cabinet. HeldHint's sweep rather than a second one of our own: the
## hint floats over the same set and the two must not disagree about where it ends.
func _measure_tv() -> void:
	_tv_top = 0.0
	if _tv and is_instance_valid(_tv):
		_tv_top = maxf(HeldHint.visual_top(_tv), 0.0)


# ── Internal helpers ───────────────────────────────────────────────────────────

func _get_ui() -> TVOptions2D:
	var vp := _viewport_node.get_node_or_null("Viewport") as SubViewport
	if not vp or vp.get_child_count() == 0:
		return null
	return vp.get_child(0) as TVOptions2D


func _ensure_ui_connected() -> void:
	if _ui_connected:
		return
	var ui := _get_ui()
	if not ui:
		call_deferred("_ensure_ui_connected")
		return
	ui.scale_changed.connect(_on_scale_changed)
	ui.scale_committed.connect(_on_scale_committed)
	ui.crt_param_changed.connect(_on_crt_param_changed)
	ui.close_requested.connect(hide_panel)
	ui.ignore_gravity_toggled.connect(_on_ignore_gravity_toggled)
	_ui_connected = true


func _populate() -> void:
	if not _tv:
		return
	var ui := _get_ui()
	if not ui:
		call_deferred("_populate")
		return
	ui.populate(_tv.get_scale_factor(), _tv.get_ignore_gravity())
	ui.populate_crt(_tv.get_crt_params())
	# No tuner is built here any more. This used to be the first thing that
	# legitimately needed one — the panel carried the channel list — and opening a
	# set's menu to resize it spun up a VlcPlayer as a side effect. The list is on
	# the aerial's menu now (AntennaOptionsPanel).


## A CRT filter slider/dropdown moved — apply live to the local TV.
func _on_crt_param_changed(pname, value) -> void:
	if _tv and is_instance_valid(_tv):
		_tv.set_crt_param(pname, value)


## Live while the slider is dragged — resizes the local TV every tick.
func _on_scale_changed(factor: float) -> void:
	if _tv and is_instance_valid(_tv):
		_tv.set_tv_scale(factor)


func _on_ignore_gravity_toggled(enabled: bool) -> void:
	if _tv and is_instance_valid(_tv):
		_tv.set_ignore_gravity(enabled)


## Drag finished — apply locally and replicate the final size to other players.
func _on_scale_committed(factor: float) -> void:
	if _tv and is_instance_valid(_tv):
		_tv.set_tv_scale(factor)
		NetworkManager.report_event(NetEvents.Event.EV_TV_SIZE,
			{"tv": _tv, "scale": factor})


# ── Placement, for FloatingObjectPanel3D ─────────────────────────────────────

func _target_node() -> Node3D:
	return _tv
