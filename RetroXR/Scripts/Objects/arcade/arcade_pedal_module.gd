## ArcadePedalModule — a foot pedal on the floor in front of a cabinet, wired to its player's button 2.
##
## The kind is `pedal`. Time Crisis and its kin have one: the gun hides you while the pedal is up and
## peeks and shoots while it is down. MAME names it that player's BUTTON2 ("Foot Pedal" in namcos22.cpp
## and namcos23.cpp), which a light gun presses with its Aux A (libretro MAME's gun device makes Aux A its
## button 2, and BUTTON2's default sequence holds GUNCODE_BUTTON2) and a joypad with its A (input_retro's
## button_mapping). So a pedal is a switch on button 2, as on a real cabinet converted to another game.
##
## A headset reads no feet, so ArcadeInput keeps the pedal down while that player's gun is in a hand and
## lifts it to take cover: the gun hand's A or X or the `arcade_pedal` key (Space, a pad's RB) in every
## mode, the free hand's trigger or ducking in the other two (AppPrefs.arcade_pedal_mode, docs/dev/arcade.md
## "The pedal"). The plate shows it.
class_name ArcadePedalModule
extends ArcadeModule

## How far the plate tips down about its hinge when pressed: it rests toe-up at 18 degrees.
const PRESS_DEG := 15.0
## How long the plate takes to go all the way down (or up).
const PRESS_SECONDS := 0.08

## Whether the pedal is wired: pressing it reaches the core. A cabinet's own pedals all are; false
## leaves one a picture.
@export var active: bool = true

var _plate: Node3D = null
var _plate_rest := Transform3D()
## The hinge's axis passes through this point along X (the pedal's own frame).
var _hinge := Vector3.ZERO
var _pressed := false
## How far the plate is down, 0 up .. 1 down, as last drawn.
var _down := 0.0


func _init() -> void:
	kind = ArcadeProfiles.KIND_PEDAL


func attach(p_cabinet: RetroSystemModel) -> void:
	super.attach(p_cabinet)
	_plate = get_node_or_null("PedalPlate") as Node3D
	if _plate != null:
		_plate_rest = _plate.transform
	var hinge := get_node_or_null("PedalHinge") as Node3D
	if hinge != null:
		_hinge = hinge.position


## The port this pedal is wired to: its player's, and player 1's for one that names none (the shipped gun
## cabinet's single pedal, in the middle).
func port() -> int:
	return maxi(player, 0)


## Show the pedal held down or let up: ArcadeInput, with what it sent.
func show_pressed(down: bool) -> void:
	_pressed = down


## Whether the pedal is held down now.
func is_pressed() -> bool:
	return active and _pressed


## How far the plate is down as last drawn (0 up .. 1 down), for the tests and the probe.
func plate_down() -> float:
	return _down


func tick(delta: float) -> void:
	var want := 1.0 if _pressed else 0.0
	if _plate == null or _down == want:
		return
	_down = move_toward(_down, want, delta / PRESS_SECONDS)
	# About the hinge's own line: the toe comes down, the heel stays on its pin.
	var turn := Basis(Vector3.RIGHT, -deg_to_rad(PRESS_DEG) * _down)
	_plate.transform = Transform3D(turn, _hinge - turn * _hinge) * _plate_rest
