## Frame cost of the bedroom at a fixed window size, with vsync off so a heavier frame shows
## as fewer frames rather than hiding under 60 Hz. Knows nothing of DesktopWindow or
## AppUpdate on purpose: it runs unchanged on a checkout that predates them, which is how
## a regression is told from the machine being busy.
##
##     XDG_DATA_HOME=/tmp/scratch "$godot" --path RetroXR --resolution 1280x720 \
##         res://Tools/room/fps_probe.tscn -- --label=mine
extends Node

const SCENE := preload("res://Scenes/BedroomScene.tscn")


func _ready() -> void:
	var label := "run"
	var zoom := 0.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--label="):
			label = a.trim_prefix("--label=")
		elif a.begins_with("--zoom="):
			zoom = float(a.trim_prefix("--zoom="))
	get_tree().create_timer(120.0).timeout.connect(func() -> void: get_tree().quit(1))
	add_child(SCENE.instantiate())
	await get_tree().create_timer(10.0).timeout
	if zoom > 0.0:
		# Only on a checkout that has DesktopWindow; the base one runs without --zoom.
		var cam := get_viewport().get_camera_3d()
		cam.fov = ProjectSettings.get_global_class_list().any(func(c: Dictionary) -> bool: return c["class"] == "DesktopWindow") \
			and 2.0 * rad_to_deg(atan(tan(deg_to_rad(75.0) * 0.5) / zoom)) or cam.fov
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	await get_tree().create_timer(2.0).timeout
	var rounds := 2 if OS.get_cmdline_user_args().has("--twice") else 1
	# --sizes=1280x720,1800x1000,1280x720: one round per size, the window set with Window.size.
	var sizes: PackedStringArray = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sizes="):
			sizes = a.trim_prefix("--sizes=").split(",")
			rounds = sizes.size()
	for round in rounds:
		if not sizes.is_empty():
			var parts := sizes[round].split("x")
			get_window().size = Vector2i(int(parts[0]), int(parts[1]))
			await get_tree().create_timer(2.0).timeout
		elif round > 0:
			# Time for something outside to resize the window, as a drag does.
			print("[fps] waiting for the drag")
			await get_tree().create_timer(14.0).timeout
		var t0 := Time.get_ticks_usec()
		var f0 := Engine.get_frames_drawn()
		await get_tree().create_timer(8.0).timeout
		var frames := Engine.get_frames_drawn() - f0
		var ms := (Time.get_ticks_usec() - t0) / 1000.0 / maxf(frames, 1)
		print("[fps] %s round %d: %d frames, %.2f ms/frame (%.1f fps)  window %s" % [label, round, frames, ms,
			1000.0 / ms, get_window().size])
	get_tree().quit(0)
