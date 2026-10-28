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
##   arrow/    a seat in a hand shows a yellow arrow along its facing, and only while it is held
##   family/   every seat scene has the script, its markers, a cushion and an eye height that is a sitting one
##   cockpit/  a sit-down driving cabinet's own seat: eyes level with the middle of its glass, pressed to sit, one seat at a time
##   follow/   a seat on a moving base carries the player with it, in position and never in heading
##   rider/    a motorbike's and a bicycle's saddle is a seat: pressed to sit, the eyes above it, a floor to get up onto, off the leaning part
##   pair/     a cockpit of two seats (Lucky & Wild): each sat in and got up from on its own side, one at a time, no pointer box over either cushion
##   save/     a seat is a plain scene saved by its token and spawned by it
extends "res://Tests/test_suite.gd"

const FAMILIES: Array[String] = ["seat_racing", "seat_stool", "seat_chair", "seat_cushion", "seat_sofa", "seat_bed"]

var _only := ""
var _rig: Node3D = null
var _origin: XROrigin3D = null
var _camera: XRCamera3D = null
var _body: XRToolsPlayerBody = null
var _loco: LocomotionManager = null


func _ready() -> void:
	suite_tag = "seat"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			_only = a.substr(7)
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("[seat] TIMED OUT")
		get_tree().quit(1))
	await _run()
	_finish()


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
	if _want("arrow"):
		await _group_arrow()
	if _want("family"):
		await _group_family()
	if _want("cockpit"):
		await _group_cockpit()
	if _want("follow"):
		await _group_follow()
	if _want("rider"):
		await _group_rider()
	if _want("pair"):
		await _group_pair()
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
	# A headset's laser hits no Area3D (its RayCast leaves collide_with_areas off): the cushion has a body of its own for it,
	# a sibling under the seat so that holding on it still carries the seat.
	var laser := trigger.laser_body()
	_ok(laser != null and laser.collision_layer == SeatTrigger.POINTABLE_LAYER and laser.get_parent() == seat,
		"press: a laser can hit the cushion (a body on the pointable layer) and it is the seat's, so a hold on it carries the seat")
	var rest_box := (trigger.get_node("CollisionShape3D") as CollisionShape3D).shape as BoxShape3D
	var laser_shape := laser.get_child(0) as CollisionShape3D
	_ok(laser != null and laser.get_child_count() == 1 and (laser_shape.shape as BoxShape3D).size.is_equal_approx(rest_box.size)
			and laser.position.is_equal_approx(trigger.position),
		"press: and it is the trigger's own size, in the same place")
	laser.call("pointer_event", _event(XRToolsPointerEvent.Type.PRESSED, laser))
	_ok(seat.is_occupied(), "press: the laser's press on that body sits")
	laser.call("pointer_event", _event(XRToolsPointerEvent.Type.PRESSED, laser))
	_ok(not seat.is_occupied(), "press: and the next one gets up")
	laser.call("pointer_event", _event(XRToolsPointerEvent.Type.ENTERED, laser))
	_ok(trigger.is_hovered() and SeatTrigger.HOVER_COLOR.r > 0.9 and SeatTrigger.HOVER_COLOR.g > 0.8 and SeatTrigger.HOVER_COLOR.b < 0.2,
		"press: aimed at by a laser the cushion is lit, and the light is yellow (not green)")
	laser.call("pointer_event", _event(XRToolsPointerEvent.Type.EXITED, laser))
	# Sat on, the cushion is under the sitter and a laser leaves the hand pointing forward: its slab grows toward the knees
	# and the sides, and shrinks back when they get up. The Area3D the desktop uses keeps its size.
	seat.sit()
	var grown := (laser_shape.shape as BoxShape3D).size
	_ok(is_equal_approx(grown.z, rest_box.size.z + SeatTrigger.STAND_REACH_FORWARD)
			and is_equal_approx(grown.x, rest_box.size.x + SeatTrigger.STAND_REACH_SIDE * 2.0) and is_equal_approx(grown.y, rest_box.size.y),
		"press: sat on, the laser's slab reaches forward and to the sides (%s)" % str(grown))
	_ok(laser_shape.position.z < trigger.get_node("CollisionShape3D").position.z - SeatTrigger.STAND_REACH_FORWARD * 0.49,
		"press: and the extra is toward the front (-Z), not behind the sitter")
	_ok(rest_box.size.is_equal_approx(Vector3(grown.x - SeatTrigger.STAND_REACH_SIDE * 2.0, grown.y, grown.z - SeatTrigger.STAND_REACH_FORWARD)),
		"press: while the desktop's Area3D keeps the cushion's own size")
	seat.stand()
	_ok((laser_shape.shape as BoxShape3D).size.is_equal_approx(rest_box.size) and laser_shape.position.is_equal_approx(trigger.get_node("CollisionShape3D").position),
		"press: stood up, the slab is the cushion again")
	# The seat's body: a press on it stands the sitter up, and does nothing to somebody who is not sitting.
	var body_part := seat.find_child("PointerArea", false, false) as StaticBody3D
	_ok(body_part is SeatPointerArea, "press: the seat's body answers a press (SeatPointerArea)")
	body_part.call("pointer_event", _event(XRToolsPointerEvent.Type.PRESSED, body_part))
	_ok(not seat.is_occupied(), "press: a press on the body of a seat nobody sits on sits nobody")
	seat.sit()
	body_part.call("pointer_event", _event(XRToolsPointerEvent.Type.ENTERED, body_part))
	_ok(seat.is_occupied(), "press: aiming at the body does not get the sitter up")
	body_part.call("pointer_event", _event(XRToolsPointerEvent.Type.PRESSED, body_part))
	_ok(not seat.is_occupied(), "press: a press on the body gets them up")
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


# --- arrow ---------------------------------------------------------------------

func _group_arrow() -> void:
	var seat := _seat("seat_sofa", Vector3(1.0, 0.0, 1.0), 0.8)
	await _frames(2)
	_ok(seat.facing_arrow() == null and seat.find_child("FacingArrow", true, false) == null, "arrow: a seat on the floor shows none")
	seat.picked_up.emit(seat)
	var arrow := seat.facing_arrow()
	_ok(arrow != null and arrow.is_inside_tree() and arrow.get_parent() == seat, "arrow: taken in a hand, it shows one, riding the seat")
	var parts := arrow.find_children("*", "MeshInstance3D", false, false)
	var yellow := parts.size() == 2
	for part in parts:
		var m := ((part as MeshInstance3D).mesh.material as StandardMaterial3D)
		yellow = yellow and m.albedo_color.r > 0.9 and m.albedo_color.g > 0.7 and m.albedo_color.b < 0.3
	_ok(yellow, "arrow: yellow, a shaft and a head")
	var eye := seat.eye_transform()
	var along := -arrow.global_transform.basis.z
	var facing := -eye.basis.z
	_ok(along.dot(facing) > 0.999, "arrow: it points the way the seat faces (%s vs %s)" % [along, facing])
	var tip := arrow.global_position + along * Seat.ARROW_LENGTH
	_ok(arrow.global_position.distance_to(Vector3(eye.origin.x, arrow.global_position.y, eye.origin.z)) < 1e-3
			and tip.distance_to(arrow.global_position) > 0.5, "arrow: from the middle of the cushion, half a metre out")
	seat.picked_up.emit(seat)
	_ok(seat.find_children("FacingArrow", "Node3D", true, false).size() == 1, "arrow: taking it again makes no second one")
	seat.rotate_y(1.0)
	var along2 := -arrow.global_transform.basis.z
	_ok(along2.dot(-seat.eye_transform().basis.z) > 0.999, "arrow: and it turns with the seat")
	seat.dropped.emit(seat)
	await _frames(2)
	_ok(seat.facing_arrow() == null and seat.find_child("FacingArrow", true, false) == null, "arrow: let go, it is gone")
	seat.picked_up.emit(seat)
	_ok(seat.facing_arrow() != null, "arrow: and comes again the next time")
	seat.free()
	await _frames(2)
	_ok(true, "arrow: a seat freed in a hand takes it with it")


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


# --- cockpit -------------------------------------------------------------------

## A sit-down cabinet's cockpit built as the room builds it (a form on a cabinet), under a stand-in cabinet at `at`
## turned by `yaw`: a bare Node3D (the builder needs nothing more), optionally a pickable one.
func _cockpit(at: Vector3, yaw: float, pickable: bool = false, romset: String = "daytona") -> Dictionary:
	var base := ArcadeCabinetSpecs.variant("generic")
	base["variant"] = "generic"
	var spec := ArcadeCabinetSpecs.for_game(base, ArcadeGameProfile.for_romset(romset))
	var cab: Node3D = XRToolsPickable.new() if pickable else Node3D.new()
	cab.transform = Transform3D(Basis(Vector3.UP, yaw), at)
	add_child(cab)
	var builder := ArcadeCabinetBuilder.new(spec, cab)
	builder.build_form()
	var seat := cab.find_child("DriverSeat", true, false)
	if seat == null:
		seat = cab.find_child("RiderSeat", true, false)
	return {"cab": cab, "seat": seat, "boxes": builder.form_boxes, "spec": spec}


func _group_cockpit() -> void:
	_make_rig()
	await _frames(2)
	_body.enabled = true
	var built := _cockpit(Vector3(2.0, 0.0, -3.0), 0.7)
	var cab := built["cab"] as Node3D
	var seat := built["seat"] as CockpitSeat
	await _frames(2)
	_ok(seat != null and seat.find_child("EyePoint", false, false) != null and seat.find_child("StandPoint", false, false) != null
			and seat.find_child("SeatTrigger", false, false) is SeatTrigger,
		"cockpit: a sit-down cabinet's seat is a CockpitSeat with its EyePoint, StandPoint and SeatTrigger")
	var as_node: Node = seat
	_ok(not seat.is_in_group("spawned") and not seat.is_in_group(Seat.GROUP) and not (as_node is XRToolsPickable),
		"cockpit: it is part of the cabinet: no object of its own, never saved by itself")
	# THE EYES ARE AT THE MIDDLE OF THE GLASS: a seated driver looks straight into the monitor.
	var racer: Dictionary = ArcadeCabinetSpecs.shapes()["racer"]
	var glass_mid := ((racer["glass_a"] as Vector2).y + (racer["glass_b"] as Vector2).y) * 0.5
	var eye := seat.eye_transform()
	var eye_local := cab.to_local(eye.origin)
	_ok(_near(eye_local.y, glass_mid, 0.005), "cockpit: the eyes are level with the middle of the glass (%.3f m, glass %.3f m)" % [eye_local.y, glass_mid])
	var cushion := seat.find_child("SeatCushion", false, false) as Node3D
	var cushion_top := cab.to_local(cushion.global_position).y + 0.04
	_ok(_near(eye_local.y - cushion_top, 0.72, 0.005),
		"cockpit: and a sitting adult's eye height above the cushion, as the racing seat furniture's (%.2f m)" % (eye_local.y - cushion_top))
	_ok(_near(Seat.yaw_of(eye.basis), Seat.yaw_of(cab.global_basis), 1e-3), "cockpit: looking the way the cabinet faces, at the screen")
	# Sitting.
	var seen: Array = []
	seat.seated_changed.connect(func(on: bool) -> void: seen.append(on))
	_ok(seat.sit() and seat.is_occupied() and Seat.current == seat, "cockpit: sitting takes the seat")
	await _frames(2)
	_ok(_camera.global_position.distance_to(eye.origin) < 0.02, "cockpit: the head is at the seat's eyes (%s vs %s)" % [_camera.global_position, eye.origin])
	_ok(_near(_camera.position.y, eye.origin.y - seat.global_position.y), "cockpit: on the desktop the camera is as tall as the seat's eyes are above its floor")
	_ok(_loco.is_blocked(LocomotionManager.CHANNEL_ALL) and _body.enabled, "cockpit: walking is held back and the body stays ON")
	var pinned := _origin.global_position
	_origin.global_position += Vector3(0.3, 0.0, -0.4)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_ok(_origin.global_position.distance_to(pinned) < 1e-3, "cockpit: whatever moves the origin is undone: the body is held in the seat")
	# One seat at a time, a chair's or a cockpit's.
	var chair := _seat("seat_chair", Vector3(-3.0, 0.0, 2.0), 0.0)
	await _frames(2)
	chair.sit()
	_ok(Seat.current == chair and not seat.is_occupied() and seen == [true, false], "cockpit: sitting in a chair gets up from the cockpit's seat")
	seat.sit()
	_ok(Seat.current == seat and not chair.is_occupied(), "cockpit: and the cockpit's seat takes the player from the chair")
	chair.free()
	# Getting up puts the player beside the seat, on the floor, and gives the camera back.
	var stand_at := seat.stand_point()
	seat.stand()
	await _frames(2)
	_ok(Seat.current == null and _near(_camera.global_position.x, stand_at.x, 1e-3) and _near(_camera.global_position.z, stand_at.z, 1e-3),
		"cockpit: getting up puts the player on the StandPoint")
	_ok(_near(cab.to_local(stand_at).x, -0.62, 0.01) and _near(cab.to_local(stand_at).y, 0.0, 0.01),
		"cockpit: ... on the driver's side, on the floor (%s)" % str(cab.to_local(stand_at)))
	_ok(not _loco.is_blocked(LocomotionManager.CHANNEL_ALL) and _near(_camera.position.y, 1.6), "cockpit: locomotion and the camera's height come back")
	# The press does it.
	var trigger := seat.find_child("SeatTrigger", false, false) as SeatTrigger
	trigger.pointer_event(_event(XRToolsPointerEvent.Type.PRESSED, trigger))
	_ok(seat.is_occupied(), "cockpit: a press on the cushion sits")
	trigger.pointer_event(_event(XRToolsPointerEvent.Type.PRESSED, trigger))
	_ok(not seat.is_occupied(), "cockpit: and the next press gets up")
	# The trigger is reachable: nothing the cabinet is aimed at by stands over the cushion.
	var slab := trigger.get_node("CollisionShape3D") as CollisionShape3D
	var slab_box := AABB(trigger.position + seat.position + slab.position - (slab.shape as BoxShape3D).size * 0.5,
		(slab.shape as BoxShape3D).size)
	var covered := false
	for box: AABB in built["boxes"]:
		covered = covered or box.intersects(slab_box)
	_ok(not covered, "cockpit: no pointer box of the cabinet stands over the cushion, where the trigger is (a laser reaches it)")
	# The form changing under the player, and the cabinet taken in a hand, let them go.
	seat.sit()
	seat.get_parent().remove_child(seat)
	seat.free()
	await _frames(2)
	_ok(Seat.current == null and not _loco.is_blocked(LocomotionManager.CHANNEL_ALL) and _near(_camera.position.y, 1.6),
		"cockpit: a form taken down with the player in it lets go of them")
	cab.free()
	var carried := _cockpit(Vector3(-2.0, 0.0, -3.0), 0.0, true)
	var carried_seat := carried["seat"] as CockpitSeat
	await _frames(2)
	carried_seat.sit()
	(carried["cab"] as XRToolsPickable).picked_up.emit(carried["cab"])
	_ok(Seat.current == null and _near(_camera.position.y, 1.6), "cockpit: the cabinet taken in a hand lets the player go")
	carried_seat.sit()
	Seat.release_all()
	_ok(Seat.current == null and not _loco.is_blocked(LocomotionManager.CHANNEL_ALL), "cockpit: leaving the room lets go of it too")
	(carried["cab"] as Node).free()
	_drop_rig()
	await _frames(2)


# --- follow --------------------------------------------------------------------

## A cockpit on a moving base (After Burner II's): the seat moves with the base, and a player in it goes where the seat went. Position only: the
## base turns a few degrees and the view must not turn with it. A seat that does not move (Daytona USA's) moves nobody.
func _group_follow() -> void:
	_make_rig()
	await _frames(2)
	_body.enabled = true
	var built := _cockpit(Vector3(2.0, 0.0, -3.0), 0.7, false, "aburner2")
	var cab := built["cab"] as Node3D
	var seat := built["seat"] as CockpitSeat
	var pivot := cab.find_child("MotionPivot", true, false) as Node3D
	await _frames(2)
	_ok(seat != null and pivot != null and pivot.is_ancestor_of(seat), "follow: After Burner II's seat is on a moving base")
	seat.sit()
	await _frames(3)
	var sat_at := _camera.global_position
	var yaw_then := Seat.yaw_of(_camera.global_basis)
	var origin_basis := _origin.global_basis
	# The base lifts and slides a few centimetres: the head goes with it, and the pin holds it there.
	var eye_before := seat.eye_transform().origin
	pivot.position = Vector3(0.04, 0.03, -0.02)
	await _frames(3)
	var eye_after := seat.eye_transform().origin
	var shift := eye_after - eye_before
	_ok(shift.length() > 0.04, "follow: the base moves the eye point (%.3f m)" % shift.length())
	_ok(_camera.global_position.distance_to(sat_at + shift) < 0.01 and _camera.global_position.distance_to(eye_after) < 0.02,
		"follow: and the head went where the seat went (%s from the eye point)" % str(_camera.global_position - eye_after))
	# The body, looked at the moment follow() puts it there. Three frames later the body's own physics step has run (here nothing holds it up, so it has
	# fallen to the floor), which a look then sees and this is not about: the host calls follow() from its physics process, and what it owes the body is a
	# start from under the head, or the body would sweep back through the seat from wherever it was.
	pivot.position = Vector3(0.07, 0.03, -0.02)
	seat.sitting().follow()
	_ok(_near(_body.global_position.x, _camera.global_position.x, 1e-3) and _near(_body.global_position.z, _camera.global_position.z, 1e-3)
			and _near(_body.global_position.y, _origin.global_position.y, 1e-3),
		"follow: and the body is put under it as it goes, or it would sweep back through the seat on the next step (body %s, head %s, origin y %.3f)"
			% [str(_body.global_position), str(_camera.global_position), _origin.global_position.y])
	await _frames(3)
	var held := _origin.global_position
	_origin.global_position += Vector3(0.3, 0.0, -0.4)
	await _frames(3)
	_ok(_origin.global_position.distance_to(held) < 1e-3, "follow: the body is still held in the seat, where the seat now is")
	# It tilts: the eye point swings a few centimetres, the head follows it, and the view does not turn.
	var centre := Vector3(0.0, ArcadeCabinetBuilder.PLATFORM_TOP, (ArcadeCabinetBuilder.COCKPIT_Z0 + ArcadeCabinetBuilder.COCKPIT_Z1) * 0.5)
	var b := Basis(Vector3.BACK, deg_to_rad(-4.0))
	pivot.transform = Transform3D(b, centre - b * centre)
	await _frames(3)
	_ok(_camera.global_position.distance_to(seat.eye_transform().origin) < 0.02, "follow: a base that tilts takes the head with the eye point")
	_ok(_near(Seat.yaw_of(_camera.global_basis), yaw_then, 1e-3) and _origin.global_basis.is_equal_approx(origin_basis),
		"follow: and the heading is the player's, not the base's: the origin does not turn")
	# Level again, the head is back; getting up still puts the player on the floor beside the seat.
	pivot.transform = Transform3D.IDENTITY
	await _frames(3)
	_ok(_camera.global_position.distance_to(sat_at) < 0.01, "follow: the base level again, the head is where it sat down")
	var stand_at := seat.stand_point()
	seat.stand()
	await _frames(2)
	_ok(Seat.current == null and _near(_camera.global_position.x, stand_at.x, 1e-3) and _near(_camera.global_position.z, stand_at.z, 1e-3),
		"follow: getting up still puts the player on the StandPoint")
	cab.free()
	# A cockpit that does not move moves nobody: the pin is the whole of it.
	var still := _cockpit(Vector3(-2.0, 0.0, -3.0), 0.0, false, "daytona")
	var still_seat := still["seat"] as CockpitSeat
	await _frames(2)
	still_seat.sit()
	await _frames(3)
	var still_head := _camera.global_position
	await _frames(3)
	_ok(_camera.global_position.distance_to(still_head) < 1e-4 and still["cab"].find_child("MotionPivot", true, false) == null,
		"follow: a seat on no base leaves the head where it is")
	still_seat.stand()
	(still["cab"] as Node).free()
	_drop_rig()
	await _frames(2)


# --- rider ---------------------------------------------------------------------

## The saddle of a ride-on motorbike (Hang-On) or bicycle (Prop Cycle) used to be a picture of one: the seat was drawn and nothing could be sat on. It is a CockpitSeat
## now: the cushion you press on the saddle's top, the eyes above it, the floor to get up onto, and NOT on the part that leans (a bike that leaned its rider 14 degrees
## would swing a head 30 cm).
func _group_rider() -> void:
	_make_rig()
	await _frames(2)
	_body.enabled = true
	for row: Array in [["hangon", "BikeSeat", 0.55, 0.80, "LeanPivot"], ["propcycl", "Saddle", 0.60, 0.85, ""]]:
		var romset: String = row[0]
		var built := _cockpit(Vector3(2.0, 0.0, -3.0), 0.7, false, romset)
		var cab := built["cab"] as Node3D
		var seat := built["seat"] as CockpitSeat
		await _frames(2)
		_ok(seat != null and seat.name == "RiderSeat" and seat.find_child("EyePoint", false, false) != null and seat.find_child("StandPoint", false, false) != null
				and seat.find_child("SeatTrigger", false, false) is SeatTrigger,
			"rider: %s: the saddle is a CockpitSeat with its EyePoint, StandPoint and SeatTrigger" % romset)
		if seat == null:
			cab.free()
			continue
		var saddle := cab.find_child(str(row[1]), true, false) as MeshInstance3D
		var size := (saddle.mesh as BoxMesh).size
		var top := cab.to_local(saddle.global_position).y + size.y * 0.5
		var eye := cab.to_local(seat.eye_transform().origin)
		var trigger := seat.find_child("SeatTrigger", false, false) as SeatTrigger
		var at := cab.to_local(trigger.global_position)
		_ok(absf(eye.x) < 0.02 and eye.y - top >= float(row[2]) and eye.y - top <= float(row[3]) and absf(eye.z - cab.to_local(saddle.global_position).z) < 0.15,
			"rider: %s: the eyes are over the saddle, %.2f m above it (%.2f..%.2f is a rider's)" % [romset, eye.y - top, float(row[2]), float(row[3])])
		_ok(absf(at.x) < 0.02 and at.y > top - 0.005 and at.y < top + 0.03 and absf(at.z - cab.to_local(saddle.global_position).z) < 0.05,
			"rider: %s: the cushion to press is on the saddle's top (%.3f m, the saddle's %.3f)" % [romset, at.y, top])
		_ok(_near(Seat.yaw_of(seat.eye_transform().basis), Seat.yaw_of(cab.global_basis), 1e-3), "rider: %s: looking the way the cabinet faces, at the screen" % romset)
		var stand := cab.to_local(seat.stand_point())
		_ok(absf(stand.x) >= 0.40 and _near(stand.y, 0.0, 0.01), "rider: %s: getting up is onto the floor beside the stand (%s)" % [romset, str(stand)])
		# The part that leans never carries the seat.
		var lean := cab.find_child("LeanPivot", true, false)
		_ok(lean == null or not lean.is_ancestor_of(seat), "rider: %s: the seat is not on the part that leans" % romset)
		# Nothing the cabinet is aimed at by stands over the cushion.
		var slab := trigger.get_node("CollisionShape3D") as CollisionShape3D
		var slab_box := AABB(trigger.position + seat.position + slab.position - (slab.shape as BoxShape3D).size * 0.5, (slab.shape as BoxShape3D).size)
		var covered := false
		for box: AABB in built["boxes"]:
			covered = covered or box.intersects(slab_box)
		_ok(not covered, "rider: %s: no pointer box of the cabinet stands over the cushion (a laser reaches it)" % romset)
		# Sitting: the head goes to the eyes, a press does it, getting up puts the player on the stand point.
		trigger.pointer_event(_event(XRToolsPointerEvent.Type.PRESSED, trigger))
		await _frames(2)
		_ok(seat.is_occupied() and _camera.global_position.distance_to(seat.eye_transform().origin) < 0.02,
			"rider: %s: a press on the saddle sits, the head at the eyes" % romset)
		_ok(_near(_camera.position.y, seat.eye_transform().origin.y - seat.global_position.y), "rider: %s: on the desktop the camera is as tall as the eyes are above the rider's floor" % romset)
		var stand_at := seat.stand_point()
		trigger.pointer_event(_event(XRToolsPointerEvent.Type.PRESSED, trigger))
		await _frames(2)
		_ok(not seat.is_occupied() and _near(_camera.global_position.x, stand_at.x, 1e-3) and _near(_camera.global_position.z, stand_at.z, 1e-3),
			"rider: %s: the next press gets up, onto the StandPoint" % romset)
		# A bike leaning to the full under the rider does not move the head.
		if lean != null:
			seat.sit()
			await _frames(2)
			var head := _camera.global_position
			(lean as Node3D).basis = Basis(Vector3.BACK, deg_to_rad(-14.0))
			await _frames(3)
			_ok(_camera.global_position.distance_to(head) < 1e-3, "rider: %s: the bike at full lean under the rider leaves the head where it is" % romset)
			seat.stand()
		cab.free()
	_drop_rig()
	await _frames(2)


# --- pair ----------------------------------------------------------------------

## Lucky & Wild's cockpit has a driver's seat and a gunner's, side by side. Each is a CockpitSeat of its own: sat in by a press, got up from onto its own side, and one
## player is in one seat at a time.
func _group_pair() -> void:
	_make_rig()
	await _frames(2)
	_body.enabled = true
	var built := _cockpit(Vector3(2.0, 0.0, -3.0), 0.7, false, "luckywld")
	var cab := built["cab"] as Node3D
	var driver := built["seat"] as CockpitSeat
	var gunner := cab.find_child("GunnerSeat", true, false) as CockpitSeat
	await _frames(2)
	_ok(driver != null and gunner != null and driver != gunner, "pair: the cockpit has two seats, a driver's and a gunner's")
	if driver == null or gunner == null:
		cab.free()
		_drop_rig()
		return
	var d := cab.to_local(driver.eye_transform().origin)
	var g := cab.to_local(gunner.eye_transform().origin)
	_ok(_near(d.x, -ArcadeCabinetSpecs.RACEGUN_SEAT_X, 0.005) and _near(g.x, ArcadeCabinetSpecs.RACEGUN_SEAT_X, 0.005) and _near(d.y, g.y, 0.001) and _near(d.z, g.z, 0.001),
		"pair: side by side, the driver on the left, with the same eyes (%s, %s)" % [str(d), str(g)])
	_ok(driver.sit() and Seat.current == driver, "pair: the driver sits")
	await _frames(2)
	_ok(_camera.global_position.distance_to(driver.eye_transform().origin) < 0.02, "pair: the head is at the driver's eyes")
	_ok(gunner.sit() and Seat.current == gunner and not driver.is_occupied(), "pair: the gunner sitting takes the driver's place: one player, one seat")
	await _frames(2)
	_ok(_camera.global_position.distance_to(gunner.eye_transform().origin) < 0.02 and _camera.global_position.distance_to(driver.eye_transform().origin) > 0.3,
		"pair: and the head is at the gunner's eyes, 0.4 m from the driver's")
	var stand_at := gunner.stand_point()
	gunner.stand()
	await _frames(2)
	_ok(Seat.current == null and _near(_camera.global_position.x, stand_at.x, 1e-3) and _near(_camera.global_position.z, stand_at.z, 1e-3) and cab.to_local(stand_at).x > 0.45,
		"pair: getting up from the gunner's seat is onto the right of the cabinet, the driver's onto the left (%s)" % str(cab.to_local(stand_at)))
	_ok(cab.to_local(driver.stand_point()).x < -0.45, "pair: ... (the driver's stand point is at %s)" % str(cab.to_local(driver.stand_point())))
	# Neither cushion is covered by a pointer box.
	var covered: Array[String] = []
	for seat: CockpitSeat in [driver, gunner]:
		var trigger := seat.find_child("SeatTrigger", false, false) as SeatTrigger
		var slab := trigger.get_node("CollisionShape3D") as CollisionShape3D
		var slab_box := AABB(trigger.position + seat.position + slab.position - (slab.shape as BoxShape3D).size * 0.5, (slab.shape as BoxShape3D).size)
		for box: AABB in built["boxes"]:
			if box.intersects(slab_box):
				covered.append(str(seat.name))
	_ok(covered.is_empty(), "pair: no pointer box of the cabinet stands over either cushion (%s)" % ", ".join(covered))
	cab.free()
	_drop_rig()
	await _frames(2)


# --- save ----------------------------------------------------------------------

func _group_save() -> void:
	for id in FAMILIES:
		_ok(ScenePersistence.PLAIN_SCENES.has(id), "save: %s is a plain scene" % id)
		var seat := ScenePersistence.instantiate(id)
		_ok(seat is Seat and (seat as Seat).type_id == id, "save: and it is spawned by its token")
		seat.free()
