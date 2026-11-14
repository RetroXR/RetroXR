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
##
## GETTING UP is onto the host's stand point only when there is somewhere to stand there (`stand_spot`): a stand point
## is beside the seat, and a seat pushed up to a wall had it past the wall, out of the room, where no floor is: the
## player fell forever (2026-11-15). A seat knocked over or held in a hand cannot be sat on at all.
class_name SeatSitting
extends RefCounted

signal seated_changed(on: bool)

## A seat tipped further than this off upright (25 degrees, as a cosine) is not sat on: its eye point is sideways, and
## the stand point turned with it, into the floor or up in the air.
const UPRIGHT_MIN_COS := 0.906
## How far from the seat's eyes a stand-up spot other than the stand point is tried, at least.
const STAND_TRY_MIN := 0.6
## The body's room tried at a stand-up spot: a capsule this tall, from just over the floor.
const STAND_ROOM_HEIGHT := 1.4
const STAND_ROOM_LIFT := 0.05
## The height the way out to a stand-up spot is looked along for a wall, over the floor.
const STAND_PATH_HEIGHT := 1.0

var _host: Node3D
## Where the origin was put when the player sat: held there every physics frame while they are in it.
var _pin := Vector3.ZERO
## The player's pieces as found when they sat, so the per-frame pin does not search the tree.
var _rig: Seat.PlayerPieces = null
## The desktop camera's height before sitting set it, to put back; negative when it was not touched.
var _saved_camera_y := -1.0
## Where the host's eye point was when the player sat, or when the seat last moved them (follow).
var _last_eye := Vector3.ZERO
## The floor under the seat when the player sat: the floor to get up onto if the seat has since been knocked over.
var _floor_at_sit := 0.0


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
	if not is_upright():
		print("[Seat] %s: not sat on: it is tipped over (up %s)" % [_host.name, str(_host.global_basis.y.normalized())])
		return false
	if is_held():
		# The seat would move with the hand while the player stayed pinned where they sat down.
		print("[Seat] %s: not sat on: it is held" % _host.name)
		return false
	if Seat.current != null and Seat.current != _host:
		print("[Seat] %s: leaving %s first" % [_host.name, Seat.current.name])
		Seat.current.call("stand")
	var eye: Transform3D = _host.call("eye_transform")
	var floor_y: float = _host.call("floor_y")
	_floor_at_sit = floor_y
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
		var stand_at := stand_spot(rig.body)
		rig.origin.global_transform = Seat.origin_for_stand(rig.origin.global_transform, rig.camera.global_transform, stand_at)
		# The desktop camera is back up at standing height: the body's capsule is made that tall at once. Grown into
		# (player_height_rate) it was short for a few ticks, so the body hung over the floor under the view and fell,
		# taking the view down 5-10 cm and leaving it 7 mm under the floor (2026-11-15).
		if rig.body != null and rig.body.has_method("snap_height"):
			rig.body.snap_height()
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
	# The body under a pinned origin is often off the floor (a headset's origin lifted to the seat's eyes): it would
	# fall, gathering speed for as long as the player sat (20 m/s after two seconds).
	if _rig.body != null and is_instance_valid(_rig.body):
		_rig.body.velocity = Vector3.ZERO


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


## Whether the host stands near enough upright to sit on.
func is_upright() -> bool:
	return _host.global_basis.y.normalized().dot(Vector3.UP) >= UPRIGHT_MIN_COS


## The pickable the host is or is part of (a Seat; a cockpit's cabinet), or null.
func _pickable() -> XRToolsPickable:
	var n: Node = _host
	while n != null:
		if n is XRToolsPickable:
			return n as XRToolsPickable
		n = n.get_parent()
	return null


## Whether the host, or the thing it is part of, is in a hand.
func is_held() -> bool:
	var p := _pickable()
	return p != null and p.is_picked_up()


## Where getting up puts the feet. The host's stand point when there is somewhere to stand there; else the first of its
## mirror across the seat, in front of the eyes, behind them and to either side that has the way there clear of walls,
## room for the body (clear of the seat itself too) and a floor under it. With nowhere that has all three, the first
## with room and a floor, then the first with a floor; with no floor found anywhere (a room-less test) the stand point,
## as it always was. A seat knocked over since the player sat gets up onto the floor it stood on then.
func stand_spot(body: XRToolsPlayerBody = null) -> Vector3:
	var primary: Vector3 = _host.call("stand_point")
	if not _host.is_inside_tree():
		return primary
	var upright := is_upright()
	var floor_at := primary.y if upright else _floor_at_sit
	var eye: Transform3D = _host.call("eye_transform")
	var centre := Vector3(eye.origin.x, floor_at, eye.origin.z)
	var fwd := -eye.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized() if fwd.length_squared() > 1.0e-6 else Vector3.FORWARD
	var side := fwd.cross(Vector3.UP).normalized()
	var reach := maxf(Vector2(primary.x - centre.x, primary.z - centre.z).length(), STAND_TRY_MIN) if upright else STAND_TRY_MIN * 1.5
	var tries: Array[Vector3] = []
	if upright:
		tries.append(Vector3(primary.x, floor_at, primary.z))
		# The other side of the seat: the stand point mirrored across the seat's own middle.
		var local := _host.to_local(primary)
		var mirrored := _host.to_global(Vector3(-local.x, local.y, local.z))
		tries.append(Vector3(mirrored.x, floor_at, mirrored.z))
	for d: Vector3 in [fwd, -fwd, side, -side]:
		tries.append(centre + d * reach)
	var space := _host.get_world_3d().direct_space_state
	var mask := body.collision_mask if body != null else 1
	var radius := body.player_radius if body != null else 0.2
	var seat := _pickable()
	var exclude: Array[RID] = []
	if body != null:
		exclude.append(body.get_rid())
	var with_room := Vector3.INF
	var with_floor := Vector3.INF
	for i in tries.size():
		var p := tries[i]
		var ground := _floor_under(space, p, mask, exclude)
		if is_nan(ground):
			continue
		var at := Vector3(p.x, ground, p.z)
		var room := _room_at(space, at, radius, mask | (seat.collision_layer if seat != null else 0), exclude)
		var path := room and _path_clear(space, centre, at, mask, exclude)
		if room and path:
			if i > 0:
				print("[Seat] %s: no room at the stand point %s: getting up at %s instead" % [_host.name, str(primary), str(at)])
			return at
		if room and with_room == Vector3.INF:
			with_room = at
		if with_floor == Vector3.INF:
			with_floor = at
	if with_room != Vector3.INF:
		return with_room
	if with_floor != Vector3.INF:
		return with_floor
	return primary if upright else Vector3(primary.x, _floor_at_sit, primary.z)


## The height of the floor under `p`, looked for half a metre over and under it, or NAN when there is none.
static func _floor_under(space: PhysicsDirectSpaceState3D, p: Vector3, mask: int, exclude: Array[RID]) -> float:
	var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 0.5, p + Vector3.DOWN * 0.5, mask, exclude)
	var hit := space.intersect_ray(q)
	if hit.is_empty() or (hit["normal"] as Vector3).y < 0.7:
		return NAN
	return (hit["position"] as Vector3).y


## Whether a standing body fits at `at` (a floor point): nothing in a capsule from just over the floor.
static func _room_at(space: PhysicsDirectSpaceState3D, at: Vector3, radius: float, mask: int, exclude: Array[RID]) -> bool:
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = STAND_ROOM_HEIGHT
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = capsule
	q.transform = Transform3D(Basis.IDENTITY, at + Vector3.UP * (STAND_ROOM_LIFT + STAND_ROOM_HEIGHT * 0.5))
	q.collision_mask = mask
	q.exclude = exclude
	return space.intersect_shape(q, 1).is_empty()


## Whether the way from the seat's eyes out to `at` is clear at waist height (no wall between).
static func _path_clear(space: PhysicsDirectSpaceState3D, from: Vector3, at: Vector3, mask: int, exclude: Array[RID]) -> bool:
	var up := Vector3.UP * STAND_PATH_HEIGHT
	var q := PhysicsRayQueryParameters3D.create(from + up, at + up, mask, exclude)
	return space.intersect_ray(q).is_empty()


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
