## CockpitSeat — the seat a sit-down driving cabinet is built with (ArcadeCabinetBuilder._build_cockpit).
##
## A seat you press to sit in, as a furniture Seat is, but part of the cabinet: it goes where the cabinet goes, is
## built and freed with its form, and is not an object of its own (never saved, never a pickable, never in the
## `seat` group). The sitting is SeatSitting's, the same as a Seat's, so one player is in one seat whichever kind.
##
## The head goes to `EyePoint`, which the builder puts at the height of the middle of the glass: a driver looks
## straight into the monitor (the cabinet's `racer` body is built for it). `StandPoint` is on the floor beside the seat
## (a cockpit's front is the dash), `SeatTrigger` the cushion you press. The cabinet being picked up or its form
## changing under the player lets them go.
class_name CockpitSeat
extends Node3D

signal seated_changed(on: bool)

var _sitting: SeatSitting


func _init() -> void:
	_sitting = SeatSitting.new(self)
	_sitting.seated_changed.connect(func(on: bool) -> void: seated_changed.emit(on))


func _ready() -> void:
	set_physics_process(false)
	# The cabinet is carried off with the player in its seat: they are put down beside it.
	var parent := get_parent()
	while parent != null and not (parent is XRToolsPickable):
		parent = parent.get_parent()
	if parent != null:
		(parent as XRToolsPickable).picked_up.connect(func(_p: Variant) -> void:
			if is_occupied():
				print("[Seat] %s: the cabinet was picked up with the player in it: standing them up" % name)
			stand())


func _exit_tree() -> void:
	# The form was changed, or the cabinet put away, with the player in it.
	if Seat.current == self:
		print("[Seat] %s: the form was rebuilt or the cabinet put away with the player in it" % name)
		stand()


func _physics_process(_delta: float) -> void:
	if Seat.current != self:
		set_physics_process(false)
		return
	# A cockpit on a moving base carries the player with it before the pin holds them.
	_sitting.follow()
	_sitting.pin()


func is_occupied() -> bool:
	return Seat.current == self


func sitting() -> SeatSitting:
	return _sitting


func toggle() -> void:
	if is_occupied():
		stand()
	else:
		sit()


func sit() -> bool:
	return _sitting.sit()


func stand() -> void:
	_sitting.stand()


## Where the eyes go: `EyePoint` in the world, -Z the way the driver looks (at the screen).
func eye_transform() -> Transform3D:
	var marker := find_child("EyePoint", true, false) as Node3D
	if marker != null:
		return marker.global_transform
	return global_transform * Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0))


## Where the feet go when the player gets up: `StandPoint`, beside the seat on the floor.
func stand_point() -> Vector3:
	var marker := find_child("StandPoint", true, false) as Node3D
	if marker != null:
		return marker.global_position
	return global_transform * Vector3(-0.6, 0.0, 0.0)


## The height of the floor the driver's feet are on: the platform's top, where this node stands.
func floor_y() -> float:
	return global_position.y
