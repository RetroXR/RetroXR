## DTerminalPort — a Japanese D-Terminal (D端子, EIAJ RC-5237) socket: a set's D IN.
##
## Component video (Y, Pb, Pr and the line-count bits) in ONE 14-pin plug, so to the
## routing it is one VIDEO socket, as SvideoPort is; TvSignal draws it as component.
## Its sound arrives on a white and a red phono beside it, as on the real lead. The
## three colour signals cannot be crossed or left out inside one plug, so the input
## is always full colour.
##
## The socket is RetroXR-models generic/dterminal-socket, the plug generic/dterminal-plug.
class_name DTerminalPort
extends RcaPort

const CONNECTOR := "dterminal_plug"


func _init() -> void:
	connector = CONNECTOR


func _own_connector() -> String:
	return CONNECTOR


func _ready() -> void:
	super._ready()
	channel = RcaPort.Channel.VIDEO
