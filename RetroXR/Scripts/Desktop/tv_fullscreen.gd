## TvFullscreen — desktop only: the picture on the screen you are looking at
## lerps out to fill the application window, and back on the same key. It moves
## as the glass itself, turning to face the camera as it grows, so a screen seen
## at an angle starts at that angle.
##
## Works for a television and for a handheld. The overlay never knows either
## class; it works over PANELS — one per picture quad — each carrying the mesh
## to project, where its picture comes from, which part of that texture it
## shows, and the aspect it is drawn at. A TV is one panel, a Game Boy is one,
## a DS is two stacked the way the device stacks them.
##
## It reads the picture, it never paints it: the texture the glass samples is
## re-read every frame, so snow, the blue screen, a source change and power-off
## all follow the device. The SOUND does move, because a picture in the window
## whose audio still arrives from a cabinet off to one side, quieter the further
## away it stands, is the thing that gives the illusion away -- the source feeding
## the shown picture is held at a fixed pair of points in front of the listener
## for as long as the overlay is up. Movement is blocked through LocomotionManager while
## the picture is up; mouse-look is outside that channel on purpose, so the turn
## provider is switched off here as well.
class_name TvFullscreen
extends CanvasLayer

const ACTION := &"desktop_tv_fullscreen"
const BLOCK_OWNER := &"tv_fullscreen"
const DURATION := 0.35
## The share of the lerp the turn to face the camera takes. Done before the
## picture is large, or its near edge swings out at the viewer.
const TURN_SHARE := 0.6
## Cells per side of a drawn picture. The canvas maps each triangle affinely, so
## a turned picture is cut fine enough that the perspective shows no seam.
const GRID := 8

var _camera: Camera3D = null
var _pickup: Node = null
var _turn: Node = null
var _reticle: Node = null
var _loco: LocomotionManager = null

var _backdrop: ColorRect = null
var _picture: Control = null
var _indices := PackedInt32Array()
var _device: WeakRef = null
var _panels: Array[Dictionary] = []
var _t := 0.0
var _opening := false
var _audio_locked: WeakRef = null


func _ready() -> void:
	layer = 120
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0, 0, 0, 0)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_backdrop)
	_picture = Control.new()
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture.set_anchors_preset(Control.PRESET_FULL_RECT)
	_picture.draw.connect(_draw_panels)
	add_child(_picture)
	_indices = _grid_indices(GRID)
	visible = false
	set_process(false)
	# By path, not rig.camera: a child is ready before its parent, so the rig's
	# @onready vars are still null here.
	var rig := get_parent() as PlayerRig
	if rig != null:
		var camera := rig.get_node_or_null("Staging/XROrigin3D/XRCamera3D") as Camera3D
		configure(camera, camera,
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
	var device := device_from_target(_pickup.aimed_target())
	# A held handheld is never under the crosshair, yet holding it is how its keys
	# are captured (Scroll Lock / F3) -- so with no screen aimed at, take the
	# picture of whatever is in the hand.
	if device == null and _pickup.has_method("held_object"):
		device = device_from_node(_pickup.held_object())
	open(device)


## The television or handheld behind a crosshair hit, or null. Walks up from the
## hit node: a DS bottom screen resolves as a pointer target, so the action node
## alone would miss it. A node with fullscreen_panels() counts too.
static func device_from_target(target: InteractionTarget) -> Node3D:
	if target == null:
		return null
	for start: Node3D in [target.hit_node, target.action_node]:
		var device := device_from_node(start)
		if device != null:
			return device
	return null


## The television or handheld `node` is part of, or null.
static func device_from_node(node: Node) -> Node3D:
	while is_instance_valid(node):
		if node is RetroTV or node is RetroSystem \
				or (node is Node3D and node.has_method("fullscreen_panels")):
			return node
		node = node.get_parent()
	return null


## One panel per picture quad on the device, or none when it has nothing to show.
static func panels_for(device: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	# A device that describes its own screens, in this same panel shape.
	if device.has_method("fullscreen_panels"):
		out.assign(device.call("fullscreen_panels"))
		return out
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
		panel["uvs"] = _grid_uvs(panel)
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
	var turn := smoothstep(0.0, 1.0, minf(_t / TURN_SHARE, 1.0))
	_backdrop.color.a = e
	var full := full_rects(_aspects(), get_viewport().get_visible_rect())
	for i in _panels.size():
		var panel := _panels[i]
		var glass := picture_frame(panel["mesh"], panel["fit_fn"].call(),
			bool(panel.get("flip_h", false)), bool(panel.get("flip_v", false)))
		panel["points"] = _project(_between(glass, full[i], e, turn))
		panel["tex"] = panel["texture_fn"].call()
	_picture.queue_redraw()
	_hold_audio()


## The picture `e` of the way from `glass` to `target` and `turn` of the way to
## facing the camera, in the frame shape picture_frame returns. It slides and
## grows at the glass's own depth, so at 1 and 1 it projects onto `target` exactly.
func _between(glass: Transform3D, target: Rect2, e: float, turn: float) -> Transform3D:
	var eye := _camera.global_transform
	var from := eye.affine_inverse() * glass
	var depth := maxf(-from.origin.z, _camera.near * 2.0)
	var a := eye.affine_inverse() * _camera.project_position(target.position, depth)
	var b := eye.affine_inverse() * _camera.project_position(target.end, depth)
	var half := Vector2(from.basis.x.length(), from.basis.y.length()).lerp(
		Vector2(b.x - a.x, a.y - b.y) * 0.5, e)
	var facing := Quaternion.IDENTITY
	var x := from.basis.x.normalized()
	var y := from.basis.y.normalized()
	if not x.cross(y).is_zero_approx():
		facing = Basis(x, y, x.cross(y)).orthonormalized().get_rotation_quaternion()
	var basis := Basis(facing.slerp(Quaternion.IDENTITY, turn))
	return eye * Transform3D(basis.x * half.x, basis.y * half.y, basis.z,
		from.origin.lerp((a + b) * 0.5, e))


## `frame`'s grid on the window, row by row from the picture's top left. A point
## behind the camera is held on the near plane.
func _project(frame: Transform3D) -> PackedVector2Array:
	var eye := _camera.global_transform
	var local := eye.affine_inverse() * frame
	var out := PackedVector2Array()
	out.resize((GRID + 1) * (GRID + 1))
	for row in GRID + 1:
		for col in GRID + 1:
			var p := local * Vector3(2.0 * col / GRID - 1.0, 1.0 - 2.0 * row / GRID, 0.0)
			p.z = minf(p.z, -_camera.near)
			out[row * (GRID + 1) + col] = _camera.unproject_position(eye * p)
	return out


func _draw_panels() -> void:
	for panel: Dictionary in _panels:
		var tex: Texture2D = panel.get("tex")
		var points: PackedVector2Array = panel.get("points", PackedVector2Array())
		if tex == null or points.is_empty():
			continue
		RenderingServer.canvas_item_add_triangle_array(_picture.get_canvas_item(), _indices,
			points, PackedColorArray([Color.WHITE]), panel["uvs"], PackedInt32Array(),
			PackedFloat32Array(), tex.get_rid())


## Texture coordinates for the grid _project lays out: the panel's region, with a
## flipped panel read from the far edge, as a flipped TextureRect would show it.
static func _grid_uvs(panel: Dictionary) -> PackedVector2Array:
	var region: Rect2 = panel.get("region", Rect2(0, 0, 1, 1))
	var flip_h := bool(panel.get("flip_h", false))
	var flip_v := bool(panel.get("flip_v", false))
	var out := PackedVector2Array()
	for row in GRID + 1:
		for col in GRID + 1:
			var uv := Vector2(float(col) / GRID, float(row) / GRID)
			if flip_h:
				uv.x = 1.0 - uv.x
			if flip_v:
				uv.y = 1.0 - uv.y
			out.append(region.position + uv * region.size)
	return out


static func _grid_indices(cells: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for row in cells:
		for col in cells:
			var a := row * (cells + 1) + col
			var c := a + cells + 1
			out.append_array([a, a + 1, c + 1, a, c + 1, c])
	return out


## Whatever is making the sound behind the picture on screen: the machine itself
## for a handheld, and for a television whichever source its selected input is
## carrying. Re-asked every frame, because the input can be changed while the
## overlay is up and the sound has to follow the picture that is showing.
func audio_source() -> Node:
	return audio_source_for(_device.get_ref() if _device != null else null)


## What makes the sound behind `device`'s picture, or null. See audio_source.
static func audio_source_for(device: Object) -> Node:
	if device is RetroSystem:
		return device as Node
	if device is RetroTV:
		return (device as RetroTV).panel().selected_system()
	return null


## Keep the shown source's two channels in front of the listener, and hand the
## room back to anything that stops being the source.
func _hold_audio() -> void:
	var want := audio_source()
	var held: Node = _audio_locked.get_ref() if _audio_locked != null else null
	if held != want:
		_release_audio()
		_audio_locked = weakref(want) if want != null else null
	if want == null or not want.has_method("set_audio_head_lock"):
		return
	var at := SpatialAudioEmitter.head_lock_positions(_camera.global_transform)
	want.set_audio_head_lock(at[0], at[1])


func _release_audio() -> void:
	var held: Node = _audio_locked.get_ref() if _audio_locked != null else null
	if is_instance_valid(held) and held.has_method("clear_audio_head_lock"):
		held.clear_audio_head_lock()
	_audio_locked = null


func _aspects() -> Array[float]:
	var out: Array[float] = []
	for panel: Dictionary in _panels:
		out.append(panel["aspect_fn"].call())
	return out


func _teardown() -> void:
	_release_audio()
	_panels.clear()
	_picture.queue_redraw()
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


## The picture on `mesh` in world space: origin at its center, x and y its half
## width and half height toward the picture's right and top, z its normal. The
## picture is the mesh's +Z face shrunk about its center by the letterbox fit; a
## flipped panel's axis is reversed, so the frame points the way its picture reads.
static func picture_frame(mesh: MeshInstance3D, fit: Vector2, flip_h := false,
		flip_v := false) -> Transform3D:
	if mesh == null or mesh.mesh == null:
		return Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO)
	var aabb := mesh.mesh.get_aabb()
	var xf := mesh.global_transform
	var right := xf.basis.x * (aabb.size.x * 0.5 * fit.x * (-1.0 if flip_h else 1.0))
	var up := xf.basis.y * (aabb.size.y * 0.5 * fit.y * (-1.0 if flip_v else 1.0))
	return Transform3D(right, up, right.cross(up).normalized(), xf * aabb.get_center())


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
