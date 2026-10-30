## The base game's audio cassette held up close, and the headphones in the RETRO XR CD player's PHONES jack, windowed:
##   godot --path RetroXR res://Tools/av/bring_in_probe.tscn --resolution 320x240 --position 20,20 -- --no-mods --out=<dir>
## --no-mods: the stock cassette (a mod dressing it, xenu.cassette, would hide it). Renders into its own SubViewport.
extends Node

const CASSETTE := preload("res://Scenes/Objects/media/audio_cassette.tscn")
const CD := preload("res://Scenes/Objects/appliances/cd_player.tscn")
const HEADPHONES := preload("res://Scenes/Objects/appliances/headphones.tscn")

var _out := ""
var _view: SubViewport
var _cam: Camera3D


func _ready() -> void:
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("[probe] TIMEOUT")
		get_tree().quit(1))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	_stage()
	await _cassette()
	await _phones()
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
	env.environment.background_color = Color(0.2, 0.2, 0.21)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.55, 0.58)
	env.environment.ambient_light_energy = 0.9
	env.environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	_view.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	sun.light_energy = 2.2
	sun.shadow_enabled = true
	_view.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8, 8)
	floor_mesh.mesh = plane
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	body.add_child(shape)
	floor_mesh.add_child(body)
	_view.add_child(floor_mesh)
	_cam = Camera3D.new()
	_cam.fov = 35
	_view.add_child(_cam)
	_cam.current = true


func _shot(file: String, frames: int = 8) -> void:
	for i in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	_view.get_texture().get_image().save_png(_out.path_join(file))
	print("[probe] wrote ", file)


## Held up as a hand holds one to read it: side A toward the eye, tilted back, a third of the way through the tape.
func _cassette() -> void:
	var t := CASSETTE.instantiate() as AudioCassette
	t.freeze = true
	t.album_label = "Summer Mix '91"
	t.tape_progress = 0.33
	_view.add_child(t)
	t.global_transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-25), deg_to_rad(18), deg_to_rad(-6))),
		Vector3(0, 1.2, 0))
	for i in 30:
		await get_tree().process_frame
	print("[probe] cassette: shell %s, progress %.2f" % [t.get_node_or_null("Shell") is CompactCassette,
		(t.get_node("Shell") as CompactCassette).progress if t.get_node_or_null("Shell") is CompactCassette else -1.0])
	_cam.look_at_from_position(Vector3(0.02, 1.27, 0.22), Vector3(0, 1.2, 0))
	await _shot("cassette_base_in_hand.png")
	t.queue_free()


## The headphones' plug in the CD player's PHONES jack, the LEVEL knob beside it.
func _phones() -> void:
	var cd := CD.instantiate() as CDPlayer
	cd.freeze = true
	_view.add_child(cd)
	cd.global_position = Vector3(0, 0.0475, 0)
	var hp := HEADPHONES.instantiate() as Node3D
	_view.add_child(hp)
	hp.global_position = Vector3(0.12, 0.03, 0.45)
	for i in 20:
		await get_tree().process_frame
	var jack := cd.get_node("PhonesOut") as XRToolsSnapZone
	jack.pick_up_object(hp.get_node("PlugB0") as Node3D)
	for i in 90:
		await get_tree().physics_frame
	print("[probe] CD sound -> %s" % (cd.sound_sink().name if cd.sound_sink() != null else "itself"))
	for h in _view.find_children("SnapHighlight", "Node3D", true, false):
		(h as Node3D).visible = false
	_cam.look_at_from_position(Vector3(0.36, 0.17, 0.55), Vector3(0.12, 0.03, 0.2))
	await _shot("headphones_in_cd_phones.png")
	_cam.look_at_from_position(Vector3(0.23, 0.07, 0.33), Vector3(0.175, 0.03, 0.15))
	await _shot("cd_phones_close.png")
