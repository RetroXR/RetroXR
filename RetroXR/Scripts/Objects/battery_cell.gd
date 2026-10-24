## BatteryCell — an AA or AAA cell: a thing of its own, put in a battery bay's
## slot of its size (CellSlots) with the bay's cover off.
##
## Its middle at its origin, its + end toward +Z and the label's front toward +Y,
## as a BatteryAA<n> / BatteryAAA<n> seat is (RetroXR-models generic/battery).
## Round about its long axis, so it goes in at the roll the hand holds it at
## (CellSlot); the ghost over the bay shows the same, as a disc shows its spin,
## so nothing turns when it is let go.
class_name BatteryCell
extends XRToolsPickable

## "AA" or "AAA". Set by the scene; the cell joins CellSlots.group_for(size)
## there too, which is what a slot of that size takes.
@export var size := "AA"


## The type a save names it by: "battery_aa", "battery_aaa".
func save_type() -> String:
	return "battery_" + size.to_lower()


## The ghost's pose in a slot: `seat` turned by the roll `held` has about it.
## Called by XRToolsSnapZone.preview_pose_for.
func preview_basis_for(seat: Basis, held: Basis) -> Basis:
	return CellSlot.roll_basis(seat, held)
