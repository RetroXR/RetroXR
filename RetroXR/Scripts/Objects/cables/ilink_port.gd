## The S400 i.LINK socket -- the 4-pin IEEE 1394 port on a PlayStation 2, and each
## of the six on an i.LINK hub.
##
## A PlayStation serial socket with a different plug group, which is everything
## PsxLinkPort already is: find the machine that owns the socket, and the core
## inside it. A PlayStation 2 has exactly one of these, so link_port stays 0 --
## the core attaches its i.LINK controller to port 0 and nothing else.
##
## The difference is that this socket can also belong to a HUB, which has no core
## behind it. get_machine() then answers null and get_hub() answers the hub, the
## same split LinkPort draws between a machine's socket and a lead's junction.
## ILinkBus is what walks through a hub; this socket only says which it is.
class_name ILinkPort
extends PsxLinkPort


func _init() -> void:
	connector = "ilink_plug"


## The i.LINK socket on a console, or null. Not find_child("ILinkPort") on its
## own: a modelled shell may carry a MARKER of that name where the socket goes
## (xenu.ps2's does), and being in the model it comes first, so the first match
## by name was a plain Node3D and the socket went unfound.
static func on(console: Node) -> ILinkPort:
	for n: Node in console.find_children("ILinkPort", "", true, false):
		if n is ILinkPort:
			return n as ILinkPort
	return null


## The hub this socket is moulded into, or null on a console.
func get_hub() -> ILinkHub:
	var n: Node = get_parent()
	while n != null:
		if n is ILinkHub:
			return n as ILinkHub
		n = n.get_parent()
	return null
