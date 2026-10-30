## The RETRO XR cassette deck or CD player, windowed, one PNG a frame at a fixed 30 fps step, plus three stills:
##   godot --path RetroXR res://Tools/av/audio_deck_video_probe.tscn --resolution 320x240 --position 20,20 --fixed-fps 30 \
##     -- --deck=cassette|cd --album=<folder of audio files> --out=<dir>
## Cassette: EJECT tips the empty door out, a cassette is lowered into it and rides in, PLAY (the counter runs, the
## meters move, the spindles turn), EJECT tips it back out. CD: OPEN slides the tray out, a disc is lowered onto it and
## rides in, PLAY (the time runs, the calendar), OPEN stops it and brings it out. Stills: hero.png (playing),
## open.png (door / tray out with the medium), vfd.png (the display, close). Encode frames/ with imageio.
extends Node

const DECKS := {
	"cassette": ["res://Scenes/Objects/appliances/cassette_player.tscn", "res://Scenes/Objects/media/audio_cassette.tscn"],
	"cd": ["res://Scenes/Objects/appliances/cd_player.tscn", "res://Scenes/Objects/media/audio_disc.tscn"],
}

var _out := ""
var _album := ""
var _kind := "cassette"
var _view: SubViewport
var _cam: Camera3D
var _n := 0
var _deck: RetroAudioPlayer
var _eye := Vector3(0.26, 0.20, 0.62)
var _look := Vector3(0.0, -0.01, 0.03)


func _ready() -> void:
	get_tree().create_timer(400.0).timeout.connect(func() -> void:
		print("[probe] TIMEOUT")
		get_tree().quit(1))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
		elif arg.begins_with("--album="):
			_album = arg.substr(8)
		elif arg.begins_with("--deck="):
			_kind = arg.substr(7)
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
	env.environment.background_color = Color(0.17, 0.17, 0.19)
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
	floor_mesh.position = Vector3(0, -0.06 if _kind == "cassette" else -0.0475, 0)
	_view.add_child(floor_mesh)
	_cam = Camera3D.new()
	_cam.fov = 38
	_view.add_child(_cam)
	_cam.current = true


func _frame() -> void:
	await get_tree().process_frame
	_cam.look_at_from_position(_eye, _look)
	for h in _view.find_children("SnapHighlight", "Node3D", true, false):
		(h as Node3D).visible = false
	_view.get_texture().get_image().save_png(_out.path_join("frames/f_%04d.png" % _n))
	_n += 1


func _frames(count: int) -> void:
	for i in count:
		await _frame()


func _still(file: String, eye: Vector3, look: Vector3) -> void:
	_cam.look_at_from_position(eye, look)
	for i in 4:
		await get_tree().process_frame
	_view.get_texture().get_image().save_png(_out.path_join(file))
	print("[probe] wrote ", file)


func _settle(drawer: DeckDrawer) -> void:
	await _frames(3)
	var guard := 0
	while drawer.is_moving() and guard < 200:
		await _frame()
		guard += 1


static func _ease(k: float) -> float:
	return k * k * (3.0 - 2.0 * k)


func _run() -> void:
	_deck = (load(DECKS[_kind][0]) as PackedScene).instantiate() as RetroAudioPlayer
	_deck.freeze = true
	_view.add_child(_deck)
	var media := (load(DECKS[_kind][1]) as PackedScene).instantiate() as RigidBody3D
	media.freeze = true
	media.set("album_path", _album)
	media.set("album_label", "Probe Album")
	_view.add_child(media)
	media.global_position = Vector3(2, 1, 0)
	for i in 8:
		await get_tree().process_frame
	var drawer: DeckDrawer = _deck.get("_drawer")
	var slot: MediaSlot = _deck.get("_slot")
	var cassette := _kind == "cassette"
	if cassette:
		_eye = Vector3(-0.30, 0.20, 0.62)
		_look = Vector3(-0.07, -0.01, 0.06)
	else:
		_eye = Vector3(-0.24, 0.26, 0.62)
		_look = Vector3(-0.05, -0.005, 0.08)
	await _frames(20)
	# Open, and the medium is lowered in from above.
	if cassette:
		(_deck.get_node("EjectButton") as VRButton).button_pressed.emit()
	else:
		(_deck.get_node("OpenButton") as VRButton).button_pressed.emit()
	await _settle(drawer)
	await _frames(10)
	var seat := (_deck.get_node("Model") as ApplianceModel).part("TapeSeat" if cassette else "DiscSeat").global_transform
	for i in 30:
		var k := _ease(float(i) / 29.0)
		media.global_transform = Transform3D(seat.basis, seat.origin + Vector3(0, 0.002 + 0.10 * (1.0 - k), 0.03 * (1.0 - k)))
		await _frame()
	slot._accept(media, false)
	await _settle(drawer)
	await _frames(15)
	_deck.remote_play()
	print("[probe] playing: ", _deck.is_playing)
	await _frames(150)
	await _still("hero.png", Vector3(0.30, 0.22, 0.66), Vector3(0.0, -0.01, 0.02))
	await _still("vfd.png", Vector3(0.08, 0.02, 0.36), Vector3(0.07 if cassette else 0.10, 0.02 if cassette else 0.018, 0.14))
	await _frames(15)
	if cassette:
		(_deck.get_node("EjectButton") as VRButton).button_pressed.emit()
	else:
		(_deck.get_node("OpenButton") as VRButton).button_pressed.emit()
	await _settle(drawer)
	await _frames(30)
	await _still("open.png", Vector3(-0.32 if cassette else -0.26, 0.22, 0.56), Vector3(-0.12, -0.01, 0.13))
