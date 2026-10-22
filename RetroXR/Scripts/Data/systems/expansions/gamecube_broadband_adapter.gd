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
# its back panel at the end clear of the A/V row. `size` is the real card's
# bounds, 109.3 long x 48.6 across x 22.15 thick (RetroXR-models'
# nintendo/gamecube/network-adapter: the published 109.3 x 45 x 21.6 with its
# latch tabs and labels), in the frame the console models seat it by: X along
# it, seated by its -Y long side, its outer face +Z.
#
# `jack` is where the real card's RJ45 is: in its -X end, 13.5 under the outer
# face, the latch slot toward that face, so on a modelled console a lead goes in
# where the real one does even on the plain box. Its mouth is on the box's end
# face (a plain box draws none of its own, so the socket keeps its recess). On
# the stand-in console the card goes in end-on through the back panel, and there
# the socket is on the end left outside instead (RetroExpansion._place_ethernet_port).
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
	"size": Vector3(0.1093, 0.0486, 0.02215),
	"loader": MediaDimensions.LOADER_NONE,
	"ethernet_port": 4,
	"jack": Transform3D(Basis(Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(-1, 0, 0)),
		Vector3(-0.1093 * 0.5 - 0.0015, 0.0, 0.010675 - 0.0135)),
}


const BOOT := {}
