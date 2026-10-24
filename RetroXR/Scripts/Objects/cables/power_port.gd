## A mains socket: a wall outlet's receptacle, a power strip's, or the inlet on
## an appliance a cord goes into.
##
## A Port, so the connector gate, the seating hooks and Port.ANY_GROUP (which is
## how RcaPlug.seated_port finds it) are the same as every other socket's. What
## is its own is the mains region -- set_connector, when the player changes it --
## and the owner a save names it against (get_device).
class_name PowerPort
extends Port

## Every mains socket in the tree, for the sweeps that want mains alone
## (PowerCord.socket_holding, the region change) rather than any socket at all.
const GROUP := "power_port"


## A North American outlet until the player's region says otherwise; the plate
## and the strip set theirs (set_connector).
func _init() -> void:
	connector = "nema_5_15_plug"


## What an export's scene conversion can undo of _init (Port._own_connector).
func _own_connector() -> String:
	return "nema_5_15_plug"


func _ready() -> void:
	super._ready()
	add_to_group(GROUP)


## Take `to` from now on, letting go of a seated plug that no longer fits.
func set_connector(to: String) -> void:
	connector = to
	if is_inside_tree():
		snap_require = to
		var plug := picked_up_object
		if plug != null and not plug.is_in_group(to):
			drop_object()


## The object a save file names this socket against, which is not the socket's
## own parent.
##
## A slot records a reference either as the id of another saved object or, for
## something that was already standing in the room, as a node path (see
## ScenePersistence._ref). Both need the node the socket can be FOUND under
## again: the wall outlet is furniture and comes back at the same path, while a
## console is spawned fresh every load and only its own root carries an id. The
## node in between, a socket's immediate parent inside a console's model, is
## neither, and naming that would write a path that means nothing next load.
##
## So: the nearest spawned ancestor if the socket belongs to something the save
## owns, else the nearest ancestor at all, which is the fixture case. Not
## Port.get_device's walk, which looks for a device on a lead's signal path: a
## wall outlet is furniture and answers nothing.
func get_device() -> Node3D:
	var at: Node = get_parent()
	var fixture: Node3D = null
	while at != null:
		if at.is_in_group("spawned"):
			return at as Node3D
		if fixture == null:
			fixture = at as Node3D
		at = at.get_parent()
	return fixture
