## A link adapter: one plug, with a socket for another lead moulded into its back.
##
## Nintendo's DMG-14 is the case. The Pocket, the Color and the Advance shrank the
## Game Boy's link connector and kept its pins, so a small lead -- a Color's, or
## the one from a Game Boy Printer -- reaches an original Game Boy by plugging into
## this and this plugging in there. It conducts and nothing else: no core, no cord.
##
## So it is a LinkCable with a CAPTIVE end A (CompositeCable._plug_at) and no
## rope, and its socket is that lead's junction. Everything the junction walk
## already does then holds as it stands: a lead seated in the adapter follows it
## to whatever the adapter is seated in, the adapter is the head of the wire (it
## hangs off nothing, the lead in it hangs off it), and saves and netplay name a
## plug in its socket by the cable it belongs to, as they do a junction's.
class_name LinkAdapter
extends LinkCable


## The socket on the back of the plug, rather than one riding a cord.
func junction_port() -> LinkPort:
	return get_node_or_null("PlugB0/LinkPort") as LinkPort
