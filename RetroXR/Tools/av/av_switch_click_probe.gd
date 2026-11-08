## The AV switch worked from the desktop, filmed: the crosshair clicks labels 3, 1 and 4, clicks the tab to step it
## on, then drags it two detents. Built on av_switch_probe's room (an NES live on INPUT 1, a Genesis on INPUT 3,
## here counted as switched on so its label lights too). The camera is aimed so a drawn crosshair is on each target,
## and the clicks are the desktop pointer's own events on what InteractionResolver.resolve_desktop takes there.
## WINDOWED, every frame rendered:
##
##     "$godot" --path RetroXR --resolution 320x240 --position 20,20 --fixed-fps 30 \
##         res://Tools/av/av_switch_click_probe.tscn -- --no-mods --out=<dir>
## then encode frames/ with imageio (libx264, -crf 24, 30 fps). Prints [avswitch-click] lines; PASS needs every
## click and the drag to land on the input it aimed at.
extends "res://Tools/av/av_switch_probe.gd"

var _pointer: Node3D
var _cross: Control


func _shoot() -> void:
	_md.is_powered_on = true
	_sw.select(0)
	_pointer = Node3D.new()
	_pointer.name = "DesktopPointer"
	add_child(_pointer)
	_cross = _Crosshair.new()
	_cross.size = Vector2(SIZE)
	_sv.add_child(_cross)
	_recording = true
	var eye := _sw.global_position + Vector3(0.02, 0.17, 0.34)
	await _look_at(eye, _sw.global_position + Vector3(0, 0.02, 0.06), 20)
	await _wait(20)
	for i in [2, 0, 3]:
		await _look_at(eye, _window(i), 24)
		await _click(_window(i), [])
		_check(_sw.selected == i, "label %d click -> input %d" % [i + 1, _sw.selected + 1])
		await _wait(30)
	await _look_at(eye, _tab(), 24)
	await _click(_tab(), [])
	_check(_sw.selected == 0, "tab click 4 -> %d (wraps to 1)" % (_sw.selected + 1))
	await _wait(30)
	# The drag: the view turns with the mouse and the crosshair carries the tab two detents to the right.
	var slider := _sw.get_node("Selector") as VRSlider
	var along := slider.global_basis.x.normalized()
	var start := _tab()
	var pitch := slider.travel / float(slider.steps - 1)
	var t := _press(start)
	var last := start
	for k in 40:
		var p := start + along * pitch * 2.0 * float(k + 1) / 40.0
		_cam.look_at(p, Vector3.UP)
		XRToolsPointerEvent.moved(_pointer, t, p, last)
		last = p
		await _wait(1)
	XRToolsPointerEvent.released(_pointer, t, last)
	XRToolsPointerEvent.exited(_pointer, t, last)
	_check(_sw.selected == 2, "drag 1 -> %d (two detents)" % (_sw.selected + 1))
	await _wait(45)
	_recording = false
	print("[avswitch-click] frames %d" % _frames)


func _window(i: int) -> Vector3:
	var part := _sw.get_node("Model").call("part", "Label%d" % (i + 1)) as MeshInstance3D
	return (part.global_transform * part.get_aabb()).get_center()


func _tab() -> Vector3:
	var tab := _sw.get_node("Model").call("part", "SlideTab") as MeshInstance3D
	return (tab.global_transform * tab.get_aabb()).get_center()


## Turn the view onto `at` over `frames` frames (the crosshair stays in the middle of the picture).
func _look_at(eye: Vector3, at: Vector3, frames: int) -> void:
	_cam.global_position = eye
	var from := eye + (-_cam.global_basis.z) * eye.distance_to(at)
	for k in frames:
		var u := float(k + 1) / float(frames)
		u = u * u * (3.0 - 2.0 * u)
		_cam.look_at(from.lerp(at, u), Vector3.UP)
		await _wait(1)


func _press(at: Vector3) -> Node3D:
	var space := _sw.get_world_3d().direct_space_state
	var from := _cam.global_position
	var r := InteractionResolver.resolve_desktop(space, from, from + (at - from) * 1.2, _pointer)
	if r == null or not is_instance_valid(r.pointer_event_target):
		print("[avswitch-click] nothing to press at %s" % at)
		return null
	var t := r.pointer_event_target
	XRToolsPointerEvent.entered(_pointer, t, r.position)
	XRToolsPointerEvent.pressed(_pointer, t, r.position)
	return t


func _click(at: Vector3, _moves: Array) -> void:
	var t := _press(at)
	if t == null:
		_failed = true
		return
	(_cross as _Crosshair).pressed = true
	await _wait(5)
	XRToolsPointerEvent.released(_pointer, t, at)
	XRToolsPointerEvent.exited(_pointer, t, at)
	(_cross as _Crosshair).pressed = false
	await _wait(2)


func _check(ok: bool, what: String) -> void:
	print("[avswitch-click] %s %s" % ["OK  " if ok else "FAIL", what])
	if not ok:
		_failed = true


class _Crosshair extends Control:
	var pressed := false:
		set(v):
			pressed = v
			queue_redraw()

	func _draw() -> void:
		var c := size / 2.0
		var col := Color(1, 0.85, 0.3) if pressed else Color(1, 1, 1, 0.9)
		var r := 9.0 if pressed else 12.0
		draw_line(c + Vector2(-r - 8, 0), c + Vector2(-r + 4, 0), col, 3.0)
		draw_line(c + Vector2(r - 4, 0), c + Vector2(r + 8, 0), col, 3.0)
		draw_line(c + Vector2(0, -r - 8), c + Vector2(0, -r + 4), col, 3.0)
		draw_line(c + Vector2(0, r - 4), c + Vector2(0, r + 8), col, 3.0)
		draw_arc(c, r, 0, TAU, 32, col, 2.0)
