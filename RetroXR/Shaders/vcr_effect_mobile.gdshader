// VCR / VHS screen effect for the RetroXR video player.
// Applied as a ShaderMaterial on the TV screen mesh; samples the live video
// texture produced by VlcPlayer and adds the classic tape look:
// chromatic aberration, scanlines, tape grain, a scrolling tracking band,
// horizontal wobble, color washout and a vignette.
//
// The picture is emitted from behind the shared lit glass surface, so room light
// can catch the faceplate without tinting or dimming the tape image itself.
shader_type spatial;
// cull_back: a screen is only ever seen from its front (see crt_effect.gdshader).
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;

#include "res://Shaders/crt_mobile.gdshaderinc"


#define CRT_FAST
#include "res://Shaders/vcr_effect_surface.gdshaderinc"
