## GbCameraEye — the Game Boy Camera's lens, as a camera in the room.
##
## A node just outside the glass of the cartridge's ball (GbCameraShell.BODY),
## looking the way the lens does. While the cartridge is in a running machine
## whose core has STARTED its camera, the room is drawn from here into a small
## viewport and each picture is handed to that core (Libretro.PushCameraFrame),
## which is what the game shows in its viewfinder and photographs.
##
## The peripheral asks its machine, as GcMicrophone does: a cartridge holds no
## reference to what it is seated in, and RetroSystem has no signal for a core
## starting. So every frame it asks "am I in a machine's own slot, is it on, has
## its core started a camera", which is three calls when the answer is no.
##
## It does not film for as long as the cartridge is in: only while the core says
## its camera is started (Libretro.IsCameraActive). But mGBA starts it as the
## game loads and stops it as the game unloads, and the interface has no way to
## say "a photograph is being asked for", so in practice the room is drawn a
## second time for as long as a Game Boy Camera is switched on, viewfinder or
## album. Hence the rate, and the viewport's settings.
##
## A second pass over the room costs its draw calls before it costs pixels, and a
## picture read back is a GPU round trip, so both are rationed: one eye arms a
## frame, the pass is taken the frame AFTER it was drawn (never waited for), and
## pictures are taken so many a SECOND, not one every so many frames -- a desktop
## window runs at whatever its monitor does, and the first probe run pushed 2947
## pictures at a core that could take 2110. What it costs on a headset is not
## measured yet.
##
## The lens looks the way its body's aperture is bored. The game's stand-in's goes
## straight out of the ball; the real one's is raised 7.8 degrees above square to
## the axle (the laser scan of nintendo/gb/camera), which a body says in
## tilt_degrees.
##
## In passthrough the room is the real one, so the picture is too: while the
## player sees the headset's view of their room, the lens holds the headset's
## camera (PassthroughCamera) and draws its frame behind the scene, reprojected
## to where the lens points (Shaders/gb_camera_passthrough). The headset camera
## sees only what is in front of the face, so a lens turned round or aimed away
## sees black there. Quest 3 / 3S, with the headset-camera permission, which is
## asked for the first time a camera films in passthrough; without it, or
## anywhere else, the lens films the scene as before.
class_name GbCameraEye
extends Node3D

## This node's basis under KnobPivot, by COLUMNS. The lens is the pivot's -Y and
## a Camera3D looks along its own -Z, so the camera's Z is the pivot's Y. Its up
## is the pivot's Z, which is the axle and so the cartridge's +Y however the ball
## is turned. Set from here and not in the scene, where a basis is read by rows.
const LENS_BASIS := Basis(Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0))

## Top to bottom, in degrees. An ESTIMATE: Nintendo published no angle and no
## source found gives the focal length. One write-up (thephotoforum's Game Boy
## Camera retrospective) measured the sensor at 3.6 mm and suspected the lens of
## being a 35 mm-equivalent 35, about 4.1 mm; the game reads 112 rows of 123.
const FOV_DEGREES := 43.0
## Past the glass and the rim of the bezel, so the ball is never in its own shot.
const NEAR := 0.02
const FAR := 100.0

## How far the lens looks up from square to the axle, toward the axle's top: the
## real aperture's 7.8, the stand-in's 0.
@export var tilt_degrees := 0.0

## Pictures a second at most. The game's own viewfinder redraws a few times a
## second, so neither is slow to look at; 12 is one frame in six on a Quest at 72.
## Never more than every other frame, whatever these say: a pass is armed on one
## frame and taken on the next.
const RATE_MOBILE := 12.0
const RATE_DESKTOP := 30.0

## The layer the lens camera leaves out and every other camera keeps, which is how
## the backdrop shader tells the lens from the rest (bit 18, layer 19). Nothing
## is put on it.
const LENS_ONLY_LAYER := 1 << 18
## Seconds between asking whether the room is real. Permissions are a JNI call.
const REAL_CHECK_PERIOD := 1.0
const BACKDROP_SHADER := preload("res://Shaders/gb_camera_passthrough.gdshader")
## Loaded, never preloaded: see backdrop_material().
const BACKDROP_DEPTH_SHADER := "res://Shaders/gb_camera_passthrough_depth.gdshader"
## How far the room is taken to be from the headset camera: a sphere it stays on
## while the cartridge moves, so holding the lens out toward it zooms in (half a
## meter nearer is half as much again). What is nearer or farther than this is
## drawn a little off, the more so the farther the lens is from the face.
const BACKDROP_RADIUS := 1.5

## The machine whose own slot holds the cartridge, or null. A suite supplies one.
var machine_source := Callable()
## The picture for a pass of the given size, or null when there is none. A suite
## supplies a still; the room's comes from the viewport.
var picture_source := Callable()
## Whether to film the real room, or null to ask the headset. A suite supplies one.
var real_source := Callable()
## "depth" or "sphere", or null to read AppPrefs. A suite supplies one.
var backdrop_mode_source := Callable()

## The process frame some eye last armed its viewport on: one a frame, so two
## cameras in a room never draw it twice more in the same one.
static var _armed_on_frame := -1
## The headset-camera permission is asked for once a run, not once a camera.
static var _asked_permission := false

var _cartridge: RetroCartridge = null
var _viewport: SubViewport = null
var _camera: Camera3D = null
var _armed := false
## Seconds until the next picture may be taken.
var _wait := 0.0
var _feeding: Object = null
var _backdrop: MeshInstance3D = null
var _sphere_material: ShaderMaterial = null
var _depth_material: ShaderMaterial = null
var _holding_real := false
var _real_check_wait := 0.0


func _ready() -> void:
	basis = Basis(Vector3.RIGHT, deg_to_rad(-tilt_degrees)) * LENS_BASIS
	_cartridge = _find_cartridge()
	# A body with no cartridge round it is a model on show -- the warmer's, a
	# probe's -- and films nothing.
	set_process(_cartridge != null)
	# Two cameras switched on together do not take their pictures together.
	_wait = randf() * _period()


func _exit_tree() -> void:
	_feeding = null
	_hold_real(false)


func _process(delta: float) -> void:
	var lib := feed_target()
	if lib != _feeding:
		_feeding = lib
		_armed = false
		_real_check_wait = 0.0
		if lib == null:
			_rest_viewport()
	_real_check_wait -= delta
	if lib == null:
		_hold_real(false)
	elif _real_check_wait <= 0.0:
		_real_check_wait = REAL_CHECK_PERIOD
		_hold_real(wants_real())
		# Room data, or the depth backdrop, switched on (or back on) while filming:
		# depth is asked for again, as it is when filming starts; the fixed
		# sphere chosen instead, it is let go.
		_hold_depth(_holding_real and uses_depth())
	if _holding_real:
		PassthroughCamera.tick()
	if lib == null:
		return
	_wait -= delta
	var size: Vector2i = lib.GetCameraFrameSize()
	if size.x <= 0 or size.y <= 0:
		return
	var picture := _next_picture(size)
	if picture != null:
		push_picture(lib, picture, size)


## The core to hand pictures to right now, or null.
func feed_target() -> Object:
	var machine: Object = machine_source.call() if machine_source.is_valid() \
		else _seated_machine()
	if machine == null or not bool(machine.get("is_powered_on")):
		return null
	var lib: Object = machine.get_libretro_node()
	# Asked of the object and not of ClassDB once: a library built before the
	# camera existed (an Android .so left behind by a Windows-only rebuild) says
	# so only when the missing method is CALLED.
	if lib == null or not lib.has_method("IsCameraActive") or not lib.IsCameraActive():
		return null
	return lib


## Whether the lens films the real room: the player is in passthrough, on a
## headset whose camera a game may use, and has allowed it. The first time the
## answer is no for want of the permission alone, it is asked for.
func wants_real() -> bool:
	if real_source.is_valid():
		return bool(real_source.call())
	if not PassthroughCamera.room_is_real() or not QrScanner.is_available():
		return false
	if QrScanner.has_permission():
		return true
	if not _asked_permission:
		_asked_permission = true
		QrScanner.request_permission()
	return false


## Whether this lens holds the headset camera now.
func is_filming_real() -> bool:
	return _holding_real


func _hold_real(want: bool) -> void:
	if want == _holding_real:
		return
	if want:
		_holding_real = PassthroughCamera.acquire(self)
		# Real surfaces where Meta's depth can run; the sphere where it cannot,
		# or where the player chose it.
		_hold_depth(_holding_real and uses_depth())
	else:
		PassthroughCamera.release(self)
		_hold_depth(false)
		_holding_real = false
		if _backdrop != null:
			_backdrop.visible = false


func _hold_depth(want: bool) -> void:
	if want and not EnvironmentDepth.holds(self):
		EnvironmentDepth.acquire(self)
	elif not want and EnvironmentDepth.holds(self):
		EnvironmentDepth.release(self)


## General > "Libretro Camera Passthrough Subviewport" (AppPrefs.libretro_camera_backdrop):
## "sphere", the default, takes the room to be BACKDROP_RADIUS from the headset
## camera everywhere and asks for no depth; "depth" finds the real room's
## surfaces with Meta's depth.
func uses_depth() -> bool:
	if backdrop_mode_source.is_valid():
		return str(backdrop_mode_source.call()) == "depth"
	var prefs := get_node_or_null("/root/AppPrefs") if is_inside_tree() else null
	return prefs != null and str(prefs.get("libretro_camera_backdrop")) == "depth"


## Hand `picture` to `lib` as a core takes one: exactly `size`, RGBA8, top row
## first. The picture is converted in place.
func push_picture(lib: Object, picture: Image, size: Vector2i) -> bool:
	if picture == null or picture.is_empty():
		return false
	# Never the room's own, which is drawn at this size. mGBA crops a larger
	# picture rather than scaling it, so one is never passed on as it came.
	if picture.get_size() != size:
		picture.resize(size.x, size.y, Image.INTERPOLATE_BILINEAR)
	if picture.get_format() != Image.FORMAT_RGBA8:
		picture.convert(Image.FORMAT_RGBA8)
	return bool(lib.PushCameraFrame(picture.get_data(), size.x, size.y))


## Its OWN slot only. A Super Game Boy's bay and a Transfer Pak's hold a Game Boy
## cartridge too, under parents that run no core of their own.
func _seated_machine() -> Object:
	if _cartridge == null or not _cartridge.is_picked_up():
		return null
	var zone := _cartridge.get_picked_up_by() as XRToolsSnapZone
	if zone == null:
		return null
	var machine := zone.get_parent()
	if machine == null or not machine.has_method("get_libretro_node") \
			or not machine.has_method("get_snapped_cartridge") \
			or machine.get_snapped_cartridge() != _cartridge:
		return null
	return machine


func _next_picture(size: Vector2i) -> Image:
	if picture_source.is_valid():
		if _wait > 0.0:
			return null
		_wait = _period()
		return picture_source.call(size)
	if not _can_draw():
		return null
	# Armed on an earlier frame, so drawn by now: taken, not waited for.
	if _armed:
		_armed = false
		return _viewport.get_texture().get_image()
	# Set, not added to: a hitch is not made up for with a burst of passes.
	if _wait <= 0.0 and _armed_on_frame != Engine.get_process_frames():
		_wait = _period()
		_arm(size)
	return null


func _arm(size: Vector2i) -> void:
	_ensure_viewport()
	if _viewport.size != size:
		_viewport.size = size
	_aim()
	_place_backdrop()
	# Disabled first: UPDATE_ONCE is consumed by the renderer, but assigning the
	# same enum again is not a reliable dirty signal on every backend.
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_armed = true
	_armed_on_frame = Engine.get_process_frames()


## Put the camera where this node is. A viewport hands no transform down to what
## is under it, so it does not follow the ball by itself. Rebuilt from the way the
## lens looks and its up, never copied: a body fitted to its cartridge's size per
## axis carries a scale, which would shear the picture and bend the look aside.
func _aim() -> void:
	var lens := global_transform.basis
	_camera.global_transform = Transform3D(
		Basis.looking_at(-lens.z, lens.y), global_transform.origin)


## The lens's own viewport, sharing the room's world, made the first time a core
## asks for a picture. The Camera3D goes UNDER it: anywhere else it would be a
## camera of the player's own viewport, and the first one there becomes current.
func _ensure_viewport() -> void:
	if _viewport != null:
		return
	_viewport = SubViewport.new()
	_viewport.name = "Feed"
	# Never UPDATE_ALWAYS: it draws for as long as it exists, and hangs a headless
	# run outright.
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	# Both are the root viewport's to choose, and a picture this size, dithered to
	# four greys, shows neither. The 3D scaling is left alone on purpose.
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.positional_shadow_atlas_size = 0
	_viewport.gui_disable_input = true
	_camera = Camera3D.new()
	_camera.name = "Lens"
	_camera.fov = FOV_DEGREES
	_camera.near = NEAR
	_camera.far = FAR
	# Posed from _process just before it is drawn. Interpolated between physics
	# ticks it would be drawn where the lens WAS, and the engine says so.
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# Everything but the one layer that tells the backdrop it is the lens's.
	_camera.cull_mask = 0xFFFFF & ~LENS_ONLY_LAYER
	_viewport.add_child(_camera)
	add_child(_viewport)
	# The flag: make_current() does not work inside a SubViewport.
	_camera.current = true


## Show the headset camera's latest frame behind the scene, as it was where it
## was taken, or nothing when there is no such frame.
func _place_backdrop() -> void:
	var pose: Variant = PassthroughCamera.world_from_camera() \
		if _holding_real and PassthroughCamera.has_frame() else null
	if pose == null:
		if _backdrop != null:
			_backdrop.visible = false
		return
	if _backdrop == null:
		_backdrop = MeshInstance3D.new()
		_backdrop.name = "Backdrop"
		var quad := QuadMesh.new()
		quad.size = Vector2(2, 2)
		_backdrop.mesh = quad
		# The shader puts it over the whole view, wherever the mesh "is".
		_backdrop.custom_aabb = AABB(Vector3.ONE * -1000.0, Vector3.ONE * 2000.0)
		_backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_backdrop.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		_camera.add_child(_backdrop)
	var material := backdrop_material()
	_backdrop.material_override = material
	material.set_shader_parameter("feed", PassthroughCamera.texture())
	material.set_shader_parameter("camera_from_world", Projection((pose as Transform3D).affine_inverse()))
	material.set_shader_parameter("intrinsics", PassthroughCamera.intrinsics())
	material.set_shader_parameter("radius", BACKDROP_RADIUS)
	if material == _depth_material:
		material.set_shader_parameter("tracking_from_world",
			Projection(PassthroughCamera.tracking_from_world()))
	_backdrop.visible = true


## The depth backdrop while Meta's depth is running for this lens, the sphere one
## otherwise. The depth shader names the plugin's globals and compiles only where
## they exist, so it is loaded the first time depth is running, never before.
func backdrop_material() -> ShaderMaterial:
	if _holding_real and uses_depth() and EnvironmentDepth.is_running():
		if _depth_material == null:
			_depth_material = ShaderMaterial.new()
			_depth_material.shader = load(BACKDROP_DEPTH_SHADER) as Shader
		return _depth_material
	if _sphere_material == null:
		_sphere_material = ShaderMaterial.new()
		_sphere_material.shader = BACKDROP_SHADER
	return _sphere_material


func _rest_viewport() -> void:
	if _viewport != null:
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


## Headless has the dummy renderer: a correctly sized picture of nothing.
func _can_draw() -> bool:
	return DisplayServer.get_name() != "headless" \
		and RenderingServer.get_rendering_device() != null


## Seconds from one picture to the next.
func _period() -> float:
	return 1.0 / (RATE_MOBILE if RenderingServer.get_current_rendering_method() == "mobile"
		else RATE_DESKTOP)


func _find_cartridge() -> RetroCartridge:
	var node := get_parent()
	while node != null:
		if node is RetroCartridge:
			return node as RetroCartridge
		node = node.get_parent()
	return null
