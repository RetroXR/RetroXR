## CellSlot — one battery's place in a bay: a snap zone at a model's
## BatteryAA<n> / BatteryAAA<n> seat that takes a cell of that size (CellSlots).
##
## A cell is round about its long axis, so it goes in at the roll it was held at:
## +Z (its + end) lies along the seat's +Z, and the label faces wherever the hand
## had it, as a disc keeps its spin in a tray. The zone holds what it picks up at
## its own pose, so the zone is what turns: about the seat's +Z, by the cell's
## roll, just before it takes the cell. Held end for end, the cell is measured as
## it would go in, + end first; a bay has one way round.
class_name CellSlot
extends XRToolsSnapZone

## The seat in the parent's frame, unturned: the cell's middle as seated, +Z to
## its + terminal, +Y out of the bay.
var seat := Transform3D()
## Radians about the seat's +Z the cell in it is turned by. Saved.
var roll := 0.0
## Set while restore puts a cell back at the roll the save gave.
var _keep_roll := false


## Radians about `seat`'s +Z that `held` is turned by, the rest of it (a tilt off
## the axis) thrown away. A cell held end for end is measured as it would go in.
static func roll_of(seat: Basis, held: Basis) -> float:
	var d := (seat.orthonormalized().inverse() * held.orthonormalized()).orthonormalized()
	if d.z.z < 0.0:
		d = d * Basis(Vector3.RIGHT, PI)
	var q := d.get_rotation_quaternion()
	# The twist about Z is (0, 0, q.z, q.w) normalised, its angle 2*atan2(z, w).
	return wrapf(2.0 * atan2(q.z, q.w), -PI, PI)


## `seat` turned by the roll `held` has about it: for a cell's preview ghost
## (preview_basis_for), so what the hand sees over the bay is what goes in.
static func roll_basis(seat: Basis, held: Basis) -> Basis:
	return seat * Basis(Vector3.BACK, roll_of(seat, held))


## Put `cell` in at `at_roll` (radians), as a save had it.
func seat_cell(cell: Node3D, at_roll: float) -> void:
	roll = at_roll
	_keep_roll = true
	pick_up_object(cell)
	_keep_roll = false


func pick_up_object(target: Node3D) -> void:
	if is_instance_valid(target) and target != picked_up_object and not _keep_roll:
		var parent := get_parent() as Node3D
		var at := parent.global_transform * seat if parent != null else seat
		roll = roll_of(at.basis, target.global_basis)
	transform = seat * Transform3D(Basis(Vector3.BACK, roll), Vector3.ZERO)
	super(target)
