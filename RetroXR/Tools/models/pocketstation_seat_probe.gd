## The PocketStation in a PlayStation's card slot, and a picture on its screen.
##
## Seats one in a real PS1 (system.tscn, psx) and prints where its card edge and lid
## landed against the slot, then puts an asymmetric 32 x 32 "F" through the unit's own
## show_picture() on a second one lying loose, so a screen turned or mirrored shows as
## that. No core runs: the picture path is the one the core's frames take.
##
##     "$godot" --path RetroXR --resolution 320x240 --position 20,20 \
##         res://Tools/models/pocketstation_seat_probe.tscn -- --out=<dir>
##
## Windowed: the headless renderer returns a blank image at the right size.
extends Node

const UNIT := "res://Scenes/Objects/peripherals/pocketstation.tscn"
const SYSTEM := "res://Scenes/Objects/system.tscn"

var out_dir := ""


func _ready() -> void:
	out_dir = OS.get_user_data_dir()
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--out="):
			out_dir = str(arg).trim_prefix("--out=").replace("\\", "/")
	get_tree().create_timer(90.0).timeout.connect(func() -> void:
		print("[psseat] TIMEOUT")
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
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)
	_add_desk()

	var sys := (load(SYSTEM) as PackedScene).instantiate() as RetroSystem
	sys.systemid = "psx"
	add_child(sys)
	sys.global_position = Vector3(0, 0, 0)
	sys.freeze = true
	for i in range(20):
		await get_tree().physics_frame

	var seated := (load(UNIT) as PackedScene).instantiate() as PocketStation
	seated.card_id = "__PS_SEAT_PROBE"
	seated.card_label = "SEATED"
	add_child(seated)
	seated.global_position = Vector3(0, 0.2, 0.3)
	var slot: XRToolsSnapZone = sys.memcard_slots()[0]
	slot.pick_up_object(seated)
	for i in range(30):
		await get_tree().physics_frame
	var edge := (seated.get_node("Model/CardEdge") as Node3D).global_position
	var hinge := (seated.get_node("Model/LidHinge") as Node3D).global_position
	var mouth := slot.global_position
	print("[psseat] seated in slot 0: %s (is_seated %s); slot mouth at %s" % [
		sys.get_snapped_memcard(0) == seated, seated.is_seated(), mouth])
	print("[psseat] card edge %.1f mm into the console along -Z, hinge %.1f mm out; unit basis z %s" % [
		(mouth.z - edge.z) * 1000.0, (hinge.z - mouth.z) * 1000.0, seated.global_basis.z])
	print("[psseat] blocker while seated: '%s'" % seated.standalone_blocker())

	var loose := (load(UNIT) as PackedScene).instantiate() as PocketStation
	loose.card_id = "__PS_SEAT_PROBE_2"
	loose.card_label = "LOOSE"
	add_child(loose)
	loose.global_position = Vector3(0.25, 0.0075, 0.15)
	loose.freeze = true
	loose.show_picture(_f_texture())

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
	await _shot(sv, cam, mouth + Vector3(0.16, 0.13, 0.30), mouth + Vector3(0, -0.01, 0.0), "pocketstation_seated.png")
	await _shot(sv, cam, mouth + Vector3(0.0, 0.03, 0.12), mouth + Vector3(0, 0.0, 0.01), "pocketstation_seated_close.png")
	# Looking down with the infrared end (+Z in the unit's frame) at the top of the picture.
	var lp := loose.global_position
	await _shot(sv, cam, lp + Vector3(0, 0.12, -0.0015), lp, "pocketstation_screen.png")
	get_tree().quit(0)


## An "F": a stroke down the left, bars along the top and the middle. Turned, it reads
## upside down; mirrored, it faces the other way.
func _f_texture() -> Texture2D:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.62, 0.66, 0.55))
	var ink := Color(0.08, 0.09, 0.07)
	img.fill_rect(Rect2i(6, 4, 5, 24), ink)
	img.fill_rect(Rect2i(6, 4, 20, 5), ink)
	img.fill_rect(Rect2i(6, 14, 14, 4), ink)
	return ImageTexture.create_from_image(img)


func _add_desk() -> void:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, 0.02, 1.0)
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
	print("[psseat] wrote %s" % path)
