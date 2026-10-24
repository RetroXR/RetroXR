// The strip of thermal paper out of a Game Boy Printer's slot.
//
// The print is the printer core's video frame: 160 dots a line, one row per
// line, oldest at the top, newest at the head. The paper is wider than the head
// (38 mm against about 27), so the dots sit in the middle and the rest is bare
// paper. The back is the sticker's backing sheet: blank.
//
// A dot is the paper as far toward the ink as it is dark, worked in sRGB as
// GbPrinterPaper.sheet bakes a torn print, so a print looks the same off the
// strip as on it. Hence no source_color on the colors or the print: they are
// read as written and only the result is made linear.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// White when unset: a strip with nothing printed on it yet is bare paper.
uniform sampler2D print_tex : filter_nearest, hint_default_white;
// How much of the paper's width the 160 dots cover.
uniform float dots_frac = 0.716;
// The roll's paper and ink (GbPrinterPaper.ROLLS); bare thermal paper is not
// quite white.
uniform vec3 paper_color = vec3(0.96, 0.955, 0.93);
uniform vec3 ink_color = vec3(0.0);
// The rows of print_tex this strip shows, [first, last) as UV, so a strip that
// has not caught up with the texture yet never stretches it.
uniform float row_from = 0.0;
uniform float row_to = 1.0;

vec3 srgb_to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	vec3 col = paper_color;
	if (FRONT_FACING) {
		float x = (UV.x - 0.5) / dots_frac + 0.5;
		if (x >= 0.0 && x <= 1.0) {
			float v = mix(row_from, row_to, UV.y);
			float ink = texture(print_tex, vec2(x, v)).r;
			col = mix(ink_color, paper_color, ink);
		}
	} else {
		col *= 0.93;
	}
	ALBEDO = srgb_to_linear(col);
	ROUGHNESS = 0.85;
}
