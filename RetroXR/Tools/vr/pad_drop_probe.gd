extends Node3D

## "Sometimes a controller will not drop and just floats in the air."
##
## Drives the REAL release path on a REAL RetroController, from rest, over and
## over, and asks the only question that matters: did it fall? A hand is faked
## (a Node3D with drop_object/_pick_up_object, the two methods XRToolsPickable
## actually calls back into), so no headset is needed — CLAUDE.md is blunt that
## no headless suite covers grabs, which is why this is a probe.
##
## The reported case is a pad picked up OFF THE FLOOR, i.e. one that has gone to
## sleep, so each trial settles the body first and re-checks that it slept.
##
##   "$godot" --headless --path RetroXR res://Tools/vr/pad_drop_probe.tscn
##      [-- --trials=N]

const PAD_SCENE := preload("res://Scenes/Objects/controllers/retro_controller.tscn")
## How far it must fall to count as dropped, and how long it is given.
const FELL_BY := 0.02
const FALL_FRAMES := 30

var _pad: RetroController = null
var _hand: Node3D = null
var _hand2: Node3D = null
var _trials := 60
var _stuck := 0
var _slept := 0


## The two methods XRToolsPickable calls back into on whatever is holding it.
class FakeHand extends Node3D:
	## Read by XRToolsPickable.pick_up() to choose the ranged vs near grab path.
	var picked_up_ranged := false
	var held: Node3D = null

	func drop_object() -> void:
		if is_instance_valid(held):
			# Zero velocity: a pad let go by a still hand, which is the case the
			# gravity nudge in pickable.let_go() exists for.
			held.let_go(self, Vector3.ZERO, Vector3.ZERO)
			held = null

	func _pick_up_object(o: Node3D) -> void:
		held = o
		o.pick_up(self)


func _ready() -> void:
	get_tree().create_timer(240.0).timeout.connect(func() -> void:
		print("[probe] GAVE UP")
		get_tree().quit(1))
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--trials="):
			_trials = int(arg.substr(9))
	_build_room()
	_pad = PAD_SCENE.instantiate() as RetroController
	add_child(_pad)
	_hand = FakeHand.new()
	add_child(_hand)
	_hand2 = FakeHand.new()
	add_child(_hand2)
	await get_tree().process_frame
	print("[probe] %s, freeze_mode=%d linear_damp=%.1f can_sleep=%s"
			% [_pad.name, _pad.freeze_mode, _pad.linear_damp, _pad.can_sleep])
	await _run()
	print("[probe] %d releases did NOT fall in total  (%d began asleep)" % [_stuck, _slept])
	print("[probe] done")
	get_tree().quit(1 if _stuck > 0 else 0)


func _build_room() -> void:
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6, 0.2, 6)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position = Vector3(0, -0.1, 0)
	add_child(floor_body)


func _run() -> void:
	# One scenario per way a pad really leaves the hands. A single-hand release
	# is the easy case; the pad allows a SECOND hand (second_hand_grab = SECOND),
	# and its toggle-hold re-grabs itself on any release that is not the combo,
	# so those are the interesting ones.
	await _scenario("one hand", func() -> void: await _release_one())
	await _scenario("two hands, second released first", func() -> void: await _release_two(false))
	await _scenario("two hands, FIRST released first", func() -> void: await _release_two(true))
	await _scenario("released while a re-hold is pending", func() -> void: await _release_during_rehold())
	await _scenario("released mid-lerp, before it reaches the hand", func() -> void: await _release_early())
	# The instrument itself: HeldObjectPhysics is supposed to photograph a pad
	# left hanging. An alarm that cannot go off is not an alarm, so stick one on
	# purpose and check the warning appears (grep the run for "[stuck]").
	await _sabotage()


func _scenario(label: String, body: Callable) -> void:
	var stuck_before := _stuck
	for trial in _trials:
		await _settle_on_floor()
		await body.call()
		await _watch_fall(label, trial)
	var failed := _stuck - stuck_before
	print("[probe] %-46s %s (%d/%d)"
			% [label, "FELL" if failed == 0 else "STUCK", _trials - failed, _trials])


func _settle_on_floor() -> void:
	_pad.global_position = Vector3(0, 0.4, 0)
	_pad.freeze = false
	_pad.linear_velocity = Vector3.ZERO
	_pad.angular_velocity = Vector3.ZERO
	for i in 120:
		await get_tree().physics_frame
		if _pad.sleeping:
			break
	if _pad.sleeping:
		_slept += 1


func _lift(hand: Node3D) -> void:
	hand.global_position = _pad.global_position
	hand.call("_pick_up_object", _pad)
	for i in 4:
		await get_tree().physics_frame
	hand.global_position = Vector3(0, 1.2, 0)
	for i in 20:
		await get_tree().physics_frame


var _fall_from := 0.0


func _mark() -> void:
	_fall_from = _pad.global_position.y


func _watch_fall(label: String, trial: int) -> void:
	for i in FALL_FRAMES:
		await get_tree().physics_frame
	var fell := _fall_from - _pad.global_position.y
	if fell < FELL_BY:
		_stuck += 1
		if _stuck <= 6:
			print("[probe]   STUCK (%s, trial %d): fell %.4f m | freeze=%s restore_freeze=%s "
					% [label, trial, fell, _pad.freeze, _pad.restore_freeze]
					+ "sleeping=%s gravity_scale=%.2f picked_up=%s"
					% [_pad.sleeping, _pad.gravity_scale, _pad.is_picked_up()])
	# Whatever happened, hand the pad back to a known state for the next trial.
	_pad._allow_drop = true
	_hand.call("drop_object")
	_hand2.call("drop_object")


func _release_one() -> void:
	await _lift(_hand)
	_mark()
	_pad._allow_drop = true
	_hand.call("drop_object")


func _release_two(first_first: bool) -> void:
	await _lift(_hand)
	_hand2.global_position = _pad.global_position
	_hand2.call("_pick_up_object", _pad)
	for i in 4:
		await get_tree().physics_frame
	_mark()
	if first_first:
		_pad._allow_drop = true
		_hand.call("drop_object")
		for i in 2:
			await get_tree().physics_frame
		_pad._allow_drop = true
		_hand2.call("drop_object")
	else:
		_pad._allow_drop = true
		_hand2.call("drop_object")
		for i in 2:
			await get_tree().physics_frame
		_pad._allow_drop = true
		_hand.call("drop_object")


## A plain release re-grabs one frame later (call_deferred("_rehold")). Let that
## be in flight and then really drop it, the way a combo landing on the heels of
## a grip release would.
func _release_during_rehold() -> void:
	await _lift(_hand)
	_mark()
	_pad._allow_drop = false
	_hand.call("drop_object")
	_pad._allow_drop = true
	_pad.drop()


## Let go before the lerp has carried it to the hand.
func _release_early() -> void:
	_hand.global_position = _pad.global_position
	_hand.call("_pick_up_object", _pad)
	await get_tree().physics_frame
	_hand.global_position = Vector3(0, 1.2, 0)
	await get_tree().physics_frame
	_mark()
	_pad._allow_drop = true
	_hand.call("drop_object")


func _sabotage() -> void:
	await _settle_on_floor()
	await _lift(_hand)
	_pad._allow_drop = true
	_hand.call("drop_object")
	# Exactly the reported end state: released, then frozen with nobody holding
	# it, hanging where it was let go.
	_pad.freeze = true
	print("[probe] sabotage: pad frozen after release, expecting a [stuck] warning")
	await get_tree().create_timer(1.4).timeout
	_pad.freeze = false
