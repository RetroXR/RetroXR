## Windowed visual proof; no ROM, room, mods or user data needed.
## Captures before and after placement into build_out. Never run headless.
extends Node3D

var objects: Array[XRToolsPickable] = []
var previews: Array[RayFloorPreview] = []
var frame := 0
var caption: Label
var placed := false
var capture_ready := false
var record := false


func _ready() -> void:
	record = OS.get_cmdline_user_args().has("--record")
	if record:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../build_out/ray_floor_frames"))
	get_tree().create_timer(30.0).timeout.connect(func() -> void: get_tree().quit(1))
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("101c2a")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("a3b7cc")
	world.environment.ambient_light_energy = 0.7
	add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -25, 0)
	light.light_energy = 1.2
	add_child(light)
	var cam := Camera3D.new()
	add_child(cam)
	cam.position = Vector3(4.3, 4.6, 6.5)
	cam.look_at(Vector3(0, 0.9, 0))
	cam.fov = 48
	cam.make_current()
	var ground := StaticBody3D.new()
	add_child(ground)
	_mesh(ground, Vector3(12, 0.15, 10), Vector3(0, -0.075, 0), Color("25364b"), true)
	var table := StaticBody3D.new()
	add_child(table)
	_mesh(table, Vector3(2.2, 0.15, 1.8), Vector3(-1.35, 0.7, 0), Color("4e6072"), true)
	for x in [-2.2, -0.5]:
		for z in [-0.65, 0.65]:
			_mesh(table, Vector3(0.08, 0.7, 0.08), Vector3(x, 0.35, z), Color("34465a"))
	var small := _object(Vector3(0.85, 0.22, 0.55), Vector3(-1.35, 1.6, 0), Color("e5d8b5"))
	small.rotation_degrees = Vector3(15, -25, 5)
	_mesh(small, Vector3(0.38, 0.008, 0.27), Vector3(0, 0.114, -0.01), Color("35475b"))
	var large := _object(Vector3(0.8, 1.5, 0.7), Vector3(1.2, 2.2, 0), Color("b46342"))
	large.rotation_degrees = Vector3(-18, 25, -20)
	_mesh(large, Vector3(0.6, 0.52, 0.015), Vector3(0, 0.30, 0.36), Color("192e40"))
	_mesh(large, Vector3(0.62, 0.06, 0.12), Vector3(0, -0.10, 0.37), Color("e7b67b"))
	var canvas := CanvasLayer.new()
	add_child(canvas)
	caption = Label.new()
	caption.position = Vector2(12, 10)
	caption.add_theme_font_size_override("font_size", 15)
	caption.text = "RAY PLACEMENT\nHold Alt / A or X: preview\nRelease: place on the surface"
	canvas.add_child(caption)
	# Autoload owners register after ready; a standalone probe has no room boot
	# to retire them. Let the desktop curtain finish fading before photographing.
	await get_tree().process_frame
	await get_tree().process_frame
	for owner_id: Variant in LoadingOverlay.owners():
		LoadingOverlay.end(owner_id)
	await get_tree().create_timer(2.5).timeout
	capture_ready = true


func _mesh(parent: Node3D, size: Vector3, at: Vector3, color: Color, collision := false) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	mesh.material_override = material
	parent.add_child(mesh)
	mesh.position = at
	if collision:
		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		col.shape = shape
		parent.add_child(col)
		col.position = at


func _object(size: Vector3, at: Vector3, color: Color) -> XRToolsPickable:
	var obj := XRToolsPickable.new()
	obj.freeze = true
	obj.collision_layer = 4
	_mesh(obj, size, Vector3.ZERO, color, true)
	add_child(obj)
	obj.position = at
	objects.append(obj)
	var preview := RayFloorPreview.new()
	add_child(preview)
	preview.set_physics_process(false)
	previews.append(preview)
	return obj


func _physics_process(delta: float) -> void:
	if not placed:
		for i in objects.size():
			previews[i].update_for(objects[i], true, delta)


func _process(_delta: float) -> void:
	if not capture_ready or frame >= 100:
		return
	frame += 1
	var captured_frame := frame
	if captured_frame == 65:
		for i in objects.size():
			var result := RayFloorPreview.solve(objects[i], true)
			if result.is_empty():
				push_error("[floor_probe] missing placement")
				get_tree().quit(1)
				return
			RayFloorPreview.place(objects[i], result)
			previews[i].clear()
		placed = true
		caption.text = "PLACED FLAT AND UPRIGHT\nHeading preserved; tilt removed\nNo throw velocity"
	await RenderingServer.frame_post_draw
	if record:
		_capture("ray_floor_frames/%03d" % captured_frame)
	if captured_frame == 50:
		_capture("ray_floor_preview")
	if captured_frame == 100:
		_capture("ray_floor_placed")
		get_tree().quit(0)


func _capture(stem: String) -> void:
	var path := ProjectSettings.globalize_path("res://../build_out/%s.png" % stem)
	get_viewport().get_texture().get_image().save_png(path)
	print("[floor_probe] ", path)
