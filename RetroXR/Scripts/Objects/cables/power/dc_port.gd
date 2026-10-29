## A handheld's DC IN socket: the jack its own AC adapter's plug goes into.
##
## A Port and nothing more for now. The game ships no adapter of its own; a mod's
## brings the wall wart, its cord and the plug, which names this socket's family.
## What a seated adapter MEANS (charging, running off the mains) is that plug's
## business, as it is for the SP's EXT.2.
##
## One script for every adapter family: each socket scene
## (Scenes/Objects/cables/*_dc_port.tscn) writes its own `connector`, and that
## scene is also where this reads it back from when an export's conversion has
## written the base default over it (Port._own_connector), so a family is named in
## one place only.
class_name DcPort
extends Port


## What an export's scene conversion can undo: the connector the socket's own
## scene writes on its root.
func _own_connector() -> String:
	if scene_file_path.is_empty():
		return ""
	var packed := load(scene_file_path) as PackedScene
	if packed == null:
		return ""
	var state := packed.get_state()
	for i in state.get_node_property_count(0):
		if state.get_node_property_name(0, i) == &"connector":
			return str(state.get_node_property_value(0, i))
	return ""
