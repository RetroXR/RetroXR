## How the RETRO XR DVD player's front keys LOOK in the game, windowed: the navigation ring (the remote's) and the
## transport row close up, then the RIGHT arc held down (VRButton.set_latched_pressed), so the press shows.
##   godot --path RetroXR res://Tools/av/dvd_ring_probe.tscn --resolution 320x240 --position 20,20 -- --out=<dir>
extends Node

const DVD_SCENE := "res://Scenes/Objects/appliances/dvd_player.tscn"

var _out := ""
var _view: SubViewport
var _cam: Camera3D
var _world: Node3D


func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("[probe] TIMEOUT")
		get_tree().quit(1))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
	if _out.is_empty():
		_out = ProjectSettings.globalize_path("user://dvd_ring_probe")
	DirAccess.make_dir_recursive_absolute(_out)
	_stage()
	await _run()
	get_tree().quit(0)


func _stage() -> void:
	_view = SubViewport.new()
	_view.size = Vector2i(1600, 1000)
	_view.own_world_3d = true
	_view.msaa_3d = Viewport.MSAA_4X
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_view)
	_world = Node3D.new()
	_view.add_child(_world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.2, 0.2, 0.21)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.55, 0.58)
	env.environment.ambient_light_energy = 0.9
	env.environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	_world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -25, 0)
	sun.light_energy = 2.2
	sun.shadow_enabled = true
	_world.add_child(sun)
	_cam = Camera3D.new()
	_cam.fov = 30
	_world.add_child(_cam)
	_cam.current = true


func _shot(file: String) -> void:
	for i in 6:
		await get_tree().process_frame
	var path := _out.path_join(file)
	_view.get_texture().get_image().save_png(path)
	print("[probe] wrote ", path)


func _run() -> void:
	var dvd := (load(DVD_SCENE) as PackedScene).instantiate() as DVDPlayer
	dvd.freeze = true
	_world.add_child(dvd)
	for i in 6:
		await get_tree().process_frame
	var ring := (dvd.get_node("SelectButton") as Node3D).global_position
	_cam.look_at_from_position(ring + Vector3(0.05, 0.035, 0.17), ring + Vector3(-0.02, -0.002, 0.0))
	await _shot("dvd_front_keys.png")
	_cam.look_at_from_position(ring + Vector3(0.03, 0.03, 0.10), ring)
	await _shot("dvd_ring.png")
	var right := dvd.get_node("RightButton") as VRButton
	var cap := right.get_node("ButtonMesh") as Node3D
	var rest := cap.global_position
	right.set_latched_pressed(true)
	await _shot("dvd_ring_right_pressed.png")
	print("[probe] RIGHT pressed: its cap moved %.2f mm into the panel" % ((rest - cap.global_position).length() * 1000.0))
	right.set_latched_pressed(false)
