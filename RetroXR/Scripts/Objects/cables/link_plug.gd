## One end of a link cable.
##
## Everything that makes a lead work already lives in RcaPlug and its cable:
## what a cord carries is decided by the two sockets its ends sit in, not by the
## plug. The only thing that differs is which sockets will take it, and that is
## one string.
##
## Kept as its own group rather than reusing an existing one because a link lead
## really does not fit anything else, and the whole point of plug_group() is that
## the room refuses connections that could not be made with the real hardware.
## It is also what will let an asymmetric cable work later: a GameCube-to-GBA
## lead is one cable whose two ends belong to different groups, so neither end
## can be pushed into the wrong socket.
class_name LinkPlug
extends RcaPlug

## Every handheld lead's plug joins this group as well as its own, for the sweeps
## that want "any link lead in the room" (RetroSystem._link_cables, focus mode).
## No socket filters on it -- a socket's snap_require is always a family.
const ANY_GROUP := "any_link_plug"

## Which handheld family's socket this plug fits, and nothing else. The GBA and
## Game Boy leads are "link_plug"; the Game Gear, WonderSwan, Lynx and Neo Geo
## Pocket leads share this scene's shape but each has its own family, set in its
## cable scene, so a Gear-to-Gear cable will not seat in a WonderSwan. Must be
## set before _ready, which is when the plug joins its group.
@export var plug_family: String = "link_plug"

const _LABELS := {
	"link_plug": "a Game Boy Advance link plug",
	"gg_link_plug": "a Gear-to-Gear cable plug",
	"ws_link_plug": "a WonderSwan communication cable plug",
	"comlynx_plug": "a ComLynx cable plug",
	"ngp_link_plug": "a Neo Geo Pocket link cable plug",
}


func plug_group() -> String:
	return plug_family


func plug_label() -> String:
	return _LABELS.get(plug_family, "a link cable plug")


func _ready() -> void:
	super._ready()
	add_to_group(ANY_GROUP)
