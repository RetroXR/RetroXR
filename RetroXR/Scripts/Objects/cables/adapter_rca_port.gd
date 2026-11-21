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
##
## It works the other way round too (2026-11-21): a block plugged into a SET's socket
## (Nintendo's SCART adaptor, SNSP-015, in a SCART IN) wears phono jacks that are the
## set's INPUTS, direction IN. TvPanel.input_of_port files them on the input whose
## socket the block is in (host_socket), and `signal_kind` says what the picture
## arriving through them is, whatever that input's own kind.
class_name AdapterRcaPort
extends RcaPort

## The picture through this jack, as a TvSignal.Kind, for a jack on a block in a set's
## socket: a composite cord into a SCART block is composite, not the SCART input's RGB.
## -1 (the default) says nothing, and the input draws as its own kind.
@export var signal_kind: int = -1


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


## The socket the adapter's plug is seated in (a set's ScartIn, a console's MULTI OUT),
## or null while it hangs loose.
func host_socket() -> Port:
	var adapter := _adapter()
	if adapter == null or not adapter.has_method("_plug_at"):
		return null
	var plug := adapter.call("_plug_at", 0, 0) as RcaPlug
	return plug.seated_port() if plug != null else null
