## Holster — the one rule for hardware a machine is wired to and that goes back where it came from: a cabinet's guns in their holsters, a drummer's sticks and a guitarist's guitars in their cradles.
##
## Such a thing carries `captive_well`, the snap zone the machine built round its seat (LightGun, ArcadeHeldGear). THE RULE: it goes back only when it is LET GO near its seat, and falls when let go
## anywhere else. Coming near does nothing: the zone is a DROPPED one and shows NO preview (a held thing was drawn seated in it as it came near, which read as it having gone in by itself), so nobody finds a gun in a holster they did not mean.
##
## A headset's hand lets go AT the seat, and the zone takes it by its own `grab_distance` (a hand's reach). The desktop's hand never gets there -- it rides in the corner of the view, half a metre from
## the camera -- so the desktop's drop asks `stow` (DesktopPickup._drop) with `DESKTOP_REACH`: near the machine it goes back, across the room it falls.
class_name Holster
extends RefCounted

## How far (m) a thing the desktop lets go of may be from its seat and still go back into it. The desktop's hand holds it 0.54 m from the camera, so this is "standing at the machine".
const DESKTOP_REACH := 0.6


## Make a seat a machine built (a snap zone) follow the rule: DROPPED, never RANGE, and never previewed. A RANGE zone takes whatever comes within its reach by itself, which put a gun in a holster whose owner only walked past it.
static func prepare_seat(well: XRToolsSnapZone) -> void:
	well.snap_mode = XRToolsSnapZone.SnapMode.DROPPED
	# And no preview: a thing in a hand near its seat is not shown seated in it (it looked as if it had gone in by itself); it goes in when let go within the zone's reach, and falls otherwise.
	well.show_preview = false


## The snap zone `item` goes back into, or null (a thing with no seat of its own, a seat already freed).
static func well_of(item: Object) -> XRToolsSnapZone:
	if item == null or not is_instance_valid(item) or not ("captive_well" in item):
		return null
	var well: Variant = item.get("captive_well")
	if well == null or not is_instance_valid(well):
		return null
	return well as XRToolsSnapZone


## How far `item` is from where its seat would lay it, in metres, or INF with no seat.
static func distance_to_seat(item: Node3D) -> float:
	var well := well_of(item)
	if well == null:
		return INF
	return well.snap_pose_for(item).origin.distance_to(item.global_position)


## Whether letting `item` go here would put it back (within `reach` of its seat).
static func in_reach(item: Node3D, reach: float = DESKTOP_REACH) -> bool:
	return distance_to_seat(item) <= reach


## Put `item`, which a hand has just let go of, back in its seat if it is within `reach` of it. False (and it falls) when it is further, when no seat is left, when the seat is full or when a hand
## still holds it.
static func stow(item: Node3D, reach: float = DESKTOP_REACH) -> bool:
	var well := well_of(item)
	if well == null:
		return false
	var name_of := str(item.name)
	if item.has_method("is_picked_up") and item.call("is_picked_up"):
		print("[Holster] %s not put back: a hand still holds it" % name_of)
		return false
	var away := distance_to_seat(item)
	if away > reach:
		print("[Holster] %s let go %.2f m from its seat (reach %.2f m): it falls" % [name_of, away, reach])
		return false
	if is_instance_valid(well.picked_up_object) and well.picked_up_object != item:
		print("[Holster] %s: its seat holds %s already" % [name_of, well.picked_up_object.name])
		return false
	well.pick_up_object(item)
	var seated := well.picked_up_object == item
	print("[Holster] %s let go %.2f m from its seat: %s" % [name_of, away, "put back" if seated else "refused by the seat"])
	return seated
