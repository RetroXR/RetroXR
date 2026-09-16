## The main scene. Replaces itself with the room SceneManager resolved for this
## launch.
extends Node


func _ready() -> void:
	# Before any room is built: nothing may compose a save path until saves have moved.
	SaveMigration.run_once(SaveSync)
	var room_id: String = SceneManager.current_scene_id
	var room := _instantiate(room_id)
	if room == null and room_id != SceneManager.default_room():
		room_id = SceneManager.default_room()
		room = _instantiate(room_id)
	if room == null:
		return
	SceneManager.current_scene_id = room_id
	print("[Boot] entering %s" % room_id)
	# The root is still readying its children, so the swap waits for the first frame.
	get_tree().change_scene_to_node.call_deferred(room)


func _instantiate(room_id: String) -> Node:
	var packed := load(RoomCatalog.path_of(room_id)) as PackedScene
	if packed == null:
		push_error("[Boot] cannot load room '%s'" % room_id)
		return null
	return packed.instantiate()
