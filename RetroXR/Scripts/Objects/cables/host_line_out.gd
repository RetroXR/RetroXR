## A phono LINE OUT on an expansion unit that carries its CONSOLE's sound (the Sega CD
## Model 2's LEFT and RIGHT).
##
## The AdapterJack arrangement: get_device() is the console the unit is bolted to while
## that console's sound reaches the unit (ExpansionAudio.carrier), so a lead from here
## to a set or an amplifier is one of the console's own audio outputs to AvSource, and
## null otherwise, so it carries nothing. Saved under the unit (save_owner), which owns
## the socket of this name whichever console is on it.
class_name HostLineOut
extends RcaPort


func _unit() -> RetroExpansion:
	var n: Node = get_parent()
	while n != null:
		if n is RetroExpansion:
			return n as RetroExpansion
		n = n.get_parent()
	return null


func get_device() -> Node3D:
	var unit := _unit()
	return ExpansionAudio.carrier(unit) if unit != null else null


func save_owner() -> Node3D:
	return _unit()
