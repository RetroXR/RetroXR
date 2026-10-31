## ArcadeSocketModule — the cabinet's extra controller and light-gun sockets.
##
## The kind is `sockets`. Its `PortSeat1`, `PortSeat2`, ... markers are where the
## RetroSystem's controller-port zones go, in the same frame the NES's are authored
## in (rolled 180 degrees about Z, +Z out of the face), so a pad or a gun plugs in as
## on a console. The zones are the system's own; this module only places them.
##
## A gun cabinet's sockets are where the guns' cords go IN, and each has a `Holster1`,
## `Holster2`, ... marker beside it: where that player's gun hangs at rest (a Transform in this
## cabinet's frame, the gun's own -Z the way it aims). The cabinet builds the guns with the
## machine and hangs them there (RetroSystem._spawn_captive_controllers).
class_name ArcadeSocketModule
extends ArcadeModule

## How far the plug is offered proud of the socket's mouth, in metres.
const PLUG_PROUD := 0.02

## The scene of the gun each Holster rests, or "" for the cabinet's pistol (a rifle cabinet names its rifle).
@export var gun_scene := ""


func _init() -> void:
	kind = ArcadeProfiles.KIND_SOCKETS


## How many sockets this module has seats for.
func seat_count() -> int:
	var n := 0
	while find_child("PortSeat%d" % (n + 1), true, false) != null:
		n += 1
	return n


## How many guns hang on this cabinet: the holster markers it has.
func holster_count() -> int:
	var n := 0
	while find_child("Holster%d" % (n + 1), true, false) != null:
		n += 1
	return n


## Where gun `index` (0-based) hangs, as a global transform, or identity without a holster.
func holster_transform(index: int) -> Transform3D:
	var h := find_child("Holster%d" % (index + 1), true, false) as Node3D
	return h.global_transform if h != null else Transform3D.IDENTITY


## The pivot gun `index` is fixed to (a `Pivot<n>` marker beside its holster: a swivel mount's), or null for a gun
## that hangs in a holster and can be carried. The marker's own basis is the way the gun faces at rest.
func pivot_node(index: int) -> Node3D:
	return find_child("Pivot%d" % (index + 1), true, false) as Node3D


## Where gun `index`'s cord goes in, as a global position.
func cord_entry(index: int) -> Vector3:
	var seat := find_child("PortSeat%d" % (index + 1), true, false) as Node3D
	return seat.global_position if seat != null else Vector3.ZERO


## Put the system's port zones on the seats. A zone with no seat is left alone.
func seat_zones(port_zones: Array) -> void:
	for i in port_zones.size():
		var zone := port_zones[i] as Node3D
		var seat := find_child("PortSeat%d" % (i + 1), true, false) as Node3D
		if zone == null or seat == null:
			continue
		zone.global_transform = seat.global_transform
		if "preview_offset" in zone:
			zone.preview_offset = Vector3(0, 0, PLUG_PROUD)
