## Network Adapter (SCPH-10281) — the fat PlayStation 2's Ethernet (and modem)
## card, in the expansion bay at the back of the console.
##
## One of the expansion units; see ExpansionCatalog for how a unit file is
## assembled into the catalog, and expansion_defs.gd for the MOUNT_* values.
extends RefCounted

const ID := "ps2_network_adapter"

# A card that slides into the expansion bay and screws in, its RJ45 socket (and
# the modem jack nobody here uses) on the face left showing. The bay is its own
# socket ("expansion_bay"); a model whose shell has the real opening places it
# there, and the stand-in box takes it through its back panel clear of the
# i.LINK socket (RetroSystemModelDefault.configure_unit_socket). `size` is the
# real SCPH-10281's bounds, its front plate 133 x 72.8 with the body behind it
# 33.3 deep in all (RetroXR-models' sony/ps2/network-adapter), in the frame the
# console models seat it by: seated by its -Y face, the plate's bottom edge, the
# plate +Z.
#
# `jack` is where the real card's NETWORK jack is: in the plate, 43.9 right of
# its middle and 18.75 above it, the latch slot up, so on a modelled console a
# lead goes in where the real one does even on the plain box. Its mouth is on the
# box's plate face (a plain box draws none of its own, so the socket keeps its
# recess). On the stand-in console the card goes in end-on through the back
# panel, and there the socket is on the end left outside instead
# (RetroExpansion._place_ethernet_port).
#
# What seating it does is ForcedCoreOptions.ethernet_adapter: the SPEED
# expansion's ethernet is the frontend's link bus, protocol "ethernet-1" on port
# 1 (`ethernet_port`), beside i.LINK's 0, and an EthernetCable from it to a hub
# puts the console on a LAN (EthernetBus) -- Gran Turismo 4's Multi-LAN Race takes
# six. A slim PlayStation 2 has the socket built in and needs no card; that is
# its model's to say (RetroSystemModel.builtin_ethernet_port).
const ROW := {
	"label": "Network Adapter",
	"host": "ps2",
	"mount": ExpansionDefs.MOUNT_ABOVE,
	"socket": "expansion_bay",
	"size": Vector3(0.133, 0.0728, 0.0333),
	"loader": MediaDimensions.LOADER_NONE,
	"ethernet_port": 1,
	"jack": Transform3D(Basis.IDENTITY, Vector3(0.0439, 0.01875, 0.0333 * 0.5 + 0.0015)),
}


const BOOT := {}
