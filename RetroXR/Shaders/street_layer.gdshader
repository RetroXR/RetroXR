// The street's backdrop and foreground layers: cut out by their alpha (the backdrop's is "not sky", the
// foreground's its coverage), so a tree's edge stays the render's edge whatever the proxy under it does.
// See street_projection.gdshaderinc.
shader_type spatial;

#include "res://Shaders/street_projection.gdshaderinc"

// The TV in the brick ranch across the street: its window's mask, and the flicker bedroom_exterior.gd drives.
uniform sampler2D tv_mask : hint_default_black, filter_linear, repeat_disable;
uniform vec4 tv_rect = vec4(0.0);
uniform vec3 tv_light = vec3(0.0);

void fragment() {
	vec2 uv = pano_uv();
	vec2 t = (uv - crop.xy) / crop.zw;
	vec4 c = mix(texture(key_a, t), texture(key_b, t), blend);
	vec3 l = decode(c.rgb);
	vec2 tu = (uv - tv_rect.xy) / max(tv_rect.zw, vec2(1e-6));
	l += texture(tv_mask, tu).r * tv_light;
	ALBEDO = l * exposure;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
