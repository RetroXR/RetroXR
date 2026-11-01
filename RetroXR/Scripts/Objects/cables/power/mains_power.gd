## MainsPower — whether the room's mains reaches a socket or a plug, and the one
## place every change of it is announced.
##
## A static resolver, as IrBus and ILinkBus are: nothing is stored, every answer
## walks the room as it stands. Power flows one way, wall to appliance: a wall
## outlet's receptacle is live; a strip's or a travel adapter's socket is live while
## that thing's own wall plug is in a live socket; an appliance end of a lead is live
## while the lead's wall end is. A walk that comes back to something it has already
## asked (a strip plugged into one of its own sockets) is dead, as it is on the
## hardware.
##
## Who answers what is duck-typed, so a mod's lead or brick takes part by having the
## method: `mains_live_at(at: Node, seen: Dictionary) -> bool` on the lead or fixture
## that owns `at` (one of its sockets or one of its plugs). PowerStrip, TravelAdapter,
## PowerCord and PowerBrick answer it.
##
## Consumers are PowerInput nodes (group CONSUMER_GROUP). Any socket seat or pull on a
## mains or DC socket, any cell in or out, a region change or the option moving calls
## changed(), which tells every consumer once, at the end of the frame.
class_name MainsPower
extends RefCounted

const CONSUMER_GROUP := &"mains_consumer"

## Set while a deferred announcement is on its way, so a burst of seats (a strip
## pulled with five plugs in it) re-asks every device once, not five times.
static var _pending := false
## The rooms (by scene path) whose missing outlets have been said already.
static var _said_no_mains := {}


## Whether there is power at the holes of `port`. `seen` is the walk so far.
static func socket_live(port: Node, seen: Dictionary = {}) -> bool:
	var socket := port as XRToolsSnapZone
	if socket == null or not is_instance_valid(socket) or not socket.is_inside_tree() \
			or socket.is_queued_for_deletion():
		return false
	var at: Node = socket.get_parent()
	if at is WallOutlet:
		return true
	# The nearest thing above the socket that can say: a strip's sockets are under its
	# body, an adapter's under its plug.
	while at != null:
		if at.has_method("mains_live_at"):
			return _ask(at, socket, seen)
		at = at.get_parent()
	return false


## Whether there is power at the pins of `plug`, from its own lead. A wall plug of a
## lead never is: power does not flow back out of an appliance.
static func plug_live(plug: Node, seen: Dictionary = {}) -> bool:
	var end := plug as RcaPlug
	if end == null or not is_instance_valid(end) or not end.is_inside_tree():
		return false
	var lead: Node = end.cable
	if not is_instance_valid(lead) or not lead.has_method("mains_live_at"):
		return false
	return _ask(lead, end, seen)


## Whether `plug` sits in a socket that has power -- the question a strip, an adapter,
## a cord and a brick each ask of their own wall plug.
static func seated_live(plug: Node, seen: Dictionary) -> bool:
	var holder := PowerCord.socket_holding(plug as Node3D)
	return holder != null and socket_live(holder, seen)


static func _ask(owner: Node, at: Node, seen: Dictionary) -> bool:
	var key := owner.get_instance_id()
	if seen.has(key):
		return false
	seen[key] = true
	return bool(owner.call("mains_live_at", at, seen))


## Whether the room has any mains wiring to plug into. A room with no wall outlet
## (the den, the test hallway, passthrough, most mod rooms) cannot power anything
## by cord, so there everything powers as though the option were on.
static func room_has_mains(tree: SceneTree) -> bool:
	if tree == null:
		return false
	var has := not tree.get_nodes_in_group(WallOutlet.GROUP).is_empty()
	if not has:
		var room := tree.current_scene.scene_file_path if tree.current_scene != null else ""
		if not _said_no_mains.has(room):
			_said_no_mains[room] = true
			print("[Power] %s has no wall outlets: every device here powers without a cord"
				% (room.get_file() if not room.is_empty() else "this room"))
	return has


## Whether the rule is off here: power simulation is off, or the room has nowhere to
## plug in.
static func everything_powered(tree: SceneTree) -> bool:
	return not AppPrefs.power_simulation or not room_has_mains(tree)


## Something that can change a device's supply happened. Every consumer re-asks
## once, at the end of this frame.
static func changed(tree: SceneTree) -> void:
	if tree == null or _pending:
		return
	_pending = true
	_announce.call_deferred(tree)


static func _announce(tree: SceneTree) -> void:
	_pending = false
	if tree == null:
		return
	tree.call_group(CONSUMER_GROUP, &"on_mains_changed")
