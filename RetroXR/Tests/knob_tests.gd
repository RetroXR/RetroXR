## VRKnob's thumbwheel drag (rim_drag) and its haptics: a straight drag along the
## rim turns the cap evenly and covers the whole sweep in one stroke, pushing past
## an end leaves no dead travel, and a held knob ticks per detent, bumps at the
## ends, and never rumbles for a turn no hand made.
##   godot --headless --path RetroXR res://Tests/knob_tests.tscn
extends "res://Tests/test_suite.gd"

const RIM := 0.008   # a Game Boy wheel's radius
const TRACKER := &"/knob_tests/hand"

var _ctrl: XRController3D
var _felt: Array[float] = []


func _ready() -> void:
	suite_tag = "knob"
	_hand()
	await get_tree().process_frame
	_rim_gearing()
	_rim_full_sweep_one_stroke()
	_rim_no_dead_travel()
	_rim_tangent_follows_box()
	_angle_mode_caps_a_straight_swipe()
	_detents_and_ends()
	_detent_rate_limit()
	_no_hand_no_rumble()
	_haptics_off()
	XRServer.remove_tracker(XRServer.get_tracker(TRACKER))
	_finish()


## A controller for the knobs to rumble. It is never moved: the cases drive the
## knob's tracking directly, as gb_camera_tests does.
func _hand() -> void:
	var tr := XRPositionalTracker.new()
	tr.name = TRACKER
	tr.type = XRServer.TRACKER_CONTROLLER
	XRServer.add_tracker(tr)
	var origin := XROrigin3D.new()
	add_child(origin)
	_ctrl = XRController3D.new()
	_ctrl.tracker = TRACKER
	origin.add_child(_ctrl)


## A 270° thumbwheel, silent at -270 and full at 0 as the DMG's, its axle the knob's
## Z, its box over the rim on +X.
func _wheel(rim_drag := true, value := 0.0) -> VRKnob:
	var k := VRKnob.new()
	var pivot := Node3D.new()
	pivot.name = VRKnob.PIVOT_NAME
	k.add_child(pivot)
	var shape := CollisionShape3D.new()
	shape.name = "Box"   # not "CollisionShape3D": the rim is found by type
	var box := BoxShape3D.new()
	box.size = Vector3(0.016, 0.012, 0.024)
	shape.shape = box
	shape.position = Vector3(RIM, 0, 0)
	k.add_child(shape)
	k.deg_at_zero = -270.0
	k.deg_at_one = 0.0
	k.value = value
	k.rim_drag = rim_drag
	k.rim_travel = 0.04
	k.position = Vector3(0, 1, 0)
	add_child(k)
	k.detent_felt.connect(func(m: float) -> void: _felt.append(m))
	return k


## Knob-local point to world.
func _at(k: VRKnob, x: float, y: float) -> Vector3:
	return k.to_global(Vector3(x, y, 0.0))


func _done(k: VRKnob) -> void:
	k._trigger_ctrl = null
	k.queue_free()
	_felt.clear()


## Half of rim_travel along the tangent is half the sweep; the cap turns with it.
func _rim_gearing() -> void:
	var k := _wheel()
	k._begin_rim(_at(k, RIM, 0.0))
	k._track_rim(_at(k, RIM, 0.02))
	_ok(absf(k.value - 0.5) < 0.001, "rim/2 cm of a 4 cm travel is half the sweep",
		"value %.4f" % k.value)
	_ok(absf(rad_to_deg(k.target.rotation.z) - -135.0) < 0.01, "rim/the cap turns with it",
		"%.3f deg" % rad_to_deg(k.target.rotation.z))
	# Movement across the rim (radially, or along the axle) turns nothing.
	k._track_rim(_at(k, RIM + 0.03, 0.02))
	k._track_rim(k.to_global(Vector3(RIM + 0.03, 0.02, 0.05)))
	_ok(absf(k.value - 0.5) < 0.001, "rim/moving off the rim, not along it, turns nothing",
		"value %.4f" % k.value)
	_done(k)


## The thumbwheel's whole point: one straight swipe from silent to full.
func _rim_full_sweep_one_stroke() -> void:
	var k := _wheel()
	k._begin_rim(_at(k, RIM, 0.0))
	for i in range(1, 11):
		k._track_rim(_at(k, RIM, 0.005 * i))
	_eq(k.value, 1.0, "rim/a 5 cm straight swipe goes silent to full")
	_done(k)


## Past an end the cap stays put; the way back turns it at once.
func _rim_no_dead_travel() -> void:
	var k := _wheel(true, 0.5)
	k._begin_rim(_at(k, RIM, 0.0))
	k._track_rim(_at(k, RIM, 0.10))
	_eq(k.value, 1.0, "rim/pushing past full stops at full")
	k._track_rim(_at(k, RIM, 0.09))
	_ok(absf(k.value - 0.75) < 0.001, "rim/coming back turns at once, no dead travel",
		"value %.4f" % k.value)
	_done(k)


## The tangent comes from where the box sits, not where the hand happens to be: a
## grab off to one side of the rim still drags along the rim.
func _rim_tangent_follows_box() -> void:
	var k := _wheel(true, 0.5)
	k._begin_rim(_at(k, RIM + 0.004, -0.006))
	k._track_rim(_at(k, RIM + 0.004, -0.006 + 0.01))
	_ok(absf(k.value - 0.75) < 0.001, "rim/the tangent is the box's rim, not the grab point's",
		"value %.4f" % k.value)
	# The box on the -X rim (a wheel showing through the other edge): the same
	# drag up turns it the other way, as the rim there moves the other way.
	var k2 := _wheel(true, 0.5)
	(k2.get_node("Box") as Node3D).position = Vector3(-RIM, 0, 0)
	k2._begin_rim(_at(k2, -RIM, 0.0))
	k2._track_rim(_at(k2, -RIM, 0.01))
	_ok(absf(k2.value - 0.25) < 0.001, "rim/a rim on the other side turns the other way",
		"value %.4f" % k2.value)
	_done(k)
	_done(k2)


## Why rim_drag exists: round the axle, the same straight swipe from the rim can
## never pass 90 degrees.
func _angle_mode_caps_a_straight_swipe() -> void:
	var k := _wheel(false)
	k._begin_track(_at(k, RIM, 0.0))
	for i in range(1, 101):
		k._track_world_point(_at(k, RIM, 0.005 * i))
	var turned := rad_to_deg(k.target.rotation.z) - -270.0
	_ok(turned < 90.0 and k.value < 0.34, "angle/a straight 50 cm swipe from the rim stays under 90 deg",
		"%.2f deg, value %.3f" % [turned, k.value])
	_done(k)


func _haptic_wheel(value := 0.0) -> VRKnob:
	var k := _wheel(true, value)
	k.haptics = true
	k.detents = 4
	k.detent_magnitude = 0.2
	k.center_magnitude = 0.6
	k.end_magnitude = 0.5
	k._trigger_ctrl = _ctrl
	return k


## Step by `dy` metres along the rim, `n` times, with the rate limit out of the way.
func _steps(k: VRKnob, from_y: float, dy: float, n: int) -> float:
	var y := from_y
	for i in n:
		y += dy
		k._last_tick_ms = -100000
		k._track_rim(_at(k, RIM, y))
	return y


## Silent to full over four detents: a tick at 1/4, the centre at 1/2, a tick at
## 3/4, the end stop at full, and nothing more for pushing on. Off the end no tick.
func _detents_and_ends() -> void:
	var k := _haptic_wheel()
	k._begin_rim(_at(k, RIM, 0.0))
	var y := _steps(k, 0.0, 0.001, 42)
	_eq(_felt, [0.2, 0.6, 0.2, 0.5] as Array[float], "haptics/detents, the centre, then the end stop")
	_felt.clear()
	y = _steps(k, y, 0.001, 10)
	_eq(_felt.size(), 0, "haptics/pushing on at the end does not bump again")
	y = _steps(k, y, -0.002, 1)
	_eq(_felt.size(), 0, "haptics/coming off the end does not tick")
	y = _steps(k, y, -0.05, 1)
	_eq(_felt, [0.5] as Array[float], "haptics/a jump across every detent to silent is one end stop")
	_done(k)


## Two detents crossed within DETENT_MIN_GAP_MS: one tick, not a buzz.
func _detent_rate_limit() -> void:
	var k := _haptic_wheel()
	k.detents = 20
	k.center_magnitude = 0.0
	k._begin_rim(_at(k, RIM, 0.0))
	k._last_tick_ms = -100000
	k._track_rim(_at(k, RIM, 0.0021))   # past 1/20
	k._track_rim(_at(k, RIM, 0.0041))   # past 2/20, the same instant
	_eq(_felt.size(), 1, "haptics/two detents in one instant are one tick")
	_done(k)


## set_value from an owner (netplay, a restore) and the desktop wheel are no hand
## on the cap: nothing rumbles.
func _no_hand_no_rumble() -> void:
	var k := _haptic_wheel()
	k._trigger_ctrl = null
	k.set_value(1.0)
	k.set_value(0.3)
	_eq(_felt.size(), 0, "haptics/set_value with no hand holding rumbles nothing")
	_done(k)


func _haptics_off() -> void:
	var k := _haptic_wheel()
	k.haptics = false
	k._begin_rim(_at(k, RIM, 0.0))
	_steps(k, 0.0, 0.001, 40)
	_eq(_felt.size(), 0, "haptics/off by default: a knob without it never rumbles")
	_done(k)
