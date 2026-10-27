## Photographs the Morphing Arcade Cabinet. WINDOWED, never --headless: the dummy
## renderer returns a correctly sized BLANK image, so a size check passes on nothing.
##
##   "$godot" --path RetroXR res://Tools/models/arcade_cabinet_probe.tscn \
##       --resolution 1280x720 --position 20,20 -- --out=/some/dir [--shots=front,three]
##
## --model=<registry id> and --system=<systemid> photograph another cabinet (the default is
## arcade_cabinet_generic on `arcade`); the extra shots `holster` and `pedal` are for the gun cabinets.
##
## --rom=<file name> dresses the cabinet in that game's scraped art (`artfront`, `artright`, `artleft`
## shots), read from the player's data root; `--art=wheel|cover|none` leaves one half out.
##
## One PNG per shot, named <shot>.png in --out. Shots: front, three, side, panel, bay,
## landscape, portrait, coin, holster, pedal. The monitor shots feed the screen module a test card
## (a circle and a grid, so a stretch shows as an ellipse) of the shape a core would
## hand over: 384x224 CPS1 on a 4:3 tube, and a vertical 224x384 frame.
##
## The board in the bay wears printed-title art, the door is opened through its own
## hinge, and the coin is a real ArcadeCoinModule toss caught in the air.
##
## --forms=<romset>,<romset>... photographs the cabinet in the form each game asks for
## (ArcadeCabinetSpecs.for_game: its panels, guns, cockpit or stage), one `form_<romset>.png` each from
## the front three-quarter, a `formside_<romset>.png` from the side, framed to what the form covers, and a
## `formscreen_<romset>.png` of the monitor square on, a `formdeck_<romset>.png` of the control deck from above and in front of the player and, for a form with pedals, a `formfeet_<romset>.png` of them, and for a sit-down cockpit a `formseat_<romset>.png` from the seat's eyes.
## A game with a scope (Silent Scope) is fed a frame of two screens as MAME draws it (8.03 x 3: a scene on the left, the scope's own picture on the right): the monitor shows the left half,
## and `formscope_<romset>.png` is the rifle's eyepiece from the player's eye, `formrifle_<romset>.png` the rifle from behind and above.
## A game of two screens over one another (a PlayChoice-10) is fed a stacked frame (4 x 6.03), so `formscreen_<romset>.png` shows the portrait pair.
## --artwork=<dir> reads MAME artwork from that folder instead of the data root's: each form then wears its
## game's bezel when the folder has one (ArcadeBezel), and a `bezel_<romset>.png` close-up is taken of it.
##
## `hands` photographs a headset's hands on the panel (ArcadePanelHands): the right one holding the stick leaned over (its
## outline amber), the left with a finger on button 2 (sunk in its flange); `handswheel` the same at a driving cockpit's wheel
## turned by a hand, `handscycle` at Prop Cycle's bars (pushed right and away) and crank, `handsslot` at Panic Park's two levers.
## A fake hand is an XRController3D on a tracker of its own, a small red ball at its fingertip.
extends Node3D

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const CART_SCENE := preload("res://Scenes/Objects/media/cartridge.tscn")
const DISC_SCENE := preload("res://Scenes/Objects/media/disc.tscn")

var _out := "/tmp"
var _model_id := "arcade_cabinet_generic"
var _systemid := "arcade"
var _shots: Array[String] = ["front", "three", "panel", "bay", "landscape", "portrait", "coin", "board", "boardside", "hover", "toast", "side"]
var _rom := "sf2.zip"
var _art := ""
var _forms: Array[String] = []
var _artwork := ""
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
		elif a.begins_with("--rom="):
			_rom = a.substr(6)
		elif a.begins_with("--art="):
			_art = a.substr(6)
		elif a.begins_with("--shots="):
			_shots.clear()
			for s in a.substr(8).split(","):
				_shots.append(s)
		elif a.begins_with("--artwork="):
			_artwork = a.substr(10)
			ArcadeBezel.test_root = _artwork
		elif a.begins_with("--forms="):
			for s in a.substr(8).split(","):
				_forms.append(s)
			_shots = ["forms"]
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


## A frame of several screens as MAME draws them, from the profile's own rectangles (ArcadeGameProfile.screen_part): each screen a 4:3 test card of its own
## colour with its number in bars (so which is which cannot be mistaken) and, for the scope's, a crosshair in a circle.
func _frame_for(profile: ArcadeGameProfile, height: int) -> ImageTexture:
	var aspect := profile.frame_aspect()
	var img := Image.create(roundi(height * aspect), height, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.02, 0.02, 0.02))
	var tints: Array[Color] = [Color(0.18, 0.32, 0.60), Color(0.15, 0.45, 0.22), Color(0.55, 0.32, 0.15), Color(0.45, 0.2, 0.5), Color(0.5, 0.5, 0.15)]
	for i in profile.screens():
		var part := profile.screen_part(i)
		var r := Rect2i(roundi(part.position.x * img.get_width()), roundi(part.position.y * height),
			roundi(part.size.x * img.get_width()), roundi(part.size.y * height))
		img.fill_rect(r, tints[i % tints.size()])
		# Screen number i + 1 as bars along the top, a grid, and a circle that is round on the screen's own shape.
		for b in i + 1:
			img.fill_rect(Rect2i(r.position.x + 12 + b * 22, r.position.y + 10, 14, 26), Color.WHITE)
		var centre := Vector2(r.position) + Vector2(r.size) * 0.5
		var radius := minf(r.size.x, r.size.y) * 0.34
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				var d := Vector2(x, y).distance_to(centre)
				if absf(d - radius) < 2.0 or (absf(x - centre.x) < 1.0 and d < radius) or (absf(y - centre.y) < 1.0 and d < radius):
					img.set_pixel(x, y, Color.WHITE)
				elif (x - r.position.x) % 40 == 0 or (y - r.position.y) % 40 == 0:
					img.set_pixel(x, y, tints[i % tints.size()].lightened(0.25))
		img.fill_rect(Rect2i(r.position, Vector2i(r.size.x, 3)), Color.RED)
		img.fill_rect(Rect2i(r.position.x, r.end.y - 3, r.size.x, 3), Color.RED)
		img.fill_rect(Rect2i(r.position, Vector2i(3, r.size.y)), Color.RED)
		img.fill_rect(Rect2i(r.end.x - 3, r.position.y, 3, r.size.y), Color.RED)
	return ImageTexture.create_from_image(img)


## Feed the monitor module a frame of several screens, and the scope's lens if the rifle has one, as a running core would.
func _glass_frame(profile: ArcadeGameProfile) -> void:
	var screen := _model.modules_of_kind(ArcadeProfiles.KIND_SCREEN)[0] as ArcadeScreenModule
	var tex := _frame_for(profile, 300)
	screen._material.set_shader_parameter("source_tex", tex)
	screen.get_screen().set_surface_override_material(0, screen._material)
	screen._serial = -1
	screen.aspect_override = profile.frame_aspect()
	screen.present(tex, false, false, 0.0)
	print("[probe] glass frame %.3f cut=%s fit=%s lens=%s" % [screen.current_aspect(), screen.is_cut(), screen.current_fit(), screen.lens() != null])


func _glass(w: int, h: int) -> void:
	var screen := _model.modules_of_kind(ArcadeProfiles.KIND_SCREEN)[0] as ArcadeScreenModule
	var tex := _card(w, h, Color(0.3, 0.8, 0.4))
	screen._material.set_shader_parameter("source_tex", tex)
	screen.get_screen().set_surface_override_material(0, screen._material)
	screen._serial = -1
	screen._refresh_geometry(tex)
	# A rifle game of one screen: its scope is a digital one, fed through present() with the rifle pointed a little right of the middle and above it.
	if screen.scope_zoom > 1.0:
		var guns := _model.get_parent().call("captive_controllers") as Array if _model.get_parent().has_method("captive_controllers") else []
		for gun: Variant in guns:
			if is_instance_valid(gun) and "last_aim" in gun:
				(gun as Node).set("last_aim", Vector2i(9000, -6000))
		screen.present(tex, false, false, 0.0)
	print("[probe] glass %dx%d aspect=%.3f fit=%s lens=%s" % [w, h, screen.current_aspect(), screen.current_fit(), screen.lens() != null])


## Light (or put out) the glow of every player's grip, as aiming at it does.
func _light_grips(on: bool) -> void:
	for panel_node: Node in _model.modules_of_kind(ArcadeProfiles.KIND_STICK_BUTTONS):
		var grip := (panel_node as ArcadeControlModule).grip()
		if grip != null:
			grip.set("_hovered", on)
			grip.call("_refresh")
	await _frames(3)


## Each game's form, built as a board in the bay would build it, from the front three-quarter and the side.
func _shot_forms() -> void:
	for romset in _forms:
		var profile := ArcadeGameProfile.for_romset(romset)
		_model.morph_to(_model.form_for(profile))
		_model.apply_game_profile(profile)
		await _frames(10)
		_model = _sys.get_model() as RetroSystemModelArcadeCabinet
		_model.set_process(false)
		if profile.screens() > 1 and profile.frame_aspect() > 0.0:
			await _frames(4)
			_glass_frame(profile)
		elif profile.is_vertical():
			_glass(224, 288)
		else:
			_glass(384, 224)
		_model.on_power_on()
		var size := _model.ground_footprint()
		var center := _model.ground_footprint_center()
		var mid := Vector3(center.x, 0.85, center.y)
		var reach := maxf(size.y, size.x) * 0.9 + 1.6
		_look(mid + Vector3(reach * 0.55, 1.15, reach * 0.85), mid)
		print("[probe] form %s: %s, %d panel(s), footprint %s about %s" % [romset,
			str(_model.form_spec().get("form", "own")), _model.modules_of_kind(ArcadeProfiles.KIND_STICK_BUTTONS).size(),
			str(size), str(center)])
		await _save("form_" + romset)
		_look(mid + Vector3(reach * 0.95, 0.75, 0.0), mid)
		await _save("formside_" + romset)
		# The monitor square on, from where a player standing at the glass would look.
		var tube := _model.get_builtin_screen()
		_look(tube.global_position + tube.global_basis.z * 1.1, tube.global_position)
		await _save("formscreen_" + romset)
		# The control deck close up, from above and in front of where a player stands: what a rhythm game's controller or a rotary stick looks like.
		var deck := _model.find_child("Deck", true, false) as Node3D
		if deck != null:
			var span := maxf(0.55, _model.cabinet_width * 0.8)
			_cam.fov = 50.0
			_look(deck.global_position + deck.global_basis.z * span * 0.85 - deck.global_basis.y * span * 0.55, deck.global_position)
			await _save("formdeck_" + romset)
			_cam.fov = 58.0
		# A scope: the rifle's eyepiece from where the player's eye would be, and the rifle from behind.
		var lens := _model.get_parent().call("captive_controllers") as Array if _model.get_parent().has_method("captive_controllers") else []
		var eye_lens: MeshInstance3D = null
		for gun: Variant in lens:
			eye_lens = (gun as Node).find_child("ScopeScreen", true, false) as MeshInstance3D
			if eye_lens != null:
				break
		if eye_lens != null:
			_cam.fov = 40.0
			_look(eye_lens.global_position + eye_lens.global_basis.z * 0.16, eye_lens.global_position)
			await _save("formscope_" + romset)
			_cam.fov = 58.0
			_look(eye_lens.global_position + eye_lens.global_basis.z * 0.55 + Vector3(0.18, 0.22, 0.0), eye_lens.global_position + eye_lens.global_basis.z * -0.1)
			await _save("formrifle_" + romset)
		# What stands on the floor at the player's feet, close: a gun game's pedal, a driver's two.
		# What a seated driver sees, from the seat's EyePoint (a sit-down cockpit).
		var driver := _model.find_child("DriverSeat", true, false) as CockpitSeat
		if driver == null:
			driver = _model.find_child("BenchSeat1", true, false) as CockpitSeat
		if driver == null:
			driver = _model.find_child("RiderSeat", true, false) as CockpitSeat
		if driver != null:
			var eye := driver.eye_transform()
			_cam.global_transform = eye
			_cam.fov = 70.0
			await _save("formseat_" + romset)
			# And what is in the lap: the stick and the throttle of a flight cockpit, the wheel's dash of a driving one, from the same eyes pitched down.
			var lap := _model.find_child("StickBall", true, false) as Node3D
			if lap == null:
				lap = _model.find_child("WheelPivot", true, false) as Node3D
			if lap == null:
				lap = _model.find_child("Handlebars", true, false) as Node3D
			if lap == null:
				lap = _model.find_child("BarsPivot", true, false) as Node3D
			if lap != null:
				_cam.global_transform = eye
				_cam.look_at(lap.global_position, Vector3.UP)
				await _save("formlap_" + romset)
				# The same view with every grip lit, as it is when aimed at: the lit area is the control, not the console round it.
				await _light_grips(true)
				await _save("formgrip_" + romset)
				await _light_grips(false)
			_cam.fov = 58.0
		# A rider standing on a board or skis: what they see from the plate, and the rig leaned over to the right, seen from behind.
		var board := _model.find_child("Board", true, false) as Node3D
		var plate := _model.find_child("LeanPivot", true, false) as Node3D
		if board != null and plate != null:
			var rest := plate.global_position
			var up := board.global_basis.y
			var back := board.global_basis.z
			_cam.fov = 70.0
			_look(rest + up * 1.55 + back * 0.05, rest + up * 1.15 - back * 1.2)
			await _save("formstand_" + romset)
			# And down at the rail: the crossbar with START on it and the two grips, from the same eyes.
			_cam.fov = 80.0
			_look(rest + up * 1.55 + back * 0.05, rest + up * 0.80 - back * 0.30)
			await _save("formrail_" + romset)
			var rig := _model.find_child("Player1", true, false) as ArcadeControlModule
			if rig != null:
				rig.show_state(1 << ControllerBindings.JOYPAD_RIGHT, Vector4i.ZERO)
				for i in 90:
					rig.tick(0.05)
				print("[probe] lean %s: steering %.2f, the plate's up is %s" % [romset, rig.steering(), str(plate.basis.y)])
				_cam.fov = 58.0
				_look(rest + back * 2.4 + up * 1.2, rest + up * 0.55)
				await _save("formlean_" + romset)
				rig.show_state(0, Vector4i.ZERO)
				for i in 90:
					rig.tick(0.05)
			_cam.fov = 58.0
		# A cockpit on a moving base, thrown over: full stick to the right and pulled back, or the wheel hard over with the gas down.
		var panel := _model.find_child("Player1", true, false) as ArcadeControlModule
		if panel != null and _model.find_child("MotionPivot", true, false) != null:
			panel.motion_override = 1
			var mask := (1 << ControllerBindings.JOYPAD_RIGHT) | (1 << ControllerBindings.JOYPAD_DOWN)
			panel.show_state(mask, Vector4i.ZERO)
			for i in 90:
				panel.tick(0.05)
			print("[probe] motion %s: %s" % [romset, str(panel.motion_state())])
			_look(mid + Vector3(reach * 0.95, 0.75, 0.0), mid)
			await _save("formtilt_" + romset)
			_look(mid + Vector3(0.0, 1.0, reach * 1.1), mid)
			await _save("formtiltfront_" + romset)
			panel.show_state(0, Vector4i.ZERO)
			for i in 90:
				panel.tick(0.05)
		var feet := _model.find_child("Pedal1", true, false) as Node3D
		var from := Vector3(0.38, 0.32, 0.46)
		if feet == null:
			# A driver's two, from the side (the seat and the dash stand fore and aft of them).
			feet = _model.find_child("PedalAxle", true, false) as Node3D
			from = Vector3(0.70, 0.40, 0.05)
		if feet != null:
			_look(feet.global_position + from, feet.global_position + Vector3(0.0, 0.04, 0.0))
			await _save("formfeet_" + romset)
		if not _artwork.is_empty():
			_model._ask_bezel("/probe/%s.zip" % romset)
			for i in 120:
				if _model.bezel_texture() != null:
					break
				await _frames(1)
			if _model.bezel_texture() != null:
				var glass := _model.get_builtin_screen()
				var at := glass.global_position
				_look(at + glass.global_basis.z * 0.95 + Vector3(0.0, 0.05, 0.0), at)
				await _save("bezel_" + romset)
		_model.on_power_off()


## A fake hand for the `hands` shots: a controller on a tracker of its own, its pose the identity, so its poke tip is
## 6 cm ahead of it along -Z; a red ball marks the tip.
func _hand(side: String) -> Dictionary:
	var origin := XROrigin3D.new()
	add_child(origin)
	var ctrl := XRController3D.new()
	ctrl.tracker = StringName(side + "_hand")
	ctrl.pose = &"default"
	origin.add_child(ctrl)
	var tracker := XRControllerTracker.new()
	tracker.name = StringName(side + "_hand")
	XRServer.add_tracker(tracker)
	tracker.set_pose(&"default", Transform3D.IDENTITY, Vector3.ZERO, Vector3.ZERO, XRPose.XR_TRACKING_CONFIDENCE_HIGH)
	var marker := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.006
	ball.height = 0.012
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.15, 0.15)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ball.material = mat
	marker.mesh = ball
	marker.position = Vector3(0, 0, -PokeTip.TIP_FORWARD)
	ctrl.add_child(marker)
	return {"origin": origin, "ctrl": ctrl, "tracker": tracker}


func _tip_at(h: Dictionary, world: Vector3) -> void:
	(h["origin"] as XROrigin3D).global_position = world + Vector3(0, 0, PokeTip.TIP_FORWARD)


func _hand_trigger(h: Dictionary, value: float) -> void:
	(h["tracker"] as XRControllerTracker).set_input(&"trigger", value)


func _drop_hands(hands: Array) -> void:
	for h: Dictionary in hands:
		XRServer.remove_tracker(h["tracker"] as XRControllerTracker)
		(h["origin"] as Node).queue_free()


## The hands on a panel: the right holds the stick leaned right, the left has a finger on button 2.
func _shot_hands() -> void:
	_sys.is_powered_on = true
	var input := _model.arcade_input()
	var panel := _model.modules_of_kind(ArcadeProfiles.KIND_STICK_BUTTONS)[0] as ArcadeControlModule
	var right := _hand("right")
	var left := _hand("left")
	input._right_vr_ctrl = right["ctrl"]
	input._left_vr_ctrl = left["ctrl"]
	var ball := (panel.find_child("StickPivot", true, false) as Node3D).global_transform * Vector3(0, 0, 0.085)
	var cap := panel.find_child("Btn2", true, false) as MeshInstance3D
	_tip_at(right, ball)
	_tip_at(left, cap.global_transform * Vector3(0, cap.mesh.get_aabb().size.y * 0.5 + 0.002, 0))
	await _frames(3)
	_hand_trigger(right, 1.0)
	await _frames(3)
	_tip_at(right, ball + panel.global_transform.basis.x * 0.03)
	for i in 8:
		panel.tick(0.016)
		await _frames(1)
	print("[probe] hands: pressed mask ", panel.hand_buttons(), " thumbstick ", panel.hand_thumbstick(0),
		" stick lean ", panel.stick_lean(), " last_sent ", input.last_sent)
	_look(Vector3(0.12, 1.42, 1.02), Vector3(-0.13, 0.99, 0.43))
	await _save("hands")
	_look(Vector3(-0.55, 1.20, 0.80), Vector3(-0.13, 0.99, 0.43))
	await _save("handsside")
	input._right_vr_ctrl = null
	input._left_vr_ctrl = null
	_drop_hands([right, left])
	_sys.is_powered_on = false


## The same at a driving cockpit's wheel: the form Daytona USA asks for, the right hand on the rim turned 60 degrees.
func _shot_handswheel() -> void:
	var profile := ArcadeGameProfile.for_romset("daytona")
	_model.morph_to(_model.form_for(profile))
	_model.apply_game_profile(profile)
	await _frames(10)
	_model = _sys.get_model() as RetroSystemModelArcadeCabinet
	_model.set_process(false)
	_sys.is_powered_on = true
	var input := _model.arcade_input()
	var panel := _model.modules_of_kind(ArcadeProfiles.KIND_STICK_BUTTONS)[0] as ArcadeControlModule
	var pivot := panel.find_child("WheelPivot", true, false) as Node3D
	var mount := pivot.get_parent() as Node3D
	var rim := pivot.find_child("WheelRim", true, false) as MeshInstance3D
	var radius := ((rim.mesh as TorusMesh).outer_radius - 0.014)
	var hand := _hand("right")
	input._right_vr_ctrl = hand["ctrl"]
	var top := mount.global_transform * Vector3(0, 0, -radius)
	_tip_at(hand, top)
	await _frames(3)
	_hand_trigger(hand, 1.0)
	await _frames(3)
	var turn := deg_to_rad(ArcadeControlModule.WHEEL_LOCK_DEG) * 0.5
	for i in 12:
		_tip_at(hand, mount.global_transform * (Basis(Vector3.UP, -turn * float(i + 1) / 12.0) * Vector3(0, 0, -radius)))
		await _frames(1)
		panel.tick(0.016)
	print("[probe] handswheel: steering ", panel.steering(), " thumbstick ", panel.hand_thumbstick(0))
	_look(mount.global_position + Vector3(0.55, 0.35, 0.65), mount.global_position)
	await _save("handswheel")
	var driver := _model.find_child("DriverSeat", true, false) as CockpitSeat
	if driver != null:
		_cam.global_transform = driver.eye_transform()
		_cam.fov = 70.0
		await _save("handsseat")
		_cam.fov = 58.0
	input._right_vr_ctrl = null
	_drop_hands([hand])
	_sys.is_powered_on = false


## The same at a bicycle (Prop Cycle): the right hand on a grip pushed right and away, the left on a pedal of the crank.
func _shot_handscycle() -> void:
	var profile := ArcadeGameProfile.for_romset("propcycl")
	_model.morph_to(_model.form_for(profile))
	_model.apply_game_profile(profile)
	await _frames(10)
	_model = _sys.get_model() as RetroSystemModelArcadeCabinet
	_model.set_process(false)
	_sys.is_powered_on = true
	var input := _model.arcade_input()
	var panel := _model.modules_of_kind(ArcadeProfiles.KIND_STICK_BUTTONS)[0] as ArcadeControlModule
	var right := _hand("right")
	var left := _hand("left")
	input._right_vr_ctrl = right["ctrl"]
	input._left_vr_ctrl = left["ctrl"]
	var grip := (panel.find_child("BarGripR", true, false) as Node3D).global_position
	var pedal := (panel.find_child("CrankPedalR", true, false) as Node3D).global_position
	_tip_at(right, grip)
	_tip_at(left, pedal)
	await _frames(3)
	_hand_trigger(right, 1.0)
	_hand_trigger(left, 1.0)
	await _frames(3)
	_tip_at(right, grip + Vector3(0.075, 0.0, -0.05))
	for i in 8:
		panel.tick(0.016)
		await _frames(1)
	print("[probe] handscycle: steering ", panel.steering(), " pitch ", panel.bars_pitch(), " sticks ", panel.hand_thumbstick(0), panel.hand_thumbstick(1))
	_look(grip + Vector3(1.0, 0.45, 0.95), grip + Vector3(0.0, -0.30, 0.25))
	await _save("handscycle")
	input._right_vr_ctrl = null
	input._left_vr_ctrl = null
	_drop_hands([right, left])
	_sys.is_powered_on = false


## And at Panic Park's slot: a hand on each lever, the right one pushed along it, the left one the other way.
func _shot_handsslot() -> void:
	var profile := ArcadeGameProfile.for_romset("panicprk")
	_model.morph_to(_model.form_for(profile))
	_model.apply_game_profile(profile)
	await _frames(10)
	_model = _sys.get_model() as RetroSystemModelArcadeCabinet
	_model.set_process(false)
	_sys.is_powered_on = true
	var input := _model.arcade_input()
	var panels := _model.modules_of_kind(ArcadeProfiles.KIND_STICK_BUTTONS)
	var right := _hand("right")
	var left := _hand("left")
	input._right_vr_ctrl = right["ctrl"]
	input._left_vr_ctrl = left["ctrl"]
	var ball := func(panel: Node3D) -> Vector3:
		return (panel.find_child("SlidePivot", true, false) as Node3D).global_transform * Vector3(0, 0, 0.14)
	var ball_a: Vector3 = ball.call(panels[0])
	var ball_b: Vector3 = ball.call(panels[1])
	_tip_at(left, ball_a)
	_tip_at(right, ball_b)
	await _frames(3)
	_hand_trigger(left, 1.0)
	_hand_trigger(right, 1.0)
	await _frames(3)
	_tip_at(left, ball_a + Vector3(0.09, 0.0, 0.0))
	_tip_at(right, ball_b + Vector3(-0.05, 0.0, 0.0))
	for i in 8:
		for panel: ArcadeControlModule in panels:
			panel.tick(0.016)
		await _frames(1)
	print("[probe] handsslot: steering ", (panels[0] as ArcadeControlModule).steering(), " and ", (panels[1] as ArcadeControlModule).steering())
	_look(ball_a.lerp(ball_b, 0.5) + Vector3(0.0, 0.55, 0.85), ball_a.lerp(ball_b, 0.5))
	await _save("handsslot")
	input._right_vr_ctrl = null
	input._left_vr_ctrl = null
	_drop_hands([right, left])
	_sys.is_powered_on = false


func _shot_front() -> void:
	_glass(384, 224)
	_model.on_power_on()
	_look(Vector3(0, 1.05, 3.0), Vector3(0, 0.9, 0))
	await _save("front")


## The game's art on the marquee and sides, from the data root's scraped media (or a RomM cover).
func _dress() -> void:
	var art := ArcadeCabinetArt.for_rom(_systemid, _rom)
	print("[probe] art for ", _rom, ": wheel=", art["wheel"], " cover=", art["cover"])
	if _art == "wheel":
		art["cover"] = null
	elif _art == "cover":
		art["wheel"] = null
	elif _art == "none":
		art = {"wheel": null, "cover": null}
	_model.apply_art(art["wheel"], art["cover"])


## The composite input's plate on the bay floor, from above and the front.
func _shot_avin() -> void:
	_model.set_lid_angle_deg(90.0)
	await _frames(4)
	_look(Vector3(-0.2, 0.62, 0.35), Vector3(-0.2, 0.11, -0.2))
	await _save("avin")


func _shot_artfront() -> void:
	_dress()
	_glass(384, 224)
	_model.on_power_on()
	_look(Vector3(0, 1.3, 3.0), Vector3(0, 1.1, 0))
	await _save("artfront")


func _shot_artright() -> void:
	_dress()
	_model.on_power_on()
	_look(Vector3(3.0, 1.3, 1.6), Vector3(0, 0.95, 0))
	await _save("artright")


func _shot_artleft() -> void:
	_dress()
	_look(Vector3(-3.0, 1.3, 1.6), Vector3(0, 0.95, 0))
	await _save("artleft")


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


## The yellow rectangle a held cabinet shows on the floor where it will be set down (GroundPlacement), beside the
## cabinet already standing there.
func _shot_ground() -> void:
	var placer := _sys.get_node_or_null("GroundPlacement") as GroundPlacement
	if placer == null:
		print("[probe] no placer on this cabinet")
		return
	var eye := Vector3(0.0, 1.6, 3.0)
	placer.preview(GroundPlacement.placement_for(Vector3(0.9, 1.2, 2.0), Vector3(0.0, -1.0, -1.0), 0.0, eye))
	await _frames(4)
	_look(Vector3(1.6, 1.5, 3.6), Vector3(0.6, 0.4, 1.0))
	await _save("ground")
	placer.preview({})


## The buttons close up: the cap and the flange of its own colour.
func _shot_buttons() -> void:
	_look(Vector3(-0.12, 1.18, 0.78), Vector3(-0.12, 0.99, 0.40))
	await _save("buttons")


## The CD-ROM bay under the JAMMA bay with a disc pushed half out by EJECT, and the board standing on it.
func _shot_drive() -> void:
	_model.set_lid_angle_deg(90.0)
	var bay: ArcadeBayUnit = _sys.get_bay()
	if bay == null or not bay.has_drive():
		print("[probe] no drive in this bay")
		return
	var cart := CART_SCENE.instantiate() as Node3D
	cart.systemid = _systemid
	cart.rom_path = "/tmp/sf2.zip"
	cart.game_label = "STREET FIGHTER II"
	cart.freeze = true
	add_child(cart)
	var disc := DISC_SCENE.instantiate() as RetroDisc
	disc.systemid = "arcade"
	disc.rom_path = "/tmp/sf2/disc.chd"
	disc.game_label = "STREET FIGHTER II"
	disc.freeze = true
	add_child(disc)
	await _frames(8)
	bay.slot.pick_up_object(cart)
	bay.restore_disc(disc)
	await _frames(6)
	bay.eject_disc()
	await _frames(70)
	_look(Vector3(0.45, 0.62, 1.05), Vector3(0, 0.22, 0.12))
	await _save("drive")


func _shot_panel() -> void:
	_look(Vector3(0, 1.55, 1.15), Vector3(0, 0.98, 0.4))
	await _save("panel")


## The power button as a latched ON / OFF switch (attract on, a game in the bay): off, then on. switch_off.png, switch_on.png.
func _shot_switch() -> void:
	AppPrefs.arcade_attract_mode = true
	_model.set_lid_angle_deg(90.0)
	var cart := CART_SCENE.instantiate() as Node3D
	cart.systemid = _systemid
	cart.rom_path = "/tmp/sf2.zip"
	cart.freeze = true
	cart.position = Vector3(0, 3, 0)
	add_child(cart)
	await _frames(8)
	(_sys as RetroSystem).get_bay().slot.pick_up_object(cart)
	await _frames(8)
	var button := (_sys as RetroSystem).get_node("PowerButton") as Node3D
	var at := button.global_position
	_look(at + Vector3(0.0, 0.18, 0.28), at)
	await _save("switch_off")
	(_sys as RetroSystem).toggle_power()
	await _frames(6)
	await _save("switch_on")
	(_sys as RetroSystem).toggle_power()
	AppPrefs.arcade_attract_mode = false


## The panel dressed for several games (ArcadeGameProfile): the table alone, then with the words FBNeo
## publishes (measured with Tools/cores/arcade_descriptors_probe). One PNG per game: game_<name>.png.
func _shot_game() -> void:
	var fbneo_sf2 := [[2, "Coin"], [3, "Start"], [4, "Up"], [5, "Down"], [6, "Left"], [7, "Right"], [1, "Weak Punch"],
		[9, "Medium Punch"], [10, "Strong Punch"], [0, "Weak Kick"], [8, "Medium Kick"], [11, "Strong Kick"]]
	var fbneo_dino := [[2, "Coin"], [3, "Start"], [4, "Up"], [5, "Down"], [6, "Left"], [7, "Right"], [0, "Attack"], [8, "Jump"]]
	var games := [["sf2_table", "sf2", []], ["sf2_words", "sf2", fbneo_sf2], ["dino_words", "dino", fbneo_dino],
		["hotd2", "hotd2", []], ["pong", "pong", []], ["daytona", "daytona", []]]
	for g: Array in games:
		var profile := ArcadeGameProfile.for_romset(str(g[1]))
		var rows: Array = []
		for port in 2:
			for d: Array in g[2]:
				rows.append({"port": port, "device": 1, "index": 0, "id": d[0], "description": d[1]})
		if not rows.is_empty():
			profile.apply_descriptors(rows)
		_model.apply_game_profile(profile)
		await _frames(3)
		_look(Vector3(0, 1.45, 1.05), Vector3(0, 0.98, 0.42))
		await _save("game_%s" % g[0])
	_model.apply_game_profile(null)


func _shot_bay() -> void:
	_model.set_lid_angle_deg(90.0)
	var cart := CART_SCENE.instantiate() as Node3D
	cart.systemid = _systemid
	cart.rom_path = "/tmp/sf2.zip"
	cart.game_label = "STREET FIGHTER II"
	cart.freeze = true
	add_child(cart)
	await _frames(8)
	var bay: ArcadeBayUnit = _sys.get_bay()
	var slot: XRToolsSnapZone = bay.slot if bay != null else _sys.get_node("CartridgeSlot") as XRToolsSnapZone
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


## The coin door close up: the RETURN cap and its legend, and a coin the cabinet gave back lying in the
## cup (a coin into a switched-off cabinet rolls straight out; ArcadeCoinModule.return_coin).
func _shot_return() -> void:
	var door := _model.modules_of_kind(ArcadeProfiles.KIND_COIN)[0] as ArcadeCoinModule
	door.return_coin()
	await get_tree().create_timer(ArcadeCoinModule.RETURN_FALL_SECONDS + 0.1).timeout
	var at := door.global_position
	_look(at + Vector3(0.05, 0.06, 0.30), at + Vector3(0.0, -0.03, 0.0))
	await _save("return")


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
