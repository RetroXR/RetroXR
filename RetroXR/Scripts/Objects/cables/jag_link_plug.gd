## One end of a JagLink cable.
##
## Its own plug group, so it fits a Jaguar's DSP port and nothing else. Both
## ends are the same group: the lead crosses each UART's TX to the other's RX,
## so either end goes in either Jaguar.
class_name JagLinkPlug
extends RcaPlug


func plug_group() -> String:
	return "jag_link_plug"


func plug_label() -> String:
	return "a JagLink cable plug"
