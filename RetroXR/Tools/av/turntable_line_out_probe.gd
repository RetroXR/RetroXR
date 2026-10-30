extends Node3D
## The RETRO XR turntable's line out, in the game: its white and red jacks cabled into the
## surround amplifier's AUDIO IN, two loudspeakers on the amplifier's FL / FR, and the
## amplifier's VFD lit for them. Two shots — the fronts, and the backs with the leads.
## Windowed only (headless draws nothing):
##
##     godot --path RetroXR res://Tools/av/turntable_line_out_probe.tscn --resolution 1280x720 --position 20,20 -- --out=<dir>
##
## Renders through its own SubViewport + camera: the desktop loading screen is a CanvasLayer
## over the main view.

const RECORD_PLAYER := preload("res://Scenes/Objects/appliances/record_player.tscn")
const AMP := preload("res://Scenes/Objects/appliances/surround_amp.tscn")
const SATELLITE := preload("res://Scenes/Objects/appliances/loudspeaker.tscn")
const LEAD := preload("res://Scenes/Objects/cables/speaker_cable.tscn")

var _vp: SubViewport
var _cam: Camera3D
var _out := "user://turntable_line_out_probe"


func _ready() -> void:
	get_tree().create_timer(90.0).timeout.connect(func(): print("[tlprobe] timeout"); get_tree().quit(1))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.2, 0.2, 0.21)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.55, 0.57)
	env.environment.ambient_light_energy = 0.9
	env.environment.tonemap_mode = Environment.TONE_MAPPER_AGX
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 2.0
	sun.shadow_enabled = true
	add_child(sun)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(4, 4)
	floor.mesh = pm
	floor.position.y = -0.03
	add_child(floor)

	var rp := RECORD_PLAYER.instantiate() as RecordPlayer
	rp.position = Vector3(-0.32, 0.0, 0.0)
	add_child(rp)
	rp.freeze = true
	var amp := AMP.instantiate() as SurroundAmp
	amp.position = Vector3(0.30, -0.03, -0.02)
	add_child(amp)
	amp.freeze = true
	_vp = SubViewport.new()
	_vp.size = Vector2i(1280, 720)
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	_cam = Camera3D.new()
	_cam.fov = 40
	_vp.add_child(_cam)
	await _frames(6)

	# white into L, red into R
	await _lead(rp.get_node("AudioLOut") as RcaPort, amp.get_node("AudioInL") as RcaPort)
	await _lead(rp.get_node("AudioROut") as RcaPort, amp.get_node("AudioInR") as RcaPort)
	# a cabinet on each front output
	for spec: Array in [["SpeakerOutL", Vector3(0.05, 0.0, 0.45)], ["SpeakerOutR", Vector3(0.62, 0.0, 0.45)]]:
		var cab := SATELLITE.instantiate() as Node3D
		cab.position = spec[1]
		add_child(cab)
		if cab is RigidBody3D:
			(cab as RigidBody3D).freeze = true
		await _frames(4)
		await _lead(amp.get_node(spec[0]) as RcaPort, cab.get_node("SpeakerIn") as RcaPort)
	await _frames(12)
	print("[tlprobe] turntable sound sink: %s, amp speakers cabled: %s, record level %.2f"
		% [rp.sound_sink().name if rp.sound_sink() else "none", amp.has_cabled_speakers(), rp._volume_linear])

	_cam.look_at_from_position(Vector3(0.05, 0.42, 1.05), Vector3(0.02, 0.02, 0.0))
	await _shot("turntable_line_out_front")
	_cam.look_at_from_position(Vector3(-0.05, 0.40, -0.95), Vector3(0.0, 0.0, -0.15))
	await _shot("turntable_line_out_back")
	get_tree().quit(0)


func _lead(out_port: RcaPort, in_port: RcaPort) -> void:
	var lead := LEAD.instantiate() as Node3D
	add_child(lead)
	await _frames(4)
	out_port.pick_up_object(lead.get_node("PlugA0") as Node3D)
	in_port.pick_up_object(lead.get_node("PlugB0") as Node3D)
	await _frames(6)


func _frames(k: int) -> void:
	for i in k:
		await get_tree().process_frame


func _shot(shot_name: String) -> void:
	await _frames(8)
	var path := _out.path_join(shot_name + ".png")
	_vp.get_texture().get_image().save_png(path)
	print("[tlprobe] wrote ", path)
