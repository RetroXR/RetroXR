## Seat self-tests — somewhere to sit: the pose arithmetic, sitting and getting up through a rig,
## the press that does it, and the seats being saved and spawned. Headless, no headset.
##
##     "$godot" --headless --path RetroXR res://Tests/seat_tests.tscn
##     "$godot" --headless --path RetroXR res://Tests/seat_tests.tscn -- --only=sit
##
## What a headless run cannot show is how a seat LOOKS or what a headset feels like seated
## (a headset, a Quest and a real person on a real chair are OWED): none of this is that proof.
##
## Groups:
##   pose/     the arithmetic: the camera lands on the eye point, a stand-up puts the camera over the floor point
##   sit/      a rig sits and stands: eyes, heading, locomotion held, the body held, one seat at a time
##   press/    the cushion's pointer event sits and stands; the body of the seat does not
##   family/   every seat scene has the script, its markers, a cushion and an eye height that is a sitting one
##   save/     a seat is a plain scene saved by its token and spawned by it
extends Node

const FAMILIES: Array[String] = ["seat_racing", "seat_stool", "seat_chair", "seat_cushion", "seat_sofa", "seat_bed"]

var _checks := 0
var _failed := 0
var _only := ""
var _rig: Node3D = null
var _origin: XROrigin3D = null
var _camera: XRCamera3D = null
var _body: XRToolsPlayerBody = null
var _loco: LocomotionManager = null


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7)
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("[seat] TIMED OUT")
		get_tree().quit(1))
	await _run()
	print("[seat] %d checks, %d failed" % [_checks, _failed])
	print("[seat] RESULT=%s" % ("PASS" if _failed == 0 else "FAIL"))
	get_tree().quit(1 if _failed > 0 else 0)


func _ok(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
	print("[seat] %s  %s" % ["PASS" if ok else "FAIL", what])


func _want(group: String) -> bool:
	return _only.is_empty() or _only == group


func _near(a: float, b: float, eps: float = 1e-4) -> bool:
	return absf(a - b) <= eps


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _run() -> void:
	if _want("pose"):
		_group_pose()
	if _want("sit"):
		await _group_sit()
	if _want("press"):
		await _group_press()
	if _want("family"):
		await _group_family()
	if _want("save"):
		await _group_save()


## A stand-in for the player: an origin offset and turned in the room, a head 1.6 m up and a little
## off its middle, turned and tilted, a body, and the locomotion manager.
func _make_rig() -> void:
	# Built detached with every node OWNED (the xr-tools finders only see owned nodes, as in a
	# scene file), then put in the tree.
	_rig = Node3D.new()
	_origin = XROrigin3D.new()
	_origin.transform = Transform3D(Basis(Vector3.UP, 0.6), Vector3(-1.0, 0.0, 4.0))
	_rig.add_child(_origin)
	_origin.owner = _rig
	_camera = XRCamera3D.new()
	_camera.transform = Transform3D(Basis.from_euler(Vector3(-0.3, 0.9, 0.05)), Vector3(0.2, 1.6, -0.1))
	_origin.add_child(_camera)
	_camera.owner = _rig
	_body = XRToolsPlayerBody.new()
	_origin.add_child(_body)
	_body.owner = _rig
	_loco = LocomotionManager.new()
	_loco.name = "LocomotionManager"
	_rig.add_child(_loco)
	add_child(_rig)
	_camera.current = true


func _drop_rig() -> void:
	Seat.current = null
	if _rig != null:
		_rig.queue_free()
	_rig = null


func _seat(id: String, at: Vector3, yaw: float) -> Seat:
	var scene := load("res://Scenes/Objects/furniture/%s.tscn" % id) as PackedScene
	var seat := scene.instantiate() as Seat
	seat.freeze = true
	seat.transform = Transform3D(Basis(Vector3.UP, yaw), at)
	add_child(seat)
	return seat


# --- pose ----------------------------------------------------------------------

func _group_pose() -> void:
	for a in [0.0, 0.7, -2.5, 3.0]:
		_ok(_near(Seat.yaw_of(Basis(Vector3.UP, a)), a), "pose: the heading of a basis turned %.1f rad is %.1f" % [a, a])
	var origin := Transform3D(Basis(Vector3.UP, 0.6), Vector3(-1.0, 0.0, 4.0))
	var camera_local := Transform3D(Basis.from_euler(Vector3(-0.3, 0.9, 0.05)), Vector3(0.2, 1.6, -0.1))
	var camera := origin * camera_local
	var eye := Transform3D(Basis(Vector3.UP, -1.2), Vector3(5.0, 1.2, -3.0))
	var floor_y := 0.4
	var moved := Seat.origin_for_eye(origin, camera, eye, floor_y)
	var cam_after := moved * camera_local
	_ok(_near(cam_after.origin.x, eye.origin.x) and _near(cam_after.origin.z, eye.origin.z), "pose: the head lands over the eye point (%s)" % cam_after.origin)
	_ok(_near(moved.origin.y, floor_y) and _near(cam_after.origin.y - floor_y, camera_local.origin.y),
		"pose: on the seat's floor, the head as high above it as the player is")
	_ok(_near(Seat.yaw_of(cam_after.basis), Seat.yaw_of(eye.basis), 1e-3), "pose: facing the way the seat faces")
	_ok(_near((-cam_after.basis.z).y, (-camera.basis.z).y, 1e-4), "pose: the head's own pitch is the player's, not the seat's")
	var in_place := Seat.origin_for_eye(origin, camera, camera, origin.origin.y)
	_ok(in_place.origin.distance_to(origin.origin) < 1e-4 and in_place.basis.is_equal_approx(origin.basis),
		"pose: a head already at the eye point, facing right, on its floor, moves nothing")
	var floor_at := Vector3(2.0, 0.25, 1.0)
	var up := Seat.origin_for_stand(moved, cam_after, floor_at)
	var cam_up := up * camera_local
	_ok(_near(cam_up.origin.x, floor_at.x) and _near(cam_up.origin.z, floor_at.z), "pose: standing puts the head over the floor point")
	_ok(_near(up.origin.y, floor_at.y), "pose: and the origin on that floor")
	_ok(_near(cam_up.origin.y - up.origin.y, camera_local.origin.y), "pose: the head is as high above that floor as the player is tall")
	_ok(up.basis.is_equal_approx(moved.basis), "pose: standing leaves the heading alone")


# --- sit -----------------------------------------------------------------------

func _group_sit() -> void:
	_make_rig()
	await _frames(2)
	_body.enabled = true
	var seat := _seat("seat_chair", Vector3(3.0, 0.0, 2.0), 1.5707963)
	await _frames(2)
	var eye := seat.eye_transform()
	_ok(not seat.is_occupied() and Seat.current == null, "sit: nobody is in a seat to begin with")
	var seen: Array = []
	seat.seated_changed.connect(func(on: bool) -> void: seen.append(on))
	_ok(seat.sit() and seat.is_occupied() and Seat.current == seat, "sit: sitting takes the seat")
	await _frames(2)
	eye = seat.eye_transform()
	_ok(_camera.global_position.distance_to(eye.origin) < 0.02, "sit: the head is at the seat's eyes (%s vs %s)" % [_camera.global_position, eye.origin])
	_ok(_near(_camera.position.y, eye.origin.y - seat.global_position.y), "sit: on the desktop the camera's own height is the seat's eye height")
	_ok(_near(Seat.yaw_of(_camera.global_transform.basis), Seat.yaw_of(eye.basis), 1e-3), "sit: looking the way the seat faces")
	_ok(_loco.is_blocked(LocomotionManager.CHANNEL_ALL) and _loco.is_blocked(LocomotionManager.CHANNEL_DESKTOP_MOVE),
		"sit: walking, turning and teleporting are held back")
	_ok(_body.enabled, "sit: the body stays ON: the movement providers (mouse-look, mouse capture) run inside its physics")
	var pinned := _origin.global_position
	_origin.global_position += Vector3(0.3, 0.2, -0.4)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_ok(_origin.global_position.distance_to(pinned) < 1e-3, "sit: whatever moves the origin is undone: the body is held")
	var look_before := _camera.global_transform.basis
	_origin.rotate_y(0.5)
	await get_tree().physics_frame
	_ok(not _camera.global_transform.basis.is_equal_approx(look_before) and _origin.global_position.distance_to(pinned) < 1e-3,
		"sit: the head turns freely (mouse-look rotates the origin) and the pin leaves the turn alone")
	_ok(seen == [true], "sit: and the seat says so")
	var other := _seat("seat_stool", Vector3(-3.0, 0.0, 2.0), 0.0)
	await _frames(2)
	other.sit()
	_ok(Seat.current == other and not seat.is_occupied(), "sit: sitting on another seat gets up from the first")
	_ok(seen == [true, false], "sit: and the first says it was left")
	other.stand()
	seat.sit()
	_origin.global_position += Vector3(0.0, 0.0, 0.0)
	seat.global_position += Vector3(0.0, 0.0, 1.0)         # moved while sat on
	var stand_at := seat.stand_point()
	seat.stand()
	await _frames(2)
	_ok(Seat.current == null and not seat.is_occupied(), "sit: getting up leaves no seat")
	_ok(_camera.global_position.x - stand_at.x < 1e-3 and _camera.global_position.z - stand_at.z < 1e-3,
		"sit: the player is put where the seat's StandPoint is NOW, not where it was")
	_ok(not _loco.is_blocked(LocomotionManager.CHANNEL_ALL) and not _loco.is_blocked(LocomotionManager.CHANNEL_DESKTOP_MOVE),
		"sit: locomotion is let go")
	_ok(_body.enabled and _near(_camera.position.y, 1.6), "sit: the camera is as tall as it was")
	seat.stand()
	_ok(Seat.current == null, "sit: standing with nobody sat is harmless")
	# Picked up, put away, the room changed: each lets the player go.
	seat.sit()
	seat.picked_up.emit(seat)
	_ok(Seat.current == null and _body.enabled and _near(_camera.position.y, 1.6), "sit: picking the seat up gets the player off it")
	seat.sit()
	seat.free()
	await _frames(2)
	_ok(Seat.current == null and _body.enabled and not _loco.is_blocked(LocomotionManager.CHANNEL_ALL) and _near(_camera.position.y, 1.6),
		"sit: a seat taken out of the room lets go of the player, body and all")
	var room := _seat("seat_cushion", Vector3(0.0, 0.0, 0.0), 0.0)
	await _frames(2)
	room.sit()
	Seat.release_all()
	_ok(Seat.current == null and not _loco.is_blocked(LocomotionManager.CHANNEL_ALL),
		"sit: leaving the room drops the claim and the locomotion block")
	_ok(_body.enabled and _near(_camera.position.y, 1.6), "sit: ...the body is the rig's (PlayerRig.leave_world / enter_world) and the camera is as tall as it was")
	room.free()
	other.free()
	_drop_rig()
	await _frames(2)
	_ok(not Seat.new().sit(), "sit: with no player there is nobody to sit")


# --- press ---------------------------------------------------------------------

func _event(type: XRToolsPointerEvent.Type, target: Node3D) -> XRToolsPointerEvent:
	return XRToolsPointerEvent.new(type, null, target, Vector3.ZERO, Vector3.ZERO)


func _group_press() -> void:
	_make_rig()
	await _frames(2)
	var seat := _seat("seat_sofa", Vector3(2.0, 0.0, 2.0), 0.0)
	await _frames(2)
	var trigger := seat.find_child("SeatTrigger", false, false) as SeatTrigger
	_ok(trigger != null and trigger.collision_layer == SeatTrigger.POINTABLE_LAYER, "press: the cushion has a pointable trigger")
	trigger.pointer_event(_event(XRToolsPointerEvent.Type.ENTERED, trigger))
	_ok(trigger.is_hovered(), "press: aimed at, it is lit")
	trigger.pointer_event(_event(XRToolsPointerEvent.Type.EXITED, trigger))
	_ok(not trigger.is_hovered(), "press: and not when the aim leaves")
	trigger.pointer_event(_event(XRToolsPointerEvent.Type.RELEASED, trigger))
	_ok(not seat.is_occupied(), "press: a release alone does nothing")
	trigger.pointer_event(_event(XRToolsPointerEvent.Type.PRESSED, trigger))
	_ok(seat.is_occupied(), "press: a press on the cushion sits")
	trigger.pointer_event(_event(XRToolsPointerEvent.Type.PRESSED, trigger))
	_ok(not seat.is_occupied(), "press: and the next press gets up")
	_ok(seat.grab_hold_seconds() == HoldToGrab.DEFAULT_SECONDS, "press: the seat itself is carried by HOLDING on it, not by a press")
	# The trigger stands proud of the surface it is on, or the body's pointer box would win the ray.
	var pointer := seat.find_child("PointerArea", false, false) as StaticBody3D
	var top := -INF
	for c in pointer.get_children():
		var cs := c as CollisionShape3D
		top = maxf(top, cs.position.y + (cs.shape as BoxShape3D).size.y * 0.5)
	var slab := trigger.get_node("CollisionShape3D") as CollisionShape3D
	var slab_top := trigger.position.y + slab.position.y + (slab.shape as BoxShape3D).size.y * 0.5
	var cushion_top: float = (seat.find_child("EyePoint", false, false) as Node3D).position.y - 0.78
	_ok(slab_top > cushion_top, "press: the trigger's top is above the cushion (%.3f > %.3f)" % [slab_top, cushion_top])
	_ok(top > 0.0, "press: the body has a pointer box to carry it by")
	seat.free()
	_drop_rig()
	await _frames(2)


# --- family --------------------------------------------------------------------

func _group_family() -> void:
	for id in FAMILIES:
		var scene := load("res://Scenes/Objects/furniture/%s.tscn" % id) as PackedScene
		_ok(scene != null, "family: %s has a scene" % id)
		var seat := scene.instantiate() as Seat
		_ok(seat != null and seat.type_id == id, "family: ... it is a Seat and names itself (%s)" % id)
		add_child(seat)
		await _frames(1)
		var eye := seat.find_child("EyePoint", false, false) as Node3D
		var stand := seat.find_child("StandPoint", false, false) as Node3D
		_ok(eye != null and stand != null and seat.find_child("SeatTrigger", false, false) != null,
			"family: %s has an EyePoint, a StandPoint and a SeatTrigger" % id)
		_ok(seat.is_in_group("spawned") and seat.is_in_group(Seat.GROUP), "family: %s is a spawned seat" % id)
		_ok(eye.position.y > 0.5 and eye.position.y < 1.7, "family: %s's eyes are at a sitting height (%.2f m)" % [id, eye.position.y])
		_ok(_near(stand.position.y, 0.0) and absf(stand.position.x) >= 0.45, "family: %s lets you up on the floor, beside it" % id)
		_ok(seat.is_in_group("spawned") and (seat as RigidBody3D).collision_layer == 4, "family: %s is on the pickable layer like the table" % id)
		seat.free()


# --- save ----------------------------------------------------------------------

func _group_save() -> void:
	for id in FAMILIES:
		_ok(ScenePersistence.PLAIN_SCENES.has(id), "save: %s is a plain scene" % id)
		var seat := ScenePersistence.instantiate(id)
		_ok(seat is Seat and (seat as Seat).type_id == id, "save: and it is spawned by its token")
		seat.free()
