## RetroSystemModelWonderSwan — Bandai WonderSwan / Color (224×144 LCD).
## Real games switch between landscape and portrait — physically rotating the
## device in VR is exactly how it was meant to be played.
## Shell geometry lives in wonderswan.tscn; this only sets the cart size.
class_name RetroSystemModelWonderSwan
extends RetroSystemModelHandheld


func _init() -> void:
	cart_size = Vector3(0.048, 0.052, 0.008)   # WonderSwan cart
	_reflective_lcd = true   # a reflective LCD with no light of its own
