## MainsSync — a mains lead's plugs, told to the other players (docs/dev/power.md).
##
## Mains plugs had no live event: only CompositeCable announced a seat or a pull,
## and a late joiner got the rest from the snapshot. With power consumed, a plug
## pulled on one peer is a machine switched off, so every mains lead now says so the
## way CompositeCable does -- diffed against the last seating it reported, one event
## per end that actually moved (EV_RCA_PLUG / EV_RCA_UNPLUG, its `cable` the lead) --
## and puts a peer's seat or pull into effect with seat() / release().
##
## An appliance's own cord (CaptiveMainsCord) is not an object of its own on the
## wire: it is named by the appliance it belongs to (EV_MAINS_CORD_PLUG / _UNPLUG).
class_name MainsSync
extends RefCounted

const LAST := &"mains_last_seating"
## How far a pulled plug is drawn out along its socket's axis (CompositeCable's).
const PULLED_CLEAR := 0.12


## Tell the others which of `lead`'s ends moved since the last time.
static func report(lead: Node) -> void:
	if lead == null or not lead.is_inside_tree() or not lead.has_method("seating"):
		return
	var last: Dictionary = lead.get_meta(LAST, {})
	var now := {}
	for seat: Dictionary in lead.call("seating"):
		var key := "%d:%d" % [int(seat["end"]), int(seat["cord"])]
		var dev: Node3D = seat["device"]
		var where := "" if dev == null else "%s/%s" % [dev.get_path(), seat["port"]]
		now[key] = where
		if str(last.get(key, "")) == where:
			continue
		if dev == null:
			NetworkManager.report_event(NetEvents.Event.EV_RCA_UNPLUG,
				{"cable": lead, "end": seat["end"], "cord": seat["cord"]})
		else:
			NetworkManager.report_event(NetEvents.Event.EV_RCA_PLUG, {
				"cable": lead, "end": seat["end"], "cord": seat["cord"],
				"dev": dev, "port": seat["port"],
			})
	lead.set_meta(LAST, now)


## A built-in cord's plug moved: said by its appliance.
static func report_captive(cord: CaptiveMainsCord) -> void:
	if cord == null or not cord.is_inside_tree() or not is_instance_valid(cord.host):
		return
	var holder := PowerCord.socket_holding(cord.wall_plug)
	var where := "" if holder == null else "%s/%s" % [holder.get_device().get_path(), holder.name]
	if str(cord.get_meta(LAST, "")) == where:
		return
	cord.set_meta(LAST, where)
	if holder == null:
		NetworkManager.report_event(NetEvents.Event.EV_MAINS_CORD_UNPLUG, {"obj": cord.host})
	else:
		NetworkManager.report_event(NetEvents.Event.EV_MAINS_CORD_PLUG,
			{"obj": cord.host, "dev": holder.get_device(), "port": String(holder.name)})


## A peer seated `plug` in the socket `port_name` on `device`.
static func seat(plug: Node3D, device: Node, port_name: String) -> void:
	if plug == null or device == null:
		return
	var port := CompositeCable.port_named(device, port_name)
	if port != null and plug.is_in_group(port.snap_require):
		port.pick_up_object(plug)
	else:
		print("[Power] a peer's plug went into %s on %s, which is not here or does not take it"
			% [port_name, device.name])


## A peer pulled `plug`: out, and drawn clear so the socket does not take it straight
## back (CompositeCable.net_release_plug says why).
static func release(plug: Node3D) -> void:
	if plug == null or not plug.is_inside_tree():
		return
	var port: Port = null
	for node in plug.get_tree().get_nodes_in_group(Port.ANY_GROUP):
		if (node as Port).picked_up_object == plug:
			port = node as Port
	if port == null:
		return
	port.enabled = false
	port.drop_object()
	plug.global_position = port.global_position + port.global_transform.basis.z.normalized() * PULLED_CLEAR
	if plug is CollisionObject3D:
		PhysicsServer3D.body_set_state((plug as CollisionObject3D).get_rid(),
			PhysicsServer3D.BODY_STATE_TRANSFORM, plug.global_transform)
	_reopen(port)


static func _reopen(port: Port) -> void:
	var tree := port.get_tree()
	await tree.physics_frame
	await tree.physics_frame
	if is_instance_valid(port):
		port.enabled = true
