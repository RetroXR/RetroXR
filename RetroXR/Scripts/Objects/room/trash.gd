## Trash — what every bin in the game shares: the StorageBox in the room and the
## MenuTrashBin at the spawn menu's corner.
##
##  - is_held: whether a body is in someone's grip, by hand, desktop or laser.
##  - set_highlight: the red "this will be deleted" outline.
##  - delete_with_dependents: the delete itself, with everything the object owns.
##
## Deleting needs nothing beyond freeing the node: ObjectSync despawns it for the
## other players on tree_exiting, and ScenePersistence saves only what is still in
## the "spawned" group.
class_name Trash
extends RefCounted


## True while `body` is held. A hand or desktop grab goes through pick_up, so
## is_picked_up() answers it; a laser grab does not — XRToolsFunctionPickup
## freezes the object and drags it itself — so the pickups are asked as well.
## Without the second half a bin never sees a laser-carried object at all.
static func is_held(body: XRToolsPickable) -> bool:
	if not is_instance_valid(body):
		return false
	if body.is_picked_up():
		return true
	if not body.is_inside_tree():
		return false
	for pickup in body.get_tree().get_nodes_in_group(XRToolsFunctionPickup.PICKUP_GROUP):
		if pickup is XRToolsFunctionPickup and pickup.is_ray_grabbing_target(body):
			return true
	return false


## Whether `node` is something a bin or a menu may delete: a pickable that
## belongs to something spawned (it, or a node above it — a lead's plug, a cover
## on its slot — is in the "spawned" group), and not a captive cable end, which
## delete_with_dependents would refuse anyway. The room's own furniture is not.
static func can_delete(node: Node) -> bool:
	if not (node is XRToolsPickable) or node is CablePlug or node is ControllerPlug:
		return false
	var n := node
	while n != null:
		if n.is_in_group("spawned"):
			return true
		n = n.get_parent()
	return false


## Red outline on (or off) a pickable over a bin.
static func set_highlight(pickable: XRToolsPickable, in_trash: bool) -> void:
	if not is_instance_valid(pickable):
		return
	for child in pickable.get_children():
		if child is PickableHighlight:
			child.set_trash_mode(in_trash)
			return


## Delete a trashed object together with everything it owns, and release
## everything it merely holds:
## - a running system is powered off first (clean emulation-thread shutdown)
## - its cable (rope + plug live at the scene root, not under the pickable)
##   is freed, plug dropped out of any snap zone first
## - media snapped into its slots (cartridge/disc/tape/memory card) is freed
##   too — otherwise it stays frozen in mid-air where the slot was
## - a controller plugged into one of its ports goes with it, cable and all —
##   a pad wired to a machine that no longer exists is not something to leave
##   standing in the room
## - other foreign plugs snapped into its ports belong to OTHER devices' cables
##   and are only dropped, never freed
## - a composite lead patched into its sockets goes with it, both ends — see
##   free_lead
## A captive plug is not deletable — freeing one would orphan the rope of the
## device that owns it — so it just falls out of the can.
static func delete_with_dependents(pickable: XRToolsPickable, seen: Dictionary = {}) -> void:
	if seen.has(pickable):
		return
	seen[pickable] = true
	if pickable is CablePlug or pickable is ControllerPlug:
		print("[Trash] '%s' is a cable plug — not deletable" % pickable.name)
		return

	if pickable is RcaPlug:
		free_lead(pickable as RcaPlug)
		return

	if pickable is RetroSystem and (pickable as RetroSystem).is_powered_on:
		(pickable as RetroSystem).power_off()

	# Release or free everything snapped into this object's zones.
	for zone in pickable.find_children("*", "XRToolsSnapZone", true, false):
		# Variant first: a zone can still point at a freed plug, and binding one to
		# a typed local throws before the validity test below can run.
		var occupant: Variant = zone.picked_up_object
		if not is_instance_valid(occupant):
			continue
		var held: Node3D = occupant
		zone.drop_object()
		if held is ControllerPlug:
			# A controller is not a lead: its plug is the tail of a device, and
			# binning the machine it is plugged into bins the controller too,
			# cable and all. Leaving the plug behind left a pad wired to nothing
			# and a rope trailing off it. The controller frees its own cable in
			# _exit_tree, so the plug goes with it.
			var owner_device: Node3D = (held as ControllerPlug).get_controller()
			if is_instance_valid(owner_device) and owner_device is XRToolsPickable:
				print("[Trash] deleting plugged-in '%s'" % owner_device.name)
				delete_with_dependents(owner_device as XRToolsPickable, seen)
			continue
		if held is CablePlug or held.is_in_group("controller_plug"):
			continue   # another device's captive cable end — released, not deleted
		if held is RcaPlug:
			free_lead(held as RcaPlug)
			continue
		print("[Trash] deleting snapped '%s'" % held.name)
		if held.has_method("drop_and_free"):
			held.call("drop_and_free")
		else:
			Vanish.free_node(held)

	# Free the object's own cable (spawned at the scene root).
	var cable: Node3D = pickable.cable_instance() \
		if pickable.has_method("cable_instance") else null
	if is_instance_valid(cable):
		for plug_name: String in ["CablePlug", "ControllerPlug"]:
			var plug := cable.get_node_or_null(plug_name)
			if plug and plug.has_method("drop"):
				plug.call("drop")
		cable.queue_free()

	if pickable.has_method("drop_and_free"):
		pickable.call("drop_and_free")
	else:
		Vanish.free_node(pickable)


## Free the whole lead one of its plugs belongs to.
##
## A lead is a free-standing object joining two devices rather than a tail either
## of them owns, and it has no body of its own — plugs and a rope — so a plug is
## the only handle a bin ever sees. Binning one end therefore bins the lead, as
## does binning a device it is patched into. drop_and_free unseats every other end
## first, so the deck or television at the far side hears the unplug and drops the
## feed rather than being left holding a dead plug.
##
## The plug is never freed on its own: its lead would go on running the tether in
## CompositeCable._physics_process over a freed end.
static func free_lead(plug: RcaPlug) -> void:
	# Variant first — a plug can outlive its lead, and binding a freed instance to
	# a typed local throws before is_instance_valid() gets a chance to guard it.
	var owner_cable: Variant = plug.cable
	if not is_instance_valid(owner_cable):
		return
	# Node, not CompositeCable: a mains lead is a PowerCord, which is neither one
	# nor a subclass of one. Both answer drop_and_free.
	var lead := owner_cable as Node
	# A console wears two sockets and so hands the same lead over twice.
	if lead == null or lead.is_queued_for_deletion():
		return
	if not lead.has_method("drop_and_free"):
		return
	print("[Trash] deleting lead '%s'" % lead.name)
	lead.call("drop_and_free")
