## The headset itself: the part of the headphones a player picks up and puts on.
##
## A pickable and its forwards, as AntennaBody is: everything the headphones DO belongs to the Headphones root above
## it (a CompositeCable, which has no body to grab). The generic menu (ObjectOptionsPanel) opens over whatever
## pickable the pointer hit, which is this, so its rows are asked of the root.
class_name HeadphonesBody
extends XRToolsPickable

## What its menu is titled.
var display_name := "Headphones"


func options_choices() -> Array:
	var root := get_parent()
	return root.call("options_choices") if is_instance_valid(root) and root.has_method("options_choices") else []


func options_choose(row: int, item: int) -> void:
	var root := get_parent()
	if is_instance_valid(root) and root.has_method("options_choose"):
		root.call("options_choose", row, item)


## Bin the whole headset with its cord, not just the body.
func drop_and_free() -> void:
	var root := get_parent()
	if is_instance_valid(root) and root.has_method("drop_and_free"):
		root.call("drop_and_free")
	else:
		Vanish.free_node(self)
