## TVTouchSurface — makes a TV screen behave like a DS/3DS touch screen.
##
## Created by RetroSystem when a dual-screen handheld's BOTTOM video-out cable
## connects to a TV, and freed on disconnect. Sits as an Area3D child of the
## TV's ScreenMesh (a +Z-facing QuadMesh), so it follows the TV wherever it
## goes and inherits its display scale.
##
## Taps arrive two ways — the desktop reticle / VR laser (pointer_event) and a
## direct VR fingertip press against the glass — and both map the hit through
## `uv_rect` (the channel's window of the composite framebuffer, i.e. what the
## TV is showing) into host.feed_touch() → RETRO_DEVICE_POINTER, exactly like
## poking the handheld's own bottom screen.
class_name TVTouchSurface
extends Area3D

## Half-thickness of the collision box, i.e. how far the glass plane sits from
## either face. The engage window is derived from it (see _tip_on_screen) so the
## two cannot drift apart — this one used to engage at 30 mm against a box only
## 4 mm thick, which is why a tap on a TV registered a good 3 cm off the picture.
const HALF_THICKNESS := 0.004
## Slack past the box before a touch counts, and the multiple of that at which it
## lets go. Same shape as VRSlider's engage/release pair.
const GLASS_TOLERANCE := 0.004
const RELEASE_SCALE := 1.6

## The RetroSystem receiving the touches.
var host: Node3D = null
## The channel's UV window of the composite framebuffer (what this TV shows).
var uv_rect := Rect2(0, 0, 1, 1)

var _size := Vector2(0.35, 0.25)
var _pointer_down := false
var _touch_ctrl: XRController3D = null
var _controllers: Array[XRController3D] = []
var _smoother := TouchSmoother.new()


## Build collision to match the screen quad it is attached to.
func setup(system: Node3D, rect: Rect2, screen_mesh: MeshInstance3D) -> void:
	host = system
	uv_rect = rect
	if screen_mesh and screen_mesh.mesh is QuadMesh:
		_size = (screen_mesh.mesh as QuadMesh).size
	name = "TVTouchSurface"
	collision_layer |= VRSlider.POINTABLE_LAYER
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(_size.x, _size.y, HALF_THICKNESS * 2.0)
	col.shape = shape
	add_child(col)


func _ready() -> void:
	await get_tree().process_frame
	# Removed during that frame (a preview thrown away, a room change): get_tree() is null now.
	if not is_inside_tree():
		return
	for node in get_tree().root.find_children("*", "XRController3D", true, false):
		_controllers.append(node as XRController3D)


## Desktop reticle / VR laser taps on the glass.
func pointer_event(event: XRToolsPointerEvent) -> void:
	match event.event_type:
		XRToolsPointerEvent.Type.PRESSED:
			_pointer_down = true
			_send_touch(event.position, true)
		XRToolsPointerEvent.Type.MOVED:
			if _pointer_down:
				_send_touch(event.position, true)
		XRToolsPointerEvent.Type.RELEASED, XRToolsPointerEvent.Type.EXITED:
			if _pointer_down:
				_pointer_down = false
				_send_touch(event.position, false)


## VR fingertip pressed against the glass.
##
## Between the engage and release windows the reported point FREEZES (see
## TouchSmoother), so lifting off — or sliding out past an edge — reports where
## you last actually were instead of the clamped border.
func _process(delta: float) -> void:
	if _pointer_down:
		return
	if _touch_ctrl != null:
		if not _qualified(_touch_ctrl) or not _tip_on_screen(PokeTip.tip_of(_touch_ctrl), RELEASE_SCALE):
			var last := _touch_ctrl
			_touch_ctrl = null
			if is_instance_valid(last):
				_send_touch_local(_smoother.current(), false)
			_smoother.reset()
		else:
			var tip: Vector3 = PokeTip.tip_of(_touch_ctrl)
			var local: Vector3 = to_local(tip)
			var p: Vector2 = _smoother.point(Vector2(local.x, local.y),
				_tip_on_screen(tip, 1.0), delta)
			_send_touch_local(p, true)
			_claim_contact(_touch_ctrl, p, local.z)
			return
	for ctrl in _controllers:
		# A hand holding something is not a stylus — without this a hand carrying
		# a cartridge past the TV drove the DS's touch screen.
		if _qualified(ctrl) and _tip_on_screen(PokeTip.tip_of(ctrl), 1.0):
			_touch_ctrl = ctrl
			var local: Vector3 = to_local(PokeTip.tip_of(ctrl))
			var p := Vector2(local.x, local.y)
			_smoother.begin(p)
			_send_touch_local(p, true)
			_claim_contact(ctrl, p, local.z)
			return


func _qualified(ctrl: XRController3D) -> bool:
	return is_instance_valid(ctrl) and ctrl.get_is_active() and PokeTip.is_poking(ctrl)


func _tip_on_screen(world_pos: Vector3, slack: float) -> bool:
	var local := to_local(world_pos)
	return absf(local.z) <= (HALF_THICKNESS + GLASS_TOLERANCE) * slack \
		and absf(local.x) <= _size.x / 2.0 + 0.005 * slack \
		and absf(local.y) <= _size.y / 2.0 + 0.005 * slack


## Put the visible fingertip ON THE GLASS, at the point the core is being told
## about — local z = 0 is the screen mesh, since this Area3D sits on it at
## identity. Clamped with the same half-extents the UV mapping clamps to, so what
## you see and what the game gets cannot disagree.
func _claim_contact(ctrl: XRController3D, p: Vector2, local_z: float) -> void:
	var half: Vector2 = _size * 0.5
	var q := Vector3(clampf(p.x, -half.x, half.x), clampf(p.y, -half.y, half.y), 0.0)
	var n: Vector3 = global_transform.basis.z.normalized()
	if local_z < 0.0:
		n = -n
	PokeTip.set_contact(ctrl, global_transform * q, n, PokeTip.CONTACT_ENGAGED)


## World point on the glass → screen fraction → composite-framebuffer UV.
func _send_touch(world_pos: Vector3, pressed: bool) -> void:
	var local := to_local(world_pos)
	_send_touch_local(Vector2(local.x, local.y), pressed)


## In-plane surface-local point (metres) → UV. The quad faces +Z: local x right,
## y up; UV y runs top-down.
func _send_touch_local(p: Vector2, pressed: bool) -> void:
	if host == null or not host.has_method("feed_touch"):
		return
	var fx := clampf(p.x / _size.x + 0.5, 0.0, 1.0)
	var fy := clampf(0.5 - p.y / _size.y, 0.0, 1.0)
	host.feed_touch(uv_rect.position + Vector2(fx, fy) * uv_rect.size, pressed)
