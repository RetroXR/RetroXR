## Photographs the six seats side by side, with a marker where each one puts the eyes and where it lets
## the player up (EyePoint, StandPoint). WINDOWED, never --headless: the dummy renderer returns a
## correctly sized BLANK image.
##
##   "$godot" --path RetroXR res://Tools/models/seats_probe.tscn --resolution 1280x560 --position 20,20 -- --out=/some/dir
##
## One PNG: seats.png (front, then `seats_side.png` from the side).
extends Node3D

const FAMILIES: Array[String] = ["seat_racing", "seat_stool", "seat_chair", "seat_cushion", "seat_sofa", "seat_bed"]


func _ready() -> void:
	var out := "/tmp"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	get_tree().create_timer(60.0).timeout.connect(func() -> void: get_tree().quit(2))
	for o in LoadingOverlay.owners():
		LoadingOverlay.end(o)
	LoadingOverlay.suspend()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.10, 0.11, 0.15)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.66)
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(14, 0.02, 6)
	floor_mesh.mesh = fm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.32, 0.30, 0.34)
	floor_mesh.material_override = fmat
	floor_mesh.position.y = -0.01
	add_child(floor_mesh)
	var x := -4.6
	for id in FAMILIES:
		var seat := (load("res://Scenes/Objects/furniture/%s.tscn" % id) as PackedScene).instantiate() as Seat
		seat.freeze = true
		seat.position = Vector3(x, 0.0, 0.0)
		add_child(seat)
		x += 1.9 if id != "seat_sofa" else 2.4
		for marker in [["EyePoint", Color(1.0, 0.9, 0.1)], ["StandPoint", Color(0.2, 1.0, 0.4)]]:
			var m := seat.find_child(marker[0], false, false) as Node3D
			var dot := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.04
			sm.height = 0.08
			var mat := StandardMaterial3D.new()
			mat.albedo_color = marker[1]
			mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			sm.material = mat
			dot.mesh = sm
			m.add_child(dot)
	var cam := Camera3D.new()
	cam.fov = 55.0
	add_child(cam)
	cam.current = true
	cam.position = Vector3(0.2, 1.7, 5.0)
	cam.look_at(Vector3(0.2, 0.6, 0.0), Vector3.UP)
	await _shot(out + "/seats.png")
	cam.position = Vector3(8.5, 1.6, 0.4)
	cam.look_at(Vector3(0.2, 0.6, 0.4), Vector3.UP)
	cam.fov = 40.0
	await _shot(out + "/seats_side.png")
	get_tree().quit(0)


func _shot(path: String) -> void:
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	print("[probe] saved ", path, " ", img.get_size(), " err=", img.save_png(path))
