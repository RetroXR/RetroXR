## A floor stand for a surround loudspeaker: a cast base, a column, and a plate a
## cabinet seats on.
##
## ── Why the seat needs no grab point ─────────────────────────────────────────
## XRToolsSnapZone puts a snapped object's GRAB POINT on the zone, or its origin
## when it carries none — which is the case ExpansionPort needed a foot for. A
## loudspeaker is baked with its origin at the BASE CENTRE, so a zone whose origin
## is the plate's top face lands the cabinet standing on the plate with no offset
## anywhere. That is also why the height in a stand's name is measured to that
## face: a satellite on the 1.2 m stand has its base at 1.2 m.
##
## ── Why there is no audio code here ─────────────────────────────────────────
## A stand carries no signal and publishes no cone. The cabinet on it goes on
## answering get_speaker_positions() from wherever it is standing, and a source
## reads that every frame rather than latching it — so raising a cabinet onto a
## stand moves its sound with no code here and none in the source.
class_name SpeakerStand
extends XRToolsPickable

## Every stand joins this, so a sweep can find them without testing the class.
const GROUP := "speaker_stand"

@onready var _seat: XRToolsSnapZone = $SpeakerSeat


func _ready() -> void:
	super()
	add_to_group("spawned")
	add_to_group(GROUP)


## The plate's snap zone, so a restore can seat a cabinet back on it.
func seat() -> XRToolsSnapZone:
	return _seat


## The cabinet standing on this stand, or null.
func seated_speaker() -> Loudspeaker:
	if _seat == null or not is_instance_valid(_seat.picked_up_object):
		return null
	return _seat.picked_up_object as Loudspeaker


## Put a cabinet back on the plate after a restore.
##
## The STAND records what is on it rather than the cabinet recording the stand:
## the zone is the stand's, and it keeps Loudspeaker ignorant of stands, which is
## the same reason it does not know which channel it carries.
func restore_seat(speaker: Loudspeaker) -> void:
	if _seat == null or speaker == null:
		return
	_seat.pick_up_object(speaker)


## Drop whatever is on the plate and free the stand. Looked for BY NAME by
## clear_scene and StorageBox, so the signature matters more than the body.
##
## The cabinet is dropped rather than freed with the stand: it is a separate prop
## the player owns, and a stand put away should not take a speaker with it.
func drop_and_free() -> void:
	if _seat != null and is_instance_valid(_seat.picked_up_object):
		_seat.drop_object()
	queue_free()
