## The console end of the Genesis Model 2 A/V lead — an RcaPlug wearing a 9-pin
## mini-DIN instead of a phono barrel.
##
## The same few lines N64AvPlug and WiiAvPlug are: what a cord carries is decided by
## the two sockets its ends sit in, so the plug only says which sockets will take it.
## GenesisAvPort declares the matching side.
class_name GenesisAvPlug
extends RcaPlug


func plug_group() -> String:
	return "genesis_av_plug"
