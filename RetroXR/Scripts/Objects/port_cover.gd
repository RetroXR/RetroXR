## PortCover — the plastic cover over a console's own expansion opening, which
## comes off so a card can go in where it was.
##
## The GameCube's Serial Port 1 cover on its underside and the fat PlayStation
## 2's EXPANSION BAY cover on its back are the two this exists for: a network
## adapter goes into the opening IN PLACE of the cover, so the cover has to come
## off first, and it is a thing of its own once it is off -- put down, carried
## away, lost -- as the Nintendo 64's lid is (ExpansionCover).
##
## Not an ExpansionCover, and on purpose. That lid sits OVER a pak and shares one
## socket with every console that has a lid; this one stands IN a socket of a
## unit's own (ExpansionCatalog's row `socket`) and fits that socket and no other.
## And a mod that dresses ExpansionCover dresses every node of the class and its
## subclasses (ModHooks._matches), so a subclass would have worn an N64 lid.
##
## It does nothing but be present or absent. The gate is the model's
## (RetroSystemModel.build_port_cover_slot): while it is in its slot the socket
## is shut, and while a card is in the socket the slot is shut.
class_name PortCover
extends XRToolsPickable

## Every cover is in this group, whichever socket it is for.
const GROUP := "port_cover"

## Which of a console's unit sockets this covers ("serial_port_1",
## "expansion_bay"). It is what the cover fits: it joins group_for(socket_id),
## which is what its slot requires. Saved.
@export var socket_id: String = "":
	set(value):
		if not socket_id.is_empty() and is_in_group(group_for(socket_id)):
			remove_from_group(group_for(socket_id))
		socket_id = value
		if not value.is_empty():
			add_to_group(group_for(value))

## The cover's box in metres, its middle at the origin and its outer face toward
## +Y: what it collides and is pointed at by, and what the plain stand-in draws
## until a mod dresses it. The console's model says how big its cover is
## (RetroSystemModel.port_cover_size); saved, so a cover lying loose keeps it.
var size: Vector3 = Vector3(0.05, 0.004, 0.03):
	set(value):
		size = value
		if is_node_ready():
			_apply_size()

## Which of its console's colors this cover is, by the ids RetroSystem.
## model_variant takes; empty for one nothing has colored. The console it was
## made on gives it that console's (RetroSystem.seed_port_covers), and it keeps
## it from then on, as a lid does.
var model_variant: String = ""


## The group a slot for `socket` requires, and a cover for it joins.
static func group_for(socket: String) -> String:
	return GROUP + ":" + socket


func _ready() -> void:
	super()
	_apply_size()


## The pointer target is the cover plus a margin on every face, so a thin flat
## thing put down on a shelf is still findable -- memory_card.tscn's reason.
const POINTER_MARGIN := Vector3(0.02, 0.022, 0.02)
var _pointer_margin := POINTER_MARGIN


## The margin the pointer target stands out of the cover by. CoverSlots draws a
## cover seated on a handheld tight, or its margin takes the aims at the console
## round it, and gives it POINTER_MARGIN back when it comes off.
func set_pointer_margin(margin: Vector3) -> void:
	if margin == _pointer_margin:
		return
	_pointer_margin = margin
	if is_node_ready():
		_apply_size()


func pointer_margin() -> Vector3:
	return _pointer_margin


## The shape of what the cover draws, in its own frame, for a cover a mod has
## dressed in a shell's part (CoverSlots.wear). Seated (a margin under the loose
## one), the pointer finds the cover by it: a curved cover's box stands proud of
## the shell round it. Loose, by the box and its margin, as ever.
var _hull: Shape3D = null
var _hull_at := Transform3D()


func set_pointer_hull(hull: Shape3D, at: Transform3D) -> void:
	_hull = hull
	_hull_at = at
	if is_node_ready():
		_apply_size()


func _apply_size() -> void:
	var shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape != null:
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
	var mesh := get_node_or_null("Mesh") as MeshInstance3D
	if mesh != null:
		var block := BoxMesh.new()
		block.size = size
		mesh.mesh = block
	var pointer := get_node_or_null("PointerArea/CollisionShape3D") as CollisionShape3D
	if pointer != null:
		if _hull != null and _pointer_margin != POINTER_MARGIN:
			pointer.shape = _hull
			pointer.transform = _hull_at
			return
		var target := BoxShape3D.new()
		target.size = size + _pointer_margin
		pointer.shape = target
		pointer.transform = Transform3D.IDENTITY
