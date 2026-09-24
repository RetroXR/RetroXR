// Dyed clear plastic, second pass: the surface. Added over the filter pass
// (cartridge_clear_plastic.gdshader), it is the shell's gloss at full strength,
// with the model's normal map, and a little light scattered in the dye. Adding
// commutes like the filter's multiply, so draw order never matters. `cloud`
// makes that scatter uneven, in soft patches fixed to the shell, as moulded
// plastic is: the frosted look, with cartridge_frosted_interior.gdshader
// blurring what is inside.
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
// How uneven the scatter is: 0 even, 1 patches from none to twice the haze.
uniform float cloud : hint_range(0.0, 1.0) = 0.0;
// Patch size, in millimetres of the mesh's own space.
uniform float cloud_size_mm : hint_range(0.5, 20.0) = 1.8;
// The moulded finish: a fine stipple of rougher and smoother spots, as the
// spark-eroded mould leaves on a real shell, by up to this much either way.
// It fades to `roughness` once a grain is smaller than a pixel.
uniform float roughness_grain : hint_range(0.0, 0.5) = 0.0;
uniform float grain_size_mm : hint_range(0.05, 2.0) = 0.3;

varying vec3 obj_pos;

#include "res://Shaders/cartridge_clear_cloud.gdshaderinc"

void vertex() {
	obj_pos = VERTEX;
}

void fragment() {
	float n = cloud_noise(obj_pos, cloud_size_mm);
	ALBEDO = albedo.rgb * haze * (1.0 + cloud * (n - 0.5) * 2.0);
	float grain = cloud_value(obj_pos / (grain_size_mm * 0.001)) - 0.5;
	float grains_per_px = length(fwidth(obj_pos)) / (grain_size_mm * 0.001);
	grain *= 1.0 - smoothstep(0.5, 1.5, grains_per_px);
	// Milkier patches are a little more matte too.
	ROUGHNESS = clamp(roughness + roughness_grain * grain * 2.0 + cloud * 0.25 * (n - 0.5), 0.05, 1.0);
	SPECULAR = specular;
	METALLIC = 0.0;
	if (normal_enabled) {
		NORMAL_MAP = texture(texture_normal, UV * uv1_scale.xy + uv1_offset.xy).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
}
