## MachineLookup -- which machine a node belongs to.
##
## A "machine" is anything running a core: it answers get_libretro_node(). That is
## duck-typed on purpose, not `is RetroSystem`: a VMU, the Game Boy Printer and a
## mod's own device keep a Libretro of their own without being a console.
##
## Every port and bus that wants "the thing behind this socket" asks here, so the
## walk up the tree is written once. A socket moulded into an expansion CARD (the
## Broadband Adapter's RJ45) belongs to the console the card is seated in rather
## than to the card itself, and asks for that hop with `through_expansion`.
class_name MachineLookup
extends RefCounted


## Does this node run a core of its own?
static func is_machine(node: Object) -> bool:
	return node != null and node.has_method("get_libretro_node")


## The machine `from` is, or is inside: `from` itself first, then each parent.
## With `through_expansion`, the first RetroExpansion met on the way answers with
## the console it is seated on (null while it lies loose), and the walk stops there.
static func owning_machine(from: Node, through_expansion := false) -> Node:
	var n := from
	while n != null:
		if is_machine(n):
			return n
		if through_expansion and n is RetroExpansion:
			return (n as RetroExpansion).get_host()
		n = n.get_parent()
	return null


## The Libretro node of a machine, or null for anything else.
static func libretro_of(machine: Object) -> Libretro:
	if not is_machine(machine):
		return null
	return machine.call("get_libretro_node") as Libretro
