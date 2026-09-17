## N64VruMic — the NUS-021 microphone on the Voice Recognition Unit's cord.
##
## It has no button, and neither has the unit: the game decides when the VRU
## listens -- Hey You, Pikachu! while the player holds Z on their own controller
## -- and the core hears whatever the microphone picks up in that window. So this
## is only the thing the player speaks into, and the point the distance law
## measures from (RetroSystem.microphone_position).
class_name N64VruMic
extends XRToolsPickable

## Where the cord leaves the body, in this microphone's frame: the mouth of the
## strain-relief boot on the tail. Moves with the tail — the rope anchors here, so
## a stale figure leaves the cord starting inside the shell or hanging off nothing.
const CORD_EXIT := Vector3(0, 0, 0.06)

var _unit: N64Vru = null
var _plug: N64VruMicPlug = null


func _ready() -> void:
	super._ready()
	add_to_group("spawned")


func set_unit(unit: N64Vru) -> void:
	_unit = unit


func set_plug(plug: N64VruMicPlug) -> void:
	_plug = plug


## The 3.5 mm plug on the other end of this microphone's cord.
func get_plug() -> N64VruMicPlug:
	return _plug


## The unit this microphone's plug is in, or null while it is out of the jack.
func connected_unit() -> Node3D:
	return _plug.seated_unit if is_instance_valid(_plug) else null
