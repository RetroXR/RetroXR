## Replays a saved room's objects through the ASYNC restore (what the loading overlay waits
## on), READ-ONLY: nothing is written. Prints each phase and whether it finishes.
##
##   "$godot" --headless --path RetroXR res://Tools/state/restore_room_probe.tscn -- --file=/path/slot.json
extends Node3D

var _file := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--file="):
			_file = a.substr(7)
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		print("[probe] TIMED OUT: the restore never finished")
		get_tree().quit(2))
	var sp := ScenePersistence.new("probe_readonly")
	var objects: Variant = sp._read_objects(_file)
	if not objects is Array:
		print("[probe] could not read ", _file)
		get_tree().quit(1)
		return
	print("[probe] %d objects" % (objects as Array).size())
	sp.restore_progress.connect(func(d: int, t: int) -> void: print("[probe] progress %d/%d" % [d, t]))
	var t0 := Time.get_ticks_msec()
	var spawned: Dictionary = await sp.instantiate_objects_async(self, objects as Array)
	print("[probe] FINISHED in %d ms with %d objects" % [Time.get_ticks_msec() - t0, spawned.size()])
	for i in 30:
		await get_tree().process_frame
	print("[probe] settled")
	get_tree().quit(0)
