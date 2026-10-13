## Game Boy Camera self-tests — the header lookup that picks its body, the
## cartridge that wears it (a Game Boy cartridge with a head standing outside the
## slot), the ball a hand turns half a turn, and the seat it shares with a game.
##
##     "$godot" --headless --path RetroXR res://Tests/gb_camera_tests.tscn
##     "$godot" --headless --path RetroXR res://Tests/gb_camera_tests.tscn -- --only=ball
##
## Exits 0 when everything passes, 1 otherwise.
##
## Writes one label fixture into the player's real gb media/label folder
## (MediaDimensions derives the path from the ROM's name) and ROM fixtures under
## user://, and removes both at each end.
extends Node

const CART_SCENE := preload("res://Scenes/Objects/media/cartridge.tscn")
const SYSTEM_SCENE := preload("res://Scenes/Objects/system.tscn")
const FIXTURE := "__gbcamera_selftest"
const HINGE_PATH := "CartModel/Overhang/LensPivot/LensHinge"
## How far off the axle the stand-in hand holds the ball.
const REACH := 0.03

var _pass := 0
var _fail := 0
var _only := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			_only = arg.substr(7)
	get_tree().create_timer(120.0).timeout.connect(func() -> void:
		print("[gbcam] TIMEOUT")
		_clear_fixtures()
		get_tree().quit(1))
	_clear_fixtures()

	if _wants("lookup"):
		_test_lookup()
	if _wants("body"):
		_test_body()
	if _wants("cartridge"):
		await _test_cartridge()
	if _wants("ball"):
		await _test_ball()
	if _wants("saved"):
		await _test_saved()
	if _wants("seated"):
		await _test_seated()
	if _wants("menu"):
		_test_menu()

	_clear_fixtures()
	await _settle_warm()
	print("[gbcam] ---- %d passed, %d failed ----" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)


func _settle_warm() -> void:
	for i in range(1200):
		if ModelWarmer.is_warmed():
			return
		await get_tree().process_frame


func _wants(group: String) -> bool:
	return _only.is_empty() or _only == group


func _ok(cond: bool, test_name: String, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("[gbcam] PASS  %s" % test_name)
	else:
		_fail += 1
		print("[gbcam] FAIL  %s%s" % [test_name, "  — " + detail if not detail.is_empty() else ""])


# ── fixtures ──────────────────────────────────────────────────────────────────


## A 0x150-byte header: title, cartridge type, Nintendo's licensee.
func _header(title: String, cart_type: int) -> PackedByteArray:
	var h := PackedByteArray()
	h.resize(GbCartShell.HEADER_BYTES)
	for i in mini(title.length(), GbCartShell.TITLE_BYTES):
		h[GbCartShell.TITLE_AT + i] = title.unicode_at(i)
	h[GbcCartShell.CART_TYPE_AT] = cart_type
	h[GbCartShell.DESTINATION_AT] = 0x01
	h[GbCartShell.OLD_LICENSEE_AT] = GbCartShell.OLD_LICENSEE_USE_NEW
	h[GbCartShell.NEW_LICENSEE_AT] = 0x30
	h[GbCartShell.NEW_LICENSEE_AT + 1] = 0x31
	return h


## The header of Game Boy Camera (USA, Europe), as far as the lookup reads it.
func _camera() -> PackedByteArray:
	return _header("GAMEBOYCAMERA", GbCameraShell.CART_TYPE_CAMERA)


func _game() -> PackedByteArray:
	return _header("TETRIS", 0x00)


func _write_rom(file_name: String, header: PackedByteArray) -> String:
	var dir := ProjectSettings.globalize_path("user://" + FIXTURE)
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join(file_name)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(header)
	f.close()
	return path


func _label_dir() -> String:
	return RomLibrary.rom_dir_for_system(GbCartShell.SYSTEMID).path_join("media").path_join("label")


func _clear_fixtures() -> void:
	DirAccess.remove_absolute(_label_dir().path_join(FIXTURE + ".png"))
	var dir := ProjectSettings.globalize_path("user://" + FIXTURE)
	if DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(f))
		DirAccess.remove_absolute(dir)


func _spawn(rom: String, shell: StringName = &"", color := "", body := "", systemid := "gb") -> RetroCartridge:
	var cart := CART_SCENE.instantiate() as RetroCartridge
	cart.systemid = systemid
	cart.rom_path = rom
	cart.shell_preset = shell
	cart.shell_color = color
	cart.body_region = body
	cart.game_label = "Selftest"
	cart.freeze = true
	add_child(cart)
	for i in 4:
		await get_tree().physics_frame
	return cart


func _model_path(cart: RetroCartridge) -> String:
	var model := cart.get_node_or_null("CartModel")
	return model.scene_file_path if model != null else ""


func _albedo(cart: Node, part: String) -> Color:
	var mi := cart.get_node("CartModel").find_child(part, true, false) as MeshInstance3D
	return (mi.get_active_material(0) as BaseMaterial3D).albedo_color


func _gb_preset(id: StringName) -> CartridgeShellPreset:
	return CartridgeColor.get_palette(GbCartShell.SYSTEMID).find(id)


## A box shape's bounds in its body's frame.
func _box_of(col: CollisionShape3D) -> AABB:
	var size := (col.shape as BoxShape3D).size
	return AABB(col.position - size * 0.5, size)


## Where the lens points, in the cartridge's frame.
func _lens(cart: Node3D) -> Vector3:
	var pivot := cart.get_node("CartModel/Overhang/LensPivot") as Node3D
	var out := (pivot.get_node("LensGlass") as Node3D).global_position - pivot.global_position
	return (cart.global_transform.basis.inverse() * out).normalized()


## The direction `deg` round the arc from the label side over the top to the
## back, in the cartridge's frame: +Z at 0, +Y at 90, -Z at 180.
func _arc(deg: float) -> Vector3:
	var a := deg_to_rad(clampf(deg, 0.0, 180.0))
	return Vector3(0.0, sin(a), cos(a))


## A hand `deg` round that arc (unclamped: a hand can go where the ball cannot).
func _hand(cart: Node3D, deg: float) -> Vector3:
	var pivot := cart.get_node("CartModel/Overhang/LensPivot") as Node3D
	var a := deg_to_rad(deg)
	return pivot.global_position + cart.global_transform.basis * (Vector3(0.0, sin(a), cos(a)) * REACH)


# ── groups ────────────────────────────────────────────────────────────────────


func _test_lookup() -> void:
	_ok(GbCameraShell.is_camera(_camera()), "lookup/cartridge type 0xFC is the camera")
	_ok(not GbCameraShell.is_camera(_game()) and not GbCameraShell.is_camera(_header("ZELDA", 0x1B)),
		"lookup/and no game's type is")
	_ok(not GbCameraShell.is_camera(PackedByteArray()), "lookup/nor a file too short to have a header")
	_ok(GbcCartShell.body_model_for("", &"", _camera()) == GbCameraShell.BODY, "lookup/the camera's header picks its body")
	_ok(GbcCartShell.body_model_for("", &"", _game()) == GbCartShell.BODY, "lookup/a game's still picks the Game Boy cartridge")
	_ok(GbcCartShell.body_model_for(GbcCartShell.BODY_GB, &"", _camera()) == GbCartShell.BODY
		and GbcCartShell.is_body(GbcCartShell.body_model_for(GbcCartShell.BODY_GBC, &"", _camera())),
		"lookup/either cartridge can be forced onto the camera's ROM")
	_ok(GbcCartShell.body_model_for(GbCameraShell.BODY_CAMERA, &"", _game()) == GbCameraShell.BODY,
		"lookup/and the camera forced onto a game")
	# On a game a forced shell brings the body its palette belongs to. The camera
	# is not a shell: it keeps its body and is repainted.
	_ok(GbcCartShell.body_model_for("", &"red", _camera()) == GbCameraShell.BODY
		and GbcCartShell.body_model_for("", &"crystal", _camera()) == GbCameraShell.BODY,
		"lookup/a forced shell does not swap the camera for a cartridge")
	var rom := _write_rom("lookup.gb", _camera())
	_ok(RetroCartridge.body_model_for("gb", rom, "", &"") == GbCameraShell.BODY
		and RetroCartridge.body_model_for("gbc", rom, "", &"") == GbCameraShell.BODY,
		"lookup/from the gb tile and the gbc one")
	_ok(RetroCartridge.body_model_for("gba", rom, "", &"") != GbCameraShell.BODY, "lookup/and from no other system's")
	_ok(MediaDimensions.cart_size("gb", rom, GbCameraShell.BODY) == MediaDimensions.CART_SIZES["gb"],
		"lookup/its size is the Game Boy cartridge's: the head is not in it")


func _test_body() -> void:
	_ok(ResourceLoader.exists(GbCameraShell.BODY), "body/the scene ships")
	var body := (load(GbCameraShell.BODY) as PackedScene).instantiate() as Node3D
	add_child(body)
	var overhang := body.get_node_or_null(RetroCartridge.OVERHANG_NODE) as Node3D
	_ok(overhang != null, "body/it has an Overhang")
	var label := CartridgeLabel.find_label(body)
	_ok(label != null and not overhang.is_ancestor_of(label), "body/and a sticker on the cartridge, not the head")
	var housing := 0
	for n in overhang.get_children():
		if n is MeshInstance3D:
			housing += 1
	_ok(housing >= 1, "body/the head has fixed housing for its box to fit", "%d meshes directly under Overhang" % housing)
	var painted := PackedStringArray()
	for s: Dictionary in CartridgeColor.shell_surfaces(body):
		painted.append(str((s["mesh"] as Node).name))
	_ok(painted.has("Tongue") and painted.has("HeadBase") and painted.has("CheekLeft") and painted.has("CheekRight"),
		"body/cartridge and head are shell plastic", str(painted))
	_ok(not painted.has("Ball") and not painted.has("LensBezel") and not painted.has("LensGlass") and not painted.has("Label"),
		"body/the ball, the lens and the sticker are not", str(painted))
	var hinge := body.get_node_or_null("Overhang/LensPivot/LensHinge") as VRHinge
	_ok(hinge != null and hinge.target == body.get_node("Overhang/LensPivot"), "body/the ball's hinge turns its pivot")
	_ok(hinge != null and is_equal_approx(hinge.min_deg, -180.0) and is_equal_approx(hinge.max_deg, 0.0),
		"body/through half a turn")
	_ok(hinge != null and not hinge.grip_engages, "body/on the trigger: the grip is how the cartridge is picked up")
	body.free()


func _test_cartridge() -> void:
	var img := Image.create(420, 370, false, Image.FORMAT_RGB8)
	img.fill(Color(0.9, 0.1, 0.5))
	DirAccess.make_dir_recursive_absolute(_label_dir())
	img.save_png(_label_dir().path_join(FIXTURE + ".png"))

	var size: Vector3 = MediaDimensions.CART_SIZES["gb"]
	var camera := await _spawn(_write_rom(FIXTURE + ".gb", _camera()))
	var bare := await _spawn(_write_rom("bare.gb", _camera()))
	var game := await _spawn(_write_rom("game.gb", _game()))
	var from_gbc := await _spawn(_write_rom("camera.gbc", _camera()), &"", "", "", "gbc")
	var red := await _spawn(_write_rom("red.gb", _camera()), &"red")
	var mixed := await _spawn(_write_rom("mixed.gb", _camera()), &"", "#3fa34d")
	var forced := await _spawn(_write_rom("forced.gb", _game()), &"", "", GbCameraShell.BODY_CAMERA)
	_ok(_model_path(camera) == GbCameraShell.BODY and _model_path(from_gbc) == GbCameraShell.BODY,
		"cartridge/the camera's ROM spawns the camera, from either tile")
	_ok(_model_path(game) == GbCartShell.BODY, "cartridge/a game spawns a Game Boy cartridge")
	_ok(_model_path(forced) == GbCameraShell.BODY, "cartridge/the hold menu's Game Boy Camera body makes any ROM one")

	var model := camera.get_node("CartModel") as Node3D
	_ok(model.scale.is_equal_approx(Vector3.ONE) and model.position.length() < 0.00001,
		"cartridge/the body is not stretched or moved by its head", "scale %s at %s" % [model.scale, model.position])
	var fitted: AABB = camera._cart_model_aabb(model)
	_ok(fitted.size.is_equal_approx(size) and fitted.get_center().length() < 0.00001,
		"cartridge/what is fitted to the slot is a Game Boy cartridge", str(fitted))
	var own := _box_of(camera.get_node("CollisionShape3D") as CollisionShape3D)
	_ok(own.size.is_equal_approx(size), "cartridge/and its own box is that cartridge", str(own.size))

	var head := camera.get_node_or_null("OverhangShape") as CollisionShape3D
	var aim := camera.get_node_or_null("PointerArea/OverhangShape") as CollisionShape3D
	_ok(head != null and aim != null, "cartridge/the head has a box to be taken by and one to be aimed at")
	_ok(game.get_node_or_null("OverhangShape") == null and game.get_node_or_null("PointerArea/OverhangShape") == null,
		"cartridge/a game's cartridge has neither")
	if head != null and aim != null:
		var head_box := _box_of(head)
		_ok(head_box.position.y > size.y * 0.5 - 0.001 and head_box.size.y > 0.03,
			"cartridge/the head's box stands past the grip end", str(head_box))
		_ok(_box_of(aim).is_equal_approx(head_box), "cartridge/and the aim box is the same box")
		var ball := model.get_node("Overhang/LensPivot/Ball") as MeshInstance3D
		var ball_box: AABB = (camera.global_transform.affine_inverse() * ball.global_transform) * ball.get_aabb()
		_ok(ball_box.end.z > head_box.end.z + 0.002 and ball_box.position.z < head_box.position.z - 0.002
			and ball_box.end.y > head_box.end.y + 0.001,
			"cartridge/the ball stands out of it front, back and top, so a ray reaches the ball first")

	_ok(_albedo(camera, "Tongue") == _gb_preset(&"blue").color and _albedo(camera, "HeadBase") == _gb_preset(&"blue").color,
		"cartridge/it is blue, cartridge and head")
	_ok(_albedo(red, "Tongue") == _gb_preset(&"red").color and _albedo(red, "CheekLeft") == _gb_preset(&"red").color,
		"cartridge/a forced Game Boy shell repaints both")
	_ok(_albedo(mixed, "CheekRight") == Color("#3fa34d"), "cartridge/and so does a mixed colour")
	_ok(_albedo(red, "Ball").r < 0.1 and _albedo(mixed, "Ball").g < 0.1, "cartridge/the ball stays black")

	var label := CartridgeLabel.find_label(model)
	var art := (label.get_active_material(0) as BaseMaterial3D).albedo_texture if label != null else null
	_ok(label != null and label.visible and art != null and art.get_width() == 420,
		"cartridge/the scraped label is painted on the sticker")
	_ok(not (camera.get_node("GameLabel") as Label3D).visible, "cartridge/with no title over it")
	var title := bare.get_node("GameLabel") as Label3D
	_ok(title.visible and title.position.z > size.z * 0.5 and title.position.y < size.y * 0.5,
		"cartridge/with no art the title is on the sticker", str(title.position))
	for cart in [camera, bare, game, from_gbc, red, mixed, forced]:
		cart.queue_free()
	await get_tree().process_frame


func _test_ball() -> void:
	var cart := await _spawn(_write_rom("ball.gb", _camera()))
	# Not lying square to the world: a ball that only turns right in the
	# cartridge's rest pose is measuring in the wrong frame.
	cart.global_transform = Transform3D(Basis.from_euler(Vector3(0.4, -1.1, 0.25)), Vector3(0.3, 1.2, -0.2))
	await get_tree().process_frame
	var hinge := cart.get_node(HINGE_PATH) as VRHinge
	_ok(_lens(cart).z > 0.999, "ball/at rest the lens looks out of the label side", str(_lens(cart)))
	# A latched hand taking the ball by the lens and carrying it over the top.
	var worst := 1.0
	var at_top := Vector3.ZERO
	hinge._begin_track(_hand(cart, 0.0))
	for step in range(1, 19):
		hinge._track_world_point(_hand(cart, float(step) * 10.0))
		worst = minf(worst, _lens(cart).dot(_arc(float(step) * 10.0)))
		if step == 9:
			at_top = _lens(cart)
	_ok(at_top.y > 0.999, "ball/a quarter turn points it straight up, not down through the housing", str(at_top))
	_ok(worst > 0.999, "ball/the lens stays under the hand the whole way over", "worst alignment %.4f" % worst)
	_ok(is_equal_approx(hinge.get_rotation_deg(), -180.0) and _lens(cart).z < -0.999,
		"ball/half a turn ends looking out of the back", "%.2f deg, %s" % [hinge.get_rotation_deg(), _lens(cart)])
	for step in range(19, 25):
		hinge._track_world_point(_hand(cart, float(step) * 10.0))
	_ok(is_equal_approx(hinge.get_rotation_deg(), -180.0), "ball/and no further, wherever the hand goes",
		"%.2f deg" % hinge.get_rotation_deg())
	for step in range(24, -6, -1):
		hinge._track_world_point(_hand(cart, float(step) * 10.0))
	_ok(is_equal_approx(hinge.get_rotation_deg(), 0.0) and _lens(cart).z > 0.999,
		"ball/it comes back the same way and stops at the front", "%.2f deg" % hinge.get_rotation_deg())

	# A hand that takes hold anywhere on the ball turns it by how far the hand
	# moves; it does not snap the lens to the hand.
	hinge._begin_track(_hand(cart, 120.0))
	_ok(is_equal_approx(hinge.get_rotation_deg(), 0.0), "ball/taking hold does not move it")
	hinge._track_world_point(_hand(cart, 150.0))
	_ok(absf(hinge.get_rotation_deg() + 30.0) < 0.01, "ball/thirty degrees of hand is thirty degrees of ball",
		"%.2f deg" % hinge.get_rotation_deg())
	hinge.set_rotation_deg_no_signal(0.0)

	# The desktop's way: press the ball with the reticle, then roll the wheel.
	var pivot := hinge.target
	hinge.pointer_event(XRToolsPointerEvent.new(XRToolsPointerEvent.Type.PRESSED, cart, hinge,
		pivot.global_position, pivot.global_position))
	var notch := InputEventMouseButton.new()
	notch.button_index = MOUSE_BUTTON_WHEEL_UP
	notch.pressed = true
	hinge._unhandled_input(notch)
	_ok(_lens(cart).y > 0.1 and _lens(cart).z > 0.0, "ball/a notch of the wheel starts it up over the top", str(_lens(cart)))
	for i in 17:
		hinge._unhandled_input(notch)
	_ok(is_equal_approx(hinge.get_rotation_deg(), -180.0), "ball/and eighteen take it all the way")
	hinge.pointer_event(XRToolsPointerEvent.new(XRToolsPointerEvent.Type.RELEASED, cart, hinge,
		pivot.global_position, pivot.global_position))
	cart.queue_free()
	await get_tree().process_frame


func _test_saved() -> void:
	var cart := await _spawn(_write_rom("saved.gb", _camera()))
	var hinge := cart.get_node(HINGE_PATH) as VRHinge
	hinge.set_rotation_deg_no_signal(-135.0)
	var persistence := ScenePersistence.new()
	var records: Array = persistence._serialize_articulated_controls(cart)
	var value := NAN
	for rec: Dictionary in records:
		if str(rec.get("path", "")) == HINGE_PATH and str(rec.get("kind", "")) == "hinge":
			value = float(rec.get("value", NAN))
	_ok(is_equal_approx(value, -135.0), "saved/a save writes where the ball was left", str(records))
	# The restore is of another cartridge: a new one, built from the same ROM.
	var again := await _spawn(_write_rom("saved.gb", _camera()))
	persistence._restore_articulated_controls(again, records)
	_ok(is_equal_approx((again.get_node(HINGE_PATH) as VRHinge).get_rotation_deg(), -135.0),
		"saved/and a restored cartridge's ball is turned back there")
	_ok(absf(_lens(again).dot(_arc(135.0)) - 1.0) < 0.0001, "saved/lens and all", str(_lens(again)))
	# What netplay binds, by the same walk.
	_ok(cart.find_children("*", "VRHinge", true, false).has(hinge), "saved/the hinge is found from the cartridge")
	cart.queue_free()
	again.queue_free()
	await get_tree().process_frame


## The camera seats wherever a Game Boy cartridge does, and exactly as one does:
## the pose is compared with a game's in the same slot, in a Game Boy Color (its
## own system's slot) and a Game Boy Advance (a foreign one, seated by its
## connector).
func _test_seated() -> void:
	var size: Vector3 = MediaDimensions.CART_SIZES["gb"]
	for systemid: String in ["gbc", "gba"]:
		var sys := SYSTEM_SCENE.instantiate() as RetroSystem
		sys.systemid = systemid
		sys.ignore_gravity = true
		sys.freeze = true
		add_child(sys)
		for i in 30:
			await get_tree().process_frame
		var slot := sys.get("_cartridge_slot") as XRToolsSnapZone
		var to_sys := sys.global_transform.affine_inverse()

		var game := await _spawn(_write_rom("seat_game.gb", _game()))
		sys.restore_cartridge(game)
		for i in 30:
			await get_tree().process_frame
		var game_pose := to_sys * game.global_transform
		slot.drop_object()
		for i in 5:
			await get_tree().process_frame
		game.queue_free()

		var camera := await _spawn(_write_rom("seat_camera.gb", _camera()))
		var head := camera.get_node("OverhangShape") as CollisionShape3D
		var head_box := _box_of(head)
		sys.restore_cartridge(camera)
		for i in 30:
			await get_tree().process_frame
		var pose := to_sys * camera.global_transform
		_ok(pose.origin.distance_to(game_pose.origin) < 0.00005 and pose.basis.is_equal_approx(game_pose.basis),
			"seated/%s: the camera sits exactly where a game does" % systemid,
			"%.3f mm apart" % (pose.origin.distance_to(game_pose.origin) * 1000.0))
		var model := sys.get("_model") as RetroSystemModelHandheld
		var edge := -model.body_size.z * 0.5
		var head_in_sys: AABB = pose * head_box
		_ok(head_in_sys.end.z < edge - 0.005, "seated/%s: its head is clear of the top edge" % systemid,
			"head to z %.1f mm, edge %.1f mm" % [head_in_sys.end.z * 1000.0, edge * 1000.0])
		var stub := _box_of(camera.get_node("CollisionShape3D") as CollisionShape3D)
		_ok(stub.size.y < size.y and _box_of(head).is_equal_approx(head_box),
			"seated/%s: the slot cuts the cartridge's box to its stub and leaves the head's" % systemid,
			"stub %.1f mm" % (stub.size.y * 1000.0))
		var hinge := camera.get_node(HINGE_PATH) as VRHinge
		var pivot := hinge.target
		var out := (to_sys.basis * ((pivot.get_node("LensGlass") as Node3D).global_position - pivot.global_position)).normalized()
		_ok(out.y < -0.999, "seated/%s: at rest the lens looks out of the back of the console" % systemid, str(out))
		hinge.set_rotation_deg_remote(-180.0)
		out = (to_sys.basis * ((pivot.get_node("LensGlass") as Node3D).global_position - pivot.global_position)).normalized()
		_ok(out.y > 0.999, "seated/%s: turned, it looks at whoever is looking at the screen" % systemid, str(out))
		slot.drop_object()
		for i in 5:
			await get_tree().process_frame
		_ok(_box_of(camera.get_node("CollisionShape3D") as CollisionShape3D).size.is_equal_approx(size)
			and _box_of(head).is_equal_approx(head_box),
			"seated/%s: taken out, the cartridge's box is whole again and the head's unchanged" % systemid)
		camera.queue_free()
		sys.queue_free()
		for i in 5:
			await get_tree().process_frame


## The hold sub-menu of a gb or gbc row offers the camera as a body.
func _test_menu() -> void:
	var holder := Control.new()
	add_child(holder)
	var view := SpawnMenuSpawnView.new()
	holder.add_child(view)
	var sent := {"options": null}
	var spawn := func(options: Dictionary) -> void: sent["options"] = options
	var press_text := func(text: String) -> bool:
		for b: Node in view._spawn_options_panel.find_children("*", "Button", true, false):
			if (b as Button).text.strip_edges() == text:
				(b as Button).pressed.emit()
				return true
		return false
	for systemid in ["gb", "gbc"]:
		view._show_cart_spawn_options(systemid, "Selftest", spawn)
		var texts := PackedStringArray()
		for b: Node in view._spawn_options_panel.find_children("*", "Button", true, false):
			texts.append((b as Button).text.strip_edges())
		_ok(texts.has("Game Boy Camera"), "menu/%s: the camera is one of the bodies" % systemid, str(texts))
		view._close_spawn_options_panel()
	view._show_cart_spawn_options("gb", "Selftest", spawn)
	press_text.call("Game Boy Camera")
	press_text.call("+  SPAWN")
	_ok(sent["options"] == {"body_region": GbCameraShell.BODY_CAMERA}, "menu/choosing it forces that body",
		str(sent["options"]))
	view._show_cart_spawn_options("gba", "Selftest", spawn)
	var gba_texts := PackedStringArray()
	for b: Node in view._spawn_options_panel.find_children("*", "Button", true, false):
		gba_texts.append((b as Button).text.strip_edges())
	_ok(not gba_texts.has("Game Boy Camera"), "menu/a Game Boy Advance row does not offer it")
	view._close_spawn_options_panel()
	holder.queue_free()
