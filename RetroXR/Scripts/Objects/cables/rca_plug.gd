## One plug on a composite lead — the grabbable end of a single cord.
##
## A cord is a WIRE, and this is one of its two ends. It carries no channel of its
## own: what a cord conducts is decided entirely by the two ports its ends sit in,
## which is why the colour here is cosmetic and any plug fits any socket. The
## routing is worked out in CompositeCable._resolve.
##
## Distinct from CablePlug, which is the single captive plug on a console's
## permanently attached lead and knows the host that owns it. This one is owned by
## a cable, not by a device.
class_name RcaPlug
extends XRToolsPickable


## Which cord of the lead this end belongs to. The plug at the same index on the
## other end is the far end of the same wire.
var cord: int = 0

## The lead this plug belongs to.
var cable: Node3D = null

## Where the cord meets this plug, in plug-local space, for the rope's fray anchor.
## The plug's origin is its SEATING reference and sits at the collar, 40 mm forward
## of where the cord actually enters; anchoring there runs the tail out through the
## barrel. Derived from the mesh, as CablePlug does, so reshaping the connector
## cannot silently desync it.
var cable_anchor: Vector3 = Vector3.ZERO


## What this end IS, and the only thing deciding which sockets will take it: a
## socket whose `connector` is the same name. Set on the node in the lead's scene
## ("vga_plug" is what stops a DE-15 hood being pushed into a phono jack); see
## Connectors. Within a connector there is no further filter -- any phono plug
## fits any phono socket, by design, see RcaPort.
@export var connector: String = Connectors.PHONO


## What to call this connector when telling a player where it goes.
##
## The same fact as `connector`, said to a different audience: one names what a
## socket filters on, the other the thing a person is holding. A lead whose two
## ends fit different sockets is unusable without it -- the GameCube lead was
## reached for by the wrong end twice in one evening, and nothing in the room was
## in a position to say so.
func plug_label() -> String:
	return Connectors.label_of(connector)


func _ready() -> void:
	super._ready()
	for group: String in Connectors.groups_of(connector):
		add_to_group(group)
	_derive_cable_anchor()
	picked_up.connect(func(_p: Variant) -> void: PlugAim.aim(self))


func _derive_cable_anchor() -> void:
	var tip := get_node_or_null("PlugTip") as MeshInstance3D
	if tip == null or tip.mesh == null:
		return
	# One rule, stated in PlugExit rather than here as well: an authored CordExit
	# marker if the connector carries one, else the centre of its back face.
	cable_anchor = PlugExit.origin_of(self, tip)


## True while a hand, a laser or a socket owns this plug's pose.
##
## Deliberately not is_picked_up(): the ray grab is a parallel hold mechanism that
## never calls pick_up(), so it reports false for the whole hold — see
## XRToolsFunctionPickup._start_ray_grab_at. Every path that takes a plug freezes
## the body, hand, beam and snap zone alike, so the freeze is the ownership flag.
## Same test HeldObjectPhysics._escape reads, for the same reason.
func is_held() -> bool:
	return freeze


## The socket this plug is currently seated in, or null when it is loose.
##
## Asked of the SOCKETS rather than remembered here, and rather than walked up the
## parent chain: whether a snap zone reparents what it holds is xr-tools' business
## and not something to depend on, while `picked_up_object` is the zone's own
## account of what it has. A plug that is dropped, stolen by another zone or freed
## therefore cannot leave a stale port behind.
func seated_port() -> RcaPort:
	for node in get_tree().get_nodes_in_group(RcaPort.GROUP):
		var port := node as RcaPort
		if port != null and port.seated_plug() == self:
			return port
	return null
