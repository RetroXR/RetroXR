## A phono socket on an adapter that plugs into a machine: the RCA analogue of
## AdapterAvPort.
##
## Nintendo's RF Modulator (NUS-003, RfModulator) is the case: a block that goes
## straight onto the console's MULTI OUT and wears an RCA "RF OUT" jack on its far
## end, which the RF switch's console lead goes into. That jack belongs to the
## machine the block is plugged into, not to the block: get_device() is the
## adapter's host, so a lead from here routes that machine's picture and sound, and
## null while the adapter hangs loose, so it routes nothing.
##
## Saved under the adapter (save_owner, read by CompositeCable._seat_of): the
## machine has no socket of this name, and the adapter may be in another one next
## load.
##
## The adapter is the first CompositeCable above this socket that answers host(),
## so any one-plug adapter can wear one (AvAdapter answers it too).
class_name AdapterRcaPort
extends RcaPort


func _adapter() -> CompositeCable:
	var n: Node = get_parent()
	while n != null:
		if n is CompositeCable and n.has_method("host"):
			return n as CompositeCable
		n = n.get_parent()
	return null


func get_device() -> Node3D:
	var adapter := _adapter()
	return adapter.call("host") as Node3D if adapter != null else null


func save_owner() -> Node3D:
	return _adapter()
