## DrumSide self-tests -- a stick striking the side of a Taiko drum, headless and with no native extension.
##
##     "$godot" --headless --path RetroXR res://Tests/drum_side_tests.tscn
##
## Exits 0 when everything passes, 1 otherwise.
##
## The drum here is a stand-in with the real one's parts and tilt: a cylinder shell (0.185 m, 5 cm) turned 15 degrees about X, the four zones as nodes beside it. Covered: a head brought in against the
## right or the left side is a ka on that half; a slow one, one over the drum, one going out, one that stops short of it, and one that comes DOWN near the edge are not; the margin outside the wall counts; the
## shaft's second point strikes as the tip does; the head must go off the side before it strikes it again; no shell, no hit.
extends "res://Tests/test_suite.gd"

const CENTRE := Vector3(0.0, 0.9, 0.0)

var _drum: Node3D = null
var _shell: MeshInstance3D = null
var _zones: Array = []


func _ready() -> void:
	suite_tag = "drum_side"
	_build()
	_test_sides()
	_test_refusals()
	_test_points_and_rearm()
	_finish()


func _build() -> void:
	_drum = Node3D.new()
	add_child(_drum)
	_shell = MeshInstance3D.new()
	_shell.name = "DrumShell"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.185
	cylinder.bottom_radius = 0.185
	cylinder.height = 0.05
	_shell.mesh = cylinder
	# As the builder lays it: the mesh's Y turned onto the deck's Z, then the drum's own turn about X.
	_shell.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(15.0)) * Basis(Quaternion(Vector3.UP, Vector3.BACK)), CENTRE)
	_drum.add_child(_shell)
	for spec: Array in [["FaceLeft", &"don", 0], ["FaceRight", &"don", 1], ["RimLeft", &"ka", 0], ["RimRight", &"ka", 1]]:
		var cap := MeshInstance3D.new()
		cap.name = spec[0]
		cap.mesh = BoxMesh.new()
		_drum.add_child(cap)
		_zones.append({"name": spec[0], "cap": cap, "kind": spec[1], "half": spec[2]})


## A point of the shell's own frame, in the world.
func _at(x: float, y: float, z: float = 0.0) -> Vector3:
	return _shell.global_transform * Vector3(x, y, z)


func _in(x_from: float, x_to: float, y_from: float, y_to: float, delta: float) -> Dictionary:
	return DrumSide.crossing([_at(x_from, y_from)], [_at(x_to, y_to)], delta, _zones)


func _name_of(hit: Dictionary) -> String:
	return "" if hit.is_empty() else str((hit["zone"] as Dictionary)["name"])


func _test_sides() -> void:
	_eq(_name_of(_in(0.24, 0.15, 0.0, 0.0, 0.05)), "RimRight", "side/a head brought in from the right is a ka on the right half")
	_eq(_name_of(_in(-0.24, -0.15, 0.0, 0.0, 0.05)), "RimLeft", "side/and from the left on the left half")
	# The wall counts a little out of the shell: a stick is not a thread.
	_eq(_name_of(_in(0.21, 0.19, 0.0, 0.0, 0.05)), "RimRight", "side/just outside the shell's own wall already strikes it (the margin)")
	# Level with the shell, a little under it and well over its top (the head rises over the rim as it comes in).
	_eq(_name_of(_in(0.24, 0.15, 0.06, 0.06, 0.05)), "RimRight", "side/over the shell's top by 3.5 cm still strikes")
	_eq(_name_of(_in(0.24, 0.15, -0.045, -0.045, 0.05)), "RimRight", "side/and a little under it")
	# Sideways with some fall in it (a swing is never level): still the side.
	_eq(_name_of(_in(0.24, 0.15, 0.03, 0.0, 0.05)), "RimRight", "side/a swing that falls a little as it comes in strikes the side")


func _test_refusals() -> void:
	_ok(_in(0.24, 0.15, 0.0, 0.0, 2.0).is_empty(), "side/a slow touch (0.05 m/s) hits nothing")
	_ok(_in(0.24, 0.15, 0.12, 0.12, 0.05).is_empty(), "side/a head 12 cm over the drum goes over it")
	_ok(_in(0.15, 0.24, 0.0, 0.0, 0.05).is_empty(), "side/going out is no strike")
	_ok(_in(0.26, 0.205, 0.0, 0.0, 0.05).is_empty(), "side/a head that stops short of the wall hits nothing")
	_ok(_in(0.215, 0.19, 0.10, -0.02, 0.05).is_empty(), "side/a head coming DOWN near the edge, more down than in, is the top's, not the side's")
	_ok(DrumSide.crossing([_at(0.24, 0.0)], [_at(0.15, 0.0)], 0.0, _zones).is_empty(), "side/no time passed, nothing struck")
	_shell.visible = false
	_ok(_in(0.24, 0.15, 0.0, 0.0, 0.05).is_empty(), "side/a drum that is hidden is not struck")
	_shell.visible = true
	_ok(DrumSide.crossing([_at(0.24, 0.0)], [_at(0.15, 0.0)], 0.05, []).is_empty(), "side/no zones, no strike")
	_ok(DrumSide.clear([_at(0.0, 0.0)], []), "side/no zones, nothing to wait for")


func _test_points_and_rearm() -> void:
	# The shaft's own point strikes when the tip is nowhere near: the first point far off, the second coming in.
	var far := _at(0.5, 0.0, 0.5)
	var hit := DrumSide.crossing([far, _at(0.24, 0.0)], [far, _at(0.15, 0.0)], 0.05, _zones)
	_ok(not hit.is_empty() and int(hit["point"]) == 1 and _name_of(hit) == "RimRight", "side/a point up the shaft strikes as the tip does")
	# The faster point is the one that counts, and a hit is one hit.
	var both := DrumSide.crossing([_at(0.24, 0.0), _at(-0.24, 0.0)], [_at(0.20, 0.0), _at(-0.14, 0.0)], 0.05, _zones)
	_eq(_name_of(both), "RimLeft", "side/of two points that strike, the faster one's half")
	# It must go off the side to strike again.
	_ok(not DrumSide.clear([_at(0.20, 0.0)], _zones) and not DrumSide.clear([_at(0.26, 0.0), _at(0.17, 0.0)], _zones),
		"side/a head still on the drum's wall, or one of its points, has not cleared it")
	_ok(DrumSide.clear([_at(0.26, 0.0), _at(0.30, 0.1)], _zones), "side/and a head well off it has")
