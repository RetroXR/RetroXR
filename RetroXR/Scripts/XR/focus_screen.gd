## FocusScreen — the floating screen VR focus mode shows a device's picture on.
##
## Reads the picture and never paints it: every panel's texture_fn is called again
## each frame, in the shape TvFullscreen.panels_for returns. Grip while a laser is on
## it to carry it along that hand's ray; while carried, the stick's Y sets the
## distance and its X the size. Trigger-drag the corner handle to size it. The aspect
## is always the picture's own.
class_name FocusScreen
extends Node3D

const SHADER := preload("res://Shaders/focus_screen.gdshader")

## Physics layer 24, FocusScreen: all the lasers can hit while focus mode is on.
const LAYER := 1 << 23

const DISTANCE := 2.0
const START_WIDTH := 1.6
const MIN_WIDTH := 0.3
const MAX_WIDTH := 6.0
const DEPTH_MIN := 0.3
const DEPTH_MAX := 8.0
const DEPTH_SPEED := 1.5
const SIZE_SPEED := 1.0
const GRIP_THRESHOLD := 0.3
const STICK_DEADZONE := 0.15
const HANDLE_HIT := 0.08
const HANDLE_ARM := 0.06
const HANDLE_BAR := 0.008
const HANDLE_OFF := Color(0.55, 0.55, 0.6)
const HANDLE_ON := Color(0.35, 0.7, 1.0)

var _camera: Node3D = null
var _hands: Array[Node3D] = []
var _panels: Array[Dictionary] = []
var _quads: Array[MeshInstance3D] = []
var _width := START_WIDTH
var _height := 0.0
var _laid_aspects: Array[float] = []
var _laid_width := -1.0

var _body: StaticBody3D = null
var _shape: BoxShape3D = null
var _handle: PanelResizeGrip = null
var _handle_mat: StandardMaterial3D = null

var _grab_hand: Node3D = null
var _grab_distance := 0.0
## Hand -> whether its grip was down last frame; a grab takes a fresh squeeze.
var _grip_down: Dictionary = {}
var _drag_pointer: Node3D = null
var _drag_from := Vector3.ZERO
var _drag_size := Vector2.ZERO


## `hands` carry and point at the screen: each answers get_float/get_vector2 and
## has a FunctionPointer child.
func setup(panels: Array[Dictionary], camera: Node3D, hands: Array[Node3D]) -> void:
	_panels = panels
	_camera = camera
	_hands = hands
	for panel: Dictionary in _panels:
		var quad := MeshInstance3D.new()
		quad.mesh = QuadMesh.new()
		quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		var region: Rect2 = panel.get("region", Rect2(0, 0, 1, 1))
		mat.set_shader_parameter("source_rect",
			Vector4(region.position.x, region.position.y, region.size.x, region.size.y))
		mat.set_shader_parameter("flip_h", bool(panel.get("flip_h", false)))
		mat.set_shader_parameter("flip_v", bool(panel.get("flip_v", false)))
		quad.material_override = mat
		add_child(quad)
		_quads.append(quad)
	_body = StaticBody3D.new()
	_body.name = "Body"
	_body.collision_layer = LAYER
	_body.collision_mask = 0
	var shape := CollisionShape3D.new()
	_shape = BoxShape3D.new()
	shape.shape = _shape
	_body.add_child(shape)
	add_child(_body)
	_build_handle()
	_layout()
	_feed()


func width() -> float:
	return _width


func height() -> float:
	return _height


func set_width(w: float) -> void:
	_width = clampf(w, MIN_WIDTH, MAX_WIDTH)
	_layout()


## Whether `node` is this screen or its handle.
func owns(node: Object) -> bool:
	if not is_instance_valid(node) or not (node is Node):
		return false
	var n := node as Node
	return n == _body or n == _handle or _body.is_ancestor_of(n) or _handle.is_ancestor_of(n)


## DISTANCE ahead of `camera` along its level forward, at eye height, facing it.
func place_in_front(camera: Node3D) -> void:
	var forward := -camera.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		forward = Vector3.FORWARD
	global_position = camera.global_position + forward.normalized() * DISTANCE
	_face(camera)
	reset_physics_interpolation()


## The screen's left and right edges, where its two channels sound from.
func speaker_positions() -> PackedVector3Array:
	return PackedVector3Array([to_global(Vector3(-_width * 0.5, 0.0, 0.0)),
		to_global(Vector3(_width * 0.5, 0.0, 0.0))])


func resize_begin(pointer: Node3D) -> void:
	if not is_instance_valid(pointer):
		return
	_drag_pointer = pointer
	_drag_from = _pointer_on_plane(pointer)
	_drag_size = Vector2(_width, _height)
	_handle_mat.albedo_color = HANDLE_ON


func resize_end() -> void:
	_drag_pointer = null
	_handle_mat.albedo_color = HANDLE_OFF


func _process(delta: float) -> void:
	_feed()
	_layout()
	if is_instance_valid(_drag_pointer):
		_drag_to(_pointer_on_plane(_drag_pointer))
	_process_grab(delta)


func _feed() -> void:
	for i in _quads.size():
		var fn: Callable = _panels[i]["texture_fn"]
		var tex: Texture2D = fn.call() if fn.is_valid() else null
		(_quads[i].material_override as ShaderMaterial).set_shader_parameter("source_tex", tex)


## Stack the panels at their own aspects inside the current width. Returns early
## unless an aspect or the width moved: resizing a QuadMesh rebuilds it.
func _layout() -> void:
	var aspects: Array[float] = []
	var widest := 0.0
	for panel: Dictionary in _panels:
		var a: float = panel["aspect_fn"].call()
		aspects.append(a)
		widest = maxf(widest, a)
	if widest <= 0.0 or (aspects == _laid_aspects and _width == _laid_width):
		return
	_laid_aspects = aspects
	_laid_width = _width
	_height = _width / widest * aspects.size()
	var rects := TvFullscreen.full_rects(aspects, Rect2(0.0, 0.0, _width, _height))
	for i in _quads.size():
		var r := rects[i]
		(_quads[i].mesh as QuadMesh).size = r.size
		_quads[i].position = Vector3(r.get_center().x - _width * 0.5,
			_height * 0.5 - r.get_center().y, 0.0)
	_shape.size = Vector3(_width, _height, 0.02)
	_handle.position = Vector3(_width * 0.5 + HANDLE_BAR, -_height * 0.5 - HANDLE_BAR, 0.0)


func _build_handle() -> void:
	_handle = PanelResizeGrip.create(self, Vector3(HANDLE_HIT, HANDLE_HIT, 0.02))
	_handle.collision_layer = LAYER
	_handle_mat = StandardMaterial3D.new()
	_handle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_handle_mat.albedo_color = HANDLE_OFF
	# One bar left along the bottom edge, one up the right, meeting at the corner.
	var bars: Array[Array] = [
		[Vector3(HANDLE_ARM, HANDLE_BAR, HANDLE_BAR), Vector3(-HANDLE_ARM * 0.5, 0.0, 0.0)],
		[Vector3(HANDLE_BAR, HANDLE_ARM, HANDLE_BAR), Vector3(0.0, HANDLE_ARM * 0.5, 0.0)],
	]
	for spec: Array in bars:
		var bar := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = spec[0]
		bar.mesh = box
		bar.position = spec[1]
		bar.material_override = _handle_mat
		_handle.add_child(bar)
	add_child(_handle)


## Scale about the centre by how far the pointer moved along the corner's diagonal,
## so the corner follows the laser and the aspect holds.
func _drag_to(at: Vector3) -> void:
	var corner := Vector2(_drag_size.x, -_drag_size.y) * 0.5
	var reach := corner.length()
	if reach <= 0.0:
		return
	var along := Vector2(at.x - _drag_from.x, at.y - _drag_from.y).dot(corner / reach)
	set_width(_drag_size.x * (reach + along) / reach)


func _process_grab(delta: float) -> void:
	if _grab_hand != null:
		if not is_instance_valid(_grab_hand) or _grab_hand.get_float("grip") < GRIP_THRESHOLD:
			_grab_hand = null
		else:
			_carry(delta)
	for hand: Node3D in _hands:
		if not is_instance_valid(hand):
			continue
		var down: bool = hand.get_float("grip") >= GRIP_THRESHOLD
		var fresh := down and not bool(_grip_down.get(hand, false))
		_grip_down[hand] = down
		if fresh and _grab_hand == null and _drag_pointer == null and owns(_pointed_by(hand)):
			_grab_hand = hand
			_grab_distance = hand.global_position.distance_to(global_position)


func _carry(delta: float) -> void:
	global_position = _grab_hand.global_position \
		- _grab_hand.global_transform.basis.z * _grab_distance
	_face(_camera)
	var stick: Vector2 = _grab_hand.get_vector2("primary")
	if absf(stick.y) >= STICK_DEADZONE:
		_grab_distance = clampf(_grab_distance + stick.y * DEPTH_SPEED * delta,
			DEPTH_MIN, DEPTH_MAX)
	if absf(stick.x) >= STICK_DEADZONE:
		set_width(_width + stick.x * SIZE_SPEED * delta)


## What `hand`'s laser is on; null while something held in that hand has its
## pointer off.
func _pointed_by(hand: Node3D) -> Object:
	var pointer := hand.get_node_or_null("FunctionPointer") as Node3D
	if pointer == null or not pointer.visible:
		return null
	return pointer.get("last_target")


## Turn the picture side (+Z) toward `camera`.
func _face(camera: Node3D) -> void:
	if camera == null:
		return
	var to := camera.global_position - global_position
	if to.length_squared() < 0.0001 or absf(to.normalized().dot(Vector3.UP)) > 0.999:
		return
	look_at(camera.global_position, Vector3.UP)
	rotate_object_local(Vector3.UP, PI)


## Where `pointer` aims on the screen's z = 0 plane, in screen-local space.
func _pointer_on_plane(pointer: Node3D) -> Vector3:
	var inv := global_transform.affine_inverse()
	var origin := inv * pointer.global_position
	var dir := (inv.basis * -pointer.global_transform.basis.z).normalized()
	if absf(dir.z) < 0.0001:
		return Vector3(origin.x, origin.y, 0.0)
	return origin + dir * (-origin.z / dir.z)
