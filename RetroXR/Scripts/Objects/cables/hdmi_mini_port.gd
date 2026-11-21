## HdmiMiniPort — an HDMI Type C (mini) socket, as on cameras and small boards. A video socket whose sound rides the plug, as HdmiPort: a source's OUT is rf_feed. RetroXR-models generic/hdmi-mini-socket.
class_name HdmiMiniPort
extends RcaPort

const CONNECTOR := "hdmi_mini_plug"


func _init() -> void:
	connector = CONNECTOR


func _own_connector() -> String:
	return CONNECTOR


func _ready() -> void:
	super._ready()
	channel = RcaPort.Channel.VIDEO
