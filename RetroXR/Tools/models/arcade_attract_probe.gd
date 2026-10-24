## Photographs a cabinet in attract mode. WINDOWED, never --headless: the dummy renderer returns a
## correctly sized BLANK image, so a size check passes on nothing.
##
##   "$godot" --path RetroXR res://Tools/models/arcade_attract_probe.tscn \
##       --resolution 1280x720 --position 20,20 -- --out=/some/dir [--shots=still,video,away,off]
##
## Needs ffmpeg on PATH (it makes a 5 s test card with a tone) and the VlcPlayer extension for `video`.
## Everything lives in a scratch ROM folder under the data root (`__attract_probe`), removed at the end.
## Shots: still (title card, no video yet), video (the snap playing on the glass), away (the camera
## behind the cabinet: the glass is out of view, and the printed frame counts show libVLC still decoding
## while no picture is uploaded), off (the option off: the cabinet does not attract, a control), side (the
## same cabinet from the side, to tell a window that is not redrawing from a picture that did not change).
## Photographs are drawn on demand (RenderingServer.force_draw) and never presented, so a locked screen,
## which gets no frames, still produces them.
extends Node3D

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const CART_SCENE := preload("res://Scenes/Objects/media/cartridge.tscn")
const SCRATCH := "__attract_probe"

var _out := "/tmp"
var _shots: Array[String] = ["still", "video", "away", "off", "row"]
var _cam: Camera3D
var _sys: RetroSystem
var _model: RetroSystemModelArcadeCabinet
var _rom := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--shots="):
			_shots.clear()
			for s in a.substr(8).split(","):
				_shots.append(s)
	get_tree().create_timer(120.0).timeout.connect(func() -> void: get_tree().quit(2))
	_stage()
	for o in LoadingOverlay.owners():
		LoadingOverlay.end(o)
	LoadingOverlay.suspend()
	var dir := RomLibrary.rom_dir_for_system(SCRATCH)
	_remove_tree(dir)
	DirAccess.make_dir_recursive_absolute(dir.path_join("media/title"))
	_rom = dir.path_join("game.zip")
	var f := FileAccess.open(_rom, FileAccess.WRITE)
	f.store_string("x")
	f.close()
	_title_card(dir.path_join("media/title/game.png"))
	AppPrefs.arcade_attract_mode = true
	_sys = SYSTEM_SCENE.instantiate()
	_sys.model_id = "arcade_cabinet_generic"
	_sys.systemid = "arcade"
	_sys.freeze = true
	add_child(_sys)
	await _frames(8)
	_model = _sys.get_model() as RetroSystemModelArcadeCabinet
	_model.set_lid_angle_deg(90.0)
	var cart := CART_SCENE.instantiate() as Node3D
	cart.systemid = SCRATCH
	cart.rom_path = _rom
	cart.position = Vector3(0, 3, 0)
	cart.freeze = true
	add_child(cart)
	await _frames(8)
	_sys.get_bay().slot.pick_up_object(cart)
	await _frames(6)
	_model.set_lid_angle_deg(0.0)
	await _frames(4)
	print("[probe] rom=", _sys.rom_path, " applies=", _sys.attract_applies())
	for shot in _shots:
		await call("_shot_" + shot)
	AppPrefs.arcade_attract_mode = false
	_remove_tree(dir)
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
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.1
	add_child(sun)
	var fill := OmniLight3D.new()
	fill.position = Vector3(0.0, 1.6, 2.2)
	fill.omni_range = 6.0
	fill.light_energy = 0.6
	add_child(fill)
	var floor_mesh := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(8, 0.02, 8)
	floor_mesh.mesh = fm
	floor_mesh.position.y = -0.01
	add_child(floor_mesh)
	_cam = Camera3D.new()
	_cam.fov = 58.0
	add_child(_cam)
	_cam.current = true


func _look(from: Vector3, at: Vector3) -> void:
	_cam.position = from
	_cam.look_at(at, Vector3.UP)


func _save(name: String) -> void:
	await _frames(4)
	# Drawn on demand and not presented: a window the compositor is not showing (a locked screen) is given
	# no frame to present into, and waiting for frame_post_draw would wait for ever.
	RenderingServer.force_draw(false)
	RenderingServer.force_draw(false)
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_out, name]
	print("[probe] saved ", path, " ", img.get_size(), " err=", img.save_png(path))


## A card that says what it is: a 4:3 title with a ring, so a stretch shows as an ellipse.
func _title_card(path: String) -> void:
	var img := Image.create(640, 480, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.10, 0.18, 0.45))
	var c := Vector2(320, 240)
	for y in 480:
		for x in 640:
			var d := Vector2(x, y).distance_to(c)
			if d > 150.0 and d < 170.0:
				img.set_pixel(x, y, Color(1.0, 0.85, 0.2))
	img.save_png(path)


func _remove_tree(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while not name.is_empty():
		var full := path.path_join(name)
		if d.current_is_dir():
			_remove_tree(full)
		else:
			DirAccess.remove_absolute(full)
		name = d.get_next()
	d.list_dir_end()
	DirAccess.remove_absolute(path)


func _front() -> void:
	_look(Vector3(0, 1.15, 1.6), Vector3(0, 1.0, 0))


func _shot_still() -> void:
	_sys.power_on()
	await _frames(6)
	print("[probe] still: attracting=", _sys.attracting, " core=", _sys.is_powered_on,
		" picture=", _sys.attract_picture(), " aspect=", _sys.attract_picture_aspect())
	_front()
	await _save("still")


func _shot_video() -> void:
	var dir := RomLibrary.rom_dir_for_system(SCRATCH).path_join("media/video")
	DirAccess.make_dir_recursive_absolute(dir)
	var out: Array = []
	var rc := OS.execute("ffmpeg", ["-y", "-loglevel", "error", "-f", "lavfi", "-i", "testsrc=size=640x480:rate=30",
		"-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000", "-t", "20", "-pix_fmt", "yuv420p",
		"-c:v", "libx264", "-c:a", "aac", dir.path_join("game.mp4")], out)
	print("[probe] ffmpeg rc=", rc)
	var attract := _sys.get_node("ArcadeAttract") as ArcadeAttract
	attract.on_media_arrived(_rom)
	# libVLC takes a moment to open the file and hand over its first frames.
	var waited := 0.0
	while waited < 6.0 and (attract._vlc == null or attract._vlc.get_frame_count() < 5):
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	await get_tree().create_timer(0.5).timeout
	print("[probe] video: first frames after ", waited, " s")
	print("[probe] video: playing=", attract.is_video_playing(), " picture=", _sys.attract_picture(),
		" aspect=", _sys.attract_picture_aspect(), " emitter=", attract.get_node_or_null("AttractEmitter"))
	_front()
	var screen := _model.modules_of_kind(ArcadeProfiles.KIND_SCREEN)[0] as ArcadeScreenModule
	var vtex: Texture2D = attract._vlc.get_texture() if attract._vlc != null else null
	var src: Variant = screen._material.get_shader_parameter("source_tex")
	print("[probe] video: vlc tex=", vtex, " size=", vtex.get_size() if vtex != null else Vector2i.ZERO,
		" video_size=", attract._vlc.get_video_size() if attract._vlc != null else Vector2i.ZERO,
		" frames=", attract._vlc.get_frame_count() if attract._vlc != null else -1,
		" glass shows vlc=", src == vtex, " picture is vlc=", attract.picture() == vtex)
	await _save("video")
	print("[probe] video: frames=", attract._vlc.get_frame_count() if attract._vlc != null else -1,
		" in_view=", attract._in_view)


func _shot_away() -> void:
	var attract := _sys.get_node("ArcadeAttract") as ArcadeAttract
	if attract._vlc == null:
		print("[probe] away: no player (no VlcPlayer here)")
		return
	_look(Vector3(0, 1.15, -1.6), Vector3(0, 1.0, 0))      # behind the cabinet: the glass faces away
	await get_tree().create_timer(1.0).timeout
	var a: int = attract._vlc.get_frame_count()
	await get_tree().create_timer(1.0).timeout
	var b: int = attract._vlc.get_frame_count()
	print("[probe] away: in_view=", attract._in_view, " frames ", a, " -> ", b, " (the picture is not uploaded;",
		" libVLC still decodes)")
	await _save("away")


func _shot_off() -> void:
	_sys.power_off()
	AppPrefs.arcade_attract_mode = false
	print("[probe] off: applies=", _sys.attract_applies(), " attracting=", _sys.attracting)
	_front()
	await _save("off")


## A control: the same cabinet from the side. If this is the same picture as `still`, the window is not
## being redrawn at all and no other shot means anything.
func _shot_side() -> void:
	_look(Vector3(2.0, 1.2, 1.0), Vector3(0, 1.0, 0))
	await _save("side")


## A row of cabinets in front of the camera and one off to the side, all attracting the same game: every
## screen in view must play its video, and the one out of view plays only for its sound.
func _shot_row() -> void:
	var cabs: Array[RetroSystem] = [_sys]
	for x in [-1.0, 1.0, 6.5]:
		cabs.append(await _extra_cabinet(x))
	for c in cabs:
		c.power_on()
	_sys.power_on()
	var waited := 0.0
	while waited < 8.0:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
		var ready := 0
		for c in cabs:
			var a := c.get_node_or_null("ArcadeAttract") as ArcadeAttract
			if a != null and a._vlc != null and a._vlc.get_frame_count() > 5:
				ready += 1
		if ready == cabs.size():
			break
	_look(Vector3(0.0, 1.3, 3.4), Vector3(0.0, 1.0, 0.0))
	await get_tree().create_timer(1.0).timeout
	for c in cabs:
		var a := c.get_node("ArcadeAttract") as ArcadeAttract
		print("[probe] row: x=%.1f playing=%s in_view=%s video=%s" % [c.position.x, a._playing, a._in_view, a.is_video_playing()])
	await _save("row")


func _extra_cabinet(x: float) -> RetroSystem:
	var sys := SYSTEM_SCENE.instantiate() as RetroSystem
	sys.model_id = "arcade_cabinet_generic"
	sys.systemid = "arcade"
	sys.freeze = true
	sys.position = Vector3(x, 0, 0)
	add_child(sys)
	await _frames(8)
	(sys.get_model() as RetroSystemModelArcadeCabinet).set_lid_angle_deg(90.0)
	var cart := CART_SCENE.instantiate() as Node3D
	cart.systemid = SCRATCH
	cart.rom_path = _rom
	cart.position = Vector3(x, 3, 0)
	cart.freeze = true
	add_child(cart)
	await _frames(8)
	sys.get_bay().slot.pick_up_object(cart)
	await _frames(6)
	(sys.get_model() as RetroSystemModelArcadeCabinet).set_lid_angle_deg(0.0)
	await _frames(4)
	return sys
