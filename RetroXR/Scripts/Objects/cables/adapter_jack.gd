## The 3.5 mm socket on a PhonesAdapter's far end.
##
## A TrsPort, OUT, that belongs to the machine the adapter is plugged into rather
## than to the adapter: get_device() is the adapter's host, so a lead from here
## routes that machine's sound, and null while the adapter hangs loose, so it
## routes nothing.
##
## A save cannot name it under that machine, though -- the machine has no socket
## of this name, and the adapter may be in another one next load -- so it is saved
## under the adapter (save_owner, read by CompositeCable._seat_of), the way a link
## lead's junction socket is saved under its cable.
class_name AdapterJack
extends TrsPort


func _adapter() -> PhonesAdapter:
	var n: Node = get_parent()
	while n != null:
		if n is PhonesAdapter:
			return n as PhonesAdapter
		n = n.get_parent()
	return null


func get_device() -> Node3D:
	var adapter := _adapter()
	return adapter.host() if adapter != null else null


func save_owner() -> Node3D:
	return _adapter()
