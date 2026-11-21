## Stills of the Classic TV's S-Video and component inputs, and of what each signal
## does to a picture (TvSignal). Windowed (no core):
##
##   "$godot" --path RetroXR --resolution 960x540 --position 20,20 \
##     res://DevTools/av/tv_inputs_render_probe.tscn -- [--out=<dir>]
##
## Shots: the back of a set with an N64 on its S-Video lead, a Wii on its component
## lead and a second Wii on its RGB SCART lead; the SCART socket empty; the empty row close up; and one test card drawn through crt_effect.gdshader as
## each input draws it, with the set's composite sliders turned up so the differences
## show (composite, S-Video, component, Y alone, Pb/Pr crossed).
extends Node3D

const CRT_SHADER := preload("res://Shaders/crt_effect.gdshader")

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
	light.rotation_degrees = Vector3(-40, 160, 0)
	add_child(light)

	var tv := preload("res://Scenes/Objects/tv.tscn").instantiate() as RetroTV
	tv.freeze = true
	add_child(tv)
	tv.position = Vector3(0.0, 0.2, 0.0)
	var empty := preload("res://Scenes/Objects/tv.tscn").instantiate() as RetroTV
	empty.freeze = true
	add_child(empty)
	empty.position = Vector3(1.5, 0.2, 0.0)

	var n64 := _console("n64", "nintendo_64", Vector3(0.35, 0.0, -0.6))
	var wii := _console("wii", "", Vector3(-0.2, 0.0, -0.6))
	var wii2 := _console("wii", "", Vector3(-0.6, 0.0, -0.6))
	var scart := preload("res://Scenes/Objects/system_models/wii/wii_scart_cable.tscn").instantiate() as Node3D
	add_child(scart)
	scart.position = Vector3(-0.5, 0.05, -0.4)
	var sv := preload("res://Scenes/Objects/system_models/nintendo_64/n64_svideo_cable.tscn").instantiate() as Node3D
	add_child(sv)
	sv.position = Vector3(0.3, 0.05, -0.4)
	var comp := preload("res://Scenes/Objects/system_models/wii/wii_component_cable.tscn").instantiate() as Node3D
	add_child(comp)
	comp.position = Vector3(-0.1, 0.05, -0.4)
	await _frames(30)
	(n64.find_child("AvMultiOut", true, false) as XRToolsSnapZone).pick_up_object(sv.get_node("PlugA0"))
	(wii.find_child("AvMultiOut", true, false) as XRToolsSnapZone).pick_up_object(comp.get_node("PlugA0"))
	(wii2.find_child("AvMultiOut", true, false) as XRToolsSnapZone).pick_up_object(scart.get_node("PlugA0"))
	(tv.get_node("ScartIn") as XRToolsSnapZone).pick_up_object(scart.get_node("PlugB0"))
	for pair in [["SvideoIn", sv, 0], ["AudioLInS", sv, 1], ["AudioRInS", sv, 2],
			["ComponentY", comp, 0], ["AudioLInC", comp, 1], ["AudioRInC", comp, 2],
			["ComponentPb", comp, 3], ["ComponentPr", comp, 4]]:
		(tv.get_node(pair[0]) as XRToolsSnapZone).pick_up_object((pair[1] as Node).get_node("PlugB%d" % pair[2]))
		await _frames(3)
	print("[tv-inputs] n64 on input %d, wii on input %d" % [
		tv.panel().input_holding(sv.get_node("PlugB0")), tv.panel().input_holding(comp.get_node("PlugB0"))])

	_card_strip(Vector3(0.0, 1.5, 0.0))
	await _frames(90)
	for o in LoadingOverlay.owners():
		LoadingOverlay.end(o)
	await _frames(120)

	var cam := Camera3D.new()
	cam.fov = 45.0
	cam.near = 0.005
	add_child(cam)
	cam.make_current()
	for shot in [["back", Vector3(-0.15, 0.4, -0.75), Vector3(0.05, 0.15, -0.15)],
			["leads", Vector3(0.12, 0.25, -0.42), Vector3(0.08, 0.17, -0.16)],
			["scart_lead", Vector3(-0.12, 0.22, -0.38), Vector3(-0.06, 0.17, -0.16)],
			["scart_socket", Vector3(1.46, 0.18, -0.36), Vector3(1.47, 0.16, -0.15)],
			["svideo_angled", Vector3(1.52, 0.2, -0.24), Vector3(1.546, 0.17, -0.15)],
			["svideo_close", Vector3(1.538, 0.176, -0.19), Vector3(1.546, 0.17, -0.151)],
			["row_empty", Vector3(1.58, 0.19, -0.36), Vector3(1.58, 0.17, -0.15)],
			["svideo_socket", Vector3(1.546, 0.18, -0.22), Vector3(1.546, 0.17, -0.15)],
			["signals", Vector3(0.0, 1.5, 0.78), Vector3(0.0, 1.5, 0.0)]]:
		cam.global_position = shot[1]
		cam.look_at(shot[2])
		await _frames(4)
		await RenderingServer.frame_post_draw
		var path := _out.path_join("tv_inputs_%s.png" % shot[0])
		get_viewport().get_texture().get_image().save_png(path)
		print("[tv-inputs] wrote %s" % path)
	get_tree().quit(0)


func _console(systemid: String, model_id: String, at: Vector3) -> RetroSystem:
	var sys := preload("res://Scenes/Objects/system.tscn").instantiate() as RetroSystem
	sys.systemid = systemid
	if not model_id.is_empty():
		sys.model_id = model_id
	sys.freeze = true
	add_child(sys)
	sys.position = at
	return sys


## The test card through the CRT stage, once per input kind, side by side.
func _card_strip(at: Vector3) -> void:
	var card := ImageTexture.create_from_image(_card_image())
	# The set's shipped composite defaults (TvDisplay: notch 1.0, smear 0.5), as each
	# input's kind scales them (TvSignal.SCALE).
	var notch := 1.0
	var smear := 0.5
	var rows := []
	for row: Array in [["composite", TvSignal.Kind.COMPOSITE, TvSignal.Chroma.FULL],
			["S-Video", TvSignal.Kind.SVIDEO, TvSignal.Chroma.FULL],
			["component", TvSignal.Kind.COMPONENT, TvSignal.Chroma.FULL],
			["Y alone", TvSignal.Kind.COMPONENT, TvSignal.Chroma.MONO],
			["Pb/Pr crossed", TvSignal.Kind.COMPONENT, TvSignal.Chroma.SWAPPED]]:
		rows.append([row[0], TvSignal.scaled(row[1], "crt_notch", notch),
			TvSignal.scaled(row[1], "crt_smear", smear), row[2]])
	var w := 0.32
	for i in rows.size():
		var row: Array = rows[i]
		var quad := MeshInstance3D.new()
		var mesh := QuadMesh.new()
		mesh.size = Vector2(w, w * 0.75)
		quad.mesh = mesh
		var mat := ShaderMaterial.new()
		mat.shader = CRT_SHADER
		mat.set_shader_parameter("source_tex", card)
		mat.set_shader_parameter("crt_enabled", true)
		mat.set_shader_parameter("crt_scanline_count", 240.0)
		mat.set_shader_parameter("crt_mask_triads", 160.0)
		mat.set_shader_parameter("crt_mask_rows", 80.0)
		mat.set_shader_parameter("crt_source_texel_size", Vector2(1.0 / 320.0, 1.0 / 240.0))
		mat.set_shader_parameter("crt_notch", row[1])
		mat.set_shader_parameter("crt_smear", row[2])
		mat.set_shader_parameter("crt_chroma", int(row[3]))
		mat.set_shader_parameter("crt_glass_reflection", 0.0)
		quad.material_override = mat
		add_child(quad)
		quad.position = at + Vector3((float(i) - 2.0) * (w + 0.02), 0.0, 0.0)
		var label := Label3D.new()
		label.text = row[0]
		label.pixel_size = 0.0006
		label.font_size = 40
		label.outline_size = 8
		add_child(label)
		label.position = quad.position + Vector3(0.0, -w * 0.375 - 0.03, 0.0)


## 320 x 240: color bars on top; under them a 1-pixel vertical dither (what the composite
## notch blends) beside solid gray; at the bottom saturated red and blue blocks with sharp
## edges against white (what chroma bleed smears), and a skin tone and sky blue (what a
## Pb/Pr swap turns green and orange).
func _card_image() -> Image:
	var img := Image.create(320, 240, false, Image.FORMAT_RGB8)
	var bars := [Color(0.75, 0.75, 0.75), Color(0.75, 0.75, 0), Color(0, 0.75, 0.75), Color(0, 0.75, 0),
		Color(0.75, 0, 0.75), Color(0.75, 0, 0), Color(0, 0, 0.75)]
	for x in 320:
		var bar: Color = bars[mini(x * bars.size() / 320, bars.size() - 1)]
		for y in 80:
			img.set_pixel(x, y, bar)
		for y in range(80, 160):
			if x < 160:
				img.set_pixel(x, y, Color.WHITE if x % 2 == 0 else Color(0.1, 0.1, 0.5))
			else:
				img.set_pixel(x, y, Color(0.55, 0.55, 0.75))
		for y in range(160, 240):
			var c := Color.WHITE
			if x >= 20 and x < 80:
				c = Color(0.9, 0.05, 0.05)
			elif x >= 100 and x < 160:
				c = Color(0.05, 0.1, 0.9)
			elif x >= 180 and x < 240:
				c = Color(0.93, 0.72, 0.58)
			elif x >= 260 and x < 310:
				c = Color(0.45, 0.7, 0.95)
			img.set_pixel(x, y, c)
	return img


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
