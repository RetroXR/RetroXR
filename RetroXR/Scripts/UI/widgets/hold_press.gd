## HoldPress — tells a click on a Button from a press held for a second.
##
## Added as a child of the Button. A view connects to `clicked` and `held`
## INSTEAD of the button's own `pressed`: a short press emits `clicked` on
## release, exactly when `pressed` would have; a press kept down for
## HOLD_SECONDS emits `held` while the pointer is still down, and the `pressed`
## that follows on release emits nothing.
##
## The button's action mode stays BUTTON_RELEASE (see vr_dropdown.gd on why a
## menu button is never BUTTON_PRESS), so the hold is timed between button_down
## and button_up. That pair is dependable in the VR panel: the pointer sends one
## mouse button down and one up, and motion in between.
##
## A hold is given up — the release still clicks, as it would have — when the
## pointer leaves the button or travels MAX_TRAVEL from where it went down, so
## dragging a list by one of its rows never opens anything.
class_name HoldPress
extends Node

signal clicked
signal held

const HOLD_SECONDS := 1.0
## The fill bar stays hidden this long, so a plain click never flashes it.
const SHOW_AFTER := 0.25
const MAX_TRAVEL := 24.0
const BAR_HEIGHT := 6.0
const BAR_COLOR := Color(0.55, 0.75, 1.0, 0.9)

## False makes this a plain click: a pooled row switches it per bind.
var hold_enabled := true

var _btn: Button = null
var _down := false
var _elapsed := 0.0
# Set when `held` fired, cleared by the NEXT button_down rather than by the
# release: BaseButton emits `pressed` and `button_up` in an order this does not
# want to depend on.
var _consumed := false
var _down_at := Vector2.ZERO
var _bar: ColorRect = null


static func attach(btn: Button) -> HoldPress:
	var hp := HoldPress.new()
	hp.name = "HoldPress"
	btn.add_child(hp)
	return hp


func _ready() -> void:
	_btn = get_parent() as Button
	if _btn == null:
		push_warning("HoldPress: parent is not a Button")
		set_process(false)
		return
	_btn.button_down.connect(_on_down)
	_btn.button_up.connect(_on_up)
	_btn.mouse_exited.connect(cancel)
	ensure_connected()
	set_process(false)


## Listen to the button's `pressed` again. A pooled row clears every listener off
## that signal each time it is rebound, this one included.
func ensure_connected() -> void:
	if _btn != null and not _btn.pressed.is_connected(_on_pressed):
		_btn.pressed.connect(_on_pressed)


## Seconds the current press has been held, 0 when none is being timed.
func elapsed() -> float:
	return _elapsed if _down else 0.0


## Give up timing this press. The release still clicks.
func cancel() -> void:
	_down = false
	_elapsed = 0.0
	set_process(false)
	_show_progress(0.0)


## Forget everything, a consumed hold included — for a pooled row being rebound
## to another entry while a press is in flight.
func reset() -> void:
	cancel()
	_consumed = false


## Time passing. Public so a headless test can hold a button without waiting.
func advance(delta: float) -> void:
	if not _down:
		return
	if _btn.get_global_mouse_position().distance_to(_down_at) > MAX_TRAVEL:
		cancel()
		return
	_elapsed += delta
	if _elapsed >= HOLD_SECONDS:
		cancel()
		_consumed = true
		held.emit()
		return
	_show_progress(0.0 if _elapsed < SHOW_AFTER else _elapsed / HOLD_SECONDS)


func _process(delta: float) -> void:
	advance(delta)


func _on_down() -> void:
	_consumed = false
	if not hold_enabled:
		return
	_down = true
	_elapsed = 0.0
	_down_at = _btn.get_global_mouse_position()
	set_process(true)


func _on_up() -> void:
	cancel()


func _on_pressed() -> void:
	if _consumed:
		return
	clicked.emit()


func _show_progress(fraction: float) -> void:
	if _bar == null:
		if fraction <= 0.0:
			return
		_bar = ColorRect.new()
		_bar.color = BAR_COLOR
		_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_btn.add_child(_bar)
	_bar.visible = fraction > 0.0
	_bar.position = Vector2(0.0, _btn.size.y - BAR_HEIGHT)
	_bar.size = Vector2(_btn.size.x * clampf(fraction, 0.0, 1.0), BAR_HEIGHT)
