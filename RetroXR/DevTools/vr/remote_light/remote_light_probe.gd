extends Node3D
## Renders a TV remote with one key lit by the thumbstick (TVRemote._light_key), close up, and saves a PNG:
## how the lit key reads on this renderer. Windowed only. -- --out=<png> [--key=KeyOk] [--none] [--held] (--none: no key lit, the control; --held: the remote's own
## held outline on, as in a VR hand).

func _ready() -> void:
	get_tree().create_timer(30.0).timeout.connect(func(): print("[probe] timeout"); get_tree().quit(2))
	var out := "user://remote_light.png"
	var key := "KeyOk"
	var none := false
	var held := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		elif a.begins_with("--key="): key = a.substr(6)
		elif a == "--none": none = true
		elif a == "--held": held = true
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.18, 0.18, 0.2)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 30, 0)
	add_child(sun)
	var r := (load("res://Scenes/Objects/appliances/tv_remote.tscn") as PackedScene).instantiate() as TVRemote
	r.freeze = true
	add_child(r)
	for i in 10:
		await get_tree().process_frame
	var b := r.key_button(key)
	var cam := Camera3D.new()
	cam.fov = 30
	add_child(cam)
	cam.global_position = b.global_position + Vector3(0, 0.22, 0.12)
	cam.look_at(b.global_position, Vector3.UP)
	cam.make_current()
	# Held at a desk with the floating grid off (in memory only, never saved): the stick lights the keys.
	AppPrefs.remote_button_menu = false
	r.set("_desktop_held", true)
	r.set("_key_sel", key)
	if none:
		r.set("_key_sel", "")
	# --held: the remote's own outline on, as it is in a VR hand (PickableHighlight held state).
	if held:
		for h: Node in r.find_children("*", "PickableHighlight", true, false):
			h.set("_is_hand_held", true)
			h.call("_update_state")
			print("[probe] remote's held outline on: %s" % h.get_path())
	for i in 20:
		await get_tree().process_frame
	# The app's loading screen is a CanvasLayer over everything: out of the picture.
	for n: Node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	print("[probe] renderer=%s stencil_safe=%s key=%s selected=%s" % [RenderingServer.get_current_rendering_method(),
		QualityManager.stencil_safe(), key, b.is_selected()])
	var img := get_viewport().get_texture().get_image()
	img.save_png(out)
	print("[probe] saved %s %s" % [out, img.get_size()])
	get_tree().quit(0)
