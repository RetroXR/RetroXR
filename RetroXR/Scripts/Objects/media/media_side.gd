## MediaSide — which side of a two-sided medium (a Compact Cassette, an LP) goes into a deck, and how it is seated.
##
## The medium says which of its local axes is side A's face (`side_a_axis()`: a cassette's +Z, the label out of the
## deck; a record's +Y, the label up) and about which axis it is turned over (`flip_axis()`: a cassette about its
## upright, so the exposed tape edge stays down; a record about X). It records the hand's release pose
## (`release_basis_in`, as RetroDisc does): by the time a slot accepts it the snap zone has squared it to the seat,
## so the hand's side is gone one call earlier. The slot (MediaSlot, MediaTray) asks `side_by_hand` and seats it
## with `seat_for`; the deck plays that side (RetroAudioPlayer._side).
class_name MediaSide
extends RefCounted


## Whether `media` is two-sided.
static func is_two_sided(media: Node3D) -> bool:
	return media != null and media.has_method("side_a_axis") and media.has_method("release_basis_in")


## The side (0 = A, 1 = B) `media` was let go with facing the seat's way, `seat` its authored basis in `holder`'s
## frame. Side B when its side-A face points away from where side A faces in the seat.
static func side_by_hand(media: Node3D, holder: Node3D, seat: Basis) -> int:
	if not is_two_sided(media):
		return 0
	var held: Basis = media.call("release_basis_in", holder)
	var axis: Vector3 = media.call("side_a_axis")
	var faces := (held * axis).normalized()
	var want := (seat * axis).normalized()
	return 1 if faces.dot(want) < 0.0 else 0


## `seat` turned over for side B (about the medium's flip axis), as it is for side A otherwise.
static func seat_for(media: Node3D, seat: Basis, side: int) -> Basis:
	if side != 1 or not is_two_sided(media):
		return seat
	var axis: Vector3 = media.call("flip_axis") if media.has_method("flip_axis") else Vector3.UP
	return seat * Basis(axis, PI)
