## Stills of the Wii U stand-ins: the console, the GamePad standing in its cradle
## with the WUP-011 plugged into the cradle's back, the Pro Controller, the two
## AC adapters. Windowed (no core):
##
##   "$godot" --path RetroXR --resolution 960x540 --position 20,20 \
##     res://DevTools/models/wiiu_render_probe.tscn -- [--out=<dir>]
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
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.85)
	add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 30, 0)
	add_child(light)
	var sys := preload("res://Scenes/Objects/system.tscn").instantiate() as RetroSystem
	sys.systemid = "wiiu"
	sys.freeze = true
	add_child(sys)
	sys.position = Vector3(-0.25, 0, 0)
	var cradle := preload("res://Scenes/Objects/peripherals/wiiu/wiiu_gamepad_cradle.tscn").instantiate() as WiiUGamePadCradle
	cradle.freeze = true
	add_child(cradle)
	cradle.position = Vector3(0.12, 0, 0.02)
	var pad := preload("res://Scenes/Objects/controllers/wiiu/wiiu_gamepad.tscn").instantiate() as RigidBody3D
	pad.freeze = true
	add_child(pad)
	pad.position = Vector3(0.12, 0.3, 0.2)
	# A second GamePad lying flat, for a grazing look at its glass (where a
	# glass level with its bezel z-fought).
	var flat := preload("res://Scenes/Objects/controllers/wiiu/wiiu_gamepad.tscn").instantiate() as RigidBody3D
	flat.freeze = true
	add_child(flat)
	flat.position = Vector3(0.45, 0.0, 0.25)
	var pro := preload("res://Scenes/Objects/controllers/wiiu/wiiu_pro_controller.tscn").instantiate() as RigidBody3D
	pro.freeze = true
	add_child(pro)
	pro.position = Vector3(-0.2, 0.02, 0.22)
	var bricks: Array = []
	for id: String in ["wiiu_gamepad_ac_adapter", "wiiu_ac_adapter"]:
		var b := preload("res://Scenes/Objects/power/power_brick.tscn").instantiate() as PowerBrick
		b.brick_id = id
		b.variant = "usa"
		b.position = Vector3(0.3 + 0.15 * bricks.size(), 0.03, -0.15)
		add_child(b)
		bricks.append(b)
	# The Classic TV behind the console, on HDMI from the Wii U's HDMI OUT.
	var tv := preload("res://Scenes/Objects/tv.tscn").instantiate() as RetroTV
	tv.freeze = true
	add_child(tv)
	tv.position = Vector3(-0.25, 0.2, -0.75)
	# A second set with nothing in its HDMI IN, to see the socket itself.
	var tv2 := preload("res://Scenes/Objects/tv.tscn").instantiate() as RetroTV
	tv2.freeze = true
	add_child(tv2)
	tv2.position = Vector3(1.2, 0.2, -0.75)
	var hdmi := preload("res://Scenes/Objects/cables/hdmi_cable.tscn").instantiate() as Node3D
	add_child(hdmi)
	hdmi.position = Vector3(-0.25, 0.05, -0.45)
	await _frames(20)
	(sys.find_child("HdmiOut", true, false) as XRToolsSnapZone).pick_up_object(hdmi.get_node("PlugA0"))
	(tv.get_node("HdmiPort") as XRToolsSnapZone).pick_up_object(hdmi.get_node("PlugB0"))
	(cradle.get_node("PadSeat") as XRToolsSnapZone).pick_up_object(pad)
	(cradle.get_node(WiiUGamePadCradle.INLET_NAME) as XRToolsSnapZone).pick_up_object((bricks[0] as PowerBrick).dc_plug)
	await _frames(90)
	# The boot curtain is head-locked to the current camera and would fill every shot.
	for o in LoadingOverlay.owners():
		LoadingOverlay.end(o)
	await _frames(120)
	var cam := Camera3D.new()
	cam.fov = 45.0
	cam.near = 0.005
	add_child(cam)
	cam.make_current()
	for shot in [["front", Vector3(0.0, 0.32, 0.7), Vector3(0.0, 0.05, 0.0)],
			["cradle", Vector3(0.22, 0.2, 0.32), Vector3(0.12, 0.06, 0.0)],
			["cradle_back", Vector3(0.05, 0.15, -0.3), Vector3(0.12, 0.04, 0.0)],
			["pad_flat", Vector3(0.45, 0.06, 0.5), Vector3(0.45, 0.0, 0.25)],
			["console_back", Vector3(-0.3, 0.12, -0.35), Vector3(-0.25, 0.02, -0.1)],
			["hdmi_console", Vector3(-0.2, 0.06, -0.24), Vector3(-0.239, 0.015, -0.134)],
			["tv_back", Vector3(-0.45, 0.16, -1.15), Vector3(-0.35, 0.11, -0.9)],
			["hdmi_tv", Vector3(-0.33, 0.13, -1.0), Vector3(-0.37, 0.11, -0.9)],
			["hdmi_socket", Vector3(1.08, 0.12, -0.99), Vector3(1.08, 0.11, -0.9)]]:
		cam.global_position = shot[1]
		cam.look_at(shot[2])
		await _frames(4)
		await RenderingServer.frame_post_draw
		var path := _out.path_join("wiiu_render_%s.png" % shot[0])
		get_viewport().get_texture().get_image().save_png(path)
		print("[wiiu-render] wrote %s" % path)
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
