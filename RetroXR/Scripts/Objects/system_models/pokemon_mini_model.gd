## RetroSystemModelPokemonMini — Nintendo Pokémon mini (96×64 LCD).
## Tiny; it has a real shake sensor + rumble, so our accelerometer plumbing
## (SetSensorAccel) gets a second customer beyond the tilt carts.
## Shell geometry lives in pokemon_mini.tscn; this only sets the cart size.
class_name RetroSystemModelPokemonMini
extends RetroSystemModelHandheld


func _init() -> void:
	cart_size = Vector3(0.022, 0.033, 0.007)   # Pokemon mini cart
	_reflective_lcd = true   # a reflective LCD with no light of its own
