## The console end of a PlayStation 2 AV lead -- an RcaPlug wearing Sony's AV MULTI
## plug instead of a phono barrel. The same few lines DcAvPlug is: routing is the
## sockets' business, and the only thing this end decides is which socket takes it.
##
## The game ships no PlayStation 2 with that socket; a mod's console has it
## (ModConnectors "ps2_av_multi"), and this is the end of the stand-in lead the
## game offers until a mod brings the real one.
class_name Ps2AvPlug
extends RcaPlug


func plug_group() -> String:
	return "ps2_av_multi"
