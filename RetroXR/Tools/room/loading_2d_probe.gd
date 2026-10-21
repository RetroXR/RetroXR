## The loading screen of a desktop run: flat, centred, over the picture. Puts the panel up over
## a lit cube (so a curtain that does not cover shows) at three window sizes and in a failed
## state, and photographs each. WINDOWED:
##
##     "$godot" --path RetroXR --resolution 1280x720 res://Tools/room/loading_2d_probe.tscn \
##         -- --out=/tmp/loading2d
extends Node3D


func _ready() -> void:
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(out)
	get_tree().create_timer(60.0).timeout.connect(func() -> void: get_tree().quit(1))
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	var cube := MeshInstance3D.new()
	cube.mesh = BoxMesh.new()
	cube.position = Vector3(0, 0, -3)
	add_child(cube)
	var sun := DirectionalLight3D.new()
	add_child(sun)
	sun.rotation_degrees = Vector3(-40, 30, 0)
	var panel: LoadingPanel = (load("res://Scenes/UI/loading_panel.tscn") as PackedScene).instantiate()
	add_child(panel)
	await get_tree().process_frame
	print("[load2d] flat screen: %s" % panel.shows_2d())
	panel.set_title("BEDROOM")
	panel.set_progress(0.42)
	panel.set_detail(PackedStringArray(["RECEIVING STATE", "1.0 / 4.0 MB"]))
	for size: Vector2i in [Vector2i(1280, 720), Vector2i(640, 360), Vector2i(1920, 1080)]:
		get_window().size = size
		await get_tree().create_timer(0.8).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(out.path_join("loading_%dx%d.png" % [size.x, size.y]))
		print("[load2d] %s photographed" % size)
	get_window().size = Vector2i(1280, 720)
	panel.show_load_error("RETRY OR CHOOSE ANOTHER ROOM")
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join("failed.png"))
	panel.visible = false
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out.path_join("hidden.png"))
	get_tree().quit(0)
