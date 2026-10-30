## Renders a room's stock card picture (RoomCatalog `thumbnail`) through
## SceneThumbnail, from where the player stands on arriving. One room a process,
## windowed (headless draws nothing), in a scratch data home so none of the
## player's own objects are in it:
##
##     APPDATA=/tmp/scratch "$godot" --path RetroXR --resolution 320x240 --position 20,20 \
##         res://Tools/room/room_thumbnail_probe.tscn -- --room=bedroom [--out=user://x.png]
##         [--look=x,y,z] [--from=x,y,z]
##
## --from / --look place the eye instead (world metres), for a room whose arrival
## pose faces a wall. The shipped pictures: arcade, den and test from the arrival
## pose; bedroom with --from=-1.55,1.6,1.6 --look=1.0,1.0,-1.6 (its arrival pose
## looks straight at the window wall from a metre away).
extends Node


func _ready() -> void:
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		print("[thumb] TIMEOUT")
		get_tree().quit(1))
	var room_id := "bedroom"
	var out := ""
	var from: Variant = null
	var look: Variant = null
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--room="):
			room_id = a.trim_prefix("--room=")
		elif a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		elif a.begins_with("--from="):
			from = _vec(a.trim_prefix("--from="))
		elif a.begins_with("--look="):
			look = _vec(a.trim_prefix("--look="))
	if out.is_empty():
		out = RoomCatalog.thumbnail_of(room_id)
	if out.is_empty() or not RoomCatalog.has(room_id):
		print("[thumb] no room or no thumbnail path for '%s'" % room_id)
		get_tree().quit(1)
		return
	var room := (load(RoomCatalog.path_of(room_id)) as PackedScene).instantiate()
	add_child(room)
	# Long enough for the room's own deferred setup and the shader cache.
	await get_tree().create_timer(10.0).timeout
	var eye := get_viewport().get_camera_3d()
	if eye == null:
		print("[thumb] no camera in %s" % room_id)
		get_tree().quit(1)
		return
	if from != null:
		eye.global_position = from
	if look != null:
		eye.look_at(look, Vector3.UP)
	print("[thumb] eye at %s looking %s" % [eye.global_position, -eye.global_transform.basis.z])
	var path := ProjectSettings.globalize_path(out) if out.begins_with("res://") else out
	var ok: bool = await SceneThumbnail.capture(path, true)
	print("[thumb] %s -> %s: %s" % [room_id, path, "OK" if ok else "FAILED"])
	get_tree().quit(0 if ok else 1)


func _vec(text: String) -> Vector3:
	var p := text.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2]))
