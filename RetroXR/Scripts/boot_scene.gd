## The main scene. Replaces itself with the room SceneManager resolved for this
## launch.
extends Node


func _ready() -> void:
	_warn_if_stock_engine()
	# Before any room is built: nothing may compose a save path until saves have moved.
	SaveMigration.run_once(SaveSync)
	SystemIdMigration.run_once(SaveSync)
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


## The Quest must run the engine built from docs/godot-4.7.2-*.patch. Stock
## 4.7.2 deadlocks at boot there, on the loading screen, and from inside a
## headset that looks exactly like a slow load. Godot's official builds call
## themselves "official"; ours are "custom_build". Said once, loudly, so the
## first lines of a logcat name the cause.
func _warn_if_stock_engine() -> void:
	if OS.has_feature("android") and str(Engine.get_version_info().get("build", "")) == "official":
		push_error("[Boot] running STOCK Godot %s, not RetroXR's patched engine: it can hang on the loading screen. Export with Tools/place_engine.py (docs/dev/engine-patches.md)."
			% str(Engine.get_version_info().get("string", "?")))


func _instantiate(room_id: String) -> Node:
	var packed := load(RoomCatalog.path_of(room_id)) as PackedScene
	if packed == null:
		push_error("[Boot] cannot load room '%s'" % room_id)
		return null
	return packed.instantiate()
