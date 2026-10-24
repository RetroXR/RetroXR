// A ring that fills clockwise from the top as `progress` goes 0 -> 1: the visual for
// HoldToGrab in VR (the desktop draws the same thing around its crosshair).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 fill_color : source_color = vec4(0.55, 0.85, 1.0, 0.95);
uniform vec4 track_color : source_color = vec4(1.0, 1.0, 1.0, 0.22);
uniform float inner = 0.38;
uniform float outer = 0.5;

void fragment() {
	vec2 p = UV - vec2(0.5);
	float r = length(p);
	if (r < inner || r > outer) {
		discard;
	}
	// 0 at the top, increasing clockwise.
	float a = atan(p.x, -p.y);
	if (a < 0.0) {
		a += 6.28318530718;
	}
	float t = a / 6.28318530718;
	vec4 c = t <= progress ? fill_color : track_color;
	ALBEDO = c.rgb;
	ALPHA = c.a;
}
