## A Nintendo Multi AV socket — ONE hole carrying the picture and both audio channels.
##
## Every other socket in the room is one signal down one wire, which is why RcaPort can
## get away with a single `channel`. This connector is the exception the whole
## `channel_for(cord)` rule exists for: the lead seated here is a three-cord lead, and
## which signal a cord carries depends on which cord it is rather than on which socket
## it is in.
##
## The mapping is the CORD INDEX, and it is the same one every multi-out lead draws its
## far end in: cord 0 yellow to VIDEO, cord 1 white to L, cord 2 red to R. So a player
## who runs the lead's yellow plug into the set's yellow socket gets a picture, and one
## who crosses them gets exactly what crossing them does on the real hardware — which is
## the whole reason CompositeCable resolves routing from sockets instead of believing
## the colours.
##
## An RcaPort otherwise, and deliberately: GROUP membership so a plug can find the
## socket holding it, get_device() so the link resolves to the console, and the OUT/IN
## direction that decides which way a cord carries. CompositeCable._resolve reads
## RcaPort, and this is one.
##
## The jack visual is a child named for its own machine (WiiAvJack, N64AvJack), so
## RcaPort's own _tint_jack and show_jack — both of which look for a child named
## RcaJack — find nothing and no-op. That is wanted: this socket has no colour code.
##
## Used as it is by every machine with one: what differs between them is which lead
## fits, and that is the socket's `connector`, set in its scene ("n64_av_plug",
## "wii_av_plug", "dc_av_plug", "genesis_av_plug"). Nintendo used the same 12-pin
## shell on the SNES, N64, GameCube and Wii, but the pinouts are not the same and a
## Wii lead does not work on an N64 — which is why N64-to-Wii adapters are a product.
## Two connectors is how the room refuses a lead that would not have worked.
class_name MultiAvPort
extends RcaPort


## Cord index to signal. Indexed directly, so the order is the contract — see the note
## above and each lead's cord_colors, which has to match it.
const CORD_CHANNELS := [
	RcaPort.Channel.VIDEO,
	RcaPort.Channel.AUDIO_L,
	RcaPort.Channel.AUDIO_R,
]


## Out of range falls back to VIDEO rather than erroring: a lead with more cords than
## this connector has signals is a scene mistake, and one that silently carries the
## picture is easier to see than one that crashes the room.
func channel_for(cord: int) -> Channel:
	if cord < 0 or cord >= CORD_CHANNELS.size():
		return Channel.VIDEO
	return CORD_CHANNELS[cord]


## An A/V IN of this shape rather than a console's A/V OUT: the 32X's, which takes the
## console's own lead (Sega's Video Link Cable, mini-DIN at both ends) and passes it on
## to its A/V OUT beside it (ExpansionAv, AvGraph). Set in code before the socket enters
## the tree; never in a scene, so a console's socket cannot be made an input by mistake.
var input := false


## Show or hide the socket's own drawing of its mouth: a child named PanelJack, which a
## socket scene carries hidden when the hardware it belongs to moulds its own
## (genesis_av_port.tscn: the Genesis's shell and the 32X's do). A surface that moulds
## none -- the primitive box, a unit's plain box -- turns it on. False when the scene
## has none to show.
func draw_jack(on: bool) -> bool:
	var jack := get_node_or_null("PanelJack") as Node3D
	if jack == null:
		return false
	jack.visible = on
	return true


## A console's output, unless built as `input`. Pinned here rather than left to the scene
## for the reason VgaPort pins its own: every machine with this socket is a source, so an
## IN authored by mistake would be a silent dead lead.
func _ready() -> void:
	super._ready()
	direction = RcaPort.Direction.IN if input else RcaPort.Direction.OUT
	channel = RcaPort.Channel.VIDEO
