## RetroSystemModelNeoGeoPocket — SNK Neo Geo Pocket Color (160×152 LCD).
## Near-square screen; landscape body with a clicky microswitch stick.
## Shell geometry lives in neo_geo_pocket.tscn; this only sets the cart size.
class_name RetroSystemModelNeoGeoPocket
extends RetroSystemModelHandheld


func _init() -> void:
	cart_size = Vector3(0.048, 0.052, 0.008)   # NGP cart


## The headphone jack, on the bottom edge beside the volume control, right of
## center (reviews of the Pocket and the Pocket Color: volume, jack and the power
## socket along the bottom; the link port is in the top right corner).
func headphone_jack() -> Dictionary:
	return edge_jack(0.25)
