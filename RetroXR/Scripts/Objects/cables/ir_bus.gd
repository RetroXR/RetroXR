## Which infrared windows in the room are a pair, and keeping LinkCoordinator
## agreeing.
##
## Two machines are linked while each one's window is inside the other's beam:
## within reach, each no further off the other's axis than the beam is wide,
## and with nothing between them. Both ways round, because infrared is a lamp
## and an eye behind the same window, and a unit that can be seen by one that
## it cannot see is half a conversation. So it is NOT "the two beams overlap":
## two units side by side looking the same way throw beams that overlap for
## ever and can see nothing of each other.
##
## One static resolver for the room rather than per-window state, for
## ILinkBus's reason: who a window is paired with depends on every other
## window (the NEAREST partner wins, and a window has one), so no window can
## decide it alone.
##
## The numbers are the room's and not the hardware's. A real Game Boy Color
## wants its partner a hand's width away and nearly dead ahead; held in two
## hands at arm's length, in a headset, that is a fiddle nobody could see the
## reason for.
##
## The core side is the Game Boy Color's RP register (docs/dev/gb-link.md):
## both forks put it on link port 1, `gbc-ir-1`, and a machine whose link cable
## carries a peer is DEAF on it, because a machine waits on one bus. So a
## cabled machine is left out of the pairing here rather than joined to a bus
## it would not listen to.
class_name IrBus
extends RefCounted

## Every IrPort is in this group.
const PORT_GROUP := "ir_port"

## How far apart two windows may be to link, and to stay linked. Further to
## stay than to start, so a pair held at the edge does not chatter.
const LINK_RANGE := 0.60
const UNLINK_RANGE := 0.80

## How far off a window's axis its partner may be, in degrees, to link and to
## stay linked. Half the beam: 60 is a cone 120 across.
const LINK_ANGLE := 60.0
const UNLINK_ANGLE := 70.0

## Physics ticks between looks: ten a second at the room's 90.
const LOOK_TICKS := 9

## Looks in a row a pair must be in view before it links, and out of view
## before it parts: a third of a second each. Every change is a bus rebuild in
## the cores and, in a netplay session, an operation the host schedules, so a
## window swept past another must not make one, nor a hand passing between.
const LINK_DWELL := 3
const UNLINK_DWELL := 3

## What can stand in the way: the room (layer 1) and loose objects (layer 3).
## Not hands, nor the player's own body, nor the two machines themselves --
## and not anything that is HELD, in a hand or in a socket, because picking a
## thing up moves it to layer 17 (XRToolsPickable.picked_up_layer). That is
## what keeps a unit's own cartridge, standing 18 mm out of the same edge as
## its window, from hiding a partner off toward the back of the shell. Adding
## layer 17 here means dealing with that cartridge first.
const SIGHT_MASK := (1 << 0) | (1 << 2)

## The link cable's port, whose peers make a machine deaf to infrared.
const CABLE_PORT := 0

## Test seam, as CompositeCable.netplay_manager_override. Runtime uses the
## NetworkManager autoload.
static var netplay_manager_override: Object = null

## How many times a pair has been handed to LinkConnectGroup. Only for tests
## to count bus rebuilds by.
static var joins := 0

## The pairs joined right now: key -> {ports, entries, lost, gate, claimed}.
## `ports` is the two windows, head first; `entries` is
## [{libretro, machine, port}] in the same order, the order handed to
## ConnectGroup; `lost` counts the looks it has been out of view.
static var _pairs: Dictionary = {}

## Pairs in view that have not held long enough yet: key -> looks so far.
static var _pending: Dictionary = {}

static var _watched_tick := -1


# ── what a window can see ────────────────────────────────────────────────────

## Whether two windows at these transforms are inside each other's beams.
## Pure, so the rule can be checked without a room.
static func in_view(a: Transform3D, b: Transform3D, reach: float, half_angle: float) -> bool:
	var to := b.origin - a.origin
	var distance := to.length()
	if distance > reach:
		return false
	if distance < 0.001:
		return true
	var along := to / distance
	var least := cos(deg_to_rad(half_angle))
	return (-a.basis.z).normalized().dot(along) >= least \
		and (-b.basis.z).normalized().dot(-along) >= least


## Whether nothing stands between two windows.
static func sight_clear(a: IrPort, b: IrPort) -> bool:
	var world := a.get_world_3d()
	if world == null or world.direct_space_state == null:
		return true
	var query := PhysicsRayQueryParameters3D.create(
		a.global_position, b.global_position, SIGHT_MASK)
	# A window is set into its own shell, and the line ends inside the other.
	query.exclude = _bodies(a) + _bodies(b)
	# A window pushed into a wall is behind it.
	query.hit_from_inside = true
	return world.direct_space_state.intersect_ray(query).is_empty()


# ── keeping the coordinator in step ─────────────────────────────────────────

## Every window calls this each physics tick; the first one on a look's tick
## does the looking.
static func watch(tree: SceneTree) -> void:
	var tick := Engine.get_physics_frames()
	if tick == _watched_tick or tick % LOOK_TICKS != 0:
		return
	_watched_tick = tick
	look(tree)


## Look at the whole room once: part the pairs that have lost each other, link
## the nearest pairs that have found each other, and light the windows of the
## ones whose cores are really talking.
static func look(tree: SceneTree) -> void:
	if tree == null:
		return
	var ports := _ports(tree)
	if ports.is_empty() and _pairs.is_empty():
		return
	var free := {}
	for port: IrPort in ports:
		if _can_link(port):
			free[port] = true

	for key: String in _pairs.keys():
		var pair: Dictionary = _pairs[key]
		var a: Variant = (pair["ports"] as Array)[0]
		var b: Variant = (pair["ports"] as Array)[1]
		# A machine switched off, cabled, or gone: nothing to wait out.
		if not is_instance_valid(a) or not is_instance_valid(b) \
				or not free.has(a) or not free.has(b):
			_part(key)
			continue
		if in_view((a as IrPort).global_transform, (b as IrPort).global_transform,
				UNLINK_RANGE, UNLINK_ANGLE) and sight_clear(a, b):
			pair["lost"] = 0
		else:
			pair["lost"] = int(pair["lost"]) + 1
			if int(pair["lost"]) >= UNLINK_DWELL:
				_part(key)
				continue
		free.erase(a)
		free.erase(b)

	var found: Array = []
	var open: Array = free.keys()
	for i in range(open.size()):
		for j in range(i + 1, open.size()):
			var a: IrPort = open[i]
			var b: IrPort = open[j]
			if a.ir_family != b.ir_family or a.get_machine() == b.get_machine():
				continue
			if not in_view(a.global_transform, b.global_transform, LINK_RANGE, LINK_ANGLE):
				continue
			found.append({"a": a, "b": b, "key": _key(a, b), "name": _name(a, b),
				"distance": a.global_position.distance_to(b.global_position)})
	# Nearest first, so a window between two others takes the closer one; the
	# name settles a tie the same way on every peer.
	found.sort_custom(func(l: Dictionary, r: Dictionary) -> bool:
		if not is_equal_approx(float(l["distance"]), float(r["distance"])):
			return float(l["distance"]) < float(r["distance"])
		return str(l["name"]) < str(r["name"]))

	var waiting := {}
	for candidate: Dictionary in found:
		var a: IrPort = candidate["a"]
		var b: IrPort = candidate["b"]
		if not free.has(a) or not free.has(b) or not sight_clear(a, b):
			continue
		free.erase(a)
		free.erase(b)
		var key: String = candidate["key"]
		var looks := mini(int(_pending.get(key, 0)) + 1, LINK_DWELL)
		if looks < LINK_DWELL or not _join(a, b):
			waiting[key] = looks
	_pending = waiting

	for port: IrPort in ports:
		port.set_live(_live(port))


## CompositeCable.rejoin for a window: its machine's core has been stopped and
## started, which took it off the bus without anything in the room moving.
static func rejoin(port: IrPort) -> void:
	var key := _key_of(port)
	if key.is_empty():
		return
	var pair: Dictionary = _pairs[key]
	_pairs.erase(key)
	# At once and here, whatever a session thinks: the core that was on this
	# bus is gone, and the wire with it.
	_disconnect(pair["entries"])
	var a: Variant = (pair["ports"] as Array)[0]
	var b: Variant = (pair["ports"] as Array)[1]
	if not is_instance_valid(a) or not is_instance_valid(b) \
			or not _can_link(a) or not _can_link(b):
		return
	if not _join(a, b):
		# Held for a session that is still starting; the next look that may,
		# joins it.
		_pending[key] = LINK_DWELL


## A window leaving the room takes its pair with it.
static func port_left(port: IrPort) -> void:
	var key := _key_of(port)
	if not key.is_empty():
		_part(key)


## The window this one is paired with, or null.
static func partner_of(port: IrPort) -> IrPort:
	var key := _key_of(port)
	if key.is_empty():
		return null
	for other: Variant in _pairs[key]["ports"]:
		if is_instance_valid(other) and other != port:
			return other as IrPort
	return null


## The window that speaks for this one's pair to a sweep of leads: the head of
## the pair, or the window itself when it has no partner.
static func head_of(port: IrPort) -> IrPort:
	var key := _key_of(port)
	if key.is_empty():
		return port
	var head: Variant = (_pairs[key]["ports"] as Array)[0]
	return head as IrPort if is_instance_valid(head) else port


## The bus this window is on, as [{machine, port}], head first -- the shape
## every link lead's linked_machines() answers in. Empty for a window alone.
static func bus_of(port: IrPort) -> Array[Dictionary]:
	var key := _key_of(port)
	if key.is_empty():
		return []
	return _as_bus(_pairs[key]["entries"])


## Forget every pair without touching a core. For tests, which share one
## process and must each start from an empty room.
static func reset() -> void:
	_pairs.clear()
	_pending.clear()
	_watched_tick = -1
	joins = 0
	netplay_manager_override = null


# ── helpers ─────────────────────────────────────────────────────────────────

static func _join(a: IrPort, b: IrPort) -> bool:
	var ports: Array = [a, b]
	# The head by a name every peer agrees on: it takes bus index 0, and a
	# session's operation names the machines in this order.
	if LinkCable.stable_key(b.get_machine()) < LinkCable.stable_key(a.get_machine()):
		ports = [b, a]
	var entries: Array = []
	for port: IrPort in ports:
		entries.append({"libretro": port.get_libretro(), "machine": port.get_machine(),
			"port": port.link_port})

	var manager := _manager()
	# A session that is still starting these machines: every peer works sight
	# out from where IT has them, so this is not the same act on any two of
	# them, and a wire one peer has at frame zero and another has not is a
	# fork. It waits, and the host schedules it once frames are running.
	if manager.has_method("netplay_prepares"):
		for entry: Dictionary in entries:
			if manager.netplay_prepares(entry["machine"]):
				return false

	var gate := NetplayLinkGate.new()
	gate.manager_override = netplay_manager_override
	var claimed := gate.took_bus(_as_bus(entries), [])
	if not claimed:
		_connect(entries)
	_pairs[_key(a, b)] = {"ports": ports, "entries": entries, "lost": 0,
		"gate": gate, "claimed": claimed}
	_log("left to the netplay session" if claimed else "linked", entries)
	return true


static func _part(key: String) -> void:
	var pair: Dictionary = _pairs[key]
	_pairs.erase(key)
	var held := _as_bus(pair["entries"])
	if not held.is_empty() and (pair["gate"] as NetplayLinkGate).took_bus([], held):
		_log("parting left to the netplay session", pair["entries"])
		return
	_disconnect(pair["entries"])
	_log("parted", pair["entries"])


static func _connect(entries: Array) -> bool:
	var head: Libretro = entries[0]["libretro"]
	var other: Libretro = entries[1]["libretro"]
	joins += 1
	return head.LinkConnectGroup([other],
		PackedInt32Array([int(entries[0]["port"]), int(entries[1]["port"])]))


static func _disconnect(entries: Array) -> void:
	for entry: Dictionary in entries:
		# Checked BEFORE binding, as ILinkBus does: a pair outlives the
		# machines on it for as long as a teardown takes.
		if is_instance_valid(entry.get("libretro")):
			var lib: Libretro = entry["libretro"]
			lib.LinkDisconnect(int(entry.get("port", 1)))


## A window that could be given a partner: on a machine that is switched on,
## whose link cable has nobody on it.
static func _can_link(port: IrPort) -> bool:
	var machine := port.get_machine()
	if machine == null or not bool(machine.get("is_powered_on")):
		return false
	var lib := port.get_libretro()
	if lib == null:
		return false
	return lib.LinkPeerCount(CABLE_PORT) < 2


## Whether this window's pair is on the bus at both ends. Asked of the cores
## rather than of the room: LinkCoordinator is the authority on whether another
## running endpoint is present, and it is the one number that tells a pair in
## view from a pair that can talk.
static func _live(port: IrPort) -> bool:
	var key := _key_of(port)
	if key.is_empty():
		return false
	for entry: Dictionary in _pairs[key]["entries"]:
		if not is_instance_valid(entry.get("libretro")):
			return false
		var lib: Libretro = entry["libretro"]
		if lib.LinkPeerCount(int(entry["port"])) < 2:
			return false
	return true


static func _ports(tree: SceneTree) -> Array[IrPort]:
	var out: Array[IrPort] = []
	for node: Node in tree.get_nodes_in_group(PORT_GROUP):
		var port := node as IrPort
		if port != null and port.is_inside_tree() and not port.is_queued_for_deletion():
			out.append(port)
	return out


static func _key_of(port: IrPort) -> String:
	for key: String in _pairs:
		if (_pairs[key]["ports"] as Array).has(port):
			return key
	return ""


static func _key(a: IrPort, b: IrPort) -> String:
	var ia := a.get_instance_id()
	var ib := b.get_instance_id()
	return "%d~%d" % [mini(ia, ib), maxi(ia, ib)]


static func _name(a: IrPort, b: IrPort) -> String:
	var ka := LinkCable.stable_key(a.get_machine())
	var kb := LinkCable.stable_key(b.get_machine())
	return ka + "~" + kb if ka < kb else kb + "~" + ka


static func _as_bus(entries: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in entries:
		if is_instance_valid(entry.get("machine")):
			out.append({"machine": entry["machine"], "port": int(entry["port"])})
	return out


## The bodies a window is part of, which its own sight line passes through.
static func _bodies(port: IrPort) -> Array[RID]:
	var out: Array[RID] = []
	var n: Node = port.get_parent()
	while n != null:
		var body := n as CollisionObject3D
		if body != null:
			out.append(body.get_rid())
		n = n.get_parent()
	return out


static func _manager() -> Object:
	return netplay_manager_override if netplay_manager_override != null else NetworkManager


static func _log(verb: String, entries: Array) -> void:
	# Peer counts come back from the cores rather than from the room, which
	# makes them the one number that tells a pair in view of each other apart
	# from a pair that can talk -- see PsxLinkCable._log_ends. Zero means that
	# core has no infrared port on the bus: a game that is not a Game Boy Color
	# one, or a core that does not carry the port at all.
	var parts := PackedStringArray()
	for entry: Dictionary in entries:
		if not is_instance_valid(entry.get("libretro")) or not is_instance_valid(entry.get("machine")):
			continue
		var lib: Libretro = entry["libretro"]
		var machine: Node = entry["machine"]
		parts.append("%s (%d peers)" % [machine.name, lib.LinkPeerCount(int(entry.get("port", 1)))])
	print("[IrBus] %s: %s" % [verb, ", ".join(parts) if parts.size() > 0 else "nothing"])
