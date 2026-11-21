## DviIPort — a DVI-I socket: the TV's DVI IN. Every DVI plug fits it (DVI-D and DVI-A through Connectors.ALSO_FITS); RetroXR-models generic/dvi-i-socket.
class_name DviIPort
extends RcaPort

const CONNECTOR := "dvi_i_plug"


func _init() -> void:
	connector = CONNECTOR


func _own_connector() -> String:
	return CONNECTOR


func _ready() -> void:
	super._ready()
	channel = RcaPort.Channel.VIDEO
