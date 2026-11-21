## HdmiMicroPort — an HDMI Type D (micro) socket. As HdmiMiniPort. RetroXR-models generic/hdmi-micro-socket.
class_name HdmiMicroPort
extends RcaPort

const CONNECTOR := "hdmi_micro_plug"


func _init() -> void:
	connector = CONNECTOR


func _own_connector() -> String:
	return CONNECTOR


func _ready() -> void:
	super._ready()
	channel = RcaPort.Channel.VIDEO
