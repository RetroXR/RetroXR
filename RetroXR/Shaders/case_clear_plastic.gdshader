// Clear molded plastic: the jewel case's lid and base, the keep case's sleeve.
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
// A molded part (a clear disc tray): where its surface turns away from the eye the plastic is seen edge-on and
// reads as a line: a wall of a hub, a ring, a rim. `rim` is the opacity there and `rim_color` its color; 0 (a flat
// lid or sleeve) draws as it always did.
uniform float rim : hint_range(0.0, 1.0) = 0.0;
uniform vec3 rim_color : source_color = vec3(0.5, 0.54, 0.6);
uniform float rim_power : hint_range(0.5, 8.0) = 2.0;

void fragment() {
	vec4 c = tint;
	if (use_pattern) {
		vec4 p = texture(pattern, UV);
		c = vec4(p.rgb * tint.rgb, p.a * tint.a);
	}
	if (rim > 0.0) {
		float edge = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), rim_power);
		c = vec4(mix(c.rgb, rim_color, edge), mix(c.a, max(c.a, rim), edge));
	}
	ALBEDO = c.rgb * c.a;
	ALPHA = c.a;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
}
