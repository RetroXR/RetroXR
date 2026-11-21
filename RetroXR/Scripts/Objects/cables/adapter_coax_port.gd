## AdapterCoaxPort — an F-type female on an adapter: the 75 to 300 ohm balun's and the F to
## Belling-Lee adaptor's. An AdapterRcaPort (the jack belongs to whatever the adapter is
## plugged into, and a set files it on the input of the socket it is in), keyed for an F
## plug: an aerial's lead, an RF switch's pigtail.
class_name AdapterCoaxPort
extends AdapterRcaPort


func _init() -> void:
	connector = "coax_plug"


func _own_connector() -> String:
	return "coax_plug"
