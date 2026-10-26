## PointerHover — hover for the pointers a panel's viewport cannot see.
##
## A Viewport2Din3D makes ONE pointer the viewport's mouse (the addon body's
## `_mouse`); every other pointer goes in as touch, and Godot's GUI never hovers
## on touch. With a laser on each hand, only the mouse laser's tile lit.
##
## For each extra pointer this runs the hit test the engine's gui_find_control
## runs, and sends the Controls under it what a real mouse would: MOUSE_ENTER
## and mouse_entered, MOUSE_EXIT and mouse_exited, along the same ancestor chain
## (_gui_update_mouse_over: up through PASS parents, stopping at STOP or a top
## level). A Control stays lit while ANY pointer is on it:
##
##   - a pointer leaving does not exit a Control another pointer, or the real
##     mouse, is still on;
##   - the real mouse leaving a Control an extra pointer is on gets the engine's
##     exit, so sync_mouse() answers it with an enter again.
##
##   var hover := PointerHover.new(viewport)
##   hover.move(pointer, at)   # an extra pointer moved to `at` (viewport px)
##   hover.release(pointer)    # it left, or it became the mouse
##   hover.sync_mouse()        # after every event pushed for the mouse
class_name PointerHover
extends RefCounted

var _viewport: Viewport = null
## pointer instance id -> the instance ids of the Controls it entered, root-most
## first (the engine's mouse_over_hierarchy order).
var _chains: Dictionary = {}
## The real mouse's chain at the last sync_mouse.
var _mouse_chain: Array = []


func _init(viewport: Viewport) -> void:
	_viewport = viewport


## An extra pointer is at `at`, in the viewport's pixels.
func move(pointer: Object, at: Vector2) -> void:
	_set_chain(pointer.get_instance_id(), chain_of(find_control(_viewport, at)))


## An extra pointer is gone from the panel, or is the mouse now.
func release(pointer: Object) -> void:
	var key := pointer.get_instance_id()
	if _chains.has(key):
		_set_chain(key, [])
		_chains.erase(key)


## Whether any extra pointer is on `control` — what the tests read, since a
## BaseButton's is_hovered() only says that SOMETHING is.
func is_held(control: Control) -> bool:
	return _held(control.get_instance_id())


## Re-enter what the engine just exited: a Control the real mouse left that an
## extra pointer is still on.
func sync_mouse() -> void:
	var now := chain_of(_viewport.gui_get_hovered_control())
	for id: int in _mouse_chain:
		if not now.has(id) and _held(id):
			_enter(id)
	_mouse_chain = now


func _set_chain(key: int, chain: Array) -> void:
	var old: Array = _chains.get(key, [])
	_chains[key] = chain
	var mouse := chain_of(_viewport.gui_get_hovered_control())
	# Children first on the way out, parents first on the way in, as the engine.
	for i in range(old.size() - 1, -1, -1):
		var id: int = old[i]
		if not chain.has(id) and not mouse.has(id) and not _held(id):
			_exit(id)
	for id: int in chain:
		if not old.has(id) and not mouse.has(id) and not _held(id, key):
			_enter(id)


## Whether a pointer other than `except` has `id` in its chain.
func _held(id: int, except: int = 0) -> bool:
	for key: int in _chains:
		if key != except and (_chains[key] as Array).has(id):
			return true
	return false


func _enter(id: int) -> void:
	var c := instance_from_id(id) as Control
	if c != null and c.is_inside_tree():
		c.notification(Control.NOTIFICATION_MOUSE_ENTER)
		c.mouse_entered.emit()


func _exit(id: int) -> void:
	var c := instance_from_id(id) as Control
	if c != null and c.is_inside_tree():
		c.notification(Control.NOTIFICATION_MOUSE_EXIT)
		c.mouse_exited.emit()


## The Controls a mouse over `over` is in, root-most first, as instance ids.
static func chain_of(over: Control) -> Array:
	var ids: Array = []
	var node: Node = over
	while node is CanvasItem:
		var c := node as Control
		if c != null:
			var filter := c.get_mouse_filter_with_override()
			if filter != Control.MOUSE_FILTER_IGNORE:
				ids.push_front(c.get_instance_id())
			if filter == Control.MOUSE_FILTER_STOP:
				break
		if (node as CanvasItem).top_level:
			break
		node = node.get_parent()
	return ids


## The Control a mouse at `at` would be over, or null: Viewport.gui_find_control,
## which the engine does not expose. Roots are tried last-drawn first.
static func find_control(viewport: Viewport, at: Vector2) -> Control:
	var roots: Array[Control] = []
	_collect_roots(viewport, roots)
	for i in range(roots.size() - 1, -1, -1):
		var root := roots[i]
		if root.is_visible_in_tree():
			var hit := _find_at(root, at)
			if hit != null:
				return hit
	return null


## A gui root is a Control whose parent is not one, or a top-level Control.
## Embedded windows and nested viewports are their own GUI, so they are skipped.
static func _collect_roots(node: Node, out: Array[Control]) -> void:
	for child in node.get_children():
		if child is Viewport:
			continue
		var c := child as Control
		if c != null and (not (node is Control) or c.top_level):
			out.append(c)
		_collect_roots(child, out)


## _gui_find_control_at_pos: children last-drawn first, then the node itself.
## One shortcut the engine does not take — a Container's children are laid out
## inside it, so a point outside a Container skips its subtree.
static func _find_at(node: CanvasItem, at: Vector2) -> Control:
	if not node.visible:
		return null
	var c := node as Control
	var inside := c != null and _has_point(c, c.get_global_transform_with_canvas().affine_inverse() * at)
	if c == null or inside or not (c.clip_contents or c is Container):
		for i in range(node.get_child_count() - 1, -1, -1):
			var child := node.get_child(i) as CanvasItem
			if child == null or child.top_level:
				continue
			var hit := _find_at(child, at)
			if hit != null:
				return hit
	if c == null or c.get_mouse_filter_with_override() == Control.MOUSE_FILTER_IGNORE:
		return null
	return c if inside else null


## Control.has_point, which scripts cannot call: the control's own rect, or its
## `_has_point` where a script shapes it.
static func _has_point(control: Control, local: Vector2) -> bool:
	if control.has_method("_has_point"):
		return control.call("_has_point", local)
	return Rect2(Vector2.ZERO, control.size).has_point(local)
