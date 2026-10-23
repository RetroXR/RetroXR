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
## Needs xr/openxr/extensions/meta/environment_depth and SpatialPermission. Off a
## Quest 3, or without either, acquire() is false and a holder carries on
## without it. A shader that names the globals does not compile where the
## extension is off, so one is loaded only once is_running() is true.
class_name EnvironmentDepth
extends RefCounted

const EXTENSION := "OpenXRMetaEnvironmentDepthExtension"
## Set by the plugin once a depth frame has arrived.
const AVAILABLE_GLOBAL := "META_ENVIRONMENT_DEPTH_AVAILABLE"

## The extension singleton, or a stand-in. A suite supplies one.
static var extension_source := Callable()
## Whether the plugin's globals hold a depth frame. A suite supplies one.
static var available_source := Callable()

const AVAILABLE_CHECK_MS := 500

static var _owners: Dictionary = {}
static var _available := false
static var _available_at_ms := -AVAILABLE_CHECK_MS


static func extension() -> Object:
	if extension_source.is_valid():
		return extension_source.call()
	return Engine.get_singleton(EXTENSION) if Engine.has_singleton(EXTENSION) else null


## The headset has depth and the player has let the game read their room.
static func is_supported() -> bool:
	var ext := extension()
	return ext != null and bool(ext.call("is_environment_depth_supported")) and SpatialPermission.has()


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
	if not is_held():
		return false
	var ext := extension()
	if ext == null or not bool(ext.call("is_environment_depth_started")):
		return false
	if available_source.is_valid():
		return bool(available_source.call())
	# Reading a global back can stall the render thread, so it is asked twice a
	# second at most, whatever asks.
	var now := Time.get_ticks_msec()
	if now - _available_at_ms >= AVAILABLE_CHECK_MS:
		_available_at_ms = now
		_available = AVAILABLE_GLOBAL in RenderingServer.global_shader_parameter_get_list() \
			and bool(RenderingServer.global_shader_parameter_get(AVAILABLE_GLOBAL))
	return _available


## For suites.
static func reset() -> void:
	_owners.clear()
	_available = false
	_available_at_ms = -AVAILABLE_CHECK_MS
	extension_source = Callable()
	available_source = Callable()
