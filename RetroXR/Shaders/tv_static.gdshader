// Analog snow for RetroXR TV screens — what the set shows on the TV input when
// there is nothing to show: no channel list, an unreachable tuner, a channel
// that will not decode.
//
// Generated rather than sampled, so it costs no texture and never repeats. The
// OSD is composited in exactly as crt_effect.gdshader does it, which is what
// puts the error text on the tube; RetroTV feeds osd_tex/osd_enabled to whatever
// shader is on the screen, so declaring the same two uniforms is the whole
// contract. Runs through the same crt_apply_full stage, so static curves,
// scanlines and blooms like a real picture.
shader_type spatial;
// cull_back: a screen is only ever seen from its front (see crt_effect.gdshader).
render_mode cull_back, shadows_disabled, fog_disabled;

#include "res://Shaders/crt_filter.gdshaderinc"


#include "res://Shaders/tv_static_surface.gdshaderinc"
