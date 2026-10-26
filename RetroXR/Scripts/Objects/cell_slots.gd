## CellSlots — the battery cells in an object's bays: a Game Boy's four AAs, a
## Rumble Pak's two AAAs, a printer's six.
##
## A model marks each cell's place with a node named BatteryAA<n> or
## BatteryAAA<n>: its origin the cell's middle as seated, +Z toward the cell's +
## terminal, +Y out of the bay through the cover. A mod hands the model's root to
## build_seats() once it is in the object, and every such node gets a CellSlot
## that takes a cell of that size and no other (a cell joins group_for its size).
## A cell goes in at the roll it was held at (CellSlot).
##
## Bays come empty: cells are things of their own, brought from the spawn menu
## and put in. While any of the object's covers (CoverSlots) is on, its slots
## take nothing and the cells in them cannot be taken out; a mod whose cover is
## something else (a hinge) says so with set_blocker().
##
## One CellSlots node per object, named "CellSlots". What is in each slot is
## saved on the object ("cell_slots"); on load the save and the slots can arrive
## in either order, as with CoverSlots, and whichever comes second seats the cell.
class_name CellSlots
extends Node

const NODE_NAME := "CellSlots"
## Every slot is in this group, so a cell can tell a slot holding it from a hand.
const SLOT_GROUP := &"cell_slot"
const GROUP := "battery_cell"
## The sizes a seat can be, longest name first so AAA is not read as AA.
const SIZES: Array[String] = ["AAA", "AA"]

const _ZONE_SCENE := preload("res://Scenes/Objects/cell_slot.tscn")
## On a restored object: what its save said about its cells (told()).
const _SAVED := &"cell_slots_saved"
## On a cover zone whose moves this already watches.
const _WATCHED := &"cell_slots_watched"

## seat name -> its CellSlot, in the order built.
var _slots: Dictionary = {}
## What the save said: seat name -> [cell, roll in radians].
var _saved: Dictionary = {}
var _blocker := Callable()
## The cells this has switched off under a closed cover, so one that leaves its
## slot some other way (its object deleted) is switched back on.
var _held_shut: Array[XRToolsPickable] = []


## The group a cell of `size` ("AA", "AAA") joins, and a slot for it requires.
static func group_for(size: String) -> String:
	return GROUP + ":" + size.to_lower()


## The size a seat named `seat_name` takes ("AA", "AAA"), or "" for a node that
## is not a seat.
static func size_of_seat(seat_name: String) -> String:
	for size: String in SIZES:
		var prefix := "Battery" + size
		if seat_name.begins_with(prefix) and seat_name.length() > prefix.length() \
				and seat_name.substr(prefix.length()).is_valid_int():
			return size
	return ""


## The object's CellSlots, made on first use. `host` is the object the save
## records (the spawned RigidBody: a console, a pak, a printer).
static func on(host: Node) -> CellSlots:
	var slots := of(host)
	if slots == null and host != null:
		slots = CellSlots.new()
		slots.name = NODE_NAME
		if host.has_meta(_SAVED):
			slots._saved = host.get_meta(_SAVED)
		host.add_child(slots)
		var covers := CoverSlots.of(host)
		if covers != null:
			slots.watch_covers(covers)
	return slots


## The object's CellSlots, or null for one with no bays.
static func of(host: Node) -> CellSlots:
	return host.get_node_or_null(NODE_NAME) as CellSlots if host != null else null


## A slot at every BatteryAA<n> / BatteryAAA<n> under `root` (a model's GLB, or
## any node of it), for the object `root` is in. Returns the slots built.
static func build_seats(root: Node) -> Array[CellSlot]:
	var out: Array[CellSlot] = []
	var host := CoverSlots.host_of(root)
	if host == null:
		return out
	var seat_nodes: Array[Node] = root.find_children("Battery*", "Node3D", true, false)
	if root is Node3D and not size_of_seat(root.name).is_empty():
		seat_nodes.push_front(root)
	for node: Node in seat_nodes:
		if not size_of_seat(node.name).is_empty():
			out.append(on(host).build(node as Node3D))
	return out


## ScenePersistence's word on a restored object's cells: seat name -> [cell,
## roll], given whether or not a mod has built its slots yet.
static func told(host: Node, saved: Dictionary) -> void:
	if host == null:
		return
	host.set_meta(_SAVED, saved)
	var slots := of(host)
	if slots != null:
		slots.restore(saved)


## The slot at `marker`, a seat node of the object's model. Under the marker's
## parent, at the marker's pose with its scale taken out (a cell is its own
## size, whatever the model was imported at). Built once.
func build(marker: Node3D) -> CellSlot:
	var seat_name := str(marker.name)
	var zone := slot(seat_name)
	if zone != null:
		return zone
	var parent := marker.get_parent() as Node3D
	zone = _ZONE_SCENE.instantiate() as CellSlot
	zone.name = seat_name + "Slot"
	zone.snap_require = group_for(size_of_seat(seat_name))
	zone.add_to_group(SLOT_GROUP)
	var world := Transform3D(marker.global_basis.orthonormalized(), marker.global_position)
	zone.seat = parent.global_transform.affine_inverse() * world
	zone.transform = zone.seat
	parent.add_child(zone)
	_slots[seat_name] = zone
	zone.has_picked_up.connect(_on_changed.unbind(1))
	zone.has_dropped.connect(_on_changed)
	if _saved.has(seat_name):
		_seat_saved(seat_name)
	_refresh()
	return zone


## The slot at the seat `seat_name`, or null.
func slot(seat_name: String) -> CellSlot:
	var zone := _slots.get(seat_name) as CellSlot
	return zone if is_instance_valid(zone) else null


## The seats with a slot, in the order they were built.
func seats() -> Array[String]:
	var out: Array[String] = []
	for seat_name: String in _slots:
		if slot(seat_name) != null:
			out.append(seat_name)
	return out


## The cells in, by seat: seat name -> [cell, roll in radians]. An empty seat is
## left out. What a save records.
func cells() -> Dictionary:
	var out := {}
	for seat_name: String in seats():
		var zone := slot(seat_name)
		if zone.has_snapped_object():
			out[seat_name] = [zone.picked_up_object, zone.roll]
	return out


## True while nothing may go in or come out: a cover is on.
func is_blocked() -> bool:
	if _blocker.is_valid() and bool(_blocker.call()):
		return true
	var covers := CoverSlots.of(get_parent())
	if covers != null:
		for socket_id: String in covers.sockets():
			if covers.is_on(socket_id):
				return true
	return false


## For an object whose bay is closed by something other than a CoverSlots cover
## (a hinged door): `blocker` returns true while the bay is shut. Call refresh()
## when it opens or closes.
func set_blocker(blocker: Callable) -> void:
	_blocker = blocker
	_refresh()


## Look again at whether the bays are shut, and open or close every slot.
func refresh() -> void:
	_refresh()


## Watch `covers`' slots, so the bays shut as a cover goes on. Called by
## whichever of the two is made second, and by CoverSlots for each slot it builds.
func watch_covers(covers: CoverSlots) -> void:
	for socket_id: String in covers.sockets():
		var zone := covers.slot(socket_id)
		if zone.has_meta(_WATCHED):
			continue
		zone.set_meta(_WATCHED, true)
		zone.has_picked_up.connect(_on_changed.unbind(1))
		zone.has_dropped.connect(_on_changed)
	_refresh()


## The save's word on this object's cells: seat name -> [cell, roll].
func restore(saved: Dictionary) -> void:
	_saved = saved
	for seat_name: String in seats():
		if _saved.has(seat_name):
			_seat_saved(seat_name)


func _seat_saved(seat_name: String) -> void:
	var rec: Variant = _saved.get(seat_name)
	var zone := slot(seat_name)
	if zone == null or not rec is Array or (rec as Array).size() < 2:
		return
	var cell := (rec as Array)[0] as Node3D
	if not is_instance_valid(cell) or zone.has_snapped_object():
		return
	zone.seat_cell(cell, float((rec as Array)[1]))
	# Once: a slot built again, or a later save word, must not pull it back.
	_saved.erase(seat_name)


func _on_changed() -> void:
	_refresh.call_deferred()


## Every slot open or shut with the bay, and every cell in one with it.
func _refresh() -> void:
	if not is_inside_tree():
		return
	var blocked := is_blocked()
	var shut: Array[XRToolsPickable] = []
	for seat_name: String in seats():
		var zone := slot(seat_name)
		zone.enabled = not blocked
		var cell := zone.picked_up_object as XRToolsPickable
		if blocked and is_instance_valid(cell):
			cell.enabled = false
			shut.append(cell)
	for cell: XRToolsPickable in _held_shut:
		if is_instance_valid(cell) and not shut.has(cell):
			cell.enabled = true
	_held_shut = shut


func _enter_tree() -> void:
	_refresh.call_deferred()


func _exit_tree() -> void:
	for cell: XRToolsPickable in _held_shut:
		if is_instance_valid(cell):
			cell.enabled = true
	_held_shut.clear()
