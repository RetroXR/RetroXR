## KeyboardKeyField — makes a RetroKeyboard's caps clickable with the desktop
## reticle / VR laser.
##
## Exists as a separate Area3D rather than as methods on the board because
## InteractionResolver._classify tests `is XRToolsPickable` BEFORE
## `has_method("pointer_event")`. RetroKeyboard *is* an XRToolsPickable, so a
## pointer_event on the board itself would never fire — every click would grab the
## keyboard instead. Hit as its own area it classifies as KIND_POINTER
## (can_grab = false), which both routes the press here and blocks the pickup.
##
## It also has to sit on POINTABLE_LAYER, and it sits INSIDE the board's own grab
## body — measured at 1 mm behind its surface. The resolver walks front to back,
## so the board is hit first; what hands the press here instead is
## InteractionResolver.ENCLOSURE_DEPTH, which lets a control win from up to 50 mm
## inside the thing housing it. A field further in than that would stop working.
##
## The individual caps have no colliders of their own — they are bare meshes —
## so this is one box over the whole grid and the board resolves which key was hit
## from the collision point via its existing rect lookup.
class_name KeyboardKeyField
extends Area3D

var _board: Node3D = null
var _pressed := false


## Called by RetroKeyboard._build_keys once the grid extents are known.
## `centre`/`size` are board-local; the box is thin and sits just above the caps.
static func create(board: Node3D, centre: Vector3, size: Vector3) -> KeyboardKeyField:
	var field := KeyboardKeyField.new()
	field.name = "KeyPointerField"
	field._board = board
	field.collision_layer = VRSlider.POINTABLE_LAYER
	field.collision_mask = 0
	field.monitoring = false
	field.monitorable = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	field.add_child(shape)
	field.position = centre
	return field


## Only claim a point with a cap actually under it.
##
## This box is 483 x 134 mm — 95% of the board's footprint — and its top sits 1 mm
## under the board's own, so without this the resolver's enclosure rule hands it
## every aim anywhere on the keyboard and the board can never be picked up by
## pointing at the surround, the palm rest or the back edge.
func accepts_pointer_at(at: Vector3) -> bool:
	if not is_instance_valid(_board) or not _board.has_method("has_key_at"):
		return true
	return bool(_board.call("has_key_at", at))


func pointer_event(event: XRToolsPointerEvent) -> void:
	if not is_instance_valid(_board):
		return
	match event.event_type:
		XRToolsPointerEvent.Type.ENTERED:
			_board.call("pointer_hover_at", event.position, event.pointer)
		XRToolsPointerEvent.Type.PRESSED:
			_pressed = true
			_board.call("pointer_hover_at", event.position, event.pointer)
			_board.call("pointer_press_at", event.position, event.pointer)
		XRToolsPointerEvent.Type.MOVED:
			_board.call("pointer_hover_at", event.position, event.pointer)
			# Dragging across the board retargets, like sliding a finger.
			if _pressed:
				_board.call("pointer_press_at", event.position, event.pointer)
		XRToolsPointerEvent.Type.RELEASED:
			if _pressed:
				_pressed = false
				_board.call("pointer_release")
		XRToolsPointerEvent.Type.EXITED:
			_board.call("pointer_hover_end", event.pointer)
			if _pressed:
				_pressed = false
				_board.call("pointer_release")
