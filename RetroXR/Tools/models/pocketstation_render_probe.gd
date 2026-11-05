## Renders the PocketStation primitive (Scenes/Objects/peripherals/pocketstation_model.tscn)
## beside a PlayStation memory card for scale: the face, from above, the side (the lid's
## step over the thinner base), the back, and one with the lid open on its hinge. Prints the
## model's measured size, so the 64 x 42 x 13.5 mm is checked by numbers as well as by eye.
##
##     "$godot" --path RetroXR --resolution 320x240 --position 20,20 \
##         res://Tools/models/pocketstation_render_probe.tscn -- --out=<dir>
##
## Windowed: the headless renderer returns a blank image at the right size.
extends Node

const MODEL := "res://Scenes/Objects/peripherals/pocketstation_model.tscn"
const CARD := "res://Scenes/Objects/media/memory_card.tscn"

var out_dir := ""


func _ready() -> void:
	out_dir = OS.get_user_data_dir()
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--out="):
			out_dir = str(arg).trim_prefix("--out=").replace("\\", "/")
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("[psrender] TIMEOUT")
		get_tree().quit(1))
	get_tree().current_scene = self
	_run()


func _run() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.30, 0.31, 0.34)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.52, 0.52, 0.55)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 25, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)
	_add_desk()

	var scene := load(MODEL) as PackedScene
	if scene == null:
		print("[psrender] FAILED to load %s" % MODEL)
		get_tree().quit(1)
		return
	# Resting on the desk: the back face is 6.75 mm below the origin, the discs on it 0.25 mm more.
	var rest := 0.0070
	var face := scene.instantiate() as Node3D
	add_child(face)
	face.position = Vector3(0, rest, 0)
	var back := scene.instantiate() as Node3D
	add_child(back)
	back.rotation_degrees = Vector3(0, 0, 180)
	back.position = Vector3(-0.075, 0.0070, 0)
	var open := scene.instantiate() as Node3D
	add_child(open)
	open.position = Vector3(0.075, rest, 0)
	(open.get_node("LidHinge") as Node3D).rotation_degrees.x = 70.0
	var card := (load(CARD) as PackedScene).instantiate() as RigidBody3D
	add_child(card)
	card.freeze = true
	card.position = Vector3(0, 0.0031, 0.075)

	var box := _aabb(face, face)
	print("[psrender] model size %.1f x %.1f x %.1f mm (W x T x L), min %s max %s" % [
		box.size.x * 1000.0, box.size.y * 1000.0, box.size.z * 1000.0, box.position, box.end])
	print("[psrender] lid hinge at %s; screen at %s" % [
		(face.get_node("LidHinge") as Node3D).position, (face.get_node("LidHinge/Screen") as Node3D).global_position - face.global_position])

	var sv := SubViewport.new()
	sv.size = Vector2i(1200, 900)
	sv.own_world_3d = false
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sv)
	var cam := Camera3D.new()
	cam.fov = 35.0
	sv.add_child(cam)
	for o in LoadingOverlay.owners():
		LoadingOverlay.end(o)
	LoadingOverlay.suspend()
	for i in range(20):
		await get_tree().process_frame
	var c := face.position
	# The infrared end at the top of the picture, as in the photographs.
	await _shot(sv, cam, c + Vector3(0.0, 0.17, 0.0015), c, "pocketstation_top.png")
	await _shot(sv, cam, c + Vector3(0.035, 0.075, 0.095), c + Vector3(0, 0, 0.004), "pocketstation_face.png")
	await _shot(sv, cam, c + Vector3(0.11, 0.012, 0.0), c + Vector3(0, 0.004, 0), "pocketstation_side.png")
	await _shot(sv, cam, back.position + Vector3(0.0, 0.15, 0.0001), back.position, "pocketstation_back.png")
	await _shot(sv, cam, open.position + Vector3(0.07, 0.07, 0.08), open.position + Vector3(0, 0.012, -0.004), "pocketstation_open.png")
	get_tree().quit(0)


## Combined bounds of every mesh under `node`, in `frame`'s space.
func _aabb(node: Node, frame: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for n in node.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		var local := frame.global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()
		out = local if first else out.merge(local)
		first = false
	return out


func _add_desk() -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 0.02, 0.5)
	shape.shape = box
	body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = box.size
	mesh.mesh = cube
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.34, 0.26)
	mat.roughness = 0.9
	mesh.material_override = mat
	body.add_child(mesh)
	add_child(body)
	body.position = Vector3(0, -0.01, 0)


func _shot(sv: SubViewport, cam: Camera3D, eye: Vector3, target: Vector3, file: String) -> void:
	cam.look_at_from_position(eye, target, Vector3.UP)
	cam.current = true
	for i in range(8):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	var path := out_dir.path_join(file)
	var img := sv.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	img.save_png(path)
	print("[psrender] wrote %s" % path)
