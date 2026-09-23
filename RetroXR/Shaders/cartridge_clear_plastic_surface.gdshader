// Dyed clear plastic, second pass: the surface. Added over the filter pass
// (cartridge_clear_plastic.gdshader), it is the shell's gloss at full strength,
// with the model's normal map, and a little light scattered in the dye. Adding
// commutes like the filter's multiply, so draw order never matters.
shader_type spatial;
render_mode blend_add, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

// Colour of the light the dye scatters back; its strength is `haze`.
uniform vec4 albedo : source_color = vec4(0.76, 0.05, 0.1, 1.0);
uniform float haze : hint_range(0.0, 1.0) = 0.3;
uniform float roughness : hint_range(0.0, 1.0) = 0.3;
uniform float specular : hint_range(0.0, 1.0) = 0.5;
uniform bool normal_enabled = false;
uniform sampler2D texture_normal : hint_roughness_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float normal_scale : hint_range(-16.0, 16.0) = 1.0;
uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset = vec3(0.0);

void fragment() {
	ALBEDO = albedo.rgb * haze;
	ROUGHNESS = roughness;
	SPECULAR = specular;
	METALLIC = 0.0;
	if (normal_enabled) {
		NORMAL_MAP = texture(texture_normal, UV * uv1_scale.xy + uv1_offset.xy).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
}
