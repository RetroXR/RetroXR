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
// The part of the picture to show, (x, y, width, height) as fractions of the frame, y down. A game of two screens in one frame (Silent
// Scope's monitor and its scope) shows each of them cut out of it; the whole frame is (0, 0, 1, 1).
uniform vec4 view_rect = vec4(0.0, 0.0, 1.0, 1.0);
// How dark the gap between two source lines goes, 0 = none. Lines per picture
// height come from the texture, so a 240-line game gets 240 scanlines.
uniform float scanlines : hint_range(0.0, 1.0) = 0.22;
// Glass brightness, so the monitor reads as lit from within.
uniform float gain : hint_range(0.5, 2.0) = 1.1;
// A rifle's DIGITAL scope (the lens of a game that has no second screen to show in it): 1 draws what looking through a scope is -- a round field of view whose rim
// darkens, and a reticle: a cross with a gap in the middle, mil dots along both arms and a dot at the centre. Without it the lens is a flat patch of the monitor's own
// picture and nothing says it magnifies. `quad_aspect` is the lens quad's width over its height, so the circle is a circle.
uniform float scope_reticle : hint_range(0.0, 1.0) = 0.0;
uniform float quad_aspect = 1.0;

// The reticle's marks at half-width `w` (all in units of the quad's height, the middle the origin): the arms with a gap in the middle, the mil dots, the centre dot.
float reticle(vec2 p, float w) {
	vec2 a = abs(p);
	float arms = max(step(a.y, w) * step(0.035, a.x) * step(a.x, 0.55), step(a.x, w) * step(0.035, a.y) * step(a.y, 0.50));
	float dots = step(length(p), 0.006 + w);
	for (int i = 1; i <= 5; i++) {
		float d = float(i) * 0.08;
		dots = max(dots, step(length(vec2(a.x - d, a.y)), 0.007 + w));
		dots = max(dots, step(length(vec2(a.x, a.y - d)), 0.007 + w));
	}
	return max(arms, dots);
}

void fragment() {
	vec2 fuv = (UV - 0.5) / fit_scale + 0.5;
	vec3 c = vec3(0.0);
	if (fuv.x >= 0.0 && fuv.x <= 1.0 && fuv.y >= 0.0 && fuv.y <= 1.0) {
		vec2 suv = view_rect.xy + fuv * view_rect.zw;
		// Confined to the window: the neighbouring screen's edge row must not enter the filter.
		c = clamp(pixel_aa_rect(source_tex, suv, view_rect).rgb, 0.0, 1.0);
		float lines = float(textureSize(source_tex, 0).y);
		float row = fract(suv.y * lines);
		c *= 1.0 - scanlines * (0.5 - 0.5 * cos(6.2831853 * row));
	}
	vec3 lit = clamp(c * gain, 0.0, 1.0);
	if (scope_reticle > 0.0) {
		vec2 p = (UV - 0.5) * vec2(quad_aspect, 1.0);
		float r = length(p);
		// The round field of view, soft at its rim, and the picture going darker toward it.
		lit *= mix(1.0, smoothstep(0.62, 0.52, r) * (1.0 - 0.4 * smoothstep(0.28, 0.55, r)), scope_reticle);
		// A dark halo under the red marks, so they show on a bright picture as well as a dark one.
		lit = mix(lit, vec3(0.0), reticle(p, 0.0050) * 0.75 * scope_reticle);
		lit = mix(lit, vec3(1.0, 0.18, 0.12), reticle(p, 0.0020) * scope_reticle);
	}
	ALBEDO = lit;
}
