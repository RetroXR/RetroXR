## The infrared window on a machine: a link with no lead.
##
## A link cable is a thing in the room with two plugs, and a seated pair of
## them is what tells two cores they share a wire. Infrared has no such thing.
## The wire is whatever two windows can see, so this node only says where the
## window is and which way it looks, and IrBus -- one resolver for the whole
## room, as ILinkBus is for i.LINK -- decides which windows are a pair.
##
## The beam leaves along this node's local -Z, the way a cord leaves its anchor.
##
## To everything that asks "what is this machine linked to" it answers as a
## lead would: it is in LinkPlug.ANY_GROUP and has a `cable` that answers
## linked_machines(), held_machines() and rejoin(). That is what puts the
## machine at the far side of the beam into a netplay session, re-states the
## link when a core restarts, and keeps the partner in view in focus mode, with
## no sweep having to learn that infrared exists.
class_name IrPort
extends Node3D

## Which of the machine's link ports its core put the transceiver on. The Game
## Boy Color's is 1 (`gbc-ir`); port 0 is its link cable.
@export var link_port: int = 1

## Windows of one family see each other and nothing else, which is what a
## plug's family is to a socket: a remote control's receiver would be a window
## too, and it is no partner for a Game Boy.
@export var ir_family: String = "gbc_ir"

## The link came up or went down: both cores are on the bus and can hear each
## other. Not "a partner is in view" -- a window facing a machine whose core
## has no infrared port is in view of it and linked to nothing.
signal link_changed(live: bool)

var _live := false


func _ready() -> void:
	add_to_group(IrBus.PORT_GROUP)
	add_to_group(LinkPlug.ANY_GROUP)


func _exit_tree() -> void:
	# A machine carried out of the room, or the room torn down, is out of sight.
	IrBus.port_left(self)
	set_live(false)


func _physics_process(_delta: float) -> void:
	IrBus.watch(get_tree())


## The machine this window is on, or null. The walk LinkPort.get_machine does.
func get_machine() -> Node3D:
	var n: Node = get_parent()
	while n != null:
		if n.has_method("get_libretro_node"):
			return n as Node3D
		n = n.get_parent()
	return null


func get_libretro() -> Libretro:
	var machine := get_machine()
	if machine == null:
		return null
	return machine.call("get_libretro_node") as Libretro


## The way the window looks, in the room.
func beam_axis() -> Vector3:
	return (-global_transform.basis.z).normalized()


## The window this one is paired with, or null.
func partner() -> IrPort:
	return IrBus.partner_of(self)


## Whether the two cores are actually on the bus together.
func is_live() -> bool:
	return _live


func set_live(live: bool) -> void:
	if live == _live:
		return
	_live = live
	link_changed.emit(live)


# ── answering as a lead does ─────────────────────────────────────────────────

## What RetroSystem._link_cables and focus mode read off every member of
## LinkPlug.ANY_GROUP. The HEAD window of a pair, from both of its windows, so
## the pair is one lead to a sweep that keeps each lead once: two would be one
## bus counted twice.
var cable: Object:
	get:
		return IrBus.head_of(self)


## The bus this window is on, as [{machine, port}], head first, or [].
func linked_machines() -> Array[Dictionary]:
	return IrBus.bus_of(self)


## The same; a pair that has parted holds nothing.
func held_machines() -> Array[Dictionary]:
	return IrBus.bus_of(self)


## A machine whose core has just been restarted asks every lead touching it to
## take its bus off the wire and state it again (CompositeCable.rejoin).
func rejoin() -> void:
	IrBus.rejoin(self)
