## XrControllers — every XRController3D in the tree, without walking the tree each time.
##
## Every pokeable control (VRButton, VRKnob, VRSlider, VRHinge, PageGrab, a pad's
## input, a book, a remote...) asked `get_tree().root.find_children("*",
## "XRController3D", true, false)` in its _ready, and that walks every node in the
## room checking its class. A 151-object room restore made 230 VRButtons alone do
## it: 2.5 s of one frame (Tracy, Tools/perf/restore_perf_probe, 2026-11-10).
##
## all() answers exactly what that call does -- the same nodes, in tree order -- and
## walks again only when an XRController3D has entered or left the tree since, or
## a node in the list is no longer in it (node_removed fires while a node is still
## inside, so a call made during that signal would otherwise cache it).
class_name XrControllers
extends RefCounted

static var _list: Array[Node] = []
static var _dirty := true
static var _tree: SceneTree = null


## The controllers, as `tree.root.find_children("*", "XRController3D", true, false)`
## would list them. A copy: the caller may keep or change it.
static func all(tree: SceneTree) -> Array[Node]:
	if tree == null:
		return []
	if tree != _tree:
		_watch(tree)
	if not _dirty:
		for node: Node in _list:
			if not is_instance_valid(node) or not node.is_inside_tree():
				_dirty = true
				break
	if _dirty:
		_list = tree.root.find_children("*", "XRController3D", true, false)
		_dirty = false
	return _list.duplicate()


static func _watch(tree: SceneTree) -> void:
	_tree = tree
	_dirty = true
	tree.node_added.connect(_on_tree_changed)
	tree.node_removed.connect(_on_tree_changed)


static func _on_tree_changed(node: Node) -> void:
	if node is XRController3D:
		_dirty = true
