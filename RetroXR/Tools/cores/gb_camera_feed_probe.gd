## The Game Boy Camera photographing the room: the real core and the real ROM.
##
##     USERPROFILE=<a scratch home holding retroxr/probe_home.txt> \
##     "$godot" --path RetroXR --resolution 640x480 --position 20,20 \
##         res://Tools/cores/gb_camera_feed_probe.tscn -- "--rom=<Game Boy Camera>"
##     ... -- ... --away      # control: the lens turned half round, at the OTHER target
##     ... -- ... --nofeed    # control: the eye stopped once the viewfinder is live
##     ... -- ... --system=gb|gbc|gba     (default gbc)
##
## WINDOWED, never --headless: the lens draws the room, and the dummy renderer
## draws nothing.
##
## gb_camera_tests proves the eye looks where the lens does and hands a core what
## it asked for, against a fake core and a still. This is the other half, which no
## suite can hold: that mGBA, started by the room on a machine that was given
## Gambatte, asks for a camera, starts it, is handed pictures on its own thread,
## and shows them in the game's viewfinder the right way up.
##
## The room holds two targets, one each side of the console, each a black wall
## with ONE white quarter: up and to the right of the lens on the far side (A),
## down and to the left on the near side (B). They are placed from the cartridge
## and the glass, never from the eye under test, so a picture turned over or
## mirrored on its way to the game lights the wrong quarter of the viewfinder.
##
## One core and one leg a process. Each control proves it reached the viewfinder,
## which a control that merely "shows nothing" would not:
##   (default)  the lens at A: the viewfinder shows A.
##   --away     the lens turned half round on its knob: it shows B, not A.
##   --nofeed   reaches A, then the eye is stopped and the lens turned to B: the
##              viewfinder goes on showing A and nothing more is pushed; started
##              again, it shows B.
##
## The cartridge's battery is WRITTEN (the game keeps its album there), and so is
## the data root. So this refuses to run unless the data root holds a file named
## probe_home.txt, which a player's never does. The scratch home wants
## `retroxr/probe_home.txt` and `retroxr/libretro/cores/mgba_libretro.dll`.
extends Node3D

const SYS_SCENE := "res://Scenes/Objects/system.tscn"
const CART_SCENE := "res://Scenes/Objects/media/cartridge.tscn"
const KNOB_PATH := "CartModel/Overhang/LensKnob"
const MARKER := "probe_home.txt"

const BTN_START := 1 << 3
const BTN_A := 1 << 8

## The core mGBA must be, whatever the machine was given.
const CAMERA_CORE := "mgba"
const RIG_AT := Vector3(60.0, 1.2, 0.0)
## How far in front of the glass each target stands, and the side of its white
## quarter, which is past the edge of what the lens takes in at that range (0.45 m
## to either side, 0.39 up and down). The wall behind it is 2.2 times that.
const TARGET_RANGE := 1.0
const TARGET_QUARTER := 1.0
## The viewfinder is the middle 128x112 of the 160x144 screen. Read a little
## inside it, so a border a pixel either way is not counted as picture.
const FINDER := Rect2i(24, 24, 112, 96)
const MAX_PRESSES := 16

var _rom := ""
var _system := "gbc"
var _leg := ""
var _out := "res://probe_out/gb_camera_feed"

var _pass := 0
var _fail := 0
var _sys: RetroSystem = null
var _lib: Libretro = null
var _cart: RetroCartridge = null
var _eye: GbCameraEye = null
var _knob: VRKnob = null
var _observer: Camera3D = null
var _shots := 0


func _ready() -> void:
	get_tree().create_timer(600.0).timeout.connect(func() -> void:
		print("[gbcam-feed] TIMEOUT")
		get_tree().quit(1))
	await _run()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--rom="):
			_rom = arg.substr(6)
		elif arg.begins_with("--system="):
			_system = arg.substr(9)
		elif arg.begins_with("--out="):
			_out = arg.substr(6)
		elif arg in ["--away", "--nofeed"]:
			_leg = arg.substr(2)

	if not FileAccess.file_exists(DataPaths.media_root(MARKER)):
		print("[gbcam-feed] SKIP  %s has no %s: this writes a battery, so it runs in a scratch home only"
			% [DataPaths.media_root(), MARKER])
		get_tree().quit(0)
		return
	if DisplayServer.get_name() == "headless":
		print("[gbcam-feed] SKIP  run it windowed: the lens draws the room, and headless draws nothing")
		get_tree().quit(0)
		return
	if _rom.is_empty() or not FileAccess.file_exists(_rom):
		print("[gbcam-feed] SKIP  pass --rom=<the Game Boy Camera>")
		get_tree().quit(0)
		return
	var root := CoreDownloadManager.default_core_root()
	if CoreDownloadManager.installed_core_lib(CAMERA_CORE).is_empty():
		print("[gbcam-feed] SKIP  no %s core under %s" % [CAMERA_CORE, root])
		get_tree().quit(0)
		return
	# The scratch home's, and only so that what the core is told about its model
	# is what this run pins rather than what the last one left behind.
	DirAccess.remove_absolute("%s/core_options/%s.opt" % [root, CAMERA_CORE])
	print("[gbcam-feed] a %s, leg: %s" % [_system, _leg if not _leg.is_empty() else "feed"])
	_ok("the ROM is the Game Boy Camera's", GbCameraShell.is_camera_rom(_rom))

	_stage()
	_sys = (load(SYS_SCENE) as PackedScene).instantiate() as RetroSystem
	_sys.systemid = _system
	# Given the core that will not load this cartridge at all, on purpose.
	_sys.core_name = "gambatte" if _system != "gba" else ""
	add_child(_sys)
	_sys.freeze = true
	_sys.gravity_scale = 0.0
	# Held upright, as in a hand: the screen to +Z, its top edge up. The lens at
	# rest then looks out of the back of the console, along -Z.
	#
	# And well clear of the origin. The lens films the window's own world, and the
	# app's boot splash stands near the origin of it: the first run photographed
	# "RETRO XR / STARTING UP" instead of the target behind it (legible, the right
	# way up, and not what was being measured). vmu_screen_probe met the same.
	_sys.global_transform = Transform3D(Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN), RIG_AT)
	await _room_frames(6)
	_lib = _sys.get_libretro_node()
	# The unit's own input node sends the idle pad every frame and would wipe a
	# press out; this probe is the only hand on the machine.
	var input := _input_node(_sys)
	if input != null:
		input.set_process(false)

	_cart = (load(CART_SCENE) as PackedScene).instantiate() as RetroCartridge
	_cart.systemid = "gb"
	_cart.rom_path = _rom
	_cart.game_label = "Camera probe"
	_cart.save_id = "gbcamerafeedprobe"
	add_child(_cart)
	_cart.global_position = _sys.global_position + Vector3(0, 0.3, 0)
	await _room_frames(4)
	_ok("the cartridge wears the camera's body", GbCameraShell.is_body(_cart.get_node("CartModel").scene_file_path))
	_sys.restore_cartridge(_cart)
	await _room_frames(30)
	_eye = _cart.get_node_or_null(KNOB_PATH + "/KnobPivot/LensEye") as GbCameraEye
	_knob = _cart.get_node_or_null(KNOB_PATH) as VRKnob
	_ok("it carries a lens eye and a knob", _eye != null and _knob != null)
	if _eye == null or _knob == null:
		return _finish()

	_eq("with the camera in it, the machine will run mGBA", _sys.resolve_core_name(), CAMERA_CORE)
	_build_targets()
	if _leg == "away":
		_knob.set_value(1.0)
	_print_eye()

	_sys.power_on()
	_ok("it switches on", _sys.is_powered_on)
	if not _sys.is_powered_on:
		return _finish()
	_ok("and the core runs", await _runs())
	await _emulated(60)
	_eq("the core asked for a camera of 128x112", _lib.GetCameraFrameSize(), Vector2i(128, 112))
	_ok("and has started it", await _until(func() -> bool: return _lib.IsCameraActive(), 300))
	var screen := _screen()
	_eq("the picture is a handheld's 160x144, not a Super Game Boy's 256x224",
		screen.get_size() if screen != null else Vector2i.ZERO, Vector2i(160, 144))
	_ok("the eye has found the core to feed", _eye.feed_target() == _lib)

	# Into the viewfinder, a press at a time, until a target is on the screen.
	var want := "B" if _leg == "away" else "A"
	var seen := await _to_viewfinder()
	_eq("the viewfinder shows the target the lens is pointed at, the right way up and unmirrored", seen, want)
	var stats: Dictionary = _lib.GetCameraStats()
	print("[gbcam-feed] camera stats %s" % str(stats))
	_ok("pictures were pushed and handed to the core", int(stats.get("pushed", 0)) > 2 and int(stats.get("delivered", 0)) > 2,
		str(stats))
	_eq("and none was the wrong size", int(stats.get("rejected", -1)), 0)
	await _photos(want.to_lower())

	if _leg == "nofeed" and seen == "A":
		# The eye stopped, and then the lens turned to the other target: if the
		# viewfinder is what was pushed, it must go on showing the first.
		_eye.set_process(false)
		await _emulated(20)
		var pushed := int((_lib.GetCameraStats() as Dictionary).get("pushed", 0))
		_knob.set_value(1.0)
		await _emulated(300)
		_eq("with the eye stopped, turning the lens changes nothing in the game", _classify(_screen()), "A")
		_eq("and nothing more was pushed", int((_lib.GetCameraStats() as Dictionary).get("pushed", 0)), pushed)
		await _photos("stopped_at_b_showing_a")
		_eye.set_process(true)
		var follows := await _until(func() -> bool: return _classify(_screen()) == "B", 400)
		_ok("started again, the viewfinder follows the lens to the other target", follows, _classify(_screen()))
		await _photos("b_again")

	_sys.power_off()
	await _room_frames(30)
	_ok("switched off, the core's camera is no longer active", not _lib.IsCameraActive())
	_ok("and the eye feeds nothing", _eye.feed_target() == null)
	_finish()


# ── the room ─────────────────────────────────────────────────────────────────

func _stage() -> void:
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.3, 0.32, 0.36)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.8, 0.8, 0.85)
	env.environment.ambient_light_energy = 0.6
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	sun.light_energy = 0.9
	add_child(sun)
	_observer = Camera3D.new()
	_observer.fov = 50.0
	_observer.near = 0.01
	add_child(_observer)
	_observer.make_current()


## Where the lens looks, read off the model: from the ball's centre to its glass.
func _lens_out() -> Vector3:
	var pivot := _cart.get_node(KNOB_PATH + "/KnobPivot") as Node3D
	return ((pivot.get_node("LensGlass") as Node3D).global_position - pivot.global_position).normalized()


func _glass() -> Vector3:
	return (_cart.get_node(KNOB_PATH + "/KnobPivot/LensGlass") as Node3D).global_position


## Two walls, built with the ball at rest. A is where the lens looks, with its
## white quarter up and to the right of a camera standing at the glass; B is
## behind the ball, where the lens looks when turned half round, with its white
## quarter down and to the left of a camera turned to face it.
func _build_targets() -> void:
	_knob.set_value(0.5)
	var out := _lens_out()
	var up := _cart.global_transform.basis.y.normalized()
	var right := out.cross(up).normalized()
	_wall("TargetA", _glass() + out * TARGET_RANGE, right, up, 1.0, 1.0)
	# Turned half round, a camera's right is the other way.
	_wall("TargetB", _glass() - out * TARGET_RANGE, -right, up, -1.0, -1.0)


func _wall(wall_name: String, centre: Vector3, right: Vector3, up: Vector3,
		side: float, rise: float) -> void:
	var holder := Node3D.new()
	holder.name = wall_name
	add_child(holder)
	var facing := Basis(right, up, right.cross(up))
	holder.global_transform = Transform3D(facing, centre)
	var back := MeshInstance3D.new()
	var slab := BoxMesh.new()
	slab.size = Vector3(TARGET_QUARTER * 2.2, TARGET_QUARTER * 2.2, 0.004)
	back.mesh = slab
	back.material_override = _flat(Color.BLACK)
	holder.add_child(back)
	var quarter := MeshInstance3D.new()
	var block := BoxMesh.new()
	block.size = Vector3(TARGET_QUARTER, TARGET_QUARTER, 0.012)
	quarter.mesh = block
	quarter.material_override = _flat(Color.WHITE)
	holder.add_child(quarter)
	quarter.position = Vector3(side * TARGET_QUARTER * 0.5, rise * TARGET_QUARTER * 0.5, 0.0)


## Unshaded: what the lens sees of a target must not depend on the room's light.
func _flat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	return mat


## The eye's own frame beside the one read off the model. They must agree, and a
## printed basis is the check that can fail (CLAUDE.md, "a check that can fail").
func _print_eye() -> void:
	var b := _eye.global_transform.basis
	var out := _lens_out()
	var up := _cart.global_transform.basis.y.normalized()
	print("[gbcam-feed] eye  forward %s  up %s  right %s" % [-b.z.normalized(), b.y.normalized(), b.x.normalized()])
	print("[gbcam-feed] lens forward %s  up %s  right %s" % [out, up, out.cross(up).normalized()])
	_ok("the eye looks where the lens points, the cartridge's top up, a camera's right on its right",
		(-b.z.normalized()).dot(out) > 0.9999 and b.y.normalized().dot(up) > 0.9999
		and b.x.normalized().dot(out.cross(up).normalized()) > 0.9999)


# ── the game ─────────────────────────────────────────────────────────────────

## START past the title, then A through the menus, looking at the screen after
## every press. Returns the target the viewfinder is showing, or "".
func _to_viewfinder() -> String:
	await _emulated(240)
	for press in range(MAX_PRESSES):
		var seen := _classify(_screen())
		if not seen.is_empty():
			print("[gbcam-feed] viewfinder live after %d press(es): %s" % [press, _quarters_text(_screen())])
			return seen
		await _tap(BTN_START if press == 0 else BTN_A, 6, 110)
	print("[gbcam-feed] no target on the screen after %d presses: %s" % [MAX_PRESSES, _quarters_text(_screen())])
	return _classify(_screen())


## Mean brightness of each quarter of the viewfinder: top left, top right,
## bottom left, bottom right.
func _quarters(screen: Image) -> PackedFloat32Array:
	var out := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	if screen == null or screen.get_width() < FINDER.end.x or screen.get_height() < FINDER.end.y:
		return out
	var half := FINDER.size / 2
	for q in 4:
		var origin := FINDER.position + Vector2i((q % 2) * half.x, int(q / 2.0) * half.y)
		var sum := 0.0
		for y in range(origin.y, origin.y + half.y):
			for x in range(origin.x, origin.x + half.x):
				sum += screen.get_pixel(x, y).get_luminance()
		out[q] = sum / float(half.x * half.y)
	return out


func _quarters_text(screen: Image) -> String:
	var q := _quarters(screen)
	return "TL %.2f  TR %.2f  BL %.2f  BR %.2f" % [q[0], q[1], q[2], q[3]]


## "A" when the top right quarter alone is bright, "B" when the bottom left alone
## is, "" for anything else: a menu, a blank, or a picture the wrong way round.
func _classify(screen: Image) -> String:
	var q := _quarters(screen)
	var best := 0
	for i in range(1, 4):
		if q[i] > q[best]:
			best = i
	var rest := 0.0
	for i in 4:
		if i != best:
			rest = maxf(rest, q[i])
	if q[best] - rest < 0.3:
		return ""
	return {1: "A", 2: "B"}.get(best, "")


func _screen() -> Image:
	var image: Image = _lib.GetVideoImage()
	return image.duplicate() as Image if image != null and not image.is_empty() else null


func _runs() -> bool:
	var was: int = _lib.GetFrameCount()
	for i in range(600):
		await get_tree().process_frame
		if _lib.GetFrameCount() > was + 5:
			return true
	return false


func _tap(mask: int, press_frames: int, gap_frames: int) -> void:
	_lib.SetJoypadState(0, mask, 0, 0, 0, 0)
	await _emulated(press_frames)
	_lib.SetJoypadState(0, 0, 0, 0, 0, 0)
	await _emulated(gap_frames)


## Frames the core has run, not frames the room has drawn.
func _emulated(n: int) -> void:
	var target: int = _lib.GetFrameCount() + n
	var guard := n * 40 + 400
	while _lib.GetFrameCount() < target and guard > 0:
		guard -= 1
		await get_tree().process_frame


func _until(cond: Callable, frames: int) -> bool:
	var target: int = _lib.GetFrameCount() + frames
	var guard := frames * 40 + 400
	while guard > 0:
		if cond.call():
			return true
		if _lib.GetFrameCount() >= target:
			return false
		guard -= 1
		await get_tree().process_frame
	return false


func _room_frames(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame


func _input_node(node: Node) -> Node:
	for child in node.get_children():
		var script := child.get_script() as Script
		if script != null and script.resource_path.ends_with("handheld_input.gd"):
			return child
		var found := _input_node(child)
		if found != null:
			return found
	return null


# ── the pictures ─────────────────────────────────────────────────────────────

## Four for each moment: the console in the hand's place with target A behind it
## (its own screen is the viewfinder), the room from further off, what the lens
## drew, and the core's own screen.
func _photos(label: String) -> void:
	var dir := _out
	if dir.begins_with("res://") or dir.begins_with("user://"):
		dir = ProjectSettings.globalize_path(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	_shots += 1
	var stem := "%s/%s_%s_%02d_%s" % [dir, _system, _leg if not _leg.is_empty() else "feed", _shots, label]

	# Both from in front of target B, which stands a metre behind the console and
	# would otherwise be all either of them saw.
	var at := _sys.global_position
	_observer.fov = 35.0
	_observer.global_position = at + Vector3(0.02, 0.05, 0.42)
	_observer.look_at(at + Vector3(0, 0.03, 0), Vector3.UP)
	await _room_frames(4)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(stem + "_hand.png")
	_observer.fov = 60.0
	_observer.global_position = at + Vector3(0.75, 0.45, 0.8)
	_observer.look_at(at + Vector3(0, 0.05, -0.45), Vector3.UP)
	await _room_frames(4)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(stem + "_room.png")

	var feed := _eye.get_node_or_null("Feed") as SubViewport
	if feed != null:
		var lens := feed.get_texture().get_image()
		if lens != null and not lens.is_empty():
			lens.resize(lens.get_width() * 4, lens.get_height() * 4, Image.INTERPOLATE_NEAREST)
			lens.save_png(stem + "_lens.png")
	var screen := _screen()
	if screen != null:
		screen.convert(Image.FORMAT_RGBA8)
		screen.resize(screen.get_width() * 4, screen.get_height() * 4, Image.INTERPOLATE_NEAREST)
		screen.save_png(stem + "_screen.png")
	print("[gbcam-feed] photos %s_{hand,room,lens,screen}.png" % stem)


func _ok(check: String, cond: bool, detail := "") -> void:
	if cond:
		_pass += 1
		print("[gbcam-feed] PASS  %s" % check)
	else:
		_fail += 1
		print("[gbcam-feed] FAIL  %s%s" % [check, "  — " + detail if not detail.is_empty() else ""])


func _eq(check: String, got: Variant, want: Variant) -> void:
	_ok(check, got == want, "got %s, want %s" % [str(got), str(want)])


func _finish() -> void:
	print("[gbcam-feed] ---- %d passed, %d failed ----" % [_pass, _fail])
	get_tree().quit(1 if _fail > 0 else 0)
