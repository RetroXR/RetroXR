## ArcadeSocketModule — the cabinet's extra controller and light-gun sockets.
##
## The kind is `sockets`. Its `PortSeat1`, `PortSeat2`, ... markers are where the
## RetroSystem's controller-port zones go, in the same frame the NES's are authored
## in (rolled 180 degrees about Z, +Z out of the face), so a pad or a gun plugs in as
## on a console. The zones are the system's own; this module only places them.
class_name ArcadeSocketModule
extends ArcadeModule

## How far the plug is offered proud of the socket's mouth, in metres.
const PLUG_PROUD := 0.02


func _init() -> void:
	kind = ArcadeProfiles.KIND_SOCKETS


## How many sockets this module has seats for.
func seat_count() -> int:
	var n := 0
	while find_child("PortSeat%d" % (n + 1), true, false) != null:
		n += 1
	return n


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
