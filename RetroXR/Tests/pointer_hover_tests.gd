extends "res://Tests/test_suite.gd"

## Two pointers, two hovers. A panel's viewport has one mouse, so a second laser
## lit nothing (PointerHover, and the local edits in viewport_2d_in_3d_body.gd);
## the 3D widgets kept hover as one bool, so the first laser off a button turned
## its outline off under the other.
##
## `hit/` is PointerHover.find_control against the engine's own answer (the mouse
## hover after a real motion). `panel/` drives the REAL addon body with synthetic
## pointer events, no headset. `widgets/` is each widget's pointer_event.

const VP := Vector2(200.0, 100.0)
const SCREEN := Vector2(2.0, 1.0)
const BODY_SCRIPT := "res://addons/godot-xr-tools/objects/viewport_2d_in_3d_body.gd"


func _ready() -> void:
	await _hit_cases()
	await _panel_cases()
	_widget_cases()
	_finish()


# ── hit/ ──────────────────────────────────────────────────────────────────────

func _hit_cases() -> void:
	var vp := _viewport()
	add_child(vp)
	var root := Control.new()
	root.size = VP
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vp.add_child(root)
	var box := HBoxContainer.new()
	box.position = Vector2(10, 10)
	box.size = Vector2(100, 40)
	root.add_child(box)
	var a := _button("A", box)
	var b := _button("B", box)
	# A label over A that ignores the mouse, as a tile's caption does.
	var caption := Label.new()
	caption.text = "caption"
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	a.add_child(caption)
	# A scroller whose content runs past its clip.
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(120, 10)
	scroll.size = Vector2(60, 40)
	root.add_child(scroll)
	var tall := VBoxContainer.new()
	scroll.add_child(tall)
	var rows: Array[Button] = []
	for i in 6:
		var row := _button("row %d" % i, tall)
		row.custom_minimum_size = Vector2(50, 20)
		rows.append(row)
	# A popup-ish top-level button drawn outside every container.
	var floater := _button("float", root)
	floater.top_level = true
	floater.position = Vector2(20, 70)
	floater.size = Vector2(40, 20)
	await get_tree().process_frame
	await get_tree().process_frame

	for at: Vector2 in [a.get_global_rect().get_center(), b.get_global_rect().get_center(),
			Vector2(150, 15), Vector2(150, 45), Vector2(150, 60), Vector2(30, 75),
			Vector2(5, 5), Vector2(190, 95)]:
		_motion(vp, at)
		var engine := vp.gui_get_hovered_control()
		var ours := PointerHover.find_control(vp, at)
		_ok(ours == engine, "hit/agrees with the engine at %s (%s, engine %s)"
			% [at, _name(ours), _name(engine)])
	_ok(PointerHover.find_control(vp, a.get_global_rect().get_center()) == a,
		"hit/an IGNORE caption passes through to its tile")
	_ok(PointerHover.find_control(vp, Vector2(150, 60)) == null,
		"hit/a row scrolled past the clip is not under the pointer")
	_ok(PointerHover.find_control(vp, Vector2(30, 75)) == floater,
		"hit/a top-level control is found outside its parent's container")
	b.visible = false
	_ok(PointerHover.find_control(vp, Vector2(80, 30)) != b, "hit/a hidden tile is not hit")
	vp.queue_free()
	await get_tree().process_frame


# ── panel/ ────────────────────────────────────────────────────────────────────

func _panel_cases() -> void:
	var panel := Node3D.new()
	add_child(panel)
	var vp := _viewport()
	vp.name = "Viewport"
	panel.add_child(vp)
	var row := HBoxContainer.new()
	row.size = VP
	vp.add_child(row)
	var t1 := _button("one", row)
	var t2 := _button("two", row)
	var t3 := _button("three", row)
	for t in [t1, t2, t3]:
		t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var body := StaticBody3D.new()
	body.set_script(load(BODY_SCRIPT))
	body.set("screen_size", SCREEN)
	body.set("viewport_size", VP)
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	body.add_child(shape)
	panel.add_child(body)
	await get_tree().process_frame
	await get_tree().process_frame

	var signals := {}
	for t: Button in [t1, t2, t3]:
		signals[t] = 0
		t.mouse_entered.connect(func() -> void: signals[t] += 1)
		t.mouse_exited.connect(func() -> void: signals[t] -= 1)
	var presses := [0]
	t1.pressed.connect(func() -> void: presses[0] += 1)

	var left := Node3D.new()
	var right := Node3D.new()
	add_child(left)
	add_child(right)
	var c1 := t1.get_global_rect().get_center()
	var c2 := t2.get_global_rect().get_center()
	var c3 := t3.get_global_rect().get_center()

	_send(body, XRToolsPointerEvent.Type.ENTERED, left, c1)
	_send(body, XRToolsPointerEvent.Type.ENTERED, right, c2)
	_ok(t1.is_hovered(), "panel/the mouse laser lights its tile")
	_ok(t2.is_hovered(), "panel/the second laser lights its tile too")
	_ok(not t3.is_hovered(), "panel/a tile neither is on stays dark")

	_send(body, XRToolsPointerEvent.Type.MOVED, right, c3, c2)
	_ok(not t2.is_hovered() and t3.is_hovered(), "panel/the second laser's light follows it")

	_send(body, XRToolsPointerEvent.Type.MOVED, right, c1, c3)
	_ok(t1.is_hovered() and not t3.is_hovered(), "panel/both lasers on one tile")
	_send(body, XRToolsPointerEvent.Type.MOVED, left, c2, c1)
	_ok(t1.is_hovered(), "panel/the mouse leaving a tile the other laser is on keeps it lit")
	_ok(t2.is_hovered(), "panel/... and the mouse lights the tile it went to")
	_send(body, XRToolsPointerEvent.Type.MOVED, right, c2, c1)
	_ok(not t1.is_hovered(), "panel/the last laser off a tile darkens it")
	_send(body, XRToolsPointerEvent.Type.MOVED, right, c3, c2)
	_ok(t2.is_hovered(), "panel/the second laser leaving the mouse's tile keeps it lit")

	_send(body, XRToolsPointerEvent.Type.EXITED, right, c3)
	_ok(not t3.is_hovered(), "panel/the second laser leaving the panel darkens its tile")
	_send(body, XRToolsPointerEvent.Type.EXITED, left, c2)
	_ok(not t2.is_hovered(), "panel/the mouse laser leaving the panel darkens its tile")
	for t: Button in [t1, t2, t3]:
		_ok(signals[t] == 0, "panel/%s's mouse_entered and mouse_exited balance (%d)"
			% [t.text, signals[t]])

	# A second laser that presses becomes the mouse: its tile stays lit and is
	# pressed once, not twice.
	_send(body, XRToolsPointerEvent.Type.ENTERED, left, c3)
	_send(body, XRToolsPointerEvent.Type.ENTERED, right, c1)
	_send(body, XRToolsPointerEvent.Type.PRESSED, right, c1)
	_ok(t1.is_hovered(), "panel/a laser that presses and takes the mouse keeps its tile lit")
	_send(body, XRToolsPointerEvent.Type.RELEASED, right, c1)
	_ok(presses[0] == 1, "panel/... and presses it once (%d)" % presses[0])
	_ok(t3.is_hovered(), "panel/... while the laser it took the mouse from stays lit")
	_send(body, XRToolsPointerEvent.Type.EXITED, right, c1)
	_send(body, XRToolsPointerEvent.Type.EXITED, left, c3)
	_ok(not t1.is_hovered() and not t3.is_hovered(), "panel/both gone, nothing lit")
	panel.queue_free()
	left.queue_free()
	right.queue_free()
	await get_tree().process_frame


# ── widgets/ ──────────────────────────────────────────────────────────────────

func _widget_cases() -> void:
	var left := Node3D.new()
	var right := Node3D.new()
	add_child(left)
	add_child(right)
	for entry: Array in [[VRButton, "_pointer_hovered"], [VRSlider, "_pointer_hovered"],
			[VRKnob, "_pointer_hover"], [VRHinge, "_pointer_hover"],
			[VRLever, "_pointer_hover"], [PageGrab, "_pointer_hover"]]:
		var w: Node3D = (entry[0] as GDScript).new()
		var field: String = entry[1]
		var label := (entry[0] as GDScript).get_global_name()
		add_child(w)
		if w is PageGrab:
			w.set("_enabled", true)
		w.pointer_event(XRToolsPointerEvent.new(XRToolsPointerEvent.Type.ENTERED, left, w, Vector3.ZERO, Vector3.ZERO))
		w.pointer_event(XRToolsPointerEvent.new(XRToolsPointerEvent.Type.ENTERED, right, w, Vector3.ZERO, Vector3.ZERO))
		w.pointer_event(XRToolsPointerEvent.new(XRToolsPointerEvent.Type.EXITED, left, w, Vector3.ZERO, Vector3.ZERO))
		_ok(w.get(field) == true, "widgets/%s stays hovered while the other laser is on it" % label)
		w.pointer_event(XRToolsPointerEvent.new(XRToolsPointerEvent.Type.EXITED, right, w, Vector3.ZERO, Vector3.ZERO))
		_ok(w.get(field) == false, "widgets/%s is not hovered once both have left" % label)
		w.queue_free()
	left.queue_free()
	right.queue_free()


# ── helpers ───────────────────────────────────────────────────────────────────

func _viewport() -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(VP)
	vp.disable_3d = true
	vp.gui_embed_subwindows = true
	return vp


func _button(text: String, parent: Node) -> Button:
	var b := Button.new()
	b.text = text
	parent.add_child(b)
	return b


func _motion(vp: Viewport, at: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	e.global_position = at
	vp.push_input(e)


## A pointer event at a viewport pixel, as the body's plane at the origin sees it.
func _send(body: Node, type: XRToolsPointerEvent.Type, pointer: Node3D, at: Vector2,
		from := Vector2(-1, -1)) -> void:
	var p := _to_world(at)
	var last := p if from.x < 0.0 else _to_world(from)
	body.pointer_event.emit(XRToolsPointerEvent.new(type, pointer, body, p, last))


func _to_world(at: Vector2) -> Vector3:
	return Vector3((at.x / VP.x - 0.5) * SCREEN.x, (0.5 - at.y / VP.y) * SCREEN.y, 0.0)


func _name(c: Control) -> String:
	return "null" if c == null else String(c.name)

