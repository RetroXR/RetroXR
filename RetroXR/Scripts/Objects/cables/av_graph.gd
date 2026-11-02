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
##
## ── Pass-throughs ────────────────────────────────────────────────────────────
## A device can stand in the MIDDLE of a signal: the 32X takes the console's A/V OUT
## into its A/V IN (Sega's Video Link Cable) and the set is cabled to the 32X's A/V
## OUT. It answers `av_through_in()`, `av_through_out()` and `av_passes()`
## (RetroExpansion through ExpansionAv), and every device but the pass-through itself
## sees it spliced out of the wiring, both ways:
##   * a SOURCE whose output reaches a pass-through's input is also given the
##     pass-through's onward links, with its own socket as their `out` -- so the
##     console resolves the set as its sink (AvSource) and the set files the console
##     on its input (TvPanel._input_for_device) with no code of their own;
##   * a SINK whose input is cabled to a pass-through's output sees the socket that
##     feeds the pass-through as the `out` instead -- the arcade cabinet's VIDEO IN
##     and the amplifier read their source off `out.get_device()`.
## Each spliced link names the pass-through it went through as `via`. A pass-through
## that is not passing (its own supply dead) or that nothing feeds is left as it is:
## its output's device is then the unit, which no sink takes a picture from. The
## pass-through itself reads its own sockets unspliced: it is asking which machine
## feeds it.
##
## The cord index carries over unchanged, which is right for what can be cabled
## today: the 32X's two sockets and the console's are all MultiAvPorts, the same
## cord-to-signal map, and one mini-DIN lead between two of them carries all of it.
class_name AvGraph


## Every link on every cable that touches `dev`, as {out, in, cord} dictionaries
## with the direction already resolved, and any pass-through spliced out (above).
## Duplicates are impossible — each cable is visited once — but a cord that reaches
## `dev` twice legitimately appears once per cable.
static func links_for(dev: Node3D) -> Array:
	var own := own_links(dev)
	if is_through(dev):
		return own
	var out: Array = []
	for link: Dictionary in own:
		var from := link["out"] as RcaPort
		var origin := source_of(from)
		if origin != from:
			var back := link.duplicate()
			back["out"] = origin
			back["via"] = from.get_device()
			out.append(back)
			continue
		out.append(link)
		if from.get_device() == dev:
			out.append_array(_onward(from, link["in"] as RcaPort, {}))
	return out


## The links on every cable seated in one of `dev`'s own sockets, nothing spliced.
static func own_links(dev: Node3D) -> Array:
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


## Whether `dev` is a pass-through: it has an A/V IN that it carries on to an A/V OUT.
static func is_through(dev: Node) -> bool:
	return is_instance_valid(dev) and dev.has_method("av_through_in") \
		and dev.call("av_through_in") != null


## The output that is really sending what leaves `port`: the socket feeding the
## pass-through `port` is the output of, followed back through any chain of them,
## or `port` itself when it belongs to no pass-through, the pass-through is not
## passing, or nothing is cabled into it.
static func source_of(port: RcaPort) -> RcaPort:
	return _source_of(port, {})


static func _source_of(port: RcaPort, seen: Dictionary) -> RcaPort:
	if port == null:
		return port
	var through := port.get_device()
	if not is_through(through) or seen.has(through) or port != through.call("av_through_out") \
			or not bool(through.call("av_passes")):
		return port
	seen[through] = true
	var feed := feeding(through)
	return _source_of(feed, seen) if feed != null else port


## The output cabled into a pass-through's A/V IN, or null.
static func feeding(through: Node3D) -> RcaPort:
	if not is_through(through):
		return null
	var at := through.call("av_through_in") as RcaPort
	for link: Dictionary in own_links(through):
		if link["in"] == at and (link["out"] as RcaPort).get_device() != through:
			return link["out"] as RcaPort
	return null


## What `from` reaches beyond the input it is cabled to, when that input is a
## pass-through's: the pass-through's own onward links, re-sourced at `from`, and on
## through any pass-through those reach in turn.
static func _onward(from: RcaPort, to: RcaPort, seen: Dictionary) -> Array:
	var out: Array = []
	var through := to.get_device() if to != null else null
	if not is_through(through) or seen.has(through) or to != through.call("av_through_in") \
			or not bool(through.call("av_passes")):
		return out
	seen[through] = true
	var at := through.call("av_through_out") as RcaPort
	for link: Dictionary in own_links(through):
		if link["out"] != at:
			continue
		out.append({"out": from, "in": link["in"], "cord": link.get("cord", 0), "via": through})
		out.append_array(_onward(from, link["in"] as RcaPort, seen))
	return out
