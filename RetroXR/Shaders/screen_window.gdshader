// Screen-window material — shows one rectangular region of a composite
// framebuffer on a full quad. Used wherever a core renders several screens
// into ONE texture and a surface should show just one of them:
//   * a dual-screen handheld's own top/bottom LCDs (DS / 3DS), and
//   * a TV connected to one of that handheld's TOP/BOTTOM video-out cables.
//
// `source_rect` is the UV window (x, y, w, h) into `source_tex`. For
// stereoscopic side-by-side sources (patched azahar: left half = left eye,
// right half = right eye) `eye_shift` moves the sample window right for the
// RIGHT eye — the same VIEW_INDEX trick as vb_stereo.gdshader, so the quad
// shows real per-eye depth in the headset and the left eye's image flat on
// desktop.
//
// A connected RetroTV chains its tube look through here exactly like it does
// with the VCR's tape shader: it flips `crt_enabled` and feeds the shared
// crt_filter uniforms + the OSD texture, instead of wrapping the material.
shader_type spatial;
render_mode cull_disabled, shadows_disabled, fog_disabled;

#include "res://Shaders/crt_filter.gdshaderinc"
#include "res://Shaders/pixel_aa.gdshaderinc"

// filter_linear is REQUIRED by pixel_aa (it does the sub-pixel ramp).

#include "res://Shaders/screen_window_surface.gdshaderinc"
