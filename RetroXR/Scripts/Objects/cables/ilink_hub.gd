## A six-port i.LINK hub: a small box a player carries, six S400 sockets along its
## back, and nothing else.
##
## A 1394 hub is a repeater. It takes no part in the bus itself -- it has no core,
## it is not a node any game counts, and it decides nothing -- so all this object
## does is hold six ILinkPorts in one place and move them together. Which consoles
## that joins is ILinkBus's to work out, walking from a lead's end into this hub
## and out through every other lead seated here.
##
## Six because that is the most consoles anything on the PlayStation 2 was
## written to put on one i.LINK bus (Gran Turismo 3's i.LINK Battle). Two hubs
## joined by a lead make one bus, as real ones do; the core takes up to 64 nodes.
##
## Unpowered, which a real one is not -- 1394 hubs need a mains adapter, because
## the PlayStation 2's 4-pin port carries no bus power. Left out on purpose: a hub
## that sat dark until a player found its power brick would be a hub that looks
## broken.
class_name ILinkHub
extends XRToolsPickable

const PORT_COUNT := 6

## The plug each socket is holding, so a release can undo the collision exception
## its seating made -- the snap zone's has_dropped says nothing about what left.
var _held: Dictionary = {}


func _ready() -> void:
	super._ready()
	add_to_group("spawned")
	for port in sockets():
		port.has_picked_up.connect(_on_seated.bind(port))
		port.has_dropped.connect(_on_pulled.bind(port))


## The six sockets, in order along the back.
func sockets() -> Array[ILinkPort]:
	var out: Array[ILinkPort] = []
	for n in get_children():
		if n is ILinkPort:
			out.append(n as ILinkPort)
	return out


## So RcaPort.get_device() finds an owner for these sockets, which is what a save
## records a seated plug against. A no-op for RfSwitch's reason: nothing about
## picture or sound passes through here.
func on_av_topology_changed(_links: Array) -> void:
	pass


## A seated plug's nose sits inside this box, and a seated plug is frozen, so it
## is kinematic: left colliding, it would shove the hub across the table the
## moment it went in. RetroSystem makes the same exception for its own sockets.
func _on_seated(what: Node, port: ILinkPort) -> void:
	var body := what as PhysicsBody3D
	if body == null:
		return
	add_collision_exception_with(body)
	_held[port] = body


func _on_pulled(port: ILinkPort) -> void:
	var held: Variant = _held.get(port)
	_held.erase(port)
	# Checked before it is bound: the plug may have gone with its lead.
	if is_instance_valid(held):
		remove_collision_exception_with(held as PhysicsBody3D)


## Bin the hub and let go of every plug in it first. A socket freed while it holds
## someone else's plug leaves that lead pointing at a dead snap zone.
func drop_and_free() -> void:
	for port in sockets():
		if port.picked_up_object != null:
			port.drop_object()
	Vanish.free_node(self)
