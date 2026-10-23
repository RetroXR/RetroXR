extends XRToolsInteractableBody


## Screen size
@export var screen_size = Vector2(3.0, 2.0)

## Viewport size
@export var viewport_size = Vector2(100.0, 100.0)


# Current mouse mask
var _mouse_mask := 0

# Viewport node
var _viewport : Viewport

# Dictionary of pointers to touch-index
var _touches := {}

# Dictionary of pressed pointers
var _presses := {}

# Dominant pointer (index == 0)
var _dominant : Node3D

# Mouse pointer
var _mouse : Node3D

# Last mouse position
var _mouse_last := Vector2.ZERO

# LOCAL MODIFICATION (RetroXR): hover for the pointers that are not the mouse,
# and where each pointer last was, for one that stops being the mouse.
var _hover : PointerHover
var _hover_at := {}


func _ready():
	# Get viewport node
	_viewport = get_node("../Viewport")
	_hover = PointerHover.new(_viewport)

	# Subscribe to pointer events
	pointer_event.connect(_on_pointer_event)


## Convert intersection point to screen coordinate
func global_to_viewport(p_at : Vector3) -> Vector2:
	var t = $CollisionShape3D.global_transform
	var at = t.affine_inverse() * p_at

	# Convert to screen space
	at.x = ((at.x / screen_size.x) + 0.5) * viewport_size.x
	at.y = (0.5 - (at.y / screen_size.y)) * viewport_size.y

	return Vector2(at.x, at.y)


# Pointer event handler
func _on_pointer_event(event : XRToolsPointerEvent) -> void:
	# Ignore if we have no viewport
	if not is_instance_valid(_viewport):
		return

	# Get the pointer and event type
	var pointer := event.pointer
	var type := event.event_type

	# Get the touch-index [0..]
	var index : int = _touches.get(pointer, -1)

	# Create a new touch-index if necessary
	if index < 0 or type == XRToolsPointerEvent.Type.ENTERED:
		# Clear any stale pointer information
		_touches.erase(pointer)
		_presses.erase(pointer)

		# Assign a new touch-index for the pointer
		index = _next_touch_index()
		_touches[pointer] = index

		# Detect dominant pointer
		if index == 0:
			_dominant = pointer

	# Get the viewport positions
	var at := global_to_viewport(event.position)
	var last := global_to_viewport(event.last_position)

	# Get/update pressed state
	var pressed : bool
	match type:
		XRToolsPointerEvent.Type.PRESSED:
			_presses[pointer] = true
			pressed = true

		XRToolsPointerEvent.Type.RELEASED:
			_presses.erase(pointer)
			pressed = false

		_:
			pressed = _presses.has(pointer)

	# LOCAL MODIFICATION (RetroXR) — reapply if this addon is updated.
	#
	# Upstream dispatched touch events for EVERY pointer and then mouse events
	# for the mouse pointer as well, so the mouse pointer sent BOTH. A Control
	# accepts either as a click, so one press arrived at a Button twice:
	#
	#   ScreenTouch pressed=true -> Button.pressed (#1)
	#   MouseButton pressed=true -> Button.pressed (#2)
	#
	# Every panel in this project is single-pointer, and the mouse path is the
	# one that carries hover and focus, so the mouse pointer now sends mouse
	# events only. Other pointers are unchanged and still get a touch index, so
	# a second simultaneous pointer keeps working.
	#
	# Selecting the mouse moved ABOVE the dispatch — it used to run between the
	# two, so a pointer becoming the mouse on this very event had already sent
	# its touch.
	#
	# A press claims the mouse whatever the pointer is. Upstream let only an
	# XRToolsFunctionPointer claim it, and neither XRToolsPoke nor
	# XRToolsDesktopFunctionPointer is one — so with a laser merely hovering the
	# panel, a fingertip poke went down the touch path. Buttons survived that;
	# LineEdit ignores InputEventScreenTouch outright, so poking a text field
	# neither focused it nor opened the overlay keyboard. The pointer that
	# pressed is the one the user means.

	# Whether this pointer was the mouse before any handover below.
	var was_mouse := pointer == _mouse
	var old_mouse := _mouse

	# If the current mouse isn't pressed then consider switching to a new one
	if not _presses.has(_mouse):
		if type == XRToolsPointerEvent.Type.PRESSED:
			# Switch to the pressing pointer
			_mouse = pointer
		elif type == XRToolsPointerEvent.Type.EXITED and pointer == _mouse:
			# Current mouse leaving, switch to dominant
			_mouse = _dominant
		elif not _mouse and _dominant:
			# No mouse, pick the dominant
			_mouse = _dominant

	# LOCAL MODIFICATION (RetroXR) — reapply if this addon is updated.
	#
	# Only the mouse hovers: Godot's GUI never lights a Control for a touch, so
	# with a laser on each hand only one tile lit. PointerHover sends the other
	# pointers' Controls the enter/exit a mouse would, and keeps a Control lit
	# while any pointer is on it (sync_mouse re-enters what the mouse just left
	# under another pointer). A pointer that has become the mouse hands its
	# hover back first, and is moved to where it is, as a real mouse would be
	# before it clicked.
	if pointer == _mouse:
		_hover.release(pointer)
		if not was_mouse and type != XRToolsPointerEvent.Type.MOVED:
			_report_mouse_move(false, at, at)

		# Fire mouse events
		match type:
			XRToolsPointerEvent.Type.PRESSED:
				_report_mouse_down(at)

			XRToolsPointerEvent.Type.RELEASED:
				_report_mouse_up( at)

			XRToolsPointerEvent.Type.MOVED:
				_report_mouse_move(pressed, last, at)

		_hover.sync_mouse()

		# The pointer this one took the mouse from is still on the panel: it
		# hovers as the others do from here.
		if old_mouse != pointer and is_instance_valid(old_mouse) 				and _hover_at.has(old_mouse):
			_hover.move(old_mouse, _hover_at[old_mouse])
	else:
		if type != XRToolsPointerEvent.Type.EXITED:
			_hover.move(pointer, at)

		# Dispatch touch events
		match type:
			XRToolsPointerEvent.Type.PRESSED:
				_report_touch_down(index, at)

			XRToolsPointerEvent.Type.RELEASED:
				_report_touch_up(index, at)

			XRToolsPointerEvent.Type.MOVED:
				_report_touch_move(index, pressed, last, at)

	_hover_at[pointer] = at

	# Clear pointer information on exit
	if type == XRToolsPointerEvent.Type.EXITED:
		# LOCAL MODIFICATION (RetroXR) — reapply if this addon is updated.
		#
		# Upstream drops the press here without ever telling the viewport, so a
		# Control holding a drag never learns the button came up. A VScrollBar
		# keeps drag.active set, and re-entering the panel resumes the drag with
		# the trigger long since released — the bar scrolls by itself. Release
		# where the pointer left, so the drag ends the way a real mouse would.
		if _presses.has(pointer):
			if pointer == _mouse:
				_report_mouse_up(at)
			else:
				_report_touch_up(index, at)

		# LOCAL MODIFICATION (RetroXR) — reapply if this addon is updated.
		#
		# Upstream never told the viewport the mouse had gone, so the Control
		# under it stayed hovered — a tile stayed lit after its laser left the
		# panel. Move the mouse off the panel, which drops the engine's hover.
		if was_mouse:
			_report_mouse_leave(at)
			_hover.sync_mouse()
		_hover.release(pointer)
		_hover_at.erase(pointer)

		# Clear pointer information
		_touches.erase(pointer)
		_presses.erase(pointer)
		if pointer == _dominant:
			_dominant = null
		if pointer == _mouse:
			_mouse = null


# Report touch-down event
func _report_touch_down(index : int, at : Vector2) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = at
	event.pressed = true
	_viewport.push_input(event)


# Report touch-up event
func _report_touch_up(index : int, at : Vector2) -> void:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = at
	event.pressed = false
	_viewport.push_input(event)


# Report touch-move event
func _report_touch_move(index : int, pressed : bool, from : Vector2, to : Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = to
	event.pressure = 1.0 if pressed else 0.0
	event.relative = to - from
	_viewport.push_input(event)


# Report mouse-down event
func _report_mouse_down(at : Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = 1
	event.pressed = true
	event.position = at
	event.global_position = at
	event.button_mask = 1
	_viewport.push_input(event)


# Report mouse-up event
func _report_mouse_up(at : Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = 1
	event.pressed = false
	event.position = at
	event.global_position = at
	event.button_mask = 0
	_viewport.push_input(event)


# Report mouse-move event
func _report_mouse_move(pressed : bool, from : Vector2, to : Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = to
	event.global_position = to
	event.relative = to - from
	event.button_mask = 1 if pressed else 0
	event.pressure = 1.0 if pressed else 0.0
	_viewport.push_input(event)


# LOCAL MODIFICATION (RetroXR): the mouse has left the panel. A motion to a
# point off the viewport finds no Control, so the engine drops its hover.
func _report_mouse_leave(from : Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = Vector2(-1.0, -1.0)
	event.global_position = event.position
	event.relative = event.position - from
	_viewport.push_input(event)


# Find the next free touch index
func _next_touch_index() -> int:
	# Get the current touches
	var current := _touches.values()
	current.sort()

	# Look for a hole
	for touch in current.size():
		if current[touch] != touch:
			return touch

	# No hole so add to end
	return current.size()
