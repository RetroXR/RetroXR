extends Node3D
## The RETRO XR turntable in the game, lit: a record playing with the cover up (needle
## on the record, platter turning), the cover shut, and a frame sequence of the cover
## opening and the arm swinging onto the record. Windowed only (headless draws nothing):
##
##     godot --path RetroXR res://Tools/av/turntable_model_probe.tscn --resolution 1280x720 --position 20,20 -- --out=<dir>
##
## Renders through its own SubViewport + camera, because the desktop loading screen is a
## CanvasLayer over the main view.

const RECORD_PLAYER := preload("res://Scenes/Objects/appliances/record_player.tscn")
const VINYL := preload("res://Scenes/Objects/media/vinyl_record.tscn")

var _vp: SubViewport
var _out := "user://turntable_probe"


func _ready() -> void:
	get_tree().create_timer(120.0).timeout.connect(func(): print("[ttprobe] timeout"); get_tree().quit(1))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(_out)
	DirAccess.make_dir_recursive_absolute(_out.path_join("frames"))

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
	sun.light_energy = 2.2
	sun.shadow_enabled = true
	add_child(sun)
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(3, 3)
	floor.mesh = pm
	floor.position.y = -0.03
	add_child(floor)

	var rp := RECORD_PLAYER.instantiate() as RecordPlayer
	add_child(rp)
	rp.freeze = true
	_vp = SubViewport.new()
	_vp.size = Vector2i(1280, 720)
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)
	var cam := Camera3D.new()
	cam.fov = 38
	_vp.add_child(cam)
	await _frames(4)

	var lp := VINYL.instantiate() as VinylRecord
	lp.album_path = "/nowhere/Probe Album"
	lp.album_label = "Probe Album"
	add_child(lp)
	await _frames(2)
	rp.restore_media(lp)
	await _frames(4)
	print("[ttprobe] record seated: %s, cover %s" % [rp._tray.has_media(), "up" if rp.cover_open() else "down"])

	# 1 playing, cover up: needle on the record, platter turning
	rp._arm.set_value_no_signal(0.72)
	rp._motor = true
	await get_tree().create_timer(1.0).timeout
	cam.look_at_from_position(Vector3(0.42, 0.42, 0.62), Vector3(-0.02, 0.07, 0.0))
	await _shot("turntable_playing_cover_up")
	cam.look_at_from_position(Vector3(0.30, 0.20, 0.10), Vector3(0.0, 0.08, -0.02))
	await _shot("turntable_tonearm_closeup")

	# 2 cover down, arm parked, motor off
	rp._motor = false
	rp._arm.set_value_no_signal(0.0)
	rp.set_cover_open(false)
	await _frames(6)
	cam.look_at_from_position(Vector3(0.42, 0.42, 0.62), Vector3(-0.02, 0.07, 0.0))
	await _shot("turntable_cover_down")
	print("[ttprobe] cover down: well open=%s, arm layer=%d" % [rp._tray.is_open(), rp._arm.collision_layer])

	# 3 frames: cover opens (0.8 s), the arm swings onto the lead-in (1.2 s), it plays
	var n := 0
	for i in 24:
		rp.set_cover_open(false)
		rp._cover.set_value(float(i + 1) / 24.0)
		await _frame_png(n)
		n += 1
	rp._motor = true
	for i in 36:
		var t := float(i + 1) / 36.0
		rp._arm.set_value_no_signal(lerpf(0.0, rp.arm_lead_in + 0.02, t * t * (3.0 - 2.0 * t)))
		await _frame_png(n)
		n += 1
	for i in 30:
		await _frame_png(n)
		n += 1
	print("[ttprobe] frames %d -> %s" % [n, _out.path_join("frames")])
	get_tree().quit(0)


func _frames(k: int) -> void:
	for i in k:
		await get_tree().process_frame


func _shot(shot_name: String) -> void:
	await _frames(3)
	var path := _out.path_join(shot_name + ".png")
	_vp.get_texture().get_image().save_png(path)
	print("[ttprobe] wrote ", path)


func _frame_png(i: int) -> void:
	await _frames(2)
	_vp.get_texture().get_image().save_png(_out.path_join("frames/f%04d.png" % i))
