## HdmiPort — an HDMI Type A socket: a set's HDMI IN, a console's HDMI OUT.
##
## A video socket, as VgaPort is. HDMI carries the sound on the same plug: a console's
## HDMI OUT is made an `rf_feed` socket by its owner, so the set it reaches gets the
## machine's sound on both speakers unless a phono or Multi-Out audio cord has
## already taken it (AvSource.resolve, the RF modulator's rule).
##
## The socket is RetroXR-models generic/hdmi-socket (common/hdmi.py's numbers), its
## dark surround standing 0.8 mm proud: the plug's overmold stops on that face, so
## the zone (where a seated plug's origin goes) is there and the socket model sits
## 0.8 mm behind it (hdmi_port.tscn).
class_name HdmiPort
extends RcaPort


func _init() -> void:
	connector = "hdmi_plug"


func _own_connector() -> String:
	return "hdmi_plug"


func _ready() -> void:
	super._ready()
	channel = RcaPort.Channel.VIDEO
