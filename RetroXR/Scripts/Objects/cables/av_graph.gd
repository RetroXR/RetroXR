## AvGraph — what is wired to what, asked once instead of worked out three times.
##
## A cable reports only its OWN cords, so a device told about a change by one lead
## used to learn nothing about the others. A console already worked around that by
## re-walking every port it owns (RetroSystem._all_links); the decks did not, so a
## deck fed by two leads had its whole routing overwritten by whichever of them
## resolved last — picture from one, sound from the other, and the loser silently
## dropped. The walk lives here now, and everything asks it the same way.
##
## Static, and there is no registry to keep in step: RcaPort puts every socket in
## its own group as it enters the tree, so the question is answered from the scene
## rather than from a cache that can drift out of date.
class_name AvGraph


## Every link on every cable that touches `dev`, as {out, in, cord} dictionaries
## with the direction already resolved. Duplicates are impossible — each cable is
## visited once — but a cord that reaches `dev` twice legitimately appears once
## per cable.
static func links_for(dev: Node3D) -> Array:
	var out: Array = []
	if not is_instance_valid(dev) or not dev.is_inside_tree():
		return out
	var seen := {}
	for node in dev.get_tree().get_nodes_in_group(RcaPort.GROUP):
		var port := node as RcaPort
		if port == null or port.get_device() != dev:
			continue
		var plug := port.seated_plug() as RcaPlug
		if plug == null or not is_instance_valid(plug.cable):
			continue
		if seen.has(plug.cable):
			continue
		seen[plug.cable] = true
		# Duck-typed, NOT `as CompositeCable`. RcaPlug.cable is a Node3D and
		# anything at all can be set as one — the RF switch is a DEVICE with two
		# captive leads that registers itself as its own plugs' cable — and a cast
		# that misses turns a perfectly good link list into a null dereference in
		# the routing hot path.
		if not plug.cable.has_method("links"):
			continue
		out.append_array(plug.cable.call("links"))
	return out
