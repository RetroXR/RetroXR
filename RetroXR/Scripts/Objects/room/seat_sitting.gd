## SeatSitting — a player sitting down on a seat and getting up again: the half of a seat that is not the furniture.
##
## One per seat, made by the seat itself (`Seat`, the furniture you carry about; `CockpitSeat`, the one a sit-down
## driving cabinet is built with). The host is any Node3D that answers `eye_transform()` (where the head goes, -Z the
## way it faces), `stand_point()` (a floor point to get up onto) and `floor_y()` (the height of the floor under the
## seat), and that calls `pin()` from its physics process while `Seat.current` is itself. What sitting does, and why
## (seats.md "What sitting does"):
##
## The origin is turned about the head to the seat's heading and carried over the eye point, standing on the seat's
## floor, then PINNED there every physics frame. Walking, teleporting and snap-turning are held back
## (LocomotionManager). Looking round stays free: the head in VR, the mouse on the desktop. THE PLAYER BODY STAYS ON:
## godot-xr-tools runs every movement provider from inside the body's physics step and skips them all when it is
## disabled, which takes the desktop's mouse-look with it and leaves the player unable to turn to the seat to get up.
##
## HEIGHT. On the desktop the camera's own height is the eye height, so sitting sets it to the seat's and getting up
## puts it back. In a headset the head's height is the person's: the floor is put under the seat and the head is left
## where it is (somebody sitting on a real chair is already at that height).
class_name SeatSitting
extends RefCounted

signal seated_changed(on: bool)

var _host: Node3D
## Where the origin was put when the player sat: held there every physics frame while they are in it.
var _pin := Vector3.ZERO
## The player's pieces as found when they sat, so the per-frame pin does not search the tree.
var _rig: Seat.PlayerPieces = null
## The desktop camera's height before sitting set it, to put back; negative when it was not touched.
var _saved_camera_y := -1.0


func _init(host: Node3D) -> void:
	_host = host


func is_occupied() -> bool:
	return Seat.current == _host


## Carry the player onto the host. False when there is no player to carry (no camera).
func sit() -> bool:
	var rig := Seat.PlayerPieces.find(_host)
	if rig.camera == null or rig.origin == null:
		return false
	if Seat.current != null and Seat.current != _host:
		Seat.current.call("stand")
	var eye: Transform3D = _host.call("eye_transform")
	var floor_y: float = _host.call("floor_y")
	_saved_camera_y = -1.0
	if not MenuStyle.is_vr_mode():
		# The desktop eye height is the camera's own height above the origin.
		_saved_camera_y = rig.camera.position.y
		rig.camera.position.y = eye.origin.y - floor_y
	rig.origin.global_transform = Seat.origin_for_eye(rig.origin.global_transform, rig.camera.global_transform, eye, floor_y)
	_pin = rig.origin.global_position
	_rig = rig
	_put_body_under_camera(rig)
	_block_locomotion(true)
	Seat.current = _host
	_host.set_physics_process(true)
	seated_changed.emit(true)
	return true


## Let the player up, onto the host's stand point. Does nothing when this is not the seat they are in.
func stand() -> void:
	if Seat.current != _host:
		return
	Seat.current = null
	_host.set_physics_process(false)
	var rig := _rig if _rig != null and is_instance_valid(_rig.origin) else Seat.PlayerPieces.find(_host)
	_rig = null
	_block_locomotion(false)
	if rig.camera != null and rig.origin != null:
		if _saved_camera_y >= 0.0:
			rig.camera.position.y = _saved_camera_y
		var stand_at: Vector3 = _host.call("stand_point")
		rig.origin.global_transform = Seat.origin_for_stand(rig.origin.global_transform, rig.camera.global_transform, stand_at)
		_put_body_under_camera(rig)
	_saved_camera_y = -1.0
	seated_changed.emit(false)


## Whatever moved the origin since the last frame (a provider that was not held back, the body being pushed) is
## undone: the head is free, the body is not. The host calls this from its physics process.
func pin() -> void:
	if _rig == null or not is_instance_valid(_rig.origin):
		return
	if _rig.origin.global_position.distance_squared_to(_pin) > 1.0e-6:
		_rig.origin.global_position = _pin


## The room is being changed: the player keeps no seat (the next room has none of these). Only the claim is dropped;
## the rig puts the body away and back itself (PlayerRig.leave_world).
func release() -> void:
	_host.set_physics_process(false)
	_block_locomotion(false)
	if _saved_camera_y >= 0.0 and _rig != null and is_instance_valid(_rig.camera):
		_rig.camera.position.y = _saved_camera_y
	_rig = null
	_saved_camera_y = -1.0
	seated_changed.emit(false)


## The body is put on the floor under the head where the player now is, as a teleport does, or it would sweep there
## from where it was, through whatever is between.
func _put_body_under_camera(rig: Seat.PlayerPieces) -> void:
	if rig.body == null or rig.camera == null or rig.origin == null:
		return
	var head := rig.camera.global_position
	rig.body.global_position = Vector3(head.x, rig.origin.global_position.y, head.z)
	rig.body.velocity = Vector3.ZERO


func _block_locomotion(on: bool) -> void:
	if not _host.is_inside_tree():
		return
	var loco := _host.get_tree().root.find_child("LocomotionManager", true, false) as LocomotionManager
	if loco == null:
		return
	if on:
		loco.set_block(Seat.BLOCK_OWNER, LocomotionManager.CHANNEL_ALL, true)
		loco.set_block(Seat.BLOCK_OWNER, LocomotionManager.CHANNEL_DESKTOP_MOVE, true)
	else:
		loco.clear_owner(Seat.BLOCK_OWNER)
