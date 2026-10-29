## RetroSystemModelSupervision — Watara Supervision (160×160 LCD).
## A chunky Game Boy clone; square screen on a tall brick body.
## Shell geometry lives in supervision.tscn; this only sets the cart size.
class_name RetroSystemModelSupervision
extends RetroSystemModelHandheld


func _init() -> void:
	cart_size = Vector3(0.066, 0.070, 0.009)   # Supervision cart


## The headphone jack, on the bottom edge just left of center: the Supervision
## copied the Game Boy's layout, jack, volume and contrast included.
func headphone_jack() -> Dictionary:
	return edge_jack(-0.052)
