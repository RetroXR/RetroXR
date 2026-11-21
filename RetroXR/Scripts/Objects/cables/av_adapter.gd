## An A/V conversion lead: a plug for one console's A/V OUT, a short cord, and a
## socket of another shape moulded into the far end.
##
## Sega's Conversion Cable (600-6412) is the case. The 32X takes the console's
## picture through its Video Link Cable, a 9-pin mini-DIN at both ends, made for
## the Genesis Model 2. An original Genesis (Model 1) has the larger 8-pin DIN, so
## Sega sold this short lead to go between: its DIN plug in the Model 1's A/V OUT,
## the Video Link Cable's plug in the mini-DIN socket at its other end. It
## conducts and nothing else.
##
## So it is a one-cord CompositeCable, built as PhonesAdapter is: end A is the
## plug, end B the socket's body, a plug that fits nothing and is only ever held
## or let hang. Its socket is an AdapterAvPort, which answers get_device() with
## whatever end A is seated in. Everything the A/V walk does then holds as it
## stands: a lead from that socket is a lead from the console's own A/V OUT, as
## far as AvGraph, AvSource and ExpansionAv can tell.
class_name AvAdapter
extends CompositeCable

## The socket on end B.
@onready var _socket: AdapterAvPort = find_child("AdapterAvPort", true, false) as AdapterAvPort


## What the plug is seated in -- the machine the socket speaks for -- or null while
## it hangs loose.
func host() -> Node3D:
	var plug := _plug_at(0, 0)
	var port: Port = plug.seated_port() if plug != null else null
	return port.get_device() if port != null else null


## The socket on the far end, for a probe or a test.
func socket() -> AdapterAvPort:
	return _socket


## The adapter's own plug moving changes which machine the lead in its socket
## belongs to. That lead holds the routing (and its record of who it last told is
## how a machine left behind hears of it), so it is made to resolve again once this
## one has, as PhonesAdapter does for its jack.
##
## The same for every lead in a phono jack the adapter wears (AdapterRcaPort): a SCART
## block's VIDEO / L / R are the set's while the block is in it, and nobody's once it
## is pulled, which the lead in them only hears of this way.
func _resolve() -> void:
	super._resolve()
	var told: Array = []
	var jacks: Array = find_children("*", "AdapterRcaPort", true, false)
	if is_instance_valid(_socket):
		jacks.append(_socket)
	for jack: Node in jacks:
		var lead_plug := (jack as Port).seated_plug() as RcaPlug
		if lead_plug == null or not is_instance_valid(lead_plug.cable) or lead_plug.cable == self:
			continue
		if told.has(lead_plug.cable):
			continue
		told.append(lead_plug.cable)
		lead_plug.cable.on_plug_seating_changed()
