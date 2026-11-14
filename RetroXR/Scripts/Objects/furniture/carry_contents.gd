## CarryContents — what lies in a piece of furniture (in its drawers, on its shelf, on its top) is HELD IN PLACE while
## the whole piece is carried, and is ordinary physics again the moment it is put down. Sliding a drawer with the piece
## standing is not a carry: what is in the drawer rides and jostles by physics as it always did.
##
## One rule, chosen 2026-11-14 over what it replaced (docs/dev/furniture.md has the history): physics alone cannot carry
## things in a piece moved as fast as a hand moves it (a pickable settles a few mm into a floor and a floor lifting past
## ~1.3 m/s outruns it; a quarter swing's walls cut through a box in one tick), and the stack of fixes that let it try
## (a speed and thickness threshold, continuous collision switched off, lids) was harder to trust than this.
##
## Each place it carries things is a bin, an Area3D, so Jolt reports what arrives and leaves (no per-tick queries; an
## idle piece costs nothing). The tick the piece is first held (its hold is POLLED by the owner: a ray grab emits no
## picked_up), everything in a bin is latched: frozen kinematic, put on the held layer (it passes through what the
## carried piece passes through, and pushes nothing in the room), and put where it lay in the piece every tick. A thing
## let go into or over the piece mid-carry is ordinary physics. Put down, each is let go with the piece's velocity at its place, on its
## own layer and mask again. Only a body this froze is ever unfrozen; one a hand takes out mid-carry is the hand's.
##
## The owner calls `add_bin()` once per place, `step()` from its _physics_process AFTER whatever moves it this tick
## (process_physics_priority above the grab driver's and the laser pickup's), every tick, with its own polled `held`,
## and `release()` from _exit_tree.
class_name CarryContents
extends RefCounted

## [{frame: Node3D, box: AABB, area: Area3D}], each box in its frame's own space (a drawer's inside rides its drawer
## body; a shelf or the top, the piece).
var bins: Array[Dictionary] = []

var _piece: RigidBody3D = null
## What lies in the bins now, by instance id: {body, n (how many bins it is in)}.
var _in: Dictionary = {}
## The piece's pose at the end of the last tick: the first held tick's move (the hold has already moved it) is measured
## from here, and a latched body's place is taken in it.
var _prev := Transform3D()
var _have_prev := false
## Held since the carry began (the latch is taken on its first tick only).
var _carrying := false
## Latched bodies by instance id: {body, rel (its pose in the piece), mode, layer, mask}.
var _latched: Dictionary = {}


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
	if not held or not _have_prev:
		_carrying = false
		if not _latched.is_empty():
			_let_go_all(piece, now * _prev.affine_inverse() if _have_prev else Transform3D(), delta, "put down")
		_prev = now
		_have_prev = true
		return
	# What is in it when the carry BEGINS is held; a thing let go into or over it mid-carry is ordinary physics (latched
	# as it arrived, one let go over the top was frozen hanging in the air where the hand let go of it).
	if not _carrying:
		_carrying = true
		_latch_new(piece)
	_carry(now)
	_prev = now


## Let everything go (the owner leaving the tree).
func release(piece: RigidBody3D) -> void:
	if not _latched.is_empty():
		_let_go_all(piece, Transform3D(), 0.0, "gone")
	_in.clear()


## Whether a body is held in place by this piece now (for a test or a probe).
func is_latched(body: Node) -> bool:
	return body != null and _latched.has(body.get_instance_id())


func _on_entered(node: Node3D) -> void:
	var rb := node as RigidBody3D
	if rb == null or rb == _piece:
		return
	var id := rb.get_instance_id()
	var row: Dictionary = _in.get(id, {"body": rb, "n": 0})
	row["n"] = int(row["n"]) + 1
	_in[id] = row


func _on_exited(node: Node3D) -> void:
	var rb := node as RigidBody3D
	if rb == null:
		return
	var id := rb.get_instance_id()
	if not _in.has(id):
		return
	var row: Dictionary = _in[id]
	row["n"] = int(row["n"]) - 1
	if int(row["n"]) <= 0:
		_in.erase(id)


## Latch whatever lies in the bins and is not latched yet, where it lay in the piece before this tick's move (the piece
## has already been moved this tick; the things in it not yet).
func _latch_new(piece: RigidBody3D) -> void:
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
		if b.freeze or _taken(b):
			continue
		_latched[id] = {"body": b, "rel": _prev.affine_inverse() * b.global_transform, "mode": b.freeze_mode,
			"layer": b.collision_layer, "mask": b.collision_mask}
		b.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		b.freeze = true
		b.collision_layer = piece.picked_up_layer
		b.collision_mask = 0
		n += 1
	if n > 0:
		print("[CarryContents] %s: carried; %d thing(s) in it held in place (%d in all)" % [piece.name, n,
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
		if _taken(b):
			# Taken by a hand or a laser. Its hold recorded the freeze IT found (ours) and would put it back on release,
			# leaving the thing frozen in the air: it is told to let it go loose. Its layers are the hold's own (it gives
			# back the pickable's original ones); only the freeze mode is ours to give back. Not ours to touch again.
			(b as XRToolsPickable).restore_freeze = false
			b.freeze_mode = row["mode"]
			_latched.erase(id)
			print("[CarryContents] %s was taken out of it while carried" % b.name)
			continue
		var at: Transform3D = now * (row["rel"] as Transform3D)
		b.global_transform = at
		PhysicsServer3D.body_set_state(b.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, at)


## A latched pickable a hand has picked up or a laser holds.
func _taken(b: RigidBody3D) -> bool:
	var p := b as XRToolsPickable
	if p == null:
		return false
	if p.is_picked_up():
		return true
	for pickup in b.get_tree().get_nodes_in_group(XRToolsFunctionPickup.PICKUP_GROUP):
		if pickup.has_method("is_ray_grabbing_target") and pickup.is_ray_grabbing_target(p):
			return true
	return false


func _restore(b: RigidBody3D, row: Dictionary) -> void:
	b.freeze_mode = row["mode"]
	b.collision_layer = row["layer"]
	b.collision_mask = row["mask"]


## Let every latched body go, moving as the piece moves where it is (no jolt).
func _let_go_all(piece: RigidBody3D, motion: Transform3D, delta: float, why: String) -> void:
	var n := 0
	for id: int in _latched.keys():
		var row: Dictionary = _latched[id]
		var rb: Variant = row["body"]
		if not is_instance_valid(rb):
			continue
		var b := rb as RigidBody3D
		b.freeze = false
		_restore(b, row)
		if delta > 0.0:
			var p := b.global_position
			b.linear_velocity = (p - motion.affine_inverse() * p) / delta
		b.angular_velocity = Vector3.ZERO
		b.sleeping = false
		n += 1
	_latched.clear()
	print("[CarryContents] %s: %s; %d thing(s) in it let go to ordinary physics" % [piece.name, why, n])
