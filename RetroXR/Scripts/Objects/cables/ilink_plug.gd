## One end of an i.LINK cable -- the 4-pin IEEE 1394 connector a PlayStation 2
## takes.
##
## Its own plug group, so it fits a PlayStation 2's S400 i.LINK socket and an
## i.LINK hub's, and nothing else. Both ends are the same group: 1394 is a bus of
## peers, so either end goes in either console, or in a hub.
##
## Also in LinkPlug.ANY_GROUP, which a PlayStation lead's plug is not. That group
## is what RetroSystem._link_cables() sweeps to find the leads a machine's netplay
## group has to follow, and an i.LINK bus can be six consoles wide through a hub:
## a lead the sweep cannot see would leave five of them out of the session.
class_name ILinkPlug
extends RcaPlug


func _ready() -> void:
	super._ready()
	add_to_group(LinkPlug.ANY_GROUP)


func plug_group() -> String:
	return "ilink_plug"


func plug_label() -> String:
	return "an i.LINK cable plug"
