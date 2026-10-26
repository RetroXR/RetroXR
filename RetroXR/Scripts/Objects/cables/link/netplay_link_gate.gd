## Whether a running lockstep game has taken a link's join/part decision.
##
## Shared by every link in the room, because the rule is about the SESSION
## rather than about what joins the machines: a lead of any shape
## (CompositeCable.netplay_took_bus) or no lead at all (IrBus, two infrared
## windows in sight of each other). Joining or parting two cores changes
## deterministic state on both, and applying it the instant a hand moves lands
## it on a different emulated frame on every peer. Both peers are then wrong in
## the same way, so the CRC checker cannot even call it a desync.
## LinkCoordinator says as much itself — the one thing it cannot enforce is that
## Connect and Disconnect happen on the same emulated frame everywhere, and that
## it is the caller's job.
##
## One gate per link, because it remembers the bus that link has asked for and
## not seen land yet.
class_name NetplayLinkGate
extends RefCounted

## Test seam for the deterministic topology policy. Runtime always uses the
## NetworkManager autoload.
var manager_override: Object = null

## The bus this link has had scheduled and not parted since.
var _held: Array = []


## `join` is the bus the link would make now, `held` the one it is still holding
## (a pull has nothing to walk to). Every machine involved must be in the
## session: a link half in one is a bus the session cannot schedule, and joining
## it locally anyway is the fork this exists to avoid. True means the caller
## must do nothing else — the host has scheduled it and every peer, this one
## included, applies it on the agreed frame.
func took_bus(join: Array, held: Array) -> bool:
	var manager: Object = manager_override if manager_override != null else NetworkManager
	# A session switching these machines on apart owns the wire until it joins
	# it itself; nothing is scheduled from here, and nothing joined.
	if manager.has_method("netplay_holds_cable"):
		var holding: Array = join if join.size() >= 2 else held
		if not holding.is_empty() and holding.all(
				func(e: Dictionary) -> bool: return manager.netplay_holds_cable(e.get("machine"))):
			return true
	if not manager.netplay_running():
		_held.clear()
		return false
	var is_join := join.size() >= 2
	var entries: Array = join if is_join else held
	# A scheduled join has not updated the link's ordinary cache yet. If the
	# player parts it again inside LINK_LEAD, retain the intended bus here so
	# the inverse operation can cancel it at the next agreed boundary.
	if entries.is_empty() and not is_join:
		entries = _held
	if entries.is_empty():
		return false
	var covered := 0
	for entry: Dictionary in entries:
		if manager.netplay_covers(entry.get("machine")):
			covered += 1
	if covered == 0:
		return false
	if covered != entries.size():
		# Never fall through to an immediate local join when only one endpoint is
		# deterministic.  That forks this peer from the rest of the session.
		if manager.is_host():
			push_warning("[Netplay] cable touches a machine outside the session; topology change refused")
		return true
	if is_join and _same_bus(_held, entries):
		return true
	if manager.is_host():
		manager.netplay_schedule_link(1 if is_join else 0, entries)
	if is_join:
		_held = entries.duplicate(true)
	else:
		_held.clear()
	return true


func _same_bus(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		var left: Dictionary = a[i]
		var right: Dictionary = b[i]
		if left.get("machine") != right.get("machine") \
				or int(left.get("port", 0)) != int(right.get("port", 0)):
			return false
	return true
