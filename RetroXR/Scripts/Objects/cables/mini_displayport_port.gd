## MiniDisplayPortPort — a Mini DisplayPort socket (a graphics card's, a laptop's). As DisplayPortPort: sound rides the plug from an rf_feed OUT. RetroXR-models generic/mini-displayport-socket.
class_name MiniDisplayPortPort
extends RcaPort

const CONNECTOR := "mini_displayport_plug"


func _init() -> void:
	connector = CONNECTOR


func _own_connector() -> String:
	return CONNECTOR


func _ready() -> void:
	super._ready()
	channel = RcaPort.Channel.VIDEO
