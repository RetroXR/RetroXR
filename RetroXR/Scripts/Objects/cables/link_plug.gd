## One end of a link cable.
##
## Everything that makes a lead work already lives in RcaPlug and its cable:
## what a cord carries is decided by the two sockets its ends sit in, not by the
## plug. The only thing that differs is which sockets will take it, and that is
## one string.
##
## Kept as its own connector rather than reusing an existing one because a link
## lead really does not fit anything else, and the whole point of a connector is
## that the room refuses connections that could not be made with the real hardware.
## It is also what will let an asymmetric cable work later: a GameCube-to-GBA
## lead is one cable whose two ends belong to different groups, so neither end
## can be pushed into the wrong socket.
class_name LinkPlug
extends RcaPlug

## Every link lead's plug joins this group as well as its own, for the sweeps
## that want "any link lead in the room" (RetroSystem._link_cables, focus mode):
## the handheld leads and the console ones (PlayStation, Saturn, Jaguar, i.LINK)
## alike, all of them this class with their own connector. One left out is a lead
## netplay never finds, so its far machine is not in the session and never starts.
## No socket filters on it -- a socket's snap_require is always a connector.
##
## What a sweep reads off a member is its `cable`, and that the cable answers
## linked_machines(). Nothing else is assumed of it, which is how a link with
## no plug at all is in here too: an IrPort, an infrared window whose `cable`
## is its pair's head window.
const ANY_GROUP := "any_link_plug"

## The GBA and Game Boy Color leads are "link_plug", which is the default; the
## original Game Boy's large connector, the Game Gear, WonderSwan, Lynx, Neo Geo
## Pocket and Virtual Boy leads share this scene's shape but each sets its own
## `connector` in its cable scene, so a Gear-to-Gear cable will not seat in a
## WonderSwan, nor a Color's lead in an original Game Boy.
func _init() -> void:
	connector = "link_plug"


func _ready() -> void:
	super._ready()
	add_to_group(ANY_GROUP)
