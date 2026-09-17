## N64VruMicPlug — the 3.5 mm plug on the end of the NUS-021's cord, which goes
## into the jack on the front of the Voice Recognition Unit.
##
## It has a group of its own rather than joining "controller_plug", which every
## cable plug in the room is in: a jack that filtered on that would take a console
## controller's plug as readily as this one. N64PakPort says the same thing about
## the pad's expansion bay, in as many words.
class_name N64VruMicPlug
extends XRToolsPickable

## What the unit's jack filters on.
const GROUP := &"vru_mic_plug"

## Where the cord leaves this plug, in its own frame: the outer end of the boot.
const CORD_EXIT := Vector3(0, 0, -0.026)

var _mic: N64VruMic = null

## The unit whose jack holds this, or null while it is out.
var seated_unit: Node3D = null


func _ready() -> void:
	super._ready()
	add_to_group("spawned")
	add_to_group(GROUP)


func set_microphone(mic: N64VruMic) -> void:
	_mic = mic


func get_microphone() -> N64VruMic:
	return _mic


## Where a machine hears from when this is in a jack: the microphone on the other
## end of the cord, not the plug.
func microphone_position() -> Vector3:
	return _mic.global_position if is_instance_valid(_mic) else global_position


## Called by the unit when this seats in its jack, and when it comes out.
func on_seated(unit: Node3D) -> void:
	seated_unit = unit


func on_pulled() -> void:
	seated_unit = null
