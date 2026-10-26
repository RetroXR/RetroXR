## Vanish — shrink an object away, then free it.
##
## Deleting a world object used to be instantaneous: the frame a pickable was
## released into the storage box it simply stopped existing, which reads as a
## glitch rather than as a deletion. Everything the player can delete goes
## through here instead, so the object collapses to nothing over a third of a
## second and is freed at the end of that.
##
## The caller keeps its own teardown. This replaces the TERMINAL queue_free()
## and nothing else — a system is still powered off, foreign captive plugs are
## still released and owned cables are still freed, all before the shrink
## starts. Cables themselves are NOT routed through here: a VerletRope is a
## native particle sim rather than a mesh, and scaling its anchor does not read
## as the cord shrinking.
##
## Bulk teardown (SceneManager clearing a room, ObjectSync clearing the world)
## deliberately still frees on the spot — an animation there would leave the
## outgoing room's nodes racing the incoming one's.
class_name Vanish
extends Object

const DURATION := 0.3

## Earth gravity, so the drop reads as a real fall rather than a slide. Godot's
## own default 3D gravity, not a number picked to look right.
const FALL_GRAVITY := 9.8

## Marks a node already on its way out. Both the storage box's overlap poll and
## a snap zone can reach the same object, and the second call must be a no-op
## rather than a second tween fighting the first.
const META := "vanishing"

## Set while a whole room is being torn down. Bulk teardown reaches the same
## drop_and_free() every deleted object does, and there an animation would leave
## the outgoing room's nodes alive for a third of a second, racing the incoming
## room's — so while this is up, free_node() frees on the spot. Always restore it
## in the same function that raised it.
static var instant := false

## Where the objects freed inside an exit-style scope go while they shrink.
## FALL is the default: down through the floor. SHRINK stays put — the item
## menu's Delete, where nothing was let go of, so nothing should drop. INTO
## heads for a point — the corner trash can's mouth, so the object is seen going
## into the can.
enum Exit { FALL, SHRINK, INTO }

## Set only for the length of shrink_in_place() / shrink_into(). Deleting one
## object reaches free_node() from many places — every drop_and_free() ends in
## one, and what is snapped into it goes too — so the style is a scope around
## the delete rather than a parameter threaded through all of them.
static var _exit := Exit.FALL
static var _into: Node3D = null


## Run `delete` with every object it frees shrinking where it stands.
static func shrink_in_place(delete: Callable) -> void:
	_scoped(Exit.SHRINK, null, delete)


## Run `delete` with every object it frees shrinking toward `target` (followed
## while it moves, so the can can be carried along with the menu).
static func shrink_into(target: Node3D, delete: Callable) -> void:
	_scoped(Exit.INTO, target, delete)


static func _scoped(exit: Exit, target: Node3D, delete: Callable) -> void:
	var was_exit := _exit
	var was_into := _into
	_exit = exit
	_into = target
	delete.call()
	_exit = was_exit
	_into = was_into


## True once free_node() has taken this object. Callers that walk a set of
## objects can use it to skip one that is already going.
static func is_vanishing(node: Node) -> bool:
	return is_instance_valid(node) and node.has_meta(META)


## Shrink `node` to nothing and free it. Safe to call twice. Anything without a
## transform has no scale to shrink and is simply freed.
static func free_node(node: Node, duration: float = DURATION) -> void:
	if not is_instance_valid(node) or node.is_queued_for_deletion():
		return
	if node.has_meta(META):
		return
	var spatial := node as Node3D
	if spatial == null or instant:
		node.queue_free()
		return
	spatial.set_meta(META, true)

	# Nothing may touch it while it shrinks: it must not be grabbed again, and it
	# must not be re-detected by the box that is deleting it.
	_neutralise(spatial)

	# Created from the node, so the tween dies with it if something frees the
	# object out from under us anyway.
	var tween := spatial.create_tween()
	tween.set_parallel(true)
	tween.tween_property(spatial, "scale", Vector3.ONE * 0.001, duration) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)

	var start := spatial.global_position
	match _exit:
		Exit.SHRINK:
			pass
		Exit.INTO:
			# Toward the target's mouth, easing in like the shrink so the two land
			# together: most of the travel comes as the object is already small.
			var target := _into
			# Boxed: a lambda's captured local is a copy, so the mouth's last known place
			# has to live in something it shares or a freed target snaps back to the first.
			var last: Array[Vector3] = [target.global_position if is_instance_valid(target) else start]
			tween.tween_method(func(t: float) -> void:
				if not is_instance_valid(spatial):
					return
				if is_instance_valid(target):
					last[0] = target.global_position
				var k := Tween.interpolate_value(0.0, 1.0, t, duration,
					Tween.TRANS_CUBIC, Tween.EASE_IN_OUT) as float
				spatial.global_position = start.lerp(last[0], k),
				0.0, duration, duration)
		_:
			# And it falls while it goes, instead of hanging in the air.
			#
			# Integrated here rather than handed back to the physics server, which is
			# not a preference: a RigidBody's transform is written from the server
			# every tick and that transform carries no scale, so an unfrozen body
			# would have the shrink wiped out from under it each frame. The body
			# stays frozen and the drop is authored — real gravity, from a standing
			# start, which over the 0.3 s of the animation is about 0.44 m.
			#
			# It keeps no collision (see _neutralise), so it falls THROUGH the box's
			# base and the floor rather than landing on them. That is the point:
			# something being deleted should sink out of the world, not settle onto
			# it.
			tween.tween_method(func(t: float) -> void:
				if not is_instance_valid(spatial):
					return
				spatial.global_position = start - Vector3(0.0, 0.5 * FALL_GRAVITY * t * t, 0.0),
				0.0, duration, duration)

	tween.finished.connect(func() -> void:
		if is_instance_valid(spatial):
			_bury(spatial))


# ── Freeing a little at a time ────────────────────────────────────────────────
#
# Freeing a machine on the spot cost ~2 ms in one frame on a desktop (an N64:
# 175 nodes, 17 bodies), a third of it leaving the tree and two thirds the free
# itself — on a Quest's CPU, a dropped frame every time something was deleted.
# The tree exit stays in one piece: it is what tells everyone the object is gone
# (ObjectSync's tree_exiting despawn, the "spawned" group the save reads, every
# _exit_tree that unplugs a cable). What is left after it is a detached subtree
# nothing can reach, and that is taken apart over the following frames instead,
# a millisecond of it per frame, children first.

## Wall-clock budget per frame for freeing detached nodes, in microseconds.
const REAP_BUDGET_USEC := 1000

static var _graveyard: Array[Node] = []
static var _reaping := false


## Take `node` out of the tree now, and free it over the next frames.
static func _bury(node: Node) -> void:
	var parent := node.get_parent()
	if parent == null:
		node.queue_free()
		return
	var tree := node.get_tree()
	parent.remove_child(node)
	if tree == null:
		node.free()
		return
	_graveyard.append(node)
	if not _reaping:
		_reaping = true
		tree.process_frame.connect(_reap)


static func _reap() -> void:
	var start := Time.get_ticks_usec()
	while not _graveyard.is_empty() and Time.get_ticks_usec() - start < REAP_BUDGET_USEC:
		var node: Node = _graveyard.back()
		if not is_instance_valid(node):
			_graveyard.pop_back()
			continue
		var n := node.get_child_count()
		if n > 0:
			# Children first, one subtree at a time: unhooking a child from a parent
			# that is out of the tree is cheap, and each lands on the pile itself.
			var child := node.get_child(n - 1)
			node.remove_child(child)
			_graveyard.append(child)
			continue
		_graveyard.pop_back()
		node.free()
	if _graveyard.is_empty():
		_reaping = false
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null and tree.process_frame.is_connected(_reap):
			tree.process_frame.disconnect(_reap)


## Take the object out of the simulation without stopping its processing — a
## tween created from a node is governed by that node's process mode, so
## disabling it would stall the shrink half way.
static func _neutralise(node: Node3D) -> void:
	var body := node as RigidBody3D
	if body != null:
		body.freeze = true
	# Deferred: a release can land inside a physics callback, where changing a
	# body's layers is not allowed.
	for child in _self_and_descendants(node):
		var col := child as CollisionObject3D
		if col != null:
			col.set_deferred("collision_layer", 0)
			col.set_deferred("collision_mask", 0)
		var area := child as Area3D
		if area != null:
			area.set_deferred("monitoring", false)
			area.set_deferred("monitorable", false)
		# Shapes off too, not just their layers: the shrink rescales the body every
		# frame, and a shape it still has is rebuilt at the new scale each time.
		var shape := child as CollisionShape3D
		if shape != null:
			shape.set_deferred("disabled", true)


static func _self_and_descendants(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	out.append_array(node.find_children("*", "", true, false))
	return out
