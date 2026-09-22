## Which PlayStation 2s share an i.LINK bus, and keeping LinkCoordinator agreeing.
##
## IEEE 1394 is a bus, not a pair. A lead between two consoles is the two-node
## case; a hub joins everything plugged into it, and a lead between two hubs joins
## both of theirs. So no one lead can decide what its consoles are on: the answer
## is the connected set of consoles, walking through every hub and every lead
## between them, and it can change when a plug moves at the far side of the room.
##
## That is why this is one static resolver rather than per-lead state, the way
## PsxLinkCable holds its own pair. Each lead asks it to settle the whole room;
## the room is a handful of leads, so recomputing it all is cheaper than being
## clever, and it cannot disagree with itself about which bus a console is on.
##
## The core side (the PS2 fork's pcsx2/FW.cpp) attaches ONE port, 0, with protocol
## "ps2-ilink-1394", and handles up to 64 nodes: bus index is the PHY id and the
## highest is root. Six consoles through one hub were verified with Gran Turismo
## 3's i.LINK Battle. Every ConnectGroup and Disconnect is a bus reset for every
## node on the wire, which is also what a real hub does when a plug goes in.
##
## One behaviour worth knowing, from the same verification: GT3's driver only
## learns who is on the bus from a reset that arrives AFTER it has started. A
## console cabled while still booting sees no later reset and finds nobody. So a
## console switching back on re-states its whole bus once its core has had time to
## start (RESTATE_COOLDOWN), and plugging anything else into the hub re-states it
## too; the one case left is a console that was cabled before it booted and then
## never sees another plug move -- replugging any lead on that bus fixes it.
class_name ILinkBus
extends RefCounted

## Every ILinkCable is in this group; the sweep reads it rather than the plugs.
const CABLE_GROUP := "ilink_cable"

## Physics frames between a console switching back on and its bus being stated
## again -- PsxLinkCable's cooldown, for its reason: not while the core is still
## starting.
const RESTATE_COOLDOWN := 20

## The buses joined right now: key -> {entries, powered, wait}. `entries` is
## [{libretro, machine, port}] in bus order, which is the order they were handed
## to ConnectGroup; the key is made from the Libretro nodes in that order, so a
## different set OR a different order is a different bus.
static var _buses: Dictionary = {}

## Which bus each lead was last part of, by the lead's instance id, so a pull can
## name the machines it was holding after the walk stops finding them.
static var _cable_bus: Dictionary = {}

## The physics frame the power watch last ran on. Every lead calls it and only
## the first one each frame does anything.
static var _watched_frame := -1


# ── the walk ─────────────────────────────────────────────────────────────────

## What one end of a lead is plugged into: the console, the hub, or null.
static func end_node(cable: CompositeCable, e: int) -> Node3D:
	var plugs: Array = cable._end_plugs(e)
	if plugs.is_empty():
		return null
	var plug := plugs[0] as RcaPlug
	if plug == null:
		return null
	var port := plug.seated_port() as ILinkPort
	if port == null:
		return null
	var machine := port.get_machine()
	if machine != null:
		return machine
	return port.get_hub()


## Every connected set in the room, as [{machines, cables}], each list in
## LinkCable.stable_key order so every netplay peer names the same bus head.
## `exclude` is a lead to leave out -- one that is on its way out of the tree.
static func components(tree: SceneTree, exclude: Node = null) -> Array:
	var out: Array = []
	if tree == null:
		return out
	var parent := {}
	var nodes := {}
	var edges: Array = []
	for n: Node in tree.get_nodes_in_group(CABLE_GROUP):
		if n == exclude or not is_instance_valid(n) or n.is_queued_for_deletion():
			continue
		var cable := n as CompositeCable
		if cable == null:
			continue
		var a := end_node(cable, CompositeCable.End.A)
		var b := end_node(cable, CompositeCable.End.B)
		if a == null or b == null:
			continue
		nodes[a.get_instance_id()] = a
		nodes[b.get_instance_id()] = b
		_union(parent, a.get_instance_id(), b.get_instance_id())
		edges.append({"cable": cable, "root": a.get_instance_id()})

	var by_root := {}
	for id: int in nodes:
		var root := _find(parent, id)
		if not by_root.has(root):
			by_root[root] = {"machines": [], "cables": []}
		var node: Node3D = nodes[id]
		if node.has_method("get_libretro_node"):
			(by_root[root]["machines"] as Array).append(node)
	for edge: Dictionary in edges:
		var root := _find(parent, int(edge["root"]))
		(by_root[root]["cables"] as Array).append(edge["cable"])

	for root: int in by_root:
		var comp: Dictionary = by_root[root]
		(comp["machines"] as Array).sort_custom(_by_stable_key)
		(comp["cables"] as Array).sort_custom(_by_stable_key)
		out.append(comp)
	out.sort_custom(func(l: Dictionary, r: Dictionary) -> bool:
		return _by_stable_key.call((l["cables"] as Array)[0], (r["cables"] as Array)[0]))
	return out


## The set this lead is part of, or {} for a lead with a loose end.
static func component_of(tree: SceneTree, cable: Node) -> Dictionary:
	for comp: Dictionary in components(tree):
		if (comp["cables"] as Array).has(cable):
			return comp
	return {}


## The bus this lead is part of, as [{machine, port}] -- the shape every link
## lead's linked_machines() answers in. Empty below two consoles.
static func bus_of(tree: SceneTree, cable: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var comp := component_of(tree, cable)
	if comp.is_empty() or (comp["machines"] as Array).size() < 2:
		return out
	for machine: Node3D in comp["machines"]:
		out.append({"machine": machine, "port": 0})
	return out


## The bus this lead was last joined into, in the same shape, for a pull.
static func held_for(cable: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var key: String = _cable_bus.get(cable.get_instance_id(), "")
	if key.is_empty() or not _buses.has(key):
		return out
	for entry: Dictionary in _buses[key]["entries"]:
		# Checked BEFORE binding, everywhere below as well: binding a freed object
		# to a typed variable faults on the assignment (PsxLinkCable._log_ends),
		# and a bus outlives the consoles on it for as long as a teardown takes.
		if is_instance_valid(entry.get("machine")):
			out.append({"machine": entry["machine"], "port": int(entry.get("port", 0))})
	return out


# ── keeping the coordinator in step ─────────────────────────────────────────

## Work the whole room out again and make LinkCoordinator match it.
##
## Stale buses are parted BEFORE new ones are joined, and only their orphans: a
## console that is moving from one bus to another is handed straight to
## ConnectGroup, which takes a listed port off whatever bus it was on. Parting it
## first would be a second reset for nothing, and parting it after would undo
## the join.
##
## `asker` is the lead the change came from; a netplay session gets to take the
## decision through it (CompositeCable.netplay_took_bus), as with every lead.
static func settle(tree: SceneTree, exclude: Node = null, asker: CompositeCable = null) -> void:
	var wanted := {}
	var wanted_members := {}
	# Rebuilt from nothing each time, so a lead that has been pulled cannot go on
	# naming a bus it is no longer part of.
	_cable_bus.clear()
	for comp: Dictionary in components(tree, exclude):
		var entries := _entries(comp["machines"])
		if entries.size() < 2:
			continue
		var key := _key(entries)
		wanted[key] = {"entries": entries, "cables": comp["cables"]}
		for entry: Dictionary in entries:
			wanted_members[(entry["libretro"] as Object).get_instance_id()] = true

	for key: String in _buses.keys():
		if wanted.has(key):
			continue
		var bus: Dictionary = _buses[key]
		_buses.erase(key)
		if asker != null and asker.netplay_took_bus([], _as_bus(bus["entries"])):
			continue
		for entry: Dictionary in bus["entries"]:
			if not is_instance_valid(entry.get("libretro")):
				continue
			var lib: Libretro = entry["libretro"]
			if wanted_members.has(lib.get_instance_id()):
				continue
			lib.LinkDisconnect(int(entry.get("port", 0)))
		_log("parted", bus["entries"])

	for key: String in wanted:
		var want: Dictionary = wanted[key]
		for cable: Node in want["cables"]:
			_cable_bus[cable.get_instance_id()] = key
		if _buses.has(key):
			continue
		var entries: Array = want["entries"]
		_buses[key] = {"entries": entries, "powered": _power_of(entries),
			"wait": RESTATE_COOLDOWN, "pending": false}
		if asker != null and asker.netplay_took_bus(_as_bus(entries), []):
			continue
		_connect(entries)
		_log("joined", entries)


## Take the bus this lead is on off the wire entirely -- CompositeCable.rejoin's
## first half, and what a lead leaving the room does before the rest settle.
static func forget(cable: Node) -> void:
	var key: String = _cable_bus.get(cable.get_instance_id(), "")
	_cable_bus.erase(cable.get_instance_id())
	if key.is_empty() or not _buses.has(key):
		return
	var bus: Dictionary = _buses[key]
	_buses.erase(key)
	for entry: Dictionary in bus["entries"]:
		if is_instance_valid(entry.get("libretro")):
			var lib: Libretro = entry["libretro"]
			lib.LinkDisconnect(int(entry.get("port", 0)))
	_log("parted", bus["entries"])


## A cabled bus can stop meaning anything without a plug moving -- PsxLinkCable's
## _watch explains why for a pair, and it is the same for six: switching a console
## off destroys the core the coordinator keyed the wire on, and switching it back
## on attaches a new core to no bus at all. So the edge back ON re-states the
## whole bus, which is also the bus reset the other consoles' drivers need to
## notice it came back.
static func watch(tree: SceneTree) -> void:
	var frame := Engine.get_physics_frames()
	if frame == _watched_frame:
		return
	_watched_frame = frame

	var gone := false
	for key: String in _buses.keys():
		var bus: Dictionary = _buses[key]
		var came_back := false
		for entry: Dictionary in bus["entries"]:
			if not is_instance_valid(entry.get("machine")) or not is_instance_valid(entry.get("libretro")):
				gone = true
				continue
			var machine: Object = entry["machine"]
			var on: bool = bool(machine.get("is_powered_on"))
			var powered: Dictionary = bus["powered"]
			if on and not bool(powered.get(machine.get_instance_id(), true)):
				came_back = true
			powered[machine.get_instance_id()] = on
		# Held over a cooldown rather than dropped: a second console switched on
		# a few frames after the first still has to be re-stated.
		bus["pending"] = bool(bus["pending"]) or came_back
		if int(bus["wait"]) > 0:
			bus["wait"] = int(bus["wait"]) - 1
			continue
		if bool(bus["pending"]):
			bus["pending"] = false
			_connect(bus["entries"])
			bus["wait"] = RESTATE_COOLDOWN
			_log("re-stated", bus["entries"])

	# A console freed out from under a bus: work the room out again without it.
	if gone:
		for key: String in _buses.keys():
			for entry: Dictionary in _buses[key]["entries"]:
				if not is_instance_valid(entry.get("machine")) or not is_instance_valid(entry.get("libretro")):
					_buses.erase(key)
					break
		settle(tree)


# ── helpers ─────────────────────────────────────────────────────────────────

static func _entries(machines: Array) -> Array:
	var out: Array = []
	for machine: Node3D in machines:
		var lib: Libretro = machine.get_libretro_node()
		if lib == null:
			continue
		out.append({"libretro": lib, "machine": machine, "port": 0})
	return out


static func _as_bus(entries: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in entries:
		out.append({"machine": entry["machine"], "port": int(entry["port"])})
	return out


static func _key(entries: Array) -> String:
	var parts := PackedStringArray()
	for entry: Dictionary in entries:
		parts.append("%d:%d" % [(entry["libretro"] as Object).get_instance_id(), int(entry["port"])])
	return ",".join(parts)


static func _power_of(entries: Array) -> Dictionary:
	var out := {}
	for entry: Dictionary in entries:
		var machine: Object = entry["machine"]
		out[machine.get_instance_id()] = bool(machine.get("is_powered_on"))
	return out


static func _connect(entries: Array) -> bool:
	var head: Libretro = entries[0]["libretro"]
	var others: Array = []
	var ports := PackedInt32Array([int(entries[0]["port"])])
	for k in range(1, entries.size()):
		others.append(entries[k]["libretro"])
		ports.append(int(entries[k]["port"]))
	return head.LinkConnectGroup(others, ports)


static func _union(parent: Dictionary, a: int, b: int) -> void:
	var ra := _find(parent, a)
	var rb := _find(parent, b)
	if ra != rb:
		parent[ra] = rb


static func _find(parent: Dictionary, a: int) -> int:
	if not parent.has(a):
		parent[a] = a
	while int(parent[a]) != a:
		parent[a] = parent[parent[a]]
		a = int(parent[a])
	return a


static var _by_stable_key := func(l: Node, r: Node) -> bool:
	return LinkCable.stable_key(l) < LinkCable.stable_key(r)


static func _log(verb: String, entries: Array) -> void:
	# Peer counts come back from the cores rather than from the room, which makes
	# them the one number that tells a cabled bus a core never joined apart from
	# a working one -- see PsxLinkCable._log_ends.
	var parts := PackedStringArray()
	for entry: Dictionary in entries:
		if not is_instance_valid(entry.get("libretro")) or not is_instance_valid(entry.get("machine")):
			continue
		var lib: Libretro = entry["libretro"]
		var machine: Node = entry["machine"]
		parts.append("%s (%d peers)" % [machine.name, lib.LinkPeerCount(int(entry.get("port", 0)))])
	print("[ILinkBus] %s %d console(s): %s" % [verb, entries.size(), ", ".join(parts)])
