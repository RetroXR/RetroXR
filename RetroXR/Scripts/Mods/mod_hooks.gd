## ModHooks — how a mod attaches to classes it cannot edit.
##
## Built on get_tree().node_added, which is already how QualityManager,
## HeldObjectPhysics, TypingGuard and VRKeyboardFix decorate nodes as they
## appear. This is the house pattern, not a new one.
##
## Connected LAZILY: with no mod asking for a node hook, nothing is connected and
## the signal costs nothing. node_added fires for every node in the tree, so the
## per-node test is kept to a class check against a small list.
class_name ModHooks
extends RefCounted

## [{owner: String, cls: StringName, cb: Callable}]
var _node_watchers: Array[Dictionary] = []
var _connected := false
var _tree: SceneTree = null
## "<cls>/<key>" -> the mod that dresses it. See claim_dress.
var _dressers: Dictionary = {}
## Every class some watcher names: {cls: true}.
var _watched: Dictionary = {}
## What _matches would say, worked out once rather than per node per watcher:
## native class -> {watched cls it is_class()es}, and Script -> {"names": {watched
## global names on its chain}, "connector": whether its nodes have one}. A room
## restore adds ~13,600 nodes against ~100 watchers, and asking _matches for each
## pair was 1.39 M calls, ~1.7 s of the restore before any hook did any work
## (Tracy, Tools/perf/restore_perf_probe, 2026-11-10). Dropped whenever the
## watcher set changes.
var _native_hits: Dictionary = {}
var _script_hits: Dictionary = {}


func _init(tree: SceneTree) -> void:
	_tree = tree


## Call `cb(node)` for every node of class `cls` added from now on.
##
## `cls` is matched with is_class(), so it covers engine classes and any
## script class registered globally -- "RetroSystem", "RetroTV", "Node3D".
func watch_nodes(owner_id: String, cls: StringName, cb: Callable) -> void:
	_node_watchers.append({"owner": owner_id, "cls": cls, "cb": cb})
	_rewatch()
	if not _connected and _tree != null:
		_tree.node_added.connect(_on_node_added)
		_connected = true


func _on_node_added(node: Node) -> void:
	var hits := _classes_of(node)
	if hits.is_empty():
		return
	for w: Dictionary in _node_watchers:
		if not hits.has(w["cls"]):
			continue
		var cb: Callable = w["cb"]
		if not cb.is_valid():
			continue
		# A mod that throws must not take the whole tree down with it, and the
		# blame has to name the mod rather than this file.
		cb.call(node)


## The watched classes `node` answers to: for every watched cls, _matches(node, cls)
## -- from the caches, so the engine and script checks run once per native class
## and per script, and only a node whose script has a connector reads it.
func _classes_of(node: Node) -> Dictionary:
	var native := node.get_class()
	var by_native: Variant = _native_hits.get(native)
	if by_native == null:
		var found: Dictionary = {}
		for cls: StringName in _watched:
			if node.is_class(cls):
				found[cls] = true
		_native_hits[native] = found
		by_native = found
	var script: Script = node.get_script() as Script
	if script == null:
		return by_native
	var by_script: Variant = _script_hits.get(script)
	if by_script == null:
		var names: Dictionary = {}
		var s: Script = script
		while s != null:
			var name := s.get_global_name()
			if _watched.has(name):
				names[name] = true
			s = s.get_base_script()
		by_script = {"names": names, "connector": "connector" in node}
		_script_hits[script] = by_script
	var names_hit: Dictionary = by_script["names"]
	var connector: StringName = &""
	if by_script["connector"]:
		connector = StringName(str(node.get("connector")))
		if not _watched.has(connector):
			connector = &""
	if names_hit.is_empty() and connector == &"":
		return by_native
	var out: Dictionary = (by_native as Dictionary).duplicate()
	out.merge(names_hit)
	if connector != &"":
		out[connector] = true
	return out


func _rewatch() -> void:
	_watched.clear()
	for w: Dictionary in _node_watchers:
		_watched[StringName(w["cls"])] = true
	_native_hits.clear()
	_script_hits.clear()


## is_class() only knows engine classes. A script class is matched by walking the
## node's own script chain, which is what makes "RetroSystem" work. A plug or a
## socket also answers to its connector: most have no class of their own, so
## "n64_av_plug" is how a mod names the Nintendo AV lead's plug.
static func _matches(node: Node, cls: StringName) -> bool:
	if node.is_class(cls):
		return true
	var s: Script = node.get_script() as Script
	while s != null:
		if s.get_global_name() == cls:
			return true
		s = s.get_base_script()
	return "connector" in node and str(node.get("connector")) == String(cls)


## Take the right to dress `cls`/`key`, or learn who has it.
##
## Returns "" when `owner_id` now holds it (or already did), else the mod that
## got there first. Two mods that each hang a shell on the same memory card both
## draw, one inside the other, and neither can see the other to step aside --
## so the first to ask is the one that dresses it. Mods register in priority
## order, which makes "first" the player's own ordering.
func claim_dress(owner_id: String, cls: StringName, key: String) -> String:
	var slot := "%s/%s" % [cls, key]
	var holder := str(_dressers.get(slot, ""))
	if holder.is_empty():
		_dressers[slot] = owner_id
		return ""
	return "" if holder == owner_id else holder


## Which mod dresses `cls`/`key`, or "" when none does: what the game's own dressing of a shipped object asks
## before it puts its model on (AudioCassette's Compact Cassette steps aside for a mod's shell).
func dresser_of(cls: StringName, key: String) -> String:
	return str(_dressers.get("%s/%s" % [cls, key], ""))


## Drop every watcher belonging to a mod. Used when a mod's registration failed
## part-way, so a half-registered mod leaves nothing behind.
func drop_owner(owner_id: String) -> void:
	for slot: String in _dressers.keys():
		if _dressers[slot] == owner_id:
			_dressers.erase(slot)
	var kept: Array[Dictionary] = []
	for w: Dictionary in _node_watchers:
		if w["owner"] != owner_id:
			kept.append(w)
	_node_watchers = kept
	_rewatch()
