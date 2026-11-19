extends Node
## How the 3.5 mm TRS to stereo RCA adapter LOOKS, windowed (av_tests phones/ checks it headless):
##   godot --path RetroXR res://DevTools/av/trs_rca_adapter_probe.tscn --resolution 320x240 --position 20,20 -- --out=<dir>
## Renders into its own SubViewport: the adapter loose on the floor (adapter_loose.png, from the jacks' end and from
## the plug's), then in a CD player's PHONES with
## a white and a red phono plug in its jacks (adapter_seated.png). Prints [probe] lines; quits when done.

const CD_SCENE := preload("res://Scenes/Objects/appliances/cd_player.tscn")
const ADAPTER_SCENE := preload("res://Scenes/Objects/cables/trs_rca_adapter.tscn")
const LEAD_SCENE := preload("res://Scenes/Objects/cables/composite_cable.tscn")

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
		_out = ProjectSettings.globalize_path("user://trs_rca_adapter_probe")
	DirAccess.make_dir_recursive_absolute(_out)
	_stage()
	await _run()
	get_tree().quit(0)


func _stage() -> void:
	_view = SubViewport.new()
	_view.size = Vector2i(1280, 720)
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
	sun.rotation_degrees = Vector3(-50, -35, 0)
	sun.light_energy = 2.2
	sun.shadow_enabled = true
	_world.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8, 8)
	floor_mesh.mesh = plane
	_world.add_child(floor_mesh)
	_cam = Camera3D.new()
	_cam.fov = 30
	_cam.near = 0.005
	_world.add_child(_cam)
	_cam.current = true


func _shot(file: String, frames: int = 6) -> void:
	for i in frames:
		await get_tree().process_frame
	var img := _view.get_texture().get_image()
	var path := _out.path_join(file)
	img.save_png(path)
	print("[probe] wrote ", path)


func _look(from: Vector3, at: Vector3) -> void:
	_cam.global_position = from
	_cam.look_at(at, Vector3.UP)


func _run() -> void:
	# Loose: lying on the floor, studs up.
	var loose := ADAPTER_SCENE.instantiate() as TrsRcaAdapter
	_world.add_child(loose)
	var body := loose.get_node("PlugA0") as RigidBody3D
	body.freeze = true
	body.global_position = Vector3(-0.5, 0.0066, 0.0)
	await get_tree().physics_frame
	var c := body.global_position
	_look(c + Vector3(0.06, 0.05, -0.09), c + Vector3(0, 0, -0.004))
	await _shot("adapter_loose_jacks.png")
	_look(c + Vector3(-0.07, 0.05, 0.1), c + Vector3(0, 0, 0.004))
	await _shot("adapter_loose_plug.png")
	print("[probe] loose jacks L %s R %s" % [loose.jacks()[0].global_position - c, loose.jacks()[1].global_position - c])

	# In a CD player's PHONES, a white and a red plug in its jacks.
	var cd := CD_SCENE.instantiate() as RetroAudioPlayer
	cd.freeze = true
	_world.add_child(cd)
	cd.global_position = Vector3(0.5, 0.05, 0.0)
	await get_tree().create_timer(0.5).timeout
	var phones := cd.get_node_or_null("PhonesOut") as RcaPort
	if phones == null:
		print("[probe] FAIL the CD player has no PhonesOut")
		return
	var adapter := ADAPTER_SCENE.instantiate() as TrsRcaAdapter
	_world.add_child(adapter)
	(adapter.get_node("PlugA0") as Node3D).global_position = phones.global_position + phones.global_basis.z * 0.2
	await get_tree().physics_frame
	phones.pick_up_object(adapter.get_node("PlugA0"))
	var lead := LEAD_SCENE.instantiate() as CompositeCable
	_world.add_child(lead)
	await get_tree().create_timer(0.3).timeout
	for i in 2:
		adapter.jacks()[i].pick_up_object(lead.get_node("PlugA%d" % (i + 1)))
	await get_tree().create_timer(1.5).timeout
	print("[probe] seated: host %s, jacks %s" % [adapter.host(), adapter.jacks()[0].direction])
	var out := phones.global_basis.z.normalized()
	var side := phones.global_basis.x.normalized()
	var at := phones.global_position + out * 0.03
	_look(at + out * 0.17 + side * 0.09 + Vector3.UP * 0.07, at)
	await _shot("adapter_seated.png", 10)
