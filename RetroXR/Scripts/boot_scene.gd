## The main scene. Replaces itself with the room SceneManager resolved for this
## launch.
class_name BootScene
extends Node

## An autoload whose start reads the data root joins this group from its _ready
## (through defer_or_load) instead of starting while a folder move is pending.
## BootScene finishes the move, then calls load_data_root() on every member in
## tree order, which is project.godot's autoload order, and SceneManager's boot
## comes after all of them. The group is the only list: an autoload that defers
## is replayed because it deferred, never because someone remembered to name it.
const DATA_ROOT_DEFERRED := &"data_root_deferred"


## Called from an autoload's _ready: start it now, or, while a data-root move is
## pending, register it to be started once BootScene has finished the move.
static func defer_or_load(loader: Node) -> void:
	if not DataPaths.migration_mode():
		loader.call(&"load_data_root")
		return
	print("[Boot] %s waits for the data-folder move" % loader.name)
	loader.add_to_group(DATA_ROOT_DEFERRED)


func _ready() -> void:
	if DataPaths.migration_mode():
		var move := DataRootMove.new()
		add_child(move)
		await move.finish_pending()
		move.queue_free()
		for loader: Node in get_tree().get_nodes_in_group(DATA_ROOT_DEFERRED):
			print("[Boot] data folder moved: starting %s" % loader.name)
			loader.remove_from_group(DATA_ROOT_DEFERRED)
			loader.call(&"load_data_root")
		# Last: resolving the room needs the rooms mods registered from the new root.
		SceneManager.start_boot()
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
