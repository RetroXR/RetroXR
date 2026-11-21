## Stills of the PC tower's graphics card: DVI-D, DisplayPort and Mini DisplayPort OUT,
## empty and with their leads seated. Windowed:
##
##   "$godot" --path RetroXR --resolution 960x540 --position 20,20 \
##     res://DevTools/av/tower_video_outs_probe.tscn -- [--out=<dir>]
extends Node3D

var _out := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	if _out.is_empty():
		_out = OS.get_user_data_dir()
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.2, 0.21, 0.24)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.85, 0.85, 0.9)
	add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-30, 160, 0)
	add_child(light)
	var towers: Array = []
	for i in 2:
		var sys := preload("res://Scenes/Objects/system.tscn").instantiate() as RetroSystem
		sys.systemid = "dos"
		sys.model_id = "pc_tower"
		sys.freeze = true
		add_child(sys)
		sys.position = Vector3(i * 0.6, 0, 0)
		towers.append(sys)
	await _frames(40)
	var seated := towers[1] as Node3D
	for row: Array in [["res://Scenes/Objects/cables/dvi_cable.tscn", "DviOut"],
			["res://Scenes/Objects/cables/displayport_cable.tscn", "DisplayPortOut"],
			["res://Scenes/Objects/cables/mini_displayport_cable.tscn", "MiniDisplayPortOut"]]:
		var lead := (load(row[0]) as PackedScene).instantiate() as Node3D
		add_child(lead)
		lead.position = seated.position + Vector3(0, 0.1, -0.5)
		await _frames(5)
		(seated.find_child(row[1], true, false) as XRToolsSnapZone).pick_up_object(lead.get_node("PlugA0"))
	await _frames(60)
	for o in LoadingOverlay.owners():
		LoadingOverlay.end(o)
	await _frames(60)
	var cam := Camera3D.new()
	cam.fov = 40.0
	cam.near = 0.005
	add_child(cam)
	cam.make_current()
	for i in 2:
		var back := (towers[i] as Node3D).find_child("DviOut", true, false) as Node3D
		var target := back.global_position + Vector3(0, -0.02, 0)
		cam.global_position = target + Vector3(0.06, 0.05, -0.2)
		cam.look_at(target)
		await _frames(4)
		await RenderingServer.frame_post_draw
		var path := _out.path_join("tower_video_outs_%s.png" % ["empty", "seated"][i])
		get_viewport().get_texture().get_image().save_png(path)
		print("[tower-outs] wrote %s" % path)
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
