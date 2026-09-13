## TvFullscreen — desktop only: the picture on the screen you are looking at
## lerps out to fill the application window, and back on the same key.
##
## Works for a television and for a handheld. The overlay never knows either
## class; it works over PANELS — one per picture quad — each carrying the mesh
## to project, where its picture comes from, which part of that texture it
## shows, and the aspect it is drawn at. A TV is one panel, a Game Boy is one,
## a DS is two stacked the way the device stacks them.
##
## It reads the picture, it never paints it: the texture the glass samples is
## re-read every frame, so snow, the blue screen, a source change and power-off
## all follow the device. Movement is blocked through LocomotionManager while
## the picture is up; mouse-look is outside that channel on purpose, so the turn
## provider is switched off here as well.
class_name TvFullscreen
extends CanvasLayer

const ACTION := &"desktop_tv_fullscreen"
const BLOCK_OWNER := &"tv_fullscreen"
const DURATION := 0.35

var _camera: Camera3D = null
var _pickup: Node = null
var _turn: Node = null
var _reticle: Node = null
var _loco: LocomotionManager = null

var _backdrop: ColorRect = null
var _device: WeakRef = null
var _panels: Array[Dictionary] = []
var _t := 0.0
var _opening := false


func _ready() -> void:
	layer = 120
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0, 0, 0, 0)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_backdrop)
	visible = false
	set_process(false)
	var rig := get_parent() as PlayerRig
	if rig != null:
		configure(rig.camera, rig.camera,
			rig.get_node_or_null("Staging/XROrigin3D/MovementDesktopTurn"),
			rig.get_node_or_null("DesktopReticle"),
			rig.get_node_or_null("LocomotionManager"))


func configure(camera: Camera3D, pickup: Node, turn: Node, reticle: Node,
		loco: LocomotionManager) -> void:
	_camera = camera
	_pickup = pickup
	_turn = turn
	_reticle = reticle
	_loco = loco


func is_active() -> bool:
	return visible


func _unhandled_input(event: InputEvent) -> void:
	if get_viewport().use_xr or not event.is_action_pressed(ACTION):
		return
	get_viewport().set_input_as_handled()
	if visible:
		close()
		return
	if _pickup == null or not _pickup.has_method("aimed_target"):
		return
	open(device_from_target(_pickup.aimed_target()))


## The television or handheld behind a crosshair hit, or null. Walks up from the
## hit node: a DS bottom screen resolves as a pointer target, so the action node
## alone would miss it.
static func device_from_target(target: InteractionTarget) -> Node3D:
	if target == null:
		return null
	for start: Node3D in [target.hit_node, target.action_node]:
		var node: Node = start
		while is_instance_valid(node):
			if node is RetroTV or node is RetroSystem:
				return node
			node = node.get_parent()
	return null


## One panel per picture quad on the device, or none when it has nothing to show.
static func panels_for(device: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if device is RetroTV:
		var tv := device as RetroTV
		out.append({
			"mesh": tv.screen_mesh(),
			"texture_fn": tv.display().screen_texture,
			"region": Rect2(0, 0, 1, 1),
			"aspect_fn": func() -> float:
				return RetroTV.ASPECT_16_9 if tv.widescreen else RetroTV.ASPECT_4_3,
			"fit_fn": tv.display().aspect_fit,
		})
		return out
	if device is RetroSystem:
		var sys := device as RetroSystem
		var model := sys.get_model()
		if model == null or not model.is_handheld() or model.host_picture_on_tv() \
				or not model.has_method("channel_screens"):
			return out
		var screens: Array[MeshInstance3D] = model.channel_screens()
		var channels: Array = model.get_video_channels()
		for i in mini(screens.size(), channels.size()):
			var channel: Dictionary = channels[i]
			# A stereo channel's rect is already the left eye; eye_shift is where
			# the right one starts, and a flat window shows one eye.
			var region: Rect2 = channel.get("rect", Rect2(0, 0, 1, 1))
			var screen := screens[i]
			out.append({
				"mesh": screen,
				"texture_fn": sys.get_video_texture,
				"region": region,
				"aspect_fn": func() -> float:
					var s := _quad_size(screen)
					return s.x / s.y if s.y > 0.0 else 1.0,
				"fit_fn": func() -> Vector2: return Vector2.ONE,
			})
	return out


static func _quad_size(screen: MeshInstance3D) -> Vector2:
	var s := Vector2.ONE
	if screen.mesh is QuadMesh:
		s = (screen.mesh as QuadMesh).size
	elif screen.mesh != null:
		var aabb := screen.mesh.get_aabb()
		s = Vector2(aabb.size.x, aabb.size.y)
	return Vector2(s.x * absf(screen.scale.x), s.y * absf(screen.scale.y))


## Take the device's picture to the window. False when it has none to take.
func open(device: Node3D) -> bool:
	if visible or device == null or _camera == null or get_viewport().use_xr:
		return false
	var panels := panels_for(device)
	if panels.is_empty():
		return false
	_device = weakref(device)
	_panels = panels
	for panel: Dictionary in _panels:
		var rect := TextureRect.new()
		rect.stretch_mode = TextureRect.STRETCH_SCALE
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(rect)
		panel["node"] = rect
		panel["atlas"] = AtlasTexture.new()
	_t = 0.0
	_opening = true
	visible = true
	set_process(true)
	_block(true)
	_step(0.0)
	return true


## Send the picture back where it came from.
func close() -> void:
	if not visible:
		return
	_opening = false


func _process(delta: float) -> void:
	var device: Node3D = _device.get_ref() if _device != null else null
	if not is_instance_valid(device):
		_teardown()
		return
	_step(delta)


func _step(delta: float) -> void:
	_t = clampf(_t + (delta if _opening else -delta) / DURATION, 0.0, 1.0)
	if not _opening and _t <= 0.0:
		_teardown()
		return
	var e := smoothstep(0.0, 1.0, _t)
	_backdrop.color.a = e
	var full := full_rects(_aspects(), get_viewport().get_visible_rect())
	for i in _panels.size():
		var panel := _panels[i]
		var node := panel["node"] as TextureRect
		var start := projected_rect(_camera, panel["mesh"], panel["fit_fn"].call())
		var target := full[i]
		node.position = start.position.lerp(target.position, e)
		node.size = start.size.lerp(target.size, e)
		_feed(panel)


func _feed(panel: Dictionary) -> void:
	var node := panel["node"] as TextureRect
	var tex: Texture2D = panel["texture_fn"].call()
	var region: Rect2 = panel["region"]
	if tex == null:
		node.texture = null
		return
	if region == Rect2(0, 0, 1, 1):
		node.texture = tex
		return
	var atlas := panel["atlas"] as AtlasTexture
	atlas.atlas = tex
	var px := tex.get_size()
	atlas.region = Rect2(region.position * px, region.size * px)
	node.texture = atlas


func _aspects() -> Array[float]:
	var out: Array[float] = []
	for panel: Dictionary in _panels:
		out.append(panel["aspect_fn"].call())
	return out


func _teardown() -> void:
	for panel: Dictionary in _panels:
		var node := panel.get("node") as TextureRect
		if node != null:
			node.free()
	_panels.clear()
	_device = null
	_backdrop.color.a = 0.0
	visible = false
	set_process(false)
	_block(false)


func _block(active: bool) -> void:
	if _loco != null:
		_loco.set_block(BLOCK_OWNER, LocomotionManager.CHANNEL_DESKTOP_MOVE, active)
	if _turn != null:
		_turn.set("enabled", not active)
	if _reticle != null:
		_reticle.set("visible", not active)


## Where a quad's picture sits on the window: the bounding rect of its mesh's
## projected corners, shrunk about its centre by the letterbox fit.
static func projected_rect(camera: Camera3D, mesh: MeshInstance3D, fit: Vector2) -> Rect2:
	if mesh == null or mesh.mesh == null:
		return Rect2()
	var aabb := mesh.mesh.get_aabb()
	var xf := mesh.global_transform
	var rect := Rect2()
	for i in 8:
		var p := camera.unproject_position(xf * aabb.get_endpoint(i))
		rect = Rect2(p, Vector2.ZERO) if i == 0 else rect.expand(p)
	var shrunk := rect.size * fit
	return Rect2(rect.position + (rect.size - shrunk) * 0.5, shrunk)


## The panels stacked top to bottom at their own aspects, scaled as one so the
## stack fits the window, and centred. One panel is a plain aspect fit.
static func full_rects(aspects: Array[float], view: Rect2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if aspects.is_empty():
		return out
	var widest := 0.0
	for a: float in aspects:
		widest = maxf(widest, a)
	var unit := minf(view.size.x / widest, view.size.y / aspects.size())
	var top := view.position.y + (view.size.y - unit * aspects.size()) * 0.5
	for a: float in aspects:
		var w := a * unit
		out.append(Rect2(view.position.x + (view.size.x - w) * 0.5, top, w, unit))
		top += unit
	return out
