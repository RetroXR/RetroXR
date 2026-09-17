## N64VruMic — the NUS-021 microphone on the Voice Recognition Unit's cord.
##
## It has no button, and neither has the unit: the game decides when the VRU
## listens -- Hey You, Pikachu! while the player holds Z on their own controller
## -- and the core hears whatever the microphone picks up in that window. So this
## is only the thing the player speaks into, and the point the distance law
## measures from (RetroSystem.microphone_position).
class_name N64VruMic
extends XRToolsPickable

## Where the cord leaves the body, in this microphone's frame.
const CORD_EXIT := Vector3(0, 0, 0.048)

var _unit: N64Vru = null


func _ready() -> void:
	super._ready()
	add_to_group("spawned")


func set_unit(unit: N64Vru) -> void:
	_unit = unit
