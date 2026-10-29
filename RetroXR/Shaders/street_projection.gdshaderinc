// The bedroom's street: Cycles renders of it, projected back onto proxies of its own shape.
//
// Every key of the day (time_of_day.gd's six) was rendered once as an equirectangular panorama from proj_p, the
// window opening's center (rooms/bedroom in RetroXR-models). A fragment looks up the direction from proj_p to
// itself, so the picture is exact along every ray through the opening, and the proxy's shape carries the parallax
// as the head moves. Two keys are bound at a time and mixed by `blend`.
//
// The textures hold srgb(L / (L + 1)); L = y / (1 - y) gets the render's own light back, which then goes through
// the room's tonemapper and glow like anything else in it. Unshaded: the light is already in the picture.

render_mode unshaded, cull_disabled, fog_disabled, shadows_disabled;

uniform sampler2D key_a : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D key_b : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float blend : hint_range(0.0, 1.0) = 0.0;
uniform float exposure = 1.0;
uniform vec3 proj_p = vec3(-0.9, 1.45, -2.2);
// azimuth (0 = -Z, positive toward +X) and elevation ranges of the panorama, radians: az0, az1, el0, el1
uniform vec4 ranges = vec4(-1.5359, 1.5359, -1.3963, 1.0821);
// where this texture sits in the panorama (x, y, w, h in panorama UV); the foreground is a crop
uniform vec4 crop = vec4(0.0, 0.0, 1.0, 1.0);

varying vec3 model_pos;

void vertex() {
	model_pos = VERTEX;
}

vec2 pano_uv() {
	vec3 d = normalize(model_pos - proj_p);
	float az = atan(d.x, -d.z);
	float el = asin(clamp(d.y, -1.0, 1.0));
	return vec2((az - ranges.x) / (ranges.y - ranges.x), (ranges.w - el) / (ranges.w - ranges.z));
}

vec3 decode(vec3 y) {
	y = min(y, vec3(0.995));
	return y / (1.0 - y);
}
