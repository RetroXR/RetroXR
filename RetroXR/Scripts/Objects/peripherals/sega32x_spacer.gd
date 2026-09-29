## Sega32xSpacer — the riser Sega packed with the 32X for the Genesis Model 2.
##
## On a Model 2 the 32X's plug bottoms out in the console's edge connector with
## the unit standing ~13 mm clear of the roof, so it rocks on its plug; the spacer
## clips under the 32X and fills that gap. Here it is its own thing in the room:
## spawned from the 32X's card, clipped into the 32X's AccessoryMount, and carried
## with it from then on -- in a hand, and into the Mega Drive's slot, where its
## underside lies on the console's top (see expansion-carts.md 2j').
##
## Shaped after the N64 paks: a pickable a socket narrows by group, carrying no
## state. Which 32X it is clipped to is recorded on the 32X, the end that means
## something; this side is only a pose.
##
## The model (sega32x_spacer.glb) shares the 32X's frame -- y = 0 on the 32X's
## resting plane, front +Z -- so its identity GrabPoint seats it exactly under a
## 32X whose mount sits at the shell's origin.
class_name Sega32xSpacer
extends XRToolsPickable

## The group the 32X's mount takes (its row's `accessory_group`).
const GROUP := "sega32x_spacer"

## Height of the drop hint above the spacer, in metres; the default floats well
## clear of something this flat.
const HINT_HEIGHT := 0.08

var _hint: HeldHint = null


func _ready() -> void:
	super._ready()
	add_to_group("spawned")
	add_to_group(GROUP)
	_hint = HeldHint.attach(self, true, HINT_HEIGHT)


## The 32X this is clipped to, or null when it is loose.
func get_unit() -> RetroExpansion:
	var n := get_picked_up_by()
	while n != null:
		if n is RetroExpansion:
			return n as RetroExpansion
		n = n.get_parent()
	return null
