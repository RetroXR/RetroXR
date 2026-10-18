// The cabinet monitor: the core's picture, shaped to the glass.
//
// The picture is fitted INSIDE the tube by `fit_scale`, the share of each axis it
// covers, which the cabinet sets from the shape the core reports (ArcadeScreenModule
// reads Libretro.GetVideoGeometry). So a vertical game on a landscape glass is
// pillarboxed in black, and a 384x224 CPS1 frame fills a 4:3 tube whatever its pixel
// ratio -- arcade pixels were never square. A light scanline pass sits on top; the
// full TV tube (crt_effect.gdshader) is tied to RetroTV's derived uniforms and is
// not reused here.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled, fog_disabled;

#include "res://Shaders/pixel_aa.gdshaderinc"

// filter_linear is REQUIRED by pixel_aa (it does the sub-pixel ramp).
uniform sampler2D source_tex : source_color, filter_linear, repeat_disable;
uniform vec2 fit_scale = vec2(1.0, 1.0);
// How dark the gap between two source lines goes, 0 = none. Lines per picture
// height come from the texture, so a 240-line game gets 240 scanlines.
uniform float scanlines : hint_range(0.0, 1.0) = 0.22;
// Glass brightness, so the monitor reads as lit from within.
uniform float gain : hint_range(0.5, 2.0) = 1.1;

void fragment() {
	vec2 fuv = (UV - 0.5) / fit_scale + 0.5;
	vec3 c = vec3(0.0);
	if (fuv.x >= 0.0 && fuv.x <= 1.0 && fuv.y >= 0.0 && fuv.y <= 1.0) {
		c = clamp(pixel_aa(source_tex, fuv).rgb, 0.0, 1.0);
		float lines = float(textureSize(source_tex, 0).y);
		float row = fract(fuv.y * lines);
		c *= 1.0 - scanlines * (0.5 - 0.5 * cos(6.2831853 * row));
	}
	ALBEDO = clamp(c * gain, 0.0, 1.0);
}
