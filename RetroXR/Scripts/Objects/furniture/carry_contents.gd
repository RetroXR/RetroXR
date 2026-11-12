## CarryContents — what lies in a piece of furniture (in its drawers, on its shelf, on its top) stays there when the
## piece is picked up and moved, however fast.
##
## Two things, both measured (2026-11-12, docs/dev/furniture.md, vr_drawer_tests again/):
##   • CONTINUOUS COLLISION OFF while it lies in the piece. Every pickable has it on (HeldObjectPhysics, against throws
##     through the floor); a body that SETTLES with it on rests a few mm into the floor it lies on, and a drawer floor
##     lifting past ~1.3 m/s then outruns it (a TV remote dropped straight through). Off from the tick it arrives,
##     before it settles, physics carries it through a 2.5 m/s lift. It is given back the tick it leaves (taken out,
##     spilled, or picked up: a held body goes to the held layer, out of the bin's mask, with it on for the throw).
##   • LATCHED while the piece moves faster than physics can carry it: frozen kinematic, put where it lay in the piece
##     every tick, and let go with the piece's velocity at its place once the piece has slowed (or is put down). Each
##     thing latches at its own speed: its bin moving its THINNEST extent in a tick (a 7.5 mm Game Boy cartridge at
##     ~0.68 m/s fell through a 2.5 m/s lift a 30 mm box rode), never above LATCH_SPEED.
##
## Cheap when nothing happens: each bin is an Area3D, so Jolt's broadphase says what arrives and leaves (signals, no
## per-tick queries); `step()` is a few field reads unless the piece is HELD, and the latch reads the areas' lists.
##
## The owner calls `add_bin()` once per place it carries things, and `step()` from its _physics_process AFTER whatever
## moves it this tick (process_physics_priority above the grab driver's and the laser pickup's), every tick, with its
## own polled `held`; `release()` from _exit_tree. Only a body this froze is ever unfrozen, and only a body whose
## continuous collision this switched off ever gets it back.
class_name CarryContents
extends RefCounted

## Above this a thing is latched whatever its size (a swing, a teleport). CC_LATCH overrides it for testing.
var LATCH_SPEED := float(OS.get_environment("CC_LATCH")) if OS.has_environment("CC_LATCH") else 3.0
## Nothing latches below this, however thin.
const MIN_LATCH_SPEED := 0.4
## Let go again once every bin has been slower than this for UNLATCH_AFTER seconds.
const UNLATCH_SPEED := 0.3
const UNLATCH_AFTER := 0.2

## [{frame: Node3D, box: AABB, area: Area3D}], each box in its frame's own space (a drawer's inside rides its drawer
## body; a shelf or the top, the piece).
var bins: Array[Dictionary] = []

var _piece: RigidBody3D = null
## What lies in the bins now, by instance id: {body, n (how many bins it is in)}.
var _in: Dictionary = {}
## Bodies whose continuous collision this switched off, by instance id.
var _ccd_off: Dictionary = {}
## The piece's pose at the end of the last held tick: this tick's motion is measured from it, and the latched bodies'
## places are taken in it.
var _prev := Transform3D()
var _have_prev := false
## Latched bodies by instance id: {body, rel (its pose in the piece's frame), mode (its freeze_mode)}.
var _latched: Dictionary = {}
var _slow_for := 0.0
## Each body's thinnest extent (m), by instance id (_latch_speed).
var _thin: Dictionary = {}


## A place it carries things: `box` in `frame`'s space. `mask` is the layer what it carries is on.
func add_bin(piece: RigidBody3D, frame: Node3D, box: AABB, mask: int) -> void:
	_piece = piece
	var area := Area3D.new()
	area.name = "CarryBin%d" % bins.size()
	area.collision_layer = 0
	area.collision_mask = mask
	area.monitorable = false
	var shape := BoxShape3D.new()
	shape.size = box.size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = box.get_center()
	area.add_child(cs)
	frame.add_child(area)
	area.body_entered.connect(_on_entered)
	area.body_exited.connect(_on_exited)
	bins.append({"frame": frame, "box": box, "area": area})


func step(piece: RigidBody3D, held: bool, delta: float) -> void:
	var now := piece.global_transform
	if not held or delta <= 0.0 or not _have_prev:
		if not _latched.is_empty():
			_let_go_all(piece, now * _prev.affine_inverse() if _have_prev else Transform3D(), delta, "put down")
		# Its pose every tick it is NOT held: the first held tick's motion (the hold has already moved it) is from here.
		_prev = now
		_have_prev = true
		_slow_for = 0.0
		return
	if _in.is_empty() and _latched.is_empty():
		_prev = now
		return
	var motion := now * _prev.affine_inverse()
	var fastest := _fastest_bin(motion, delta)
	if fastest > MIN_LATCH_SPEED:
		_latch_new(piece, fastest, delta)
	if fastest > MIN_LATCH_SPEED and not _latched.is_empty():
		_slow_for = 0.0
	elif fastest < UNLATCH_SPEED:
		_slow_for += delta
	else:
		_slow_for = 0.0
	if not _latched.is_empty() and _slow_for >= UNLATCH_AFTER:
		_let_go_all(piece, motion, delta, "slowed to %.2f m/s" % fastest)
	_carry(now)
	_prev = now


## Let everything go and give back what was taken (the owner leaving the tree).
func release(piece: RigidBody3D) -> void:
	if not _latched.is_empty():
		_let_go_all(piece, Transform3D(), 0.0, "gone")
	for id: int in _ccd_off.keys():
		_give_ccd_back(id)
	_in.clear()


func _on_entered(node: Node3D) -> void:
	var rb := node as RigidBody3D
	if rb == null or rb == _piece:
		return
	var id := rb.get_instance_id()
	var row: Dictionary = _in.get(id, {"body": rb, "n": 0})
	row["n"] = int(row["n"]) + 1
	_in[id] = row
	if rb.continuous_cd and not _ccd_off.has(id) and not OS.has_environment("CC_NOCCD"):
		rb.continuous_cd = false
		_ccd_off[id] = rb
		print("[CarryContents] %s: %s in it (%.2f m/s); its continuous collision off while it lies there" % [
			_piece.name if is_instance_valid(_piece) else "?", rb.name, rb.linear_velocity.length()])


func _on_exited(node: Node3D) -> void:
	var rb := node as RigidBody3D
	if rb == null:
		return
	var id := rb.get_instance_id()
	if not _in.has(id):
		return
	var row: Dictionary = _in[id]
	row["n"] = int(row["n"]) - 1
	if int(row["n"]) > 0:
		return
	_in.erase(id)
	# A latched body never leaves (it is carried in place); one that does is no longer this piece's.
	_give_ccd_back(id)


func _give_ccd_back(id: int) -> void:
	if not _ccd_off.has(id):
		return
	var rb: Variant = _ccd_off[id]
	_ccd_off.erase(id)
	if is_instance_valid(rb):
		(rb as RigidBody3D).continuous_cd = true


## How fast the middle of the fastest bin moved this tick.
func _fastest_bin(motion: Transform3D, delta: float) -> float:
	var top := 0.0
	var back := motion.affine_inverse()
	for bin in bins:
		var frame := bin["frame"] as Node3D
		if not is_instance_valid(frame):
			continue
		var c := frame.global_transform * (bin["box"] as AABB).get_center()
		top = maxf(top, c.distance_to(back * c) / delta)
	return top


## Latch whatever lies in the bins, is not latched yet and is thin enough for this speed, where it lay in the piece
## before this tick's move (the piece has already been moved this tick; the things in it not yet).
func _latch_new(piece: RigidBody3D, speed: float, delta: float) -> void:
	var n := 0
	for id: int in _in.keys():
		if _latched.has(id):
			continue
		var rb: Variant = (_in[id] as Dictionary)["body"]
		if not is_instance_valid(rb):
			_in.erase(id)
			continue
		var b := rb as RigidBody3D
		# Frozen means somebody else owns its pose (a hand, a socket, the cartridge in a console in the drawer).
		if b.freeze or (b is XRToolsPickable and (b as XRToolsPickable).is_picked_up()):
			continue
		if speed < _latch_speed(b, delta):
			continue
		_latched[id] = {"body": b, "rel": _prev.affine_inverse() * b.global_transform, "mode": b.freeze_mode}
		b.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		b.freeze = true
		n += 1
	if n > 0:
		print("[CarryContents] %s: moving %.2f m/s, %d thing(s) in it latched (%d in all)" % [piece.name, speed, n,
			_latched.size()])


## The speed a body is latched at: its bin moving its own THINNEST extent in one tick, never above LATCH_SPEED.
func _latch_speed(rb: RigidBody3D, delta: float) -> float:
	var id := rb.get_instance_id()
	if not _thin.has(id):
		var thin := INF
		for owner_id in rb.get_shape_owners():
			var t := rb.shape_owner_get_transform(owner_id)
			for i in rb.shape_owner_get_shape_count(owner_id):
				var mesh := rb.shape_owner_get_shape(owner_id, i).get_debug_mesh()
				if mesh == null:
					continue
				var size := (t * mesh.get_aabb()).size
				thin = minf(thin, minf(size.x, minf(size.y, size.z)))
		_thin[id] = thin if thin < INF else 0.0
	return minf(LATCH_SPEED, float(_thin[id]) / maxf(delta, 0.0001))


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
