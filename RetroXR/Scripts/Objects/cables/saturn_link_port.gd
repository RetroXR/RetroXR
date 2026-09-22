## The Communication Connector on the back of a Sega Saturn -- the socket a Link
## Cable goes in.
##
## Behind it are the serial ports of both SH-2s (and the sound chip's MIDI
## pair), which is what the core's `saturn-sci-1` wire carries. To the room it is
## a PlayStation serial socket with a different plug group: one console per end,
## no junction, link_port 0. What it must NOT do is take a PlayStation lead, and
## the group is the whole of that.
class_name SaturnLinkPort
extends PsxLinkPort


func plug_group() -> String:
	return "saturn_link_plug"
