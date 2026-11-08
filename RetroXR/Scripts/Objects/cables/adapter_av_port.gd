## The multi-way A/V socket on an AvAdapter's far end.
##
## A MultiAvPort, OUT, that belongs to the machine the adapter is plugged into
## rather than to the adapter, as AdapterJack does for a headphone adapter's jack:
## get_device() is the adapter's host, so a lead from here routes that machine's
## picture and sound (cord by cord, MultiAvPort.channel_for), and null while the
## adapter hangs loose, so it routes nothing.
##
## Saved under the adapter (save_owner, read by CompositeCable._seat_of): the
## machine has no socket of this name, and the adapter may be in another one next
## load.
class_name AdapterAvPort
extends MultiAvPort


func _adapter() -> AvAdapter:
	var n: Node = get_parent()
	while n != null:
		if n is AvAdapter:
			return n as AvAdapter
		n = n.get_parent()
	return null


func get_device() -> Node3D:
	var adapter := _adapter()
	return adapter.host() if adapter != null else null


func save_owner() -> Node3D:
	return _adapter()
