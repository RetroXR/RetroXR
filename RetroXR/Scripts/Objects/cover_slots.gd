## CoverSlots — the removable covers on any object: a handheld's battery cover, a
## Rumble Pak's battery door, a printer's bottom panel.
##
## A console's covers over its own unit sockets are RetroSystem's
## (RetroSystemModel.build_port_cover_slot); this is the same PortCover for
## things that are not consoles, or for covers that close no socket. All three
## kinds of cover slot, the N64's lid among them, are made by make_zone(). A mod builds
## a slot where the shell has the cover, and the cover is then a thing of its own:
## taken off, put down, carried away, put back. A mod's PortCover hook dresses it
## in the shell's own part, as xenu.gamecube dresses the Serial Port 1 cover.
##
## One CoverSlots node per object, named "CoverSlots", made by on(). A slot is
## built once, under any node of the object (the model, the shell), at the pose
## the cover's middle has there, its outer face +Y.
##
## Who seeds the cover. On an object spawned fresh, every slot gets a cover as it
## is built. On one being restored (ScenePersistence marks it RESTORING before it
## enters the room) the save says: restore() hands over each slot's cover, or
## null for one that was off; a slot the save does not name (a save from before
## the object had covers) gets a fresh one. The slot and the save can arrive in
## either order -- a shell can finish loading after the restore's second pass --
## so whichever comes second settles the slot.
class_name CoverSlots
extends Node

## Set on an object by ScenePersistence before a restored object enters the
## room, so its slots wait for the save instead of seeding covers.
const RESTORING := &"cover_slots_restoring"
const NODE_NAME := "CoverSlots"

const _COVER_SCENE := preload("res://Scenes/Objects/port_cover.tscn")
const _ZONE_SCENE := preload("res://addons/godot-xr-tools/objects/snap_zone.tscn")
## How close a cover must be brought to go back: pressed into its own opening.
## Closer than a console's port cover (6 cm): a battery cover is on something
## held, often small, and a reach that size takes in most of a Game Boy, so a
## pointer aimed past the shell anywhere round it would find the slot.
const _GRAB_DISTANCE := 0.025
## A seated cover's pointer target stands this far out of its box, not the loose
## cover's 2 cm: on a handheld's back that margin would take every aim at the
## console round it.
const SEATED_POINTER_MARGIN := Vector3(0.001, 0.001, 0.001)
## Every slot is in this group, so a cover can tell a slot holding it from a hand.
const SLOT_GROUP := &"cover_slot"
## On a cover whose moves this already watches.
const _WATCHED := &"cover_slots_watched"
## On a restored object: what its save said about its covers (told()).
const _SAVED := &"cover_slots_saved"

## socket id -> its slot (XRToolsSnapZone), and how big its cover is.
var _slots: Dictionary = {}
var _sizes: Dictionary = {}
## What the save said, once restore() has been told: socket id -> the cover (a
## PortCover) or null. `_told` is false until then.
var _saved: Dictionary = {}
var _told := false
## Sockets already settled (seeded, restored, or left off), so a slot built again
## never seeds a second cover.
var _settled: Dictionary = {}


## The object's CoverSlots, made on first use. `host` is the object the save
## records (the spawned RigidBody: a console, a pak, a printer).
static func on(host: Node) -> CoverSlots:
	var slots := of(host)
	if slots == null and host != null:
		slots = CoverSlots.new()
		slots.name = NODE_NAME
		if host.has_meta(_SAVED):
			slots._saved = host.get_meta(_SAVED)
			slots._told = true
		host.add_child(slots)
	return slots


## ScenePersistence's word on a restored object's covers, given in the restore's
## second pass whether or not a mod has built its slots yet: kept on the object
## for slots built later, and settled now for the ones already there.
static func told(host: Node, saved: Dictionary) -> void:
	if host == null:
		return
	host.set_meta(_SAVED, saved)
	var slots := of(host)
	if slots != null:
		slots.restore(saved)


## The object's CoverSlots, or null for one with no covers.
static func of(host: Node) -> CoverSlots:
	return host.get_node_or_null(NODE_NAME) as CoverSlots if host != null else null


## The slot for a shell's own cover `part` (a mesh of the object's model), with
## its outer face toward `out` (in the part's parent's frame): built under the
## part's parent, round the part's bounds, and the part hidden, since the cover
## that goes there wears it (wear()). Returns the slot, or null when the part is
## not in an object.
static func shell_cover(part: MeshInstance3D, socket_id: String, out: Vector3) -> XRToolsSnapZone:
	var host := host_of(part)
	var parent := part.get_parent() as Node3D
	if host == null or parent == null:
		return null
	var seat := part_seat(part, out)
	var zone := on(host).build(socket_id, parent, seat, part_size(part, out))
	part.visible = false
	return zone


## Where a cover made from `part` sits, in the part's parent's frame: the middle
## of the part's bounds, turned so +Y is `out` (a principal axis) and the other two
## axes stay on principal axes, so the box's extents keep their meaning.
static func part_seat(part: MeshInstance3D, out: Vector3) -> Transform3D:
	var box := part.transform * part.get_aabb()
	var y := out.normalized()
	var x := Vector3.RIGHT if absf(y.x) < 0.9 else Vector3.BACK
	var z := x.cross(y).normalized()
	x = y.cross(z).normalized()
	return Transform3D(Basis(x, y, z), box.get_center())


## The cover's box in its own frame (part_seat's).
static func part_size(part: MeshInstance3D, out: Vector3) -> Vector3:
	var box := part.transform * part.get_aabb()
	var b := part_seat(part, out).basis
	return Vector3(absf(b.x.dot(box.size)), absf(b.y.dot(box.size)), absf(b.z.dot(box.size)))


## Dress `cover` in `part`, a shell's cover mesh taken from a copy of its model
## (still parented there, at its place in that model): the part moves into the
## cover where part_seat puts it, and the cover's plain block is hidden. For a
## mod's PortCover hook.
static func wear(cover: PortCover, part: MeshInstance3D, out: Vector3) -> void:
	var seat := part_seat(part, out)
	var placed := seat.affine_inverse() * part.transform
	part.get_parent().remove_child(part)
	part.owner = null
	part.transform = placed
	part.visible = true
	var plain := cover.get_node_or_null("Mesh") as Node3D
	if plain != null:
		plain.visible = false
	var shell := Node3D.new()
	shell.name = "Shell"
	shell.add_child(part)
	cover.add_child(shell)
	# Seated, the pointer finds it by what it draws, not by its box.
	if part.mesh != null:
		cover.set_pointer_hull(part.mesh.create_convex_shape(true, true), placed)


## The object a node belongs to, for a mod's script deep inside it: the nearest
## pickable above it (a console, a pak, a printer), or null.
static func host_of(node: Node) -> Node:
	var n := node
	while n != null and not n is XRToolsPickable:
		n = n.get_parent()
	return n


## A cover slot's snap zone, as every one in the room is made -- the console's
## over its own unit sockets (RetroSystemModel.build_port_cover_slot), the N64's
## Expansion Pak lid (RetroSystemModelNintendo64) and an object's (build()): a
## snap zone named `zone_name` under `parent`, taking only what is in group
## `require`, from `grab_distance` away. The caller places it and gates it; what
## differs between the three is who seeds the cover and how a save records it.
static func make_zone(zone_name: String, require: String, grab_distance: float,
		parent: Node3D) -> XRToolsSnapZone:
	var zone := _ZONE_SCENE.instantiate() as XRToolsSnapZone
	zone.name = zone_name
	zone.snap_require = require
	zone.grab_distance = grab_distance
	parent.add_child(zone)
	return zone


## A fresh PortCover for `socket_id`, of box `size`, in color `variant`: what every
## cover slot seeds -- an object's (_seed) and a console's over its own unit
## sockets (SystemExpansions). Not yet in the room; seat_new() puts it there.
static func new_port_cover(socket_id: String, size: Vector3, variant: String) -> PortCover:
	var cover := _COVER_SCENE.instantiate() as PortCover
	cover.socket_id = socket_id
	cover.size = size
	cover.model_variant = variant
	return cover


## Bring a freshly made cover into the room and seat it in `zone`: the one way
## every kind of cover slot seeds -- an object's, a console's port covers and the
## N64's Expansion Pak lid. It arrives at the slot's own pose, or at `from` (a
## global position, its turn left as built) for a caller that has always
## started it elsewhere. Spawned like anything a hand put down, so it saves.
static func seat_new(zone: XRToolsSnapZone, cover: Node3D, from: Variant = null) -> void:
	zone.get_tree().current_scene.add_child(cover)
	cover.add_to_group("spawned")
	if from is Vector3:
		cover.global_position = from
	else:
		cover.global_transform = zone.global_transform
	zone.pick_up_object(cover)


## Put a cover a save names back into its slot -- every kind of cover slot's
## restore. False (and nothing done) when either is missing or the slot is already
## holding something.
static func seat_saved(zone: XRToolsSnapZone, cover: Node3D) -> bool:
	if zone == null or not is_instance_valid(cover):
		return false
	if zone.has_snapped_object():
		return false
	zone.pick_up_object(cover)
	return true


## Build the slot for `socket_id` under `parent`, at `seat` in parent's frame (the
## cover's middle, its outer face +Y), for a cover of box `size`. Built once: a
## second call returns the first slot.
func build(socket_id: String, parent: Node3D, seat: Transform3D, size: Vector3) -> XRToolsSnapZone:
	var zone := slot(socket_id)
	if zone != null:
		return zone
	zone = make_zone(socket_id.to_pascal_case() + "CoverSlot", PortCover.group_for(socket_id),
		_GRAB_DISTANCE, parent)
	zone.add_to_group(SLOT_GROUP)
	zone.transform = seat
	_slots[socket_id] = zone
	_sizes[socket_id] = size
	zone.has_picked_up.connect(_on_seated)
	_settle(socket_id)
	# The object's battery bays shut while this is on (CellSlots).
	var cells := CellSlots.of(get_parent())
	if cells != null:
		cells.watch_covers(self)
	return zone


## The slot over `socket_id`, or null.
func slot(socket_id: String) -> XRToolsSnapZone:
	var zone := _slots.get(socket_id) as XRToolsSnapZone
	return zone if is_instance_valid(zone) else null


## The sockets with a slot, in the order they were built.
func sockets() -> Array[String]:
	var out: Array[String] = []
	for socket_id: String in _slots:
		if slot(socket_id) != null:
			out.append(socket_id)
	return out


## How big the cover over `socket_id` is, or ZERO.
func size_of(socket_id: String) -> Vector3:
	return _sizes.get(socket_id, Vector3.ZERO)


## Each slot and the cover in it, or null for one that is off: what a save records.
func covers() -> Dictionary:
	var out := {}
	for socket_id: String in sockets():
		out[socket_id] = slot(socket_id).picked_up_object as Node3D
	return out


## True while the cover over `socket_id` is on.
func is_on(socket_id: String) -> bool:
	var zone := slot(socket_id)
	return zone != null and zone.has_snapped_object()


## The save's word on this object's covers: socket id -> its cover, or null for
## one that was off. A save that names no covers at all (one from before covers)
## is an empty Dictionary, and every slot then gets a fresh cover.
func restore(saved: Dictionary) -> void:
	_saved = saved
	_told = true
	for socket_id: String in sockets():
		_settle(socket_id)


func _settle(socket_id: String) -> void:
	if _settled.has(socket_id):
		return
	var host := get_parent()
	var restoring := host != null and host.has_meta(RESTORING)
	if restoring and not _told:
		return                  # the save's second pass will say
	_settled[socket_id] = true
	var zone := slot(socket_id)
	if restoring and _saved.has(socket_id):
		seat_saved(zone, _saved[socket_id] as PortCover)
		return
	_seed.call_deferred(socket_id)


## A fresh cover in the object's color, given before it enters the room: that is
## when a mod's hook dresses it.
func _seed(socket_id: String) -> void:
	var zone := slot(socket_id)
	if zone == null or zone.has_snapped_object() or not zone.is_inside_tree():
		return
	seat_new(zone, new_port_cover(socket_id, size_of(socket_id), _variant_of(get_parent())))


static func _variant_of(host: Node) -> String:
	if host == null:
		return ""
	var own: Variant = host.get("model_variant")
	if own is String and not (own as String).is_empty():
		return own
	return SystemModelRegistry.variant_of(host)


## Seated, a cover's pointer target is its own box; off, the loose cover's
## margin again. Whatever moves it (a zone letting go, a hand taking it straight
## out of its slot), the cover looks again at what holds it, a frame later when
## the hand-over is done.
func _on_seated(what: Node3D) -> void:
	var cover := what as PortCover
	if cover == null:
		return
	_refresh(cover)
	if cover.has_meta(_WATCHED):
		return
	cover.set_meta(_WATCHED, true)
	var later := _refresh_later.bind(cover)
	cover.picked_up.connect(later.unbind(1))
	cover.dropped.connect(later.unbind(1))
	cover.grabbed.connect(later.unbind(2))
	cover.released.connect(later.unbind(2))


static func _refresh_later(cover: PortCover) -> void:
	_refresh.call_deferred(cover)


static func _refresh(cover: PortCover) -> void:
	if not is_instance_valid(cover):
		return
	var by := cover.get_picked_up_by()
	var seated := by != null and by.is_in_group(SLOT_GROUP)
	cover.set_pointer_margin(SEATED_POINTER_MARGIN if seated else PortCover.POINTER_MARGIN)
