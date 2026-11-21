## An S-Video socket on an adapter that plugs into a machine: the 4-pin mini-DIN
## analogue of AdapterRcaPort.
##
## The original Xbox's Advanced AV Pack is the case: a box on the console's A/V
## lead with an S-VIDEO jack beside its phonos. That jack belongs to the machine
## the pack is plugged into, not to the pack: get_device() is the adapter's host,
## so an S-Video lead from here carries that machine's picture, and null while the
## adapter hangs loose, so it carries nothing.
##
## Always OUT. Saved under the adapter (save_owner), as AdapterRcaPort is.
class_name AdapterSvideoPort
extends SvideoPort

## The picture through this jack, as a TvSignal.Kind (AdapterRcaPort.signal_kind): 1,
## SVIDEO, for an S-Video jack on a block in a set's socket; -1 says nothing.
@export var signal_kind: int = -1


func _ready() -> void:
	super._ready()
	direction = RcaPort.Direction.OUT


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


## The socket the adapter's plug is seated in, or null while it hangs loose
## (AdapterRcaPort.host_socket).
func host_socket() -> Port:
	var adapter := _adapter()
	if adapter == null or not adapter.has_method("_plug_at"):
		return null
	var plug := adapter.call("_plug_at", 0, 0) as RcaPlug
	return plug.seated_port() if plug != null else null


## The socket model show_jack shows or hides: a box whose own model draws the jack
## (an AV pack) turns svideo_port.tscn's SvideoSocket off.
func _jack_node() -> Node3D:
	return get_node_or_null("SvideoSocket") as Node3D
