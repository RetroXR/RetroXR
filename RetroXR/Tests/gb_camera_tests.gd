## Game Boy Camera self-tests — the header lookup that picks its body, the
## cartridge that wears it (a Game Boy cartridge with a head standing outside the
## slot), the ball a hand swivels half a turn, and the seat it shares with a game.
## And the camera it is: where the lens looks, what is handed to a core and when,
## the core its ROM names, and why it stays out of netplay.
##
## No core runs here. What a core is handed is stood in for by FakeLibretro, and
## a headless run draws nothing, so the picture is a still a case supplies. That
## the real core shows the room is Tools/cores/gb_camera_feed_probe.
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
const KNOB_PATH := "CartModel/Overhang/LensKnob"
const EYE_PATH := KNOB_PATH + "/KnobPivot/LensEye"
## How far off the axle the stand-in hand holds the ball.
const REACH := 0.03
## What mGBA asks for.
const CAMERA_SIZE := Vector2i(128, 112)

var _pass := 0
var _fail := 0
var _only := ""


## A core that has asked for a camera, as far as GbCameraEye can tell.
class FakeLibretro:
	extends RefCounted
	var active := true
	var size := CAMERA_SIZE
	var pushes: Array = []

	func IsCameraActive() -> bool:
		return active

	func GetCameraFrameSize() -> Vector2i:
		return size

	func PushCameraFrame(rgba: PackedByteArray, width: int, height: int) -> bool:
		pushes.append({"rgba": rgba, "width": width, "height": height})
		return true


## A library built before the camera existed: none of the three calls.
class OldLibretro:
	extends RefCounted


class FakeMachine:
	extends RefCounted
	var lib: RefCounted = FakeLibretro.new()
	var is_powered_on := true

	func get_libretro_node() -> RefCounted:
		return lib


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
	if _wants("colors"):
		await _test_colors()
	if _wants("eye"):
		await _test_eye()
	if _wants("feed"):
		await _test_feed()
	if _wants("binding"):
		_test_binding()
	if _wants("core"):
		await _test_core()

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
	var m := mi.get_active_material(0)
	if m is ShaderMaterial:                 # a metal flake finish: the gold edition
		return (m as ShaderMaterial).get_shader_parameter("albedo")
	return (m as BaseMaterial3D).albedo_color


func _is_flake(cart: Node, part: String) -> bool:
	var mi := cart.get_node("CartModel").find_child(part, true, false) as MeshInstance3D
	var m := mi.get_active_material(0) as ShaderMaterial
	return m != null and m.shader == CartridgeColor.FLAKE_SHADER


func _gb_preset(id: StringName) -> CartridgeShellPreset:
	return CartridgeColor.get_palette(GbCartShell.SYSTEMID).find(id)


## A box shape's bounds in its body's frame.
func _box_of(col: CollisionShape3D) -> AABB:
	var size := (col.shape as BoxShape3D).size
	return AABB(col.position - size * 0.5, size)


func _pivot(cart: Node3D) -> Node3D:
	return cart.get_node(KNOB_PATH + "/KnobPivot") as Node3D


## Where the lens points, in the cartridge's frame.
func _lens(cart: Node3D) -> Vector3:
	var pivot := _pivot(cart)
	var out := (pivot.get_node("LensGlass") as Node3D).global_position - pivot.global_position
	return (cart.global_transform.basis.inverse() * out).normalized()


## The direction `deg` round the upright axle from the label side, in the
## cartridge's frame: +Z at 0, +X at 90, -Z at 180 and at -180, -X at -90.
func _arc(deg: float) -> Vector3:
	var a := deg_to_rad(clampf(deg, -180.0, 180.0))
	return Vector3(sin(a), 0.0, cos(a))


## A hand `deg` round that axle (unclamped: a hand can go where the ball cannot),
## and a little above the lens, which is where one holding a ball would be.
func _hand(cart: Node3D, deg: float) -> Vector3:
	var a := deg_to_rad(deg)
	return _pivot(cart).global_position + cart.global_transform.basis \
		* (Vector3(sin(a), 0.0, cos(a)) * REACH + Vector3(0.0, 0.008, 0.0))


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
	var knob := body.get_node_or_null("Overhang/LensKnob") as VRKnob
	_ok(knob != null and knob.target == knob.get_node_or_null("KnobPivot"), "body/the ball's knob turns its pivot")
	# The housing is under the ball and nowhere beside it: the real one's ball
	# stands on top with nothing either side.
	var housing := 0
	var beside := PackedStringArray()
	for n in overhang.get_children():
		var mi := n as MeshInstance3D
		if mi == null:
			continue
		housing += 1
		if knob != null and (mi.transform * mi.get_aabb()).end.y > knob.position.y - 0.0065:
			beside.append(str(mi.name))
	_ok(housing >= 1, "body/the head has fixed housing for its box to fit", "%d meshes directly under Overhang" % housing)
	_ok(beside.is_empty(), "body/and none of it stands beside the ball", str(beside))
	var painted := PackedStringArray()
	for s: Dictionary in CartridgeColor.shell_surfaces(body):
		painted.append(str((s["mesh"] as Node).name))
	_ok(painted.has("Tongue") and painted.has("HeadBase"), "body/cartridge and head are shell plastic", str(painted))
	_ok(not painted.has("Ball") and not painted.has("LensBezel") and not painted.has("LensGlass") and not painted.has("Label"),
		"body/the ball, the lens and the sticker are not", str(painted))
	if knob != null:
		# The knob turns about its own Z, so its Z has to be the cartridge's length:
		# the axle stands upright. Written as its transpose it lies along the label.
		_ok((knob.transform.basis.z - Vector3.UP).length() < 0.0001, "body/the ball's axle stands upright",
			str(knob.transform.basis.z))
		_ok(is_equal_approx(knob.deg_at_zero, 0.0) and is_equal_approx(knob.deg_at_one, -180.0)
			and is_equal_approx(knob.get_value(), 0.0), "body/half a turn clockwise from above, and it starts at the front")
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
	_ok(game.get_node_or_null("OverhangShape") == null and game.get_node_or_null("PointerArea/OverhangShape") == null
		and game.get_node_or_null("OverhangMovingShape") == null, "cartridge/a game's cartridge has none of them")
	if head != null and aim != null:
		var head_box := _box_of(head)
		_ok(head_box.position.y > size.y * 0.5 - 0.001 and head_box.size.y > 0.015,
			"cartridge/the head's box stands past the grip end", str(head_box))
		_ok(_box_of(aim).is_equal_approx(head_box), "cartridge/and the aim box is the same box")
		var ball := _pivot(camera).get_node("Ball") as MeshInstance3D
		var ball_box: AABB = (camera.global_transform.affine_inverse() * ball.global_transform) * ball.get_aabb()
		_ok(ball_box.end.z > head_box.end.z + 0.002 and ball_box.position.z < head_box.position.z - 0.002
			and ball_box.end.y > head_box.end.y + 0.02,
			"cartridge/the ball stands on top of it and out of it front and back, so a ray reaches the ball first")
		# The cartridge rests on the ball, and is lifted by it.
		var rest := camera.get_node_or_null("OverhangMovingShape") as CollisionShape3D
		_ok(rest != null and _box_of(rest).grow(0.0001).encloses(ball_box),
			"cartridge/the ball has a box on the cartridge to rest on", str(_box_of(rest)) if rest != null else "none")
		_ok(camera.get_node_or_null("PointerArea/OverhangMovingShape") == null,
			"cartridge/and none to be aimed at, which would stand in front of its own grab")

	var blue := CartridgeColor.get_palette(GbCameraShell.PALETTE).find(GbCameraShell.DEFAULT_PRESET)
	_ok(_albedo(camera, "Tongue") == blue.color and _albedo(camera, "HeadBase") == blue.color,
		"cartridge/it is the camera's blue, cartridge and head")
	_ok(_albedo(red, "Tongue") == _gb_preset(&"red").color and _albedo(red, "HeadBase") == _gb_preset(&"red").color,
		"cartridge/a forced Game Boy shell repaints both")
	_ok(_albedo(mixed, "HeadBase") == Color("#3fa34d"), "cartridge/and so does a mixed colour")
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
	var knob := cart.get_node(KNOB_PATH) as VRKnob
	_ok(_lens(cart).z > 0.999, "ball/at rest the lens looks out of the label side", str(_lens(cart)))
	# A latched hand taking the ball by the lens and carrying it round to the back:
	# clockwise seen from above, the lens passing the cartridge's -X, as the real
	# one goes. It swivels about its upright axle: the lens stays level.
	var worst := 1.0
	var tipped := 0.0
	var at_side := Vector3.ZERO
	knob._begin_track(_hand(cart, 0.0))
	for step in range(1, 19):
		knob._track_world_point(_hand(cart, -float(step) * 10.0))
		worst = minf(worst, _lens(cart).dot(_arc(-float(step) * 10.0)))
		tipped = maxf(tipped, absf(_lens(cart).y))
		if step == 9:
			at_side = _lens(cart)
	_ok(at_side.x < -0.999, "ball/a quarter turn points it out of the -X side, not up over the top", str(at_side))
	_ok(tipped < 0.0001, "ball/the lens stays level the whole way: it swivels, it does not tip", "%.5f" % tipped)
	_ok(worst > 0.999, "ball/and stays under the hand the whole way round", "worst alignment %.4f" % worst)
	_ok(is_equal_approx(knob.get_value(), 1.0) and _lens(cart).z < -0.999,
		"ball/half a turn ends looking out of the back", "value %.3f, %s" % [knob.get_value(), _lens(cart)])
	for step in range(19, 25):
		knob._track_world_point(_hand(cart, -float(step) * 10.0))
	_ok(is_equal_approx(knob.get_value(), 1.0) and _lens(cart).z < -0.999, "ball/and no further, wherever the hand goes",
		"value %.3f" % knob.get_value())
	# Back the same way to the front, and it stops there: it does not go round the
	# other side.
	for step in range(24, -10, -1):
		knob._track_world_point(_hand(cart, -float(step) * 10.0))
		tipped = maxf(tipped, absf(_lens(cart).y))
		if step == 0:
			_ok(is_equal_approx(knob.get_value(), 0.0) and _lens(cart).z > 0.999, "ball/it comes back the same way to the front")
	_ok(is_equal_approx(knob.get_value(), 0.0) and _lens(cart).z > 0.999 and tipped < 0.0001,
		"ball/and no further round the +X side: it stops at the front", "value %.3f, %s" % [knob.get_value(), _lens(cart)])
	knob.set_value_no_signal(0.5)

	# A hand that takes hold anywhere round the ball turns it by how far the hand
	# moves; it does not snap the lens to the hand. Halfway, the lens looks out of
	# the -X side.
	knob._begin_track(_hand(cart, 60.0))
	_ok(is_equal_approx(knob.get_value(), 0.5), "ball/taking hold does not move it")
	knob._track_world_point(_hand(cart, 30.0))
	_ok(absf(_lens(cart).dot(_arc(-120.0)) - 1.0) < 0.0001, "ball/thirty degrees of hand is thirty degrees of ball", str(_lens(cart)))
	knob.set_value_no_signal(0.0)

	# The desktop's way: press the ball with the reticle, then roll the wheel.
	var pivot := _pivot(cart)
	knob.pointer_event(XRToolsPointerEvent.new(XRToolsPointerEvent.Type.PRESSED, cart, knob,
		pivot.global_position, pivot.global_position))
	var notch := InputEventMouseButton.new()
	notch.button_index = MOUSE_BUTTON_WHEEL_UP
	notch.pressed = true
	knob._unhandled_input(notch)
	_ok(absf(_lens(cart).y) < 0.0001 and _lens(cart).x < -0.1 and _lens(cart).z > 0.0,
		"ball/a notch of the wheel starts it round sideways, the way it goes", str(_lens(cart)))
	for i in 19:
		knob._unhandled_input(notch)
	_ok(_lens(cart).z < -0.999, "ball/and twenty take it to the back", str(_lens(cart)))
	knob.pointer_event(XRToolsPointerEvent.new(XRToolsPointerEvent.Type.RELEASED, cart, knob,
		pivot.global_position, pivot.global_position))
	cart.queue_free()
	await get_tree().process_frame


func _test_saved() -> void:
	var cart := await _spawn(_write_rom("saved.gb", _camera()))
	var knob := cart.get_node(KNOB_PATH) as VRKnob
	knob.set_value_no_signal(0.875)
	var persistence := ScenePersistence.new()
	var records: Array = persistence._serialize_articulated_controls(cart)
	var value := NAN
	for rec: Dictionary in records:
		if str(rec.get("path", "")) == KNOB_PATH and str(rec.get("kind", "")) == "knob":
			value = float(rec.get("value", NAN))
	_ok(is_equal_approx(value, 0.875), "saved/a save writes where the ball was left", str(records))
	# The restore is of another cartridge: a new one, built from the same ROM.
	var again := await _spawn(_write_rom("saved.gb", _camera()))
	persistence._restore_articulated_controls(again, records)
	_ok(is_equal_approx((again.get_node(KNOB_PATH) as VRKnob).get_value(), 0.875),
		"saved/and a restored cartridge's ball is turned back there")
	# 0.875 of the half turn clockwise from above: -157.5 degrees
	_ok(absf(_lens(again).dot(_arc(-157.5)) - 1.0) < 0.0001, "saved/lens and all", str(_lens(again)))
	# What netplay binds, by the same walk.
	_ok(cart.find_children("*", "VRKnob", true, false).has(knob), "saved/the knob is found from the cartridge")
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
		var rest := camera.get_node("OverhangMovingShape") as CollisionShape3D
		var head_box := _box_of(head)
		var rest_box := _box_of(rest)
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
		_ok(stub.size.y < size.y and _box_of(head).is_equal_approx(head_box) and _box_of(rest).is_equal_approx(rest_box),
			"seated/%s: the slot cuts the cartridge's box to its stub and leaves the head's and the ball's" % systemid,
			"stub %.1f mm" % (stub.size.y * 1000.0))
		var knob := camera.get_node(KNOB_PATH) as VRKnob
		var pivot := _pivot(camera)
		var glass := pivot.get_node("LensGlass") as Node3D
		var out := (to_sys.basis * (glass.global_position - pivot.global_position)).normalized()
		_ok(out.y < -0.999, "seated/%s: at rest the lens looks out of the back of the console" % systemid, str(out))
		knob.set_value(0.5)
		out = (to_sys.basis * (glass.global_position - pivot.global_position)).normalized()
		_ok(absf(out.x) > 0.999, "seated/%s: a quarter turn, along the top edge" % systemid, str(out))
		knob.set_value(1.0)
		out = (to_sys.basis * (glass.global_position - pivot.global_position)).normalized()
		_ok(out.y > 0.999, "seated/%s: half a turn, at whoever is looking at the screen" % systemid, str(out))
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
## The camera's own colors: which a ROM came in, a color bringing the camera body,
## a mod's shells keeping the camera a camera, the two halves of a real camera
## painted apart, its front label printed in the color's ground, and the colors on
## the hold menu.
func _test_colors() -> void:
	var gold_rom := _header("GAMEBOYCAMERA G", GbCameraShell.CART_TYPE_CAMERA)
	_ok(GbCameraShell.preset_for_header(gold_rom) == GbCameraShell.GOLD_PRESET,
		"colors/the gold edition's ROM is gold")
	_ok(GbCameraShell.preset_for_header(_camera()) == GbCameraShell.DEFAULT_PRESET,
		"colors/the plain one's is blue")
	var pocket_rom := _header("POCKETCAMERA", GbCameraShell.CART_TYPE_CAMERA)
	pocket_rom[GbCartShell.DESTINATION_AT] = GbCartShell.DESTINATION_JAPAN
	_ok(GbCameraShell.is_japanese(pocket_rom) and not GbCameraShell.is_japanese(_camera())
		and not GbCameraShell.is_japanese(gold_rom), "colors/the Pocket Camera's ROM is Japan's, the others overseas")
	_ok(GbCameraShell.preset_for_header(pocket_rom) == GbCameraShell.JAPAN_PRESET,
		"colors/and it is red")
	_ok(GbCameraShell.is_preset(&"camera_red") and not GbCameraShell.is_preset(&"red")
		and not GbCameraShell.is_preset(&""), "colors/the camera's ids are its own, apart from the Game Boy's")
	_ok(GbcCartShell.body_model_for("", &"camera_red", _game()) == GbCameraShell.BODY,
		"colors/a camera color asked of a game brings the camera body")

	var gold := await _spawn(_write_rom("gold.gb", gold_rom))
	var gold_preset := CartridgeColor.get_palette(GbCameraShell.PALETTE).find(GbCameraShell.GOLD_PRESET)
	_ok(_model_path(gold) == GbCameraShell.BODY and _albedo(gold, "HeadBase") == gold_preset.color,
		"colors/the gold ROM spawns a gold camera", str(_albedo(gold, "HeadBase")))
	_ok(gold_preset.finish == CartridgeShellPreset.Finish.METAL_FLAKE and _is_flake(gold, "HeadBase"),
		"colors/its gold is metal flake plastic, as the real one's is")
	gold.queue_free()
	var pocket := await _spawn(_write_rom("pocket.gb", pocket_rom))
	var pocket_red := CartridgeColor.get_palette(GbCameraShell.PALETTE).find(GbCameraShell.JAPAN_PRESET)
	_ok(_model_path(pocket) == GbCameraShell.BODY and _albedo(pocket, "HeadBase") == pocket_red.color,
		"colors/the Pocket Camera's ROM spawns a red camera", str(_albedo(pocket, "HeadBase")))
	pocket.queue_free()

	# A mod that brings the Game Boy's shells: its camera body if it has one, the
	# game's stand-in if it has none, never a plain cartridge with no lens.
	var rom := _write_rom("modded.gb", _camera())
	var plain := {"id": "t.gbcam:gb", "label": "Game Boy", "size": Vector3(0.057, 0.065, 0.0075),
		"model": GbCartShell.BODY}
	ModCartShells.register("gb", {"bodies": [plain]}, "t.gbcam")
	_ok(RetroCartridge.body_model_for("gb", rom, "", &"") == GbCameraShell.BODY,
		"colors/under a mod with no camera of its own, the camera ROM keeps the game's camera")
	ModCartShells.drop_mod("t.gbcam")
	var own := {"id": "t.gbcam:camera", "label": "Game Boy Camera", "size": Vector3(0.057, 0.065, 0.0083),
		"model": CART_SCENE.resource_path}
	ModCartShells.register("gb", {"bodies": [plain, own]}, "t.gbcam")
	_ok(RetroCartridge.body_model_for("gb", rom, "", &"") == CART_SCENE.resource_path,
		"colors/and wears the mod's own camera when it has one")
	_ok(RetroCartridge.body_model_for("gb", _write_rom("modded_game.gb", _game()), "", &"camera_green")
		== CART_SCENE.resource_path, "colors/as a game asked for in a camera color does")
	ModCartShells.drop_mod("t.gbcam")

	# A real camera's two plastics, as a mod's model names them, and its label.
	var model := Node3D.new()
	add_child(model)
	var parts := {}
	for part: Array in [["Front", GbCameraShell.FRONT_PLASTIC], ["Back", GbCameraShell.BACK_PLASTIC],
			["BallFront", GbCameraShell.BALL_FRONT_PLASTIC], ["BallBack", GbCameraShell.BALL_BACK_PLASTIC],
			[GbCameraShell.LABEL_MESH, &"Label"], [GbCameraShell.BOARD_NODE, &"PCB_Green"]]:
		var mi := MeshInstance3D.new()
		mi.name = part[0]
		mi.mesh = BoxMesh.new()
		var mat := StandardMaterial3D.new()
		mat.resource_name = part[1]
		mi.mesh.surface_set_material(0, mat)
		model.add_child(mi)
		parts[part[0]] = mi
	model.add_child(GbCameraEye.new())
	var labels := GDScript.new()
	labels.source_code = "extends Node3D\nfunc label_art() -> Dictionary:\n\treturn {&\"camera_red\": \"%s\"}\n" \
		% RetroTV.GLASS_WEAR_TEXTURE.resource_path
	labels.reload()
	model.set_script(labels)
	_ok(GbCameraShell.is_camera_model(model) and not GbCameraShell.is_camera_model(parts["Front"]),
		"colors/a body with the lens in it is a camera")
	var red := CartridgeColor.get_palette(GbCameraShell.PALETTE).find(&"camera_red")
	RetroCartridge.paint_camera(model, red, &"camera_red")
	var front: Material = (parts["Front"] as MeshInstance3D).get_active_material(0)
	var back: Material = (parts["Back"] as MeshInstance3D).get_active_material(0)
	_ok(front is BaseMaterial3D and (front as BaseMaterial3D).albedo_color.is_equal_approx(GbCameraShell.FRONT),
		"colors/the front half stays charcoal")
	_ok(back is BaseMaterial3D and (back as BaseMaterial3D).albedo_color.is_equal_approx(red.color),
		"colors/the back half takes the color")
	var bf := (parts["BallFront"] as MeshInstance3D).get_active_material(0) as BaseMaterial3D
	var bb := (parts["BallBack"] as MeshInstance3D).get_active_material(0) as BaseMaterial3D
	_ok(bf != null and bb != null and bf.albedo_color.is_equal_approx(GbCameraShell.FRONT) and bb.albedo_color.is_equal_approx(red.color),
		"colors/the ball's halves follow them: charcoal at the eye, the color behind")
	_ok(not (parts[GbCameraShell.BOARD_NODE] as Node3D).visible, "colors/the board inside is hidden behind an opaque shell")
	var printed := (parts[GbCameraShell.LABEL_MESH] as MeshInstance3D).get_active_material(0) as BaseMaterial3D
	_ok(printed != null and printed.albedo_texture != null
		and printed.albedo_texture.resource_path == RetroTV.GLASS_WEAR_TEXTURE.resource_path,
		"colors/and the front label is the one printed in that color's ground")
	RetroCartridge.paint_camera(model, CartridgeColor.get_palette(GbCameraShell.PALETTE).find(&"camera_clear_purple"),
		&"camera_clear_purple")
	front = (parts["Front"] as MeshInstance3D).get_active_material(0)
	_ok(not (front is BaseMaterial3D and (front as BaseMaterial3D).albedo_color.is_equal_approx(GbCameraShell.FRONT)),
		"colors/a clear edition is clear in front too")
	var pair: Array = GbCameraShell.CLEAR_BALL[&"camera_clear_purple"]
	var ball_front: Material = (parts["BallFront"] as MeshInstance3D).get_active_material(0)
	var ball_back: Material = (parts["BallBack"] as MeshInstance3D).get_active_material(0)
	_ok(ball_front is BaseMaterial3D and ball_back is BaseMaterial3D
		and (ball_front as BaseMaterial3D).albedo_color.is_equal_approx(pair[0])
		and (ball_back as BaseMaterial3D).albedo_color.is_equal_approx(pair[1])
		and (ball_front as BaseMaterial3D).transparency == BaseMaterial3D.TRANSPARENCY_DISABLED,
		"colors/the clear purple's ball is opaque: violet at the eye, light gray behind",
		"%s %s" % [str(ball_front), str(ball_back)])
	_ok((parts[GbCameraShell.BOARD_NODE] as Node3D).visible, "colors/and its board shows through the clear shell")
	# A model that dresses itself by region: asked which, its answer prints the label.
	var regional := GDScript.new()
	regional.source_code = "extends Node3D\nvar japan = null\nfunc label_art() -> Dictionary:\n\treturn {}\n" \
		+ "func dress_region(jp: bool) -> Dictionary:\n\tjapan = jp\n\treturn {&\"camera_red\": \"%s\"} if jp else {}\n" \
		% RetroTV.GLASS_WEAR_TEXTURE.resource_path
	regional.reload()
	model.set_script(regional)
	(parts[GbCameraShell.LABEL_MESH] as MeshInstance3D).set_surface_override_material(0, null)
	RetroCartridge.paint_camera(model, red, &"camera_red")
	_ok(model.get("japan") == false and (parts[GbCameraShell.LABEL_MESH] as MeshInstance3D).get_surface_override_material(0) == null,
		"colors/a model that dresses by region is asked for the overseas one by default")
	RetroCartridge.paint_camera(model, red, &"camera_red", true)
	printed = (parts[GbCameraShell.LABEL_MESH] as MeshInstance3D).get_active_material(0) as BaseMaterial3D
	_ok(model.get("japan") == true and printed != null and printed.albedo_texture != null
		and printed.albedo_texture.resource_path == RetroTV.GLASS_WEAR_TEXTURE.resource_path,
		"colors/and for Japan's on a Pocket Camera, whose label it prints")
	model.queue_free()

	# The colors on a Game Boy ROM's hold menu, with and without a mod's shells: the
	# camera's own on what spawns as the camera, and only a cartridge's on the rest.
	var holder := Control.new()
	add_child(holder)
	var view := SpawnMenuSpawnView.new()
	holder.add_child(view)
	var sent := {"options": null}
	var spawn := func(options: Dictionary) -> void: sent["options"] = options
	var texts := func() -> PackedStringArray:
		var shown := PackedStringArray()
		for b: Node in view._spawn_options_panel.find_children("*", "Button", true, false):
			shown.append((b as Button).text.strip_edges())
		return shown
	var press_text := func(text: String) -> void:
		for b: Node in view._spawn_options_panel.find_children("*", "Button", true, false):
			if (b as Button).text.strip_edges() == text:
				(b as Button).pressed.emit()
				return
	var camera_rom := _write_rom("hold_camera.gb", _camera())
	var game_rom := _write_rom("hold_game.gb", _game())
	var camera_gold := CartridgeColor.get_palette(GbCameraShell.PALETTE).find(GbCameraShell.GOLD_PRESET).display_name
	var cart_gold := _gb_preset(&"gold").display_name
	for modded: bool in [false, true]:
		var under := " under a mod's shells" if modded else ""
		if modded:
			ModCartShells.register("gb", {"bodies": [plain, own], "tint": [&"Gray_ABS_Textured"],
				"palette": "res://Resources/gb_cartridge_shells.tres"}, "t.gbcam")
		view._show_cart_spawn_options("gb", "Selftest", spawn, camera_rom)
		var shown: PackedStringArray = texts.call()
		_ok(shown.has(camera_gold) and shown.has("Clear Purple (Pocket Camera)") and not shown.has(cart_gold),
			"colors/the camera's hold menu offers only the camera's colors%s" % under, str(shown))
		press_text.call(camera_gold)
		press_text.call("Game Boy")
		shown = texts.call()
		_ok(shown.has(cart_gold) and not shown.has(camera_gold),
			"colors/and a cartridge's once a cartridge body is chosen%s" % under, str(shown))
		press_text.call("+  SPAWN")
		_ok(sent["options"] == {"body_region": "t.gbcam:gb" if modded else GbcCartShell.BODY_GB},
			"colors/the camera color picked before goes with its swatches%s" % under, str(sent["options"]))
		view._show_cart_spawn_options("gb", "Selftest", spawn, game_rom)
		shown = texts.call()
		_ok(shown.has(cart_gold) and not shown.has(camera_gold),
			"colors/a game's hold menu offers only a cartridge's colors%s" % under, str(shown))
		press_text.call("Game Boy Camera")
		shown = texts.call()
		_ok(shown.has(camera_gold) and not shown.has(cart_gold),
			"colors/and the camera's once the camera body is chosen%s" % under, str(shown))
		view._close_spawn_options_panel()
	ModCartShells.drop_mod("t.gbcam")
	holder.queue_free()
	await get_tree().process_frame


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


# ── the camera ────────────────────────────────────────────────────────────────


## Four quadrants, no two alike, so a picture turned over or mirrored on its way
## to a core lands on different colours: red and green across the top, blue and
## white across the bottom.
func _still(size: Vector2i, format := Image.FORMAT_RGBA8) -> Image:
	var img := Image.create(size.x, size.y, false, format)
	var half := size / 2
	img.fill_rect(Rect2i(Vector2i.ZERO, half), Color.RED)
	img.fill_rect(Rect2i(Vector2i(half.x, 0), size - Vector2i(half.x, 0)), Color.GREEN)
	img.fill_rect(Rect2i(Vector2i(0, half.y), Vector2i(half.x, size.y - half.y)), Color.BLUE)
	img.fill_rect(Rect2i(half, size - half), Color.WHITE)
	return img


## One pixel of what a core was handed.
func _pushed(push: Dictionary, x: int, y: int) -> Color:
	var data: PackedByteArray = push["rgba"]
	var at := (y * int(push["width"]) + x) * 4
	return Color8(data[at], data[at + 1], data[at + 2])


## The four corners of a push, two pixels in: red, green, blue, white.
func _corners_right(push: Dictionary) -> bool:
	var w := int(push["width"])
	var h := int(push["height"])
	return _pushed(push, 2, 2) == Color.RED and _pushed(push, w - 3, 2) == Color.GREEN \
		and _pushed(push, 2, h - 3) == Color.BLUE and _pushed(push, w - 3, h - 3) == Color.WHITE


## The eye of a body that is in no cartridge, and the body to free with it.
func _loose_body() -> Node3D:
	var body := (load(GbCameraShell.BODY) as PackedScene).instantiate() as Node3D
	add_child(body)
	return body


func _eye_of(body: Node3D) -> GbCameraEye:
	return body.get_node("Overhang/LensKnob/KnobPivot/LensEye") as GbCameraEye


## Where the lens points is where the camera looks, however the ball is turned
## and however the cartridge is held.
func _test_eye() -> void:
	var cart := await _spawn(_write_rom("eye.gb", _camera()))
	cart.global_transform = Transform3D(Basis.from_euler(Vector3(0.4, -0.9, 0.25)), Vector3(0.5, 1.2, -0.3))
	await get_tree().physics_frame
	var eye := cart.get_node_or_null(EYE_PATH) as GbCameraEye
	_ok(eye != null, "eye/the ball carries the lens as a camera")
	if eye == null:
		cart.queue_free()
		return
	var knob := cart.get_node(KNOB_PATH) as VRKnob
	var to_cart := cart.global_transform.basis.inverse()
	for value: float in [0.5, 0.75, 0.25, 1.0]:
		knob.set_value(value)
		var lens := _lens(cart)
		var fwd := (to_cart * -eye.global_transform.basis.z).normalized()
		var up := (to_cart * eye.global_transform.basis.y).normalized()
		var right := (to_cart * eye.global_transform.basis.x).normalized()
		_ok(fwd.dot(lens) > 0.9999, "eye/at %.2f it looks where the lens points" % value,
			"%s against the lens at %s" % [fwd, lens])
		_ok(up.dot(Vector3.UP) > 0.9999, "eye/at %.2f its top is the top of the cartridge" % value, str(up))
		_ok(right.dot(fwd.cross(up)) > 0.9999, "eye/at %.2f its right is the right of a camera, so nothing is mirrored" % value,
			str(right))
	knob.set_value(0.0)
	# Behind the label and looking out of it, the right of a camera is -X of the
	# cartridge: the side that is the RIGHT of the screen once seated, so the
	# viewfinder is the room as seen through the console.
	_ok((to_cart * eye.global_transform.basis.x).normalized().dot(Vector3.LEFT) > 0.9999,
		"eye/at the front its right is -X of the cartridge")
	var pivot := _pivot(cart)
	var out := eye.global_position - pivot.global_position
	var along := out.dot((cart.global_transform.basis * _lens(cart)).normalized())
	var glass := pivot.get_node("LensGlass") as MeshInstance3D
	var face := glass.position.length() + (glass.mesh as CylinderMesh).height * 0.5
	_ok(along > face and along < face + 0.001, "eye/it stands just outside the glass",
		"%.2f mm out, the glass ends at %.2f" % [along * 1000.0, face * 1000.0])
	_ok(out.length() - along < 0.00001, "eye/on the axis of the lens", "%.3f mm off it" % ((out.length() - along) * 1000.0))
	_ok(eye.get("_cartridge") == cart and eye.is_processing(), "eye/it knows the cartridge it is part of")
	var show := _loose_body()
	_ok(_eye_of(show).get("_cartridge") == null and not _eye_of(show).is_processing(),
		"eye/a body on show, with no cartridge round it, films nothing")
	show.free()

	# The viewport: made on demand, sharing the room, and never the one the player sees through.
	var before := get_viewport().get_camera_3d()
	_ok(eye.get_node_or_null("Feed") == null, "eye/it has no viewport until a core asks for a picture")
	eye.call("_ensure_viewport")
	var feed := eye.get_node_or_null("Feed") as SubViewport
	var cam := (feed.get_node_or_null("Lens") as Camera3D) if feed != null else null
	_ok(feed != null and cam != null and cam.get_parent() == feed, "eye/its camera is under a viewport of its own")
	if feed != null and cam != null:
		_ok(before == null and get_viewport().get_camera_3d() == null,
			"eye/so the viewport of the room has gained no camera, and the view of the player is not taken",
			"before %s, after %s" % [before, get_viewport().get_camera_3d()])
		_ok(cam.current, "eye/and it is the current one of its own")
		_ok(cam.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF,
			"eye/posed each frame it is drawn, it is not interpolated between physics ticks")
		_ok(feed.render_target_update_mode == SubViewport.UPDATE_DISABLED, "eye/the viewport draws nothing until it is armed")
		_ok(not feed.own_world_3d and feed.find_world_3d() == get_viewport().find_world_3d(),
			"eye/it films the world of the room, not one of its own")
		_ok(feed.msaa_3d == Viewport.MSAA_DISABLED and feed.positional_shadow_atlas_size == 0,
			"eye/with no antialiasing and no shadow atlas of its own")
		_ok(is_equal_approx(cam.fov, GbCameraEye.FOV_DEGREES) and cam.near <= 0.02 and cam.far >= 50.0,
			"eye/through the angle of the lens, from the glass to the far wall")
		knob.set_value(0.8)
		eye.call("_aim")
		var want := eye.global_transform
		_ok(cam.global_position.distance_to(want.origin) < 0.00001
			and (-cam.global_transform.basis.z).dot(-want.basis.z.normalized()) > 0.9999
			and cam.global_transform.basis.y.dot(want.basis.y.normalized()) > 0.9999,
			"eye/aimed, the camera is where the lens is and looks as it does")
		# A body fitted per axis to another size: the eye is then scaled and
		# sheared, and none of that may reach the camera.
		(cart.get_node("CartModel") as Node3D).scale = Vector3(1.3, 0.8, 1.1)
		eye.call("_aim")
		var sheared := eye.global_transform.basis
		_ok(absf(sheared.determinant() - 1.0) > 0.05, "eye/(a fitted body does scale the eye)", "%.3f" % sheared.determinant())
		_ok(cam.global_transform.basis.is_equal_approx(cam.global_transform.basis.orthonormalized())
			and absf(cam.global_transform.basis.determinant() - 1.0) < 0.0001,
			"eye/none of the scale of a fitted body is carried into the picture")
		_ok((-cam.global_transform.basis.z).dot((-sheared.z).normalized()) > 0.9999,
			"eye/and the camera still looks exactly where the lens does")
		(cart.get_node("CartModel") as Node3D).scale = Vector3.ONE
	cart.queue_free()
	await get_tree().process_frame


## What is handed to a core, and when. A FakeMachine stands for the console and a
## still for the room.
func _test_feed() -> void:
	var body := _loose_body()
	var eye := _eye_of(body)
	var machine := FakeMachine.new()
	var lib := machine.lib as FakeLibretro
	var asked: Array[Vector2i] = []
	var shot := {"size": Vector2i.ZERO, "format": Image.FORMAT_RGBA8}
	eye.machine_source = func() -> Object: return machine
	eye.picture_source = func(size: Vector2i) -> Image:
		asked.append(size)
		var made: Vector2i = shot["size"]
		return _still(size if made == Vector2i.ZERO else made, shot["format"])
	# A frame a little over a quarter of the time from one picture to the next.
	var period: float = eye.call("_period")
	var tick := period * 0.26

	machine.is_powered_on = false
	_ok(eye.feed_target() == null, "feed/a machine switched off is not filmed for")
	machine.is_powered_on = true
	lib.active = false
	_ok(eye.feed_target() == null, "feed/nor one whose core has not started its camera")
	eye.set("_wait", 0.0)
	for i in 16:
		eye._process(tick)
	_ok(lib.pushes.is_empty() and asked.is_empty(), "feed/and no picture is made for it")

	lib.active = true
	_ok(eye.feed_target() == lib, "feed/switched on with its camera started, it is")
	eye.set("_wait", 0.0)
	for i in 12:
		eye._process(tick)
	_ok(lib.pushes.size() == 3, "feed/so many pictures a second, not one a frame",
		"%d pictures in 12 frames, each %.0f%% of the time between two" % [lib.pushes.size(), tick / period * 100.0])
	if not lib.pushes.is_empty():
		var first: Dictionary = lib.pushes[0]
		_ok(int(first["width"]) == CAMERA_SIZE.x and int(first["height"]) == CAMERA_SIZE.y
			and (first["rgba"] as PackedByteArray).size() == CAMERA_SIZE.x * CAMERA_SIZE.y * 4,
			"feed/at the size the core asked for, four bytes a pixel")
		_ok(_corners_right(first), "feed/the right way up and unmirrored: each corner where the still had it",
			"%s %s / %s %s" % [_pushed(first, 2, 2), _pushed(first, 125, 2), _pushed(first, 2, 109), _pushed(first, 125, 109)])

	# A picture that is not what the core asked for is never passed on as it came.
	lib.pushes.clear()
	shot["size"] = CAMERA_SIZE * 2
	eye.set("_wait", 0.0)
	eye._process(0.0)
	_ok(lib.pushes.size() == 1 and int(lib.pushes[0]["width"]) == CAMERA_SIZE.x
		and (lib.pushes[0]["rgba"] as PackedByteArray).size() == CAMERA_SIZE.x * CAMERA_SIZE.y * 4
		and _corners_right(lib.pushes[0]), "feed/a larger picture is brought to the size of the core, not left for it to crop")
	lib.pushes.clear()
	shot["size"] = Vector2i.ZERO
	shot["format"] = Image.FORMAT_RGB8
	eye.set("_wait", 0.0)
	eye._process(0.0)
	_ok(lib.pushes.size() == 1 and (lib.pushes[0]["rgba"] as PackedByteArray).size() == CAMERA_SIZE.x * CAMERA_SIZE.y * 4
		and _corners_right(lib.pushes[0]), "feed/a picture in another format is handed over as RGBA8")
	shot["format"] = Image.FORMAT_RGBA8

	# The size belongs to the core, and is asked for with every picture.
	lib.pushes.clear()
	asked.clear()
	lib.size = Vector2i(64, 56)
	eye.set("_wait", 0.0)
	eye._process(0.0)
	_ok(asked.size() == 1 and asked[0] == Vector2i(64, 56) and lib.pushes.size() == 1 and int(lib.pushes[0]["height"]) == 56,
		"feed/another size asked for is another size of picture", str(asked))
	lib.pushes.clear()
	asked.clear()
	lib.size = Vector2i.ZERO
	eye.set("_wait", 0.0)
	for i in 8:
		eye._process(tick)
	_ok(lib.pushes.is_empty() and asked.is_empty(), "feed/a core that has named no size is handed nothing")
	lib.size = CAMERA_SIZE

	lib.active = false
	eye.set("_wait", 0.0)
	for i in 8:
		eye._process(tick)
	_ok(lib.pushes.is_empty() and eye.get("_feeding") == null, "feed/it stops when the core stops its camera")

	# A library from before the camera: asked nothing it does not have.
	machine.lib = OldLibretro.new()
	_ok(eye.feed_target() == null, "feed/a core library with no camera in it is never called")
	eye._process(0.0)
	eye.machine_source = func() -> Object: return null
	_ok(eye.feed_target() == null, "feed/and with no machine there is nothing to feed")

	# No still supplied: the picture is the room, which a headless run cannot draw.
	machine.lib = lib
	lib.active = true
	lib.pushes.clear()
	eye.machine_source = func() -> Object: return machine
	eye.picture_source = Callable()
	if DisplayServer.get_name() == "headless":
		eye.set("_wait", 0.0)
		for i in 16:
			eye._process(tick)
		_ok(lib.pushes.is_empty() and eye.get_node_or_null("Feed") == null,
			"feed/a headless run draws no room and hands no blank picture over")
	body.free()

	# The real thing it asks: the console whose own slot the cartridge is in.
	var sys := SYSTEM_SCENE.instantiate() as RetroSystem
	sys.systemid = "gbc"
	sys.ignore_gravity = true
	sys.freeze = true
	add_child(sys)
	for i in 30:
		await get_tree().process_frame
	var camera := await _spawn(_write_rom("feed_camera.gb", _camera()))
	var seated := camera.get_node(EYE_PATH) as GbCameraEye
	_ok(seated.call("_seated_machine") == null and seated.feed_target() == null, "feed/a camera lying loose is in no machine")
	sys.restore_cartridge(camera)
	for i in 30:
		await get_tree().process_frame
	_ok(seated.call("_seated_machine") == sys, "feed/in the slot of a console, that console is its machine")
	_ok(seated.feed_target() == null, "feed/which it does not film for while the console is off")
	(sys.get("_cartridge_slot") as XRToolsSnapZone).drop_object()
	for i in 5:
		await get_tree().process_frame
	_ok(seated.call("_seated_machine") == null, "feed/and taken out again, it is in none")
	camera.queue_free()
	sys.queue_free()
	for i in 5:
		await get_tree().process_frame


func _test_binding() -> void:
	for method: String in ["PushCameraFrame", "IsCameraActive", "GetCameraFrameSize", "GetCameraStats"]:
		_ok(ClassDB.class_has_method("Libretro", method), "binding/%s is bound" % method)
	if not ClassDB.class_exists("Libretro"):
		return
	var lib: Node = ClassDB.instantiate("Libretro")
	_ok(not lib.IsCameraActive(), "binding/a node with no core has no camera started")
	_ok(lib.GetCameraFrameSize() == Vector2i.ZERO, "binding/and no picture size, no core having asked for one")
	var picture := PackedByteArray()
	picture.resize(CAMERA_SIZE.x * CAMERA_SIZE.y * 4)
	_ok(not lib.PushCameraFrame(picture, CAMERA_SIZE.x, CAMERA_SIZE.y), "binding/a picture pushed at it is refused")
	_ok(not lib.PushCameraFrame(picture, 0, 0) and not lib.PushCameraFrame(PackedByteArray(), -4, 7),
		"binding/as is one with no size, or a senseless one")
	var stats: Dictionary = lib.GetCameraStats()
	_ok(int(stats.get("starts", -1)) == 0 and int(stats.get("delivered", -1)) == 0 and int(stats.get("pushed", -1)) == 0,
		"binding/and nothing has been handed to any core", str(stats))
	lib.free()


## The core the ROM of the camera names, what that core is told, and netplay.
func _test_core() -> void:
	var camera_rom := _write_rom("core_camera.gb", _camera())
	var game_rom := _write_rom("core_game.gb", _game())
	_ok(GbCameraShell.is_camera_rom(camera_rom) and not GbCameraShell.is_camera_rom(game_rom),
		"core/the ROM of the camera is known on disk by its header, and that of a game is not")
	var late := ProjectSettings.globalize_path("user://" + FIXTURE).path_join("core_late.gb")
	_ok(not GbCameraShell.is_camera_rom(late) and not GbCameraShell.is_camera_rom(""), "core/a file that is not there is no camera")
	_write_rom("core_late.gb", _camera())
	_ok(GbCameraShell.is_camera_rom(late), "core/but is asked again once it is: a ROM still arriving is not remembered as a game")
	for systemid: String in ["gb", "gbc", "gba"]:
		_ok(GbCameraShell.boot_for(systemid, camera_rom) == {"core": "mgba"}, "core/%s: the camera names mGBA" % systemid,
			str(GbCameraShell.boot_for(systemid, camera_rom)))
	_ok(GbCameraShell.boot_for("gb", game_rom).is_empty() and GbCameraShell.boot_for("gbc", "").is_empty(),
		"core/a game names no core, nor does an empty slot")
	_ok(GbCameraShell.boot_for("snes", camera_rom).is_empty() and GbCameraShell.boot_for("n64", camera_rom).is_empty(),
		"core/and the camera names none for a machine that is not a Game Boy")

	# What mGBA is told it is: never a Super Game Boy, which the header of the camera asks for.
	_ok(ForcedCoreOptions.game_boy_model("mgba", "gb") == {"mgba_gb_model": "Game Boy", "mgba_sgb_borders": "OFF"},
		"core/on a Game Boy, mGBA is a Game Boy with no TV border", str(ForcedCoreOptions.game_boy_model("mgba", "gb")))
	_ok(ForcedCoreOptions.game_boy_model("mgba", "gbc") == {"mgba_gb_model": "Game Boy Color", "mgba_sgb_borders": "OFF"},
		"core/on a Game Boy Color, a Game Boy Color", str(ForcedCoreOptions.game_boy_model("mgba", "gbc")))
	_ok(ForcedCoreOptions.game_boy_model("mgba", "gba") == {"mgba_sgb_borders": "OFF"},
		"core/a Game Boy Advance loses the border and keeps its own model", str(ForcedCoreOptions.game_boy_model("mgba", "gba")))
	# Gambatte: a Game Boy is a DMG whatever is in it, so a Color-only game shows its
	# own refusal; a Game Boy Color colors an original game, a Game Boy does not.
	_ok(ForcedCoreOptions.game_boy_model("gambatte", "gb") == {"gambatte_gb_hwmode": "GB", "gambatte_gb_colorization": "disabled"},
		"core/on a Game Boy, gambatte is a DMG and leaves the color to the green panel", str(ForcedCoreOptions.game_boy_model("gambatte", "gb")))
	_ok(ForcedCoreOptions.game_boy_model("gambatte", "gbc") == {"gambatte_gb_hwmode": "GBC", "gambatte_gb_colorization": "GBC"},
		"core/on a Game Boy Color, a Color with its own palettes for Game Boy games", str(ForcedCoreOptions.game_boy_model("gambatte", "gbc")))
	for key: String in ForcedCoreOptions.game_boy_model("gambatte", "gb"):
		_ok(CoreOptionsStore.HARDWARE_PINNED.has(key), "core/the core manager locks %s too" % key)
	_ok(ForcedCoreOptions.game_boy_model("sameboy", "gb").is_empty() and ForcedCoreOptions.game_boy_model("mgba", "ereader").is_empty()
		and ForcedCoreOptions.game_boy_model("gambatte", "snes").is_empty(),
		"core/no other core is told anything, and neither core anything for another machine")

	var sys := SYSTEM_SCENE.instantiate() as RetroSystem
	sys.systemid = "gbc"
	sys.core_name = "gambatte"
	sys.ignore_gravity = true
	sys.freeze = true
	add_child(sys)
	for i in 30:
		await get_tree().process_frame
	var slot := sys.get("_cartridge_slot") as XRToolsSnapZone
	_ok(sys.resolve_core_name() == "gambatte", "core/an empty Game Boy Color runs the core it was given")
	var game := await _spawn(game_rom)
	sys.restore_cartridge(game)
	for i in 30:
		await get_tree().process_frame
	_ok(sys.resolve_core_name() == "gambatte" and sys.expansion_boot().is_empty(),
		"core/and so does one with a game in it", sys.resolve_core_name())
	_ok(not sys.net_boot_spec("gambatte").is_empty(), "core/a game there can be booted alike by every peer of a session")
	slot.drop_object()
	for i in 5:
		await get_tree().process_frame
	game.queue_free()

	var camera := await _spawn(camera_rom)
	sys.restore_cartridge(camera)
	for i in 30:
		await get_tree().process_frame
	_ok(sys.resolve_core_name() == "mgba", "core/with the camera in it, it runs mGBA whatever it was given",
		sys.resolve_core_name())
	var forced: Dictionary = sys.call("_all_forced_options", sys.resolve_core_name())
	_ok(str(forced.get("mgba_gb_model", "")) == "Game Boy Color" and str(forced.get("mgba_sgb_borders", "")) == "OFF",
		"core/and that run is pinned to a Game Boy Color with no border", str(forced))
	var none: Array[Dictionary] = []
	var verdict := RetroSystem._power_on_verdict(sys.resolve_core_name(), "gbc", camera_rom, none, "", false, false)
	_ok(not bool(verdict["start"]) and "mgba" in str(verdict["description"]),
		"core/a player who never chose mGBA is told it is the core this needs", str(verdict.get("description", "")))

	# Netplay: no two peers draw the room alike, so the camera boots for the host alone.
	_ok(sys.rom_path == camera_rom and sys.net_boot_spec("mgba").is_empty(),
		"core/the camera has no boot the peers of a session could share", str(sys.net_boot_spec("mgba")))
	var heard := {"reason": "", "remedy": {"unset": true}}
	var on_blocked := func(reason: String, _machine: Object, remedy: Dictionary) -> void:
		heard["reason"] = reason
		heard["remedy"] = remedy
	NetworkManager.netplay_blocked.connect(on_blocked)
	sys.call("_report_netplay_blocked")
	NetworkManager.netplay_blocked.disconnect(on_blocked)
	_ok("Game Boy Camera" in str(heard["reason"]) and (heard["remedy"] as Dictionary).is_empty(),
		"core/and the host is told why in words of its own, with no core swap offered", str(heard))
	slot.drop_object()
	for i in 5:
		await get_tree().process_frame
	_ok(sys.resolve_core_name() == "gambatte", "core/the camera taken out, it is the core it was given again")
	camera.queue_free()
	sys.queue_free()
	for i in 5:
		await get_tree().process_frame
