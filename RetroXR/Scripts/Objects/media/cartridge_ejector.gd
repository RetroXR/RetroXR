## CartridgeEjector — a cartridge console's EJECT lever: lifts the seated cartridge
## out of its connector, which stops the game, and leaves it standing proud of the
## seat for a hand to take.
##
## The Super NES's lever is the one modelled. A model turns it on with
## RetroSystemModel.has_cartridge_eject; the cabinet's EJECT button then calls
## RetroSystemModel.eject_cartridge, which lands here. A shell with a lever of its
## own presses it from its lever's button the same way.
##
## A child of the model, made on first use (of).
class_name CartridgeEjector
extends Node

const NODE_NAME := "CartridgeEjector"
## How far a lifted cartridge stands proud of its seat: the SNES lever's throw.
const LIFT := 0.012
## Past this from the slot, a lifted cartridge has left the well some other way
## than in a hand (the console was carried off from under it).
const CLEAR := 0.09

var lift := LIFT
var clear := CLEAR

var _slot: XRToolsSnapZone = null
## The one lifted, which the slot must not take straight back.
var _lifted: RigidBody3D = null


## The model's ejector, made the first time it is asked for.
static func of(model: Node3D) -> CartridgeEjector:
	var ej := model.get_node_or_null(NODE_NAME) as CartridgeEjector
	if ej == null:
		ej = CartridgeEjector.new()
		ej.name = NODE_NAME
		model.add_child(ej)
	return ej


func _ready() -> void:
	set_process(false)


## Lift what `slot` holds. Returns the cartridge, or null for an empty slot.
##
## Out of the connector and up by the lever's throw, then held still: loose inside
## the console's collision box it would be thrown clear. The slot is shut until a
## hand has it, or it would take the cartridge straight back.
func eject(slot: XRToolsSnapZone) -> RigidBody3D:
	_slot = slot
	var cart := slot.picked_up_object as RigidBody3D if slot != null else null
	if cart == null:
		return null
	var up := Vector3.UP
	var model := get_parent() as Node3D
	if model != null:
		up = model.global_transform.basis.y.normalized()
	slot.enabled = false
	slot.drop_object()
	cart.freeze = true
	_hold_off(cart)
	cart.global_position += up * lift
	_lifted = cart
	if not cart.is_connected("picked_up", _on_taken):
		cart.connect("picked_up", _on_taken, CONNECT_ONE_SHOT)
	set_process(true)
	return cart


## The lifted cartridge, while it still stands in the well.
func lifted() -> RigidBody3D:
	return _lifted if is_instance_valid(_lifted) else null


## A hand has it. The cartridge noted it was frozen as the state to go back to on
## release and would hang wherever the hand left it, so that note is put right, as
## MediaSlot does for a disc.
func _on_taken(what: Variant) -> void:
	var cart := what as RigidBody3D
	if cart == null or cart != _lifted:
		return
	if "restore_freeze" in cart:
		cart.set("restore_freeze", false)
	_open_slot()


func _open_slot() -> void:
	_lifted = null
	set_process(false)
	if _slot != null:
		_slot.enabled = true


## Seated, the slot kept a collision exception between cartridge and console, and
## drop_object took it back. Lifted, the cartridge still stands in the console's
## box and, frozen, would shove the console down through the table. So the console
## keeps clear of it until it is let go somewhere.
func _hold_off(cart: RigidBody3D) -> void:
	var host := _host()
	if host == null:
		return
	host.add_collision_exception_with(cart)
	if not cart.is_connected("dropped", _let_touch):
		cart.connect("dropped", _let_touch, CONNECT_ONE_SHOT)


## Put back in the slot, it is the slot's again, exception and all.
func _let_touch(what: Variant) -> void:
	var cart := what as RigidBody3D
	var host := _host()
	if cart == null or host == null or (_slot != null and _slot.picked_up_object == cart):
		return
	host.remove_collision_exception_with(cart)


## The console body: the model's parent.
func _host() -> PhysicsBody3D:
	var model := get_parent()
	return model.get_parent() as PhysicsBody3D if model != null else null


## A lifted cartridge that has left the well some other way than in a hand is let
## fall and the slot opened again.
func _process(_delta: float) -> void:
	if not is_instance_valid(_lifted):
		_open_slot()
		return
	if _slot == null or _lifted.global_position.distance_to(_slot.global_position) <= clear:
		return
	var cart := _lifted
	cart.freeze = false
	if cart.is_connected("picked_up", _on_taken):
		cart.disconnect("picked_up", _on_taken)
	if cart.is_connected("dropped", _let_touch):
		cart.disconnect("dropped", _let_touch)
	_let_touch(cart)
	_open_slot()
