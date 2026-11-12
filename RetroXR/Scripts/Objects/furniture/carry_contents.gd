## CarryContents — what lies in a held piece of furniture (in its drawers, on its shelf, on its top) stays there however
## fast the piece is moved: while the piece moves fast, its contents are LATCHED to it (frozen where they lie, carried as
## part of it); moving slowly, and put down, they are ordinary physics again.
##
## Why not physics all the way: every pickable has continuous collision on (HeldObjectPhysics, against throws through
## the floor), settles a few mm INTO a floor and stays there, and a drawer floor lifting faster than about 1.2-1.3 m/s
## then outruns it: a TV remote dropped straight through. A hold moves a piece as fast as a hand (the pull-in starts at
## 2.5 m/s; a desktop turn swings a chest at metres a second), and walls cutting through a box in one tick threw it
## 100 m. Cancelling damping, switching continuous collision off, a deeper floor: none of it carried them
## (2026-11-12, furniture.md). Holding the piece to 1 m/s did, and was a piece that cannot keep up with a walk.
##
## The owner calls `step()` from its _physics_process AFTER whatever moves it this tick (its process_physics_priority
## above the grab driver's and the laser pickup's), every tick, held or not; `held` is its own polled answer.
## Only a body this froze is ever unfrozen, and every latch is let go when the piece is put down or leaves the tree.
class_name CarryContents
extends RefCounted

## Fastest a bin may move (m/s, at its middle) with what is in it left to physics; latched above it.
## 3 m/s: below it, what is in it is carried by physics (its continuous collision is off, _watch_ccd); above it, a swing
## or a teleport, no physics could follow. CC_LATCH overrides it for testing.
var LATCH_SPEED := float(OS.get_environment("CC_LATCH")) if OS.has_environment("CC_LATCH") else 3.0
## Let go again once every bin has been slower than this for UNLATCH_AFTER seconds.
const UNLATCH_SPEED := 0.3
const UNLATCH_AFTER := 0.2

## Where it carries things: [{frame: Node3D, box: AABB}], each box in its frame's own space (a drawer's inside rides its
## drawer body; a shelf or the top, the piece).
var bins: Array[Dictionary] = []

## The piece's pose at the end of the last tick: what this tick's motion is measured from, and the frame the latched
## bodies' places were taken in.
var _prev := Transform3D()
var _have_prev := false
## Latched bodies by instance id: {body, rel (its pose in the piece's frame), freeze_mode}.
var _latched: Dictionary = {}
var _slow_for := 0.0
var _query := PhysicsShapeQueryParameters3D.new()
var _query_box := BoxShape3D.new()


func step(piece: RigidBody3D, held: bool, delta: float) -> void:
	if not OS.has_environment("CC_NOCCD"):
		_watch_ccd(piece)
	var now := piece.global_transform
	if not held or delta <= 0.0 or not _have_prev:
		if not _latched.is_empty():
			_let_go_all(piece, now * _prev.affine_inverse() if _have_prev else Transform3D(), delta, "put down")
		_prev = now
		_have_prev = true
		_slow_for = 0.0
		return
	var motion := now * _prev.affine_inverse()
	var fastest := _fastest_bin(motion, delta)
	if fastest > LATCH_SPEED:
		_slow_for = 0.0
		_latch_new(piece, fastest)
	elif fastest < UNLATCH_SPEED:
		_slow_for += delta
	else:
		_slow_for = 0.0
	if not _latched.is_empty() and _slow_for >= UNLATCH_AFTER:
		_let_go_all(piece, motion, delta, "slowed to %.2f m/s" % fastest)
	_carry(now)
	_prev = now


## Let everything go now (the owner leaving the tree).
func release(piece: RigidBody3D) -> void:
	if not _latched.is_empty():
		_let_go_all(piece, Transform3D(), 0.0, "gone")


## How fast the middle of the fastest bin moved this tick.
func _fastest_bin(motion: Transform3D, delta: float) -> float:
	var top := 0.0
	for bin in bins:
		var frame := bin["frame"] as Node3D
		if not is_instance_valid(frame):
			continue
		var c := frame.global_transform * (bin["box"] as AABB).get_center()
		# `c` is where the middle is now: where it was is the motion undone.
		var was := motion.affine_inverse() * c
		top = maxf(top, c.distance_to(was) / delta)
	return top


## Latch whatever lies in a bin and is not latched yet. Queried where the bins WERE (the piece has already been moved
## this tick, the things in it not yet), and each is put where it lay relative to the piece then.
func _latch_new(piece: RigidBody3D, speed: float) -> void:
	if bins.is_empty() or not piece.is_inside_tree():
		return
	var space := piece.get_world_3d().direct_space_state
	var back := _prev * piece.global_transform.affine_inverse()
	_query.shape = _query_box
	_query.collision_mask = piece.original_collision_layer if piece.original_collision_layer != 0 else 4
	_query.collide_with_areas = false
	var n := 0
	for bin in bins:
		var frame := bin["frame"] as Node3D
		if not is_instance_valid(frame):
			continue
		var box: AABB = bin["box"]
		_query_box.size = box.size
		_query.transform = back * frame.global_transform * Transform3D(Basis(), box.get_center())
		for hit in space.intersect_shape(_query, 32):
			var rb := hit.get("collider") as RigidBody3D
			if rb == null or rb == piece or _latched.has(rb.get_instance_id()):
				continue
			# Frozen means somebody else owns its pose (a hand, a socket, the cartridge in a console in the drawer).
			if rb.freeze or (rb is XRToolsPickable and (rb as XRToolsPickable).is_picked_up()):
				continue
			_latched[rb.get_instance_id()] = {"body": rb, "rel": _prev.affine_inverse() * rb.global_transform,
				"mode": rb.freeze_mode}
			rb.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			rb.freeze = true
			n += 1
	if n > 0:
		print("[CarryContents] %s: moving %.2f m/s, %d thing(s) in it latched (%d in all)" % [piece.name, speed, n,
			_latched.size()])


## Put every latched body where it lay in the piece, now. One a hand has taken out meanwhile is its holder's.
func _carry(now: Transform3D) -> void:
	for id: int in _latched.keys():
		var row: Dictionary = _latched[id]
		var rb: Variant = row["body"]
		if not is_instance_valid(rb):
			_latched.erase(id)
			continue
		var b := rb as RigidBody3D
		if b is XRToolsPickable and (b as XRToolsPickable).is_picked_up():
			# Taken by a hand: its hold restores it when it lets go. Not ours to touch again.
			b.freeze_mode = row["mode"]
			_latched.erase(id)
			print("[CarryContents] %s was taken out of it while latched" % b.name)
			continue
		var at: Transform3D = now * (row["rel"] as Transform3D)
		b.global_transform = at
		PhysicsServer3D.body_set_state(b.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, at)


## Unfreeze every latched body, moving as the piece moves where it is (no jolt).
func _let_go_all(piece: RigidBody3D, motion: Transform3D, delta: float, why: String) -> void:
	var n := 0
	for id: int in _latched.keys():
		var row: Dictionary = _latched[id]
		var rb: Variant = row["body"]
		if not is_instance_valid(rb):
			continue
		var b := rb as RigidBody3D
		b.freeze = false
		b.freeze_mode = row["mode"]
		if delta > 0.0:
			var p := b.global_position
			b.linear_velocity = (p - motion.affine_inverse() * p) / delta
		b.angular_velocity = Vector3.ZERO
		b.sleeping = false
		n += 1
	_latched.clear()
	_slow_for = 0.0
	print("[CarryContents] %s: %s; %d thing(s) let go to ordinary physics" % [piece.name, why, n])


## TRIAL (2026-11-12, on by default; CC_NOCCD=1 turns it off): whatever arrives in a bin has its continuous collision
## switched off at once, while it is still moving, before it settles, and given back as it leaves. A body that SETTLED
## with it on rests a few mm into the floor and a floor lifting past ~1.3 m/s outruns it; switched off as it arrives,
## physics carries it through a 2.5 m/s lift (vr_drawer_tests again/).
var _ccd_off: Dictionary = {}

func _watch_ccd(piece: RigidBody3D) -> void:
	if bins.is_empty() or not piece.is_inside_tree():
		return
	var space := piece.get_world_3d().direct_space_state
	_query.shape = _query_box
	_query.collision_mask = piece.original_collision_layer if piece.original_collision_layer != 0 else 4
	_query.collide_with_areas = false
	var found := {}
	for bin in bins:
		var frame := bin["frame"] as Node3D
		if not is_instance_valid(frame):
			continue
		var box: AABB = bin["box"]
		_query_box.size = box.size
		_query.transform = frame.global_transform * Transform3D(Basis(), box.get_center())
		for hit in space.intersect_shape(_query, 32):
			var rb := hit.get("collider") as RigidBody3D
			if rb == null or rb == piece:
				continue
			found[rb.get_instance_id()] = true
			if rb.continuous_cd and not _ccd_off.has(rb.get_instance_id()):
				rb.continuous_cd = false
				_ccd_off[rb.get_instance_id()] = rb
				print("[CarryContents] %s: %s arrived moving %.2f m/s; continuous collision off" % [piece.name, rb.name,
					rb.linear_velocity.length()])
	for id: int in _ccd_off.keys():
		if found.has(id):
			continue
		var rb: Variant = _ccd_off[id]
		if is_instance_valid(rb):
			(rb as RigidBody3D).continuous_cd = true
		_ccd_off.erase(id)
