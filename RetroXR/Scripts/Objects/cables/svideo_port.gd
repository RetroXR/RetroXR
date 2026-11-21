## SvideoPort — a 4-pin mini-DIN S-Video (Y/C) socket: a set's S-VIDEO IN.
##
## A video socket, as VgaPort and HdmiPort are: one connector, one signal for the
## routing (VIDEO), though it is two wires inside, luma and chroma kept apart, which
## is the whole difference it makes (TvSignal: no notch, so no lost detail). No
## sound: an S-Video lead carries its audio on a white and a red phono beside it,
## into the L and R jacks of the same input.
##
## The socket is RetroXR-models generic/svideo-socket (common/minidin.py's 4-pin), the
## plug generic/svideo-plug; a 6-pin PS/2 or any other mini-DIN is another connector
## and is refused here, as an S-Video plug is refused by them.
class_name SvideoPort
extends RcaPort

const CONNECTOR := "svideo_plug"


func _init() -> void:
	connector = CONNECTOR


func _own_connector() -> String:
	return CONNECTOR


func _ready() -> void:
	super._ready()
	channel = RcaPort.Channel.VIDEO
