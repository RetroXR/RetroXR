## JumpPack — the Dreamcast's rumble, as a thing you have to go and fetch.
##
## Sega's Puru Puru Pack. It goes into a controller's expansion slot exactly as a
## VMU does, and the two compete for the same two sockets: a pad with a card in
## slot 1 and a pack in slot 2 is the arrangement most players had, which is also
## flycast's own default for slot 2.
##
## It sends nothing to libretro itself, for the same reason RumblePak does not.
## The core drives haptics through RETRO_ENVIRONMENT_GET_RUMBLE_INTERFACE, which
## this project already answers all the way through to the hand holding the pad
## (RetroSystem._on_rumble_state_changed routes a port's rumble to that port's
## controller). All this has to do is BE SEATED, so flycast is told to fit a
## Purupuru to the slot and starts driving it at all.
##
## Which is the whole of the wiring: with no pack in a slot the option reads
## "None", the core creates no vibration device, and a game's rumble commands go
## nowhere. Seat one and the same commands reach your hand.
class_name JumpPack
extends XRToolsPickable

## What flycast's `reicast_device_port<N>_slot<S>` takes for one of these. The
## core's own spelling, matched in libretro.cpp against MDT_PurupuruPack.
const OPTION_VALUE := "Purupuru"

## Objects in this group seat in a VMU slot. Shared with VmuCard, because the
## socket takes either and has no way to tell them apart otherwise -- see
## VmuPort.SLOT_GROUP.
const SLOT_GROUP := &"dc_slot_device"

@export var pack_label: String = "Jump Pack"

## Which slot this pack is in, or -1 when it is loose. Set by VmuPort.
var _slot := -1
var _pad: Node = null


func _ready() -> void:
	super._ready()
	add_to_group("spawned")
	# The slot requires this group, the same one every cable plug joins. Being in
	# it is what makes a cable-less accessory seatable at all; the group below is
	# what then narrows the socket to things that belong in a VMU slot.
	add_to_group("controller_plug")
	add_to_group(SLOT_GROUP)
	add_to_group("jump_pack")


## What flycast's per-slot device option should be set to. VmuPort asks whatever
## is seated, so a pack and a card answer the same question differently.
func slot_option_value() -> String:
	return OPTION_VALUE


## Told by VmuPort which slot took this pack, and on which pad. Nothing here
## acts on it -- the rumble route is per PORT and the port belongs to the pad --
## but a pack that has been seated can say where it is.
func seated_in(pad: Node, slot: int) -> void:
	_pad = pad
	_slot = slot


func unseated() -> void:
	_pad = null
	_slot = -1


## Which slot this is in, or -1 loose.
func seated_slot() -> int:
	return _slot


func display_name() -> String:
	return pack_label
