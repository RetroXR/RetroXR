## RetroSystemModelGameGear — Sega Game Gear (landscape, 160×144 LCD).
## A wide black brick: pad on the left, buttons 1 and 2 on the right with the
## blue START above them, the EXT socket on the top edge for the Gear-to-Gear
## Cable. Shell geometry lives in game_gear.tscn; this only sets the cart size.
class_name RetroSystemModelGameGear
extends RetroSystemModelHandheld


func _init() -> void:
	cart_size = Vector3(0.068, 0.047, 0.012)   # Game Gear cart
