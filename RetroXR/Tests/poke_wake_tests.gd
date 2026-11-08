## PokeWake: poke widgets out of a fingertip's reach stop polling, and a fingertip
## coming into reach (or a laser) wakes them in time to be pressed. A widget the
## physics query could never find must never sleep, or it ignores a finger.
##   godot --headless --path RetroXR res://Tests/poke_wake_tests.tscn
extends "res://Tests/test_suite.gd"

const FINGER := &"/poke_wake_tests/finger"
const FAR := Vector3(0, 4, 0)

var _finger: XRPositionalTracker


func _ready() -> void:
	_tracked_finger()
	await _sleep_and_wake()
	await _teleport_press()
	await _never_sleeps_unfindable()
	await _switched_off_stays_off()
	await _laser_wakes()
	await _slider_and_knob()
	await _kill_switch()
	XRServer.remove_tracker(_finger)
	_finish()


## A tracked hand: an XRController3D on a tracker of our own with a PokeTip at its
## origin, as appliance_pointer_tests drives VRButton's touch path.
func _tracked_finger() -> void:
	var tr := XRPositionalTracker.new()
	tr.name = FINGER
	tr.type = XRServer.TRACKER_CONTROLLER
	XRServer.add_tracker(tr)
	var origin := XROrigin3D.new()
	add_child(origin)
	var ctrl := XRController3D.new()
	ctrl.tracker = FINGER
	origin.add_child(ctrl)
	var tip := Node3D.new()
	tip.name = "PokeTip"
	ctrl.add_child(tip)
	_finger = tr
	_place(FAR)


func _place(at: Vector3) -> void:
	_finger.set_pose(&"default", Transform3D(Basis(), at), Vector3.ZERO, Vector3.ZERO,
		XRPose.XR_TRACKING_CONFIDENCE_HIGH)


func _ticks(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## A button with a cap and a 2 cm box the query can find, at `at`.
func _button(at: Vector3, with_shape := true) -> VRButton:
	var b := VRButton.new()
	var cap := MeshInstance3D.new()
	cap.name = "ButtonMesh"
	cap.mesh = BoxMesh.new()
	b.add_child(cap)
	if with_shape:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3.ONE * 0.02
		shape.shape = box
		b.add_child(shape)
	b.position = at
	add_child(b)
	return b


func _asleep_soon(w: Node) -> void:
	await _ticks(PokeWake.SLEEP_AFTER + 5)


func _sleep_and_wake() -> void:
	var b := _button(Vector3(2, 0, 0))
	await _ticks(2)
	_ok(b.is_processing(), "sleep/a new button polls at first")
	await _asleep_soon(b)
	_ok(not b.is_processing(), "sleep/out of every fingertip's reach it stops polling")
	_place(Vector3(2, 0, 0.4))
	await _ticks(2)
	_ok(b.is_processing(), "wake/a fingertip 40 cm away wakes it")
	_place(FAR)
	await _asleep_soon(b)
	_ok(not b.is_processing(), "sleep/and it sleeps again once the hand leaves")
	b.free()


## A hand that arrives in one frame (a test's tracked finger, a fast reach): the
## button must be awake and press before the finger has gone.
func _teleport_press() -> void:
	var b := _button(Vector3(-2, 0, 0))
	var fired := [0]
	b.button_pressed.connect(func() -> void: fired[0] += 1)
	await _asleep_soon(b)
	_ok(not b.is_processing(), "press/the button is asleep before the poke")
	_place(Vector3(-2, 0, 0))
	await _ticks(4)
	_ok(fired[0] == 1, "press/a finger put straight onto a sleeping button presses it once (%d)" % fired[0])
	_place(FAR)
	await _ticks(4)
	b.free()


func _never_sleeps_unfindable() -> void:
	var b := _button(Vector3(0, 0, 2), false)
	await _asleep_soon(b)
	_ok(b.is_processing(), "unfindable/a button with no shape never sleeps")
	b.free()
	var c := _button(Vector3(0, 0, -2))
	c.collision_layer = 1   # pointable bit cleared after _ready, as an owner might
	await _asleep_soon(c)
	_ok(c.is_processing(), "unfindable/a button off the pointable layer never sleeps")
	c.free()


func _switched_off_stays_off() -> void:
	var b := _button(Vector3(3, 0, 0))
	await _asleep_soon(b)
	b.set_interactive(false)
	b.collision_layer = VRButton.POINTABLE_LAYER   # still findable: the meta must hold it
	_place(Vector3(3, 0, 0.2))
	await _ticks(3)
	_ok(not b.is_processing(), "off/a fingertip does not wake a button switched off")
	b.set_interactive(true)
	_ok(b.is_processing(), "off/switched back on, it polls")
	b.set_meta(PokeWake.META_SUSPENDED, true)
	b.set_process(false)
	await _ticks(3)
	_ok(not b.is_processing(), "off/nor one focus mode has suspended")
	b.remove_meta(PokeWake.META_SUSPENDED)
	await _ticks(3)
	_ok(b.is_processing(), "off/lifted, the fingertip wakes it")
	_place(FAR)
	b.free()


func _laser_wakes() -> void:
	var b := _button(Vector3(-3, 0, 0))
	await _asleep_soon(b)
	var pointer := Node3D.new()
	add_child(pointer)
	b.pointer_event(XRToolsPointerEvent.new(XRToolsPointerEvent.Type.ENTERED, pointer, b,
		b.global_position, b.global_position))
	_ok(b.is_processing(), "laser/a laser landing on a sleeping button wakes it")
	await _asleep_soon(b)
	_ok(b.is_processing(), "laser/and it stays awake while hovered")
	b.pointer_event(XRToolsPointerEvent.new(XRToolsPointerEvent.Type.EXITED, pointer, b,
		b.global_position, b.global_position))
	await _asleep_soon(b)
	_ok(not b.is_processing(), "laser/the laser gone, it sleeps")
	b.set_selected(true)
	_ok(b.is_processing(), "laser/selected by its owner, it wakes")
	b.set_selected(false)
	pointer.free()
	b.free()


func _slider_and_knob() -> void:
	var slider := VRSlider.new()
	var sshape := CollisionShape3D.new()
	var sbox := BoxShape3D.new()
	sbox.size = Vector3.ONE * 0.03
	sshape.shape = sbox
	slider.add_child(sshape)
	slider.position = Vector3(0, 2, 2)
	add_child(slider)
	var knob := VRKnob.new()
	var pivot := Node3D.new()
	pivot.name = VRKnob.PIVOT_NAME
	knob.add_child(pivot)
	knob.target = pivot
	var kshape := CollisionShape3D.new()
	var kbox := BoxShape3D.new()
	kbox.size = Vector3.ONE * 0.03
	kshape.shape = kbox
	knob.add_child(kshape)
	knob.position = Vector3(0.3, 2, 2)
	add_child(knob)
	await _ticks(PokeWake.SLEEP_AFTER + 10)
	_ok(not slider.is_processing() and not knob.is_processing(), "slider/slider and knob sleep out of reach")
	_place(Vector3(0.15, 2, 2.2))
	await _ticks(2)
	_ok(slider.is_processing() and knob.is_processing(), "slider/a fingertip between them wakes both")
	_place(FAR)
	slider.free()
	knob.free()


func _kill_switch() -> void:
	PokeWake.enabled = false
	var b := _button(Vector3(4, 0, 0))
	await _asleep_soon(b)
	_ok(b.is_processing(), "switch/with PokeWake off, nothing sleeps")
	PokeWake.enabled = true
	await _asleep_soon(b)
	_ok(not b.is_processing(), "switch/on again, it does")
	b.free()
