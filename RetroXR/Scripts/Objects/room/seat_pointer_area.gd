## SeatPointerArea — the body of a seat that a laser or a click can hit: carrying the seat is a hold on it
## (HoldToGrab, through its parent), and while somebody sits on it a press on any part of it stands them up.
##
## Without this the only way up was the cushion itself, which the sitter is on top of: from the lap the laser
## flew over the seat and found nothing. The seat puts this script on its `PointerArea` when it is made
## (Seat._ready), so a mod's seat has it too.
##
## ONLY WHILE OCCUPIED does it claim the desktop's aim. Its boxes are the seat's own collision boxes, and the
## desktop's InteractionResolver lets a pointer target (a "control") win over the pickable it sits flush on, so
## claiming always turned every click on an empty seat into a press that did nothing: placed seats could not be
## picked up or moved on the desktop (2026-11-10). Declined, the walk goes on to the Seat and the hold carries it.
class_name SeatPointerArea
extends StaticBody3D


## InteractionResolver asks this before taking the aim: only a seat with somebody on it wants a press.
func accepts_pointer_at(_at: Vector3) -> bool:
	var seat := get_parent()
	return seat != null and seat.has_method("is_occupied") and bool(seat.call("is_occupied"))


func pointer_event(event: XRToolsPointerEvent) -> void:
	if event.event_type != XRToolsPointerEvent.Type.PRESSED:
		return
	var seat := get_parent()
	if seat != null and seat.has_method("is_occupied") and bool(seat.call("is_occupied")):
		# Said, because it is the one press that is NOT the player's own aim: a click meant for the menu that lands here stands them up.
		print("[Seat] a press on %s's body stood the sitter up (at %s)" % [seat.name, str(event.position)])
		seat.call("stand")
