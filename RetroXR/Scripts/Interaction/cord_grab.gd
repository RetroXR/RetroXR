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
## KeepTautOutside). An end that is a loose plug is reeled along behind
## (PlugTether, as every lead does).
##
## Local and cosmetic: nothing is saved and nothing is sent in a session.

## How near a hand, or a desk's crosshair ray, must be to a cord's middle line
## to take it, metres. One figure for both.
const REACH := 0.02
## A desk reaches as far as its pickup does.
const DESK_MAX_DIST := 5.0
const DESK_MIN_DIST := 0.15
const DESK_SCROLL_STEP := 0.05
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
	# A loose plug on a held cord follows it, as it follows its own lead.
	for key: int in _holds:
		var h: Hold = _holds[key]
		if not is_instance_valid(h.rope):
			continue
		var hand: Vector3 = h.rope.point_position(h.index)
		var last := int(h.rope.get_segment_count())
		var body := _loose_body(h.rope.get_start_node())
		if body != null:
			PlugTether.reel_in(body, h.rope.point_position(0), hand, h.along)
		body = _loose_body(h.rope.get_end_node())
		if body != null:
			PlugTether.reel_in(body, h.rope.point_position(last), hand, h.length - h.along)


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
