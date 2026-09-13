// VR focus mode's floating screen: one panel of a device's frame, pixel-AA sampled.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

#include "res://Shaders/pixel_aa.gdshaderinc"

// filter_linear is required by pixel_aa.
uniform sampler2D source_tex : source_color, hint_default_black, filter_linear, repeat_disable;
// The panel's part of the frame, (x, y, w, h) in UV.
uniform vec4 source_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform bool flip_h = false;
uniform bool flip_v = false;

void fragment() {
	vec2 uv = vec2(flip_h ? 1.0 - UV.x : UV.x, flip_v ? 1.0 - UV.y : UV.y);
	vec2 at = source_rect.xy + uv * source_rect.zw;
	ALBEDO = clamp(pixel_aa_rect(source_tex, at, source_rect).rgb, 0.0, 1.0);
}
