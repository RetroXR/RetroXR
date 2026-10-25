## PassthroughSupport — what this headset can do in passthrough, for the menu.
##
## The OPTIONS page shows a passthrough switch only where it does something. The
## answers come from the OpenXR session, which is up long after the page is
## built, so the page asks again each time it is shown (SpawnMenuOptionsView).
##
## A Quest 2 or Pro has passthrough and Space Setup's room (boxes and planes),
## but no room mesh, no depth and no passthrough camera a game may read; a
## Quest 3 or 3S has all of it. Each is asked of the runtime (OpenXR, or the
## room it read), except the camera: that is Android's Camera2, whose
## passthrough cameras Horizon OS hides until the headset-camera permission is
## granted, so QrScanner answers it by model, as Meta's own samples do.
class_name PassthroughSupport
extends RefCounted

## name -> bool, standing in for a headset. A suite supplies it.
static var override: Dictionary = {}

## A room mesh has been read this run (RealRoom, when its GLOBAL_MESH arrives).
static var mesh_seen := false
## Which way the mesh question was last answered, logged when it changes.
static var _mesh_told := ""


## The view of the real room at all.
static func passthrough() -> bool:
	if override.has("passthrough"):
		return bool(override["passthrough"])
	return XrPassthrough.supported()


## Space Setup's room: "Use Room Data in Passthrough", "Room Scan".
static func room_data() -> bool:
	if override.has("room_data"):
		return bool(override["room_data"])
	const EXT := "OpenXRFbSpatialEntityExtension"
	return passthrough() and Engine.has_singleton(EXT) \
		and bool(Engine.get_singleton(EXT).call("is_spatial_entity_supported"))


## The scanned mesh: "Detailed Room Mesh". Asked of OpenXR where it can be:
## XR_META_spatial_entity_mesh's own query. In vendors 5.1.0 its wrapper is no
## Engine singleton and binds no static get_singleton() (the spatial probe on a
## Quest 3 whose mesh arrived, 2026-10-24; a desktop check, 2026-10-25), so a
## script cannot reach it; then the room is asked instead -- a mesh has been
## read (mesh_seen, set by RealRoom), which is the headset having one.
static func room_mesh() -> bool:
	if override.has("room_mesh"):
		return bool(override["room_mesh"])
	if not room_data():
		return false
	var ext := mesh_extension()
	var answer: bool
	var how: String
	if ext != null and ext.has_method("is_spatial_entity_mesh_supported"):
		answer = bool(ext.call("is_spatial_entity_mesh_supported"))
		how = "openxr"
	else:
		answer = mesh_seen
		how = "room"
	if how != _mesh_told:
		_mesh_told = how
		print("[PassthroughSupport] room mesh supported=%s (asked by %s)" % [answer, how])
	return answer


## The mesh extension's wrapper, or null: an Engine singleton if it is one, else
## what the class's static get_singleton() hands back.
static func mesh_extension() -> Object:
	const CLS := "OpenXRMetaSpatialEntityMeshExtension"
	if Engine.has_singleton(CLS):
		return Engine.get_singleton(CLS)
	if not ClassDB.class_exists(CLS) or not ClassDB.class_has_method(CLS, "get_singleton", true) \
			or not ClassDB.has_method("class_call_static"):
		return null
	var got: Variant = ClassDB.call("class_call_static", CLS, "get_singleton")
	return got as Object if got is Object else null


## Meta's depth: "Real Objects Hide Virtual".
static func depth() -> bool:
	if override.has("depth"):
		return bool(override["depth"])
	var ext := EnvironmentDepth.extension()
	return passthrough() and ext != null and bool(ext.call("is_environment_depth_supported"))


## A passthrough camera a game may read: "Libretro Camera Passthrough Subviewport".
static func camera() -> bool:
	if override.has("camera"):
		return bool(override["camera"])
	return passthrough() and QrScanner.is_available()
