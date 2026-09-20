## HeldObjectPhysics — a held object passes through the world, and gets pushed
## back out if you let go of it inside something.
##
## Two halves, both applied to every pickable as it enters the tree, the same way
## VRKeyboardFix and TypingGuard reach every text field.
##
## ── Passing through while held ────────────────────────────────────────────────
## xr-tools already sets a held object's collision_mask to 0 and moves it to
## picked_up_layer (17, "XRHand_SnapZone"). That is only half the job: Godot
## registers a contact when EITHER body's mask matches the other's layer, and
## every pickable in this project masks 196613 — World, Pickable, SnapZone(17)
## and XRHand_Physics. Bit 17 is exactly the layer the thing in your hand just
## moved to, so loose objects went on colliding with it from their side.
##
## Clearing that bit is what actually stops it. Only PhysicsBody3D masks are
## touched: snap zones are Area3Ds and detect on their own mask (65540), so they
## still see a held object and keep working.
##
## ── Escaping on release ───────────────────────────────────────────────────────
## Because a held object passes through everything, you can let go of one while
## it is inside a shelf or a cabinet. Dropping it there would either wedge it or
## fire it across the room as the solver resolves the overlap. Instead it steps
## out toward the player, still passing through, and only rejoins the simulation
## once it is clear — so the thing it was inside is never touched.
##
## The question that drives it is "is this buried in immovable world geometry?",
## and both halves of that are load-bearing — measured, not assumed:
##
##   * WORLD ONLY. Every shelf, wall, table and cabinet is a StaticBody3D at the
##     default layer 1. A pickable overlapping a pickable is never a wedge: it is
##     either deliberate (media seated in a slot, a plug in its socket, both held
##     open by a collision exception a shape query cannot see) or two loose bodies
##     the solver separates by itself. Asking about everything instead shoved a Wii
##     0.22 m at the player for the disc inside it.
##   * BURIED, NOT TOUCHING. intersect_shape cannot tell the two apart — a console
##     settled on a table and one released inside a shelf both come back as one
##     hit. Their contact DEPTHS are 0.000 m and 0.053 m, so collide_shape can.
class_name HeldObjectPhysics
extends Node

## Bit 17, "XRHand_SnapZone" — XRToolsPickable.DEFAULT_LAYER, where a held object
## lives for as long as it is held.
const HELD_BIT := 1 << 16

## Bit 1, "World" — the room itself. See the header: the only thing worth
## escaping from.
const WORLD_BIT := 1

## Contact shallower than this is resting ON something rather than buried IN it.
## Measured: settled on a table 0.000 m, released inside a shelf 0.053 m.
const BURIED_DEPTH := 0.005

## Contact pairs sampled per query. A box has four corners in a face contact;
## anything past this is already far past the depth test.
const MAX_CONTACTS := 8

## Metres per step while escaping, how far it may travel, and the cap on steps so
## a bad query can never spin.
const STEP := 0.02
const MAX_TRAVEL := 0.6
const MAX_STEPS := int(MAX_TRAVEL / STEP)

# ── Falling out of the world ──────────────────────────────────────────────────
# Every room puts the top of its floor slab at y = 0, so anything this far under
# it has left through the floor or over an edge and is never coming back.
const FALL_LIMIT_Y := -2.0

## Rate the fall check runs at. A falling object is recovered wherever it got to,
## so this needs no precision — and at 60-120 Hz, per-frame checks on every
## pickable in the room would be pure waste.
const FALL_CHECK_HZ := 4.0

## An object is "at rest" — and so worth remembering as a safe spot — below this
## speed. Squared, to keep the check off sqrt.
const AT_REST_SPEED2 := 0.01

## How far below a rider to look for the thing it was standing on, and the cap on
## bodies one query answers with. Contact is touching, so the probe is slack for a
## support being carried gently downward rather than a reach.
const SUPPORT_PROBE := 0.03
const MAX_RIDERS := 8

## How far under the support's top face a body's underside may be and still count
## as standing ON it rather than merely touching it. Without this test a shelf of
## objects pressed against each other all come back as riders, and coupling those
## would let a held object shove its neighbours aside — the exact bulldozing the
## pass-through at the top of this file exists to stop.
const RIDER_SEAT_SLACK := 0.02

## Rate the rider watch runs at. A rider drops one tick after its support clears,
## and 20 Hz is inside a frame or two at any headset rate.
const RIDER_CHECK_HZ := 20.0

## Every layer but the held one — what a rider can be, which is anything that is
## not itself in a hand. Masked to 32 bits: collision_mask is a uint32, and the
## bare ~ leaves a negative int.
const NOT_HELD_MASK := 0xFFFFFFFF & ~HELD_BIT

## Clear of the floor by this much before a pose counts as safe, so a body that
## has already begun sinking into geometry is never recorded as somewhere to
## return to.
const SAFE_MIN_Y := 0.02

var _fall_timer := 0.0
## Every pickable in the tree, and the last pose each was seen resting at.
## Keyed by instance id so a freed object cannot resurrect one.
var _watched: Dictionary = {}
var _safe_pose: Dictionary = {}

var _rider_timer := 0.0
## Bodies that were standing on something now held, and the thing each was
## standing on: {rider instance id: [rider, support]}.
var _riders: Dictionary = {}


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	_patch_tree(get_tree().root)
	# This autoload is where the hint rows for every pickable are declared, so it
	# is also where the panel's one-time cost is paid — otherwise the first grab of
	# the session wears it. Deferred because it adds a node to the root, and the
	# root is mid-setup while an autoload readies. See HeldHint.warm.
	_warm_hint.call_deferred()


func _warm_hint() -> void:
	if AppPrefs.show_hints:
		HeldHint.warm(get_tree().root)


func _on_node_added(node: Node) -> void:
	_patch(node)


func _patch_tree(root: Node) -> void:
	_patch(root)
	for c in root.get_children():
		_patch_tree(c)


func _patch(node: Node) -> void:
	var body := node as PhysicsBody3D
	if body != null and (body.collision_mask & HELD_BIT) != 0:
		# Before _ready, so XRToolsPickable's @onready original_collision_mask
		# captures the cleared value and a drop restores the cleared value too.
		body.collision_mask &= ~HELD_BIT

	var pickable := node as XRToolsPickable
	if pickable != null:
		_watched[pickable.get_instance_id()] = pickable
		# No pickable in this project had continuous collision detection, so a
		# hard throw could step straight through the 0.2 m floor slab in one
		# tick. A ray-thrown object is the worst case by far: swung at arm's
		# length on a 3 m beam it leaves the hand several times faster than the
		# hand ever moved.
		pickable.continuous_cd = true
	if pickable != null and not pickable.dropped.is_connected(_on_dropped):
		pickable.dropped.connect(_on_dropped)
	if pickable != null and not pickable.picked_up.is_connected(_on_picked_up):
		pickable.picked_up.connect(_on_picked_up)

	# A ray grab never creates a GrabDriver, so the pickable's own picked_up never
	# fires for one — the ray-only rows have to come off the pickup instead.
	var pickup := node as XRToolsFunctionPickup
	if pickup != null:
		if not pickup.has_picked_up.is_connected(_on_pickup_grabbed):
			pickup.has_picked_up.connect(_on_pickup_grabbed.bind(pickup))
		if not pickup.has_transferred.is_connected(_on_pickup_transferred):
			pickup.has_transferred.connect(_on_pickup_transferred.bind(pickup))


# ── Teaching the rotate verbs ─────────────────────────────────────────────────
# Every pickable can be turned while you hold it, and nothing says so. Taught
# here rather than in each object's script for the same reason the collision
# fix is: this autoload already sees every pickable as it enters the tree.

## Desktop: middle-mouse drag rotates (Kenney names the middle button by its
## wheel, hence mouse_scroll_outline), and Shift swaps its horizontal axis from
## yaw to roll. Vertical pitches either way — hence "pitch and yaw" / "pitch and
## roll" rather than one axis each. See desktop_pickup.gd.
const DESKTOP_ROTATE_GLYPHS: Array[String] = ["mouse_scroll_outline"]
const DESKTOP_ROLL_GLYPHS: Array[String] = ["keyboard_shift_outline", "mouse_scroll_outline"]
## VR: the FREE hand's thumbstick, and grip on that same hand for roll. Only
## while ray-grabbing — a direct hand grab is turned with your wrist, so the
## rows would be advertising a control that does nothing. See
## function_pickup._compute_ray_grab_rotation.
const VR_ROTATE_GLYPHS: Array[String] = ["quest_stick_l_press"]
const VR_ROLL_GLYPHS: Array[String] = ["quest_grip_left_outline", "quest_stick_l_press"]


func _on_picked_up(pickable: Variant) -> void:
	var obj := pickable as XRToolsPickable
	if obj == null or not is_instance_valid(obj):
		return
	# Before the desktop gate below: whatever was standing on this has just lost
	# its floor whichever way it was grabbed.
	watch_riders(obj)
	var by := obj.get_picked_up_by()
	# VR is driven off the pickup's own signals instead (see _apply_mode_rows) —
	# the rows differ between the hand hold and the ray hold, and only the pickup
	# knows which one is live.
	if not (is_instance_valid(by) and by.is_in_group("desktop_hand")):
		return

	var hint := HeldHint.for_node(obj)
	if hint == null:
		return
	hint.add_row(&"rotate_yaw", HeldHint.PLATFORM_DESKTOP, DESKTOP_ROTATE_GLYPHS,
		"Use {g} to pitch and yaw", HeldHint.WHEN_HELD)
	hint.add_row(&"rotate_roll", HeldHint.PLATFORM_DESKTOP, DESKTOP_ROLL_GLYPHS,
		"Use {g} to pitch and roll", HeldHint.WHEN_HELD)

	# Objects with a hint of their own call this from their own grab handler, and
	# a second call only rebuilds the same panel. Objects without one — a
	# cartridge, a disc — have nobody to call it, and these rows would never show.
	hint.on_grabbed(by)


## True when `by` is holding `obj` at the end of a laser rather than in the hand.
func _is_ray_grab(by: Node3D, obj: XRToolsPickable) -> bool:
	return is_instance_valid(by) \
		and by.has_method("is_ray_grabbing_target") \
		and by.call("is_ray_grabbing_target", obj)


## The push-out verb: only offered on objects that accept it, and only in VR.
## Unlike the rotate rows — which are the FREE hand and so hardcode left art —
## these are on the hand doing the holding, so they take the {side}/{s} tokens.
const VR_PUSH_GLYPHS: Array[String] = ["quest_trigger_{side}_outline", "quest_stick_{s}_press"]
## The catch: pull the stick to its edge and hold. Without this row an object
## parked at arm's length and refusing to come closer just reads as stuck.
const VR_CATCH_GLYPHS: Array[String] = ["quest_stick_{s}_press"]


func _on_pickup_grabbed(what: Variant, pickup: XRToolsFunctionPickup) -> void:
	var obj := what as XRToolsPickable
	if obj == null or not is_instance_valid(obj):
		return
	# The ray grab's only pickup signal — it never calls pick_up, so picked_up
	# does not fire for one. A hand grab reaches this twice and re-records the
	# same rows, which is what the second call already did for the hints.
	watch_riders(obj)
	_apply_mode_rows(obj, pickup, _is_ray_grab(pickup, obj))


func _on_pickup_transferred(what: Variant, to_ray: bool,
		pickup: XRToolsFunctionPickup) -> void:
	var obj := what as XRToolsPickable
	if obj == null or not is_instance_valid(obj):
		return
	_apply_mode_rows(obj, pickup, to_ray)


## Swap the rows that describe how the object is being held right now. Rotating
## with the free hand's stick only works off the laser; pushing out only works
## from the hand.
func _apply_mode_rows(obj: XRToolsPickable, pickup: XRToolsFunctionPickup,
		on_ray: bool) -> void:
	var hint := HeldHint.for_node(obj)
	if hint == null:
		return

	if on_ray:
		hint.remove_row(&"push_to_ray")
		hint.add_row(&"rotate_yaw", HeldHint.PLATFORM_VR, VR_ROTATE_GLYPHS,
			"Use {g} to pitch and yaw", HeldHint.WHEN_HELD)
		hint.add_row(&"rotate_roll", HeldHint.PLATFORM_VR, VR_ROLL_GLYPHS,
			"Use {g} to pitch and roll", HeldHint.WHEN_HELD)
		hint.add_row(&"catch_from_ray", HeldHint.PLATFORM_VR, VR_CATCH_GLYPHS,
			"Pull {g} all the way back and hold to catch it", HeldHint.WHEN_HELD)
	else:
		hint.remove_row(&"rotate_yaw")
		hint.remove_row(&"rotate_roll")
		hint.remove_row(&"catch_from_ray")
		if _accepts_push(obj):
			hint.add_row(&"push_to_ray", HeldHint.PLATFORM_VR, VR_PUSH_GLYPHS,
				"Hold {g} and push forward to send it to the beam", HeldHint.WHEN_HELD)

	hint.on_grabbed(pickup)


func _accepts_push(obj: XRToolsPickable) -> bool:
	if obj.has_method("wants_ray_handoff"):
		return obj.wants_ray_handoff()
	return true


# ── Escaping on release ───────────────────────────────────────────────────────

func _on_dropped(pickable: Variant) -> void:
	var body := pickable as XRToolsPickable
	if body != null:
		_escape.call_deferred(body)
		if body.is_in_group("hand_held_device"):
			_report_if_stuck(body, body.global_position)


## "Sometimes a controller will not drop, it just floats in the air" — reported
## from a headset 2026-09-20, rare and not reproducible on demand:
## Tools/vr/pad_drop_probe drives five release shapes (one hand, both hands
## either order, a release racing the toggle-hold re-grab, a release mid-lerp)
## and every one of them falls.
##
## From inside a headset every cause looks identical — a frozen body, a sleeping
## one, one whose gravity was left at zero and one a stale grab still owns all
## just hang there — so rather than guess, the next occurrence is made to say
## which it was, and who is holding it. WARN because that is the level that
## survives into logcat.
##
## Only hand-held devices, and only with nothing underneath: coming to rest on a
## table is the ordinary way to stop moving, and photographing that would bury
## the real thing in noise.
const STUCK_AFTER := 0.75
const STUCK_MOVED := 0.005
const STUCK_CLEARANCE := 0.15


func _report_if_stuck(body: XRToolsPickable, from: Vector3) -> void:
	await get_tree().create_timer(STUCK_AFTER).timeout
	if not is_instance_valid(body) or not body.is_inside_tree():
		return
	if body.global_position.distance_to(from) > STUCK_MOVED:
		return
	if not body.freeze and not body.sleeping and body.gravity_scale > 0.0 			and not body.is_picked_up():
		return
	var space := body.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		body.global_position, body.global_position + Vector3.DOWN * STUCK_CLEARANCE)
	query.exclude = [body.get_rid()]
	if not space.intersect_ray(query).is_empty():
		return          # resting on something, which is not this bug
	var held_by := "nobody"
	if body.is_picked_up() and is_instance_valid(body._grab_driver.primary):
		var who: Variant = body._grab_driver.primary.by
		held_by = "%s (%s)" % [who.name, who.get_class()] if is_instance_valid(who) 			else "a FREED grabber"
	push_warning(("[stuck] %s hung in the air %.2fs after release: freeze=%s " % [body.name, STUCK_AFTER, body.freeze])
		+ ("restore_freeze=%s sleeping=%s gravity_scale=%.2f " % [body.restore_freeze, body.sleeping, body.gravity_scale])
		+ ("picked_up=%s held_by=%s" % [body.is_picked_up(), held_by]))


func _escape(body: XRToolsPickable) -> void:
	if not is_instance_valid(body) or not body.is_inside_tree():
		return
	# A snap zone that claimed it on release has picked it up again; leaving is
	# the whole point of a slot, so nothing to escape from.
	if body.is_picked_up():
		return
	# Frozen means an owner has claimed the pose. MediaTray and MediaSlot drop the
	# zone's grab so they, not its grab driver, own the media, then seat it and
	# freeze it — and being inside the deck IS the seated pose. No solver acts on a
	# frozen body, so there is nothing to escape from. Same test the fall watch uses.
	# Still needed with the world-only query below: a disc seated in a console that
	# is pushed up against a bookcase really does overlap the world, and without
	# this the escape would drag it out of the machine.
	if body.freeze:
		return

	var cs := _first_shape(body)
	if cs == null:
		return
	# Sampled once, here: the loop below stomps the body's own mask to 0, and a
	# query built from it in there would ask about nothing at all.
	var world := body.collision_mask & WORLD_BIT
	# The shape's own transform, not the body's: a CollisionShape3D is usually
	# offset from its body's origin, and querying at the origin tests empty space.
	if world == 0 or not _buried(body, cs.shape, cs.global_transform, world):
		return

	var cam := body.get_viewport().get_camera_3d()
	if cam == null:
		return
	var dir := cam.global_position - body.global_position
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		dir = Vector3.BACK
	dir = dir.normalized()

	# Pass through for the whole escape, so the thing it was inside is never
	# pushed. Frozen too: the solver must not act on the overlap we are undoing.
	var layer := body.collision_layer
	var mask := body.collision_mask
	var frozen := body.freeze
	body.collision_layer = HELD_BIT
	body.collision_mask = 0
	body.freeze = true

	var probe := cs.global_transform
	var moved := 0.0
	for i in MAX_STEPS:
		probe.origin += dir * STEP
		moved += STEP
		if not _buried(body, cs.shape, probe, world):
			break
	var t := body.global_transform
	t.origin += dir * moved
	body.global_transform = t

	body.collision_layer = layer
	body.collision_mask = mask
	body.freeze = frozen
	body.force_update_transform()
	PhysicsServer3D.body_set_state(
		body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, t)
	# physics_interpolation is on project-wide, so without this the step out is
	# rendered as a glide from the old pose instead of the pop it actually is.
	body.reset_physics_interpolation()


# ── What was standing on it ───────────────────────────────────────────────────
#
# Picking something up takes it out of the simulation entirely: xr-tools moves it
# to the held layer and clears its mask, and the patch at the top of this file
# clears that layer from every other pickable's mask. Nothing collides with it
# any more — so a body that had fallen asleep resting ON it loses its support
# without a single contact being reported, and there is nothing left to tell it.
# It hangs in the air exactly where it sat: a console on top of a set stays put
# while the set is carried off. Measured on the shipped masks, it floats even
# when the held object never moves at all.
#
# Not woken at the grab, which would be the obvious place. The held object is
# still right there underneath at that moment, just intangible, so waking then
# drops the console THROUGH the set and lands it inside the cabinet. Each rider
# is watched instead and woken once the thing it was standing on is no longer
# under it — the same instant a player sees it slide out.
#
# ── Riding ────────────────────────────────────────────────────────────────────
# A rider also gets the held layer put BACK into its own mask for as long as it
# is riding, which re-opens that one collision pair and hands the job to the
# solver: a keyboard on a desktop machine is carried along by friction, slides
# when the machine is yanked, and goes over the edge when it is tilted, none of
# which is written here. Measured on a 0.6 kg board — carried at 0.6 m/s it
# travels the full 0.5 m still on top; yanked at 3.6 m/s it makes 0.28 m of a
# 1.5 m sweep and slips off the back.
#
# One pair, one direction. The held body's own mask stays 0, so a rider can
# never shove the thing in the player's hand, and every OTHER loose object in
# the room still passes straight through it.

## Take note of whatever is standing on `body`, which is about to become
## intangible in someone's hand. Called from every hold: the pickable's own
## picked_up (hand, desktop, snap zone) and the pickup function's has_picked_up
## (which is all a ray grab emits — it never calls pick_up).
func watch_riders(body: Variant) -> void:
	var rb := body as RigidBody3D
	if rb == null or not is_instance_valid(rb) or not rb.is_inside_tree():
		return
	for rider in _riders_on(rb):
		# Re-open this one collision pair, and remember whether opening it was
		# ours to undo — a mask that already had the bit is somebody else's.
		var couple := (rider.collision_mask & HELD_BIT) == 0
		if couple:
			rider.collision_mask |= HELD_BIT
		_riders[rider.get_instance_id()] = [rider, rb, couple]


## The bodies resting on `body`, found with its own shape lifted by the probe.
##
## Sleep state is deliberately NOT a filter here, tempting as it is: an object
## only just set down is still awake when the grab comes, and measured, it goes
## to sleep in mid-air on the very next tick — the support stopped colliding, so
## nothing disturbed it, and it never accumulated a frame of gravity to notice.
## Skipping the awake ones let exactly that case float. Waking a body that never
## slept costs nothing, so the watch takes them all.
##
## Frozen ones ARE skipped: a frozen body is held, parked by a float lock, or
## seated in a socket, and all three want to stay where they are.
func _riders_on(body: RigidBody3D) -> Array[RigidBody3D]:
	var out: Array[RigidBody3D] = []
	var cs := _first_shape(body)
	var world := body.get_world_3d()
	if cs == null or world == null:
		return out
	var top := _world_aabb(cs).end.y
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = cs.shape
	# The shape's own transform, scale included: a set carries its size on the
	# body node, so the unscaled resource alone would query a smaller cabinet.
	query.transform = cs.global_transform.translated(Vector3.UP * SUPPORT_PROBE)
	query.collision_mask = NOT_HELD_MASK
	query.collide_with_areas = false
	query.exclude = [body.get_rid()]
	for hit: Dictionary in world.direct_space_state.intersect_shape(query, MAX_RIDERS):
		var rider := hit.get("collider") as RigidBody3D
		if rider == null or rider == body or rider.freeze:
			continue
		# Standing on it, not just touching it. The query answers with the shelf
		# neighbour a cabinet is pressed against as readily as the console on its
		# roof, and only one of those is riding anything.
		var rcs := _first_shape(rider)
		if rcs == null or _world_aabb(rcs).position.y < top - RIDER_SEAT_SLACK:
			continue
		if not out.has(rider):
			out.append(rider)
	return out


## A collision shape's bounds in world space. Shape3D publishes no extent of its
## own — the debug mesh is the one way to ask a shape of any kind how big it is,
## and it is built once and cached on the resource.
func _world_aabb(cs: CollisionShape3D) -> AABB:
	return cs.global_transform * cs.shape.get_debug_mesh().get_aabb()


func _tick_riders(delta: float) -> void:
	_rider_timer += delta
	if _rider_timer < 1.0 / RIDER_CHECK_HZ:
		return
	_rider_timer = 0.0

	for id: int in _riders.keys():
		var row: Array = _riders[id]
		# Untyped first, for the reason spelled out in the fall watch below: a
		# typed read of a freed instance raises before the erase can run.
		var rider_any: Variant = row[0]
		var support_any: Variant = row[1]
		var rider: RigidBody3D = rider_any if is_instance_valid(rider_any) else null
		var support: RigidBody3D = support_any if is_instance_valid(support_any) else null
		if rider == null or not rider.is_inside_tree():
			_riders.erase(id)
			continue
		# Somebody has claimed the rider itself — picked it up, parked it, or
		# seated it. Its pose is theirs now, and so is its mask: a pickable puts
		# its own back on release, from a snapshot that never had our bit.
		if rider.freeze:
			_riders.erase(id)
			continue
		# Support gone or put down: wake either way. Put down back underneath, the
		# rider settles onto it again in the same breath, so there is nothing to
		# tell apart here.
		if support == null or not support.is_inside_tree() or not support.freeze \
				or not _still_under(rider, support):
			if bool(row[2]):
				rider.collision_mask &= ~HELD_BIT
			_wake(rider)
			_riders.erase(id)


## True while `support` is still under `rider` — asked of the held layer alone,
## so only the object in the hand can answer it.
func _still_under(rider: RigidBody3D, support: RigidBody3D) -> bool:
	var cs := _first_shape(rider)
	var world := rider.get_world_3d()
	if cs == null or world == null:
		return false
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = cs.shape
	query.transform = cs.global_transform.translated(Vector3.DOWN * SUPPORT_PROBE)
	query.collision_mask = HELD_BIT
	query.collide_with_areas = false
	query.exclude = [rider.get_rid()]
	for hit: Dictionary in world.direct_space_state.intersect_shape(query, MAX_RIDERS):
		if hit.get("collider") == support:
			return true
	return false


## Hand a body back to gravity. Both writes: the node property alone leaves the
## server's copy asleep, which is the same reason the drop in pickable.gd pushes
## it through PhysicsServer3D as well.
func _wake(body: RigidBody3D) -> void:
	body.sleeping = false
	PhysicsServer3D.body_set_state(
		body.get_rid(), PhysicsServer3D.BODY_STATE_SLEEPING, false)


# ── Falling out of the world ──────────────────────────────────────────────────
#
# Objects still get under the floor: released inside it (the escape above only
# moves horizontally, so it cannot lift one out), thrown through it, or simply
# dropped past the edge of a floor slab that is only as big as the room. Rather
# than chase each of those, this catches the outcome they share — the object is
# below the world and falling forever — and puts it back.
#
# "Back" is where it was last sitting still, not straight up from where it fell:
# an object that went over the edge has no floor above it to return to, and one
# that dropped through has an owner who last saw it on a shelf, not on the
# carpet beneath.

func _physics_process(delta: float) -> void:
	# Ahead of the fall watch's own rate gate, which returns early.
	_tick_riders(delta)

	_fall_timer += delta
	if _fall_timer < 1.0 / FALL_CHECK_HZ:
		return
	_fall_timer = 0.0

	for id: int in _watched.keys():
		# Read it untyped first. A typed assignment type-checks its value, and on a
		# freed instance that check IS the error ("Trying to assign invalid
		# previously freed instance") — which aborts this function before the erase
		# below can run, so the stale row survives to raise it again next pass. This
		# autoload outlives every scene, so a room change leaves a stale row for
		# every pickable that was in the old room.
		var watched: Variant = _watched[id]
		var body: XRToolsPickable = watched if is_instance_valid(watched) else null
		if body == null or not body.is_inside_tree():
			_watched.erase(id)
			_safe_pose.erase(id)
			continue
		# Held, socketed or flying on a beam: its position is somebody else's
		# business, and mid-flight is not a pose worth remembering.
		if body.is_picked_up() or body.freeze:
			continue
		if body.global_position.y < FALL_LIMIT_Y:
			_recover(id, body)
		elif body.global_position.y > SAFE_MIN_Y \
				and body.linear_velocity.length_squared() < AT_REST_SPEED2:
			_safe_pose[id] = body.global_transform


func _recover(id: int, body: XRToolsPickable) -> void:
	var to: Transform3D = _safe_pose.get(id, Transform3D.IDENTITY)
	if not _safe_pose.has(id):
		# Never seen at rest — it fell before it ever settled. Put it in front of
		# the player instead, where they will actually notice it came back.
		var cam := body.get_viewport().get_camera_3d()
		if cam == null:
			return          # no camera yet; try again on the next pass
		to = Transform3D(body.global_transform.basis, _in_front_of(cam))

	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.global_transform = to
	body.force_update_transform()
	# A teleported body keeps its old transform in the physics server until it is
	# pushed explicitly, and would carry on falling from where it was.
	PhysicsServer3D.body_set_state(
		body.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, to)
	PhysicsServer3D.body_set_state(
		body.get_rid(), PhysicsServer3D.BODY_STATE_LINEAR_VELOCITY, Vector3.ZERO)
	PhysicsServer3D.body_set_state(
		body.get_rid(), PhysicsServer3D.BODY_STATE_ANGULAR_VELOCITY, Vector3.ZERO)
	# As in _escape: a teleport under project-wide physics interpolation is
	# otherwise drawn as a streak across the room it just came back from.
	body.reset_physics_interpolation()


## A spot at chest height an arm's length in front of the player.
func _in_front_of(cam: Camera3D) -> Vector3:
	var fwd := -cam.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		fwd = Vector3.FORWARD
	return cam.global_position + fwd.normalized() * 0.5 + Vector3(0.0, -0.2, 0.0)


## True while `shape`, placed at `xform`, is buried in `mask` geometry by more
## than a resting contact. Areas are excluded: a snap zone or a trigger volume is
## not something to escape from.
##
## collide_shape rather than intersect_shape, because intersect_shape answers the
## wrong question — it reports a single hit both for a console settled on a table
## and for one released inside a shelf. The contact pairs carry the depth that
## tells those apart (0.000 m against 0.053 m).
func _buried(body: PhysicsBody3D, shape: Shape3D, xform: Transform3D,
		mask: int) -> bool:
	var space := body.get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = xform
	q.collide_with_areas = false
	q.collide_with_bodies = true
	q.exclude = [body.get_rid()]
	q.collision_mask = mask
	var pts := space.collide_shape(q, MAX_CONTACTS)
	for i in range(0, pts.size() - 1, 2):
		if pts[i].distance_to(pts[i + 1]) > BURIED_DEPTH:
			return true
	return false


func _first_shape(body: PhysicsBody3D) -> CollisionShape3D:
	for c in body.get_children():
		var cs := c as CollisionShape3D
		if cs != null and cs.shape != null and not cs.disabled:
			return cs
	return null
