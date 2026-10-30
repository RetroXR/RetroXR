extends Node
## How the RETRO XR decks LOOK, windowed (deck_model_tests checks them headless):
##   godot --path RetroXR res://Tools/av/deck_model_probe.tscn --resolution 320x240 --position 20,20 -- --out=<dir>
## Renders into its own SubViewport (the desktop loading screen covers the main view): the VCR, its display
## running with PLAY lit, a load and an eject frame by frame (frames/vcr_NNNN.png), the DVD player with its tray
## out holding a disc, and a combo set with both decks built in. Prints [probe] lines; quits when done.

const VCR_SCENE := preload("res://Scenes/Objects/appliances/vcr_player.tscn")
const DVD_SCENE := "res://Scenes/Objects/appliances/dvd_player.tscn"
const TAPE_SCENE := preload("res://Scenes/Objects/media/vcr_tape.tscn")
const DISC_SCENE := "res://Scenes/Objects/media/dvd_disc.tscn"
const TV_SCENE := "res://Scenes/Objects/tv.tscn"
const COMBO_SHELL := "res://Tests/fixtures/combo_tv_shell.tscn"

var _out := ""
var _view: SubViewport
var _cam: Camera3D
var _world: Node3D


func _ready() -> void:
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("[probe] TIMEOUT")
		get_tree().quit(1))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
	if _out.is_empty():
		_out = ProjectSettings.globalize_path("user://deck_model_probe")
	DirAccess.make_dir_recursive_absolute(_out.path_join("frames"))
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
	sun.rotation_degrees = Vector3(-45, -30, 0)
	sun.light_energy = 2.2
	sun.shadow_enabled = true
	_world.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8, 8)
	floor_mesh.mesh = plane
	floor_mesh.position = Vector3(0, -0.047, 0)
	_world.add_child(floor_mesh)
	_cam = Camera3D.new()
	_cam.fov = 40
	_world.add_child(_cam)
	_cam.current = true


func _shot(file: String, frames: int = 4) -> void:
	for i in frames:
		await get_tree().process_frame
	var img := _view.get_texture().get_image()
	var path := _out.path_join(file)
	img.save_png(path)
	print("[probe] wrote ", path)


func _look(from: Vector3, at: Vector3) -> void:
	_cam.look_at_from_position(from, at)


func _run() -> void:
	if "--combo" in OS.get_cmdline_user_args():
		await _combo()
		return
	# --- the VCR, a tape playing
	var vcr := VCR_SCENE.instantiate() as VCRPlayer
	vcr.freeze = true
	_world.add_child(vcr)
	await get_tree().process_frame
	_look(Vector3(0.30, 0.24, 0.56), Vector3(0, -0.01, 0.02))
	await _shot("vcr_hero.png", 8)
	var tape := TAPE_SCENE.instantiate() as VCRTape
	tape.freeze = true
	tape.video_label = "HOLIDAY 1989"
	tape.position = Vector3(1, 1, 1)
	_world.add_child(tape)
	tape.recording_seconds = 600.0
	tape.cassette = 120
	tape.tape_progress = 1.0
	tape.tape_time = 594.0
	vcr.restore_media(tape)
	# Playing on into the blank tape: the counter runs at play speed with no file to decode.
	vcr._ensure_recordings()
	vcr.is_playing = true
	vcr._blank = true
	_look(Vector3(0.16, 0.0, 0.33), Vector3(0.105, 0.0, 0.13))
	await _shot("vcr_vfd_playing_1.png", 8)
	for i in 70:
		await get_tree().process_frame
	await _shot("vcr_vfd_playing_2.png", 2)
	print("[probe] counter now %s (state %s)" % [VCRClock.counter(vcr._tape_time() + vcr._tape_blank()), vcr._vfd_state])
	vcr.is_playing = false
	vcr._blank = false
	# --- eject, then load, frame by frame from low in front
	_look(Vector3(-0.22, 0.05, 0.52), Vector3(-0.07, 0.0, 0.12))
	var n := 0
	vcr._on_eject_pressed()
	while vcr._ride_media != null and n < 400:
		await _frame_shot(n)
		n += 1
	for i in 12:
		await _frame_shot(n)
		n += 1
	# Taken out by a hand and put back: the slot takes it at the mouth again.
	vcr._slot._on_media_taken(tape)
	await get_tree().process_frame
	await get_tree().process_frame
	tape.freeze = true
	vcr._slot._accept(tape, false)
	while vcr._ride_media != null and n < 800:
		await _frame_shot(n)
		n += 1
	for i in 12:
		await _frame_shot(n)
		n += 1
	print("[probe] %d mechanism frames" % n)
	vcr.queue_free()
	tape.queue_free()
	await get_tree().process_frame
	await _dvd()
	await _combo()


func _frame_shot(n: int) -> void:
	await get_tree().process_frame
	_view.get_texture().get_image().save_png(_out.path_join("frames/vcr_%04d.png" % n))


func _dvd() -> void:
	var dvd := (load(DVD_SCENE) as PackedScene).instantiate() as DVDPlayer
	dvd.freeze = true
	_world.add_child(dvd)
	await get_tree().process_frame
	_look(Vector3(0.36, 0.26, 0.62), Vector3(0, -0.01, 0.04))
	await _shot("dvd_hero.png", 8)
	dvd._on_eject_pressed()
	await _until(func() -> bool: return dvd._tray_anim == "")
	_look(Vector3(-0.30, 0.30, 0.62), Vector3(-0.08, 0.0, 0.12))
	await _shot("dvd_tray_out_empty.png", 6)
	_look(Vector3(-0.24, 0.17, 0.38), Vector3(-0.085, 0.0, 0.2))
	await _shot("dvd_tray_close_empty.png", 6)
	var disc :=(load(DISC_SCENE) as PackedScene).instantiate() as Node3D
	(disc as RigidBody3D).freeze = true
	disc.position = Vector3(1, 1, 1)
	_world.add_child(disc)
	dvd._slot._accept(disc, false)
	await _until(func() -> bool: return dvd._tray_anim == "")
	dvd._on_eject_pressed()
	await _until(func() -> bool: return dvd._tray_anim == "")
	_look(Vector3(-0.30, 0.30, 0.62), Vector3(-0.08, 0.0, 0.12))
	await _shot("dvd_tray_out_disc.png", 6)
	_look(Vector3(-0.24, 0.17, 0.38), Vector3(-0.085, 0.0, 0.2))
	await _shot("dvd_tray_close_disc.png", 6)
	# The playing layout, set by hand: a disc's titles and chapters need a real DVD image playing.
	dvd._on_eject_pressed()
	await _until(func() -> bool: return dvd._tray_anim == "")
	dvd._loading_until = 0
	dvd.set_process(false)
	dvd._vfd_state = {"word": "", "title": 1, "chapter": 3, "secs": 765, "paused": false, "scan": 0}
	dvd._vfd.refresh()
	_look(Vector3(0.10, 0.02, 0.34), Vector3(0.07, 0.008, 0.14))
	await _shot("dvd_vfd_playing.png", 6)
	dvd._vfd_state = {"word": "OPEN", "title": -1, "chapter": -1, "secs": -1, "paused": false, "scan": 0}
	dvd._vfd.refresh()
	await _shot("dvd_vfd_open.png", 4)
	dvd.queue_free()
	disc.queue_free()
	await get_tree().process_frame


func _combo() -> void:
	RetroTV.register_mod_shell("deck_model_probe:combo", COMBO_SHELL, "Combo", "deck_model_probe")
	var tv := (load(TV_SCENE) as PackedScene).instantiate() as RetroTV
	tv.tv_model = "deck_model_probe:combo"
	tv.freeze = true
	tv.position = Vector3(0, 0.45, 0)
	_world.add_child(tv)
	for i in 10:
		await get_tree().process_frame
	_look(Vector3(0.35, 0.40, 1.05), Vector3(0.0, 0.33, 0.1))
	await _shot("combo_tv_decks.png", 6)
	tv.queue_free()
	RetroTV.drop_mod_shells("deck_model_probe")


func _until(cond: Callable) -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while not cond.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
