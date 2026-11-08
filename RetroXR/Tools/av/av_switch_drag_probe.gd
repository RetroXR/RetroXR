## The AV switch worked from the desktop, filmed: the cursor goes to the slide's tab, presses it, and DRAGS it with
## the mouse from 1 to 4 and back to 2, the set following as it passes each detent; the button coming up snaps it.
## Built on av_switch_probe's room (an NES live on INPUT 1, a Genesis on INPUT 3, here counted as switched on so its
## label lights too). The press is the desktop pointer's own event on what InteractionResolver.resolve_desktop takes
## there, and the drag is real InputEventMouseMotion, measured by VRSlider against the slot as the camera sees it
## (a camera in the root viewport mirrors the filming one, since the slider projects through its own viewport).
## WINDOWED, every frame rendered:
##
##     "$godot" --path RetroXR --resolution 320x240 --position 20,20 --fixed-fps 30 \
##         res://Tools/av/av_switch_drag_probe.tscn -- --no-mods --out=<dir>
## then encode frames/ with imageio (libx264, -crf 24, 30 fps). Prints [avswitch-drag] lines; PASS needs the press
## to take the tab, the view to stay put and each leg of the drag to land on the input it aimed at.
extends "res://Tools/av/av_switch_probe.gd"

var _pointer: Node3D
var _cursor: _Cursor
var _rootcam: Camera3D


func _shoot() -> void:
	_md.is_powered_on = true
	_sw.select(0)
	_pointer = Node3D.new()
	_pointer.name = "DesktopPointer"
	add_child(_pointer)
	_rootcam = Camera3D.new()
	_rootcam.near = _cam.near
	_rootcam.fov = _cam.fov
	add_child(_rootcam)
	_rootcam.current = true
	_cursor = _Cursor.new()
	_cursor.size = Vector2(SIZE)
	_sv.add_child(_cursor)
	var slider := _sw.get_node("Selector") as VRSlider
	_aim(_sw.global_position + Vector3(0.03, 0.16, 0.30), _sw.global_position + Vector3(0, 0.0, 0.03))
	_rootcam.global_transform = _cam.global_transform
	_cursor.at = Vector2(SIZE) * Vector2(0.62, 0.70)
	_recording = true
	await _wait(25)
	# The cursor goes to the tab.
	var from := _cursor.at
	for k in 24:
		var u := float(k + 1) / 24.0
		_cursor.at = from.lerp(_cam.unproject_position(_tab()), u * u * (3.0 - 2.0 * u))
		await _wait(1)
	var t := _press(_tab())
	_check(t == slider, "the press takes the slide (%s)" % (t.name if t != null else "nothing"))
	if t == null:
		return
	_cursor.down = true
	await _wait(8)
	var px := slider.mouse_px_per_travel()
	var dir: Vector2 = slider._slot_on_screen().get("dir", Vector2.RIGHT)
	print("[avswitch-drag] %.0f px end to end, %.0f px a position, slot dir %s" % [px, px / 3.0, dir])
	var basis := _cam.global_basis
	await _drag(dir * px * 1.0, 60)
	_check(_sw.selected == 3, "drag to the right end -> input %d" % (_sw.selected + 1))
	await _wait(25)
	await _drag(-dir * px * 0.62, 45)
	_mouse_up()
	XRToolsPointerEvent.released(_pointer, t, _tab())
	XRToolsPointerEvent.exited(_pointer, t, _tab())
	_cursor.down = false
	_cursor.at = _cam.unproject_position(_tab())
	await _wait(2)
	_check(_sw.selected == 1 and is_equal_approx(slider.value, 1.0 / 3.0),
		"back and let go -> input %d, value %.3f (snapped)" % [_sw.selected + 1, slider.value])
	_check(_cam.global_basis.is_equal_approx(basis), "the view did not turn")
	await _wait(45)
	_recording = false
	print("[avswitch-drag] frames %d" % _frames)


## Move the mouse by `total` over `frames` frames, eased; the cursor rides on the tab as the hand would.
func _drag(total: Vector2, frames: int) -> void:
	var done := Vector2.ZERO
	for k in frames:
		var u := float(k + 1) / float(frames)
		var want := total * (u * u * (3.0 - 2.0 * u))
		var ev := InputEventMouseMotion.new()
		ev.relative = want - done
		ev.position = Vector2(-500, -500)
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT
		get_viewport().push_input(ev)
		done = want
		_cursor.at = _cam.unproject_position(_tab())
		await _wait(1)


func _mouse_up() -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.position = Vector2(-500, -500)
	get_viewport().push_input(ev)


func _tab() -> Vector3:
	var tab := _sw.get_node("Model").call("part", "SlideTab") as MeshInstance3D
	return (tab.global_transform * tab.get_aabb()).get_center()


func _press(at: Vector3) -> Node3D:
	var space := _sw.get_world_3d().direct_space_state
	var from := _cam.global_position
	var r := InteractionResolver.resolve_desktop(space, from, from + (at - from) * 1.2, _pointer)
	if r == null or not is_instance_valid(r.pointer_event_target):
		print("[avswitch-drag] nothing to press at %s" % at)
		_failed = true
		return null
	var t := r.pointer_event_target
	XRToolsPointerEvent.entered(_pointer, t, r.position)
	XRToolsPointerEvent.pressed(_pointer, t, r.position)
	return t


func _check(ok: bool, what: String) -> void:
	print("[avswitch-drag] %s %s" % ["OK  " if ok else "FAIL", what])
	if not ok:
		_failed = true


## A plain arrow cursor (the desktop shows the OS's own; the filmed viewport has none), filled while pressed.
class _Cursor extends Control:
	var at := Vector2.ZERO:
		set(v):
			at = v
			queue_redraw()
	var down := false:
		set(v):
			down = v
			queue_redraw()

	func _draw() -> void:
		var s := 2.2
		var pts := PackedVector2Array([Vector2(0, 0), Vector2(0, 17), Vector2(4, 13), Vector2(7, 20), Vector2(10, 19),
			Vector2(7, 12), Vector2(12, 12)])
		for i in pts.size():
			pts[i] = at + pts[i] * s
		draw_colored_polygon(pts, Color(1, 0.85, 0.3) if down else Color(1, 1, 1))
		var loop := pts.duplicate()
		loop.append(pts[0])
		draw_polyline(loop, Color(0, 0, 0), 2.0)
