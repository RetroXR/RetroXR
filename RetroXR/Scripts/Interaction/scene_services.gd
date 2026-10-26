## SceneServices — the one place the room's player-side services are looked up.
##
## Held objects (pads, the light gun, the Wiimote, handhelds, the TV remote, ...)
## need the SpawnMenuController (to disable the left-hand menu while that hand
## holds them) and the LocomotionManager (to block the stick that is now a
## d-pad). Both live in the player rig, which a held object has no path to, so
## they are found by NODE NAME anywhere under the root. Each script used to
## write that search inline, so renaming either node silently switched the
## behaviour off in every copy; here the names are written once, and a lookup
## that finds nothing says so in the log.
##
## The search is deliberately the same tree-wide find_child the copies used, so
## a mod's rig or a test scene that names the node the same way is found exactly
## as before.
class_name SceneServices
extends RefCounted

const SPAWN_MENU_NAME := "SpawnMenuController"
const LOCOMOTION_NAME := "LocomotionManager"

# Which names have already been reported missing, so a room without a rig (a
# headless suite, a probe) logs one line per name rather than one per object.
static var _reported_missing: Dictionary = {}


## The room's SpawnMenuController, or null.
static func spawn_menu(from: Node) -> Node:
	return _find(from, SPAWN_MENU_NAME)


## The room's LocomotionManager, or null.
static func locomotion(from: Node) -> Node:
	return _find(from, LOCOMOTION_NAME)


static func _find(from: Node, node_name: String) -> Node:
	if from == null or not from.is_inside_tree():
		_report_missing(node_name, "asked from a node outside the tree")
		return null
	var found: Node = from.get_tree().root.find_child(node_name, true, false)
	if found == null:
		_report_missing(node_name, "no node of that name under the root")
	return found


static func _report_missing(node_name: String, why: String) -> void:
	if _reported_missing.has(node_name):
		return
	_reported_missing[node_name] = true
	print("[SceneServices] %s not found (%s); held objects will not block it" % [node_name, why])
