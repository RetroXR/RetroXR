## Photographs the consolized Neo Geo MVS with a cassette in it. WINDOWED, never --headless.
##
##   "$godot" --path RetroXR res://Tools/models/neogeo_console_probe.tscn \
##       --resolution 1280x720 --position 20,20 -- --out=/some/dir
##
## Shots: three (front three-quarter), rear (the three phono jacks), top (the slot and the cassette).
extends Node3D

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const CART_SCENE := preload("res://Scenes/Objects/media/cartridge.tscn")

var _out := "/tmp"
var _cam: Camera3D
var _sys: Node3D


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	get_tree().create_timer(90.0).timeout.connect(func() -> void: get_tree().quit(2))
	_stage()
	for o in LoadingOverlay.owners():
		LoadingOverlay.end(o)
	LoadingOverlay.suspend()
	_sys = SYSTEM_SCENE.instantiate()
	_sys.model_id = "neogeo_mvs_console"
	_sys.systemid = "neogeo"
	_sys.freeze = true
	_sys.position = Vector3(0, 0.74, 0)           # on a table
	add_child(_sys)
	await _frames(8)
	var cart := CART_SCENE.instantiate() as Node3D
	cart.systemid = "neogeo"
	cart.rom_path = "/tmp/mslug.zip"
	cart.game_label = "METAL SLUG"
	cart.freeze = true
	cart.position = Vector3(0, 2.0, 0)
	add_child(cart)
	await _frames(8)
	(_sys.get_node("CartridgeSlot") as XRToolsSnapZone).pick_up_object(cart)
	await _frames(10)
	_look(Vector3(0.55, 1.25, 0.95), Vector3(0, 0.80, 0))
	await _save("three")
	_look(Vector3(0.35, 1.0, -0.8), Vector3(0, 0.78, -0.1))
	await _save("rear")
	_look(Vector3(0.0, 1.5, 0.45), Vector3(0, 0.85, -0.02))
	await _save("top")
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
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)
	var table := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.6, 0.04, 1.0)
	table.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.36, 0.28)
	table.material_override = mat
	table.position = Vector3(0, 0.72, 0)
	add_child(table)
	_cam = Camera3D.new()
	_cam.fov = 55.0
	add_child(_cam)
	_cam.current = true


func _look(from: Vector3, at: Vector3) -> void:
	_cam.position = from
	_cam.look_at(at, Vector3.UP)


func _save(name: String) -> void:
	await _frames(4)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_out, name]
	print("[probe] saved ", path, " ", img.get_size(), " err=", img.save_png(path))
