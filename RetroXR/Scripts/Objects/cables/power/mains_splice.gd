class_name MainsSplice
extends RefCounted

## A change of mains region, as the room lives through it: every plate, strip and
## travel adapter becomes the new region's, and every plug that was in a wall
## outlet or a strip socket ends up back in the socket of the same name --
## straight in if it fits there, through a travel adapter spliced in if it does
## not. A plug whose socket is gone -- a six-outlet strip become a UK four-gang
## -- goes into a free socket on the same strip instead. An adapter the game
## spliced in comes out again once its plug fits the socket on its own; one the
## player put there stays.
##
## Before this a strip's own plug fell out of the wall on every change: the
## strip let go of the old socket as its plug changed, before the plate was
## rebuilt to take it.

const ADAPTER_SCENE := preload("res://Scenes/Objects/appliances/travel_adapter.tscn")


## Make `tree`'s room `id`'s, keeping what is plugged in plugged in.
static func change_region(tree: SceneTree, id: String) -> void:
	var seats := _room_seats(tree)
	PowerStrip.apply_region(tree, id)
	TravelAdapter.apply_region(tree, id)
	WallOutlet.apply_region(tree, id)
	# Every plug whose socket is still there first, so the ones moved off a
	# shrunk strip take only sockets nobody had.
	var homeless := []
	for seat: Dictionary in seats:
		if not _reseat(tree, seat):
			homeless.append(seat)
	for seat: Dictionary in homeless:
		var owner: Node = seat["owner"]
		if not is_instance_valid(owner) or not owner is PowerStrip:
			continue
		for s in (owner as PowerStrip).sockets():
			if s.enabled and s.picked_up_object == null:
				seat["port"] = String(s.name)
				_reseat(tree, seat)
				break


## Every plug seated in a wall outlet's or a strip's socket, by the socket's
## owner and name: the plates free their sockets and make new ones of the same
## names, so the node itself does not survive.
static func _room_seats(tree: SceneTree) -> Array:
	var out := []
	for node in tree.get_nodes_in_group(PowerPort.GROUP):
		var port := node as PowerPort
		var plug := port.picked_up_object as PowerPlug
		var owner := _room_owner(port)
		if plug != null and owner != null:
			out.append({"owner": owner, "port": String(port.name), "plug": plug})
	return out


## The plate or strip a socket is on, or null for any other socket (an
## appliance's inlet, an adapter's own).
static func _room_owner(port: PowerPort) -> Node:
	var parent := port.get_parent()
	if parent is WallOutlet:
		return parent
	if parent != null and parent.get_parent() is PowerStrip:
		return parent.get_parent()
	return null


static func _port_of(owner: Node, port_name: String) -> PowerPort:
	var path := port_name if owner is WallOutlet else "Body/" + port_name
	var port := owner.get_node_or_null(path) as PowerPort
	return port if port != null and port.enabled and not port.is_queued_for_deletion() else null


## Put a recorded plug back in its socket; false when the socket is gone (or
## taken), for change_region to find it another.
static func _reseat(tree: SceneTree, seat: Dictionary) -> bool:
	var owner: Node = seat["owner"]
	var plug: PowerPlug = seat["plug"]
	if not is_instance_valid(owner) or not is_instance_valid(plug):
		return true
	var port := _port_of(owner, str(seat["port"]))
	if port == null or (port.picked_up_object != null and port.picked_up_object != plug):
		return false
	var adapter := plug.cable as TravelAdapter
	if adapter != null and adapter.spliced:
		# Ours: out again if what is in it goes straight in now.
		var inner := adapter.socket.picked_up_object as PowerPlug
		if inner != null and inner.is_in_group(port.snap_require):
			adapter.socket.drop_object()
			adapter.drop_and_free()
			port.pick_up_object(inner)
			return true
	if PowerCord.socket_holding(plug) == port:
		return true
	if plug.is_in_group(port.snap_require):
		_seat(port, plug)
		return true
	# It does not fit the new socket: an adapter between them, as a traveller
	# would. Not on a netplay client, whose spawns are the host's to make.
	if not plug.is_in_group("universal_socket") or NetworkManager.is_client():
		return true
	var made := ADAPTER_SCENE.instantiate() as TravelAdapter
	made.spliced = true
	tree.current_scene.add_child(made)
	made.add_to_group("spawned")
	NetworkManager.on_local_spawn(made)
	if not is_instance_valid(made) or made.is_queued_for_deletion():
		return true
	print("[Mains] spliced a travel adapter in for %s" % plug.connector)
	made.wall_plug.global_transform = port.global_transform
	_seat(port, made.wall_plug)
	_seat(made.socket, plug)
	return true


## Seat `plug` in `port`, out of wherever it is first.
static func _seat(port: PowerPort, plug: PowerPlug) -> void:
	var holder := PowerCord.socket_holding(plug)
	if holder != null:
		holder.drop_object()
	port.pick_up_object(plug)
