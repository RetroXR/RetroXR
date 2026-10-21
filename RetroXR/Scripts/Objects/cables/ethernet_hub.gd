## An eight-port Ethernet hub: a small box a player carries, eight RJ45 sockets
## along its front, and nothing else.
##
## ILinkHub's reason for being nothing more: a hub is a repeater. It has no core,
## no game counts it, and it decides nothing, so this object holds eight
## EthernetPorts in one place and moves them together; EthernetBus walks through
## it. Eight because Mario Kart: Double Dash!! takes eight GameCubes on one LAN,
## the most of anything here (Gran Turismo 4 takes six PlayStation 2s). Two hubs
## joined by a lead make one LAN, as real ones do.
##
## Unpowered, which a real one is not, for ILinkHub's reason: a hub dark until a
## player found its mains brick would be a hub that looks broken.
class_name EthernetHub
extends XRToolsPickable

const PORT_COUNT := 8

## The plug each socket is holding, so a release can undo the collision exception
## its seating made.
var _held: Dictionary = {}


func _ready() -> void:
	super._ready()
	add_to_group("spawned")
	for port in sockets():
		port.has_picked_up.connect(_on_seated.bind(port))
		port.has_dropped.connect(_on_pulled.bind(port))


## The eight sockets, in order along the front.
func sockets() -> Array[EthernetPort]:
	var out: Array[EthernetPort] = []
	for n in get_children():
		if n is EthernetPort:
			out.append(n as EthernetPort)
	return out


## So RcaPort.get_device() finds an owner for these sockets, which is what a save
## records a seated plug against. Nothing about picture or sound passes here.
func on_av_topology_changed(_links: Array) -> void:
	pass


func _on_seated(what: Node, port: EthernetPort) -> void:
	var body := what as PhysicsBody3D
	if body == null:
		return
	add_collision_exception_with(body)
	_held[port] = body


func _on_pulled(port: EthernetPort) -> void:
	var held: Variant = _held.get(port)
	_held.erase(port)
	if is_instance_valid(held):
		remove_collision_exception_with(held as PhysicsBody3D)


## Bin the hub and let go of every plug in it first, for ILinkHub's reason.
func drop_and_free() -> void:
	for port in sockets():
		if port.picked_up_object != null:
			port.drop_object()
	Vanish.free_node(self)
