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
# i.LINK socket (RetroSystemModelDefault.configure_unit_socket). `size` is width
# x depth in x thickness, from the real card's face and the bay it fills.
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
	"size": Vector3(0.095, 0.09, 0.023),
	"loader": MediaDimensions.LOADER_NONE,
	"ethernet_port": 1,
}


const BOOT := {}
