## One end of a Sega Saturn Link Cable.
##
## Its own plug group, so it fits a Saturn's Communication Connector and nothing
## else -- not a PlayStation's serial socket, which the connector looks nothing
## like and whose wire speaks a different protocol besides. Both ends are the
## same group: the cable crosses each SH-2's TxD to the other console's RxD, so
## either end goes in either Saturn.
class_name SaturnLinkPlug
extends RcaPlug


func plug_group() -> String:
	return "saturn_link_plug"


func plug_label() -> String:
	return "a Saturn link cable plug"
