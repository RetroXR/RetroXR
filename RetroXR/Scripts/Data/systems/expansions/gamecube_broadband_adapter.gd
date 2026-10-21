## Broadband Adapter (DOL-015) — the GameCube's 10/100 Ethernet card, in Serial
## Port 1 on the underside of the console.
##
## One of the expansion units; see ExpansionCatalog for how a unit file is
## assembled into the catalog, and expansion_defs.gd for the MOUNT_* values.
extends RefCounted

const ID := "gamecube_broadband_adapter"

# A card that slides into the bay under the console and stays there, its RJ45
# socket on the face left showing at the back. The bay is its own socket
# ("serial_port_1"); a model whose shell has the real opening places it there
# (RetroSystemModel.configure_unit_socket), and the stand-in box takes it through
# its back panel at the end clear of the A/V row. `size` is width x depth in x
# thickness, from the real card's 81 x 55 x 16 mm.
#
# What seating it does is ForcedCoreOptions.ethernet_adapter: SP1 becomes the
# Ethernet Link Cable device, whose socket is the frontend's link bus, protocol
# "ethernet-1" on port 4 (`ethernet_port`), and an EthernetCable from it to a hub
# puts the console on a LAN (EthernetBus). Mario Kart: Double Dash!! shows LAN
# MODE on its title menu only while one is in.
const ROW := {
	"label": "Broadband Adapter",
	"host": "gc",
	"mount": ExpansionDefs.MOUNT_ABOVE,
	"socket": "serial_port_1",
	"size": Vector3(0.081, 0.055, 0.016),
	"loader": MediaDimensions.LOADER_NONE,
	"ethernet_port": 4,
}


const BOOT := {}
