// Clear molded plastic for small parts (the cassette windows).
// Premultiplied alpha lets the plastic's own color fade with ALPHA while reflections keep full strength;
// plain alpha blending dims them with the opacity. Godot adds the lit color as-is in this mode, so ALBEDO is
// premultiplied here.
shader_type spatial;
render_mode blend_premul_alpha, depth_draw_never, cull_back;

// rgb: the plastic's tint; a: its opacity (multiplies the pattern's alpha when there is one).
uniform vec4 tint : source_color = vec4(0.06, 0.06, 0.065, 0.16);
// Frosted and polished areas: rgb the frost's color, a how much it hides.
uniform sampler2D pattern : source_color, filter_linear_mipmap, repeat_disable;
uniform bool use_pattern = false;
uniform float roughness : hint_range(0.0, 1.0) = 0.06;

void fragment() {
	vec4 c = tint;
	if (use_pattern) {
		vec4 p = texture(pattern, UV);
		c = vec4(p.rgb * tint.rgb, p.a * tint.a);
	}
	ALBEDO = c.rgb * c.a;
	ALPHA = c.a;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
}
