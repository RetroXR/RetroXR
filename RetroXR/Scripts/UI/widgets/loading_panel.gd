## LoadingPanel — the loading screen itself, with nothing around it.
##
## Split out of LoadingRig so the same panel can cover a room that is ALREADY in
## the tree. The rig owns a WorldEnvironment and a fallback camera and therefore
## has to leave before the incoming scene enters; this has neither, so it can hang
## in front of a live room while that room's objects are still being built. That
## gap — the room visible, its contents still arriving — is the whole reason this
## exists.
##
## Two things move independently and the split is deliberate. `Screen` is
## yaw-smoothed so a deliberate turn brings the panel round without copying every
## twitch. `Curtain` is parented straight to the camera and so is FULLY
## head-locked: a yaw-smoothed curtain lags a head turn and shows a sliver of the
## room it is supposed to be hiding.
##
## On a DESKTOP (not in a headset) the same screen is a flat 2D one: a CanvasLayer over the
## picture, centred, with its own curtain, instead of a quad standing in the world with
## perspective and a yaw that follows the camera. The 3D nodes stay (the rig, the overlay and
## the tests drive them) but are hidden there. A headset keeps the 3D panel: there is no screen
## to lay a layer on, only a world.
class_name LoadingPanel
extends Node3D


## Fast enough to follow a deliberate turn, slow enough to ignore small movements.
const FOLLOW_RATE := 6.0

## Resolved by _ensure() rather than @onready, because a caller can reach this
## panel before its _ready has run. A node added to a parent that is not itself
## ready yet has its own _ready DEFERRED, and the boot curtain goes up from
## SceneManager._ready while the LoadingOverlay autoload is still being set up —
## so every @onready here was still null on the first set_progress.
var _screen: Node3D = null
var _curtain: MeshInstance3D = null
var _title_label: Label3D = null
var _status_label: Label3D = null
var _percent_label: Label3D = null
var _detail_label: Label3D = null
var _progress_material: ShaderMaterial = null
var _resolved := false

var _player_camera: XRCamera3D = null
var _player_origin: Node3D = null
var _progress: float = 0.0
var _animation_time: float = 0.0
var _status_text: String = "PREPARING ROOM"
## Set by set_status(). While it is non-empty the band derived from progress is
## suppressed — a caller that knows it is on object 14 of 31 has more to say than
## "LOADING ROOM DATA".
var _status_override: String = ""
var _last_percent: int = -1
var _last_status_rendered: String = ""
var _load_failed: bool = false
var _following: bool = false

# The flat 2D screen of a desktop run. Built only there (see _use_2d).
const COLOR_CURTAIN := Color(0.008, 0.01, 0.025, 1.0)
const COLOR_FRAME := Color(0.10, 0.14, 0.30, 1.0)
const COLOR_PANEL := Color(0.025, 0.03, 0.075, 1.0)
const LAYER_2D := 130
var _layer: CanvasLayer = null
## The curtain has a layer of its own, unscaled and anchored to the viewport: it must cover the
## picture at every window size at every moment, which a layer scaled with the window and sized by
## a script one frame after the window moved does not (the room showed in the strip it had not
## yet reached when a launch resized the window).
var _curtain_layer: CanvasLayer = null
var _root_2d: Control = null
var _c_title: Label = null
var _c_status: Label = null
var _c_percent: Label = null
var _c_detail: Label = null
var _c_bar: Control = null
var _layer_scale: float = 1.0


func _ensure() -> void:
	if _resolved:
		return
	_screen = get_node_or_null("Screen") as Node3D
	if _screen == null:
		return
	_curtain = get_node_or_null("Curtain") as MeshInstance3D
	_title_label = _screen.get_node_or_null("TitleLabel") as Label3D
	_status_label = _screen.get_node_or_null("StatusLabel") as Label3D
	_percent_label = _screen.get_node_or_null("PercentLabel") as Label3D
	_detail_label = _screen.get_node_or_null("DetailLabel") as Label3D
	var bar := _screen.get_node_or_null("ProgressBar") as MeshInstance3D
	if bar != null:
		_progress_material = bar.get_surface_override_material(0) as ShaderMaterial
	_resolved = true
	if _use_2d():
		_build_2d()


func _ready() -> void:
	_ensure()
	visibility_changed.connect(_sync_layer_visibility)
	if _following:
		_follow_player(0.0, true)
	_apply_progress()


func _process(delta: float) -> void:
	_animation_time += delta
	if _following:
		_follow_player(delta)
	_update_status_label()
	if _layer != null and _layer.visible:
		_fit_2d()
		_c_bar.queue_redraw()


## Track the player's head without touching the scene tree. This is what
## LoadingRig uses: there the panel stands in an empty world behind the rig's own
## dark WorldEnvironment, so nothing can show past the curtain and the yaw
## smoothing is free to lag.
func follow(camera: XRCamera3D, origin: Node3D) -> void:
	if not is_instance_valid(camera):
		return
	_player_camera = camera
	_player_origin = origin
	_following = true
	if is_inside_tree():
		_follow_player(0.0, true)


## Same, plus the curtain is reparented onto the camera so it is FULLY
## head-locked — the PerfHud pattern, where plain parenting costs nothing per
## frame and cannot lag. Only LoadingOverlay uses this, and only because it
## covers a room that is really there: a yaw-smoothed curtain lags a head turn
## and shows a sliver of the room it is meant to be hiding.
##
## detach() must be called before this node dies, or the curtain is left behind
## on a camera that outlives it. _exit_tree does that.
func attach_to(camera: XRCamera3D, origin: Node3D) -> void:
	follow(camera, origin)
	if not _following:
		return
	if is_instance_valid(_curtain) and _curtain.get_parent() != camera:
		_curtain.get_parent().remove_child(_curtain)
		camera.add_child(_curtain)
		_curtain.transform = Transform3D(Basis(), Vector3(0.0, 0.0, -10.5))


## The curtain may be parented to a camera we do not own, so leaving the tree has
## to reclaim it. Without this, a panel freed while attached leaves a 44x30 quad
## welded to the player's face for the rest of the session.
func _exit_tree() -> void:
	detach()


## Put the curtain back under this node and stop following. Safe to call when
## never attached, and safe while the camera is already being freed — the curtain
## is ours, so it is reclaimed rather than left behind on a dying node.
func detach() -> void:
	if is_instance_valid(_curtain):
		var parent := _curtain.get_parent()
		if parent != null and parent != self:
			parent.remove_child(_curtain)
			add_child(_curtain)
			_curtain.transform = Transform3D(Basis(), Vector3(0.0, 1.65, -10.5))
	_player_camera = null
	_player_origin = null
	_following = false


func _follow_player(delta: float, snap: bool = false) -> void:
	_ensure()
	if not is_instance_valid(_player_camera) or _screen == null:
		return
	var here := _player_camera.global_position
	here.y = _player_origin.global_position.y if is_instance_valid(_player_origin) else 0.0
	global_position = here
	var target_yaw := _player_camera.global_rotation.y
	if snap:
		_screen.global_rotation.y = target_yaw
	else:
		# lerp_angle cannot overshoot the way a fixed angular step can.
		var weight := 1.0 - exp(-FOLLOW_RATE * delta)
		_screen.global_rotation.y = lerp_angle(_screen.global_rotation.y, target_yaw, weight)


## What is being loaded, shown above the bar.
func set_title(title: String) -> void:
	_ensure()
	if _title_label != null:
		_title_label.text = title
	if _c_title != null:
		_c_title.text = title


## Say what is happening in words, instead of the band derived from progress.
## An empty string hands the band back.
func set_status(text: String) -> void:
	_ensure()
	_status_override = text
	if _status_override.is_empty():
		_apply_progress_status()
	else:
		_status_text = _status_override
	_update_status_label()


## Extra rows under the bar — a netplay transfer's phase and byte counts. Empty
## clears them.
func set_detail(rows: PackedStringArray) -> void:
	_ensure()
	if not is_instance_valid(_detail_label):
		return
	_detail_label.text = "\n".join(rows)
	if _c_detail != null:
		_c_detail.text = _detail_label.text


func set_progress(value: float) -> void:
	if _load_failed:
		return
	# Threaded-loader progress should be monotonic, but individual dependency
	# reports can briefly move backwards. A loading bar must never do the same.
	_progress = maxf(_progress, clampf(value, 0.0, 1.0))
	_apply_progress()


func _apply_progress() -> void:
	_ensure()
	if _progress_material == null:
		return
	_progress_material.set_shader_parameter("progress", _progress)
	var percent := roundi(_progress * 100.0)
	if percent != _last_percent:
		_last_percent = percent
		_percent_label.text = "%d%%" % percent
		if _c_percent != null:
			_c_percent.text = _percent_label.text
	if _status_override.is_empty():
		_apply_progress_status()
	_update_status_label()


func _apply_progress_status() -> void:
	if _progress >= 1.0:
		_status_text = "READY"
	elif _progress >= 0.9:
		_status_text = "FINISHING SETUP"
	elif _progress >= 0.05:
		_status_text = "LOADING ROOM DATA"
	else:
		_status_text = "PREPARING ROOM"


## Make the failure unmistakable without taking the player's view away. The
## caller decides how long it stays.
func show_load_error(message: String = "RETRY OR CHOOSE ANOTHER ROOM") -> void:
	_ensure()
	_load_failed = true
	if _title_label != null:
		_title_label.text = "LOAD FAILED"
	_status_override = message
	_status_text = message
	_percent_label.text = "!"
	if _c_title != null:
		_c_title.text = "LOAD FAILED"
	if _c_percent != null:
		_c_percent.text = "!"
	_progress_material.set_shader_parameter("failed", true)
	_progress_material.set_shader_parameter("progress", 1.0)
	_update_status_label()


## Back to a fresh screen, so one panel instance can serve a second show without
## inheriting the first one's bar position or error state.
func reset() -> void:
	_ensure()
	_load_failed = false
	_progress = 0.0
	_status_override = ""
	_last_percent = -1
	_progress_material.set_shader_parameter("failed", false)
	set_detail(PackedStringArray())
	_apply_progress()


func _update_status_label() -> void:
	if _status_label == null:
		return
	var rendered := _status_text
	if _load_failed or _progress >= 1.0:
		rendered += "   "
	else:
		var dot_count := int(_animation_time / 0.35) % 4
		rendered += ".".repeat(dot_count) + " ".repeat(3 - dot_count)
	if rendered != _last_status_rendered:
		_last_status_rendered = rendered
		_status_label.text = rendered
		if _c_status != null:
			_c_status.text = rendered


# ── The flat screen of a desktop run ──────────────────────────────────────────

## True where there is a screen to put a layer on: anywhere that is not a headset.
func _use_2d() -> bool:
	return not MenuStyle.is_vr_mode()


func _build_2d() -> void:
	if _layer != null:
		return
	# The 3D screen and its curtain are replaced, not drawn under: a hidden quad costs nothing.
	if _screen != null:
		_screen.visible = false
	if _curtain != null:
		_curtain.visible = false
	_curtain_layer = CanvasLayer.new()
	_curtain_layer.name = "Curtain2D"
	_curtain_layer.layer = LAYER_2D - 1
	add_child(_curtain_layer)
	var curtain := ColorRect.new()
	curtain.color = COLOR_CURTAIN
	curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	curtain.mouse_filter = Control.MOUSE_FILTER_STOP
	_curtain_layer.add_child(curtain)

	_layer = CanvasLayer.new()
	_layer.name = "Screen2D"
	_layer.layer = LAYER_2D
	add_child(_layer)

	_root_2d = Control.new()
	_root_2d.name = "Root"
	_root_2d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_root_2d)

	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root_2d.add_child(centre)

	var frame := PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = COLOR_PANEL
	box.border_color = COLOR_FRAME
	box.set_border_width_all(4)
	box.set_corner_radius_all(6)
	box.set_content_margin_all(36)
	frame.add_theme_stylebox_override("panel", box)
	frame.custom_minimum_size = Vector2(620, 0)
	centre.add_child(frame)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	frame.add_child(column)

	var icon := TextureRect.new()
	icon.texture = load("res://Textures/app_icon.png")
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(84, 84)
	column.add_child(icon)

	column.add_child(_label_2d("RETRO XR", 40, Color(0.28, 0.72, 1.0)))
	_c_title = _label_2d("LOADING", 34, Color(0.92, 0.94, 1.0))
	column.add_child(_c_title)
	_c_status = _label_2d("PREPARING ROOM", 22, Color(0.56, 0.62, 0.78))
	column.add_child(_c_status)

	_c_bar = Bar2D.new()
	_c_bar.panel = self
	_c_bar.custom_minimum_size = Vector2(0, 22)
	column.add_child(_c_bar)

	_c_percent = _label_2d("0%", 26, Color(0.28, 1.0, 0.7))
	column.add_child(_c_percent)
	_c_detail = _label_2d("", 18, Color(0.45, 0.55, 0.7))
	column.add_child(_c_detail)

	# What the 3D labels hold now, in case anything was said before this was built.
	if _title_label != null:
		_c_title.text = _title_label.text
	if _detail_label != null:
		_c_detail.text = _detail_label.text
	_fit_2d()
	# At once when the window moves, not on the next _process: that is a frame drawn with the
	# screen sized for the old window.
	var viewport := get_viewport()
	if viewport != null and not viewport.size_changed.is_connected(_fit_2d):
		viewport.size_changed.connect(_fit_2d)
	_sync_layer_visibility()


func _label_2d(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "Courier New", "monospace"])
	l.add_theme_font_override("font", font)
	return l


## Scale the whole screen with the window so it fits a small one and does not shrink in a big
## one: 1 at 720 px tall, between half and one and a half of that.
func _fit_2d() -> void:
	if _layer == null or _root_2d == null:
		return
	var size := get_viewport().get_visible_rect().size
	if size.y <= 0.0:
		return
	var k := clampf(size.y / 720.0, 0.5, 1.5)
	if is_equal_approx(k, _layer_scale) and _root_2d.size.is_equal_approx(size / k):
		return
	_layer_scale = k
	_layer.transform = Transform2D().scaled(Vector2(k, k))
	_root_2d.position = Vector2.ZERO
	_root_2d.size = size / k


## A CanvasLayer is not hidden by its parent Node3D's visibility, so suspend() and resume()
## in LoadingOverlay would otherwise leave the flat screen up while the rig has the view.
func _sync_layer_visibility() -> void:
	if _layer != null:
		_layer.visible = visible
		_curtain_layer.visible = visible


## True while the flat screen is the one being shown (a desktop run).
func shows_2d() -> bool:
	return _layer != null


## The bar of the flat screen, drawn the way the 3D one is shaded: segments, a pulse, and the
## error colours when the load failed.
class Bar2D extends Control:
	var panel: LoadingPanel = null

	func _draw() -> void:
		if panel == null:
			return
		var w := size.x
		var h := size.y
		var segments := 18
		var seg_w := w / segments
		var pulse_t := Time.get_ticks_msec() / 1000.0
		for i in segments:
			var x := i * seg_w
			var u := (float(i) + 0.5) / segments
			var filled := u <= panel._progress
			var color := Color(0.075, 0.085, 0.17)
			if filled:
				var pulse := 0.88 + 0.12 * sin(pulse_t * 4.0 - u * 9.0)
				var start := Color(1.0, 0.18, 0.12) if panel._load_failed else Color(0.28, 0.55, 1.0)
				var end := Color(1.0, 0.55, 0.12) if panel._load_failed else Color(0.20, 1.0, 0.70)
				color = start.lerp(end, u) * pulse
				color.a = 1.0
			draw_rect(Rect2(x, h * 0.06, seg_w * 0.86, h * 0.88), color)
