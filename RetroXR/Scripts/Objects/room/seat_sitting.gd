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
## puts it back. In a headset the head's height is the person's, and the origin is lifted or lowered ONCE, as they sit,
## so the head is at the seat's eye point (Seat.origin_at_eye_height); getting up puts the origin back on the floor.
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
## Where the host's eye point was when the player sat, or when the seat last moved them (follow).
var _last_eye := Vector3.ZERO


func _init(host: Node3D) -> void:
	_host = host


func is_occupied() -> bool:
	return Seat.current == _host


## Carry the player onto the host. False when there is no player to carry (no camera).
func sit() -> bool:
	var rig := Seat.PlayerPieces.find(_host)
	if rig.camera == null or rig.origin == null:
		push_warning("[Seat] %s: cannot sit (camera found=%s, origin found=%s)" % [_host.name, str(rig.camera != null), str(rig.origin != null)])
		return false
	if Seat.current != null and Seat.current != _host:
		print("[Seat] %s: leaving %s first" % [_host.name, Seat.current.name])
		Seat.current.call("stand")
	var eye: Transform3D = _host.call("eye_transform")
	var floor_y: float = _host.call("floor_y")
	_saved_camera_y = -1.0
	if not MenuStyle.is_vr_mode():
		# The desktop eye height is the camera's own height above the origin.
		_saved_camera_y = rig.camera.position.y
		rig.camera.position.y = eye.origin.y - floor_y
		print("[Seat] %s: desktop eye height %.2f m -> %.2f m (the floor under it at %.2f)" % [_host.name, _saved_camera_y, eye.origin.y - floor_y, floor_y])
	rig.origin.global_transform = Seat.origin_for_eye(rig.origin.global_transform, rig.camera.global_transform, eye, floor_y)
	if MenuStyle.is_vr_mode():
		# The head goes to the seat's eyes, whatever height the person really is at (Seat.origin_at_eye_height).
		var before := rig.camera.global_position.y
		rig.origin.global_transform = Seat.origin_at_eye_height(rig.origin.global_transform, rig.camera.global_transform, eye.origin.y)
		print("[Seat] %s: head from %.2f m to the seat's eyes at %.2f m (the floor under it at %.2f)" % [_host.name, before, eye.origin.y, floor_y])
	_pin = rig.origin.global_position
	_last_eye = eye.origin
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
	print("[Seat] %s: stood up" % _host.name)
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


## The seat has moved under the player (a cockpit on a base that tilts with the play, ArcadeControlModule): the head goes where the eye point went.
## The origin is carried by the same move and pinned there; only the position, because the base turns a few degrees and the view must not turn with
## it. The host calls this from its physics process, before `pin()`.
func follow() -> void:
	if _rig == null or not is_instance_valid(_rig.origin):
		return
	var eye: Vector3 = (_host.call("eye_transform") as Transform3D).origin
	var d := eye - _last_eye
	if d.length_squared() < 1.0e-10:
		return
	_last_eye = eye
	_rig.origin.global_position += d
	_pin += d
	_put_body_under_camera(_rig)


## The room is being changed: the player keeps no seat (the next room has none of these). Only the claim is dropped;
## the rig puts the body away and back itself (PlayerRig.leave_world).
func release() -> void:
	print("[Seat] %s: released for a room change" % _host.name)
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
		push_warning("[Seat] %s: locomotion not %s: the seat is not in the tree" % [_host.name, "held" if on else "freed"])
		return
	var loco := _host.get_tree().root.find_child("LocomotionManager", true, false) as LocomotionManager
	if loco == null:
		push_warning("[Seat] %s: no LocomotionManager: locomotion not %s" % [_host.name, "held" if on else "freed"])
		return
	if on:
		loco.set_block(Seat.BLOCK_OWNER, LocomotionManager.CHANNEL_ALL, true)
		loco.set_block(Seat.BLOCK_OWNER, LocomotionManager.CHANNEL_DESKTOP_MOVE, true)
	else:
		loco.clear_owner(Seat.BLOCK_OWNER)
