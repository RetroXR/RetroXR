## XrPassthrough — putting the scene over the headset's view of the real room.
class_name XrPassthrough
extends RefCounted


## Whether the running XR interface has a blend mode that shows passthrough.
static func supported() -> bool:
	var xr := XRServer.primary_interface
	if xr == null or not xr.is_initialized():
		return false
	var modes := xr.get_supported_environment_blend_modes()
	return XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND in modes \
		or XRInterface.XR_ENV_BLEND_MODE_ADDITIVE in modes


## Switch to a passthrough blend mode and a transparent viewport background. False,
## with nothing changed, when the interface offers neither blend mode. The caller
## still has to clear the environment's background to alpha 0.
static func enable(viewport: Viewport) -> bool:
	var xr := XRServer.primary_interface
	if xr == null:
		return false
	var modes := xr.get_supported_environment_blend_modes()
	if XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND in modes:
		xr.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
	elif XRInterface.XR_ENV_BLEND_MODE_ADDITIVE in modes:
		xr.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ADDITIVE
	else:
		return false
	viewport.transparent_bg = true
	return true
