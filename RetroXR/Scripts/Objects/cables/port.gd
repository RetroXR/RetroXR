## A socket on something in the room: a snap zone that takes one family of plug
## and tells the lead seated in it when that changes.
##
## Everything a socket needs whatever runs down its wire lives here: the
## `connector` gate, membership of ANY_GROUP so a plug can find the socket holding
## it, the seat/pull hooks that tell the plug's cable, and the walk to the device
## that owns it. What a seated lead MEANS is a subclass's business -- an A/V
## channel for RcaPort, two cores sharing a wire for LinkPort, mains for
## PowerPort -- and none of them carries the others' fields.
class_name Port
extends XRToolsSnapZone


## Every socket in the room, of every kind, so a plug can find the one holding it
## (RcaPlug.seated_port) and a probe can shut them all while it moves a plug.
## RcaPort.GROUP and PowerPort.GROUP are the narrower sweeps.
const ANY_GROUP := "port"


## The plug this socket takes -- the other half of RcaPlug.connector, set on the
## node in its scene. A VGA socket and a VGA lead both naming "vga_plug" is what
## keeps a DE-15 hood out of a phono jack and a phono plug out of a DE-15 shell.
## Empty here; every socket class sets its own family in _init.
@export var connector: String = ""


## The family this socket class always takes, for when an export undoes _init.
##
## A subclass sets `connector` in _init, but that is not enough in an exported
## build: converting scenes to binary writes the declared default onto a socket
## that a scene instances inside another scene, over what _init set, and every
## Color, Printer and link socket lost its plug. That default is "" now, and was
## Connectors.PHONO while this lived in RcaPort, so both mean "put it back" --
## except on a phono jack, for which PHONO is its own family.
func _own_connector() -> String:
	return ""


## What to call this socket in the seating log. Its plug's name by default; an
## A/V jack says which channel it carries instead.
func port_label() -> String:
	return Connectors.label_of(connector)


func _ready() -> void:
	super._ready()
	add_to_group(ANY_GROUP)
	var own := _own_connector()
	if not own.is_empty() and (connector.is_empty()
			or (connector == Connectors.PHONO and own != Connectors.PHONO)):
		connector = own
	snap_require = connector
	# The SOCKET announces seating, not the plug. A snap zone's has_picked_up /
	# has_dropped fire whenever the zone's own state changes, while the pickable's
	# `dropped` needs the releasing zone to be the one actually holding the grab —
	# so a plug taken straight out of one socket into another leaves the first
	# socket empty without the plug ever reporting a thing.
	has_picked_up.connect(_on_seated)
	has_dropped.connect(_on_unseated)


func _on_seated(what: Node3D) -> void:
	_last_plug = what
	_log_seating("seated", _last_plug)
	_announce(_last_plug)
	_mains_moved()


func _on_unseated() -> void:
	var plug := _last_plug
	_last_plug = null
	_log_seating("pulled", plug)
	_announce(plug)
	_mains_moved()


## A mains socket or a DC jack took or let go of a plug: whatever runs off it may
## have gained or lost its supply (MainsPower).
func _mains_moved() -> void:
	if (self is PowerPort or self is DcPort) and is_inside_tree():
		MainsPower.changed(get_tree())


## Every connection in the room passes through here, so this is the one place
## that can say what is actually wired to what.
##
## Worth the noise because the symptom it explains is silent and misleading: sound
## and picture travel by different cords, so a console with its audio pair in and
## its video cord out plays perfectly through a set showing nothing but blue. From
## the outside that looks like a broken console, and there was no way to tell it
## from a wrong input, an unseated plug, or a socket that belongs to nobody.
func _log_seating(verb: String, plug: Node3D) -> void:
	var dev := get_device()
	print("[Port] %s %s on %s%s" % [
		verb,
		port_label(),
		_device_label(dev),
		"" if is_instance_valid(plug) else "  (plug already gone)",
	])
	# A socket whose walk up the tree found no owner accepts plugs and routes
	# nothing — the failure is invisible at the socket and only shows up as a
	# device that never notices it was connected.
	if dev == null:
		push_warning("[Port] %s socket belongs to no device — nothing will be routed"
			% port_label())


static func _device_label(dev: Node) -> String:
	if dev == null:
		return "<no device>"
	var name_prop: Variant = dev.get("display_name")
	if name_prop is String and not (name_prop as String).is_empty():
		return "%s (%s)" % [name_prop, dev.name]
	return str(dev.name)


## Tell the lead that what it carries may have changed. A loose lead's plug is an
## RcaPlug whatever it carries; a console's captive CablePlug is told by the
## console instead. A mains cord has no such hook -- its socket is read when the
## room is saved -- so a lead is only told when it listens.
func _announce(plug: Node3D) -> void:
	var end := plug as RcaPlug
	if is_instance_valid(end) and is_instance_valid(end.cable) \
			and end.cable.has_method("on_plug_seating_changed"):
		end.cable.on_plug_seating_changed()


# The plug this socket last held, so an unseat — which reports nothing — still
# knows which lead to tell.
var _last_plug: Node3D = null


## The plug currently seated here, or null.
func seated_plug() -> Node3D:
	return picked_up_object if is_instance_valid(picked_up_object) else null


## The device this socket belongs to — the deck, television or machine that owns
## it, and the node a save names its lead's end against.
##
## Walked rather than exported, so a port can be dropped anywhere in a device's
## scene (on a shell, inside a back-panel node) without also having to be wired up.
## What it walks for is on_av_topology_changed, which every device that owns a
## lead's socket answers -- a printer or a hub with a no-op, so it is found here.
## PowerPort walks for a saved object instead.
func get_device() -> Node3D:
	var n: Node = get_parent()
	while n != null:
		if n.has_method("on_av_topology_changed"):
			return n as Node3D
		n = n.get_parent()
	return null
