## LinkBusSweep — which machines a link cable joins, found from the LEADS.
##
## Lifted out of system.gd, where RetroSystem's NetMachine methods
## (net_link_group, net_link_buses, net_link_bus, net_refresh_link_cables) still
## answer by name and forward here. Static, and keyed on any machine node, so a
## machine that is not a RetroSystem can ask the same question the same way.
class_name LinkBusSweep
extends RefCounted


## Every machine on this one's link bus, ITSELF FIRST, or just itself when
## nothing is cabled to it.
##
## Netplay asks this because a link cable never crosses the network: the bus is
## a process-wide singleton joining two cores in one process, so a cabled pair
## is one session over two machines that every peer replicates, not two players'
## machines talking to each other.
##
## Self first because index 0 anchors the session — it owns the frame clock and
## the savestate. Only the host walks this; every other peer is told the answer,
## so the order has to be stable within one process rather than across them.
static func group_of(machine: Node) -> Array:
	if not machine.is_inside_tree():
		return [machine]
	# A console may have one independent link cable per controller socket (four
	# GameCube-to-GBA leads are the common case).  No single cable's bus contains
	# the other handhelds, so collect every bus that contains this machine.
	return merge(machine, buses_of(machine))


## Every distinct physical cable bus containing this machine. This is also the
## list netplay re-resolves after restarting cores, because StopContent drops
## LinkCoordinator ownership while the plugs themselves never moved.
static func buses_of(machine: Node) -> Array:
	var buses: Array = []
	for cable: Object in cables(machine):
		var bus: Array = cable.linked_machines()
		if has_machine(bus, machine):
			buses.append(bus)
	return buses


static func refresh(machine: Node) -> void:
	for cable: Object in cables(machine):
		if has_machine(cable.linked_machines(), machine) and cable.has_method("rejoin"):
			# Why a rejoin and not a resolve is LinkCable.rejoin()'s to explain.
			cable.call("rejoin")


## Flatten every cable bus reachable from `anchor`.  Kept pure so the rule can
## be tested without constructing sockets and cables: one console with several
## independent controller-port leads still needs every far machine in its
## replicated netplay group.
static func merge(anchor: Object, buses: Array) -> Array:
	var machines: Array = [anchor]
	var changed := true
	while changed:
		changed = false
		for bus: Array in buses:
			var touches := false
			for entry: Dictionary in bus:
				if machines.has(entry.get("machine")):
					touches = true
					break
			if not touches:
				continue
			for entry: Dictionary in bus:
				var machine: Object = entry.get("machine")
				if machine != null and not machines.has(machine):
					machines.append(machine)
					changed = true
	return machines


## The bus this machine is on, as [{machine, port}], or [] when it is on none.
##
## Asked of every LEAD in the room rather than walked out of this machine's own
## sockets, because the three kinds of link cable do not attach the same way and
## two of them cannot be found from here at all. A handheld lead and a
## PlayStation null modem both sit in LinkPorts, but a GameCube-to-GBA lead puts
## its wide end in a CONTROLLER socket — there is no LinkPort on the console
## side to walk out of, and a search from this machine would silently decide a
## cabled GameCube was on no bus.
static func bus_of(machine: Node) -> Array:
	for cable: Object in cables(machine):
		var bus: Array = cable.linked_machines()
		if has_machine(bus, machine):
			return bus
	return []


## Every distinct link cable in the room, in group order.
##
## Swept from the LEADS rather than from this machine's sockets, for the reason
## bus_of() gives above — and it is the pair of GROUPS that is easy to get
## wrong, which is why three methods asking the same question now ask it once. A
## sweep that forgot controller_plug would decide a cabled GameCube was on no
## bus at all, silently, while going on working for the two leads that do sit in
## a LinkPort.
##
## Empty off the tree. A machine can be stopped as its room is torn down, when
## get_tree() is already null — power-off reaches here, not only netplay.
static func cables(machine: Node) -> Array:
	var out: Array = []
	if not machine.is_inside_tree():
		return out
	var tree := machine.get_tree()
	var seen := {}
	for plug in tree.get_nodes_in_group(LinkPlug.ANY_GROUP) \
			+ tree.get_nodes_in_group("controller_plug"):
		var cable: Object = plug.get("cable")
		if not is_instance_valid(cable) or seen.has(cable) \
				or not cable.has_method("linked_machines"):
			continue
		seen[cable] = true
		out.append(cable)
	return out


## True when a linked_machines() list includes `machine`.
static func has_machine(bus: Array, machine: Object) -> bool:
	for entry: Dictionary in bus:
		if entry.get("machine") == machine:
			return true
	return false
