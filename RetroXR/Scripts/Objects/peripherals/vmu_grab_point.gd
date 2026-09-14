## The VMU's grab point. Snap zones and the desktop hand seat the card at it; a VR
## hand does not, and takes the card by its authored grip instead (see
## VmuCard.grip_anchor). Landing on this point first would swing the card into
## that grip on every grab.
extends XRToolsGrabPoint


func can_grab(grabber: Node3D, current: XRToolsGrabPoint) -> float:
	if grabber is XRToolsFunctionPickup:
		return 0.0
	return super.can_grab(grabber, current)
