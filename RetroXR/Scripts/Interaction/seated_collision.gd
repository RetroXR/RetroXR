## SeatedCollision — lends a seated object's collision to the body it is seated in.
##
## A snap zone FREEZES what it takes and clears its collision mask, then drags it
## to the zone every tick. So a Transfer Pak in a loose N64 pad was a box nothing
## could push: the pad settled on its own shell alone, and the pak, 26 mm below
## it, went through the table while staying attached.
##
## The fix makes the two one rigid body while they are joined: copies of the
## guest's shapes are added to the HOST, where Jolt solves them with the host's
## own. The guest keeps its shapes too, because they are what a hand or the
## desktop ray finds when it reaches for the guest rather than the host; the
## copies are inset by INSET so a ray from outside meets the guest's box first.
##
## Lending alone is not enough under Jolt. Its manifold reduction merges every
## sub-shape's contacts with one floor into a single manifold and keeps the four
## points spanning the most area: the corners of the pad's shell. A pak hanging
## near the middle lost its points and sank 2 cm through the floor with its box
## on the pad. Jolt reduces only for a body that reports no contacts, so a host
## holding lent shapes reports one (no signal goes anywhere unless its
## contact_monitor is on) and gets its own setting back when the last is taken.
##
## Nesting follows: a guest's lent shapes are its children like any other, so a
## cartridge in a Transfer Pak in a pad hands its box all the way up, and a
## cartridge seated or pulled while the pak is already in the pad re-lends the
## pak to the pad.
class_name SeatedCollision

## On a lent CollisionShape3D: the instance id of the guest it was copied from.
const _LENT_FROM := &"seated_collision_from"
## On a lent CollisionShape3D: the instance id of the body the shape is really
## part of (the cartridge, for a cartridge's box passed on by a pak). The host
## gets a collision exception with it, or that frozen body would shove the host
## off its own copy of it.
const _ORIGIN := &"seated_collision_origin"
## On a guest while it lends: {host, zone}.
const _SEAT := &"seated_collision_seat"
## On a host while it holds lent shapes: its own max_contacts_reported.
const _OWN_CONTACTS := &"seated_collision_own_contacts"

## How far each face of a lent box is pulled in, so the guest's own box stays the
## outermost surface for a ray.
const INSET := 0.001


## Lend `guest`'s shapes to `host`, at the pose `zone` holds the guest in.
##
## Call from the zone's has_picked_up. The pose is read from the guest's grab, not
## from where the guest is now: a restore seats it in the same call, before the
## grab driver has moved it anywhere.
static func lend(host: CollisionObject3D, guest: CollisionObject3D, zone: Node3D) -> void:
	if not is_instance_valid(host) or not is_instance_valid(guest) or not is_instance_valid(zone):
		return
	# Leaving the tree (a room being torn down): there is no pose to read, and
	# nothing left to rest on.
	if not host.is_inside_tree() or not guest.is_inside_tree() or not zone.is_inside_tree():
		return
	_take_back(host, guest)
	guest.set_meta(_SEAT, {"host": host, "zone": zone})
	var seat := _seat_of(host, guest, zone)
	for child in guest.get_children():
		var src := child as CollisionShape3D
		if src == null or src.disabled or src.shape == null:
			continue
		var origin_id: int = src.get_meta(_ORIGIN, guest.get_instance_id())
		var origin := instance_from_id(origin_id) as PhysicsBody3D
		if origin != null and host is PhysicsBody3D:
			(host as PhysicsBody3D).add_collision_exception_with(origin)
		var copy := CollisionShape3D.new()
		copy.name = "Lent%s" % src.name
		copy.shape = _inset(src.shape)
		copy.transform = seat * src.transform
		copy.set_meta(_LENT_FROM, guest.get_instance_id())
		copy.set_meta(_ORIGIN, origin_id)
		host.add_child(copy)
	_keep_every_contact(host)
	_relend_up(host)


## Take back what `guest` lent `host`. Call from the zone's has_dropped.
static func withdraw(host: CollisionObject3D, guest: CollisionObject3D) -> void:
	if not is_instance_valid(host):
		return
	if is_instance_valid(guest):
		_take_back(host, guest)
		guest.remove_meta(_SEAT)
	_keep_every_contact(host)
	_relend_up(host)


## The shapes `host` holds for `guest`, as lent copies; for a probe or a test.
static func lent_shapes(host: Node, guest: Object) -> Array[CollisionShape3D]:
	var out: Array[CollisionShape3D] = []
	var id := guest.get_instance_id()
	for child in host.get_children():
		if child is CollisionShape3D and child.get_meta(_LENT_FROM, 0) == id:
			out.append(child)
	return out


static func _take_back(host: CollisionObject3D, guest: CollisionObject3D) -> void:
	for copy in lent_shapes(host, guest):
		var origin := instance_from_id(copy.get_meta(_ORIGIN, 0)) as PhysicsBody3D
		if origin != null and host is PhysicsBody3D:
			(host as PhysicsBody3D).remove_collision_exception_with(origin)
		# Not remove_child: a zone lets go while its host is being freed, when the
		# host is too busy to give up a child. Off and untagged is gone enough.
		copy.disabled = true
		copy.remove_meta(_LENT_FROM)
		copy.name = "Returned%d" % copy.get_instance_id()
		copy.queue_free()


## Switch Jolt's manifold reduction off for `host` while it holds any lent shape,
## and back to what it was once it holds none.
static func _keep_every_contact(host: CollisionObject3D) -> void:
	var body := host as RigidBody3D
	if body == null:
		return
	var lending := false
	for child in body.get_children():
		if child.has_meta(_LENT_FROM):
			lending = true
			break
	if lending and not body.has_meta(_OWN_CONTACTS):
		body.set_meta(_OWN_CONTACTS, body.max_contacts_reported)
		body.max_contacts_reported = maxi(body.max_contacts_reported, 1)
	elif not lending and body.has_meta(_OWN_CONTACTS):
		body.max_contacts_reported = body.get_meta(_OWN_CONTACTS)
		body.remove_meta(_OWN_CONTACTS)


## `body`'s shapes just changed; when it is itself seated in something, lend
## them again to whatever holds it.
static func _relend_up(body: CollisionObject3D) -> void:
	if not body.has_meta(_SEAT):
		return
	var seat: Dictionary = body.get_meta(_SEAT)
	var outer := seat.get("host") as CollisionObject3D
	var zone := seat.get("zone") as Node3D
	if is_instance_valid(outer) and is_instance_valid(zone):
		lend(outer, body, zone)


## Where `guest` sits in `host`'s frame once `zone` has it home.
static func _seat_of(host: Node3D, guest: Node3D, zone: Node3D) -> Transform3D:
	# The grab driver puts the guest at zone * grab.transform⁻¹ every tick.
	var at_zone := zone.global_transform.affine_inverse() * guest.global_transform
	var driver: Variant = VrHold.grab_driver(guest)
	if driver != null and is_instance_valid(driver.primary) and driver.primary.by == zone:
		at_zone = (driver.primary.transform as Transform3D).affine_inverse()
	return host.global_transform.affine_inverse() * zone.global_transform * at_zone


## A box of its own, INSET smaller; any other shape is shared as it is.
static func _inset(shape: Shape3D) -> Shape3D:
	var box := shape as BoxShape3D
	if box == null:
		return shape
	var smaller := BoxShape3D.new()
	smaller.size = (box.size - Vector3.ONE * INSET * 2.0).max(Vector3.ONE * INSET)
	return smaller
