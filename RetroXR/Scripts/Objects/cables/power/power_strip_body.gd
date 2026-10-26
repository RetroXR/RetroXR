## The power strip's case: the part a player actually picks up. Everything the
## strip DOES belongs to the PowerStrip root above it — the AntennaBody split.
class_name PowerStripBody
extends XRToolsPickable


## Bin the whole strip — cord, plug and whatever is in its sockets — not just the case.
func drop_and_free() -> void:
	var root := get_parent()
	if is_instance_valid(root) and root.has_method("drop_and_free"):
		root.call("drop_and_free")
	else:
		Vanish.free_node(self)
