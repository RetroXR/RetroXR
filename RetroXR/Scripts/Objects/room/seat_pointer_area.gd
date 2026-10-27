## SeatPointerArea — the body of a seat that a laser or a click can hit: carrying the seat is a hold on it
## (HoldToGrab, through its parent), and while somebody sits on it a press on any part of it stands them up.
##
## Without this the only way up was the cushion itself, which the sitter is on top of: from the lap the laser
## flew over the seat and found nothing. The seat puts this script on its `PointerArea` when it is made
## (Seat._ready), so a mod's seat has it too.
class_name SeatPointerArea
extends StaticBody3D


func pointer_event(event: XRToolsPointerEvent) -> void:
	if event.event_type != XRToolsPointerEvent.Type.PRESSED:
		return
	var seat := get_parent()
	if seat != null and seat.has_method("is_occupied") and bool(seat.call("is_occupied")):
		seat.call("stand")
