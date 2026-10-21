## Where the spawn menu stands at each zoom, and what it looks like from there.
##
## Opens the bedroom, then for each zoom sets QualityManager.zoom, the camera's field of view as
## the Zoom slider would, shows the menu and measures its distance from the camera. WINDOWED, and
## with a scratch XDG_DATA_HOME (it moves the saved zoom):
##
##     XDG_DATA_HOME=/tmp/scratch "$godot" --path RetroXR --resolution 1280x720 \
##         res://Tools/room/menu_zoom_probe.tscn -- --out=/tmp/menu_zoom
extends Node

const SCENE := preload("res://Scenes/BedroomScene.tscn")


func _ready() -> void:
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out)
	get_tree().create_timer(120.0).timeout.connect(func() -> void: get_tree().quit(1))
	add_child(SCENE.instantiate())
	await get_tree().create_timer(10.0).timeout
	var ctrl: Node3D = null
	for n: Node in get_tree().root.find_children("*", "Node3D", true, false):
		var sc: Script = n.get_script()
		if sc != null and sc.resource_path.ends_with("spawn_menu_controller.gd"):
			ctrl = n
			break
	var cam := get_viewport().get_camera_3d()
	if ctrl == null or cam == null:
		print("[menuzoom] no controller (%s) or camera (%s)" % [ctrl, cam])
		get_tree().quit(1)
		return
	for z: float in [1.0, 2.0, 3.0, 4.0]:
		QualityManager.zoom = z
		cam.fov = DesktopWindow.zoomed_fov(75.0, z)
		ctrl.call("_show_menu")
		await get_tree().create_timer(1.0).timeout
		print("[menuzoom] zoom %.1f  factor %.1f  menu %.2f m from the camera  fov %.1f" % [z,
			DesktopWindow.menu_distance_factor(z), ctrl.global_position.distance_to(cam.global_position), cam.fov])
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join("zoom_%d.png" % int(z)))
		ctrl.call("_hide_menu")
		await get_tree().create_timer(0.3).timeout
	get_tree().quit(0)
