## EnvironmentDepth — Meta's live depth of the real room, for whoever wants it.
##
## The Quest 3 measures how far away what is in front of it is, a few times a
## second, and the vendors plugin (OpenXRMetaEnvironmentDepthExtension) hands it
## to every shader as global parameters: META_ENVIRONMENT_DEPTH_TEXTURE, one layer
## an eye, and the matrices from the tracking space to each eye's depth. Two
## things look through it: a Game Boy Camera's lens filming the real room
## (GbCameraEye, so its picture meets real surfaces) and, when the player wants
## it, the occlusion node over their own eyes (RealRoom). Depth runs while
## anything holds it.
##
## Needs xr/openxr/extensions/meta/environment_depth and SpatialPermission.usable()
## (the player's "Use Room Data in Passthrough", and their consent). Off a
## Quest 3, or without either, acquire() is false and a holder carries on
## without it. A shader that names the globals does not compile where the
## extension is off, so one is loaded only once is_running() is true.
class_name EnvironmentDepth
extends RefCounted

const EXTENSION := "OpenXRMetaEnvironmentDepthExtension"
## The project declares the plugin's globals here (the editor writes them when
## environment_depth is switched on there). Without them the plugin fails to set
## them every frame, and on a Quest 3 the app hung coming back from the consent
## dialog (spatial probe, 2026-10-24); a shader naming them would not compile.
const DECLARED_SETTING := "shader_globals/META_ENVIRONMENT_DEPTH_TEXTURE"
## How long after starting before depth is taken to be there. The probe saw its
## first frames within a frame or two; reading the plugin's
## META_ENVIRONMENT_DEPTH_AVAILABLE back is an editor-only call that Godot warns
## "can severely damage performance", so the time is used instead.
const WARMUP_MS := 500

## The extension singleton, or a stand-in. A suite supplies one.
static var extension_source := Callable()
## Whether a depth frame is there, or null to go by WARMUP_MS. A suite supplies one.
static var available_source := Callable()

static var _owners: Dictionary = {}
static var _started_ms := -1


static func extension() -> Object:
	if extension_source.is_valid():
		return extension_source.call()
	return Engine.get_singleton(EXTENSION) if Engine.has_singleton(EXTENSION) else null


## The headset has depth, and the player wants their room used and has let the
## game read it.
static func is_supported() -> bool:
	var ext := extension()
	return ext != null and bool(ext.call("is_environment_depth_supported")) and SpatialPermission.usable() \
		and (extension_source.is_valid() or ProjectSettings.has_setting(DECLARED_SETTING))


static func holds(owner: Object) -> bool:
	return _owners.has(owner.get_instance_id())


## Stop depth for every holder at once: the player switched room data off. A
## holder that releases afterwards releases nothing; one that still wants depth
## asks again (GbCameraEye does, once a second).
static func drop_all() -> void:
	if _owners.is_empty():
		return
	_owners.clear()
	var ext := extension()
	if ext != null and bool(ext.call("is_environment_depth_started")):
		ext.call("stop_environment_depth")


## Start depth for `owner` if no one has. False when it cannot run here.
static func acquire(owner: Object) -> bool:
	var id := owner.get_instance_id()
	if _owners.has(id):
		return true
	if not is_supported():
		return false
	_owners[id] = true
	if _owners.size() == 1:
		var ext := extension()
		if not bool(ext.call("is_environment_depth_started")):
			ext.call("start_environment_depth")
		_started_ms = Time.get_ticks_msec()
	return true


## Safe for an owner that holds nothing.
static func release(owner: Object) -> void:
	if not _owners.erase(owner.get_instance_id()) or not _owners.is_empty():
		return
	var ext := extension()
	if ext != null and bool(ext.call("is_environment_depth_started")):
		ext.call("stop_environment_depth")


static func is_held() -> bool:
	return not _owners.is_empty()


## Held, started, and a depth frame has arrived: a shader may sample it now.
static func is_running() -> bool:
	if not is_held() or not SpatialPermission.usable():
		return false
	var ext := extension()
	if ext == null or not bool(ext.call("is_environment_depth_started")):
		return false
	if available_source.is_valid():
		return bool(available_source.call())
	return _started_ms >= 0 and Time.get_ticks_msec() - _started_ms >= WARMUP_MS


## For suites.
static func reset() -> void:
	_owners.clear()
	_started_ms = -1
	extension_source = Callable()
	available_source = Callable()
