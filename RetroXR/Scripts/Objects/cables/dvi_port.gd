## DviPort — a DVI-D socket: a set's DVI IN, a computer's DVI OUT.
##
## A video socket, as VgaPort and HdmiPort are: one connector, one signal for the
## routing (VIDEO), RGB to the picture (TvSignal). DVI carries no sound: a computer's
## audio leaves on its own jacks, exactly as with VGA.
##
## The socket is RetroXR-models generic/dvi-socket, the plug generic/dvi-plug (their
## faces from common/dvi.py).
class_name DviPort
extends RcaPort

## A DVI-D socket. DVI-D plugs (single or dual link) fit it; a DVI-I or DVI-A plug does
## not (their analog pins and cross blade hit), which is Connectors.ALSO_FITS's to say.
const CONNECTOR := "dvi_d_plug"


func _init() -> void:
	connector = CONNECTOR


func _own_connector() -> String:
	return CONNECTOR


func _ready() -> void:
	super._ready()
	channel = RcaPort.Channel.VIDEO
