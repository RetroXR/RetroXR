## HsvWheel — a colour wheel to pick hue and saturation on: hue round the rim,
## saturation out from a white centre, the disc drawn at the brightness it is
## given. A press or a drag anywhere on it picks; outside the disc picks the rim
## colour in that direction. The pointer's drag arrives as mouse motion with the
## left button held (Viewport2Din3D sets button_mask), so it drags in the headset
## as with a mouse.
##
## Build with HsvWheel.create(diameter). set_hsv() moves it without emitting, so
## sliders beside it can drive it and it them without echoing.
class_name HsvWheel
extends Control

## A hue and saturation, each 0..1, from the player's own press or drag.
signal picked(hue: float, saturation: float)

const SHADER := preload("res://Shaders/ui_hsv_wheel.gdshader")
const MARKER_RADIUS := 16.0
## Below this brightness the disc is too dark to read a hue off, so it is shown
## no darker; the marker still wears the real colour.
const MIN_SHOWN_VALUE := 0.3

var hue := 0.0
var saturation := 0.0
var value := 1.0

var _disc: ColorRect
var _marker: Control


static func create(diameter: float) -> HsvWheel:
	var w := HsvWheel.new()
	w.custom_minimum_size = Vector2(diameter, diameter)
	w.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	w.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	w.mouse_filter = Control.MOUSE_FILTER_STOP
	w.focus_mode = Control.FOCUS_NONE
	w._disc = ColorRect.new()
	w._disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	w._disc.material = mat
	w.add_child(w._disc)
	w._marker = Control.new()
	w._marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	w._marker.draw.connect(w._draw_marker)
	w.add_child(w._marker)
	w._layout()
	return w


## Moves the wheel to a colour without emitting `picked`.
func set_hsv(h: float, s: float, v: float) -> void:
	hue = fposmod(h, 1.0)
	saturation = clampf(s, 0.0, 1.0)
	value = clampf(v, 0.0, 1.0)
	(_disc.material as ShaderMaterial).set_shader_parameter("value", maxf(value, MIN_SHOWN_VALUE))
	_marker.queue_redraw()


## Picks the hue and saturation under `pos`, in the wheel's own coordinates.
func pick_at(pos: Vector2) -> void:
	var d := (pos - _center()) / maxf(_radius(), 1.0)
	saturation = minf(d.length(), 1.0)
	hue = fposmod(atan2(-d.y, d.x) / TAU, 1.0)
	_marker.queue_redraw()
	picked.emit(hue, saturation)


## Where the marker sits for the current hue and saturation.
func marker_position() -> Vector2:
	var a := hue * TAU
	return _center() + Vector2(cos(a), -sin(a)) * saturation * _radius()


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		pick_at(mb.position)
		accept_event()
		return
	var mm := event as InputEventMouseMotion
	if mm != null and mm.button_mask & MOUSE_BUTTON_MASK_LEFT:
		pick_at(mm.position)
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _disc != null:
		_layout()


func _center() -> Vector2:
	return size * 0.5


## The disc's radius: the wheel's shorter side, less room for the marker at the rim.
func _radius() -> float:
	return minf(size.x, size.y) * 0.5 - MARKER_RADIUS


func _layout() -> void:
	var r := maxf(_radius(), 0.0)
	_disc.position = _center() - Vector2(r, r)
	_disc.size = Vector2(r, r) * 2.0
	_marker.position = Vector2.ZERO
	_marker.size = size


func _draw_marker() -> void:
	var at := marker_position()
	_marker.draw_circle(at, MARKER_RADIUS, Color.from_hsv(hue, saturation, value))
	_marker.draw_arc(at, MARKER_RADIUS, 0.0, TAU, 32, Color.WHITE, 4.0, true)
	_marker.draw_arc(at, MARKER_RADIUS + 2.5, 0.0, TAU, 32, Color(0, 0, 0, 0.6), 1.5, true)
