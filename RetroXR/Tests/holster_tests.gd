## Holster self-tests -- the one rule for hardware that goes back where it came from, headless.
##
##     "$godot" --headless --path RetroXR res://Tests/holster_tests.tscn
##
## Exits 0 when everything passes, 1 otherwise.
##
## A thing a machine is wired to (a cabinet's gun, a drumstick, a guitar) carries `captive_well`, the snap zone
## round its seat. Covered: a seat is made a DROPPED zone and never a RANGE one; a thing let go within the
## desktop's reach of its seat goes back into ITS OWN seat, one let go further off is not put back (it falls),
## and one a hand still holds is not put back under it; a thing merely brought near does nothing; a seat that is
## already full, freed or missing is refused without an error.
extends "res://Tests/test_suite.gd"

const ZONE_SCENE := preload("res://addons/godot-xr-tools/objects/snap_zone.tscn")

## A pickable with a seat, as a LightGun and an ArcadeHeldGear have.
const SEATED := "extends XRToolsPickable\nvar captive_well: XRToolsSnapZone = null\n"

var _script: GDScript = null


func _ready() -> void:
	suite_tag = "holster"
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("[holster] TIMEOUT")
		get_tree().quit(1))
	_script = GDScript.new()
	_script.source_code = SEATED
	_script.reload()
	await _test_rule()
	await _test_refusals()
	_finish()


## One seat with its thing, the thing at `at` (world), and the zone in the tree where it stands.
func _seat(zone_at: Vector3, at: Vector3, label: String) -> Array:
	var zone := ZONE_SCENE.instantiate() as XRToolsSnapZone
	zone.name = "Seat_" + label
	zone.snap_require = "holster_test"
	zone.grab_distance = 0.1
	add_child(zone)
	zone.global_position = zone_at
	Holster.prepare_seat(zone)
	var thing := XRToolsPickable.new()
	thing.set_script(_script)
	thing.name = label
	thing.add_to_group("holster_test")
	thing.freeze = true
	thing.set("captive_well", zone)
	zone.snap_filter = func(obj: Node3D) -> bool: return obj == thing
	add_child(thing)
	thing.global_position = at
	return [zone, thing]


func _test_rule() -> void:
	var made := _seat(Vector3(0.0, 1.0, 0.0), Vector3(0.0, 1.3, 0.0), "near")
	var zone: XRToolsSnapZone = made[0]
	var thing: XRToolsPickable = made[1]
	await get_tree().process_frame

	zone.snap_mode = XRToolsSnapZone.SnapMode.RANGE
	Holster.prepare_seat(zone)
	_eq(zone.snap_mode, XRToolsSnapZone.SnapMode.DROPPED, "rule/a seat is made a DROPPED zone, never RANGE")
	zone.show_preview = true
	_ok(zone.can_preview(thing), "rule/fixture: a seat that shows its preview would draw the thing seated in it")
	Holster.prepare_seat(zone)
	_ok(not zone.can_preview(thing), "rule/a seat is never previewed: a thing in a hand near it is not drawn going in")

	await get_tree().physics_frame
	await get_tree().physics_frame
	_ok(zone.picked_up_object != thing, "rule/a thing brought near its seat does not go in by itself")
	_ok(is_equal_approx(Holster.distance_to_seat(thing), 0.3), "rule/its distance is measured to where the seat would lay it", str(Holster.distance_to_seat(thing)))
	_ok(Holster.in_reach(thing), "rule/0.3 m is within the desktop's reach (%.2f m)" % Holster.DESKTOP_REACH)
	_ok(Holster.stow(thing) and zone.picked_up_object == thing, "rule/let go near its seat it goes back")

	zone.drop_object()
	thing.global_position = Vector3(0.0, 1.0, Holster.DESKTOP_REACH + 0.4)
	_ok(not Holster.in_reach(thing) and not Holster.stow(thing) and zone.picked_up_object != thing,
		"rule/let go further off than the reach it is not put back (it falls)")

	thing.global_position = Vector3(0.0, 1.0, Holster.DESKTOP_REACH - 0.05)
	_ok(Holster.in_reach(thing) and Holster.stow(thing), "rule/just inside the reach it goes back")
	zone.drop_object()

	# Each thing goes to ITS OWN seat, whichever it is standing near.
	var other := _seat(Vector3(3.0, 1.0, 0.0), Vector3(3.0, 1.2, 0.0), "other")
	var zone2: XRToolsSnapZone = other[0]
	var thing2: XRToolsPickable = other[1]
	thing.global_position = Vector3(3.0, 1.1, 0.0)
	await get_tree().process_frame
	_ok(not Holster.in_reach(thing) and not Holster.stow(thing),
		"rule/a thing near ANOTHER seat is judged by its own, which is far off")
	_ok(Holster.stow(thing2) and zone2.picked_up_object == thing2 and zone.picked_up_object != thing2, "rule/and the other goes to its own")


func _test_refusals() -> void:
	var made := _seat(Vector3(0.0, 1.0, 5.0), Vector3(0.0, 1.1, 5.0), "refused")
	var zone: XRToolsSnapZone = made[0]
	var thing: XRToolsPickable = made[1]
	await get_tree().process_frame

	# A seat that holds something else already.
	var squatter := XRToolsPickable.new()
	squatter.name = "squatter"
	squatter.add_to_group("holster_test")
	add_child(squatter)
	zone.snap_filter = Callable()
	zone.pick_up_object(squatter)
	_ok(zone.picked_up_object == squatter, "refusal/fixture: the seat holds another thing")
	_ok(not Holster.stow(thing), "refusal/a full seat is not given a second thing")
	zone.drop_object()
	squatter.free()

	# No seat at all, and a seat already freed.
	var plain := Node3D.new()
	add_child(plain)
	_eq(Holster.distance_to_seat(plain), INF, "refusal/a thing with no seat is infinitely far from it")
	_ok(not Holster.stow(plain), "refusal/and is not put anywhere")
	zone.queue_free()
	await get_tree().process_frame
	_ok(not Holster.stow(thing) and Holster.well_of(thing) == null, "refusal/a freed seat is no seat")
	plain.queue_free()
