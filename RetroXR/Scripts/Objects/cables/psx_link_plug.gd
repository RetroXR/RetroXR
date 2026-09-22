## One end of a PlayStation link cable.
##
## Its own plug group, and that is the whole class. The room refuses connections
## that could not be made with the real hardware, and a PlayStation's serial
## socket does not take a Game Boy Advance lead: the connectors are nothing
## alike, and the two cables carry different protocols besides.
##
## Reusing "link_plug" would have let a GBA lead seat in a PlayStation's socket
## and looked right doing it. The refusal would still have happened, one layer
## down, where LinkCoordinator declines to join two endpoints whose cores publish
## different protocol ids -- but it would have arrived as a line in a log, with
## the cable sitting there in the room looking connected. A plug that does not
## fit should not go in.
##
## Both ends are the same group, unlike the GameCube lead's. A PlayStation link
## cable is a null modem: transmit crossed to receive, DTR to DSR, RTS to CTS,
## both ways. The two consoles are peers and either end goes in either console,
## which is exactly what one group for both ends means.
class_name PsxLinkPlug
extends RcaPlug


func _ready() -> void:
	super._ready()
	# The sweeps that find a machine's bus (netplay, focus mode) look here.
	add_to_group(LinkPlug.ANY_GROUP)


func plug_group() -> String:
	return "psx_link_plug"


func plug_label() -> String:
	return "a PlayStation link cable plug"
