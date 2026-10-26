## One cabinet of a SpeakerPair — a plain pickable box.
##
## It carries no behaviour of its own on purpose. The pair owns the wire, the socket,
## the knob and the sink contract; a cabinet is only the thing you pick up and put
## down, and both of them being independently grabbable is the whole point of it
## being its own body rather than a mesh on the pair's root.
##
## Exists as a class rather than the addon's pickable.gd attached raw so that
## ScenePersistence and the pair can name what they are looking at.
class_name SpeakerBox
extends XRToolsPickable


## Bin the whole pair — both cabinets, the wire and whatever is in its socket — not just
## this cabinet. Freed alone, it left the pair holding a dead box, and the next autosave
## (SpeakerPair.box_poses) read global_position off it and crashed.
func drop_and_free() -> void:
	var root := get_parent()
	if is_instance_valid(root) and root.has_method("drop_and_free"):
		print("[SpeakerPair] cabinet '%s' binned — binning its pair '%s'" % [name, root.name])
		root.call("drop_and_free")
	else:
		Vanish.free_node(self)
