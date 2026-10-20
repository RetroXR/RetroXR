## Loads a saved room the way the app does (the ASYNC restore the loading overlay waits on) and
## says how far it got: where "RESTORING OBJECTS n / m" would stop.
##
##   "$godot" --headless --path RetroXR res://Tools/room/load_slot_probe.tscn -- --room=bedroom --slot=c0357d79
extends Node3D

var _room := "bedroom"
var _slot := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--room="):
			_room = a.substr(7)
		elif a.begins_with("--slot="):
			_slot = a.substr(7)
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("[probe] STUCK: no finish in 60 s")
		get_tree().quit(2))
	var sp := ScenePersistence.new(_room)
	sp.restore_progress.connect(func(d: int, t: int) -> void: print("[probe] progress ", d, "/", t))
	var ok: bool = await sp.load_slot_async(self, _slot)
	print("[probe] finished ok=", ok, " children=", get_child_count())
	get_tree().quit(0)
