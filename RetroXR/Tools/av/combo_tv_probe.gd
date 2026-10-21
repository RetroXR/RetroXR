## Combination set probe — how a TV with a VCR and a DVD player built in LOOKS.
##
## Windowed, never --headless (the dummy renderer saves a blank image):
##   godot --path RetroXR --resolution 320x240 --position 20,20 \
##       res://Tools/av/combo_tv_probe.tscn -- --out=<dir> [--housing]
##
## Builds the reference cabinet (Tests/fixtures/combo_tv_shell.tscn), puts a tape
## in its VCR and a disc in its DVD player, selects the VCR, and photographs the
## front and a three-quarter view. --housing turns the decks' own grey boxes back
## on, which is the control: they should stand where the cabinet's bays are.
## combo_tv_tests is what checks the behaviour; this is only the picture.
extends Node

const TV_SCENE := preload("res://Scenes/Objects/tv.tscn")
const TAPE_SCENE := preload("res://Scenes/Objects/media/vcr_tape.tscn")
const DISC_SCENE := preload("res://Scenes/Objects/media/dvd_disc.tscn")
const COMBO_SHELL := "res://Tests/fixtures/combo_tv_shell.tscn"

var _sv: SubViewport = null
var _cam: Camera3D = null
var _out := "res://probe_out"


func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		print("[combo] TIMEOUT")
		get_tree().quit(1))
	await _run()
	get_tree().quit(0)


func _run() -> void:
	var housing := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.trim_prefix("--out=")
		elif arg == "--housing":
			housing = true

	_sv = SubViewport.new()
	_sv.size = Vector2i(1000, 800)
	_sv.own_world_3d = true
	_sv.msaa_3d = Viewport.MSAA_4X
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_sv)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.30, 0.31, 0.35)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.85, 0.87, 0.95)
	e.ambient_light_energy = 0.7
	env.environment = e
	_sv.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35.0, 25.0, 0.0)
	key.light_energy = 1.2
	_sv.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20.0, -40.0, 0.0)
	fill.light_energy = 0.6
	_sv.add_child(fill)
	_cam = Camera3D.new()
	_cam.fov = 40.0
	_sv.add_child(_cam)
	_cam.current = true

	if housing:
		var shell := (load(COMBO_SHELL) as PackedScene).instantiate() as RetroTVShell
		shell.deck_housing = true
		for child in shell.get_children():
			child.owner = shell
		var packed := PackedScene.new()
		packed.pack(shell)
		shell.free()
		ResourceSaver.save(packed, "user://combo_tv_probe_shell.tscn")
		RetroTV.register_mod_shell("probe:combo", "user://combo_tv_probe_shell.tscn", "Combo", "probe")
	else:
		RetroTV.register_mod_shell("probe:combo", COMBO_SHELL, "Combo", "probe")
	var tv := TV_SCENE.instantiate() as RetroTV
	tv.tv_model = "probe:combo"
	tv.freeze = true
	_sv.add_child(tv)
	await _frames(20)

	var tape := TAPE_SCENE.instantiate() as VCRTape
	tape.video_label = "HOLIDAY 1989"
	(tape as RigidBody3D).freeze = true
	_sv.add_child(tape)
	var disc := DISC_SCENE.instantiate() as DVDDisc
	disc.dvd_label = "FEATURE"
	(disc as RigidBody3D).freeze = true
	_sv.add_child(disc)
	await _frames(5)
	(tv.decks().deck_of_kind("vcr") as VCRPlayer).restore_tape(tape)
	(tv.decks().deck_of_kind("dvd") as DVDPlayer).restore_disc(disc)
	tv.set_source(RetroTV.Source.COMPOSITE_2)
	await _frames(20)
	for deck: MediaTransport in tv.decks().decks():
		var play := deck.get_node("PlayButton") as Node3D
		print("[combo] %s PLAY cap faces %s (set front is %s)" % [deck.name,
			play.global_basis.y.normalized(), tv.global_basis.z])

	var suffix := "_housing" if housing else ""
	_cam.position = Vector3(0.0, 0.05, 1.45)
	_cam.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)
	await _shoot("combo_front" + suffix)
	_cam.position = Vector3(0.85, 0.35, 1.0)
	_cam.look_at(Vector3(0.0, -0.05, 0.0), Vector3.UP)
	await _shoot("combo_three_quarter" + suffix)
	RetroTV.drop_mod_shells("probe")


func _shoot(shot: String) -> void:
	await _frames(12)
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(_out)
	var path := "%s/%s.png" % [_out, shot]
	_sv.get_texture().get_image().save_png(path)
	print("[combo] saved %s" % path)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
