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
const _POINTER_MARGIN := Vector3(0.02, 0.022, 0.02)


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
		var target := BoxShape3D.new()
		target.size = size + _POINTER_MARGIN
		pointer.shape = target
