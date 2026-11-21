## DisplayPortPort — a full-size DisplayPort receptacle: a set's DISPLAYPORT IN, a
## computer's DisplayPort OUT.
##
## HdmiPort's arrangement: a video socket whose sound rides the same plug. A machine's
## DisplayPort OUT is made an `rf_feed` socket by its owner, so the set it reaches
## gets the sound on both speakers unless a phono or line-out cord already took it
## (AvSource.resolve, the RF modulator's rule). RGB to the picture (TvSignal).
##
## The socket is RetroXR-models generic/displayport-socket, the plug
## generic/displayport-plug (their faces from common/displayport.py).
class_name DisplayPortPort
extends RcaPort

const CONNECTOR := "displayport_plug"


func _init() -> void:
	connector = CONNECTOR


func _own_connector() -> String:
	return CONNECTOR


func _ready() -> void:
	super._ready()
	channel = RcaPort.Channel.VIDEO
