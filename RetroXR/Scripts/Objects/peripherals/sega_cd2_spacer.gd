## SegaCd2Spacer — the extension spacer Sega packed with the Sega CD Model 2 "for use
## with the original Genesis model".
##
## The Model 2's platform was made for the Genesis Model 2, 220 mm wide; a Model 1 is
## 280, so standing against the drive's receptacle it overhangs the platform's left end
## by about 58 mm. The spacer is a ribbed bar as tall as the base that clips along that
## end (screwed to it through the small joining plate under both), so the Model 1 has
## something under it there. It changes nothing the machine does.
##
## The 32X spacer's arrangement (Sega32xSpacer): a pickable carrying no state, spawned
## from the Sega CD's card, clipped into the drive's AccessoryMount (its row's
## `accessory_group`) and carried with it from then on. Which drive it is on is saved on
## the DRIVE ("accessory").
##
## A primitive stand-in (sega_cd2_spacer.tscn) in the drive's own frame -- RetroXR-models
## sega/sega-cd/console-2-spacer, read off auction photographs and the service manual's
## drawing, low confidence -- so its identity GrabPoint seats it exactly at the drive's
## left end.
class_name SegaCd2Spacer
extends XRToolsPickable

## The group the Sega CD's mount takes (its row's `accessory_group`).
const GROUP := "sega_cd2_spacer"

## Height of the drop hint above the spacer, in metres.
const HINT_HEIGHT := 0.08

var _hint: HeldHint = null


func _ready() -> void:
	super._ready()
	add_to_group("spawned")
	add_to_group(GROUP)
	_hint = HeldHint.attach(self, true, HINT_HEIGHT)


## The Sega CD this is clipped to, or null when it is loose.
func get_unit() -> RetroExpansion:
	var n := get_picked_up_by()
	while n != null:
		if n is RetroExpansion:
			return n as RetroExpansion
		n = n.get_parent()
	return null
