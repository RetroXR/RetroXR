## An Ethernet cable -- RJ45 at both ends, what joins a GameCube's Broadband
## Adapter or a PlayStation 2's network adapter to a hub, or straight to one
## other console.
##
## ILinkCable's shape on a different wire: one cord, the same connector at both
## ends, either end anywhere, and a lead that is one spoke of a LAN rather than a
## pair in itself. Which consoles share the LAN is a question about the whole
## room, so every decision is handed to EthernetBus.
class_name EthernetCable
extends PsxLinkCable


func _init() -> void:
	add_to_group(EthernetBus.CABLE_GROUP)


func _resolve() -> void:
	if not is_inside_tree():
		return
	EthernetBus.settle(get_tree(), null, self)
	_report_seating_changes()
	topology_changed.emit()


## The whole LAN this lead is part of, hub and all -- what RetroSystem merges
## into one netplay group.
func linked_machines() -> Array[Dictionary]:
	if not is_inside_tree():
		return []
	return EthernetBus.bus_of(get_tree(), self)


func held_machines() -> Array[Dictionary]:
	return EthernetBus.held_for(self)


## One rejoin per LAN, not per lead: on a hub every spoke is asked.
func rejoin() -> void:
	EthernetBus.rejoin(self)


func _disconnect() -> void:
	EthernetBus.forget(self)


func _watch() -> void:
	if is_inside_tree():
		EthernetBus.watch(get_tree())


func _exit_tree() -> void:
	# Carried out of the room: the LAN goes off the wire, and the leads left
	# behind work the room out again without this one.
	EthernetBus.forget(self)
	if not is_inside_tree():
		return
	for other: Node in get_tree().get_nodes_in_group(EthernetBus.CABLE_GROUP):
		if other != self:
			other.call_deferred("_resolve")
			break
