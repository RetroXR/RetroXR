## Does the loading screen ever let the room show through? Boots a room, then changes to another
## with the real SceneManager, and from the first frame to the last looks at what was DRAWN: a
## frame whose four corners are not the curtain's near-black is a frame the room showed in.
## One line per frame that is not covered, with the owners that were registered at the time.
## WINDOWED, scratch XDG_DATA_HOME:
##
##     XDG_DATA_HOME=/tmp/scratch "$godot" --path RetroXR --resolution 640x360 \
##         res://Tools/room/loading_gap_probe.tscn -- --to=arcade
extends Node

var _frame := 0
var _log: PackedStringArray = []
var _was_covered := true
var _gaps := 0


func _ready() -> void:
	var to := "arcade"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--to="):
			to = a.trim_prefix("--to=")
	get_tree().create_timer(170.0).timeout.connect(func() -> void: get_tree().quit(1))
	SceneManager.current_scene_id = "bedroom"
	var packed := load(RoomCatalog.path_of("bedroom")) as PackedScene
	var room := packed.instantiate()
	# Not change_scene_to_node: that frees the current scene, which is this probe.
	_enter.call_deferred(room)
	_watch.call_deferred(to)


func _enter(room: Node) -> void:
	get_tree().root.add_child(room)
	get_tree().current_scene = room


func _covered() -> Array:
	var img := get_viewport().get_texture().get_image()
	var w := img.get_width()
	var h := img.get_height()
	var dark := 0
	var samples := 0
	for p: Vector2i in [Vector2i(2, 2), Vector2i(w - 3, 2), Vector2i(2, h - 3), Vector2i(w - 3, h - 3),
			Vector2i(w / 2, 2), Vector2i(w / 2, h - 3)]:
		var c := img.get_pixelv(p)
		samples += 1
		# The curtain is (0.008, 0.01, 0.025); a lit room is nothing like it.
		if c.r < 0.06 and c.g < 0.06 and c.b < 0.09:
			dark += 1
	return [dark == samples, dark, samples]


func _watch(to: String) -> void:
	var phase := "boot"
	var settled := 0
	var changed := false
	while true:
		await RenderingServer.frame_post_draw
		_frame += 1
		var c := _covered()
		if _frame in [1, 2, 3, 4, 70, 72, 74, 76, 80, 86, 88, 89, 90]:
			get_viewport().get_texture().get_image().save_png("/home/xargon/.cache/pj_probe/gap_f%04d.png" % _frame)
		var owners := LoadingOverlay.owners()
		var line := "[gap] f%04d %-6s covered=%s (%d/%d) owners=%s overlay=%s" % [_frame, phase, c[0], c[1], c[2], owners,
			LoadingOverlay.is_active()]
		# Only an UNCOVERED frame while something is loading is the bug; a room on screen after
		# the screen has come down is the goal.
		if not c[0] and (LoadingOverlay.is_active() or phase == "change"):
			_gaps += 1
			print(line + "   <-- the room shows")
		if _frame % 60 == 0:
			print(line)
		if phase == "boot" and not LoadingOverlay.is_active() and SceneManager.is_scene_content_ready("bedroom") and _frame > 30:
			settled += 1
			if settled > 40 and not changed:
				changed = true
				phase = "change"
				print("[gap] -- booted at frame %d; changing to %s" % [_frame, to])
				SceneManager.change_scene(to)
		elif phase == "change" and changed and not LoadingOverlay.is_active() and SceneManager.is_scene_content_ready(to):
			settled += 1
			if settled > 100:
				break
	print("[gap] done after %d frames: %d uncovered while loading" % [_frame, _gaps])
	get_tree().quit(0 if _gaps == 0 else 2)
