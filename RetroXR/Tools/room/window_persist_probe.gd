## Does the desktop window come back the way the player left it?
##
## Two launches against ONE scratch user dir (it WRITES graphics_prefs.json -- run it
## with a scratch XDG_DATA_HOME):
##
##     --phase=set    opens the bedroom, picks a mode and a size the way the menu does,
##                    lets them settle and quits
##     --phase=drag   the same, but the size is dragged: Window.size set, nothing saved by
##                    the menu, so only the tracker can have remembered it
##     --phase=check  opens the bedroom and prints the window it got and the frame time
##
##     XDG_DATA_HOME=/tmp/scratch "$godot" --path RetroXR --resolution 960x600 \
##         res://Tools/room/window_persist_probe.tscn -- --phase=set --size=1280x720
extends Node

const SCENE := preload("res://Scenes/BedroomScene.tscn")


func _ready() -> void:
	var phase := "check"
	var size := "1280x720"
	var mode := "windowed"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--phase="):
			phase = a.trim_prefix("--phase=")
		elif a.begins_with("--size="):
			size = a.trim_prefix("--size=")
		elif a.begins_with("--mode="):
			mode = a.trim_prefix("--mode=")
	get_tree().create_timer(150.0).timeout.connect(func() -> void: get_tree().quit(1))
	add_child(SCENE.instantiate())
	await _seconds(8.0)
	print("[persist] %s: window %s mode %s saved %s/%s" % [phase, DisplayServer.window_get_size(),
		DesktopWindow.current_mode(), QualityManager.window_mode, QualityManager.resolution])
	if phase == "vert":
		# An outside script has just maximised the window vertically (what GNOME does when its
		# edge is dragged to the top of the screen). Ask for 640x480 the way the row does.
		for i in 14:
			await _seconds(1.0)
		print("[persist] before: Window.size %s DS %s mode %s" % [get_window().size,
			DisplayServer.window_get_size(), DesktopWindow.current_mode()])
		await DesktopWindow.apply_size("640x480", false, true)
		await _seconds(2.0)
		print("[persist] after 640x480: Window.size %s DS %s mode %s" % [get_window().size,
			DisplayServer.window_get_size(), DesktopWindow.current_mode()])
		get_tree().quit(0)
		return
	if phase == "sizes":
		# Every size the Resolution row can offer, asked for the way the row asks, and what
		# the window became. Width and height must come back in the order they were given.
		for step in DesktopWindow.SIZE_STEPS:
			DesktopWindow.apply_size(DesktopWindow.key_of(step))
			await _seconds(0.8)
			var got := get_window().size
			print("[persist] asked %-10s -> window %-10s viewport %s %s" % [DesktopWindow.key_of(step),
				DesktopWindow.key_of(got), get_viewport().get_visible_rect().size,
				"" if got == step else "   <-- differs"])
		get_tree().quit(0)
		return
	if phase == "watch":
		# Something outside resizes the window meanwhile (a WM, Tools/room's xlib script).
		for i in 44:
			print("[persist] t=%.1f DS %s Window.size %s saved %s" % [i * 0.5,
				DisplayServer.window_get_size(), get_window().size, QualityManager.resolution])
			await _seconds(0.5)
		get_tree().quit(0)
		return
	if phase == "set":
		DesktopWindow.apply_mode(mode)
		QualityManager.set_window_state(mode, "")
		DesktopWindow.apply_size(size)
		QualityManager.set_window_state("", size)
	elif phase == "drag":
		get_window().size = DesktopWindow.parse_key(size)
	if phase != "check":
		await _seconds(2.0)
		print("[persist] after: window %s mode %s saved %s/%s" % [DisplayServer.window_get_size(),
			DesktopWindow.current_mode(), QualityManager.window_mode, QualityManager.resolution])
	else:
		# Frame time with vsync off, so a doubled cost shows rather than hiding under 60 Hz.
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		await _seconds(3.0)
		var t0 := Time.get_ticks_usec()
		var f0 := Engine.get_frames_drawn()
		await _seconds(6.0)
		var frames := Engine.get_frames_drawn() - f0
		print("[persist] frames in 6 s: %d  (%.2f ms/frame), process %.2f ms" % [
			frames, (Time.get_ticks_usec() - t0) / 1000.0 / maxf(frames, 1),
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0])
	get_tree().quit(0)


func _seconds(s: float) -> void:
	await get_tree().create_timer(s).timeout
