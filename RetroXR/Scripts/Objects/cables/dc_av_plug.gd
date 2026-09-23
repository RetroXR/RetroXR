## The console end of a Dreamcast stereo AV lead — an RcaPlug wearing Sega's AV OUT
## tongue instead of a phono barrel. The same few lines N64AvPlug is: routing is the
## sockets' business, and the only thing this end decides is which socket takes it.
## DcAvPort declares the matching side.
class_name DcAvPlug
extends RcaPlug


func plug_group() -> String:
	return "dc_av_plug"
