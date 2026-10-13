## The Game Boy Camera stand-in: that a cartridge whose header says POCKET CAMERA
## wears it, that the part of it in the slot is still a Game Boy cartridge, and
## that the ball swivels the way the real one does -- about its upright axle, the
## lens swinging round sideways and never tipping over the top.
##
## Spawns the cartridge from a fixture header (cartridge type 0xFC and nothing
## else), twists the ball with a point where a latched hand would be, saves and
## restores it, then seats it in a Game Boy Color through restore_cartridge().
## A plain Game Boy cartridge beside it is the control.
##
##   godot --headless --path RetroXR res://Tools/models/game_boy_camera_probe.tscn
##
## Windowed (no --headless, `--resolution 320x240 --position 20,20`) it also
## photographs the camera into probe_out/gb_camera/, and with `-- --film` writes
## the swivel as frames into probe_out/gb_camera/film/ for an mp4.
extends Node3D

const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const CART_SCENE := preload("res://Scenes/Objects/media/cartridge.tscn")
const OUT_DIR := "res://probe_out/gb_camera"
const FIXTURE_DIR := "user://__gb_camera_probe"
const KNOB_PATH := "CartModel/Overhang/LensKnob"
const SHOT := Vector2i(1200, 900)
## How far off the axle the stand-in hand holds the ball.
const REACH := 0.03

var _fail := false
var _shot := 0
var _sv: SubViewport = null
var _cam: Camera3D = null


func _check(ok: bool, what: String) -> void:
	print("[gbcam] %s: %s" % ["PASS" if ok else "FAIL", what])
	if not ok:
		_fail = true


func _ready() -> void:
	get_tree().create_timer(240.0).timeout.connect(func() -> void:
		print("[gbcam] TIMEOUT")
		_clear_fixtures()
		get_tree().quit(1))
	get_tree().current_scene = self
	_run()


func _wait(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


## A 0x150-byte header with only what the lookup reads.
func _rom(file_name: String, title: String, cart_type: int) -> String:
	var h := PackedByteArray()
	h.resize(GbCartShell.HEADER_BYTES)
	for i in mini(title.length(), GbCartShell.TITLE_BYTES):
		h[GbCartShell.TITLE_AT + i] = title.unicode_at(i)
	h[GbcCartShell.CART_TYPE_AT] = cart_type
	h[GbCartShell.DESTINATION_AT] = 0x01
	h[GbCartShell.OLD_LICENSEE_AT] = GbCartShell.OLD_LICENSEE_USE_NEW
	h[GbCartShell.NEW_LICENSEE_AT] = 0x30
	h[GbCartShell.NEW_LICENSEE_AT + 1] = 0x31
	var dir := ProjectSettings.globalize_path(FIXTURE_DIR)
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join(file_name)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(h)
	f.close()
	return path


func _clear_fixtures() -> void:
	var dir := ProjectSettings.globalize_path(FIXTURE_DIR)
	if DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(f))
		DirAccess.remove_absolute(dir)


func _cart(rom: String, at: Vector3, shell: StringName = &"", body := "") -> RetroCartridge:
	var cart := CART_SCENE.instantiate() as RetroCartridge
	cart.systemid = "gb"
	cart.rom_path = rom
	cart.shell_preset = shell
	cart.body_region = body
	cart.game_label = "Game Boy Camera"
	cart.position = at
	cart.freeze = true
	add_child(cart)
	cart.add_to_group("spawned")
	return cart


func _run() -> void:
	var made := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_check(made == OK, "probe_out/gb_camera is there to write to (%s)" % error_string(made))
	_build_world()
	var camera_rom := _rom("camera.gb", "GAMEBOYCAMERA", GbCameraShell.CART_TYPE_CAMERA)
	var game_rom := _rom("game.gb", "TETRIS", 0x00)
	var cart := _cart(camera_rom, Vector3(0, 1, 0))
	var plain := _cart(game_rom, Vector3(-0.09, 1, 0))
	var red := _cart(camera_rom, Vector3(0.09, 1, 0), &"red")
	var forced := _cart(game_rom, Vector3(0.18, 1, 0), &"", GbCameraShell.BODY_CAMERA)
	await _wait(20)

	# --- which body --------------------------------------------------------------
	var model := cart.get_node_or_null("CartModel") as Node3D
	_check(model != null and model.scene_file_path == GbCameraShell.BODY, "a POCKET CAMERA header wears the camera")
	var plain_model := plain.get_node_or_null("CartModel") as Node3D
	_check(plain_model != null and plain_model.scene_file_path == GbCartShell.BODY,
		"and a game's header still wears the Game Boy cartridge")
	var forced_model := forced.get_node_or_null("CartModel") as Node3D
	_check(forced_model != null and forced_model.scene_file_path == GbCameraShell.BODY,
		"the camera body can be forced onto a game")
	if model == null:
		_clear_fixtures()
		get_tree().quit(1)
		return

	# --- the part in the slot is a Game Boy cartridge ----------------------------
	var size: Vector3 = MediaDimensions.CART_SIZES["gb"]
	_check(MediaDimensions.cart_size("gb", camera_rom, GbCameraShell.BODY) == size,
		"its size is the Game Boy cartridge's: %s mm" % (size * 1000.0))
	_check(model.scale.is_equal_approx(Vector3.ONE) and model.position.length() < 0.00001,
		"the body is unstretched and centred: scale %s, at %s mm" % [model.scale, model.position * 1000.0])
	var to_cart := cart.global_transform.affine_inverse()
	var tongue := model.get_node("Tongue") as MeshInstance3D
	# Everything outside the head, sticker included: the bounds the fit is made to.
	var fitted: AABB = cart._cart_model_aabb(model)
	_check(fitted.size.is_equal_approx(size) and fitted.get_center().length() < 0.00001,
		"what goes in the slot is exactly that box: %s mm" % (fitted.size * 1000.0))
	var own := (cart.get_node("CollisionShape3D") as CollisionShape3D).shape as BoxShape3D
	_check(own.size.is_equal_approx(size), "and so is the cartridge's own box: %s mm" % (own.size * 1000.0))

	# --- the head ----------------------------------------------------------------
	var head := cart.get_node_or_null("OverhangShape") as CollisionShape3D
	var aim := cart.get_node_or_null("PointerArea/OverhangShape") as CollisionShape3D
	_check(head != null and aim != null, "the head has a box to be taken by and one to be aimed at")
	_check(plain.get_node_or_null("OverhangShape") == null, "and a plain cartridge has neither")
	var head_box := AABB()
	if head != null:
		head_box = _box_of(head)
		print("[gbcam] head box %s .. %s mm" % [head_box.position * 1000.0, head_box.end * 1000.0])
		_check(head_box.position.y > size.y * 0.5 - 0.001 and absf(head_box.get_center().x) < 0.00001,
			"it stands past the cartridge's grip end, from %.1f to %.1f mm" % [head_box.position.y * 1000.0, head_box.end.y * 1000.0])
	var knob := model.get_node("Overhang/LensKnob") as VRKnob
	var pivot := knob.get_node("KnobPivot") as Node3D
	var ball := pivot.get_node("Ball") as MeshInstance3D
	var ball_box: AABB = (to_cart * ball.global_transform) * ball.get_aabb()
	var lens_y: float = (to_cart * (pivot.get_node("LensGlass") as Node3D).global_position).y
	_check(head_box.end.y < lens_y - 0.006,
		"nothing stands beside the ball: the housing ends %.1f mm below the lens" % ((lens_y - head_box.end.y) * 1000.0))
	_check(ball_box.end.z > head_box.end.z + 0.002 and ball_box.position.z < head_box.position.z - 0.002
			and ball_box.end.y > head_box.end.y + 0.02,
		"the ball stands on top of it and out of it front and back, so a ray reaches the ball first")
	var rest := cart.get_node_or_null("OverhangMovingShape") as CollisionShape3D
	_check(rest != null and _box_of(rest).grow(0.0001).encloses(ball_box),
		"the ball has a box on the cartridge too, so the camera lies on its ball and not through it")
	_check(cart.get_node_or_null("PointerArea/OverhangMovingShape") == null,
		"but none to be aimed at: a ray at the ball is for the ball's own grab")
	print("[gbcam] overall %.1f mm long, %.1f mm deep at the ball" % [
		(ball_box.end.y + size.y * 0.5) * 1000.0, ball_box.size.z * 1000.0])

	# --- its plastic -------------------------------------------------------------
	var blue := CartridgeColor.get_palette(GbCartShell.SYSTEMID).find(&"blue")
	var want_red := CartridgeColor.get_palette(GbCartShell.SYSTEMID).find(&"red")
	var base := model.get_node("Overhang/HeadBase") as MeshInstance3D
	_check((tongue.get_active_material(0) as BaseMaterial3D).albedo_color == blue.color
			and (base.get_active_material(0) as BaseMaterial3D).albedo_color == blue.color,
		"cartridge and head are the Game Boy palette's blue")
	var red_model := red.get_node("CartModel")
	_check(_albedo(red_model, "Tongue") == want_red.color and _albedo(red_model, "Overhang/HeadBase") == want_red.color,
		"and a forced shell repaints both")
	_check(_albedo(red_model, "Overhang/LensKnob/KnobPivot/Ball").r < 0.1, "but never the ball")
	var title := cart.get_node("GameLabel") as Label3D
	_check(title.visible and title.position.z > size.z * 0.5 and absf(title.position.x) < 0.001,
		"with no scraped art its title is on the sticker")

	# --- the ball ----------------------------------------------------------------
	_check(knob.target == pivot, "the ball is on a VRKnob that turns its pivot")
	_check(is_equal_approx(knob.deg_at_zero, -180.0) and is_equal_approx(knob.deg_at_one, 180.0)
			and is_equal_approx(knob.get_value(), 0.5), "half a turn either way from the front")
	_check(_lens(cart, pivot).z > 0.999, "at rest the lens looks out of the label side: %s" % _lens(cart, pivot))
	# A latched hand, taking the ball by the lens and carrying it round by the
	# cartridge's +X to the back. The lens has to stay under the hand the whole
	# way, and level: the real one swivels, it does not tip.
	var worst := 1.0
	var tipped := 0.0
	knob._begin_track(_hand(cart, pivot, 0.0))
	for step in range(1, 19):
		knob._track_world_point(_hand(cart, pivot, float(step) * 10.0))
		worst = minf(worst, _lens(cart, pivot).dot(_arc(float(step) * 10.0)))
		tipped = maxf(tipped, absf(_lens(cart, pivot).y))
		if step == 9:
			_check(_lens(cart, pivot).x > 0.999, "a quarter of the way it looks out of the side: %s" % _lens(cart, pivot))
	_check(worst > 0.999, "the lens follows the hand round (worst alignment %.4f)" % worst)
	_check(tipped < 0.0001, "and stays level all the way: it swivels, it does not tip (%.5f)" % tipped)
	_check(is_equal_approx(knob.get_value(), 1.0) and _lens(cart, pivot).z < -0.999,
		"and ends looking out of the back: value %.2f, %s" % [knob.get_value(), _lens(cart, pivot)])
	for step in range(19, 24):
		knob._track_world_point(_hand(cart, pivot, float(step) * 10.0))
	_check(is_equal_approx(knob.get_value(), 1.0), "it stops there, however much further the hand goes")
	# Back through the front and on round the other side.
	for step in range(23, -19, -1):
		knob._track_world_point(_hand(cart, pivot, float(step) * 10.0))
		tipped = maxf(tipped, absf(_lens(cart, pivot).y))
		if step == -9:
			_check(_lens(cart, pivot).x < -0.999, "the other way round it passes the other side: %s" % _lens(cart, pivot))
	_check(is_equal_approx(knob.get_value(), 0.0) and _lens(cart, pivot).z < -0.999 and tipped < 0.0001,
		"to the back again, and stops there too: value %.2f" % knob.get_value())
	for step in range(-18, 1):
		knob._track_world_point(_hand(cart, pivot, float(step) * 10.0))
	_check(is_equal_approx(knob.get_value(), 0.5) and _lens(cart, pivot).z > 0.999, "and comes back to the front")

	# The desktop's way: press it with the reticle, then roll the wheel.
	knob.pointer_event(XRToolsPointerEvent.new(XRToolsPointerEvent.Type.PRESSED, self, knob,
		pivot.global_position, pivot.global_position))
	var notch := InputEventMouseButton.new()
	notch.button_index = MOUSE_BUTTON_WHEEL_UP
	notch.pressed = true
	for i in 10:
		knob._unhandled_input(notch)
	_check(is_equal_approx(knob.get_value(), 1.0) and _lens(cart, pivot).z < -0.999,
		"ten notches of the wheel turn it to the back")
	knob.pointer_event(XRToolsPointerEvent.new(XRToolsPointerEvent.Type.RELEASED, self, knob,
		pivot.global_position, pivot.global_position))

	# --- it is saved, where it was left ------------------------------------------
	var persistence := ScenePersistence.new()
	var records: Array = persistence._serialize_articulated_controls(cart)
	var saved := false
	for rec: Dictionary in records:
		if str(rec.get("path", "")) == KNOB_PATH and str(rec.get("kind", "")) == "knob":
			saved = is_equal_approx(float(rec.get("value", 0.0)), 1.0)
	_check(saved, "a save writes where the ball was left: %s" % str(records))
	knob.set_value_no_signal(0.5)
	persistence._restore_articulated_controls(cart, records)
	_check(is_equal_approx(knob.get_value(), 1.0) and _lens(cart, pivot).z < -0.999, "and a restore turns it back there")
	knob.set_value_no_signal(0.5)

	if DisplayServer.get_name() != "headless":
		await _loose_shots(cart, knob, [plain, red, forced])

	# --- in a Game Boy Color -----------------------------------------------------
	for other: Node3D in [plain, red, forced]:
		other.visible = false
	var sys := SYSTEM_SCENE.instantiate() as RetroSystem
	sys.systemid = "gbc"
	sys.position = Vector3(0, 1, 0.5)
	sys.ignore_gravity = true
	add_child(sys)
	sys.add_to_group("spawned")
	await _wait(40)
	sys.restore_cartridge(cart)
	await _wait(40)
	var sys_model := sys.get("_model") as RetroSystemModelHandheld
	var to_sys := sys.global_transform.affine_inverse()
	var rel := to_sys * cart.global_transform
	var top_edge := -sys_model.body_size.z * 0.5
	var grip := rel * Vector3(0, size.y * 0.5, 0)
	_check((rel.basis * Vector3.UP).z < -0.99 and absf((top_edge - grip.z) - sys_model._cart_protrude()) < 0.0001,
		"seated, the cartridge stands %.1f mm out of the top edge, as a game does" % ((top_edge - grip.z) * 1000.0))
	var head_in_sys: AABB = rel * head_box
	_check(head_in_sys.end.z < top_edge - 0.01, "and the head is clear of the console, %.1f mm past its top edge"
		% ((top_edge - head_in_sys.end.z) * 1000.0))
	var stub := (cart.get_node("CollisionShape3D") as CollisionShape3D).shape as BoxShape3D
	_check(stub.size.y < size.y * 0.5 and _box_of(head).is_equal_approx(head_box),
		"the slot cuts the cartridge's box to its stub (%.1f mm) and leaves the head's alone" % (stub.size.y * 1000.0))
	var out_front := (to_sys.basis * _world_lens(pivot)).normalized()
	_check(out_front.y < -0.999, "at rest the lens looks out of the BACK of the console: %s" % out_front)
	knob.set_value(0.75)
	var out_side := (to_sys.basis * _world_lens(pivot)).normalized()
	_check(absf(out_side.x) > 0.999, "a quarter turn, along the console's top edge: %s" % out_side)
	knob.set_value(1.0)
	var out_back := (to_sys.basis * _world_lens(pivot)).normalized()
	_check(out_back.y > 0.999, "and half a turn, at whoever is looking at the screen: %s" % out_back)

	if DisplayServer.get_name() != "headless":
		await _seated_shots(sys, knob)

	(sys.get("_cartridge_slot") as XRToolsSnapZone).drop_object()
	await _wait(5)
	for n: Node in [cart, plain, red, forced, sys]:
		n.queue_free()
	await _wait(3)
	_clear_fixtures()
	print("[gbcam] %s" % ("ALL CHECKS PASSED" if not _fail else "FAILED"))
	get_tree().quit(1 if _fail else 0)


func _albedo(model: Node, path: String) -> Color:
	return ((model.get_node(path) as MeshInstance3D).get_active_material(0) as BaseMaterial3D).albedo_color


## A box shape's bounds in its body's frame.
func _box_of(col: CollisionShape3D) -> AABB:
	var box := (col.shape as BoxShape3D).size
	return AABB(col.position - box * 0.5, box)


## Where the lens points, in the cartridge's frame.
func _lens(cart: Node3D, pivot: Node3D) -> Vector3:
	return (cart.global_transform.basis.inverse() * _world_lens(pivot)).normalized()


func _world_lens(pivot: Node3D) -> Vector3:
	return ((pivot.get_node("LensGlass") as Node3D).global_position - pivot.global_position).normalized()


## The direction `deg` round the upright axle from the label side, in the
## cartridge's frame: +Z at 0, +X at 90, -Z at 180 and at -180, -X at -90.
func _arc(deg: float) -> Vector3:
	var a := deg_to_rad(clampf(deg, -180.0, 180.0))
	return Vector3(sin(a), 0.0, cos(a))


## A hand `deg` round that axle (unclamped: a hand can go where the ball cannot),
## and a little above the lens, which is where one holding a ball would be.
func _hand(cart: Node3D, pivot: Node3D, deg: float) -> Vector3:
	var a := deg_to_rad(deg)
	return pivot.global_position + cart.global_transform.basis \
		* (Vector3(sin(a), 0.0, cos(a)) * REACH + Vector3(0.0, 0.008, 0.0))


# --- windowed: pictures --------------------------------------------------------

func _camera() -> void:
	if _cam != null:
		return
	_sv = SubViewport.new()
	_sv.size = SHOT
	_sv.own_world_3d = false
	_sv.msaa_3d = Viewport.MSAA_4X
	_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_sv)
	_cam = Camera3D.new()
	_cam.near = 0.005
	_cam.far = 5.0
	_cam.fov = 28.0
	_sv.add_child(_cam)
	for o in LoadingOverlay.owners():
		LoadingOverlay.end(o)


func _loose_shots(cart: Node3D, knob: VRKnob, others: Array) -> void:
	_camera()
	var c := cart.global_position + Vector3(0, 0.022, 0)
	# The row: a game, the camera, a red one, and the body forced onto a game.
	var row := cart.global_position + Vector3(0.045, 0.022, 0)
	await _snap(row + Vector3(0.0, 0.05, 0.72), row, "row_front")
	for other: Node3D in others:
		other.visible = false
	await _snap(c + Vector3(0.10, 0.06, 0.33), c, "front")
	await _snap(c + Vector3(-0.12, 0.05, -0.31), c, "back")
	# From above one shoulder, where the sideways swing shows.
	var over := c + Vector3(0.15, 0.24, 0.20)
	await _snap(over, c, "lens_front")
	knob.set_value_no_signal(0.75)
	await _snap(over, c, "lens_side")
	knob.set_value_no_signal(1.0)
	await _snap(over, c, "lens_back")
	await _snap(c + Vector3(-0.12, 0.05, -0.31), c, "back_lens_back")
	knob.set_value_no_signal(0.5)
	if OS.get_cmdline_user_args().has("--film"):
		await _film(cart, knob, over, c)
	for other: Node3D in others:
		other.visible = true


## The swivel, as frames for an mp4 (`-- --film`): an orange bead where a latched
## hand is, carried round one side to the back, home, and round the other, and
## the ball driven by nothing but that point -- the same call the trigger makes
## every frame it is held.
func _film(cart: Node3D, knob: VRKnob, eye: Vector3, target: Vector3) -> void:
	var dir := ProjectSettings.globalize_path(OUT_DIR.path_join("film"))
	DirAccess.make_dir_recursive_absolute(dir)
	var pivot := knob.target
	var bead := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.004
	sphere.height = 0.008
	bead.mesh = sphere
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color(1.0, 0.55, 0.1)
	glow.emission_enabled = true
	glow.emission = Color(1.0, 0.55, 0.1)
	bead.material_override = glow
	add_child(bead)
	_cam.look_at_from_position(eye, target, Vector3.UP)
	_cam.current = true
	var path: Array[float] = []
	for leg: Array in [[0, 180], [180, 0], [0, -180], [-180, 0]]:
		var from: int = leg[0]
		var to: int = leg[1]
		for deg in range(from, to, 4 if to > from else -4):
			path.append(float(deg))
		for i in 10:
			path.append(float(to))
	knob._begin_track(_hand(cart, pivot, 0.0))
	var frame := 0
	for deg: float in path:
		bead.global_position = _hand(cart, pivot, deg)
		knob._track_world_point(bead.global_position)
		await _wait(2)
		await RenderingServer.frame_post_draw
		var img := _sv.get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		img.resize(800, 600, Image.INTERPOLATE_LANCZOS)
		img.save_png(dir.path_join("%04d.png" % frame))
		frame += 1
	bead.queue_free()
	knob.set_value_no_signal(0.5)
	_check(frame == path.size(), "filmed the swivel: %d frames in %s" % [frame, dir])


func _seated_shots(sys: Node3D, knob: VRKnob) -> void:
	_camera()
	# The console lies screen-up with its top edge toward -Z; the pictures are of
	# it as it is held, from over the bottom edge and from behind the top one.
	var c := sys.global_position + Vector3(0, 0, -0.03)
	await _snap(c + Vector3(-0.10, 0.34, 0.30), c, "seated_lens_at_player")
	knob.set_value_no_signal(0.75)
	await _snap(c + Vector3(-0.10, 0.34, 0.30), c, "seated_lens_sideways")
	knob.set_value_no_signal(0.5)
	await _snap(c + Vector3(0.12, -0.20, -0.38), c, "seated_from_behind_lens_out")
	await _snap(c + Vector3(0.34, 0.06, -0.06), c, "seated_side")


func _snap(eye: Vector3, target: Vector3, file: String) -> void:
	_cam.look_at_from_position(eye, target, Vector3.UP)
	_cam.current = true
	await _wait(8)
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	# FORMAT_RGB8 first: the frame carries an alpha channel nothing fills, and a
	# straight save writes a picture every viewer paints as a blank rectangle.
	var img := _sv.get_texture().get_image()
	img.convert(Image.FORMAT_RGB8)
	var path := OUT_DIR.path_join("%02d_%s.png" % [_shot, file])
	var err := img.save_png(path)
	_shot += 1
	_check(err == OK, "wrote %s%s" % [path, "" if err == OK else " (%s)" % error_string(err)])


func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.30, 0.31, 0.34)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.72, 0.74, 0.80)
	e.ambient_light_energy = 0.85
	env.environment = e
	add_child(env)
	for spec in [[Vector3(-46, -30, 0), 1.9], [Vector3(-12, 150, 0), 0.7]]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = spec[0]
		light.light_energy = spec[1]
		add_child(light)
