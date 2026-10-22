## Which consoles share an Ethernet LAN, and keeping LinkCoordinator agreeing.
##
## ILinkBus's job for a different wire, and the same answer: a hub joins
## everything plugged into it, a lead between two hubs joins both, and a lead
## straight from one adapter to another is the two-console case. So the LAN a
## console is on is the connected set of consoles, walking through every hub and
## every lead, worked out for the whole room at once. See ILinkBus for why that
## is one static resolver rather than per-lead state; everything here follows it.
##
## What differs is the far end. Both cores speak protocol "ethernet" -- one
## message is one Ethernet frame, broadcast to the bus as a hub repeats it -- but
## each attaches its own link port: the PS2 fork's network adapter on 1 (beside
## i.LINK's 0), Dolphin's broadband adapter on 4 (beside the four controller
## sockets). So an entry carries the port of the socket the walk found, and a
## GameCube and a PlayStation 2 can share one hub, as they could on a real one;
## they simply hear each other's broadcasts.
##
## Unlike i.LINK, joining a LAN resets nothing a game sees: a cable going in is
## frames starting to arrive. The re-statement after a console switches back on
## is still needed, for ILinkBus.watch's reason -- the coordinator keyed the wire
## on a core that no longer exists.
class_name EthernetBus
extends RefCounted

## Every EthernetCable is in this group; the sweep reads it rather than the plugs.
const CABLE_GROUP := "ethernet_cable"

const RESTATE_COOLDOWN := 20

## ILinkBus's bookkeeping, kept apart from it: a settle of one wire must never
## part the other's buses.
static var _buses: Dictionary = {}
static var _cable_bus: Dictionary = {}
static var _watched_frame := -1
static var _rejoined: Dictionary = {}

## How many times a LAN has been handed to ConnectGroup. Only for tests.
static var joins := 0


# ── the walk ─────────────────────────────────────────────────────────────────

## What one end of a lead is plugged into -- {node, port} where node is the
## console (its adapter's or its own socket) or a hub -- or {} for a loose end.
static func end_of(cable: CompositeCable, e: int) -> Dictionary:
	var plugs: Array = cable._end_plugs(e)
	if plugs.is_empty():
		return {}
	var plug := plugs[0] as RcaPlug
	if plug == null:
		return {}
	var port := plug.seated_port() as EthernetPort
	if port == null:
		return {}
	var machine := port.get_machine()
	if machine != null:
		return {"node": machine, "port": port.link_port}
	var hub := port.get_hub()
	if hub != null:
		return {"node": hub, "port": -1}
	return {}


## Every connected set in the room, as [{machines, ports, cables}] -- `ports`
## maps a console's instance id to its Ethernet link port -- each list in
## LinkCable.stable_key order so every netplay peer names the same bus head.
static func components(tree: SceneTree, exclude: Node = null) -> Array:
	var out: Array = []
	if tree == null:
		return out
	var parent := {}
	var nodes := {}
	var ports := {}
	var edges: Array = []
	for n: Node in tree.get_nodes_in_group(CABLE_GROUP):
		if n == exclude or not is_instance_valid(n) or n.is_queued_for_deletion():
			continue
		var cable := n as CompositeCable
		if cable == null:
			continue
		var a := end_of(cable, CompositeCable.End.A)
		var b := end_of(cable, CompositeCable.End.B)
		if a.is_empty() or b.is_empty():
			continue
		for end: Dictionary in [a, b]:
			var node: Node3D = end["node"]
			nodes[node.get_instance_id()] = node
			if int(end["port"]) >= 0:
				ports[node.get_instance_id()] = int(end["port"])
		var ida := (a["node"] as Object).get_instance_id()
		_union(parent, ida, (b["node"] as Object).get_instance_id())
		edges.append({"cable": cable, "root": ida})

	var by_root := {}
	for id: int in nodes:
		var root := _find(parent, id)
		if not by_root.has(root):
			by_root[root] = {"machines": [], "ports": {}, "cables": []}
		var node: Node3D = nodes[id]
		if node.has_method("get_libretro_node"):
			(by_root[root]["machines"] as Array).append(node)
			(by_root[root]["ports"] as Dictionary)[id] = int(ports.get(id, 0))
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


static func component_of(tree: SceneTree, cable: Node) -> Dictionary:
	for comp: Dictionary in components(tree):
		if (comp["cables"] as Array).has(cable):
			return comp
	return {}


## The LAN this lead is part of, as [{machine, port}]. Empty below two consoles.
static func bus_of(tree: SceneTree, cable: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var comp := component_of(tree, cable)
	if comp.is_empty() or (comp["machines"] as Array).size() < 2:
		return out
	for machine: Node3D in comp["machines"]:
		out.append({"machine": machine,
			"port": int((comp["ports"] as Dictionary).get(machine.get_instance_id(), 0))})
	return out


## The LAN this lead was last joined into, in the same shape, for a pull.
static func held_for(cable: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var key: String = _cable_bus.get(cable.get_instance_id(), "")
	if key.is_empty() or not _buses.has(key):
		return out
	for entry: Dictionary in _buses[key]["entries"]:
		if is_instance_valid(entry.get("machine")):
			out.append({"machine": entry["machine"], "port": int(entry.get("port", 0))})
	return out


# ── keeping the coordinator in step ─────────────────────────────────────────

## Work the whole room out again and make LinkCoordinator match it -- ILinkBus
## .settle, step for step: stale LANs parted first and only their orphans, new
## ones joined, a netplay session given the decision through `asker`.
static func settle(tree: SceneTree, exclude: Node = null, asker: CompositeCable = null) -> void:
	var wanted := {}
	var wanted_members := {}
	_cable_bus.clear()
	for comp: Dictionary in components(tree, exclude):
		var entries := _entries(comp["machines"], comp["ports"])
		if entries.size() < 2:
			continue
		var key := _key(entries)
		wanted[key] = {"entries": entries, "cables": comp["cables"]}
		for entry: Dictionary in entries:
			wanted_members[_member_key(entry)] = true

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
			if wanted_members.has(_member_key(entry)):
				continue
			var lib: Libretro = entry["libretro"]
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


## Take the LAN this lead is on off the wire entirely.
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


## CompositeCable.rejoin for an Ethernet lead, once per LAN per frame however
## many of its spokes ask.
static func rejoin(cable: CompositeCable) -> void:
	var frame := Engine.get_process_frames()
	var key: String = _cable_bus.get(cable.get_instance_id(), "")
	if not key.is_empty() and int(_rejoined.get(key, -1)) == frame:
		return
	forget(cable)
	if cable.is_inside_tree():
		settle(cable.get_tree(), null, cable)
	var now: String = _cable_bus.get(cable.get_instance_id(), "")
	for k: String in [key, now]:
		if not k.is_empty():
			_rejoined[k] = frame


## ILinkBus.watch: a console switching back on re-states its LAN once its core
## has had time to start, and a console freed out from under one re-settles the
## room without it.
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
		bus["pending"] = bool(bus["pending"]) or came_back
		if int(bus["wait"]) > 0:
			bus["wait"] = int(bus["wait"]) - 1
			continue
		if bool(bus["pending"]):
			bus["pending"] = false
			_connect(bus["entries"])
			bus["wait"] = RESTATE_COOLDOWN
			_log("re-stated", bus["entries"])

	if gone:
		for key: String in _buses.keys():
			for entry: Dictionary in _buses[key]["entries"]:
				if not is_instance_valid(entry.get("machine")) or not is_instance_valid(entry.get("libretro")):
					_buses.erase(key)
					break
		settle(tree)


# ── helpers ─────────────────────────────────────────────────────────────────

static func _entries(machines: Array, ports: Dictionary) -> Array:
	var out: Array = []
	for machine: Node3D in machines:
		var lib: Libretro = machine.get_libretro_node()
		if lib == null:
			continue
		out.append({"libretro": lib, "machine": machine,
			"port": int(ports.get(machine.get_instance_id(), 0))})
	return out


static func _as_bus(entries: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in entries:
		out.append({"machine": entry["machine"], "port": int(entry["port"])})
	return out


static func _member_key(entry: Dictionary) -> String:
	return "%d:%d" % [(entry["libretro"] as Object).get_instance_id(), int(entry["port"])]


static func _key(entries: Array) -> String:
	var parts := PackedStringArray()
	for entry: Dictionary in entries:
		parts.append(_member_key(entry))
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
	joins += 1
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
	# Peer counts come back from the cores, which is what tells a cabled LAN a
	# core never joined (its adapter off, or a core without the cable) apart from
	# a working one -- see PsxLinkCable._log_ends.
	var parts := PackedStringArray()
	for entry: Dictionary in entries:
		if not is_instance_valid(entry.get("libretro")) or not is_instance_valid(entry.get("machine")):
			continue
		var lib: Libretro = entry["libretro"]
		var machine: Node = entry["machine"]
		parts.append("%s (%d peers)" % [machine.name, lib.LinkPeerCount(int(entry.get("port", 0)))])
	print("[EthernetBus] %s %d console(s): %s" % [verb, entries.size(), ", ".join(parts)])
