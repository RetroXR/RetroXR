## GcMicrophonePlug — the memory-card-shaped end of the GameCube Microphone
## (DOL-022), on the cord of a GcMicrophone.
##
## Seats in either memory card slot. It has no card_id, so the slot resolves no
## card image and MemoryCardController mounts the microphone there instead.
class_name GcMicrophonePlug
extends XRToolsPickable

## Where the cord leaves the plug, in the plug's own frame: the middle of its
## outer end.
const CORD_EXIT := Vector3(0.0, 0.0, 0.0375)

## What a card slot filters on.
var family := "gamecube"
## Tells a card slot's owner this is a microphone rather than a card.
var is_microphone := true

var _microphone: WeakRef = null


func _ready() -> void:
	super._ready()
	add_to_group("memory_card")


func set_microphone(microphone: Node3D) -> void:
	_microphone = weakref(microphone)


func get_microphone() -> Node3D:
	return _microphone.get_ref() as Node3D if _microphone != null else null


## Where the console hears from: the stick, not the plug.
func microphone_position() -> Vector3:
	var microphone := get_microphone()
	return microphone.global_position if microphone != null else global_position


## The console whose card slot holds this plug, or null.
func seated_system() -> RetroSystem:
	var node: Node = get_picked_up_by()
	while node != null and not (node is RetroSystem):
		node = node.get_parent()
	return node as RetroSystem


## Which card slot, or -1.
func seated_slot() -> int:
	var system := seated_system()
	if system == null:
		return -1
	return system.memcard_slots().find(get_picked_up_by())
