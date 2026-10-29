## RetroSystemModelAtariLynx — Atari Lynx (landscape, 160×102 LCD).
## Flippable in real life for left-handers; in VR you just turn it over.
## Shell geometry lives in atari_lynx.tscn; this only sets the cart size.
class_name RetroSystemModelAtariLynx
extends RetroSystemModelHandheld


func _init() -> void:
	cart_size = Vector3(0.073, 0.086, 0.006)   # Lynx card


## The headphone socket, on the bottom edge beside the ComLynx jack (LinkPort in
## atari_lynx.tscn, at x -0.06), on its inboard side, 14 mm along.
func headphone_jack() -> Dictionary:
	return {"position": Vector3(-0.046, 0.0, body_size.z * 0.5), "normal": Vector3(0, 0, 1)}
