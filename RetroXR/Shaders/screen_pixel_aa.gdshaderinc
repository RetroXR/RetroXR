// The plain pixel-AA screen colour, shared by screen_pixel_aa.gdshader (self-lit)
// and screen_pixel_aa_lit.gdshader (lit by the room). The includer declares the
// render_mode; this is the colour alone.

#include "res://Shaders/pixel_aa.gdshaderinc"

// filter_linear is REQUIRED by pixel_aa (it does the sub-pixel ramp).
uniform sampler2D source_tex : source_color, filter_linear, repeat_disable;

vec3 screen_pixel_aa(vec2 uv) {
	return clamp(pixel_aa(source_tex, uv).rgb, 0.0, 1.0);
}
