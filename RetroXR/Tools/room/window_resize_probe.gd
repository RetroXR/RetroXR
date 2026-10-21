## Does the desktop room survive being resized -- and does the window remember it?
##
## Opens the bedroom in a real window, then does to that window what a player does:
## drags it to odd shapes, picks a size from the Resolution row (DesktopWindow
## .apply_size), maximises it. After each, waits for the window to settle and
## prints what the window is, what QualityManager has saved, and writes a
## screenshot of the picture, so the framing (FOV, crosshair, overlays) can be
## looked at rather than assumed.
##
## WINDOWED, never --headless (the dummy renderer returns blank images). It
## WRITES graphics_prefs.json -- that is the point -- so run it with a scratch user
## dir or it overwrites the player's:
##
##     XDG_DATA_HOME=/tmp/scratch_home "$godot" --path RetroXR --resolution 960x600 \
##         --position 20,20 res://Tools/room/window_resize_probe.tscn -- --out=/tmp/resize_out
extends Node

const SCENE := preload("res://Scenes/BedroomScene.tscn")

## [label, how, size]. "drag" is a raw DisplayServer.window_set_size: on X11 that resizes
## the real window WITHOUT telling the Window node, which is the desync the code now
## avoids by never calling it (the probe still does, to show what it looks like);
## "pick" is the Resolution row.
const STEPS := [
	["drag_wide", "drag", Vector2i(1500, 600)],
	["drag_tall", "drag", Vector2i(700, 1000)],
	["drag_tiny", "drag", Vector2i(300, 200)],
	["pick_720p", "pick", Vector2i(1280, 720)],
	["pick_huge", "pick", Vector2i(7680, 4320)],
	["drag_wide_again", "drag", Vector2i(1500, 600)],
]

var _out := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
	if _out.is_empty():
		push_error("[probe] needs --out=<dir>")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(_out)
	get_tree().create_timer(120.0).timeout.connect(func() -> void: get_tree().quit(1))
	add_child(SCENE.instantiate())
	await _frames(90)
	await get_tree().create_timer(2.0).timeout
	print("[probe] start: window %s mode %s min_size %s tracker %s" % [
		DisplayServer.window_get_size(), DesktopWindow.current_mode(),
		get_window().min_size, DesktopWindow.instance != null])
	await _shot("00_start")
	var events := [0, 0]
	get_window().size_changed.connect(func() -> void: events[0] += 1)
	DesktopWindow.instance.settled.connect(func(_k: String) -> void: events[1] += 1)

	for step: Array in STEPS:
		var size: Vector2i = step[2]
		if step[1] == "drag":
			DisplayServer.window_set_size(size)
		else:
			DesktopWindow.apply_size(DesktopWindow.key_of(size))
		await get_tree().create_timer(DesktopWindow.SETTLE_SECONDS + 0.6).timeout
		await _report(str(step[0]), size)
		print("[probe]   size_changed %d, settled %d so far" % events)
		await _shot(str(step[0]))

	await _zoom_steps()
	DesktopWindow.apply_mode("maximized")
	await get_tree().create_timer(DesktopWindow.SETTLE_SECONDS + 0.8).timeout
	await _report("maximized", Vector2i.ZERO)
	await _shot("maximized")
	DesktopWindow.apply_mode("windowed")
	DesktopWindow.apply_size("1000x640")
	await get_tree().create_timer(DesktopWindow.SETTLE_SECONDS + 0.6).timeout
	await _report("back_to_windowed", Vector2i(1000, 640))
	get_tree().quit(0)


## The OPTIONS tab's Zoom slider, driven through its signal: the camera's field of
## view must follow, 1x leave it at the Field of View as set, and the value be saved.
func _zoom_steps() -> void:
	var options: Array = get_tree().root.find_children("*", "SpawnMenuOptionsView", true, false)
	var cam := get_viewport().get_camera_3d()
	if options.is_empty() or cam == null:
		print("[probe] zoom: no options view (%d) or camera (%s)" % [options.size(), cam])
		return
	for z: float in [1.0, 2.0, 4.0, 1.0]:
		(options[0] as SpawnMenuOptionsView).zoom_changed.emit(z)
		await _frames(4)
		print("[probe] zoom %.1fx -> camera fov %.2f  (QualityManager.zoom %.2f)" % [z, cam.fov, QualityManager.zoom])
		await _shot("zoom_%d" % int(z * 10))


func _report(label: String, asked: Vector2i) -> void:
	var viewport := get_viewport().get_visible_rect().size
	print("[probe]   X-side window %s, Window.size %s" % [DisplayServer.window_get_size(), get_window().size])
	print("[probe] %-16s asked %s  window %s  viewport %s  mode %s  saved %s/%s" % [
		label, asked, DisplayServer.window_get_size(), viewport,
		DesktopWindow.current_mode(), QualityManager.window_mode, QualityManager.resolution])


func _shot(label: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_out.path_join(label + ".png"))


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
