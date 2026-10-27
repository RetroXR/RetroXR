## ArcadeGuitarGrab — where a hand takes a guitar: its body or its neck, by the left hand or the right.
##
## A guitar is held by both hands (the body in one, the neck in the other: ArcadeGuitar) and each place has its own pose for each hand, because the guitar is held as one is played: the
## neck out to the player's left and forward for a right-handed player (the body in the right hand, the neck in the left), and to the right for the other way round. A grab point's own transform
## is the hand's pose on the guitar (XRToolsGrabPoint: `transform` is where the controller is, in the guitar's frame), so the four points are authored with those poses and this class says which
## of them a grab may take:
##   the first hand takes the nearest place that is ITS side's (a left hand never takes a right-hand place), body or neck;
##   the second takes the other END with the other hand (a body hand and a neck hand: never two on the body);
##   the desktop's hand pivot takes its own place (DESKTOP: the guitar turned to show its face to the eye, lying across the lower right of the view);
##   and a thing that is not a hand (the cradle seating the guitar) takes the RIGHT hand's body place, the pose it is stowed in.
class_name ArcadeGuitarGrab
extends XRToolsGrabPoint

const BODY := 0
const NECK := 1
const DESKTOP := 2
const LEFT := 0
const RIGHT := 1

## Which end of the guitar this is (DESKTOP: the place the mouse and keyboard's hand takes it by).
@export_enum("Body", "Neck", "Desktop") var role: int = BODY
## Which hand holds it so.
@export_enum("Left", "Right") var hand_side: int = RIGHT


## The hand a grabber is: LEFT or RIGHT for a pickup function on a controller, -1 for anything else.
static func hand_of(grabber: Node3D) -> int:
	if grabber == null or not grabber.has_method("get_controller"):
		return -1
	var ctrl := grabber.call("get_controller") as XRController3D
	if ctrl == null:
		return -1
	if ctrl.tracker == &"left_hand":
		return LEFT
	if ctrl.tracker == &"right_hand":
		return RIGHT
	return -1


## Is the grabber the desktop's hand (its pivot, in the group the pickup keeps for it)?
static func is_desktop(grabber: Node3D) -> bool:
	return grabber != null and grabber.is_in_group("desktop_hand")


func can_grab(grabber: Node3D, current: XRToolsGrabPoint) -> float:
	if not enabled:
		return 0.0
	# The desktop's hand has the one place and a controller's places are not for it.
	if is_desktop(grabber) != (role == DESKTOP):
		return 0.0
	if role == DESKTOP:
		return _weight(grabber) if current == null else 0.0
	var hand := hand_of(grabber)
	if current != null:
		# The second hand: the other end of the guitar, in the other hand.
		var held := current as ArcadeGuitarGrab
		if held == null or held.role == role or hand == held.hand_side or hand < 0:
			return 0.0
	if hand >= 0:
		if hand != hand_side:
			return 0.0
	elif role != BODY or hand_side != RIGHT:
		return 0.0
	return _weight(grabber)
