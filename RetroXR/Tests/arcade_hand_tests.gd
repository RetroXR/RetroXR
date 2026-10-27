## Arcade hand self-tests — a headset's hands work a panel's controls (ArcadePanelHands): a fingertip presses a cap, the
## trigger takes hold of a stick, a wheel, a dial, a trackball, a gear lever, a motorbike's bars. Headless, no core, no
## ROM, no headset: a fake hand (an XRController3D on a tracker of its own) puts a fingertip and a trigger where the case
## says, on panels the cabinet really builds.
##
##     "$godot" --headless --path RetroXR res://Tests/arcade_hand_tests.tscn
##     "$godot" --headless --path RetroXR res://Tests/arcade_hand_tests.tscn -- --only=stick
##
## Exits 0 when everything passes, 1 otherwise.
##
## What a headless run can say: where a tip has to be to press or to take hold, what each control reads for a hand that
## has moved so far, that what the hands hold reaches the port the way an attached controller's does, that a panel the
## game does not use cannot be touched, and that a laser comes back when a hand is done. How it FEELS (the reach, the
## throw, the speed of a dial) is a headset's.
##
## Groups:
##   zone/     the pure half: how near a tip is to pressing a part
##   caps/     a fingertip presses a cap, and it holds, slides, shares and lets go
##   pedals/   a racer's two pedals under a finger
##   stick/    the trigger takes hold of a stick, which leans with the hand and comes back
##   twin/     two sticks, one a hand
##   wheel/    a steering wheel turns with the hand to the lock, and back to centre
##   dial/     a paddle dial turns, clockwise is right
##   ball/     a trackball rolls where the hand pushes it
##   lever/    a gear lever stays in high gear
##   bars/     a motorbike's bars lean it
##   cycle/    a bicycle's bars steer and tip, its crank is pedalled by a hand
##   slot/     two levers in one slot, one a hand each
##   fly/      a flight cockpit's stick (a long shaft, a long throw) and its throttle, which stays where the hand left it
##   input/    what the hands hold goes out like an attached controller's: the port, the bindings, the cap that sinks
##   laser/    a hand on a control has no laser; it is back when the hand is done, and the panel takes no press from it
##   carry/    a hand on a control cannot pick the cabinet up, and its squeeze does not attach
##   use/      a finger on a cap starts an attract game, and a hand on the panel is somebody at the cabinet
extends Node

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const PICKUP_SCENE := preload("res://addons/godot-xr-tools/functions/function_pickup.tscn")
var P := ArcadeGameProfile
var S := ArcadeCabinetSpecs

var _checks := 0
var _failed := 0
var _cases_failed := 0
var _only := ""
var _spawned: Array[Node] = []
var _hands: Array[Dictionary] = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7)
	get_tree().create_timer(240.0).timeout.connect(func() -> void:
		print("[hand] TIMED OUT")
		get_tree().quit(1))
	await _run()
	print("[hand] %d checks, %d case(s) failed" % [_checks, _cases_failed])
	print("[hand] RESULT=%s" % ("PASS" if _failed == 0 else "FAIL"))
	get_tree().quit(1 if _failed > 0 else 0)


func _ok(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		_cases_failed += 1
	print("[hand] %s  %s" % ["PASS" if ok else "FAIL", what])


func _wait(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _want(group: String) -> bool:
	return _only.is_empty() or _only == group


func _run() -> void:
	if _want("zone"):
		_group_zone()
	for g: Array in [["caps", _group_caps], ["pedals", _group_pedals], ["stick", _group_stick],
			["twin", _group_twin], ["wheel", _group_wheel], ["dial", _group_dial], ["ball", _group_ball],
			["lever", _group_lever], ["bars", _group_bars], ["rider", _group_rider], ["cycle", _group_cycle], ["slot", _group_slot], ["fly", _group_fly],
			["input", _group_input],
			["laser", _group_laser], ["carry", _group_carry], ["use", _group_use]]:
		if _want(str(g[0])):
			await (g[1] as Callable).call()
			await _clear()


# --- helpers -------------------------------------------------------------------

## A cabinet, switched on, wearing the form a game asks for ("" is the generic cabinet as it stands). Returns the
## system, its model, its input and player 1's panel.
func _rig(romset: String = "", frames: int = 6, with_profile: bool = false) -> Dictionary:
	var sys := SYSTEM_SCENE.instantiate() as RetroSystem
	sys.model_id = ArcadeProfiles.CABINET_MODEL_ID
	sys.systemid = "arcade"
	sys.position = Vector3(_spawned.size() * 4.0, 0, 0)
	sys.freeze = true
	add_child(sys)
	sys.add_to_group("spawned")
	_spawned.append(sys)
	await _wait(frames)
	var model := sys.get_model() as RetroSystemModelArcadeCabinet
	if not romset.is_empty():
		var base := S.variant("generic")
		base["variant"] = "generic"
		model.morph_to(S.for_game(base, P.for_romset(romset)))
		if with_profile:
			# What a board in the bay does besides the form: the panels learn the game (its gear lever, its caps).
			model.apply_game_profile(P.for_romset(romset))
		await _wait(2)
	sys.is_powered_on = true
	var panels := model.modules_of_kind(ArcadeProfiles.KIND_STICK_BUTTONS)
	return {"sys": sys, "model": model, "input": model.arcade_input(), "panel": panels[0] as ArcadeControlModule,
		"panels": panels}


func _clear() -> void:
	for h in _hands:
		_drop_hand(h)
	_hands.clear()
	for n in _spawned:
		if is_instance_valid(n):
			n.queue_free()
	_spawned.clear()
	await _wait(6)


## A hand: an XRController3D on a tracker of its own, its pose the identity, so its poke tip is 6 cm ahead of it along -Z.
func _hand(side: String = "right") -> Dictionary:
	var origin := XROrigin3D.new()
	add_child(origin)
	var ctrl := XRController3D.new()
	ctrl.tracker = StringName(side + "_hand")
	ctrl.pose = &"default"
	origin.add_child(ctrl)
	var tracker := XRControllerTracker.new()
	tracker.name = StringName(side + "_hand")
	XRServer.add_tracker(tracker)
	tracker.set_pose(&"default", Transform3D.IDENTITY, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	var h := {"origin": origin, "ctrl": ctrl, "tracker": tracker}
	_hands.append(h)
	return h


func _drop_hand(h: Dictionary) -> void:
	XRServer.remove_tracker(h["tracker"] as XRControllerTracker)
	if is_instance_valid(h["origin"]):
		(h["origin"] as Node).free()


## Put the hand's fingertip at `world`.
func _tip_at(h: Dictionary, world: Vector3) -> void:
	(h["origin"] as XROrigin3D).global_position = world + Vector3(0, 0, PokeTip.TIP_FORWARD)
	# The tip is remembered for the frame it was asked in; a case moves a hand several times in one.
	PokeTip._cache_frame = -1


func _trigger(h: Dictionary, value: float) -> void:
	(h["tracker"] as XRControllerTracker).set_input(&"trigger", value)


func _ctrl(h: Dictionary) -> XRController3D:
	return h["ctrl"] as XRController3D


## One step of the hands on `panel`, with these hands.
func _step(panel: ArcadeControlModule, hands: Array, delta: float = 0.016) -> void:
	var ctrls: Array = []
	for h: Dictionary in hands:
		ctrls.append(h["ctrl"])
	PokeTip._cache_frame = -1
	panel.update_hands(delta, ctrls, true)


func _bit(id: int) -> int:
	return 1 << id


## The D-pad bits the hands' thumbsticks come to through the player's bindings (the same mapping the port gets).
func _dpad(input: ArcadeInput, panel: ArcadeControlModule) -> int:
	return int(input._map_sticks(panel.hand_thumbstick(0), panel.hand_thumbstick(1))["btn"])


## The middle of a cap's face, `lift` metres proud of it, in the world.
func _cap_top(panel: ArcadeControlModule, node_name: String, lift: float = 0.002) -> Vector3:
	var cap := panel.find_child(node_name, true, false) as MeshInstance3D
	return cap.global_transform * Vector3(0, cap.mesh.get_aabb().size.y * 0.5 + lift, 0)


func _ball_at(panel: ArcadeControlModule, index: int = 0) -> Vector3:
	var pivot := panel.find_child("StickPivot" if index == 0 else "StickPivot2", true, false) as Node3D
	return pivot.global_transform * Vector3(0, 0, 0.085)


## A panel's own axes in the world, for moving a hand "right" or "toward the player".
func _right(panel: ArcadeControlModule) -> Vector3:
	return panel.global_transform.basis.x.normalized()


## Toward the player along the deck: the deck's -Y (its +Y runs up the slope to the monitor).
func _toward(panel: ArcadeControlModule) -> Vector3:
	return -panel.global_transform.basis.y.normalized()


## A laser the hand carries: the node VrPointerBlock switches off, with its ray.
func _laser(h: Dictionary) -> Node3D:
	var pointer := Node3D.new()
	pointer.name = "FunctionPointer"
	var ray := RayCast3D.new()
	ray.name = "RayCast"
	pointer.add_child(ray)
	_ctrl(h).add_child(pointer)
	return pointer


func _laser_on(pointer: Node3D) -> bool:
	return pointer.visible and (pointer.get_node("RayCast") as RayCast3D).enabled


## What a hand holds in place of an empty hand: a pickup that has picked something up (PokeTip.is_poking is false).
class FakePickup extends Node:
	var picked_up_object: Object = null


# --- zone ----------------------------------------------------------------------

func _group_zone() -> void:
	var cap := AABB(Vector3(-0.0155, -0.006, -0.0155), Vector3(0.031, 0.012, 0.031))
	var R := ArcadePanelHands
	_ok(R.poke_reading(Vector3(0, 0.006 + 0.002, 0), cap, true) < 0.5, "zone: a tip just over the face of a cap is well inside")
	_ok(R.poke_reading(Vector3(0, 0.006 + R.POKE_OUT * 0.99, 0), cap, true) <= 1.0
			and R.poke_reading(Vector3(0, 0.006 + R.POKE_OUT * 1.05, 0), cap, true) > 1.0,
		"zone: and a hand's hover over it ends at POKE_OUT above the face (%.0f mm)" % (R.POKE_OUT * 1000.0))
	_ok(R.poke_reading(Vector3(0.0155 + R.POKE_SIDE * 0.99, 0, 0), cap, true) <= 1.0
			and R.poke_reading(Vector3(0.0155 + R.POKE_SIDE * 1.05, 0, 0), cap, true) > 1.0,
		"zone: and its side at POKE_SIDE beyond the cap's edge (%.0f mm)" % (R.POKE_SIDE * 1000.0))
	_ok(R.poke_reading(Vector3(0, -0.006 - R.POKE_IN * 0.99, 0), cap, true) <= 1.0
			and R.poke_reading(Vector3(0, -0.006 - R.POKE_IN * 1.05, 0), cap, true) > 1.0,
		"zone: and through it to POKE_IN (a finger pushes the cap down)")
	var corner := Vector3(0.0155 + R.POKE_SIDE * 0.8, 0, 0.0155 + R.POKE_SIDE * 0.8)
	_ok(R.poke_reading(corner, cap, true) > 1.0 and R.poke_reading(corner, cap, false) <= 1.0,
		"zone: a round cap's corner is outside, a flat one's (an arrow) is not")
	_ok(R.poke_reading(Vector3(0.0235, 0, 0), cap, true) > 1.0 and R.poke_reading(Vector3(0.0235, 0, 0), cap, true, R.RELEASE_SCALE) <= 1.0,
		"zone: a press that has been made lets go further out (RELEASE_SCALE), as a button's does")
	_ok(R.poke_reading(Vector3.ZERO, cap, true) < R.poke_reading(Vector3(0.01, 0, 0), cap, true),
		"zone: the nearer the middle the lower the reading, which is how the nearest cap is picked")
	# A dancer's arrow is pressed by the body over its square (foot_on; the stage group does it through a rig).
	var arrow := AABB(Vector3(-0.25, -0.005, -0.25), Vector3(0.5, 0.01, 0.5))
	_ok(R.foot_on(Vector3(0, 0.005, 0), arrow), "zone: a body on the middle of an arrow's face is on it")
	_ok(R.foot_on(Vector3(0.25 + R.FOOT_MARGIN * 0.99, 0.005, 0), arrow) and not R.foot_on(Vector3(0.25 + R.FOOT_MARGIN * 1.05, 0.005, 0), arrow),
		"zone: and off its side at FOOT_MARGIN beyond the edge (a foot is wider than a point)")
	_ok(R.foot_on(Vector3(0, 0.005, -0.25 - R.FOOT_MARGIN * 0.99), arrow) and not R.foot_on(Vector3(0, 0.005, -0.25 - R.FOOT_MARGIN * 1.05), arrow),
		"zone: the same along the other way")
	_ok(R.foot_on(Vector3(0, 0.005 - R.FOOT_BELOW * 0.99, 0), arrow) and not R.foot_on(Vector3(0, 0.005 - R.FOOT_BELOW * 1.05, 0), arrow),
		"zone: the floor it stands on may be FOOT_BELOW under the arrow's top (a step up from the room's floor), no further")
	_ok(R.foot_on(Vector3(0, 0.005 + R.FOOT_ABOVE * 0.99, 0), arrow) and not R.foot_on(Vector3(0, 0.005 + R.FOOT_ABOVE * 1.05, 0), arrow),
		"zone: and FOOT_ABOVE over it, no more (a hand-high point is not a foot)")


# --- caps ----------------------------------------------------------------------

func _group_caps() -> void:
	var r := await _rig()
	var panel: ArcadeControlModule = r["panel"]
	var input: ArcadeInput = r["input"]
	var h := _hand()
	var B := ArcadeProfiles.BUTTON_BITS
	_tip_at(h, _cap_top(panel, "Btn1"))
	_step(panel, [h])
	_ok(panel.hand_buttons() == _bit(B[0]) and panel.hands_active(),
		"caps: a fingertip on the face of button 1 presses button 1 (and only it)")
	_tip_at(h, _cap_top(panel, "Btn1") + _right(panel) * 0.001)
	_step(panel, [h])
	_ok(panel.hand_buttons() == _bit(B[0]), "caps: the press holds while the finger stays")
	# A press is let go further out than it was made: 22 mm to the side is outside the zone it was made in (20.5) and
	# inside the one it lets go in (24.5), and holds with no grace at all.
	_tip_at(h, _cap_top(panel, "Btn1") + _toward(panel) * 0.022)
	_step(panel, [h], 0.5)
	_ok(panel.hand_buttons() == _bit(B[0]), "caps: a finger that has drifted 2 mm off the edge of the cap keeps it down (the release zone is wider)")
	# Lifted well clear (3 cm over the face): a moment's grace, then it is let go.
	_tip_at(h, _cap_top(panel, "Btn1") + panel.global_transform.basis.z * 0.03)
	_step(panel, [h], 0.02)
	_ok(panel.hand_buttons() == _bit(B[0]), "caps: a finger that has just gone keeps it down for CONTACT_GRACE (a dropped frame)")
	_step(panel, [h], 0.04)
	_ok(panel.hand_buttons() == 0 and not panel.hands_active(), "caps: and then it is up")
	# Sliding from a cap to the next without lifting: no gap between.
	_tip_at(h, _cap_top(panel, "Btn1"))
	_step(panel, [h])
	_tip_at(h, _cap_top(panel, "Btn2"))
	_step(panel, [h])
	_ok(panel.hand_buttons() == _bit(B[1]), "caps: a finger rolled onto the next cap presses it at once and lets the first go")
	# Between two caps (the middle of a 52 mm gap is outside both): nothing new, the last is kept for its grace.
	_tip_at(h, _cap_top(panel, "Btn1"))
	_step(panel, [h])
	var gap := (_cap_top(panel, "Btn1") + _cap_top(panel, "Btn4")) * 0.5
	_tip_at(h, gap)
	_step(panel, [h], 0.2)
	_ok(panel.hand_buttons() == 0, "caps: a finger in the gap between caps presses neither")
	# Two hands.
	var left := _hand("left")
	_tip_at(h, _cap_top(panel, "Btn1"))
	_tip_at(left, _cap_top(panel, "Btn2"))
	_step(panel, [h, left])
	_ok(panel.hand_buttons() == (_bit(B[0]) | _bit(B[1])), "caps: each hand presses a cap of its own, two at once")
	_tip_at(left, _cap_top(panel, "Btn1"))
	_step(panel, [h, left])
	_ok(panel.hand_buttons() == _bit(B[0]),
		"caps: a second hand rolled onto a cap already pressed shares it, and lets the one it was on go")
	_tip_at(h, _cap_top(panel, "Btn3") + panel.global_transform.basis.z * 0.2)
	_step(panel, [h, left], 0.2)
	_ok(panel.hand_buttons() == _bit(B[0]), "caps: and the cap stays down until BOTH hands have left it")
	_tip_at(left, _cap_top(panel, "Btn3") + panel.global_transform.basis.z * 0.2)
	_step(panel, [h, left], 0.2)
	_ok(panel.hand_buttons() == 0, "caps: and is up when the last has")
	# START.
	_tip_at(h, _cap_top(panel, "Start"))
	_step(panel, [h])
	_ok(panel.hand_buttons() == _bit(ArcadeProfiles.START_BIT), "caps: a finger on START presses START")
	_tip_at(h, _cap_top(panel, "Start") + panel.global_transform.basis.z * 0.2)
	_step(panel, [h], 0.2)
	# A hand that holds something (a gun, a pad) presses nothing.
	var pickup := FakePickup.new()
	pickup.name = "FunctionPickup"
	_ctrl(h).add_child(pickup)
	pickup.picked_up_object = panel
	_tip_at(h, _cap_top(panel, "Btn1"))
	_step(panel, [h])
	_ok(panel.hand_buttons() == 0, "caps: a hand holding something presses nothing")
	pickup.picked_up_object = null
	_step(panel, [h])
	_ok(panel.hand_buttons() == _bit(B[0]), "caps: and presses again when its hand is empty")
	# A button the game does not have cannot be pressed (a Pac-Man panel has none).
	panel.apply_profile(P.for_romset("pacman"))
	_ok(panel.hand_buttons() == 0, "caps: a cap the game stops using is not held down, even before the hands are stepped again")
	_step(panel, [h])
	_ok(panel.hand_buttons() == 0 and not panel.hands_active(), "caps: a button the game does not have is not pressed, and the press on it is let go")
	panel.apply_profile(null)
	# The whole panel gone (a one-player game's second panel): nothing on it works.
	var other := (r["panels"] as Array)[1] as ArcadeControlModule
	other.apply_profile(P.for_romset("robotron"))
	_tip_at(h, _cap_top(other, "Start"))
	_step(other, [h])
	_ok(other.hand_buttons() == 0, "caps: a panel the game does not use is dead to a hand")
	other.apply_profile(null)
	# The machine off: a hand holds nothing.
	_tip_at(h, _cap_top(panel, "Btn1"))
	_step(panel, [h])
	panel.update_hands(0.016, [h["ctrl"]], false)
	_ok(panel.hand_buttons() == 0, "caps: switched off, what a finger held is let go")
	# An inactive hand (a controller that is lost) does not press.
	_step(panel, [h])
	XRServer.remove_tracker(h["tracker"] as XRControllerTracker)
	_step(panel, [h])
	_ok(panel.hand_buttons() == 0, "caps: a controller that is lost presses nothing")
	_ok(input != null, "caps: (the cabinet has its input)")


# --- pedals --------------------------------------------------------------------

func _group_pedals() -> void:
	var r := await _rig("daytona")
	var panel: ArcadeControlModule = r["panel"]
	var h := _hand()
	var gas := panel.find_child("GasDeck", true, false) as MeshInstance3D
	var brake := panel.find_child("BrakeDeck", true, false) as MeshInstance3D
	_ok(gas != null and brake != null, "pedals: the cockpit has a gas and a brake tread")
	var gas_at := gas.global_transform * Vector3(0, 0.012, -0.05)
	_tip_at(h, gas_at)
	_step(panel, [h])
	_ok(panel.hand_buttons() == _bit(ControllerBindings.JOYPAD_R2), "pedals: a fingertip on the gas pad presses R2")
	var brake_at := brake.global_transform * Vector3(0, 0.012, -0.05)
	_tip_at(h, brake_at)
	_step(panel, [h])
	_ok(panel.hand_buttons() == _bit(ControllerBindings.JOYPAD_L2), "pedals: and on the brake pad L2, the gas let go")
	# A pedal under a finger goes down (the keyboard's R2 does the same): the zone is where the pedal RESTS, so the
	# finger that pushes it does not let it go.
	panel.show_state(_bit(ControllerBindings.JOYPAD_L2))
	for i in 20:
		panel.tick(0.016)
	# A long step: a zone that had gone down with the pedal would be let go of after the grace, not at once.
	_step(panel, [h], 0.2)
	_ok(panel.pedal_down("brake") > 0.9 and panel.hand_buttons() == _bit(ControllerBindings.JOYPAD_L2),
		"pedals: the pedal pressed down under the finger stays pressed (its zone does not follow it down)")
	_tip_at(h, brake_at + Vector3(0, 0.3, 0))
	_step(panel, [h], 0.2)
	_ok(panel.hand_buttons() == 0, "pedals: lifted away, it is up")


# --- stick ---------------------------------------------------------------------

func _group_stick() -> void:
	var r := await _rig()
	var panel: ArcadeControlModule = r["panel"]
	var input: ArcadeInput = r["input"]
	var h := _hand()
	var hands: ArcadePanelHands = panel.hands()
	var stick := panel.find_child("StickPivot", true, false) as Node3D
	var ball := _ball_at(panel)
	_tip_at(h, ball)
	_step(panel, [h])
	_ok(not hands.holds(&"stick", 0), "stick: a hand at the ball with its trigger up holds nothing")
	_trigger(h, 1.0)
	_step(panel, [h])
	_ok(hands.holds(&"stick", 0) and panel.hands_active(), "stick: the trigger pulled at the ball takes hold of the stick")
	_ok(panel.hand_buttons() == 0 and panel.hand_thumbstick(0) == Vector2.ZERO and _dpad(input, panel) == 0,
		"stick: and taking hold moves nothing")
	_tip_at(h, ball + _right(panel) * 0.03)
	_step(panel, [h])
	_ok(hands.stick_lean(0).is_equal_approx(Vector2(1.0, 0.0)), "stick: the hand 3 cm to the right leans it fully right (%s)" % str(hands.stick_lean(0)))
	_ok(_dpad(input, panel) == _bit(ControllerBindings.JOYPAD_RIGHT) and panel.hand_thumbstick(0).is_equal_approx(Vector2(1.0, 0.0))
			and panel.hand_buttons() == 0,
		"stick: and that is RIGHT, and the left thumbstick all the way right (the stick presses no pad button of its own)")
	_tip_at(h, ball - _right(panel) * 0.03)
	_step(panel, [h])
	_ok(_dpad(input, panel) == _bit(ControllerBindings.JOYPAD_LEFT), "stick: to the left, LEFT")
	_tip_at(h, ball + _toward(panel) * 0.03)
	_step(panel, [h])
	_ok(_dpad(input, panel) == _bit(ControllerBindings.JOYPAD_DOWN) and hands.stick_lean(0).y > 0.99,
		"stick: toward the player, DOWN (the deck's -Y)")
	_tip_at(h, ball - _toward(panel) * 0.03)
	_step(panel, [h])
	_ok(_dpad(input, panel) == _bit(ControllerBindings.JOYPAD_UP), "stick: away from the player, UP")
	_tip_at(h, ball + _right(panel) * 0.025 - _toward(panel) * 0.025)
	_step(panel, [h])
	_ok(_dpad(input, panel) == (_bit(ControllerBindings.JOYPAD_RIGHT) | _bit(ControllerBindings.JOYPAD_UP)),
		"stick: and a diagonal is both")
	_tip_at(h, ball + _right(panel) * 0.001)
	_step(panel, [h])
	_ok(_dpad(input, panel) == 0 and panel.hand_thumbstick(0) == Vector2.ZERO, "stick: a hand's 1 mm shake is inside the dead zone and the switches stay open")
	_tip_at(h, ball + _right(panel) * 0.008)
	_step(panel, [h])
	_ok(_dpad(input, panel) == 0 and panel.hand_thumbstick(0).x > 0.2,
		"stick: a quarter of the way over, the analog axis reads it but the switch is not shut (35%)")
	# The ball follows the hand, with no easing: one tick and it is where the hand has it.
	_tip_at(h, ball + _right(panel) * 0.03)
	_step(panel, [h])
	panel.tick(0.016)
	_ok(stick.basis.is_equal_approx(Basis.from_euler(Vector3(0.0, deg_to_rad(ArcadeControlModule.STICK_TILT_DEG), 0.0))),
		"stick: the ball is drawn leaned all the way over at once, to the hand")
	# Let go: the hands let go, and the stick eases back to rest on its own.
	_trigger(h, 0.0)
	_step(panel, [h])
	_ok(not hands.holds(&"stick", 0) and _dpad(input, panel) == 0 and not panel.hands_active(),
		"stick: the trigger let go releases the stick and the switches")
	for i in 60:
		panel.tick(0.016)
	_ok(panel.stick_lean().length() < 0.01 and stick.basis.is_equal_approx(Basis.IDENTITY),
		"stick: and it springs back upright")
	# A pull with the hand already at the trigger on arrival does not take hold: only the rising edge does.
	_tip_at(h, ball + Vector3(0, 0, 0.5))
	_trigger(h, 1.0)
	_step(panel, [h])
	_tip_at(h, ball)
	_step(panel, [h])
	_ok(not hands.holds(&"stick", 0), "stick: a trigger already held on the way in takes hold of nothing (sweeping past is safe)")
	_trigger(h, 0.0)
	_step(panel, [h])
	_trigger(h, 1.0)
	_step(panel, [h])
	_ok(hands.holds(&"stick", 0), "stick: pulled again at the ball it does")
	_trigger(h, 0.0)
	_step(panel, [h])
	# Out of reach.
	_tip_at(h, ball + Vector3(0.07, 0, 0))
	_trigger(h, 1.0)
	_step(panel, [h])
	_ok(not hands.holds(&"stick", 0), "stick: 7 cm from the ball is out of reach (%.0f cm)" % (ArcadePanelHands.STICK_REACH * 100.0))
	_trigger(h, 0.0)
	_step(panel, [h])
	# A hand holding something cannot take hold.
	var pickup := FakePickup.new()
	pickup.name = "FunctionPickup"
	_ctrl(h).add_child(pickup)
	pickup.picked_up_object = panel
	_tip_at(h, ball)
	_step(panel, [h])
	_trigger(h, 1.0)
	_step(panel, [h])
	_ok(not hands.holds(&"stick", 0), "stick: a hand holding a gun or a pad does not take hold of the stick")
	pickup.picked_up_object = null
	_trigger(h, 0.0)
	_step(panel, [h])
	# One hand holds it: another cannot.
	var left := _hand("left")
	_tip_at(h, ball)
	_tip_at(left, ball)
	_trigger(h, 1.0)
	_step(panel, [h, left])
	_trigger(left, 1.0)
	_step(panel, [h, left])
	_ok(hands.holds(&"stick", 0) and (hands.grabs()[0] as ArcadePanelHands.ControlGrab).holder == _ctrl(h),
		"stick: a stick one hand holds is not taken by the other")
	_trigger(h, 0.0)
	_trigger(left, 0.0)
	_step(panel, [h, left])
	# A hand that has been taken away (a lost tracker) lets go.
	_tip_at(h, ball)
	_trigger(h, 1.0)
	_step(panel, [h])
	_ok(hands.holds(&"stick", 0), "stick: (held again)")
	_tip_at(h, ball + Vector3(0.6, 0, 0))
	_step(panel, [h])
	_ok(not hands.holds(&"stick", 0), "stick: a hand that goes 35 cm from what it holds lets go (a stuck trigger)")
	_trigger(h, 0.0)
	_step(panel, [h])
	# A key holding the stick over: taking hold of it does not snap it, and the hand carries on from there.
	panel.show_state(_bit(ControllerBindings.JOYPAD_RIGHT))
	for i in 40:
		panel.tick(0.016)
	var leaned := panel.stick_lean()
	_tip_at(h, _ball_at(panel))
	_trigger(h, 1.0)
	_step(panel, [h])
	_ok(leaned.x > 0.99 and hands.stick_lean(0).is_equal_approx(leaned),
		"stick: taking hold of a stick a key holds over keeps it where it is, no jump")
	_tip_at(h, _ball_at(panel) - _right(panel) * 0.03)
	_step(panel, [h])
	_ok(hands.stick_lean(0).x < 0.01, "stick: and the hand brings it back by the width it was moved (%s)" % str(hands.stick_lean(0)))
	_trigger(h, 0.0)
	_step(panel, [h])
	panel.show_state(0)
	# A game with no stick (a gun game's panel has none): the stick is not there to take.
	panel.apply_profile(P.for_romset("ptblank"))
	_tip_at(h, ball)
	_trigger(h, 1.0)
	_step(panel, [h])
	_ok(not hands.holds(&"stick", 0), "stick: a stick the game does not use is not there to take hold of")
	_trigger(h, 0.0)
	_step(panel, [h])
	panel.apply_profile(null)


# --- twin ----------------------------------------------------------------------

func _group_twin() -> void:
	var r := await _rig("robotron")
	var panel: ArcadeControlModule = r["panel"]
	var hands: ArcadePanelHands = panel.hands()
	var input: ArcadeInput = r["input"]
	var right_hand := _hand("right")
	var left_hand := _hand("left")
	var ball1 := _ball_at(panel, 0)
	var ball2 := _ball_at(panel, 1)
	_ok(ball1.distance_to(ball2) > 0.08, "twin: Robotron's two sticks are apart (%.0f cm)" % (ball1.distance_to(ball2) * 100.0))
	_tip_at(left_hand, ball1)
	_tip_at(right_hand, ball2)
	_trigger(left_hand, 1.0)
	_trigger(right_hand, 1.0)
	_step(panel, [left_hand, right_hand])
	_ok(hands.holds(&"stick", 0) and hands.holds(&"stick", 1), "twin: one hand on each stick holds both")
	_tip_at(left_hand, ball1 + _right(panel) * 0.03)
	_tip_at(right_hand, ball2 - _toward(panel) * 0.03)
	_step(panel, [left_hand, right_hand])
	_ok(panel.hand_thumbstick(0).is_equal_approx(Vector2(1.0, 0.0)) and panel.hand_thumbstick(1).is_equal_approx(Vector2(0.0, 1.0)),
		"twin: the first stick is the left thumbstick, the second the right (%s, %s)" % [str(panel.hand_thumbstick(0)), str(panel.hand_thumbstick(1))])
	_ok(_dpad(input, panel) == _bit(ControllerBindings.JOYPAD_RIGHT),
		"twin: only the left stick's directions are the D-pad (the right stick is analog alone)")
	panel.tick(0.016)
	var s2 := panel.find_child("StickPivot2", true, false) as Node3D
	_ok(not s2.basis.is_equal_approx(Basis.IDENTITY), "twin: and the second stick leans with the hand that holds it")
	_trigger(left_hand, 0.0)
	_trigger(right_hand, 0.0)
	_step(panel, [left_hand, right_hand])
	_ok(not hands.holds(&"stick", 0) and not hands.holds(&"stick", 1) and panel.hand_thumbstick(1) == Vector2.ZERO,
		"twin: let go, both are free")


# --- wheel ---------------------------------------------------------------------

## The point of the wheel's rim at `turn` radians from its top, as the driver turns it (positive turn = the top goes
## to the driver's right, clockwise), in the world.
func _rim(panel: ArcadeControlModule, turn: float, scale: float = 1.0) -> Vector3:
	var pivot := panel.find_child("WheelPivot", true, false) as Node3D
	var mount := pivot.get_parent() as Node3D
	var rim := pivot.find_child("WheelRim", true, false) as MeshInstance3D
	var radius := ((rim.mesh as TorusMesh).outer_radius - 0.014) * scale
	return mount.global_transform * (Basis(Vector3.UP, -turn) * Vector3(0, 0, -radius))


func _group_wheel() -> void:
	var r := await _rig("daytona")
	var panel: ArcadeControlModule = r["panel"]
	var input: ArcadeInput = r["input"]
	var hands: ArcadePanelHands = panel.hands()
	var h := _hand()
	var lock := deg_to_rad(ArcadeControlModule.WHEEL_LOCK_DEG)
	var top := _rim(panel, 0.0)
	_tip_at(h, _rim(panel, 0.0, 2.0))
	_ok(not hands.reaching(_ctrl(h)), "wheel: a hand at twice the wheel's radius is not reaching for it (its laser stays)")
	_tip_at(h, _rim(panel, 0.0, 0.2))
	_trigger(h, 1.0)
	_step(panel, [h])
	_ok(not hands.holds(&"wheel"), "wheel: the hub is not where a wheel is held (a tip near the axle has no angle)")
	_trigger(h, 0.0)
	_step(panel, [h])
	_tip_at(h, top + panel.find_child("WheelPivot", true, false).get_parent().global_transform.basis.y * 0.2)
	_trigger(h, 1.0)
	_step(panel, [h])
	_ok(not hands.holds(&"wheel"), "wheel: nor 20 cm off the plane of the rim")
	_trigger(h, 0.0)
	_step(panel, [h])
	_tip_at(h, top)
	_trigger(h, 1.0)
	_step(panel, [h])
	_ok(hands.holds(&"wheel"), "wheel: the trigger on the rim takes hold of the wheel")
	_ok(is_zero_approx(hands.steer(&"wheel")) and panel.hand_thumbstick(0) == Vector2.ZERO, "wheel: and taking hold turns nothing")
	var quarter := deg_to_rad(ArcadeControlModule.WHEEL_LOCK_DEG) * 0.5
	var start_x := top.x
	_tip_at(h, _rim(panel, quarter))
	_step(panel, [h])
	_ok(_rim(panel, quarter).x > start_x + 0.05, "wheel: (the hand carried the top of the wheel to the driver's right)")
	_ok(is_equal_approx(hands.steer(&"wheel"), 0.5) and panel.hand_thumbstick(0).is_equal_approx(Vector2(0.5, 0.0)),
		"wheel: half the lock to the right reads half right (%.3f)" % hands.steer(&"wheel"))
	_ok(_dpad(input, panel) == _bit(ControllerBindings.JOYPAD_RIGHT),
		"wheel: and past the switch point RIGHT is pressed as well, as a thumbstick's is")
	_tip_at(h, _rim(panel, -quarter))
	_step(panel, [h])
	_ok(is_equal_approx(hands.steer(&"wheel"), -0.5) and _dpad(input, panel) == _bit(ControllerBindings.JOYPAD_LEFT),
		"wheel: the other way, left")
	# Past the lock the wheel stops; the hand winds nothing up, and turning back moves it at once.
	_tip_at(h, _rim(panel, lock * 0.9))
	_step(panel, [h])
	_tip_at(h, _rim(panel, lock * 1.8))
	_step(panel, [h])
	_ok(is_equal_approx(hands.steer(&"wheel"), 1.0), "wheel: it stops at the lock when the hand goes on")
	_tip_at(h, _rim(panel, lock * 1.6))
	_step(panel, [h])
	_ok(hands.steer(&"wheel") < 0.9, "wheel: and turning back turns it back at once (%.2f)" % hands.steer(&"wheel"))
	# The wheel stopped at the lock while the hand went on 0.8 of a lock further, and the hand has since come back 1.3
	# of one: the wheel has moved with it from where IT stopped, not to where the hand is (the hand wound nothing up).
	_tip_at(h, _rim(panel, quarter))
	_step(panel, [h])
	_ok(is_equal_approx(hands.steer(&"wheel"), -0.3), "wheel: a wheel the hand took past the lock follows the hand's turn from the lock (%.2f)" % hands.steer(&"wheel"))
	# Let go and take hold again at the top: drawn with the hand, no easing.
	_trigger(h, 0.0)
	_step(panel, [h])
	_tip_at(h, _rim(panel, 0.0))
	_trigger(h, 1.0)
	_step(panel, [h])
	_tip_at(h, _rim(panel, quarter))
	_step(panel, [h])
	input._left_vr_ctrl = _ctrl(h)
	input._process(0.016)
	panel.tick(0.016)
	_ok(absf(panel.steering() - hands.steer(&"wheel")) < 0.001, "wheel: the wheel is drawn where the hand has it, at once (%.3f)" % panel.steering())
	var pivot := panel.find_child("WheelPivot", true, false) as Node3D
	var drawn_top := pivot.global_transform * Vector3(0, 0, -0.15)
	_ok(drawn_top.x > (pivot.get_parent() as Node3D).global_position.x + 0.03,
		"wheel: the top of the drawn wheel is to the driver's right")
	# Let go: back to centre by itself.
	_trigger(h, 0.0)
	input._process(0.016)
	_ok(not hands.holds(&"wheel"), "wheel: the trigger let go releases the wheel")
	for i in 60:
		input._process(0.016)
		panel.tick(0.016)
	_ok(absf(panel.steering()) < 0.01, "wheel: and it comes back to centre (%.3f)" % panel.steering())
	input._left_vr_ctrl = null


# --- dial ----------------------------------------------------------------------

func _group_dial() -> void:
	var r := await _rig("pong")
	var panel: ArcadeControlModule = r["panel"]
	var hands: ArcadePanelHands = panel.hands()
	var input: ArcadeInput = r["input"]
	var h := _hand()
	var dial := panel.find_child("DialPivot", true, false) as Node3D
	_ok(dial != null, "dial: Pong has a paddle dial")
	var knob := dial.global_transform * Vector3(0, 0, 0.012)
	var radius := 0.02
	var base := panel.global_transform
	# A point on the knob, `a` radians clockwise seen by the player from its right-hand side.
	var at := func(a: float) -> Vector3:
		return knob + base.basis * (Basis(Vector3.BACK, -a) * Vector3(radius, 0, 0))
	_tip_at(h, at.call(0.0))
	_trigger(h, 1.0)
	_step(panel, [h])
	_ok(hands.holds(&"dial"), "dial: the trigger at the knob takes hold of the dial")
	_ok(panel.hand_thumbstick(0) == Vector2.ZERO, "dial: and a dial held still sends nothing")
	# A quarter turn clockwise in a quarter second: one turn a second, the speed holding RIGHT turns it at.
	for i in 15:
		_tip_at(h, at.call(PI * 0.5 * float(i + 1) / 15.0))
		_step(panel, [h], 0.25 / 15.0)
	_ok(panel.hand_thumbstick(0).x > 0.9, "dial: turned clockwise at a turn a second it reads full right (%.2f)" % panel.hand_thumbstick(0).x)
	_ok(_dpad(input, panel) == _bit(ControllerBindings.JOYPAD_RIGHT), "dial: clockwise is RIGHT")
	_ok(absf(hands.dial_angle() - PI * 0.5) < 0.05, "dial: and the knob has turned a quarter of a turn (%.2f rad)" % hands.dial_angle())
	panel.tick(0.016)
	# The knob's mark points up the deck at rest; turned a quarter clockwise seen by the player it points to the right.
	var mark := panel.global_transform.basis.inverse() * (dial.global_transform.basis * Vector3(0, 1, 0))
	_ok(mark.x > 0.9, "dial: and it is drawn turned with the hand, clockwise (the mark now points right: %s)" % str(mark))
	# Anticlockwise: left.
	for i in 15:
		_tip_at(h, at.call(PI * 0.5 - PI * 0.5 * float(i + 1) / 15.0))
		_step(panel, [h], 0.25 / 15.0)
	_ok(panel.hand_thumbstick(0).x < -0.9 and _dpad(input, panel) == _bit(ControllerBindings.JOYPAD_LEFT),
		"dial: anticlockwise is LEFT")
	# Held and still: the speed goes to nothing.
	for i in 6:
		_step(panel, [h], 0.05)
	_ok(absf(panel.hand_thumbstick(0).x) < 0.05, "dial: and held still again it sends nothing (the dial is a speed, not a place)")
	_trigger(h, 0.0)
	_step(panel, [h])
	_ok(not hands.holds(&"dial") and panel.hand_thumbstick(0) == Vector2.ZERO, "dial: let go")
	# A key turns the dial the same way a hand does: RIGHT is clockwise.
	var start := panel.dial_angle()
	var before := hands.dial_angle()
	var start_mark := panel.global_transform.basis.inverse() * (dial.global_transform.basis * Vector3(0, 1, 0))
	panel.show_state(_bit(ControllerBindings.JOYPAD_RIGHT))
	for i in 7:
		panel.tick(1.0 / 60.0)
	var key_mark := panel.global_transform.basis.inverse() * (dial.global_transform.basis * Vector3(0, 1, 0))
	var turned := wrapf(panel.dial_angle() - start, -PI, PI)
	# Clockwise seen by the player by `turned` takes (x, y) to (x cos + y sin, y cos - x sin) in the panel's plane.
	var expected := Vector3(start_mark.x * cos(turned) + start_mark.y * sin(turned),
		start_mark.y * cos(turned) - start_mark.x * sin(turned), start_mark.z)
	_ok(turned > 0.5 and before == hands.dial_angle() and key_mark.distance_to(expected) < 0.05,
		"dial: and holding RIGHT turns the knob clockwise too (the same way round as a hand)")


# --- ball ----------------------------------------------------------------------

func _group_ball() -> void:
	var r := await _rig("centiped")
	var panel: ArcadeControlModule = r["panel"]
	var hands: ArcadePanelHands = panel.hands()
	var input: ArcadeInput = r["input"]
	var h := _hand()
	var ball := panel.find_child("BallPivot", true, false) as Node3D
	_ok(ball != null, "ball: Centipede has a trackball")
	var centre := ball.global_position
	_tip_at(h, centre)
	_trigger(h, 1.0)
	_step(panel, [h])
	_ok(hands.holds(&"ball"), "ball: the trigger at the ball takes hold of it")
	var speed := ArcadeControlModule.BALL_SPEED * 0.038
	for i in 6:
		_tip_at(h, centre + _right(panel) * speed * 0.016 * float(i + 1))
		_step(panel, [h], 0.016)
	_ok(panel.hand_thumbstick(0).x > 0.9 and _dpad(input, panel) == _bit(ControllerBindings.JOYPAD_RIGHT),
		"ball: the hand pushing at the surface speed the picture rolls at reads full right (%s)" % str(panel.hand_thumbstick(0)))
	var rest := ball.basis
	panel.tick(0.1)
	_ok(not ball.basis.is_equal_approx(rest), "ball: and the drawn ball rolls with it")
	var p := centre + _right(panel) * speed * 0.016 * 6.0
	for i in 6:
		p += _toward(panel) * speed * 0.016
		_tip_at(h, p)
		_step(panel, [h], 0.016)
	_ok(panel.hand_thumbstick(0).y < -0.4, "ball: toward the player rolls it DOWN (%s)" % str(panel.hand_thumbstick(0)))
	for i in 8:
		_step(panel, [h], 0.016)
	_ok(panel.hand_thumbstick(0).length() < 0.1, "ball: a hand that stops stops the ball (a trackball is a speed)")
	_trigger(h, 0.0)
	_step(panel, [h])
	_ok(not hands.holds(&"ball"), "ball: let go")


# --- lever ---------------------------------------------------------------------

## The knob's place in the world with the lever thrown `amount` of the way (0 low .. 1 high); the lever is put back as it was.
func _knob_at(lever: Node3D, rest: Basis, amount: float) -> Vector3:
	lever.basis = rest * Basis(Vector3.RIGHT, -deg_to_rad(ArcadeControlModule.SHIFT_DEG) * amount)
	var knob := lever.global_transform * Vector3(0, 0, 0.125)
	lever.basis = rest
	return knob


## `frames` frames of the hands on `panel` the way the cabinet runs them: the hands' buttons are what the panel is shown. Returns how many
## times each pad bit in `bits` went down.
func _lever_frames(panel: ArcadeControlModule, h: Dictionary, bits: Array, frames: int) -> Dictionary:
	var downs := {}
	for b: int in bits:
		downs[b] = 0
	var last := 0
	for i in frames:
		_step(panel, [h])
		var mask := panel.hand_buttons()
		panel.show_state(mask)
		panel.tick(0.016)
		for b: int in bits:
			if (mask >> b) & 1 == 1 and (last >> b) & 1 == 0:
				downs[b] = int(downs[b]) + 1
		last = mask
	return downs


## The hand moved along `plan` ([[tip, frames], ...]) with the pad bit `bit` watched all the way: how many times it went down.
func _lever_run(panel: ArcadeControlModule, h: Dictionary, bit: int, plan: Array) -> int:
	var downs := 0
	var last := 0
	for leg: Array in plan:
		_tip_at(h, leg[0])
		for i in int(leg[1]):
			_step(panel, [h])
			var mask := panel.hand_buttons()
			panel.show_state(mask)
			panel.tick(0.016)
			if (mask >> bit) & 1 == 1 and (last >> bit) & 1 == 0:
				downs += 1
			last = mask
	return downs


func _group_lever() -> void:
	# A shifter MAME holds (Pole Position, button 3): the button is down for as long as the lever is high.
	var r := await _rig("polepos", 6, true)
	var panel: ArcadeControlModule = r["panel"]
	var hands: ArcadePanelHands = panel.hands()
	var h := _hand()
	var lever := panel.find_child("ShifterPivot", true, false) as Node3D
	_ok(lever != null and panel.shift_config() == {"button": 3, "toggle": false},
		"lever: Pole Position has a gear lever, on button 3, held (%s)" % str(panel.shift_config()))
	var y := _bit(ArcadeProfiles.button_bit(3))
	var rest := lever.basis
	var knob_rest := _knob_at(lever, rest, 0.0)
	var knob_part := _knob_at(lever, rest, 0.3)
	var knob_thrown := _knob_at(lever, rest, 1.0)
	_tip_at(h, knob_rest)
	_trigger(h, 1.0)
	_step(panel, [h])
	_ok(hands.holds(&"lever") and panel.hand_buttons() == 0, "lever: the trigger at the knob takes hold of the lever, in low gear")
	_tip_at(h, knob_part)
	_step(panel, [h])
	_ok(panel.hand_buttons() == 0 and hands.lever_throw() > 0.2 and hands.lever_throw() < 0.4,
		"lever: a third of the way over is still low gear (%.2f)" % hands.lever_throw())
	_tip_at(h, knob_thrown)
	_step(panel, [h])
	_ok(panel.hand_buttons() == y and hands.lever_throw() > 0.95,
		"lever: thrown it is high gear, and the game's own button (3, not button 1) is down")
	_trigger(h, 0.0)
	_step(panel, [h])
	_ok(not hands.holds(&"lever") and panel.hand_buttons() == y,
		"lever: and it STAYS in high gear when let go, as a gear lever does")
	_tip_at(h, knob_thrown)
	_trigger(h, 1.0)
	_step(panel, [h])
	_tip_at(h, knob_rest)
	_step(panel, [h])
	_trigger(h, 0.0)
	_step(panel, [h])
	_ok(panel.hand_buttons() == 0, "lever: pulled back it is low gear again")
	# Drawn with the hand.
	_tip_at(h, knob_thrown)
	_trigger(h, 1.0)
	_step(panel, [h])
	_tip_at(h, knob_thrown)
	var input: ArcadeInput = r["input"]
	input._left_vr_ctrl = _ctrl(h)
	input._process(0.016)
	panel.tick(0.016)
	_ok(panel.shift_amount() > 0.95, "lever: the drawn lever is where the hand has it (%.2f)" % panel.shift_amount())
	_trigger(h, 0.0)
	input._process(0.016)
	input._left_vr_ctrl = null
	await _clear()

	# A shifter MAME makes a toggle (Out Run, button 3): every change of gear is ONE tap of the button, never a held press.
	r = await _rig("outrun", 6, true)
	panel = r["panel"]
	hands = panel.hands()
	h = _hand()
	lever = panel.find_child("ShifterPivot", true, false) as Node3D
	_ok(lever != null and panel.shift_config() == {"button": 3, "toggle": true},
		"lever: Out Run's is on button 3 and a toggle (%s)" % str(panel.shift_config()))
	rest = lever.basis
	knob_rest = _knob_at(lever, rest, 0.0)
	var knob_mid := _knob_at(lever, rest, 0.5)
	var knob_hi := _knob_at(lever, rest, 0.7)
	var knob_lo := _knob_at(lever, rest, 0.3)
	knob_thrown = _knob_at(lever, rest, 1.0)
	_tip_at(h, knob_rest)
	_trigger(h, 1.0)
	var taps := _lever_frames(panel, h, [ArcadeProfiles.button_bit(3)], 3)
	_ok(hands.holds(&"lever") and int(taps[ArcadeProfiles.button_bit(3)]) == 0 and not panel.shift_high(),
		"lever: taken in low gear it taps nothing")
	_tip_at(h, knob_thrown)
	taps = _lever_frames(panel, h, [ArcadeProfiles.button_bit(3)], 25)
	_ok(int(taps[ArcadeProfiles.button_bit(3)]) == 1 and panel.shift_high(),
		"lever: thrown it taps button 3 ONCE, and the lever is high (%d taps)" % int(taps[ArcadeProfiles.button_bit(3)]))
	_ok(panel.hand_buttons() == 0, "lever: and the button is up again, not held")
	_trigger(h, 0.0)
	taps = _lever_frames(panel, h, [ArcadeProfiles.button_bit(3)], 20)
	_ok(int(taps[ArcadeProfiles.button_bit(3)]) == 0 and panel.shift_high() and panel.hand_buttons() == 0,
		"lever: let go it stays high and taps nothing more")
	for i in 30:
		panel.tick(0.016)
	_ok(panel.shift_amount() > 0.95, "lever: and is drawn high")
	# A wobble about the middle, from the high side, shifts nothing: it takes 40% to go back.
	_tip_at(h, knob_thrown)
	_trigger(h, 1.0)
	_lever_frames(panel, h, [ArcadeProfiles.button_bit(3)], 3)
	var wobble := 0
	for i in 12:
		_tip_at(h, knob_mid if i % 2 == 0 else knob_hi)
		wobble += int(_lever_frames(panel, h, [ArcadeProfiles.button_bit(3)], 4)[ArcadeProfiles.button_bit(3)])
	_ok(wobble == 0 and panel.shift_high(), "lever: a hand that wobbles about the middle changes no gear (%d taps)" % wobble)
	_tip_at(h, knob_lo)
	taps = _lever_frames(panel, h, [ArcadeProfiles.button_bit(3)], 25)
	_ok(int(taps[ArcadeProfiles.button_bit(3)]) == 1 and not panel.shift_high(), "lever: pulled back it taps once more, and the lever is low")
	# Two changes in a hurry are two taps, never one long press: the second waits for the first.
	_tip_at(h, knob_thrown)
	var quick := _lever_frames(panel, h, [ArcadeProfiles.button_bit(3)], 1)
	_tip_at(h, knob_rest)
	var rest_of := _lever_frames(panel, h, [ArcadeProfiles.button_bit(3)], 45)
	_ok(int(quick[ArcadeProfiles.button_bit(3)]) + int(rest_of[ArcadeProfiles.button_bit(3)]) == 2 and not panel.shift_high()
			and panel.hand_buttons() == 0, "lever: two changes in a hurry are two taps, and the lever ends where the hand left it")
	# Three changes inside one tap: three taps, queued behind it, and the lever ends where the hand left it (high).
	var burst := _lever_run(panel, h, ArcadeProfiles.button_bit(3), [[knob_thrown, 1], [knob_rest, 2], [knob_thrown, 90]])
	_ok(burst == 3 and panel.shift_high() and panel.hand_buttons() == 0,
		"lever: a flurry of three changes is three taps, one after the other (%d) and ends high" % burst)
	_trigger(h, 0.0)
	_step(panel, [h])
	await _clear()

	# A sequential box (Super Monaco GP: up on 2, down on 1) taps `up` going high and `down` going low.
	r = await _rig("smgp", 6, true)
	panel = r["panel"]
	hands = panel.hands()
	h = _hand()
	lever = panel.find_child("ShifterPivot", true, false) as Node3D
	_ok(lever != null and panel.shift_config() == {"up": 2, "down": 1}, "lever: Super Monaco GP's is a sequential box, up on 2 and down on 1 (%s)" % str(panel.shift_config()))
	rest = lever.basis
	knob_rest = _knob_at(lever, rest, 0.0)
	knob_thrown = _knob_at(lever, rest, 1.0)
	var up_bit := ArcadeProfiles.button_bit(2)
	var down_bit := ArcadeProfiles.button_bit(1)
	_tip_at(h, knob_rest)
	_trigger(h, 1.0)
	_lever_frames(panel, h, [up_bit, down_bit], 2)
	_tip_at(h, knob_thrown)
	taps = _lever_frames(panel, h, [up_bit, down_bit], 25)
	_ok(int(taps[up_bit]) == 1 and int(taps[down_bit]) == 0 and panel.shift_high(), "lever: thrown it taps UP once and the lever is high")
	_tip_at(h, knob_rest)
	taps = _lever_frames(panel, h, [up_bit, down_bit], 25)
	_ok(int(taps[up_bit]) == 0 and int(taps[down_bit]) == 1 and not panel.shift_high(), "lever: pulled back it taps DOWN once and the lever is low")
	_trigger(h, 0.0)
	_step(panel, [h])
	await _clear()


# --- bars ----------------------------------------------------------------------

func _group_bars() -> void:
	var r := await _rig("hangon")
	var panel: ArcadeControlModule = r["panel"]
	var hands: ArcadePanelHands = panel.hands()
	var h := _hand()
	var grip := panel.find_child("BarGripR", true, false) as Node3D
	_ok(grip != null, "bars: the bike has handlebars with grips")
	var at := grip.global_position
	_tip_at(h, at)
	_trigger(h, 1.0)
	_step(panel, [h])
	_ok(hands.holds(&"bars") and is_zero_approx(hands.steer(&"bars")), "bars: the trigger on a grip takes hold of the bars")
	_tip_at(h, at + Vector3(ArcadePanelHands.BARS_THROW * 0.5, 0, 0))
	_step(panel, [h])
	_ok(is_equal_approx(hands.steer(&"bars"), 0.5) and panel.hand_thumbstick(0).is_equal_approx(Vector2(0.5, 0.0)),
		"bars: pushed 7.5 cm to the right, half a lean to the right (%.2f)" % hands.steer(&"bars"))
	_tip_at(h, at + Vector3(-ArcadePanelHands.BARS_THROW * 2.0, 0, 0))
	_step(panel, [h])
	var input: ArcadeInput = r["input"]
	_ok(is_equal_approx(hands.steer(&"bars"), -1.0) and _dpad(input, panel) == _bit(ControllerBindings.JOYPAD_LEFT),
		"bars: and as far to the left as it goes, a full lean left")
	var lean := panel.find_child("LeanPivot", true, false) as Node3D
	input._left_vr_ctrl = _ctrl(h)
	input._process(0.016)
	panel.tick(0.016)
	_ok(lean.global_basis.y.x < -0.1, "bars: the bike is drawn leaning left with them")
	_trigger(h, 0.0)
	input._process(0.016)
	_ok(not hands.holds(&"bars"), "bars: let go")
	input._left_vr_ctrl = null


# --- rider ---------------------------------------------------------------------

## A rider's rail (Top Skater, Alpine Surfer, Alpine Racer): taken at a side grip it steers the plate as a bike's bars do, a full throw of the hand is still within the let-go
## distance (the middle of the rail is the middle of its two grips, 34 cm out), a hand far off has lost it, and START on its crossbar is pressed by a finger.
func _group_rider() -> void:
	for romset: String in ["topskatr", "alpines", "alpinerd"]:
		var r := await _rig(romset)
		var panel: ArcadeControlModule = r["panel"]
		var input: ArcadeInput = r["input"]
		var hands: ArcadePanelHands = panel.hands()
		var h := _hand()
		var grip := panel.find_child("BarGripR", true, false) as Node3D
		var lean := panel.find_child("LeanPivot", true, false) as Node3D
		_ok(grip != null and lean != null and panel.find_child("BarGripL", true, false) != null, "rider: %s has a rail with a grip each side on a plate that leans" % romset)
		if grip == null or lean == null:
			continue
		var at := grip.global_position
		_tip_at(h, at)
		_trigger(h, 1.0)
		_step(panel, [h])
		_ok(hands.holds(&"bars") and is_zero_approx(hands.steer(&"bars")), "rider: %s: the trigger on a grip takes hold of the rail" % romset)
		_tip_at(h, at + Vector3(ArcadePanelHands.BARS_THROW, 0, 0))
		_step(panel, [h])
		var far: float = (panel.find_child("Handlebars", true, false) as Node3D).global_position.distance_to(at + Vector3(ArcadePanelHands.BARS_THROW, 0, 0))
		_ok(is_equal_approx(hands.steer(&"bars"), 1.0) and hands.holds(&"bars") and panel.hand_thumbstick(0).is_equal_approx(Vector2(1.0, 0.0)) and far < ArcadePanelHands.BARS_LET_GO,
			"rider: %s: pushed 15 cm to the right the rail is all the way over, and a hand %.2f m from the middle of it has it still" % [romset, far])
		_tip_at(h, at + Vector3(-ArcadePanelHands.BARS_THROW * 2.0, 0, 0))
		_step(panel, [h])
		_ok(is_equal_approx(hands.steer(&"bars"), -1.0) and _dpad(input, panel) == _bit(ControllerBindings.JOYPAD_LEFT),
			"rider: %s: and as far to the left as it goes, a full lean left" % romset)
		input._left_vr_ctrl = _ctrl(h)
		input._process(0.016)
		panel.tick(0.016)
		_ok(lean.global_basis.y.x < -0.1, "rider: %s: the plate is drawn leaning left with it" % romset)
		_tip_at(h, at + Vector3(1.0, 0, 0))
		_step(panel, [h])
		_ok(not hands.holds(&"bars"), "rider: %s: and a hand a metre off has lost it" % romset)
		_trigger(h, 0.0)
		input._process(0.016)
		input._left_vr_ctrl = null
		for i in 90:
			panel.tick(0.05)
		_tip_at(h, _cap_top(panel, "Start"))
		_step(panel, [h])
		_ok(panel.hand_buttons() == _bit(ArcadeProfiles.START_BIT), "rider: %s: a finger on START, on top of the crossbar, presses START" % romset)
		await _clear()


# --- cycle ---------------------------------------------------------------------

func _group_cycle() -> void:
	var r := await _rig("propcycl")
	var panel: ArcadeControlModule = r["panel"]
	var input: ArcadeInput = r["input"]
	var hands: ArcadePanelHands = panel.hands()
	var h := _hand()
	var bars := panel.find_child("BarsPivot", true, false) as Node3D
	var at := (panel.find_child("BarGripR", true, false) as Node3D).global_position
	_tip_at(h, at)
	_trigger(h, 1.0)
	_step(panel, [h])
	_ok(hands.holds(&"bars") and is_zero_approx(hands.steer(&"bars")) and is_zero_approx(hands.bars_pitch()),
		"cycle: the trigger on a grip takes hold of the bars")
	_tip_at(h, at + Vector3(0.075, 0.0, -0.05))
	_step(panel, [h])
	_ok(is_equal_approx(hands.steer(&"bars"), 0.5) and is_equal_approx(hands.bars_pitch(), -0.5)
			and panel.hand_thumbstick(0).is_equal_approx(Vector2(0.5, 0.5)),
		"cycle: pushed 7.5 cm right and 5 cm away from the rider: half a turn to the right and half pushed (%s)" % str(panel.hand_thumbstick(0)))
	_tip_at(h, at + Vector3(0.0, 0.0, 0.10))
	_step(panel, [h])
	_ok(is_equal_approx(hands.bars_pitch(), 1.0) and panel.hand_thumbstick(0).y < -0.99,
		"cycle: pulled 10 cm toward the rider the bars are all the way back (the stick's DOWN)")
	# Drawn with the hand.
	_tip_at(h, at + Vector3(0.075, 0.0, -0.05))
	_step(panel, [h])
	input._left_vr_ctrl = _ctrl(h)
	input._process(0.016)
	panel.tick(0.016)
	var want := panel.rest_basis_of(bars) * Basis(Vector3.UP, -deg_to_rad(ArcadeControlModule.BARS_YAW_DEG) * 0.5) \
		* Basis(Vector3.RIGHT, deg_to_rad(ArcadeControlModule.BARS_PITCH_DEG) * -0.5)
	_ok(bars.basis.is_equal_approx(want), "cycle: the bars are drawn turned and tipped as the hand has them, at once")
	var axes := input._heard_axes.get(0, Vector4i.ZERO) as Vector4i
	_ok(axes.x == int(0.5 * ArcadeInput.ANALOG_SCALE) and axes.y == int(-0.5 * ArcadeInput.ANALOG_SCALE),
		"cycle: and the game is sent the left stick: half right, half up (%s)" % str(axes))
	# The grips stand 30 cm out from the middle of the bars: a hand at the far one and past it has them still (the let-go
	# distance is the bars' own, not a stick's 35 cm), and one a metre off has lost them.
	_tip_at(h, at + Vector3(0.10, 0.0, 0.0))
	_step(panel, [h])
	_ok(hands.holds(&"bars"), "cycle: a hand 40 cm from the middle of the bars, at the far grip and past it, has them still")
	_tip_at(h, at + Vector3(1.0, 0.0, 0.0))
	_step(panel, [h])
	_ok(not hands.holds(&"bars"), "cycle: and a hand a metre off has lost them")
	_trigger(h, 0.0)
	input._process(0.016)
	input._left_vr_ctrl = null
	# The crank: taken at a pedal, turned forward like a dial turns.
	var crank := panel.find_child("CrankPivot", true, false) as Node3D
	var pedal := panel.find_child("CrankPedalR", true, false) as Node3D
	var axle := crank.global_position
	var radius := 0.17
	_tip_at(h, at + Vector3(0, 0.5, 0))
	_step(panel, [h])
	# A trigger pulled a quarter of a metre from either pedal takes hold of nothing; at a pedal it takes the crank.
	_tip_at(h, pedal.global_position + Vector3(0.0, 0.0, 0.25))
	_trigger(h, 1.0)
	input._right_vr_ctrl = _ctrl(h)
	input._process(0.016)
	_ok(not hands.holds(&"crank"), "cycle: a trigger pulled 25 cm from the pedals takes hold of nothing")
	_trigger(h, 0.0)
	input._process(0.016)
	# (4 cm along the axle from the pedal: within reach of it, and the same angle about the axle)
	_tip_at(h, pedal.global_position + panel.global_transform.basis.x * 0.04)
	_trigger(h, 1.0)
	input._process(0.016)
	_ok(hands.holds(&"crank"), "cycle: the trigger at a pedal takes hold of the crank")
	var at_angle := func(a: float) -> Vector3:
		# The pedal after a forward turn of `a`: the top of the crank going away from the rider.
		return panel.global_transform * (crank.position + Vector3(0.14, radius * cos(a), -radius * sin(a)))
	for i in 6:
		_tip_at(h, at_angle.call(PI * 0.5 * float(i + 1) / 6.0))
		input._process(0.025)
	_ok(panel.hand_thumbstick(1).y > 0.9 and panel.hand_thumbstick(0) == Vector2.ZERO and absf(hands.crank_angle() - PI * 0.5) < 0.05,
		"cycle: a quarter turn forward in 0.15 s is a brisk pedal: the right stick all the way up (%s, %.2f rad)"
			% [str(panel.hand_thumbstick(1)), hands.crank_angle()])
	panel.tick(0.016)
	var sent := input._heard_axes.get(0, Vector4i.ZERO) as Vector4i
	_ok(sent.w < int(-0.9 * ArcadeInput.ANALOG_SCALE) and sent.x == 0 and sent.y == 0,
		"cycle: sent as the right stick up (the game's Cycle Pedal), the left stick untouched (%s)" % str(sent))
	_ok(pedal.global_position.z < axle.z - 0.12, "cycle: and the crank is drawn turned forward with it: the pedal is away from the rider")
	for i in 6:
		_tip_at(h, at_angle.call(PI * 0.5 - PI * 0.5 * float(i + 1) / 6.0))
		input._process(0.025)
	_ok(panel.hand_thumbstick(1).y < -0.9, "cycle: turned back the other way it pedals backward")
	# A slow turn is a slow pedal: the same quarter turn in 0.6 s is about a quarter of the speed that is all the way up.
	for i in 6:
		_tip_at(h, at_angle.call(PI * 0.5 * float(i + 1) / 6.0))
		input._process(0.1)
	var slow := panel.hand_thumbstick(1).y
	_ok(slow > 0.15 and slow < 0.40, "cycle: a quarter turn in 0.6 s is a slow pedal, not a brisk one (%.2f)" % slow)
	# On its axle a hand has no angle: the crank does not jump to wherever the noise points.
	var turned := hands.crank_angle()
	_tip_at(h, panel.global_transform * (crank.position + Vector3(0.14, 0.0, 0.0)))
	input._process(0.016)
	_tip_at(h, panel.global_transform * (crank.position + Vector3(0.14, 0.01, 0.0)))
	input._process(0.016)
	_ok(absf(hands.crank_angle() - turned) < 0.001, "cycle: a hand on the axle itself does not turn the crank (%.3f)" % (hands.crank_angle() - turned))
	_trigger(h, 0.0)
	input._process(0.016)
	input._right_vr_ctrl = null
	_ok(not hands.holds(&"crank") and panel.hand_thumbstick(1) == Vector2.ZERO, "cycle: let go, the crank is free")


# --- slot ----------------------------------------------------------------------

func _group_slot() -> void:
	var r := await _rig("panicprk")
	var input: ArcadeInput = r["input"]
	var a := (r["panels"] as Array)[0] as ArcadeControlModule
	var b := (r["panels"] as Array)[1] as ArcadeControlModule
	var right := _hand("right")
	var left := _hand("left")
	input._right_vr_ctrl = _ctrl(right)
	input._left_vr_ctrl = _ctrl(left)
	# The handle a hand takes is the dome that is DRAWN, wherever the builder put it.
	var ball := func(panel: ArcadeControlModule) -> Vector3:
		return (panel.find_child("LeverBall", true, false) as Node3D).global_position
	var ball_a: Vector3 = ball.call(a)
	var ball_b: Vector3 = ball.call(b)
	var grab_a: ArcadePanelHands.ControlGrab = null
	for g in a.hands().grabs():
		if g is ArcadePanelHands.SlideGrab:
			grab_a = g
	_ok(grab_a != null and grab_a.handle().distance_to(ball_a) < 0.001,
		"slot: the point a hand reaches for is the centre of the drawn dome (%.3f m off)" % (grab_a.handle().distance_to(ball_a) if grab_a != null else -1.0))
	_tip_at(right, ball_a + Vector3(0, 0, 0.09))
	input._process(0.016)
	_trigger(right, 1.0)
	input._process(0.016)
	_ok(not a.hands().holds(&"slide"), "slot: a trigger squeezed 9 cm in front of the dome takes nothing")
	_trigger(right, 0.0)
	input._process(0.016)
	_tip_at(right, ball_a)
	_tip_at(left, ball_b)
	_trigger(right, 1.0)
	_trigger(left, 1.0)
	input._process(0.016)
	_ok(a.hands().holds(&"slide") and b.hands().holds(&"slide"), "slot: a hand on each lever takes hold of its own")
	_tip_at(right, ball_a + Vector3(0.07, 0, 0))
	_tip_at(left, ball_b + Vector3(-S.SLOT_TRAVEL * 2.0, 0, 0))
	input._process(0.016)
	_ok(is_equal_approx(a.hands().steer(&"slide"), 0.5) and is_equal_approx(b.hands().steer(&"slide"), -1.0),
		"slot: 7 cm along the slot is half a lever, past the end of it is the end")
	var axes_a := input._heard_axes.get(0, Vector4i.ZERO) as Vector4i
	var axes_b := input._heard_axes.get(1, Vector4i.ZERO) as Vector4i
	_ok(axes_a.x == int(0.5 * ArcadeInput.ANALOG_SCALE) and axes_b.x == -ArcadeInput.ANALOG_SCALE,
		"slot: each lever is its own player's left stick (%s, %s)" % [str(axes_a), str(axes_b)])
	a.tick(0.016)
	b.tick(0.016)
	var la := (a.find_child("SlidePivot", true, false) as Node3D).position.x
	_ok(absf(la - (-S.SLOT_TRAVEL + 0.5 * S.SLOT_TRAVEL)) < 0.001, "slot: the lever is drawn where the hand has it (%.3f)" % la)
	_trigger(right, 0.0)
	_trigger(left, 0.0)
	input._process(0.016)
	_ok(not a.hands().holds(&"slide") and not b.hands().holds(&"slide"), "slot: let go, both are free")
	input._right_vr_ctrl = null
	input._left_vr_ctrl = null


# --- fly -----------------------------------------------------------------------

func _group_fly() -> void:
	var r := await _rig("aburner2", 6, true)
	var input: ArcadeInput = r["input"]
	var panel: ArcadeControlModule = r["panel"]
	var hands := panel.hands()
	var right := _hand("right")
	var left := _hand("left")
	input._right_vr_ctrl = _ctrl(right)
	input._left_vr_ctrl = _ctrl(left)
	var ball := panel.find_child("StickBall", true, false) as Node3D
	var knob := panel.find_child("ThrottleKnob", true, false) as Node3D
	var ahead := -panel.global_transform.basis.z.normalized()
	# The stick: taken at its grip, 30 cm up its shaft.
	_tip_at(right, ball.global_position)
	_trigger(right, 1.0)
	input._process(0.016)
	_ok(hands.holds(&"stick"), "fly: the trigger at the grip takes hold of the flight stick")
	var grip_at := ball.global_position
	# A hand that moves 5 cm does not lean it all the way: the throw is the shaft's, not a deck stick's 3 cm.
	_tip_at(right, grip_at + _right(panel) * 0.05)
	input._process(0.016)
	var half := hands.stick_lean(0).x
	_ok(half > 0.3 and half < 0.7, "fly: 5 cm of hand is about half a lean on a 30 cm shaft (%.2f)" % half)
	_tip_at(right, grip_at + _right(panel) * 0.15)
	input._process(0.016)
	_ok(hands.stick_lean(0).x > 0.99 and panel.hand_thumbstick(0).x > 0.99 and panel.hand_thumbstick(1) == Vector2.ZERO,
		"fly: 15 cm is all of it, the left stick, and the right stick (the throttle) left alone")
	panel.tick(0.016)
	var leaned := ball.global_position
	_ok(leaned.x > grip_at.x + 0.05, "fly: and the grip is drawn where the hand has it (%.3f m over)" % (leaned.x - grip_at.x))
	# Pushed away from the player is up on the stick; the grip follows the hand to within a few centimetres.
	_tip_at(right, grip_at + ahead * 0.15)
	input._process(0.016)
	_ok(hands.stick_lean(0).y < -0.99 and panel.hand_thumbstick(0).y > 0.99, "fly: pushed forward it is the left stick up")
	_trigger(right, 0.0)
	input._process(0.016)
	# A finger on the stick's head presses the first button, which is on the stick and goes with it.
	_tip_at(left, _cap_top(panel, "Btn1"))
	_step(panel, [left])
	_ok(panel.hand_buttons() & (1 << ArcadeProfiles.BUTTON_BITS[0]) != 0, "fly: a finger on the stick's head presses its first button")
	_tip_at(left, grip_at + Vector3(0, 0.6, 0))
	_step(panel, [left])
	# The throttle: taken at its knob, pushed 5 cm forward is half, and it stays where the hand left it.
	_tip_at(left, knob.global_position + ahead * 0.09)
	_trigger(left, 1.0)
	input._process(0.016)
	_ok(not hands.holds(&"throttle"), "fly: a trigger pulled 9 cm from the knob takes nothing")
	_trigger(left, 0.0)
	input._process(0.016)
	var knob_at := knob.global_position
	_tip_at(left, knob_at)
	_trigger(left, 1.0)
	input._process(0.016)
	_ok(hands.holds(&"throttle") and hands.throttle_value() == 0.0, "fly: the trigger at the knob takes hold of the throttle, in the middle")
	_tip_at(left, knob_at + ahead * 0.05)
	input._process(0.016)
	_ok(_near_f(hands.throttle_value(), 0.5) and _near_f(panel.hand_thumbstick(1).y, 0.5) and panel.hand_thumbstick(0) == Vector2.ZERO,
		"fly: 5 cm forward is half throttle: the right stick up by half (%s)" % str(panel.hand_thumbstick(1)))
	panel.tick(0.016)
	_ok(panel.throttle_amount() == hands.throttle_value() and _near_f(panel.throttle_amount(), 0.5),
		"fly: a lever in a hand is drawn where the hand has it, with no easing between (%.6f)" % panel.throttle_amount())
	var sent := input._heard_axes.get(0, Vector4i.ZERO) as Vector4i
	_ok(absi(sent.w + int(0.5 * ArcadeInput.ANALOG_SCALE)) <= 2 and sent.x == 0 and sent.y == 0 and sent.z == 0,
		"fly: sent as the right stick's Y, up, and nothing else (%s)" % str(sent))
	_tip_at(left, knob_at + ahead * 0.2)
	input._process(0.016)
	_ok(hands.throttle_value() == 1.0, "fly: a hand that goes on past the end of the travel gets the end")
	_tip_at(left, knob_at + ahead * -0.2)
	input._process(0.016)
	_ok(hands.throttle_value() == -1.0, "fly: and the other end")
	_tip_at(left, knob_at + ahead * 0.03)
	input._process(0.016)
	var wanted := hands.throttle_value()
	_trigger(left, 0.0)
	input._process(0.016)
	_ok(not hands.holds(&"throttle") and hands.throttle_value() == wanted and _near_f(panel.hand_thumbstick(1).y, wanted),
		"fly: let go, the lever stays where the hand left it, and the game goes on reading it (%.2f)" % wanted)
	_tip_at(left, Vector3(0, 5, 0))
	input._process(0.016)
	input._process(0.016)
	_ok(_near_f(hands.throttle_value(), wanted), "fly: even with the hand gone from the cabinet")
	# The pad beside it: whichever of the two is further over wins, as with any control both work.
	var pad_small := input._with_hands({"btn": 0, "alx": 0, "aly": 0, "arx": 0, "ary": int(0.01 * ArcadeInput.ANALOG_SCALE)}, 0)
	var pad_big := input._with_hands({"btn": 0, "alx": 0, "aly": 0, "arx": 0, "ary": ArcadeInput.ANALOG_SCALE}, 0)
	_ok(int(pad_small["ary"]) == int(-wanted * ArcadeInput.ANALOG_SCALE) and int(pad_big["ary"]) == ArcadeInput.ANALOG_SCALE,
		"fly: a pad's right stick pushed further than the lever takes over from it, one barely touched does not")
	# The lever is drawn at the throttle's value.
	input._process(0.016)
	for i in 30:
		panel.tick(0.05)
	_ok(_near_f(panel.throttle_amount(), wanted, 0.01), "fly: and drawn there (%.2f)" % panel.throttle_amount())
	# The run over, the lever is back in the middle: the next game starts at idle.
	panel.rest()
	input._process(0.016)
	for i in 30:
		panel.tick(0.05)
	_ok(hands.throttle_value() == 0.0 and panel.hand_thumbstick(1) == Vector2.ZERO and _near_f(panel.throttle_amount(), 0.0, 0.01),
		"fly: the run over, the throttle is back in the middle")
	# A machine switched off puts it back too.
	_tip_at(left, knob.global_position)
	_trigger(left, 1.0)
	input._process(0.016)
	_tip_at(left, knob.global_position + ahead * 0.05)
	input._process(0.016)
	_trigger(left, 0.0)
	input._process(0.016)
	var set := hands.throttle_value()
	r["sys"].is_powered_on = false
	input._process(0.016)
	_ok(set > 0.4 and hands.throttle_value() == 0.0, "fly: a machine switched off has its throttle back in the middle (%.2f first)" % set)
	input._right_vr_ctrl = null
	input._left_vr_ctrl = null


func _near_f(a: float, b: float, tolerance: float = 0.02) -> bool:
	return absf(a - b) <= tolerance


# --- input ---------------------------------------------------------------------

func _group_input() -> void:
	var r := await _rig()
	var panel: ArcadeControlModule = r["panel"]
	var input: ArcadeInput = r["input"]
	var h := _hand()
	input._right_vr_ctrl = _ctrl(h)
	var B := ArcadeProfiles.BUTTON_BITS
	var cap := panel.find_child("Btn1", true, false) as Node3D
	var rest_z := cap.position.z
	_tip_at(h, _cap_top(panel, "Btn1"))
	input._process(0.016)
	_ok((int(input.last_sent.get(0, 0)) & _bit(B[0])) != 0 and not input.playing,
		"input: a finger on button 1 reaches port 0 with nobody attached to the panel")
	_ok(cap.position.z < rest_z - ArcadeControlModule.CAP_PRESS * 0.9, "input: and the cap sinks in its flange")
	_ok(input.engaged(), "input: and somebody is at the cabinet (the idle clock does not put the game away)")
	_ok(int(input.last_sent.get(1, 0)) == 0, "input: player 2's port hears nothing")
	_tip_at(h, _cap_top(panel, "Btn1") + panel.global_transform.basis.z * 0.3)
	input._process(0.2)
	_ok((int(input.last_sent.get(0, 0)) & _bit(B[0])) == 0 and not input.engaged() and is_equal_approx(cap.position.z, rest_z),
		"input: lifted away it is up and sent, and nobody is at the cabinet")
	# The stick through the bindings: analog and the D-pad (the default "left+dpad"), then only what the player set.
	_trigger(h, 1.0)
	_tip_at(h, _ball_at(panel))
	input._process(0.016)
	_tip_at(h, _ball_at(panel) + _right(panel) * 0.03)
	input._process(0.016)
	_ok((int(input.last_sent.get(0, 0)) & _bit(ControllerBindings.JOYPAD_RIGHT)) != 0
			and (input._heard_axes.get(0, Vector4i.ZERO) as Vector4i).x == ArcadeInput.ANALOG_SCALE,
		"input: a stick held right is RIGHT and the left analog axis at full, with the default bindings")
	input._stick_map = {"stick_left": "dpad", "stick_right": "right"}
	input._process(0.016)
	_ok((int(input.last_sent.get(0, 0)) & _bit(ControllerBindings.JOYPAD_RIGHT)) != 0
			and (input._heard_axes.get(0, Vector4i.ZERO) as Vector4i).x == 0,
		"input: the player's bindings apply to a hand as to a controller (the left stick set to the D-pad alone sends no axis)")
	input._stick_map = {"stick_left": "left", "stick_right": "right"}
	input._process(0.016)
	_ok((int(input.last_sent.get(0, 0)) & _bit(ControllerBindings.JOYPAD_RIGHT)) == 0
			and (input._heard_axes.get(0, Vector4i.ZERO) as Vector4i).x == ArcadeInput.ANALOG_SCALE,
		"input: and set to the analog axis alone, no D-pad")
	input._stick_map = ControllerBindings.DEFAULT_STICK_MAP.duplicate()
	# A controller's own thumbstick and a hand on the stick: the buttons add up, the larger stick wins.
	var pad := _hand("left")
	input._left_vr_ctrl = _ctrl(pad)
	(pad["tracker"] as XRControllerTracker).set_input(&"primary", Vector2(-0.5, 0.0))
	input.attached[0] = true
	input._process(0.016)
	var both := int(input.last_sent.get(0, 0))
	var axes := input._heard_axes.get(0, Vector4i.ZERO) as Vector4i
	_ok((both & _bit(ControllerBindings.JOYPAD_LEFT)) != 0 and (both & _bit(ControllerBindings.JOYPAD_RIGHT)) != 0
			and axes.x == ArcadeInput.ANALOG_SCALE,
		"input: an attached controller's thumbstick and a hand on the stick add up (both directions), and the larger axis is sent")
	(pad["tracker"] as XRControllerTracker).set_input(&"primary", Vector2.ZERO)
	input.attached.erase(0)
	input._left_vr_ctrl = null
	_trigger(h, 0.0)
	input._process(0.016)
	# The machine off: nothing held, nothing sent.
	_tip_at(h, _cap_top(panel, "Btn2"))
	input._process(0.016)
	_ok((int(input.last_sent.get(0, 0)) & _bit(B[1])) != 0, "input: (button 2 pressed)")
	(r["sys"] as RetroSystem).is_powered_on = false
	input._process(0.016)
	_ok(not panel.hands_active() and panel.hand_buttons() == 0, "input: the machine switched off, the finger on the cap holds nothing")
	(r["sys"] as RetroSystem).is_powered_on = true
	input._right_vr_ctrl = null


# --- laser ---------------------------------------------------------------------

func _group_laser() -> void:
	var r := await _rig()
	var panel: ArcadeControlModule = r["panel"]
	var hands: ArcadePanelHands = panel.hands()
	var h := _hand()
	var laser := _laser(h)
	_tip_at(h, _ball_at(panel) + Vector3(0, 0, 0.2))
	_step(panel, [h])
	_ok(_laser_on(laser), "laser: a hand well away from the panel keeps its laser")
	_tip_at(h, _ball_at(panel) + Vector3(0.06, 0, 0))
	_step(panel, [h])
	_ok(not _laser_on(laser), "laser: a hand reaching for the stick has none (the trigger it pulls is for the stick)")
	_tip_at(h, _cap_top(panel, "Btn1"))
	_step(panel, [h])
	_ok(_laser_on(laser), "laser: a finger on a cap keeps it (a press is not a pull)")
	_tip_at(h, _ball_at(panel))
	_trigger(h, 1.0)
	_step(panel, [h])
	_ok(hands.holds(&"stick", 0) and not _laser_on(laser), "laser: holding the stick, it is off")
	# The panel does not take a press from a hand on its stick: that trigger was the stick's.
	var grip := panel.grip()
	var pointer := laser
	grip.pointer_event(XRToolsPointerEvent.new(XRToolsPointerEvent.Type.PRESSED, pointer, grip, Vector3.ZERO, Vector3.ZERO))
	_ok(not panel.is_attached(), "laser: a press on the panel from the hand that holds the stick does not attach to it")
	_trigger(h, 0.0)
	_step(panel, [h])
	_ok(not hands.holds(&"stick", 0) and not _laser_on(laser), "laser: let go but still at the stick, it stays off (the next pull is the stick's)")
	_tip_at(h, _ball_at(panel) + Vector3(0, 0, 0.3))
	_step(panel, [h])
	_ok(_laser_on(laser), "laser: moved off the stick, it is back")
	grip.pointer_event(XRToolsPointerEvent.new(XRToolsPointerEvent.Type.PRESSED, pointer, grip, Vector3.ZERO, Vector3.ZERO))
	_ok(panel.is_attached(), "laser: a press from a hand well away from the controls attaches, as it always did")
	panel.set_attached(false)
	grip.pointer_event(XRToolsPointerEvent.new(XRToolsPointerEvent.Type.PRESSED, null, grip, Vector3.ZERO, Vector3.ZERO))
	_ok(panel.is_attached(), "laser: and the desktop's reticle (no hand) attaches too")
	panel.set_attached(false)
	# The machine off, the panel gone, a morph under a held stick: every laser is given back.
	_tip_at(h, _ball_at(panel))
	_trigger(h, 1.0)
	_step(panel, [h])
	_ok(not _laser_on(laser), "laser: (held again)")
	panel.update_hands(0.016, [h["ctrl"]], false)
	_ok(_laser_on(laser) and not hands.holds(&"stick", 0), "laser: switching the machine off gives the laser back and lets the stick go")
	_trigger(h, 0.0)
	_step(panel, [h])
	_tip_at(h, _ball_at(panel))
	_trigger(h, 1.0)
	_step(panel, [h])
	_trigger(h, 0.0)
	_tip_at(h, _ball_at(panel))
	_step(panel, [h])
	var model: RetroSystemModelArcadeCabinet = r["model"]
	_trigger(h, 1.0)
	_trigger(h, 0.0)
	_tip_at(h, _ball_at(panel))
	_step(panel, [h])
	_trigger(h, 1.0)
	_step(panel, [h])
	_ok(not _laser_on(laser), "laser: (reaching again)")
	var base := S.variant("generic")
	base["variant"] = "generic"
	model.morph_to(S.for_game(base, P.for_romset("tmnt")))
	await _wait(3)
	_ok(_laser_on(laser), "laser: the panel the hand was on is rebuilt away, and the laser is back")


# --- carry ---------------------------------------------------------------------

func _group_carry() -> void:
	var r := await _rig()
	var sys: RetroSystem = r["sys"]
	var panel: ArcadeControlModule = r["panel"]
	var hands: ArcadePanelHands = panel.hands()
	var h := _hand()
	var pickup := PICKUP_SCENE.instantiate() as XRToolsFunctionPickup
	_ctrl(h).add_child(pickup)
	await _wait(2)
	_ok(pickup.get_controller() == _ctrl(h), "carry: (the pickup finds the hand it is on)")
	var ball := _ball_at(panel)
	_tip_at(h, ball + Vector3(0, 0, 0.5))
	_ok(sys.can_pick_up(pickup), "carry: a hand well away from the panel can pick the cabinet up, as ever")
	_tip_at(h, ball + Vector3(0.06, 0, 0))
	_ok(not sys.can_pick_up(pickup), "carry: a hand reaching for the stick cannot (the squeeze round it would start the carry ring)")
	_tip_at(h, ball)
	_trigger(h, 1.0)
	_step(panel, [h])
	_ok(hands.holds(&"stick", 0) and not sys.can_pick_up(pickup), "carry: nor one that holds it")
	_trigger(h, 0.0)
	_step(panel, [h])
	_tip_at(h, ball + Vector3(0, 0, 0.5))
	_ok(sys.can_pick_up(pickup), "carry: and it can again once it has let go and gone")
	var other := _hand("left")
	var other_pickup := PICKUP_SCENE.instantiate() as XRToolsFunctionPickup
	_ctrl(other).add_child(other_pickup)
	await _wait(2)
	_tip_at(h, ball)
	_trigger(h, 1.0)
	_step(panel, [h, other])
	_tip_at(other, ball + Vector3(0, 0, 0.5))
	_ok(not sys.can_pick_up(pickup) and sys.can_pick_up(other_pickup),
		"carry: the other hand, off the controls, can still pick the cabinet up")
	_trigger(h, 0.0)
	_step(panel, [h, other])
	# The squeeze: a fist round the stick does not attach to the panel; a squeeze on the panel elsewhere does.
	var grip := panel.grip()
	grip._controllers.append(_ctrl(h))
	var squeeze := func(value: float) -> void:
		(h["tracker"] as XRControllerTracker).set_input(&"grip", value)
		PokeTip._cache_frame = -1
		grip._process(0.016)
	_tip_at(h, ball)
	squeeze.call(1.0)
	_ok(not panel.is_attached(), "carry: a squeeze with the hand round the stick does not attach to the panel")
	squeeze.call(0.0)
	var clear := grip.global_position + panel.global_transform.basis.x * 0.08
	_tip_at(h, clear)
	_ok(clear.distance_to(grip.global_position) <= ArcadePanelGrip.REACH and not hands.reaching(_ctrl(h)),
		"carry: (a place on the panel clear of the controls)")
	squeeze.call(1.0)
	_ok(panel.is_attached(), "carry: a squeeze on the panel clear of the controls attaches, as it always did")
	squeeze.call(0.0)
	panel.set_attached(false)


# --- use -----------------------------------------------------------------------

func _group_use() -> void:
	var r := await _rig()
	var panel: ArcadeControlModule = r["panel"]
	var input: ArcadeInput = r["input"]
	var sys: RetroSystem = r["sys"]
	var h := _hand()
	input._right_vr_ctrl = _ctrl(h)
	var seen: Array[StringName] = []
	input.first_use.connect(func(kind: StringName) -> void: seen.append(kind))
	sys.is_powered_on = false
	sys.attracting = true
	_tip_at(h, Vector3(0, 5, 0))
	input._process(0.016)
	_ok(seen.is_empty(), "use: a cabinet showing its game, with nobody near it, is left showing it")
	_tip_at(h, _cap_top(panel, "Btn1"))
	input._process(0.016)
	_ok(seen == [&"panel"], "use: a finger on a cap starts the game, as a panel pressed does (%s)" % str(seen))
	# Again, from a cabinet that shows its game and nobody at it: a hand on the stick does the same.
	panel.release_hands()
	sys.is_powered_on = false
	sys.attracting = true
	seen.clear()
	_tip_at(h, Vector3(0, 5, 0))
	input._process(0.016)
	_ok(seen.is_empty() and not input.engaged(), "use: (the hand gone, nobody is at the cabinet)")
	_tip_at(h, _ball_at(panel))
	_trigger(h, 1.0)
	input._process(0.016)
	_ok(seen == [&"panel"], "use: and so does a hand on the stick (%s)" % str(seen))
	sys.attracting = false
	_trigger(h, 0.0)
	input._process(0.016)
	input._right_vr_ctrl = null
