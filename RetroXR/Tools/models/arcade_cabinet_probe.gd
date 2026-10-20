## Photographs the Primitive Arcade Cabinet. WINDOWED, never --headless: the dummy
## renderer returns a correctly sized BLANK image, so a size check passes on nothing.
##
##   "$godot" --path RetroXR res://Tools/models/arcade_cabinet_probe.tscn \
##       --resolution 1280x720 --position 20,20 -- --out=/some/dir [--shots=front,three]
##
## --model=<registry id> and --system=<systemid> photograph another cabinet (the default is
## arcade_cabinet_generic on `arcade`); the extra shots `holster` and `pedal` are for the gun cabinets.
##
## One PNG per shot, named <shot>.png in --out. Shots: front, three, side, panel, bay,
## landscape, portrait, coin, holster, pedal. The monitor shots feed the screen module a test card
## (a circle and a grid, so a stretch shows as an ellipse) of the shape a core would
## hand over: 384x224 CPS1 on a 4:3 tube, and a vertical 224x384 frame.
##
## The board in the bay wears printed-title art, the door is opened through its own
## hinge, and the coin is a real ArcadeCoinModule toss caught in the air.
extends Node3D

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const CART_SCENE := preload("res://Scenes/Objects/media/cartridge.tscn")

var _out := "/tmp"
var _model_id := "arcade_cabinet_generic"
var _systemid := "arcade"
var _shots: Array[String] = ["front", "three", "panel", "bay", "landscape", "portrait", "coin", "board", "boardside", "hover", "toast", "side"]
var _cam: Camera3D
var _sys: Node3D
var _model: RetroSystemModelArcadeCabinet


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
		elif a.begins_with("--model="):
			_model_id = a.substr(8)
		elif a.begins_with("--system="):
			_systemid = a.substr(9)
		elif a.begins_with("--shots="):
			_shots.clear()
			for s in a.substr(8).split(","):
				_shots.append(s)
	get_tree().create_timer(120.0).timeout.connect(func() -> void: get_tree().quit(2))
	_stage()
	# The app's loading panel stands in front of whatever a probe draws until the room
	# it is waiting on is ready, which a probe never builds.
	for o in LoadingOverlay.owners():
		LoadingOverlay.end(o)
	LoadingOverlay.suspend()
	_sys = SYSTEM_SCENE.instantiate()
	_sys.model_id = _model_id
	_sys.systemid = _systemid
	_sys.freeze = true
	add_child(_sys)
	await _frames(8)
	_model = _sys.get_model() as RetroSystemModelArcadeCabinet
	print("[probe] model=", _model, " modules=", _model.get_child_count())
	_model.set_process(false)       # the probe paints the glass itself
	for shot in _shots:
		await call("_shot_" + shot)
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
	sun.shadow_enabled = true
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
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.32, 0.30, 0.34)
	floor_mesh.material_override = fmat
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
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_out, name]
	print("[probe] saved ", path, " ", img.get_size(), " err=", img.save_png(path))


## A test card, drawn the way an arcade game is: for a TUBE, not for square pixels. Its
## circle is round on a 4:3 (or, turned, 3:4) tube, so it is an ellipse in pixels, wider
## or narrower by pixel aspect / display aspect. Shown at the right shape it reads as a
## circle; stretched to the pixel ratio it would be an ellipse -- which is what a screen
## that sized itself from the texture would show.
func _card(w: int, h: int, tint: Color) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.08, 0.10, 0.18))
	var c := Vector2(w * 0.5, h * 0.5)
	var display := 4.0 / 3.0 if w >= h else 3.0 / 4.0
	var squeeze := (float(w) / float(h)) / display     # pixel aspect / display aspect
	var r := minf(float(h), float(w) / squeeze) * 0.38
	for y in h:
		for x in w:
			var d := Vector2((x - c.x) / squeeze, y - c.y).length()
			if absf(d - r) < 2.0:
				img.set_pixel(x, y, Color(1, 1, 1))
			elif x % 32 == 0 or y % 32 == 0:
				img.set_pixel(x, y, tint)
	for x in w:
		img.set_pixel(x, 0, Color(1, 0.2, 0.2))
		img.set_pixel(x, h - 1, Color(1, 0.2, 0.2))
	for y in h:
		img.set_pixel(0, y, Color(1, 0.2, 0.2))
		img.set_pixel(w - 1, y, Color(1, 0.2, 0.2))
	return ImageTexture.create_from_image(img)


func _glass(w: int, h: int) -> void:
	var screen := _model.modules_of_kind(ArcadeProfiles.KIND_SCREEN)[0] as ArcadeScreenModule
	var tex := _card(w, h, Color(0.3, 0.8, 0.4))
	screen._material.set_shader_parameter("source_tex", tex)
	screen.get_screen().set_surface_override_material(0, screen._material)
	screen._serial = -1
	screen._refresh_geometry(tex)
	print("[probe] glass %dx%d aspect=%.3f fit=%s" % [w, h, screen.current_aspect(), screen.current_fit()])


func _shot_front() -> void:
	_glass(384, 224)
	_model.on_power_on()
	_look(Vector3(0, 1.05, 3.0), Vector3(0, 0.9, 0))
	await _save("front")


func _shot_three() -> void:
	_look(Vector3(2.0, 1.5, 2.1), Vector3(0, 0.85, 0))
	await _save("three")


## From the side: the silhouette, the glass on its slanted edge and the tube set back inside.
func _shot_side() -> void:
	_glass(384, 224)
	_model.on_power_on()
	_look(Vector3(3.2, 1.2, 0.1), Vector3(0, 1.0, 0.1))
	await _save("side")


## The holsters, close: the guns hanging muzzle-down on the apron, and their cords.
func _shot_holster() -> void:
	_glass(384, 224)
	_model.on_power_on()
	await _frames(120)         # let the cords settle
	_look(Vector3(0.45, 0.95, 1.35), Vector3(0.0, 0.62, 0.45))
	await _save("holster")


## One gun hanging in its holster, close, from the front.
func _shot_gunclose() -> void:
	_model.on_power_on()
	await _frames(60)
	_look(Vector3(-0.05, 0.80, 0.95), Vector3(-0.25, 0.72, 0.52))
	await _save("gunclose")


## The left gun, straight on and from its own side.
func _shot_gunfront() -> void:
	_model.on_power_on()
	await _frames(60)
	_look(Vector3(-0.25, 0.74, 1.15), Vector3(-0.25, 0.72, 0.5))
	await _save("gunfront")


func _shot_gunside() -> void:
	_model.on_power_on()
	await _frames(60)
	_look(Vector3(-1.05, 0.72, 0.52), Vector3(-0.25, 0.70, 0.52))
	await _save("gunside")


## The pedal on the floor in front of the cabinet.
func _shot_pedal() -> void:
	_look(Vector3(0.9, 0.9, 1.9), Vector3(0.0, 0.1, 0.8))
	await _save("pedal")


func _shot_panel() -> void:
	_look(Vector3(0, 1.55, 1.15), Vector3(0, 0.98, 0.4))
	await _save("panel")


func _shot_bay() -> void:
	_model.set_lid_angle_deg(90.0)
	var cart := CART_SCENE.instantiate() as Node3D
	cart.systemid = _systemid
	cart.rom_path = "/tmp/sf2.zip"
	cart.game_label = "STREET FIGHTER II"
	cart.freeze = true
	add_child(cart)
	await _frames(8)
	var slot := _sys.get_node("CartridgeSlot") as XRToolsSnapZone
	slot.pick_up_object(cart)
	await _frames(6)
	_look(Vector3(0.7, 0.75, 1.5), Vector3(0, 0.25, 0.1))
	await _save("bay")


func _shot_landscape() -> void:
	_glass(384, 224)
	_look(Vector3(0, 1.26, 0.95), Vector3(0, 1.22, 0.27))
	await _save("landscape")


func _shot_portrait() -> void:
	_glass(224, 384)
	_look(Vector3(0, 1.26, 0.95), Vector3(0, 1.22, 0.27))
	await _save("portrait")


func _shot_coin() -> void:
	var door := _model.modules_of_kind(ArcadeProfiles.KIND_COIN)[0] as ArcadeCoinModule
	door.insert_coin()
	await get_tree().create_timer(0.11).timeout
	_look(Vector3(-0.05, 0.8, 0.85), Vector3(-0.14, 0.65, 0.42))
	await _save("coin")


## A board on its own, with the title the cartridge prints when it has no art: the text
## must sit ON the sticker, whichever way it is looked at. Prints how far apart they are.
var _board: Node3D = null


func _make_board() -> void:
	if _board != null:
		return
	_board = CART_SCENE.instantiate() as Node3D
	_board.systemid = _systemid
	_board.rom_path = "/tmp/sf2.zip"
	_board.game_label = "STREET FIGHTER II"
	_board.freeze = true
	_board.position = Vector3(2.0, 1.0, 0.0)
	add_child(_board)
	await _frames(10)
	var label := _board.find_child("Label", true, false) as MeshInstance3D
	var title := _board.get_node_or_null("GameLabel") as Label3D
	if label != null and title != null:
		var face: Vector3 = label.global_transform * label.get_aabb().get_center()
		print("[probe] sticker centre ", face, "  title at ", title.global_position,
			"  gap ", title.global_position.distance_to(face), " m, title visible=", title.visible)


func _shot_board() -> void:
	await _make_board()
	_look(Vector3(2.0, 1.15, 0.55), Vector3(2.0, 1.0, 0.0))
	await _save("board")


func _shot_boardside() -> void:
	await _make_board()
	_look(Vector3(2.55, 1.12, 0.15), Vector3(2.0, 1.0, 0.0))
	await _save("boardside")


## Aiming at a player's panel lights ALL of it, as aiming at a controller lights the controller.
func _shot_hover() -> void:
	var panels := _model.modules_of_kind(ArcadeProfiles.KIND_STICK_BUTTONS)
	var p1 := panels[0] as ArcadeControlModule
	if p1.player != 0:
		p1 = panels[1] as ArcadeControlModule
	var grip := p1.grip()
	grip.pointer_event(XRToolsPointerEvent.new(XRToolsPointerEvent.Type.ENTERED, null, grip, Vector3.ZERO, Vector3.ZERO))
	_look(Vector3(-0.1, 1.5, 1.05), Vector3(-0.1, 0.98, 0.4))
	await _save("hover")
	grip.pointer_event(XRToolsPointerEvent.new(XRToolsPointerEvent.Type.PRESSED, null, grip, Vector3.ZERO, Vector3.ZERO))
	await _save("attached")
	grip.pointer_event(XRToolsPointerEvent.new(XRToolsPointerEvent.Type.PRESSED, null, grip, Vector3.ZERO, Vector3.ZERO))


## A notice floats in front of the monitor, parallel to it, clear of the cabinet.
func _shot_toast() -> void:
	var t: AchievementToast = _sys._machine_toast()
	t.show_notice("Arcade", "Could not start", "This core refused the game.\nsfix.sfix NOT FOUND (tried in wakuwak7)",
		AchievementToast.ACCENT_NOTICE)
	await get_tree().create_timer(1.0).timeout
	_look(Vector3(0.5, 1.45, 2.3), Vector3(0.0, 1.3, 0.6))
	await _save("toast")
