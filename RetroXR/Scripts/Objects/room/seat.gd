## Seat — somewhere the player sits: a racing seat, a stool, a cushion on the floor, a chair,
## a sofa, a bed.
##
## Press the seat's cushion (a desktop click, the laser's trigger: SeatTrigger) and the
## player is carried onto it: the origin is moved so the HEAD is at the seat's `EyePoint`,
## looking the way the seat faces, and stays there, at that height and that heading, until
## the same press again (or the seat is picked up, removed or the room is left). Walking,
## teleporting and snap-turning are held back while seated (LocomotionManager). Looking round
## stays free: the head in VR, the mouse on the desktop. Only the BODY is held: the origin is
## pinned where it was put.
##
## THE PLAYER BODY STAYS ON. godot-xr-tools runs every movement provider from inside the body's
## physics step and skips them all when it is disabled, which takes the desktop's mouse-look and
## its mouse capture with it: a seat that switched the body off left the player unable to turn
## and so unable to aim at the seat to get up. The body's collision mask has no pickable layer, so
## its capsule does not fight the seat's own shape.
##
## HEIGHT. On the desktop the camera's own height is the player's eye height, so the seat sets it
## to its own and puts it back when the player gets up. In a headset the head's height is the
## person's, measured from the floor, and a seat cannot move it: it puts the floor under the seat
## and leaves the head where it is (somebody sitting on a real chair is already at that height).
##
## Standing up puts the player on the seat's `StandPoint`, which is worked out from where the
## seat IS then, so a seat that was moved while sat on, or is gone, lets go sensibly.
##
## A seat is a pickable thing like a table: carried by HOLDING on it (HoldToGrab), pressed on
## its cushion to sit. Its pose is its whole saved state (the player's being seated is
## nobody's but this session's: it is never saved and never on the wire).
##
## The scenes are baked by Tools/gen/gen_seats.gd; a mod's seat is any scene with this script
## and an `EyePoint` and a `StandPoint` marker.
class_name Seat
extends XRToolsPickable

signal seated_changed(on: bool)

## Every seat joins this, so a sweep can find them without testing the class.
const GROUP := "seat"
const BLOCK_OWNER := &"seat"

## The seat the player is in, or null. One player, one seat.
static var current: Seat = null

## The ScenePersistence PLAIN_SCENES key this scene is saved and spawned under.
@export var type_id := "seat_chair"

## Where the origin was put when the player sat: held there every physics frame while they are in it.
var _pin := Vector3.ZERO
## The player's pieces as found when they sat, so the per-frame pin does not search the tree.
var _rig: PlayerPieces = null
## The desktop camera's height before the seat set it, to put back; negative when it was not touched.
var _saved_camera_y := -1.0


func _ready() -> void:
	super._ready()
	add_to_group("spawned")
	add_to_group(GROUP)
	picked_up.connect(func(_p: Variant) -> void:
		stand()
		_show_facing_arrow())
	dropped.connect(func(_p: Variant) -> void: _hide_facing_arrow())
	set_physics_process(false)


func _exit_tree() -> void:
	# Taken out of the room (put away, a mod unloaded) with the player in it: let go.
	if current == self:
		stand()


func _physics_process(_delta: float) -> void:
	if current != self:
		set_physics_process(false)
		return
	# Whatever moved the origin since the last frame (a provider that was not held back, the body
	# being pushed) is undone: the head is free, the body is not.
	if _rig == null or not is_instance_valid(_rig.origin):
		return
	if _rig.origin.global_position.distance_squared_to(_pin) > 1.0e-6:
		_rig.origin.global_position = _pin


## While the seat is in a hand a yellow arrow shows which way the player will face when they sit on it, so it can be
## set down the right way round. It is only an indicator: made when the seat is taken, freed when it is let go, never
## saved and never part of the scene.
const ARROW_COLOR := Color(1.0, 0.85, 0.1)
const ARROW_LENGTH := 0.55
const ARROW_HEAD := 0.16

var _arrow: Node3D = null


## The arrow while it is showing, or null (for the tests).
func facing_arrow() -> Node3D:
	return _arrow


func _show_facing_arrow() -> void:
	if _arrow != null:
		return
	var eye := find_child("EyePoint", true, false) as Node3D
	var trigger := find_child("SeatTrigger", true, false) as Node3D
	# From the middle of the cushion, level with it, along the way the eyes look.
	var base := Vector3(eye.position.x if eye != null else 0.0, trigger.position.y + 0.05 if trigger != null else 0.5,
		eye.position.z if eye != null else 0.0)
	var basis := eye.basis if eye != null else Basis.IDENTITY
	_arrow = Node3D.new()
	_arrow.name = "FacingArrow"
	_arrow.transform = Transform3D(basis, base)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = ARROW_COLOR
	# Seen through the seat's own cushion and back, or a sofa would hide most of it.
	mat.no_depth_test = true
	mat.render_priority = 10
	var shaft_len := ARROW_LENGTH - ARROW_HEAD
	var shaft := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.05, 0.015, shaft_len)
	box.material = mat
	shaft.mesh = box
	shaft.position = Vector3(0.0, 0.0, -shaft_len * 0.5)
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_arrow.add_child(shaft)
	var head := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.09
	cone.height = ARROW_HEAD
	cone.material = mat
	head.mesh = cone
	# A cylinder stands along +Y: laid so its point leads along -Z.
	head.basis = Basis(Vector3.RIGHT, -PI * 0.5)
	head.position = Vector3(0.0, 0.0, -shaft_len - ARROW_HEAD * 0.5)
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_arrow.add_child(head)
	add_child(_arrow)


func _hide_facing_arrow() -> void:
	if _arrow != null:
		_arrow.queue_free()
		_arrow = null


## A seat is carried by holding on it, never by a stray press: the press is the sitting.
func grab_hold_seconds() -> float:
	return HoldToGrab.DEFAULT_SECONDS


func is_occupied() -> bool:
	return current == self


## Sit down, or stand up if this is the seat the player is in.
func toggle() -> void:
	if is_occupied():
		stand()
	else:
		sit()


## Where the eyes go: `EyePoint`'s transform in the world. -Z is the way the seat faces. A seat
## with no marker looks forward from a metre up, which is only the contract failing quietly.
func eye_transform() -> Transform3D:
	var marker := find_child("EyePoint", true, false) as Node3D
	if marker != null:
		return marker.global_transform
	return global_transform * Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0))


## Where the feet go when the player gets up: `StandPoint`, on the floor. Without one, half a
## metre in front of the seat.
func stand_point() -> Vector3:
	var marker := find_child("StandPoint", true, false) as Node3D
	if marker != null:
		return marker.global_position
	return global_transform * Vector3(0.0, 0.0, -0.5)


## Carry the player onto this seat. False when there is no player to carry (no camera).
func sit() -> bool:
	var rig := PlayerPieces.find(self)
	if rig.camera == null or rig.origin == null:
		return false
	if current != null and current != self:
		current.stand()
	var eye := eye_transform()
	var floor_y := global_position.y
	_saved_camera_y = -1.0
	if not MenuStyle.is_vr_mode():
		# The desktop eye height is the camera's own height above the origin.
		_saved_camera_y = rig.camera.position.y
		rig.camera.position.y = eye.origin.y - floor_y
	rig.origin.global_transform = origin_for_eye(rig.origin.global_transform, rig.camera.global_transform, eye, floor_y)
	_pin = rig.origin.global_position
	_rig = rig
	_put_body_under_camera(rig)
	_block_locomotion(true)
	current = self
	set_physics_process(true)
	seated_changed.emit(true)
	return true


## Let the player up, onto the StandPoint. Does nothing when this is not the seat they are in.
func stand() -> void:
	if current != self:
		return
	current = null
	set_physics_process(false)
	var rig := _rig if _rig != null and is_instance_valid(_rig.origin) else PlayerPieces.find(self)
	_rig = null
	_block_locomotion(false)
	if rig.camera != null and rig.origin != null:
		if _saved_camera_y >= 0.0:
			rig.camera.position.y = _saved_camera_y
		rig.origin.global_transform = origin_for_stand(rig.origin.global_transform, rig.camera.global_transform, stand_point())
		_put_body_under_camera(rig)
	_saved_camera_y = -1.0
	seated_changed.emit(false)


## The body is put on the floor under the head where the player now is, as a teleport does, or it
## would sweep there from where it was, through whatever is between.
func _put_body_under_camera(rig: PlayerPieces) -> void:
	if rig.body == null or rig.camera == null or rig.origin == null:
		return
	var head := rig.camera.global_position
	rig.body.global_position = Vector3(head.x, rig.origin.global_position.y, head.z)
	rig.body.velocity = Vector3.ZERO


## The room is being changed: whoever sits keeps no seat (the next room has none of these). Only
## the claim is dropped; the rig puts the body away and back itself (PlayerRig.leave_world).
static func release_all() -> void:
	if current == null:
		return
	var seat := current
	current = null
	seat.set_physics_process(false)
	seat._block_locomotion(false)
	if seat._saved_camera_y >= 0.0 and seat._rig != null and is_instance_valid(seat._rig.camera):
		seat._rig.camera.position.y = seat._saved_camera_y
	seat._rig = null
	seat._saved_camera_y = -1.0
	seat.seated_changed.emit(false)


func _block_locomotion(on: bool) -> void:
	var loco := get_tree().root.find_child("LocomotionManager", true, false) as LocomotionManager
	if loco == null:
		return
	if on:
		loco.set_block(BLOCK_OWNER, LocomotionManager.CHANNEL_ALL, true)
		loco.set_block(BLOCK_OWNER, LocomotionManager.CHANNEL_DESKTOP_MOVE, true)
	else:
		loco.clear_owner(BLOCK_OWNER)


# ── the pose, pure ──────────────────────────────────────────────────────────

## The heading of a basis about the world's up: the angle that turns -Z to where the basis faces.
static func yaw_of(basis: Basis) -> float:
	var forward := -basis.z
	return atan2(-forward.x, -forward.z)


## Where the origin must stand for the camera to be at `eye` looking the way `eye` does (yaw only:
## the head's own pitch and roll are the player's). The origin turns about the camera's own spot
## first, so the room-scale position the player is standing at within it is kept, then the whole
## rig is carried over the eye, standing on `floor_y` (the origin is the player's floor, and the
## head is as high above it as the player's own height: on the desktop that is the camera's
## height, which the seat has just set; in a headset it is the person's).
static func origin_for_eye(origin: Transform3D, camera: Transform3D, eye: Transform3D, floor_y: float) -> Transform3D:
	var turn := Basis(Vector3.UP, yaw_of(eye.basis) - yaw_of(camera.basis))
	var turned := Transform3D(turn * origin.basis, camera.origin + turn * (origin.origin - camera.origin))
	return Transform3D(turned.basis, Vector3(turned.origin.x + eye.origin.x - camera.origin.x,
		floor_y, turned.origin.z + eye.origin.z - camera.origin.z))


## Where the origin must stand to put the player on `stand` (a floor point): the camera over it
## horizontally, the origin on its floor. The heading is left as it is.
static func origin_for_stand(origin: Transform3D, camera: Transform3D, stand_at: Vector3) -> Transform3D:
	var shift := Vector3(stand_at.x - camera.origin.x, stand_at.y - origin.origin.y, stand_at.z - camera.origin.z)
	return Transform3D(origin.basis, origin.origin + shift)


## The parts of the player a seat moves, found from the camera the viewport is looking through.
class PlayerPieces extends RefCounted:
	var camera: Camera3D = null
	var origin: XROrigin3D = null
	var body: XRToolsPlayerBody = null

	static func find(from: Node) -> PlayerPieces:
		var pieces := PlayerPieces.new()
		pieces.camera = from.get_viewport().get_camera_3d() if from.is_inside_tree() else null
		if pieces.camera != null:
			pieces.origin = XRHelpers.get_xr_origin(pieces.camera)
			pieces.body = XRToolsPlayerBody.find_instance(pieces.camera)
		return pieces
