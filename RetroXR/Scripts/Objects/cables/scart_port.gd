## ScartPort — a 21-pin SCART (Peritel, EN 50049) socket: a European set's AV IN.
##
## One connector carrying the picture (RGB on the leads the game ships, composite on
## the cheap ones) and BOTH audio channels, so it is a MultiAvPort built as an input: the
## 32X's A/V IN arrangement. A SCART lead's cords 0-2 are video, L and R inside its one
## plug (CompositeCable.inner_cords), and channel_for(cord) reads them as the Multi Out at
## the console end does, so the set hears the machine on its own speakers with no phono
## pair beside it.
##
## The socket is RetroXR-models generic/scart-socket, the plug generic/scart-plug.
## TvSignal draws the input as RGB: the leads the game offers are RGB SCART leads.
class_name ScartPort
extends MultiAvPort

const CONNECTOR := "scart_plug"


func _init() -> void:
	connector = CONNECTOR
	input = true


func _own_connector() -> String:
	return CONNECTOR
