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
## The sitting itself (the pose, the pin, the camera's height, the locomotion block) is SeatSitting, which a sit-down
## driving cabinet's own seat (CockpitSeat) uses as well; this is the furniture: a thing you carry about.
##
## The scenes are baked by Tools/gen/gen_seats.gd; a mod's seat is any scene with this script
## and an `EyePoint` and a `StandPoint` marker.
class_name Seat
extends XRToolsPickable

signal seated_changed(on: bool)

## Every seat joins this, so a sweep can find them without testing the class.
const GROUP := "seat"
const BLOCK_OWNER := &"seat"

## The seat the player is in (a Seat or a CockpitSeat), or null. One player, one seat.
static var current: Node = null

## The ScenePersistence PLAIN_SCENES key this scene is saved and spawned under.
@export var type_id := "seat_chair"

var _sitting: SeatSitting


func _init() -> void:
	_sitting = SeatSitting.new(self)
	_sitting.seated_changed.connect(func(on: bool) -> void: seated_changed.emit(on))


func _ready() -> void:
	super._ready()
	add_to_group("spawned")
	add_to_group(GROUP)
	picked_up.connect(func(_p: Variant) -> void:
		stand()
		_show_facing_arrow())
	dropped.connect(func(_p: Variant) -> void: _hide_facing_arrow())
	set_physics_process(false)
	# The seat's body answers a press by standing the sitter up (SeatPointerArea).
	var pointer_body := get_node_or_null("PointerArea") as StaticBody3D
	if pointer_body != null and pointer_body.get_script() == null:
		pointer_body.set_script(SeatPointerArea)


func _exit_tree() -> void:
	# Taken out of the room (put away, a mod unloaded) with the player in it: let go.
	if current == self:
		stand()


func _physics_process(_delta: float) -> void:
	if current != self:
		set_physics_process(false)
		return
	_sitting.pin()


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


## The sitting (SeatSitting.release reaches a seat through this).
func sitting() -> SeatSitting:
	return _sitting


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


## The height of the floor under the seat: its own origin stands on it.
func floor_y() -> float:
	return global_position.y


## Carry the player onto this seat. False when there is no player to carry (no camera).
func sit() -> bool:
	return _sitting.sit()


## Let the player up, onto the StandPoint. Does nothing when this is not the seat they are in.
func stand() -> void:
	_sitting.stand()


## The room is being changed: whoever sits keeps no seat (the next room has none of these). Only
## the claim is dropped; the rig puts the body away and back itself (PlayerRig.leave_world).
static func release_all() -> void:
	if current == null:
		return
	var seat := current
	current = null
	var sitting := seat.call("sitting") as SeatSitting
	if sitting != null:
		sitting.release()


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


## IN A HEADSET, the origin lifted or lowered so the HEAD is at `eye_y` (the seat's eye point, in the world), once, as the player sits. The head is the person's own, wherever they really are: standing, on
## a low real chair, on the floor. The first version left it where it was ("somebody sitting on a real chair is already at that height") and put the floor under the SEAT, so a person sitting low sat on the
## floor beside a stool whose top was at their eyes (2026-10-29). A person who really sits at the seat's height moves a few centimetres at most.
static func origin_at_eye_height(origin: Transform3D, camera: Transform3D, eye_y: float) -> Transform3D:
	return Transform3D(origin.basis, origin.origin + Vector3(0.0, eye_y - camera.origin.y, 0.0))


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
