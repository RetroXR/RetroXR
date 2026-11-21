## Jp21Port — a Japanese RGB21 (JP-21) socket: a set's RGB IN.
##
## The same 21-pin shell as SCART with the pins moved (RGB on other contacts, a
## different switching line), so a SCART lead in it gives a wrong picture and a JP-21
## lead in a SCART socket the same. The room models that as two CONNECTORS: a SCART plug
## is refused here, and the other way round. Otherwise ScartPort's arrangement: a
## MultiAvPort input carrying picture, L and R on one plug, drawn as RGB.
##
## The socket and plug wear RetroXR-models generic/scart-socket and generic/scart-plug,
## which is the real shell.
class_name Jp21Port
extends MultiAvPort

const CONNECTOR := "jp21_plug"


func _init() -> void:
	connector = CONNECTOR
	input = true


func _own_connector() -> String:
	return CONNECTOR
