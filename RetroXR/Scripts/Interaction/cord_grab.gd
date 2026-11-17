class_name CordGrab
extends Node
## A hand on a cable, anywhere along it (rope.md "A hand on the cord").
##
## A cord has no body: nothing a pickup's sphere or a pointer's ray can find. So
## it is found by DISTANCE, to the hand in a headset and to the crosshair's ray at
## a desk, and only when that hand has nothing else to take: a pickable or a
## widget in reach always wins, and the pickup is asked before the cord is.
##
##   headset  GRIP beside a cord takes it where the hand is; letting go drops it
##            moving as the hand was.
##   desk     a left click on a cord takes it, on the ray at the distance it was;
##            the wheel brings it nearer or sends it away; the next click lets go.
##
## What is held is ONE particle of the rope (VerletRope.hold_point): a pin like
## the cord's own ends. The hand is never held back: carried further than the
## cord reaches from an end that cannot move, the cord stretches, as it does
## behind a held plug, and stays outside what it is hooked round (the rope's
## KeepTautOutside). What is loose on an end (a plug, a pad) hangs from the
## cord by the point the cord leaves it (a length limit: `_hang`).
##
## Local and cosmetic: nothing is saved and nothing is sent in a session.

## How near a hand, or a desk's crosshair ray, must be to a cord's middle line
## to take it, metres. One figure for both.
const REACH := 0.02
## A desk reaches as far as its pickup does.
const DESK_MAX_DIST := 5.0
const DESK_MIN_DIST := 0.15
const DESK_SCROLL_STEP := 0.05
## A cord over its length comes back this share of the excess a tick, and no
## faster than HANG_RETURN_MAX metres a second.
const HANG_RETURN := 0.2
## This close to its full length the cord is already bearing the weight.
const HANG_BEARING := 0.003
const HANG_RETURN_MAX := 3.0
## Further over its length than this, what hangs is moved, not pulled.
const HANG_SLIP := 0.15
const GRIP_ON := 0.6
const GRIP_OFF := 0.4
const GRIP_ACTION := "grip"
## The "you could take this" mark is looked for this often, not every frame.
const HOVER_INTERVAL := 0.1
## A desk click's key in `_holds`; a headset hand's is its controller's id.
const DESK_KEY := -1
static var instance: CordGrab

class Hold:
	var rope: Node3D
	var index: int
	## Cord between the hold and the start, and the trunk's whole length, metres.
	var along: float
	var length: float
	var pickup: Node
	## Desk only: how far down the crosshair's ray it is held.
	var dist: float

var _holds: Dictionary = {}
var _grip_down: Dictionary = {}
var _marks: Dictionary = {}
var _ropes: Array[Node] = []
var _ropes_known := false
var _hover_clock := 0.0


func _enter_tree() -> void:
	instance = self


func _exit_tree() -> void:
	release_all()
	if instance == self:
		instance = null
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)
	# A room change takes the player's rig out of the old room and seats it in
	# the new one: this node leaves the tree and comes back. What it knew is
	# the old room's cords, and it must look and listen again. (Left "known",
	# it never reconnected, and no cord in any room after the first could be
	# taken until the app was restarted.)
	_ropes_known = false
	_ropes.clear()
	_grip_down.clear()
	print("[CordGrab] left the tree: the room's cords are looked for afresh on return")


# ── the cords in the room ─────────────────────────────────────────────────────

func _all_ropes() -> Array[Node]:
	if not _ropes_known:
		_ropes_known = true
		_ropes.clear()
		if ClassDB.class_exists("VerletRope"):
			_ropes.assign(get_tree().root.find_children("*", "VerletRope", true, false))
		get_tree().node_added.connect(_on_node_added)
	return _ropes


func _on_node_added(node: Node) -> void:
	if node.is_class("VerletRope") and not _ropes.has(node):
		_ropes.append(node)


## The takeable spot nearest `point` within `reach`, as VerletRope.closest_point
## answers it plus "rope"; empty when there is none.
func nearest_to_point(point: Vector3, reach: float) -> Dictionary:
	var best := {}
	var best_d := reach
	for k in range(_all_ropes().size() - 1, -1, -1):
		var rope: Node = _ropes[k]
		if not is_instance_valid(rope):
			_ropes.remove_at(k)
			continue
		if not _takeable(rope):
			continue
		var hit: Dictionary = rope.closest_point(point)
		if int(hit.get("index", -1)) < 0 or float(hit.distance) > best_d:
			continue
		best_d = float(hit.distance)
		best = hit
		best["rope"] = rope
	return best


## The same down a ray. A cord behind something solid is not taken.
func nearest_to_ray(origin: Vector3, dir: Vector3, max_dist: float) -> Dictionary:
	var best := {}
	var best_d := REACH
	for k in range(_all_ropes().size() - 1, -1, -1):
		var rope: Node = _ropes[k]
		if not is_instance_valid(rope):
			_ropes.remove_at(k)
			continue
		if not _takeable(rope):
			continue
		var hit: Dictionary = rope.closest_point_to_ray(origin, dir, max_dist)
		if int(hit.get("index", -1)) < 0:
			continue
		var d := float(hit.distance)
		if d > best_d:
			continue
		best_d = d
		best = hit
		best["rope"] = rope
	if best.is_empty():
		return best
	var world := _world()
	if world != null:
		var to: Vector3 = best.position
		var q := PhysicsRayQueryParameters3D.create(origin, to)
		var blocked := world.direct_space_state.intersect_ray(q)
		if not blocked.is_empty() and origin.distance_to(blocked.position) < origin.distance_to(to) - 0.05:
			return {}
	return best


func _takeable(rope: Node) -> bool:
	return rope.is_inside_tree() and (rope as Node3D).is_visible_in_tree() \
			and rope.has_method("hold_point")


func _world() -> World3D:
	var vp := get_viewport()
	return vp.find_world_3d() if vp != null else null


# ── taking, carrying, letting go ──────────────────────────────────────────────

func is_holding(key: int) -> bool:
	return _holds.has(key)


## Take `rope` at particle `index` for `key`, the hand at `point`.
func take(key: int, rope: Node3D, index: int, point: Vector3, pickup: Node = null) -> bool:
	if _holds.has(key):
		release(key)
	if not is_instance_valid(rope) or not rope.hold_point(index, rope.point_position(index)):
		print("[CordGrab] %s refused a hand at particle %d" % [_name_of(rope), index])
		return false
	var h := Hold.new()
	h.rope = rope
	h.index = index
	h.along = float(index) * float(rope.get_segment_length())
	h.length = float(rope.get_segment_count()) * float(rope.get_segment_length())
	h.pickup = pickup
	_holds[key] = h
	if is_instance_valid(pickup):
		# The hand is full: it takes nothing else while it has the cord.
		pickup.set("enabled", false)
	print("[CordGrab] took %s at particle %d (%.2f m along %.2f m)%s" % [
			_name_of(rope), index, h.along, h.length, " at the desk" if key == DESK_KEY else ""])
	carry(key, point)
	return true


## Move a held cord's hand to `point`, as near as the cord allows.
func carry(key: int, point: Vector3) -> void:
	var h: Hold = _holds.get(key)
	if h == null:
		return
	if not is_instance_valid(h.rope) or not h.rope.is_held(h.index):
		# Freed, or laid afresh too short to keep the hold.
		release(key)
		return
	h.rope.move_hold(h.index, point)


func release(key: int) -> void:
	var h: Hold = _holds.get(key)
	if h == null:
		return
	_holds.erase(key)
	if is_instance_valid(h.rope):
		h.rope.release_hold(h.index)
	if is_instance_valid(h.pickup):
		h.pickup.set("enabled", true)
	print("[CordGrab] let go of %s" % _name_of(h.rope))


func release_all() -> void:
	for key: int in _holds.keys():
		release(key)


## The free rigid body `end` is or rides on, null when the end cannot be pulled.
func _loose_body(end: Node) -> RigidBody3D:
	var n := end
	while n != null:
		if n is RigidBody3D:
			var body := n as RigidBody3D
			return null if body.freeze else body
		n = n.get_parent()
	return null


func _physics_process(_delta: float) -> void:
	# What is loose on the end of a held cord HANGS from it. It is hauled by
	# the point the cord leaves it (`_hang`: an impulse there, which the
	# body's own inertia turns into the tip and the swing), not reeled in: a
	# reel is a move with no turn in it, and a pad lifted by its wire rose
	# level off the floor, as if on a tray.
	for key: int in _holds:
		var h: Hold = _holds[key]
		if not is_instance_valid(h.rope):
			continue
		var hand: Vector3 = h.rope.point_position(h.index)
		var last := int(h.rope.get_segment_count())
		_hang(_loose_body(h.rope.get_start_node()), _end_point(h.rope, true, 0), hand, h.along)
		_hang(_loose_body(h.rope.get_end_node()), _end_point(h.rope, false, last), hand, h.length - h.along)


## Where the cord leaves what is on its end, NOW. The rope's own end particle
## is where that was when the rope last ticked: a tick stale, and a limit
## worked out from a stale place pushes a hanging pad a little every tick.
func _end_point(rope: Node3D, at_start: bool, index: int) -> Vector3:
	var end: Node3D = rope.get_start_node() if at_start else rope.get_end_node()
	if not is_instance_valid(end):
		return rope.point_position(index)
	var offset: Vector3 = rope.get("start_anchor_offset" if at_start else "end_anchor_offset")
	return end.global_transform * offset


func _hang(body: RigidBody3D, at: Vector3, hand: Vector3, reach: float) -> void:
	if body == null or reach <= 0.0 or not at.is_finite() or not hand.is_finite():
		return
	# A cord is a LIMIT on how far the point it leaves the body by may be from
	# the hand, and it only ever pulls. So when it is taut, exactly the speed
	# that would stretch it further is taken out of that point, with the pull
	# a real cord would give: one impulse along the cord, sized by how the body
	# answers there (its mass AND how readily it turns about that point).
	#
	# It was a spring first (CableHaul: an impulse for every metre over-long),
	# which bounced for good, and then a spring with a damper sized by the
	# mass alone. A pad's cord leaves by its edge, where it answers a push far
	# more readily than its mass says, so the damper overdid it every tick and
	# the pad fought itself in the air.
	var out := at - hand
	var d := out.length()
	var over := d - reach
	# Within a hair of taut it is already bearing: there the cord only stops
	# the point going further out, every tick, as a cord holding a weight does.
	# Acting only once it was over-long, it was on one tick and off the next
	# (gravity lengthens it, the pull shortens it), and a pad that had come to
	# rest was set wobbling again by the pulses.
	if over <= -HANG_BEARING or d < 0.0001:
		return
	out /= d
	var state := PhysicsServer3D.body_get_direct_state(body.get_rid())
	if state == null:
		return
	# (Its centre of mass is given from the body's origin, in the world's axes.)
	var arm := at - (body.global_position + state.center_of_mass)
	var speed := (state.linear_velocity + state.angular_velocity.cross(arm)).dot(out)
	# Back to its length over a few ticks, not in one (that is a kick).
	var dt := maxf(get_physics_process_delta_time(), 0.001)
	var wanted := -minf(maxf(over, 0.0) * HANG_RETURN / dt, HANG_RETURN_MAX)
	if speed <= wanted:
		return
	var turn := arm.cross(out)
	var answer := state.inverse_mass + turn.dot(state.inverse_inertia_tensor * turn)
	if answer <= 0.0:
		return
	body.apply_impulse(out * ((wanted - speed) / answer), at - body.global_position)
	# Far past its length (a hand moved faster than any pull can answer): the
	# rest is taken out by hand, swept so nothing is carried through a wall.
	if over > HANG_SLIP:
		var hit := body.move_and_collide(out * -(over - HANG_SLIP))
		if hit != null:
			body.move_and_collide(hit.get_remainder().slide(hit.get_normal()))


# ── hands ─────────────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	_hover_clock += delta
	var look := _hover_clock >= HOVER_INTERVAL
	if look:
		_hover_clock = 0.0
	var vp := get_viewport()
	if vp != null and vp.use_xr:
		_process_headset(look)
	else:
		_process_desk(look)


func _process_headset(look: bool) -> void:
	_mark(DESK_KEY, {})
	for ctrl: Node in XrControllers.all(get_tree()):
		var xr := ctrl as XRController3D
		if xr == null:
			continue
		var key := xr.get_instance_id()
		var pickup := xr.get_node_or_null("FunctionPickup")
		var hand: Vector3 = (pickup as Node3D).global_position if pickup is Node3D else xr.global_position
		var grip := xr.get_float(GRIP_ACTION) if xr.get_is_active() else 0.0
		var was: bool = _grip_down.get(key, false)
		var down := grip > (GRIP_OFF if was else GRIP_ON)
		_grip_down[key] = down
		if _holds.has(key):
			_mark(key, {})
			if down:
				carry(key, hand)
			else:
				release(key)
			continue
		if not _hand_free(pickup):
			_mark(key, {})
			continue
		if down and not was:
			var hit := nearest_to_point(hand, REACH)
			if not hit.is_empty():
				take(key, hit.rope, int(hit.index), hand, pickup)
				_mark(key, {})
		elif look:
			_mark(key, {} if down else nearest_to_point(hand, REACH))


## A hand that has nothing, and nothing else in reach or under its laser.
func _hand_free(pickup: Node) -> bool:
	if pickup == null or not pickup.get("enabled"):
		return false
	if is_instance_valid(pickup.get("picked_up_object")) or is_instance_valid(pickup.get("closest_object")):
		return false
	if is_instance_valid(pickup.get("_pointer_highlighted")):
		return false
	return not (pickup.has_method("is_ray_grabbing") and pickup.is_ray_grabbing())


func _process_desk(look: bool) -> void:
	var cam := _desk_camera()
	if cam == null:
		return
	if _holds.has(DESK_KEY):
		_mark(DESK_KEY, {})
		var h: Hold = _holds[DESK_KEY]
		carry(DESK_KEY, cam.global_position - cam.global_transform.basis.z * h.dist)
	elif look:
		var hit := {}
		if not cam.is_holding() and not cam.aimed_target().can_grab:
			hit = nearest_to_ray(cam.global_position, -cam.global_transform.basis.z, DESK_MAX_DIST)
		_mark(DESK_KEY, hit)


func _desk_camera() -> DesktopPickup:
	# The desk pickup is the script on the rig's camera.
	var vp := get_viewport()
	var cam: Node = vp.get_camera_3d() if vp != null else null
	return cam as DesktopPickup


## A desk click that found nothing to pick up: is there a cord under it?
func desk_click(origin: Vector3, dir: Vector3) -> bool:
	var hit := nearest_to_ray(origin, dir, DESK_MAX_DIST)
	if hit.is_empty():
		return false
	var at: Vector3 = hit.position
	if not take(DESK_KEY, hit.rope, int(hit.index), at):
		return false
	(_holds[DESK_KEY] as Hold).dist = clampf(float(hit.ray_distance), DESK_MIN_DIST, DESK_MAX_DIST)
	return true


func desk_holding() -> bool:
	return _holds.has(DESK_KEY)


func desk_release() -> void:
	release(DESK_KEY)


## The wheel, while a cord is held: nearer (-1) or further (+1).
func desk_scroll(steps: int) -> void:
	var h: Hold = _holds.get(DESK_KEY)
	if h != null:
		h.dist = clampf(h.dist + DESK_SCROLL_STEP * steps, DESK_MIN_DIST, DESK_MAX_DIST)


# ── the mark ──────────────────────────────────────────────────────────────────

## A pale bead on the cord where `key`'s hand would take it; `hit` empty hides it.
func _mark(key: int, hit: Dictionary) -> void:
	var bead: MeshInstance3D = _marks.get(key)
	if hit.is_empty():
		if is_instance_valid(bead):
			bead.visible = false
		return
	if not is_instance_valid(bead):
		bead = MeshInstance3D.new()
		var ball := SphereMesh.new()
		ball.radius = 1.0
		ball.height = 2.0
		ball.radial_segments = 12
		ball.rings = 6
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(1, 1, 1, 0.55)
		ball.material = mat
		bead.mesh = ball
		bead.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bead.top_level = true
		add_child(bead)
		_marks[key] = bead
	var rope: Node3D = hit.rope
	var r := maxf(float(rope.get_tube_radius()) * 2.2, 0.006)
	bead.global_transform = Transform3D(Basis().scaled(Vector3(r, r, r)), hit.position)
	bead.visible = true


func _name_of(rope: Node) -> String:
	if not is_instance_valid(rope):
		return "a cord that is gone"
	var p := rope.get_parent()
	return "%s/%s" % [p.name if p != null else &"", rope.name]
