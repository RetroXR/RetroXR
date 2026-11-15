## The arrow a Seat shows while it is in a hand: which way the player will face when they sit on it. One flat quad
## lying over the cushion, drawn by `seat_facing_arrow.gdshader` (an amber hologram: outline, glow, scanlines running
## toward the tip, a slow pulse), seen through the seat's own cushion and back. It fades in when made and fades out
## and frees itself when let go of (`dismiss`), so the seat can drop its reference at once.
class_name SeatFacingArrow
extends MeshInstance3D

const SHADER := preload("res://Shaders/seat_facing_arrow.gdshader")
const WIDTH := 0.24
const LENGTH := 0.62
const FADE_IN := 0.18
const FADE_OUT := 0.25

var _mat: ShaderMaterial
var _tween: Tween


## An arrow standing at `base`, lying level and pointing along `basis`'s -Z (the way the eyes look).
static func make(basis: Basis, base: Vector3) -> SeatFacingArrow:
	var arrow := SeatFacingArrow.new()
	arrow.name = "FacingArrow"
	# Level whatever the eye's pitch: only its heading counts.
	var fwd := -basis.z
	fwd.y = 0.0
	if fwd.length() < 0.001:
		fwd = Vector3.FORWARD
	arrow.transform = Transform3D(Basis.looking_at(fwd.normalized(), Vector3.UP), base)
	var plane := PlaneMesh.new()
	plane.size = Vector2(WIDTH, LENGTH)
	# The tail at the base, the quad reaching forward along -Z.
	plane.center_offset = Vector3(0.0, 0.0, -LENGTH * 0.5)
	arrow._mat = ShaderMaterial.new()
	arrow._mat.shader = SHADER
	arrow._mat.set_shader_parameter("quad_size", Vector2(WIDTH, LENGTH))
	arrow._mat.set_shader_parameter("fade", 0.0)
	arrow._mat.render_priority = 10
	plane.material = arrow._mat
	arrow.mesh = plane
	arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return arrow


func _ready() -> void:
	_fade_to(1.0, FADE_IN)


## Fade out, then free. Safe to call twice.
func dismiss() -> void:
	if is_queued_for_deletion():
		return
	if not is_inside_tree():
		queue_free()
		return
	_fade_to(0.0, FADE_OUT).finished.connect(queue_free)


func fade() -> float:
	return float(_mat.get_shader_parameter("fade"))


func _fade_to(to: float, seconds: float) -> Tween:
	if _tween != null:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_method(func(v: float) -> void: _mat.set_shader_parameter("fade", v), fade(), to, seconds)
	return _tween
