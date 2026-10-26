## An i.LINK cable -- a 4-pin to 4-pin IEEE 1394 lead, what joins two PlayStation 2
## consoles for Gran Turismo 3's i.LINK Battle, Time Crisis II's cooperative mode
## and the handful of other games that took one.
##
## A PlayStation lead's shape -- one cord, the same connector at both ends, either
## end in either console -- so it keeps PsxLinkCable's scene and plug handling.
## What it does not keep is PsxLinkCable's idea that a lead IS a pair. 1394 is a
## bus: an end can go into an i.LINK hub instead of a console, and then this lead
## is one spoke of a bus up to six consoles wide (more, through a second hub).
## Which consoles share a wire is therefore a question about the whole room, and
## every decision here is handed to ILinkBus, which answers it for all the leads
## at once.
class_name ILinkCable
extends PsxLinkCable


func _init() -> void:
	add_to_group(ILinkBus.CABLE_GROUP)


func _resolve() -> void:
	if not is_inside_tree():
		return
	ILinkBus.settle(get_tree(), null, self)
	_report_seating_changes()
	topology_changed.emit()


## The whole bus this lead is part of, hub and all -- not just its two ends.
## RetroSystem merges the buses its leads report into one netplay group, and a
## console at the far side of a hub is on this wire as much as the one at the
## other end of the cord.
func linked_machines() -> Array[Dictionary]:
	if not is_inside_tree():
		return []
	return ILinkBus.bus_of(get_tree(), self)


func held_machines() -> Array[Dictionary]:
	return ILinkBus.held_for(self)


## One rejoin per BUS, not per lead: RetroSystem asks every lead touching a
## console that restarted, and on a hub those are all spokes of the same wire.
func rejoin() -> void:
	ILinkBus.rejoin(self)


## Take this lead's bus off the wire -- what leaving the room does before the
## other leads settle.
func _disconnect() -> void:
	ILinkBus.forget(self)


func _watch() -> void:
	if is_inside_tree():
		ILinkBus.watch(get_tree())


func _exit_tree() -> void:
	# Carried out of the room, or a scene change. The bus goes off the wire, and
	# every other lead works the room out again next frame without this one: a
	# hub with five other consoles on it is still a bus when one spoke leaves.
	ILinkBus.forget(self)
	if not is_inside_tree():
		return
	for other: Node in get_tree().get_nodes_in_group(ILinkBus.CABLE_GROUP):
		if other != self:
			other.call_deferred("_resolve")
			break
