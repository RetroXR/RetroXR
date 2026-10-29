## A headphone adapter: a plug for a handheld's accessory socket, a short cord,
## and a 3.5 mm jack moulded into the far end.
##
## Nintendo's for the Game Boy Advance SP is the case. The SP has no headphone
## jack; its sound leaves through EXT.2, the socket the AC adapter charges it by,
## and this is what turns that back into a jack. It conducts and nothing else.
##
## So it is a one-cord CompositeCable whose end A is the accessory plug and whose
## end B is the jack's body, a plug that fits nothing and is only ever held or let
## hang. Its socket is an AdapterJack, which answers get_device() with whatever
## end A is seated in. Everything the A/V walk does then holds as it stands: a
## 3.5 mm lead from the jack to a pair of speakers is a lead from the SP's own
## jack, as far as AvGraph, AvSource and SystemAvPorts can tell.
class_name PhonesAdapter
extends CompositeCable

## The jack's socket, on end B.
@onready var _jack: AdapterJack = find_child("AdapterJack", true, false) as AdapterJack


## What the accessory plug is seated in -- the machine the jack speaks for -- or
## null while it hangs loose.
func host() -> Node3D:
	var plug := _plug_at(0, 0)
	var port: Port = plug.seated_port() if plug != null else null
	return port.get_device() if port != null else null


## The socket on the jack end, for a probe or a test.
func jack() -> AdapterJack:
	return _jack


## The adapter's own plug moving changes which machine the lead in its jack
## belongs to. That lead is the one that has to say so -- it holds the routing,
## and its record of who it last told is how the machine left behind hears about
## it -- so it is made to resolve again once this one has.
func _resolve() -> void:
	super._resolve()
	if not is_instance_valid(_jack):
		return
	var lead_plug := _jack.seated_plug() as RcaPlug
	if lead_plug != null and is_instance_valid(lead_plug.cable) and lead_plug.cable != self:
		lead_plug.cable.on_plug_seating_changed()
