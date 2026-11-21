## IecAerialPort — a Belling-Lee (IEC 61169-2, 9.5 mm) aerial socket: how a European
## or UK set takes its aerial and an RF modulator's lead.
##
## Another way into the set's RF input, beside the F-type (CoaxPort): to the routing
## it is the same VIDEO socket on the same input, and a set may carry both (TvInputKinds
## "rf" with "iec"). An F-type lead reaches it through the F to Belling-Lee adaptor.
##
## The socket is RetroXR-models generic/belling-lee-socket, the plug generic/belling-lee-plug.
class_name IecAerialPort
extends RcaPort

const CONNECTOR := "iec_aerial_plug"


func _init() -> void:
	connector = CONNECTOR


func _own_connector() -> String:
	return CONNECTOR


func _ready() -> void:
	super._ready()
	channel = RcaPort.Channel.VIDEO
