## The Dreamcast's AV OUT. Everything about how one hole carries three signals lives in
## MultiAvPort; the only thing that is the Dreamcast's own is which leads it accepts.
##
## Sega's own connector, not Nintendo's Multi Out: a flat keyed tongue in a 20 x 6 mm
## tunnel, shaped nothing like the 12-pin shell, so no N64 or Wii lead goes in and a
## Dreamcast lead goes into nothing else. The group is that shape.
class_name DcAvPort
extends MultiAvPort


func plug_group() -> String:
	return "dc_av_plug"
