## How the RETRO XR headphones LOOK in the game, windowed, into its own SubViewport (headphones_tests checks them
## headless):
##   godot --path RetroXR res://Tools/av/headphones_probe.tscn --resolution 320x240 --position 20,20 --fixed-fps 30 -- --out=<dir>
## Writes hero.png (the headset standing on its cups, its cord out to the plug), plugged.png (the plug in a Game Boy
## Color's headphone jack) and frames/f_NNNN.png: the plug carried to the jack and pushed in along it, at a fixed
## 30 fps step. Prints [probe] lines, including the handheld's route once seated. Encode frames/ with imageio.
extends Node

const HEADPHONES := preload("res://Scenes/Objects/appliances/headphones.tscn")
const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")

var _out := ""
var _view: SubViewport
var _cam: Camera3D
var _n := 0


func _ready() -> void:
	get_tree().create_timer(200.0).timeout.connect(func() -> void:
		print("[probe] TIMEOUT")
		get_tree().quit(1))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
	if _out.is_empty():
		_out = ProjectSettings.globalize_path("user://headphones_probe")
	DirAccess.make_dir_recursive_absolute(_out.path_join("frames"))
	_stage()
	await _run()
	print("[probe] %d frames" % _n)
	get_tree().quit(0)


func _stage() -> void:
	_view = SubViewport.new()
	_view.size = Vector2i(1280, 720)
	_view.own_world_3d = true
	_view.msaa_3d = Viewport.MSAA_4X
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_view)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.18, 0.18, 0.2)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.56, 0.6)
	env.environment.ambient_light_energy = 1.0
	env.environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	_view.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 2.2
	sun.shadow_enabled = true
	_view.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(6, 6)
	floor_mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.6, 0.57)
	mat.roughness = 0.85
	floor_mesh.material_override = mat
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	floor_shape.shape = WorldBoundaryShape3D.new()
	floor_body.add_child(floor_shape)
	floor_mesh.add_child(floor_body)
	_view.add_child(floor_mesh)
	_cam = Camera3D.new()
	_cam.fov = 40
	_cam.near = 0.01
	_view.add_child(_cam)
	_cam.current = true


func _shot(file: String) -> void:
	for i in 6:
		await get_tree().process_frame
	_view.get_texture().get_image().save_png(_out.path_join(file))
	print("[probe] wrote ", file)


func _frame() -> void:
	await get_tree().process_frame
	for h in _view.find_children("SnapHighlight", "Node3D", true, false):
		(h as Node3D).visible = false
	_view.get_texture().get_image().save_png(_out.path_join("frames/f_%04d.png" % _n))
	_n += 1


static func _ease(k: float) -> float:
	return k * k * (3.0 - 2.0 * k)


func _run() -> void:
	var hp := HEADPHONES.instantiate() as Headphones
	_view.add_child(hp)
	var body := hp.get_node("Body") as RigidBody3D
	body.freeze = true
	# Standing on its cups, as the concept shows it.
	body.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(-20)), Vector3(0.0, 0.022, 0.0))
	var gbc := SYSTEM_SCENE.instantiate() as RetroSystem
	gbc.systemid = "gbc"
	gbc.freeze = true
	_view.add_child(gbc)
	gbc.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(30)), Vector3(0.32, 0.07, 0.12))
	for i in 40:
		await get_tree().physics_frame
	var plug := hp.get_node("PlugB0") as RcaPlug
	plug.freeze = true
	plug.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(80)), Vector3(0.18, 0.004, 0.2))
	# The rope was laid round where the headset stood when it spawned; lay it again round where it stands now.
	hp.call("_build_rope")
	for i in 30:
		await get_tree().physics_frame
	_cam.look_at_from_position(Vector3(0.12, 0.2, 0.42), Vector3(0.05, 0.05, 0.05))
	await _shot("hero.png")
	var jack := gbc.find_child("PhonesOut", true, false) as XRToolsSnapZone
	if jack == null:
		print("[probe] the Game Boy Color has no PhonesOut")
		return
	# The seated pose, read by seating once and letting go.
	jack.pick_up_object(plug)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var seated := plug.global_transform
	jack.drop_object()
	plug.freeze = true
	var start := Transform3D(Basis(Vector3.UP, deg_to_rad(80)), Vector3(0.18, 0.004, 0.2))
	var mouth := seated.origin + jack.global_basis.z * 0.06
	var at := jack.global_position
	for i in 20:
		_cam.look_at_from_position(at + Vector3(-0.14, 0.12, 0.2), at)
		plug.global_transform = start
		await _frame()
	for i in 45:
		var k := _ease(float(i) / 44.0)
		var q := start.basis.get_rotation_quaternion().slerp(seated.basis.get_rotation_quaternion(), k)
		plug.global_transform = Transform3D(Basis(q), start.origin.lerp(mouth, k))
		await _frame()
	for i in 20:
		plug.global_transform = Transform3D(seated.basis, mouth.lerp(seated.origin, _ease(float(i) / 19.0)))
		await _frame()
	jack.pick_up_object(plug)
	for i in 30:
		await _frame()
	var route := gbc.audio_route()
	print("[probe] seated: route to %s, the handheld's speaker %s, carrying %s" % [
		(route["tv"] as Node).name if route["tv"] != null else "none",
		"cut" if route["socketed"] else "on", hp.source().name if hp.source() else "nothing"])
	_cam.look_at_from_position(Vector3(0.05, 0.28, 0.5), Vector3(0.12, 0.04, 0.06))
	await _shot("plugged.png")
