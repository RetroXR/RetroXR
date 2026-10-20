## Photographs an arcade bay with a board standing in it. WINDOWED, never --headless: the dummy
## renderer returns a correctly sized BLANK image.
##
##   "$godot" --path RetroXR res://Tools/models/arcade_bay_probe.tscn \
##       --resolution 1280x720 --position 20,20 -- --out=/some/dir [--kind=jamma|mvs|laserdisc|discrete] \
##       [--cabinet]
##
## One PNG per shot in --out: three (from the front, above), top, back. With --cabinet the bay is
## photographed clipped into its cabinet, from above through the open top.
extends Node3D

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const CART_SCENE := preload("res://Scenes/Objects/media/cartridge.tscn")

var _out := "/tmp"
var _kind := "jamma"
var _cabinet := false
var _cam: Camera3D


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--kind="):
			_kind = a.substr(7)
		elif a == "--cabinet":
			_cabinet = true
	get_tree().create_timer(90.0).timeout.connect(func() -> void: get_tree().quit(2))
	_stage()
	for o in LoadingOverlay.owners():
		LoadingOverlay.end(o)
	LoadingOverlay.suspend()
	var bay: ArcadeBayUnit
	var centre := Vector3(0, 0.25, 0)
	if _cabinet:
		var sys := SYSTEM_SCENE.instantiate() as RetroSystem
		sys.model_id = {"jamma": "arcade_cabinet_generic", "mvs": "arcade_cabinet_neogeo",
			"laserdisc": "arcade_cabinet_daphne", "discrete": "arcade_cabinet_dice"}[_kind]
		sys.systemid = {"jamma": "arcade", "mvs": "neogeo", "laserdisc": "daphne", "discrete": "dice"}[_kind]
		sys.freeze = true
		add_child(sys)
		await _frames(12)
		bay = sys.get_bay()
		centre = Vector3(0, 0.25, 0.0)
		(sys.get_model() as RetroSystemModelArcadeCabinet).set_lid_angle_deg(90.0)
	else:
		bay = ArcadeBayUnit.scene_for(_kind).instantiate() as ArcadeBayUnit
		bay.freeze = true
		add_child(bay)
		await _frames(6)
	var cart := CART_SCENE.instantiate() as Node3D
	cart.systemid = bay.primary_system()
	cart.rom_path = "/tmp/probe_board.zip"
	cart.game_label = "STREET FIGHTER II"
	cart.freeze = true
	cart.position = Vector3(0, 3, 0)
	add_child(cart)
	await _frames(8)
	bay.slot.enabled = true
	bay.slot.pick_up_object(cart)
	await _frames(10)
	if _cabinet:
		await _shot("cab_above", Vector3(0.0, 1.35, 0.55), centre)
		await _shot("cab_inside", Vector3(0.0, 0.80, -0.25), Vector3(0, 0.15, 0.05))
		await _shot("cab_av", Vector3(0.15, 0.80, 0.05), Vector3(-0.20, 0.20, -0.29))
		await _shot("cab_front_low", Vector3(0.0, 0.70, 1.1), centre)
	else:
		await _shot("three", Vector3(0.55, 0.55, 0.75), Vector3(0, 0.12, 0))
		await _shot("top", Vector3(0.0, 0.95, 0.35), Vector3(0, 0.03, 0.0))
		await _shot("back", Vector3(-0.3, 0.25, -0.6), Vector3(0, 0.04, -0.12))
	print("[probe] done")
	get_tree().quit(0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.10, 0.11, 0.15)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.56, 0.62)
	env.ambient_light_energy = 0.8
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 30, 0)
	sun.light_energy = 1.2
	add_child(sun)
	var fill := OmniLight3D.new()
	fill.position = Vector3(0.3, 1.2, 1.2)
	fill.omni_range = 5.0
	fill.light_energy = 0.7
	add_child(fill)
	var floor_mesh := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(6, 0.02, 6)
	floor_mesh.mesh = fm
	floor_mesh.position.y = -0.01
	add_child(floor_mesh)
	_cam = Camera3D.new()
	_cam.fov = 55.0
	add_child(_cam)
	_cam.current = true


func _shot(name: String, from: Vector3, at: Vector3) -> void:
	_cam.position = from
	_cam.look_at(at, Vector3.UP)
	await _frames(4)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s_%s.png" % [_out, _kind, name]
	print("[probe] saved ", path, " ", img.get_size(), " err=", img.save_png(path))
