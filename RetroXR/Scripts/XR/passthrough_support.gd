## PassthroughSupport — what this headset can do in passthrough, for the menu.
##
## The OPTIONS page shows a passthrough switch only where it does something. The
## answers come from the OpenXR session, which is up long after the page is
## built, so the page asks again each time it is shown (SpawnMenuOptionsView).
##
## A Quest 2 or Pro has passthrough and Space Setup's room (boxes and planes),
## but no room mesh, no depth and no passthrough camera a game may read; a
## Quest 3 or 3S has all of it.
class_name PassthroughSupport
extends RefCounted

## name -> bool, standing in for a headset. A suite supplies it.
static var override: Dictionary = {}


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


## The scanned mesh: "Detailed Room Mesh". Asked by model, as QrScanner's camera
## is: the mesh extension reports no singleton even on a Quest 3 whose mesh
## arrived (spatial probe, 2026-10-24).
static func room_mesh() -> bool:
	if override.has("room_mesh"):
		return bool(override["room_mesh"])
	return room_data() and QrScanner.is_available()


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
