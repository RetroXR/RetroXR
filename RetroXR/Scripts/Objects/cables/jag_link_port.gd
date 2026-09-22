## The DSP port on the back of an Atari Jaguar -- where a JagLink interface
## (or ICD's CatBox) plugs in.
##
## Behind it is JERRY's UART, which the virtualjaguar fork carries on wire
## `jag-uart-1`. To the room it is a PlayStation serial socket with its own plug
## group: one console per end, no junction, link_port 0.
class_name JagLinkPort
extends PsxLinkPort


func plug_group() -> String:
	return "jag_link_plug"
