## ArcadePedalModule — a foot pedal on the floor in front of a cabinet. DRAWN, NOT ACTIVE.
##
## The kind is `pedal`. Time Crisis and its kin have one: the gun hides you while the pedal is
## up and peeks and shoots while it is down, which no game on a plain light gun does. How a pedal
## should reach the core (a button of the lightgun, a footswitch the VR player cannot press with
## a controller, or a key) is its own analysis (docs/dev/arcade.md); until that is decided the
## pedal is a picture. `active` stays false and nothing reads it, so the contract has a slot for
## it and a cabinet that draws one is still a valid cabinet.
class_name ArcadePedalModule
extends ArcadeModule

## Whether the pedal does anything. False until the input analysis is done; do not set it.
@export var active: bool = false


func _init() -> void:
	kind = ArcadeProfiles.KIND_PEDAL


## Nothing is read from a pedal that is not active.
func is_pressed() -> bool:
	return false
