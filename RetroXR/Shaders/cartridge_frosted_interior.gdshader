// What sits inside a clear cartridge (board, contacts, chips, battery), as it is
// seen through moulded plastic: out of focus and lower in contrast, because the
// plastic scatters a little of the light on its way out. Only ever seen through
// the shell, so blurring the parts themselves is the whole effect, and costs a
// texture bias, not a copy of the screen.
//
// CartridgeColor swaps a part onto this while its shell is clear and frosted,
// carrying the StandardMaterial3D's colour, texture, roughness and metallic across.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D texture_albedo : source_color, filter_linear_mipmap, repeat_disable;
uniform bool use_texture = false;
uniform float roughness : hint_range(0.0, 1.0) = 0.7;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
// Mip levels the image is pushed down: 1 halves its sharpness, 4 is a soft blur.
uniform float blur : hint_range(0.0, 8.0) = 0.0;
// Share of the way to the image's own average colour: scattered light lifts the
// shadows and flattens the detail.
uniform float flatten : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec3 c = albedo.rgb;
	if (use_texture) {
		vec3 seen = texture(texture_albedo, UV, blur).rgb;
		vec3 mean = textureLod(texture_albedo, UV, 12.0).rgb;
		c *= mix(seen, mean, flatten);
	}
	ALBEDO = c;
	ROUGHNESS = mix(roughness, 1.0, flatten);
	METALLIC = metallic * (1.0 - flatten);
}
