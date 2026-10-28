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
##   cycle/    a bicycle's bars turn about the stem with a hand on a grip and tip with its lift, its crank is pedalled by a hand
##   handlebars/ a squeeze takes the bars as a trigger does, a second hand takes the other grip, two hands turn them by the line between them and tip them by their push and pull, one letting go leaves
##              the bars where they are; a motorbike's lean with the mean of the hands; a squeeze takes nothing that is not bars
##   slot/     two levers in one slot, one a hand each
##   fly/      a flight cockpit's stick (a long shaft, a long throw) and its throttle, which stays where the hand left it
##   input/    what the hands hold goes out like an attached controller's: the port, the bindings, the cap that sinks
##   off/      a cabinet that is switched off still has its controls worked -- the caps sink, the stick, the wheel, the pedals, the lever and the throttle follow the hand -- and sends nothing; a motor stays still
##   laser/    a hand on a control has no laser; it is back when the hand is done, and the panel takes no press from it
##   carry/    a hand on a control cannot pick the cabinet up, and its squeeze does not attach
##   use/      a finger on a cap starts an attract game, and a hand on the panel is somebody at the cabinet
##   sticks/    a Taiko drummer's sticks in a headset's hands: the trigger and the thumb buttons hit the drum on the hand's own side, a swing hits where the head comes down
##   guitar/    a GuitarFreaks guitar in two hands: the neck hand's trigger, X/A and Y/B are the frets, the body hand's trigger strums and its stick wails and turns the knob, the neck raised wails,
##              one hand works the frets and a free hand strums, and all of it reaches the port through the cabinet's input
extends "res://Tests/test_suite.gd"

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const PICKUP_SCENE := preload("res://addons/godot-xr-tools/functions/function_pickup.tscn")
var P := ArcadeGameProfile
var S := ArcadeCabinetSpecs

var _only := ""
var _spawned: Array[Node] = []
var _hands: Array[Dictionary] = []


func _ready() -> void:
	suite_tag = "hand"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7)
	get_tree().create_timer(240.0).timeout.connect(func() -> void:
		print("[hand] TIMED OUT")
		get_tree().quit(1))
	# A hint counts what it has taught in the player's own file: a suite counts in memory (the `prompts/` group puts the counts back).
	HeldHint.persist_uses = false
	await _run()
	_finish()


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
			["lever", _group_lever], ["helm", _group_helm], ["bars", _group_bars], ["rider", _group_rider], ["cycle", _group_cycle], ["handlebars", _group_handlebars], ["slot", _group_slot], ["fly", _group_fly],
			["input", _group_input], ["transfer", _group_transfer], ["off", _group_off],
			["laser", _group_laser], ["carry", _group_carry], ["use", _group_use], ["sticks", _group_sticks], ["guitar", _group_guitar], ["prompts", _group_prompts]]:
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
	panel.update_hands(delta, ctrls)


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
	# A yoke is taken by a grip: near one of the two ends of its bar by angle about the axle, not at the top or the bottom of its turn.
	_ok(R.near_helm_grip(Vector3(0.145, 0.05, 0.0)) and R.near_helm_grip(Vector3(-0.145, 0.05, 0.0)),
		"zone: a yoke's handgrips are taken where the bar ends, at 90 degrees either side of its top")
	_ok(not R.near_helm_grip(Vector3(0.0, 0.05, -0.145)) and not R.near_helm_grip(Vector3(0.0, 0.05, 0.145)),
		"zone: the middle of the bar, its top and its bottom, are not a place to hold it by")
	_ok(R.near_helm_grip(Vector3(sin(PI * 0.5 - R.HELM_GRIP_ARC * 0.95), 0.0, cos(PI * 0.5 - R.HELM_GRIP_ARC * 0.95))) \
			and not R.near_helm_grip(Vector3(sin(PI * 0.5 - R.HELM_GRIP_ARC * 1.05), 0.0, cos(PI * 0.5 - R.HELM_GRIP_ARC * 1.05))),
		"zone: and a grip's reach ends at HELM_GRIP_ARC (%.0f degrees) from it" % rad_to_deg(R.HELM_GRIP_ARC))
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
	# A panel that is hidden lets go of what a finger held, and takes it again when it is shown with the finger still there. (Switched off is not hidden: `off/`.)
	_tip_at(h, _cap_top(panel, "Btn1"))
	_step(panel, [h])
	_ok(panel.hands_active(), "caps: (a finger on button 1)")
	panel.visible = false
	_step(panel, [h])
	_ok(not panel.hands_active() and panel.hand_buttons() == 0, "caps: a panel that is hidden lets go of what a finger held")
	panel.visible = true
	_step(panel, [h])
	_ok(panel.hand_buttons() == _bit(B[0]), "caps: and presses again when it is shown, the finger being there")
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

## The point of a yoke's handgrip (`side` +1 right, -1 left) as the driver turns it `turn` radians (positive = the top goes to the driver's right), in the world: the middle of the grip
## along the axle, HELM_SPAN from it.
func _grip_point(panel: ArcadeControlModule, side: float, turn: float) -> Vector3:
	var pivot := panel.find_child("WheelPivot", true, false) as Node3D
	var mount := pivot.get_parent() as Node3D
	return mount.global_transform * (Basis(Vector3.UP, -turn) * Vector3(side * ArcadeCabinetBuilder.HELM_SPAN, 0.055, 0.0))


## Road Blasters' yoke: a wheel to the input and the hands, a yoke to look at. It turns 135 degrees each way (about 270 lock to lock), is taken by a grip and not by the top of its bar, and the holding
## hand's A / X and B / Y are the buttons that are on its grips (button 2, "Lasers", and 3, "Special Weapon").
func _group_helm() -> void:
	var r := await _rig("roadblst", 6, true)
	var panel: ArcadeControlModule = r["panel"]
	var input: ArcadeInput = r["input"]
	var hands: ArcadePanelHands = panel.hands()
	var h := _hand()
	_ok(panel.find_child("WheelRim", true, false) == null and panel.find_child("HelmBar", true, false) != null and is_equal_approx(panel.wheel_lock_deg(), 135.0),
		"helm: a yoke with no rim, which turns 135 degrees each way")
	var pivot := panel.find_child("WheelPivot", true, false) as Node3D
	var mount := pivot.get_parent() as Node3D
	# The top of the bar, between the grips, is nothing to take hold of.
	_tip_at(h, mount.global_transform * Vector3(0.0, 0.055, -ArcadeCabinetBuilder.HELM_SPAN))
	_trigger(h, 1.0)
	_step(panel, [h])
	_ok(not hands.holds(&"wheel"), "helm: the trigger over the top of the bar takes nothing")
	_trigger(h, 0.0)
	_step(panel, [h])
	# A grip, the right one: taken, and taking hold turns nothing.
	_tip_at(h, _grip_point(panel, 1.0, 0.0))
	_trigger(h, 1.0)
	_step(panel, [h])
	_ok(hands.holds(&"wheel") and is_zero_approx(hands.steer(&"wheel")), "helm: the trigger on a handgrip takes hold of the yoke, and taking hold turns nothing")
	# Turned to the lock: 135 degrees is all the way, 120 is not (a wheel's lock was 120).
	_tip_at(h, _grip_point(panel, 1.0, deg_to_rad(120.0)))
	_step(panel, [h])
	var at_120 := hands.steer(&"wheel")
	_tip_at(h, _grip_point(panel, 1.0, deg_to_rad(135.0)))
	_step(panel, [h])
	var at_135 := hands.steer(&"wheel")
	_ok(absf(at_120 - 120.0 / 135.0) < 0.01 and is_equal_approx(at_135, 1.0),
		"helm: 120 degrees is %.2f of the way and 135 all of it" % at_120)
	# (A hand's turn is followed a step at a time, the short way round: it goes back through the middle.)
	for turn in [60.0, 0.0, -50.0, -100.0]:
		_tip_at(h, _grip_point(panel, 1.0, deg_to_rad(turn)))
		_step(panel, [h])
	_ok(hands.steer(&"wheel") < -0.7 and _dpad(input, panel) == _bit(ControllerBindings.JOYPAD_LEFT), "helm: turned the other way it reads left, as a thumbstick's left")
	# The grips carry the game's buttons: A / X is Lasers (button 2), B / Y Special Weapon (button 3).
	_tip_at(h, _grip_point(panel, 1.0, 0.0))
	_step(panel, [h])
	var lasers := _bit(ArcadeProfiles.button_bit(2))
	var special := _bit(ArcadeProfiles.button_bit(3))
	_ok(panel.hand_buttons() & (lasers | special) == 0, "helm: with no thumb on a button, none is pressed")
	(h["tracker"] as XRControllerTracker).set_input(&"ax_button", 1.0)
	_step(panel, [h])
	var a_only := panel.hand_buttons() & (lasers | special)
	(h["tracker"] as XRControllerTracker).set_input(&"ax_button", 0.0)
	(h["tracker"] as XRControllerTracker).set_input(&"by_button", 1.0)
	_step(panel, [h])
	var b_only := panel.hand_buttons() & (lasers | special)
	(h["tracker"] as XRControllerTracker).set_input(&"by_button", 0.0)
	_ok(a_only == lasers and b_only == special, "helm: A or X on the grip is Lasers (button 2), B or Y Special Weapon (button 3)")
	# Let go: the buttons go with the hold (a hand off the grips presses nothing with its A).
	_trigger(h, 0.0)
	_step(panel, [h])
	(h["tracker"] as XRControllerTracker).set_input(&"ax_button", 1.0)
	_step(panel, [h])
	_ok(not hands.holds(&"wheel") and panel.hand_buttons() & (lasers | special) == 0, "helm: and with the yoke let go, A presses nothing")
	(h["tracker"] as XRControllerTracker).set_input(&"ax_button", 0.0)


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

func _squeeze(h: Dictionary, value: float) -> void:
	(h["tracker"] as XRControllerTracker).set_input(&"grip", value)


## Where a hand on the grip `side` (+1 the right one, -1 the left) of a bicycle's bars is when the bars are turned `steer` of their lock to the right (clockwise seen from above) about the stem, and the hand
## is lifted `lift` and pushed `toward` the rider (m).
func _bars_hand(bars: Node3D, side: float, steer: float, lift: float = 0.0, toward: float = 0.0) -> Vector3:
	var turned := Basis(Vector3.UP, -deg_to_rad(ArcadeControlModule.BARS_YAW_DEG) * steer) * Vector3(side * 0.30, 0.0, 0.0)
	return (bars.get_parent() as Node3D).global_transform * (bars.position + turned + Vector3(0.0, lift, toward))


## The bars drawn turned `steer` of their lock, as ArcadeControlModule.tick draws them: the grips go where the hands are, and a second hand reaches the one that moved.
func _draw_bars(panel: ArcadeControlModule, bars: Node3D, steer: float) -> void:
	bars.basis = panel.rest_basis_of(bars) * Basis(Vector3.UP, -deg_to_rad(ArcadeControlModule.BARS_YAW_DEG) * steer)


func _bars_grab(hands: ArcadePanelHands) -> ArcadePanelHands.BarsGrab:
	for g in hands.grabs():
		if g.kind == &"bars":
			return g as ArcadePanelHands.BarsGrab
	return null


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
	# A hand on a grip goes round the stem as the grip does: the grip drawn toward the rider (the stick's right) to half the lock is half a turn to the right.
	_tip_at(h, _bars_hand(bars, 1.0, 0.5))
	_step(panel, [h])
	_ok(absf(hands.steer(&"bars") - 0.5) < 0.01 and absf(hands.bars_pitch()) < 0.01 and absf(panel.hand_thumbstick(0).x - 0.5) < 0.01,
		"cycle: the right grip taken round the stem to half the lock is half a turn to the right and no tip (%.3f, %.3f)" % [hands.steer(&"bars"), hands.bars_pitch()])
	_tip_at(h, _bars_hand(bars, 1.0, -1.0))
	_step(panel, [h])
	_ok(is_equal_approx(hands.steer(&"bars"), -1.0), "cycle: and away from the rider, all the way left")
	# Along the bar a hand turns nothing: it is not on the arc.
	_tip_at(h, at + (bars.get_parent() as Node3D).global_basis.x * 0.10)
	_step(panel, [h])
	_ok(absf(hands.steer(&"bars")) < 0.001 and absf(hands.bars_pitch()) < 0.001, "cycle: a hand pushed along the bar itself turns nothing (%.3f)" % hands.steer(&"bars"))
	# On the stem itself a hand has no angle: it says nothing, however the noise points.
	var stem := (bars.get_parent() as Node3D).global_transform * bars.position
	_tip_at(h, stem + (bars.get_parent() as Node3D).global_basis.z * 0.02)
	_step(panel, [h])
	_ok(absf(hands.steer(&"bars")) < 0.001, "cycle: a hand 2 cm from the stem turns nothing (%.3f)" % hands.steer(&"bars"))
	# The left grip turns them the same way, the other way round: it goes away from the rider for a turn to the right.
	var hl := _hand("left")
	_trigger(h, 0.0)
	_step(panel, [h])
	_tip_at(hl, (panel.find_child("BarGripL", true, false) as Node3D).global_position)
	_trigger(hl, 1.0)
	_step(panel, [hl])
	_tip_at(hl, _bars_hand(bars, -1.0, 0.5))
	_step(panel, [hl])
	_ok(absf(hands.steer(&"bars") - 0.5) < 0.01, "cycle: the left grip going away from the rider turns them right as well (%.3f)" % hands.steer(&"bars"))
	_trigger(hl, 0.0)
	_step(panel, [hl])
	_trigger(h, 1.0)
	_tip_at(h, at)
	_step(panel, [h])
	# The lift of the hand tips them: 5 cm up is half the way back (pulled), the stick's down.
	_tip_at(h, _bars_hand(bars, 1.0, 0.0, 0.05))
	_step(panel, [h])
	_ok(absf(hands.bars_pitch() - 0.5) < 0.01 and absf(hands.steer(&"bars")) < 0.01 and absf(panel.hand_thumbstick(0).y + 0.5) < 0.01,
		"cycle: the hand lifted 5 cm tips them half back, the stick's down (%s)" % str(panel.hand_thumbstick(0)))
	_tip_at(h, _bars_hand(bars, 1.0, 0.0, -0.20))
	_step(panel, [h])
	_ok(is_equal_approx(hands.bars_pitch(), -1.0), "cycle: and pushed down all the way, they are pushed")
	# Drawn with the hand.
	_tip_at(h, _bars_hand(bars, 1.0, 0.5, -0.05))
	_step(panel, [h])
	input._left_vr_ctrl = _ctrl(h)
	input._process(0.016)
	panel.tick(0.016)
	var want := panel.rest_basis_of(bars) * Basis(Vector3.UP, -deg_to_rad(ArcadeControlModule.BARS_YAW_DEG) * hands.steer(&"bars")) \
		* Basis(Vector3.RIGHT, deg_to_rad(ArcadeControlModule.BARS_PITCH_DEG) * hands.bars_pitch())
	_ok(bars.basis.is_equal_approx(want) and absf(hands.steer(&"bars") - 0.5) < 0.01 and absf(hands.bars_pitch() + 0.5) < 0.01,
		"cycle: the bars are drawn turned and tipped as the hand has them, at once")
	var axes := input._heard_axes.get(0, Vector4i.ZERO) as Vector4i
	_ok(absf(axes.x - 0.5 * ArcadeInput.ANALOG_SCALE) < 0.02 * ArcadeInput.ANALOG_SCALE and absf(axes.y + 0.5 * ArcadeInput.ANALOG_SCALE) < 0.02 * ArcadeInput.ANALOG_SCALE,
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


# --- handlebars ----------------------------------------------------------------

func _group_handlebars() -> void:
	var r := await _rig("propcycl")
	var panel: ArcadeControlModule = r["panel"]
	var hands: ArcadePanelHands = panel.hands()
	var bars := panel.find_child("BarsPivot", true, false) as Node3D
	var grab := _bars_grab(hands)
	var hr := _hand("right")
	var hl := _hand("left")
	# A squeeze takes the bars as a trigger does, and lets go when the squeeze does (the trigger pulled as well changes nothing).
	_tip_at(hr, _bars_hand(bars, 1.0, 0.0))
	_squeeze(hr, 1.0)
	_step(panel, [hr, hl])
	_ok(hands.holds(&"bars") and grab.holder == _ctrl(hr), "handlebars: a squeeze on a grip takes hold of the bars")
	_trigger(hr, 1.0)
	_step(panel, [hr, hl])
	_trigger(hr, 0.0)
	_step(panel, [hr, hl])
	_ok(hands.holds(&"bars"), "handlebars: a trigger pulled and let go while the squeeze is held does not let go of them")
	_squeeze(hr, 0.2)
	_step(panel, [hr, hl])
	_ok(not hands.holds(&"bars") and grab.holder == null, "handlebars: letting go of the squeeze lets go of them")
	# Taken with the trigger, a squeeze means nothing and the trigger lets go.
	_trigger(hr, 1.0)
	_step(panel, [hr, hl])
	_squeeze(hr, 1.0)
	_step(panel, [hr, hl])
	_squeeze(hr, 0.0)
	_step(panel, [hr, hl])
	_ok(hands.holds(&"bars"), "handlebars: taken with the trigger they are held while it is, whatever the squeeze does")
	_trigger(hr, 0.0)
	_step(panel, [hr, hl])
	_ok(not hands.holds(&"bars"), "handlebars: and let go when it is")
	# A second hand takes the OTHER grip, never the one a hand is on.
	_trigger(hr, 1.0)
	_step(panel, [hr, hl])
	_tip_at(hl, _bars_hand(bars, 1.0, 0.0))
	_squeeze(hl, 1.0)
	_step(panel, [hr, hl])
	_ok(grab.holder == _ctrl(hr) and grab.holder2 == null, "handlebars: a second hand at the grip the first is on takes nothing")
	_squeeze(hl, 0.0)
	_step(panel, [hr, hl])
	_tip_at(hl, _bars_hand(bars, -1.0, 0.0))
	_squeeze(hl, 1.0)
	_step(panel, [hr, hl])
	_ok(grab.holder == _ctrl(hr) and grab.holder2 == _ctrl(hl), "handlebars: at the other grip it takes hold, and the bars have two hands")
	_ok(is_zero_approx(hands.steer(&"bars")) and is_zero_approx(hands.bars_pitch()), "handlebars: joining moves nothing")
	_ok(grab._outlines.size() == 2 and not grab._outlines[0].visible and not grab._outlines[1].visible,
		"handlebars: with a hand on each, neither grip is outlined (a control in a hand has no outline)")
	# Two hands turn them by the line between them: the right grip toward the rider and the left away is a turn to the right, and they tip nothing.
	_tip_at(hr, _bars_hand(bars, 1.0, 0.5))
	_tip_at(hl, _bars_hand(bars, -1.0, 0.5))
	_step(panel, [hr, hl])
	_ok(absf(hands.steer(&"bars") - 0.5) < 0.01 and absf(hands.bars_pitch()) < 0.01, "handlebars: both hands round the stem to half the lock: half a turn right, no tip (%.3f, %.3f)" % [hands.steer(&"bars"), hands.bars_pitch()])
	_tip_at(hr, _bars_hand(bars, 1.0, -1.0))
	_tip_at(hl, _bars_hand(bars, -1.0, -1.0))
	_step(panel, [hr, hl])
	_ok(is_equal_approx(hands.steer(&"bars"), -1.0), "handlebars: and the other way to the lock")
	# Both pushed toward the rider tip them back, both lifted likewise, both together all the way.
	_tip_at(hr, _bars_hand(bars, 1.0, 0.0, 0.0, 0.05))
	_tip_at(hl, _bars_hand(bars, -1.0, 0.0, 0.0, 0.05))
	_step(panel, [hr, hl])
	_ok(absf(hands.bars_pitch() - 0.5) < 0.01 and absf(hands.steer(&"bars")) < 0.01, "handlebars: both hands 5 cm toward the rider tip them half back and turn nothing (%.3f, %.3f)" % [hands.bars_pitch(), hands.steer(&"bars")])
	_tip_at(hr, _bars_hand(bars, 1.0, 0.0, 0.05))
	_tip_at(hl, _bars_hand(bars, -1.0, 0.0, 0.05))
	_step(panel, [hr, hl])
	_ok(absf(hands.bars_pitch() - 0.5) < 0.01, "handlebars: both lifted 5 cm the same")
	_tip_at(hr, _bars_hand(bars, 1.0, 0.0, 0.05, 0.05))
	_tip_at(hl, _bars_hand(bars, -1.0, 0.0, 0.05, 0.05))
	_step(panel, [hr, hl])
	_ok(is_equal_approx(hands.bars_pitch(), 1.0), "handlebars: and lifted and pulled, all the way")
	# One hand lets go: the bars stay where they were, turned and tipped, and the other goes on from there.
	_tip_at(hr, _bars_hand(bars, 1.0, 0.5, 0.05))
	_tip_at(hl, _bars_hand(bars, -1.0, 0.5, 0.05))
	_step(panel, [hr, hl])
	var held_at := hands.steer(&"bars")
	var tipped_at := hands.bars_pitch()
	_ok(absf(held_at - 0.5) < 0.01 and absf(tipped_at - 0.5) < 0.01, "handlebars: both hands turn them half and lift them 5 cm: half a turn and half back (%.3f, %.3f)" % [held_at, tipped_at])
	_trigger(hr, 0.0)
	_step(panel, [hr, hl])
	_ok(hands.holds(&"bars") and grab.holder == _ctrl(hl) and grab.holder2 == null and absf(hands.steer(&"bars") - held_at) < 0.001 and absf(hands.bars_pitch() - tipped_at) < 0.001,
		"handlebars: one hand letting go leaves the bars where they were, in the other (%.3f, %.3f)" % [hands.steer(&"bars"), hands.bars_pitch()])
	_tip_at(hl, _bars_hand(bars, -1.0, 0.75, 0.07))
	_step(panel, [hr, hl])
	_ok(absf(hands.steer(&"bars") - 0.75) < 0.01 and absf(hands.bars_pitch() - 0.7) < 0.01,
		"handlebars: and the hand that is left goes on turning and lifting them (%.3f, %.3f)" % [hands.steer(&"bars"), hands.bars_pitch()])
	_ok(not grab._outlines[0].visible and not grab._outlines[1].visible, "handlebars: held by one hand, neither grip is outlined")
	_squeeze(hl, 0.0)
	_step(panel, [hr, hl])
	_ok(not hands.holds(&"bars"), "handlebars: and when it lets go they are free")
	# A hand a metre off has lost them, whichever hand it is.
	_trigger(hr, 1.0)
	_tip_at(hr, _bars_hand(bars, 1.0, 0.0))
	_step(panel, [hr, hl])
	_tip_at(hr, _bars_hand(bars, 1.0, 0.0) + Vector3(1.0, 0.0, 0.0))
	_step(panel, [hr, hl])
	_ok(not hands.holds(&"bars"), "handlebars: a hand a metre off has lost them")
	_trigger(hr, 0.0)
	_step(panel, [hr, hl])
	# Joining bars that are already turned moves nothing, and neither does one hand leaving after only the other has moved on: the hand that is left takes them from where they are.
	_tip_at(hr, _bars_hand(bars, 1.0, 0.0))
	_trigger(hr, 1.0)
	_step(panel, [hr, hl])
	_tip_at(hr, _bars_hand(bars, 1.0, 0.5))
	_step(panel, [hr, hl])
	_draw_bars(panel, bars, hands.steer(&"bars"))
	_tip_at(hl, _bars_hand(bars, -1.0, 0.5))
	_squeeze(hl, 1.0)
	_step(panel, [hr, hl])
	_ok(grab.holder2 == _ctrl(hl) and absf(hands.steer(&"bars") - 0.5) < 0.01,
		"handlebars: a second hand joining bars that are already turned half moves nothing (%.3f)" % hands.steer(&"bars"))
	_tip_at(hl, _bars_hand(bars, -1.0, 1.0))
	_step(panel, [hr, hl])
	_ok(absf(hands.steer(&"bars") - 0.75) < 0.01, "handlebars: and with the first hand still, the line between them turns half as far as the hand that moves (%.3f)" % hands.steer(&"bars"))
	_trigger(hr, 0.0)
	_step(panel, [hr, hl])
	_ok(grab.holder == _ctrl(hl) and absf(hands.steer(&"bars") - 0.75) < 0.01, "handlebars: and the hand that is left holds them where they were, not where its own arc says (%.3f)" % hands.steer(&"bars"))
	_squeeze(hl, 0.0)
	_step(panel, [hr, hl])
	_draw_bars(panel, bars, 0.0)
	# A squeeze already held on the way in takes nothing: only its rising edge does.
	_squeeze(hl, 1.0)
	_tip_at(hl, _bars_hand(bars, -1.0, 0.0) + Vector3(1.0, 0.0, 0.0))
	_step(panel, [hr, hl])
	_tip_at(hl, _bars_hand(bars, -1.0, 0.0))
	_step(panel, [hr, hl])
	_ok(not hands.holds(&"bars"), "handlebars: a squeeze already held on the way in takes nothing, only its edge does")
	_squeeze(hl, 0.0)
	_step(panel, [hr, hl])
	_squeeze(hl, 1.0)
	_step(panel, [hr, hl])
	_ok(hands.holds(&"bars"), "handlebars: let go and squeezed again, it does")
	# Everything let go at once (the machine went off): no hand is left on the bars.
	_tip_at(hr, _bars_hand(bars, 1.0, 0.0))
	_trigger(hr, 1.0)
	_step(panel, [hr, hl])
	_ok(grab.holder != null and grab.holder2 != null, "handlebars: two hands on the bars again")
	hands.release_all()
	_ok(not hands.holds(&"bars") and grab.holder == null and grab.holder2 == null, "handlebars: released all at once, no hand is left on them")
	_squeeze(hl, 0.0)
	_trigger(hr, 0.0)
	_step(panel, [hr, hl])
	# (White box.) Two hands whose line was 5 cm long at the start say nothing about which way it points, however it turns: the first hand's own arc, none here, stands in.
	var axis := grab.node.position
	grab._ids = [11, 12]
	grab._ref = {11: axis + Vector3(0.30, 0.0, 0.0), 12: axis + Vector3(0.35, 0.0, 0.0)}
	grab._now = {11: axis + Vector3(0.30, 0.0, 0.0), 12: axis + Vector3(0.30, 0.0, 0.05)}
	_ok(is_zero_approx(grab._yaw()), "handlebars: a pair of hands 5 cm apart turn nothing by the line between them (%.3f)" % grab._yaw())
	grab._now[12] = axis + Vector3(0.30, 0.0, 0.40)
	grab._ref[12] = axis + Vector3(-0.30, 0.0, 0.0)
	grab._now[11] = axis + Vector3(0.30, 0.0, 0.0)
	_ok(absf(grab._yaw() - PI * 0.5) < 0.001, "handlebars: and hands 60 cm apart do: the line a quarter turn round is a quarter turn (%.3f)" % grab._yaw())
	grab._ids.clear()
	grab._ref.clear()
	grab._now.clear()
	# A squeeze takes nothing that is not bars: a stick on a deck, taken at its ball, wants the trigger.
	var r2 := await _rig("sf2")
	var panel2: ArcadeControlModule = r2["panel"]
	var hands2: ArcadePanelHands = panel2.hands()
	var h2 := _hand("right")
	_tip_at(h2, _ball_at(panel2))
	_squeeze(h2, 1.0)
	_step(panel2, [h2])
	_ok(not hands2.holds(&"stick"), "handlebars: a squeeze on a stick takes nothing: it is the trigger's")
	_squeeze(h2, 0.0)
	_step(panel2, [h2])
	_trigger(h2, 1.0)
	_step(panel2, [h2])
	_ok(hands2.holds(&"stick"), "handlebars: the trigger takes it")
	# A second hand at a stick a hand holds takes nothing from it: only a pair of bars has two grips.
	var h3 := _hand("left")
	_tip_at(h3, _ball_at(panel2))
	_trigger(h3, 1.0)
	_step(panel2, [h2, h3])
	var stick_grab: ArcadePanelHands.ControlGrab = null
	for g in hands2.grabs():
		if g.kind == &"stick":
			stick_grab = g
	_ok(stick_grab != null and stick_grab.holder == _ctrl(h2), "handlebars: a second hand at a stick that a hand holds does not take it from the first")
	_trigger(h3, 0.0)
	_trigger(h2, 0.0)
	_step(panel2, [h2, h3])
	# A motorbike's bars: a squeeze takes them too, and two hands lean it by the mean of how far they are pushed.
	var r3 := await _rig("hangon")
	var panel3: ArcadeControlModule = r3["panel"]
	var hands3: ArcadePanelHands = panel3.hands()
	var grab3 := _bars_grab(hands3)
	var hbr := _hand("right")
	var hbl := _hand("left")
	var grip_r := (panel3.find_child("BarGripR", true, false) as Node3D).global_position
	var grip_l := (panel3.find_child("BarGripL", true, false) as Node3D).global_position
	_tip_at(hbr, grip_r)
	_squeeze(hbr, 1.0)
	_step(panel3, [hbr, hbl])
	_ok(hands3.holds(&"bars") and grab3 != null, "handlebars: a squeeze takes a motorbike's bars too")
	_tip_at(hbl, grip_l)
	_squeeze(hbl, 1.0)
	_step(panel3, [hbr, hbl])
	_ok(grab3.holder2 == _ctrl(hbl), "handlebars: and a second hand the other grip")
	var along := (grab3.node.get_parent() as Node3D).global_basis.x
	_tip_at(hbr, grip_r + along * ArcadePanelHands.BARS_THROW)
	_step(panel3, [hbr, hbl])
	_ok(absf(hands3.steer(&"bars") - 0.5) < 0.01, "handlebars: one hand pushing the bar 15 cm over and the other still lean the bike half (the mean of the two: %.3f)" % hands3.steer(&"bars"))
	_tip_at(hbl, grip_l + along * ArcadePanelHands.BARS_THROW)
	_step(panel3, [hbr, hbl])
	_ok(is_equal_approx(hands3.steer(&"bars"), 1.0), "handlebars: and both, all the way")
	_squeeze(hbr, 0.0)
	_squeeze(hbl, 0.0)
	_step(panel3, [hbr, hbl])
	_ok(not hands3.holds(&"bars"), "handlebars: let go of, the motorbike's bars are free")


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
	# The machine switched off: the finger on the cap stays on it (`off/` says what it does there), and what it holds is sent nowhere.
	_tip_at(h, _cap_top(panel, "Btn2"))
	input._process(0.016)
	_ok((int(input.last_sent.get(0, 0)) & _bit(B[1])) != 0, "input: (button 2 pressed)")
	(r["sys"] as RetroSystem).is_powered_on = false
	input.last_sent.clear()
	input._process(0.016)
	_ok(panel.hands_active() and panel.hand_buttons() == _bit(B[1]) and input.last_sent.is_empty(),
		"input: the machine switched off, the finger is still on the cap and nothing is sent")
	(r["sys"] as RetroSystem).is_powered_on = true
	input._right_vr_ctrl = null


# --- transfer ------------------------------------------------------------------

## A hand holding a control takes the controllers' sticks with it: they are the game's while it holds (and walk the player
## no further), the player's again when it lets go. Its outline is yellow while a hand could take the control and gone while
## one holds it.
func _group_transfer() -> void:
	var r := await _rig()
	var panel: ArcadeControlModule = r["panel"]
	var input: ArcadeInput = r["input"]
	var hands: ArcadePanelHands = panel.hands()
	var loco := LocomotionManager.new()
	input._locomotion_manager = loco
	var h := _hand("right")
	var pad := _hand("left")
	input._right_vr_ctrl = _ctrl(h)
	input._left_vr_ctrl = _ctrl(pad)
	var up := _bit(ControllerBindings.JOYPAD_UP)
	var r2 := _bit(ControllerBindings.JOYPAD_R2)
	input._button_map["right_trigger"] = ControllerBindings.JOYPAD_R2
	(pad["tracker"] as XRControllerTracker).set_input(&"primary", Vector2(0.0, 1.0))
	var ball := _ball_at(panel)
	_tip_at(h, ball)
	input._process(0.016)
	var grab := hands._grab_of(&"stick", 0)
	_ok(grab._outline != null and grab._outline.visible, "transfer: a hand at the stick with nothing in it shows the stick's outline")
	_ok(grab._outline.outline_color_is(WidgetOutline.SELECT_COLOR), "transfer: and it is the yellow of a selectable thing, not the green")
	_ok(not loco.is_blocked(LocomotionManager.CHANNEL_ALL) and input.held_players.is_empty(),
		"transfer: nothing is held yet, and the player walks as ever")
	_ok((int(input.last_sent.get(0, 0)) & up) == 0, "transfer: a thumbstick pushed forward plays nothing for a player at the cabinet who holds nothing")
	_trigger(h, 1.0)
	input._process(0.016)
	_ok(hands.holds(&"stick", 0) and input.held_players.has(0) and not input.playing, "transfer: the stick is in a hand (and nobody is attached)")
	_ok(not grab._outline.visible, "transfer: and the outline of a control in a hand is gone")
	_ok(loco.is_blocked(LocomotionManager.CHANNEL_LEFT) and loco.is_blocked(LocomotionManager.CHANNEL_RIGHT),
		"transfer: holding it, neither stick walks or turns the player")
	_ok((int(input.last_sent.get(0, 0)) & up) != 0, "transfer: and the other hand's thumbstick pushed forward is UP, the game's")
	_ok((int(input.last_sent.get(0, 0)) & r2) == 0, "transfer: the trigger that holds the stick is not also the button it is bound to")
	_ok((int(input.last_sent.get(1, 0)) & up) == 0, "transfer: the other player hears nothing of it")
	# The control leg: attached, with the trigger pulled far from any control, the same trigger is that button.
	_trigger(h, 0.0)
	input._process(0.016)
	_ok(not loco.is_blocked(LocomotionManager.CHANNEL_ALL) and input.held_players.is_empty(),
		"transfer: let go, the player walks again")
	_ok((int(input.last_sent.get(0, 0)) & up) == 0, "transfer: and the thumbstick is theirs, not the game's")
	_ok(grab._outline.visible, "transfer: and the outline is back, the hand still being at the stick")
	input.attached[0] = true
	_tip_at(h, ball + Vector3(0.0, 1.0, 0.0))
	_trigger(h, 1.0)
	input._process(0.016)
	_ok((int(input.last_sent.get(0, 0)) & r2) != 0 and input.held_players.is_empty(),
		"transfer: (control) the trigger of a hand that holds nothing is its button, attached")
	input.attached.erase(0)
	_trigger(h, 0.0)
	input._process(0.016)
	# The machine going off mid-hold: the stick is still in the hand (a control works with the power off) and the player is held back as they were, but the thumbstick
	# pushed forward goes nowhere.
	_tip_at(h, ball)
	_trigger(h, 1.0)
	input._process(0.016)
	_ok(input.held_players.has(0) and loco.is_blocked(LocomotionManager.CHANNEL_ALL), "transfer: held again")
	(r["sys"] as RetroSystem).is_powered_on = false
	input.last_sent.clear()
	input._process(0.016)
	_ok(hands.holds(&"stick", 0) and input.held_players.has(0) and loco.is_blocked(LocomotionManager.CHANNEL_ALL),
		"transfer: the machine switched off, the hand still holds the stick and the player is still held back")
	_ok(input.last_sent.is_empty(), "transfer: and the thumbstick pushed forward is the game's no longer: nothing is sent")
	_trigger(h, 0.0)
	input._process(0.016)
	_ok(input.held_players.is_empty() and not loco.is_blocked(LocomotionManager.CHANNEL_ALL),
		"transfer: let go, the player walks again")
	(r["sys"] as RetroSystem).is_powered_on = true
	input._left_vr_ctrl = null
	input._right_vr_ctrl = null
	input._locomotion_manager = null
	loco.free()


# --- off -----------------------------------------------------------------------

## A cabinet that is switched off still has its controls worked: a finger presses a cap, the trigger takes the stick, the wheel turns with the hand. They were dead (the machine
## off, every hand let go), which in a headset read as a panel that could not be touched. What the hands hold reaches no core then, and a motor does not run.
func _group_off() -> void:
	var r := await _rig()
	var sys: RetroSystem = r["sys"]
	var panel: ArcadeControlModule = r["panel"]
	var input: ArcadeInput = r["input"]
	var hands: ArcadePanelHands = panel.hands()
	var h := _hand()
	input._right_vr_ctrl = _ctrl(h)
	var B := ArcadeProfiles.BUTTON_BITS
	var cap := panel.find_child("Btn1", true, false) as Node3D
	var rest_z := cap.position.z
	sys.is_powered_on = false
	input.last_sent.clear()
	# A cap.
	_tip_at(h, _cap_top(panel, "Btn1"))
	input._process(0.016)
	_ok(panel.hands_active() and panel.hand_buttons() == _bit(B[0]), "off: a finger on button 1 of a cabinet that is switched off presses it")
	_ok(cap.position.z < rest_z - ArcadeControlModule.CAP_PRESS * 0.9, "off: and the cap sinks in its flange")
	_ok(input.last_sent.is_empty(), "off: and nothing is sent to the core")
	_tip_at(h, _cap_top(panel, "Btn2"))
	input._process(0.016)
	_ok(panel.hand_buttons() == _bit(B[1]) and is_equal_approx(cap.position.z, rest_z), "off: rolled onto button 2 it is that one that is down, and button 1 is up again")
	_tip_at(h, _cap_top(panel, "Btn2") + panel.global_transform.basis.z * 0.3)
	input._process(0.2)
	_ok(not panel.hands_active(), "off: lifted away, no cap is down")
	# The stick: its outline says it can be taken, the hand has no laser at it, the trigger takes it, it leans with the hand and comes back.
	var laser := _laser(h)
	var ball := _ball_at(panel)
	var grab := hands._grab_of(&"stick", 0)
	_tip_at(h, ball)
	input._process(0.016)
	_ok(grab._outline != null and grab._outline.visible, "off: a hand at the stick of a cabinet that is off sees its outline")
	_ok(not _laser_on(laser), "off: and has no laser at it, so the trigger it pulls is for the stick")
	_trigger(h, 1.0)
	input._process(0.016)
	_ok(hands.holds(&"stick", 0), "off: the trigger takes hold of the stick")
	_tip_at(h, ball + _right(panel) * 0.03)
	input._process(0.016)
	panel.tick(0.016)
	_ok(panel.stick_lean().x > 0.99, "off: and the stick leans to the right with the hand")
	_ok(input.last_sent.is_empty(), "off: and the game hears nothing of it")
	_trigger(h, 0.0)
	input._process(0.016)
	for i in 40:
		panel.tick(0.05)
	_ok(panel.stick_lean() == Vector2.ZERO, "off: let go, the stick comes back to the middle")

	# The wheel and the pedals.
	await _clear()
	r = await _rig("daytona")
	sys = r["sys"]
	panel = r["panel"]
	input = r["input"]
	hands = panel.hands()
	h = _hand()
	input._right_vr_ctrl = _ctrl(h)
	sys.is_powered_on = false
	input.last_sent.clear()
	var quarter := deg_to_rad(ArcadeControlModule.WHEEL_LOCK_DEG) * 0.5
	_tip_at(h, _rim(panel, 0.0))
	_trigger(h, 1.0)
	input._process(0.016)
	_ok(hands.holds(&"wheel"), "off: the trigger on the rim takes hold of the wheel of a cabinet that is off")
	_tip_at(h, _rim(panel, quarter))
	input._process(0.016)
	for i in 30:
		panel.tick(0.016)
	_ok(_near_f(panel.steering(), 0.5), "off: and the wheel is drawn turned half to the right with it (%.2f)" % panel.steering())
	_ok(input.last_sent.is_empty(), "off: and nothing is sent")
	_trigger(h, 0.0)
	input._process(0.016)
	_tip_at(h, Vector3(0, 5, 0))
	input._process(0.016)
	for i in 60:
		panel.tick(0.05)
	_ok(_near_f(panel.steering(), 0.0, 0.01), "off: let go, it comes back to the middle")
	var gas := panel.find_child("GasDeck", true, false) as MeshInstance3D
	_tip_at(h, gas.global_transform * Vector3(0, 0.012, -0.05))
	input._process(0.016)
	for i in 30:
		panel.tick(0.016)
	_ok(panel.hand_buttons() == _bit(ControllerBindings.JOYPAD_R2) and panel.pedal_down("gas") > 0.9 and input.last_sent.is_empty(),
		"off: a finger on the gas pedal of a cabinet that is off pushes it down, and nothing is sent")

	# A gear lever is followed, and the cabinet is in no gear: nothing is playing.
	await _clear()
	r = await _rig("polepos", 6, true)
	sys = r["sys"]
	panel = r["panel"]
	input = r["input"]
	hands = panel.hands()
	h = _hand()
	input._right_vr_ctrl = _ctrl(h)
	sys.is_powered_on = false
	var lever := panel.find_child("ShifterPivot", true, false) as Node3D
	var lever_rest := lever.basis
	_tip_at(h, _knob_at(lever, lever_rest, 0.0))
	_trigger(h, 1.0)
	input._process(0.016)
	_tip_at(h, _knob_at(lever, lever_rest, 1.0))
	input._process(0.016)
	for i in 10:
		panel.tick(0.016)
	_ok(hands.holds(&"lever") and panel.shift_amount() > 0.95, "off: the gear lever of a cabinet that is off is thrown with the hand (%.2f)" % panel.shift_amount())
	_ok(not panel.shift_high(), "off: but the cabinet is in no gear, nothing being played")
	_trigger(h, 0.0)
	input._process(0.016)
	_tip_at(h, Vector3(0, 5, 0))
	input._process(0.016)
	for i in 60:
		panel.tick(0.05)
	_ok(panel.shift_amount() < 0.05, "off: and it goes back to first when let go (%.2f)" % panel.shift_amount())

	# A flight cockpit: its throttle stays where the hand leaves it, and its base is a motor, which does not run. Switched on with the stick in the hand, it is played at once.
	await _clear()
	r = await _rig("aburner2", 6, true)
	sys = r["sys"]
	panel = r["panel"]
	input = r["input"]
	hands = panel.hands()
	var right := _hand("right")
	var left := _hand("left")
	input._right_vr_ctrl = _ctrl(right)
	input._left_vr_ctrl = _ctrl(left)
	panel.motion_override = 1
	sys.is_powered_on = false
	input.last_sent.clear()
	var stick_ball := panel.find_child("StickBall", true, false) as Node3D
	var grip_at := stick_ball.global_position
	_tip_at(right, grip_at)
	_trigger(right, 1.0)
	input._process(0.016)
	_tip_at(right, grip_at + _right(panel) * 0.15)
	input._process(0.016)
	for i in 40:
		panel.tick(0.05)
	_ok(hands.holds(&"stick") and hands.stick_lean(0).x > 0.99, "off: the flight stick of a cabinet that is off leans with the hand")
	_ok(panel.motion_state() == Vector2.ZERO, "off: and the base does not move, its motor being off (%s)" % str(panel.motion_state()))
	sys.is_powered_on = true
	input._process(0.016)
	for i in 40:
		panel.tick(0.05)
	_ok((int(input.last_sent.get(0, 0)) & _bit(ControllerBindings.JOYPAD_RIGHT)) != 0 and panel.motion_state().x > 0.5,
		"off: (control) switched on with the stick in the hand it is played, and the base banks (%s)" % str(panel.motion_state()))
	_trigger(right, 0.0)
	input._process(0.016)
	_tip_at(right, Vector3(0, 5, 0))
	input._process(0.016)
	sys.is_powered_on = false
	input._process(0.016)
	input.last_sent.clear()
	var knob := panel.find_child("ThrottleKnob", true, false) as Node3D
	var ahead := -panel.global_transform.basis.z.normalized()
	var knob_at := knob.global_position
	_tip_at(left, knob_at)
	_trigger(left, 1.0)
	input._process(0.016)
	_tip_at(left, knob_at + ahead * 0.05)
	input._process(0.016)
	_trigger(left, 0.0)
	input._process(0.016)
	_tip_at(left, Vector3(0, 5, 0))
	for i in 30:
		input._process(0.016)
	_ok(_near_f(hands.throttle_value(), 0.5), "off: a throttle pushed forward on a cabinet that is off stays where it was left (%.2f)" % hands.throttle_value())
	_ok(input.last_sent.is_empty(), "off: and nothing is sent")
	input._right_vr_ctrl = null
	input._left_vr_ctrl = null


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
	# The panel hidden, gone, a morph under a held stick: every laser is given back.
	_tip_at(h, _ball_at(panel))
	_trigger(h, 1.0)
	_step(panel, [h])
	_ok(not _laser_on(laser), "laser: (held again)")
	panel.visible = false
	_step(panel, [h])
	_ok(_laser_on(laser) and not hands.holds(&"stick", 0), "laser: hiding the panel gives the laser back and lets the stick go")
	panel.visible = true
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


# --- sticks --------------------------------------------------------------------

## A Taiko player's stick: the cabinet's player, and the left (0) or right (1) one of the pair.
func _stick(sys: RetroSystem, player: int, side: int) -> ArcadeDrumstick:
	for piece: Variant in sys.captive_gear():
		var stick := piece as ArcadeDrumstick
		if stick != null and stick.player == player and stick.side == side:
			return stick
	return null


## A hand takes `stick` out of its cradle, as a squeeze does: the controller where the stick lies and the hand's pickup function reaching for the cradle (what a hand closes on).
func _take(h: Dictionary, stick: ArcadeDrumstick) -> void:
	(h["origin"] as XROrigin3D).global_transform = stick.global_transform
	if not h.has("pickup"):
		var made := PICKUP_SCENE.instantiate() as XRToolsFunctionPickup
		_ctrl(h).add_child(made)
		h["pickup"] = made
		await _wait(2)
	var pickup := h["pickup"] as XRToolsFunctionPickup
	pickup._pick_up_object(stick.captive_well if stick.captive_well.picked_up_object == stick else stick)
	await _wait(2)


func _button(h: Dictionary, action: StringName, down: bool) -> void:
	(h["tracker"] as XRControllerTracker).set_input(action, down)


## The pad ids tapped on `port` now.
func _tapped(input: ArcadeInput, port: int = 0) -> Array:
	var held: Array = (input._taps.get(port, {}) as Dictionary).keys()
	held.sort()
	return held


func _group_sticks() -> void:
	var r := await _rig("taiko6")
	var sys: RetroSystem = r["sys"]
	var input: ArcadeInput = r["input"]
	var panel: ArcadeControlModule = r["panel"]
	await _wait(6)
	var left := _stick(sys, 0, 0)
	var right := _stick(sys, 0, 1)
	var second := _stick(sys, 1, 0)
	_ok(left != null and right != null and second != null, "sticks: a Taiko cabinet has a pair of sticks for each of its players")
	if left == null or right == null or second == null:
		return
	var don_left := ArcadeProfiles.button_bit(3)
	var don_right := ArcadeProfiles.button_bit(2)
	var ka_left := ArcadeProfiles.button_bit(4)
	var ka_right := ArcadeProfiles.button_bit(1)
	# The left hand takes the left stick; its trigger is a don on the left half of the face, once for a squeeze.
	var hl := _hand("left")
	await _take(hl, left)
	_ok(left.holding_controller() == _ctrl(hl) and not left.held_by_desktop() and input.engaged(),
		"sticks: a stick taken by a headset's hand is held by that controller, and somebody is at the cabinet")
	input._taps.clear()
	_trigger(hl, 1.0)
	left._read_buttons(_ctrl(hl))
	_ok(_tapped(input) == [don_left], "sticks: the trigger is a don on the left half of the face, from the left hand (%s)" % str(_tapped(input)))
	input._taps.clear()
	left._read_buttons(_ctrl(hl))
	_ok(_tapped(input).is_empty(), "sticks: a trigger that stays down hits once")
	_trigger(hl, 0.5)
	left._read_buttons(_ctrl(hl))
	_trigger(hl, 1.0)
	left._read_buttons(_ctrl(hl))
	_ok(_tapped(input).is_empty(), "sticks: a trigger eased off only to half has not let go, and pressing it again from there hits nothing")
	_trigger(hl, 0.1)
	left._read_buttons(_ctrl(hl))
	_trigger(hl, 1.0)
	left._read_buttons(_ctrl(hl))
	_ok(_tapped(input) == [don_left], "sticks: let go and squeezed again, it hits again")
	# The thumb buttons: A / X a ka on the rim, B / Y a don on the face, once a press.
	_trigger(hl, 0.0)
	left._read_buttons(_ctrl(hl))
	input._taps.clear()
	_button(hl, &"ax_button", true)
	left._read_buttons(_ctrl(hl))
	_ok(_tapped(input) == [ka_left], "sticks: A / X is a ka on the left half of the rim (%s)" % str(_tapped(input)))
	input._taps.clear()
	left._read_buttons(_ctrl(hl))
	_ok(_tapped(input).is_empty(), "sticks: and a button held down hits once")
	_button(hl, &"ax_button", false)
	left._read_buttons(_ctrl(hl))
	_button(hl, &"by_button", true)
	left._read_buttons(_ctrl(hl))
	_ok(_tapped(input) == [ka_left, don_left] or _tapped(input) == [don_left, ka_left] or _tapped(input).has(don_left), "sticks: B / Y is a don on the face (%s)" % str(_tapped(input)))
	_button(hl, &"by_button", false)
	left._read_buttons(_ctrl(hl))
	# The right hand takes the right stick: the right half of the drum.
	var hr := _hand("right")
	await _take(hr, right)
	input._taps.clear()
	_trigger(hr, 1.0)
	right._read_buttons(_ctrl(hr))
	_ok(_tapped(input) == [don_right], "sticks: the right hand's trigger is a don on the right half (%s)" % str(_tapped(input)))
	_trigger(hr, 0.0)
	right._read_buttons(_ctrl(hr))
	input._taps.clear()
	_button(hr, &"ax_button", true)
	right._read_buttons(_ctrl(hr))
	_ok(_tapped(input) == [ka_right], "sticks: and its A is a ka on the right half of the rim (%s)" % str(_tapped(input)))
	_button(hr, &"ax_button", false)
	right._read_buttons(_ctrl(hr))
	# Which half is the HAND's side, not the stick's: the left hand holding the right stick still hits the left half, on that stick's own player's port.
	right.drop()
	await _wait(2)
	left.drop()
	await _wait(2)
	await _take(hl, right)
	input._taps.clear()
	_trigger(hl, 1.0)
	right._read_buttons(_ctrl(hl))
	_ok(_tapped(input) == [don_left], "sticks: the half is the hand's own side whichever stick it holds (%s)" % str(_tapped(input)))
	_trigger(hl, 0.0)
	right._read_buttons(_ctrl(hl))
	# The second player's stick hits on the second player's port, and not on the first's.
	right.drop()
	await _wait(2)
	await _take(hl, second)
	input._taps.clear()
	_trigger(hl, 1.0)
	second._read_buttons(_ctrl(hl))
	_ok(input._taps.size() == 1 and (input._taps.get(1, {}) as Dictionary).has(don_left), "sticks: the second player's stick hits the second port, not the first (%s)" % str(input._taps.keys()))
	_trigger(hl, 0.0)
	second._read_buttons(_ctrl(hl))
	second.drop()
	await _wait(2)
	# End to end, by the stick's own frame: held by a controller, a squeeze is a hit with nothing called by hand.
	await _take(hl, left)
	var struck: Array = []
	left.struck.connect(func(zone: String, kind: StringName, hit_side: int) -> void: struck.append([zone, kind, hit_side]))
	_trigger(hl, 1.0)
	await _wait(3)
	_ok(struck == [["FaceLeft", ArcadeDrumstick.DON, 0]], "sticks: held by a controller, the stick reads its hand's trigger every frame by itself (%s)" % str(struck))
	_trigger(hl, 0.0)
	await _wait(3)
	# A swing, end to end: the hand brings the head down onto the left half of the face, slowly (nothing) and then fast (a don).
	var face: Dictionary = {}
	for zone: Dictionary in ArcadeDrumstick.zones_of(panel):
		if zone["name"] == "FaceLeft":
			face = zone
	var cap := face["cap"] as MeshInstance3D
	var sector: Dictionary = cap.get_meta(&"sector")
	var radius := (float(sector["r0"]) + float(sector["r1"])) * 0.5
	var angle := (float(sector["a0"]) + float(sector["a1"])) * 0.5
	var mid := Vector3(radius * cos(angle), cap.mesh.get_aabb().end.y, -radius * sin(angle))
	var over := cap.global_transform * (mid + Vector3(0.0, 0.08, 0.0))
	var onto := cap.global_transform * (mid + Vector3(0.0, -0.02, 0.0))
	var head_at := func(point: Vector3) -> void:
		(hl["origin"] as XROrigin3D).global_transform = Transform3D(Basis.IDENTITY, point - ArcadeDrumstick.TIP)
	struck.clear()
	head_at.call(over)
	await _wait(4)
	for step in 20:
		head_at.call(over.lerp(onto, float(step + 1) / 20.0))
		await _wait(1)
	await _wait(3)
	_ok(struck.is_empty(), "sticks: a head lowered onto the drum slowly (0.2 m/s) hits nothing (%s)" % str(struck))
	head_at.call(over)
	await _wait(4)
	_ok(left.tip_position().distance_to(over) < 0.005,
		"sticks: held over the drum the stick stays where the hand has it, and is not drawn back into its cradle a quarter of a metre off (%.3f m off)" % left.tip_position().distance_to(over))
	head_at.call(onto)
	await _wait(3)
	_ok(struck == [["FaceLeft", ArcadeDrumstick.DON, 0]], "sticks: the same head brought down fast on the same place is a don on the left face (%s)" % str(struck))
	head_at.call(over)
	await _wait(4)
	head_at.call(onto)
	await _wait(3)
	_ok(struck.size() == 2, "sticks: and, lifted off and brought down again, hits again (%d)" % struck.size())
	# At its cradle it IS shown in it: the hand brings the grip to the seat, and letting go there seats it.
	var well := left.captive_well
	(hl["origin"] as XROrigin3D).global_transform = Transform3D(well.global_basis, well.global_position + Vector3(0.0, 0.0, 0.03))
	await _wait(20)
	_ok(left.global_position.distance_to(well.global_position) < 0.005,
		"sticks: with the grip brought to the cradle the stick is shown in it (%.3f m off)" % left.global_position.distance_to(well.global_position))
	left.drop()
	await _wait(6)
	_ok(well.picked_up_object == left and not ArcadeInput.held_by_hand(left),
		"sticks: and let go there it is taken back into the cradle, and is nobody's in a hand")
	# A stick in a hand is somebody at a cabinet that only shows its game (and one lying in its cradle is nobody).
	var used: Array[StringName] = []
	input.first_use.connect(func(kind: StringName) -> void: used.append(kind))
	sys.is_powered_on = false
	sys.attracting = true
	input._process(0.016)
	_ok(used.is_empty() and not input.engaged(), "sticks: sticks lying in their cradles leave a cabinet that is showing its game showing it (%s)" % str(used))
	await _take(hl, left)
	input._process(0.016)
	_ok(used == [&"grab"], "sticks: a stick in a hand starts the game a cabinet is only showing, as taking a gun does (%s)" % str(used))
	sys.attracting = false
	sys.is_powered_on = true
	for held: ArcadeDrumstick in [left, right, second]:
		if held.is_picked_up() and ArcadeInput.held_by_hand(held):
			held.drop()
	await _wait(2)


# --- guitar --------------------------------------------------------------------

## A GuitarFreaks player's guitar.
func _guitar(sys: RetroSystem, player: int) -> ArcadeGuitar:
	for piece: Variant in sys.captive_gear():
		var guitar := piece as ArcadeGuitar
		if guitar != null and guitar.player == player:
			return guitar
	return null


## A hand takes `guitar` by the place called `point_name` as a squeeze does: the controller where a hand would be for that place (its pose the playing pose: the guitar's own, so it only turns), and the hand's
## pickup function reaching for what it is in (its cradle, or the other hand's grip).
func _take_guitar(h: Dictionary, guitar: ArcadeGuitar, point_name: String) -> void:
	var point := guitar.get_node(point_name) as ArcadeGuitarGrab
	# The controller's pose in the guitar's frame is the point's transform: the controller stands at the guitar's times that. A first hand is at the guitar's own orientation turned into a hand's.
	var held_already := guitar.is_picked_up() and ArcadeInput.held_by_hand(guitar)
	if held_already:
		(h["origin"] as XROrigin3D).global_transform = guitar.global_transform * point.transform
	else:
		(h["origin"] as XROrigin3D).global_transform = Transform3D(Basis.IDENTITY, guitar.global_position - point.transform.affine_inverse().origin)
	if not h.has("pickup"):
		var made := PICKUP_SCENE.instantiate() as XRToolsFunctionPickup
		_ctrl(h).add_child(made)
		h["pickup"] = made
		await _wait(2)
	var pickup := h["pickup"] as XRToolsFunctionPickup
	var inside := guitar.captive_well.picked_up_object == guitar
	pickup._pick_up_object(guitar.captive_well if inside else guitar)
	await _wait(2)


func _stick_push(h: Dictionary, value: Vector2) -> void:
	(h["tracker"] as XRControllerTracker).set_input(&"primary", value)


func _group_guitar() -> void:
	var r := await _rig("gtrfrks")
	var sys: RetroSystem = r["sys"]
	var input: ArcadeInput = r["input"]
	await _wait(8)
	var g := _guitar(sys, 0)
	var other := _guitar(sys, 1)
	_ok(g != null and other != null, "guitar: a GuitarFreaks cabinet has a guitar for each of its two players")
	if g == null or other == null:
		return
	var red := 1 << ArcadeProfiles.button_bit(1)
	var green := 1 << ArcadeProfiles.button_bit(2)
	var blue := 1 << ArcadeProfiles.button_bit(3)
	var wail := 1 << ArcadeProfiles.button_bit(7)
	var pick := ArcadeProfiles.button_bit(6)
	# Hanging in its cradle it holds nothing down, whatever its buttons say.
	g._fret_down[0] = true
	g._wail_key = true
	g._knob = 0.8
	_ok(g.held_pad_bits() == 0 and g.held_sticks()[0] == Vector2.ZERO and not input.engaged(), "guitar: in its cradle it holds nothing down and nobody is at the cabinet")
	g._fret_down[0] = false
	g._wail_key = false
	g._knob = 0.0
	# The body in the right hand.
	var hr := _hand("right")
	await _take_guitar(hr, g, "BodyR")
	# Held at its bay it is SHOWN in it (the cradle's preview, as any seated thing is): the hand takes it off to where a player holds a guitar, and it lies the way a hand has it.
	_ok(g.global_basis.y.y > 0.99 and g.captive_well != null, "guitar: held at its bay it is still shown hanging in it")
	(hr["origin"] as XROrigin3D).global_position += Vector3(0.0, 0.0, 0.8)
	await _wait(60)
	var holders := g.holders()
	_ok(g.holding_controller() == _ctrl(hr) and ArcadeInput.held_by_hand(g) and input.engaged() and holders.size() == 1 and int(holders[0]["role"]) == ArcadeGuitarGrab.BODY
			and int(holders[0]["hand"]) == ArcadeGuitarGrab.RIGHT,
		"guitar: a right hand that takes it by its body holds the body, and somebody is at the cabinet")
	_ok(g.neck_side() == ArcadeGuitarGrab.LEFT and g.global_basis.y.y < ArcadeGuitar.TILT_OFF, "guitar: with the body in the right hand the neck is the left's, and lies out below the wail's angle (%.2f)" % g.global_basis.y.y)
	# One hand: it works the frets, a free hand strums.
	var hl := _hand("left")
	_trigger(hr, 1.0)
	g._read_vr()
	_ok(g.frets_down()[0] and (g.held_pad_bits() & red) != 0, "guitar: with one hand on it, that hand's trigger is the red fret")
	_trigger(hr, 0.0)
	g._read_vr()
	input._taps.clear()
	_trigger(hl, 1.0)
	g._read_vr()
	_ok(_tapped(input, 0) == [pick], "guitar: and the free hand's trigger strums, the pick's BUTTON6 on the player's own port (%s)" % str(_tapped(input, 0)))
	_trigger(hl, 0.0)
	g._read_vr()
	# The neck in the left hand: now the two have their parts.
	await _take_guitar(hl, g, "NeckL")
	await _wait(6)
	holders = g.holders()
	_ok(holders.size() == 2 and int(holders[0]["role"]) == ArcadeGuitarGrab.BODY and int(holders[1]["role"]) == ArcadeGuitarGrab.NECK and int(holders[1]["hand"]) == ArcadeGuitarGrab.LEFT,
		"guitar: the left hand takes the neck as the second hand, by the real pickup function (%d holders)" % holders.size())
	_ok(g.holding_controller() == _ctrl(hr) and g.neck_side() == ArcadeGuitarGrab.LEFT, "guitar: the neck is the left hand's")
	var settled := g.global_transform
	await _wait(10)
	_ok(g.global_position.distance_to(settled.origin) < 0.01 and g.global_basis.y.dot(settled.basis.y) > 0.995,
		"guitar: held by both hands it keeps still when they are where the two places say (%.3f m)" % g.global_position.distance_to(settled.origin))
	# The frets: the neck hand's trigger, X and Y, held as buttons are.
	input._taps.clear()
	_trigger(hl, 1.0)
	g._read_vr()
	_ok(g.frets_down() == [true, false, false] and g.held_pad_bits() == red and input._taps.is_empty(),
		"guitar: the neck hand's trigger is the red fret, held, and no strum (%s)" % str(g.frets_down()))
	_button(hl, &"ax_button", true)
	g._read_vr()
	_ok(g.frets_down() == [true, true, false] and g.held_pad_bits() == (red | green), "guitar: its X is the green fret")
	_button(hl, &"by_button", true)
	g._read_vr()
	_ok(g.frets_down() == [true, true, true] and g.held_pad_bits() == (red | green | blue), "guitar: its Y the blue, all three held together")
	_trigger(hl, 0.5)
	g._read_vr()
	_ok(g.frets_down()[0], "guitar: a trigger eased off only to half is still the red fret")
	_trigger(hl, 0.2)
	_button(hl, &"ax_button", false)
	_button(hl, &"by_button", false)
	g._read_vr()
	_ok(g.frets_down() == [false, false, false] and g.held_pad_bits() == 0, "guitar: let go of, they are all up")
	_trigger(hl, 0.5)
	g._read_vr()
	_ok(not g.frets_down()[0], "guitar: and a trigger only half squeezed from rest is not a fret")
	_trigger(hl, 0.0)
	g._read_vr()
	# The body hand's buttons are not frets when the neck has a hand.
	_button(hr, &"ax_button", true)
	_button(hr, &"by_button", true)
	g._read_vr()
	_ok(g.frets_down() == [false, false, false], "guitar: the body hand's X/A and Y/B are no frets while the neck has a hand")
	_button(hr, &"ax_button", false)
	_button(hr, &"by_button", false)
	# The strum: the body hand's trigger, once a squeeze.
	input._taps.clear()
	_trigger(hr, 1.0)
	g._read_vr()
	_ok(_tapped(input, 0) == [pick] and g.frets_down() == [false, false, false], "guitar: the body hand's trigger strums, once, and is no fret (%s)" % str(_tapped(input, 0)))
	input._taps.clear()
	g._read_vr()
	_ok(_tapped(input, 0).is_empty(), "guitar: a trigger that stays down strums once")
	_trigger(hr, 0.5)
	g._read_vr()
	_trigger(hr, 1.0)
	g._read_vr()
	_ok(_tapped(input, 0).is_empty(), "guitar: eased off only to half and squeezed again it strums nothing")
	_trigger(hr, 0.1)
	g._read_vr()
	_trigger(hr, 1.0)
	g._read_vr()
	_ok(_tapped(input, 0) == [pick], "guitar: let go and squeezed again it strums again")
	_trigger(hr, 0.0)
	g._read_vr()
	g._pick_t = 1.0
	g.strum(_ctrl(hr))
	_ok(g._pick_t == 0.0, "guitar: a strum flicks the pick bar")
	# The wail: the body hand's stick up, with a gap; the knob: its stick sideways, with a dead zone.
	_stick_push(hr, Vector2(0.0, 1.0))
	g._read_vr()
	_ok(g.wailing() and (g.held_pad_bits() & wail) != 0, "guitar: the body hand's stick pushed up is the wail, BUTTON7")
	_stick_push(hr, Vector2(0.0, 0.5))
	g._read_vr()
	_ok(g.wailing(), "guitar: and eased to half it is still the wail")
	_stick_push(hr, Vector2(0.0, 0.3))
	g._read_vr()
	_ok(not g.wailing() and (g.held_pad_bits() & wail) == 0, "guitar: and let go below that it is not")
	_stick_push(hr, Vector2(0.8, 0.0))
	g._read_vr()
	_ok(is_equal_approx(g.held_sticks()[0].x, 0.8) and g.held_sticks()[1] == Vector2.ZERO and not g.wailing(), "guitar: the stick sideways turns the effect knob, on the dial's axis (the left stick's X)")
	_stick_push(hr, Vector2(-0.6, 0.0))
	g._read_vr()
	_ok(is_equal_approx(g.held_sticks()[0].x, -0.6), "guitar: either way")
	_stick_push(hr, Vector2(0.1, 0.0))
	g._read_vr()
	_ok(g.held_sticks()[0] == Vector2.ZERO, "guitar: and a stick barely off centre turns nothing")
	_stick_push(hl, Vector2(0.0, 1.0))
	_stick_push(hr, Vector2.ZERO)
	g._read_vr()
	_ok(not g.wailing() and g.held_sticks()[0] == Vector2.ZERO, "guitar: the neck hand's stick does nothing while the body has a hand")
	_stick_push(hl, Vector2.ZERO)
	# The neck raised is the wail, the tilt switch a real guitar has.
	var up := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(35.0)), Vector3.ZERO)
	(hr["origin"] as XROrigin3D).global_transform = up * (hr["origin"] as XROrigin3D).global_transform
	(hl["origin"] as XROrigin3D).global_transform = up * (hl["origin"] as XROrigin3D).global_transform
	await _wait(8)
	g._read_vr()
	_ok(g.global_basis.y.y > ArcadeGuitar.TILT_ON and g.wailing() and (g.held_pad_bits() & wail) != 0,
		"guitar: the neck raised %.0f degrees is the wail" % rad_to_deg(asin(clampf(g.global_basis.y.y, -1.0, 1.0))))
	(hr["origin"] as XROrigin3D).global_transform = up.affine_inverse() * (hr["origin"] as XROrigin3D).global_transform
	(hl["origin"] as XROrigin3D).global_transform = up.affine_inverse() * (hl["origin"] as XROrigin3D).global_transform
	await _wait(8)
	g._read_vr()
	_ok(not g.wailing(), "guitar: and lowered again it is not")
	# What reaches the port, through the cabinet's own input.
	_trigger(hl, 1.0)
	_button(hl, &"by_button", true)
	_stick_push(hr, Vector2(0.0, 1.0))
	g._read_vr()
	var plain := {"btn": 0, "alx": 0, "aly": 0, "arx": 0, "ary": 0}
	var state := input._with_hands(plain, 0)
	_ok((int(state["btn"]) & (red | blue | wail)) == (red | blue | wail) and (int(state["btn"]) & green) == 0,
		"guitar: the cabinet's input adds what the guitar holds to its player's buttons: red, blue and the wail, not the green")
	var untouched := input._with_hands(plain, 1)
	_ok(int(untouched["btn"]) == 0, "guitar: and nothing to the other player's")
	_stick_push(hr, Vector2(0.9, 0.0))
	g._read_vr()
	state = input._with_hands(plain, 0)
	_ok(int(state["alx"]) > 20000 and int(state["arx"]) == 0, "guitar: the knob goes out as the left stick's X (%d)" % int(state["alx"]))
	# Let go of it, and everything it held goes up.
	g.drop()
	await _wait(4)
	_ok(g.frets_down() == [false, false, false] and not g.wailing() and g.held_pad_bits() == 0 and g.held_sticks()[0] == Vector2.ZERO and not ArcadeInput.held_by_hand(g),
		"guitar: let go of it holds nothing down any more")
	_trigger(hl, 0.0)
	_button(hl, &"by_button", false)
	_stick_push(hr, Vector2.ZERO)
	# The left-handed way about: the body in the left hand, the neck in the right, the frets under the RIGHT hand.
	var hl2 := _hand("left")
	var hr2 := _hand("right")
	await _wait(30)
	await _take_guitar(hl2, g, "BodyL")
	await _wait(40)
	await _take_guitar(hr2, g, "NeckR")
	await _wait(6)
	holders = g.holders()
	_ok(holders.size() == 2 and g.neck_side() == ArcadeGuitarGrab.RIGHT and int(holders[0]["hand"]) == ArcadeGuitarGrab.LEFT and int(holders[1]["role"]) == ArcadeGuitarGrab.NECK,
		"guitar: the left hand on the body and the right on the neck is the left-handed way about")
	_trigger(hr2, 1.0)
	_button(hr2, &"ax_button", true)
	g._read_vr()
	_ok(g.frets_down() == [true, true, false], "guitar: and then the frets are under the right hand")
	input._taps.clear()
	_trigger(hr2, 0.0)
	_button(hr2, &"ax_button", false)
	g._read_vr()
	_trigger(hl2, 1.0)
	g._read_vr()
	_ok(_tapped(input, 0) == [pick], "guitar: and the strum is the left hand's trigger")
	_trigger(hl2, 0.0)
	g._read_vr()
	# The hint ON the guitar (what the second hand's grab redeclared), not the rows the guitar would compute.
	var neck_row: Array = []
	var pick_row: Array = []
	for row: Array in (g.get_node("HeldHint") as HeldHint)._rows:
		if row[0] == &"fret_vr":
			neck_row = row[2]
		elif row[0] == &"pick_vr":
			pick_row = row[2]
	_ok(neck_row == ["quest_trigger_right_outline", "quest_button_a_outline", "quest_button_b_outline"], "guitar: and the hint names the right hand's trigger, A and B (%s)" % str(neck_row))
	_ok(pick_row == ["quest_trigger_left_outline"], "guitar: and the strum is the left hand's trigger on it (%s)" % str(pick_row))
	g.drop()
	await _wait(4)
	# A guitar in a hand is somebody at a cabinet that only shows its game (and one hanging in its bay is nobody).
	var used: Array[StringName] = []
	input.first_use.connect(func(kind: StringName) -> void: used.append(kind))
	sys.is_powered_on = false
	sys.attracting = true
	input._process(0.016)
	_ok(used.is_empty() and not input.engaged(), "guitar: guitars hanging in their bays leave a cabinet that is showing its game showing it (%s)" % str(used))
	var hr3 := _hand("right")
	await _take_guitar(hr3, other, "BodyR")
	input._process(0.016)
	_ok(used == [&"grab"], "guitar: a guitar in a hand starts the game a cabinet is only showing (%s)" % str(used))
	sys.attracting = false
	sys.is_powered_on = true
	other.drop()
	await _wait(2)


# --- prompts -------------------------------------------------------------------

## The ids of the rows a panel's hint has on show now (none while it is hidden).
func _on_show(panel: ArcadeControlModule) -> Array:
	var ids: Array = []
	var hint := panel.prompt_hint()
	if hint != null and hint.visible:
		for row: Array in hint._last_rows:
			ids.append(row[0])
	return ids


## The caption of the row `id` on show, "" when it is not.
func _caption_of(panel: ArcadeControlModule, id: StringName) -> String:
	var hint := panel.prompt_hint()
	if hint != null and hint.visible:
		for row: Array in hint._last_rows:
			if row[0] == id:
				return str(row[3])
	return ""


## Let go of whatever the hand has, one step (the trigger or the squeeze).
func _release(panel: ArcadeControlModule, h: Dictionary) -> void:
	_trigger(h, 0.0)
	_squeeze(h, 0.0)
	_step(panel, [h])


func _group_prompts() -> void:
	# The counts of what has been taught are the player's: put back what was there.
	var saved_uses := AppPrefs.hint_uses.duplicate()
	var saved_show := AppPrefs.show_hints
	AppPrefs.hint_uses = {}
	AppPrefs.show_hints = true
	# The words: a row for every kind of control, the glyph of the button that takes it, and every glyph there.
	var bad: Array = []
	for kind: StringName in [&"stick", &"wheel", &"dial", &"ball", &"lever", &"bars", &"lean", &"crank", &"slide", &"throttle"]:
		var rows := ArcadePrompts.control_rows(kind)
		if rows.is_empty():
			bad.append(kind)
		for row: Array in rows:
			if int(row[1]) != HeldHint.PLATFORM_VR or str(row[3]).is_empty():
				bad.append(row[0])
			for glyph: String in row[2]:
				for right in [true, false]:
					var path := "%s/%s%s" % [HeldHint.GLYPH_DIR, HeldHint.glyph_name(glyph, right), ConsolePadDiagram.GLYPH_EXT]
					if not ResourceLoader.exists(path):
						bad.append(path)
	_ok(bad.is_empty(), "prompts: every kind of control has words, for a headset, and every glyph they name exists for both hands (%s)" % str(bad))
	_ok(ArcadePrompts.control_rows(&"nonsense").is_empty(), "prompts: what is no control has no rows")
	_ok((ArcadePrompts.control_rows(&"stick")[0] as Array)[2] == ["quest_trigger_{side}_outline"] and (ArcadePrompts.control_rows(&"bars")[0] as Array)[2] == ["quest_grip_{side}_outline"]
			and (ArcadePrompts.control_rows(&"lean")[0] as Array)[2] == ["quest_grip_{side}_outline"] and (ArcadePrompts.control_rows(&"crank")[0] as Array)[2] == ["quest_trigger_{side}_outline"],
		"prompts: a stick and a crank are taken by the trigger, bars by the squeeze")
	var ids := func(rows: Array) -> Array:
		var out: Array = []
		for row: Array in rows:
			out.append(row[0])
		return out
	_ok(ids.call(ArcadePrompts.control_rows(&"bars")) == [&"ap_bars_vr", &"ap_bars_two_vr", &"ap_bars_tip_vr"] and ids.call(ArcadePrompts.control_rows(&"lean")) == [&"ap_lean_vr"],
		"prompts: a bicycle's bars are turned, held in two hands and tipped; a motorbike's only leaned")
	# The buttons of a game, in the core's words when it gave them, else by number.
	var six: Array = []
	for n in range(1, 7):
		six.append({"n": n, "label": ""})
	var named: Array = [{"n": 1, "label": "Punch"}, {"n": 2, "label": "Kick"}]
	var five: Array = []
	for n in range(1, 6):
		five.append({"n": n, "label": "Move %d" % n})
	_ok(ArcadePrompts.button_rows(six)[0][3] == "Press the buttons with a fingertip: buttons 1 to 6", "prompts: six buttons with no names are buttons 1 to 6 (%s)" % str(ArcadePrompts.button_rows(six)))
	_ok(ArcadePrompts.button_rows(named)[0][3] == "Press the buttons with a fingertip: 1 Punch, 2 Kick", "prompts: and with the core's words they are named")
	_ok(ArcadePrompts.button_rows(five)[0][3].ends_with("buttons 1 to 5"), "prompts: more than four, named or not, are numbered (%s)" % str(ArcadePrompts.button_rows(five)[0][3]))
	_ok(ArcadePrompts.button_rows([{"n": 3, "label": ""}])[0][3].ends_with("button 3") and ArcadePrompts.button_rows([{"n": 1, "label": "Light\nPunch"}, {"n": 2, "label": ""}])[0][3].ends_with("1 Light Punch, 2")
			and ArcadePrompts.button_rows([]).is_empty(), "prompts: one button is a button, a name on two lines is one line, a panel with none says nothing")
	_ok(ArcadePrompts.is_game_row(&"ap_buttons_vr") and ArcadePrompts.is_game_row(&"ap_buttons_map2") and ArcadePrompts.is_game_row(&"ap_pedals_vr") and ArcadePrompts.is_game_row(&"ap_buttons_pc2")
			and not ArcadePrompts.is_game_row(&"ap_stick_vr") and not ArcadePrompts.is_game_row(&"ap_attach_vr") and not ArcadePrompts.is_game_row(&"ap_move_pc"),
		"prompts: the buttons and the pedals say what THIS game has, the rest are verbs")
	# Attaching with a controller: the player's own map says which of its buttons is start, the coin and each of the game's.
	var stick_map: Dictionary = ControllerBindings.DEFAULT_STICK_MAP
	var rows_vr := ArcadePrompts.attach_rows_vr(0, true, six.slice(0, 2), ControllerBindings.DEFAULT_BUTTON_MAP, stick_map)
	_ok(ids.call(rows_vr) == [&"ap_attach_vr", &"ap_buttons_map"] and str(rows_vr[0][3]) == "This controller plays player 1 (Left stick moves; Right Stick Button: start; Left Stick Button: coin)"
			and str(rows_vr[1][3]) == "1: Right B, 2: Right A", "prompts: the default map plays button 1 with Right B and 2 with Right A (%s)" % str(rows_vr))
	var moved: Dictionary = ControllerBindings.DEFAULT_BUTTON_MAP.duplicate()
	moved["right_grip"] = ControllerBindings.JOYPAD_START
	moved["right_primary_click"] = -1
	moved["left_by_button"] = ControllerBindings.JOYPAD_B
	var rows_moved := ArcadePrompts.attach_rows_vr(1, false, six.slice(0, 1), moved, {"stick_left": "right", "stick_right": "right"})
	_ok(str(rows_moved[0][3]) == "This controller plays player 2 (Right Grip: start; Left Stick Button: coin)" and str(rows_moved[1][3]) == "1: Left Y or Right B",
		"prompts: a map of the player's own says its own: start on the grip, button 1 on two inputs, a panel with no stick says none (%s)" % str(rows_moved))
	_ok(str(ArcadePrompts.attach_rows_vr(0, true, [], ControllerBindings.DEFAULT_BUTTON_MAP, {"stick_left": "dpad", "stick_right": "left"})[0][3]).contains("Left stick or Right stick moves")
			and not str(ArcadePrompts.attach_rows_vr(0, true, [], ControllerBindings.DEFAULT_BUTTON_MAP, {"stick_left": "right", "stick_right": "right"})[0][3]).contains("moves"),
		"prompts: a stick that is the D-pad moves it, either stick the player pointed at it, none the player did not")
	var many: Array = []
	for n in range(1, 8):
		many.append({"n": n, "label": ""})
	_ok(ids.call(ArcadePrompts.attach_rows_vr(0, true, many, ControllerBindings.DEFAULT_BUTTON_MAP, stick_map)) == [&"ap_attach_vr", &"ap_buttons_map", &"ap_buttons_map2", &"ap_buttons_map3"],
		"prompts: seven buttons are three to a row, three rows")
	# And with the keyboard: the keys of the cabinet's own map.
	var rows_pc := ArcadePrompts.attach_rows_desktop(0, true, six, "arcade")
	var key := func(action: String) -> String:
		return DesktopBindings.display_name_for_system(action, "arcade")
	_ok(ids.call(rows_pc) == [&"ap_move_pc", &"ap_buttons_pc", &"ap_buttons_pc2", &"ap_start_pc"]
			and str(rows_pc[3][3]) == "%s: start, %s: coin (player 1)" % [key.call("RETRO_JOYPAD_START"), key.call("RETRO_JOYPAD_SELECT")]
			and str(rows_pc[0][3]) == "%s %s %s %s: move" % [key.call("RETRO_JOYPAD_UP"), key.call("RETRO_JOYPAD_LEFT"), key.call("RETRO_JOYPAD_DOWN"), key.call("RETRO_JOYPAD_RIGHT")]
			and str(rows_pc[1][3]) == "%s: 1, %s: 2, %s: 3" % [key.call("RETRO_JOYPAD_B"), key.call("RETRO_JOYPAD_A"), key.call("RETRO_JOYPAD_Y")]
			and str(rows_pc[2][3]) == "%s: 4, %s: 5, %s: 6" % [key.call("RETRO_JOYPAD_X"), key.call("RETRO_JOYPAD_L"), key.call("RETRO_JOYPAD_R")],
		"prompts: the keyboard's rows name the keys: the buttons in MAME's order, three to a row, then start and the coin (%s)" % str(rows_pc))
	if not DesktopBindings.has_system_override("arcade"):
		_ok(str(rows_pc[1][3]) == "Ctrl: 1, Alt: 2, Space: 3" and str(rows_pc[3][3]) == "1: start, 5: coin (player 1)",
			"prompts: a cabinet with no map of its own says MAME's layout: Ctrl Alt Space, 1 and 5 (%s)" % str(rows_pc))
	_ok(ids.call(ArcadePrompts.attach_rows_desktop(0, false, [], "arcade")) == [&"ap_start_pc"], "prompts: a panel with no stick and no buttons says only start and the coin")
	# A bicycle's bars, taken by a squeeze: what they are for, three lines, in the glyph of the hand that took them.
	var r := await _rig("propcycl")
	var panel: ArcadeControlModule = r["panel"]
	var hands: ArcadePanelHands = panel.hands()
	var hr := _hand("right")
	var hl := _hand("left")
	var grip_r := (panel.find_child("BarGripR", true, false) as Node3D).global_position
	var grip_l := (panel.find_child("BarGripL", true, false) as Node3D).global_position
	_ok(_on_show(panel).is_empty() and panel.prompt_hint() == null, "prompts: a panel nobody has touched says nothing")
	_tip_at(hr, grip_r)
	_squeeze(hr, 1.0)
	_step(panel, [hr, hl])
	_ok(hands.holds(&"bars") and _on_show(panel) == [&"ap_bars_vr", &"ap_bars_two_vr", &"ap_bars_tip_vr"] and panel.prompt_hint()._last_right,
		"prompts: taking a bicycle's bars says what they are for, in the right hand's glyph (%s)" % str(_on_show(panel)))
	_ok(int(AppPrefs.hint_uses.get("ap_bars_vr", 0)) == 1 and int(AppPrefs.hint_uses.get("ap_bars_tip_vr", 0)) == 1, "prompts: and counts one use of each (%s)" % str(AppPrefs.hint_uses))
	# A second hand on the other grip is the same take of the bars: not told again, not counted again.
	_tip_at(hl, grip_l)
	_squeeze(hl, 1.0)
	_step(panel, [hr, hl])
	_ok(hands.holds(&"bars") and int(AppPrefs.hint_uses.get("ap_bars_vr", 0)) == 1, "prompts: a second hand joining the bars counts nothing more (%s)" % str(AppPrefs.hint_uses))
	_release(panel, hr)
	_release(panel, hl)
	# The left hand alone takes them with its own glyphs.
	_tip_at(hl, grip_l)
	_squeeze(hl, 1.0)
	_step(panel, [hl])
	_ok(hands.holds(&"bars") and not panel.prompt_hint()._last_right, "prompts: taken by the left hand the glyphs are the left's")
	_release(panel, hl)
	# The crank is a pedal: its line only, and no buttons.
	var pedal := (panel.find_child("CrankPedalR", true, false) as Node3D).global_position
	_tip_at(hr, pedal + panel.global_transform.basis.x * 0.04)
	_trigger(hr, 1.0)
	_step(panel, [hr])
	_ok(hands.holds(&"crank") and _on_show(panel) == [&"ap_crank_vr"], "prompts: taking the crank says to turn it forward, and nothing of buttons (%s)" % str(_on_show(panel)))
	_release(panel, hr)
	# A fighting game's stick: the stick, and the game's buttons the first time.
	var r2 := await _rig("sf2", 6, true)
	var panel2: ArcadeControlModule = r2["panel"]
	var hands2: ArcadePanelHands = panel2.hands()
	var h2 := _hand("right")
	var buttons := panel2.shown_buttons()
	_ok(buttons.size() == 6, "prompts: the panel of Street Fighter II shows six buttons (%d)" % buttons.size())
	_tip_at(h2, _ball_at(panel2))
	_trigger(h2, 1.0)
	_step(panel2, [h2])
	_ok(hands2.holds(&"stick") and _on_show(panel2) == [&"ap_stick_vr", &"ap_buttons_vr"] and _caption_of(panel2, &"ap_buttons_vr") == str(ArcadePrompts.button_rows(buttons)[0][3]),
		"prompts: taking the stick says what it does and which buttons the game has (%s)" % str(_on_show(panel2)))
	_ok(int(AppPrefs.hint_uses.get("ap_stick_vr", 0)) == 1 and not AppPrefs.hint_uses.has("ap_buttons_vr"), "prompts: the stick's line is counted as taught, the game's buttons are not (%s)" % str(AppPrefs.hint_uses))
	var stick_grab: ArcadePanelHands.ControlGrab = null
	for g in hands2.grabs():
		if g.kind == &"stick":
			stick_grab = g
	var over: Vector3 = stick_grab.handle() + Vector3.UP * ArcadeControlModule.PROMPT_LIFT
	_ok(panel2.prompt_hint()._pinned and panel2.prompt_hint()._anchor().distance_to(over) < 0.01,
		"prompts: the hint floats %d cm over the stick that was taken (%s against %s)" % [int(ArcadeControlModule.PROMPT_LIFT * 100.0), str(panel2.prompt_hint()._anchor()), str(over)])
	_release(panel2, h2)
	# The same game's buttons are not said at every take of its stick.
	_trigger(h2, 1.0)
	_step(panel2, [h2])
	_ok(_on_show(panel2) == [&"ap_stick_vr"], "prompts: the second take says the stick only (%s)" % str(_on_show(panel2)))
	_release(panel2, h2)
	# A verb is learned by doing it: three takes, and it is not said.
	_trigger(h2, 1.0)
	_step(panel2, [h2])
	_release(panel2, h2)
	_ok(int(AppPrefs.hint_uses.get("ap_stick_vr", 0)) == HeldHint.LEARNED_AFTER, "prompts: three takes teach the stick (%s)" % str(AppPrefs.hint_uses))
	_trigger(h2, 1.0)
	_step(panel2, [h2])
	_ok(hands2.holds(&"stick") and _on_show(panel2).is_empty(), "prompts: and the fourth is silent (%s)" % str(_on_show(panel2)))
	_release(panel2, h2)
	# Another game in the panel: its buttons are said afresh (the same row, other words), the stick's line not.
	r2["model"].apply_game_profile(P.for_romset("mslug"))
	await _wait(2)
	_ok(panel2.shown_buttons().size() == 4, "prompts: Metal Slug shows four buttons against Street Fighter II's six (%d)" % panel2.shown_buttons().size())
	_trigger(h2, 1.0)
	_step(panel2, [h2])
	_ok(_on_show(panel2) == [&"ap_buttons_vr"] and _caption_of(panel2, &"ap_buttons_vr").ends_with("buttons 1 to 4"), "prompts: a game with other buttons is told its own once the stick is taught (%s)" % str(_on_show(panel2)))
	_release(panel2, h2)
	# A game with none has nothing to say of buttons, and the stick has been taught.
	r2["model"].apply_game_profile(P.for_romset("pacman"))
	await _wait(2)
	_trigger(h2, 1.0)
	_step(panel2, [h2])
	_ok(hands2.holds(&"stick") and panel2.shown_buttons().is_empty() and _on_show(panel2).is_empty(), "prompts: a game with no buttons says nothing of any (%s)" % str(_on_show(panel2)))
	_release(panel2, h2)
	# Hints off: nothing is said.
	AppPrefs.show_hints = false
	AppPrefs.hint_uses = {}
	_trigger(h2, 1.0)
	_step(panel2, [h2])
	_ok(hands2.holds(&"stick") and _on_show(panel2).is_empty(), "prompts: with the hints switched off a control taken says nothing")
	_release(panel2, h2)
	AppPrefs.show_hints = true
	# A racer's wheel and its pedals.
	var r3 := await _rig("daytona", 6, true)
	var panel3: ArcadeControlModule = r3["panel"]
	var hands3: ArcadePanelHands = panel3.hands()
	var h3 := _hand("right")
	var rim := (panel3.find_child("WheelPivot", true, false) as Node3D)
	var mount := rim.get_parent() as Node3D
	var wheel_rim := rim.find_child("WheelRim", true, false) as MeshInstance3D
	var radius := (wheel_rim.mesh as TorusMesh).outer_radius - 0.014
	_tip_at(h3, mount.global_transform * Vector3(0, 0, -radius))
	_trigger(h3, 1.0)
	_step(panel3, [h3])
	var wheel_ids := _on_show(panel3)
	_ok(hands3.holds(&"wheel") and wheel_ids.has(&"ap_wheel_vr") and wheel_ids.has(&"ap_pedals_vr"), "prompts: a driving cockpit's wheel says to turn it and that there are pedals (%s)" % str(wheel_ids))
	_release(panel3, h3)
	# A motorbike's grip: leaned, not turned.
	var r4 := await _rig("hangon")
	var panel4: ArcadeControlModule = r4["panel"]
	var h4 := _hand("right")
	_tip_at(h4, (panel4.find_child("BarGripR", true, false) as Node3D).global_position)
	_squeeze(h4, 1.0)
	_step(panel4, [h4])
	_ok(panel4.hands().holds(&"bars") and _on_show(panel4).has(&"ap_lean_vr") and not _on_show(panel4).has(&"ap_bars_tip_vr"), "prompts: a motorbike's bars are leaned, not tipped (%s)" % str(_on_show(panel4)))
	_release(panel4, h4)
	# Attaching with the keyboard (a headless run has no headset): the keys of this cabinet, said at once.
	AppPrefs.hint_uses = {}
	r2["model"].apply_game_profile(P.for_romset("sf2"))
	await _wait(2)
	panel2.set_attached(true)
	await _wait(2)
	var attach_ids := _on_show(panel2)
	_ok(attach_ids.has(&"ap_move_pc") and attach_ids.has(&"ap_buttons_pc") and attach_ids.has(&"ap_start_pc") and panel2.prompt_hint()._desktop_rows and not panel2.prompt_hint()._pinned,
		"prompts: attaching with the keyboard says the keys: move, the buttons, start and the coin (%s)" % str(attach_ids))
	_ok(int(AppPrefs.hint_uses.get("ap_move_pc", 0)) == 1 and not AppPrefs.hint_uses.has("ap_buttons_pc"), "prompts: the move line is taught, the game's keys are not counted (%s)" % str(AppPrefs.hint_uses))
	_ok(_caption_of(panel2, &"ap_start_pc") == "%s: start, %s: coin (player 1)" % [DesktopBindings.display_name_for_system("RETRO_JOYPAD_START", "arcade"), DesktopBindings.display_name_for_system("RETRO_JOYPAD_SELECT", "arcade")],
		"prompts: and they are the keys of the cabinet's own map (%s)" % _caption_of(panel2, &"ap_start_pc"))
	panel2.set_attached(false)
	# With a headset's controller the rows are the controller's, by the player's own map.
	AppPrefs.hint_uses = {}
	panel2.prompt_attached(true, ControllerBindings.DEFAULT_BUTTON_MAP, ControllerBindings.DEFAULT_STICK_MAP, "arcade")
	_ok(_on_show(panel2) == [&"ap_attach_vr", &"ap_buttons_map", &"ap_buttons_map2"] and not panel2.prompt_hint()._desktop_rows
			and _caption_of(panel2, &"ap_buttons_map") == "1: Right B, 2: Right A, 3: Left Y" and _caption_of(panel2, &"ap_buttons_map2") == "4: Left X, 5: Left Grip, 6: Right Grip",
		"prompts: attaching with a controller says its own buttons: 1 to 3 on one row, 4 to 6 on the next (%s)" % str(_on_show(panel2)))
	AppPrefs.hint_uses = saved_uses
	AppPrefs.show_hints = saved_show
