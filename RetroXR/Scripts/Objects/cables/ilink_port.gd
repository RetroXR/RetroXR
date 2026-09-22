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


func plug_group() -> String:
	return "ilink_plug"


## The hub this socket is moulded into, or null on a console.
func get_hub() -> ILinkHub:
	var n: Node = get_parent()
	while n != null:
		if n is ILinkHub:
			return n as ILinkHub
		n = n.get_parent()
	return null
