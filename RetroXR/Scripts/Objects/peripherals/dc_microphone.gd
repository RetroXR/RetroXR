## DcMicrophone — the Dreamcast Microphone (HKT-7200), which goes into a
## controller's expansion slot exactly as a VMU or a Jump Pack does.
##
## It has no button of its own. Every game that uses one talks on a controller
## button instead — A in Seaman, Y in Alien Front Online — so there is nothing
## here to press: the microphone is live whenever the game switches it on, as on
## the hardware. Seaman wants the pad in port A with a VMU in slot 1 and this in
## slot 2, which is why the core offers it in both slots.
##
## All this has to do is BE SEATED. Then flycast is told to fit a Microphone to
## the slot, the maple device is created, and the frontend's captured audio
## reaches the game through the core's microphone path. With nothing in a slot
## the option reads "None", no device is created, and a game that asks for sound
## hears nothing at all.
class_name DcMicrophone
extends XRToolsPickable

## What flycast's `reicast_device_port<N>_slot<S>` takes for one of these. The
## core's own spelling, matched in libretro.cpp against MDT_Microphone.
const OPTION_VALUE := "Microphone"

## Objects in this group seat in a VMU slot. Shared with VmuCard and JumpPack,
## because the socket takes any of them — see VmuPort.SLOT_GROUP.
const SLOT_GROUP := &"dc_slot_device"

@export var mic_label: String = "Microphone"

## Which slot this is in, or -1 when it is loose. Set by VmuPort.
var _slot := -1
var _pad: Node = null


func _ready() -> void:
	super._ready()
	add_to_group("spawned")
	# The slot requires this group, the same one every cable plug joins; the
	# group below then narrows the socket to things that belong in a VMU slot.
	add_to_group("controller_plug")
	add_to_group(SLOT_GROUP)
	add_to_group("dc_microphone")


## What flycast's per-slot device option should be set to.
func slot_option_value() -> String:
	return OPTION_VALUE


## Where this machine hears from, for the Microphone autoload's distance law.
## The pad carries it, so speaking near the hand holding the controller is what
## reaches the game.
func microphone_position() -> Vector3:
	return global_position


## Told by VmuPort which slot took this, and on which pad.
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
	return mic_label
