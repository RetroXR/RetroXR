// The street's backdrop and foreground layers (street_backdrop.gdshader, street_layer.gdshader). See
// street_projection.gdshaderinc.
//
// The foreground is cut out by its alpha, its coverage, so a shrub's edge stays the render's edge whatever the
// proxy under it does. The backdrop is NOT cut out: where its alpha says sky, it draws the sky dome's own color
// along the eye's ray, which is what the dome behind would have shown through the hole. That keeps it a solid
// layer, so the headset's GPU can reject what it hides (the dome, most of all) before shading it; a cut-out
// layer turns that off. Measured on a Quest 3 at the window, 2026-11-07, that saved only 0.15-0.3 ms: most of
// the street's cost was its proxies' triangles (rooms/bedroom params.py's grids; 3.7 ms of 13.2 before, 1.4 after).
//
// The trees sway: where the render's leaf mask says foliage, the lookup drifts with a slow gust and a quick
// flutter, a fraction of a degree, so the canopies breathe and their edges move against the sky. Trunks,
// houses and lawn are not in the mask and stand still. One small extra texture read a pixel.

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

#ifdef BACKDROP
// the dome's two bound keys, the same pair as key_a and key_b
uniform sampler2D sky_a : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D sky_b : source_color, filter_linear_mipmap, repeat_disable;
#endif

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
	// most of the day the two bound keys are the same one and nothing blends: read it once
	vec4 c = texture(key_a, t);
	if (blend > 0.0) {
		c = mix(c, texture(key_b, t), blend);
	}
	vec3 l = decode(c.rgb);
#ifdef BACKDROP
	if (c.a < 0.5) {
		// the dome is far enough to be at infinity: its color is the eye's ray, in this mesh's frame
		vec3 ray = transpose(mat3(MODEL_MATRIX)) * (mat3(INV_VIEW_MATRIX) * VERTEX);
		vec2 su = pano_uv_dir(normalize(ray));
		vec3 sc = texture(sky_a, su).rgb;
		if (blend > 0.0) {
			sc = mix(sc, texture(sky_b, su).rgb, blend);
		}
		l = decode(sc);
	}
#endif
	vec2 tu = (uv - tv_rect.xy) / max(tv_rect.zw, vec2(1e-6));
	l += texture(tv_mask, tu).r * tv_light;
	ALBEDO = l * exposure;
#ifndef BACKDROP
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
#endif
}
