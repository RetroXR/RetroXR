// The street's backdrop and foreground layers: cut out by their alpha (the backdrop's is "not sky", the
// foreground's its coverage), so a tree's edge stays the render's edge whatever the proxy under it does.
// See street_projection.gdshaderinc.
//
// The trees sway: where the render's leaf mask says foliage, the lookup drifts with a slow gust and a quick
// flutter, a fraction of a degree, so the canopies breathe and their edges move against the sky. Trunks,
// houses and lawn are not in the mask and stand still. One small extra texture read a pixel.
shader_type spatial;

#include "res://Shaders/street_projection.gdshaderinc"

// The TV in the brick ranch across the street: its window's mask, and the flicker bedroom_exterior.gd drives.
uniform sampler2D tv_mask : hint_default_black, filter_linear, repeat_disable;
uniform vec4 tv_rect = vec4(0.0);
uniform vec3 tv_light = vec3(0.0);

// How much each pixel of this layer sways (0 still, 1 a tree's leaves), in the same crop as its textures.
uniform sampler2D leaf_mask : hint_default_black, filter_linear, repeat_disable;
// Peak sway, radians: 0.0015 is about 3 cm at 20 m, a summer breeze.
uniform float sway = 0.0015;
uniform float wind_speed = 1.0;

void fragment() {
	vec2 uv = pano_uv();
	vec2 t = (uv - crop.xy) / crop.zw;
	float leaf = texture(leaf_mask, t).r;
	if (leaf > 0.01) {
		float s = TIME * wind_speed;
		// a gust rolling across the street, and each tree's leaves fluttering on their own
		float gust = sin(s * 0.7 + uv.x * 6.0) * 0.6 + sin(s * 1.9 + uv.x * 17.0 + uv.y * 11.0) * 0.3;
		float flutter = sin(s * 7.3 + uv.x * 230.0 + uv.y * 170.0) * 0.22;
		vec2 per_rad = vec2(1.0 / (ranges.y - ranges.x), 1.0 / (ranges.w - ranges.z)) / crop.zw;
		t += leaf * sway * per_rad * vec2(gust + flutter, 0.35 * flutter - 0.15 * abs(gust));
	}
	vec4 c = mix(texture(key_a, t), texture(key_b, t), blend);
	vec3 l = decode(c.rgb);
	vec2 tu = (uv - tv_rect.xy) / max(tv_rect.zw, vec2(1e-6));
	l += texture(tv_mask, tu).r * tv_light;
	ALBEDO = l * exposure;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
}
