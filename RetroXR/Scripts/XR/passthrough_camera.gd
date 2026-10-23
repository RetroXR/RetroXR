## PassthroughCamera — the headset's own camera, as a picture placed in the room.
##
## Something that looks through the passthrough camera from inside the game (the
## Game Boy Camera's lens, GbCameraEye) holds it here, and while anything holds
## it the RetroXRQr plugin sends luma frames at FEED_SIZE (QrScanner's binding is
## the scan's; this is the feed's, and the plugin lets both share one camera).
##
## A frame is only useful with WHERE it was taken: the camera is fixed to the
## head, the head moves, and a frame arrives tens of milliseconds after it was
## exposed. So every frame carries its age, the head's pose is kept for the last
## half second, and world_from_camera() is the head as it was when the frame was
## exposed, times the lens's pose on the head (LENS_POSE_*, read by the plugin at
## open). project() is the same mapping the backdrop shader makes per pixel, here
## so a suite can check it.
##
## Quest 3 / 3S only, as QrScanner. Everywhere else acquire() is false and a
## holder carries on without it.
class_name PassthroughCamera
extends RefCounted

## What the plugin is asked for: the 1280x960 capture halved. A Game Boy Camera
## takes 128x112 of a 43-degree look, which is ~300 rows of this.
const FEED_SIZE := Vector2i(640, 480)
## How long head poses are kept. A frame older than this has no pose and is not
## shown.
const HISTORY_USEC := 500_000
## A frame older than this is not shown: the camera has stopped or stalled.
const STALE_USEC := 500_000
## Assumed when the camera's clock is not elapsedRealtime and a frame has no age.
const DEFAULT_LATENCY_USEC := 40_000
## Held, and no frame for this long: the plugin gave the feed up (an error ends
## every use of the camera), so it is asked again.
const RETRY_USEC := 5_000_000
## Turns a Camera2 optical frame (x right, y down, z out of the lens) into a
## Godot camera's (x right, y up, looking down -z): half a turn about x.
const OPTICAL_TO_GODOT := Basis(Vector3(1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, -1))

## The plugin, or a stand-in. A suite supplies one.
static var plugin_source := Callable()
## The head's global transform now, or null. A suite supplies one; otherwise the
## root viewport's current camera, which in XR is the XRCamera3D.
static var head_source := Callable()
## Microseconds, as Time.get_ticks_usec(). A suite supplies one.
static var clock_source := Callable()

static var _owners: Dictionary = {}
static var _plugin: Object = null
static var _receiver: _Receiver = null
static var _texture: ImageTexture = null
static var _frame_usec := -1
static var _asked_usec := -1
## [usec, Transform3D] pairs, oldest first.
static var _history: Array = []
static var _sampled_frame := -1
static var _info: Dictionary = {}
static var _lens := Transform3D.IDENTITY
static var _intrinsics := Vector4.ZERO


## Plugin signals arrive on the camera's thread; this takes them there and hands
## each frame to the main thread. A static Callable cannot be connected to a
## plugin signal on every Godot release, an object's method can.
class _Receiver:
	extends RefCounted

	func on_frame(luma: PackedByteArray, width: int, height: int, age_us: int) -> void:
		PassthroughCamera._accept_frame.call_deferred(
			luma, width, height, age_us, PassthroughCamera.now_usec())


static func plugin() -> Object:
	if plugin_source.is_valid():
		return plugin_source.call()
	return QrScanner.singleton()


## Whether `p` has `method`. An Android plugin is a JNISingleton, whose Java
## methods has_method() does not see (it answers false for every one of them);
## has_java_method() does. A plugin built before the feed existed has neither.
static func plugin_has(p: Object, method: String) -> bool:
	if p.has_method(method):
		return true
	return p.has_method("has_java_method") and bool(p.call("has_java_method", method))


static func now_usec() -> int:
	return int(clock_source.call()) if clock_source.is_valid() else Time.get_ticks_usec()


## Whether the room the player sees is the real one: the headset's passthrough
## with the scene blended over it (the passthrough room, focus mode).
static func room_is_real() -> bool:
	var xr := XRServer.primary_interface
	return xr != null and xr.is_initialized() \
		and xr.environment_blend_mode == XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND


## Start the feed for `owner`, if it is not already running for someone. False
## when there is no plugin to run it.
static func acquire(owner: Object) -> bool:
	var id := owner.get_instance_id()
	if _owners.has(id):
		return true
	var p := plugin()
	if p == null or not plugin_has(p, "startFeed"):
		return false
	_owners[id] = true
	if _owners.size() == 1:
		_plugin = p
		_receiver = _Receiver.new()
		p.connect("camera_frame", _receiver.on_frame)
		_start()
	return true


## Safe to call for an owner that holds nothing.
static func release(owner: Object) -> void:
	if not _owners.erase(owner.get_instance_id()) or not _owners.is_empty():
		return
	if _plugin != null:
		if _receiver != null and _plugin.is_connected("camera_frame", _receiver.on_frame):
			_plugin.disconnect("camera_frame", _receiver.on_frame)
		_plugin.stopFeed()
	_plugin = null
	_receiver = null
	_texture = null
	_frame_usec = -1
	_history.clear()


static func is_held() -> bool:
	return not _owners.is_empty()


## Once a frame by any holder (the second call in a frame does nothing): keeps
## the head's history, and asks again for a feed that stopped coming.
static func tick() -> void:
	var frame := Engine.get_process_frames()
	if frame == _sampled_frame and not clock_source.is_valid():
		return
	_sampled_frame = frame
	var now := now_usec()
	var head: Variant = head_source.call() if head_source.is_valid() else _xr_head()
	if head is Transform3D:
		_history.append([now, head])
	while _history.size() > 1 and now - int(_history[0][0]) > HISTORY_USEC:
		_history.pop_front()
	if is_held() and now - maxi(_frame_usec, _asked_usec) > RETRY_USEC:
		_start()


## Whether there is a frame recent enough to show.
static func has_frame() -> bool:
	return _texture != null and _frame_usec >= 0 and now_usec() - _frame_usec < STALE_USEC


## The latest frame, FORMAT_L8, top row first. Null before the first.
static func texture() -> ImageTexture:
	return _texture


## The latest frame's camera in the world, or null when its moment is not in the
## head's history (or nothing is known about the lens yet).
static func world_from_camera() -> Variant:
	if _info.is_empty() or _frame_usec < 0:
		return null
	var head: Variant = head_at(_frame_usec)
	if head == null:
		return null
	return (head as Transform3D) * _lens


## fu, fv, cu, cv: x and y over z to the frame's 0..1 UVs (see intrinsics_uv).
static func intrinsics() -> Vector4:
	return _intrinsics


## What the plugin read when the camera opened. Set by a suite.
static func set_info(info: Dictionary) -> void:
	_info = info
	_lens = lens_from_head(info)
	_intrinsics = intrinsics_uv(info)


## The head at `usec`, between the two poses kept either side of it; the nearest
## end when it is outside them, null when none is kept.
static func head_at(usec: int) -> Variant:
	if _history.is_empty():
		return null
	if usec <= int(_history[0][0]):
		return _history[0][1]
	for i in range(1, _history.size()):
		var t1 := int(_history[i][0])
		if usec <= t1:
			var t0 := int(_history[i - 1][0])
			var w := 0.0 if t1 == t0 else float(usec - t0) / float(t1 - t0)
			return (_history[i - 1][1] as Transform3D).interpolate_with(_history[i][1], w)
	return _history[-1][1]


## The lens on the head, as a Godot camera transform: it looks down its -Z. The
## pose is Camera2's optical frame (z out of the lens), turned half round x.
static func lens_from_head(info: Dictionary) -> Transform3D:
	var q: PackedFloat32Array = info.get("pose_rotation", PackedFloat32Array())
	var t: PackedFloat32Array = info.get("pose_translation", PackedFloat32Array())
	var basis := Basis(Quaternion(q[0], q[1], q[2], q[3]).normalized()) if q.size() == 4 else Basis()
	var origin := Vector3(t[0], t[1], t[2]) if t.size() == 3 else Vector3.ZERO
	return Transform3D(basis * OPTICAL_TO_GODOT, origin)


## The calibration (fx, fy, cx, cy in active-array pixels) as it maps onto a
## frame: the frame is the active array scaled to fit and centered-cropped to the
## capture's aspect (1280x960 out of a square sensor), so the crop is undone and
## the pixels become 0..1 UVs.
static func intrinsics_uv(info: Dictionary) -> Vector4:
	var k: PackedFloat32Array = info.get("intrinsics", PackedFloat32Array())
	var area: PackedInt32Array = info.get("active_array", PackedInt32Array())
	var capture: PackedInt32Array = info.get("capture_size", PackedInt32Array())
	if k.size() < 4 or area.size() < 4 or capture.size() < 2:
		return Vector4.ZERO
	var sensor := Vector2(area[2] - area[0], area[3] - area[1])
	var scale := Vector2(capture[0], capture[1]) / sensor
	scale /= maxf(scale.x, scale.y)
	var crop_size := sensor * scale
	var crop_at := sensor * (Vector2.ONE - scale) * 0.5
	return Vector4(k[0] / crop_size.x, k[1] / crop_size.y,
		(k[2] - crop_at.x) / crop_size.x, (k[3] - crop_at.y) / crop_size.y)


## Where `world_point` falls in a frame taken from `world_from_cam`, in 0..1 UVs
## with v down. (-1, -1) when it is behind the lens. The backdrop shader's
## mapping, the same steps.
static func project(world_point: Vector3, world_from_cam: Transform3D, k: Vector4) -> Vector2:
	var p := world_from_cam.affine_inverse() * world_point
	var z := -p.z
	if z <= 0.0001:
		return Vector2(-1, -1)
	return Vector2(k.x * p.x / z + k.z, k.y * -p.y / z + k.w)


## Where a ray from `origin` along `dir` (world) meets the room, taken to be a
## sphere of `radius` round the headset camera at `world_from_cam`; null when it
## meets it nowhere ahead. The sphere stays where the head put it, so a lens held
## out toward it covers less of it: the picture zooms as the cartridge is moved
## away from the face. The backdrop shader's steps.
static func surface_point(origin: Vector3, dir: Vector3, world_from_cam: Transform3D, radius: float) -> Variant:
	var o := origin - world_from_cam.origin
	var d := dir.normalized()
	var b := o.dot(d)
	var disc := b * b - (o.dot(o) - radius * radius)
	if disc < 0.0:
		return null
	var t := -b + sqrt(disc)
	return origin + d * t if t > 0.0 else null


## Back to nothing held and nothing known. For suites.
static func reset() -> void:
	for id: int in _owners.keys():
		var o := instance_from_id(id)
		if o != null:
			release(o)
	_owners.clear()
	_plugin = null
	_receiver = null
	_texture = null
	_frame_usec = -1
	_asked_usec = -1
	_history.clear()
	_sampled_frame = -1
	_info = {}
	_lens = Transform3D.IDENTITY
	_intrinsics = Vector4.ZERO


static func _start() -> void:
	_asked_usec = now_usec()
	if _plugin != null:
		_plugin.startFeed(FEED_SIZE.x, FEED_SIZE.y)


static func _accept_frame(luma: PackedByteArray, width: int, height: int, age_us: int, received_usec: int) -> void:
	# Released while the frame was on its way.
	if not is_held() or width <= 0 or height <= 0 or luma.size() != width * height:
		return
	var image := Image.create_from_data(width, height, false, Image.FORMAT_L8, luma)
	if _texture == null or _texture.get_size() != Vector2(width, height):
		_texture = ImageTexture.create_from_image(image)
	else:
		_texture.update(image)
	_frame_usec = received_usec - (age_us if age_us >= 0 else DEFAULT_LATENCY_USEC)
	if _info.is_empty() and _plugin != null and plugin_has(_plugin, "getCameraInfo"):
		var info: Dictionary = _plugin.getCameraInfo()
		if not info.is_empty():
			set_info(info)


static func _xr_head() -> Variant:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	var camera := tree.root.get_camera_3d()
	return camera.global_transform if camera != null else null
