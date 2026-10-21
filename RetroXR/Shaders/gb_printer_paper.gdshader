// The strip of thermal paper out of a Game Boy Printer's slot.
//
// The print is the printer core's video frame: 160 dots a line, one row per
// line, oldest at the top, newest at the head. The paper is wider than the head
// (38 mm against about 27), so the dots sit in the middle and the rest is bare
// paper. The back is the sticker's backing sheet: blank.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// White when unset: a strip with nothing printed on it yet is bare paper.
uniform sampler2D print_tex : source_color, filter_nearest, hint_default_white;
// How much of the paper's width the 160 dots cover.
uniform float dots_frac = 0.716;
// Bare thermal paper is not quite white.
uniform vec3 paper_color : source_color = vec3(0.96, 0.955, 0.93);
// The rows of print_tex this strip shows, [first, last) as UV, so a strip that
// has not caught up with the texture yet never stretches it.
uniform float row_from = 0.0;
uniform float row_to = 1.0;

void fragment() {
	vec3 col = paper_color;
	if (FRONT_FACING) {
		float x = (UV.x - 0.5) / dots_frac + 0.5;
		if (x >= 0.0 && x <= 1.0) {
			float v = mix(row_from, row_to, UV.y);
			float ink = texture(print_tex, vec2(x, v)).r;
			col *= ink;
		}
	} else {
		col *= 0.93;
	}
	ALBEDO = col;
	ROUGHNESS = 0.85;
}
